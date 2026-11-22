"""Import the Steam demo's serialized scene hierarchy, cameras and sprite renderers."""
import argparse
from collections import Counter
from contextlib import ExitStack
import json
import math
from pathlib import Path
import re

import UnityPy
from UnityPy.streams import EndianBinaryReader
from UnityPy.helpers.MeshHelper import MeshHandler


def quote(value):
    return json.dumps(value, ensure_ascii=False)


def vector(kind, *values):
    return f"{kind}({', '.join(format(v, '.9g') for v in values)})"


def correlated_light_rgb(temperature):
    """Unity's published linear RGB fit (SIGGRAPH 2018 HDRP, slide 131)."""
    t = min(40000, max(1000, temperature)) / 1000
    t2 = t * t
    if t < 6.57:
        red = 1.0
        green = (-399.809 + 414.271 * t + 111.543 * t2) / (2779.24 + 164.143 * t + 84.7356 * t2)
    else:
        red = (1.35651 + 0.216422 * t + 0.000633715 * t2) / (-3.24223 + 0.918711 * t)
        green = (1370.38 + 734.616 * t + 0.689955 * t2) / (-4625.69 + 1699.87 * t)
    blue = 1.0 if t > 6.57 else (
        (348.963 - 523.53 * t + 183.62 * t2) / (2848.82 - 214.52 * t + 78.8614 * t2))
    return tuple(min(1.0, max(0.0, channel)) for channel in (red, green, blue))


def light_color(data, apply_temperature):
    color = tuple(data["m_Color"][key] for key in "rgba")
    if not apply_temperature or not data.get("m_UseColorTemperature"):
        return color
    modulated = []
    for channel, multiplier in zip(color, correlated_light_rgb(data["m_ColorTemperature"])):
        linear = channel / 12.92 if channel <= 0.04045 else ((channel + 0.055) / 1.055) ** 2.4
        value = linear * multiplier
        modulated.append(value * 12.92 if value <= 0.0031308 else 1.055 * value ** (1 / 2.4) - 0.055)
    return (*modulated, color[3])


class Source:
    def __init__(self, data, stack):
        self.data = data
        self.env = UnityPy.Environment()
        self.stack = stack
        self.files = {}
        self.materials = set()
        self.character_probe = None
        self.non_casting_materials = set()
        self.shader_materials = set()
        self.use_light_temperature = None
        for path in data.glob("*.resS"):
            reader = EndianBinaryReader(stack.enter_context(path.open("rb")))
            self.env.register_cab(path.name, reader)

    def file(self, name):
        if name not in self.files:
            path = self.data / name
            if not path.is_file():
                path = self.data / "Resources" / name
            stream = self.stack.enter_context(path.open("rb"))
            self.files[name] = self.env.load_file(stream, name=name)
        return self.files[name]

    def resolve(self, owner, ptr):
        idx = ptr["m_FileID"]
        file = self.file(Path(owner.externals[idx - 1].path).name) if idx else owner
        return file, file.objects[ptr["m_PathID"]]

    def lights_use_temperature(self):
        if self.use_light_temperature is None:
            graphics = next(o.read_typetree(check_read=False) for o in self.file("globalgamemanagers").objects.values()
                            if o.type.name == "GraphicsSettings")
            self.use_light_temperature = graphics.get("m_LightsUseLinearIntensity", False) and graphics.get(
                "m_LightsUseColorTemperature", False)
        return self.use_light_temperature


def mesh_asset(src, scene, pointer, game):
    file, reader = src.resolve(scene, pointer)
    path = f"meshes/{Path(file.name).stem.replace(' ', '_')}_{reader.path_id}.obj"
    dest = game / path
    if dest.exists():
        return path
    mesh = MeshHandler(reader.read())
    mesh.process()
    if not mesh.m_Vertices:
        return None
    dest.parent.mkdir(parents=True, exist_ok=True)
    with dest.open("w", encoding="utf-8") as stream:
        for x, y, z, *_ in mesh.m_Vertices:
            stream.write(f"v {x:.9g} {y:.9g} {-z:.9g}\n")
        for u, v, *_ in mesh.m_UV0 or []:
            stream.write(f"vt {u:.9g} {v:.9g}\n")
        for x, y, z, *_ in mesh.m_Normals or []:
            stream.write(f"vn {x:.9g} {y:.9g} {-z:.9g}\n")
        for i, triangles in enumerate(mesh.get_triangles()):
            stream.write(f"g surface_{i}\n")
            for a, b, c in triangles:
                face = []
                for vertex in (c+1, b+1, a+1):
                    uv = str(vertex) if mesh.m_UV0 else ""
                    suffix = f"/{uv}/{vertex}" if mesh.m_Normals else (f"/{uv}" if uv else "")
                    face.append(f"{vertex}{suffix}")
                stream.write("f " + " ".join(face) + "\n")
    return path


def material_texture(src, owner, pointer, game):
    owner, texture = src.resolve(owner, pointer)
    path = f"textures/{Path(owner.name).stem}_{texture.path_id}.png"
    dest = game / path
    if not dest.exists():
        dest.parent.mkdir(parents=True, exist_ok=True)
        texture.read().image.save(dest)
    return path, texture


def texture_transform(row):
    sx, sy = (row["m_Scale"][axis] for axis in "xy")
    ox, oy = (row["m_Offset"][axis] for axis in "xy")
    return vector("Vector4", sx, sy, ox, 1 - sy - oy)


