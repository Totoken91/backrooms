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
	await check_chunk_seams()
	await check_receiver_shadows()
	await check_wall_profile()
	await check_uniform_gather()
	if failures == 0:
		print("PASS: analytic wall profile and light transport — linear uniforms, dark blue, zero, greys, surface layers, bilinear floor, chunk edges/corners, negative coordinates, stale slots, energy interpolation, receiver shadows, uniform gather")
	quit(0 if failures == 0 else 1)


func check_chunk_seams() -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(8, 8)
	vp.disable_3d = true
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var rect := ColorRect.new()
	rect.size = Vector2(8, 8)
	vp.add_child(rect)
	var shader := Shader.new()
	shader.code = "shader_type canvas_item; render_mode blend_disabled;\n#include \"res://shaders/gap.gdshaderinc\"\n#include \"res://shaders/light_maps.gdshaderinc\"\nuniform vec2 at; uniform bool test_ao=false; uniform bool test_energy=false; void fragment(){COLOR=test_ao?vec4(vec3(ao_map(at)),1.0):(test_energy?light_energy(0,at):light_map(0,at));}"
	var mat := ShaderMaterial.new()
	mat.shader = shader
	rect.material = mat
	var values := {Vector2i(0, 0): 0.2, Vector2i(1, 0): 0.6, Vector2i(0, 1): 0.4, Vector2i(1, 1): 0.8, Vector2i(-1, 0): 0.1}
	var slots := PackedVector2Array()
	slots.resize(49)
	slots.fill(Vector2(1e6, 1e6))
	var light: Array[Image] = []
	var ao: Array[Image] = []
	for slot in 49:
		var img := Image.create(2, 2, false, Image.FORMAT_RGBA8)
		img.fill(Color.BLACK)
		for coord in values:
			if WorldStreamer.slot_of(coord) == slot:
				slots[slot] = Vector2(coord)
				img.fill(Color(values[coord], values[coord], values[coord], 1))
		for layer in 11:
			light.append(img)
		ao.append(img)
	var maps := Texture2DArray.new()
	maps.create_from_images(light)
	var aos := Texture2DArray.new()
	aos.create_from_images(ao)
	mat.set_shader_parameter("light_maps", maps)
	mat.set_shader_parameter("ao_maps", aos)
	mat.set_shader_parameter("slot_chunk", slots)
	var cases := [[Vector2(39.999, 20), 0.4], [Vector2(40.001, 20), 0.4], [Vector2(40, 40), 0.5], [Vector2(-0.001, 20), 0.15], [Vector2(0.001, 20), 0.15]]
	for test_ao in [false, true]:
		mat.set_shader_parameter("test_ao", test_ao)
		for sample in cases:
			mat.set_shader_parameter("at", sample[0])
			for frame in 2:
				await process_frame
				await RenderingServer.frame_post_draw
			var img := vp.get_texture().get_image()
			var v: float = sample[1]
			check_color(img.get_pixel(4, 4), Color(v, v, v), "chunk seam %s ao=%s" % [sample[0], test_ao])
	# sqrt-encoded maps must mix decoded energies, both inside a chunk and
	# across its edges/corners. Mixing encoded values and squaring gives 0.16
	# instead of 0.20 for the first case: a 20% artificial energy loss.
	mat.set_shader_parameter("test_ao", false)
	mat.set_shader_parameter("test_energy", true)
	var energy_cases := [[Vector2(39.999, 20), 0.2], [Vector2(40.001, 20), 0.2], [Vector2(40, 40), 0.3], [Vector2(-0.001, 20), 0.025], [Vector2(0.001, 20), 0.025]]
	for sample in energy_cases:
		mat.set_shader_parameter("at", sample[0])
		for frame in 2:
			await process_frame
			await RenderingServer.frame_post_draw
		var v: float = sample[1]
		check_color(vp.get_texture().get_image().get_pixel(4, 4), Color(v, v, v), "energy seam %s" % sample[0])
	var contrast := light[0].duplicate()
	contrast.fill(Color(0.2, 0.2, 0.2, 1))
	for y in 2:
		contrast.set_pixel(1, y, Color(0.6, 0.6, 0.6, 1))
	maps.update_layer(contrast, 0)
	mat.set_shader_parameter("at", Vector2(20, 20))
	for frame in 2:
		await process_frame
		await RenderingServer.frame_post_draw
	check_color(vp.get_texture().get_image().get_pixel(4, 4), Color(0.2, 0.2, 0.2), "energy interior contrast")
	maps.update_layer(light[0], 0)
	mat.set_shader_parameter("test_energy", false)
	# A missing or reused slot must clamp to the owned chunk, never read stale light.
	for invalid in [Vector2(1e6, 1e6), Vector2(8, 0)]:
		slots[1] = invalid
		mat.set_shader_parameter("slot_chunk", slots)
		mat.set_shader_parameter("at", Vector2(39.999, 20))
		for frame in 2:
			await process_frame
			await RenderingServer.frame_post_draw
		check_color(vp.get_texture().get_image().get_pixel(4, 4), Color(0.2, 0.2, 0.2), "missing/stale neighbour %s" % invalid)
	vp.queue_free()


