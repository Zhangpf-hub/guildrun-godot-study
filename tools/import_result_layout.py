"""Keep the original result screen graphics and the templates bound by Godot."""
import json
import re
from pathlib import Path

GAME = Path(__file__).resolve().parents[1] / "game"
BASE = "Canvas/Root/BattleResultPanelView"
STATS = "Panel/BattleStatsPanel"
REWARDS = "Panel/RewardsPanel"
SWITCH = STATS + "/TitlePanel/SwitchHolder"
VERSUS = STATS + "/TitlePanel/BottomPanel/VersusPortraits"
ROW = STATS + "/DetailStatsPanel/DamageTrackerSummary/DamageTrackerHolder/HeroTrackerView_BattleResult"
PROCEED = REWARDS + "/ButtonContainer/ProceedButton"
LINEAR_BACKDROPS = {"Modal/UnityImage", STATS + "/Background/UnityImage", REWARDS + "/Background/UnityImage"}
ENEMY_PORTRAIT = VERSUS + "/PortraitsRow_Enemies/HeroRoundIconSmall_3"


def export_portrait_states(source, scene, layouts, game=GAME):
    from import_balancing import read_fields
    from import_first_battle import save_sprite

    indicator = read_fields(scene.objects[32094], layouts)
    save_sprite(source, scene, indicator["_banishedSprite"], game)


def export_entrance(source, scene, view, layouts, game=GAME):
    from import_balancing import read_fields

    result = (game / "UI/battle_result.tscn").read_text(encoding="utf-8")
    paths = set()
    controls = {}
    for block in re.split(r"(?=^\[node )", result, flags=re.M):
        header = block.partition("\n")[0]
        match = re.search(r'name="([^"]+)" type="[^"]+" parent="([^"]+)"', header)
        if match:
            path = "/".join(filter(None, (match[2] if match[2] != "." else "", match[1])))
            paths.add(path)
            unity_id = re.search(r"^metadata/unity_id = (\d+)", block, flags=re.M)
            if unity_id:
                controls[int(unity_id[1])] = path

    def flatten(owner, component, parent_start=0):
        animation = read_fields(component, layouts)["animation"]
        tracks = []
        length = last_start = 0
        for track in animation["animations"]:
            kind = track["tweenType"]
            start = (length, last_start, track["startTime"])[track["operation"]]
            last_start = start
            if kind == 72:  # Nested TweenAnimationComponent carries its own complete timing.
                for pointer in track["targets"]:
                    child_owner, child = source.resolve(owner, pointer)
                    nested, nested_length = flatten(child_owner, child, parent_start + start)
                    tracks.extend(nested)
                    length = max(length, start + nested_length)
                continue
            duration = track["duration"]
            length = max(length, start + duration)
            for pointer in track["targets"]:
                _, target = source.resolve(owner, pointer)
                fields = read_fields(target, layouts) if target.type.name == "MonoBehaviour" else target.read_typetree()
                path = controls.get(fields["m_GameObject"]["m_PathID"])
                if path is None:
                    continue
                if kind == 77:  # The TextMeshPro component maps to a Label below its holder.
                    path += "/UnityText"
                if path not in paths:
                    continue
                properties = {76: ("modulate:a",), 77: ("modulate:a",), 84: ("position:x",), 112: ("size:x", "size:y")}[kind]
                for axis, property_name in zip("xy", properties):
                    first, last = (track[key][axis] for key in ("startValue", "endValue"))
                    if first != last:
                        tracks.append({"path": path, "property": property_name, "from": first, "to": last,
                                       "start": round(parent_start + start, 5), "duration": round(duration, 5),
                                       "linear": track["ease"] == 1})
        return tracks, round(length, 5)

    # DamageTrackerSummary and the first HeroTrackerView_BattleResult template in level3.
    summary = read_fields(scene.objects[30859], layouts)
    bindings = {"stats": source.resolve(scene, view["_statsPanelTween"]),
                "rewards": source.resolve(scene, view["_rewardsPanelTween"]), "tracker": (scene, scene.objects[30834])}
    phases = {}
    for name, (file, component) in bindings.items():
        tracks, duration = flatten(file, component)
        if name == "tracker":
            for track in tracks:
                track["path"] = track["path"].removeprefix(ROW + "/")
        phases[name] = {"source": f"{file.name}:{component.path_id}", "duration": duration, "tracks": tracks}
    canvas = read_fields(scene.objects[26843], layouts)
    result = {"canvas_fade_delay": round(canvas["_resultPanelFadeDelay"], 5),
              "canvas_fade_duration": round(canvas["_resultPanelFadeDuration"], 5),
              "reward_delay": round(view["delayToRewards"], 5), "tracker_stagger": round(summary["staggerDelay"], 5),
              **phases}
    output = game / "balancing/result_entrance.json"
    output.parent.mkdir(exist_ok=True)
    output.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")


