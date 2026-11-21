"""Extract the level3 battle camera selectors, lens settings, and Cinemachine blends."""
import argparse
import json
from contextlib import ExitStack
from pathlib import Path

from import_balancing import BuildLayouts, read_fields
from import_scenes import Source


STATE_FIELDS = {
    "start": "_preparationStartVCam", "placement": "_preparationVCam",
    "fight": "_battleDefaultVCam", "result": "_postBattleVCam",
    "crossroads": "_crossroadsVCam", "crossroads_zoom": "_crossroadsZoomVCam",
    "intro": "_introTransitionVCam", "boss_intro": "_bossIntroVCam",
}
GATE_FITS = ("none", "vertical", "horizontal", "fill", "overscan")
LENS_OVERRIDES = ("inherit", "orthographic", "perspective", "physical")


def extract(data, output):
    with ExitStack() as stack:
        source = Source(data, stack)
        for asset in data.glob("*.assets"):
            source.file(asset.name)
        build = next(row.read_typetree() for row in source.file("globalgamemanagers").objects.values()
                     if row.type.name == "BuildSettings")
        layouts = BuildLayouts(build["m_Version"])
        layouts.load_local_game(str(data.parent))
        source.env.typetree_generator = layouts
        battle_scene = next(i for i, path in enumerate(build["scenes"]) if Path(path).stem == "Battle")
        file = source.file(f"level{battle_scene}")

        def components(game_object):
            for entry in game_object.read_typetree()["m_Component"]:
                obj = file.objects[entry["component"]["m_PathID"]]
                if obj.type.name == "MonoBehaviour":
                    pointer = obj.parse_monobehaviour_head().m_Script
                    yield pointer.deref_parse_as_object().m_ClassName, read_fields(obj, layouts)

        controller = dict(components(file.objects[5673]))["BattleCameraController"]
        main_object = file.objects[1804]
        main = dict(components(main_object))["CinemachineBrain"]
        main_camera = next(obj for entry in main_object.read_typetree()["m_Component"]
                           if (obj := file.objects[entry["component"]["m_PathID"]]).type.name == "Camera")
        projection = main_camera.read_typetree()
        _, blend_asset = source.resolve(file, main["CustomBlends"])
        blending = read_fields(blend_asset, layouts)["CustomBlends"]
        payload = {
            "source": {"scene": file.name, "controller": 5673, "virtual_camera_blends": blend_asset.path_id,
                       "effective_aspect_cap": "CameraEffectiveRectApplier.Apply@0x6D4E20",
                       "intro_delay": "BattleCameraController.OnBattleFlowStateChanged@0x38B410"},
            "active_priority": 10, "intro_delay": 0.10000000149011612,
            "effective_aspect_cap": 2.3333332538604736,
            "projection": {
                "camera": main_camera.path_id,
                "physical": projection["m_projectionMatrixMode"] == 2,
                "gate_fit": GATE_FITS[projection["m_GateFitMode"]],
                "sensor": [projection["m_SensorSize"][axis] for axis in ("x", "y")],
                "lens_shift": [projection["m_LensShift"][axis] for axis in ("x", "y")],
                "focal_length": projection["m_FocalLength"],
            },
            "default_blend": [main["DefaultBlend"]["Style"], main["DefaultBlend"]["Time"]],
            "blends": [[row["From"], row["To"], row["Blend"]["Style"], row["Blend"]["Time"]] for row in blending],
            "cameras": {},
        }
        for name, ref in {"cut": None, **STATE_FIELDS}.items():
            camera = (read_fields(file.objects[controller[ref]["m_PathID"]], layouts)
                      if ref else dict(components(file.objects[4160]))["CinemachineCamera"])
            game_object = file.objects[camera["m_GameObject"]["m_PathID"]]
            fields = dict(components(game_object))
            lens = camera["Lens"]
            physical = lens["PhysicalProperties"]
            entry = {"id": game_object.path_id, "name": game_object.read_typetree()["m_Name"],
                     "priority": camera["Priority"]["m_Value"], "fov": lens["FieldOfView"],
                     "near": lens["NearClipPlane"], "far": lens["FarClipPlane"],
                     "physical_lens": {
                         "mode_override": LENS_OVERRIDES[lens["ModeOverride"]],
                         "gate_fit": GATE_FITS[physical["GateFit"]],
                         "sensor": [physical["SensorSize"][axis] for axis in ("x", "y")],
                         "lens_shift": [physical["LensShift"][axis] for axis in ("x", "y")],
                     }}
            if "BattleCameraRatioPositionAdjuster" in fields:
                adjust = fields["BattleCameraRatioPositionAdjuster"]
                entry["aspect"] = list(adjust["_aspectRatioThresholdMinMax"].values())
                entry["z"] = [-v for v in adjust["_localPositionZMinMax"].values()]
            payload["cameras"][name] = entry
        handler = read_fields(file.objects[controller["_inputHandler"]["m_PathID"]], layouts)
        payload["input"] = {
            "mover": file.objects[file.objects[handler["_cameraMoveParent"]["m_PathID"]]
                                  .read_typetree()["m_GameObject"]["m_PathID"]].path_id,
            "aspect": list(handler["_aspectRatioRange"].values()),
            "narrow": list(handler["_zoomRangeNarrow"].values()),
            "wide": list(handler["_zoomRangeWide"].values()),
            "initial": list(handler["_initialZoomCoef"].values()),
            "aim_distance": list(handler["_cameraDistanceByAspect"].values()),
            "bounds_x": [handler[k] for k in ("_minZoom_MinX", "_minZoom_MaxX", "_maxZoom_MinX", "_maxZoom_MaxX")],
            "bounds_z": [handler[k] for k in ("_minZoom_MinZ", "_minZoom_MaxZ", "_maxZoom_MinZ", "_maxZoom_MaxZ")],
        }
        output.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf8")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("data", type=Path)
    args = parser.parse_args()
    extract(args.data, Path(__file__).resolve().parents[1] / "game/balancing/battle_camera.json")
