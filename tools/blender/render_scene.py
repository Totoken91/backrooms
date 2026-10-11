# Ground-truth renders of the game's geometry in Blender Cycles.
# Builds the exported boxes, floors, ceiling and panels (scene JSON from
# `godot -- export_scene=...`), applies the game's textures in world space,
# places the camera exactly like the game (eye height, yaw, vertical FOV) and
# renders with path tracing and denoising.
#
# blender --background --factory-startup --python tools/blender/render_scene.py -- \
#   scene.json out.png '{"view":"entry","width":720,"height":540,"samples":96, ...}'
import bpy, json, math, os, sys

argv = sys.argv[sys.argv.index("--") + 1:]
scene_path, out_path = argv[0], os.path.abspath(argv[1])  # Blender resolves relative paths elsewhere
opts = json.loads(argv[2]) if len(argv) > 2 else {}
root = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
tex = lambda name: os.path.join(root, "assets", "textures", name)
data = json.load(open(scene_path))
H = data["height"]
P = {  # artistic parameters, all overridable from the command line
    "view": "entry", "width": 720, "height": 540, "samples": 96, "bounces": 6,
    "panel_strength": 9.0, "panel_color": [1.0, 0.96, 0.86], "exposure": 0.0,
    "wall_tint": [1.0, 1.0, 1.0], "floor_tint": [1.0, 1.0, 1.0], "ceiling_tint": [1.0, 1.0, 1.0],
    "wall_rough": 0.85, "look": "AgX - Base Contrast", "wall_scale": 0.6,
}
P.update(opts)

bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
sc.render.engine = "CYCLES"
sc.cycles.device = "CPU"
sc.cycles.samples = P["samples"]
sc.cycles.use_denoising = True
sc.cycles.max_bounces = P["bounces"]
sc.cycles.diffuse_bounces = P["bounces"]
sc.render.resolution_x, sc.render.resolution_y = P["width"], P["height"]
sc.render.resolution_percentage = 100
sc.view_settings.view_transform = "AgX"
try:
    sc.view_settings.look = P["look"]
except TypeError:
    pass
sc.view_settings.exposure = P["exposure"]
world = bpy.data.worlds.new("Black")
world.use_nodes = True
world.node_tree.nodes["Background"].inputs[0].default_value = (0, 0, 0, 1)
sc.world = world


def material(name, image, scale, tint, rough, axis_scale=(1, 1, 1)):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    n, l = m.node_tree.nodes, m.node_tree.links
    bsdf = n["Principled BSDF"]
    geo = n.new("ShaderNodeNewGeometry")
    mapping = n.new("ShaderNodeMapping")
    mapping.inputs["Scale"].default_value = (axis_scale[0] / scale, axis_scale[1] / scale, axis_scale[2] / scale)
    img = n.new("ShaderNodeTexImage")
    img.image = bpy.data.images.load(image)
    img.projection = "BOX"
    img.projection_blend = 0.05
    mul = n.new("ShaderNodeMix")
    mul.data_type = "RGBA"
    mul.blend_type = "MULTIPLY"
    mul.inputs[0].default_value = 1.0
    mul.inputs[7].default_value = (*tint, 1)
    l.new(geo.outputs["Position"], mapping.inputs["Vector"])
    l.new(mapping.outputs["Vector"], img.inputs["Vector"])
    l.new(img.outputs["Color"], mul.inputs[6])
    l.new(mul.outputs[2], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Specular IOR Level"].default_value = P.get("specular", 0.5)
    return m


wall_m = material("Wall", tex("wallpaper_albedo.png"), P["wall_scale"], P["wall_tint"], P["wall_rough"])
floor_m = material("Floor", tex("carpet_albedo.png"), 0.6, P["floor_tint"], 0.95)
# Square tiles, three per 2.5 m cell: the 1 × 2 tile texture shows its top half.
ceil_m = material("Ceiling", tex("ceiling_tile_albedo.png"), 2.5 / 3, P["ceiling_tint"], 0.9, (1, 0.5, 1))
panel_m = bpy.data.materials.new("Panel")
panel_m.use_nodes = True
pn = panel_m.node_tree.nodes
for node in list(pn):
    pn.remove(node)
em = pn.new("ShaderNodeEmission")
em.inputs["Color"].default_value = (*P["panel_color"], 1)
# Strength = panel_strength × the panel's power (face attribute), like the game.
pw = pn.new("ShaderNodeAttribute")
pw.attribute_name = "power"
scale = pn.new("ShaderNodeMath")
scale.operation = "MULTIPLY"
scale.inputs[1].default_value = P["panel_strength"]
panel_m.node_tree.links.new(pw.outputs["Fac"], scale.inputs[0])
panel_m.node_tree.links.new(scale.outputs[0], em.inputs["Strength"])
out = pn.new("ShaderNodeOutputMaterial")
panel_m.node_tree.links.new(em.outputs[0], out.inputs[0])


def to_b(x, y, z):  # Godot (x, y up, z) -> Blender (x, -z, y up)
    return (x, -z, y)


def add_mesh(name, verts, faces, mat):
    me = bpy.data.meshes.new(name)
    me.from_pydata(verts, [], faces)
    me.update()
    ob = bpy.data.objects.new(name, me)
    ob.data.materials.append(mat)
    sc.collection.objects.link(ob)
    return ob


# Walls and bulkheads as closed boxes.
verts, faces = [], []
for x0, z0, x1, z1, y0, y1 in data["boxes"]:
    b = len(verts)
    for (x, y, z) in [(x0, y0, z0), (x1, y0, z0), (x1, y0, z1), (x0, y0, z1), (x0, y1, z0), (x1, y1, z0), (x1, y1, z1), (x0, y1, z1)]:
        verts.append(to_b(x, y, z))
    faces += [(b, b + 1, b + 2, b + 3), (b + 4, b + 7, b + 6, b + 5), (b, b + 4, b + 5, b + 1), (b + 1, b + 5, b + 6, b + 2), (b + 2, b + 6, b + 7, b + 3), (b + 3, b + 7, b + 4, b)]
add_mesh("Walls", verts, faces, wall_m)
# Floor and ceiling per open cell; panels are thin emissive slabs.
fv, ff, cv, cf = [], [], [], []
c = data["cell"]
for x, z in data["floors"]:
    for (vs, fs, y) in [(fv, ff, 0.0), (cv, cf, H)]:
        b = len(vs)
        vs += [to_b(x * c, y, z * c), to_b((x + 1) * c, y, z * c), to_b((x + 1) * c, y, (z + 1) * c), to_b(x * c, y, (z + 1) * c)]
        fs.append((b, b + 3, b + 2, b + 1) if y == 0 else (b, b + 1, b + 2, b + 3))
add_mesh("Floor", fv, ff, floor_m)
add_mesh("Ceiling", cv, cf, ceil_m)
pv, pf, dv, df, powers = [], [], [], [], []
# panel_keep: keep 1 panel out of N (light placement studies).
for i, (x0, z0, x1, z1, power) in enumerate(data["fixtures"]):
    if i % P.get("panel_keep", 1):
        continue
    vs, fs_ = (pv, pf) if power > 0.1 else (dv, df)
    b = len(vs)
    y = H - 0.004
    vs += [to_b(x0, y, z0), to_b(x1, y, z0), to_b(x1, y, z1), to_b(x0, y, z1)]  # frameless diffuser
    fs_.append((b, b + 3, b + 2, b + 1))
    if power > 0.1:
        powers.append(power)
panels = add_mesh("Panels", pv, pf, panel_m)
attr = panels.data.attributes.new("power", "FLOAT", "FACE")
attr.data.foreach_set("value", powers if P.get("panel_power", True) else [1.0] * len(powers))
if dv:
    dead_m = bpy.data.materials.new("DeadPanel")
    dead_m.use_nodes = True
    dead_m.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.62, 0.62, 0.58, 1)
    add_mesh("DeadPanels", dv, df, dead_m)

