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

## Altitude bands (metres above the ground): low (ground), mid, high, very high. Scrap earned is multiplied by the band the
## glider is in when it earns it (distance pay as it flies, pickups when they are picked up).
var band_edge_1 := 10.0
var band_edge_2 := 24.0
var band_edge_3 := 48.0
var band_mult_0 := 1.0
var band_mult_1 := 1.5
var band_mult_2 := 1.75
var band_mult_3 := 2.0
const BAND_NAMES := ["LOW", "MID", "HIGH", "SKY"]

## Mid air: hot air balloons (clip the top to bounce up), kites and geese (slow you on contact).
var balloon_r := 2.3
var balloon_kick := 17.0
var balloon_restitution := 0.7
var kite_slow := 0.9
var kite_radius := 1.2
var goose_slow := 0.86
var goose_radius := 1.0
## High air: boost rings, tailwind streams, blimps (skim the top), storm clouds.
var ring_radius := 3.4
var ring_boost := 6.5
var ring_scrap := 8                    # prizes pay well: active flying must earn clearly more than gliding
var balloon_scrap := 90
var blimp_scrap := 10
var stream_scrap := 2.0
var low_rings := 1.0                    # 1: a small launch gets its rings, streams and blimps in the mid air it can reach
var chain_window := 6.0                 # seconds to reach the next prize to keep a chain going
var chain_bonus := 0.35                 # each link in a chain pays this much more than the one before per second inside a tailwind
var stream_accel := 4.0
var stream_half_height := 3.6
var stream_len := 42.0
var blimp_len := 9.0
var blimp_height := 3.2
var blimp_boost := 6.5
var blimp_kick := 4.5
var storm_radius := 5.2
var storm_down := 15.0
var storm_drag := 0.6
## Very high: joke finds that pay big (before the band multiplier).
var find_radius := 2.8
var find_value := [80, 200, 120, 160]       # lost satellite, astronaut cat, rubber duck, cow in a bubble
const FIND_NAMES := ["LOST SATELLITE", "ASTRONAUT CAT", "SPACE DUCK", "COSMIC COW"]
var find_min_reach := 34.0                  # finds only appear for launches that can really get up there
## Chunk weights: how often each kind of pattern comes up, and the length of a chunk (m).
var chunk_len_min := 26.0
var chunk_len_max := 40.0
var w_arc := 3.0
var w_line := 2.0
var w_pad := 1.5
var w_fan := 1.0
var w_bird := 1.0
var w_gear := 0.5
var w_low := 0.35
## Air pattern chances (times each zone's own weights): balloon, kite, geese, weave (scrap leading up a band), ring, stream, blimp, storm, find.
var w_balloon := 6.0
var w_kite := 0.9
var w_geese := 1.0
var w_weave := 1.3
var w_ring := 3.0
var w_stream := 1.4
var w_blimp := 1.3
var w_storm := 0.7
var w_find := 0.6
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

# ---------- Frames (every upgrade applies to every frame) ----------
## Featherweight: lighter and lifty, so it glides farther, but it slows down faster (extra drag, birds hurt more).
var feather_lift := 1.3
var feather_drag := 1.05
var feather_gravity := 0.82
var feather_slow := 0.012         # extra speed loss per second (1/s)
var feather_bird := 1.35          # bird hits cost this power more speed (bird_slow ^ this)
## Anvil: heavy and slippery: dives fast, but climbs badly.
var anvil_lift := 0.95
var anvil_drag := 0.72
var anvil_gravity := 1.08
var anvil_climb := 0.45           # extra gravity while climbing (fraction of g)
var anvil_bird := 0.45            # birds barely slow it (bird_slow ^ this)
## Pogo: every bounce (pads, water, clouds) gives this much more.
var pogo_bounce := 1.4
var pogo_lift := 1.0
var frame_price_mult := 1.0

