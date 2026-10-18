class_name WorldView
extends Node2D
## Draws the whole side-view world in one _draw(): sky, parallax hills and junk piles, ground and props,
## the ramp, the things, the glider (which shows every upgrade) and the particles. Low-poly flat
## shapes with black outlines. Nothing is allocated per frame: the polygon scratch buffers are made
## once, particles live in a fixed pool, text comes from cached strings.

const OUTLINE := 3.0
const GLIDER_SCALE := 1.3
const PARTICLES := 128
const MAX_SIDES := 16

# Particle kinds
const P_SPARK := 0   # scrap pickup glint
const P_RUBBER := 1  # bounce pad puff
const P_FEATHER := 2
const P_FLAME := 3
const P_DUST := 4
const P_SCRAP := 5   # chunks flying off a hard landing
const P_BUBBLE := 6  # trail bubbles

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
static var ARROW_UP := PackedVector2Array([Vector2(0, -0.5), Vector2(0.5, 0.0), Vector2(0.2, 0.0), Vector2(0.2, 0.5), Vector2(-0.2, 0.5), Vector2(-0.2, 0.0), Vector2(-0.5, 0.0)])
static var STAR := PackedVector2Array([Vector2(0, -0.5), Vector2(0.09, -0.09), Vector2(0.5, 0), Vector2(0.09, 0.09), Vector2(0, 0.5), Vector2(-0.09, 0.09), Vector2(-0.5, 0), Vector2(-0.09, -0.09)])
static var ANVIL := PackedVector2Array([Vector2(-2.0, -0.5), Vector2(1.6, -0.62), Vector2(2.3, -0.1), Vector2(2.0, 0.72), Vector2(-1.9, 0.72), Vector2(-2.2, 0.0)])
static var CROWN := PackedVector2Array([Vector2(-0.5, 0.3), Vector2(-0.5, -0.3), Vector2(-0.25, 0.0), Vector2(0.0, -0.4), Vector2(0.25, 0.0), Vector2(0.5, -0.3), Vector2(0.5, 0.3)])
static var FLAME := PackedVector2Array([Vector2(0, -0.28), Vector2(-1.0, 0.0), Vector2(0, 0.28)])

# set by Main every frame
var flight: Flight
var cam_x := 0.0
var cam_bottom := 0.0
var ppm := 28.0          # pixels per meter (the camera zoom; the shop zooms out for tall ramps)
var best_text := ""
var best_x := 0.0
var target_x := 0.0     # the daily target flag (0 = none)
var show_aura := false
var boost_fx := 0.0     # 0..1 while a boost burns: speed lines
var _chord_mult := 1.0  # wing length factor of the frame being drawn
var paint_color := Color(0, 0, 0, 0)   # equipped paint (alpha 0 = the frame's own colours)
var hat_id := "none"
var showcase := false   # pre-warm: draw one of everything

var _font: Font
var _fill: Array[PackedVector2Array] = []
var _line: Array[PackedVector2Array] = []
var _ramp_fill := PackedVector2Array()
var _ramp_top_line := PackedVector2Array()
var _ramp_bot_line := PackedVector2Array()
var _zig := PackedVector2Array()
var _pal: Array[Color] = []     # palette in effect at the middle of the screen (sky): blended across zone borders
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
	_zig.resize(9)
	for i in 10:
		_pal.append(Color.WHITE)
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
			P_BUBBLE:
				_pvy[i] += 2.5 * dt
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

## A rectangle centred at pixel (cx, cy), w x h pixels.
func _rect_m(cx: float, cy: float, w: float, h: float, col: Color, rot: float = 0.0, lw: float = OUTLINE) -> void:
	_poly(RECT, Vector2(cx, cy), rot, Vector2(w, h), col, lw)

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
	_update_palette()
	_draw_sky()
	_draw_clouds()
	_draw_hills()
	_draw_piles()
	_draw_ground()
	_draw_props()
	_draw_signs()
	_draw_target_flag()
	_draw_ramp()
	_draw_things()
	_draw_glider()
	_draw_particles()
	_draw_speed_lines()

## Zone index of the world point drawn at screen x.
func _zone_at_screen(sx: float) -> int:
	return Tuning.zone_index(cam_x + sx / _ppm)

func _zp(z: int, k: int) -> Color:
	return Zones.list[z]["pal"][k]

## The sky palette follows the middle of the screen and fades from the previous zone's over 80 m.
func _update_palette() -> void:
	var cx := cam_x + _size.x * 0.5 / _ppm
	var z := Tuning.zone_index(cx)
	var t := 1.0
	var zp := maxi(z - 1, 0)
	if z > 0:
		t = clampf((cx - Tuning.zone_start(z)) / 80.0, 0.0, 1.0)
	for i in 10:
		_pal[i] = _zp(zp, i).lerp(_zp(z, i), t)
	if Zones.list[z]["id"] == "disco":
		_pal[1] = Color.from_hsv(fmod(_time * 0.15, 1.0), 0.6, 0.6)
		_pal[2] = Color.from_hsv(fmod(_time * 0.15 + 0.3, 1.0), 0.5, 0.9)

func _draw_sky() -> void:
	var h := _size.y
	draw_rect(Rect2(0, 0, _size.x, h), _pal[1])
	# three flat bands stepping from deep to pale toward the horizon (low-poly look)
	var top_h := clampf(_ground_sy * 0.45, 0.0, h)
	draw_rect(Rect2(0, 0, _size.x, top_h), _pal[0])
	var low_y := clampf(_ground_sy - 9.0 * _ppm, 0.0, h)
	draw_rect(Rect2(0, low_y, _size.x, h - low_y), _pal[2])
	if _pal[0].v < 0.35:   # a dark sky (the moon): stars
		for k in 40:
			var sx := _hash(k + 5) * _size.x
			var sy := _hash(k + 55) * _ground_sy * 0.8
			var tw := 0.5 + 0.5 * sin(_time * 2.0 + k)
			draw_rect(Rect2(sx, sy, 4, 4), Color(1, 1, 1, 0.4 + 0.5 * tw))

func _draw_clouds() -> void:
	var par := 0.10
	var w := 17.0
	var base := cam_x * par
	var first := int(floorf(base / w)) - 1
	var cc := Color(1, 1, 1).lerp(_pal[2], 0.25)
	for i in range(first, first + int(_size.x / (w * _ppm)) + 4):
		var h := _hash(i + 900)
		var wx := i * w + h * 8.0
		var wy := 22.0 + _hash(i + 77) * 26.0
		var o := Vector2((wx - base) * _ppm, _ground_sy - wy * _ppm * 0.55 - 120.0)
		_poly(CLOUD, o, 0.0, Vector2(1.0 + h * 0.8, 1.0 + h * 0.5) * _ppm * 1.4, cc, 2.0)

# ---- small pixel-space shape helpers (bottom-centre anchored) ----
func _box(bx: float, by: float, w: float, h: float, col: Color, lw: float = 2.0) -> void:
	_poly(RECT, Vector2(bx, by - h * 0.5), 0.0, Vector2(w, h), col, lw)

