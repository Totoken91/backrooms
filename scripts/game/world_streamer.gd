class_name WorldStreamer
extends Node3D
## Loads chunks around the player (nearest first, at most one build per
## frame), bakes their irradiance fields in short slices once their
## neighbours' colliders exist, composites the fields into one texture, and
## frees chunks that fall out of range.

## Field and baking radius; geometry loads one ring further so every baked
## chunk has its neighbours' colliders.
const RADIUS := 2
const LOAD_RADIUS := 3
const FIELD_RES := Chunk.FIELD_RES
const SPAN := (RADIUS * 2 + 1) * FIELD_RES
const BAKE_SLICE_MS := 3.0
const BUILD_SLICE_MS := 4.0

var world: LevelWorld
var chunks := {}
var materials := {}
var panel_mesh: Mesh
var center := Vector2i(1 << 30, 0)
var field_image: Image
var field_texture: ImageTexture
## Panels of the field area, one texel per cell (see surface.gdshader).
var fixture_image: Image
var ao_image: Image
var ao_texture: ImageTexture
var fixture_texture: ImageTexture
var _fixture_pixels := {}
var _fixtures_dirty := false
var last_build_ms := 0.0
var max_build_ms := 0.0
## Changes whenever the set of loaded chunks changes.
var generation := 0

var _baking: Chunk = null
var _building: Chunk = null
var _field_dirty := true


func _ready() -> void:
	field_image = Image.create(SPAN, SPAN, false, Image.FORMAT_RGBA8)
	field_image.fill(Color(0.11, 0.14, 1, 1))
	field_texture = ImageTexture.create_from_image(field_image)
	ao_image = Image.create((RADIUS * 2 + 1) * Chunk.AO_RES, (RADIUS * 2 + 1) * Chunk.AO_RES, false, Image.FORMAT_L8)
	ao_image.fill(Color.WHITE)
	ao_texture = ImageTexture.create_from_image(ao_image)
	var cells := (RADIUS * 2 + 1) * LevelWorld.CHUNK
	fixture_image = Image.create(cells, cells, false, Image.FORMAT_RGBA8)
	fixture_texture = ImageTexture.create_from_image(fixture_image)


func reset(p_world: LevelWorld) -> void:
	for c in chunks.values():
		c.queue_free()
	chunks.clear()
	generation += 1
	_baking = null
	_building = null
	world = p_world
	center = Vector2i(1 << 30, 0)
	_field_dirty = true


static func chunk_of(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / (LevelWorld.CELL * LevelWorld.CHUNK)), floori(p.z / (LevelWorld.CELL * LevelWorld.CHUNK)))


## Builds everything around `p` synchronously (loading screen / spawn).
func warm(p: Vector3) -> void:
	var c := chunk_of(p)
	for dz in range(-LOAD_RADIUS, LOAD_RADIUS + 1):
		for dx in range(-LOAD_RADIUS, LOAD_RADIUS + 1):
			_build(c + Vector2i(dx, dz))
	update(p)


func update(p: Vector3) -> void:
	var c := chunk_of(p)
	if c != center:
		center = c
		_field_dirty = true
		for key in chunks.keys():
			if absi(key.x - c.x) > LOAD_RADIUS + 1 or absi(key.y - c.y) > LOAD_RADIUS + 1:
				chunks[key].queue_free()
				chunks.erase(key)
				generation += 1
		world.prune(c.x, c.y, LOAD_RADIUS + 2)
	# Nearest missing chunk first; one per frame.
	var missing: Vector2i = Vector2i(1 << 30, 0)
	var best := INF
	for dz in range(-LOAD_RADIUS, LOAD_RADIUS + 1):
		for dx in range(-LOAD_RADIUS, LOAD_RADIUS + 1):
			var k := c + Vector2i(dx, dz)
			if not chunks.has(k) and Vector2(dx, dz).length() < best:
				best = Vector2(dx, dz).length()
				missing = k
	if best < INF and (_building == null or not is_instance_valid(_building) or _building.built):
		_build(missing, BUILD_SLICE_MS)
	if _baking == null:
		_start_next_bake()
	if _field_dirty:
		_composite()
	if _fixtures_dirty:
		_fixtures_dirty = false
		fixture_texture.update(fixture_image)


func _build(k: Vector2i, slice_ms := INF) -> void:
	if chunks.has(k):
		return
	var chunk := Chunk.new()
	add_child(chunk)
	chunks[k] = chunk
	_building = chunk
	await chunk.setup(world, k, materials, panel_mesh, slice_ms)
	if not is_instance_valid(chunk) or not chunk.built:
		return
	generation += 1
	_field_dirty = true
	last_build_ms = chunk.build_ms
	max_build_ms = maxf(max_build_ms, chunk.build_ms)


