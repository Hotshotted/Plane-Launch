class_name WorldView
extends Node2D
## Draws the whole side-view world in one _draw(): sky, parallax hills and junk piles, ground and props,
## the ramp, the things, the glider (which shows every upgrade) and the particles. Low-poly flat
## shapes with black outlines. Nothing is allocated per frame: the polygon scratch buffers are made
## once, particles live in a fixed pool, text comes from cached strings.

const OUTLINE := 3.0
const PARTICLES := 72
const MAX_SIDES := 16

# Particle kinds
const P_SPARK := 0   # scrap pickup glint
const P_RUBBER := 1  # bounce pad puff
const P_FEATHER := 2
const P_FLAME := 3
const P_DUST := 4
const P_SCRAP := 5   # chunks flying off a hard landing

# ---- palette ----
const SKY_TOP := Color(0.36, 0.64, 0.88)
const SKY_MID := Color(0.58, 0.80, 0.93)
const SKY_LOW := Color(0.85, 0.92, 0.90)
const HILL_FAR := Color(0.52, 0.68, 0.74)
const HILL_NEAR := Color(0.45, 0.58, 0.55)
const PILE := Color(0.50, 0.44, 0.40)
const PILE_DARK := Color(0.38, 0.34, 0.33)
const DIRT := Color(0.42, 0.32, 0.24)
const DIRT_TOP := Color(0.55, 0.44, 0.30)
const BLACK := Color(0, 0, 0)

# ---- shape templates (meters, screen orientation: +x right, +y DOWN) ----
static var HEX := PackedVector2Array([Vector2(0.6, 0), Vector2(0.3, 0.52), Vector2(-0.3, 0.52), Vector2(-0.6, 0), Vector2(-0.3, -0.52), Vector2(0.3, -0.52)])
static var OCT := PackedVector2Array([Vector2(1, 0.38), Vector2(0.38, 1), Vector2(-0.38, 1), Vector2(-1, 0.38), Vector2(-1, -0.38), Vector2(-0.38, -1), Vector2(0.38, -1), Vector2(1, -0.38)])
static var RECT := PackedVector2Array([Vector2(-0.5, -0.5), Vector2(0.5, -0.5), Vector2(0.5, 0.5), Vector2(-0.5, 0.5)])
static var TRI := PackedVector2Array([Vector2(0, -0.5), Vector2(0.5, 0.5), Vector2(-0.5, 0.5)])
static var DIAMOND := PackedVector2Array([Vector2(0.5, 0), Vector2(0, 0.5), Vector2(-0.5, 0), Vector2(0, -0.5)])
static var GEAR := PackedVector2Array([
	Vector2(1.0, 0.0), Vector2(0.78, 0.30), Vector2(0.62, 0.62), Vector2(0.30, 0.78), Vector2(0.0, 1.0), Vector2(-0.30, 0.78),
	Vector2(-0.62, 0.62), Vector2(-0.78, 0.30), Vector2(-1.0, 0.0), Vector2(-0.78, -0.30), Vector2(-0.62, -0.62), Vector2(-0.30, -0.78),
	Vector2(0.0, -1.0), Vector2(0.30, -0.78), Vector2(0.62, -0.62), Vector2(0.78, -0.30)])
