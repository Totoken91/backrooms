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
		{"name": "E1 head", "rect": free[1].rect, "y0": 2.25, "y1": LevelWorld.HEIGHT},
		{"name": "E2 head", "rect": free[2].rect, "y0": 2.2, "y1": LevelWorld.HEIGHT},
		{"name": "B1", "rect": [p1_end - thick, room[1], p1_end, p1_north], "y0": 2.3, "y1": LevelWorld.HEIGHT},
	]
	# Panels: square 2 × 2 ft troffers, one centred in each 2.5 m cell of the
	# world grid (the site origin and width are whole cells, mirror included),
	# like the references: a regular, symmetric grid. A few are missing; panels
	# too close to a wall or bulkhead are omitted (resolve).
	var fixtures := []
	var cell := q(2.5)
	for zi in range(0, site_d / cell):
		for xi in range(0, site_w / cell):
			var cx := xi * cell + cell / 2
			var cz := zi * cell + cell / 2
			if cx < room[0] or cx > room[2] or cz < room[1] or cz > room[3]:
				continue
			var key := xi + zi * 64
			if pick.call("fixtures.hole.%d" % key, 100) < 8:
				continue
			fixtures.append({"rect": [cx - 3, cz - 3, cx + 3, cz + 3], "key": key})
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
		"id": "C01", "name": "Pièce désaxée", "height": LevelWorld.HEIGHT,
		"variant": {"mirror": mirror, "p1_end": p1_end, "p1_north": p1_north, "p2z": p2z},
		"free": free, "solid": solid, "lintels": lintels, "fixtures": fixtures,
		"views": views, "spawn": "entry", "fixture_margin": q(0.3),
	}


## C02 pilot: a low, narrow entry opens tangentially into a taller room.
## Height regions align with whole world cells so ceiling tiles never straddle
## a height change. This is a finite authored composition, not random tall cells.
static func c02(pick: Callable, site_w: int, site_d: int) -> Dictionary:
	var room := [q(2.5), q(1.25), q(15.0), q(10.0)]
	var free := [
		{"name": "room", "rect": room},
		{"name": "E1", "rect": [q(3.125), room[3], q(4.875), site_d], "exit": "south"},
		{"name": "E2", "rect": [0, q(2.875), room[0], q(4.375)], "exit": "west"},
		{"name": "E3", "rect": [room[2], q(7.875), site_w, q(9.625)], "exit": "east"},
	]
	var solid := [{"name": "return", "rect": [q(8.75), q(5.0), q(9.375), room[3]]}]
	var fixtures := []
	var cell := q(LevelWorld.CELL)
	for zi in range(site_d / cell):
		for xi in range(site_w / cell):
			var cx := xi * cell + cell / 2
			var cz := zi * cell + cell / 2
			var key := xi + zi * 64
			if zi == 4 or pick.call("fixtures.hole.%d" % key, 100) < 12:
				continue
			fixtures.append({"rect": [cx - 3, cz - 3, cx + 3, cz + 3], "key": key})
	var views := {
		"entry": {"x": q(4.0), "z": q(16.0), "yaw": 0.0, "label": "Passage bas : ouverture en retrait"},
		"reveal": {"x": q(4.0), "z": q(9.25), "yaw": 0.8, "label": "Révélation : plafond haut et profondeur masquée"},
		"interior": {"x": q(11.25), "z": q(3.75), "yaw": -2.4, "label": "Intérieur : contrechamp derrière le retour de cloison"},
		"east": {"x": q(13.75), "z": q(8.75), "yaw": -1.6, "label": "Allée est : retour de cloison"},
	}
	var mirror: bool = pick.call("template", 2) == 1
	if mirror:
		for list in [free, solid, fixtures]:
			for item in list:
				var r: Array = item.rect
				item.rect = [site_w - r[2], r[1], site_w - r[0], r[3]]
		for item in free:
			if item.get("exit") == "west": item.exit = "east"
			elif item.get("exit") == "east": item.exit = "west"
		for v in views.values():
			v.x = site_w - v.x
			v.yaw = -v.yaw
	return {
		"id": "C02", "name": "Compression et ouverture", "height": 4.8,
		"variant": {"mirror": mirror}, "free": free, "solid": solid,
		"lintels": [], "fixtures": fixtures, "views": views, "spawn": "entry",
		"fixture_margin": q(0.15), "ceiling_regions": [
			{"rect": [0, 0, site_w, q(10.0)], "height": 4.8},
			{"rect": [0, q(10.0), site_w, site_d], "height": 2.2},
		],
	}


