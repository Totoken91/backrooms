extends SceneTree
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: ",label)
func run() -> void:
	var p := FlashlightProjector.new()
	root.add_child(p)
	var map := SpanMap._create(Vector2(-4,-4),64,0.125)
	for z in 64:
		for x in 64:
			var px := -4 + (x + 0.5) * 0.125
			map._write(x,z, [[-10.0,3.2]] if px >= 0.5 and px < 0.625 else [[-10.0,0.0],[3.2,100.0]])
	p.shadow.set_shader_parameter("span_a",ImageTexture.create_from_image(map.a))
	p.shadow.set_shader_parameter("span_b",ImageTexture.create_from_image(map.b))
	p.shadow.set_shader_parameter("occ_origin",map.origin)
	p.shadow.set_shader_parameter("occ_size",Vector2(64,64))
	p.shadow.set_shader_parameter("beam_range",3.5)
	p.shadow.set_shader_parameter("beam_origin",Vector3(-1,1.5,0))
	var directions := [[Vector3.RIGHT,Vector3.BACK,Vector3.UP,1.5],[Vector3.DOWN,Vector3.RIGHT,Vector3.BACK,1.5],[Vector3.UP,Vector3.RIGHT,Vector3.FORWARD,1.7],[Vector3.LEFT,Vector3.FORWARD,Vector3.UP,3.5]]
	for spec in directions:
		p.shadow.set_shader_parameter("beam_forward",spec[0])
		p.shadow.set_shader_parameter("beam_right",spec[1])
		p.shadow.set_shader_parameter("beam_up",spec[2])
		p.viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		for frame in 3: await process_frame
		await RenderingServer.frame_post_draw
		var c := p.viewport.get_texture().get_image().get_pixel(64,64)
		var depth := (c.r * 65280.0 + c.g * 255.0) / 65535.0 * 3.5
		check(absf(depth - spec[3]) < 0.02,"shadow DDA exact wall/floor/ceiling/parallel ray %s -> %s" % [spec[0],depth])
	# Reset to the wall for real receiver shader probes.
	p.shadow.set_shader_parameter("beam_forward",Vector3.RIGHT)
	p.shadow.set_shader_parameter("beam_right",Vector3.BACK)
	p.shadow.set_shader_parameter("beam_up",Vector3.UP)
	p.viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	for frame in 3: await process_frame
	var baker := LightBaker.new()
	root.add_child(baker)
	var shader := Shader.new()
	shader.code = "shader_type canvas_item; render_mode blend_disabled;\n#include \"res://shaders/flashlight.gdshaderinc\"\nuniform vec3 probe; uniform vec3 face; void fragment(){COLOR=vec4(flashlight_irradiance(probe,face)/24.0,1.0);}"
	var m := ShaderMaterial.new()
	m.shader = shader
	m.set_shader_parameter("flashlight_enabled",true)
	m.set_shader_parameter("flashlight_origin",Vector3(-1,1.5,0))
	m.set_shader_parameter("flashlight_right",Vector3.BACK)
	m.set_shader_parameter("flashlight_up",Vector3.UP)
	m.set_shader_parameter("flashlight_forward",Vector3.RIGHT)
	m.set_shader_parameter("flashlight_range",3.5)
	m.set_shader_parameter("flashlight_shadow",p.viewport.get_texture())
	for spec in [[Vector3(0.25,1.5,0),Vector3.LEFT,true],[Vector3(1,1.5,0),Vector3.LEFT,false],[Vector3(0.25,1.5,2),Vector3.LEFT,false],[Vector3(0.25,1.5,0),Vector3.RIGHT,false]]:
		m.set_shader_parameter("probe",spec[0]); m.set_shader_parameter("face",spec[1])
		var tiles: Array = await baker._render(m,0)
		var c: Color = tiles[0].get_pixel(0,0)
		check((c.r > 0.1) if spec[2] else c.r == 0.0,"receiver lit / occluded / outside cone / wrong normal")
	var rig: Node3D = load("res://assets/flashlight/flashlight.tscn").instantiate()
	root.add_child(rig)
	check(not rig.enabled,"flashlight off by default")
	check(rig.get_node("Beam") is Marker3D,"no native shadow light")
	check(rig.materials.size() == 1,"opaque model has integrated material")
	rig.update_light(Color(0.2,0.3,0.1),0.0,false)
	check(rig.materials[0].get_shader_parameter("player_light") == Vector3(0.2,0.3,0.1),"Player.light reaches model")
	# Exercise the actual player handler without starting the whole world.
	var player := Player.new()
	var head := Node3D.new()
	head.name = "Head"
	var camera := Camera3D.new()
	camera.name = "Camera3D"
	head.add_child(camera)
	player.add_child(head)
	root.add_child(player)
	player.set_process(false)
	player.set_physics_process(false)
	player.active = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var key := InputEventKey.new()
	key.physical_keycode = KEY_F
	key.pressed = true
	player._unhandled_input(key)
	check(player.flashlight.enabled, "F switches on")
	key.echo = true
	player._unhandled_input(key)
	check(player.flashlight.enabled, "F repeat ignored")
	key.echo = false
	player._unhandled_input(key)
	check(not player.flashlight.enabled, "F switches off")
	player.active = false
	player._unhandled_input(key)
	check(not player.flashlight.enabled, "F inactive ignored")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	player.queue_free()
	rig.queue_free(); baker.queue_free();p.queue_free()
	await process_frame
	if failures == 0: print("PASS: flashlight — GPU shadow wall/floor/ceiling/parallel rays, receiver occlusion/cone/normal, off by default, no native light, Player.light material")
	quit(1 if failures else 0)
