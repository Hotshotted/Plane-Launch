class_name UpgradeIcon
extends Control
## A small drawn icon for an upgrade card (flat shapes, black outlines, like the rest of the game):
## ramp, sling, catapult, sled (the Launcher card follows the equipped launcher), wings, body, booster, magnet.

var kind := "ramp"

func set_kind(k: String) -> void:
	if k != kind:
		kind = k
		queue_redraw()

func _poly(pts: Array, col: Color, lw: float = 3.0) -> void:
	var p := PackedVector2Array()
	var s := minf(size.x, size.y) / 100.0
	var o := (size - Vector2(100, 100) * s) * 0.5
	for v in pts:
		p.append(o + v * s)
	draw_colored_polygon(p, col)
	p.append(p[0])
	draw_polyline(p, Color.BLACK, lw)

func _line(a: Vector2, b: Vector2, col: Color, w: float) -> void:
	var s := minf(size.x, size.y) / 100.0
	var o := (size - Vector2(100, 100) * s) * 0.5
	draw_line(o + a * s, o + b * s, Color.BLACK, w + 5.0)
	draw_line(o + a * s, o + b * s, col, w)

func _draw() -> void:
	var wood := Color(0.62, 0.48, 0.32)
	match kind:
		"wings":
			_poly([Vector2(8, 60), Vector2(70, 60), Vector2(94, 28), Vector2(34, 28)], Color(0.92, 0.88, 0.72))
			_line(Vector2(26, 60), Vector2(50, 28), Color(0, 0, 0, 0.5), 3.0)
			_line(Vector2(48, 60), Vector2(72, 28), Color(0, 0, 0, 0.5), 3.0)
			_poly([Vector2(20, 76), Vector2(80, 76), Vector2(80, 86), Vector2(20, 86)], Color(0.62, 0.34, 0.2), 3.0)
		"body":
			_poly([Vector2(6, 58), Vector2(58, 32), Vector2(94, 52), Vector2(58, 72), Vector2(14, 72)], Color(0.2, 0.62, 0.7))
			_poly([Vector2(40, 34), Vector2(60, 24), Vector2(62, 40)], Color(0.93, 0.76, 0.6), 3.0)
		"booster":
			_poly([Vector2(26, 36), Vector2(76, 36), Vector2(86, 50), Vector2(76, 64), Vector2(26, 64)], Color(0.55, 0.57, 0.62))
			_poly([Vector2(26, 40), Vector2(2, 50), Vector2(26, 60)], Color(1.0, 0.65, 0.15), 3.0)
			_poly([Vector2(34, 36), Vector2(46, 36), Vector2(46, 64), Vector2(34, 64)], Color(0.85, 0.25, 0.2), 2.0)
		"magnet":
			_poly([Vector2(18, 20), Vector2(38, 20), Vector2(38, 58), Vector2(62, 58), Vector2(62, 20), Vector2(82, 20), Vector2(82, 66), Vector2(62, 90), Vector2(38, 90), Vector2(18, 66)], Color(0.85, 0.15, 0.15))
			_poly([Vector2(18, 20), Vector2(38, 20), Vector2(38, 34), Vector2(18, 34)], Color(0.85, 0.85, 0.9), 2.0)
			_poly([Vector2(62, 20), Vector2(82, 20), Vector2(82, 34), Vector2(62, 34)], Color(0.85, 0.85, 0.9), 2.0)
		"sling":
			_line(Vector2(50, 96), Vector2(50, 58), wood, 12.0)
			_line(Vector2(50, 58), Vector2(22, 22), wood, 10.0)
			_line(Vector2(50, 58), Vector2(78, 22), wood, 10.0)
			_line(Vector2(22, 24), Vector2(50, 50), Color(0.85, 0.25, 0.2), 5.0)
			_line(Vector2(78, 24), Vector2(50, 50), Color(0.85, 0.25, 0.2), 5.0)
		"catapult":
			_line(Vector2(24, 94), Vector2(46, 52), wood, 9.0)
			_line(Vector2(70, 94), Vector2(46, 52), wood, 9.0)
			_line(Vector2(78, 70), Vector2(14, 20), wood.lightened(0.15), 9.0)
			_poly([Vector2(74, 62), Vector2(94, 62), Vector2(94, 82), Vector2(74, 82)], Color(0.35, 0.35, 0.4), 3.0)
		"sled":
			_line(Vector2(4, 76), Vector2(96, 56), Color(0.75, 0.75, 0.8), 6.0)
			_poly([Vector2(30, 64), Vector2(78, 54), Vector2(80, 42), Vector2(34, 50)], Color(0.8, 0.2, 0.15))
			_poly([Vector2(30, 56), Vector2(6, 50), Vector2(30, 46)], Color(1.0, 0.65, 0.15), 2.0)
		_:   # ramp
			_poly([Vector2(6, 22), Vector2(34, 26), Vector2(70, 56), Vector2(96, 60), Vector2(96, 70), Vector2(66, 68), Vector2(30, 38), Vector2(6, 34)], wood)
			_line(Vector2(20, 34), Vector2(20, 94), wood.darkened(0.2), 6.0)
			_line(Vector2(56, 52), Vector2(56, 94), wood.darkened(0.2), 6.0)
