class_name SiteProfiles
extends RefCounted
## P06: a whole-site identity, independent from the six-room assembler.
## No arches. The pillar field is a bounded pilot for future multi-chunk fields.
static func pillar_field(pick: Callable, width: int, depth: int) -> Dictionary:
	var spacing: int = [32,40][pick.call("pillars.spacing",2)]
	var half: int = [3,4][pick.call("pillars.width",2)]
	var solid := []
	var pillars := []
	for z in range(40,201,spacing):
		for x in range(40,201,spacing):
			var rect := [x-half,z-half,x+half,z+half]
			solid.append({"rect":rect})
			pillars.append({"rect":rect,"center":Vector2i(x,z)})
	var fixtures := []
	for z in range(depth/20):
		for x in range(width/20):
			var key := x+z*64
			if pick.call("fixtures.hole.%d" % key,100)<8: continue
			var cx := x*20+10
			var cz := z*20+10
			fixtures.append({"rect":[cx-3,cz-3,cx+3,cz+3],"key":key})
	return {
		"id":"P06","name":"Champ de piliers","profile":"pillar_field",
		"height":4.8,"variant":{"spacing":spacing,"half_width":half},
		"free":[
			{"name":"hall","rect":[30,10,width-10,depth-10]},
			{"name":"E1","rect":[143,depth-10,157,depth],"exit":"south"},
			{"name":"E2","rect":[0,23,30,37],"exit":"west"},
			{"name":"E3","rect":[width-10,23,width,37],"exit":"east"}],
		"solid":solid,"lintels":[],"fixtures":fixtures,"fixture_margin":2,
		"assembly":{"profile":"pillar_field","pillars":pillars,"links":[]},
		"ceiling_regions":[
			{"rect":[0,0,width,depth],"height":4.8},
			{"rect":[0,20,20,40],"height":2.2}],
		"views":{
			"entry":{"x":14,"z":30,"yaw":PI/2,"label":"Passage bas vers le champ"},
			"reveal":{"x":32,"z":30,"yaw":1.35,"label":"Ouverture sur la trame"},
			"pillars":{"x":54,"z":60,"yaw":1.15,"label":"Profondeur du champ"},
			"return":{"x":188,"z":188,"yaw":-PI/4,"label":"Contrechamp"}},
		"spawn":"entry"}
