class_name FlashlightProjector
extends Node
## 128² span-traced shadow map. Redrawn only when the emitter moves, no GPU
## readback, no rebake of panel lighting and no native SpotLight shadow pass.
const RES := 128
const RANGE := 18.0
var world: LevelWorld
var player: Player
var materials := {}
var viewport: SubViewport
var shadow: ShaderMaterial
var map: SpanMap
var key := Vector2i(1 << 30, 0)
var preparing := false
var epoch := 0
var pose := Transform3D()
var dirty := true
var shadow_updates := 0
var enabled_override := true
var bounce_viewport: SubViewport
var bounce_shadow: ShaderMaterial
var bounce_pose := Transform3D()
var bounce_age := 1.0
var bounce_updates := 0
var dirty_bounce := true
var bounce_positions := PackedVector3Array()
var bounce_normals := PackedVector3Array()
var bounce_powers := PackedVector3Array()

func _ready() -> void:
	viewport = SubViewport.new()
	viewport.size = Vector2i(RES, RES)
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(viewport)
	var rect := ColorRect.new()
	rect.size = Vector2(RES, RES)
	shadow = ShaderMaterial.new()
	shadow.shader = load("res://shaders/flashlight_shadow.gdshader")
	rect.material = shadow
	viewport.add_child(rect)
	bounce_viewport = SubViewport.new()
	bounce_viewport.size = Vector2i(144,96)
	bounce_viewport.disable_3d = true
	bounce_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(bounce_viewport)
	var bounce_rect := ColorRect.new()
	bounce_rect.size = Vector2(144,96)
	bounce_shadow = ShaderMaterial.new()
	bounce_shadow.shader = load("res://shaders/flashlight_bounce_shadow.gdshader")
	bounce_rect.material = bounce_shadow
	bounce_viewport.add_child(bounce_rect)
	bounce_positions.resize(4)
	bounce_normals.resize(4)
	bounce_powers.resize(4)

func configure(w: LevelWorld, p: Player, mats: Dictionary) -> void:
	epoch += 1
	world = w
	player = p
	player.flashlight_bounce = Color.BLACK
	materials = mats
	map = null
	bounce_pose = Transform3D()
	bounce_age = 1.0
	dirty_bounce = true
	preparing = false
	key = Vector2i(1 << 30, 0)
	dirty = true
	for m in materials.values():
		m.set_shader_parameter("flashlight_enabled", false)
		m.set_shader_parameter("flashlight_shadow", viewport.get_texture())
		m.set_shader_parameter("flashlight_bounce_shadow",bounce_viewport.get_texture())

func prepare(w: LevelWorld, wanted: Vector2i, revision: int) -> void:
	preparing = true
	var origin := Vector2(wanted) * 10.0 - Vector2(20, 20)
	var result := await SpanMap.build_sliced(w, origin, 480, 0.125, get_tree(), 1.0)
	if revision != epoch or world != w: return
	map = result
	key = wanted
	var a := ImageTexture.create_from_image(map.a)
	var b := ImageTexture.create_from_image(map.b)
	for material in [shadow,bounce_shadow]:
		material.set_shader_parameter("span_a",a)
		material.set_shader_parameter("span_b",b)
		material.set_shader_parameter("occ_origin",origin)
		material.set_shader_parameter("occ_size",Vector2(480,480))
	bounce_age = 1.0
	dirty_bounce = true
	preparing = false
	dirty = true

func _process(delta: float) -> void:
	bounce_age += delta
	if not player or not world: return
	var enabled: bool = player.flashlight.enabled and enabled_override
	if not enabled:
		dirty_bounce = true
		player.flashlight_bounce = Color.BLACK
		for m in materials.values(): m.set_shader_parameter("flashlight_enabled", false)
		return
	var source: Transform3D = player.flashlight.get_node("Beam").global_transform
	# Do not let a muzzle protruding past a close wall light the other side.
	var query := PhysicsRayQueryParameters3D.create(player.camera.global_position, source.origin, 1)
	var hit: Dictionary = player.get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty(): source.origin = hit.position + hit.normal * 0.035
	var wanted := Vector2i(floori(source.origin.x / 10.0), floori(source.origin.z / 10.0))
	if enabled and key != wanted and not preparing: prepare(world, wanted, epoch)
	var ready := enabled and map != null
	if ready:
		ready = Rect2(map.origin + Vector2(RANGE, RANGE), Vector2.ONE * (map.size * map.texel - RANGE * 2.0)).has_point(Vector2(source.origin.x, source.origin.z))
	if ready and (dirty or not pose.is_equal_approx(source)):
		pose = source
		dirty = false
		shadow.set_shader_parameter("beam_origin", source.origin)
		shadow.set_shader_parameter("beam_right", source.basis.x)
		shadow.set_shader_parameter("beam_up", source.basis.y)
		shadow.set_shader_parameter("beam_forward", -source.basis.z)
		viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		shadow_updates += 1
	if ready and bounce_age >= 1.0/15.0 and (dirty_bounce or not bounce_pose.is_equal_approx(source)):
		update_bounce(source)
	for m in materials.values():
		m.set_shader_parameter("flashlight_enabled", ready)
		if ready:
			m.set_shader_parameter("flashlight_origin", source.origin)
			m.set_shader_parameter("flashlight_right", source.basis.x)
			m.set_shader_parameter("flashlight_up", source.basis.y)
			m.set_shader_parameter("flashlight_forward", -source.basis.z)

func update_bounce(source: Transform3D) -> void:
	bounce_pose = source
	bounce_age = 0.0
	dirty_bounce = false
	bounce_powers.fill(Vector3.ZERO)
	for i in 4:
		var uv := Vector2(-0.22 if i%2 == 0 else 0.22,-0.22 if i < 2 else 0.22)
		var ray := (-source.basis.z+(source.basis.x*uv.x-source.basis.y*uv.y)*0.7).normalized()
		var hit := map.trace_ray(source.origin,ray,10.0)
		if hit.is_empty(): continue
		var d: float = hit.distance
		var normal: Vector3 = hit.normal
		bounce_positions[i] = hit.position+normal*0.06
		bounce_normals[i] = normal
		var albedo := Vector3(0.6,0.49,0.14)
		if normal.y > 0.5: albedo = Vector3(0.23,0.19,0.1)
		elif normal.y < -0.5: albedo = Vector3(0.65,0.64,0.5)
		# Each hit represents a quarter of the central cone's solid angle.
		# Reflected power follows intercepted flux, not distance-free ambient.
		bounce_powers[i] = albedo*24.0*0.15*0.85*(d*d/(1.0+d*d))/PI
	bounce_shadow.set_shader_parameter("bounce_position",bounce_positions)
	bounce_shadow.set_shader_parameter("bounce_power",bounce_powers)
	bounce_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	bounce_updates += 1
	for m in materials.values():
		m.set_shader_parameter("bounce_position",bounce_positions)
		m.set_shader_parameter("bounce_normal",bounce_normals)
		m.set_shader_parameter("bounce_power",bounce_powers)
	# The held model also receives reflected room light, even with no neon.
	var ambient := Vector3.ZERO
	for i in 4:
		var v := player.camera.global_position-bounce_positions[i]
		var d := v.length()
		if d < 0.02 or d >= 6.0: continue
		var hit := map.trace_ray(bounce_positions[i],v/d,maxf(0.01,d-0.12))
		if hit.is_empty(): ambient += bounce_powers[i]*maxf(0.0,bounce_normals[i].dot(v/d))/(0.4+d*d)/PI
	player.flashlight_bounce = Color(ambient.x,ambient.y,ambient.z)
