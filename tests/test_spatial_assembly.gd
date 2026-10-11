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
	var graphs := {}
	var widths := {}
	var deep_rows := {}
	var loops_seen := {}
	for seed in Array(range(96)) + [99,4294967295]:
		var w := LevelWorld.new(seed,"P04")
		var assembly: Dictionary = w.composition_report.assembly
		var bounds: Rect2 = w.composition_report.site
		var variant: Dictionary = w.composition_report.variant
		widths[variant.left_width] = true
		deep_rows[str(variant.rows)] = true
		loops_seen[variant.loops] = true
		check(assembly.modules.size() == 6,"six modules")
		check(assembly.links.size() == 5+variant.loops,"spanning tree plus requested loops")
		var seen := reachable(w)
		for key in w.views:
			var p: Vector3 = w.views[key].position
			check(seen.has(Vector2i(((Vector2(p.x,p.z)-bounds.position)*4).round())),"reachable shaped view %s seed %d" % [key,seed])
		for e in w.composition_report.exits:
			var p := Vector2((e.x0+e.x1)/2,(e.z0+e.z1)/2)
			if e.side == "west": p.x = e.x0+0.5
			elif e.side == "east": p.x = e.x1-0.5
			else: p.y = e.z1-0.5
			check(seen.has(Vector2i(((p-bounds.position)*4).round())),"exit reachable")
			if e.side == "west": p.x = e.x0-1.25
			elif e.side == "east": p.x = e.x1+1.25
			else: p.y = e.z1+1.25
			check(not w.circle_blocked(p.x,p.y,0.3),"exit joins maze seed %d" % seed)
		var degrees := [0,0,0,0,0,0]
		var signature := []
		var used := {"0.west":true,"1.east":true,"4.south":true}
		for link in assembly.links:
			degrees[link.a] += 1
			degrees[link.b] += 1
			signature.append("%d-%d" % [mini(link.a,link.b),maxi(link.a,link.b)])
			used["%d.%s" % [link.a,link.side_a]] = true
			used["%d.%s" % [link.b,link.side_b]] = true
			var center := bounds.position+Vector2(link.at)*Compositions.Q
			var axis := Vector2.RIGHT if link.side_a in ["east","west"] else Vector2.DOWN
			for step in range(-12,13):
				var p := center+axis*step*0.125
				check(not w.circle_blocked(p.x,p.y,0.3),"port seed %d %s/%s step %d at %s" % [seed,link.a,link.side_a,step,p])
		signature.sort()
		graphs[str(signature)] = true
		check(degrees.max() >= 3,"branch rather than pure snake")
		if variant.loops == 0: check(degrees[2] == 1 or degrees[3] == 1 or degrees[5] == 1,"tree has dead end without a maze exit")
		var shapes := {}
		for module in assembly.modules:
			shapes[module.shape] = true
			check(module.width%20 == 0 and module.depth%20 == 0,"cell aligned footprint")
			var m := RoomFamilies.make_shaped(module.family,module.variant,module.width,module.depth)
			for side in m.ports:
				if used.has("%d.%s" % [module.slot,side]): continue
				var p := bounds.position+Vector2(module.origin+m.ports[side].at)*Compositions.Q
				check(w.circle_blocked(p.x,p.y,0.3),"unused shaped port closed")
			if module.shape != "rectangle":
				var p := bounds.position+Vector2(module.origin+Vector2i(module.width-12,module.depth-12))*Compositions.Q
				check(w.point_blocked(p.x,p.y),"footprint has actual missing corner")
		check(shapes.size() == 4,"rectangle, L, T and cross present")
		for z in range(w.site.position.y,w.site.end.y):
			for x in range(w.site.position.x,w.site.end.x):
				for f in w.cell_fixtures(x,z):
					check(f.y == w.ceiling_height(x,z),"panel follows shaped roof")
					for p in [Vector2(f.x0,f.z0),Vector2(f.x1,f.z1)]: check(not w.point_blocked(p.x,p.y),"panel outside shaped solids")
		var other := LevelWorld.new(seed,"P04")
		other.chunk_at(-2,3)
		check(w.site_grid == other.site_grid and w.composition_report == other.composition_report,"deterministic P04")
		if seed < 4: await check_step_mesh(w)
	check(widths.size() == 5 and deep_rows.size() == 3 and loops_seen.size() == 3,"all sizes and cycle counts exercised")
	check(graphs.size() >= 10,"multiple actual connection graphs")
	if failures == 0: print("PASS: P04 — 98 seeds, %d connection graphs, 5 width splits, 3 depth splits, L/T/cross footprints, reachable views/exits, body clearance, closed ports, real step meshes and panels" % graphs.size())
	quit(1 if failures else 0)
