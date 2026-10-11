class_name RoomFamilies
extends RefCounted
## Authored local modules, expressed in Compositions.Q units. Ports belong to
## the 12.5 x 10 m reservation, not to a mesh. The assembler opens only used ports.
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
		"height": height, "ports": ports, "view": view}

static func open_port(module: Dictionary, side: String) -> Dictionary:
	var p: Dictionary = module.ports[side]
	var at: Vector2i = p.at
	var r: Array
	match side:
		"north": r = [at.x - HALF_OPENING, 0, at.x + HALF_OPENING, 10]
		"south": r = [at.x - HALF_OPENING, 70, at.x + HALF_OPENING, DEPTH]
		"west": r = [0, at.y - HALF_OPENING, 10, at.y + HALF_OPENING]
		_: r = [90, at.y - HALF_OPENING, WIDTH, at.y + HALF_OPENING]
	return {"rect": r}
