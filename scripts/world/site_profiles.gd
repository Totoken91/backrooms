class_name SiteProfiles
extends RefCounted
## P06 compact and P07 multi-chunk pillar fields, independent from the
## six-room assembler. No arches. All geometry remains axis-aligned.
static func pillar_field(pick: Callable, width: int, depth: int, compact_holes := false) -> Dictionary:
	var spacing: int = [32,40][pick.call("pillars.spacing",2)]
	var half: int = [3,4][pick.call("pillars.width",2)]
	var solid := []
	var pillars := []
	for z in range(40,depth-19,spacing):
		for x in range(40,width-19,spacing):
			var rect := [x-half,z-half,x+half,z+half]
			solid.append({"rect":rect})
			pillars.append({"rect":rect,"center":Vector2i(x,z)})
	var fixtures := []
	var holes_base: int = pick.call("fixtures.holes",0x7fffffff) if compact_holes else 0
	for z in range(depth/20):
		for x in range(width/20):
			var key := x+z*64
			var missing: int = Hashing.mix(holes_base^key)%100 if compact_holes else pick.call("fixtures.hole.%d" % key,100)
			if missing<8: continue
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

## Same global lattice across four chunks. The 72.5m outer site keeps odd-cell
## maze anchors on both sides. Views straddle each internal streaming seam.
static func large_field(pick: Callable, width: int, depth: int) -> Dictionary:
	var c := pillar_field(pick,width,depth,true)
	c.id = "P07"
	c.profile = "large_pillar_field"
	c.name = "Grand champ de piliers"
	c.assembly.profile = c.profile
	c.views["seam_west"] = {"x":272,"z":140,"yaw":PI/2,"label":"Avant le raccord est"}
	c.views["seam_east"] = {"x":288,"z":140,"yaw":PI/2,"label":"Après le raccord est"}
	c.views["seam_north"] = {"x":140,"z":272,"yaw":PI,"label":"Avant le raccord sud"}
	c.views["seam_south"] = {"x":140,"z":288,"yaw":PI,"label":"Après le raccord sud"}
	var aisle: int = 40+c.variant.spacing*8+c.variant.spacing/2
	c.views["depth"] = {"x":aisle,"z":aisle,"yaw":-PI/2,"label":"Profondeur du grand champ"}
	return c
