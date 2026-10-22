class_name LevelPips
extends Control
## A row of round dots showing an upgrade's level: filled up to `level`, hollow after, out of `max_level`.

var level := 0
var max_level := 10
var fill := Style.ACCENT
var empty := Color(Style.INK, 0.55)
var pop := 0.0                  # 1 -> 0 right after a purchase: the newest dot pops in

## The newest dot pops in (the buy sequence).
func start_pop() -> void:
	pop = 1.0
	set_process(true)

func _ready() -> void:
	set_process(false)

func _process(delta: float) -> void:
	pop = maxf(pop - delta * 3.0, 0.0)
	if pop <= 0.0:
		set_process(false)
	queue_redraw()

func set_level(l: int, m: int) -> void:
	if l != level or m != max_level:
		level = l
		max_level = m
		queue_redraw()

func _draw() -> void:
	var n := maxi(max_level, 1)
	var d := minf(size.y, (size.x / n) * 0.8)
	var step := (size.x - d) / maxf(n - 1, 1)
	for i in n:
		var c := Vector2(d * 0.5 + i * step, size.y * 0.5)
		var k := 1.0
		if pop > 0.0 and i == level - 1:
			k = 1.0 + 0.9 * sin(pop * PI) * pop     # a quick overshoot
		draw_circle(c, d * 0.5 * k, fill if i < level else empty)
		if i < level:
			draw_arc(c, d * 0.5 - 1.0, PI * 1.1, PI * 1.9, 6, Color(1, 1, 1, 0.5), 2.0)
