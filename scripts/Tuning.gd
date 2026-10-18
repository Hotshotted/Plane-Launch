extends Node
## Every "feel" and economy value of the game lives here, in one place.
## Registered as the autoload `Tuning`, so any script can read `Tuning.some_value`.
## They are plain vars (not consts) so the ?tune panel can edit them live.
## World units are meters: +x is the flight direction (screen-right), +y is up. Ground is y = 0.
## x = 0 is the lip of the ramp; the distance score is the x where the glider first touches down.

# ---------- Frame time ----------
## The simulation never advances more than this per frame (seconds), whatever the real frame took.
var max_frame_delta := 0.05
## A frame longer than this (a tab switch, a long hitch) is a stall: it is not simulated at all.
var stall_delta := 0.25
## Frames skipped (no simulation) after a stall or the window coming back, so nothing catches up.
var resume_skip_frames := 2
## The physics runs in fixed sub-steps of this many seconds (a frame takes as many as it needs).
var physics_step := 1.0 / 120.0

# ---------- Start-up pre-warm (see Main._prewarm) ----------
var prewarm_min_seconds := 1.5
var prewarm_stable_frames := 10
var prewarm_stable_ms := 45.0
var prewarm_max_seconds := 5.0

# ---------- Boost feel ----------
## Camera kick when a boost fires: the view is pulled back this many meters and eases home; plus a zoom pulse.
var boost_kick_m := 1.6
var boost_kick_zoom := 0.05
var boost_kick_decay := 3.2

# ---------- Camera / screen ----------
## Pixels per meter (the canvas is 1080 px wide, so the screen is about 1080 / view_scale meters wide).
var view_scale := 34.0
## Where the glider sits across the screen while flying (fraction of the width).
var glider_screen_x := 0.30
## While low, the camera keeps the ground this many meters above the bottom of the screen.
var ground_margin := 5.5
## Once high, the glider is held at this fraction of the screen height (from the bottom).
var glider_screen_y := 0.42
## How quickly the camera follows (1 / seconds).
var camera_follow := 4.0

# ---------- Glide physics ----------
## Gravity (m/s^2).
var gravity := 9.8
## Wing lift: lift acceleration = lift_k * speed^2 * CL. The Wings upgrade scales lift_k.
var lift_k := 0.040
## CL (lift coefficient) = camber + cl_slope * angle_of_attack(rad), up to the stall angle.
var cl_slope := 5.0
var camber := 0.15
## Past this angle of attack (degrees) the wing stalls and CL drops to stall_lift_frac of its peak
## (blended over stall_soft_deg). Low speed makes the glider stall because the nose can't keep up.
var stall_angle_deg := 20.0
var stall_soft_deg := 6.0
var stall_lift_frac := 0.30
## Most negative CL (pushing over / diving).
var cl_min := -0.25
## Drag acceleration = speed^2 * (drag0 + drag_ind * CL^2) (+ stall_drag when stalled).
## Best glide ratio at the start ~ lift_k / (2 * sqrt(drag0 * drag_ind)) = 4.5.
var drag0 := 0.0049
var drag_ind := 0.0040
var stall_drag := 0.012
## While stalled the nose is pushed down at this rate (degrees/second): "too slow stalls".
var stall_nose_drop := 70.0
## Pitch control: holding raises the nose at pitch_rate (deg/s) up to pitch_up_deg; releasing lowers it down to pitch_down_deg.
var pitch_rate := 70.0
var pitch_up_deg := 28.0
var pitch_down_deg := -34.0

# ---------- Ramp / launch ----------
## The ramp slopes down, then curves up into a ski-jump lip. Speed at the lip = sqrt(push^2 + 2 * g * drop)
## (the glider rolls without friction), leaving at ramp_lip_angle_deg above horizontal.
const RAMP_N := 32          # points in the ramp polyline
var ramp_lip_height := 12.0
## Ramp upgrade: starting push (m/s) and ramp drop (m) at level 0, and the gain per level.
var ramp_push_base := 14.0
var ramp_push_step := 2.2
var ramp_drop_base := 5.0
var ramp_drop_step := 1.2
## Slope of the straight part (degrees), and the ski-jump: how long the curve is and where it points.
var ramp_angle_deg := 25.0
var ramp_curve_len := 8.0
var ramp_lip_angle_deg := 8.0