## id, name, price, what it does. Scrapper is the starter.
var frames: Array[Dictionary] = [
	{"id": "scrapper", "name": "Scrapper", "cost": 0.0, "desc": "Balanced. Where everyone starts."},
	{"id": "feather", "name": "Featherweight", "cost": 300.0, "desc": "Glides farther, slows faster."},
	{"id": "anvil", "name": "Anvil", "cost": 550.0, "desc": "Dives fast, shrugs off birds, bad at climbing."},
	{"id": "pogo", "name": "Pogo", "cost": 900.0, "desc": "Extra bounce from every bounce."},
]

func frame_def(id: String) -> Dictionary:
	for f in frames:
		if f["id"] == id:
			return f
	return frames[0]

func frame_cost(id: String) -> float:
	return roundf(float(frame_def(id)["cost"]) * frame_price_mult)

## The numbers a frame changes: lift, drag, gravity, extra drag, climb penalty, bounce, bird exponent.
func frame_stats(id: String) -> Dictionary:
	match id:
		"feather":
			return {"lift": feather_lift, "drag": feather_drag, "gravity": feather_gravity, "slow": feather_slow, "climb": 0.0, "bounce": 1.0, "bird": feather_bird}
		"anvil":
			return {"lift": anvil_lift, "drag": anvil_drag, "gravity": anvil_gravity, "slow": 0.0, "climb": anvil_climb, "bounce": 1.0, "bird": anvil_bird}
		"pogo":
			return {"lift": pogo_lift, "drag": 1.0, "gravity": 1.0, "slow": 0.0, "climb": 0.0, "bounce": pogo_bounce, "bird": 1.0}
	return {"lift": 1.0, "drag": 1.0, "gravity": 1.0, "slow": 0.0, "climb": 0.0, "bounce": 1.0, "bird": 1.0}

# ---------- Launchers (big milestone purchases; the Ramp upgrade scales them all) ----------
## Launch speed (m/s) at upgrade level 0 for the launchers that are not a rolling ramp, and the gain per level.
var sling_speed := 27.0
var catapult_speed := 37.0
var sled_speed := 48.0
var launcher_step := 2.2
## Slingshot: the pull needed for full power (px), the weakest launch as a fraction, the aim limits.
var sling_pull_px := 260.0
var sling_min_power := 0.55
var sling_angle_min := 8.0
var sling_angle_max := 62.0
var sling_default_angle := 30.0
var launcher_price_mult := 1.0

## id, name, price, how it launches. Bought in order: each one needs the one before it.
var launchers: Array[Dictionary] = [
	{"id": "ramp", "name": "Ramp", "cost": 0.0, "desc": "Roll down the ramp and fly."},
	{"id": "sling", "name": "Slingshot", "cost": 1200.0, "desc": "Pull back to aim and power, let go."},
	{"id": "catapult", "name": "Catapult", "cost": 5000.0, "desc": "A big wooden arm hurls you."},
	{"id": "sled", "name": "Rocket Sled", "cost": 18000.0, "desc": "Rockets on rails, then up."},
]

func launcher_def(id: String) -> Dictionary:
	for l in launchers:
		if l["id"] == id:
			return l
	return launchers[0]

func launcher_index(id: String) -> int:
	for i in launchers.size():
		if launchers[i]["id"] == id:
			return i
	return 0

func launcher_cost(id: String) -> float:
	return roundf(float(launcher_def(id)["cost"]) * launcher_price_mult)

## Launch speed at the end of the launcher for an upgrade level (the ramp's depends on its height).
func launcher_speed(id: String, l: int) -> float:
	match id:
		"sling":
			return sling_speed + launcher_step * l
		"catapult":
			return catapult_speed + launcher_step * l
		"sled":
			return sled_speed + launcher_step * l
	return ramp_lip_speed(l)

# ---------- Daily launch and ad stubs ----------
var daily_reward_mult := 1.0
## The fake "Ad playing" screen lasts this long (s). Real ad SDKs would replace Hud.show_ad().
var ad_seconds := 3.0
## An interstitial stub shows between flights at most every this many flights (never in the first few).
var interstitial_every := 4
var interstitial_first_flight := 4
var ads_enabled := true
var trail_rate := 0.04            # seconds between trail particles

