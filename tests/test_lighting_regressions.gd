extends SceneTree
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: ",label)
func run() -> void:
	var map := SpanMap._create(Vector2(-16,-16),256,0.125)
	for z in 256:
		for x in 256:
			var px := -16+(x+0.5)*0.125
			map._write(x,z,[[-10.0,100.0]] if px>=2.5 and px<2.625 else [[-10.0,0.0],[3.2,100.0]])
	for spec in [[Vector3.RIGHT,2.5,Vector3.LEFT],[Vector3.DOWN,1.5,Vector3.UP],[Vector3.UP,1.7,Vector3.DOWN]]:
		var hit := map.trace_ray(Vector3(0,1.5,0),spec[0],18)
		check(not hit.is_empty() and absf(hit.distance-spec[1])<0.001 and hit.normal==spec[2],"CPU exact slab distance/normal")
	check(map.trace_ray(Vector3(0,1.5,0),Vector3.FORWARD,10).is_empty(),"parallel open ray")
	var p := FlashlightProjector.new()
	root.add_child(p)
	for material in [p.shadow,p.bounce_shadow]:
		material.set_shader_parameter("span_a",ImageTexture.create_from_image(map.a))
		material.set_shader_parameter("span_b",ImageTexture.create_from_image(map.b))
		material.set_shader_parameter("occ_origin",map.origin)
		material.set_shader_parameter("occ_size",Vector2(256,256))
	p.shadow.set_shader_parameter("beam_origin",Vector3(0,1.5,0))
	p.shadow.set_shader_parameter("beam_forward",Vector3.FORWARD)
	p.shadow.set_shader_parameter("beam_right",Vector3.RIGHT)
	p.shadow.set_shader_parameter("beam_up",Vector3.UP)
	p.viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	for frame in 3: await process_frame
	var baker := LightBaker.new()
	root.add_child(baker)
	var shader := Shader.new()
	shader.code = "shader_type canvas_item; render_mode blend_disabled;\n#include \"res://shaders/flashlight.gdshaderinc\"\nuniform vec3 point; uniform vec3 face; uniform bool indirect=false; void fragment(){vec3 v=point-flashlight_origin;float d=length(v);float f=dot(v,flashlight_forward);float r=length(vec2(dot(v,flashlight_right),dot(v,flashlight_up)))/(f*flashlight_tan);float cone=0.82*(1.0-smoothstep(0.12,0.55,r))+0.18*(1.0-smoothstep(0.1,1.0,r));float expected=flashlight_energy*cone*(1.0-smoothstep(13.5,18.0,d))*max(dot(face,-v/d),0.0)/(1.0+d*d);float value=indirect?flashlight_indirect(point,face).r*10.0:flashlight_irradiance(point,face).r/max(expected,0.000001);COLOR=vec4(vec3(value),1.0);}"
	var m := ShaderMaterial.new()
	m.shader = shader
	m.set_shader_parameter("flashlight_enabled",true)
	m.set_shader_parameter("flashlight_origin",Vector3(0,1.5,0))
	m.set_shader_parameter("flashlight_forward",Vector3.FORWARD)
	m.set_shader_parameter("flashlight_right",Vector3.RIGHT)
	m.set_shader_parameter("flashlight_up",Vector3.UP)
	m.set_shader_parameter("flashlight_shadow",p.viewport.get_texture())
	for i in 32:
		var z := -8.0-i*0.25
		for sample in [[Vector3(0,0,z),Vector3.UP],[Vector3(0,3.2,z),Vector3.DOWN],[Vector3(2.5,1.5,z),Vector3.LEFT]]:
			m.set_shader_parameter("point",sample[0])
			m.set_shader_parameter("face",sample[1])
			var result: Array = await baker._render(m,0)
			check(result[0].get_pixel(0,0).r > 0.98,"no self shadow stripes at grazing floor/ceiling/wall %s" % sample[0])
	var positions := PackedVector3Array([Vector3(0,0.06,-2),Vector3.ZERO,Vector3.ZERO,Vector3.ZERO])
	var powers := PackedVector3Array([Vector3(1,0.8,0.3),Vector3.ZERO,Vector3.ZERO,Vector3.ZERO])
	p.bounce_shadow.set_shader_parameter("bounce_position",positions)
	p.bounce_shadow.set_shader_parameter("bounce_power",powers)
	p.bounce_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	for frame in 3: await process_frame
	m.set_shader_parameter("indirect",true)
	m.set_shader_parameter("bounce_position",positions)
	m.set_shader_parameter("bounce_normal",PackedVector3Array([Vector3.UP,Vector3.ZERO,Vector3.ZERO,Vector3.ZERO]))
	m.set_shader_parameter("bounce_power",powers)
	m.set_shader_parameter("flashlight_bounce_shadow",p.bounce_viewport.get_texture())
	m.set_shader_parameter("face",Vector3.LEFT)
	for sample in [[Vector3(2,1.5,-2),true],[Vector3(4,1.5,-2),false]]:
		m.set_shader_parameter("point",sample[0])
		var result: Array = await baker._render(m,0)
		var value: float = result[0].get_pixel(0,0).r
		check(value > 0.1 if sample[1] else value == 0.0,"reflected patch visible / blocked by wall: %s -> %s" % [sample[0],value])
	m.set_shader_parameter("flashlight_enabled",false)
	var off: Array = await baker._render(m,0)
	check(off[0].get_pixel(0,0).r==0.0,"no bounce when flashlight off")
	await check_height_seam(baker)
	p.queue_free(); baker.queue_free()
	await process_frame
	if failures == 0: print("PASS: lighting regressions — CPU slab hits, 96 grazing GPU receivers, reflected patch occlusion/off, continuous wall across room-height boundary")
	quit(1 if failures else 0)