def sprite_pivot_offset(sprite, flip_x, flip_y):
    # UnityPy exports the trimmed texture rectangle. Unity keeps the pivot in the original rectangle.
    render_data = sprite.m_RD
    rect, trimmed = sprite.m_Rect, render_data.textureRect
    origin, pivot = render_data.textureRectOffset, sprite.m_Pivot
    x = origin.x + trimmed.width / 2 - rect.width * pivot.x
    y = origin.y + trimmed.height / 2 - rect.height * pivot.y
    return (-x if flip_x else x, -y if flip_y else y)


def particle_range(parameter):
    if parameter["minMaxState"] == 3:
        return sorted((parameter["minScalar"], parameter["scalar"]))
    return [parameter["scalar"]] * 2


def persistent_ray(src, scene, components, game):
    particle = components.get("ParticleSystem")
    renderer = components.get("ParticleSystemRenderer")
    if particle is None or renderer is None or not renderer["m_Enabled"] or renderer["m_RenderMode"] != 4:
        return None
    initial = particle["InitialModule"]
    if not particle["playOnAwake"] or not math.isinf(initial["startLifetime"]["scalar"]):
        return None

    mesh = mesh_asset(src, scene, renderer["m_Mesh"], game)
    owner, reader = src.resolve(scene, renderer["m_Materials"][0])
    data = reader.read_typetree()
    _, shader = src.resolve(owner, data["m_Shader"])
    if shader.read().m_ParsedForm.m_Name != "Shader Graphs/VFXTrail_SG":
        return None
    props = data["m_SavedProperties"]
    textures = dict(props["m_TexEnvs"])
    floats = dict(props["m_Floats"])
    colors = dict(props["m_Colors"])
    tint = initial["startColor"]["maxColor"]
    material = f"materials/rays/{Path(owner.name).stem}_{reader.path_id}.tres"
    dest = game / material
    dest.parent.mkdir(parents=True, exist_ok=True)
    header = ['[gd_resource type="ShaderMaterial" format=3]',
              '[ext_resource type="Shader" path="res://materials/forest_ray.gdshader" id="Ray"]']
    settings = ["[resource]", 'shader = ExtResource("Ray")',
                f"shader_parameter/distortion_amount = {floats['_DistortionAmount']:.9g}",
                "shader_parameter/distortion_speed = " + vector("Vector2", colors["_DistortionSpeed"]["r"],
                                                                 -colors["_DistortionSpeed"]["g"]),
                f'metadata/unity_material = {quote(f"{owner.name}:{reader.path_id}")}']
    for parameter, key in (("beam", "_MainTex"), ("mask", "_MaskTex"), ("distortion", "_DistortionTex")):
        row = textures[key]
        path, _ = material_texture(src, owner, row["m_Texture"], game)
        header.append(f'[ext_resource type="Texture2D" path="res://{path}" id="{parameter}"]')
        setting = "beam_mask" if parameter == "mask" else f"{parameter}_texture"
        settings.append(f'shader_parameter/{setting} = ExtResource("{parameter}")')
        settings.append(f"shader_parameter/{parameter}_uv = " + texture_transform(row))
    dest.write_text("\n".join(header + [""] + settings) + "\n", encoding="utf-8")
    src.shader_materials.add(material)
    rotation = vector("Vector3", -initial["startRotationX"]["scalar"], -initial["startRotationY"]["scalar"],
                      initial["startRotation"]["scalar"])
    # The source mesh lies in the YZ plane, so use a nonsingular scale on its empty normal axis.
    scale = vector("Vector3", 1, initial["startSizeY"]["scalar"], initial["startSizeZ"]["scalar"])
    return mesh, material, rotation, scale, vector("Color", *(tint[k] for k in "rgba"))


def light_shaft(src, scene, obj_id, particle, renderer, game, textures, resources):
    shape = particle["ShapeModule"]
    if (not renderer["m_Enabled"] or renderer["m_RenderMode"] != 1 or not particle["playOnAwake"]
            or not particle["looping"] or not shape["enabled"] or shape["type"] != 8 or shape["angle"] != 0):
        return None
    owner, reader = src.resolve(scene, renderer["m_Materials"][0])
    material = reader.read_typetree()
    props = material["m_SavedProperties"]
    floats, maps = dict(props["m_Floats"]), dict(props["m_TexEnvs"])
    shader = "materials/forest_light_shafts.gdshader"
    shader_id = textures.setdefault(shader, str(len(textures) + 1))
    material_id, mesh_id = (f"{kind}{obj_id}" for kind in ("Shaft", "ShaftMesh"))
    resources.extend([f'[sub_resource type="ShaderMaterial" id="{material_id}"]',
                      f'render_priority = {renderer["m_SortingOrder"]}',
                      f'shader = ExtResource("{shader_id}")',
                      f'shader_parameter/intensity = {floats["_ColorIntensity"]:.9g}',
                      f'shader_parameter/additive = {str(floats["_DstBlend"] == 1).lower()}'])
    if "_DEPTHFADE" in material["m_ValidKeywords"]:
        resources.append(f'shader_parameter/fade_distance = {floats["_FadeDistance"]:.9g}')
    for parameter, field in (("beam", "_MainTex"), ("mask", "_MaskTex")):
        row = maps[field]
        path, texture = material_texture(src, owner, row["m_Texture"], game)
        texture_id = textures.setdefault(path, str(len(textures) + 1))
        uniform = "beam_texture" if parameter == "beam" else "beam_mask"
        resources.extend([f'shader_parameter/{uniform} = ExtResource("{texture_id}")',
                          f"shader_parameter/{parameter}_uv = " + texture_transform(row)])
        if parameter == "beam" and texture.read().m_ColorSpace == 1:
            resources.append("shader_parameter/beam_is_srgb = true")
    stretch = renderer["m_LengthScale"]
    pivot = renderer["m_Pivot"]["y"]
    resources.extend(["", f'[sub_resource type="QuadMesh" id="{mesh_id}"]',
                      f'material = SubResource("{material_id}")', "size = " + vector("Vector2", 1, stretch),
                      "center_offset = " + vector("Vector3", 0, pivot, 0), ""])
    emitter, slots = forest_emitter(obj_id, particle, owner, reader, textures, resources, randomize_seed=True)
    pitch, yaw = (math.radians(shape["m_Rotation"][axis]) for axis in "xy")
    direction = (math.sin(yaw) * math.cos(pitch), -math.sin(pitch), -math.cos(yaw) * math.cos(pitch))
    emitter.extend(["emission_direction = " + vector("Vector3", *direction),
                    "emission_cylinder = " + vector("Vector2", shape["radius"]["value"], shape["length"])])
    # Quaternion from the quad's +Y axis to the authored emission direction.
    w = math.sqrt((1.0 + direction[1]) * 0.5)
    rotation = (direction[2] / (2 * w), 0, -direction[0] / (2 * w), w) if w > 0 else (1, 0, 0, 0)
    orientation = "quaternion = " + vector("Quaternion", *rotation)
    height = max(particle_range(particle["InitialModule"]["startSizeY"]))
    cull_margin = height * (stretch * 0.5 + abs(pivot))
    return emitter, mesh_id, slots, cull_margin, orientation


