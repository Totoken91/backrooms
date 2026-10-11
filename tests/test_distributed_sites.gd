extends SceneTree
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: ", label)

## Independent body-radius BFS over the complete chunk, including its maze.
func reachable(w: LevelWorld, data: Dictionary, owner: Vector2i) -> Dictionary:
	var base := Vector2(owner) * 40.0
	var p: Vector3 = data.spawn.position
	var start := Vector2i(((Vector2(p.x,p.z)-base)*4).round())
	var seen := {start:true}
	var queue := [start]
	var cursor := 0
	while cursor < queue.size():
		var at: Vector2i = queue[cursor]
		cursor += 1
		for dir in LevelWorld.DIRS:
			var n: Vector2i = at + dir
			if n.x < 1 or n.y < 1 or n.x >= 160 or n.y >= 160 or seen.has(n): continue
			var point := base + Vector2(n)*0.25
			if w.circle_blocked(point.x,point.y,0.3): continue
			seen[n] = true
			queue.append(n)
	return seen

func signature(w: LevelWorld, owner: Vector2i) -> Array:
	var data := w.reservation_at(owner.x,owner.y)
	var boxes := []
	for b in data.boxes: boxes.append([b.id,b.x0,b.z0,b.x1,b.z1,b.y0,b.y1])
	var fixtures := []
	for f in data.fixtures: fixtures.append([f.id,f.x,f.z,f.y,f.seed])
	return [data.grid,boxes,fixtures,data.report,data.views,w.chunk_at(owner.x,owner.y)]

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

func check_step_mesh(w: LevelWorld, data: Dictionary, owner: Vector2i) -> void:
	var chunk := Chunk.new()
	root.add_child(chunk)
	var materials := {}
	for key in ["wall", "floor", "ceiling", "skirting"]:
		materials[key] = StandardMaterial3D.new()
	await chunk.setup(w, owner, materials, PlaneMesh.new())
	var mesh: Mesh = chunk.get_node("Geometry").mesh
	var bounds: Rect2 = data.report.site
	for link in data.report.assembly.links:
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
	var tested := 0
	var owners := []
	var fixture_ids := {}
	for seed in [0,1,7,17,42,99,1601967012,4294967295]:
		var w := LevelWorld.new(seed,"P05")
		var other := LevelWorld.new(seed,"P05")
		other.reservation_at(15,-21)
		other.chunk_at(12,-8)
		for dz in range(-1,2):
			for dx in range(-1,2):
				var chosen := []
				for z in range(dz*2,dz*2+2):
					for x in range(dx*2,dx*2+2):
						if w.reservation_rect(x,z).has_area(): chosen.append(Vector2i(x,z))
				check(chosen.size()==1,"one site per district")
				var owner: Vector2i = chosen[0]
				var data := w.reservation_at(owner.x,owner.y)
				var seen := reachable(w,data,owner)
				var base := Vector2(owner)*40.0
				check(signature(w,owner)==signature(other,owner),"query-order independent site %s" % owner)
				for view in data.views.values():
					var p: Vector3 = view.position
					check(seen.has(Vector2i(((Vector2(p.x,p.z)-base)*4).round())),"all views reachable %s seed %d" % [owner,seed])
				for exit in data.report.exits:
					var p := Vector2((exit.x0+exit.x1)*0.5,(exit.z0+exit.z1)*0.5)
					var dir := Vector2.LEFT if exit.side=="west" else Vector2.RIGHT if exit.side=="east" else Vector2.DOWN
					for signum in [-1,1]:
						var point := p+dir*float(signum)*1.25
						check(seen.has(Vector2i(((point-base)*4).round())),"exit connects site and maze %s" % owner)
				# Left/top inter-chunk contracts are reachable from the site.
				for side in [0,1]:
					var k := 1+2*(w.hash_cell(owner.x,owner.y,101 if side==0 else 202)%8)
					var point := Vector2(0.75,(k+0.5)*2.5) if side==0 else Vector2((k+0.5)*2.5,0.75)
					check(seen.has(Vector2i((point*4).round())),"reaches chunk border contract")
					var crossing := base+(Vector2(0,point.y) if side==0 else Vector2(point.x,0))
					for step in range(-4,5):
						var q := crossing+(Vector2.RIGHT if side==0 else Vector2.DOWN)*float(step)*0.25
						check(not w.circle_blocked(q.x,q.y,0.3),"chunk seam body clearance")
				for f in data.fixtures:
					check(not fixture_ids.has(str(seed)+":"+f.id),"globally unique fixture ID")
					fixture_ids[str(seed)+":"+f.id]=true
					check(f.y==w.ceiling_height(floori(f.x/2.5),floori(f.z/2.5)),"fixture height follows remote room")
				var before := signature(w,owner)
				w.panels_off[data.fixtures[0].id]=true
				w.prune(100,100,2)
				check(w._reservations.size()<=26,"bounded reservation cache after pruning")
				check(before==signature(w,owner),"same site after eviction")
				check(w.panels_off.has(data.fixtures[0].id),"extinction retained after eviction")
				if seed==99:
					owners.append(owner)
					if owner in [Vector2i(-2,-1),Vector2i(3,1),Vector2i(3,3)]:
						await check_step_mesh(w,data,owner)
				tested += 1
	await check_gpu_metadata()
	print("P05 seed99 owners: ",owners)
	if failures==0: print("PASS: P05 distributed sites — ",tested," reservations, district budget, signed coordinates, independent query order, body BFS, maze/border exits, unique panels, eviction/return")
	quit(1 if failures else 0)


