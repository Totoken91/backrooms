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


func _ready() -> void:
	options = _read_options()
	debug = options.has("debug")
	_build_materials()
	_build_environment()
	_build_ui()
	lights.streamer = streamer
	# Development: isolate each lighting component (lights=0, field=0).
	if options.get("lights") == "0":
		lights.energy = 0.0
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
	if options.get("field") == "0":
		for m in streamer.materials.values():
			m.set_shader_parameter("field_strength", 0.0)
	player.stepped.connect(ambience.step)
	new_exploration(int(options.seed) if options.has("seed") else -1)
	if options.has("view"):
		view(options.view)
	# Development: arbitrary viewpoint, at=x,z,yaw (metres, radians).
	if options.has("at"):
		var a := str(options.at).split(",")
		world.views["at"] = {"position": Vector3(float(a[0]), 0, float(a[1])), "yaw": float(a[2]), "label": "at"}
	_update_ui()
	if options.has("shots"):
		_capture(str(options.shots).split(","), str(options.get("out", "user://")))


## Development: captures QA views once lighting is baked, then quits.
func _capture(names: PackedStringArray, folder: String) -> void:
	_capturing = true
	start()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	for n in names:
		if not view(n):
			continue
		var waited := 0
		while (streamer.pending_bakes() > 0 and waited < 1200) or waited < 90:
			await get_tree().process_frame
			waited += 1
		var path := folder.path_join("godot-s%d-%s%s.png" % [world.seed, n, str(options.get("tag", ""))])
		get_viewport().get_texture().get_image().save_png(path)
		print("capture ", path, " fps ", Engine.get_frames_per_second(), " bakes ", streamer.pending_bakes(), " build max ", streamer.max_build_ms, " phases ", streamer.chunks.get(Vector2i(0, 0)).phases if streamer.chunks.has(Vector2i(0, 0)) else {}, " chunks ", streamer.chunks.size())
	get_tree().quit()


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
	world = LevelWorld.new(value)
	streamer.reset(world)
	player.place(world.spawn.position, world.spawn.yaw)
	streamer.warm(player.global_position)
	lights.refresh_panels()
	_update_ui()


func view(name: String) -> bool:
	if not world.views.has(name):
		return false
	var v: Dictionary = world.views[name]
	player.place(v.position, v.yaw)
	streamer.update(player.global_position)
	lights.refresh_panels()
	return true