func _tri_up(bx: float, by: float, w: float, h: float, col: Color, lw: float = 2.0) -> void:
	_poly(TRI, Vector2(bx, by - h * 0.5), 0.0, Vector2(w, h), col, lw)

func _ball(cx: float, cy: float, r: float, col: Color, lw: float = 2.0) -> void:
	_poly(OCT, Vector2(cx, cy), 0.0, Vector2(r, r), col, lw)

func _draw_hills() -> void:
	var par := 0.22
	var w := 16.0
	var base := cam_x * par
	var first := int(floorf(base / w)) - 1
	for i in range(first, first + int(_size.x / (w * _ppm)) + 4):
		var h := _hash(i + 300)
		var cx := (i * w - base) * _ppm
		var z := _zone_at_screen(cx)
		var zd: Dictionary = Zones.list[z]
		var c3 := _zp(z, 3)
		var c4 := _zp(z, 4)
		var gy := _ground_sy
		match int(zd["far"]):
			0:   # mountains
				var ph := (5.0 + h * 8.0) * _ppm * 0.9
				_tri_up(cx, gy, w * 1.5 * _ppm, ph, c3 if h < 0.5 else c4)
			1:   # skyline
				for k in 3:
					var bw := (2.4 + _hash(i * 3 + k) * 1.6) * _ppm
					var bh := (6.0 + _hash(i * 7 + k) * 12.0) * _ppm
					var bx := cx + (k - 1) * 4.4 * _ppm
					_box(bx, gy, bw, bh, c3 if k % 2 == 0 else c4)
					for wy in 4:
						draw_rect(Rect2(bx - bw * 0.3, gy - bh + (0.8 + wy * 1.6) * _ppm, bw * 0.25, 0.7 * _ppm), Color(1, 1, 0.7, 0.5))
						draw_rect(Rect2(bx + bw * 0.05, gy - bh + (0.8 + wy * 1.6) * _ppm, bw * 0.25, 0.7 * _ppm), Color(1, 1, 0.7, 0.5))
			2:   # cloud bumps
				_poly(CLOUD, Vector2(cx, gy - 2.0 * _ppm), 0.0, Vector2(2.4 + h, 1.8 + h) * _ppm * 1.4, c3, 2.0)

func _draw_piles() -> void:
	var par := 0.5
	var w := 12.0
	var base := cam_x * par
	var first := int(floorf(base / w)) - 1
	for i in range(first, first + int(_size.x / (w * _ppm)) + 4):
		var h := _hash(i + 500)
		var cx := (i * w + h * 4.0 - base) * _ppm
		var z := _zone_at_screen(cx)
		var c5 := _zp(z, 5)
		var c6 := _zp(z, 6)
		var gy := _ground_sy
		var u := _ppm
		match int(Zones.list[z]["mid"]):
			0:   # junk piles with a roof or crate poking out
				var ph := (2.0 + h * 3.5) * u
				var hw := (3.0 + h * 2.0) * u
				_tri_up(cx, gy, hw * 2.0, ph, c5 if h < 0.5 else c6)
				_poly_sq(RECT, Vector2(cx + hw * 0.2, gy - ph * 0.8), 0.2 * (h - 0.5), 1.1, Color(0.62, 0.32, 0.26) if h > 0.3 else Color(0.35, 0.45, 0.52))
			1:   # barn and silo
				_box(cx, gy, 5.0 * u, 3.4 * u, c5)
				_tri_up(cx, gy - 3.4 * u, 5.6 * u, 2.0 * u, c6)
				_box(cx + 4.0 * u, gy, 1.6 * u, 5.5 * u, Color(0.8, 0.8, 0.82))
				_ball(cx + 4.0 * u, gy - 5.6 * u, 0.8 * u, Color(0.6, 0.6, 0.65))
			2:   # houses
				_box(cx, gy, 3.6 * u, 2.6 * u, Color(0.92, 0.85, 0.7))
				_tri_up(cx, gy - 2.6 * u, 4.2 * u, 1.8 * u, c5)
				draw_rect(Rect2(cx - 0.4 * u, gy - 1.5 * u, 0.8 * u, 0.9 * u), Color(0.5, 0.7, 0.9))
			3:   # trees
				_box(cx, gy, 0.5 * u, 2.2 * u, Color(0.45, 0.3, 0.18))
				_ball(cx, gy - 3.2 * u, 1.9 * u, c5)
				_ball(cx + 1.1 * u, gy - 2.6 * u, 1.3 * u, c6)
			4:   # pines
				_box(cx, gy, 0.5 * u, 1.2 * u, Color(0.4, 0.28, 0.18))
				_tri_up(cx, gy - 0.8 * u, 3.0 * u, 2.6 * u, c5)
				_tri_up(cx, gy - 2.4 * u, 2.4 * u, 2.4 * u, c6)
				_tri_up(cx, gy - 4.0 * u, 1.8 * u, 2.0 * u, c5)
			5:   # skyscrapers
				var bh := (7.0 + h * 9.0) * u
				_box(cx, gy, 3.4 * u, bh, c5)
				_box(cx + 2.4 * u, gy, 2.4 * u, bh * 0.65, c6)
				for wy in 5:
					draw_rect(Rect2(cx - 1.2 * u, gy - bh + (0.8 + wy * 1.5) * u, 0.7 * u, 0.7 * u), Color(1, 0.95, 0.6, 0.65))
					draw_rect(Rect2(cx + 0.2 * u, gy - bh + (0.8 + wy * 1.5) * u, 0.7 * u, 0.7 * u), Color(1, 0.95, 0.6, 0.65))
			6:   # palms and a beach hut
				draw_line(Vector2(cx, gy), Vector2(cx + 0.6 * u, gy - 4.2 * u), BLACK, 9.0)
				draw_line(Vector2(cx, gy), Vector2(cx + 0.6 * u, gy - 4.2 * u), Color(0.6, 0.45, 0.28), 5.0)
				for lf in 4:
					_poly(TRI, Vector2(cx + 0.6 * u + (lf - 1.5) * 0.9 * u, gy - 4.5 * u), (lf - 1.5) * 0.7, Vector2(0.9, 2.4) * u, c5, 2.0)
			7:   # cloud towers
				_poly(CLOUD, Vector2(cx, gy - 1.6 * u), 0.0, Vector2(2.0 + h, 1.6) * u, c5, 2.0)
				_poly(CLOUD, Vector2(cx + 1.0 * u, gy - 3.6 * u), 0.0, Vector2(1.4, 1.2) * u, c6, 2.0)
			8:   # volcanoes / moon mountains
				_tri_up(cx, gy, 6.0 * u, (3.0 + h * 3.0) * u, c5)
				_tri_up(cx, gy - (3.0 + h * 3.0) * u + 0.1 * u, 1.6 * u, 0.9 * u, Color(1.0, 0.45, 0.1) if int(Zones.list[z]["props"]) == 9 else c6)

