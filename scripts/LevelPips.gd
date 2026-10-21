class_name LevelPips
extends Control
## A row of small squares showing an upgrade's level: filled up to `level`, hollow after, out of `max_level`.

var level := 0
var max_level := 10
var fill := Color(0.99, 0.60, 0.12)
var empty := Color(0.26, 0.29, 0.36)

func set_level(l: int, m: int) -> void:
	if l != level or m != max_level:
		level = l
		max_level = m
		queue_redraw()

func _draw() -> void:
	var n := maxi(max_level, 1)
	var gap := 5.0
	var w := (size.x - gap * (n - 1)) / n
	var h := minf(size.y, 22.0)
	var y := (size.y - h) * 0.5
	for i in n:
		var r := Rect2(i * (w + gap), y, w, h)
		draw_rect(r, fill if i < level else empty)
		draw_rect(r, Color.BLACK, false, 2.0)
