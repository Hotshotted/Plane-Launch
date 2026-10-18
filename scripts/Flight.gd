class_name Flight
extends RefCounted
## The whole simulation of a run, with no nodes in it (so tests and the balance sim can drive it
## headless): the glider's physics, the ramp, the things in the world and the chunk generator.
## World units are meters, +x flight direction, +y up, ground at y = 0, x = 0 at the ramp lip.
## Everything is pooled: the things live in fixed-size arrays that are reused for the whole session
## and nothing is allocated while flying.

const MAX_THINGS := 96
const MAX_EVENTS := 32

# Things
const K_NUT := 0
const K_GEAR := 1
const K_PAD := 2
const K_FAN := 3
const K_BIRD := 4

# Events (for the effects and the HUD; read and cleared by Main every frame)
const EV_SCRAP := 0
const EV_PAD := 1
const EV_BIRD := 2
const EV_BOOST := 3
const EV_STALL := 4
const EV_LAND := 5
const EV_LAUNCH := 6
const EV_BEST := 7
const EV_FAN := 8     # just flew into an updraft
const EV_TARGET := 11 # passed the daily target distance
const EV_ZONE := 9    # entered a new zone for the first time this run (val = zone index)
const EV_SKIP := 10   # bounced off the ground (val = 1 water, 2 cloud)

# Phases
const PH_READY := 0   # on top of the ramp, waiting for the launch
const PH_RAMP := 1    # rolling down the ramp
const PH_AIR := 2     # flying
const PH_SLIDE := 3   # touched down, skidding to a stop
const PH_DONE := 4    # stopped: the run is over
const PH_AIM := 5     # slingshot: pulling back to aim, waiting for the release

const BELLY := 0.55   # glider centre to its underside (m)

# --- the things (parallel arrays, MAX_THINGS long) ---
var t_active := PackedByteArray()
var t_kind := PackedInt32Array()
var t_x := PackedFloat32Array()
var t_y := PackedFloat32Array()
var t_y0 := PackedFloat32Array()      # birds: the height they bob around
var t_vx := PackedFloat32Array()
var t_phase := PackedFloat32Array()   # random phase, or a squash timer (pads)
var t_zone := PackedInt32Array()      # the zone a thing belongs to (its look)
var t_scale := PackedFloat32Array()   # birds: size, fans: strength
var thing_count := 0                  # active things (for ?perf)

# --- events ---
var ev_kind := PackedInt32Array()
var ev_x := PackedFloat32Array()
var ev_y := PackedFloat32Array()
var ev_val := PackedInt32Array()
var ev_n := 0

# --- the glider ---
var phase := PH_READY
var x := 0.0
var y := 0.0
var vx := 0.0
var vy := 0.0
var theta := 0.0          # pitch (rad), + = nose up
var stall_amount := 0.0   # 0 = flying, 1 = fully stalled
var cl_now := 0.0
var in_fan := false
var _was_in_fan := false
var boost_left := 0.0
var charges := 0
var charges_max := 0
var slide_time := 0.0
var time_in_air := 0.0
var clock := 0.0          # seconds since the launch

# --- upgrade levels in effect (copied from Save at reset) ---
var lv_ramp := 0
var lv_wings := 0
var lv_body := 0
var lv_booster := 0
var lv_magnet := 0
var frame_id := "scrapper"
var launcher_id := "ramp"
# frame traits (Tuning.frame_stats)
var tr_lift := 1.0
var tr_drag := 1.0
var tr_gravity := 1.0
var tr_slow := 0.0
var tr_climb := 0.0
var tr_bounce := 1.0
var tr_bird := 1.0
var lift_k_eff := 0.0
var drag0_eff := 0.0
var magnet_r := 0.0
var thrust := 0.0

# --- the ramp ---
var ramp_pts := PackedVector2Array()   # the ramp polyline, top first, lip last (Tuning.build_ramp)
var ramp_top := Vector2.ZERO   # world position of the top end
var ramp_len := 0.0            # along the path
var ramp_u := 0.0              # distance the glider has rolled
var ramp_speed := 0.0
var ramp_psi := 0.0            # direction of the ramp where the glider is (rad, + = up)
var path_kind := 0             # 0: rolls down the ramp (energy), 1: pushed along the path (catapult, sled, slingshot)
var start_speed := 0.0         # speed at the start of a pushed path
var lip_speed := 0.0           # speed leaving the launcher
var pivot := Vector2.ZERO      # catapult: where the arm turns
var aim_power := 0.0           # slingshot: 0..1
var aim_angle := 30.0          # slingshot: degrees
var _pivot_tmp := PackedVector2Array([Vector2.ZERO])

