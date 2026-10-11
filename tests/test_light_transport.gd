extends SceneTree
## GPU diagnostics: run through tools/capture.sh with GODOT_SCRIPT set to this file.
var failures := 0

func check_color(actual: Color, expected: Color, label: String, tolerance := 2.0 / 255.0) -> void:
	var error := maxf(absf(actual.r - expected.r), maxf(absf(actual.g - expected.g), absf(actual.b - expected.b)))
	if error > tolerance:
		failures += 1
		printerr("FAIL: ", label, " expected ", expected, " got ", actual)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(64, 16)
	vp.disable_3d = true
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var rect := ColorRect.new()
	rect.size = Vector2(64, 16)
	var mat := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = "shader_type canvas_item; render_mode blend_disabled; uniform vec3 a; uniform vec3 b; void fragment(){ COLOR=vec4(UV.x<0.5?a:b,1.0); }"
	mat.shader = shader
	mat.set_shader_parameter("a", Color(0.599, 0.491, 0.141))
	mat.set_shader_parameter("b", Vector3(0.599, 0.491, 0.141))
	rect.material = mat
	vp.add_child(rect)
	await process_frame
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	print("probe uniform Color ", img.get_pixel(16, 8), " Vector3 ", img.get_pixel(48, 8))
	check_color(img.get_pixel(16, 8), Color(0.599, 0.491, 0.141), "linear albedo uniform")
	check_color(img.get_pixel(48, 8), Color(0.599, 0.491, 0.141), "numeric uniform")
	# A constant unshaded patch must survive the 3D render path at low light.
	var scene := Node3D.new()
	# Each test teleports the camera/quad; interpolation must not render an
	# intermediate pose from the preceding case.
	scene.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	root.add_child(scene)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.environment.adjustment_enabled = false
	scene.add_child(env)
	var camera := Camera3D.new()
	camera.position.z = 2.0
	scene.add_child(camera)
	camera.current = true
	var mesh := MeshInstance3D.new()
	mesh.mesh = QuadMesh.new()
	scene.add_child(mesh)
	var sm := ShaderMaterial.new()
	var ss := Shader.new()
	ss.code = "shader_type spatial; render_mode unshaded; uniform vec3 value;\n#include \"res://shaders/color_space.gdshaderinc\"\nvoid fragment(){ALBEDO=compatibility_albedo(value);}"
	sm.shader = ss
	sm.set_shader_parameter("raw_output", true)
	mesh.material_override = sm
	for v in [Vector3.ZERO, Vector3(0.004, 0.003, 0.001), Vector3(0.04, 0.03, 0.01), Vector3(0.18, 0.18, 0.18), Vector3.ONE]:
		sm.set_shader_parameter("value", v)
		await process_frame
		await RenderingServer.frame_post_draw
		await process_frame
		await RenderingServer.frame_post_draw
		var shot := root.get_texture().get_image()
		var actual := shot.get_pixel(shot.get_width() / 2, shot.get_height() / 2)
		print("probe linear ", v, " rendered ", actual)
		check_color(actual, Color(v.x, v.y, v.z).linear_to_srgb(), "raw output %s" % v)
	# The same packed array is shared by all surfaces. Give floor, ceiling and
	# wall layers distinct colours to catch a swapped layer or broken filtering.
	var layers: Array[Image] = []
	for i in 49 * 11:
		var layer := Image.create(2, 2, false, Image.FORMAT_RGBA8)
		layer.fill(Color.BLACK)
		if i == 8: layer.fill(Color(0.2, 0, 0))
		if i == 9: layer.fill(Color(0, 0.3, 0))
		if i == 10: layer.fill(Color(0, 0, 0.4))
		layers.append(layer)
	var maps := Texture2DArray.new()
	maps.create_from_images(layers)
	var slots := PackedVector2Array()
	slots.resize(49)
	slots.fill(Vector2(1e6, 1e6))
	slots[0] = Vector2.ZERO
	var surface := ShaderMaterial.new()
	surface.shader = load("res://shaders/surface.gdshader")
	surface.set_shader_parameter("light_maps", maps)
	surface.set_shader_parameter("slot_chunk", slots)
	surface.set_shader_parameter("raw_output", true)
	surface.set_shader_parameter("debug_view", 9.0)
	mesh.material_override = surface
	mesh.position = Vector3(1, 1, 1)
	var normals := [Vector3.UP, Vector3.DOWN, Vector3.BACK]
	var codes := [Color(0.2, 0, 0), Color(0, 0.3, 0), Color(0, 0, 0.4)]
	for i in 3:
		mesh.rotation.x = -PI / 2.0 if i == 0 else (PI / 2.0 if i == 1 else 0.0)
		camera.position = mesh.position + normals[i] * 2.0
		camera.look_at(mesh.position, Vector3.BACK if i < 2 else Vector3.UP)
		await process_frame
		await RenderingServer.frame_post_draw
		await process_frame
		await RenderingServer.frame_post_draw
		var shot := root.get_texture().get_image()
		var code: Color = codes[i]
		# Images quantize each channel to 8 bits before the shader reads it.
		code = layers[8 + i].get_pixel(0, 0)
		var expected := Color(code.r * code.r, code.g * code.g, code.b * code.b) * (2.0 / PI)
		check_color(shot.get_pixel(shot.get_width() / 2, shot.get_height() / 2), expected.linear_to_srgb(), "packed surface %d" % i)
	# Sample halfway between black and red texels. A nearest-bound array would
	# produce either endpoint, making visible 0.25 m squares in the real map.
	for y in 2:
		layers[8].set_pixel(0, y, Color.BLACK)
		layers[8].set_pixel(1, y, Color(0.4, 0, 0))
	maps.update_layer(layers[8], 8)
	mesh.position = Vector3(20, 1, 20)
	mesh.rotation.x = -PI / 2.0
	camera.position = mesh.position + Vector3.UP * 2.0
	camera.look_at(mesh.position, Vector3.BACK)
	for frame in 3:
		await process_frame
		await RenderingServer.frame_post_draw
	var filtered := root.get_texture().get_image()
	check_color(filtered.get_pixel(filtered.get_width() / 2, filtered.get_height() / 2), Color(0.2 * 0.2 * 2.0 / PI, 0, 0).linear_to_srgb(), "bilinear floor light", 3.0 / 255.0)
	if failures == 0:
		print("PASS: light transport — linear uniforms, dark blue, zero, greys, floor/ceiling/wall layers, bilinear floor")
	quit(0 if failures == 0 else 1)
