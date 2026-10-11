extends SceneTree
## Validate the actual player-radius navigation graph, including each loop arm
## independently. No path may escape the site to bypass its partitions.
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

func run() -> void:
	for seed in [0, 1, 2, 7, 17, 99, 65535, 4294967295]:
		var w := LevelWorld.new(seed, "P01")
		check(w.site == Rect2i(2, 2, 11, 11), "larger reservation")
		var bounds: Rect2 = w.composition_report.site
		var seen := reachable(w)
		for key in w.views:
			var p: Vector3 = w.views[key].position
			check(seen.has(Vector2i(((Vector2(p.x, p.z) - bounds.position) * 4).round())), "reachable view %s seed %d" % [key, seed])
		for e in w.composition_report.exits:
			var p := Vector2((e.x0 + e.x1) / 2, (e.z0 + e.z1) / 2)
			if e.side == "west": p.x = e.x0 + 0.5
			elif e.side == "east": p.x = e.x1 - 0.5
			else: p.y = e.z1 - 0.5
			check(seen.has(Vector2i(((p - bounds.position) * 4).round())), "reachable exit %s" % e.name)
			if e.side == "west": p.x = e.x0 - 1.25
			elif e.side == "east": p.x = e.x1 + 1.25
			else: p.y = e.z1 + 1.25
			check(not w.circle_blocked(p.x, p.y, 0.3), "exit joins maze %s" % e.name)
		# Either arm alone must connect the entire hall to the enfilade.
		for z in [2.875, 12.875]:
			var without_arm := reachable(w, Rect2(bounds.position + Vector2(9.375, z), Vector2(0.625, 1.75)))
			var p: Vector3 = w.views.pillars.position
			check(without_arm.has(Vector2i(((Vector2(p.x, p.z) - bounds.position) * 4).round())), "loop survives closed arm %s" % z)
		check(w.segment_blocked(9, 24, 9, 8), "staggered thresholds hide forward vista")
		for z in [3.75, 8.75, 13.75]:
			for x in [13.75, 18.75, 23.75]:
				check(w.circle_blocked(5 + x, 5 + z, 0.3), "pillar collision")
		for z in range(w.site.position.y, w.site.end.y):
			for x in range(w.site.position.x, w.site.end.x):
				check(w.chunk_at(0, 0)[z * 16 + x] == 2, "maze never overwrites reservation")
				for f in w.cell_fixtures(x, z):
					check(f.y == w.ceiling_height(x, z), "panel altitude")
					for p in [Vector2(f.x0, f.z0), Vector2(f.x1, f.z1)]:
						check(not w.point_blocked(p.x, p.y), "panel footprint avoids pillars")
		check(w.ceiling_height(3, 12) == 2.2 and w.ceiling_height(3, 7) == 3.2 and w.ceiling_height(7, 4) == 4.8, "three ceiling registers")
	if failures == 0:
		print("PASS: P01 promenade — 8 seeds, player-radius reachability, 3 maze exits, independent loop arms, masked vista, 9 pillar collisions, ceiling registers and panel clearance")
	quit(1 if failures else 0)