# --- the run ---
var distance := 0.0            # meters: live while flying, final at touchdown
var picked_value := 0          # scrap value picked up
var picked_count := 0
var best_x := 0.0              # the best-distance marker in the world (0 = none yet)
var passed_best := false
var target_x := 0.0            # the daily target marker in the world (0 = none)
var passed_target := false
var gen_x := 0.0
var rng := RandomNumberGenerator.new()
var bird_hits := 0
var pad_bounces := 0
var boosts_used := 0
var gears_picked := 0
var fan_entries := 0
var stall_time := 0.0          # seconds spent stalled this run
var max_altitude := 0.0
var max_speed := 0.0
var zone := 0                  # zone the glider is in
var zone_max := 0              # farthest zone reached this run
var skips := 0
var _gravity := 9.8

var _weights := PackedFloat32Array([0, 0, 0, 0, 0, 0, 0])

func _init() -> void:
	t_active.resize(MAX_THINGS)
	t_kind.resize(MAX_THINGS)
	t_x.resize(MAX_THINGS)
	t_y.resize(MAX_THINGS)
	t_y0.resize(MAX_THINGS)
	t_vx.resize(MAX_THINGS)
	t_phase.resize(MAX_THINGS)
	t_zone.resize(MAX_THINGS)
	t_scale.resize(MAX_THINGS)
	ev_kind.resize(MAX_EVENTS)
	ev_x.resize(MAX_EVENTS)
	ev_y.resize(MAX_EVENTS)
	ev_val.resize(MAX_EVENTS)

func push_event(kind: int, ex: float, ey: float, val: int = 0) -> void:
	if ev_n < MAX_EVENTS:
		ev_kind[ev_n] = kind
		ev_val[ev_n] = val
		ev_x[ev_n] = ex
		ev_y[ev_n] = ey
		ev_n += 1

# ---------------------------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------------------------

## Put everything back for a new run, with the given upgrade levels. Nothing is allocated.
func reset(levels: Dictionary, seed_value: int = -1) -> void:
	lv_ramp = int(levels.get("ramp", 0))
	lv_wings = int(levels.get("wings", 0))
	lv_body = int(levels.get("body", 0))
	lv_booster = int(levels.get("booster", 0))
	lv_magnet = int(levels.get("magnet", 0))
	frame_id = String(levels.get("frame", "scrapper"))
	launcher_id = String(levels.get("launcher", "ramp"))
	refresh_derived()
	if seed_value >= 0:
		rng.seed = seed_value
	else:
		rng.randomize()
	clear_things()
	ev_n = 0
	phase = PH_READY
	theta = 0.0
	stall_amount = 0.0
	cl_now = 0.0
	in_fan = false
	_was_in_fan = false
	boost_left = 0.0
	charges = Tuning.booster_charges(lv_booster)
	charges_max = charges
	slide_time = 0.0
	time_in_air = 0.0
	clock = 0.0
	distance = 0.0
	picked_value = 0
	picked_count = 0
	passed_best = false
	passed_target = false
	bird_hits = 0
	pad_bounces = 0
	boosts_used = 0
	gears_picked = 0
	fan_entries = 0
	stall_time = 0.0
	max_altitude = 0.0
	max_speed = 0.0
	zone = 0
	zone_max = 0
	skips = 0
	_update_gravity()
	vx = 0.0
	vy = 0.0
	aim_power = 0.65   # (the slingshot waits pulled back, so the bands are visible; LAUNCH starts the aim from zero)
	aim_angle = Tuning.sling_default_angle
	_build_launcher()
	ramp_u = 0.0
	_place_on_ramp()
	gen_x = Tuning.first_chunk_x

