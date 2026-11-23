"""Resolve controller overrides per character before exporting skeletal motion."""
import argparse
from contextlib import ExitStack
import json
from pathlib import Path

from import_balancing import BuildLayouts, read_fields
from import_scenes import Source, material_asset


# Godot's FBX importer suffixes these renderers to disambiguate duplicate node names.
IMPORTED_MESH_NAMES = {50022: {"Ratna": "Ratna2"}, 50074: {"Tilly": "Tilly2"}}


def death_blends(src, file, prefab):
    result = {}
    for ref in prefab.read_typetree()["m_Component"]:
        component = file.objects[ref["component"]["m_PathID"]]
        if component.type.name != "MonoBehaviour":
            continue
        script = component.parse_monobehaviour_head().m_Script.deref_parse_as_object()
        if script.m_ClassName != "CharacterMaterialController":
            continue
        for binding in read_fields(component, src.env.typetree_generator)["_renderers"]:
            # MaterialOverrideDeathLilToon. Unbound renderers retain their authored material.
            if binding["_deathOverrides"]["m_PathID"] != 60896:
                continue
            _, renderer = src.resolve(file, binding["_renderer"])
            owner, go = src.resolve(file, renderer.read_typetree()["m_GameObject"])
            if owner != file:
                raise ValueError(f"External character renderer {owner.name}:{go.path_id}")
            settings = binding["_deathBlendSettings"]["settings"]
            result[go.read_typetree()["m_Name"]] = [
                round(settings["startDelay"], 5), round(settings["duration"], 5)]
    return result


