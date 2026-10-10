class_name WorldStreamer
extends Node3D
## Loads chunks around the player (nearest first, one build at a time spread
## over frames), bakes their light on the GPU (LightBaker: direct, then a first
## gather once the neighbours' direct light exists, then a second gather once
## their first gather exists), composites the light and contact-occlusion maps
## of the loaded region, and frees distant chunks.

## Chunks within RADIUS get the indirect light; geometry and direct light load one
## ring further so every bounced chunk sees its neighbours.
const RADIUS := 2
const LOAD_RADIUS := 3
const SPAN_CHUNKS := LOAD_RADIUS * 2 + 1
const BUILD_SLICE_MS := 4.0
const AO_SLICE_MS := 3.0

var world: LevelWorld
var chunks := {}
var materials := {}
var panel_mesh: Mesh
var baker: LightBaker
var center := Vector2i(1 << 30, 0)
var last_build_ms := 0.0
var max_build_ms := 0.0
## Changes whenever the set of loaded chunks changes.
var generation := 0
## Region light maps (LightBaker layout): direct0..2, first gather 0..2, and
## the displayed indirect light 0..2 (second gather, else first); then AO.
var light_images: Array[Image] = []
var light_textures: Array[ImageTexture] = []
var ao_image: Image
var ao_texture: ImageTexture

var _building: Chunk = null
var _baking := false
var _dirty := true


func _ready() -> void:
	var size := SPAN_CHUNKS * LightBaker.RES
	for i in 9:
		var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
		img.fill(Color(0, 0, 0, 1))
		light_images.append(img)
		light_textures.append(ImageTexture.create_from_image(img))
	ao_image = Image.create(SPAN_CHUNKS * Chunk.AO_RES, SPAN_CHUNKS * Chunk.AO_RES, false, Image.FORMAT_L8)
	ao_image.fill(Color.WHITE)
	ao_texture = ImageTexture.create_from_image(ao_image)


func reset(p_world: LevelWorld) -> void:
	for c in chunks.values():
		c.queue_free()
	chunks.clear()
	generation += 1
	_building = null
	world = p_world
	center = Vector2i(1 << 30, 0)
	_dirty = true


static func chunk_of(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / (LevelWorld.CELL * LevelWorld.CHUNK)), floori(p.z / (LevelWorld.CELL * LevelWorld.CHUNK)))


func region_rect() -> Rect2:
	var size := SPAN_CHUNKS * LevelWorld.CHUNK * LevelWorld.CELL
	return Rect2(LightBaker.chunk_origin(center - Vector2i(LOAD_RADIUS, LOAD_RADIUS)), Vector2(size, size))


## Builds the geometry around `p` synchronously (spawn); light follows.
func warm(p: Vector3) -> void:
	var c := chunk_of(p)
	for dz in range(-LOAD_RADIUS, LOAD_RADIUS + 1):
		for dx in range(-LOAD_RADIUS, LOAD_RADIUS + 1):
			_build(c + Vector2i(dx, dz))
	update(p)


## Bakes until every chunk around the player is fully lit (loading).
func settle(p: Vector3, limit := 4000) -> void:
	for i in limit:
		update(p)
		if pending_bakes() == 0 and not _baking:
			break
		await get_tree().process_frame
	_composite()


func update(p: Vector3) -> void:
	var c := chunk_of(p)
	if c != center:
		center = c
		_dirty = true
		for key in chunks.keys():
			if absi(key.x - c.x) > LOAD_RADIUS + 1 or absi(key.y - c.y) > LOAD_RADIUS + 1:
				chunks[key].queue_free()
				chunks.erase(key)
				generation += 1
		world.prune(c.x, c.y, LOAD_RADIUS + 2)
	var missing := Vector2i(1 << 30, 0)
	var best := INF
	for dz in range(-LOAD_RADIUS, LOAD_RADIUS + 1):
		for dx in range(-LOAD_RADIUS, LOAD_RADIUS + 1):
			var k := c + Vector2i(dx, dz)
			if not chunks.has(k) and Vector2(dx, dz).length() < best:
				best = Vector2(dx, dz).length()
				missing = k
	if best < INF and (_building == null or not is_instance_valid(_building) or _building.built):
		_build(missing, BUILD_SLICE_MS)
	if not _baking:
		_next_bake()
	if _dirty:
		_composite()


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
	last_build_ms = chunk.build_ms
	max_build_ms = maxf(max_build_ms, chunk.build_ms)