## Recompute the numbers the upgrades change (also called when a ?tune slider moves).
func refresh_derived() -> void:
	var st := Tuning.frame_stats(frame_id)
	tr_lift = st["lift"]
	tr_drag = st["drag"]
	tr_gravity = st["gravity"]
	tr_slow = st["slow"]
	tr_climb = st["climb"]
	tr_bounce = st["bounce"]
	tr_bird = st["bird"]
	lift_k_eff = Tuning.wing_lift_k(lv_wings) * tr_lift
	drag0_eff = Tuning.body_drag0(lv_body) * tr_drag
	_update_gravity()
	magnet_r = Tuning.magnet_radius(lv_magnet)
	thrust = Tuning.booster_thrust(lv_booster)

func _update_gravity() -> void:
	_gravity = Tuning.gravity * float(Zones.list[zone]["gravity"]) * tr_gravity

## Build the launcher's path for the equipped launcher and level.
func _build_launcher() -> void:
	match launcher_id:
		"catapult":
			ramp_len = Tuning.build_catapult(ramp_pts, _pivot_tmp)
			pivot = _pivot_tmp[0]
			path_kind = 1
			start_speed = 6.0
			lip_speed = Tuning.launcher_speed("catapult", lv_ramp)
		"sled":
			ramp_len = Tuning.build_sled(ramp_pts)
			path_kind = 1
			start_speed = 8.0
			lip_speed = Tuning.launcher_speed("sled", lv_ramp)
		"sling":
			_build_sling()
		_:
			ramp_len = Tuning.build_ramp(lv_ramp, ramp_pts)
			path_kind = 0
			start_speed = Tuning.ramp_push(lv_ramp)
			lip_speed = Tuning.ramp_lip_speed(lv_ramp)
	ramp_top = ramp_pts[0]
	ramp_speed = start_speed

## The slingshot: a straight path from the pulled-back pouch to the fork, pointing along the aim.
func _build_sling() -> void:
	if ramp_pts.size() != Tuning.RAMP_N + 1:
		ramp_pts.resize(Tuning.RAMP_N + 1)
	var a := deg_to_rad(aim_angle)
	var pull := 0.8 + 4.5 * aim_power
	var anchor := Vector2(0.0, 5.0)
	var dir := Vector2(cos(a), sin(a))
	var s := anchor - dir * pull
	for i in Tuning.RAMP_N + 1:
		ramp_pts[i] = s.lerp(anchor, float(i) / Tuning.RAMP_N)
	ramp_len = pull
	path_kind = 1
	lip_speed = Tuning.launcher_speed("sling", lv_ramp) * lerpf(Tuning.sling_min_power, 1.0, aim_power)
	start_speed = lip_speed * 0.3

## Slingshot: change the pull (power 0..1, angle in degrees) while aiming.
func set_aim(power: float, angle_deg: float) -> void:
	if phase != PH_AIM and phase != PH_READY:
		return
	aim_power = clampf(power, 0.0, 1.0)
	aim_angle = clampf(angle_deg, Tuning.sling_angle_min, Tuning.sling_angle_max)
	_build_sling()
	ramp_top = ramp_pts[0]
	ramp_u = 0.0
	_place_on_ramp()

## Slingshot: let go. Needs some pull.
func fire() -> bool:
	if phase != PH_AIM or aim_power < 0.2:
		return false
	phase = PH_RAMP
	ramp_u = 0.0
	push_event(EV_LAUNCH, x, y)
	return true

func clear_things() -> void:
	for i in MAX_THINGS:
		t_active[i] = 0
	thing_count = 0

## Put the glider on the ramp at distance `ramp_u` along it (sits on the surface, BELLY above it).
func _place_on_ramp() -> void:
	var fi := clampf(ramp_u / ramp_len, 0.0, 1.0) * Tuning.RAMP_N
	var i := mini(int(fi), Tuning.RAMP_N - 1)
	var seg := ramp_pts[i + 1] - ramp_pts[i]
	var p := ramp_pts[i].lerp(ramp_pts[i + 1], fi - i)
	ramp_psi = atan2(seg.y, seg.x)
	x = p.x - sin(ramp_psi) * BELLY
	y = p.y + cos(ramp_psi) * BELLY
	theta = ramp_psi

## Start rolling. (Called when LAUNCH is pressed.)
func launch() -> void:
	if phase != PH_READY:
		return
	if launcher_id == "sling":
		phase = PH_AIM   # wait for the pull and release
		set_aim(0.0, Tuning.sling_default_angle)
		return
	phase = PH_RAMP
	push_event(EV_LAUNCH, x, y)