def forest_glow_material(src, owner, material, alignment, data, game, textures, resources, generated):
    identity = f"{Path(owner.name).stem}_{material.path_id}_{alignment}"
    mesh_id = f"ForestGlowQuad_{identity}"
    if mesh_id in generated:
        return mesh_id
    generated.add(mesh_id)
    shader_path = "materials/forest_glow.gdshader"
    shader = textures.setdefault(shader_path, str(len(textures) + 1))
    props = data["m_SavedProperties"]
    values, maps = dict(props["m_Floats"]), dict(props["m_TexEnvs"])
    color = dict(props["m_Colors"])["_Color"]
    material_id = f"ForestGlow_{identity}"
    resources.extend([f'[sub_resource type="ShaderMaterial" id="{material_id}"]',
                      f'shader = ExtResource("{shader}")',
                      f'shader_parameter/alignment = {alignment}',
                      f'shader_parameter/intensity = {values["_ColorIntensity"]:.9g}',
                      f'shader_parameter/additive = {str(values["_DstBlend"] == 1).lower()}'])
    tint = tuple(color[k] for k in "rgb")
    if tint != (1.0, 1.0, 1.0):
        resources.append("shader_parameter/material_tint = " + vector("Vector3", *tint))
    if "_DEPTHFADE" in data["m_ValidKeywords"]:
        resources.append(f'shader_parameter/fade_distance = {values["_FadeDistance"]:.9g}')
    if values["_AlphaClip"]:
        resources.append(f'shader_parameter/alpha_cutoff = {values["_AlphaClipping"]:.9g}')
    bindings = [("main", "_MainTex")]
    if values.get("_MaskMainTex"):
        bindings.append(("mask", "_MaskTex"))
    if alignment == 2:
        bindings.extend([("dissolve", "_DissolveTex"), ("distortion", "_DistortionTex")])
        resources.extend(["shader_parameter/animated_ground = true",
                          f'shader_parameter/double_opacity = {str(bool(values["_NonDistort"])).lower()}',
                          f'shader_parameter/dissolve_amount = {values["_DissolveAmount"]:.9g}',
                          f'shader_parameter/distortion_amount = {values["_DistortionAmount"]:.9g}',
                          "shader_parameter/dissolve_speed = " + vector("Vector2", values["_Dissolve_X_Spd"],
                                                                         -values["_Dissolve_Y_Spd"])])
    for uniform, field in bindings:
        row = maps[field]
        path, _ = material_texture(src, owner, row["m_Texture"], game)
        texture = textures.setdefault(path, str(len(textures) + 1))
        resources.extend([f'shader_parameter/{uniform}_texture = ExtResource("{texture}")',
                          f"shader_parameter/{uniform}_uv = " + texture_transform(row)])
    resources.extend(["", f'[sub_resource type="QuadMesh" id="{mesh_id}"]',
                      f'material = SubResource("{material_id}")', 'size = Vector2(1, 1)', ""])
    return mesh_id


def forest_emitter(obj_id, particle, owner, material, textures, resources, randomize_seed=False):
    gradient = particle["ColorModule"]["gradient"]["maxGradient"]
    alpha_id = f"ForestGlowAlpha{obj_id}"
    count = gradient["m_NumAlphaKeys"]
    offsets = [gradient[f"atime{i}"] / 65535 for i in range(count)]
    colors = [value for i in range(count) for value in (1, 1, 1, gradient[f"key{i}"]["a"])]
    resources.extend([f'[sub_resource type="Gradient" id="{alpha_id}"]',
                      "offsets = " + vector("PackedFloat32Array", *offsets),
                      "colors = " + vector("PackedColorArray", *colors), ""])
    source = "materials/forest_glow_emitter.gd"
    script = textures.setdefault(source, str(len(textures) + 1))
    emission, initial = particle["EmissionModule"], particle["InitialModule"]
    looping = particle["looping"]
    burst = int(emission["m_Bursts"][0]["countCurve"]["scalar"]) if emission["m_BurstCount"] else 0
    slots = initial["maxNumParticles"] if looping else min(initial["maxNumParticles"], burst)
    seed = particle["randomSeed"]
    if particle["autoRandomSeed"]:
        seed = -1 if randomize_seed else obj_id
    emitter = [f'script = ExtResource("{script}")',
               f'source_seed = {seed}',
               f'duration = {particle["lengthInSec"]:.9g}',
               f'simulation_speed = {particle["simulationSpeed"]:.9g}',
               f'prewarm = {str(particle["prewarm"]).lower()}', f'looping = {str(looping).lower()}',
               f'births_per_second = {emission["rateOverTime"]["scalar"]:.9g}', f'burst_count = {burst}',
               f'alpha_curve = SubResource("{alpha_id}")',
               f'independent_height = {str(initial["size3D"]).lower()}',
               f'metadata/unity_particle_material = {quote(f"{owner.name}:{material.path_id}")}']
    ranges = (("speed_range", "startSpeed"), ("width_range", "startSize"),
              ("height_range", "startSizeY"), ("spin_range", "startRotation"))
    if looping:
        ranges += (("lifetime_range", "startLifetime"),)
    emitter.extend(f'{name} = ' + vector("Vector2", *particle_range(initial[field])) for name, field in ranges)
    tint = initial["startColor"]
    for end, key in (("min", "minColor" if tint["minMaxState"] == 2 else "maxColor"), ("max", "maxColor")):
        emitter.append(f'tint_{end} = ' + vector("Color", *(tint[key][channel] for channel in "rgba")))
    return emitter, slots


