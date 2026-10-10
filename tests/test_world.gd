extends SceneTree
## Generator invariants. Run: godot --headless --path . --script res://tests/test_world.gd

const CELL := LevelWorld.CELL
const CHUNK := LevelWorld.CHUNK
var failures := 0


func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: ", message)


func digest(w: LevelWorld, x0: int, z0: int, x1: int, z1: int) -> String:
	var parts := PackedStringArray()
	for z in range(z0, z1):
		for x in range(x0, x1):
			for b in w.cell_boxes(x, z):
				parts.append("%s:%s:%s:%s:%s:%s:%s" % [b.id, b.x0, b.z0, b.x1, b.z1, b.y0, b.y1])
			for f in w.cell_fixtures(x, z):
				parts.append("%s:%s:%s:%d" % [f.id, f.x0, f.z0, f.seed])
	return "|".join(parts).sha256_text()


func reach(w: LevelWorld, from: Vector3, radius: float, bounds: Rect2) -> Callable:
	var step := 0.125
	var nx := int(round(bounds.size.x / step))
	var nz := int(round(bounds.size.y / step))
	var seen := PackedByteArray()
	seen.resize(nx * nz)
	var start := Vector2i(int(round((from.x - bounds.position.x) / step)), int(round((from.z - bounds.position.y) / step)))
	var queue: Array[Vector2i] = [start]
	seen[start.y * nx + start.x] = 1
	var i := 0
	while i < queue.size():
		var p := queue[i]
		i += 1
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = p + d
			if n.x < 0 or n.y < 0 or n.x >= nx or n.y >= nz or seen[n.y * nx + n.x]:
				continue
			if w.circle_blocked(bounds.position.x + n.x * step, bounds.position.y + n.y * step, radius):
				continue
			seen[n.y * nx + n.x] = 1
			queue.append(n)
	return func(x: float, z: float) -> bool:
		var a := int(round((x - bounds.position.x) / step))
		var b := int(round((z - bounds.position.y) / step))
		return a >= 0 and b >= 0 and a < nx and b < nz and seen[b * nx + a] == 1


func _init() -> void:
	var started := Time.get_ticks_msec()
	var seeds := [0, 1, 2, 7, 42, 65535, 2147483648, 4294967295, 2654435761, 1013904223, 123456789, 3735928559]
	var mirrors := {}
	for seed in seeds:
		var a := LevelWorld.new(seed)
		var b := LevelWorld.new(seed)
		# Order independence of cells, boxes and fixtures, negative chunks too.
		var coords := []
		for z in range(-2, 3):
			for x in range(-2, 3):
				coords.append(Vector2i(x, z))
		var expected := {}
		for c in coords:
			expected[c] = a.chunk_at(c.x, c.y)
		coords.reverse()
		for c in coords:
			check(b.chunk_at(c.x, c.y) == expected[c], "chunk depends on load order (seed %d)" % seed)
		check(digest(a, -12, -12, 28, 28) == digest(b, -12, -12, 28, 28), "boxes depend on query order")
		for c in coords:
			var cells := a.chunk_at(c.x, c.y)
			var first := -1
			var open := 0
			for k in cells.size():
				if cells[k] == 0:
					open += 1
					if first < 0:
						first = k
			var seen := {first: true}
			var queue := [first]
			var qi := 0
			while qi < queue.size():
				var n: int = queue[qi]
				qi += 1
				for d in LevelWorld.DIRS:
					var x: int = n % CHUNK + d.x
					var z: int = n / CHUNK + d.y
					var j := z * CHUNK + x
					if x >= 0 and z >= 0 and x < CHUNK and z < CHUNK and cells[j] == 0 and not seen.has(j):
						seen[j] = true
						queue.append(j)
			check(seen.size() == open, "disconnected maze in chunk %s (seed %d)" % [c, seed])
			for dir in [Vector2i(1, 0), Vector2i(0, 1)]:
				var joined := false
				for n in CHUNK:
					var x: int = c.x * CHUNK + (CHUNK - 1 if dir.x else n)
					var z: int = c.y * CHUNK + (CHUNK - 1 if dir.y else n)
					if a.is_open(x, z) and a.is_open(x + dir.x, z + dir.y):
						joined = true
				check(joined, "chunks %s must share a traversable edge" % c)
		mirrors[a.composition_report.variant.mirror] = true
		# C01: spawn clear, exits reachable at the body radius and 1.1 m width.
		var s: Vector3 = a.spawn.position
		check(not a.circle_blocked(s.x, s.z, 1.0), "spawn needs 1 m of clearance")
		var site: Rect2 = a.composition_report.site
		var bounds := site.grow(CELL)
		for radius in [0.22, 0.55]:
			var ok := reach(a, s, radius, bounds)
			for e in a.composition_report.exits:
				var cx: float = e.x0 - CELL / 2 if e.side == "west" else (e.x1 + CELL / 2 if e.side == "east" else (e.x0 + e.x1) / 2)
				var cz: float = e.z1 + CELL / 2 if e.side == "south" else (e.z0 + e.z1) / 2
				var cell := Vector2i(floori(cx / CELL), floori(cz / CELL))
				check(a.is_open(cell.x, cell.y) and posmod(cell.x, 2) == 1 and posmod(cell.y, 2) == 1, "exit %s must face an odd maze cell" % e.name)
				var any := false
				for dz in range(-4, 5):
					for dx in range(-4, 5):
						if ok.call(cx + dx * 0.125, cz + dz * 0.125):
							any = true
				check(any, "exit %s unreachable at radius %s (seed %d)" % [e.name, radius, seed])
		var e2: Dictionary = a.composition_report.exits.filter(func(e): return e.name == "E2")[0]
		check(a.segment_blocked(s.x, s.z, (e2.x0 + e2.x1) / 2, (e2.z0 + e2.z1) / 2), "E2 visible from the entry")
		for z in range(4):
			for x in range(10):
				for f in a.cell_fixtures(x, z):
					for v in [f.x0, f.z0, f.x1, f.z1]:
						check(absf(v / 0.625 - round(v / 0.625)) < 1e-6, "panel off the ceiling grid")
	check(mirrors.size() == 2, "both orientations occur")
	var w := LevelWorld.new(99)
	for seg in [[-30.3, -12.1, -14.6, -27.9], [-3.1, 2.2, 20.4, 9.9], [1.1, 1.1, 1.1, -40.0]]:
		check(w.segment_blocked(seg[0], seg[1], seg[2], seg[3]) == w.segment_blocked(seg[2], seg[3], seg[0], seg[1]), "visibility must be symmetric")
	check(Hashing.channel(5, 1, "x", [-3, 7]) != Hashing.channel(5, 1, "x", [3, 7]), "negative ids hash distinctly")
	if failures == 0:
		print("PASS: world — %d seeds, order independence, connected maze, C01 exits and masking, panel grid, symmetric visibility (%d ms)" % [seeds.size(), Time.get_ticks_msec() - started])
	quit(1 if failures else 0)