## Launch without interaction (tests, the balance sim): the slingshot fires at full pull and the default angle.
func launch_auto() -> void:
	launch()
	if phase == PH_AIM:
		set_aim(1.0, Tuning.sling_default_angle)
		fire()

# ---------------------------------------------------------------------------------------------
# Stepping
# ---------------------------------------------------------------------------------------------

## Advance by `delta` seconds (sub-stepped). `hold` = the pitch-up control is held.
func advance(delta: float, hold: bool) -> void:
	var h := Tuning.physics_step
	var n := ceili(delta / h)
	if n <= 0:
		return
	h = delta / n
	for i in n:
		step(h, hold)

func step(dt: float, hold: bool) -> void:
	match phase:
		PH_RAMP:
			_step_ramp(dt)
		PH_AIR:
			_step_air(dt, hold)
		PH_SLIDE:
			_step_slide(dt)

func _step_ramp(dt: float) -> void:
	clock += dt
	if path_kind == 0:
		var push := Tuning.ramp_push(lv_ramp)
		var fall := ramp_top.y - (y - cos(ramp_psi) * BELLY)
		ramp_speed = sqrt(push * push + 2.0 * Tuning.gravity * maxf(fall, 0.0))
	else:
		ramp_speed = sqrt(start_speed * start_speed + (lip_speed * lip_speed - start_speed * start_speed) * clampf(ramp_u / ramp_len, 0.0, 1.0))
	ramp_u += maxf(ramp_speed, 1.0) * dt
	if ramp_u >= ramp_len:
		# Off the lip: free flight in the direction of the lip.
		ramp_u = ramp_len
		_place_on_ramp()
		var s := lip_speed
		vx = s * cos(ramp_psi)
		vy = s * sin(ramp_psi)
		theta = ramp_psi
		phase = PH_AIR
		time_in_air = 0.0
		return
	_place_on_ramp()

func _step_air(dt: float, hold: bool) -> void:
	clock += dt
	time_in_air += dt
	# --- pitch control ---
	var rate := deg_to_rad(Tuning.pitch_rate)
	if hold:
		theta = minf(theta + rate * dt, deg_to_rad(Tuning.pitch_up_deg))
	else:
		theta = maxf(theta - rate * dt, deg_to_rad(Tuning.pitch_down_deg))
	# --- aerodynamics ---
	var s := maxf(sqrt(vx * vx + vy * vy), 0.5)
	var gam := atan2(vy, vx)
	var alpha := wrapf(theta - gam, -PI, PI)
	var a_st := deg_to_rad(Tuning.stall_angle_deg)
	var peak := Tuning.camber + Tuning.cl_slope * a_st
	var cl: float
	var st := 0.0
	if alpha > a_st:
		st = clampf((alpha - a_st) / deg_to_rad(Tuning.stall_soft_deg), 0.0, 1.0)
		cl = lerpf(peak, peak * Tuning.stall_lift_frac, st)
	else:
		cl = maxf(Tuning.camber + Tuning.cl_slope * alpha, Tuning.cl_min)
	if st > 0.0 and stall_amount <= 0.0:
		push_event(EV_STALL, x, y)
	stall_amount = st
	if st > 0.0:
		stall_time += dt
	cl_now = cl
	var lift := lift_k_eff * s * s * cl
	var drag := s * s * (drag0_eff + Tuning.drag_ind * cl * cl + Tuning.stall_drag * st)
	var nx := -vy / s   # unit vector perpendicular to the velocity, to the left of it: lift direction
	var ny := vx / s
	var ax := nx * lift - drag * vx / s
	var ay := ny * lift - drag * vy / s - _gravity
	if vy > 0.0 and tr_climb > 0.0:
		ay -= _gravity * tr_climb
	if st > 0.0:
		theta -= deg_to_rad(Tuning.stall_nose_drop) * st * dt
	# --- booster ---
	if boost_left > 0.0:
		boost_left = maxf(boost_left - dt, 0.0)
		ax += cos(theta) * thrust
		ay += sin(theta) * thrust
	# --- things that act on the glider ---
	in_fan = false
	for i in MAX_THINGS:
		if t_active[i] == 0:
			continue
		var kind := t_kind[i]
		if kind == K_FAN:
			var dx := absf(x - t_x[i])
			var up := y - BELLY - t_y[i]
			if dx < Tuning.fan_half_width and up > -0.5 and up < Tuning.fan_height:
				in_fan = true
				ay += Tuning.fan_accel * t_scale[i] * (1.0 - 0.6 * clampf(up / Tuning.fan_height, 0.0, 1.0))
	if in_fan and not _was_in_fan:
		fan_entries += 1
		push_event(EV_FAN, x, y)
	_was_in_fan = in_fan
	vx += ax * dt
	vy += ay * dt
	if tr_slow > 0.0:
		var keep := 1.0 - tr_slow * dt
		vx *= keep
		vy *= keep
	var sp := sqrt(vx * vx + vy * vy)
	if sp > 90.0:
		vx *= 90.0 / sp
		vy *= 90.0 / sp
	x += vx * dt
	y += vy * dt
	distance = maxf(x, 0.0)
	var zi := Tuning.zone_index(x)
	if zi != zone:
		zone = zi
		_update_gravity()
		if zi > zone_max:
			zone_max = zi
			push_event(EV_ZONE, x, y, zi)
	max_altitude = maxf(max_altitude, y - BELLY)
	max_speed = maxf(max_speed, sp)
	_touch_things(dt)
	if not passed_best and best_x > 0.0 and x >= best_x:
		passed_best = true
		push_event(EV_BEST, x, y)
	if not passed_target and target_x > 0.0 and x >= target_x:
		passed_target = true
		push_event(EV_TARGET, x, y)
	# --- keep the world filled ahead, and drop what is behind ---
	while gen_x < x + 70.0:
		_gen_chunk()
	# --- the ground: dirt ends the run, water skips, clouds bounce ---
	if y - BELLY <= 0.0 or clock > Tuning.max_flight_seconds:
		_ground_contact()