## The ground: one band per zone (dirt, water with waves, cloud puffs, cheese, disco floor).
func _draw_ground() -> void:
	var gy := _ground_sy
	if gy > _size.y + 4.0:
		return
	var left := cam_x
	var right := cam_x + _size.x / _ppm
	for z in Zones.COUNT:
		var z0 := Tuning.zone_start(z)
		var z1 := Tuning.zone_start(z + 1) if z + 1 < Zones.COUNT else 1.0e9
		if z1 < left or z0 > right:
			continue
		var xa := maxf((z0 - cam_x) * _ppm, -4.0)
		var xb := minf((z1 - cam_x) * _ppm, _size.x + 4.0)
		var w := xb - xa
		var zd: Dictionary = Zones.list[z]
		var dirt := _zp(z, 7)
		var top := _zp(z, 8)
		match int(zd["ground"]):
			1:   # water: you can skim it
				var water := _zp(z, 9)
				draw_rect(Rect2(xa, gy, w, _size.y - gy + 8), water.darkened(0.25))
				draw_rect(Rect2(xa, gy, w, 3.0 * _ppm), water)
				var x := xa
				while x < xb:
					var wy := gy + 0.9 * _ppm + sin(x * 0.02 + _time * 2.0) * 5.0
					draw_line(Vector2(x, wy), Vector2(minf(x + 70.0, xb), wy), Color(1, 1, 1, 0.45), 4.0)
					x += 140.0
				draw_line(Vector2(xa, gy), Vector2(xb, gy), BLACK, 4.0)
			2:   # clouds: soft, bouncy
				draw_rect(Rect2(xa, gy, w, _size.y - gy + 8), top.darkened(0.12))
				var x := xa - fmod(cam_x * _ppm, 3.0 * _ppm)
				while x < xb + 3.0 * _ppm:
					if x > xa - 3.0 * _ppm:
						_poly(OCT, Vector2(x, gy + 0.2 * _ppm), 0.0, Vector2(1.7, 1.3) * _ppm, top, 2.5)
					x += 3.0 * _ppm
			3:   # cheese with holes
				draw_rect(Rect2(xa, gy, w, _size.y - gy + 8), dirt)
				draw_rect(Rect2(xa, gy, w, 1.2 * _ppm), top)
				draw_line(Vector2(xa, gy), Vector2(xb, gy), BLACK, 4.0)
				var hole0 := int(floorf((cam_x + xa / _ppm) / 6.0)) - 1
				for hh in range(hole0, hole0 + int(w / (6.0 * _ppm)) + 3):
					var hx := (hh * 6.0 + _hash(hh + 9) * 3.0 - cam_x) * _ppm
					if hx > xa and hx < xb:
						_ball(hx, gy + (2.0 + _hash(hh + 4) * 3.0) * _ppm, (0.6 + _hash(hh) * 0.8) * _ppm, dirt.darkened(0.3), 2.0)
			4:   # disco floor: coloured tiles that pulse
				draw_rect(Rect2(xa, gy, w, _size.y - gy + 8), dirt)
				var t0 := int(floorf((cam_x + xa / _ppm) / 3.0)) - 1
				for tt in range(t0, t0 + int(w / (3.0 * _ppm)) + 3):
					var tx := (tt * 3.0 - cam_x) * _ppm
					var hue := fmod(tt * 0.13 + _time * 0.6, 1.0)
					draw_rect(Rect2(tx, gy, 3.0 * _ppm - 3.0, 1.4 * _ppm), Color.from_hsv(hue, 0.7, 0.9))
				draw_line(Vector2(xa, gy), Vector2(xb, gy), BLACK, 4.0)
			_:   # dirt
				draw_rect(Rect2(xa, gy, w, _size.y - gy + 8), dirt)
				draw_rect(Rect2(xa, gy, w, 1.2 * _ppm), top)
				draw_line(Vector2(xa, gy), Vector2(xb, gy), BLACK, 4.0)
				var st0 := int(floorf((cam_x + xa / _ppm) / 5.0)) - 1
				for k in range(st0, st0 + int(w / (5.0 * _ppm)) + 3):
					var sh := _hash(k + 40)
					var o := Vector2((k * 5.0 + sh * 3.0 - cam_x) * _ppm, gy + (1.8 + sh * 3.0) * _ppm)
					if o.x > xa and o.x < xb:
						_poly_sq(DIAMOND, o, sh * 3.0, 0.9 + sh, dirt.darkened(0.22))

