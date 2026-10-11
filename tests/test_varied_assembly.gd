extends SceneTree
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
	var variants := {}
	var topologies := {}
	var widths := {}
	for seed in Array(range(64)) + [99,4294967295]:
		var w := LevelWorld.new(seed,"P03")
		var assembly: Dictionary = w.composition_report.assembly
		var bounds: Rect2 = w.composition_report.site
		var variant: Dictionary = w.composition_report.variant
		variants[str(variant)] = true
		topologies[variant.topology] = true
		widths[variant.left_width] = true
		check(assembly.modules.size() == 5,"five modules")
		check(assembly.links.size() == (5 if variant.topology == 0 else 4),"cycle or branching tree")
		var seen := reachable(w)
		for key in w.views:
			var p: Vector3 = w.views[key].position
			check(seen.has(Vector2i(((Vector2(p.x,p.z)-bounds.position)*4).round())),"reachable resized view %s seed %d" % [key,seed])
		for e in w.composition_report.exits:
			var p := Vector2((e.x0+e.x1)/2,(e.z0+e.z1)/2)
			if e.side == "west": p.x = e.x0+0.5
			elif e.side == "east": p.x = e.x1-0.5
			else: p.y = e.z1-0.5
			check(seen.has(Vector2i(((p-bounds.position)*4).round())),"exit reachable")
			if e.side == "west": p.x = e.x0-1.25
			elif e.side == "east": p.x = e.x1+1.25
			else: p.y = e.z1+1.25
			check(not w.circle_blocked(p.x,p.y,0.3),"exit joins maze")
		var degrees := [0,0,0,0,0]
		for link in assembly.links:
			degrees[link.a] += 1
			degrees[link.b] += 1
			var center := bounds.position + Vector2(link.at)*Compositions.Q
			var axis := Vector2.RIGHT if link.side_a in ["east","west"] else Vector2.DOWN
			for step in range(-12,13):
				var p := center+axis*step*0.125
				check(not w.circle_blocked(p.x,p.y,0.3),"unscaled port clearance")
		check(degrees[4] == 1 and degrees.max() == 3,"single-entry alcove and actual branching")
		if variant.topology != 0:
			var closed := Vector2(variant.left_width*Compositions.Q,3.75) if variant.topology == 1 else Vector2(3.75,10)
			closed += bounds.position
			check(w.circle_blocked(closed.x,closed.y,0.3),"unused connection stays closed")
		for module in assembly.modules:
			check(module.width%20 == 0 and module.depth%20 == 0,"cell-aligned roof footprint")
		for z in range(w.site.position.y,w.site.end.y):
			for x in range(w.site.position.x,w.site.end.x):
				for f in w.cell_fixtures(x,z):
					check(f.y == w.ceiling_height(x,z),"panel follows resized roof")
					for p in [Vector2(f.x0,f.z0),Vector2(f.x1,f.z1)]: check(not w.point_blocked(p.x,p.y),"panel outside resized solids")
		var other := LevelWorld.new(seed,"P03")
		other.chunk_at(-2,3)
		check(w.site_grid == other.site_grid and w.composition_report == other.composition_report,"deterministic varied assembly")
		if seed < 4: await check_step_mesh(w)
	check(topologies.size() == 3 and widths.size() == 2,"all graph and size choices exercised")
	check(variants.size() >= 24,"variety beyond family permutation")
	if failures == 0: print("PASS: P03 — 66 seeds, %d variants, 3 graphs, 2 size splits, reachable rooms/exits, branch/dead end, closed unused ports, actual port/step meshes, panel clearance, determinism" % variants.size())
	quit(1 if failures else 0)