def forest_glow(src, scene, obj_id, particle, renderer, game, textures, resources, generated):
    if not renderer["m_Enabled"] or not particle["playOnAwake"]:
        return None
    owner, material = src.resolve(scene, renderer["m_Materials"][0])
    data = material.read_typetree()
    alignments = {"VFX_Mat_Gradient_00": (0, 2, 0), "VFX_Mat_Glow_00": (0, 0, 1),
                  "VFX_Mat_Shine_00": (2, 0, 2)}
    mode = alignments.get(data["m_Name"])
    if mode is None or mode[:2] != (renderer["m_RenderMode"], renderer["m_RenderAlignment"]):
        return None
    emitter, slots = forest_emitter(obj_id, particle, owner, material, textures, resources)
    mesh_id = forest_glow_material(src, owner, material, mode[2], data, game, textures, resources, generated)
    shape = particle["ShapeModule"]
    if shape["enabled"] and shape["type"] == 16:
        emitter.append("ground_half_extents = " + vector("Vector2", *(shape["m_Scale"][axis] * 0.5 for axis in "xy")))
    atlas = particle["UVModule"]
    if atlas["enabled"]:
        emitter.extend([f'atlas_columns = {atlas["tilesX"]}',
                        "start_frame_range = " + vector("Vector2", *particle_range(atlas["startFrame"]))])
    return emitter, mesh_id, slots, particle_range(particle["InitialModule"]["startSize"])[1]


def write_character_toon(src, file, material_id, data, shader_name, game, destination):
    props = data["m_SavedProperties"]
    colors = dict(props["m_Colors"])
    floats = dict(props["m_Floats"])
    textures = dict(props["m_TexEnvs"])
    header = ['[gd_resource type="ShaderMaterial" format=3]',
              '[ext_resource type="Shader" path="res://materials/character_toon.gdshader" id="toon"]']
    settings = ["[resource]", f'resource_name = {quote(data["m_Name"])}', 'shader = ExtResource("toon")',
                f'metadata/unity_shader = {quote(shader_name)}',
                f'metadata/unity_material_id = {material_id}',
                f'metadata/unity_reflection = {str(bool(floats["_UseReflection"])).lower()}']

    def param(name, value):
        settings.append(f"shader_parameter/{name} = {value}")

    def texture(name, field):
        row = textures[field]
        if not row["m_Texture"]["m_PathID"]:
            return False
        path, _ = material_texture(src, file, row["m_Texture"], game)
        header.append(f'[ext_resource type="Texture2D" path="res://{path}" id="{name}"]')
        param(name, f'ExtResource("{name}")')
        return True

    def color(name, field, kind="Color"):
        param(name, vector(kind, *(colors[field][key] for key in "rgba")))

    def transform(name, field):
        uv = textures[field]
        x, y = uv["m_Scale"]["x"], uv["m_Scale"]["y"]
        u, v = uv["m_Offset"]["x"], uv["m_Offset"]["y"]
        param(name, vector("Vector4", x, y, u, 1.0 - y - v))

    def values(name, kind, fields):
        param(name, vector(kind, *(floats[key] for key in fields)))

    texture("main_texture", "_MainTex")
    transform("main_transform", "_MainTex")
    color("tint", "_Color")
    param("cutoff", floats["_Cutoff"] if shader_name == "Hidden/lilToonCutout" else 0.0)
    param("use_shadow", str(bool(floats["_UseShadow"])).lower())
    if texture("shadow_texture", "_ShadowColorTex"):
        param("use_shadow_texture", "true")
    color("shadow_color", "_ShadowColor")
    color("second_color", "_Shadow2ndColor")
    color("shadow_border_color", "_ShadowBorderColor")
    values("shade_shape", "Vector4", ("_ShadowBorder", "_ShadowBlur", "_Shadow2ndBorder", "_Shadow2ndBlur"))
    values("shade_controls", "Vector4", ("_ShadowStrength", "_ShadowBorderRange", "_ShadowMainStrength", "_AAStrength"))
    values("shade_receivers", "Vector3", ("_ShadowReceive", "_Shadow2ndReceive", "_Shadow3rdReceive"))
    values("light_limits", "Vector2", ("_LightMinLimit", "_LightMaxLimit"))
    if floats["_UseEmission"]:
        param("use_emission", "true")
        texture("emission_texture", "_EmissionMap")
        transform("emission_transform", "_EmissionMap")
        color("emission_color", "_EmissionColor")
        color("emission_blink", "_EmissionBlink", "Vector4")
        values("emission_controls", "Vector3", ("_EmissionBlend", "_EmissionBlendMode", "_EmissionMainStrength"))
    if floats["_UseReflection"] and floats["_ApplySpecular"] and floats["_SpecularToon"]:
        param("use_highlight", "true")
        param("highlight_additional_lights", str(bool(floats["_ApplySpecularFA"])).lower())
        texture("highlight_texture", "_ReflectionColorTex")
        texture("smoothness_texture", "_SmoothnessTex")
        color("highlight_color", "_ReflectionColor")
        values("highlight_shape", "Vector3", ("_Smoothness", "_SpecularBorder", "_SpecularBlur"))
    if floats["_ShadowEnvStrength"]:
        if src.character_probe is None:
            render_settings = src.file("level3").objects[9527].read_typetree()
            src.character_probe = list(render_settings["m_AmbientProbe"].values())
        probe = src.character_probe
        param("shadow_environment", floats["_ShadowEnvStrength"])
        for channel, base in zip("rgb", (0, 9, 18)):
            row = probe[base:base + 9]
            param("probe_a" + channel, vector("Vector4", row[3], row[1], row[2], row[0] - row[6]))
            param("probe_b" + channel, vector("Vector4", row[4], row[5], 3.0 * row[6], row[7]))
        param("probe_c", vector("Vector3", probe[8], probe[17], probe[26]))
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text("\n".join(header + [""] + settings) + "\n", encoding="utf-8")