func point_wall(r: float, y: float) -> float:
	var d := maxf(3.19 - y, 0.0)
	return 12.0 * (25.0 / 36.0) * r * d / pow(r * r + d * d, 2)


func check_uniform_gather() -> void:
	# A closed white room with the same outgoing radiance on every surface
	# must return the same irradiance for every receiver and jitter pattern.
	var vp := SubViewport.new()
	vp.size = Vector2i(48, 16)
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var rect := ColorRect.new()
	rect.size = Vector2(48, 16)
	vp.add_child(rect)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/bake_indirect.gdshader")
	rect.material = mat
	var a := Image.create(40, 40, false, Image.FORMAT_RGBAH)
	a.fill(Color(-10, 0, 3.2, 100))
	# Closed box surrounding receivers, all coordinates within slot zero.
	for r in [Rect2i(0, 0, 2, 40), Rect2i(38, 0, 2, 40), Rect2i(0, 0, 40, 2), Rect2i(0, 38, 40, 2)]:
		a.fill_rect(r, Color(-10, 100, -100, -100))
	var b := Image.create(40, 40, false, Image.FORMAT_RGBAH)
	b.fill(Color(-100, -100, -100, -100))
	mat.set_shader_parameter("span_a", ImageTexture.create_from_image(a))
	mat.set_shader_parameter("span_b", ImageTexture.create_from_image(b))
	mat.set_shader_parameter("occ_size", Vector2(40, 40))
	mat.set_shader_parameter("res", 16.0)
	mat.set_shader_parameter("band_rows", 16.0)
	mat.set_shader_parameter("use_bounce", 1.0)
	mat.set_shader_parameter("wall_albedo", Vector3.ONE)
	mat.set_shader_parameter("floor_albedo", Vector3.ONE)
	mat.set_shader_parameter("ceiling_albedo", Vector3.ONE)
	var layers: Array[Image] = []
	for i in 49 * 11:
		var im := Image.create(2, 2, false, Image.FORMAT_RGBA8)
		im.fill(Color(0.5, 0.5, 0.5, 0.5) if i >= 5 and i <= 7 else Color(0, 0, 0, 0))
		layers.append(im)
	var maps := Texture2DArray.new()
	maps.create_from_images(layers)
	mat.set_shader_parameter("light_maps", maps)
	var slots := PackedVector2Array()
	slots.resize(49)
	slots.fill(Vector2(1e6, 1e6))
	slots[0] = Vector2.ZERO
	mat.set_shader_parameter("slot_chunk", slots)
	for frame in 3:
		await process_frame
		await RenderingServer.frame_post_draw
	var shot := vp.get_texture().get_image()
	var worst := 0.0
	for tile in 3:
		for y in range(2, 14):
			for x in range(2, 14):
				worst = maxf(worst, absf(shot.get_pixel(tile * 16 + x, y).r - 128.0 / 255.0))
	print("probe uniform gather samples ", shot.get_pixel(8, 8), " / ", shot.get_pixel(24, 8), " / ", shot.get_pixel(40, 8))
	print("probe uniform gather max encoded error ", worst)
	if worst > 2.0 / 255.0:
		failures += 1
		printerr("FAIL: uniform radiance must conserve irradiance: ", worst)
	# First-gather mode must ignore the deliberately nonzero bounce maps.
	# This also guards the zero-bounce fast path against leaking indirect light.
	mat.set_shader_parameter("use_bounce", 0.0)
	for frame in 2:
		await process_frame
		await RenderingServer.frame_post_draw
	shot = vp.get_texture().get_image()
	for tile in 3:
		check_color(shot.get_pixel(tile * 16 + 8, 8), Color.BLACK, "black gather tile %d" % tile)
	# A square room and its light rotated 90 degrees around the centre must
	# produce the same result there (AZ=16 gives the same rotated ray set).
	# Each of the four walls carries direct illumination in turn.
	# This catches ambiguous diagonal column crossings picking an X face.
	mat.set_shader_parameter("texel", 5.0 / 17.0) # pixel (8,8) is exactly (2.5,2.5).
	mat.set_shader_parameter("floor_albedo", Vector3.ZERO)
	mat.set_shader_parameter("ceiling_albedo", Vector3.ZERO)
	var rotated_samples: Array[Color] = []
	for axis in [1, 3, 0, 2]:
		for layer in 4:
			var value := Color(0, 0, 0, 0)
			if axis == 1 and layer <= 2:
				value.b = 0.4 # -X at each of the three stored heights.
			if axis == 3 and layer >= 1:
				value.r = 0.4 # -Z at each height.
			if axis == 0 and layer <= 2:
				value.g = 0.4 # +X at each height.
			if axis == 2 and layer <= 2:
				value.a = 0.4 # +Z at each height.
			layers[layer].fill(value)
			maps.update_layer(layers[layer], layer)
		for frame in 3:
			await process_frame
			await RenderingServer.frame_post_draw
		shot = vp.get_texture().get_image()
		for tile in 3:
			rotated_samples.append(shot.get_pixel(tile * 16 + 8, 8))
	print("probe rotated gather ", rotated_samples)
	for turn in range(1, 4):
		for tile in 3:
			check_color(rotated_samples[tile], rotated_samples[turn * 3 + tile], "gather quarter-turn %d tile %d" % [turn, tile])
	vp.queue_free()


