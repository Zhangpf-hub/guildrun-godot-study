"""Read character configurations, model/FX prefab graphs and materials from Guildrun Demo."""

import argparse
from collections import Counter
from contextlib import ExitStack
from functools import wraps
from hashlib import sha256
import json
from pathlib import Path
import re

from import_balancing import BuildLayouts, preserve_ids, read_fields, serialize
from import_scenes import Source


def object_id(reader):
    return f"{reader.assets_file.name}:{reader.path_id}"


def pointers(value, field=""):
    if isinstance(value, dict):
        if "m_FileID" in value and "m_PathID" in value:
            if value["m_PathID"]:
                yield field, value
            return
        for name, entry in value.items():
            yield from pointers(entry, f"{field}.{name}" if field else name)
    elif isinstance(value, (list, tuple)):
        for index, entry in enumerate(value):
            yield from pointers(entry, f"{field}[{index}]")


def read_selected(payload, names):
    return {name: payload[name] for name in names if name in payload}


def normalize_fields(fields):
    return {re.sub(r"^<(.+)>k__BackingField$", r"\1", key): value
            for key, value in fields.items()}


def authored_fields(data):
    return {key: value for key, value in data.items()
            if key not in {"m_GameObject", "m_Enabled", "m_Name", "m_Script"}}


def cache_reader(method):
    @wraps(method)
    def cached(self, reader):
        cache = self.cache.setdefault(method.__name__, {})
        key = object_id(reader)
        if key not in cache:
            cache[key] = method(self, reader)
        return cache[key]

    return cached