## P01: a finite promenade, not a procedural assembler. Three staggered
## thresholds lead to a tall pillar hall, joined at both ends to form a loop.
## All roofs remain cell-aligned; the two earlier pilots stay untouched.
static func p01(pick: Callable, site_w: int, site_d: int) -> Dictionary:
	var free := [
		{"name": "enfilade", "rect": [q(1.25), q(1.25), q(9.375), q(20)]},
		{"name": "hall", "rect": [q(10), q(1.25), q(26.25), q(15)]},
		{"name": "north_link", "rect": [q(9.375), q(2.875), q(10), q(4.625)]},
		{"name": "south_link", "rect": [q(9.375), q(12.875), q(10), q(14.625)]},
		{"name": "E1", "rect": [q(3.125), q(20), q(4.875), site_d], "exit": "south"},
		{"name": "E2", "rect": [0, q(3.125), q(1.25), q(4.875)], "exit": "west"},
		{"name": "E3", "rect": [q(26.25), q(13.125), site_w, q(14.875)], "exit": "east"},
	]
	var solid := []
	for spec in [[6.25, 3.125], [11.25, 6.875], [16.25, 3.125]]:
		var z: float = spec[0]
		var opening: float = spec[1]
		solid.append({"rect": [q(1.25), q(z), q(opening), q(z + 0.625)]})
		solid.append({"rect": [q(opening + 1.75), q(z), q(9.375), q(z + 0.625)]})
	for z in [3.75, 8.75, 13.75]:
		for x in [13.75, 18.75, 23.75]:
			solid.append({"rect": [q(x - 0.625), q(z - 0.625), q(x + 0.625), q(z + 0.625)]})
	var fixtures := []
	var cell := q(LevelWorld.CELL)
	for zi in range(site_d / cell):
		for xi in range(site_w / cell):
			var key := xi + zi * 64
			# A sparse, reproducible failure pattern; no random blackout wall.
			if pick.call("fixtures.hole.%d" % key, 100) < 8: continue
			var cx := xi * cell + cell / 2
			var cz := zi * cell + cell / 2
			fixtures.append({"rect": [cx - 3, cz - 3, cx + 3, cz + 3], "key": key})
	return {
		"id": "P01", "name": "Enfilades et salle à piliers", "height": 4.8,
		"variant": {"layout": "composed_loop"}, "free": free, "solid": solid,
		"lintels": [], "fixtures": fixtures, "spawn": "entry", "fixture_margin": q(0.25),
		"views": {
			"entry": {"x": q(4), "z": q(26), "yaw": 0.0, "label": "Passage bas vers la première pièce"},
			"enfilade": {"x": q(4), "z": q(19), "yaw": 0.0, "label": "Seuils décalés : la suite reste masquée"},
			"reveal": {"x": q(8), "z": q(13.75), "yaw": PI / 2, "label": "Ouverture latérale sur les piliers"},
			"pillars": {"x": q(11.25), "z": q(6.25), "yaw": 1.15, "label": "Répétition et profondeur dans la salle haute"},
			"return": {"x": q(25), "z": q(11.25), "yaw": -1.2, "label": "Contrechamp vers les deux liaisons"},
		},
		"ceiling_regions": [
			{"rect": [0, 0, site_w, site_d], "height": 3.2},
			{"rect": [q(10), 0, site_w, q(15)], "height": 4.8},
			{"rect": [0, q(20), site_w, site_d], "height": 2.2},
		],
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
