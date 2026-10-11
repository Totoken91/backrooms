extends Node3D
## Hors Plan — Level 0. Game states (title, playing, paused), world set-up,
## environment and interface. Development options come from the page URL
## (?seed=N, ?view=entry|reveal|interior|east, ?debug) or user command-line
## arguments (-- seed=N view=reveal debug).

const BUILD := "0.4.0-godot"

var world: LevelWorld
var started := false
var paused := false
var debug := false
var options := {}

@onready var player: Player = $Player
@onready var streamer: WorldStreamer = $World
@onready var lights: PanelLights = $Lights
@onready var ambience: Ambience = $Ambience
@onready var environment: WorldEnvironment = $Environment

var _ui := {}
var _was_captured := false
var _panel_generation := -1
var _capturing := false
var _frame_times := PackedFloat32Array()
var _bake_frame_times: Array[float] = []
var _profile_frame_stamp := 0
var _session := 0.0
var flashlight_projector: FlashlightProjector
## Light view (F7): normal, direct only, indirect only, albedo.
var _light_view := 0
const LIGHT_VIEWS := [[0.0, "normale"], [8.0, "directe seule"], [9.0, "indirecte seule"], [6.0, "albédo"]]


func _ready() -> void:
	options = _read_options()
	# Capture A/B: geometric edge coverage, without changing light intensity.
	if options.has("msaa"):
		var mode := [0, 2, 4, 8].find(int(options.msaa))
		if mode >= 0:
			get_viewport().msaa_3d = mode
	debug = options.has("debug")
	_build_materials()
	_build_environment()
	_build_ui()
	lights.streamer = streamer
	var baker := LightBaker.new()
	baker.name = "LightBaker"
	add_child(baker)
	flashlight_projector = FlashlightProjector.new()
	add_child(flashlight_projector)
	# Diagnostic only: longer source reach, within the existing span margin.
	if options.has("direct_reach"):
		baker.direct_reach = clampf(float(options.direct_reach), 1.0, 9.5)
	if options.has("wall_receiver_fraction"):
		baker.wall_receiver_fraction = clampf(float(options.wall_receiver_fraction), 0.1, 0.9)
	if int(options.get("light_bands", 0)) in [4, 8, 16]:
		baker.light_bands = int(options.light_bands)
	streamer.baker = baker
	# Development: isolate each lighting component (lights=0, field=0).
	# Development: tune=param:value,... on surface materials; env.<prop>:value on
	# the Environment (e.g. env.fog_density:0.02).
	if options.has("tune"):
		for pair in str(options.tune).split(","):
			var kv := pair.split(":")
			var value: Variant = float(kv[1]) if kv.size() == 2 else Color(float(kv[1]), float(kv[2]), float(kv[3]))
			if kv[0].begins_with("env."):
				environment.environment.set(kv[0].trim_prefix("env."), value)
			else:
				for m in streamer.materials.values():
					m.set_shader_parameter(kv[0], value)
	# Development: raw output (no tonemap, exposure 1, no glow) for measurements.
	if options.has("raw"):
		environment.environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
		environment.environment.tonemap_exposure = 1.0
		environment.environment.glow_enabled = false
		environment.environment.adjustment_enabled = false
		for m in streamer.materials.values():
			m.set_shader_parameter("raw_output", true)
	if options.get("field") == "0":
		for m in streamer.materials.values():
			m.set_shader_parameter("field_strength", 0.0)
	# Development: flicker=v forces every flicker group to power v.
	if options.has("flicker"):
		lights.force = Vector3.ONE * float(options.flicker)
	player.stepped.connect(ambience.step)
	new_exploration(int(options.seed) if options.has("seed") else -1)
	# QA: inspect a distributed reservation without editing the generation.
	if options.has("site"):
		var parts := str(options.site).split(",")
		var data := world.reservation_at(int(parts[0]), int(parts[1]))
		if data.is_empty():
			printerr("Requested chunk has no reservation: ", options.site)
			get_tree().quit(1)
			return
		world.views = data.views.duplicate(true)
	# Development: arbitrary viewpoint, at=x,z,yaw (metres, radians).
	if options.has("at"):
		var a := str(options.at).split(",")
		world.views["at"] = {"position": Vector3(float(a[0]), 0, float(a[1])), "yaw": float(a[2]), "pitch": float(a[3]) if a.size() > 3 else 0.0, "label": "at"}
	# Development: scout=N adds views dim0..dimN-1 in dim zones of the maze
	# (free cell, no panel within one cell but some within two), for QA shots.
	if options.has("scout"):
		var found := 0
		var rng := RandomNumberGenerator.new()
		rng.seed = world.seed
		for attempt in 4000:
			if found >= int(options.scout):
				break
			var r := int(options.get("scout_r", 24))
			var cx := rng.randi_range(-r, r)
			var cz := rng.randi_range(-r, r)
			if r >= 20 and absi(cx) < 10 and absi(cz) < 10:
				continue
			if world.cell_kind(cx, cz) == 2:
				continue
			# Geometry test: views next to test cells.
			if world.geo_test:
				var near_test := false
				for dz in range(-1, 2):
					for dx in range(-1, 2):
						if world.cell_kind(cx + dx, cz + dz) == 0 and not world.cell_boxes(cx + dx, cz + dz).is_empty():
							near_test = true
				if not near_test:
					continue
			var p := Vector2((cx + 0.5) * LevelWorld.CELL, (cz + 0.5) * LevelWorld.CELL)
			if world.point_blocked(p.x, p.y) or world.light_density(cx, cz) > 0.6:
				continue
			var near := 0
			var around := 0
			for dz in range(-2, 3):
				for dx in range(-2, 3):
					var n := world.cell_fixtures(cx + dx, cz + dz).size()
					if absi(dx) <= 1 and absi(dz) <= 1:
						near += n
					else:
						around += n
			if options.get("scout_any") == null and (near > 0 or around < 1):
				continue
			world.views["dim%d" % found] = {"position": Vector3(p.x, 0, p.y), "yaw": rng.randf() * TAU, "label": "dim"}
			print("scout dim%d " % found, [p.x, p.y, world.views["dim%d" % found].yaw])
			found += 1
	if options.has("audit"):
		_add_audit_views()
	# Custom and audit views must exist before selecting the initial view.
	if options.has("view"):
		view(options.view)
	_update_ui()
	if options.has("export_scene"):
		set_process(false)
		_export_scene(str(options.export_scene))
		get_tree().quit()
		return
	if options.has("bench_flashlight") and not options.has("shots"):
		_bench_when_ready()
	if options.has("shots"):
		_capture(str(options.shots).split(","), str(options.get("out", "user://")))


