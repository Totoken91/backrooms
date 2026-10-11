class_name PromenadeAssembler
extends RefCounted
## Bounded assemblers: P02 four-module loop; P03 varied sizes and branching.
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
	return _build(pick, site_w, site_d, false)

static func build_varied(pick: Callable, site_w: int, site_d: int) -> Dictionary:
	return _build(pick, site_w, site_d, true)

static func _build(pick: Callable, site_w: int, site_d: int, varied: bool) -> Dictionary:
	var order := ["enfilade", "pillars", "return", "empty"]
	for i in range(order.size() - 1, 0, -1):
		var j: int = pick.call("order.%d" % i, i + 1)
		var swap: String = order[i]
		order[i] = order[j]
		order[j] = swap
	var left: int = (80 if pick.call("sizes.left", 2) == 0 else 120) if varied else 100
	var right := 200 - left
	var offsets := [Vector2i(0, 0), Vector2i(left, 0), Vector2i(0, 80), Vector2i(left, 80)]
	if varied: offsets.append(Vector2i(left, 160))
	var modules := []
	var free := []
	var solid := []
	var regions := [{"rect": [0, 0, site_w, site_d], "height": 3.2}]
	var views := {"entry": {"x": 30, "z": 208, "yaw": 0.0, "label": "Entrée basse vers le parcours assemblé"}}
	var report := []
	for i in offsets.size():
		var variant: int = pick.call("module.%d.variant" % i, 2)
		var family: String = order[i] if i < 4 else "empty"
		var m := RoomFamilies.make_sized(family, variant, left if i in [0,2] else right, 60 if i == 4 else 80) if varied else RoomFamilies.make(family, variant)
		if i == 4:
			m.height = 2.2
			for port in m.ports.values(): port.ceiling = 2.2
			m.view.label = "Branche basse en impasse"
		modules.append(m)
		for f in m.free: free.append(shifted(f, offsets[i]))
		for s in m.solid: solid.append(shifted(s, offsets[i]))
		regions.append({"rect": [offsets[i].x, offsets[i].y, offsets[i].x + m.width, offsets[i].y + m.depth], "height": m.height})
		var v: Dictionary = m.view.duplicate()
		v.x += offsets[i].x
		v.z += offsets[i].y
		views[order[i] if i < 4 else "alcove"] = v
		report.append({"slot": i, "family": family if i < 4 else "alcove", "variant": variant, "origin": offsets[i], "height": m.height, "width": m.width, "depth": m.depth})
	var links := []
	# Loop: NW -> NE -> SE -> SW -> NW. No unattached opening is carved.
	var edges := [[0, "east", 1, "west"], [1, "south", 3, "north"], [3, "west", 2, "east"], [2, "north", 0, "south"]]
	var topology: int = pick.call("topology", 3) if varied else 0
	if varied:
		if topology == 1: edges.remove_at(0)
		elif topology == 2: edges.remove_at(3)
		edges.append([3,"south",4,"north"])
	for edge in edges:
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
	return {"id": "P03" if varied else "P02", "name": "Parcours ramifié" if varied else "Promenade assemblée", "height": 4.8,
		"variant": {"order": order, "topology": topology, "left_width": left}, "assembly": {"modules": report, "links": links},
		"free": free, "solid": solid, "lintels": [], "fixtures": fixtures,
		"views": views, "spawn": "entry", "fixture_margin": 2, "ceiling_regions": regions}