def write_crystal_shine(src, file, data, shader_name, game, destination):
    props = data["m_SavedProperties"]
    textures = dict(props["m_TexEnvs"])
    colors = dict(props["m_Colors"])
    floats = dict(props["m_Floats"])
    tint = colors["_Color"]
    speed = colors["_Scroll_Speed"]
    header = ['[gd_resource type="ShaderMaterial" format=3]',
              '[ext_resource type="Shader" path="res://materials/forest_crystal_shine.gdshader" id="Shine"]']
    settings = ["[resource]", f'resource_name = {quote(data["m_Name"])}',
                'shader = ExtResource("Shine")',
                "shader_parameter/tint = " + vector("Vector3", *(tint[k] for k in "rgb")),
                f'shader_parameter/intensity = {floats["_ColorIntensity"]:.9g}',
                "shader_parameter/sweep_speed = " + vector("Vector2", speed["r"], -speed["g"]),
                "metadata/unity_shader = " + quote(shader_name)]
    for uniform, uv, field in (("sweep_texture", "sweep_uv", "_MainTex"), ("crystal_mask", "mask_uv", "_MaskTex")):
        row = textures[field]
        path, _ = material_texture(src, file, row["m_Texture"], game)
        header.append(f'[ext_resource type="Texture2D" path="res://{path}" id="{uniform}"]')
        settings.extend([f'shader_parameter/{uniform} = ExtResource("{uniform}")',
                         f'shader_parameter/{uv} = ' + texture_transform(row)])
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text("\n".join(header + [""] + settings) + "\n", encoding="utf-8")