## Reproducible visual QA views looking across a 40 m streaming boundary.
## Both sides must have player clearance; use a nearby corridor for each seed.
func _add_audit_views() -> void:
	var spawn: Vector3 = world.spawn.position
	for axis in 2:
		var near := spawn.z if axis == 0 else spawn.x
		var odd := floori(near / (LevelWorld.CELL * 2.0)) * 2 + 1
		for attempt in 64:
			var offset := 0 if attempt == 0 else ((attempt + 1) / 2) * (-1 if attempt % 2 else 1)
			var along := (odd + 2 * offset + 0.5) * LevelWorld.CELL
			var a := Vector2(39.4, along) if axis == 0 else Vector2(along, 39.4)
			var b := Vector2(40.6, along) if axis == 0 else Vector2(along, 40.6)
			if world.circle_blocked(a.x, a.y, 0.3) or world.circle_blocked(b.x, b.y, 0.3):
				continue
			world.views["seam-x" if axis == 0 else "seam-z"] = {
				"position": Vector3(a.x, 0, a.y), "yaw": PI / 2.0 if axis == 0 else PI,
				"label": "chunk boundary", "pitch": -0.25,
			}
			var key := "seam-x" if axis == 0 else "seam-z"
			world.views[key + "-across"] = world.views[key].duplicate()
			world.views[key + "-across"].position = Vector3(b.x, 0, b.y)
			world.views[key + "-back"] = world.views[key].duplicate()
			break


