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

func configure(w: LevelWorld, p: Player, mats: Dictionary) -> void:
	epoch += 1
	world = w
	player = p
	materials = mats
	map = null
	preparing = false
	key = Vector2i(1 << 30, 0)
	dirty = true
	for m in materials.values():
		m.set_shader_parameter("flashlight_enabled", false)
		m.set_shader_parameter("flashlight_shadow", viewport.get_texture())

func prepare(w: LevelWorld, wanted: Vector2i, revision: int) -> void:
	preparing = true
	var origin := Vector2(wanted) * 10.0 - Vector2(20, 20)
	var result := await SpanMap.build_sliced(w, origin, 480, 0.125, get_tree(), 1.0)
	if revision != epoch or world != w: return
	map = result
	key = wanted
	shadow.set_shader_parameter("span_a", ImageTexture.create_from_image(map.a))
	shadow.set_shader_parameter("span_b", ImageTexture.create_from_image(map.b))
	shadow.set_shader_parameter("occ_origin", origin)
	shadow.set_shader_parameter("occ_size", Vector2(480, 480))
	preparing = false
	dirty = true

func _process(_delta: float) -> void:
	if not player or not world: return
	var enabled: bool = player.flashlight.enabled and enabled_override
	if not enabled:
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
	for m in materials.values():
		m.set_shader_parameter("flashlight_enabled", ready)
		if ready:
			m.set_shader_parameter("flashlight_origin", source.origin)
			m.set_shader_parameter("flashlight_right", source.basis.x)
			m.set_shader_parameter("flashlight_up", source.basis.y)
			m.set_shader_parameter("flashlight_forward", -source.basis.z)
