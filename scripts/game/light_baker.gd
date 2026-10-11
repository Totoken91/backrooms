class_name LightBaker
extends Node
## GPU light bake of a chunk in two passes (shaders/bake_direct.gdshader,
## shaders/bake_indirect.gdshader), rendered in an off-screen viewport and
## read back as images: three tiles of 160 × 160 texels (0.25 m) per pass.
## One render per frame; callers await the returned coroutine.

const RES := 160
## Viewport tiles: the direct pass fills five, the gather passes three.
const TILES := 5
const TEXEL := 0.25
const OCC_TEXEL := 0.125
const MARGIN := 10.0
## Heavy passes render in this many bands (one per frame).
const BANDS := 8
const E_MAX := 6.0
const I_MAX := 2.0

## Panel radiance: a Cycles emission strength is the radiance itself (truth renders: 12).
var panel_radiance := 12.0
## Direct emitter cutoff; keep inside the obstacle margin for valid shadows.
var direct_reach := 8.0
## Diagnostic only: vertical location of the single wall-indirect sample.
var wall_receiver_fraction := 0.5
## Linear albedos: texture averages times the tints calibrated in Cycles.
var albedo := {"wall": Color(0.599, 0.491, 0.141), "floor": Color(0.312, 0.266, 0.098), "ceiling": Color(0.771, 0.755, 0.553)}
## Second gather: hit surfaces show their first-gather light times this, for
## all their indirect light (infinite-bounce approximation, ≈ 1 / (1 - albedo);
## fitted on the Cycles diffuse passes).
var higher_bounces := 1.7
var busy := false
var renders := 0
var last_ms := 0.0
## CPU timings exclude awaited frames. Draw waits include GPU work and pacing.
var timings := {}

var _viewport: SubViewport
var _rect: ColorRect
var _direct := ShaderMaterial.new()
var _indirect := ShaderMaterial.new()
var _filter := ShaderMaterial.new()
var _span_cache := {}
var _span_order: Array[Vector2i] = []
var _span_world: LevelWorld
var _span_geo_test := false
var _span_textures := {}


func record_time(label: String, started: int) -> void:
	var ms := (Time.get_ticks_usec() - started) / 1000.0
	var t: Dictionary = timings.get(label, {"count": 0, "total_ms": 0.0, "max_ms": 0.0})
	t.count += 1
	t.total_ms += ms
	t.max_ms = maxf(t.max_ms, ms)
	timings[label] = t


func _ensure_world(world: LevelWorld) -> void:
	if _span_world != world or _span_geo_test != world.geo_test:
		_span_cache.clear()
		_span_order.clear()
		_span_textures.clear()
		_span_world = world
		_span_geo_test = world.geo_test


func _remember(coord: Vector2i, map: SpanMap) -> void:
	_span_cache[coord] = map
	_span_order.erase(coord)
	_span_order.append(coord)
	if _span_order.size() > 8:
		var old: Vector2i = _span_order.pop_front()
		_span_cache.erase(old)
		_span_textures.erase(old)


func _ready() -> void:
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(RES * TILES, RES)
	_viewport.disable_3d = true
	_viewport.transparent_bg = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_NEVER
	add_child(_viewport)
	_rect = ColorRect.new()
	_rect.size = Vector2(RES * TILES, RES)
	_viewport.add_child(_rect)
	_direct.shader = preload("res://shaders/bake_direct.gdshader")
	_indirect.shader = preload("res://shaders/bake_indirect.gdshader")
	_filter.shader = preload("res://shaders/bake_filter.gdshader")
	for m in [_direct, _indirect, _filter]:
		m.set_shader_parameter("texel", TEXEL)
		m.set_shader_parameter("tiles", float(TILES))
		m.set_shader_parameter("res", float(RES))
		m.set_shader_parameter("occ_texel", OCC_TEXEL)
		m.set_shader_parameter("e_max", E_MAX)
		m.set_shader_parameter("ceiling", LevelWorld.HEIGHT)
	_indirect.set_shader_parameter("i_max", I_MAX)


static func chunk_origin(coord: Vector2i) -> Vector2:
	return Vector2(coord) * LevelWorld.CHUNK * LevelWorld.CELL


## Solid geometry of the chunk and a margin, as vertical spans (SpanMap).
## The three bakes of a chunk reuse it: a few recent chunks are kept.
func spans(world: LevelWorld, coord: Vector2i) -> SpanMap:
	_ensure_world(world)
	if _span_cache.has(coord):
		_span_order.erase(coord)
		_span_order.append(coord)
		return _span_cache[coord]
	var size := int((LevelWorld.CHUNK * LevelWorld.CELL + 2.0 * MARGIN) / OCC_TEXEL)
	var started := Time.get_ticks_usec()
	var m := SpanMap.build(world, chunk_origin(coord) - Vector2(MARGIN, MARGIN), size, OCC_TEXEL)
	record_time("span_build_cpu", started)
	_remember(coord, m)
	return m


func prepare_spans(world: LevelWorld, coord: Vector2i) -> SpanMap:
	_ensure_world(world)
	if _span_cache.has(coord):
		return spans(world, coord)
	var size := int((LevelWorld.CHUNK * LevelWorld.CELL + 2.0 * MARGIN) / OCC_TEXEL)
	var map := await SpanMap.build_sliced(world, chunk_origin(coord) - Vector2(MARGIN, MARGIN), size, OCC_TEXEL, get_tree())
	timings["span_slice_cpu"] = {"max_ms": maxf(timings.get("span_slice_cpu", {}).get("max_ms", 0.0), map.max_slice_ms)}
	# Do not insert an obsolete world's work after an awaited frame.
	if _span_world == world and _span_geo_test == world.geo_test:
		_remember(coord, map)
	return map


