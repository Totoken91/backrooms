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
var _session := 0.0
## Light view (F7): normal, direct only, indirect only, albedo.
var _light_view := 0
const LIGHT_VIEWS := [[0.0, "normale"], [8.0, "directe seule"], [9.0, "indirecte seule"], [6.0, "albédo"]]


func _ready() -> void:
	options = _read_options()
	debug = options.has("debug")
	_build_materials()
	_build_environment()
	_build_ui()
	lights.streamer = streamer
	var baker := LightBaker.new()
	baker.name = "LightBaker"
	add_child(baker)
	streamer.baker = baker
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
	# Development: raw output (no tonemap, exposure 1, no glow) for measurements.
	if options.has("raw"):
		environment.environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
		environment.environment.tonemap_exposure = 1.0
		environment.environment.glow_enabled = false
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
			var cx := rng.randi_range(-24, 24)
			var cz := rng.randi_range(-24, 24)
			if absi(cx) < 10 and absi(cz) < 10:
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
	_update_ui()
	if options.has("export_scene"):
		_export_scene(str(options.export_scene))
		get_tree().quit()
		return
	if options.has("shots"):
		_capture(str(options.shots).split(","), str(options.get("out", "user://")))


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
		if not view(n):
			continue
		var waited := 0
		while (streamer.pending_bakes() > 0 and waited < 4000) or waited < 90:
			await get_tree().process_frame
			waited += 1
		var path := folder.path_join("godot-s%d-%s%s.png" % [world.seed, n, str(options.get("tag", ""))])
		get_viewport().get_texture().get_image().save_png(path)
		if options.has("dump"):
			for i in streamer.light_images.size():
				streamer.light_images[i].save_png(folder.path_join("dump-%s-%d.png" % [n, i]))
			streamer.ao_image.save_png(folder.path_join("dump-%s-ao.png" % n))
			var c: Chunk = streamer.chunks.get(WorldStreamer.chunk_of(player.global_position))
			if c:
				streamer.baker._occupancy(world, c.coord).save_png(folder.path_join("dump-%s-occ.png" % n))
				var origin := LightBaker.chunk_origin(c.coord)
				var r := streamer.region_rect()
				for t in [Vector2i(20, 20), Vector2i(40, 30), Vector2i(80, 80), Vector2i(120, 60), Vector2i(10, 140), Vector2i(150, 10), Vector2i(100, 120)]:
					var p := origin + (Vector2(t) + Vector2(0.5, 0.5)) * LightBaker.TEXEL
					var e := 0.0
					var near := 0
					for z in range(floori(p.y / 2.5) - 4, floori(p.y / 2.5) + 5):
						for x in range(floori(p.x / 2.5) - 4, floori(p.x / 2.5) + 5):
							for f in world.cell_fixtures(x, z):
								var v := Vector3(f.x - p.x, 2.79 - 0.02, f.z - p.y)
								var d2 := v.length_squared()
								var oy := v.y / sqrt(d2)
								e += PanelLights.power(0, f.seed, true) * streamer.baker.panel_radiance * 0.735 * oy * oy / d2
								near += 1
					var px := Vector2i(((p - r.position) / LightBaker.TEXEL).floor())
					var stored := streamer.light_images[0].get_pixelv(px)
					var single: Image = c.direct[0]
					var fl := single.get_pixel(t.x, LightBaker.RES - 1 - t.y)
					print("texel ", t, " cpu E ", e, " gpu ", single.get_pixelv(t).r ** 2 * 6.0, " flipped ", fl.r ** 2 * 6.0)
			print("light_rect ", streamer.region_rect(), " baker ms ", streamer.baker.last_ms)
			var pp := player.global_position
			var cc := WorldStreamer.chunk_of(pp)
			var occ_img: Image = streamer.baker._occupancy(world, cc)
			var op := (Vector2(pp.x, pp.z) - LightBaker.chunk_origin(cc) + Vector2(LightBaker.MARGIN, LightBaker.MARGIN)) / LightBaker.OCC_TEXEL
			var cbx := []
			for b in world.cell_boxes(floori(pp.x / 2.5), floori(pp.z / 2.5)):
				cbx.append([b.id, b.x0, b.z0, b.x1, b.z1, b.occluder])
			var kinds := []
			for dz in range(-2, 3):
				var row := ""
				for dx in range(-2, 3):
					row += str(world.cell_kind(floori(pp.x / 2.5) + dx, floori(pp.z / 2.5) + dz))
				kinds.append(row)
			print("kinds ", kinds)
			print("player ", pp, " chunk ", cc, " blocked ", world.point_blocked(pp.x, pp.z), " occ ", occ_img.get_pixelv(Vector2i(op)).r, " cell boxes ", cbx)
			var fwd := -player.global_transform.basis.z
			for dist in [2.0, 4.0, 6.0, 8.0]:
				var w: Vector3 = player.global_position + fwd * dist
				var px := Vector2i(((Vector2(w.x, w.z) - streamer.region_rect().position) / LightBaker.TEXEL).floor())
				var vals := []
				for i in 10:
					var col: Color = streamer.light_images[i].get_pixelv(px)
					var scale := LightBaker.E_MAX if i < 4 else LightBaker.I_MAX
					vals.append("%.2f/%.2f/%.2f/%.2f" % [col.r * col.r * scale, col.g * col.g * scale, col.b * col.b * scale, col.a * col.a * scale])
				print("at ", dist, "m ", Vector2(w.x, w.z), " D0 ", vals[0], " D1 ", vals[1], " | B1 floor ", vals[4], " ceil ", vals[5], " wall ", vals[6], " | B2 floor ", vals[7], " ceil ", vals[8], " wall ", vals[9])
				var e_cpu := 0.0
				var near := []
				for z in range(floori(w.z / 2.5) - 4, floori(w.z / 2.5) + 5):
					for x in range(floori(w.x / 2.5) - 4, floori(w.x / 2.5) + 5):
						for f in world.cell_fixtures(x, z):
							var v := Vector3(f.x - w.x, 2.77, f.z - w.z)
							var d2 := v.length_squared()
							e_cpu += PanelLights.power(0, f.seed, true) * streamer.baker.panel_radiance * 0.735 * (v.y * v.y / d2) / d2
							if d2 < 30.0: near.append(Vector2(f.x, f.z))
				print("   cpu floor E ", e_cpu, " panels <5.5m ", near)
			if c:
				var origin := LightBaker.chunk_origin(c.coord)
				var occ: Image = streamer.baker._occupancy(world, c.coord)
				var view_img := Image.create(640, 640, false, Image.FORMAT_RGB8)
				var tile0: Image = c.direct[0]
				for y in 640:
					for x in 640:
						var v := tile0.get_pixel(x / 4, y / 4).r
						var o := occ.get_pixel(int(LightBaker.MARGIN / LightBaker.OCC_TEXEL) + x / 2, int(LightBaker.MARGIN / LightBaker.OCC_TEXEL) + y / 2).r
						view_img.set_pixel(x, y, Color(v, v, v + o * 0.6))
				for z in range(c.coord.y * 16, c.coord.y * 16 + 16):
					for x in range(c.coord.x * 16, c.coord.x * 16 + 16):
						for f in world.cell_fixtures(x, z):
							var q := (Vector2(f.x, f.z) - origin) * 16.0
							view_img.fill_rect(Rect2i(int(q.x) - 9, int(q.y) - 4, 19, 9), Color(1, 0, 0))
				view_img.save_png(folder.path_join("dump-%s-floormap.png" % n))
			streamer.baker._direct.set_shader_parameter("calibrate", true)
			var cal: Array = await streamer.baker._render(streamer.baker._direct)
			streamer.baker._direct.set_shader_parameter("calibrate", false)
			for t in [Vector2i(0, 0), Vector2i(10, 150), Vector2i(150, 10)]:
				for k in 3:
					var px: Color = cal[k].get_pixelv(t)
					print("calib tile ", k, " pixel ", t, " -> local ", Vector2(px.r, px.g) * 160.0, " tile ", px.b * 4.0, " a ", px.a)
		print("capture ", path, " fps ", Engine.get_frames_per_second(), " bakes ", streamer.pending_bakes(), " build max ", streamer.max_build_ms, " phases ", streamer.chunks.get(Vector2i(0, 0)).phases if streamer.chunks.has(Vector2i(0, 0)) else {}, " chunks ", streamer.chunks.size())
	if options.has("hold"):
		await get_tree().create_timer(float(options.hold)).timeout
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
	player.place(v.position, v.yaw, float(options.pitch) if options.has("pitch") else v.get("pitch", 0.0))
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
	player.light = streamer.light_at(player.global_position)
	if running:
		_session += delta
	_frame_times.append(delta * 1000.0)
	if _frame_times.size() > 240:
		_frame_times.remove_at(0)
	_ui.skate.visible = player.skating and not debug
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
	env.tonemap_exposure = 1.27
	env.glow_enabled = true
	env.glow_intensity = 0.2
	env.glow_bloom = 0.0
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
	tv.add_child(_label("ZQSD / WASD · Souris · Maj pour sprinter · K skate · F3 debug · Échap pour la pause", 11, Color(0.73, 0.72, 0.65)))
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
	var p := player.global_position
	var cell := Vector2i(floori(p.x / LevelWorld.CELL), floori(p.z / LevelWorld.CELL))
	var kind := world.cell_kind(cell.x, cell.y)
	var zone: String = ["labyrinthe", "mur", "site C01"][clampi(kind, 0, 2)]
	var yaw_deg := fposmod(rad_to_deg(player.yaw()), 360.0)
	var heading: String = ["N", "NE", "E", "SE", "S", "SO", "O", "NO"][int(round(yaw_deg / 45.0)) % 8]
	var light := streamer.light_at(p)
	var mode := "skate" if player.skating else ("sprint" if Input.is_physical_key_pressed(KEY_SHIFT) else "marche")
	var mb := func(bytes: float) -> String: return "%.0f Mo" % (bytes / 1048576.0)
	var size := get_viewport().get_visible_rect().size
	_ui.debug.text = "
