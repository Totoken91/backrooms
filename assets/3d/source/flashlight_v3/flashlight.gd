extends Node3D
## Attach flashlight.tscn directly beneath the player's Camera3D.
@export var enabled := true:
	set(value):
		enabled = value
		if is_node_ready():
			$Beam.visible = value
@export var allow_keyboard_toggle := true
@export_range(0.0, 1.0) var movement_amount := 0.35
var _rest := Vector3.ZERO
var _time := 0.0

func _ready() -> void:
	_rest = position
	$Beam.visible = enabled

func _unhandled_key_input(event: InputEvent) -> void:
	if allow_keyboard_toggle and event is InputEventKey:
		if event.pressed and not event.echo and event.physical_keycode == KEY_F:
			if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
				enabled = not enabled
				get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	_time += delta
	position = _rest + Vector3(sin(_time * 1.4) * 0.002, sin(_time * 1.8) * 0.002, 0.0) * movement_amount
