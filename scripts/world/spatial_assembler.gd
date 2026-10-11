class_name SpatialAssembler
extends RefCounted
## P04: six modules, independent row/column dimensions, connected seeded graph.
## Integer room boundaries keep ceiling panels and span volumes on their grid.
static func build(pick: Callable, site_w: int, site_d: int) -> Dictionary:
	var left: int = [60,80,100,120,140][pick.call("width",5)]
	var rows := [60,60,80]
	var wide_row: int = pick.call("deep_row",3)
	rows = [60,60,60]
	rows[wide_row] = 80
	var order := ["enfilade","pillars","return","bend","tee","cross"]
	for i in range(5,0,-1):
		var j: int = pick.call("order.%d" % i,i+1)
		var swap: String = order[i]
		order[i] = order[j]
		order[j] = swap
	var modules := []
	var offsets := []
	var free := []
	var solid := []
	var regions := [{"rect":[0,0,site_w,site_d],"height":3.2}]
	var views := {}
	var report := []
	var z := 0
	for row in 3:
		for col in 2:
			var i := row*2+col
			var offset := Vector2i(0 if col == 0 else left,z)
			var m := RoomFamilies.make_shaped(order[i],pick.call("variant.%d" % i,2),left if col == 0 else 200-left,rows[row])
			modules.append(m)
			offsets.append(offset)
			for f in m.free: free.append(PromenadeAssembler.shifted(f,offset))
			for s in m.solid: solid.append(PromenadeAssembler.shifted(s,offset))
			regions.append({"rect":[offset.x,offset.y,offset.x+m.width,offset.y+m.depth],"height":m.height})
			var v: Dictionary = m.view.duplicate()
			v.x += offset.x
			v.z += offset.y
			views[order[i]] = v
			report.append({"slot":i,"family":order[i],"shape":m.shape,"variant":m.variant,"origin":offset,"height":m.height,"width":m.width,"depth":m.depth})
		z += rows[row]
	# Randomized Kruskal: every selected edge joins two distinct components.
	var candidates := [[0,"east",1,"west"],[2,"east",3,"west"],[4,"east",5,"west"],[0,"south",2,"north"],[1,"south",3,"north"],[2,"south",4,"north"],[3,"south",5,"north"]]
	for i in range(6,0,-1):
		var j: int = pick.call("edge.%d" % i,i+1)
		var swap: Array = candidates[i]
		candidates[i] = candidates[j]
		candidates[j] = swap
	var components := [0,1,2,3,4,5]
	var edges := []
	var spare := []
	for edge in candidates:
		var a: int = components[edge[0]]
		var b: int = components[edge[2]]
		if a == b:
			spare.append(edge)
			continue
		edges.append(edge)
		for i in 6:
			if components[i] == b: components[i] = a
	# Require branching and a leaf without an outside exit in the tree.
	# Otherwise use a seeded comb, then optionally reconnect its branches.
	var degrees := [0,0,0,0,0,0]
	for edge in edges:
		degrees[edge[0]] += 1
		degrees[edge[2]] += 1
	var internal_leaf: bool = degrees[2] == 1 or degrees[3] == 1 or degrees[5] == 1
	if degrees.max() < 3 or not internal_leaf:
		var spine: int = pick.call("spine",2)
		edges = [[0,"east",1,"west"],[2,"east",3,"west"],[4,"east",5,"west"],[spine,"south",spine+2,"north"],[spine+2,"south",spine+4,"north"]]
		spare = [[1-spine,"south",3-spine,"north"],[3-spine,"south",5-spine,"north"]]
	var loops: int = pick.call("loops",3)
	for i in loops: edges.append(spare[i])
	var links := []
	for edge in edges:
		var a: int = edge[0]
		var b: int = edge[2]
		var pa: Dictionary = modules[a].ports[edge[1]]
		var pb: Dictionary = modules[b].ports[edge[3]]
		assert(PromenadeAssembler.compatible(pa,pb) and pa.at+offsets[a] == pb.at+offsets[b])
		free.append(PromenadeAssembler.shifted(RoomFamilies.open_port(modules[a],edge[1]),offsets[a]))
		free.append(PromenadeAssembler.shifted(RoomFamilies.open_port(modules[b],edge[3]),offsets[b]))
		links.append({"a":a,"b":b,"side_a":edge[1],"side_b":edge[3],"at":pa.at+offsets[a],"width":pa.width,"floor":0.0,"ceil_a":pa.ceiling,"ceil_b":pb.ceiling})
	# Exits are anchored to odd maze cells; the southern/eastern margins are 2.5m.
	for ext in [[0,"west"],[1,"east"],[4,"south"]]:
		free.append(PromenadeAssembler.shifted(RoomFamilies.open_port(modules[ext[0]],ext[1]),offsets[ext[0]]))
	free.append({"name":"E1","rect":[23,200,37,site_d],"exit":"south"})
	free.append({"name":"E2","rect":[0,23,10,37],"exit":"west"})
	var east_z := 30
	free.append({"name":"E3","rect":[200,east_z-7,site_w,east_z+7],"exit":"east"})
	var entry: Dictionary = modules[4].view.duplicate()
	entry.x += offsets[4].x
	entry.z += offsets[4].y
	entry.label = "Départ dans le parcours ramifié"
	views.entry = entry
	var fixtures := []
	for zi in range(site_d/20):
		for xi in range(site_w/20):
			var key := xi+zi*64
			if pick.call("fixtures.hole.%d" % key,100) < 8: continue
			var cx := xi*20+10
			var cz := zi*20+10
			fixtures.append({"rect":[cx-3,cz-3,cx+3,cz+3],"key":key})
	return {"id":"P04","name":"Pièces et ramifications","height":4.8,"variant":{"order":order,"left_width":left,"rows":rows,"loops":loops},"assembly":{"modules":report,"links":links},"free":free,"solid":solid,"lintels":[],"fixtures":fixtures,"views":views,"spawn":"entry","fixture_margin":2,"ceiling_regions":regions}
