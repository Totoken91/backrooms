extends SceneTree
## Actual baker pipeline: compare retained GPU texture against the old CPU
## readback/re-upload path, including bands, encoded heights and target reuse.
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var baker := LightBaker.new()
	root.add_child(baker)
	var shader := Shader.new()
	shader.code = "shader_type canvas_item; render_mode blend_disabled;\n#include \"res://shaders/spans.gdshaderinc\"\nuniform float res=160.0; uniform float tiles=5.0; uniform float phase; void fragment(){vec2 c=bake_cell(UV,res,tiles); float tile=floor(c.x/res); vec2 p=vec2(mod(c.x,res),c.y); COLOR=vec4(fract(p.x*0.071+phase),fract(p.y*0.043+phase),fract((p.x+p.y)*0.017+tile*0.1),fract(p.y*0.059+phase));}"
	var span := Image.create(1, 1, false, Image.FORMAT_RGBAH)
	span.fill(Color(-10, 0, 3.2, 100))
	var spans := ImageTexture.create_from_image(span)
	for source in [baker._direct, baker._indirect]:
		source.shader = shader
		source.set_shader_parameter("span_a", spans)
		source.set_shader_parameter("span_b", spans)
		for phase in [0.0, 0.37]:
			source.set_shader_parameter("phase", phase)
			for radius in [0, 1, 3]:
				# Oracle explicitly retains the old readback and re-upload boundary.
				await baker._draw(source, LightBaker.BANDS)
				var raw := baker._viewport.get_texture().get_image()
				raw.convert(Image.FORMAT_RGBA8)
				var expected := raw
				if radius > 0:
					for key in ["span_a", "span_b", "occ_origin", "occ_size"]:
						baker._filter.set_shader_parameter(key, source.get_shader_parameter(key))
					baker._filter.set_shader_parameter("src", ImageTexture.create_from_image(raw))
					baker._filter.set_shader_parameter("radius", radius)
					baker._filter.set_shader_parameter("sigma", radius * 0.6)
					baker._filter.set_shader_parameter("active_tiles", 4.0 if source == baker._direct else 3.0)
					await baker._draw(baker._filter, LightBaker.BANDS)
					expected = baker._filter_viewport.get_texture().get_image()
					expected.convert(Image.FORMAT_RGBA8)
				var count: int = baker.timings.get("readback_cpu", {}).get("count", 0)
				baker.light_bands = 16
				var actual: Array = await baker._render(source, radius)
				if baker.timings.readback_cpu.count != count + 1:
					failures += 1
					printerr("FAIL: exactly one readback per completed bake")
				for tile in LightBaker.TILES:
					var oracle := expected.get_region(Rect2i(tile * LightBaker.RES, 0, LightBaker.RES, LightBaker.RES))
					if actual[tile].get_data() != oracle.get_data():
						failures += 1
						printerr("FAIL: GPU filter differs from readback oracle phase=%s radius=%s tile=%s" % [phase, radius, tile])
	baker.queue_free()
	await process_frame
	if failures == 0:
		print("PASS: GPU bake pipeline — byte-identical CPU oracle, direct/gather, 2 patterns, 3 radii, 5 tiles, 8/16-band equivalence, target reuse, one readback")
	quit(1 if failures else 0)