def build(game=GAME):
    canvas = (game / "UI/Battle.tscn").read_text(encoding="utf-8")
    head, *blocks = re.split(r"(?=^\[node )", canvas, flags=re.M)
    nodes = {}
    for block in blocks:
        header, _, body = block.partition("\n")
        match = re.search(r'name="([^"]+)" type="[^"]+" parent="([^"]+)"', header)
        if match and (match[2] == BASE or match[2].startswith(BASE + "/")):
            parent = match[2].removeprefix(BASE).lstrip("/")
            nodes["/".join(filter(None, (parent, match[1])))] = (
                header.replace(f'parent="{match[2]}"', f'parent="{parent or "."}"'), body)

    leaves = {
        "Modal/UnityImage", "DefeatBackground/UnityImage", "Panel/TitlePanel/TitleText/UnityText",
        STATS + "/Background/UnityImage", STATS + "/TitlePanel/StatsTitleText/UnityText",
        STATS + "/TitlePanel/TotalDurationText/UnityText",
        STATS + "/TitlePanel/Line/UnityImage",
        STATS + "/TitlePanel/BottomPanel/CombatDurationText/UnityText", VERSUS + "/VS/UnityText",
        ENEMY_PORTRAIT + "/HeroDamageIndicator/DamageIcon/UnityImage",
        SWITCH + "/Image/UnityImage", REWARDS + "/Background/UnityImage",
        REWARDS + "/Background/Deco/UnityImage", REWARDS + "/ResultTitleText/UnityText",
        REWARDS + "/Scroll_Rewards/Viewport/Content", REWARDS + "/Line/UnityImage",
        REWARDS + "/TotalEarnedRewardView/RewardTitle/UnityText",
        REWARDS + "/TotalEarnedRewardView/ShardValueText/UnityText",
        PROCEED + "/UnityImage", PROCEED + "/Text (TMP)/UnityText",
        PROCEED + "/Button_Graphics/UnityImage", PROCEED + "/Button_Graphics/TopLayer/UnityImage",
        PROCEED + "/HighlightUI_Proceed/UnityImage",
        PROCEED + "/HighlightUI_Proceed/Highlight_Rotating/UnityImage",
    }
    for base, subtree in (
            (SWITCH, "TrackerButton"), (SWITCH, "HeroStatsButton"),
            (VERSUS, "PortraitsRow_Heroes/HeroRoundIconSmall"),
            (VERSUS, "PortraitsRow_Enemies/HeroRoundIconSmall_3"),
            (ROW, "HeroRoundIconSmall"), (ROW, "DamageSlidersHolder")):
        path = f"{base}/{subtree}/"
        leaves.update(name for name in nodes if name.startswith(path) and (
            "/UnityText" in name or name.endswith("/UnityImage")) and not any(
            child in name for child in ("/DamagedBackground/", "/HeroDamageIndicator/", "/Selected/")))

    retained = set()
    for path in leaves:
        assert path in nodes, path
        while path:
            retained.add(path)
            path = path.rpartition("/")[0]

    output = ['[node name="BattleResultView" type="Control"]\nlayout_mode = 0\nmouse_filter = 2\n'
              'metadata/reference_resolution = Vector2(1920, 1080)\n'
              'metadata/aspect_ratio_threshold = 1.7999999523162842\n']
    resources = set()
    for path, (header, body) in nodes.items():
        if path in retained:
            if path in ("Modal", "Panel"):
                output.append(f'[node name="CopyBefore{path}" type="BackBufferCopy" parent="."]\ncopy_mode = 2\n')
            if path in LINEAR_BACKDROPS:
                body = 'material = SubResource("LinearBackdrop")\n' + body
            resources.update(re.findall(r'ExtResource\("([^"]+)"\)', body))
            # Godot plays the entrance on the result view. Unity CanvasGroup values here
            # are only the hidden starting values of their individual reveal tweens.
            body = body.replace("modulate = Color(1, 1, 1, 0.0)\n", "")
            body = re.sub(r"^(theme_override_colors/font_color = Color\([^\n]+), 0\)$",
                          r"\g<1>, 1)", body, flags=re.M)
            output.append(header + "\n" + body.rstrip() + "\n")
    ext = [line for line in head.splitlines() if line.startswith("[ext_resource") and
           re.search(r'id="([^"]+)"', line)[1] in resources]
    ext.append('[ext_resource type="Shader" path="res://materials/ui_linear_blend.gdshader" id="LinearBlend"]')
    (game / "UI/battle_result.tscn").write_text(
        "[gd_scene format=3]\n\n" + "\n".join(ext) +
        '\n\n[sub_resource type="ShaderMaterial" id="LinearBackdrop"]\nshader = ExtResource("LinearBlend")\n\n' +
        "\n".join(output), encoding="utf-8")


if __name__ == "__main__":
    build()
