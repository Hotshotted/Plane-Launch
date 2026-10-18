class_name Rusty
extends Control
## Rusty the Beaver, the junkyard mentor: a simple primitive portrait (drawn, no textures) and his
## one-liners after each flight. The portrait is a Control that draws itself; the lines are static data.

const GREETING := "Name's Rusty. Haul some scrap, beat my missions, and we'll build you a real glider. Hold the screen to climb, let go to dive!"
const RECORD := [
	"A NEW RECORD! Chew on that, kid!",
	"Farthest yet! I'm gonna tell the whole yard.",
	"That's a record! My teeth are tingling.",
	"Beaver-approved record flight!",
]
const GOOD := [
	"Smooth flying! Almost like you meant it.",
	"Now THAT'S a glide. Keep it up.",
	"Solid run. The wind likes you.",
	"Nice distance! More scrap, more wings.",
]
const BAD := [
	"Ouch. Bolt it back together and go again.",
	"Short one. Spend that scrap, it helps.",
	"Landed already? Even the pigeons flew farther.",
	"Shake it off, kid. Every flight is practice.",
]
const STALL := [
	"You stalled! When you're slow, let go and dive for speed.",
	"Nose too high for too long. Release and let her dive!",
]
const BIRD := [
	"Watch for the birds! They slow you right down.",
	"Feathers everywhere... dodge the birds next time.",
]
const MISSION := [
	"Mission done! Told you you had it in you.",
	"Another mission in the bag. Here's your scrap!",
	"Ha! That's how you do missions.",
]
const DAILY := [
	"Daily target smashed! Take the bonus, you earned it.",
	"That's the daily done. Same sky for everybody, kid, and you beat it!",
]
const ZONE := [
	"New territory! I've never been out that far.",
	"A whole new zone! Don't forget to wave.",
]

## Which line Rusty says after a flight. ctx: new_best, distance, best_before (the old best), mission_done,
## new_zone, stall_time, bird_hits, run (flight number, to vary the line).
static func comment(ctx: Dictionary) -> String:
	var run := int(ctx["run"])
	var list: Array
	if ctx.get("daily_reached", false):
		list = DAILY
	elif ctx["new_best"] and ctx["best_before"] > 0.0:
		list = RECORD
	elif ctx["new_zone"]:
		list = ZONE
	elif ctx["mission_done"]:
		list = MISSION
	elif ctx["stall_time"] > 1.2 and ctx["distance"] < ctx["best_before"] * 0.7:
		list = STALL
	elif ctx["bird_hits"] >= 2:
		list = BIRD
	elif ctx["best_before"] > 0.0 and ctx["distance"] < ctx["best_before"] * 0.5:
		list = BAD
	elif ctx["best_before"] <= 0.0 and ctx["distance"] < 40.0:
		list = BAD
	else:
		list = GOOD
	return list[run % list.size()]

# ---- the portrait ----
var _t := 0.0

func _process(delta: float) -> void:
	if is_visible_in_tree():
		_t += delta
		queue_redraw()

func _poly(pts: PackedVector2Array, col: Color) -> void:
	draw_colored_polygon(pts, col)
	var closed := pts.duplicate()
	closed.append(pts[0])
	draw_polyline(closed, Color.BLACK, 4.0)

func _blob(c: Vector2, r: Vector2, col: Color, sides: int = 12) -> void:
	var pts := PackedVector2Array()
	for i in sides:
		var a := TAU * i / sides
		pts.append(c + Vector2(cos(a) * r.x, sin(a) * r.y))
	_poly(pts, col)

func _draw() -> void:
	var s := minf(size.x, size.y) / 100.0
	var o := Vector2(size.x * 0.5, size.y * 0.5)
	var bob := sin(_t * 3.0) * 1.5 * s
	var fur := Color(0.62, 0.38, 0.2)
	var dark := Color(0.42, 0.25, 0.13)
	# flat tail behind
	_poly(PackedVector2Array([o + Vector2(28, 30) * s, o + Vector2(48, 22) * s, o + Vector2(52, 46) * s, o + Vector2(32, 48) * s]), dark)
	# body
	_blob(o + Vector2(0, 34 + bob / s) * s, Vector2(30, 24) * s, fur, 10)
	# ears
	_blob(o + Vector2(-26, -26 + bob / s) * s, Vector2(10, 10) * s, dark, 8)
	_blob(o + Vector2(26, -26 + bob / s) * s, Vector2(10, 10) * s, dark, 8)
	# head
	_blob(o + Vector2(0, -6 + bob / s) * s, Vector2(34, 30) * s, fur, 14)
	# snout and buck teeth
	_blob(o + Vector2(0, 8 + bob / s) * s, Vector2(18, 13) * s, Color(0.85, 0.65, 0.45), 10)
	_blob(o + Vector2(0, 2 + bob / s) * s, Vector2(7, 5) * s, Color(0.12, 0.08, 0.08), 8)
	_poly(PackedVector2Array([o + Vector2(-6, 12 + bob / s) * s, o + Vector2(6, 12 + bob / s) * s, o + Vector2(6, 26 + bob / s) * s, o + Vector2(-6, 26 + bob / s) * s]), Color(1, 1, 0.95))
	draw_line(o + Vector2(0, 12 + bob / s) * s, o + Vector2(0, 26 + bob / s) * s, Color.BLACK, 2.0)
	# goggles on the forehead and eyes
	_blob(o + Vector2(-13, -10 + bob / s) * s, Vector2(10, 10) * s, Color(0.7, 0.85, 0.95), 10)
	_blob(o + Vector2(13, -10 + bob / s) * s, Vector2(10, 10) * s, Color(0.7, 0.85, 0.95), 10)
	draw_circle(o + Vector2(-13, -10 + bob / s) * s, 3.5 * s, Color.BLACK)
	draw_circle(o + Vector2(13, -10 + bob / s) * s, 3.5 * s, Color.BLACK)
	draw_line(o + Vector2(-34, -16 + bob / s) * s, o + Vector2(34, -16 + bob / s) * s, Color(0.2, 0.2, 0.25), 5.0)
	# hard hat
	_poly(PackedVector2Array([o + Vector2(-26, -26 + bob / s) * s, o + Vector2(-16, -44 + bob / s) * s, o + Vector2(16, -44 + bob / s) * s, o + Vector2(26, -26 + bob / s) * s]), Color(1.0, 0.8, 0.1))