func _touch_things(dt: float) -> void:
	var mag := magnet_r
	var pick_r := Tuning.scrap_pick_radius
	for i in MAX_THINGS:
		if t_active[i] == 0:
			continue
		var kind := t_kind[i]
		var tx := t_x[i]
		if tx < x - 14.0:
			t_active[i] = 0
			thing_count -= 1
			continue
		match kind:
			K_NUT, K_GEAR:
				var dx := x - tx
				var dy := y - t_y[i]
				var d2 := dx * dx + dy * dy
				if d2 < pick_r * pick_r:
					t_active[i] = 0
					thing_count -= 1
					var v := Tuning.scrap_nut_value if kind == K_NUT else Tuning.scrap_gear_value
					picked_value += v
					picked_count += 1
					if kind == K_GEAR:
						gears_picked += 1
					push_event(EV_SCRAP, tx, t_y[i], v)
				elif d2 < mag * mag and mag > pick_r:
					var d := sqrt(d2)
					var pull := Tuning.magnet_pull_speed * dt
					t_x[i] = tx + dx / d * minf(pull, d)
					t_y[i] = t_y[i] + dy / d * minf(pull, d)
			K_PAD:
				t_phase[i] = maxf(t_phase[i] - dt, 0.0)
				var base := t_y[i]
				if vy < 0.0 and y - BELLY <= base + Tuning.pad_height and y - BELLY >= base - 0.6 and absf(x - tx) < Tuning.pad_half_width + 0.4:
					var vy_in := vy
					vy = maxf(-vy * Tuning.pad_restitution, Tuning.pad_min_kick) * tr_bounce
					y = base + Tuning.pad_height + BELLY
					t_phase[i] = 0.35
					pad_bounces += 1
					push_event(EV_PAD, tx, base + Tuning.pad_height, roundi(vy - vy_in))
			K_BIRD:
				t_x[i] = tx + t_vx[i] * dt
				t_y[i] = t_y0[i] + sin(clock * 2.6 + t_phase[i]) * 1.1
				var bx := x - t_x[i]
				var by := y - t_y[i]
				var rr := Tuning.bird_radius * t_scale[i] + 0.8
				if bx * bx + by * by < rr * rr:
					t_active[i] = 0
					thing_count -= 1
					var sp_in := speed()
					var bs := pow(Tuning.bird_slow, tr_bird)
					vx *= bs
					vy *= bs
					bird_hits += 1
					push_event(EV_BIRD, t_x[i], t_y[i], roundi(sp_in - speed()))