## Render the actual structural metadata shader, including negative slots,
## reassignment seven chunks away and reset. Upload order matches production.
func check_gpu_metadata() -> void:
	var streamer := WorldStreamer.new()
	root.add_child(streamer)
	var baker := LightBaker.new()
	root.add_child(baker)
	var shader := Shader.new()
	shader.code = "shader_type canvas_item; render_mode blend_disabled;\n#include \"res://shaders/structural_room.gdshaderinc\"\nuniform vec2 point; void fragment(){ COLOR=vec4(vec3(structural_ceiling(point,3.2)/8.0),1.0); }"
	var material := ShaderMaterial.new()
	material.shader = shader
	streamer.materials={"test":material}
	var world := LevelWorld.new(99,"P05")
	streamer.reset(world)
	for owner in [Vector2i(-2,-1),Vector2i(3,1)]:
		streamer.center = owner
		var chunk := Chunk.new()
		chunk.coord = owner
		streamer._upload(chunk)
		var data := world.reservation_at(owner.x,owner.y)
		for ceiling in [2.2,3.2,4.8]:
			var cell := Vector2i.ZERO
			for key in data.ceilings:
				if is_equal_approx(data.ceilings[key],ceiling):
					cell = key
					break
			var point := (Vector2(cell)+Vector2(0.5,0.5))*2.5
			material.set_shader_parameter("point",point)
			var result: Array = await baker._render(material,0)
			check(absf(result[0].get_pixel(0,0).r*8.0-ceiling)<0.04,"GPU ceiling lookup positive/negative owner")
		var alias := Chunk.new()
		alias.coord = owner+Vector2i(7,0)
		streamer.center = alias.coord
		streamer._upload(alias)
		var stale: Array = await baker._render(material,0)
		check(absf(stale[0].get_pixel(0,0).r*8.0-3.2)<0.04,"GPU rejects stale metadata slot")
		chunk.free()
		alias.free()
	streamer.reset(LevelWorld.new(7,"P05"))
	var reset: Array = await baker._render(material,0)
	check(absf(reset[0].get_pixel(0,0).r*8.0-3.2)<0.04,"GPU invalidates room metadata on reset")
	streamer.queue_free()
	baker.queue_free()
	await process_frame
