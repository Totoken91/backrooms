class_name PanelLights
extends Node3D
## Real Godot lights for the panels nearest the camera (shadowed downward
## spots), and the flicker that drives both those lights and every panel's
## emission. The irradiance field carries all other panels.

const POOL := 4
const SELECT_RADIUS := 14.0
const LIGHT_COLOR := Color(1.0, 0.95, 0.82)

var streamer: WorldStreamer
var reduced_motion := false
var energy := 1.25
var shadows := true

var _lights: Array[SpotLight3D] = []
var _assigned: Array = []
var _time := 0.0
var _tick := -1
var _panels: Array = []
var _query := PhysicsRayQueryParameters3D.new()


func _ready() -> void:
	_query.collision_mask = 1
	for i in POOL:
		var light := SpotLight3D.new()
		light.light_color = LIGHT_COLOR
		light.spot_angle = 78.0
		light.spot_angle_attenuation = 0.8
		light.spot_range = 7.5
		light.spot_attenuation = 1.6
		light.light_energy = 0.0
		light.light_specular = 0.25
		light.shadow_enabled = shadows
		light.shadow_bias = 0.04
		light.shadow_normal_bias = 1.0
		light.shadow_blur = 1.5
		light.rotation = Vector3(-PI / 2, 0, 0)
		light.visible = false
		add_child(light)
		_lights.append(light)
		_assigned.append(null)


static func power(time: float, seed: int, steady: bool) -> float:
	var nominal := 0.76 + float(seed % 101) / 101.0 * 0.24
	if steady:
		return nominal
	var flutter := 0.985 + 0.015 * sin(time * 2.1 + seed % 127)
	var period := 11.0 + seed % 8
	var phase := fmod(time + float(seed % 997) / 997.0 * period, period)
	if seed % 9 != 0 or phase > 0.85:
		return nominal * flutter
	var dip := func(a: float, b: float) -> float: return clampf(minf((phase - a) / 0.045, (b - phase) / 0.045), 0.0, 1.0)
	return nominal * flutter * (1.0 - 0.88 * maxf(dip.call(0.08, 0.27), dip.call(0.48, 0.72)))


func refresh_panels() -> void:
	_panels = streamer.panels()


func update(delta: float, camera: Camera3D, running: bool) -> void:
	if running:
		_time += delta
	var tick := int(_time * 30.0)
	var eye := camera.global_position
	if tick != _tick:
		_tick = tick
		# Flicker: only panels whose seed flickers ever change their emission.
		for entry in _panels:
			var f = entry[2]
			if f.seed % 9 == 0 and is_instance_valid(entry[0]):
				entry[0].set_panel_power(entry[1], power(_time, f.seed, reduced_motion))
		_select(eye)
	for i in POOL:
		var light := _lights[i]
		var f = _assigned[i]
		var target := 0.0
		if f != null:
			target = power(_time, f.seed, reduced_motion) * energy
		# Lights fade in and out over ~0.25 s when the selection changes.
		var current := light.light_energy
		if f == null or light.visible:
			light.light_energy = move_toward(current, target, delta * energy * 4.0)
		if f == null and light.light_energy <= 0.001:
			light.visible = false


func _select(eye: Vector3) -> void:
	var space := get_world_3d().direct_space_state
	var candidates := []
	for entry in _panels:
		var f = entry[2]
		var d := Vector2(f.x - eye.x, f.z - eye.z).length()
		if d > SELECT_RADIUS:
			continue
		_query.from = eye
		_query.to = Vector3(f.x, LevelWorld.HEIGHT - 0.3, f.z)
		var visible := space.intersect_ray(_query).is_empty()
		candidates.append([d + (0.0 if visible else 6.0), f])
	candidates.sort_custom(func(a, b): return a[0] < b[0])
	var wanted := {}
	for i in mini(POOL, candidates.size()):
		wanted[candidates[i][1].id] = candidates[i][1]
	# Keep lights that remain wanted; free the others (they fade out first).
	for i in POOL:
		var f = _assigned[i]
		if f != null and wanted.has(f.id):
			wanted.erase(f.id)
		elif f != null:
			_assigned[i] = null
	for f in wanted.values():
		for i in POOL:
			if _assigned[i] == null and _lights[i].light_energy <= 0.001:
				_assigned[i] = f
				_lights[i].global_position = Vector3(f.x, LevelWorld.HEIGHT - 0.02, f.z)
				_lights[i].light_energy = 0.0
				_lights[i].visible = true
				break


func stats() -> Dictionary:
	var lit := 0
	for l in _lights:
		if l.visible:
			lit += 1
	return {"pool": POOL, "lit": lit, "panels": _panels.size()}
