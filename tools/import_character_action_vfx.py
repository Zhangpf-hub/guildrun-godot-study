"""Stage and install authored particle layers for ordinary Guildrun character actions."""

import argparse
from collections import Counter
from contextlib import ExitStack
from copy import deepcopy
import json
import math
from pathlib import Path
import re
from shutil import copyfile

from character_source_inventory import source_metadata
from import_balancing import BuildLayouts
from import_battle_revival import export_prefab
from import_scenes import Source


EVENT_FIELDS = {"BasicAttack": "_basicAttackVfxReferences", "SkillAttack": "_skillVfxReferences",
                "Die": "_deathVfxReferences"}
DEDICATED = {"60914", "60916", "60919"}
PILOT_VISUAL = "60916"
GAME = Path(__file__).resolve().parents[1] / "game"
SEPARATE_BINDINGS = {"60923"}
GROUP = "character_actions"
UNSUPPORTED_MODULES = {"CollisionModule", "ExternalForcesModule", "ForceModule", "LightsModule", "SubModule",
                       "TriggerModule"}
IDENTITY = ((0.0, 0.0, 0.0), (0.0, 0.0, 0.0, 1.0), (1.0, 1.0, 1.0))


def unity_id(key):
    file, path_id = key.rsplit(":", 1)
    return file, int(path_id)


def pose(node):
    local = node["local"]
    return (tuple(local["m_LocalPosition"][axis] for axis in "xyz"),
            tuple(local["m_LocalRotation"][axis] for axis in "xyzw"),
            tuple(local["m_LocalScale"][axis] for axis in "xyz"))


def cross(a, b):
    ax, ay, az = a
    bx, by, bz = b
    return (ay * bz - az * by, az * bx - ax * bz, ax * by - ay * bx)


def rotate(q, vector):
    u = cross(q[:3], vector)
    v = cross(q[:3], u)
    return tuple(coord + 2 * (q[3] * first + second) for coord, first, second in zip(vector, u, v))


def compose(parent, child):
    position, q, scale = parent
    offset, rotation, size = child
    if not all(math.isclose(scale[0], length, rel_tol=1e-6) for length in scale):
        if any(abs(axis) > 1e-6 for axis in rotation[:3]):
            raise ValueError("Nonuniform parent scale combined with child rotation")
    translated = rotate(q, tuple(a * b for a, b in zip(scale, offset)))
    wedge = cross(q[:3], rotation[:3])
    orientation = tuple(q[3] * b + rotation[3] * a + c for a, b, c in zip(q[:3], rotation[:3], wedge))
    orientation += (q[3] * rotation[3] - sum(a * b for a, b in zip(q[:3], rotation[:3])),)
    return (tuple(a + b for a, b in zip(position, translated)), orientation,
            tuple(a * b for a, b in zip(scale, size)))


def placement(effect, nodes):
    ancestry = effect["ancestry"]
    if ancestry[0]["game_object"] not in nodes:
        raise ValueError("FX root is outside character prefab")
    # Character position and orientation are supplied by the unit placement.
    transform = (*IDENTITY[:2], pose(nodes[ancestry[0]["game_object"]])[2])
    for anchor in ancestry[1:-1]:
        if anchor["name"] not in ("VFXParent", "VFXParents"):
            raise ValueError(f"Animated attachment requires validation: {anchor['name']}")
        transform = compose(transform, pose(nodes[anchor["game_object"]]))
    position, rotation, scale = compose(transform, pose(nodes[effect["root"]]))
    return {"position": [*position[:2], -position[2]],
            "rotation": [-rotation[0], -rotation[1], rotation[2], rotation[3]], "scale": list(scale)}


def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def gathers_emission(particle):
    emission = particle["emission"]
    return emission["enabled"] and (
        emission["m_BurstCount"] or emission["rateOverTime"]["scalar"] > 0 or
        emission["rateOverDistance"]["scalar"] > 0)


