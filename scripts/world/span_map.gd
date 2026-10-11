class_name SpanMap
extends RefCounted
## The level's solid geometry in 3D, as vertical spans per column (like the
## compact heightfield of navigation-mesh builders): for each 0.125 m column,
## up to MAX_SPANS solid height intervals, sorted, merged. The floor and the
## ceiling are spans like any wall, lintel, slab or duct roof, so any stack of
## floors, overhangs and low passages is described exactly in height.
## Stored in two RGBAH images (spans 0-1 in `a`, 2-3 in `b`: y0, y1, y0, y1);
## unused spans are EMPTY. Read by the light baker (shaders/spans.gdshaderinc).

const MAX_SPANS := 4
const EMPTY := -100.0
## The floor span reaches down to BELOW and the ceiling span up to ABOVE.
const BELOW := -10.0
const ABOVE := 100.0

## Cell-resolution structural ceiling metadata, distinct from duct/lintel gaps.
var room_heights: Image
var room_origin: Vector2
var a: Image
var b: Image
var origin: Vector2
var texel: float
var size: int
## Columns whose spans had to be merged to fit MAX_SPANS (merged conservatively).
var overflow := 0
var max_slice_ms := 0.0


## Spans of the square of `size` × `size` columns whose corner is `p_origin`
## (world metres). Rasterise constant-span rectangles between projected box
## edges, with exactly the same centre tests as the per-column representation.
static func build(world: LevelWorld, p_origin: Vector2, p_size: int, p_texel: float) -> SpanMap:
	var m := _create(p_origin, p_size, p_texel)
	for c in m._cells():
		m._raster_cell(world, c.x, c.y)
	return m


## Runtime preparation yields between cells; no frame pays for a whole map.
static func build_sliced(world: LevelWorld, p_origin: Vector2, p_size: int, p_texel: float, tree: SceneTree, slice_ms := 3.0) -> SpanMap:
	var m := _create(p_origin, p_size, p_texel)
	var started := Time.get_ticks_usec()
	for c in m._cells():
		m._raster_cell(world, c.x, c.y)
		if Time.get_ticks_usec() - started >= slice_ms * 1000.0:
			m.max_slice_ms = maxf(m.max_slice_ms, (Time.get_ticks_usec() - started) / 1000.0)
			await tree.process_frame
			started = Time.get_ticks_usec()
	m.max_slice_ms = maxf(m.max_slice_ms, (Time.get_ticks_usec() - started) / 1000.0)
	return m


static func _create(p_origin: Vector2, p_size: int, p_texel: float) -> SpanMap:
	var m := SpanMap.new()
	m.origin = p_origin
	m.size = p_size
	m.texel = p_texel
	m.room_origin = (p_origin / LevelWorld.CELL).floor() * LevelWorld.CELL
	var end := ((p_origin + Vector2(p_size, p_size) * p_texel) / LevelWorld.CELL).ceil()
	var extent := Vector2i(end - m.room_origin / LevelWorld.CELL)
	m.room_heights = Image.create(extent.x, extent.y, false, Image.FORMAT_RGBAF)
	m.room_heights.fill(Color(0, LevelWorld.HEIGHT, 0, 0))
	m.a = Image.create(p_size, p_size, false, Image.FORMAT_RGBAH)
	m.b = Image.create(p_size, p_size, false, Image.FORMAT_RGBAH)
	return m


func _cells() -> Array[Vector2i]:
	var c0 := Vector2i((origin / LevelWorld.CELL).floor())
	var c1 := Vector2i(((origin + Vector2(size, size) * texel) / LevelWorld.CELL).ceil())
	var cells: Array[Vector2i] = []
	for z in range(c0.y, c1.y):
		for x in range(c0.x, c1.x):
			cells.append(Vector2i(x, z))
	return cells


func _raster_cell(world: LevelWorld, cx: int, cz: int) -> void:
	var cell := LevelWorld.CELL
	var lo := Vector2i(((Vector2(cx, cz) * cell - origin) / texel).round())
	var hi := Vector2i(((Vector2(cx + 1, cz + 1) * cell - origin) / texel).round())
	var rect := Rect2i(lo, hi - lo).intersection(Rect2i(0, 0, size, size))
	if not rect.has_area():
		return
	var fl := world.floor_height(cx, cz)
	var ce := world.ceiling_height(cx, cz)
	room_heights.set_pixel(cx - floori(room_origin.x / cell), cz - floori(room_origin.y / cell), Color(fl, ce, 0, 0))
	var boxes := world.cell_boxes(cx, cz)
	var room := [[BELOW, fl], [ce, ABOVE]]
	if boxes.is_empty():
		_fill(rect, room)
		return
	# Axis-aligned boxes have constant spans between their projected edges.
	# Partition there, rather than allocate/merge arrays for every column.
	# Strict centre-in-box bounds match the original per-column raster exactly.
	var xs := [rect.position.x, rect.end.x]
	var zs := [rect.position.y, rect.end.y]
	var projected := []
	for bx in boxes:
		var x0 := clampi(floori((bx.x0 - origin.x) / texel - 0.5) + 1, rect.position.x, rect.end.x)
		var x1 := clampi(ceili((bx.x1 - origin.x) / texel - 0.5), rect.position.x, rect.end.x)
		var z0 := clampi(floori((bx.z0 - origin.y) / texel - 0.5) + 1, rect.position.y, rect.end.y)
		var z1 := clampi(ceili((bx.z1 - origin.y) / texel - 0.5), rect.position.y, rect.end.y)
		if x1 <= x0 or z1 <= z0:
			continue
		projected.append([Rect2i(x0, z0, x1 - x0, z1 - z0), bx.y0, bx.y1])
		for x in [x0, x1]:
			if not xs.has(x): xs.append(x)
		for z in [z0, z1]:
			if not zs.has(z): zs.append(z)
	xs.sort()
	zs.sort()
	for iz in zs.size() - 1:
		for ix in xs.size() - 1:
			var part := Rect2i(xs[ix], zs[iz], xs[ix + 1] - xs[ix], zs[iz + 1] - zs[iz])
			var spans := room.duplicate()
			for bx in projected:
				if bx[0].has_point(part.position):
					spans.append([bx[1], bx[2]])
			_fill(part, _merge(spans))


