class_name FrameGraph
extends Control
## Debug: frame times of the last frames as bars, with 60 / 144 Hz guides.

const SCALE_MS := 40.0
var times := PackedFloat32Array()


func push(ms: float) -> void:
	times.append(ms)
	if times.size() > int(size.x / 2.0):
		times.remove_at(0)
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.45))
	for hz in [60.0, 144.0]:
		var y: float = size.y - (1000.0 / hz) / SCALE_MS * size.y
		draw_line(Vector2(0, y), Vector2(size.x, y), Color(1, 1, 1, 0.18))
		draw_string(ThemeDB.fallback_font, Vector2(2, y - 2), "%d Hz" % hz, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(1, 1, 1, 0.45))
	for i in times.size():
		var ms := times[i]
		var h := minf(ms / SCALE_MS, 1.0) * size.y
		var c := Color(0.55, 0.9, 0.45) if ms < 8.0 else (Color(0.95, 0.85, 0.3) if ms < 17.5 else Color(1.0, 0.35, 0.3))
		draw_rect(Rect2(i * 2.0, size.y - h, 2.0, h), c)