func check_wall_profile() -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(8, 8)
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var rect := ColorRect.new()
	rect.size = Vector2(8, 8)
	vp.add_child(rect)
	var shader := Shader.new()
	shader.code = "shader_type canvas_item; render_mode blend_disabled;\n#include \"res://shaders/gap.gdshaderinc\"\nuniform vec3 samples; uniform float y; uniform float expected; void fragment(){float e=wall_profile(samples.x,samples.y,samples.z,y,vec2(0,3.2),3.19); COLOR=vec4(vec3(0.5*e/expected),1.0);}"
	var mat := ShaderMaterial.new()
	mat.shader = shader
	rect.material = mat
	# Independent analytic point-emitter law, including heights between and
	# beyond the stored samples. Old log interpolation cannot reproduce it.
	for r in [2.0, 4.0, 8.0]:
		mat.set_shader_parameter("samples", Vector3(point_wall(r, 0.4), point_wall(r, 1.65), point_wall(r, 2.9)))
		for y in [0.1, 1.0, 2.2, 2.8, 3.1]:
			mat.set_shader_parameter("y", y)
			mat.set_shader_parameter("expected", point_wall(r, y))
			for frame in 2:
				await process_frame
				await RenderingServer.frame_post_draw
			check_color(vp.get_texture().get_image().get_pixel(4, 4), Color(0.5, 0.5, 0.5), "wall profile r=%s y=%s" % [r, y])
	mat.set_shader_parameter("samples", Vector3.ZERO)
	mat.set_shader_parameter("expected", 1.0)
	for frame in 2:
		await process_frame
		await RenderingServer.frame_post_draw
	check_color(vp.get_texture().get_image().get_pixel(4, 4), Color.BLACK, "unlit wall stays black")
	vp.queue_free()