func check_height_seam(baker: LightBaker) -> void:
	var layers: Array[Image] = []
	for i in 49*11:
		var img := Image.create(2,2,false,Image.FORMAT_RGBA8)
		img.fill(Color.BLACK)
		layers.append(img)
	for x in 2:
		var ceiling := 3.2 if x == 0 else 4.8
		var hs := [0.4,(0.4+ceiling-0.3)/2.0,ceiling-0.3]
		for z in 2:
			for i in 3:
				var d: float = 5.0-hs[i]
				var e := 10.0*d/pow(4.0+d*d,2.0)
				layers[i].set_pixel(x,z,Color(0,sqrt(e/6.0),0,0))
			var a := encode_height(0)
			var b := encode_height(ceiling)
			layers[4].set_pixel(x,z,Color(a.x,a.y,b.x,b.y))
	var maps := Texture2DArray.new()
	maps.create_from_images(layers)
	var slots := PackedVector2Array()
	slots.resize(49); slots.fill(Vector2(1e6,1e6)); slots[0]=Vector2.ZERO
	var shader := Shader.new()
	shader.code = "shader_type canvas_item; render_mode blend_disabled;\n#include \"res://shaders/gap.gdshaderinc\"\n#include \"res://shaders/light_maps.gdshaderinc\"\n#include \"res://shaders/structural_room.gdshaderinc\"\n#include \"res://shaders/wall_surface.gdshaderinc\"\nuniform vec2 point; void fragment(){COLOR=vec4(vec3(wall_surface_light(point,0,2.0,6.0,5.0)*4.0),1.0);}"
	var m := ShaderMaterial.new()
	m.shader = shader
	m.set_shader_parameter("light_maps",maps)
	m.set_shader_parameter("slot_chunk",slots)
	var values := []
	for x in [19.999,20.001]:
		m.set_shader_parameter("point",Vector2(x,20))
		var result: Array = await baker._render(m,0)
		values.append(result[0].get_pixel(0,0).r)
	check(absf(values[0]-values[1])<=1.0/255.0,"same wall must not jump when nearest gap changes")

func encode_height(h: float) -> Vector2:
	var v := floori((h+16.0)/64.0*65535.0+0.5)
	return Vector2(floori(v/256.0),v%256)/255.0