## Things standing on the ground near the player: by zone, three or four kinds each.
func _draw_props() -> void:
	var w := 7.0
	var first := int(floorf((cam_x - 4.0) / w))
	var u := _ppm
	for i in range(first, first + int(_size.x / (w * _ppm)) + 3):
		var wx := i * w + 2.0
		if wx > -42.0 and wx < 8.0:
			continue   # the ramp stands here
		var h := _hash(i + 11)
		if h > 0.62:
			continue
		var o := Vector2(_sx(wx), _ground_sy)
		var z := _zone_at_screen(o.x)
		var kind := int(h * 100.0) % 4
		var water := int(Zones.list[z]["ground"]) == 1
		match int(Zones.list[z]["props"]):
			0:   # junk
				match kind:
					0:
						_rect_m(o.x, o.y - 0.7 * u, 1.4 * u, 1.4 * u, Color(0.66, 0.5, 0.28))
						draw_line(o + Vector2(-0.7, -1.4) * u, o + Vector2(0.7, 0.0) * u, BLACK, 2.0)
					1:
						_rect_m(o.x, o.y - 0.8 * u, 1.1 * u, 1.6 * u, Color(0.7, 0.28, 0.22))
						draw_line(o + Vector2(-0.55, -1.2) * u, o + Vector2(0.55, -1.2) * u, BLACK, 2.0)
					2:
						_poly(OCT, o + Vector2(0, -0.45 * u), 0.0, Vector2(1.1, 0.45) * u, Color(0.2, 0.2, 0.22))
						_poly(OCT, o + Vector2(0, -1.3 * u), 0.0, Vector2(0.95, 0.42) * u, Color(0.24, 0.24, 0.26))
					3:
						_rect_m(o.x, o.y - 0.7 * u, 4.0 * u, 1.0 * u, Color(0.45, 0.5, 0.58))
						_rect_m(o.x - 0.2 * u, o.y - 1.55 * u, 2.0 * u, 0.8 * u, Color(0.55, 0.6, 0.66))
						_poly(OCT, o + Vector2(-1.3, -0.25) * u, 0.0, Vector2(0.42, 0.42) * u, Color(0.15, 0.15, 0.15))
						_poly(OCT, o + Vector2(1.3, -0.25) * u, 0.0, Vector2(0.42, 0.42) * u, Color(0.15, 0.15, 0.15))
			1:   # farm
				match kind:
					0, 1:   # hay bales
						_box(o.x, o.y, 1.6 * u, 1.3 * u, Color(0.92, 0.8, 0.35))
						draw_line(o + Vector2(-0.8, -0.65) * u, o + Vector2(0.8, -0.65) * u, BLACK, 2.0)
					2:   # fence
						for k in 3:
							_box(o.x + (k - 1) * 0.9 * u, o.y, 0.22 * u, 1.3 * u, Color(0.8, 0.7, 0.55), 1.5)
						draw_line(o + Vector2(-1.2, -0.9) * u, o + Vector2(1.2, -0.9) * u, BLACK, 3.0)
					3:   # scarecrow
						_box(o.x, o.y, 0.2 * u, 2.2 * u, Color(0.5, 0.35, 0.2), 1.5)
						draw_line(o + Vector2(-0.9, -1.6) * u, o + Vector2(0.9, -1.6) * u, BLACK, 5.0)
						_ball(o.x, o.y - 2.4 * u, 0.4 * u, Color(0.9, 0.75, 0.4))
			2:   # reeds and stones by the river
				var by := o.y - (0.0 if not water else 0.0)
				for k in 4:
					var rx := o.x + (k - 1.5) * 0.35 * u
					draw_line(Vector2(rx, by), Vector2(rx + sin(_time * 2.0 + k + h * 9.0) * 4.0, by - (1.6 + k * 0.25) * u), BLACK, 6.0)
					draw_line(Vector2(rx, by), Vector2(rx + sin(_time * 2.0 + k + h * 9.0) * 4.0, by - (1.6 + k * 0.25) * u), Color(0.4, 0.62, 0.25), 3.0)
				if kind == 0:
					_poly(OCT, o + Vector2(1.6, -0.3) * u, 0.0, Vector2(0.9, 0.5) * u, Color(0.55, 0.55, 0.58))
			3:   # town
				match kind:
					0, 1:   # small house
						_box(o.x, o.y, 3.0 * u, 2.2 * u, Color(0.95, 0.88, 0.72))
						_tri_up(o.x, o.y - 2.2 * u, 3.5 * u, 1.4 * u, Color(0.75, 0.35, 0.3))
						draw_rect(Rect2(o.x - 0.3 * u, o.y - 1.5 * u, 0.7 * u, 1.5 * u), Color(0.5, 0.35, 0.25))
					2:   # lamp post
						_box(o.x, o.y, 0.2 * u, 3.4 * u, Color(0.25, 0.25, 0.3), 1.5)
						_ball(o.x, o.y - 3.6 * u, 0.4 * u, Color(1.0, 0.95, 0.6))
					3:   # mailbox
						_box(o.x, o.y, 0.3 * u, 1.0 * u, Color(0.4, 0.3, 0.2), 1.5)
						_box(o.x, o.y - 1.0 * u, 0.9 * u, 0.6 * u, Color(0.2, 0.4, 0.8))
			4:   # nature
				match kind:
					0, 1:
						_poly(OCT, o + Vector2(0, -0.6 * u), 0.0, Vector2(1.5, 1.1) * u, Color(0.6, 0.6, 0.62))
					2:
						_box(o.x, o.y, 0.4 * u, 1.0 * u, Color(0.4, 0.28, 0.18), 1.5)
						_tri_up(o.x, o.y - 0.6 * u, 2.0 * u, 2.6 * u, Color(0.2, 0.5, 0.3))
					3:
						_ball(o.x, o.y - 0.7 * u, 1.0 * u, Color(0.3, 0.6, 0.3))
			5:   # city
				match kind:
					0, 1:   # kiosk
						_box(o.x, o.y, 2.4 * u, 2.0 * u, Color(0.4, 0.5, 0.6))
						_box(o.x, o.y - 2.0 * u, 2.8 * u, 0.4 * u, Color(0.85, 0.3, 0.3))
					2:   # hydrant
						_box(o.x, o.y, 0.7 * u, 1.0 * u, Color(0.85, 0.2, 0.2))
					3:   # lamp
						_box(o.x, o.y, 0.2 * u, 3.6 * u, Color(0.3, 0.3, 0.35), 1.5)
						_box(o.x + 0.5 * u, o.y - 3.6 * u, 1.2 * u, 0.3 * u, Color(0.3, 0.3, 0.35), 1.5)
			6:   # beach
				match kind:
					0, 1:   # umbrella
						_box(o.x, o.y, 0.15 * u, 2.4 * u, Color(0.4, 0.3, 0.2), 1.5)
						_poly(TRI, o + Vector2(0, -2.6 * u), 0.0, Vector2(3.2, 1.2) * u, Color(0.95, 0.35, 0.4))
					2:   # towel
						_box(o.x, o.y, 2.2 * u, 0.25 * u, Color(0.3, 0.7, 0.9), 1.5)
					3:   # sandcastle
						_box(o.x, o.y, 1.6 * u, 1.0 * u, Color(0.95, 0.85, 0.55))
						_box(o.x - 0.5 * u, o.y - 1.0 * u, 0.5 * u, 0.5 * u, Color(0.95, 0.85, 0.55))
			7:   # cloud puffs
				_poly(CLOUD, o + Vector2(0, -0.9 * u), 0.0, Vector2(1.0 + h, 0.8) * u, Color(1, 1, 1), 2.0)
			8:   # moon
				match kind:
					0, 1:   # cheese wedge
						_poly(TRI, o + Vector2(0, -0.7 * u), 0.0, Vector2(2.4, 1.4) * u, Color(1.0, 0.85, 0.3))
						_ball(o.x + 0.3 * u, o.y - 0.6 * u, 0.25 * u, Color(0.8, 0.6, 0.15), 1.5)
					2:   # flag
						_box(o.x, o.y, 0.12 * u, 3.0 * u, Color(0.9, 0.9, 0.9), 1.5)
						_poly(TRI, o + Vector2(0.6 * u, -2.6 * u), -PI * 0.5, Vector2(0.9, 1.2) * u, Color(0.9, 0.2, 0.3), 1.5)
					3:
						_poly(OCT, o + Vector2(0, -0.35 * u), 0.0, Vector2(2.0, 0.5) * u, Color(0.85, 0.65, 0.2))
			9:   # dino
				match kind:
					0, 1:   # fern
						for lf in 3:
							_poly(TRI, o + Vector2((lf - 1) * 0.7 * u, -1.0 * u), (lf - 1) * 0.5, Vector2(0.7, 2.0) * u, Color(0.3, 0.6, 0.25), 2.0)
					2:   # egg
						_poly(OCT, o + Vector2(0, -0.8 * u), 0.0, Vector2(0.8, 1.0) * u, Color(0.95, 0.92, 0.8))
					3:   # bone
						draw_line(o + Vector2(-1.0, -0.4) * u, o + Vector2(1.0, -0.4) * u, BLACK, 9.0)
						draw_line(o + Vector2(-1.0, -0.4) * u, o + Vector2(1.0, -0.4) * u, Color(0.95, 0.95, 0.9), 5.0)
			10:  # disco
				match kind:
					0, 1:   # disco ball on a stand
						_box(o.x, o.y, 0.15 * u, 2.4 * u, Color(0.7, 0.7, 0.8), 1.5)
						_ball(o.x, o.y - 2.9 * u, 0.9 * u, Color.from_hsv(fmod(_time * 0.5 + h, 1.0), 0.3, 1.0))
					2:   # speaker
						_box(o.x, o.y, 1.6 * u, 2.2 * u, Color(0.15, 0.1, 0.2))
						_ball(o.x, o.y - 0.8 * u, 0.4 * u + sin(_time * 12.0) * 2.0, Color(0.8, 0.8, 0.9), 1.5)
						_ball(o.x, o.y - 1.7 * u, 0.25 * u, Color(0.8, 0.8, 0.9), 1.5)
					3:
						_poly(DIAMOND, o + Vector2(0, -1.0 * u), _time, Vector2(1.2, 1.2) * u, Color.from_hsv(fmod(_time * 0.3 + h, 1.0), 0.8, 1.0))

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

