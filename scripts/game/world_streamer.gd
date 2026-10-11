class_name WorldStreamer
extends Node3D
## Loads chunks around the player (nearest first, one build at a time spread
## over frames), bakes their light on the GPU (LightBaker: direct, then a first
## gather once the neighbours' direct light exists, then a second gather once
## their first gather exists), composites the light and contact-occlusion maps
## of the loaded chunks into texture arrays (a layer set per chunk slot, the
## chunk coordinates modulo SLOTS, uploaded alone when that chunk changes),
## and frees distant chunks.

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
## Baked light on the GPU (shaders/light_maps.gdshaderinc): MAPS layers per
## chunk slot (LightBaker layout: 0-3 direct, 4-6 first gather, 7-9 shown
## indirect light) and one contact-occlusion layer; slot_chunk[slot] is the
## chunk a slot holds.
const SLOTS := 7
const MAPS := 10
var light_maps := Texture2DArray.new()
var ao_maps := Texture2DArray.new()
var slot_chunk := PackedVector2Array()
var _black: Image
var _white: Image

var _building: Chunk = null
var _baking := false


func _ready() -> void:
	_black = Image.create(LightBaker.RES, LightBaker.RES, false, Image.FORMAT_RGBA8)
	_black.fill(Color(0, 0, 0, 1))
	_white = Image.create(Chunk.AO_RES, Chunk.AO_RES, false, Image.FORMAT_L8)
	_white.fill(Color.WHITE)
	var layers: Array[Image] = []
	for i in SLOTS * SLOTS * MAPS:
		layers.append(_black)
	light_maps.create_from_images(layers)
	var ao_layers: Array[Image] = []
	for i in SLOTS * SLOTS:
		ao_layers.append(_white)
	ao_maps.create_from_images(ao_layers)
	slot_chunk.resize(SLOTS * SLOTS)
	slot_chunk.fill(Vector2(1e6, 1e6))


func reset(p_world: LevelWorld) -> void:
	for c in chunks.values():
		c.queue_free()
	chunks.clear()
	generation += 1
	_building = null
	world = p_world
	center = Vector2i(1 << 30, 0)
	slot_chunk.fill(Vector2(1e6, 1e6))
	_bind()


static func chunk_of(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / (LevelWorld.CELL * LevelWorld.CHUNK)), floori(p.z / (LevelWorld.CELL * LevelWorld.CHUNK)))


static func slot_of(c: Vector2i) -> int:
	return posmod(c.x, SLOTS) + posmod(c.y, SLOTS) * SLOTS


func _bind() -> void:
	for m in materials.values():
		if m is ShaderMaterial:
			m.set_shader_parameter("light_maps", light_maps)
			m.set_shader_parameter("ao_maps", ao_maps)
	if baker:
		baker.bind_light_maps(light_maps)
	_publish_slots()


func _publish_slots() -> void:
	for m in materials.values():
		if m is ShaderMaterial:
			m.set_shader_parameter("slot_chunk", slot_chunk)
	if baker:
		baker.set_slots(slot_chunk)


## Uploads a chunk's light into its slot: `what` is "all", "direct",
## "bounce1" or "bounce". Chunks outside the 7 × 7 region keep no slot.
func _upload(chunk: Chunk, what := "all") -> void:
	var k := chunk.coord
	if absi(k.x - center.x) > LOAD_RADIUS or absi(k.y - center.y) > LOAD_RADIUS:
		return
	var slot := slot_of(k)
	var base := slot * MAPS
	var owned := slot_chunk[slot] == Vector2(k)
	if not owned:
		what = "all"
	var shown: Array = chunk.bounce if not chunk.bounce.is_empty() else chunk.bounce1
	if what == "all" or what == "direct":
		for i in 4:
			light_maps.update_layer(chunk.direct[i] if i < chunk.direct.size() else _black, base + i)
		ao_maps.update_layer(chunk.ao if chunk.ao else _white, slot)
	if what == "all" or what == "bounce1":
		for i in 3:
			light_maps.update_layer(chunk.bounce1[i] if i < chunk.bounce1.size() else _black, base + 4 + i)
	if what != "direct":
		for i in 3:
			light_maps.update_layer(shown[i] if i < shown.size() else _black, base + 7 + i)
	if not owned:
		slot_chunk[slot] = Vector2(k)
		_publish_slots()


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


func update(p: Vector3) -> void:
	var c := chunk_of(p)
	if c != center:
		center = c
		for key in chunks.keys():
			if absi(key.x - c.x) > LOAD_RADIUS + 1 or absi(key.y - c.y) > LOAD_RADIUS + 1:
				chunks[key].queue_free()
				chunks.erase(key)
				generation += 1
		world.prune(c.x, c.y, LOAD_RADIUS + 2)
		# Chunks entering the region take their slot.
		for key in chunks:
			if chunks[key].built and slot_chunk[slot_of(key)] != Vector2(key):
				_upload(chunks[key])
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
	_upload(chunk)
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
		if is_instance_valid(chunk):
			_upload(chunk, "direct")
	_baking = false


func _bake_gather(chunk: Chunk, second: bool) -> void:
	_baking = true
	var tiles: Array = await baker.indirect(world, chunk.coord, second)
	if is_instance_valid(chunk):
		if second:
			chunk.bounce = tiles
		else:
			chunk.bounce1 = tiles
		_upload(chunk, "bounce" if second else "bounce1")
	_baking = false


func pending_bakes() -> int:
	var n := 0
	for dz in range(-RADIUS, RADIUS + 1):
		for dx in range(-RADIUS, RADIUS + 1):
			var chunk: Chunk = chunks.get(center + Vector2i(dx, dz))
			if chunk == null or not chunk.built or chunk.bounce.is_empty():
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


## The ten map values (sqrt-encoded, LightBaker layout) at p, from the
## chunk's images; black where not baked.
func map_values(p: Vector3) -> Array[Color]:
	var out: Array[Color] = []
	out.resize(MAPS)
	out.fill(Color(0, 0, 0, 0))
	var chunk: Chunk = chunks.get(chunk_of(p))
	if chunk == null:
		return out
	var t := Vector2i(((Vector2(p.x, p.z) - LightBaker.chunk_origin(chunk.coord)) / LightBaker.TEXEL).floor()).clamp(Vector2i.ZERO, Vector2i(LightBaker.RES - 1, LightBaker.RES - 1))
	var shown: Array = chunk.bounce if not chunk.bounce.is_empty() else chunk.bounce1
	for i in chunk.direct.size():
		out[i] = chunk.direct[i].get_pixelv(t)
	for i in chunk.bounce1.size():
		out[4 + i] = chunk.bounce1[i].get_pixelv(t)
	for i in shown.size():
		out[7 + i] = shown[i].get_pixelv(t)
	return out


## Linear irradiance / π on the floor at p (direct + indirect).
func light_at(p: Vector3) -> Color:
	var v := map_values(p)
	var e := v[0].r * v[0].r * LightBaker.E_MAX
	var k := LightBaker.I_MAX
	return Color(e + v[7].r * v[7].r * k, e * 0.97 + v[7].g * v[7].g * k, e * 0.9 + v[7].b * v[7].b * k) / PI
