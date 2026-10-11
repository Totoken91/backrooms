extends SceneTree
## Assembly contract and independent player-radius traversal of generated data.
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: ", label)

func reachable(w: LevelWorld, closed := Rect2()) -> Dictionary:
	var bounds: Rect2 = w.composition_report.site
	var start := Vector2i(((Vector2(w.spawn.position.x, w.spawn.position.z) - bounds.position) * 4).round())
	var size := Vector2i((bounds.size * 4).round())
	var seen := {start: true}
	var queue := [start]
	var cursor := 0
	while cursor < queue.size():
		var at: Vector2i = queue[cursor]
		cursor += 1
		for dir in LevelWorld.DIRS:
			var n: Vector2i = at + dir
			if n.x < 1 or n.y < 1 or n.x >= size.x or n.y >= size.y or seen.has(n): continue
			var p := bounds.position + Vector2(n) * 0.25
			if closed.has_area() and closed.grow(0.3).has_point(p): continue
			if w.circle_blocked(p.x, p.y, 0.3): continue
			seen[n] = true
			queue.append(n)
	return seen

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

func check_step_mesh(w: LevelWorld) -> void:
	var chunk := Chunk.new()
	root.add_child(chunk)
	var materials := {}
	for key in ["wall", "floor", "ceiling", "skirting"]:
		materials[key] = StandardMaterial3D.new()
	await chunk.setup(w, Vector2i.ZERO, materials, PlaneMesh.new())
	var mesh: Mesh = chunk.get_node("Geometry").mesh
	var bounds: Rect2 = w.composition_report.site
	for link in w.composition_report.assembly.links:
		if link.ceil_a == link.ceil_b: continue
		var center: Vector2 = bounds.position + Vector2(link.at) * Compositions.Q
		var axis := Vector3.RIGHT if link.side_a in ["east", "west"] else Vector3.BACK
		var at := Vector3(center.x, (link.ceil_a + link.ceil_b) * 0.5, center.y)
		var hit = mesh_hit(mesh, at - axis * 0.75, at + axis * 0.75)
		check(hit != null and hit.distance_to(at) < 1e-5, "actual ceiling step closes port roof seed %d" % w.seed)
		var body := Vector3(center.x, 1.52, center.y)
		check(mesh_hit(mesh, body - axis * 0.75, body + axis * 0.75) == null, "mesh does not seal walkable port")
	chunk.queue_free()
	await process_frame

func run() -> void:
	var signatures := {}
	for seed in Array(range(32)) + [99, 4294967295]:
		var w := LevelWorld.new(seed, "P02")
		var report: Dictionary = w.composition_report.assembly
		var signature := str(w.composition_report.variant.order)
		signatures[signature] = true
		check(report.modules.size() == 4 and report.links.size() == 4, "four modules in a loop")
		var seen := reachable(w)
		var bounds: Rect2 = w.composition_report.site
		for key in w.views:
			var p: Vector3 = w.views[key].position
			check(seen.has(Vector2i(((Vector2(p.x, p.z) - bounds.position) * 4).round())), "reachable family %s seed %d" % [key, seed])
		for e in w.composition_report.exits:
			var p := Vector2((e.x0 + e.x1) / 2, (e.z0 + e.z1) / 2)
			if e.side == "west": p.x = e.x0 + 0.5
			elif e.side == "east": p.x = e.x1 - 0.5
			else: p.y = e.z1 - 0.5
			check(seen.has(Vector2i(((p - bounds.position) * 4).round())), "exit reachable seed %d %s" % [seed, e.name])
			if e.side == "west": p.x = e.x0 - 1.25
			elif e.side == "east": p.x = e.x1 + 1.25
			else: p.y = e.z1 + 1.25
			check(not w.circle_blocked(p.x, p.y, 0.3), "exit joins maze")
		for link in report.links:
			var center: Vector2 = bounds.position + Vector2(link.at) * Compositions.Q
			var axis := Vector2.RIGHT if link.side_a in ["east", "west"] else Vector2.DOWN
			# Sweep the actual body across both halves of every port, including
			# the shared module boundary and its ceiling change.
			for step in range(-12, 13):
				var p := center + axis * step * 0.125
				check(not w.circle_blocked(p.x, p.y, 0.3), "port crossing seed %d" % seed)
			var size := Vector2(0.25, 1.75) if axis == Vector2.RIGHT else Vector2(1.75, 0.25)
			if seed < 4:
				var without_arm := reachable(w, Rect2(center - size / 2, size))
				for v in w.views.values():
					var p: Vector3 = v.position
					check(without_arm.has(Vector2i(((Vector2(p.x, p.z) - bounds.position) * 4).round())), "loop survives one closed link")
		if seed < 4:
			await check_step_mesh(w)
		var other := LevelWorld.new(seed, "P02")
		other.chunk_at(-1, 1)
		other.chunk_at(0, 0)
		check(w.site_grid == other.site_grid and w.composition_report == other.composition_report, "order-independent deterministic assembly")
		for z in range(w.site.position.y, w.site.end.y):
			for x in range(w.site.position.x, w.site.end.x):
				for f in w.cell_fixtures(x, z):
					check(f.y == w.ceiling_height(x, z), "panel altitude")
					for p in [Vector2(f.x0, f.z0), Vector2(f.x1, f.z1)]:
						check(not w.point_blocked(p.x, p.y), "panel clearance")
	check(signatures.size() >= 8, "genuine family order variety")
	var a: Dictionary = RoomFamilies.make("empty", 0).ports.east
	var b: Dictionary = RoomFamilies.make("pillars", 0).ports.west
	check(PromenadeAssembler.compatible(a, b), "explicit low/high ceiling transition allowed")
	for field in ["side", "width", "floor", "ceiling"]:
		var bad := b.duplicate(true)
		match field:
			"side": bad.side = "east"
			"width": bad.width = 1
			"floor": bad.floor = 0.5
			"ceiling": bad.ceiling = 1.0
		check(not PromenadeAssembler.compatible(a, bad), "reject incompatible " + field)
	if failures == 0:
		print("PASS: P02 assembly — 34 seeds, %d family orders, deterministic reservation, all views/exits, every body-radius port crossing, single-link loop failures, contract rejection, panels, actual port/step meshes" % signatures.size())
	quit(1 if failures else 0)
