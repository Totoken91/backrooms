extends SceneTree
## Variable ceilings: data clearance, mesh closure, panel heights, collisions.
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: ", label)

func mesh_hit(mesh: Mesh, a: Vector3, b: Vector3) -> Variant:
	var nearest: Variant = null
	for surface in mesh.get_surface_count():
		var data := mesh.surface_get_arrays(surface)
		var vs: PackedVector3Array = data[Mesh.ARRAY_VERTEX]
		for i in range(0, vs.size(), 3):
			var hit = Geometry3D.segment_intersects_triangle(a, b, vs[i], vs[i + 1], vs[i + 2])
			if hit != null and (nearest == null or a.distance_to(hit) < a.distance_to(nearest)):
				nearest = hit
	return nearest

func check_exits(w: LevelWorld) -> void:
	var bounds: Rect2 = w.composition_report.site.grow(2.5)
	var step := 0.25
	var size := Vector2i((bounds.size / step).round())
	var a: Vector3 = w.spawn.position
	var start := Vector2i(((Vector2(a.x, a.z) - bounds.position) / step).round())
	var seen := {start: true}
	var queue := [start]
	var cursor := 0
	while cursor < queue.size():
		var at: Vector2i = queue[cursor]
		cursor += 1
		for dir in LevelWorld.DIRS:
			var n: Vector2i = at + dir
			if n.x < 0 or n.y < 0 or n.x >= size.x or n.y >= size.y or seen.has(n): continue
			var p := bounds.position + Vector2(n) * step
			if w.circle_blocked(p.x, p.y, 0.3): continue
			seen[n] = true
			queue.append(n)
	for e in w.composition_report.exits:
		var p := Vector2((e.x0 + e.x1) / 2, (e.z0 + e.z1) / 2)
		if e.side == "west": p.x = e.x0 - 1.25
		elif e.side == "east": p.x = e.x1 + 1.25
		else: p.y = e.z1 + 1.25
		check(seen.has(Vector2i(((p - bounds.position) / step).round())), "C02 exit reaches maze seed %d %s" % [w.seed, e.name])

func run() -> void:
	var mirrors := {}
	for seed in [0, 1, 2, 7, 17, 99, 65535, 4294967295]:
		var w := LevelWorld.new(seed, "C02")
		mirrors[w.composition_report.variant.mirror] = true
		check_exits(w)
		var a: Vector3 = w.views.entry.position
		var b: Vector3 = w.views.reveal.position
		check(w.composition_report.id == "C02", "composition identifier")
		check(absf(w.ceiling_height(floori(a.x / 2.5), floori(a.z / 2.5)) - 2.2) < 1e-6, "low entry")
		check(absf(w.ceiling_height(floori(b.x / 2.5), floori(b.z / 2.5)) - 4.8) < 1e-6, "high reveal")
		for step in 101:
			var p := a.lerp(b, step / 100.0)
			check(not w.circle_blocked(p.x, p.z, 0.3), "entry/reveal body clearance seed %d" % seed)
		for v in w.views.values():
			check(not w.circle_blocked(v.position.x, v.position.z, 0.3), "QA view clearance")
		for z in range(2, 9):
			for x in range(2, 9):
				for f in w.cell_fixtures(x, z):
					check(f.y == w.ceiling_height(x, z), "fixture follows ceiling")
					check(absf(f.x / 2.5 - floorf(f.x / 2.5) - 0.5) < 1e-6, "panel X grid")
					check(absf(f.z / 2.5 - floorf(f.z / 2.5) - 0.5) < 1e-6, "panel Z grid")
					for p in [Vector2(f.x0, f.z0), Vector2(f.x1, f.z1)]:
						check(not w.point_blocked(p.x, p.y), "actual panel footprint clear")
	check(mirrors.size() == 2, "both mirrored plans covered")
	var w := LevelWorld.new(99, "C02")
	var chunk := Chunk.new()
	root.add_child(chunk)
	var materials := {}
	for key in ["wall", "floor", "ceiling", "skirting"]:
		materials[key] = StandardMaterial3D.new()
	await chunk.setup(w, Vector2i.ZERO, materials, PlaneMesh.new())
	var mesh: Mesh = chunk.get_node("Geometry").mesh
	var x: float = w.views.entry.position.x
	# Miss panel holes: probe off their cell centres.
	for spec in [[Vector3(x, 1, 19.5), 2.2], [Vector3(x, 1, 13.0), 4.8]]:
		var hit = mesh_hit(mesh, spec[0], spec[0] + Vector3.UP * 6)
		check(hit != null and absf(hit.y - spec[1]) < 1e-5, "ceiling mesh at actual height %s" % spec[1])
	var step = mesh_hit(mesh, Vector3(x, 3, 14), Vector3(x, 3, 16))
	check(step != null and absf(step.z - 15.0) < 1e-5, "height transition has a closed vertical face")
	var panels: MultiMesh = chunk.get_node("Panels").multimesh
	for i in chunk.fixtures.size():
		check(absf(panels.get_instance_transform(i).origin.y - (chunk.fixtures[i].y - 0.006)) < 1e-5, "panel mesh flush with its ceiling")
	var max_y := 0.0
	var body: StaticBody3D = chunk.get_node("Collision")
	for owner in body.get_shape_owners():
		for i in body.shape_owner_get_shape_count(owner):
			var shape: BoxShape3D = body.shape_owner_get_shape(owner, i)
			max_y = maxf(max_y, body.shape_owner_get_transform(owner).origin.y + shape.size.y / 2)
	check(absf(max_y - 4.8) < 1e-5, "wall collision not clamped to old height")
	var spans := SpanMap.build(w, Vector2(5, 5), 140, 0.125)
	check(not spans.solid(x, 3, 13) and spans.solid(x, 3, 19.5), "lighting spans distinguish the high and low spaces")
	var low: Color = spans.room_heights.get_pixel(floori((x - 5) / 2.5), 5)
	check(absf(low.g - 2.2) < 1e-6, "structural metadata retains precise ceiling height")
	# Exercise the actual metadata upload and shared shader lookup on the GPU.
	var baker := LightBaker.new()
	root.add_child(baker)
	var shader := Shader.new()
	shader.code = "shader_type canvas_item; render_mode blend_disabled;\n#include \"res://shaders/structural_room.gdshaderinc\"\nuniform vec2 probe; void fragment(){COLOR=vec4(structural_ceiling(probe,3.2)/8.0,0,0,1);}"
	var material := ShaderMaterial.new()
	material.shader = shader
	baker._set_spans(material, spans, Vector2i.ZERO)
	for spec in [[Vector2(x, 13), 4.8], [Vector2(x, 19.5), 2.2], [Vector2(-100, -100), 3.2]]:
		material.set_shader_parameter("probe", spec[0])
		var tiles: Array = await baker._render(material, 0)
		check(absf(tiles[0].get_pixel(0, 0).r - spec[1] / 8.0) <= 1.0 / 255.0, "GPU structural ceiling lookup")
	baker.queue_free()
	chunk.queue_free()
	await process_frame
	if failures == 0:
		print("PASS: variable ceilings — 8 seeds, connected exits, mirrored clearance, actual panels, mesh roofs and step closure, collision height, spans and structural metadata CPU/GPU")
	quit(1 if failures else 0)
