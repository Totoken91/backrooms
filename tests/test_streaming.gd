extends SceneTree
## Real streaming scheduler and GPU slot uploads, with deterministic delayed
## bake data. Isolates lifetime/invalidation races from transport accuracy.
var failures := 0

class DelayedBaker extends LightBaker:
	var images := {}
	func _ready() -> void:
		pass
	func bind_light_maps(_maps: Texture2DArray) -> void:
		pass
	func set_slots(_slots: PackedVector2Array) -> void:
		pass
	func tiles(w: LevelWorld, k: Vector2i, count: int) -> Array:
		var key := Vector3i(posmod(k.x, 251), posmod(k.y, 251), int(w.panels_off.has("test") and k.x in [-1, 0] and k.y in [-1, 0]))
		if not images.has(key):
			var im := Image.create(RES, RES, false, Image.FORMAT_RGBA8)
			im.fill(Color(float(key.x) / 255.0, float(key.y) / 255.0, float(key.z + 1) / 255.0, 1))
			images[key] = im
		var result := []
		for i in count: result.append(images[key])
		return result
	func direct(w: LevelWorld, k: Vector2i) -> Array:
		var result := tiles(w, k, 5)
		await get_tree().process_frame
		return result
	func indirect(w: LevelWorld, k: Vector2i, _second: bool) -> Array:
		var result := tiles(w, k, 3)
		await get_tree().process_frame
		return result

class Scheduler extends WorldStreamer:
	func _build(k: Vector2i, _slice_ms := INF) -> void:
		if chunks.has(k): return
		var c := Chunk.new()
		c.coord = k
		c.built = true
		c.ao = _white
		add_child(c)
		chunks[k] = c
		generation += 1
		_upload(c)

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: ", label)

func settled(s: WorldStreamer, p: Vector3) -> void:
	var done := false
	for frame in 1200:
		s.update(p)
		await process_frame
		if s.pending_bakes() == 0 and not s._baking:
			done = true
			break
	check(done, "scheduler terminates at %s" % p)
	for dz in range(-s.RADIUS, s.RADIUS + 1):
		for dx in range(-s.RADIUS, s.RADIUS + 1):
			var k := s.center + Vector2i(dx, dz)
			check(s.slot_chunk[s.slot_of(k)] == Vector2(k), "slot owner %s" % k)
			var c: Chunk = s.chunks.get(k)
			if c == null: continue
			check(c.bounce.size() == 3 and c.relight == 0, "complete bounce %s" % k)
			var expected: Array = s.baker.tiles(s.world, k, 5)
			check(c.direct[0].get_data() == expected[0].get_data(), "direct current %s" % k)
			check(s.light_maps.get_layer_data(s.slot_of(k) * s.MAPS).get_data() == expected[0].get_data(), "GPU slot current %s" % k)

func run() -> void:
	var s := Scheduler.new()
	var b := DelayedBaker.new()
	root.add_child(b)
	root.add_child(s)
	s.baker = b
	s.reset(LevelWorld.new(99))
	await settled(s, Vector3.ZERO)
	# Extinction during a direct pass must not accept the older snapshot.
	var c: Chunk = s.chunks[Vector2i.ZERO]
	c.relight = 1
	s._bake_direct(c)
	s.world.panels_off["test"] = true
	s.relight(Vector2(1, 1))
	await process_frame
	check(c.relight == 1, "in-flight direct invalidated, direct stage still pending")
	await settled(s, Vector3.ZERO)
	check(s.discarded_bakes == 1, "obsolete direct result discarded")
	# A new change during the second gather must restart at the first gather,
	# including a neighbour which is already waiting at relight stage three.
	var neighbour: Chunk = s.chunks[Vector2i(1, 0)]
	neighbour.relight = 3
	s._bake_gather(neighbour, true)
	s.relight(Vector2(1, 1))
	await process_frame
	check(neighbour.relight == 2, "neighbour invalidation restarts first gather")
	await settled(s, Vector3.ZERO)
	check(s.discarded_bakes == 2, "obsolete gather result discarded")
	# Extinction during the very first direct pass (there is no old map yet).
	c.direct.clear()
	c.bounce1.clear()
	c.bounce.clear()
	s._bake_direct(c)
	s.relight(Vector2(1, 1))
	await process_frame
	check(c.direct.is_empty() and c.relight == 1, "initial direct pass invalidated")
	await settled(s, Vector3.ZERO)
	# Cross negative boundaries, reuse modulo slots seven chunks away, return.
	for p in [Vector3(-0.1, 0, -0.1), Vector3(40.1, 0, 0), Vector3(280.1, 0, 0), Vector3.ZERO]:
		await settled(s, p)
	check(s.world.panels_off.has("test"), "extinction survives unload/reload")
	# New world while a bake is suspended: no old result may be published.
	c = s.chunks[Vector2i.ZERO]
	c.relight = 1
	s._bake_direct(c)
	s.reset(LevelWorld.new(7))
	await settled(s, Vector3.ZERO)
	check(s.world.panels_off.is_empty(), "new world has independent panel state")
	s.queue_free()
	b.queue_free()
	await process_frame
	if failures == 0:
		print("PASS: streaming scheduler — negative boundaries, slot reuse, return, in-flight extinction, reset, GPU slot contents")
	quit(1 if failures else 0)