## The daily target: a teal flag on a pole.
func _draw_target_flag() -> void:
	if target_x <= 0.0:
		return
	var bx := _sx(target_x)
	if bx < -300.0 or bx > _size.x + 300.0:
		return
	var top := _ground_sy - 8.0 * _ppm
	draw_line(Vector2(bx, _ground_sy), Vector2(bx, top), BLACK, 9.0)
	draw_line(Vector2(bx, _ground_sy), Vector2(bx, top), Color(0.9, 0.9, 0.9), 5.0)
	var sway := sin(_time * 5.0 + 1.0) * 0.25
	_poly(TRI, Vector2(bx + 1.5 * _ppm, top + 0.9 * _ppm), -PI * 0.5 + sway * 0.2, Vector2(1.7, 3.0) * _ppm * 0.6, Color(0.1, 0.8, 0.8) if flight.passed_target else Color(0.2, 0.55, 0.95))
	draw_string_outline(_font, Vector2(bx - 3.0 * _ppm, top - 0.6 * _ppm), "DAILY TARGET", HORIZONTAL_ALIGNMENT_CENTER, 6.0 * _ppm, 34, 8, BLACK)
	draw_string(_font, Vector2(bx - 3.0 * _ppm, top - 0.6 * _ppm), "DAILY TARGET", HORIZONTAL_ALIGNMENT_CENTER, 6.0 * _ppm, 34, Color(0.7, 0.95, 1.0))

func _draw_ramp() -> void:
	if flight.ramp_pts.size() != Tuning.RAMP_N + 1:
		return
	match flight.launcher_id:
		"sling":
			_draw_sling()
			return
		"catapult":
			_draw_catapult()
			return
		"sled":
			_draw_sled()
			return
	_draw_plain_ramp()

## The Slingshot: a forked post, rubber bands to the glider's pouch (they snap back after the release), and
## while aiming a dotted path showing roughly where you will go.
func _draw_sling() -> void:
	var f := flight
	var fork := Vector2(_sx(0.0), _sy(5.0))
	var u := _ppm
	# the post
	draw_line(Vector2(fork.x, _ground_sy), fork + Vector2(0, 0.4 * u), BLACK, 20.0)
	draw_line(Vector2(fork.x, _ground_sy), fork + Vector2(0, 0.4 * u), Color(0.55, 0.38, 0.22), 13.0)
	var left := fork + Vector2(-1.1 * u, -1.3 * u)
	var right := fork + Vector2(1.1 * u, -1.3 * u)
	for tip in [left, right]:
		draw_line(fork + Vector2(0, 0.4 * u), tip, BLACK, 16.0)
		draw_line(fork + Vector2(0, 0.4 * u), tip, Color(0.55, 0.38, 0.22), 10.0)
	# the bands: stretched to the glider while it is held / pulled, wobbling shut afterwards
	var pouch := Vector2(_sx(f.x), _sy(f.y))
	if f.phase == Flight.PH_AIM or f.phase == Flight.PH_READY or f.phase == Flight.PH_RAMP:
		for tip in [left, right]:
			draw_line(tip, pouch, BLACK, 9.0)
			draw_line(tip, pouch, Color(0.85, 0.25, 0.2), 5.0)
	else:
		var amp := exp(-minf(f.time_in_air, 2.0) * 7.0) * sin(f.time_in_air * 55.0) * 0.5 * u
		var mid := fork + Vector2(0, -1.0 * u + amp)
		for tip in [left, right]:
			draw_line(tip, mid, BLACK, 9.0)
			draw_line(tip, mid, Color(0.85, 0.25, 0.2), 5.0)
	# the aim preview: ballistic dots from the fork along the launch direction
	if f.phase == Flight.PH_AIM:
		var a := deg_to_rad(f.aim_angle)
		var v := f.lip_speed
		var g := Tuning.gravity
		for k in 14:
			var t := 0.12 * (k + 1)
			var p := Vector2(_sx(v * cos(a) * t), _sy(5.0 + v * sin(a) * t - 0.5 * g * t * t))
			draw_circle(p, 6.0 - k * 0.25, Color(1, 1, 1, 0.9 - k * 0.05))

## The Catapult: a wooden frame, a long arm with a counterweight, the glider riding the arm tip.
func _draw_catapult() -> void:
	var f := flight
	var piv := Vector2(_sx(f.pivot.x), _sy(f.pivot.y))
	var u := _ppm
	var wood := Color(0.6, 0.42, 0.25)
	# legs and base
	for dx in [-2.2, 2.2]:
		draw_line(Vector2(piv.x + dx * u, _ground_sy), piv, BLACK, 20.0)
		draw_line(Vector2(piv.x + dx * u, _ground_sy), piv, wood, 13.0)
	_box(piv.x, _ground_sy, 7.0 * u, 0.7 * u, wood.darkened(0.2))
	# the arm: from the counterweight end through the pivot to the tip where the glider sits
	var end := Vector2(f.x, f.y)
	if f.phase == Flight.PH_AIR or f.phase == Flight.PH_SLIDE or f.phase == Flight.PH_DONE:
		var last := f.ramp_pts[Tuning.RAMP_N]
		end = last
	else:
		end = Vector2(f.x, f.y) if f.phase == Flight.PH_RAMP else f.ramp_pts[0]
	var tip := Vector2(_sx(end.x), _sy(end.y))
	var back := piv - (tip - piv) * 0.35
	draw_line(back, tip, BLACK, 18.0)
	draw_line(back, tip, wood.lightened(0.15), 11.0)
	_poly(OCT, back, 0.0, Vector2(0.9, 0.9) * u, Color(0.35, 0.35, 0.4))
	_poly(OCT, piv, 0.0, Vector2(0.45, 0.45) * u, Color(0.25, 0.25, 0.3), 2.0)