# ---------- Upgrades (gains per level) ----------
## Wings: lift_k grows by this fraction of its base per level.
var wings_lift_step := 0.10
## Body: drag0 shrinks by this fraction per level (compounding).
var body_drag_step := 0.10
## Booster: tap fires one burst; level = charges per run. Thrust acceleration along the nose, for burst_time seconds.
var booster_accel := 3.45
var booster_accel_step := 0.575
var booster_time := 0.8
## Scrap Magnet: pickup radius (m) at level 0, and the gain per level. Scrap inside the radius flies to the glider.
var magnet_base := 1.5
var magnet_step := 1.1
var magnet_pull_speed := 26.0

# ---------- World things ----------
## Bounce pad (trampoline tire): rebound speed = max(down speed * pad_restitution, pad_min_kick).
var pad_restitution := 0.85
var pad_min_kick := 13.0
var pad_half_width := 2.2
var pad_height := 1.1
## Updraft fan: extra upward acceleration inside the draft (strongest at the fan, fading to the top).
var fan_accel := 22.0
var fan_height := 15.0
var fan_half_width := 2.4
## Birds slow you: speed is multiplied by this on a hit (and the bird is gone).
var bird_slow := 0.68
var bird_radius := 1.2
var bird_drift := 2.5
## Scrap: pickup radius of the glider body (before the magnet), values.
var scrap_pick_radius := 1.0
var scrap_nut_value := 1
var scrap_gear_value := 6
## Chunk weights: how often each kind of pattern comes up, and the length of a chunk (m).
var chunk_len_min := 26.0
var chunk_len_max := 40.0
var w_arc := 3.0
var w_line := 2.0
var w_pad := 1.5
var w_fan := 1.0
var w_bird := 1.0
var w_gear := 0.5
var w_low := 0.6
## Birds get more common with distance: extra weight per 1000 m.
var bird_weight_per_km := 2.0
## First chunk starts this far past the ramp lip.
var first_chunk_x := 22.0

# ---------- Zones ----------
## Multiply every zone's start distance / scrap bonus (the zone table itself is in Zones.gd).
var zone_distance_mult := 1.0
var zone_bonus_mult := 1.0
## Water (River, Coast): a shallow, fast enough touch skips the glider back up like a stone.
var skip_min_speed := 10.0
var skip_max_sink := 7.5
var skip_restitution := 0.55
var skip_min_kick := 3.0
var skip_speed_kept := 0.97
## Longest flight (s): a safety stop so a bouncing glider can never fly forever.
var max_flight_seconds := 240.0

# ---------- Economy ----------
## Scrap earned per meter flown.
var scrap_per_meter := 0.5
## Every upgrade's price: base * growth ^ level, times these two global multipliers.
var cost_mult := 1.0
var cost_growth_add := 0.0

## id, name, max level, base cost, cost growth per level, unit shown in the shop.
var upgrades: Array[Dictionary] = [
	{"id": "ramp", "name": "Ramp", "max": 10, "base_cost": 25.0, "growth": 1.55, "blurb": "launch speed"},
	{"id": "wings", "name": "Wings", "max": 10, "base_cost": 30.0, "growth": 1.55, "blurb": "lift"},
	{"id": "body", "name": "Body", "max": 10, "base_cost": 30.0, "growth": 1.55, "blurb": "drag"},
	{"id": "booster", "name": "Booster", "max": 8, "base_cost": 84.0, "growth": 1.65, "blurb": "boosts per run"},
	{"id": "magnet", "name": "Scrap Magnet", "max": 8, "base_cost": 20.0, "growth": 1.45, "blurb": "pickup reach"},
]

func zone_index(x: float) -> int:
	return Zones.index_at(x, zone_distance_mult)

func zone_start(i: int) -> float:
	return Zones.start_of(i, zone_distance_mult)

func zone_name(i: int) -> String:
	return Zones.list[clampi(i, 0, Zones.COUNT - 1)]["name"]

## Scrap paid the first time zone i is reached.
func zone_bonus(i: int) -> int:
	return roundi(float(Zones.list[clampi(i, 0, Zones.COUNT - 1)]["bonus"]) * zone_bonus_mult)