func _ground_contact() -> void:
	var zd: Dictionary = Zones.list[zone]
	var kind := int(zd["ground"])
	var sp := speed()
	if clock <= Tuning.max_flight_seconds:
		if kind == 1 and sp >= Tuning.skip_min_speed and vy >= -Tuning.skip_max_sink:
			vy = maxf(-vy * Tuning.skip_restitution, Tuning.skip_min_kick) * tr_bounce
			vx *= Tuning.skip_speed_kept
			y = BELLY + 0.02
			skips += 1
			push_event(EV_SKIP, x, 0.0, 1)
			return
		var bounce := float(zd["bounce"])
		if bounce > 0.0 and vy < -2.0:
			vy = -vy * bounce * tr_bounce
			y = BELLY + 0.02
			skips += 1
			push_event(EV_SKIP, x, 0.0, 2)
			return
	_touch_down()

func _touch_down() -> void:
	y = BELLY
	distance = maxf(x, 0.0)
	phase = PH_SLIDE
	slide_time = 0.0
	boost_left = 0.0
	stall_amount = 0.0
	vy = 0.0
	theta = 0.0
	push_event(EV_LAND, x, 0.0)

func _step_slide(dt: float) -> void:
	slide_time += dt
	x += vx * dt
	vx = maxf(vx - (6.0 + vx * 1.2) * dt, 0.0)
	if vx < 0.3 or slide_time > 1.6:
		vx = 0.0
		phase = PH_DONE

# ---------------------------------------------------------------------------------------------
# Booster
# ---------------------------------------------------------------------------------------------

func boost() -> bool:
	if phase != PH_AIR or charges <= 0 or boost_left > 0.0:
		return false
	charges -= 1
	boosts_used += 1
	boost_left = Tuning.booster_time
	push_event(EV_BOOST, x, y, roundi(thrust * Tuning.booster_time))
	return true

# ---------------------------------------------------------------------------------------------
# Results
# ---------------------------------------------------------------------------------------------

func is_over() -> bool:
	return phase == PH_DONE

func airborne() -> bool:
	return phase == PH_AIR

func speed() -> float:
	return sqrt(vx * vx + vy * vy)

func altitude() -> float:
	return maxf(y - BELLY, 0.0)

## Scrap this run is worth: distance pay plus what was picked up.
func scrap_for_distance() -> int:
	return int(floorf(distance * Tuning.scrap_per_meter))

func scrap_total() -> int:
	return scrap_for_distance() + picked_value

# ---------------------------------------------------------------------------------------------
# World generation
# ---------------------------------------------------------------------------------------------

func add_thing(kind: int, tx: float, ty: float, tvx: float = 0.0) -> void:
	var zi := Tuning.zone_index(tx)
	var zd: Dictionary = Zones.list[zi]
	for i in MAX_THINGS:
		if t_active[i] == 0:
			t_active[i] = 1
			t_kind[i] = kind
			t_x[i] = tx
			t_y[i] = ty
			t_y0[i] = ty
			t_vx[i] = tvx
			t_phase[i] = rng.randf() * TAU if kind == K_BIRD else 0.0
			t_zone[i] = zi
			t_scale[i] = float(zd["bird_scale"]) if kind == K_BIRD else (float(zd["fan_mult"]) if kind == K_FAN else 1.0)
			thing_count += 1
			return