## Development: captures QA views once lighting is baked, then quits.
func _capture(names: PackedStringArray, folder: String) -> void:
	_capturing = true
	start()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# The capture window must not take mouse input: views stay as defined.
	player.set_process_unhandled_input(false)
	player.set_process_input(false)
	if options.has("skate"):
		player.toggle_skate()
	for n in names:
		# QA only: physically sample the short clear crossing in both directions.
		# Other view changes remain teleports; this is not a navigation test.
		if options.has("walk_audit") and (n.ends_with("-across") or n.ends_with("-back")) and world.views.has(n):
			var from := player.global_position
			var to: Vector3 = world.views[n].position
			to.y = from.y
			if from.distance_to(to) > 2.0:
				printerr("FAIL: audit crossing must start at the adjacent seam view")
				get_tree().quit(1)
				return
			for step in range(1, 37):
				var p := from.lerp(to, step / 36.0)
				if world.circle_blocked(p.x, p.z, 0.3):
					printerr("FAIL: obstructed audit crossing")
					get_tree().quit(1)
					return
				player.place(p, world.views[n].yaw, -0.25)
				await get_tree().process_frame
		if not view(n):
			printerr("FAIL: missing capture view: ", n)
			get_tree().quit(1)
			return
		var waited := 0
		var bake_started := Time.get_ticks_usec()
		var bake_deadline := bake_started + int(float(options.get("capture_wait",120))*1000000)
		while (streamer.pending_bakes() > 0 and Time.get_ticks_usec() < bake_deadline) or waited < 90:
			await get_tree().process_frame
			waited += 1
			if options.has("profile") and waited % 120 == 0:
				print("capture progress ", n, " frames ", waited, " pending ", streamer.pending_bakes(), " fps ", Engine.get_frames_per_second())
		var bake_wait_ms := (Time.get_ticks_usec() - bake_started) / 1000.0
		# Development: off switches the nearest panel off, then waits for the relight.
		if options.has("off"):
			var lamp = lights.nearest(player.global_position - player.camera.global_transform.basis.z * 5.0, 4.0)
			if lamp != null:
				print("switch off ", lamp.id, " at ", Vector2(lamp.x, lamp.z), " from ", player.global_position)
				lights.switch_off(lamp)
				waited = 0
				bake_started = Time.get_ticks_usec()
				bake_deadline = bake_started + int(float(options.get("capture_wait",120))*1000000)
				while (streamer.pending_bakes() > 0 and Time.get_ticks_usec() < bake_deadline) or waited < 30:
					await get_tree().process_frame
					waited += 1
				bake_wait_ms += (Time.get_ticks_usec() - bake_started) / 1000.0
		if streamer.pending_bakes() > 0:
			printerr("FAIL: unfinished light bake for capture: ", n)
			get_tree().quit(1)
			return
		# Wait for the independent flashlight map as well as the panel bake.
		while player.flashlight.enabled and flashlight_projector.preparing:
			await get_tree().process_frame
		for frame in 3: await get_tree().process_frame
		var path := folder.path_join("godot-s%d-%s%s.png" % [world.seed, n, str(options.get("tag", ""))])
		if get_viewport().get_texture().get_image().save_png(path) != OK:
			printerr("FAIL: cannot save capture: ",path)
			get_tree().quit(1)
			return
		# Compare material and lighting at precisely the same camera/bake.
		if options.has("layers"):
			var saved := {}
			for m in streamer.materials.values():
				saved[m] = m.get_shader_parameter("debug_view")
			for mode in [6, 8, 9, 10]:
				for m in streamer.materials.values():
					m.set_shader_parameter("debug_view", float(mode))
				for frame in 2:
					await get_tree().process_frame
					await RenderingServer.frame_post_draw
				get_viewport().get_texture().get_image().save_png(path.get_basename() + "-layer%d.png" % mode)
			for m in streamer.materials.values():
				m.set_shader_parameter("debug_view", saved[m])
		if options.has("dump"):
			_dump(folder, n)
		print("capture ", path, " fps ", Engine.get_frames_per_second(), " bakes ", streamer.pending_bakes(), " build max ", streamer.max_build_ms, " phases ", streamer.chunks.get(Vector2i(0, 0)).phases if streamer.chunks.has(Vector2i(0, 0)) else {}, " chunks ", streamer.chunks.size())
		if options.has("profile"):
			var frames := _bake_frame_times.duplicate()
			frames.sort()
			var data := {"baker": streamer.baker.timings, "bake_frames": frames.size(), "bake_wait_ms": bake_wait_ms, "light_bands": streamer.baker.light_bands, "build_slice_cpu_max_ms": streamer.max_build_slice_ms}
			if not frames.is_empty():
				data["frame_ms"] = {"p50": frames[frames.size() / 2], "p95": frames[int(frames.size() * 0.95)], "max": frames[-1], "p99": frames[int(frames.size() * 0.99)]}
				for threshold in [16.7, 33.3, 50.0]:
					var count := 0
					for ms in frames:
						if ms > threshold: count += 1
					data.frame_ms["over_%.1f_pct" % threshold] = 100.0 * count / frames.size()
			var f := FileAccess.open(path.get_basename() + "-profile.json", FileAccess.WRITE)
			f.store_string(JSON.stringify(data, "\t"))
	if options.has("bench_flashlight"):
		await _benchmark_flashlight(folder)
	if options.has("hold"):
		await get_tree().create_timer(float(options.hold)).timeout
	# Stop scheduling outer-ring jobs, then let the current coroutine finish.
	# Quitting during a background bake otherwise leaves its resources alive.
	set_process(false)
	for frame in 1000:
		if not streamer._baking: break
		await get_tree().process_frame
	if streamer._baking:
		printerr("FAIL: capture shutdown bake did not finish")
		get_tree().quit(1)
		return
	get_tree().quit()