def material_asset(src, scene, pointer, game, character=False):
    file, reader = src.resolve(scene, pointer)
    key = f"{Path(file.name).stem.replace(' ', '_')}_{reader.path_id}"
    path = f"materials/{key}.tres"
    dest = game / path
    if path in src.materials:
        return path
    data = reader.read_typetree()
    shader_name = ""
    if data["m_Shader"]["m_PathID"]:
        _, shader = src.resolve(file, data["m_Shader"])
        shader_name = shader.read().m_ParsedForm.m_Name
    props = data["m_SavedProperties"]
    if shader_name == "Shader Graphs/VFXTrail_SG" and data["m_Name"] == "RuinsForest_Crystal_Mat_Default_Shine":
        write_crystal_shine(src, file, data, shader_name, game, dest)
        src.materials.add(path)
        src.shader_materials.add(path)
        src.non_casting_materials.add(path)
        return path
    if shader_name == "Custom/ShadowDrawerMod":
        tint = dict(props["m_Colors"])["_Color"]
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_text("\n".join([
            '[gd_resource type="ShaderMaterial" format=3]', '',
            '[ext_resource type="Shader" path="res://materials/battle_shadow_receiver.gdshader" id="1"]', '',
            '[resource]', f'resource_name = {quote(data["m_Name"])}',
            # The Compatibility shader reads the opaque floor before later transparent effects.
            'render_priority = -90', 'shader = ExtResource("1")',
            "shader_parameter/shadow_tint = " + vector("Color", *(tint[key] for key in "rgba")),
            'metadata/unity_shader = "Custom/ShadowDrawerMod"', '',
        ]), encoding="utf-8")
        src.materials.add(path)
        src.shader_materials.add(path)
        src.non_casting_materials.add(path)
        return path
    if (character and shader_name in ("lilToon", "Hidden/lilToonCutout")
            and dict(props["m_Floats"]).get("_Cull") == 2):
        write_character_toon(src, file, reader.path_id, data, shader_name, game, dest)
        src.materials.add(path)
        src.shader_materials.add(path)
        return path
    textures = dict(props["m_TexEnvs"])
    main = next((textures[k] for k in ("_BaseMap", "_BaseColorMap", "_MainTex")
                 if k in textures and textures[k]["m_Texture"]["m_PathID"]), None)
    header = ['[gd_resource type="StandardMaterial3D" format=3]']
    settings = ["[resource]", f'resource_name = {quote(data["m_Name"])}']
    if main:
        texpath, tex = material_texture(src, file, main["m_Texture"], game)
        header.append(f'[ext_resource type="Texture2D" path="res://{texpath}" id="1"]')
        settings.append('albedo_texture = ExtResource("1")')
        if shader_name not in ("lilToon", "Hidden/lilToonOutline"):
            settings.append('transparency = 1')
        settings.append('cull_mode = 2')
    colors = dict(props["m_Colors"])
    color = colors.get("_BaseColor", colors.get("_Color"))
    if shader_name == "Shader Graphs/EnvironmentPlane_SG":
        floats = dict(props["m_Floats"])
        keywords = set(data["m_ValidKeywords"])
        mode = "transparent" if "_SURFACE_TYPE_TRANSPARENT" in keywords else "cutout"
        if mode == "cutout" and floats["_Cull"] == 0:
            mode = "cutout_double_sided"
        texture_parameter = "main_texture"
        sampler_mode = 0
        if main:
            texture = tex.read()
            sampler = texture.m_TextureSettings
            if sampler.m_FilterMode == 0:
                texture_parameter, sampler_mode = "main_texture_point_clamped", 2
            elif sampler.m_WrapU == 1 and sampler.m_WrapV == 1:
                texture_parameter, sampler_mode = "main_texture_clamped", 1
            elif texture.m_MipCount > 1:
                texture_parameter, sampler_mode = "main_texture_mipped", 3
        header[0] = '[gd_resource type="ShaderMaterial" format=3]'
        header.append(f'[ext_resource type="Shader" path="res://materials/environment_plane_{mode}.gdshader" id="2"]')
        settings = settings[:2] + [
            'shader = ExtResource("2")',
            "shader_parameter/tint = " + vector("Vector3", *(color[k] for k in "rgb")),
        ]
        if main:
            settings.append(f'shader_parameter/{texture_parameter} = ExtResource("1")')
        if sampler_mode:
            settings.append(f'shader_parameter/sampler_mode = {sampler_mode}')
        if "_ALPHATEST_ON" in keywords:
            settings.append(f'shader_parameter/alpha_threshold = {floats["_AlphaClipping"]:.9g}')
        src.shader_materials.add(path)
        if floats["_CastShadows"] == 0:
            src.non_casting_materials.add(path)
    elif color:
        settings.append("albedo_color = " + vector("Color", *(color[k] for k in "rgba")))
    if shader_name == "Hidden/lilToonOutline" and data["m_Name"] == "BackgroundIcon_Mat":
        floats = dict(props["m_Floats"])
        if floats["_UseEmission"] and textures["_EmissionMap"]["m_Texture"]["m_PathID"]:
            emission_path, _ = material_texture(src, file, textures["_EmissionMap"]["m_Texture"], game)
            header.append(f'[ext_resource type="Texture2D" path="res://{emission_path}" id="2"]')
            emission = colors["_EmissionColor"]
            settings.remove("cull_mode = 2")
            settings.extend(["disable_receive_shadows = true", "emission_enabled = true",
                             "emission = " + vector("Color", *(emission[k] for k in "rgba")),
                             "emission_operator = 1", 'emission_texture = ExtResource("2")'])
    settings.append("metadata/unity_shader = " + quote(shader_name))
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_text("\n".join(header + [""] + settings) + "\n", encoding="utf-8")
    src.materials.add(path)
    return path


def is_crossroads_gate(src, scene, game_object):
    if not re.fullmatch(r"GateIcon(?:_\d+)?", game_object["m_Name"]):
        return False
    for ref in game_object["m_Component"]:
        owner, component = src.resolve(scene, ref["component"])
        if component.type.name != "MonoBehaviour":
            continue
        fields = component.read_typetree(check_read=False)
        _, script = src.resolve(owner, fields["m_Script"])
        definition = script.read()
        if (definition.m_ClassName == "GateIconView"
                and definition.m_Namespace == "Ember.Scopes.GameRun.Crossroads.Views"):
            return True
    return False


def crossroads_gate_metadata(src, scene, game_object):
    metadata = ["metadata/unity_crossroads_gate = true"]
    for ref in game_object["m_Component"]:
        _, component = src.resolve(scene, ref["component"])
        if component.type.name == "SphereCollider":
            hit = component.read_typetree()
            if hit["m_Enabled"]:
                center = hit["m_Center"]
                metadata.append("metadata/gate_hit_center = " + vector("Vector3", center["x"], center["y"], -center["z"]))
                metadata.append(f'metadata/gate_hit_radius = {hit["m_Radius"]:.9g}')
                break
    return metadata