static var CLOUD := PackedVector2Array([Vector2(-2.6, 0.5), Vector2(-2.2, -0.4), Vector2(-1.0, -0.9), Vector2(0.2, -1.5), Vector2(1.6, -0.8), Vector2(2.6, -0.2), Vector2(2.7, 0.5)])
static var BIRD_BODY := PackedVector2Array([Vector2(-1.1, 0.1), Vector2(-0.3, -0.5), Vector2(0.8, -0.35), Vector2(1.1, 0.1), Vector2(0.2, 0.55)])
static var BIRD_WING := PackedVector2Array([Vector2(0.4, 0), Vector2(-0.6, 0), Vector2(-0.2, -1.3)])
static var BIRD_BEAK := PackedVector2Array([Vector2(1.1, -0.15), Vector2(1.7, 0.05), Vector2(1.1, 0.25)])
# glider bits
static var TUB := PackedVector2Array([Vector2(-2.0, -0.35), Vector2(1.3, -0.45), Vector2(2.0, 0.0), Vector2(1.5, 0.55), Vector2(-1.7, 0.5), Vector2(-2.1, 0.1)])
static var FUSE_MID := PackedVector2Array([Vector2(-2.3, -0.3), Vector2(1.6, -0.5), Vector2(2.7, 0.05), Vector2(1.7, 0.55), Vector2(-2.0, 0.5)])
static var FUSE_SLEEK := PackedVector2Array([Vector2(-2.6, -0.25), Vector2(0.8, -0.62), Vector2(2.9, -0.05), Vector2(2.9, 0.15), Vector2(0.6, 0.62), Vector2(-2.4, 0.35)])
static var FIN := PackedVector2Array([Vector2(-1.8, -0.3), Vector2(-3.0, -1.4), Vector2(-3.3, -0.3)])
static var STAB := PackedVector2Array([Vector2(-2.2, -0.2), Vector2(-3.5, -0.45), Vector2(-3.6, -0.15), Vector2(-2.2, 0.1)])
static var BOOM := PackedVector2Array([Vector2(-2.0, -0.15), Vector2(-3.6, -0.3), Vector2(-3.6, -0.05), Vector2(-2.0, 0.2)])
static var HORSESHOE := PackedVector2Array([Vector2(-0.5, -0.5), Vector2(-0.2, -0.5), Vector2(-0.2, 0.0), Vector2(0.2, 0.0), Vector2(0.2, -0.5), Vector2(0.5, -0.5), Vector2(0.5, 0.2), Vector2(0.3, 0.5), Vector2(-0.3, 0.5), Vector2(-0.5, 0.2)])
static var FLAME := PackedVector2Array([Vector2(0, -0.28), Vector2(-1.0, 0.0), Vector2(0, 0.28)])

# set by Main every frame
var flight: Flight
var cam_x := 0.0
var cam_bottom := 0.0
var ppm := 28.0          # pixels per meter (the camera zoom; the shop zooms out for tall ramps)
var best_text := ""
var best_x := 0.0
var show_aura := false
var showcase := false   # pre-warm: draw one of everything

var _font: Font
var _fill: Array[PackedVector2Array] = []
var _line: Array[PackedVector2Array] = []
var _ramp_fill := PackedVector2Array()
var _ramp_top_line := PackedVector2Array()
var _ramp_bot_line := PackedVector2Array()
var _sign_text: Array[String] = []

# particle pool
var _px := PackedFloat32Array()
var _py := PackedFloat32Array()
var _pvx := PackedFloat32Array()
var _pvy := PackedFloat32Array()
var _plife := PackedFloat32Array()
var _pmax := PackedFloat32Array()
var _psize := PackedFloat32Array()
var _pkind := PackedInt32Array()
var _pcol := PackedColorArray()
var _pnext := 0
var _time := 0.0

# per-frame draw state
var _ppm := 28.0
var _size := Vector2(1080, 1920)
var _ground_sy := 0.0

func _ready() -> void:
	_font = ThemeDB.fallback_font
	for n in MAX_SIDES + 1:
		_fill.append(PackedVector2Array())
		_line.append(PackedVector2Array())
		if n >= 3:
			_fill[n].resize(n)
			_line[n].resize(n + 1)
	var rn := Tuning.RAMP_N + 1
	_ramp_fill.resize(rn * 2)
	_ramp_top_line.resize(rn)
	_ramp_bot_line.resize(rn)
	for p in [_px, _py, _pvx, _pvy, _plife, _pmax, _psize]:
		p.resize(PARTICLES)
	_pkind.resize(PARTICLES)
	_pcol.resize(PARTICLES)
	for i in 400:
		_sign_text.append("%d m" % ((i + 1) * 100))

# ---------------------------------------------------------------------------------------------
# Particles
# ---------------------------------------------------------------------------------------------

func spawn(kind: int, wx: float, wy: float, vx: float, vy: float, life: float, size: float, col: Color) -> void:
	var i := _pnext
	_pnext = (_pnext + 1) % PARTICLES
	_px[i] = wx
	_py[i] = wy
	_pvx[i] = vx
	_pvy[i] = vy
	_plife[i] = life
	_pmax[i] = life
	_psize[i] = size
	_pkind[i] = kind
	_pcol[i] = col

func burst(kind: int, wx: float, wy: float, n: int, speed: float, life: float, size: float, col: Color, rng: RandomNumberGenerator) -> void:
	for k in n:
		var a := rng.randf() * TAU
		var s := speed * (0.4 + rng.randf() * 0.6)
		spawn(kind, wx, wy, cos(a) * s, sin(a) * s, life * (0.6 + rng.randf() * 0.4), size, col)

func clear_particles() -> void:
	for i in PARTICLES:
		_plife[i] = 0.0