## The Rocket Sled: a long rail on posts with a rocket-powered cart under the glider.
func _draw_sled() -> void:
	var f := flight
	var u := _ppm
	var pts := f.ramp_pts
	var n := Tuning.RAMP_N + 1
	var a := Vector2(_sx(pts[0].x), _sy(pts[0].y))
	# posts
	for k in 6:
		var p := pts[int(float(k) / 5.0 * (n - 1))]
		var sx := _sx(p.x)
		draw_line(Vector2(sx, _ground_sy), Vector2(sx, _sy(p.y - 0.3)), BLACK, 12.0)
		draw_line(Vector2(sx, _ground_sy), Vector2(sx, _sy(p.y - 0.3)), Color(0.5, 0.5, 0.55), 7.0)
	for i in n:
		_ramp_top_line[i] = Vector2(_sx(pts[i].x), _sy(pts[i].y))
	draw_polyline(_ramp_top_line, BLACK, 12.0)
	draw_polyline(_ramp_top_line, Color(0.75, 0.75, 0.8), 6.0)
	for k in 17:
		var p2 := pts[int(float(k) / 16.0 * (n - 1))]
		draw_line(Vector2(_sx(p2.x), _sy(p2.y)) + Vector2(0, 3), Vector2(_sx(p2.x), _sy(p2.y)) + Vector2(0, 0.45 * u), Color(0.45, 0.35, 0.25), 5.0)
	# the cart rides under the glider until the lip, then stays there
	var cart_world := Vector2(f.x, f.y - Flight.BELLY - 0.35)
	if f.phase == Flight.PH_AIR or f.phase == Flight.PH_SLIDE or f.phase == Flight.PH_DONE:
		cart_world = pts[n - 1] + Vector2(0, -0.1)
	var cart := Vector2(_sx(cart_world.x), _sy(cart_world.y))
	var rot := -f.ramp_psi if f.phase == Flight.PH_RAMP or f.phase == Flight.PH_READY else -deg_to_rad(22.0)
	_poly(RECT, cart, rot, Vector2(3.2, 0.7) * u, Color(0.8, 0.2, 0.15))
	_poly(RECT, cart + Vector2(-1.7 * u * cos(rot), -1.7 * u * sin(rot)), rot, Vector2(1.2, 0.8) * u, Color(0.3, 0.3, 0.35), 2.5)
	if f.phase == Flight.PH_RAMP:
		var fl := 1.6 + 0.8 * sin(_time * 60.0)
		_poly(FLAME, cart + Vector2(-2.7 * u * cos(rot), -2.7 * u * sin(rot)), rot + PI, Vector2(fl, 1.1) * u, Color(1.0, 0.7, 0.15), 2.5)

func _draw_plain_ramp() -> void:
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
				draw_circle(Vector2(sx, sy), 0.95 * _ppm, Color(1.0, 0.95, 0.6, 0.16))
				_poly_sq(HEX, Vector2(sx, sy), _time * 1.5 + wx, 1.0, Color(0.82, 0.85, 0.9))
				_poly_sq(HEX, Vector2(sx, sy), _time * 1.5 + wx, 0.4, Color(0.3, 0.33, 0.4), 2.0)
				_glint(Vector2(sx, sy), wx, 1.0)
			Flight.K_GEAR:
				draw_circle(Vector2(sx, sy), 1.5 * _ppm, Color(1.0, 0.85, 0.3, 0.2))
				_poly_sq(GEAR, Vector2(sx, sy), _time * 1.2, 0.95, Color(1.0, 0.78, 0.18))
				_poly_sq(HEX, Vector2(sx, sy), _time * 1.2, 0.5, Color(0.55, 0.4, 0.1), 2.0)
				_glint(Vector2(sx, sy), wx, 1.7)
			Flight.K_PAD:
				_draw_pad(sx, f.t_phase[i], wx, f.t_y[i], int(Zones.list[f.t_zone[i]]["pad_skin"]), f.t_zone[i])
			Flight.K_FAN:
				_draw_fan(sx, f.t_y[i], int(Zones.list[f.t_zone[i]]["fan_skin"]), f.t_scale[i])
			Flight.K_BIRD:
				_draw_bird(sx, sy, wx, f.t_zone[i], f.t_scale[i])

## The scrap glint: a thin white star that flashes now and then (each nut on its own beat).
func _glint(o: Vector2, wx: float, scale: float) -> void:
	var ph := fmod(_time * 0.9 + wx * 0.37, 1.0)
	if ph < 0.22:
		var k := sin(ph / 0.22 * PI)
		if k < 0.12:
			return
		_poly(STAR, o + Vector2(-0.3, -0.35) * _ppm * scale, 0.0, Vector2(1.1, 1.1) * _ppm * scale * k, Color(1, 1, 1, 0.95), 1.0)

## A building under a raised pad or vent (Town awnings, City rooftops): a block from the ground up to `base`.
func _draw_stand(sx: float, base: float, z: int) -> void:
	if base <= 0.3:
		return
	var top := _ground_sy - base * _ppm
	var wpx := 5.2 * _ppm
	_box(sx, _ground_sy, wpx, base * _ppm, _zp(z, 5))
	for r in int(base / 2.6):
		draw_rect(Rect2(sx - wpx * 0.32, top + (1.0 + r * 2.4) * _ppm, wpx * 0.2, 1.0 * _ppm), Color(1, 0.95, 0.6, 0.7))
		draw_rect(Rect2(sx + wpx * 0.1, top + (1.0 + r * 2.4) * _ppm, wpx * 0.2, 1.0 * _ppm), Color(1, 0.95, 0.6, 0.7))

## A bounce pad. Skins: tyre on a coil spring, hay bale, shop awning, beach ball. All squash and wobble
## after a bounce (`phase` counts down from 0.35), all carry the big bobbing UP arrow.
func _draw_pad(sx: float, phase: float, wx: float, base: float, skin: int, z: int) -> void:
	_draw_stand(sx, base, z)
	var base_y := _ground_sy - base * _ppm
	var elapsed := 0.35 - phase
	var disp := 0.0
	if phase > 0.0:
		disp = exp(-elapsed * 7.0) * cos(elapsed * 30.0)   # +1 = squashed down, then rebounds
	var idle := sin(_time * 4.0 + wx) * 0.06
	var lift := 0.9 - 0.45 * disp + idle                    # height of the top above the base (m)
	var top_y := base_y - (0.8 + lift) * _ppm
	match skin:
		1:   # hay bale that squashes
			var hh := (1.5 - 0.5 * disp + idle) * _ppm
			_box(sx, base_y, 3.4 * _ppm, hh, Color(0.95, 0.82, 0.35), 3.0)
			draw_line(Vector2(sx - 1.7 * _ppm, base_y - hh * 0.5), Vector2(sx + 1.7 * _ppm, base_y - hh * 0.5), BLACK, 3.0)
			top_y = base_y - hh
		2:   # awning
			var ah := (0.5 - 0.2 * disp) * _ppm
			for k in 6:
				_box(sx + (k - 2.5) * 0.7 * _ppm, base_y - 1.0 * _ppm, 0.7 * _ppm, ah + 0.6 * _ppm, Color(0.9, 0.2, 0.25) if k % 2 == 0 else Color(1, 1, 1), 2.0)
			top_y = base_y - 1.6 * _ppm - ah
		3:   # beach ball
			var rr := (1.2 - 0.35 * disp) * _ppm
			_poly(OCT, Vector2(sx, base_y - rr), 0.0, Vector2(1.25 * _ppm, rr), Color(1.0, 0.85, 0.2), 3.0)
			_poly(TRI, Vector2(sx, base_y - rr), _time * 0.0, Vector2(1.0 * _ppm, rr * 1.4), Color(0.9, 0.2, 0.3), 2.0)
			top_y = base_y - rr * 2.0
		_:   # tyre on a spring
			_poly(OCT, Vector2(sx, base_y - 0.35 * _ppm), 0.0, Vector2(2.3, 0.4) * _ppm, Color(0.2, 0.2, 0.22))
			for k in 9:
				var t := k / 8.0
				_zig[k] = Vector2(sx + (0.7 if k % 2 == 0 else -0.7) * _ppm * (0.4 if k == 0 or k == 8 else 1.0), base_y - (0.55 + t * lift) * _ppm)
			draw_polyline(_zig, BLACK, 7.0)
			draw_polyline(_zig, Color(0.85, 0.85, 0.9), 3.5)
			_poly(OCT, Vector2(sx, top_y), 0.0, Vector2(2.0, 0.4 * (1.0 + 0.3 * disp)) * _ppm, Color(0.95, 0.5, 0.15))
	var bob := sin(_time * 5.0 + wx) * 0.35 + maxf(-disp, 0.0) * 1.2
	_poly(ARROW_UP, Vector2(sx, top_y - (2.4 + bob) * _ppm), 0.0, Vector2(2.4, 2.8) * _ppm, Color(1.0, 0.9, 0.2), 4.0)