func _bench_when_ready() -> void:
	while streamer.pending_bakes() > 0 or streamer._baking:
		await get_tree().process_frame
	await _benchmark_flashlight()

## Settled ABBA comparison on the same view and scripted camera path. Frame
## pacing includes the complete renderer; not a GPU timestamp or mouse benchmark.
func _benchmark_flashlight(folder := "") -> void:
	set_process(false)
	player.active = false
	while streamer._baking: await get_tree().process_frame
	var saved_rotation := player.head.rotation
	var saved_enabled: bool = player.flashlight.enabled
	var saved_visible: bool = player.flashlight.visible
	player.flashlight.visible = true
	player.flashlight.enabled = true
	for frame in 90: await get_tree().process_frame
	while flashlight_projector.preparing: await get_tree().process_frame
	var results := []
	for enabled in [false, true, true, false]:
		player.flashlight.enabled = enabled
		var times: Array[float] = []
		var updates := flashlight_projector.shadow_updates
		var bounce_updates := flashlight_projector.bounce_updates
		for frame in 210:
			player.head.rotation = saved_rotation + Vector3(0.025 * sin(frame * 0.04), 0.08 * sin(frame * 0.03), 0.0)
			var stamp := Time.get_ticks_usec()
			await get_tree().process_frame
			if frame >= 30: times.append((Time.get_ticks_usec() - stamp) / 1000.0)
		times.sort()
		results.append({"enabled": enabled,"p50_ms":times[90],"p95_ms":times[171],"max_ms":times.back(),"shadow_updates":flashlight_projector.shadow_updates-updates,"bounce_updates":flashlight_projector.bounce_updates-bounce_updates,"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),"primitives":Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)})
	player.head.rotation = saved_rotation
	player.flashlight.enabled = true
	for frame in 20: await get_tree().process_frame
	var idle_start := flashlight_projector.shadow_updates
	var idle_bounce := flashlight_projector.bounce_updates
	for frame in 30: await get_tree().process_frame
	var report := {"seed":world.seed,"composition":world.composition,"resolution":get_viewport().size,"shadow_resolution":FlashlightProjector.RES,"blocks":results,"idle_shadow_updates":flashlight_projector.shadow_updates-idle_start,"idle_bounce_updates":flashlight_projector.bounce_updates-idle_bounce,"note":"Settled ABBA, same model and scripted camera path, frame pacing incl renderer; not GPU timestamps or real mouse input"}
	print("FLASHLIGHT_BENCH ",JSON.stringify(report))
	if not folder.is_empty():
		var file := FileAccess.open(folder.path_join("flashlight-bench-seed%d.json" % world.seed),FileAccess.WRITE)
		file.store_string(JSON.stringify(report,"\t"))
	player.flashlight.enabled = saved_enabled
	player.flashlight.visible = saved_visible
	player.active = started and not paused
	set_process(true)


## Development (dump): the light maps of the player's chunk as PNG, and the
## decoded light at a few points ahead.
func _dump(folder: String, n: String) -> void:
	var p := player.global_position
	var chunk: Chunk = streamer.chunks.get(WorldStreamer.chunk_of(p))
	if chunk == null:
		return
	for i in chunk.direct.size():
		chunk.direct[i].save_png(folder.path_join("dump-%s-direct%d.png" % [n, i]))
	for i in chunk.bounce.size():
		chunk.bounce[i].save_png(folder.path_join("dump-%s-bounce%d.png" % [n, i]))
	for i in chunk.bounce1.size():
		chunk.bounce1[i].save_png(folder.path_join("dump-%s-bounce1-%d.png" % [n, i]))
	if chunk.ao:
		chunk.ao.save_png(folder.path_join("dump-%s-ao.png" % n))
	var spans := streamer.baker.spans(world, chunk.coord)
	print("player ", p, " chunk ", chunk.coord, " solid at floor ", spans.solid(p.x, 0.05, p.z), " span overflow ", spans.overflow)
	var fwd := -player.global_transform.basis.z
	for dist in [2.0, 4.0, 6.0, 8.0]:
		var w: Vector3 = p + fwd * dist
		var v := streamer.map_values(w)
		var e := func(c: Color, k: float) -> String: return "%.6f/%.6f/%.6f/%.6f" % [c.r * c.r * k, c.g * c.g * k, c.b * c.b * k, c.a * c.a * k]
		print("at %.0fm " % dist, Vector2(w.x, w.z), " direct ", e.call(v[0], LightBaker.E_MAX), " | indirect floor ", e.call(v[8], LightBaker.I_MAX), " ceiling ", e.call(v[9], LightBaker.I_MAX), " walls ", e.call(v[10], LightBaker.I_MAX))


# --- Options --------------------------------------------------------------

func _read_options() -> Dictionary:
	var out := {}
	var args := PackedStringArray()
	if OS.has_feature("web"):
		var search: String = str(JavaScriptBridge.eval("location.search", true))
		args = search.trim_prefix("?").split("&", false)
	else:
		args = OS.get_cmdline_user_args()
	for a in args:
		var kv := a.split("=", true, 1)
		out[kv[0]] = kv[1].uri_decode() if kv.size() > 1 else true
	if out.has("seed") and not (str(out.seed).is_valid_int() and int(out.seed) >= 0 and int(out.seed) <= 0xFFFFFFFF):
		out.erase("seed")
	return out


# --- World ----------------------------------------------------------------

func new_exploration(seed := -1) -> void:
	var value := seed if seed >= 0 else LevelWorld.fresh_seed(world.seed if world else -1)
	world = LevelWorld.new(value, str(options.get("composition", "P07")))
	world.geo_test = options.has("geotest")
	player.flashlight.enabled = options.get("flashlight", "0") == "1"
	flashlight_projector.configure(world, player, streamer.materials)
	lights.world = world
	streamer.reset(world)
	player.place(world.spawn.position, world.spawn.yaw)
	if not options.has("export_scene"):
		streamer.warm(player.global_position)
	lights.refresh_panels()
	_update_ui()


func view(name: String) -> bool:
	if not world.views.has(name):
		return false
	var v: Dictionary = world.views[name]
	player.place(v.position, v.yaw, float(options.pitch) if options.has("pitch") else v.get("pitch", 0.0))
	streamer.update(player.global_position)
	lights.refresh_panels()
	return true


func _process(delta: float) -> void:
	player.flashlight.visible = started and options.get("viewmodel", "1") != "0"
	var running := started and not paused
	player.active = running
	streamer.update(player.global_position)
	if streamer.generation != _panel_generation:
		_panel_generation = streamer.generation
		lights.refresh_panels()
	lights.update(delta, running)
	ambience.set_running(running)
	# Losing the pointer lock (Esc in a browser) pauses the game.
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if _was_captured and not captured and running and not _capturing:
		set_paused(true)
	_was_captured = captured
	player.light = streamer.light_at(player.global_position)
	if running:
		_session += delta
	_frame_times.append(delta * 1000.0)
	if options.has("profile"):
		var stamp := Time.get_ticks_usec()
		if streamer.pending_bakes() > 0 and _profile_frame_stamp > 0:
			_bake_frame_times.append((stamp - _profile_frame_stamp) / 1000.0)
		_profile_frame_stamp = stamp
	if _frame_times.size() > 240:
		_frame_times.remove_at(0)
	_ui.skate.visible = player.skating and not debug
	_ui.lamp.visible = started and not paused and not debug and not _capturing
	_ui.lamp.text = "F · éteindre la lampe" if player.flashlight.enabled else "F · allumer la lampe"
	if debug:
		_ui.graph.push(delta * 1000.0)
		_update_debug()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE:
		if started:
			set_paused(not paused)
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F3:
		debug = not debug
		_ui.debug_panel.visible = debug
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_K:
		if started and not paused:
			player.toggle_skate()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F8:
		# Development: switch off the nearest panel (its light is baked away).
		var f = lights.nearest(player.global_position)
		if f != null:
			lights.switch_off(f)
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F7:
		_light_view = (_light_view + 1) % LIGHT_VIEWS.size()
		for m in streamer.materials.values():
			m.set_shader_parameter("debug_view", LIGHT_VIEWS[_light_view][0])
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if started and not paused and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func start() -> void:
	started = true
	paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_update_ui()


func set_paused(value: bool) -> void:
	if not started:
		return
	paused = value
	if paused:
		_was_captured = false
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_update_ui()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and started and not paused and not _capturing:
		set_paused(true)


# --- Look -------------------------------------------------------------------

func _texture(name: String) -> Texture2D:
	return load("res://assets/textures/%s.png" % name)


func _surface(base: String, extra := {}) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = preload("res://shaders/surface.gdshader")
	m.set_shader_parameter("albedo_tex", _texture(base + "_albedo"))
	m.set_shader_parameter("normal_tex", _texture(base + "_normal"))
	m.set_shader_parameter("rough_tex", _texture(base + "_rough"))
	for k in extra:
		m.set_shader_parameter(k, extra[k])
	return m


func _build_materials() -> void:
	streamer.materials = {
		"wall": _surface("wallpaper", {"wall_damp": true, "tint": Color(0.95, 1.0, 0.7), "roughness": 0.85}),
		"skirting": _surface("wallpaper", {"tint": Color(0.95, 1.0, 0.7), "roughness": 0.85}),
		"floor": _surface("carpet", {"tint": Color(0.84, 0.86, 0.72), "roughness": 0.95}),
		"ceiling": _surface("ceiling", {"ceiling_grid": true, "tint": Color(1.1, 1.1, 1.05)}),
	}
	for m in streamer.materials.values():
		m.set_shader_parameter("ceiling_height", LevelWorld.HEIGHT)
		m.set_shader_parameter("tile_size", LevelWorld.TILE)
	var panel := ShaderMaterial.new()
	panel.shader = preload("res://shaders/panel.gdshader")
	panel.set_shader_parameter("diffuser_tex", _texture("diffuser_albedo"))
	# Diffuser filling its ceiling tile, no visible frame (as in the references).
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var w := LevelWorld.PANEL * 0.5
	var d := LevelWorld.PANEL * 0.5
	for p in [Vector3(-w, 0, -d), Vector3(w, 0, d), Vector3(w, 0, -d), Vector3(-w, 0, -d), Vector3(-w, 0, d), Vector3(w, 0, d)]:
		st.set_normal(Vector3.DOWN)
		st.set_uv(Vector2((p.x + w) / (2 * w), (p.z + d) / (2 * d)))
		st.add_vertex(p)
	var mesh := st.commit()
	mesh.surface_set_material(0, panel)
	streamer.panel_mesh = mesh


func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.03, 0.028, 0.02)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1.0, 0.92, 0.72)
	env.ambient_light_energy = 0.04
	# AgX desaturates highlights like the reference renders (pale walls near
	# the panels instead of lemon yellow). Levels calibrated on USER-LUMIERE.
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.27
	env.glow_enabled = true
	env.glow_intensity = 0.2
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = 1.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	# No fog: Level 0 has no haze; distance is carried by light and geometry.
	env.fog_enabled = false
	# Neutral adjustments still add a post-pass in Compatibility, including
	# another approximate sRGB round trip that crushes dim colours.
	env.adjustment_enabled = false
	env.adjustment_saturation = 1.0
	environment.environment = env


