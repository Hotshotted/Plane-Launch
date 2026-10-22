class_name Glyphs
extends RefCounted
## The icon set (docs/style.md, "Icons"): bold filled silhouettes and thick round strokes, no text, no emoji.
## Every icon is drawn in code onto any CanvasItem at centre `c`, fitting a box of radius `r`, in colour `col`.
## Two-tone only where the colour is the meaning (scrap gold, flame orange, danger red). The same icon always
## stands for the same thing: upgrades, launchers, frames, cosmetics, missions, stats and buttons.
##
##   upgrades   ramp wings body booster magnet            launchers  ramp sling catapult sled
##   frames     scrapper feather anvil pogo               cosmetics  paint hat trail  hat_cap hat_tophat hat_party hat_crown
##                                                         trail_sparkle trail_smoke trail_bubbles trail_rainbow
##   missions   bounce scrap distance noboost_zone skip updraft boost gear nobird ring balloon blimp tailwind highair find
##   stats      scrap gear star trophy flag speed altitude clock
##   buttons    play pause restart home back close check lock speaker note ad garage style daily chev_up chev_down rocket

const ALL := ["ramp", "wings", "body", "booster", "magnet", "sling", "catapult", "sled", "scrapper", "feather", "anvil", "pogo",
		"paint", "hat", "trail", "hat_cap", "hat_tophat", "hat_party", "hat_crown", "trail_sparkle", "trail_smoke", "trail_bubbles", "trail_rainbow",
		"bounce", "scrap", "distance", "noboost_zone", "skip", "updraft", "boost", "gear", "nobird", "star", "trophy", "flag", "speed", "altitude", "clock",
		"ring", "balloon", "blimp", "tailwind", "highair", "find", "propeller", "play", "pause", "restart", "home", "back", "close", "check", "lock", "speaker", "note", "ad", "garage", "style", "daily", "chev_up", "chev_down", "rocket"]

const GOLD := Style.ACCENT
const FLAME := Color(1.0, 0.55, 0.15)
const RED := Style.DANGER

static func _poly(ci: CanvasItem, c: Vector2, r: float, pts: Array, col: Color) -> void:
	var p := PackedVector2Array()
	for v in pts:
		p.append(c + (v as Vector2) * r)
	if p.size() >= 3:
		ci.draw_colored_polygon(p, col)

static func _line(ci: CanvasItem, c: Vector2, r: float, a: Vector2, b: Vector2, col: Color, w: float) -> void:
	ci.draw_line(c + a * r, c + b * r, col, w, true)

static func _poly_line(ci: CanvasItem, c: Vector2, r: float, pts: Array, col: Color, w: float) -> void:
	var p := PackedVector2Array()
	for v in pts:
		p.append(c + (v as Vector2) * r)
	ci.draw_polyline(p, col, w, true)

static func _circle(ci: CanvasItem, c: Vector2, r: float, at: Vector2, rad: float, col: Color) -> void:
	ci.draw_circle(c + at * r, rad * r, col)

static func _rect(ci: CanvasItem, c: Vector2, r: float, x: float, y: float, w: float, h: float, col: Color) -> void:
	ci.draw_rect(Rect2(c + Vector2(x, y) * r, Vector2(w, h) * r), col)

