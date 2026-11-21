"""Translate the placement button's three serialized particle bursts to canvas geometry."""
import argparse
import math
from contextlib import ExitStack
from pathlib import Path

from PIL import Image
from UnityPy.helpers.MeshHelper import MeshHandler
from import_scenes import Source, material_texture, vector


def curve(resources, name, keys):
    points = []
    for time, value, left, right in keys:
        points.append(f"{vector('Vector2', time, value)}, {left:.9g}, {right:.9g}, 0, 0")
    resources.extend([f'[sub_resource type="Curve" id="{name}"]',
                      "_data = [" + ", ".join(points) + "]", f"point_count = {len(keys)}", ""])
    return f'SubResource("{name}")'


def size_curve(resources, name, module):
    keys = [(k["time"], k["value"], k["inSlope"], k["outSlope"])
            for k in module["maxCurve"]["m_Curve"]]
    return curve(resources, name, keys)


def alpha_curve(resources, name, gradient):
    values = [(gradient[f"atime{i}"] / 65535, gradient[f"key{i}"]["a"])
              for i in range(gradient["m_NumAlphaKeys"])]
    slopes = [(b - a) / (end - start) for (start, a), (end, b) in zip(values, values[1:])]
    keys = [(time, alpha, slopes[max(0, i - 1)], slopes[min(i, len(slopes) - 1)])
            for i, (time, alpha) in enumerate(values)]
    return curve(resources, name, keys)


def packed_points(points):
    return vector("PackedVector2Array", *(v for point in points for v in point))


