class_name LightBaker
extends Node
## GPU light bake of a chunk in two passes (shaders/bake_direct.gdshader,
## shaders/bake_indirect.gdshader), rendered in an off-screen viewport and
## read back as images: three tiles of 160 × 160 texels (0.25 m) per pass.
## One render per frame; callers await the returned coroutine.

const RES := 160
const TILES := 3
const TEXEL := 0.25
const OCC_TEXEL := 0.125
const MARGIN := 10.0
const E_MAX := 6.0
const I_MAX := 2.0

## Panel radiance: a Cycles emission strength is the radiance itself (truth renders: 12).
var panel_radiance := 12.0
## Linear albedos: texture averages times the tints calibrated in Cycles.
var albedo := {"wall": Color(0.599, 0.491, 0.141), "floor": Color(0.312, 0.266, 0.098), "ceiling": Color(0.771, 0.755, 0.553)}
## Second gather: hit surfaces show their first-gather light times this, for
## all their indirect light (infinite-bounce approximation, ≈ 1 / (1 - albedo);
## fitted on the Cycles diffuse passes).
var higher_bounces := 1.7
var busy := false
var renders := 0
var last_ms := 0.0

var _viewport: SubViewport
var _rect: ColorRect
var _direct := ShaderMaterial.new()
var _indirect := ShaderMaterial.new()


func _ready() -> void:
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(RES * TILES, RES)
	_viewport.disable_3d = true
	_viewport.transparent_bg = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_viewport)
	_rect = ColorRect.new()
	_rect.size = Vector2(RES * TILES, RES)
	_viewport.add_child(_rect)
	_direct.shader = preload("res://shaders/bake_direct.gdshader")
	_indirect.shader = preload("res://shaders/bake_indirect.gdshader")
	for m in [_direct, _indirect]:
		m.set_shader_parameter("texel", TEXEL)
		m.set_shader_parameter("tiles", float(TILES))
		m.set_shader_parameter("res", float(RES))
		m.set_shader_parameter("occ_texel", OCC_TEXEL)
		m.set_shader_parameter("e_max", E_MAX)
		m.set_shader_parameter("ceiling", LevelWorld.HEIGHT)
	_indirect.set_shader_parameter("i_max", I_MAX)


static func chunk_origin(coord: Vector2i) -> Vector2:
	return Vector2(coord) * LevelWorld.CHUNK * LevelWorld.CELL


## Full-height walls of the chunk and a margin, relative to the chunk origin.
func _occupancy(world: LevelWorld, coord: Vector2i) -> Image:
	var origin := chunk_origin(coord) - Vector2(MARGIN, MARGIN)
	var size := int((LevelWorld.CHUNK * LevelWorld.CELL + 2.0 * MARGIN) / OCC_TEXEL)
	var img := Image.create(size, size, false, Image.FORMAT_R8)
	var c0 := Vector2i((origin / LevelWorld.CELL).floor())
	var cells := int(ceil((LevelWorld.CHUNK * LevelWorld.CELL + 2.0 * MARGIN) / LevelWorld.CELL)) + 1
	var seen := {}
	for z in range(c0.y, c0.y + cells):
		for x in range(c0.x, c0.x + cells):
			for b in world.cell_boxes(x, z):
				if not b.occluder or seen.has(b.id):
					continue
				seen[b.id] = true
				var r := Rect2i(Vector2i(floori((b.x0 - origin.x) / OCC_TEXEL + 0.5), floori((b.z0 - origin.y) / OCC_TEXEL + 0.5)), Vector2i.ZERO)
				r.end = Vector2i(floori((b.x1 - origin.x) / OCC_TEXEL + 0.5), floori((b.z1 - origin.y) / OCC_TEXEL + 0.5))
				img.fill_rect(r.intersection(Rect2i(0, 0, size, size)), Color(1, 0, 0))
	return img


func _set_occupancy(m: ShaderMaterial, img: Image) -> void:
	m.set_shader_parameter("occ_tex", ImageTexture.create_from_image(img))
	m.set_shader_parameter("occ_origin", Vector2(-MARGIN, -MARGIN))
	m.set_shader_parameter("occ_size", Vector2(img.get_size()))


func _render(m: ShaderMaterial) -> Array:
	while busy:
		await get_tree().process_frame
	busy = true
	var started := Time.get_ticks_usec()
	_rect.material = m
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	# The material change reaches the canvas one frame late: read back after
	# the second draw, or each chunk gets the previous chunk's light.
	await RenderingServer.frame_post_draw
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	var img := _viewport.get_texture().get_image()
	img.convert(Image.FORMAT_RGBA8)
	var tiles := []
	for t in TILES:
		tiles.append(img.get_region(Rect2i(t * RES, 0, RES, RES)))
	busy = false
	renders += 1
	last_ms = (Time.get_ticks_usec() - started) / 1000.0
	return tiles


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
	var fix := Image.create(maxi(1, fixtures.size()), 1, false, Image.FORMAT_RGBAF)
	for i in fixtures.size():
		var f = fixtures[i]
		fix.set_pixel(i, 0, Color(f.x - origin.x, f.z - origin.y, PanelLights.power(0.0, f.seed, true) * panel_radiance, 0))
	_direct.set_shader_parameter("fix_tex", ImageTexture.create_from_image(fix))
	_direct.set_shader_parameter("fix_count", fixtures.size())
	_set_occupancy(_direct, _occupancy(world, coord))
	return await _render(_direct)


## Gather pass. `maps` are the 3 direct then the 3 first-gather textures of
## the streamed region whose origin (world metres) and size are given by
## `region`; `second` makes hits carry the first gather too (two bounces).
func indirect(world: LevelWorld, coord: Vector2i, maps: Array, region: Rect2, second: bool) -> Array:
	var origin := chunk_origin(coord)
	_set_occupancy(_indirect, _occupancy(world, coord))
	for i in 3:
		_indirect.set_shader_parameter("direct%d" % i, maps[i])
		_indirect.set_shader_parameter("bounce%d" % i, maps[3 + i])
	_indirect.set_shader_parameter("use_bounce", higher_bounces if second else 0.0)
	_indirect.set_shader_parameter("region", Vector4(region.position.x - origin.x, region.position.y - origin.y, region.size.x, region.size.y))
	_indirect.set_shader_parameter("wall_albedo", albedo.wall)
	_indirect.set_shader_parameter("floor_albedo", albedo.floor)
	_indirect.set_shader_parameter("ceiling_albedo", albedo.ceiling)
	return await _render(_indirect)