static func _bolt(ci: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	_poly(ci, c, r, [Vector2(0.15, -0.95), Vector2(-0.55, 0.1), Vector2(-0.05, 0.1), Vector2(-0.2, 0.95), Vector2(0.6, -0.15), Vector2(0.08, -0.15)], col)

static func _star(ci: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	var p := PackedVector2Array()
	for k in 10:
		var a := -PI * 0.5 + k * PI / 5.0
		p.append(c + Vector2(cos(a), sin(a)) * r * (1.0 if k % 2 == 0 else 0.45))
	ci.draw_colored_polygon(p, col)

static func _cog(ci: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	var p := PackedVector2Array()
	for k in 16:
		var a := k * TAU / 16.0
		p.append(c + Vector2(cos(a), sin(a)) * r * (1.0 if (k / 2) % 2 == 0 else 0.74))
	ci.draw_colored_polygon(p, col)
	ci.draw_circle(c, r * 0.32, Style.SURFACE_DARK if col.get_luminance() > 0.35 else Color(1, 1, 1, 0.9))

## A hex nut: the scrap currency.
static func _nut(ci: CanvasItem, c: Vector2, r: float, col: Color, hole: Color) -> void:
	var p := PackedVector2Array()
	for k in 6:
		var a := k * TAU / 6.0
		p.append(c + Vector2(cos(a), sin(a)) * r)
	ci.draw_colored_polygon(p, col)
	ci.draw_circle(c, r * 0.4, hole)

## Draw icon `id`. `col` is the main colour (its alpha fades the whole icon). `aux` is a second colour for the
## icons that have one (a paint swatch).
static func draw(ci: CanvasItem, id: String, c: Vector2, r: float, col: Color = Color.WHITE, aux: Color = Color(0, 0, 0, 0)) -> void:
	var w := maxf(r * 0.17, 3.0)
	var a := col.a
	var hole := Color(Style.SURFACE_DARK, a)
	match id:
		# ---------------- upgrades and launchers ----------------
		"ramp":
			_poly(ci, c, r, [Vector2(-0.95, -0.7), Vector2(-0.45, -0.7), Vector2(0.2, 0.05), Vector2(0.95, 0.15), Vector2(0.95, 0.4), Vector2(0.1, 0.35), Vector2(-0.95, -0.35)], col)
			_line(ci, c, r, Vector2(-0.6, -0.4), Vector2(-0.6, 0.95), col, w)
			_line(ci, c, r, Vector2(0.1, 0.3), Vector2(0.1, 0.95), col, w)
		"sling":
			_line(ci, c, r, Vector2(0, 0.95), Vector2(0, 0.1), col, w * 1.6)
			_line(ci, c, r, Vector2(0, 0.1), Vector2(-0.65, -0.85), col, w * 1.5)
			_line(ci, c, r, Vector2(0, 0.1), Vector2(0.65, -0.85), col, w * 1.5)
			_poly_line(ci, c, r, [Vector2(-0.65, -0.85), Vector2(0, -0.2), Vector2(0.65, -0.85)], Color(RED, a), w * 0.8)
		"catapult":
			_line(ci, c, r, Vector2(-0.85, 0.95), Vector2(-0.15, 0.1), col, w * 1.4)
			_line(ci, c, r, Vector2(0.55, 0.95), Vector2(-0.15, 0.1), col, w * 1.4)
			_line(ci, c, r, Vector2(0.75, 0.55), Vector2(-0.85, -0.75), col, w * 1.5)
			_circle(ci, c, r, Vector2(0.75, 0.6), 0.28, col)
		"sled":
			_line(ci, c, r, Vector2(-0.95, 0.65), Vector2(0.95, 0.65), col, w)
			_poly(ci, c, r, [Vector2(-0.35, 0.5), Vector2(0.75, 0.5), Vector2(0.75, 0.0), Vector2(0.2, -0.1), Vector2(-0.35, 0.0)], col)
			_poly(ci, c, r, [Vector2(-0.4, 0.1), Vector2(-0.95, 0.25), Vector2(-0.4, 0.4)], Color(FLAME, a))
		"wings":
			_poly(ci, c, r, [Vector2(-0.95, 0.35), Vector2(0.2, 0.35), Vector2(0.95, -0.55), Vector2(-0.1, -0.55)], col)
			_poly(ci, c, r, [Vector2(-0.6, 0.85), Vector2(0.45, 0.85), Vector2(0.8, 0.5), Vector2(-0.25, 0.5)], Color(col, a * 0.6))
		"body":
			_poly(ci, c, r, [Vector2(-0.95, 0.2), Vector2(-0.4, -0.5), Vector2(0.45, -0.45), Vector2(0.95, 0.05), Vector2(0.4, 0.55), Vector2(-0.7, 0.55)], col)
			ci.draw_circle(c + Vector2(0.05, -0.12) * r, r * 0.26, hole)
		"booster":
			_poly(ci, c, r, [Vector2(-0.35, -0.5), Vector2(0.55, -0.5), Vector2(0.95, 0.0), Vector2(0.55, 0.5), Vector2(-0.35, 0.5)], col)
			_poly(ci, c, r, [Vector2(-0.4, -0.35), Vector2(-0.95, 0.0), Vector2(-0.4, 0.35)], Color(FLAME, a))
			_rect(ci, c, r, 0.05, -0.5, 0.18, 1.0, hole)
		"magnet":
			_poly(ci, c, r, [Vector2(-0.75, -0.8), Vector2(-0.3, -0.8), Vector2(-0.3, 0.1), Vector2(0.3, 0.1), Vector2(0.3, -0.8), Vector2(0.75, -0.8), Vector2(0.75, 0.25), Vector2(0.4, 0.8), Vector2(-0.4, 0.8), Vector2(-0.75, 0.25)], col)
			_rect(ci, c, r, -0.75, -0.8, 0.45, 0.3, Color(1, 1, 1, a * 0.85))
			_rect(ci, c, r, 0.3, -0.8, 0.45, 0.3, Color(1, 1, 1, a * 0.85))
		# ---------------- frames ----------------
		"scrapper":
			_poly(ci, c, r, [Vector2(-0.85, 0.1), Vector2(0.65, 0.0), Vector2(0.95, 0.35), Vector2(0.7, 0.6), Vector2(-0.8, 0.6)], col)
			_poly(ci, c, r, [Vector2(-0.4, -0.05), Vector2(0.4, -0.05), Vector2(0.75, -0.7), Vector2(-0.05, -0.7)], Color(col, a * 0.7))
		"feather":
			_poly(ci, c, r, [Vector2(-0.9, 0.85), Vector2(-0.5, 0.0), Vector2(0.0, -0.7), Vector2(0.85, -0.9), Vector2(0.55, -0.1), Vector2(0.0, 0.5)], col)
			_line(ci, c, r, Vector2(-0.9, 0.85), Vector2(0.4, -0.45), hole, w * 0.7)
		"anvil":
			_poly(ci, c, r, [Vector2(-0.95, -0.7), Vector2(0.95, -0.7), Vector2(0.6, -0.3), Vector2(0.25, -0.2), Vector2(0.45, 0.4), Vector2(0.8, 0.85), Vector2(-0.8, 0.85), Vector2(-0.45, 0.4), Vector2(-0.25, -0.2), Vector2(-0.6, -0.3)], col)
		"pogo":
			_poly_line(ci, c, r, [Vector2(0, -0.3), Vector2(-0.4, -0.15), Vector2(0.4, 0.05), Vector2(-0.4, 0.25), Vector2(0.4, 0.45), Vector2(0, 0.6)], col, w * 1.1)
			_poly(ci, c, r, [Vector2(-0.7, -0.35), Vector2(0.7, -0.35), Vector2(0.55, -0.85), Vector2(-0.55, -0.85)], col)
			_rect(ci, c, r, -0.45, 0.65, 0.9, 0.22, col)
		# ---------------- cosmetics ----------------
		"paint":
			_poly(ci, c, r, [Vector2(0, -0.95), Vector2(0.65, 0.0), Vector2(0.7, 0.4), Vector2(0.4, 0.8), Vector2(-0.4, 0.8), Vector2(-0.7, 0.4), Vector2(-0.65, 0.0)], aux if aux.a > 0.0 else col)
			ci.draw_circle(c + Vector2(-0.25, 0.1) * r, r * 0.16, Color(1, 1, 1, a * 0.5))
		"hat", "hat_tophat":
			_rect(ci, c, r, -0.4, -0.8, 0.8, 1.0, col)
			_rect(ci, c, r, -0.9, 0.2, 1.8, 0.3, col)
			_rect(ci, c, r, -0.4, -0.05, 0.8, 0.14, Color(RED, a))
		"hat_cap":
			ci.draw_arc(c + Vector2(0, 0.35) * r, r * 0.8, PI, TAU, 14, col, r * 0.5)
			_poly(ci, c, r, [Vector2(0.2, 0.2), Vector2(0.95, 0.35), Vector2(0.9, 0.55), Vector2(0.2, 0.5)], Color(RED, a))
		"hat_party":
			_poly(ci, c, r, [Vector2(0, -0.85), Vector2(0.65, 0.7), Vector2(-0.65, 0.7)], col)
			_circle(ci, c, r, Vector2(0, -0.9), 0.17, Color(GOLD, a))
		"hat_crown":
			_poly(ci, c, r, [Vector2(-0.8, 0.6), Vector2(-0.8, -0.5), Vector2(-0.4, -0.05), Vector2(0, -0.8), Vector2(0.4, -0.05), Vector2(0.8, -0.5), Vector2(0.8, 0.6)], Color(GOLD, a))
		"trail", "trail_sparkle":
			_star(ci, c + Vector2(0.45, -0.1) * r, r * 0.5, col)
			_star(ci, c + Vector2(-0.35, 0.3) * r, r * 0.32, Color(col, a * 0.7))
			_star(ci, c + Vector2(-0.75, -0.4) * r, r * 0.2, Color(col, a * 0.5))
		"trail_smoke":
			_circle(ci, c, r, Vector2(0.45, 0.0), 0.4, col)
			_circle(ci, c, r, Vector2(-0.1, 0.1), 0.34, Color(col, a * 0.7))
			_circle(ci, c, r, Vector2(-0.6, 0.2), 0.26, Color(col, a * 0.45))
		"trail_bubbles":
			ci.draw_arc(c + Vector2(0.4, 0.0) * r, r * 0.38, 0.0, TAU, 16, col, w)
			ci.draw_arc(c + Vector2(-0.2, 0.35) * r, r * 0.28, 0.0, TAU, 14, col, w)
			ci.draw_arc(c + Vector2(-0.6, -0.3) * r, r * 0.18, 0.0, TAU, 12, col, w)
		"trail_rainbow":
			for k in 3:
				ci.draw_arc(c + Vector2(0, 0.55) * r, r * (0.9 - k * 0.27), PI, TAU, 16, [Color(RED, a), Color(GOLD, a), Color(Style.SUCCESS, a)][k], w * 1.3)
		# ---------------- missions (and the world things they count) ----------------
		"bounce":
			_poly(ci, c, r, [Vector2(0, -0.95), Vector2(0.6, -0.3), Vector2(0.2, -0.3), Vector2(0.2, 0.0), Vector2(-0.2, 0.0), Vector2(-0.2, -0.3), Vector2(-0.6, -0.3)], col)
			_poly_line(ci, c, r, [Vector2(-0.55, 0.3), Vector2(0.55, 0.45), Vector2(-0.55, 0.6), Vector2(0.55, 0.75)], col, w)
		"scrap":
			_nut(ci, c, r, Color(GOLD, a), Color(Style.ACCENT_DARK, a))
		"gear":
			_cog(ci, c, r, col)
		"distance":
			_line(ci, c, r, Vector2(-0.9, 0.0), Vector2(0.9, 0.0), col, w)
			_poly(ci, c, r, [Vector2(0.95, 0.0), Vector2(0.4, -0.45), Vector2(0.4, 0.45)], col)
			_line(ci, c, r, Vector2(-0.9, -0.4), Vector2(-0.9, 0.4), col, w)
		"noboost_zone":
			_bolt(ci, c, r * 0.85, col)
			_line(ci, c, r, Vector2(-0.85, -0.85), Vector2(0.85, 0.85), Color(RED, a), w * 1.2)
		"skip":
			_poly_line(ci, c, r, [Vector2(-0.95, 0.5), Vector2(-0.6, 0.35), Vector2(-0.25, 0.5), Vector2(0.1, 0.35), Vector2(0.45, 0.5)], col, w)
			ci.draw_arc(c + Vector2(0.45, 0.15) * r, r * 0.5, PI * 1.05, PI * 1.95, 10, col, w)
			_circle(ci, c, r, Vector2(0.7, -0.5), 0.2, col)
		"updraft":
			for k in 3:
				_poly_line(ci, c, r, [Vector2(-0.6, 0.55 - k * 0.5), Vector2(0, 0.05 - k * 0.5), Vector2(0.6, 0.55 - k * 0.5)], Color(col, a * (1.0 - k * 0.25)), w * 1.3)
		"boost":
			_bolt(ci, c, r, Color(FLAME, a))
		"nobird":
			_poly(ci, c, r, [Vector2(-0.8, 0.1), Vector2(-0.2, -0.45), Vector2(0.5, -0.35), Vector2(0.9, -0.1), Vector2(0.4, 0.3), Vector2(-0.3, 0.55)], col)
			_line(ci, c, r, Vector2(-0.85, -0.85), Vector2(0.85, 0.85), Color(RED, a), w * 1.2)
		# ---------------- stats ----------------
		"star":
			_star(ci, c, r, Color(GOLD, a))
		"trophy":
			_poly(ci, c, r, [Vector2(-0.6, -0.8), Vector2(0.6, -0.8), Vector2(0.5, 0.0), Vector2(0.0, 0.3), Vector2(-0.5, 0.0)], Color(GOLD, a))
			ci.draw_arc(c + Vector2(-0.6, -0.4) * r, r * 0.3, PI * 0.5, PI * 1.5, 8, Color(GOLD, a), w)
			ci.draw_arc(c + Vector2(0.6, -0.4) * r, r * 0.3, -PI * 0.5, PI * 0.5, 8, Color(GOLD, a), w)
			_rect(ci, c, r, -0.12, 0.25, 0.24, 0.35, Color(GOLD, a))
			_rect(ci, c, r, -0.45, 0.6, 0.9, 0.25, Color(GOLD, a))
		"flag":
			_line(ci, c, r, Vector2(-0.55, 0.95), Vector2(-0.55, -0.85), col, w * 1.2)
			_poly(ci, c, r, [Vector2(-0.55, -0.85), Vector2(0.85, -0.45), Vector2(-0.55, 0.0)], Color(RED, a))
		"speed":
			ci.draw_arc(c + Vector2(0, 0.3) * r, r * 0.85, PI, TAU, 20, col, w * 1.2)
			_line(ci, c, r, Vector2(0, 0.3), Vector2(0.5, -0.3), Color(FLAME, a), w * 1.2)
		"altitude":
			_poly(ci, c, r, [Vector2(-0.95, 0.8), Vector2(-0.2, -0.3), Vector2(0.2, 0.25), Vector2(0.5, -0.1), Vector2(0.95, 0.8)], col)
			_poly(ci, c, r, [Vector2(0.0, -0.95), Vector2(0.3, -0.55), Vector2(-0.3, -0.55)], col)
		"clock":
			ci.draw_arc(c, r * 0.9, 0.0, TAU, 28, col, w)
			_line(ci, c, r, Vector2.ZERO, Vector2(0, -0.6), col, w)
			_line(ci, c, r, Vector2.ZERO, Vector2(0.4, 0.2), col, w)
		# ---------------- buttons ----------------
		"play":
			_poly(ci, c, r, [Vector2(-0.5, -0.8), Vector2(-0.5, 0.8), Vector2(0.85, 0.0)], col)
		"pause":
			_rect(ci, c, r, -0.55, -0.7, 0.42, 1.4, col)
			_rect(ci, c, r, 0.13, -0.7, 0.42, 1.4, col)
		"restart":
			ci.draw_arc(c, r * 0.7, -PI * 0.15, PI * 1.5, 24, col, w * 1.5)
			_poly(ci, c, r, [Vector2(0.95, -0.05), Vector2(0.3, -0.2), Vector2(0.85, -0.8)], col)
		"home":
			_poly(ci, c, r, [Vector2(-0.95, -0.05), Vector2(0.0, -0.85), Vector2(0.95, -0.05)], col)
			_rect(ci, c, r, -0.6, -0.05, 1.2, 0.85, col)
			_rect(ci, c, r, -0.17, 0.3, 0.34, 0.5, hole)
		"back":
			_poly_line(ci, c, r, [Vector2(0.4, -0.7), Vector2(-0.4, 0.0), Vector2(0.4, 0.7)], col, w * 1.6)
		"close":
			_line(ci, c, r, Vector2(-0.7, -0.7), Vector2(0.7, 0.7), col, w * 1.6)
			_line(ci, c, r, Vector2(0.7, -0.7), Vector2(-0.7, 0.7), col, w * 1.6)
		"check":
			_poly_line(ci, c, r, [Vector2(-0.7, 0.0), Vector2(-0.2, 0.55), Vector2(0.8, -0.55)], col, w * 1.8)
		"lock":
			_rect(ci, c, r, -0.65, -0.1, 1.3, 0.95, col)
			ci.draw_arc(c + Vector2(0, -0.1) * r, r * 0.45, PI, TAU, 12, col, w * 1.3)
		"chev_down":
			_poly_line(ci, c, r, [Vector2(-0.7, -0.3), Vector2(0, 0.4), Vector2(0.7, -0.3)], col, w * 1.4)
		"chev_up":
			_poly_line(ci, c, r, [Vector2(-0.7, 0.3), Vector2(0, -0.4), Vector2(0.7, 0.3)], col, w * 1.4)
		"speaker":
			_poly(ci, c, r, [Vector2(-0.9, -0.35), Vector2(-0.4, -0.35), Vector2(0.15, -0.8), Vector2(0.15, 0.8), Vector2(-0.4, 0.35), Vector2(-0.9, 0.35)], col)
			ci.draw_arc(c + Vector2(0.15, 0) * r, r * 0.55, -PI * 0.35, PI * 0.35, 8, col, w)
			ci.draw_arc(c + Vector2(0.15, 0) * r, r * 0.95, -PI * 0.35, PI * 0.35, 8, col, w)
		"note":
			_circle(ci, c, r, Vector2(-0.4, 0.55), 0.38, col)
			_line(ci, c, r, Vector2(-0.05, 0.5), Vector2(-0.05, -0.8), col, w * 1.3)
			_poly(ci, c, r, [Vector2(-0.05, -0.8), Vector2(0.7, -0.4), Vector2(-0.05, -0.2)], col)
		"ad":
			ci.draw_rect(Rect2(c + Vector2(-0.9, -0.6) * r, Vector2(1.8, 1.2) * r), col, false, w)
			_poly(ci, c, r, [Vector2(-0.25, -0.35), Vector2(-0.25, 0.35), Vector2(0.4, 0.0)], col)
		"garage":      # a wrench
			_line(ci, c, r, Vector2(-0.7, 0.75), Vector2(0.35, -0.3), col, w * 1.7)
			ci.draw_arc(c + Vector2(0.5, -0.5) * r, r * 0.42, PI * 0.9, PI * 2.55, 12, col, w * 1.5)
		"style":      # a palette
			_poly(ci, c, r, [Vector2(-0.95, 0.0), Vector2(-0.6, -0.65), Vector2(0.0, -0.9), Vector2(0.7, -0.7), Vector2(0.95, -0.05), Vector2(0.6, 0.4), Vector2(0.15, 0.3), Vector2(0.1, 0.8), Vector2(-0.5, 0.75)], col)
			_circle(ci, c, r, Vector2(-0.4, -0.2), 0.16, Color(RED, a))
			_circle(ci, c, r, Vector2(0.05, -0.5), 0.16, Color(GOLD, a))
			_circle(ci, c, r, Vector2(0.5, -0.2), 0.16, Color(Style.SUCCESS, a))
		"daily":
			ci.draw_circle(c, r * 0.45, Color(GOLD, a))
			for k in 8:
				var an := k * PI / 4.0
				ci.draw_line(c + Vector2(cos(an), sin(an)) * r * 0.7, c + Vector2(cos(an), sin(an)) * r * 1.0, Color(GOLD, a), w * 1.3, true)
		"ring":          # a boost ring with the glider's path through it
			ci.draw_arc(c, r * 0.78, 0.0, TAU, 24, Color(FLAME, a), w * 1.7)
			ci.draw_arc(c, r * 0.78, 0.0, TAU, 24, Color(GOLD, a), w * 0.7)
			_line(ci, c, r, Vector2(-0.95, 0.35), Vector2(0.95, -0.35), col, w * 0.9)
			_poly(ci, c, r, [Vector2(0.95, -0.35), Vector2(0.45, -0.38), Vector2(0.62, 0.02)], col)
		"balloon":
			_circle(ci, c, r, Vector2(0, -0.28), 0.62, col)
			_poly(ci, c, r, [Vector2(-0.4, 0.15), Vector2(0.4, 0.15), Vector2(0.0, 0.42)], col)
			_line(ci, c, r, Vector2(-0.25, 0.3), Vector2(-0.18, 0.62), col, w * 0.6)
			_line(ci, c, r, Vector2(0.25, 0.3), Vector2(0.18, 0.62), col, w * 0.6)
			_rect(ci, c, r, -0.2, 0.6, 0.4, 0.32, col)
			_rect(ci, c, r, -0.08, -0.85, 0.16, 1.0, Color(1, 1, 1, a * 0.35))
		"blimp":
			var hull := []
			for k in 14:
				var an := k * TAU / 14.0
				hull.append(Vector2(cos(an) * 0.9, sin(an) * 0.42 - 0.08))
			_poly(ci, c, r, hull, col)
			_poly(ci, c, r, [Vector2(-0.7, -0.1), Vector2(-1.0, -0.45), Vector2(-0.45, -0.28)], col)
			_poly(ci, c, r, [Vector2(-0.7, 0.0), Vector2(-1.0, 0.35), Vector2(-0.45, 0.2)], col)
			_rect(ci, c, r, -0.2, 0.34, 0.4, 0.22, col)
			_line(ci, c, r, Vector2(-0.4, -0.35), Vector2(-0.4, 0.2), Color(1, 1, 1, a * 0.4), w * 0.5)
			_line(ci, c, r, Vector2(0.1, -0.4), Vector2(0.1, 0.25), Color(1, 1, 1, a * 0.4), w * 0.5)
		"tailwind":
			for k in 3:
				_poly_line(ci, c, r, [Vector2(-0.9, -0.5 + k * 0.5), Vector2(-0.3, -0.62 + k * 0.5), Vector2(0.3, -0.38 + k * 0.5), Vector2(0.75, -0.5 + k * 0.5)], col, w * 1.1)
			_poly(ci, c, r, [Vector2(0.95, 0.0), Vector2(0.5, -0.32), Vector2(0.5, 0.32)], col)
		"highair":
			_circle(ci, c, r, Vector2(-0.35, 0.3), 0.36, col)
			_circle(ci, c, r, Vector2(0.1, 0.18), 0.48, col)
			_circle(ci, c, r, Vector2(0.55, 0.34), 0.32, col)
			_rect(ci, c, r, -0.7, 0.3, 1.55, 0.36, col)
			_poly_line(ci, c, r, [Vector2(-0.25, -0.2), Vector2(0.1, -0.62), Vector2(0.45, -0.2)], Color(GOLD, a), w * 1.2)
			_poly_line(ci, c, r, [Vector2(-0.25, -0.62), Vector2(0.1, -0.98), Vector2(0.45, -0.62)], Color(GOLD, a * 0.6), w * 1.2)
		"find":          # a little flying saucer: the joke finds up in the sky
			var dome := []
			for k in 9:
				var an := PI + k * PI / 8.0
				dome.append(Vector2(cos(an) * 0.42, sin(an) * 0.5 - 0.1))
			_poly(ci, c, r, dome, Color(Style.PRIMARY.lightened(0.3), a))
			_poly(ci, c, r, [Vector2(-0.95, 0.15), Vector2(-0.5, -0.12), Vector2(0.5, -0.12), Vector2(0.95, 0.15), Vector2(0.5, 0.42), Vector2(-0.5, 0.42)], col)
			for k in 3:
				_circle(ci, c, r, Vector2(-0.4 + k * 0.4, 0.15), 0.08, Color(GOLD, a))
			_star(ci, c + Vector2(0.65, -0.65) * r, r * 0.3, Color(GOLD, a))
		"propeller":     # the studio mark: three bold blades round a hub
			for k in 3:
				var an := k * TAU / 3.0
				var rot := func(v: Vector2) -> Vector2: return v.rotated(an)
				var blade := [Vector2(-0.17, -0.14), Vector2(-0.3, -0.62), Vector2(-0.06, -0.97), Vector2(0.24, -0.72), Vector2(0.17, -0.14)]
				var pts: Array = []
				for v in blade:
					pts.append(rot.call(v))
				_poly(ci, c, r, pts, col)
				_line(ci, c, r, rot.call(Vector2(0.0, -0.3)), rot.call(Vector2(-0.02, -0.78)), Color(1, 1, 1, a * 0.35), w * 0.6)
			ci.draw_circle(c, r * 0.27, col)
			ci.draw_circle(c, r * 0.14, Color(GOLD, a))
		"rocket":      # LAUNCH
			_poly(ci, c, r, [Vector2(0.0, -0.95), Vector2(0.4, -0.3), Vector2(0.4, 0.4), Vector2(-0.4, 0.4), Vector2(-0.4, -0.3)], col)
			_poly(ci, c, r, [Vector2(-0.4, 0.05), Vector2(-0.85, 0.7), Vector2(-0.4, 0.4)], col)
			_poly(ci, c, r, [Vector2(0.4, 0.05), Vector2(0.85, 0.7), Vector2(0.4, 0.4)], col)
			_poly(ci, c, r, [Vector2(-0.22, 0.45), Vector2(0.22, 0.45), Vector2(0.0, 0.95)], Color(FLAME, a))
			ci.draw_circle(c + Vector2(0, -0.3) * r, r * 0.16, Color(Style.SURFACE_DARK, a))
		_:
			ci.draw_circle(c, r * 0.5, col)