func check_receiver_shadows() -> void:
	# A 0.6 m slab close to the receiver hides a panel from the floor, but
	# not from a point 0.4 m higher on the wall. Sharing floor visibility
	# incorrectly turns both channels black.
	var vp := SubViewport.new()
	vp.size = Vector2i(40, 8)
	vp.disable_3d = true
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var rect := ColorRect.new()
	rect.size = Vector2(40, 8)
	vp.add_child(rect)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/bake_direct.gdshader")
	rect.material = mat
	var a := Image.create(32, 32, false, Image.FORMAT_RGBAH)
	a.fill(Color(-10, 0, 3.2, 100))
	a.fill_rect(Rect2i(2, 0, 2, 32), Color(-10, 0.6, 3.2, 100))
	var b := Image.create(32, 32, false, Image.FORMAT_RGBAH)
	b.fill(Color(-100, -100, -100, -100))
	var fixtures := Image.create(1, 2, false, Image.FORMAT_RGBAF)
	fixtures.set_pixel(0, 0, Color(1.625, 0.125, 12, 3.2))
	fixtures.set_pixel(0, 1, Color(0, 0, 0, 0))
	mat.set_shader_parameter("span_a", ImageTexture.create_from_image(a))
	mat.set_shader_parameter("span_b", ImageTexture.create_from_image(b))
	mat.set_shader_parameter("occ_origin", Vector2.ZERO)
	mat.set_shader_parameter("occ_size", Vector2(32, 32))
	mat.set_shader_parameter("fix_tex", ImageTexture.create_from_image(fixtures))
	mat.set_shader_parameter("fix_count", 1)
	mat.set_shader_parameter("tiles", 5.0)
	mat.set_shader_parameter("res", 8.0)
	mat.set_shader_parameter("band_rows", 8.0)
	for frame in 2:
		await process_frame
		await RenderingServer.frame_post_draw
	await check_direct_pruning(mat, vp)
	var shadowed := vp.get_texture().get_image().get_pixel(0, 0)
	print("probe slab floor / low wall encoded ", shadowed.r, " / ", shadowed.g)
	if shadowed.r > 0.01 or shadowed.g < 0.05:
		failures += 1
		printerr("FAIL: floor and low wall must have independent shadows: ", shadowed)
	a.fill(Color(-10, 0, 3.2, 100))
	mat.set_shader_parameter("span_a", ImageTexture.create_from_image(a))
	for frame in 2:
		await process_frame
		await RenderingServer.frame_post_draw
	await check_direct_pruning(mat, vp)
	var clear := vp.get_texture().get_image().get_pixel(0, 0)
	if clear.r < 0.05 or clear.g < 0.05:
		failures += 1
		printerr("FAIL: both receivers must see the unoccluded panel: ", clear)
	# A symmetric panel must give symmetric direct illumination: no random
	# source-centroid shift from one receiver column to the next.
	fixtures.set_pixel(0, 0, Color(1.0, 0.125, 12, 3.2))
	mat.set_shader_parameter("fix_tex", ImageTexture.create_from_image(fixtures))
	for frame in 2:
		await process_frame
		await RenderingServer.frame_post_draw
	var symmetric := vp.get_texture().get_image()
	var left := symmetric.get_pixel(0, 0)
	var right := symmetric.get_pixel(7, 0)
	check_color(Color(left.r, left.g, 0), Color(right.r, right.b, 0), "symmetric panel integration", 1.0 / 255.0)
	vp.queue_free()


func check_direct_pruning(mat: ShaderMaterial, vp: SubViewport) -> void:
	mat.set_shader_parameter("prune_receivers", false)
	for frame in 2:
		await process_frame
		await RenderingServer.frame_post_draw
	var expected := vp.get_texture().get_image().get_data()
	mat.set_shader_parameter("prune_receivers", true)
	for frame in 2:
		await process_frame
		await RenderingServer.frame_post_draw
	if vp.get_texture().get_image().get_data() != expected:
		failures += 1
		printerr("FAIL: receiver pruning must preserve every packed direct channel")