func update_particles(dt: float) -> void:
	_time += dt
	for i in PARTICLES:
		if _plife[i] <= 0.0:
			continue
		_plife[i] -= dt
		_px[i] += _pvx[i] * dt
		_py[i] += _pvy[i] * dt
		match _pkind[i]:
			P_FEATHER, P_SCRAP:
				_pvy[i] -= 9.0 * dt
			P_RUBBER, P_DUST:
				_pvx[i] *= 1.0 - 2.0 * dt
				_pvy[i] *= 1.0 - 2.0 * dt

func live_particles() -> int:
	var n := 0
	for i in PARTICLES:
		if _plife[i] > 0.0:
			n += 1
	return n

# ---------------------------------------------------------------------------------------------
# Drawing helpers
# ---------------------------------------------------------------------------------------------

## Screen position of a world point (valid after the camera values are set).
func to_screen(wx: float, wy: float) -> Vector2:
	var sz := get_viewport_rect().size
	return Vector2((wx - cam_x) * ppm, sz.y + cam_bottom * ppm - wy * ppm)

func _sx(wx: float) -> float:
	return (wx - cam_x) * _ppm

func _sy(wy: float) -> float:
	return _ground_sy - wy * _ppm

## A filled polygon with a black outline. `tpl` is in meters (y down); it is scaled, rotated, moved to `o`.
func _poly(tpl: PackedVector2Array, o: Vector2, rot: float, sc: Vector2, col: Color, lw: float = OUTLINE) -> void:
	var n := tpl.size()
	var f := _fill[n]
	var l := _line[n]
	var c := cos(rot)
	var s := sin(rot)
	for i in n:
		var p := tpl[i] * sc
		var q := Vector2(p.x * c - p.y * s, p.x * s + p.y * c) + o
		f[i] = q
		l[i] = q
	l[n] = l[0]
	draw_colored_polygon(f, col)
	draw_polyline(l, BLACK, lw)

func _poly_sq(tpl: PackedVector2Array, o: Vector2, rot: float, size_m: float, col: Color, lw: float = OUTLINE) -> void:
	_poly(tpl, o, rot, Vector2(size_m, size_m) * _ppm, col, lw)

func _rect_m(cx: float, cy: float, w: float, h: float, col: Color, rot: float = 0.0) -> void:
	_poly(RECT, Vector2(cx, cy), rot, Vector2(w, h) * _ppm, col)

func _hash(i: int) -> float:
	var v := sin(float(i) * 12.9898 + 78.233) * 43758.5453
	return v - floorf(v)

# ---------------------------------------------------------------------------------------------
# Main draw
# ---------------------------------------------------------------------------------------------

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	if flight == null:
		return
	_ppm = ppm
	_size = get_viewport_rect().size
	_ground_sy = _size.y + cam_bottom * _ppm
	_draw_sky()
	_draw_clouds()
	_draw_hills()
	_draw_piles()
	_draw_ground()
	_draw_props()
	_draw_signs()
	_draw_ramp()
	_draw_things()
	_draw_glider()
	_draw_particles()

func _draw_sky() -> void:
	var h := _size.y
	draw_rect(Rect2(0, 0, _size.x, h), SKY_MID)
	# three flat bands stepping from deep to pale blue toward the horizon (low-poly look)
	var top_h := clampf(_ground_sy * 0.45, 0.0, h)
	draw_rect(Rect2(0, 0, _size.x, top_h), SKY_TOP)
	var low_y := clampf(_ground_sy - 9.0 * _ppm, 0.0, h)
	draw_rect(Rect2(0, low_y, _size.x, h - low_y), SKY_LOW)

func _draw_clouds() -> void:
	var par := 0.10
	var w := 17.0
	var base := cam_x * par
	var first := int(floorf(base / w)) - 1
	for i in range(first, first + int(_size.x / (w * _ppm)) + 4):
		var h := _hash(i + 900)
		var wx := i * w + h * 8.0
		var wy := 22.0 + _hash(i + 77) * 26.0
		var o := Vector2((wx - base) * _ppm, _ground_sy - wy * _ppm * 0.55 - 120.0)
		_poly(CLOUD, o, 0.0, Vector2(1.0 + h * 0.8, 1.0 + h * 0.5) * _ppm * 1.4, Color(1, 1, 1), 2.0)

