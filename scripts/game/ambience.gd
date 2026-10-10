class_name Ambience
extends Node
## Fluorescent hum and carpet footsteps, synthesised at start-up.

const RATE := 22050

var enabled := true:
	set(value):
		enabled = value
		_apply()

var _hum := AudioStreamPlayer.new()
var _steps: Array[AudioStreamPlayer] = []
var _next := 0
var _running := false


func _ready() -> void:
	_hum.stream = _hum_stream()
	_hum.volume_db = -30.0
	add_child(_hum)
	var step := _step_stream()
	for i in 3:
		var p := AudioStreamPlayer.new()
		p.stream = step
		p.volume_db = -14.0
		add_child(p)
		_steps.append(p)


func set_running(running: bool) -> void:
	_running = running
	_apply()


func _apply() -> void:
	if not is_inside_tree():
		return
	var on := enabled and _running
	if on and not _hum.playing:
		_hum.play()
	elif not on and _hum.playing:
		_hum.stop()


func step() -> void:
	if not (enabled and _running):
		return
	var p := _steps[_next]
	_next = (_next + 1) % _steps.size()
	p.pitch_scale = randf_range(0.9, 1.08)
	p.play()


static func _wav(samples: PackedFloat32Array, loop: bool) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.data = data
	if loop:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_end = samples.size()
	return wav


## One second of 50/100/150 Hz mains hum: whole periods, so it loops cleanly.
static func _hum_stream() -> AudioStreamWAV:
	var s := PackedFloat32Array()
	s.resize(RATE)
	for i in RATE:
		var t := float(i) / RATE
		s[i] = 0.5 * sin(TAU * 50.0 * t) + 0.35 * sin(TAU * 100.0 * t) + 0.2 * sin(TAU * 150.0 * t)
	return _wav(s, true)


## Low-passed noise burst with a soft thump.
static func _step_stream() -> AudioStreamWAV:
	var n := int(RATE * 0.16)
	var s := PackedFloat32Array()
	s.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var low := 0.0
	for i in n:
		var t := float(i) / n
		low += (rng.randf_range(-1.0, 1.0) - low) * 0.12
		s[i] = (low * 1.4 + 0.35 * sin(TAU * 55.0 * i / RATE)) * pow(1.0 - t, 3.0)
	return _wav(s, false)