# --- Interface ----------------------------------------------------------------

func _panel_style(alpha: float) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.105, 0.11, 0.086, alpha)
	s.border_color = Color(1, 1, 1, 0.09)
	s.set_border_width_all(1)
	s.set_corner_radius_all(5)
	s.set_content_margin_all(28)
	return s


func _label(text: String, size: int, color := Color(0.93, 0.93, 0.89)) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _button(text: String, primary := false) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 44)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	if primary:
		var s := StyleBoxFlat.new()
		s.bg_color = Color(0.83, 0.78, 0.58)
		s.set_corner_radius_all(3)
		s.set_content_margin_all(12)
		b.add_theme_stylebox_override("normal", s)
		var hover := s.duplicate()
		hover.bg_color = Color(0.88, 0.84, 0.65)
		b.add_theme_stylebox_override("hover", hover)
		b.add_theme_color_override("font_color", Color(0.14, 0.13, 0.09))
		b.add_theme_color_override("font_hover_color", Color(0.14, 0.13, 0.09))
	return b


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	# Title card.
	var title := PanelContainer.new()
	title.add_theme_stylebox_override("panel", _panel_style(0.88))
	title.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	title.position = Vector2(60, -60)
	title.grow_vertical = Control.GROW_DIRECTION_BEGIN
	title.custom_minimum_size = Vector2(390, 0)
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", 12)
	title.add_child(tv)
	tv.add_child(_label("NIVEAU 0 · EXPLORATION", 11, Color(0.82, 0.78, 0.66)))
	tv.add_child(_label("HORS PLAN", 46))
	tv.add_child(_label("Le vide, les murs jaunes, le bruit des néons.", 14, Color(0.8, 0.79, 0.73)))
	var go := _button("Explorer", true)
	go.pressed.connect(start)
	tv.add_child(go)
	tv.add_child(_label("ZQSD / WASD · Souris · Maj pour sprinter · F lampe · K skate · F3 debug · Échap pour la pause", 11, Color(0.73, 0.72, 0.65)))
	var build := _label("ÉTUDE %s · NOUVELLE GRAINE À CHAQUE LANCEMENT" % BUILD, 9, Color(0.64, 0.62, 0.55))
	tv.add_child(build)
	layer.add_child(title)
	_ui.title = title
	# Pause menu.
	var shade := ColorRect.new()
	shade.color = Color(0.067, 0.07, 0.055, 0.78)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.add_child(center)
	var pause := PanelContainer.new()
	pause.add_theme_stylebox_override("panel", _panel_style(0.96))
	pause.custom_minimum_size = Vector2(420, 0)
	center.add_child(pause)
	var pv := VBoxContainer.new()
	pv.add_theme_constant_override("separation", 10)
	pause.add_child(pv)
	pv.add_child(_label("HORS PLAN · NIVEAU 0", 11, Color(0.82, 0.78, 0.66)))
	pv.add_child(_label("Pause", 30))
	var resume := _button("Reprendre", true)
	resume.pressed.connect(func(): set_paused(false))
	pv.add_child(resume)
	var again := _button("Nouvelle exploration")
	again.pressed.connect(func(): new_exploration(); set_paused(false))
	pv.add_child(again)
	var sens_label := _label("Sensibilité souris : 100 %", 12, Color(0.84, 0.81, 0.68))
	pv.add_child(sens_label)
	var slider := HSlider.new()
	slider.min_value = 20
	slider.max_value = 250
	slider.step = 5
	slider.value = 100
	slider.value_changed.connect(func(v): player.sensitivity_scale = v / 100.0; sens_label.text = "Sensibilité souris : %d %%" % v)
	pv.add_child(slider)
	var sound := CheckButton.new()
	sound.text = "Son"
	sound.button_pressed = true
	sound.toggled.connect(func(on): ambience.enabled = on)
	pv.add_child(sound)
	var seed_label := _label("", 9, Color(0.64, 0.62, 0.55))
	pv.add_child(seed_label)
	_ui.pause = shade
	_ui.seed = seed_label
	# Debug interface (F3): readout and frame-time graph.
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.02, 0.015, 0.72)
	style.set_content_margin_all(10)
	style.set_corner_radius_all(3)
	panel.add_theme_stylebox_override("panel", style)
	panel.position = Vector2(10, 10)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dv := VBoxContainer.new()
	dv.add_theme_constant_override("separation", 6)
	panel.add_child(dv)
	var dbg := _label("", 12, Color(0.94, 1.0, 0.72))
	dbg.autowrap_mode = TextServer.AUTOWRAP_OFF
	dbg.add_theme_constant_override("line_spacing", 1)
	dv.add_child(dbg)
	var graph := FrameGraph.new()
	graph.custom_minimum_size = Vector2(360, 56)
	dv.add_child(graph)
	panel.visible = debug
	layer.add_child(panel)
	_ui.debug = dbg
	_ui.debug_panel = panel
	_ui.graph = graph
	# Skateboard reminder outside the debug view.
	var skate := _label("SKATE · K pour descendre · Maj pour accélérer · S pour freiner", 11, Color(0.94, 0.92, 0.82))
	skate.autowrap_mode = TextServer.AUTOWRAP_OFF
	skate.add_theme_color_override("font_outline_color", Color.BLACK)
	skate.add_theme_constant_override("outline_size", 4)
	skate.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	skate.position = Vector2(14, -30)
	skate.visible = false
	layer.add_child(skate)
	_ui.skate = skate
	var lamp := _label("F · allumer la lampe", 11, Color(0.94,0.92,0.82))
	lamp.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	lamp.position = Vector2(-180,-30)
	lamp.add_theme_color_override("font_outline_color",Color.BLACK)
	lamp.add_theme_constant_override("outline_size",3)
	lamp.visible = false
	layer.add_child(lamp)
	_ui.lamp = lamp