class Batch:
    def __init__(self, src, layouts, inventory, stage):
        self.src = src
        self.layouts = layouts
        self.inventory = inventory
        self.stage = stage
        self.summary = {}
        self.outputs = set()
        self.converted = {}

    def run(self, only_visual=None):
        for source, character in self.inventory["characters"].items():
            _, visual = unity_id(source)
            key = str(visual)
            if only_visual is not None and key != only_visual:
                continue
            record = {"name": character["name"], "base_prefab": character["prefab"],
                      "rank_prefabs": character["prefabs_per_rank"], "events": {}}
            self.summary[key] = record
            if key in DEDICATED:
                record["status"] = "dedicated_playback"
                if key == PILOT_VISUAL:
                    file = Path("Characters/action_vfx") / f"{key}.json"
                    manifest = json.loads((GAME / file).read_text(encoding="utf-8"))
                    manifest.pop("ranks", None)
                    record["ranks"] = {}
                    self.ranked_variants(key, character, manifest, record["ranks"])
                    dest = self.stage / file
                    write_json(dest, manifest)
                    self.outputs.add(dest)
                continue
            manifest = self.variant(key, character["prefab"], record["events"])
            record["status"] = "base_action_layers_staged" if self.has_bindings(manifest) else "no_base_action_layers_staged"
            record["ranks"] = {}
            if key not in SEPARATE_BINDINGS:
                self.ranked_variants(key, character, manifest, record["ranks"])
            if manifest:
                dest = self.stage / "Characters" / "action_vfx" / f"{key}.json"
                write_json(dest, manifest)
                if key not in SEPARATE_BINDINGS:
                    self.outputs.add(dest)

    def ranked_variants(self, visual, character, manifest, reports):
        for rank, source in enumerate(character["prefabs_per_rank"], 1):
            key = str(rank)
            if source is None or source == character["prefab"]:
                reports[key] = {"prefab": source, "status": "shared_base_prefab"}
                continue
            report = {"prefab": source, "events": {}}
            reports[key] = report
            variant = self.variant(visual, source, report["events"], ranked=True)
            report["fallback_to_base"] = [event for event in EVENT_FIELDS if event not in variant and
                                           event not in variant.get("scaling", {})]
            if self.has_bindings(variant):
                report["status"] = "rank_action_layers_staged"
                manifest.setdefault("ranks", {})[key] = variant
            else:
                report["status"] = "no_rank_action_layers_staged"

    @staticmethod
    def has_bindings(manifest):
        return (any(manifest.get(event) for event in EVENT_FIELDS) or
                any(group["default"] or any(tier["effects"] for tier in group["tiers"])
                    for groups in manifest.get("scaling", {}).values() for group in groups))

    def variant(self, visual, prefab, events, ranked=False):
        nodes = {node["source"]: node for node in self.inventory["prefabs"][prefab]["nodes"]}
        handlers = [component for node in nodes.values() for component in node["components"]
                    if component.get("class", "").endswith("VfxHandlerComponent")]
        manifest = {}
        for event, field in EVENT_FIELDS.items():
            effects = []
            events[event] = effects
            for handler in handlers:
                if handler["class"] == "ScalingVfxHandlerComponent":
                    groups = handler.get("serialized_fields", {}).get(field, [])
                    for index, group in enumerate(groups):
                        row = self.scaling_group(visual, group, nodes, handler, field, index, effects)
                        has_layers = row["default"] or any(tier["effects"] for tier in row["tiers"])
                        if has_layers or not ranked:
                            manifest.setdefault("scaling", {}).setdefault(event, []).append(row)
                    continue
                for ref in handler.get("references", []):
                    if ref["field"].split("[", 1)[0] != field:
                        continue
                    effect = self.inventory["effects"][ref["target"]]
                    report = {"source": ref["target"], "field": ref["field"], "handler": handler["source"],
                              "type": effect["type"]}
                    effects.append(report)
                    binding = self.convert(visual, effect, nodes, report)
                    if binding:
                        manifest.setdefault(event, []).append(binding)
        return manifest

    def scaling_group(self, visual, group, nodes, handler, field, index, effects):
        source_file, _ = unity_id(handler["source"])
        references = {ref["field"]: ref["target"] for ref in handler["references"]}
        prefix = f"{field}[{index}]"

        def branch(path, pointers):
            bindings = []
            for ordinal, pointer in enumerate(pointers):
                target_path = f"{prefix}{path}[{ordinal}]"
                if not pointer["m_PathID"]:
                    effects.append({"field": target_path, "handler": handler["source"], "status": "null_pointer"})
                    continue
                target = references.get(target_path, f"{source_file}:{pointer['m_PathID']}")
                effect = self.inventory["effects"][target]
                report = {"source": target, "field": target_path, "handler": handler["source"], "type": effect["type"]}
                effects.append(report)
                binding = self.convert(visual, effect, nodes, report)
                if binding:
                    bindings.append(binding)
            return bindings

        key = ""
        tiers = []
        for ordinal, level in enumerate(group["_levels"]):
            expression = level["<DataTrackingExpression>k__BackingField"]
            if key and key != expression:
                raise ValueError(f"Scaling group contains mixed expressions: {visual}, {prefix}")
            key = expression
            tiers.append({"comparison": level["<ComparisonType>k__BackingField"],
                          "value": level["<Threshold>k__BackingField"]["RawValue"],
                          "effects": branch(f"._levels[{ordinal}].<Value>k__BackingField",
                                            level["<Value>k__BackingField"])})
        return {"key": key, "tiers": tiers, "default": branch("._defaultValue", group["_defaultValue"])}

    def convert(self, visual, effect, nodes, report):
        key = visual, report["source"]
        binding, prior = self.converted.get(key, (None, None))
        if prior is None:
            details = {"source": report["source"]}
            binding = self.component(visual, effect, nodes, details)
            self.converted[key] = binding, details
            prior = details
        report.update(deepcopy(prior))
        return binding

    def component(self, visual, effect, nodes, report):
        if effect["type"] != "ParticleSystemVfxComponent":
            report["status"] = "deferred_component"
            return None
        fields = effect["fields"]
        report["timing"] = {key: fields.get(key) for key in
                            ("_delay", "_duration", "_disableOnRelease", "_isLooping", "_randomizeDelay")}
        if not effect["enabled"] or fields["_randomizeDelay"] or fields["_isLooping"]:
            report.update(status="deferred_component", reason="Disabled component, randomized delay or persistent loop")
            return None
        try:
            binding = placement(effect, nodes)
        except ValueError as error:
            report.update(status="deferred_attachment", reason=str(error))
            return None
        transforms, layers = self.layers(effect)
        report["layers"] = layers
        if not transforms:
            report["status"] = "no_layers_staged"
            return None
        errors = {}
        file, path_id = unity_id(report["source"])
        owner = self.src.file(file)
        name = f"{visual}_{path_id}"
        scene = export_prefab(self.src, owner, owner.objects[path_id], self.layouts, self.stage, name,
                              particles=set(transforms), flat_emitters=transforms, layer_errors=errors,
                              finish_particles=not bool(fields["_disableOnRelease"]), output_group=GROUP)
        for layer in layers:
            _, pid = unity_id(layer["source"])
            if pid in errors:
                layer.update(status="excluded", reason=errors[pid])
        count = sum(layer["status"] == "converted" for layer in layers)
        report["converted_layers"] = count
        if not count:
            scene.unlink()
            report["status"] = "no_layers_staged"
            return None
        report["status"] = "converted_layers" if count == len(layers) else "partial_layers"
        report["scene"] = f"res://battle/{GROUP}/{name}.tscn"
        self.outputs.add(scene)
        return {"scene": report["scene"], **binding}

    def layers(self, effect):
        inventory = self.inventory
        lineage = {}
        chosen = {}
        layers = []
        for node in inventory["prefabs"][effect["root"]]["nodes"]:
            is_root = node["parent"] is None
            parent_pose, parent_active = lineage.get(node["parent"], (IDENTITY, True))
            try:
                relative = IDENTITY if is_root else compose(parent_pose, pose(node))
            except (TypeError, ValueError):
                relative = None
            active = parent_active and (node["active_self"] or is_root)
            lineage[node["source"]] = relative, active
            if not active:
                continue
            types = {component["type"]: component for component in node["components"]}
            for kind in ("TrailRenderer", "MeshRenderer", "SkinnedMeshRenderer", "SpriteRenderer", "VisualEffect"):
                if kind in types and types[kind].get("m_Enabled", True):
                    renderer = types[kind]
                    layers.append(self.layer(node, renderer, renderer, "Requires a non-particle effect renderer"))
            particle = types.get("ParticleSystem")
            renderer = types.get("ParticleSystemRenderer")
            if not particle or not renderer or not renderer["m_Enabled"] or not gathers_emission(particle):
                continue
            reason = ""
            if relative is None:
                reason = "Unsupported transform shear"
            elif renderer["m_RenderMode"] not in (0, 1, 2, 3, 4, 5):
                reason = f"Unsupported Unity render mode {renderer['m_RenderMode']}"
            elif UNSUPPORTED_MODULES.intersection(particle["enabled_modules"]):
                reason = ", ".join(sorted(UNSUPPORTED_MODULES.intersection(particle["enabled_modules"])))
            elif renderer["m_RenderMode"] != 5 and "TrailModule" in particle["enabled_modules"]:
                reason = "Source contains both a particle body and trail pass"
            layer = self.layer(node, particle, renderer, reason)
            layers.append(layer)
            if not reason:
                chosen[unity_id(particle["source"])[1]] = tuple(dict(zip(axes, value)) for axes, value in
                                                                  zip(("xyz", "xyzw", "xyz"), relative))
        return chosen, layers

    def layer(self, node, component, renderer, reason):
        materials = self.inventory["materials"]
        shaders = self.inventory["shaders"]
        links = []
        for field, source in renderer.get("dependencies", {}).items():
            if source not in materials:
                continue
            material = materials[source]
            shader = material["shader"]
            links.append({"field": field, "material": source, "material_name": material["name"],
                          "shader": shader, "shader_name": shaders.get(shader, {}).get("name", ""),
                          "keywords": material.get("m_ValidKeywords", [])})
        data = {"source": component["source"], "renderer": renderer["source"], "node": node["name"],
                "materials": links, "status": "excluded" if reason else "converted"}
        if reason:
            data["reason"] = reason
        return data

    def install(self, game):
        scenes = [path for path in self.outputs if path.suffix == ".tscn"]
        for path in scenes:
            for dependency in re.findall(r'path="res://([^"]+)"', path.read_text(encoding="utf-8")):
                staged = self.stage / dependency
                installed = game / dependency
                if staged.is_file() and not installed.is_file():
                    installed.parent.mkdir(parents=True, exist_ok=True)
                    copyfile(staged, installed)
                if not installed.is_file():
                    raise FileNotFoundError(installed)
        for staged in sorted(self.outputs, key=lambda path: (path.suffix != ".tscn", path)):
            target = game / staged.relative_to(self.stage)
            target.parent.mkdir(parents=True, exist_ok=True)
            copyfile(staged, target)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("data", type=Path)
    parser.add_argument("inventory", type=Path)
    parser.add_argument("work", type=Path)
    parser.add_argument("--install", action="store_true")
    parser.add_argument("--visual", help="Stage or install only this visual config")
    args = parser.parse_args()
    stage = args.work / "stage"
    for subdir in ("battle", "textures", "meshes"):
        (stage / subdir).mkdir(parents=True, exist_ok=True)
    inventory = json.loads(args.inventory.read_text(encoding="utf-8"))
    version = inventory["source"]["unity_version"]
    current_source = source_metadata(args.data, version)
    if current_source["global_metadata_sha256"] != inventory["source"]["global_metadata_sha256"]:
        parser.error("The inventory was built from different IL2CPP metadata. Regenerate the source inventory.")
    with ExitStack() as stack:
        src = Source(args.data, stack)
        src.file("globalgamemanagers.assets")
        layouts = BuildLayouts(version)
        layouts.load_local_game(str(args.data.parent))
        src.env.typetree_generator = layouts
        batch = Batch(src, layouts, inventory, stage)
        batch.run(args.visual)
        write_json(args.work / "coverage.json", {"source": inventory["source"], "characters": batch.summary})
        print(Counter(row["status"] for entry in batch.summary.values() for rows in entry["events"].values()
                      for row in rows))
        print(Counter(rank["status"] for entry in batch.summary.values() for rank in entry.get("ranks", {}).values()))
        if args.install:
            batch.install(GAME)


if __name__ == "__main__":
    main()
