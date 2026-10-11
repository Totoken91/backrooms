class_name PromenadeAssembler
extends RefCounted
## First bounded assembler: seeded family permutation on a four-module loop.
## No global RNG, rejection loop or dependency on chunk visitation order.
const OPPOSITE := {"north": "south", "south": "north", "east": "west", "west": "east"}

static func compatible(a: Dictionary, b: Dictionary) -> bool:
	return OPPOSITE.get(a.side, "") == b.side and a.width == b.width and a.width * Compositions.Q >= 0.6 and a.floor == b.floor and minf(a.ceiling - a.floor, b.ceiling - b.floor) >= maxf(a.clearance, b.clearance)

static func shifted(item: Dictionary, offset: Vector2i) -> Dictionary:
	var result := item.duplicate(true)
	var r: Array = result.rect
	result.rect = [r[0] + offset.x, r[1] + offset.y, r[2] + offset.x, r[3] + offset.y]
	return result

static func build(pick: Callable, site_w: int, site_d: int) -> Dictionary:
	var order := ["enfilade", "pillars", "return", "empty"]
	for i in range(order.size() - 1, 0, -1):
		var j: int = pick.call("order.%d" % i, i + 1)
		var swap: String = order[i]
		order[i] = order[j]
		order[j] = swap
	var offsets := [Vector2i(0, 0), Vector2i(100, 0), Vector2i(0, 80), Vector2i(100, 80)]
	var modules := []
	var free := []
	var solid := []
	var regions := [{"rect": [0, 0, site_w, site_d], "height": 3.2}]
	var views := {"entry": {"x": 30, "z": 208, "yaw": 0.0, "label": "Entrée basse vers le parcours assemblé"}}
	var report := []
	for i in 4:
		var variant: int = pick.call("module.%d.variant" % i, 2)
		var m := RoomFamilies.make(order[i], variant)
		modules.append(m)
		for f in m.free: free.append(shifted(f, offsets[i]))
		for s in m.solid: solid.append(shifted(s, offsets[i]))
		regions.append({"rect": [offsets[i].x, offsets[i].y, offsets[i].x + 100, offsets[i].y + 80], "height": m.height})
		var v: Dictionary = m.view.duplicate()
		v.x += offsets[i].x
		v.z += offsets[i].y
		views[order[i]] = v
		report.append({"slot": i, "family": order[i], "variant": variant, "origin": offsets[i], "height": m.height})
	var links := []
	# Loop: NW -> NE -> SE -> SW -> NW. No unattached opening is carved.
	for edge in [[0, "east", 1, "west"], [1, "south", 3, "north"], [3, "west", 2, "east"], [2, "north", 0, "south"]]:
		var a: int = edge[0]
		var b: int = edge[2]
		var pa: Dictionary = modules[a].ports[edge[1]]
		var pb: Dictionary = modules[b].ports[edge[3]]
		assert(compatible(pa, pb), "Incompatible room ports")
		assert(pa.at + offsets[a] == pb.at + offsets[b], "Room ports do not meet")
		free.append(shifted(RoomFamilies.open_port(modules[a], edge[1]), offsets[a]))
		free.append(shifted(RoomFamilies.open_port(modules[b], edge[3]), offsets[b]))
		links.append({"a": a, "b": b, "side_a": edge[1], "side_b": edge[3], "at": pa.at + offsets[a], "width": pa.width, "floor": pa.floor, "ceil_a": pa.ceiling, "ceil_b": pb.ceiling})
	# Three outside exits retain the maze's odd-cell alignment.
	for ext in [[2, "south"], [0, "west"], [3, "east"]]:
		free.append(shifted(RoomFamilies.open_port(modules[ext[0]], ext[1]), offsets[ext[0]]))
	free.append({"name": "E1", "rect": [23, 160, 37, site_d], "exit": "south"})
	free.append({"name": "E2", "rect": [0, 23, 10, 37], "exit": "west"})
	free.append({"name": "E3", "rect": [200, 103, site_w, 117], "exit": "east"})
	regions.append({"rect": [0, 160, site_w, site_d], "height": 2.2})
	var fixtures := []
	for zi in range(site_d / 20):
		for xi in range(site_w / 20):
			var key := xi + zi * 64
			if pick.call("fixtures.hole.%d" % key, 100) < 8: continue
			var cx := xi * 20 + 10
			var cz := zi * 20 + 10
			fixtures.append({"rect": [cx - 3, cz - 3, cx + 3, cz + 3], "key": key})
	return {"id": "P02", "name": "Promenade assemblée", "height": 4.8,
		"variant": {"order": order}, "assembly": {"modules": report, "links": links},
		"free": free, "solid": solid, "lintels": [], "fixtures": fixtures,
		"views": views, "spawn": "entry", "fixture_margin": 2, "ceiling_regions": regions}