func _draw_hills() -> void:
	var par := 0.22
	var w := 16.0
	var base := cam_x * par
	var first := int(floorf(base / w)) - 1
	for i in range(first, first + int(_size.x / (w * _ppm)) + 4):
		var h := _hash(i + 300)
		var cx := (i * w - base) * _ppm
		var ph := (5.0 + h * 8.0) * _ppm * 0.9
		var hw := (w * 0.75) * _ppm
		_poly(TRI, Vector2(cx, _ground_sy - ph * 0.5), 0.0, Vector2(hw * 2.0, ph), HILL_FAR if h < 0.5 else HILL_NEAR, 2.0)

func _draw_piles() -> void:
	var par := 0.5
	var w := 12.0
	var base := cam_x * par
	var first := int(floorf(base / w)) - 1
	for i in range(first, first + int(_size.x / (w * _ppm)) + 4):
		var h := _hash(i + 500)
		var cx := (i * w + h * 4.0 - base) * _ppm
		var ph := (2.0 + h * 3.5) * _ppm
		var hw := (3.0 + h * 2.0) * _ppm
		_poly(TRI, Vector2(cx, _ground_sy - ph * 0.5), 0.0, Vector2(hw * 2.0, ph), PILE if h < 0.5 else PILE_DARK, 2.0)
		# a car roof / crate poking out of the pile
		_poly_sq(RECT, Vector2(cx + hw * 0.2, _ground_sy - ph * 0.8), 0.2 * (h - 0.5), 1.1, Color(0.62, 0.32, 0.26) if h > 0.3 else Color(0.35, 0.45, 0.52))

func _draw_ground() -> void:
	var gy := _ground_sy
	if gy > _size.y + 4.0:
		return
	draw_rect(Rect2(-4, gy, _size.x + 8, _size.y - gy + 8), DIRT)
	draw_rect(Rect2(-4, gy, _size.x + 8, 1.2 * _ppm), DIRT_TOP)
	draw_line(Vector2(-4, gy), Vector2(_size.x + 4, gy), BLACK, 4.0)
	# a few dark stones in the dirt so the ground is not a blank band
	var first := int(floorf(cam_x / 5.0)) - 1
	for i in range(first, first + int(_size.x / (5.0 * _ppm)) + 3):
		var h := _hash(i + 40)
		var o := Vector2((i * 5.0 + h * 3.0 - cam_x) * _ppm, gy + (1.8 + h * 3.0) * _ppm)
		_poly_sq(DIAMOND, o, h * 3.0, 0.9 + h, Color(0.33, 0.25, 0.19))

func _draw_props() -> void:
	var w := 7.0
	var first := int(floorf((cam_x - 4.0) / w))
	for i in range(first, first + int(_size.x / (w * _ppm)) + 3):
		var wx := i * w + 2.0
		if wx > -42.0 and wx < 8.0:
			continue   # the ramp stands here
		var h := _hash(i + 11)
		if h > 0.62:
			continue
		var o := Vector2(_sx(wx), _ground_sy)
		var kind := int(h * 100.0) % 4
		match kind:
			0:   # crate
				_rect_m(o.x, o.y - 0.7 * _ppm, 1.4 * _ppm, 1.4 * _ppm, Color(0.66, 0.5, 0.28))
				draw_line(o + Vector2(-0.7, -1.4) * _ppm, o + Vector2(0.7, 0.0) * _ppm, BLACK, 2.0)
			1:   # barrel
				_rect_m(o.x, o.y - 0.8 * _ppm, 1.1 * _ppm, 1.6 * _ppm, Color(0.7, 0.28, 0.22))
				draw_line(o + Vector2(-0.55, -1.2) * _ppm, o + Vector2(0.55, -1.2) * _ppm, BLACK, 2.0)
			2:   # tyre stack
				_poly(OCT, o + Vector2(0, -0.45 * _ppm), 0.0, Vector2(1.1, 0.45) * _ppm, Color(0.2, 0.2, 0.22))
				_poly(OCT, o + Vector2(0, -1.3 * _ppm), 0.0, Vector2(0.95, 0.42) * _ppm, Color(0.24, 0.24, 0.26))
			3:   # car hulk
				_rect_m(o.x, o.y - 0.7 * _ppm, 4.0 * _ppm, 1.0 * _ppm, Color(0.45, 0.5, 0.58))
				_rect_m(o.x - 0.2 * _ppm, o.y - 1.55 * _ppm, 2.0 * _ppm, 0.8 * _ppm, Color(0.55, 0.6, 0.66))
				_poly(OCT, o + Vector2(-1.3, -0.25) * _ppm, 0.0, Vector2(0.42, 0.42) * _ppm, Color(0.15, 0.15, 0.15))
				_poly(OCT, o + Vector2(1.3, -0.25) * _ppm, 0.0, Vector2(0.42, 0.42) * _ppm, Color(0.15, 0.15, 0.15))