func _gen_chunk() -> void:
	var cx := gen_x
	var d := clampf(cx / 1000.0, 0.0, 1.0)
	var zd: Dictionary = Zones.list[Tuning.zone_index(cx)]
	var zw: Array = zd["weights"]
	var raise: Array = zd["raise"]
	_weights[0] = Tuning.w_arc * zw[0]
	_weights[1] = Tuning.w_line * zw[1]
	_weights[2] = Tuning.w_pad * zw[2]
	_weights[3] = Tuning.w_fan * zw[3]
	_weights[4] = (Tuning.w_bird + Tuning.bird_weight_per_km * (cx / 1000.0)) * zw[4]
	_weights[5] = Tuning.w_gear * zw[5]
	_weights[6] = Tuning.w_low * zw[6]
	var total := 0.0
	for w in _weights:
		total += w
	var pick := rng.randf() * total
	var which := 0
	for i in _weights.size():
		pick -= _weights[i]
		if pick <= 0.0:
			which = i
			break
	var base := 0.0
	if float(raise[1]) > 0.0:
		base = rng.randf_range(float(raise[0]), float(raise[1]))
	match which:
		0:   # an arc of nuts
			var apex := rng.randf_range(5.0, 18.0 + 18.0 * d)
			for i in 6:
				var t := i / 5.0
				add_thing(K_NUT, cx + 2.0 + t * 12.0, apex + 3.5 * sin(PI * t))
		1:   # a straight row of nuts
			var ly := rng.randf_range(3.0, 28.0)
			for i in 5:
				add_thing(K_NUT, cx + 3.0 + i * 2.2, ly)
		2:   # a bounce pad (on a rooftop in the Town and City) with nuts along the arc it throws you on
			var px := cx + rng.randf_range(4.0, 10.0)
			add_thing(K_PAD, px, base)
			for i in 4:
				var t := i / 3.0
				add_thing(K_NUT, px + 4.0 + t * 8.0, base + 7.0 + 4.0 * sin(PI * t))
		3:   # an updraft (fan, windmill, heat vent, geyser) with nuts up its column
			var fx := cx + rng.randf_range(4.0, 10.0)
			add_thing(K_FAN, fx, base)
			for i in 4:
				add_thing(K_NUT, fx, base + 4.0 + i * 3.5)
		4:   # birds, sometimes guarding a gear
			var n := 1 + (1 if rng.randf() < 0.4 else 0) + (1 if d > 0.4 and rng.randf() < 0.4 else 0)
			for i in n:
				var by := rng.randf_range(6.0, 30.0)
				add_thing(K_BIRD, cx + 6.0 + i * 7.0, by, -Tuning.bird_drift)
				if i == 0 and rng.randf() < 0.45:
					add_thing(K_GEAR, cx + 10.0, by + 2.0)
		5:   # a lone gear up high with a couple of nuts
			var gy := rng.randf_range(8.0, 30.0)
			add_thing(K_GEAR, cx + 8.0, gy)
			add_thing(K_NUT, cx + 5.0, gy - 1.5)
			add_thing(K_NUT, cx + 11.0, gy - 1.5)
		6:   # nuts skimming the ground (or the water: skim for them)
			for i in 6:
				add_thing(K_NUT, cx + 3.0 + i * 2.0, 1.6)
	gen_x += rng.randf_range(Tuning.chunk_len_min, Tuning.chunk_len_max)

# ---------------------------------------------------------------------------------------------
# A simple pilot for tests and the balance sim
# ---------------------------------------------------------------------------------------------

var _ap_hold := false
var _ap_timer := 0.0
var _ap_boost_timer := 0.0

## Best-glide speed for the current wings and body: the speed the pilot tries to keep.
func best_glide_speed() -> float:
	var cl_bg := sqrt(drag0_eff / Tuning.drag_ind)
	return sqrt(Tuning.gravity / (lift_k_eff * cl_bg))

## A decent human: keeps the wing at its best-glide angle of attack (holds when the nose is too low
## for that, lets go when it is too high), decides about every 0.04 * `skill` seconds, flares near the
## ground and fires the booster when it is sinking low. `skill` 1 = quick, 3 = sluggish.
func pilot(delta: float, skill: float = 1.0) -> bool:
	_ap_timer -= delta
	_ap_boost_timer -= delta
	if _ap_timer <= 0.0:
		_ap_timer = 0.04 * skill
		var cl_bg := sqrt(drag0_eff / Tuning.drag_ind)
		var alpha_bg := (cl_bg - Tuning.camber) / Tuning.cl_slope
		var alpha := wrapf(theta - atan2(vy, vx), -PI, PI)
		var limit := deg_to_rad(Tuning.stall_angle_deg)
		if stall_amount > 0.0:
			_ap_hold = false
		elif altitude() < 3.0 and vy < 0.0:
			_ap_hold = alpha < limit * 0.8   # flare near the ground
		else:
			_ap_hold = alpha < alpha_bg
	if phase == PH_AIR and charges > 0 and _ap_boost_timer <= 0.0 and altitude() < 14.0 and vy < -1.0 and theta > deg_to_rad(-12.0):
		if boost():
			_ap_boost_timer = 1.2
	return _ap_hold