func _update_ui() -> void:
	if _ui.is_empty():
		return
	_ui.title.visible = not started
	_ui.pause.visible = paused
	if world:
		_ui.seed.text = "GRAINE %d · %s · %s" % [world.seed, world.version, BUILD]


func _update_debug() -> void:
	var sorted := _frame_times.duplicate()
	sorted.sort()
	var q := func(p: float) -> float: return sorted[mini(sorted.size() - 1, int(p * sorted.size()))] if sorted.size() else 0.0
	var p := player.global_position
	var cell := Vector2i(floori(p.x / LevelWorld.CELL), floori(p.z / LevelWorld.CELL))
	var kind := world.cell_kind(cell.x, cell.y)
	var zone: String = ["labyrinthe", "mur", "site " + world.composition][clampi(kind, 0, 2)]
	var yaw_deg := fposmod(rad_to_deg(player.yaw()), 360.0)
	var heading: String = ["N", "NE", "E", "SE", "S", "SO", "O", "NO"][int(round(yaw_deg / 45.0)) % 8]
	var light := streamer.light_at(p)
	var mode := "skate" if player.skating else ("sprint" if Input.is_physical_key_pressed(KEY_SHIFT) else "marche")
	var mb := func(bytes: float) -> String: return "%.0f Mo" % (bytes / 1048576.0)
	var size := get_viewport().get_visible_rect().size
	_ui.debug.text = "
