extends Node3D
## Imported v3 rig, integrated with custom world lighting. Beam is a transform
## marker: no native light or native shadow pass is submitted.
var enabled := false
var materials: Array[ShaderMaterial] = []
var lens: StandardMaterial3D
var rest: Vector3
var phase := 0.0
func _ready() -> void:
	rest = position
	_convert_materials($Model)
func _convert_materials(node: Node) -> void:
	if node is MeshInstance3D:
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for i in node.mesh.get_surface_count():
			var original: Material = node.mesh.surface_get_material(i)
			if original is StandardMaterial3D and original.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
				lens = original.duplicate()
				lens.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				node.set_surface_override_material(i, lens)
			else:
				var m := ShaderMaterial.new()
				m.shader = load("res://shaders/flashlight_model.gdshader")
				m.set_shader_parameter("albedo_tex", original.albedo_texture)
				m.set_shader_parameter("normal_tex", original.normal_texture)
				m.set_shader_parameter("orm_tex", original.roughness_texture)
				node.set_surface_override_material(i, m)
				materials.append(m)
	for child in node.get_children(): _convert_materials(child)
func update_light(light: Color, delta: float, moving: bool) -> void:
	phase += delta if moving else 0.0
	position = rest + Vector3(sin(phase * 7.0), sin(phase * 14.0), 0) * (0.0015 if moving else 0.0)
	for m in materials: m.set_shader_parameter("player_light", Vector3(light.r, light.g, light.b))
	if lens:
		lens.albedo_color = Color(0.19,0.27,0.25,0.055) * Color(light.r,light.g,light.b,1.0).linear_to_srgb()