func _draw_signs() -> void:
	# a sign every 100 m, and the best-distance flag
	var first := maxi(int(floorf(cam_x / 100.0)), 0)
	for k in range(first, first + 2):
		if k < 1 or k > _sign_text.size():
			continue
		var wx := k * 100.0
		var sx := _sx(wx)
		if sx < -200.0 or sx > _size.x + 200.0:
			continue
		draw_line(Vector2(sx, _ground_sy), Vector2(sx, _ground_sy - 4.0 * _ppm), BLACK, 8.0)
		draw_line(Vector2(sx, _ground_sy), Vector2(sx, _ground_sy - 4.0 * _ppm), Color(0.8, 0.8, 0.75), 4.0)
		_rect_m(sx, _ground_sy - 4.2 * _ppm, 3.6 * _ppm, 1.6 * _ppm, Color(0.95, 0.85, 0.3))
		draw_string(_font, Vector2(sx - 1.6 * _ppm, _ground_sy - 3.85 * _ppm), _sign_text[k - 1], HORIZONTAL_ALIGNMENT_CENTER, 3.2 * _ppm, 34, BLACK)
	if best_x > 0.0:
		var bx := _sx(best_x)
		if bx > -300.0 and bx < _size.x + 300.0:
			var top := _ground_sy - 9.0 * _ppm
			draw_line(Vector2(bx, _ground_sy), Vector2(bx, top), BLACK, 9.0)
			draw_line(Vector2(bx, _ground_sy), Vector2(bx, top), Color(0.9, 0.9, 0.9), 5.0)
			var flag_col := Color(0.2, 0.8, 0.4) if (flight.passed_best) else Color(0.95, 0.25, 0.25)
			var sway := sin(_time * 5.0) * 0.25
			_poly(TRI, Vector2(bx + 1.5 * _ppm, top + 0.9 * _ppm), -PI * 0.5 + sway * 0.2, Vector2(1.7, 3.0) * _ppm * 0.6, flag_col)
			draw_string_outline(_font, Vector2(bx - 3.0 * _ppm, top - 0.6 * _ppm), best_text, HORIZONTAL_ALIGNMENT_CENTER, 6.0 * _ppm, 38, 8, BLACK)
			draw_string(_font, Vector2(bx - 3.0 * _ppm, top - 0.6 * _ppm), best_text, HORIZONTAL_ALIGNMENT_CENTER, 6.0 * _ppm, 38, Color(1, 0.95, 0.5))

func _draw_ramp() -> void:
	if flight.ramp_pts.size() != Tuning.RAMP_N + 1:
		return
	var n := Tuning.RAMP_N + 1
	var thick := 0.7
	var pts := flight.ramp_pts
	if _sx(pts[0].x) > _size.x + 300.0 or _sx(0.0) < -300.0:
		return
	for i in n:
		var p := pts[i]
		var a := pts[mini(i + 1, n - 1)] - pts[maxi(i - 1, 0)]
		var nrm := Vector2(-a.y, a.x).normalized()   # points up-left of the path
		var top := Vector2(_sx(p.x), _sy(p.y))
		var bot := Vector2(_sx(p.x - nrm.x * thick), _sy(p.y - nrm.y * thick))
		_ramp_fill[i] = top
		_ramp_fill[2 * n - 1 - i] = bot
		_ramp_top_line[i] = top
		_ramp_bot_line[i] = bot
	# scaffolding first (behind the deck): posts from the deck to the ground
	var legs := 5
	for k in legs:
		var idx := int(float(k) / float(legs) * (n - 1)) + 1
		idx = mini(idx, n - 1)
		var p := pts[idx]
		var sx := _sx(p.x)
		var top_y := _sy(p.y - thick)
		draw_line(Vector2(sx, _ground_sy), Vector2(sx, top_y), BLACK, 11.0)
		draw_line(Vector2(sx, _ground_sy), Vector2(sx, top_y), Color(0.55, 0.42, 0.3), 6.0)
		if k > 0:
			var q := pts[maxi(int(float(k - 1) / float(legs) * (n - 1)) + 1, 0)]
			draw_line(Vector2(_sx(q.x), _ground_sy), Vector2(sx, top_y), BLACK, 5.0)
	draw_colored_polygon(_ramp_fill, Color(0.62, 0.5, 0.36))
	draw_polyline(_ramp_top_line, BLACK, 4.0)
	draw_polyline(_ramp_bot_line, BLACK, 4.0)
	draw_line(_ramp_top_line[0], _ramp_bot_line[0], BLACK, 4.0)
	draw_line(_ramp_top_line[n - 1], _ramp_bot_line[n - 1], BLACK, 4.0)
	# lip marker stripe
	draw_line(_ramp_top_line[n - 3], _ramp_bot_line[n - 3], Color(1, 0.8, 0.2), 6.0)