".join([
		"HORS PLAN · DEBUG    F3 masquer · K skate · F7 vue lumière · Échap pause",
		"FPS %d · image p50 %.1f / p95 %.1f / max %.1f ms · %dx%d" % [Engine.get_frames_per_second(), q.call(0.5), q.call(0.95), q.call(1.0), size.x, size.y],
		"graine %d · %s · %s" % [world.seed, LevelWorld.VERSION, BUILD],
		"position x %.2f  y %.2f  z %.2f · cellule (%d, %d) · chunk %s" % [p.x, p.y, p.z, cell.x, cell.y, WorldStreamer.chunk_of(p)],
		"cap %.0f° %s · tangage %.0f°" % [yaw_deg, heading, rad_to_deg(player.pitch())],
		"%s · %.1f m/s (%.0f km/h) · parcouru %.0f m · session %d:%02d" % [mode, player.speed, player.speed * 3.6, player.walked, int(_session) / 60, int(_session) % 60],
		"zone %s · densité néons %.2f · néons dans la cellule %d" % [zone, world.light_density(cell.x, cell.y), world.cell_fixtures(cell.x, cell.y).size()],
		"lumière au sol E/π %.3f (r %.3f g %.3f b %.3f) · vue %s" % [(light.r + light.g + light.b) / 3.0, light.r, light.g, light.b, LIGHT_VIEWS[_light_view][1]],
		"chunks %d · calculs lumière en attente %d · bake %.1f ms (n° %d) · construction %.1f ms (max %.1f)" % [streamer.chunks.size(), streamer.pending_bakes(), streamer.baker.last_ms, streamer.baker.renders, streamer.last_build_ms, streamer.max_build_ms],
		"draw calls %d · primitives %d · VRAM %s · mémoire %s" % [RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME), RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME), mb.call(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)), mb.call(Performance.get_monitor(Performance.MEMORY_STATIC))],
	])


## Development: writes the boxes, panels and QA views around the spawn as
## JSON, for the Blender ground-truth renders (tools/blender/render_scene.py).
func _export_scene(path: String) -> void:
	var boxes := {}
	var fixtures := {}
	var s: Vector3 = world.spawn.position
	var c := Vector2i(floori(s.x / LevelWorld.CELL), floori(s.z / LevelWorld.CELL))
	for z in range(c.y - 14, c.y + 15):
		for x in range(c.x - 14, c.x + 15):
			for b in world.cell_boxes(x, z):
				boxes[b.id] = [b.x0, b.z0, b.x1, b.z1, b.y0, b.y1]
			for f in world.cell_fixtures(x, z):
				fixtures[f.id] = [f.x0, f.z0, f.x1, f.z1, PanelLights.power(0.0, f.seed, true)]
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
		"boxes": boxes.values(), "fixtures": fixtures.values(), "floors": floors, "views": views, "seed": world.seed}
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	print("scene: %d boxes, %d panels" % [boxes.size(), fixtures.size()])