func _process(delta: float) -> void:
	var running := started and not paused
	player.active = running
	streamer.update(player.global_position)
	if streamer.generation != _panel_generation:
		_panel_generation = streamer.generation
		lights.refresh_panels()
	lights.update(delta, player.camera, running)
	ambience.set_running(running)
	# Losing the pointer lock (Esc in a browser) pauses the game.
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if _was_captured and not captured and running and not _capturing:
		set_paused(true)
	_was_captured = captured
	if debug:
		_frame_times.append(delta * 1000.0)
		if _frame_times.size() > 240:
			_frame_times.remove_at(0)
		_update_debug()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE:
		if started:
			set_paused(not paused)
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
		"wall": _surface("wallpaper", {"wall_damp": true, "normal_strength": 0.25, "tint": Color(0.93, 1.0, 1.02)}),
		"skirting": _surface("skirting", {"normal_strength": 0.3, "roughness_scale": 0.85, "tint": Color(1.25, 1.2, 1.1)}),
		"floor": _surface("carpet", {"normal_strength": 0.8, "tint": Color(0.86, 0.92, 1.18)}),
		"ceiling": _surface("ceiling", {"ceiling_grid": true, "normal_strength": 0.4}),
	}
	var panel := ShaderMaterial.new()
	panel.shader = preload("res://shaders/panel.gdshader")
	panel.set_shader_parameter("diffuser_tex", _texture("diffuser_albedo"))
	var frame := StandardMaterial3D.new()
	frame.albedo_color = Color(0.82, 0.8, 0.72)
	frame.roughness = 0.5
	frame.metallic = 0.3
	# Diffuser (1.225 × 0.6 m) and its four frame returns, centred on the panel.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var w := 0.6125
	var d := 0.3
	for p in [Vector3(-w, 0, -d), Vector3(w, 0, d), Vector3(w, 0, -d), Vector3(-w, 0, -d), Vector3(-w, 0, d), Vector3(w, 0, d)]:
		st.set_normal(Vector3.DOWN)
		st.set_uv(Vector2((p.x + w) / (2 * w), (p.z + d) / (2 * d)))
		st.add_vertex(p)
	var mesh := st.commit()
	mesh.surface_set_material(0, panel)
	var fr := SurfaceTool.new()
	fr.begin(Mesh.PRIMITIVE_TRIANGLES)
	for r in [Rect2(-w - 0.0125, -d - 0.0125, 2 * w + 0.025, 0.0125), Rect2(-w - 0.0125, d, 2 * w + 0.025, 0.0125), Rect2(-w - 0.0125, -d, 0.0125, 2 * d), Rect2(w, -d, 0.0125, 2 * d)]:
		var a := Vector3(r.position.x, -0.004, r.position.y)
		var b := Vector3(r.end.x, -0.004, r.position.y)
		var c := Vector3(r.end.x, -0.004, r.end.y)
		var e := Vector3(r.position.x, -0.004, r.end.y)
		for p in [a, c, b, a, e, c]:
			fr.set_normal(Vector3.DOWN)
			fr.add_vertex(p)
	fr.commit(mesh)
	mesh.surface_set_material(1, frame)
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
	env.tonemap_exposure = 1.6
	env.glow_enabled = true
	env.glow_intensity = 0.55
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	# No fog: Level 0 has no haze; distance is carried by light and geometry.
	env.fog_enabled = false
	env.adjustment_enabled = true
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
	tv.add_child(_label("ZQSD / WASD · Souris · Maj pour sprinter · Échap pour la pause", 11, Color(0.73, 0.72, 0.65)))
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
	# Development readout.
	var dbg := _label("", 12, Color(0.94, 1.0, 0.6))
	dbg.autowrap_mode = TextServer.AUTOWRAP_OFF
	dbg.position = Vector2(10, 8)
	dbg.add_theme_color_override("font_outline_color", Color.BLACK)
	dbg.add_theme_constant_override("outline_size", 4)
	dbg.visible = debug
	layer.add_child(dbg)
	_ui.debug = dbg


func _update_ui() -> void:
	if _ui.is_empty():
		return
	_ui.title.visible = not started
	_ui.pause.visible = paused
	if world:
		_ui.seed.text = "GRAINE %d · %s · %s" % [world.seed, LevelWorld.VERSION, BUILD]


func _update_debug() -> void:
	var sorted := _frame_times.duplicate()
	sorted.sort()
	var q := func(p: float) -> float: return sorted[mini(sorted.size() - 1, int(p * sorted.size()))] if sorted.size() else 0.0
	var raw := "?"
	if OS.has_feature("web"):
		raw = str(JavaScriptBridge.eval("window.__rawPointer", true))
	_ui.debug.text = "\n".join([
		"FPS %d · image p50 %.1f / p95 %.1f / max %.1f ms" % [Engine.get_frames_per_second(), q.call(0.5), q.call(0.95), q.call(1.0)],
		"souris: capture %s · brute %s · paquets %d · max %.0f px" % [Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, raw, player.look_events, player.look_max_delta],
		"chunks %d · lumière en attente %d · construction %.1f ms (max %.1f)" % [streamer.chunks.size(), streamer.pending_bakes(), streamer.last_build_ms, streamer.max_build_ms],
		"lumières %s · draw calls %d" % [lights.stats(), RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)],
		"position %s · yaw %.2f" % [player.global_position.snapped(Vector3.ONE * 0.01), player.yaw()],
	])
