class_name Compositions
## Authored Level 0 compositions. Pure data: rectangles are integer quanta of
## 0.125 m in the site frame (x east, z south, origin at the north-west
## corner), half-open [x0, z0, x1, z1). Altitudes are metres.
##
## C01 — pièce désaxée. A 12.5 × 15 m room entered from its south-west corner.
## A thick L partition attached to the west wall hides a north-west pocket and
## its exit; a free-standing yellow mass layers the east aisle. Three openings
## to the classic maze, none on a shared axis. Variants mirror the plan and
## move secondary edges by one ceiling module; the partition always stays.

const Q := 0.125
const TILE := 0.625


static func q(metres: float) -> int:
	return int(round(metres / Q))


## pick: Callable(domain: String, n: int) -> int in [0, n).
static func c01(pick: Callable, site_w: int, site_d: int) -> Dictionary:
	var mirror: bool = pick.call("template", 2) == 1
	var step := q(TILE)
	var shift := func(n: String) -> int: return (int(pick.call(n, 3)) - 1) * step
	var room := [q(2.5), q(1.25), q(15.0), q(16.25)]
	var p1_end: int = q(8.75) + shift.call("dimensions.p1")
	var p1_north: int = q(6.875) + shift.call("dimensions.p1b")
	var p2z: int = shift.call("dimensions.p2")
	var thick := q(0.625)
	var free := [
		{"name": "room", "rect": room},
		{"name": "E1", "rect": [q(3.125), room[3], q(4.875), site_d], "exit": "south"},
		{"name": "E2", "rect": [0, q(2.875), room[0], q(4.375)], "exit": "west"},
		{"name": "E3", "rect": [room[2], q(7.875), site_w, q(9.625)], "exit": "east"},
	]
	var solid := [
		# P1 masks the pocket from the entrance; P1b returns north so the pocket
		# opens only after the player walks past its end.
		{"name": "P1", "rect": [room[0], q(10.0), p1_end, q(10.0) + thick]},
		{"name": "P1b", "rect": [p1_end - thick, p1_north, p1_end, q(10.0)]},
		{"name": "P2", "rect": [q(11.875), q(3.125) + p2z, q(13.125), q(5.625) + p2z]},
	]
	# Bulkheads frame thresholds without blocking passage. B1 carries the line
	# of P1b overhead to the north wall and frames the pocket as a portal.
	var lintels := [
		{"name": "E1 head", "rect": free[1].rect, "y0": 2.25, "y1": 2.8},
		{"name": "E2 head", "rect": free[2].rect, "y0": 2.2, "y1": 2.8},
		{"name": "B1", "rect": [p1_end - thick, room[1], p1_end, p1_north], "y0": 2.3, "y1": 2.8},
	]
	# Panels replace two ceiling tiles on the world 0.625 m grid. A regular
	# room grid; panels too close to a wall or bulkhead are omitted.
	# Irregular on purpose: candidates on a loose room grid, each kept with a
	# probability and nudged by one ceiling module; the entry corner always
	# keeps light. Placement follows the references: lit areas and dark gaps.
	var fixtures := []
	for zi in 5:
		for xi in 4:
			var key := xi + zi * 4
			var entry := zi >= 3 and xi <= 1
			if not entry and pick.call("fixtures.keep.%d" % key, 100) >= 55:
				continue
			var cx := q(3.75) + xi * q(3.125) + (int(pick.call("fixtures.dx.%d" % key, 3)) - 1) * step
			var z0 := q(2.5) + zi * q(3.125) + (int(pick.call("fixtures.dz.%d" % key, 3)) - 1) * step
			fixtures.append({"rect": [cx - step, z0, cx + step, z0 + step], "key": key})
	var views := {
		"entry": {"x": q(7.5), "z": q(15.25), "yaw": 0.7, "label": "Entrée : la cloison proche masque la poche nord-ouest"},
		"reveal": {"x": q(10.625), "z": q(6.25), "yaw": -1.26, "label": "Révélation : la poche et sa sortie apparaissent après le retour de cloison"},
		"interior": {"x": q(4.0), "z": q(8.75), "yaw": 0.9, "label": "Intérieur : depuis la poche vers l'allée est et la masse jaune"},
		"east": {"x": q(13.75), "z": q(8.75), "yaw": -2.12, "label": "Contrechamp : depuis l'allée est vers l'entrée"},
	}
	if mirror:
		for list in [free, solid, lintels, fixtures]:
			for item in list:
				var r: Array = item.rect
				item.rect = [site_w - r[2], r[1], site_w - r[0], r[3]]
		for item in free:
			if item.get("exit") == "west":
				item.exit = "east"
			elif item.get("exit") == "east":
				item.exit = "west"
		for v in views.values():
			v.x = site_w - v.x
			v.yaw = -v.yaw
	return {
		"id": "C01", "name": "Pièce désaxée", "height": 2.8,
		"variant": {"mirror": mirror, "p1_end": p1_end, "p1_north": p1_north, "p2z": p2z},
		"free": free, "solid": solid, "lintels": lintels, "fixtures": fixtures,
		"views": views, "spawn": "entry", "fixture_margin": q(0.3),
	}


## Occupancy and a deterministic, non-overlapping rectangle cover of the solid
## parts of a site. Rows of equal runs merge vertically.
static func resolve(c: Dictionary, w: int, d: int) -> Dictionary:
	var grid := PackedByteArray()
	grid.resize(w * d)
	grid.fill(1)
	for f in c.free:
		grid = _paint(grid, w, d, f.rect, 0)
	for s in c.solid:
		grid = _paint(grid, w, d, s.rect, 1)
	var boxes := []
	var active := {}
	for z in d + 1:
		var runs := []
		if z < d:
			var x := 0
			while x < w:
				if grid[z * w + x] == 0:
					x += 1
					continue
				var e := x
				while e < w and grid[z * w + e] == 1:
					e += 1
				runs.append(Vector2i(x, e))
				x = e
		for key in active.keys():
			if not runs.has(key):
				var rect: Array = active[key]
				rect[3] = z
				boxes.append(rect)
				active.erase(key)
		for key in runs:
			if not active.has(key):
				active[key] = [key.x, z, key.y, 0]
	boxes.sort_custom(func(a, b): return a[1] < b[1] or (a[1] == b[1] and a[0] < b[0]))
	var overhead := PackedByteArray()
	overhead.resize(w * d)
	for l in c.lintels:
		overhead = _paint(overhead, w, d, l.rect, 1)
	var margin: int = c.fixture_margin
	var fixtures := []
	for f in c.fixtures:
		var r: Array = f.rect
		var ok := true
		for z in range(r[1] - margin, r[3] + margin):
			for x in range(r[0] - margin, r[2] + margin):
				if x < 0 or z < 0 or x >= w or z >= d or grid[z * w + x] or overhead[z * w + x]:
					ok = false
					break
			if not ok:
				break
		if ok:
			fixtures.append(f)
	return {"grid": grid, "boxes": boxes, "fixtures": fixtures}


## Packed arrays are copy-on-write values: return the painted array.
static func _paint(grid: PackedByteArray, w: int, d: int, r: Array, v: int) -> PackedByteArray:
	for z in range(maxi(0, r[1]), mini(d, r[3])):
		for x in range(maxi(0, r[0]), mini(w, r[2])):
			grid[z * w + x] = v
	return grid
