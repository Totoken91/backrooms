extends "res://tests/test_distributed_sites.gd"
## Independent body BFS over a complete 80m district, not the site topology.
func district_reachable(w: LevelWorld, data: Dictionary, anchor: Vector2i) -> Dictionary:
	var base := Vector2(anchor)*40.0
	var p: Vector3 = data.spawn.position
	var start := Vector2i(((Vector2(p.x,p.z)-base)*4).round())
	var seen := {start:true}
	var queue := [start]
	var cursor := 0
	while cursor<queue.size():
		var at: Vector2i = queue[cursor]
		cursor += 1
		for dir in LevelWorld.DIRS:
			var n: Vector2i = at+dir
			if n.x<1 or n.y<1 or n.x>=320 or n.y>=320 or seen.has(n): continue
			var point := base+Vector2(n)*0.25
			if w.circle_blocked(point.x,point.y,0.3): continue
			seen[n]=true
			queue.append(n)
	return seen

func run() -> void:
	var count := 0
	var fields := 0
	var peak_ms := 0.0
	var peak_grid := 0
	for seed in [0,1,7,17,42,99,1601967012,4294967295]:
		var w := LevelWorld.new(seed,"P07")
		var other := LevelWorld.new(seed,"P07")
		other.chunk_at(13,-19)
		for dz in range(-1,2):
			for dx in range(-1,2):
				var anchor := Vector2i(dx,dz)*2
				var layout := w._district_layout(anchor.x,anchor.y)
				var owner: Vector2i = layout.owner
				var start := Time.get_ticks_usec()
				var data := w.reservation_at(owner.x,owner.y)
				peak_ms=maxf(peak_ms,(Time.get_ticks_usec()-start)/1000.0)
				peak_grid=maxi(peak_grid,data.grid.size())
				var members := 0
				var fixture_ids := {}
				for z in range(anchor.y,anchor.y+2):
					for x in range(anchor.x,anchor.x+2):
						var rect := w.reservation_rect(x,z)
						check(not rect.has_area() or Rect2i(0,0,16,16).encloses(rect),"chunk-local reservation bounds")
						if not rect.has_area(): continue
						members += 1
						var alias := w.reservation_at(x,z)
						check(is_same(alias,data),"all member chunks share one cached owner")
						for cz in range(z*16,(z+1)*16):
							for cx in range(x*16,(x+1)*16):
								for b in w.cell_boxes(cx,cz):
									check(b.x0>=x*40 and b.x1<=(x+1)*40 and b.z0>=z*40 and b.z1<=(z+1)*40,"geometry fragment stays in owning chunk")
								for f in w.cell_fixtures(cx,cz):
									check(not fixture_ids.has(f.id),"no duplicated streamed panel")
									fixture_ids[f.id]=true
				check(members==(4 if layout.large else 1),"four-chunk field or single-chunk segmented site")
				check(signature(w,owner)==signature(other,owner),"query order independent")
				if layout.large:
					fields += 1
					check(data.report.site.size==Vector2(72.5,72.5),"field spans 72.5m in both directions")
					check(data.report.assembly.pillars.size() in [196,289],"complete large lattice")
				var seen := district_reachable(w,data,anchor)
				var base := Vector2(anchor)*40.0
				for v in data.views.values():
					var p: Vector3 = v.position
					check(not w.circle_blocked(p.x,p.z,0.3),"exact camera body clearance")
					check(seen.has(Vector2i(((Vector2(p.x,p.z)-base)*4).round())),"district views reachable seed %d owner %s"%[seed,owner])
				for e in data.report.exits:
					var p := Vector2((e.x0+e.x1)*0.5,(e.z0+e.z1)*0.5)
					var dir := Vector2.LEFT if e.side=="west" else Vector2.RIGHT if e.side=="east" else Vector2.DOWN
					for signum in [-1,1]:
						var at := p+dir*float(signum)*1.25
						check(not w.circle_blocked(at.x,at.y,0.3),"exact exit clearance")
						check(seen.has(Vector2i(((at-base)*4).round())),"district exit reachable seed %d owner %s"%[seed,owner])
				var saved := signature(w,owner)
				var off: String = data.fixtures[0].id
				w.panels_off[off]=true
				w.prune(100,-100,2)
				check(saved==signature(w,owner) and w.panels_off.has(off),"deterministic eviction and persistent panel state")
				count += 1
		# Never retain an unbounded history of districts or shared geometries.
		for i in range(-12,13):
			w.reservation_at(i*2,i*2)
			w.prune(i*2,i*2,2)
			check(w._district_layouts.size()<=10 and w._reservations.size()<=10,"bounded district/owner cache")
	await check_seam_meshes()
	check_compression()
	check_partial_retention()
	check_legacy_fixture_seeds()
	if failures==0: print("PASS: P07 multi-chunk — ",count," districts, ",fields," fields, shared owners, 196/289 pillars, independent order, body BFS/exits, unique panels, bounded caches, real cut faces; peak owner build ms=",peak_ms," grid bytes=",peak_grid)
	quit(1 if failures else 0)