func _draw_things() -> void:
	var f := flight
	for i in Flight.MAX_THINGS:
		if f.t_active[i] == 0:
			continue
		var wx := f.t_x[i]
		var sx := _sx(wx)
		if sx < -150.0 or sx > _size.x + 150.0:
			continue
		var sy := _sy(f.t_y[i])
		match f.t_kind[i]:
			Flight.K_NUT:
				_poly_sq(HEX, Vector2(sx, sy), _time * 1.5 + wx, 1.0, Color(0.78, 0.8, 0.84))
				_poly_sq(HEX, Vector2(sx, sy), _time * 1.5 + wx, 0.4, Color(0.3, 0.33, 0.4), 2.0)
			Flight.K_GEAR:
				_poly_sq(GEAR, Vector2(sx, sy), _time * 1.2, 0.95, Color(1.0, 0.78, 0.18))
				_poly_sq(HEX, Vector2(sx, sy), _time * 1.2, 0.5, Color(0.55, 0.4, 0.1), 2.0)
			Flight.K_PAD:
				var squash := f.t_phase[i] / 0.35
				var sh := 1.0 - 0.45 * squash
				var base := Vector2(sx, _ground_sy)
				_poly(OCT, base + Vector2(0, -0.35 * _ppm * sh), 0.0, Vector2(2.3, 0.4 * sh) * _ppm, Color(0.2, 0.2, 0.22))
				_poly(OCT, base + Vector2(0, -0.8 * _ppm * sh - 0.3 * _ppm * squash), 0.0, Vector2(2.0, 0.4) * _ppm, Color(0.95, 0.5, 0.15))
			Flight.K_FAN:
				_draw_fan(sx)
			Flight.K_BIRD:
				_draw_bird(sx, sy, wx)

func _draw_fan(sx: float) -> void:
	var gy := _ground_sy
	var hub := Vector2(sx, gy - 1.7 * _ppm)
	# draft streaks rising inside the column
	for k in 5:
		var ph := fmod(_time * 0.9 + k * 0.2, 1.0)
		var wy := 1.5 + ph * Tuning.fan_height * 0.8
		var dx := (float(k) - 2.0) * 0.8
		var a := 0.5 * (1.0 - ph)
		draw_line(Vector2(sx + dx * _ppm, _sy(wy)), Vector2(sx + dx * _ppm, _sy(wy + 1.6)), Color(1, 1, 1, a), 3.0)
	_poly(TRI, Vector2(sx, gy - 0.9 * _ppm), 0.0, Vector2(2.6, 1.8) * _ppm, Color(0.45, 0.5, 0.55))
	_poly(OCT, hub, 0.0, Vector2(1.5, 1.5) * _ppm, Color(0.8, 0.82, 0.85), 2.0)
	var ang := _time * 14.0
	for b in 3:
		_poly(DIAMOND, hub + Vector2(cos(ang + b * TAU / 3.0), sin(ang + b * TAU / 3.0)) * 0.7 * _ppm, ang + b * TAU / 3.0, Vector2(1.4, 0.45) * _ppm, Color(0.3, 0.7, 0.95), 2.0)
	_poly_sq(HEX, hub, 0.0, 0.4, Color(0.2, 0.2, 0.25), 2.0)

func _draw_bird(sx: float, sy: float, wx: float) -> void:
	var flap := sin(_time * 14.0 + wx)
	var o := Vector2(sx, sy)
	_poly(BIRD_WING, o + Vector2(0, -0.1 * _ppm), 0.0, Vector2(1.0, -flap * 0.7 - 0.2) * _ppm * 1.0, Color(0.28, 0.24, 0.4))
	_poly(BIRD_BODY, o, 0.0, Vector2(_ppm, _ppm), Color(0.4, 0.34, 0.55))
	_poly(BIRD_BEAK, o, 0.0, Vector2(_ppm, _ppm), Color(1.0, 0.7, 0.15), 2.0)
	draw_circle(o + Vector2(0.6, -0.15) * _ppm, 3.5, Color(1, 1, 1))