## Order: the nearest pending job, direct light first, then the first gather
## (3 × 3 neighbours have direct light), then the second gather (neighbours
## within RADIUS have their first gather). A ring beyond lets earlier stages
## run ahead so the nearest chunks finish first.
func _next_bake() -> void:
	var best: Chunk = null
	var best_stage := 0
	var best_score := INF
	for k in chunks:
		var chunk: Chunk = chunks[k]
		if not chunk.built:
			continue
		var stage := 0 if chunk.direct.is_empty() else (1 if chunk.bounce1.is_empty() else (2 if chunk.bounce.is_empty() else 3))
		if stage == 3:
			continue
		if stage > 0 and (absi(k.x - center.x) > RADIUS or absi(k.y - center.y) > RADIUS):
			continue
		var ready := true
		if stage > 0:
			for dz in range(-1, 2):
				for dx in range(-1, 2):
					var nk: Vector2i = k + Vector2i(dx, dz)
					var n: Chunk = chunks.get(nk)
					if stage == 1 and (n == null or n.direct.is_empty()):
						ready = false
					elif stage == 2 and absi(nk.x - center.x) <= RADIUS and absi(nk.y - center.y) <= RADIUS and (n == null or n.bounce1.is_empty()):
						ready = false
		var score := Vector2(k - center).length() + stage * 1.0
		if ready and score < best_score:
			best_score = score
			best = chunk
			best_stage = stage
	if best == null:
		return
	if best_stage == 0:
		_bake_direct(best)
	else:
		_bake_gather(best, best_stage == 2)


func _bake_direct(chunk: Chunk) -> void:
	_baking = true
	var tiles: Array = await baker.direct(world, chunk.coord)
	if is_instance_valid(chunk):
		chunk.direct = tiles
		await chunk.bake_ao(AO_SLICE_MS)
		_dirty = true
	_baking = false


func _bake_gather(chunk: Chunk, second: bool) -> void:
	_baking = true
	if _dirty:
		_composite()
	var tiles: Array = await baker.indirect(world, chunk.coord, light_textures.slice(0, 6), region_rect(), second)
	if is_instance_valid(chunk):
		if second:
			chunk.bounce = tiles
		else:
			chunk.bounce1 = tiles
		_dirty = true
	_baking = false


func _composite() -> void:
	_dirty = false
	var res := LightBaker.RES
	for img in light_images:
		img.fill(Color(0, 0, 0, 1))
	ao_image.fill(Color.WHITE)
	for dz in range(-LOAD_RADIUS, LOAD_RADIUS + 1):
		for dx in range(-LOAD_RADIUS, LOAD_RADIUS + 1):
			var chunk: Chunk = chunks.get(center + Vector2i(dx, dz))
			if chunk == null:
				continue
			var at := Vector2i(dx + LOAD_RADIUS, dz + LOAD_RADIUS)
			var shown: Array = chunk.bounce if not chunk.bounce.is_empty() else chunk.bounce1
			for i in chunk.direct.size():
				light_images[i].blit_rect(chunk.direct[i], Rect2i(0, 0, res, res), at * res)
			for i in chunk.bounce1.size():
				light_images[3 + i].blit_rect(chunk.bounce1[i], Rect2i(0, 0, res, res), at * res)
			for i in shown.size():
				light_images[6 + i].blit_rect(shown[i], Rect2i(0, 0, res, res), at * res)
			if chunk.ao:
				ao_image.blit_rect(chunk.ao, Rect2i(0, 0, Chunk.AO_RES, Chunk.AO_RES), at * Chunk.AO_RES)
	for i in light_images.size():
		light_textures[i].update(light_images[i])
	ao_texture.update(ao_image)
	var r := region_rect()
	for m in materials.values():
		if m is ShaderMaterial:
			for i in 3:
				m.set_shader_parameter("direct%d" % i, light_textures[i])
				m.set_shader_parameter("bounce%d" % i, light_textures[6 + i])
			m.set_shader_parameter("ao_tex", ao_texture)
			m.set_shader_parameter("light_rect", Vector4(r.position.x, r.position.y, r.size.x, r.size.y))


func pending_bakes() -> int:
	var n := 0
	for k in chunks:
		var chunk: Chunk = chunks[k]
		if absi(k.x - center.x) <= RADIUS and absi(k.y - center.y) <= RADIUS and chunk.bounce.is_empty():
			n += 1
	return n


## All panels of loaded chunks, with their chunk and index for power updates.
func panels() -> Array:
	var out := []
	for chunk in chunks.values():
		for i in chunk.fixtures.size():
			out.append([chunk, i, chunk.fixtures[i]])
	return out


## Flicker currently drives the panel's emission only (baked light is steady).
func set_fixture_power(_f, _power: float) -> void:
	pass