## An updraft: fan, windmill, heat vent or geyser, with a wind column and chevrons rising through it.
func _draw_fan(sx: float, base: float, skin: int, power: float) -> void:
	var z := _zone_at_screen(sx)
	_draw_stand(sx, base, z)
	var gy := _ground_sy - base * _ppm
	var hw := Tuning.fan_half_width * _ppm
	var col_h := Tuning.fan_height * _ppm
	var tint := Color(0.75, 0.95, 1.0, 0.16)
	var chev := Color(1, 1, 1)
	if skin == 2:
		tint = Color(1.0, 0.6, 0.2, 0.2)
		chev = Color(1.0, 0.85, 0.4)
	elif skin == 3:
		tint = Color(0.8, 0.9, 1.0, 0.22)
	draw_rect(Rect2(sx - hw, gy - col_h, hw * 2.0, col_h), tint)
	for k in 12:
		var ph := fmod(_time * 0.8 * power + k * 0.083, 1.0)
		var dx := (_hash(k + 123) - 0.5) * 2.0 * Tuning.fan_half_width * 0.8
		var p := Vector2(sx + dx * _ppm, gy - (2.0 + ph * (Tuning.fan_height - 2.0)) * _ppm)
		var a := 0.85 * sin(ph * PI)
		var w := 0.5 * _ppm
		draw_line(p + Vector2(-w, w * 0.6), p, Color(0, 0, 0, a * 0.7), 7.0)
		draw_line(p + Vector2(w, w * 0.6), p, Color(0, 0, 0, a * 0.7), 7.0)
		draw_line(p + Vector2(-w, w * 0.6), p, Color(chev.r, chev.g, chev.b, a), 4.0)
		draw_line(p + Vector2(w, w * 0.6), p, Color(chev.r, chev.g, chev.b, a), 4.0)
	match skin:
		1:   # windmill: a tower with big turning sails
			var hub := Vector2(sx, gy - 5.2 * _ppm)
			_poly(TRI, Vector2(sx, gy - 2.6 * _ppm), 0.0, Vector2(2.6, 5.2) * _ppm, Color(0.92, 0.88, 0.8))
			var ang := _time * 3.0
			for b in 4:
				var a2 := ang + b * PI * 0.5
				_poly(RECT, hub + Vector2(cos(a2), sin(a2)) * 1.5 * _ppm, a2, Vector2(3.0, 0.7) * _ppm, Color(0.75, 0.3, 0.25), 2.5)
			_ball(hub.x, hub.y, 0.45 * _ppm, Color(0.3, 0.2, 0.15))
		2:   # heat vent: a grate with shimmering heat
			_box(sx, gy, 3.2 * _ppm, 0.9 * _ppm, Color(0.35, 0.35, 0.4))
			for k in 4:
				draw_line(Vector2(sx - 1.2 * _ppm + k * 0.8 * _ppm, gy - 0.15 * _ppm), Vector2(sx - 1.2 * _ppm + k * 0.8 * _ppm, gy - 0.75 * _ppm), Color(1.0, 0.5, 0.15), 4.0)
		3:   # geyser: a fountain of stacked puffs
			for k in 5:
				var ph2 := fmod(_time * 1.5 + k * 0.2, 1.0)
				_ball(sx + sin(_time * 3.0 + k) * 8.0, gy - (1.0 + ph2 * 5.0) * _ppm, (1.2 - ph2 * 0.6) * _ppm, Color(0.9, 0.95, 1.0, 0.9), 2.0)
			_poly(OCT, Vector2(sx, gy - 0.3 * _ppm), 0.0, Vector2(1.8, 0.45) * _ppm, Color(0.5, 0.5, 0.52))
		_:   # plain fan on a stand
			var hub2 := Vector2(sx, gy - 1.7 * _ppm)
			_poly(TRI, Vector2(sx, gy - 0.9 * _ppm), 0.0, Vector2(2.6, 1.8) * _ppm, Color(0.45, 0.5, 0.55))
			_poly(OCT, hub2, 0.0, Vector2(1.5, 1.5) * _ppm, Color(0.8, 0.82, 0.85), 2.0)
			var ang2 := _time * 14.0
			for b2 in 3:
				_poly(DIAMOND, hub2 + Vector2(cos(ang2 + b2 * TAU / 3.0), sin(ang2 + b2 * TAU / 3.0)) * 0.7 * _ppm, ang2 + b2 * TAU / 3.0, Vector2(1.4, 0.45) * _ppm, Color(0.3, 0.7, 0.95), 2.0)
			_poly_sq(HEX, hub2, 0.0, 0.4, Color(0.2, 0.2, 0.25), 2.0)

## Horizontal streaks across the screen while a boost burns.
func _draw_speed_lines() -> void:
	if boost_fx <= 0.01:
		return
	for k in 16:
		var h := _hash(k + 700)
		var y := (0.1 + 0.8 * _hash(k + 31)) * _size.y
		var len := (0.25 + 0.4 * h) * _size.x
		var x := fmod(_time * (2400.0 + h * 1800.0) + h * 3000.0, _size.x + len * 2.0)
		x = _size.x + len - x
		draw_line(Vector2(x, y), Vector2(x + len, y), Color(1, 1, 1, 0.5 * boost_fx * (0.4 + h)), 3.0 + 4.0 * h)