def export(src, game, name, pairs):
    level = src.file("level3")
    ext = {'res://battle/fight_highlight_particle.gd': ('Script', 'Particle')}
    resources = []
    nodes = ['[node name="HighlightOrigin" type="Control"]', "anchor_left = 0.5", "anchor_right = 0.5",
             "anchor_top = 0.5", "anchor_bottom = 0.5", "mouse_filter = 2", ""]
    for system_id, renderer_id in pairs:
        ps = level.objects[system_id].read_typetree()
        init = ps["InitialModule"]
        size = ps["SizeModule"]
        renderer = level.objects[renderer_id].read_typetree()
        owner, mat_reader = src.resolve(level, renderer["m_Materials"][0])
        material = mat_reader.read_typetree()["m_SavedProperties"]
        floats, colors = dict(material["m_Floats"]), dict(material["m_Colors"])
        maps = dict(material["m_TexEnvs"])
        main = maps["_MainTex"]
        texture_path, texture = material_texture(src, owner, main["m_Texture"], game)
        image = texture.read()
        properties = []
        if renderer["m_RenderMode"] == 4:
            _, reader = src.resolve(level, renderer["m_Mesh"])
            mesh = MeshHandler(reader.read())
            mesh.process()
            sx = init["startSizeZ"]["scalar"] * math.sin(init["startRotationY"]["scalar"])
            sy = -init["startSize"]["scalar"] * math.sin(init["startRotation"]["scalar"])
            if size["enabled"]:
                sx *= size["z"]["scalar"]
                sy *= size["curve"]["scalar"]
            points = [(z * sx, x * sy) for x, _, z in mesh.m_Vertices]
            uv = [(u * image.m_Width, (1-v) * image.m_Height) for u, v in mesh.m_UV0]
            faces = [vector("PackedInt32Array", *tri) for tri in mesh.get_triangles()[0]]
            properties.append("polygons = [" + ", ".join(faces) + "]")
            ext['res://UI/fight_highlight.gdshader'] = ('Shader', 'Shader')
            resources.extend([f'[sub_resource type="ShaderMaterial" id="Mat{system_id}"]', 'shader = ExtResource("Shader")',
                              'shader_parameter/tex_scale = ' + vector("Vector2", *[main["m_Scale"][k] for k in "xy"]),
                              'shader_parameter/tex_offset = ' + vector("Vector2", *[main["m_Offset"][k] for k in "xy"]),
                              f'shader_parameter/intensity = {colors["_Color"]["r"]}'])
            if floats["_Dissolve"]:
                noise = maps["_DissolveTex"]
                noise_path, _ = material_texture(src, owner, noise["m_Texture"], game)
                ext['res://' + noise_path] = ("Texture2D", "Noise")
                resources.extend(['shader_parameter/use_dissolve = true', 'shader_parameter/dissolve_tex = ExtResource("Noise")',
                                  'shader_parameter/dissolve_scale = ' + vector("Vector2", *[noise["m_Scale"][k] for k in "xy"]),
                                  'shader_parameter/dissolve_speed = ' + vector("Vector2", *[floats[f"_Dissolve_{k}_Spd"] for k in "XY"]),
                                  f'shader_parameter/dissolve_amount = {floats["_DissolveAmount"]}',
                                  f'shader_parameter/dissolve_softness = {floats["_DissolveSmoothness"]}',
                                  f'shader_parameter/dissolve_power = {floats["_DissolvePower"]}'])
            resources.append("")
            properties.extend([f'material = SubResource("Mat{system_id}")', f'metadata/unity_mesh = {reader.path_id}'])
        else:
            assert renderer["m_RenderMode"] == 0
            image_mask = image.image.getchannel("R")
            rgba = Image.new("RGBA", image_mask.size, "white")
            rgba.putalpha(image_mask)
            texture_path = "UI/textures/fight_highlight_quad_mask.png"
            (game / texture_path).parent.mkdir(exist_ok=True, parents=True)
            rgba.save(game / texture_path)
            width, height = init["startSize"]["scalar"], init["startSizeY"]["scalar"]
            points = [(x * width, y * height) for x, y in [(-.5, -.5), (.5, -.5), (.5, .5), (-.5, .5)]]
            uv = [(0, 0), (image.m_Width, 0), (image.m_Width, image.m_Height), (0, image.m_Height)]
        texture_key = f"T{texture.path_id}"
        ext['res://' + texture_path] = ("Texture2D", texture_key)
        tint = init["startColor"]["maxColor"]
        nodes.extend([f'[node name="Burst{system_id}" type="Polygon2D" parent="."]',
                      'script = ExtResource("Particle")', f'texture = ExtResource("{texture_key}")',
                      'polygon = ' + packed_points(points), 'uv = ' + packed_points(uv),
                      'color = ' + vector("Color", *(tint[k] for k in "rgba")),
                      f'period = {ps["lengthInSec"]}', f'lifetime = {init["startLifetime"]["scalar"]}',
                      f'metadata/unity_particle = {system_id}', f'metadata/unity_material = {mat_reader.path_id}', *properties])
        if size["enabled"]:
            ycurve = size_curve(resources, f"Vertical{system_id}", size["curve"])
            xcurve = size_curve(resources, f"Horizontal{system_id}", size["z"]) if size["separateAxes"] else ycurve
            nodes.extend([f"horizontal_size = {xcurve}", f"vertical_size = {ycurve}"])
        if ps["ColorModule"]["enabled"]:
            gradient = ps["ColorModule"]["gradient"]["maxGradient"]
            nodes.append("opacity = " + alpha_curve(resources, f"Alpha{system_id}", gradient))
        nodes.append("")
    header = ['[gd_scene format=3]', '']
    header.extend(f'[ext_resource type="{kind}" path="{path}" id="{key}"]' for path, (kind, key) in ext.items())
    (game / "UI" / f"fight_highlight_{name}.tscn").write_text("\n".join(header + [""] + resources + nodes), encoding="utf-8")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("data", type=Path)
    args = parser.parse_args()
    with ExitStack() as stack:
        source = Source(args.data, stack)
        project = Path(__file__).resolve().parents[1] / "game"
        export(source, project, "front", [(9535, 12328), (9536, 12329)])
        export(source, project, "back", [(10391, 14305)])
