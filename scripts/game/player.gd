class_name Player
extends CharacterBody3D
## First-person explorer. Movement is immediate (no inertia), the look applies
## each mouse report in full on the next frame, never smoothed.

signal stepped

const WALK := 2.0
const SPRINT := 3.8
const EYE := 1.52
const STRIDE := 0.78
const BASE_SENSITIVITY := 0.0016

var sensitivity_scale := 1.0
var active := false
var look_events := 0
var look_max_delta := 0.0

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D

var _stride := 0.0
var _walked := 0.0
var _bob := 0.0


func _ready() -> void:
	# The head turns outside physics ticks; interpolating it would add lag.
	head.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF


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
	var speed := SPRINT if sprinting else WALK
	velocity = Vector3(direction.x * speed, 0.0 if is_on_floor() else velocity.y - 9.8 * delta, direction.z * speed)
	var before := global_position
	move_and_slide()
	var moved := Vector2(global_position.x - before.x, global_position.z - before.z).length()
	_walked += moved
	_stride += moved
	if _stride >= STRIDE:
		_stride = fmod(_stride, STRIDE)
		stepped.emit()


func _process(delta: float) -> void:
	var moving := active and Vector2(velocity.x, velocity.z).length() > 0.1
	var target := sin(_walked / STRIDE * TAU) * 0.012 if moving else 0.0
	_bob = lerpf(_bob, target, 1.0 - exp(-delta * 18.0))
	camera.position.y = _bob