func _draw_bird(sx: float, sy: float, wx: float, z: int, scale: float) -> void:
	var flap := sin(_time * 14.0 + wx)
	var o := Vector2(sx, sy)
	var u := _ppm * scale
	var body: Color = Zones.list[z]["bird_color"]
	_poly(BIRD_WING, o + Vector2(0, -0.1 * u), 0.0, Vector2(1.0, -flap * 0.7 - 0.2) * u, body.darkened(0.25))
	_poly(BIRD_BODY, o, 0.0, Vector2(u, u), body)
	_poly(BIRD_BEAK, o, 0.0, Vector2(u, u), Color(1.0, 0.7, 0.15), 2.0)
	draw_circle(o + Vector2(0.6, -0.15) * u, 3.5 * scale, Color(1, 1, 1))

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
		if o.x < -300.0 or o.x > _size.x + 300.0 or o.y < -300.0 or o.y > _size.y + 300.0:
			continue
		match _pkind[i]:
			P_FLAME:
				draw_circle(o, sz * 0.5, col)
			P_BUBBLE:
				draw_circle(o, sz * 0.5, Color(col.r, col.g, col.b, col.a * 0.3))
				draw_arc(o, sz * 0.5, 0.0, TAU, 12, Color(0.2, 0.4, 0.6, col.a), 2.0)
			P_FEATHER:
				if sz > 4.0:
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
	var u := _ppm * GLIDER_SCALE       # meters -> pixels (drawn a bit bigger than life so the upgrades read)
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
	# frame look: shape, colours and wings
	var fuse_sc := Vector2(u, u)
	_chord_mult = 1.0
	match f.frame_id:
		"feather":
			body_col = Color(0.88, 0.92, 0.98).darkened(0.04 * (3 - tier))
			wing_col = Color(0.96, 0.9, 0.7).lerp(wing_col, 0.25)
			fuse_sc = Vector2(u * 1.08, u * 0.72)
			_chord_mult = 1.3
		"anvil":
			body_col = Color(0.36, 0.38, 0.44).lightened(0.05 * tier)
			wing_col = Color(0.5, 0.52, 0.56).lerp(wing_col, 0.2)
			_chord_mult = 0.78
		"pogo":
			body_col = Color(0.28, 0.74, 0.36).lightened(0.05 * tier)
			wing_col = Color(1.0, 0.85, 0.25).lerp(wing_col, 0.2)
	if paint_color.a > 0.0:
		body_col = paint_color.lightened(0.04 * tier)
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
		_wing(o, rot, Vector2(-0.6, 0.15), (1.7 + 0.14 * wl) * _chord_mult, wing_col.darkened(0.12), 0.0)
	# --- fuselage ---
	var fuse := TUB if tier == 0 else (FUSE_MID if tier == 1 else FUSE_SLEEK)
	if f.frame_id == "anvil":
		fuse = ANVIL
	elif f.frame_id == "feather":
		fuse = FUSE_SLEEK
	elif f.frame_id == "pogo":
		fuse = TUB
	_poly(fuse, o, rot, fuse_sc, body_col)
	if tier >= 2:
		_poly(RECT, o + Vector2(0.2 * c - 0.1 * s, 0.2 * s + 0.1 * c) * u, rot, Vector2(4.2, 0.14) * u, Color(0.95, 0.95, 0.95), 1.0)
	# --- pilot ---
	var head := o + Vector2(0.2 * c + 0.75 * s, 0.2 * s - 0.75 * c) * u
	_poly(OCT, head, rot, Vector2(0.34, 0.34) * u, Color(0.93, 0.76, 0.6), 2.5)
	_poly(RECT, head + Vector2(0.18 * c, 0.18 * s) * u, rot, Vector2(0.28, 0.16) * u, Color(0.15, 0.15, 0.2), 1.5)
	_draw_hat(o, rot, c, s, u)
	if tier >= 3:
		_poly(DIAMOND, o + Vector2(0.4 * c + 0.55 * s, 0.4 * s - 0.55 * c) * u, rot, Vector2(1.7, 1.25) * u, Color(0.6, 0.85, 0.95, 0.75), 2.5)
	# --- front wing: bigger and better with every Wings level ---
	_wing(o, rot, Vector2(0.4, -0.45), (1.7 + 0.14 * wl) * _chord_mult, wing_col, 1.0)
	# --- wheels (the Pogo bounces on a spring instead) ---
	if f.frame_id == "pogo":
		var top := o + Vector2(0.1 * c - 0.5 * s, 0.1 * s + 0.5 * c) * u
		var bot := o + Vector2(0.1 * c - 2.0 * s, 0.1 * s + 2.0 * c) * u
		for k in 9:
			var t := k / 8.0
			var side := (0.28 if k % 2 == 0 else -0.28) * (0.0 if k == 0 or k == 8 else 1.0)
			_zig[k] = top.lerp(bot, t) + Vector2(side * c, side * s) * u
		draw_polyline(_zig, BLACK, 8.0)
		draw_polyline(_zig, Color(0.85, 0.85, 0.9), 4.0)
		_poly(RECT, bot, rot, Vector2(0.9, 0.2) * u, Color(0.25, 0.25, 0.3), 2.5)
	for wxp in ([] if f.frame_id == "pogo" else [-1.1, 1.0]):
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

## Whiskers' hat, on top of the pilot's head.
func _draw_hat(o: Vector2, rot: float, c: float, s: float, u: float) -> void:
	if hat_id == "none":
		return
	match hat_id:
		"cap":
			_poly(RECT, _rot_pt(Vector2(0.2, -1.1), c, s, u, o), rot, Vector2(0.62, 0.3) * u, Color(0.85, 0.15, 0.15), 2.5)
			_poly(RECT, _rot_pt(Vector2(0.55, -0.98), c, s, u, o), rot, Vector2(0.5, 0.1) * u, Color(0.65, 0.1, 0.1), 2.0)
		"tophat":
			_poly(RECT, _rot_pt(Vector2(0.2, -1.38), c, s, u, o), rot, Vector2(0.5, 0.68) * u, Color(0.12, 0.12, 0.15), 2.5)
			_poly(RECT, _rot_pt(Vector2(0.2, -1.04), c, s, u, o), rot, Vector2(0.95, 0.1) * u, Color(0.12, 0.12, 0.15), 2.5)
			_poly(RECT, _rot_pt(Vector2(0.2, -1.2), c, s, u, o), rot, Vector2(0.52, 0.1) * u, Color(0.8, 0.2, 0.25), 1.5)
		"party":
			_poly(TRI, _rot_pt(Vector2(0.2, -1.38), c, s, u, o), rot, Vector2(0.55, 0.8) * u, Color(0.35, 0.6, 0.95), 2.5)
			_poly(OCT, _rot_pt(Vector2(0.2, -1.8), c, s, u, o), rot, Vector2(0.1, 0.1) * u, Color(1.0, 0.85, 0.2), 2.0)
		"crown":
			_poly(CROWN, _rot_pt(Vector2(0.2, -1.12), c, s, u, o), rot, Vector2(0.75, 0.75) * u, Color(1.0, 0.82, 0.15), 2.5)

## A wing seen from the side-front: a slab above the fuselage with a slanted far edge.
## `chord` is its length in meters; the far edge slants up-back, longer with more lift.
func _wing(o: Vector2, rot: float, root: Vector2, chord: float, col: Color, front: float) -> void:
	var u := _ppm * GLIDER_SCALE
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