func upgrade_def(id: String) -> Dictionary:
	for u in upgrades:
		if u["id"] == id:
			return u
	return {}

func max_level(id: String) -> int:
	var u := upgrade_def(id)
	return int(u["max"]) if not u.is_empty() else 0

## Price of going from `level` to level + 1.
func upgrade_cost(id: String, level: int) -> float:
	var u := upgrade_def(id)
	if u.is_empty():
		return INF
	return roundf(float(u["base_cost"]) * cost_mult * pow(float(u["growth"]) + cost_growth_add, level))

# ---------- What each level does ----------
func ramp_push(l: int) -> float:
	return ramp_push_base + ramp_push_step * l

func ramp_drop(l: int) -> float:
	return ramp_drop_base + ramp_drop_step * l

var _ramp_tmp := PackedVector2Array()

## Fill `pts` (RAMP_N + 1 points, top first, the lip last, evenly spaced along the path) with the ramp
## of the given Ramp level; returns the path length. Pure geometry, shared by the physics, the
## drawing and the shop text.
func build_ramp(l: int, pts: PackedVector2Array) -> float:
	if pts.size() != RAMP_N + 1:
		pts.resize(RAMP_N + 1)
	var phi := deg_to_rad(ramp_angle_deg)
	var psi_lip := deg_to_rad(ramp_lip_angle_deg)
	var total := ramp_drop(l) / sin(phi) + ramp_curve_len
	var ds := total / RAMP_N
	var p := Vector2(0.0, ramp_lip_height)
	pts[RAMP_N] = p
	for i in range(RAMP_N, 0, -1):
		var e := (RAMP_N - i + 0.5) * ds
		var psi := lerpf(psi_lip, -phi, smoothstep(0.0, 1.0, e / ramp_curve_len))
		p -= Vector2(cos(psi), sin(psi)) * ds
		pts[i - 1] = p
	return total

## Speed at the lip (m/s) for a Ramp level.
func ramp_lip_speed(l: int) -> float:
	build_ramp(l, _ramp_tmp)
	var drop := _ramp_tmp[0].y - _ramp_tmp[RAMP_N].y
	return sqrt(ramp_push(l) * ramp_push(l) + 2.0 * gravity * drop)

func wing_lift_k(l: int) -> float:
	return lift_k * (1.0 + wings_lift_step * l)

func body_drag0(l: int) -> float:
	return drag0 * pow(1.0 - body_drag_step, l)

func booster_charges(l: int) -> int:
	return l

func booster_thrust(l: int) -> float:
	return booster_accel + booster_accel_step * maxi(l - 1, 0)

func magnet_radius(l: int) -> float:
	return magnet_base + magnet_step * l

## Best glide ratio for a body/wing level pair (lift_k / (2 sqrt(drag0 * drag_ind))).
func glide_ratio(wing_level: int, body_level: int) -> float:
	return wing_lift_k(wing_level) / (2.0 * sqrt(body_drag0(body_level) * drag_ind))

## "14 -> 16 m/s" style text for the shop: the stat now and at the next level.
func effect_text(id: String, level: int) -> String:
	var nxt := mini(level + 1, max_level(id))
	var maxed := level >= max_level(id)
	var a := _stat_text(id, level)
	if maxed:
		return a
	return "%s  >  %s" % [a, _stat_text(id, nxt)]

func _stat_text(id: String, l: int) -> String:
	match id:
		"ramp":
			return "launch %d m/s" % roundi(ramp_lip_speed(l))
		"wings":
			return "lift +%d%%" % roundi(wings_lift_step * l * 100.0)
		"body":
			return "drag -%d%%" % roundi((1.0 - pow(1.0 - body_drag_step, l)) * 100.0)
		"booster":
			return "%d boost%s" % [booster_charges(l), "" if booster_charges(l) == 1 else "s"]
		"magnet":
			return "reach %.1f m" % magnet_radius(l)
	return ""

## 12345 -> "12,345".
func fmt(v: float) -> String:
	var n := int(floorf(maxf(v, 0.0)))
	var s := str(n)
	var out := ""
	var count := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "," + out
	return out