func _draw_particles() -> void:
	for i in PARTICLES:
		var life := _plife[i]
		if life <= 0.0:
			continue
		var t := life / _pmax[i]
		var sz := _psize[i] * (0.4 + 0.6 * t) * _ppm
		var col := _pcol[i]
		col.a = clampf(t * 2.0, 0.0, 1.0)
		var o := Vector2(_sx(_px[i]), _sy(_py[i]))
		match _pkind[i]:
			P_FLAME:
				draw_circle(o, sz * 0.5, col)
			P_FEATHER:
				_poly(DIAMOND, o, _time * 8.0 + i, Vector2(sz * 1.6, sz * 0.7), col, 2.0)
			_:
				draw_rect(Rect2(o - Vector2(sz, sz) * 0.5, Vector2(sz, sz)), col)
				draw_rect(Rect2(o - Vector2(sz, sz) * 0.5, Vector2(sz, sz)), Color(0, 0, 0, col.a), false, 2.0)

# ---------------------------------------------------------------------------------------------
# The glider: every upgrade shows
# ---------------------------------------------------------------------------------------------

func _draw_glider() -> void:
	var f := flight
	var o := Vector2(_sx(f.x), _sy(f.y))
	var rot := -f.theta
	if f.stall_amount > 0.0:
		rot += sin(_time * 40.0) * 0.06 * f.stall_amount
	var u := _ppm                      # meters -> pixels
	var c := cos(rot)
	var s := sin(rot)
	var bl := f.lv_body
	var wl := f.lv_wings
	# helper values
	var tier := 0 if bl < 3 else (1 if bl < 6 else (2 if bl < 9 else 3))
	var body_cols := [Color(0.62, 0.34, 0.2), Color(0.85, 0.5, 0.2), Color(0.18, 0.62, 0.7), Color(0.95, 0.82, 0.25)]
	var body_col: Color = body_cols[tier]
	var wing_cols := [Color(0.66, 0.67, 0.66), Color(0.78, 0.3, 0.24), Color(0.3, 0.55, 0.85), Color(0.95, 0.95, 0.9)]
	var wtier := 0 if wl < 3 else (1 if wl < 6 else (2 if wl < 9 else 3))
	var wing_col: Color = wing_cols[wtier]
	# --- booster pods (behind everything) ---
	var pods := mini(3, (f.lv_booster + 2) / 3) if f.lv_booster > 0 else 0
	for k in pods:
		var py := 0.25 + k * 0.38
		var lp := Vector2(-2.5, py)
		var pp := o + Vector2(lp.x * c - lp.y * s, lp.x * s + lp.y * c) * u
		_poly(RECT, pp, rot, Vector2(1.3, 0.34) * u, Color(0.45, 0.47, 0.5))
		_poly(TRI, pp + Vector2(-0.75 * c, -0.75 * s) * u, rot + PI * 0.5, Vector2(0.34, 0.3) * u, Color(0.25, 0.25, 0.28), 2.0)
		if f.boost_left > 0.0:
			var fl := 1.1 + 0.6 * sin(_time * 50.0 + k)
			_poly(FLAME, pp + Vector2(-0.9 * c, -0.9 * s) * u, rot + PI, Vector2(fl, 0.9) * u, Color(1.0, 0.65, 0.1), 2.0)
	# --- tail ---
	_poly(FIN, o, rot, Vector2(u, u) * (1.0 + 0.05 * tier), body_col.darkened(0.15))
	_poly(STAB, o, rot, Vector2(u, u), body_col.darkened(0.1))
	if tier >= 1:
		_poly(BOOM, o, rot, Vector2(u, u), body_col.darkened(0.2))
	# --- rear wing (biplane) ---
	if wl >= 3:
		_wing(o, rot, Vector2(-0.6, 0.15), 1.7 + 0.14 * wl, wing_col.darkened(0.12), 0.0)
	# --- fuselage ---
	var fuse := TUB if tier == 0 else (FUSE_MID if tier == 1 else FUSE_SLEEK)
	_poly(fuse, o, rot, Vector2(u, u), body_col)
	if tier >= 2:
		_poly(RECT, o + Vector2(0.2 * c - 0.1 * s, 0.2 * s + 0.1 * c) * u, rot, Vector2(4.2, 0.14) * u, Color(0.95, 0.95, 0.95), 1.0)
	# --- pilot ---
	var head := o + Vector2(0.2 * c + 0.75 * s, 0.2 * s - 0.75 * c) * u
	_poly(OCT, head, rot, Vector2(0.34, 0.34) * u, Color(0.93, 0.76, 0.6), 2.5)
	_poly(RECT, head + Vector2(0.18 * c, 0.18 * s) * u, rot, Vector2(0.28, 0.16) * u, Color(0.15, 0.15, 0.2), 1.5)
	if tier >= 3:
		_poly(DIAMOND, o + Vector2(0.4 * c + 0.55 * s, 0.4 * s - 0.55 * c) * u, rot, Vector2(1.7, 1.25) * u, Color(0.6, 0.85, 0.95, 0.75), 2.5)
	# --- front wing: bigger and better with every Wings level ---
	_wing(o, rot, Vector2(0.4, -0.45), 1.7 + 0.14 * wl, wing_col, 1.0)
	# --- wheels ---
	for wxp in [-1.1, 1.0]:
		var wp := o + Vector2(wxp * c - 0.62 * s, wxp * s + 0.62 * c) * u
		_poly(OCT, wp, 0.0, Vector2(0.27, 0.27) * u, Color(0.2, 0.2, 0.22), 2.5)
	# --- magnet ---
	if f.lv_magnet > 0:
		var ms := 0.55 + 0.07 * f.lv_magnet
		var mp := o + Vector2(1.2 * c - 0.85 * s, 1.2 * s + 0.85 * c) * u
		_poly(HORSESHOE, mp, rot + PI, Vector2(ms, ms) * u, Color(0.85, 0.15, 0.15), 2.5)
	if show_aura and f.lv_magnet > 0:
		draw_arc(o, f.magnet_r * u, 0.0, TAU, 28, Color(0.9, 0.3, 0.3, 0.22), 3.0)

