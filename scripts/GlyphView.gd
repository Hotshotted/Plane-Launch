class_name GlyphView
extends Control
## One icon from Glyphs as a Control, optionally on a round plate (the look of every card and row icon).

var id := "ramp"
var col := Style.TEXT
var aux := Color(0, 0, 0, 0)
var plate := Color(0, 0, 0, 0)     # alpha 0 = no plate
var fit := 0.86                     # icon radius as a share of the half-size
var rot := 0.0                      # radians (the studio propeller spins)

func set_glyph(g: String, c: Color = Color(-1, 0, 0, 0), a: Color = Color(0, 0, 0, 0)) -> void:
	var cc := col if c.r < 0.0 else c
	if g != id or cc != col or a != aux:
		id = g
		col = cc
		aux = a
		queue_redraw()

func _draw() -> void:
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.5
	if plate.a > 0.0:
		draw_circle(c + Vector2(0, 3), r, Color(Style.INK, 0.5))
		draw_circle(c, r, plate)
		draw_arc(c, r - 1.5, 0.0, TAU, 28, Color(1, 1, 1, 0.14), 3.0)
		r *= fit * 0.78
	else:
		r *= fit
	if rot != 0.0:
		draw_set_transform(c, rot)
		Glyphs.draw(self, id, Vector2.ZERO, r, col, aux)
		draw_set_transform(Vector2.ZERO, 0.0)
	else:
		Glyphs.draw(self, id, c, r, col, aux)