".join([
		"HORS PLAN · DEBUG    F3 masquer · K skate · F7 vue lumière · F8 éteindre le néon proche",
		"FPS %d · image p50 %.1f / p95 %.1f / max %.1f ms · %dx%d" % [Engine.get_frames_per_second(), q.call(0.5), q.call(0.95), q.call(1.0), size.x, size.y],
		"graine %d · %s · %s" % [world.seed, world.version, BUILD],
		"position x %.2f  y %.2f  z %.2f · cellule (%d, %d) · chunk %s" % [p.x, p.y, p.z, cell.x, cell.y, WorldStreamer.chunk_of(p)],
		"cap %.0f° %s · tangage %.0f°" % [yaw_deg, heading, rad_to_deg(player.pitch())],
		"%s · %.1f m/s (%.0f km/h) · parcouru %.0f m · session %d:%02d" % [mode, player.speed, player.speed * 3.6, player.walked, int(_session) / 60, int(_session) % 60],
		"lampe F : %s · carte ombre %d² · mises à jour %d" % ["allumée" if player.flashlight.enabled else "éteinte", FlashlightProjector.RES, flashlight_projector.shadow_updates],
		"zone %s · densité néons %.2f · néons dans la cellule %d" % [zone, world.light_density(cell.x, cell.y), world.cell_fixtures(cell.x, cell.y).size()],
		"lumière au sol E/π %.3f (r %.3f g %.3f b %.3f) · vue %s" % [(light.r + light.g + light.b) / 3.0, light.r, light.g, light.b, LIGHT_VIEWS[_light_view][1]],
		"clignotement groupes %.2f / %.2f / %.2f · néons éteints %d · zones à recalculer %d" % [lights.group_power.x, lights.group_power.y, lights.group_power.z, world.panels_off.size(), streamer.relighting()],
		"chunks %d · calculs lumière en attente %d · bake %.1f ms (n° %d) · construction %.1f ms (max %.1f)" % [streamer.chunks.size(), streamer.pending_bakes(), streamer.baker.last_ms, streamer.baker.renders, streamer.last_build_ms, streamer.max_build_ms],
		"draw calls %d · primitives %d · VRAM %s · mémoire %s" % [RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME), RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME), mb.call(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)), mb.call(Performance.get_monitor(Performance.MEMORY_STATIC))],
	])