func _rot_pt(p: Vector2, c: float, s: float, u: float, o: Vector2) -> Vector2:
	return Vector2(p.x * c - p.y * s, p.x * s + p.y * c) * u + o

## A wing seen from the side-front: a slab above the fuselage with a slanted far edge.
## `chord` is its length in meters; the far edge slants up-back, longer with more lift.
func _wing(o: Vector2, rot: float, root: Vector2, chord: float, col: Color, front: float) -> void:
	var u := _ppm
	var c := cos(rot)
	var s := sin(rot)
	var depth := 0.55 + 0.05 * flight.lv_wings
	var p0 := root + Vector2(chord * 0.5, 0.0)
	var p1 := root - Vector2(chord * 0.5, 0.0)
	var p2 := p1 + Vector2(-depth * 1.2, -depth * 1.1 - 0.15)
	var p3 := p0 + Vector2(-depth * 1.2, -depth * 1.1 - 0.15)
	var f := _fill[4]
	var l := _line[4]
	f[0] = _rot_pt(p0, c, s, u, o)
	f[1] = _rot_pt(p1, c, s, u, o)
	f[2] = _rot_pt(p2, c, s, u, o)
	f[3] = _rot_pt(p3, c, s, u, o)
	for i in 4:
		l[i] = f[i]
	l[4] = l[0]
	draw_colored_polygon(f, col)
	draw_polyline(l, BLACK, OUTLINE)
	# ribs: more of them as the wings improve
	var ribs := 1 + flight.lv_wings / 3
	for r in ribs:
		var t := (r + 1.0) / (ribs + 1.0)
		draw_line(f[0].lerp(f[1], t), f[3].lerp(f[2], t), Color(0, 0, 0, 0.55), 2.0)
	# struts down to the fuselage
	if front > 0.5 and flight.lv_wings >= 3:
		var a := Vector2((root.x + 0.4) * c - (root.y) * s, (root.x + 0.4) * s + (root.y) * c) * u + o
		var b := Vector2((root.x + 0.4) * c - (root.y + 0.9) * s, (root.x + 0.4) * s + (root.y + 0.9) * c) * u + o
		draw_line(a, b, BLACK, 3.0)
	# winglet at the tip
	if flight.lv_wings >= 6:
		var tip := f[3]
		var tip2 := f[2]
		draw_line(tip, tip + Vector2(0, -0.7 * u).rotated(rot), BLACK, 5.0)
		draw_line(tip2, tip2 + Vector2(0, -0.7 * u).rotated(rot), BLACK, 5.0)
