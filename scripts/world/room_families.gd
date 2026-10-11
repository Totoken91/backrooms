class_name RoomFamilies
extends RefCounted
## Authored local modules, expressed in Compositions.Q units. Ports belong to
## base 12.5 x 10 m reservation; resized/shaped modules retain anchor contracts.
## The assembler opens only used ports.
const WIDTH := 100
const DEPTH := 80
const HALF_OPENING := 7 # 1.75 m clear width

static func make(family: String, variant: int) -> Dictionary:
	var free := [{"rect": [10, 10, 90, 70]}]
	var solid := []
	var height := 3.2
	var view := {"x": 30, "z": 55, "yaw": 0.0, "label": family}
	match family:
		"enfilade":
			var opening := 23 if variant == 0 else 63
			solid = [{"rect": [10, 35, opening, 40]}, {"rect": [opening + 14, 35, 90, 40]}]
			view = {"x": opening + 7, "z": 58, "yaw": 0.0, "label": "Seuil décalé"}
		"pillars":
			height = 4.8
			for z in [30, 50]:
				for x in [30, 70]:
					solid.append({"rect": [x - 4, z - 4, x + 4, z + 4]})
			view = {"x": 50, "z": 62, "yaw": 0.3, "label": "Salle haute à piliers"}
		"return":
			# A thick return masks the central vista but leaves both ways around.
			var z := 20 if variant == 0 else 35
			solid = [{"rect": [47, z, 53, z + 25]}]
			view = {"x": 30, "z": 58, "yaw": 0.45, "label": "Pièce désaxée"}
		"empty":
			view = {"x": 50, "z": 58, "yaw": -0.45, "label": "Respiration vide"}
	var ports := {}
	for side in ["north", "south", "east", "west"]:
		var at: Vector2i
		match side:
			"north": at = Vector2i(30, 0)
			"south": at = Vector2i(30, DEPTH)
			"west": at = Vector2i(0, 30)
			_: at = Vector2i(WIDTH, 30)
		ports[side] = {"at": at, "side": side, "width": HALF_OPENING * 2, "floor": 0.0, "ceiling": height, "clearance": 1.9}
	return {"family": family, "variant": variant, "free": free, "solid": solid,
		"height": height, "width": WIDTH, "depth": DEPTH, "ports": ports, "view": view}

## Preserve a 1.25 m perimeter and the 1.75 m connection contract while
## resizing the interior. Roof boundaries remain whole 2.5 m cells.
static func make_sized(family: String, variant: int, width: int, depth: int) -> Dictionary:
	var m := make(family, variant)
	var remap := func(value: int, original: int, target: int) -> int:
		return roundi(10.0 + (value - 10.0) * (target - 20.0) / (original - 20.0))
	for list in [m.free, m.solid]:
		for item in list:
			var r: Array = item.rect
			item.rect = [remap.call(r[0], WIDTH, width), remap.call(r[1], DEPTH, depth), remap.call(r[2], WIDTH, width), remap.call(r[3], DEPTH, depth)]
	m.view.x = remap.call(m.view.x, WIDTH, width)
	m.view.z = remap.call(m.view.z, DEPTH, depth)
	m.width = width
	m.depth = depth
	m.ports.east.at.x = width
	m.ports.south.at.y = depth
	return m

static func open_port(module: Dictionary, side: String) -> Dictionary:
	var p: Dictionary = module.ports[side]
	var at: Vector2i = p.at
	var r: Array
	match side:
		"north": r = [at.x - HALF_OPENING, 0, at.x + HALF_OPENING, 10]
		"south": r = [at.x - HALF_OPENING, module.depth - 10, at.x + HALF_OPENING, module.depth]
		"west": r = [0, at.y - HALF_OPENING, 10, at.y + HALF_OPENING]
		_: r = [module.width - 10, at.y - HALF_OPENING, module.width, at.y + HALF_OPENING]
	return {"rect": r}

## Orthogonal footprints with all four contracted anchors on connected arms.
## These are unions of rooms/aisles, not obstacles scattered inside a rectangle.
static func make_shaped(family: String, variant: int, width: int, depth: int) -> Dictionary:
	if family not in ["bend", "tee", "cross"]:
		var rectangular := make_sized(family, variant, width, depth)
		rectangular.shape = "rectangle"
		# Compression must not move an internal partition across a port mouth.
		# Reserve a short vestibule around each anchor before opening used ports.
		for cut in [[23,0,37,20],[23,depth-20,37,depth],[0,23,20,37],[width-20,23,width,37]]:
			var trimmed := []
			for item in rectangular.solid:
				for rect in subtract_rect(item.rect,cut): trimmed.append({"rect":rect})
			rectangular.solid = trimmed
		return rectangular
	var m := make_sized("empty", variant, width, depth)
	m.family = family
	m.shape = family
	m.solid = []
	match family:
		"bend":
			m.free = [{"rect":[10,10,width-10,44]}, {"rect":[10,10,44,depth-10]}]
			m.view = {"x":30,"z":depth-20,"yaw":0.0,"label":"Pièce en L, révélation à angle droit"}
			m.height = 2.2
		"tee":
			m.free = [{"rect":[10,10,width-10,44]}, {"rect":[23,10,37,depth-10]}]
			m.view = {"x":30,"z":depth-20,"yaw":0.0,"label":"Galerie en T, branche étroite"}
		"cross":
			m.free = [{"rect":[10,23,width-10,37]}, {"rect":[23,10,37,depth-10]}, {"rect":[16,16,44,44]}]
			m.view = {"x":30,"z":40,"yaw":0.0,"label":"Carrefour resserré"}
			m.height = 2.2
	for port in m.ports.values(): port.ceiling = m.height
	return m

static func subtract_rect(r: Array, cut: Array) -> Array:
	var x0: int = maxi(r[0],cut[0])
	var z0: int = maxi(r[1],cut[1])
	var x1: int = mini(r[2],cut[2])
	var z1: int = mini(r[3],cut[3])
	if x0 >= x1 or z0 >= z1: return [r]
	var result := []
	for piece in [[r[0],r[1],x0,r[3]],[x1,r[1],r[2],r[3]],[x0,r[1],x1,z0],[x0,z1,x1,r[3]]]:
		if piece[0] < piece[2] and piece[1] < piece[3]: result.append(piece)
	return result