# ---------- Missions ----------
## Multiplies every mission's scrap reward.
var mission_reward_mult := 1.0

# ---------- Economy ----------
## Scrap earned per meter flown.
var scrap_per_meter := 0.20
## Every upgrade's price: base * growth ^ level, times these two global multipliers.
var cost_mult := 1.15
var cost_growth_add := 0.11

## id, name, max level, base cost, cost growth per level, unit shown in the shop.
var upgrades: Array[Dictionary] = [
	{"id": "ramp", "name": "Ramp", "max": 10, "base_cost": 25.0, "growth": 1.55, "blurb": "launch speed"},
	{"id": "wings", "name": "Wings", "max": 10, "base_cost": 30.0, "growth": 1.55, "blurb": "lift"},
	{"id": "body", "name": "Body", "max": 10, "base_cost": 30.0, "growth": 1.55, "blurb": "drag"},
	{"id": "booster", "name": "Booster", "max": 8, "base_cost": 84.0, "growth": 1.65, "blurb": "boosts per run"},
	{"id": "magnet", "name": "Scrap Magnet", "max": 8, "base_cost": 20.0, "growth": 1.45, "blurb": "pickup reach"},
]

## Altitude band of a height above the ground: 0 low, 1 mid, 2 high, 3 very high.
func band_of(alt: float) -> int:
	if alt < band_edge_1:
		return 0
	if alt < band_edge_2:
		return 1
	return 2 if alt < band_edge_3 else 3

func band_mult(b: int) -> float:
	match b:
		0:
			return band_mult_0
		1:
			return band_mult_1
		2:
			return band_mult_2
	return band_mult_3

## "x2", "x1.5": the multiplier as shown next to the distance.
func mult_text(m: float) -> String:
	return "x%d" % int(m) if is_equal_approx(m, floorf(m)) else "x%.1f" % m

## The lowest height of band b (metres).
func band_floor(b: int) -> float:
	match b:
		0:
			return 0.0
		1:
			return band_edge_1
		2:
			return band_edge_2
	return band_edge_3

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

## Fill `pts` for the Catapult: an arc of a swinging arm (radius 6 m) from behind and below up to release at the lip.
## Returns the path length. The arm pivot is returned in `pivot_out[0]`.
func build_catapult(pts: PackedVector2Array, pivot_out: PackedVector2Array) -> float:
	if pts.size() != RAMP_N + 1:
		pts.resize(RAMP_N + 1)
	var r := 6.0
	var a0 := deg_to_rad(190.0)
	var a1 := deg_to_rad(308.0)   # the tangent here points 38 degrees up
	var lip := Vector2(0.0, 7.0)
	var pivot := lip - Vector2(cos(a1), sin(a1)) * r
	pivot_out[0] = pivot
	for i in RAMP_N + 1:
		var a := lerpf(a0, a1, float(i) / RAMP_N)
		pts[i] = pivot + Vector2(cos(a), sin(a)) * r
	return absf(a1 - a0) * r

## Fill `pts` for the Rocket Sled: a long flat track kicking up at the end. Returns the path length.
func build_sled(pts: PackedVector2Array) -> float:
	if pts.size() != RAMP_N + 1:
		pts.resize(RAMP_N + 1)
	var total := 34.0
	var curve := 8.0
	var ds := total / RAMP_N
	var psi_lip := deg_to_rad(22.0)
	var p := Vector2(0.0, 3.5)
	pts[RAMP_N] = p
	for i in range(RAMP_N, 0, -1):
		var e := (RAMP_N - i + 0.5) * ds
		var psi := lerpf(psi_lip, 0.0, smoothstep(0.0, 1.0, e / curve))
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
var current_launcher := "ramp"   # set by Main: the equipped launcher (the "ramp" upgrade acts on it)

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
			return "launch %d m/s" % roundi(launcher_speed(current_launcher, l))
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
