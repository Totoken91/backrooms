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

var a: Image
var b: Image
var origin: Vector2
var texel: float
var size: int
## Columns whose spans had to be merged to fit MAX_SPANS (merged conservatively).
var overflow := 0


## Spans of the square of `size` × `size` columns whose corner is `p_origin`
## (world metres). Cells without boxes and cells filled by one full box are
## written as rectangles; the others column by column.
static func build(world: LevelWorld, p_origin: Vector2, p_size: int, p_texel: float) -> SpanMap:
	var m := SpanMap.new()
	m.origin = p_origin
	m.size = p_size
	m.texel = p_texel
	m.a = Image.create(p_size, p_size, false, Image.FORMAT_RGBAH)
	m.b = Image.create(p_size, p_size, false, Image.FORMAT_RGBAH)
	var cell := LevelWorld.CELL
	var c0 := Vector2i((p_origin / cell).floor())
	var c1 := Vector2i(((p_origin + Vector2(p_size, p_size) * p_texel) / cell).ceil())
	var area := Rect2i(0, 0, p_size, p_size)
	for cz in range(c0.y, c1.y):
		for cx in range(c0.x, c1.x):
			var lo := Vector2i(((Vector2(cx, cz) * cell - p_origin) / p_texel).round())
			var hi := Vector2i(((Vector2(cx + 1, cz + 1) * cell - p_origin) / p_texel).round())
			var rect := Rect2i(lo, hi - lo).intersection(area)
			if rect.size.x <= 0 or rect.size.y <= 0:
				continue
			var fl := world.floor_height(cx, cz)
			var ce := world.ceiling_height(cx, cz)
			var boxes := world.cell_boxes(cx, cz)
			var room := [[BELOW, fl], [ce, ABOVE]]
			if boxes.is_empty():
				m._fill(rect, room)
				continue
			if boxes.size() == 1:
				var bx = boxes[0]
				if bx.x0 <= cx * cell + 1e-6 and bx.z0 <= cz * cell + 1e-6 and bx.x1 >= (cx + 1) * cell - 1e-6 and bx.z1 >= (cz + 1) * cell - 1e-6 and bx.y0 <= fl + 1e-6 and bx.y1 >= ce - 1e-6:
					m._fill(rect, [[BELOW, ABOVE]])
					continue
			for ty in range(rect.position.y, rect.end.y):
				for tx in range(rect.position.x, rect.end.x):
					var px := p_origin.x + (tx + 0.5) * p_texel
					var pz := p_origin.y + (ty + 0.5) * p_texel
					var spans := room.duplicate()
					for bx in boxes:
						if px > bx.x0 and px < bx.x1 and pz > bx.z0 and pz < bx.z1:
							spans.append([bx.y0, bx.y1])
					m._write(tx, ty, m._merge(spans))
	return m


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
	var c := _encode(spans)
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