func check_seam_meshes() -> void:
	# Force 5m lattice to put a real column on the four-chunk intersection.
	var world: LevelWorld
	for seed in range(30):
		world=LevelWorld.new(seed,"P07")
		if world.composition_report.variant.spacing==40: break
	check(world.composition_report.variant.spacing==40,"seam column fixture found")
	var materials := {}
	for key in ["wall","floor","ceiling","skirting"]: materials[key]=StandardMaterial3D.new()
	var chunks := []
	var total_hit := 0
	for coord in [Vector2i.ZERO,Vector2i(1,0),Vector2i(0,1),Vector2i(1,1)]:
		var c := Chunk.new()
		root.add_child(c)
		await c.setup(world,coord,materials,PlaneMesh.new())
		chunks.append(c)
		var mesh: Mesh = c.get_node("Geometry").mesh
		check(mesh_hit(mesh,Vector3(39.9,3,39.9),Vector3(40.1,3,39.9))==null,"no internal east cut face in actual mesh")
		check(mesh_hit(mesh,Vector3(39.9,3,39.9),Vector3(39.9,3,40.1))==null,"no internal south cut face in actual mesh")
		if mesh_hit(mesh,Vector3(38,3,39.8),Vector3(39.9,3,39.8))!=null: total_hit += 1
		check(mesh_hit(mesh,Vector3(39,1.52,22.5),Vector3(41,1.52,22.5))==null,"walkable east mesh seam")
		check(mesh_hit(mesh,Vector3(22.5,1.52,39),Vector3(22.5,1.52,41))==null,"walkable south mesh seam")
	check(total_hit==1,"single exterior wall hit across four meshes")
	for c in chunks: c.queue_free()
	await process_frame

func check_compression() -> void:
	# Dense resolver is retained as an independent oracle for geometry/fixtures.
	for spacing in [32,40]:
		for width in [3,4]:
			var pick := func(domain: String,n: int) -> int:
				if domain=="pillars.spacing": return 0 if spacing==32 else 1
				if domain=="pillars.width": return 0 if width==3 else 1
				return Hashing.text(domain)%n
			var recipe := SiteProfiles.large_field(pick,580,580)
			var dense := Compositions.resolve(recipe,580,580)
			var compressed := Compositions.resolve_rectangles(recipe,580,580)
			check(dense.boxes==compressed.boxes and dense.fixtures==compressed.fixtures,"compressed geometry and panels exactly match dense oracle")
			check(compressed.grid.size()<3000,"bounded compressed work grid")

func check_partial_retention() -> void:
	var w := LevelWorld.new(99,"P07")
	var found := false
	for z in range(-5,0):
		for x in range(-5,0):
			var anchor := Vector2i(x,z)*2
			if not w._district_layout(anchor.x,anchor.y).large: continue
			var data := w.reservation_at(anchor.x,anchor.y)
			w.prune(anchor.x+1,anchor.y+1,0)
			check(w._reservations.has(anchor),"owner retained when only far corner is in keep area")
			check(is_same(data,w.reservation_at(anchor.x+1,anchor.y+1)),"remaining corner reuses retained metadata")
			found=true
			break
		if found: break
	check(found,"negative-coordinate retention fixture found")

func check_legacy_fixture_seeds() -> void:
	for composition in ["C01","C02","P01","P02","P03","P04","P05","P06"]:
		var w := LevelWorld.new(99,composition)
		var owners := [Vector2i.ZERO]
		if composition in ["P05","P06"]:
			for z in range(-2,0):
				for x in range(-2,0):
					if w.reservation_rect(x,z).has_area(): owners.append(Vector2i(x,z))
		for owner in owners:
			for f in w.reservation_at(owner.x,owner.y).fixtures:
				var key := int(f.id.substr(f.id.rfind("c")+1))
				var ids := [owner.x,owner.y,key] if composition in ["P05","P06"] else [key]
				check(f.seed==w.channel(composition+".fixtures",ids),"legacy panel seed equals original full channel")
