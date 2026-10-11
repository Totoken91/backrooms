extends SceneTree
## Geometry equivalence and world-cache isolation. Run headless.
var failures := 0

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: ", message)

func _initialize() -> void:
	call_deferred("run")

## Independent column oracle: evaluate actual box membership at each centre.
func reference(world: LevelWorld, origin: Vector2, size: int, texel: float) -> SpanMap:
	var map := SpanMap._create(origin, size, texel)
	for z in size:
		for x in size:
			var p := origin + (Vector2(x, z) + Vector2(0.5, 0.5)) * texel
			var cx := floori(p.x / LevelWorld.CELL)
			var cz := floori(p.y / LevelWorld.CELL)
			var spans := [[SpanMap.BELOW, world.floor_height(cx, cz)], [world.ceiling_height(cx, cz), SpanMap.ABOVE]]
			for box in world.cell_boxes(cx, cz):
				if p.x > box.x0 and p.x < box.x1 and p.y > box.z0 and p.y < box.z1:
					spans.append([box.y0, box.y1])
			map._write(x, z, SpanMap._merge(spans))
	return map

func run() -> void:
	for spec in [[2, true, Vector2(-10, -10)], [99, false, Vector2(-50, -10)], [17, true, Vector2(30, -50)], [99, false, Vector2(-10, -10), "C02"], [99, false, Vector2(-10, -10), "P01"], [99, false, Vector2(-10, -10), "P02"], [7, false, Vector2(-10, -10), "P03"], [99, false, Vector2(-10, -10), "P04"]]:
		var world := LevelWorld.new(spec[0], spec[3] if spec.size() > 3 else "C01")
		world.geo_test = spec[1]
		var actual := SpanMap.build(world, spec[2], 480, 0.125)
		var expected := reference(world, spec[2], 480, 0.125)
		check(actual.a.get_data() == expected.a.get_data() and actual.b.get_data() == expected.b.get_data(), "rectangular raster must match every column: %s" % [spec])
		check(actual.overflow == expected.overflow, "overflow counts columns")
		var sliced := await SpanMap.build_sliced(world, spec[2], 480, 0.125, self, 0.1)
		check(sliced.a.get_data() == actual.a.get_data() and sliced.b.get_data() == actual.b.get_data(), "yielding must preserve geometry")
	var baker := LightBaker.new()
	var a := LevelWorld.new(2)
	var b := LevelWorld.new(99)
	var first := baker.spans(a, Vector2i.ZERO)
	check(baker.spans(a, Vector2i.ZERO) == first, "same world reuses geometry")
	var second := baker.spans(b, Vector2i.ZERO)
	check(second != first and second.a.get_data() != first.a.get_data(), "new world cannot inherit old obstacles")
	b.geo_test = true
	check(baker.spans(b, Vector2i.ZERO) != second, "geometry test mode invalidates cache")
	for x in 10:
		baker.spans(b, Vector2i(x, 0))
	check(baker._span_cache.size() == 8 and baker._span_order.size() == 8, "cache memory remains bounded")
	baker.free()
	if failures == 0:
		print("PASS: span maps — 1843200 columns, sliced raster, world isolation and bounded cache")
	quit(1 if failures else 0)