## Development: writes the boxes, panels and QA views around the spawn as
## JSON, for the Blender ground-truth renders (tools/blender/render_scene.py).
func _export_scene(path: String) -> void:
	var boxes := {}
	var fixtures := {}
	var ceilings := []
	var ceiling_steps := []
	var s: Vector3 = world.spawn.position
	var c := Vector2i(floori(s.x / LevelWorld.CELL), floori(s.z / LevelWorld.CELL))
	for z in range(c.y - 24, c.y + 25):
		for x in range(c.x - 24, c.x + 25):
			ceilings.append([x, z, world.ceiling_height(x, z)])
			for face in world.ceiling_steps(x, z):
				var vertices := []
				var order := [0, 1, 2, 3] if (face[1] - face[0]).cross(face[2] - face[0]).dot(face[4]) > 0 else [0, 3, 2, 1]
				for i in order:
					vertices.append([face[i].x, face[i].y, face[i].z])
				ceiling_steps.append(vertices)
			for b in world.cell_boxes(x, z):
				boxes[b.id] = [b.x0, b.z0, b.x1, b.z1, b.y0, b.y1]
			for f in world.cell_fixtures(x, z):
				fixtures[f.id] = [f.x0, f.z0, f.x1, f.z1, PanelLights.power(0.0, f.seed, true), f.y]
			if world.cell_kind(x, z) != 1:
				boxes["floor%d,%d" % [x, z]] = null
	var floors := []
	for k in boxes.keys():
		if boxes[k] == null:
			var xz: PackedStringArray = k.trim_prefix("floor").split(",")
			floors.append([int(xz[0]), int(xz[1])])
			boxes.erase(k)
	var views := {}
	for k in world.views:
		var v: Dictionary = world.views[k]
		views[k] = [v.position.x, v.position.z, v.yaw]
	var data := {"cell": LevelWorld.CELL, "height": LevelWorld.HEIGHT, "eye": Player.EYE, "fov": player.camera.fov,
		"boxes": boxes.values(), "fixtures": fixtures.values(), "floors": floors, "ceilings": ceilings, "ceiling_steps": ceiling_steps, "views": views, "seed": world.seed, "generator_version": world.version}
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	print("scene: %d boxes, %d panels" % [boxes.size(), fixtures.size()])
