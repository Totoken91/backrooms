extends "res://tests/test_distributed_sites.gd"
## Reuse independent BFS/mesh intersection oracles; only run the P06 audit.
func run() -> void:
	var profiles := {}
	var spacings := {}
	var widths := {}
	var field_count := 0
	var sites := 0
	var fixture_ids := {}
	for seed in [0,1,7,17,42,99,1601967012,4294967295]:
		var world := LevelWorld.new(seed,"P06")
		var other := LevelWorld.new(seed,"P06")
		other.chunk_at(13,-19)
		for dz in range(-1,2):
			for dx in range(-1,2):
				var owners := []
				for z in range(dz*2,dz*2+2):
					for x in range(dx*2,dx*2+2):
						if world.reservation_rect(x,z).has_area(): owners.append(Vector2i(x,z))
				check(owners.size()==1,"P06 district budget")
				var owner: Vector2i = owners[0]
				var data := world.reservation_at(owner.x,owner.y)
				var seen := reachable(world,data,owner)
				var base := Vector2(owner)*40.0
				profiles[data.report.profile]=true
				check(signature(world,owner)==signature(other,owner),"profile independent of query order")
				for v in data.views.values():
					var p: Vector3 = v.position
					check(seen.has(Vector2i(((Vector2(p.x,p.z)-base)*4).round())),"all profile views reachable")
				for e in data.report.exits:
					var p := Vector2((e.x0+e.x1)*0.5,(e.z0+e.z1)*0.5)
					var dir := Vector2.LEFT if e.side=="west" else Vector2.RIGHT if e.side=="east" else Vector2.DOWN
					for signum in [-1,1]:
						var point := p+dir*float(signum)*1.25
						check(seen.has(Vector2i(((point-base)*4).round())),"exit seed=%s owner=%s profile=%s side=%s point=%s" % [seed,owner,data.report.profile,e.side,point])
				for f in data.fixtures:
					var id: String = str(seed)+":"+f.id
					check(not fixture_ids.has(id),"unique panels across profiles")
					fixture_ids[id]=true
					check(f.y==world.ceiling_height(floori(f.x/2.5),floori(f.z/2.5)),"profile panel height")
					check(not world.point_blocked(f.x,f.z),"profile panel outside solids")
				if data.report.profile=="pillar_field":
					field_count += 1
					var variant: Dictionary = data.report.variant
					spacings[variant.spacing]=true
					widths[variant.half_width]=true
					var pillars: Array = data.report.assembly.pillars
					var positions := {}
					for item in pillars:
						var p := Vector2(data.report.site.position)+Vector2(item.center)*Compositions.Q
						check(world.circle_blocked(p.x,p.y,0.3),"pillar is an actual collision volume")
						positions[item.center]=true
					var count := 0
					for z in range(40,201,variant.spacing):
						for x in range(40,201,variant.spacing):
							check(positions.has(Vector2i(x,z)),"regular complete lattice")
							count += 1
					check(count==pillars.size() and count in [25,36],"field pillar count")
					var origin: Vector2 = data.report.site.position
					check(world.ceiling_height(floori((origin.x+1.25)/2.5),floori((origin.y+3.75)/2.5))==2.2,"compressed threshold")
					check(world.ceiling_height(floori((origin.x+8.75)/2.5),floori((origin.y+8.75)/2.5))==4.8,"high field roof")
					if owner==Vector2i.ZERO and seed in [7,99]:
						await check_field_mesh(world,data,owner)
				var saved := signature(world,owner)
				world.prune(100,-100,2)
				check(saved==signature(world,owner),"profile survives eviction identically")
				sites += 1
	check(profiles.size()==2,"both architectural profiles generated")
	check(spacings.size()==2 and widths.size()==2,"both lattice scales and column widths")
	if failures==0: print("PASS: P06 profiles — ",sites," sites, ",field_count," fields, 25/36 real pillars, two scales, connected views/exits, independent order, eviction and real threshold meshes")
	quit(1 if failures else 0)

func check_field_mesh(world: LevelWorld,data: Dictionary,owner: Vector2i) -> void:
	var chunk := Chunk.new()
	root.add_child(chunk)
	var materials := {}
	for key in ["wall","floor","ceiling","skirting"]: materials[key]=StandardMaterial3D.new()
	await chunk.setup(world,owner,materials,PlaneMesh.new())
	var mesh: Mesh = chunk.get_node("Geometry").mesh
	var origin: Vector2 = data.report.site.position
	var step := Vector3(origin.x+2.5,3.5,origin.y+3.75)
	var hit = mesh_hit(mesh,step-Vector3.RIGHT*0.5,step+Vector3.RIGHT*0.5)
	check(hit!=null and hit.distance_to(step)<0.001,"real step closes high/low threshold")
	step.y=1.52
	check(mesh_hit(mesh,step-Vector3.RIGHT*0.5,step+Vector3.RIGHT*0.5)==null,"real threshold walkable")
	chunk.queue_free()
	await process_frame
