class_name Player
extends CharacterBody3D
## First-person explorer. Walking is immediate (no inertia), the look applies
## each mouse report in full on the next frame, never smoothed. A skateboard
## (toggle_skate) rides with inertia for fast exploration.

signal stepped

const WALK := 2.0
const SPRINT := 3.8
const EYE := 1.52
const STRIDE := 0.78
const BASE_SENSITIVITY := 0.0016
# Skateboard: push up to SKATE_MAX (Shift: SKATE_BOOST), glide, brake with S.
const SKATE_MAX := 9.0
const SKATE_BOOST := 15.0
const SKATE_PUSH := 6.5
const SKATE_BRAKE := 9.0
const SKATE_GLIDE := 0.7
const BOARD_HEIGHT := 0.11

var sensitivity_scale := 1.0
var active := false
var look_events := 0
var look_max_delta := 0.0
var skating := false
## Horizontal speed (m/s) and distance travelled (m), for the debug readout.
var speed := 0.0
var walked := 0.0
## Linear irradiance / π at the player (set by the game), lights the board.
var light := Color(0.2, 0.2, 0.2)

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D

var flashlight_bounce := Color.BLACK
var flashlight: Node3D

var _stride := 0.0
var _walked := 0.0
var _bob := 0.0
var _board: Node3D
var _board_materials: Array[StandardMaterial3D] = []
var _board_colors: Array[Color] = []
var _roll := 0.0


func _ready() -> void:
	# The head turns outside physics ticks; interpolating it would add lag.
	head.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_build_board()
	flashlight = load("res://assets/flashlight/flashlight.tscn").instantiate()
	camera.add_child(flashlight)


## Deck with grip tape and four wheels, under the player (seen looking down).
func _build_board() -> void:
	_board = Node3D.new()
	_board.visible = false
	add_child(_board)
	var part := func(mesh: Mesh, at: Vector3, color: Color, rot := Vector3.ZERO) -> void:
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_board_materials.append(m)
		_board_colors.append(color)
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = m
		mi.position = at
		mi.rotation = rot
		_board.add_child(mi)
	var deck := BoxMesh.new()
	deck.size = Vector3(0.21, 0.014, 0.8)
	part.call(deck, Vector3(0, 0.092, 0), Color(0.62, 0.36, 0.17))
	var grip := BoxMesh.new()
	grip.size = Vector3(0.2, 0.004, 0.76)
	part.call(grip, Vector3(0, 0.101, 0), Color(0.13, 0.13, 0.12))
	for zx in [Vector2(-0.075, -0.27), Vector2(0.075, -0.27), Vector2(-0.075, 0.27), Vector2(0.075, 0.27)]:
		var wheel := CylinderMesh.new()
		wheel.top_radius = 0.028
		wheel.bottom_radius = 0.028
		wheel.height = 0.032
		part.call(wheel, Vector3(zx.x, 0.028, zx.y), Color(0.86, 0.84, 0.76), Vector3(0, 0, PI / 2))
	for z in [-0.27, 0.27]:
		var truck := BoxMesh.new()
		truck.size = Vector3(0.17, 0.035, 0.045)
		part.call(truck, Vector3(0, 0.065, z), Color(0.55, 0.56, 0.57))
	# A little ahead of the eyes, so looking down shows the whole board.
	for c in _board.get_children():
		c.position.z -= 0.3


func toggle_skate() -> void:
	skating = not skating
	_board.visible = skating
	_board.rotation.y = head.rotation.y
	if not skating:
		head.rotation.z = 0.0


func place(position_: Vector3, yaw: float, pitch := 0.0) -> void:
	global_position = Vector3(position_.x, 0.0, position_.z)
	velocity = Vector3.ZERO
	# Godot's -Z is "north" (yaw 0) like the plan; yaw grows clockwise from above.
	head.rotation = Vector3(pitch, -yaw, 0.0)
	reset_physics_interpolation()


func yaw() -> float:
	return -head.rotation.y


func pitch() -> float:
	return head.rotation.x


func _unhandled_input(event: InputEvent) -> void:
	if not active or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F:
		flashlight.enabled = not flashlight.enabled
		get_viewport().set_input_as_handled()
	if event is InputEventMouseMotion:
		var d: Vector2 = event.relative
		look_events += 1
		look_max_delta = maxf(look_max_delta, maxf(absf(d.x), absf(d.y)))
		var k := BASE_SENSITIVITY * sensitivity_scale
		head.rotation.y = wrapf(head.rotation.y - d.x * k, -PI, PI)
		head.rotation.x = clampf(head.rotation.x - d.y * k, -1.2, 1.2)


