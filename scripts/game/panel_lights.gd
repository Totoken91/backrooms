class_name PanelLights
extends Node3D
## Panel states over time. Steady panels never change. Flickering panels
## belong to one of GROUPS circuits that flicker together: the baked light
## keeps each group's share of the direct light (LightBaker), so the surface
## shader dims the room with the group's power every frame, in step with the
## diffusers' emission. A panel switched off is remembered by the world and
## its surroundings are baked again (WorldStreamer.relight).

const GROUPS := 3

var streamer: WorldStreamer
var world: LevelWorld
var reduced_motion := false
## Current power factor of each flicker group (1 = nominal).
var group_power := Vector3.ONE
## Development: forces the groups' power (x < 0: off).
var force := Vector3(-1, -1, -1)

var _time := 0.0
var _tick := -1
var _panels: Array = []


## Flicker group of a panel: 0 for steady panels, 1..GROUPS otherwise.
static func group_of(seed: int) -> int:
	if seed % 9 != 0 or seed % 19 == 0:
		return 0
	return 1 + (seed / 9) % GROUPS


## Nominal power of a panel (a few dead tubes give no light).
static func nominal(seed: int) -> float:
	if seed % 19 == 0:
		return 0.02
	return 0.76 + float(seed % 101) / 101.0 * 0.24


## Power factor of a flicker group at a time: mostly 1, with irregular
## double dips (each group has its own period and phase).
static func group_factor(time: float, group: int) -> float:
	if group <= 0:
		return 1.0
	var period := 9.0 + group * 2.7
	var phase := fmod(time + group * 3.1, period)
	var flutter := 0.985 + 0.015 * sin(time * (2.1 + group * 0.4))
	if phase > 0.85:
		return flutter
	var dip := func(a: float, b: float) -> float: return clampf(minf((phase - a) / 0.045, (b - phase) / 0.045), 0.0, 1.0)
	return flutter * (1.0 - 0.88 * maxf(dip.call(0.08, 0.27), dip.call(0.48, 0.72)))


## Panel power at a time (steady: the nominal power, as baked).
static func power(time: float, seed: int, steady: bool) -> float:
	return nominal(seed) * (1.0 if steady else group_factor(time, group_of(seed)))


func refresh_panels() -> void:
	_panels = streamer.panels()


func update(delta: float, running: bool) -> void:
	if running:
		_time += delta
	var t := 0.0 if reduced_motion else _time
	group_power = Vector3(group_factor(t, 1), group_factor(t, 2), group_factor(t, 3))
	if force.x >= 0.0:
		group_power = force
	streamer.set_group_power(group_power)
	var tick := int(_time * 30.0)
	if tick == _tick:
		return
	_tick = tick
	# Emission of the flickering diffusers, in step with their group's light.
	for entry in _panels:
		var f = entry[2]
		var g := group_of(f.seed)
		if g > 0 and is_instance_valid(entry[0]) and not world.panels_off.has(f.id):
			entry[0].set_panel_power(entry[1], nominal(f.seed) * group_power[g - 1])


## Switches a panel off for good: dark diffuser, and its light baked away.
func switch_off(f) -> void:
	if world.panels_off.has(f.id):
		return
	world.panels_off[f.id] = true
	for entry in _panels:
		if entry[2] == f and is_instance_valid(entry[0]):
			entry[0].set_panel_power(entry[1], 0.0)
	streamer.relight(Vector2(f.x, f.z))


## The lit panel nearest to a point, within `radius` metres, or null.
func nearest(p: Vector3, radius := 6.0):
	var best = null
	var best_d := radius
	for entry in _panels:
		var f = entry[2]
		var d := Vector2(f.x - p.x, f.z - p.z).length()
		if d < best_d and not world.panels_off.has(f.id) and nominal(f.seed) > 0.1:
			best_d = d
			best = f
	return best