class Inventory:
    def __init__(self, src, layouts):
        self.src = src
        self.layouts = layouts
        self.cache = {}
        self.errors = []
        self.prefabs = {}
        self.effects = {}
        self.materials = {}
        self.shaders = {}
        self.resources = {}
        self.controllers = {}

    def resolve(self, reader, pointer, context):
        if not pointer or not pointer["m_PathID"]:
            return None
        try:
            return self.src.resolve(reader.assets_file, pointer)[1]
        except (KeyError, OSError, IndexError) as error:
            self.errors.append({"source": object_id(reader), "field": context, "pointer": pointer,
                                "error": str(error)})
            return None

    @cache_reader
    def fields(self, reader):
        if reader.type.name == "MonoBehaviour":
            return read_fields(reader, self.layouts)
        return reader.read_typetree()

    @cache_reader
    def script(self, reader):
        p = reader.parse_monobehaviour_head().m_Script
        script = self.resolve(reader, {"m_FileID": p.m_FileID, "m_PathID": p.m_PathID}, "m_Script")
        return self.fields(script) if script else {}

    @cache_reader
    def components(self, go):
        return tuple(target for p in self.fields(go)["m_Component"]
                     if (target := self.resolve(go, p["component"], "m_Component")))

    def resource(self, reader):
        key = object_id(reader)
        catalog = {"Material": self.materials, "Shader": self.shaders,
                   "AnimatorController": self.controllers,
                   "AnimatorOverrideController": self.controllers}.get(reader.type.name, self.resources)
        if key in catalog:
            return key
        name = reader.peek_name()
        record = {"type": reader.type.name, "name": name}
        catalog[key] = record
        if reader.type.name == "Material":
            data = self.fields(reader)
            shader = self.resolve(reader, data["m_Shader"], "m_Shader")
            record["shader"] = self.resource(shader) if shader else None
            record.update(read_selected(data, ("m_CustomRenderQueue", "m_ValidKeywords", "m_InvalidKeywords",
                                               "stringTagMap", "disabledShaderPasses", "m_DoubleSidedGI")))
            props = data["m_SavedProperties"]
            record.update(read_selected(props, ("m_Floats", "m_Colors", "m_Ints")))
            record["textures"] = {}
            for prop, value in props["m_TexEnvs"]:
                texture = self.resolve(reader, value["m_Texture"], prop)
                record["textures"][prop] = {
                    "asset": self.resource(texture) if texture else None,
                    "scale": value["m_Scale"], "offset": value["m_Offset"],
                }
        elif reader.type.name == "Shader":
            shader = reader.read().m_ParsedForm
            record["name"] = shader.m_Name
            record["subshaders"] = [{"tags": dict(entry.m_Tags.tags),
                                     "passes": len(entry.m_Passes)}
                                    for entry in shader.m_SubShaders]
        elif reader.type.name in ("AnimatorController", "AnimatorOverrideController"):
            data = self.fields(reader)
            selected = read_selected(data, ("m_AnimationClips", "m_Controller", "m_Clips")) if (
                reader.type.name == "AnimatorOverrideController") else read_selected(data, ("m_AnimationClips",))
            record["dependencies"] = self.dependencies(reader, selected, set())
        elif reader.type.name == "Texture2D":
            record.update(read_selected(self.fields(reader), (
                "m_Width", "m_Height", "m_TextureFormat", "m_MipCount", "m_ColorSpace", "m_TextureSettings",
            )))
        elif reader.type.name == "AnimationClip":
            data = self.fields(reader)
            record["events"] = data.get("m_Events", [])
            settings = data.get("m_AnimationClipSettings") or data.get("m_MuscleClip", {})
            record["settings"] = read_selected(settings, ("m_StartTime", "m_StopTime", "m_LoopTime", "m_SampleRate"))
        return key

    def dependencies(self, reader, data, allowed):
        dependencies = {}
        for field, p in pointers(data):
            target = self.resolve(reader, p, field)
            if target and (not allowed or target.type.name in allowed):
                dependencies[field] = self.resource(target)
        return dependencies

    @cache_reader
    def transform(self, go):
        return next(component for component in self.components(go) if
                    component.type.name in ("Transform", "RectTransform"))

    @cache_reader
    def ancestry(self, go):
        data = self.fields(self.transform(go))
        parent_transform = self.resolve(self.transform(go), data["m_Father"], "m_Father")
        parent = self.resolve(parent_transform, self.fields(parent_transform)["m_GameObject"], "m_GameObject"
                              ) if parent_transform else None
        own = ({"game_object": object_id(go), "name": self.fields(go)["m_Name"]},)
        return self.ancestry(parent) + own if parent else own

    def hierarchy(self, go, up_active=True, parent=None):
        data = self.fields(go)
        transform = self.transform(go)
        local = self.fields(transform)
        active = bool(data["m_IsActive"])
        yield go, {
            "source": object_id(go), "parent": parent, "name": data["m_Name"], "transform": object_id(transform),
            "layer": data["m_Layer"], "active_self": active, "active_in_prefab": up_active and active,
            "local": read_selected(local, ("m_LocalRotation", "m_LocalPosition", "m_LocalScale")),
        }
        for p in local["m_Children"]:
            child_transform = self.resolve(transform, p, "m_Children")
            if child_transform:
                child = self.resolve(child_transform, self.fields(child_transform)["m_GameObject"], "m_GameObject")
                if child:
                    yield from self.hierarchy(child, up_active and active, object_id(go))

    def node_components(self, go, scan_handlers):
        records = []
        for component in self.components(go):
            kind = component.type.name
            if kind in ("Transform", "RectTransform"):
                continue
            record = {"source": object_id(component), "type": kind}
            records.append(record)
            if kind == "MonoBehaviour":
                script = self.script(component)
                record["class"] = script.get("m_ClassName", "")
                record["namespace"] = script.get("m_Namespace", "")
                record["enabled"] = bool(component.parse_monobehaviour_head().m_Enabled)
                class_name = record["class"].lower()
                if scan_handlers and ("vfxhandler" in class_name or "areaofeffectviewcontroller" in class_name
                                      or "projectileviewcontroller" in class_name):
                    self.handler(component, record)
                continue
            if kind == "ParticleSystem":
                data = self.fields(component)
                record.update(read_selected(data, ("lengthInSec", "simulationSpeed", "looping", "prewarm",
                                                   "playOnAwake", "useAutoRandomSeed", "randomSeed",
                                                   "moveWithTransform", "scalingMode", "stopAction")))
                record["enabled_modules"] = [k for k, v in data.items() if
                                             k.endswith("Module") and isinstance(v, dict) and v.get("enabled")]
                emission = data["EmissionModule"]
                record["emission"] = read_selected(emission, ("enabled", "rateOverTime", "rateOverDistance",
                                                              "m_BurstCount", "m_Bursts"))
                record["dependencies"] = self.dependencies(component, data, {
                    "Mesh", "Material", "Sprite", "Texture2D", "ParticleSystem", "SkinnedMeshRenderer",
                })
            elif kind.endswith("Renderer") or kind in ("MeshFilter", "Animator", "Animation", "VisualEffect"):
                data = self.fields(component)
                record.update(read_selected(data, ("m_Enabled", "m_RenderMode", "m_RenderAlignment", "m_Emitting",
                                                   "m_ApplyActiveColorSpace", "m_SortingLayerID", "m_SortingOrder",
                                                   "m_CastShadows", "m_ReceiveShadows", "m_Time", "m_Parameters",
                                                   "m_MinVertexDistance", "m_VertexStreams", "m_UseCustomVertexStreams")))
                record["dependencies"] = self.dependencies(component, data, {
                    "Material", "Mesh", "Sprite", "Avatar", "AnimatorController", "AnimatorOverrideController",
                    "AnimationClip", "VisualEffectAsset",
                })
        return records

    def handler(self, component, record):
        try:
            data = self.fields(component)
        except (ValueError, EOFError, KeyError) as error:
            self.errors.append({"source": object_id(component), "field": record["class"], "error": str(error)})
            return
        record["serialized_fields"] = authored_fields(data)
        record["references"] = []
        for field, p in pointers(record["serialized_fields"]):
            target = self.resolve(component, p, field)
            if not target:
                continue
            entry = {"field": field, "target": object_id(target), "type": target.type.name}
            record["references"].append(entry)
            if target.type.name == "MonoBehaviour":
                entry["class"] = self.script(target).get("m_ClassName", "")
                if entry["class"].startswith("Vfx") or "VfxReference" in field or "vfx" in field.lower():
                    self.effect(target, entry["class"])
            elif target.type.name == "GameObject":
                self.prefab(target, scan_handlers=False)

    def effect(self, component, kind):
        key = object_id(component)
        if key in self.effects:
            return
        record = {"type": kind}
        self.effects[key] = record
        try:
            data = self.fields(component)
        except (ValueError, EOFError, KeyError) as error:
            self.errors.append({"source": key, "field": kind, "error": str(error)})
            return
        go = self.resolve(component, data["m_GameObject"], "m_GameObject")
        if go:
            record["root"] = self.prefab(go, scan_handlers=False)
            record["ancestry"] = self.ancestry(go)
        record["enabled"] = bool(data.get("m_Enabled"))
        record["fields"] = authored_fields(data)

    def prefab(self, go, scan_handlers=True):
        key = object_id(go)
        if key not in self.prefabs:
            self.prefabs[key] = {"name": self.fields(go)["m_Name"], "nodes": []}
            for node, record in self.hierarchy(go):
                record["components"] = self.node_components(node, scan_handlers)
                self.prefabs[key]["nodes"].append(record)
        return key

    def characters(self):
        visual_file = self.src.file("sharedassets1.assets")
        characters = {}
        for visual in visual_file.objects.values():
            if visual.type.name != "MonoBehaviour":
                continue
            name = visual.parse_monobehaviour_head().m_Name
            if not name.endswith("_VisualConfig") or self.script(visual).get("m_ClassName") != "CharacterVisualConfig":
                continue
            data = normalize_fields(self.fields(visual))
            record = {"name": name, "prefab": None, "prefabs_per_rank": [], "projectile_prefab": None,
                      "animation_settings": data["AnimationSettings"], "audio_settings": data["AudioSettings"],
                      "portraits": self.dependencies(visual, {key: value for key, value in data.items()
                                                               if "Portrait" in key}, {"Sprite"})}
            characters[object_id(visual)] = record
            for field, key in (("Prefab", "prefab"), ("ProjectilePrefab", "projectile_prefab")):
                go = self.resolve(visual, data.get(field), field)
                if go:
                    record[key] = self.prefab(go)
            for p in data["PrefabsPerRank"]:
                rank = self.resolve(visual, p, "PrefabsPerRank")
                record["prefabs_per_rank"].append(self.prefab(rank) if rank else None)
        return characters

    def gameplay(self, characters):
        """Index gameplay identifiers separately from shared character visual configurations."""
        visual_file = self.src.file("sharedassets1.assets")
        sheets = {}
        aoes = {}
        for source in visual_file.objects.values():
            if source.type.name != "MonoBehaviour":
                continue
            name = source.parse_monobehaviour_head().m_Name
            if name.endswith("AoeEntry"):
                fields = normalize_fields(self.fields(source))
                area = self.resolve(source, fields["AoePrefab"], "AoePrefab")
                aoes[object_id(source)] = {"name": name, "prefab": self.prefab(area) if area else None,
                                           "fields": authored_fields(fields)}
            elif name in {"HeroSheetHolder", "EnemySheetHolder", "ActiveAbilitySheetHolder",
                          "PassiveAbilitySheetHolder", "HeroSpecializationSheetHolder",
                          "HeroSpecializationChoiceSheetHolder"}:
                fields = normalize_fields(self.fields(source))
                entries = {}
                sheets[name] = {"source": object_id(source), "entries": entries,
                                "references": fields.get("references", {}).get("RefIds", [])}
                for ordinal, raw in enumerate(fields["Entries"]):
                    entry = normalize_fields(raw)
                    key = str(entry["Id"]["_sequentialId"])
                    record = {"ordinal": ordinal, "fields": entry}
                    entries[key] = record
                    projectile = self.resolve(source, entry.get("ProjectilePrefab"), "ProjectilePrefab")
                    if projectile:
                        record["projectile_prefab"] = self.prefab(projectile)
                    config = self.resolve(source, entry.get("VisualConfig"), "VisualConfig")
                    if config and object_id(config) in characters:
                        record["visual"] = object_id(config)
                        bindings = characters[object_id(config)].setdefault("gameplay_entries", {})
                        bindings.setdefault(name, []).append(key)
        return {"sheets": sheets, "aoes": aoes}