func _key(keys: Array) -> bool:
	for k in keys:
		if Input.is_physical_key_pressed(k):
			return true
	return false


func _physics_process(delta: float) -> void:
	if not active:
		velocity = Vector3.ZERO
		return
	# Physical keys: WASD positions, so ZQSD works on AZERTY keyboards.
	var forward := float(_key([KEY_W, KEY_UP])) - float(_key([KEY_S, KEY_DOWN]))
	var side := float(_key([KEY_D])) - float(_key([KEY_A]))
	var turn := float(_key([KEY_RIGHT])) - float(_key([KEY_LEFT]))
	var sprinting := _key([KEY_SHIFT])
	if turn != 0.0:
		head.rotation.y = wrapf(head.rotation.y - turn * delta * 1.6, -PI, PI)
	var input := Vector2(side, -forward)
	if input.length() > 1.0:
		input = input.normalized()
	var basis_yaw := Basis(Vector3.UP, head.rotation.y)
	var direction := basis_yaw * Vector3(input.x, 0.0, input.y)
	var fall := 0.0 if is_on_floor() else velocity.y - 9.8 * delta
	if skating:
		_skate(delta, forward, direction, sprinting)
	else:
		var walk_speed := SPRINT if sprinting else WALK
		velocity = Vector3(direction.x * walk_speed, 0.0, direction.z * walk_speed)
	velocity.y = fall
	var before := global_position
	move_and_slide()
	var moved := Vector2(global_position.x - before.x, global_position.z - before.z).length()
	speed = moved / delta
	walked += moved
	_walked += moved
	if skating:
		return
	_stride += moved
	if _stride >= STRIDE:
		_stride = fmod(_stride, STRIDE)
		stepped.emit()


## Skateboard: pushing accelerates along the input direction, the board
## glides when released, S brakes; walls take the speed away (slide).
func _skate(delta: float, forward: float, direction: Vector3, boost: bool) -> void:
	var v := Vector2(velocity.x, velocity.z)
	var top := SKATE_BOOST if boost else SKATE_MAX
	if forward < 0.0 and v.length() > 0.2:
		v = v.move_toward(Vector2.ZERO, SKATE_BRAKE * delta)
	elif direction.length() > 0.01:
		var d := Vector2(direction.x, direction.z)
		# Carve: the heading follows the input, the speed is kept.
		var along := maxf(v.dot(d), 0.0)
		v = v.lerp(d * maxf(along, v.length()), 1.0 - exp(-delta * 3.5))
		if v.length() < top:
			v += d * SKATE_PUSH * (1.6 if boost else 1.0) * delta
		else:
			v = v.move_toward(v.normalized() * top, SKATE_BRAKE * delta)
	else:
		v = v.move_toward(Vector2.ZERO, SKATE_GLIDE * delta)
	# Lean into turns: lateral acceleration rolls the view a little.
	var old := Vector2(velocity.x, velocity.z)
	var lateral := 0.0
	if old.length() > 0.5:
		lateral = old.normalized().cross(v - old) / delta
	_roll = lerpf(_roll, clampf(lateral * 0.012, -0.12, 0.12), 1.0 - exp(-delta * 6.0))
	velocity = Vector3(v.x, velocity.y, v.y)


func _process(delta: float) -> void:
	if flashlight: flashlight.update_light(light + flashlight_bounce, delta, active and speed > 0.1)
	var moving := active and Vector2(velocity.x, velocity.z).length() > 0.1
	var target := sin(_walked / STRIDE * TAU) * 0.012 if moving and not skating else 0.0
	_bob = lerpf(_bob, target, 1.0 - exp(-delta * 18.0))
	camera.position.y = _bob + (BOARD_HEIGHT if skating else 0.0)
	if skating:
		head.rotation.z = _roll
		var v := Vector2(velocity.x, velocity.z)
		# The board points along the motion (Godot -Z forward), or the gaze at rest.
		var heading := atan2(-v.x, -v.y) if v.length() > 0.3 else head.rotation.y
		_board.rotation.y = lerp_angle(_board.rotation.y, heading, 1.0 - exp(-delta * 10.0))
		_board.rotation.z = -_roll * 1.5
		for i in _board_materials.size():
			var c: Color = _board_colors[i].srgb_to_linear() * light
			_board_materials[i].albedo_color = Color(c.r, c.g, c.b).linear_to_srgb()