# Camera exactly like the game: eye height, yaw (0 = north = Godot -Z), vertical FOV.
vx, vz, yaw = data["views"][P["view"]] if isinstance(P["view"], str) else P["view"]
cam_data = bpy.data.cameras.new("Eye")
cam_data.sensor_fit = "VERTICAL"
cam_data.angle_y = math.radians(data["fov"])
cam_data.clip_start = 0.05
cam = bpy.data.objects.new("Eye", cam_data)
cam.location = to_b(vx, data["eye"], vz)
cam.rotation_euler = (math.pi / 2, 0, -yaw)
sc.collection.objects.link(cam)
sc.camera = cam
sc.render.filepath = out_path
sc.render.image_settings.file_format = "PNG"

# passes: also writes the diffuse direct / indirect light (E / π, without the
# surface colour) and the diffuse colour as EXR, and prints their means over a
# 3 × 3 grid of the image (rows top to bottom) for comparison with the game.
if P.get("passes"):
    vl = sc.view_layers[0]
    vl.use_pass_diffuse_direct = vl.use_pass_diffuse_indirect = vl.use_pass_diffuse_color = True
    sc.use_nodes = True
    nt = sc.node_tree
    rl = nt.nodes.new("CompositorNodeRLayers")
    comp = nt.nodes.new("CompositorNodeComposite")
    nt.links.new(rl.outputs["Image"], comp.inputs["Image"])
    fo = nt.nodes.new("CompositorNodeOutputFile")
    fo.base_path = os.path.dirname(out_path)
    fo.format.file_format = "OPEN_EXR"
    fo.format.color_depth = "32"
    fo.file_slots.clear()
    prefix = os.path.splitext(os.path.basename(out_path))[0]
    for name in ["DiffDir", "DiffInd", "DiffCol"]:
        fo.file_slots.new(f"{prefix}-{name}-")
        nt.links.new(rl.outputs[name], fo.inputs[-1])
bpy.ops.render.render(write_still=True)
print("rendered", out_path)
if P.get("passes"):
    stats = {}
    for name in ["DiffDir", "DiffInd", "DiffCol"]:
        f = os.path.join(os.path.dirname(out_path), f"{prefix}-{name}-{sc.frame_current:04d}.exr")
        img = bpy.data.images.load(f)
        w, h = img.size
        px = list(img.pixels)
        grid = []
        for row in range(3):          # top to bottom
            for col in range(3):
                s, n = [0.0, 0.0, 0.0], 0
                for y in range(h - (row + 1) * h // 3, h - row * h // 3, 3):
                    for x in range(col * w // 3, (col + 1) * w // 3, 3):
                        i = (y * w + x) * 4
                        s = [s[0] + px[i], s[1] + px[i + 1], s[2] + px[i + 2]]
                        n += 1
                grid.append([round(v / n, 4) for v in s])
        stats[name] = grid
    json.dump(stats, open(os.path.splitext(out_path)[0] + "-passes.json", "w"))
    print("passes", json.dumps(stats))