def source_metadata(data, version):
    metadata = data / "il2cpp_data" / "Metadata" / "global-metadata.dat"
    steam_root = data.parent.parent.parent
    app_manifest = steam_root / "appmanifest_4425970.acf"
    manifest_text = app_manifest.read_text(encoding="utf-8") if app_manifest.is_file() else ""
    build_id = re.search(r'"buildid"\s+"(\d+)"', manifest_text)
    return {"data": str(data), "steam_build": build_id[1] if build_id else None, "unity_version": version,
            "global_metadata_sha256": sha256(metadata.read_bytes()).hexdigest()}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("data", type=Path, help="Path to original Guildrun_Data directory.")
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    with ExitStack() as stack:
        src = Source(args.data, stack)
        src.file("globalgamemanagers.assets")
        settings = next(o.read_typetree() for o in src.file("globalgamemanagers").objects.values()
                        if o.type.name == "BuildSettings")
        version = settings["m_Version"]
        layouts = BuildLayouts(version)
        layouts.load_local_game(str(args.data.parent))
        src.env.typetree_generator = layouts
        inventory = Inventory(src, layouts)
        characters = inventory.characters()
        gameplay = inventory.gameplay(characters)
        report = {"source": source_metadata(args.data, version), "characters": characters,
                  "prefabs": inventory.prefabs, "effects": inventory.effects, "materials": inventory.materials,
                  "shaders": inventory.shaders, "controllers": inventory.controllers,
                  "resources": inventory.resources, "gameplay": gameplay, "errors": inventory.errors}
        args.output.write_text(json.dumps(preserve_ids(report), default=serialize, ensure_ascii=False, indent=2),
                               encoding="utf-8")
        print({key: len(value) for key, value in report.items() if key != "source"})
        print(Counter(component["class"] for prefab in inventory.prefabs.values() for node in prefab["nodes"]
                      for component in node["components"] if "references" in component))


if __name__ == "__main__":
    main()