func _set_spans(m: ShaderMaterial, map: SpanMap, coord: Vector2i) -> void:
	var started := Time.get_ticks_usec()
	if not _span_textures.has(coord) or _span_cache.get(coord) != map:
		_span_textures[coord] = [ImageTexture.create_from_image(map.a), ImageTexture.create_from_image(map.b)]
	m.set_shader_parameter("span_a", _span_textures[coord][0])
	m.set_shader_parameter("span_b", _span_textures[coord][1])
	m.set_shader_parameter("occ_origin", Vector2(-MARGIN, -MARGIN))
	m.set_shader_parameter("occ_size", Vector2(map.size, map.size))
	record_time("span_upload_cpu", started)


## Renders `m`, then (denoise > 0) the wall-aware blur of that result with
## that radius in texels.
func _render(m: ShaderMaterial, denoise := 0) -> Array:
	while busy:
		await get_tree().process_frame
	busy = true
	var started := Time.get_ticks_usec()
	var img := await _draw(m, BANDS)
	if denoise > 0:
		for key in ["span_a", "span_b", "occ_origin", "occ_size"]:
			_filter.set_shader_parameter(key, m.get_shader_parameter(key))
		_filter.set_shader_parameter("src", ImageTexture.create_from_image(img))
		_filter.set_shader_parameter("radius", denoise)
		_filter.set_shader_parameter("sigma", denoise * 0.6)
		_filter.set_shader_parameter("active_tiles", 4.0 if m == _direct else 3.0)
		img = await _draw(_filter, BANDS)
	var tiles := []
	for t in TILES:
		tiles.append(img.get_region(Rect2i(t * RES, 0, RES, RES)))
	busy = false
	renders += 1
	last_ms = (Time.get_ticks_usec() - started) / 1000.0
	return tiles


## Draws `m` over the tiles in `bands` horizontal bands, one per frame,
## so a heavy pass costs the frame a fraction of its GPU time (the viewport
## keeps its content between bands), then reads the result back.
func _draw(m: ShaderMaterial, bands := 1) -> Image:
	_rect.material = m
	var rows := RES / bands
	for k in bands:
		var started := Time.get_ticks_usec()
		_rect.position.y = k * rows
		_rect.size.y = rows
		m.set_shader_parameter("band_y0", float(k * rows))
		m.set_shader_parameter("band_rows", float(rows))
		# One draw per band (verified: the material and uniforms set above reach
		# this draw; no stale band).
		_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		await RenderingServer.frame_post_draw
		record_time("filter_band_wait" if m == _filter else "light_band_wait", started)
	var read_started := Time.get_ticks_usec()
	var img := _viewport.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	record_time("readback_cpu", read_started)
	return img


## Pass 1. Returns 3 images (see bake_direct.gdshader for the channels).
func direct(world: LevelWorld, coord: Vector2i) -> Array:
	var origin := chunk_origin(coord)
	var fixtures := []
	var c0 := Vector2i(((origin - Vector2(9, 9)) / LevelWorld.CELL).floor())
	var span := int((LevelWorld.CHUNK * LevelWorld.CELL + 18.0) / LevelWorld.CELL) + 1
	for z in range(c0.y, c0.y + span):
		for x in range(c0.x, c0.x + span):
			for f in world.cell_fixtures(x, z):
				fixtures.append(f)
	# Row 0: x, z, radiance, height; row 1: flicker group. Panels switched off
	# give no light.
	var fix := Image.create(maxi(1, fixtures.size()), 2, false, Image.FORMAT_RGBAF)
	for i in fixtures.size():
		var f = fixtures[i]
		var lit := 0.0 if world.panels_off.has(f.id) else PanelLights.power(0.0, f.seed, true)
		fix.set_pixel(i, 1, Color(PanelLights.group_of(f.seed), 0, 0, 0))
		fix.set_pixel(i, 0, Color(f.x - origin.x, f.z - origin.y, lit * panel_radiance, f.y))
	_direct.set_shader_parameter("fix_tex", ImageTexture.create_from_image(fix))
	_direct.set_shader_parameter("fix_count", fixtures.size())
	_direct.set_shader_parameter("reach", direct_reach)
	_set_spans(_direct, await prepare_spans(world, coord), coord)
	return await _render(_direct, 1)


func bind_light_maps(maps: Texture2DArray) -> void:
	_indirect.set_shader_parameter("light_maps", maps)


func set_slots(slots: PackedVector2Array) -> void:
	_indirect.set_shader_parameter("slot_chunk", slots)


## Gather pass over the chunk, reading the streamed light maps bound with
## bind_light_maps; `second` makes hits carry the first gather too.
func indirect(world: LevelWorld, coord: Vector2i, second: bool) -> Array:
	_set_spans(_indirect, await prepare_spans(world, coord), coord)
	_indirect.set_shader_parameter("bake_origin", chunk_origin(coord))
	_indirect.set_shader_parameter("use_bounce", higher_bounces if second else 0.0)
	_indirect.set_shader_parameter("wall_receiver_fraction", wall_receiver_fraction)
	_indirect.set_shader_parameter("wall_albedo", albedo.wall)
	_indirect.set_shader_parameter("floor_albedo", albedo.floor)
	_indirect.set_shader_parameter("ceiling_albedo", albedo.ceiling)
	var tiles: Array = await _render(_indirect, 3)
	return tiles.slice(0, 3)