def import_scene(src, index, scene_path, game, prefab=None):
    scene = src.file(f"level{index}") if prefab is None else prefab[0]
    objects = {}
    transforms = {}
    extras = {}
    counts = Counter()
    def prefab_objects(root):
        yield root
        data = root.read_typetree()
        for ref in data["m_Component"]:
            component = scene.objects[ref["component"]["m_PathID"]]
            yield component
            if component.type.name in ("RectTransform", "Transform"):
                for child in component.read_typetree()["m_Children"]:
                    transform = scene.objects[child["m_PathID"]].read_typetree()
                    yield from prefab_objects(scene.objects[transform["m_GameObject"]["m_PathID"]])

    readers = scene.objects.values() if prefab is None else prefab_objects(prefab[1])
    for obj in readers:
        kind = obj.type.name
        counts[kind] += 1
        if kind == "GameObject":
            objects[obj.path_id] = obj.read_typetree()
        elif kind in ("Transform", "RectTransform"):
            transforms[obj.path_id] = obj.read_typetree()
        elif kind in ("Camera", "Light", "SpriteRenderer", "MeshFilter", "MeshRenderer", "SkinnedMeshRenderer"):
            data = obj.read_typetree()
            extras.setdefault(data["m_GameObject"]["m_PathID"], []).append((kind, data))
    name = Path(scene_path).stem
    nodes = [f'[node name={quote(name)} type="Node3D"]']
    textures = {}
    resources = []
    glow_meshes = set()

    def emit(transform_id, parent, siblings):
        transform = transforms[transform_id]
        obj_id = transform["m_GameObject"]["m_PathID"]
        obj = objects[obj_id]
        raw_name = obj["m_Name"]
        label = re.sub(r'[\x00-\x1f.:@/"%\\]', "_", raw_name).strip() or "Object"
        if label in siblings:
            label += f"_{obj_id}"
        siblings.add(label)
        nodes.append(f'\n[node name={quote(label)} type="Node3D" parent={quote(parent)}]')
        p, q, s = (transform[k] for k in ("m_LocalPosition", "m_LocalRotation", "m_LocalScale"))
        nodes.extend(["position = " + vector("Vector3", p["x"], p["y"], -p["z"]),
                      "quaternion = " + vector("Quaternion", -q["x"], -q["y"], q["z"], q["w"]),
                      "scale = " + vector("Vector3", s["x"], s["y"], s["z"]),
                      f'metadata/unity_id = {obj_id}', f'metadata/unity_name = {quote(raw_name)}'])
        # CrossroadsController hides these scene templates when the board starts.
        crossroads_gate = is_crossroads_gate(src, scene, obj)
        if crossroads_gate:
            nodes.extend(crossroads_gate_metadata(src, scene, obj))
        if not obj["m_IsActive"] or crossroads_gate:
            nodes.extend(["visible = false", "process_mode = 4"])
        path = label if parent == "." else f"{parent}/{label}"
        child_names = set()
        components = dict(extras.get(obj_id, []))
        ray_names = ("Ray_Infinite", "VFX_Rays", "Rays_01", "Rays_02", "Rays_01_Blurry", "Rays_02_Blurry")
        glow_name = name.startswith("Environment_") and re.fullmatch(r"Gradient_01|Ground_Glow_(Left|Right|Back)|Glow_\d{2}", raw_name)
        if prefab is None and obj["m_IsActive"] and (raw_name in ray_names or glow_name):
            for link in obj["m_Component"]:
                component = scene.objects[link["component"]["m_PathID"]]
                if component.type.name in ("ParticleSystem", "ParticleSystemRenderer"):
                    components[component.type.name] = component.read_typetree()
        if raw_name == "Ray_Infinite":
            ray = persistent_ray(src, scene, components, game)
            if ray:
                mesh_path, material_path, rotation, particle_scale, tint = ray
                mesh_id = textures.setdefault(mesh_path, str(len(textures) + 1))
                material_id = textures.setdefault(material_path, str(len(textures) + 1))
                child_names.add("UnityRay")
                nodes.extend([f'\n[node name="UnityRay" type="MeshInstance3D" parent={quote(path)}]',
                              f'mesh = ExtResource("{mesh_id}")', f'material_override = ExtResource("{material_id}")',
                              f"rotation = {rotation}", f"scale = {particle_scale}", "cast_shadow = 0",
                              f"instance_shader_parameters/beam_tint = {tint}"])
        elif glow_name and "ParticleSystem" in components and "ParticleSystemRenderer" in components:
            glow = forest_glow(src, scene, obj_id, components["ParticleSystem"], components["ParticleSystemRenderer"],
                               game, textures, resources, glow_meshes)
            if glow:
                emitter, mesh_id, slots, size = glow
                nodes.extend(emitter)
                for index in range(slots):
                    slot = f"UnityGlow{index + 1}"
                    child_names.add(slot)
                    nodes.extend([f'\n[node name="{slot}" type="MeshInstance3D" parent={quote(path)}]',
                                  f'mesh = SubResource("{mesh_id}")', 'visible = false', 'cast_shadow = 0',
                                  f'extra_cull_margin = {size:.9g}'])
        elif "ParticleSystem" in components and "ParticleSystemRenderer" in components:
            shaft = light_shaft(src, scene, obj_id, components["ParticleSystem"],
                                components["ParticleSystemRenderer"], game, textures, resources)
            if shaft:
                emitter, mesh_id, slots, margin, orientation = shaft
                nodes.extend(emitter)
                for index in range(slots):
                    slot = f"UnityLightShaft{index + 1}"
                    child_names.add(slot)
                    nodes.extend([f'\n[node name="{slot}" type="MeshInstance3D" parent={quote(path)}]',
                                  f'mesh = SubResource("{mesh_id}")', orientation, 'visible = false',
                                  'cast_shadow = 0', f'extra_cull_margin = {margin:.9g}'])
        if "SkinnedMeshRenderer" in components or ("MeshRenderer" in components and "MeshFilter" in components):
            renderer = components.get("SkinnedMeshRenderer", components.get("MeshRenderer"))
            ptr = components.get("MeshFilter", renderer)["m_Mesh"]
            asset = mesh_asset(src, scene, ptr, game) if ptr["m_PathID"] else None
            if asset:
                key = textures.setdefault(asset, str(len(textures) + 1))
                child_names.add("UnityMesh")
                nodes.extend([f'\n[node name="UnityMesh" type="MeshInstance3D" parent={quote(path)}]',
                              f'mesh = ExtResource("{key}")',
                              f'visible = {str(bool(renderer["m_Enabled"])).lower()}'])
                surface_materials = []
                for i, ptr in enumerate(renderer["m_Materials"]):
                    if ptr["m_PathID"]:
                        mat = material_asset(src, scene, ptr, game, character=prefab is not None)
                        key = textures.setdefault(mat, str(len(textures) + 1))
                        nodes.append(f'surface_material_override/{i} = ExtResource("{key}")')
                        surface_materials.append(mat)
                cast_shadow = renderer["m_CastShadows"]
                if (surface_materials and len(surface_materials) == len(renderer["m_Materials"])
                        and all(mat in src.non_casting_materials for mat in surface_materials)):
                    cast_shadow = 0
                if cast_shadow != 1:
                    nodes.append(f"cast_shadow = {cast_shadow}")
        for kind, d in extras.get(obj_id, []):
            if kind == "Light" and d["m_Type"] in (0, 1, 2):
                child_names.add("UnityLight")
                light = {0: "SpotLight3D", 1: "DirectionalLight3D", 2: "OmniLight3D"}[d["m_Type"]]
                nodes.extend([f'\n[node name="UnityLight" type="{light}" parent={quote(path)}]',
                              "light_color = " + vector("Color", *light_color(d, src.lights_use_temperature())),
                              f'light_energy = {d["m_Intensity"]}',
                              f'visible = {str(bool(d["m_Enabled"])).lower()}',
                              f'shadow_enabled = {str(bool(d["m_Shadows"]["m_Type"])).lower()}'])
                if src.lights_use_temperature() and d.get("m_UseColorTemperature"):
                    nodes.append(f'metadata/unity_color_temperature = {d["m_ColorTemperature"]:.9g}')
                if name.startswith("Environment_") and d["m_Type"] == 1 and d["m_Shadows"]["m_Type"]:
                    # PC_RPAsset (globalgamemanagers.assets:6665) uses one 4096px shadow map to 150 units.
                    nodes.extend(["directional_shadow_mode = 0", "directional_shadow_max_distance = 150.0",
                                  f'shadow_opacity = {d["m_Shadows"]["m_Strength"]:.9g}'])
                if d["m_Type"] == 0:
                    nodes.extend([f'spot_range = {d["m_Range"]}', f'spot_angle = {d["m_SpotAngle"]/2}'])
                elif d["m_Type"] == 2:
                    nodes.append(f'omni_range = {d["m_Range"]}')
            elif kind == "Camera":
                child_names.add("UnityCamera")
                nodes.append(f'\n[node name="UnityCamera" type="Camera3D" parent={quote(path)}]')
                nodes.extend([f'fov = {d["field of view"]}', f'near = {d["near clip plane"]}',
                              f'far = {d["far clip plane"]}'])
                if d["orthographic"]:
                    nodes.extend(["projection = 1", f'size = {2*d["orthographic size"]}'])
            elif kind == "SpriteRenderer" and d["m_Sprite"]["m_PathID"]:
                file, reader = src.resolve(scene, d["m_Sprite"])
                sprite = reader.read()
                asset = f"sprites/{Path(file.name).stem}_{reader.path_id}.png"
                dest = game / asset
                if not dest.exists():
                    dest.parent.mkdir(parents=True, exist_ok=True)
                    sprite.image.save(dest)
                key = textures.setdefault(asset, str(len(textures) + 1))
                child_names.add("UnitySprite")
                nodes.append(f'\n[node name="UnitySprite" type="Sprite3D" parent={quote(path)}]')
                nodes.extend([f'texture = ExtResource("{key}")', f'pixel_size = {1/sprite.m_PixelsToUnits}',
                              f'visible = {str(bool(d["m_Enabled"])).lower()}',
                              f'flip_h = {str(bool(d["m_FlipX"])).lower()}',
                              f'flip_v = {str(bool(d["m_FlipY"])).lower()}',
                              "modulate = " + vector("Color", *(d["m_Color"][k] for k in "rgba"))])
                if name.startswith("Environment_"):
                    # PC ForegroundRender (6673) follows the character and layer-8 VFX passes.
                    if obj["m_Layer"] == 12:
                        nodes.append("render_priority = 24")
                    offset = sprite_pivot_offset(sprite, d["m_FlipX"], d["m_FlipY"])
                    if any(abs(coordinate) > 0.0002 for coordinate in offset):
                        nodes.append("offset = " + vector("Vector2", *offset))
        for child in transform["m_Children"]:
            emit(child["m_PathID"], path, child_names)

    root_names = set()
    for key, transform in transforms.items():
        if transform["m_Father"]["m_PathID"] not in transforms:
            emit(key, ".", root_names)
    header = ["[gd_scene format=3]"]
    types = {".png": "Texture2D", ".obj": "ArrayMesh", ".tres": "StandardMaterial3D", ".gdshader": "Shader", ".gd": "Script"}
    for path, resource_id in textures.items():
        resource_type = "ShaderMaterial" if path in src.shader_materials else types[Path(path).suffix]
        header.append(f'[ext_resource type="{resource_type}" path="res://{path}" id="{resource_id}"]')
    dest = (game / Path(scene_path).relative_to("Assets")).with_suffix(".tscn")
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_text("\n".join(header + [""] + resources + nodes) + "\n", encoding="utf-8")
    print(index, name, counts["GameObject"], len(textures), flush=True)
    return dict(index=index, source=scene_path, scene=dest.relative_to(game).as_posix(), components=counts)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("data", type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    with ExitStack() as stack:
        src = Source(args.data, stack)
        settings = next(o.read_typetree() for o in src.file("globalgamemanagers").objects.values()
                        if o.type.name == "BuildSettings")
        scenes = [import_scene(src, i, p, root / "game") for i, p in enumerate(settings["scenes"])]
    (root / "scene_inventory.json").write_text(json.dumps(scenes, indent=2), encoding="utf-8")


if __name__ == "__main__":
    main()