func _start_next_bake() -> void:
	var best: Chunk = null
	var best_d := INF
	for k in chunks:
		var chunk: Chunk = chunks[k]
		if not chunk.built or chunk.field_ready or absi(k.x - center.x) > RADIUS or absi(k.y - center.y) > RADIUS:
			continue
		var neighbours := true
		for dz in range(-1, 2):
			for dx in range(-1, 2):
				var n: Chunk = chunks.get(k + Vector2i(dx, dz))
				if n == null or not n.built:
					neighbours = false
		if not neighbours:
			continue
		var d := Vector2(k - center).length()
		if d < best_d:
			best_d = d
			best = chunk
	if best == null:
		return
	_baking = best
	var nearby := []
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			nearby.append_array(chunks[best.coord + Vector2i(dx, dz)].fixtures)
	_run_bake(best, nearby)


func _run_bake(chunk: Chunk, nearby: Array) -> void:
	await get_tree().physics_frame
	if not is_instance_valid(chunk) or not chunk.is_inside_tree():
		_baking = null
		return
	await chunk.bake_field(get_world_3d().direct_space_state, nearby, BAKE_SLICE_MS)
	if _baking == chunk:
		_baking = null
	_field_dirty = true


func _composite() -> void:
	_field_dirty = false
	field_image.fill(Color(0.11, 0.14, 1, 1))
	for dz in range(-RADIUS, RADIUS + 1):
		for dx in range(-RADIUS, RADIUS + 1):
			var chunk: Chunk = chunks.get(center + Vector2i(dx, dz))
			if chunk and chunk.field_ready:
				field_image.blit_rect(chunk.field, Rect2i(0, 0, FIELD_RES, FIELD_RES), Vector2i((dx + RADIUS) * FIELD_RES, (dz + RADIUS) * FIELD_RES))
				ao_image.blit_rect(chunk.ao, Rect2i(0, 0, Chunk.AO_RES, Chunk.AO_RES), Vector2i((dx + RADIUS) * Chunk.AO_RES, (dz + RADIUS) * Chunk.AO_RES))
			else:
				ao_image.fill_rect(Rect2i((dx + RADIUS) * Chunk.AO_RES, (dz + RADIUS) * Chunk.AO_RES, Chunk.AO_RES, Chunk.AO_RES), Color.WHITE)
	field_texture.update(field_image)
	ao_texture.update(ao_image)
	var size := SPAN * LevelWorld.CELL * LevelWorld.CHUNK / float(FIELD_RES)
	var rect := Vector4((center.x - RADIUS) * LevelWorld.CHUNK * LevelWorld.CELL, (center.y - RADIUS) * LevelWorld.CHUNK * LevelWorld.CELL, size, size)
	# Panel map: every loaded panel of the field area, at nominal power.
	fixture_image.fill(Color(0, 0, 0, 0))
	_fixture_pixels.clear()
	var origin := (center - Vector2i(RADIUS, RADIUS)) * LevelWorld.CHUNK
	var cells := fixture_image.get_width()
	for dz in range(-RADIUS, RADIUS + 1):
		for dx in range(-RADIUS, RADIUS + 1):
			var chunk: Chunk = chunks.get(center + Vector2i(dx, dz))
			if chunk == null:
				continue
			for f in chunk.fixtures:
				var cx := floori(f.x / LevelWorld.CELL)
				var cz := floori(f.z / LevelWorld.CELL)
				var px := Vector2i(cx - origin.x, cz - origin.y)
				if px.x < 0 or px.y < 0 or px.x >= cells or px.y >= cells:
					continue
				fixture_image.set_pixelv(px, Color(f.x / LevelWorld.CELL - cx, f.z / LevelWorld.CELL - cz, PanelLights.power(0.0, f.seed, true), 1.0))
				_fixture_pixels[f.id] = px
	fixture_texture.update(fixture_image)
	for m in materials.values():
		if m is ShaderMaterial:
			m.set_shader_parameter("field_tex", field_texture)
			m.set_shader_parameter("field_rect", rect)
			m.set_shader_parameter("ao_tex", ao_texture)
			m.set_shader_parameter("fixture_tex", fixture_texture)
			m.set_shader_parameter("fixture_origin", Vector2(origin))
			m.set_shader_parameter("fixture_cells", float(cells))


func pending_bakes() -> int:
	var n := 0
	for k in chunks:
		if not chunks[k].field_ready and absi(k.x - center.x) <= RADIUS and absi(k.y - center.y) <= RADIUS:
			n += 1
	return n


## All panels of loaded chunks, with their chunk and index for power updates.
func panels() -> Array:
	var out := []
	for chunk in chunks.values():
		for i in chunk.fixtures.size():
			out.append([chunk, i, chunk.fixtures[i]])
	return out


## Live power of a panel for the direct light (flicker).
func set_fixture_power(f, power: float) -> void:
	var px = _fixture_pixels.get(f.id)
	if px == null:
		return
	var c := fixture_image.get_pixelv(px)
	c.b = power
	fixture_image.set_pixelv(px, c)
	_fixtures_dirty = true