static func _merge(spans: Array) -> Array:
	spans.sort_custom(func(u, v): return u[0] < v[0])
	var out := []
	for s in spans:
		if not out.is_empty() and s[0] <= out[-1][1] + 1e-4:
			out[-1][1] = maxf(out[-1][1], s[1])
		else:
			out.append([s[0], s[1]])
	return out


func _encode(spans: Array) -> Array[Color]:
	# More spans than fit: close the smallest gaps (conservative: more solid).
	while spans.size() > MAX_SPANS:
		overflow += 1
		var best := 0
		for i in spans.size() - 1:
			if spans[i + 1][0] - spans[i][1] < spans[best + 1][0] - spans[best][1]:
				best = i
		spans[best][1] = spans[best + 1][1]
		spans.remove_at(best + 1)
	var v := []
	for s in spans:
		v.append_array(s)
	while v.size() < 2 * MAX_SPANS:
		v.append(EMPTY)
	return [Color(v[0], v[1], v[2], v[3]), Color(v[4], v[5], v[6], v[7])]


func _fill(rect: Rect2i, spans: Array) -> void:
	var before := overflow
	var c := _encode(spans)
	overflow += (overflow - before) * (rect.get_area() - 1)
	a.fill_rect(rect, c[0])
	b.fill_rect(rect, c[1])


func _write(x: int, y: int, spans: Array) -> void:
	var c := _encode(spans)
	a.set_pixel(x, y, c[0])
	b.set_pixel(x, y, c[1])


## Solid at world point (x, y, z)? Outside the map: the default room.
func solid(x: float, y: float, z: float) -> bool:
	var t := Vector2i(((Vector2(x, z) - origin) / texel).floor())
	if t.x < 0 or t.y < 0 or t.x >= size or t.y >= size:
		return y < 0.0 or y > LevelWorld.HEIGHT
	for c in [a.get_pixelv(t), b.get_pixelv(t)]:
		if (y > c.r and y < c.g) or (y > c.b and y < c.a):
			return true
	return false

## CPU counterpart of the projector DDA, used for a handful of bounce probes.
## No GPU readback; slabs include the floor and ceiling as well as walls.
func trace_ray(start: Vector3, ray: Vector3, limit: float) -> Dictionary:
	var c := Vector2i(floori((start.x-origin.x)/texel),floori((start.z-origin.y)/texel))
	var sx := 1 if ray.x >= 0 else -1
	var sz := 1 if ray.z >= 0 else -1
	var nx := (origin.x+(c.x+(1 if sx > 0 else 0))*texel-start.x)/ray.x if absf(ray.x)>1e-6 else INF
	var nz := (origin.y+(c.y+(1 if sz > 0 else 0))*texel-start.z)/ray.z if absf(ray.z)>1e-6 else INF
	var dx := absf(texel/ray.x) if absf(ray.x)>1e-6 else INF
	var dz := absf(texel/ray.z) if absf(ray.z)>1e-6 else INF
	var t := 0.0
	var entered := -ray
	for step in 256:
		if c.x < 0 or c.y < 0 or c.x >= size or c.y >= size: return {}
		var end := minf(limit,minf(nx,nz))
		var ca := a.get_pixel(c.x,c.y)
		var cb := b.get_pixel(c.x,c.y)
		var closest := INF
		var normal := entered
		for slab in [Vector2(ca.r,ca.g),Vector2(ca.b,ca.a),Vector2(cb.r,cb.g),Vector2(cb.b,cb.a)]:
			if slab.x < -50 and slab.y < -50: continue
			if absf(ray.y) < 1e-6:
				if start.y > slab.x and start.y < slab.y: closest = t
			else:
				var lo: float = (slab.x-start.y)/ray.y
				var hi: float = (slab.y-start.y)/ray.y
				var entry := maxf(t,minf(lo,hi))
				if entry <= minf(end,maxf(lo,hi)) and entry < closest:
					closest = maxf(0,entry)
					normal = (Vector3.DOWN if ray.y > 0 else Vector3.UP) if entry > t+1e-6 else entered
		if closest < INF: return {"distance":closest,"position":start+ray*closest,"normal":normal}
		if end >= limit: return {}
		t = end
		if nx <= nz:
			c.x += sx
			nx += dx
			entered = Vector3(-sx,0,0)
		else:
			c.y += sz
			nz += dz
			entered = Vector3(0,0,-sz)
	return {}