def plan(src, game, target, *, output=None, ranked=False, visual_ids=(), ranks=()):
    file = src.file("sharedassets1.assets")
    records = json.loads((game / "balancing/sharedassets1.json").read_text(encoding="utf8"))["records"]
    output = output or game
    rig_by_visual = {}
    exports = {}
    # PC_Renderer/HeroRender (globalgamemanagers.assets:6684), opaque queue, layers 3 and 10.
    outline_layers = 1032

    def visit(go, parent_active=True):
        data = go.read_typetree()
        active = parent_active and bool(data["m_IsActive"])
        for ref in data["m_Component"]:
            c = file.objects[ref["component"]["m_PathID"]]
            if c.type.name == "Animator":
                yield c, active
            elif c.type.name == "Transform":
                for ptr in c.read_typetree()["m_Children"]:
                    tr = file.objects[ptr["m_PathID"]].read_typetree()
                    yield from visit(file.objects[tr["m_GameObject"]["m_PathID"]], active)

    def mesh_bindings(go, result, parent_active=True):
        data = go.read_typetree()
        active = parent_active and bool(data["m_IsActive"])
        for ref in data["m_Component"]:
            component = file.objects[ref["component"]["m_PathID"]]
            if component.type.name in ("MeshRenderer", "SkinnedMeshRenderer"):
                renderer = component.read_typetree()
                paths = ["res://" + material_asset(src, file, ptr, output, character=True) if ptr["m_PathID"] else ""
                         for ptr in renderer["m_Materials"]]
                binding = {"surfaces": paths, "visible": active and bool(renderer["m_Enabled"])}
                if binding["visible"] and outline_layers & (1 << data["m_Layer"]):
                    queues = []
                    for ptr in renderer["m_Materials"]:
                        if not ptr["m_PathID"]:
                            continue
                        owner, material = src.resolve(file, ptr)
                        info = material.read_typetree()
                        queue = info["m_CustomRenderQueue"]
                        if queue < 0 and info["m_Shader"]["m_PathID"]:
                            _, shader = src.resolve(owner, info["m_Shader"])
                            tags = dict(shader.read().m_ParsedForm.m_SubShaders[0].m_Tags.tags)
                            queue = 3000 if tags.get("Queue", "").startswith(("Transparent", "Overlay")) else 2000
                        queues.append(queue)
                    if queues and all(queue <= 2500 for queue in queues):
                        binding["outline"] = True
                        # HeroRender02 (6647) draws layer 10 again after HeroRender.
                        if data["m_Layer"] == 10:
                            binding["redraw_after_outline"] = True
                result[data["m_Name"]] = binding
            elif component.type.name == "Transform":
                for child in component.read_typetree()["m_Children"]:
                    tr = file.objects[child["m_PathID"]].read_typetree()
                    mesh_bindings(file.objects[tr["m_GameObject"]["m_PathID"]], result, active)

    hero_visuals = set()
    if ranked:
        sheet = next(record for record in records if record["type"] == "HeroSheetHolder")
        hero_visuals = {hero["<VisualConfig>k__BackingField"]["m_PathID"] for hero in sheet["fields"]["Entries"]
                        if not hero["<DisabledInGame>k__BackingField"]}

    def selected_prefabs():
        for record in records:
            visual = record["id"]
            if record["type"] != "CharacterVisualConfig" or (visual_ids and visual not in visual_ids):
                continue
            fields = record["fields"]
            if not ranked:
                yield visual, None, fields["Prefab"]
            elif visual in hero_visuals:
                for rank, prefab in enumerate(fields["PrefabsPerRank"], start=1):
                    if prefab["m_PathID"] and (not ranks or rank in ranks):
                        yield visual, rank, prefab

    for visual, rank, prefab_ref in selected_prefabs():
        renderers = []
        _, prefab = src.resolve(file, prefab_ref)
        death = death_blends(src, file, prefab)
        board_origin_node = None
        if rank is not None:
            root_transform = next(
                ref.component.deref() for ref in prefab.read().m_Component
                if ref.component.deref().type.name == "Transform"
            )
            position = root_transform.read_typetree()["m_LocalPosition"]
            # Battle spawning replaces the prefab root translation with its assigned cell.
            if any(abs(position[axis]) > 0.00001 for axis in "xyz"):
                board_origin_node = prefab.peek_name()
        for animator, active in visit(prefab):
            ptr = animator.read_typetree()["m_Controller"]
            if not ptr["m_PathID"]:
                continue
            owner, controller = src.resolve(file, ptr)
            data = controller.read_typetree()
            overrides = {}
            if controller.type.name == "AnimatorOverrideController":
                overrides = {p["m_OriginalClip"]["m_PathID"]: p["m_OverrideClip"] for p in data["m_Clips"]
                             if p["m_OverrideClip"]["m_PathID"]}
                owner, controller = src.resolve(owner, data["m_Controller"])
                data = controller.read_typetree()
            roles = {}
            loops = {}
            clip_settings = {}
            clips = []
            for original in data["m_AnimationClips"]:
                if not original["m_PathID"]:
                    continue
                _, template = src.resolve(owner, original)
                source, clip = src.resolve(owner, overrides.get(original["m_PathID"], original))
                if source != file:
                    raise ValueError(f"External animation {source.name}: {clip.path_id}")
                clips.append(clip.path_id)
                roles[template.peek_name()] = clip.peek_name()
                fields = clip.read_typetree()
                settings = fields.get("m_AnimationClipSettings") or fields["m_MuscleClip"]
                loops[clip.peek_name()] = bool(settings.get("m_LoopTime", False))
                clip_settings[clip.peek_name()] = settings
            if clips:
                names = dict(data["m_TOS"])
                states = {}
                machine = data["m_Controller"]["m_StateMachineArray"][0]["data"]
                for state_ptr in machine["m_StateConstantArray"]:
                    state = state_ptr["data"]
                    trees = state["m_BlendTreeConstantArray"]
                    if not trees:
                        continue
                    leaves = trees[0]["data"]["m_NodeArray"]
                    if len(leaves) != 1:
                        continue
                    clip_index = leaves[0]["data"]["m_ClipID"]
                    if 0 <= clip_index < len(data["m_AnimationClips"]):
                        ptr = data["m_AnimationClips"][clip_index]
                        if ptr["m_PathID"]:
                            _, template = src.resolve(owner, ptr)
                            states[names[state["m_NameID"]]] = roles[template.peek_name()]
                mesh_map = {}
                mesh_bindings(file.objects[animator.read_typetree()["m_GameObject"]["m_PathID"]], mesh_map)
                for source_name, imported_name in IMPORTED_MESH_NAMES.get(animator.path_id, {}).items():
                    mesh_map[source_name]["imported_name"] = imported_name
                for name, binding in mesh_map.items():
                    if name in death:
                        binding["death_blend"] = death[name]
                exports[animator.path_id] = list(dict.fromkeys(clips))
                binding = {"model": f"res://rigs/{animator.path_id}/model.fbx", "clips": roles,
                           "loop": loops, "meshes": mesh_map, "states": states}
                if rank is not None:
                    binding["prefab"] = prefab.path_id
                    if active and board_origin_node:
                        binding["board_origin_node"] = board_origin_node
                if not active:
                    # Javryn's bow animator is authored under an inactive skill VFX root at every rank.
                    binding["action_only"] = True
                if states.get("BasicAttack") == "Ayaka_BasicAttack02":
                    state_indices = {names[entry["data"]["m_NameID"]]: index
                                     for index, entry in enumerate(machine["m_StateConstantArray"])}
                    entry_blends = {}
                    exit_blends = {}
                    for state_name in ("BasicAttack", "SkillAttack"):
                        index = state_indices[state_name]
                        transition, = (entry["data"] for entry in machine["m_AnyStateTransitionConstantArray"]
                                       if entry["data"]["m_DestinationState"] == index)
                        assert transition["m_HasFixedDuration"] and not transition["m_HasExitTime"]
                        assert transition["m_TransitionOffset"] == 0 and transition["m_CanTransitionToSelf"]
                        entry_blends[state_name] = transition["m_TransitionDuration"]
                        exit_transition, = (entry["data"] for entry in
                                            machine["m_StateConstantArray"][index]["data"]["m_TransitionConstantArray"])
                        assert exit_transition["m_DestinationState"] == state_indices["Idle"]
                        assert exit_transition["m_HasExitTime"] and exit_transition["m_HasFixedDuration"]
                        assert not exit_transition["m_ConditionConstantArray"] and exit_transition["m_TransitionOffset"] == 0
                        settings = clip_settings[states[state_name]]
                        clip_length = settings["m_StopTime"] - settings["m_StartTime"]
                        exit_blends[state_name] = [clip_length * exit_transition["m_ExitTime"],
                                                   exit_transition["m_TransitionDuration"]]
                    binding["entry_blends"] = entry_blends
                    binding["exit_blends"] = exit_blends
                renderers.append(binding)
        if rank is None:
            rig_by_visual[str(visual)] = renderers
        elif renderers:
            rig_by_visual.setdefault(str(visual), {})[str(rank)] = renderers
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text("\n".join(f"{i}\t{','.join(map(str, clips))}" for i, clips in exports.items()), encoding="utf8")
    name = "rank_rigs.json" if ranked else "rigs.json"
    folder = output / "Characters"
    folder.mkdir(parents=True, exist_ok=True)
    (folder / name).write_text(json.dumps(rig_by_visual, indent=2), encoding="utf8")
    print(len(exports), "rigs", sum(map(len, exports.values())), "clip bindings")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("data", type=Path)
    parser.add_argument("plan", type=Path)
    parser.add_argument("--output", type=Path, help="Staging Godot project directory for manifests and materials")
    parser.add_argument("--ranked", action="store_true", help="Use enabled heroes' PrefabsPerRank entries")
    parser.add_argument("--visual-id", type=int, action="append", default=[])
    parser.add_argument("--rank", type=int, action="append", default=[])
    args = parser.parse_args()
    with ExitStack() as stack:
        src = Source(args.data, stack)
        managers = src.file("globalgamemanagers")
        src.file("globalgamemanagers.assets")
        settings = next(obj.read_typetree() for obj in managers.objects.values()
                        if obj.type.name == "BuildSettings")
        layouts = BuildLayouts(settings["m_Version"])
        layouts.load_local_game(str(args.data.parent))
        src.env.typetree_generator = layouts
        plan(src, Path(__file__).resolve().parents[1] / "game", args.plan, output=args.output,
             ranked=args.ranked, visual_ids=args.visual_id, ranks=args.rank)
