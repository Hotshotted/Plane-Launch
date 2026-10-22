extends Node2D
## Game loop: states (shop <-> flight), input, camera, effects, the run's result, and the start-up pre-warm.
## One scene for the whole session: a new run is a reset IN PLACE (nothing is created or freed).

const STATE_SHOP := 0
const STATE_FLIGHT := 1

const FINISH_DELAY := 0.9     # seconds on the landing spot before the shop comes back
const MAX_TOUCHES := 10

var flight := Flight.new()
var world: WorldView
var hud: Hud
var sfx: Sfx
var paused := false             # the pause card is up: the flight is frozen
var _audio_hold := false        # the page went to the background: sound is held until the player taps Resume
var _page_hidden := false
var _poll_t := 0.0
var _haptic_warmed := false
var tune_panel: TunePanel
var rng := RandomNumberGenerator.new()

var state := STATE_SHOP
var last_result := {}          # distance, earned, dist_scrap, picked, picked_count, new_best
var runs_this_session := 0
var daily_mode := false          # this flight is the Daily Launch
var bonus_charge := 0            # free boost charges from a rewarded ad, used by the next launch
var restart_count := 0

# camera (smoothed)
var cam_x := 0.0
var cam_bottom := 0.0
var cam_ppm := 28.0
var _snap_camera := true
var _trail_t := 0.0
var _toast_val := PackedInt32Array([0, 0, 0])   # last mission progress shown as a toast, per mission
var _kick := 0.0               # camera kick from a boost, 1 -> 0
var _time := 0.0

# input
var _touch_hold := PackedByteArray()
var _touch_boost := PackedByteArray()
var _key_hold := false
var _touch_seen := false
var _aim_index := -1                 # the finger pulling the slingshot
var _aim_start := Vector2.ZERO

# frame time
var _grinder_t := 0.0
var _prev_phase := -1
var _chain_shown := 0
var _scrap_sum := 0             # nut scrap waiting for its one popup
var _scrap_mult := 10
var _scrap_pos := Vector2.ZERO
var _scrap_t := 0.0
var _dust_left := 0.0           # seconds of dust trail still to lay (after a bounce)
var _dust_t := 0.0
var _wind_t := 0.0
var _smoke_t := 0.0
var _tumble_w := 0.0            # the crunch-and-tumble after touchdown: spin rate (rad/s), height and its speed
var _tumble_a := 0.0
var _hop_y := 0.0
var _hop_v := 0.0
var _skip_frames := 0
var _suspended := false
var _warming := false
var _finish_timer := -1.0
var _event := ""
var _event_frame := -100

func _ready() -> void:
	rng.randomize()
	_touch_hold.resize(MAX_TOUCHES)
	_touch_boost.resize(MAX_TOUCHES)
	world = WorldView.new()
	world.flight = flight
	add_child(world)
	sfx = Sfx.new()
	add_child(sfx)
	Sfx.set_bus_volume("SFX", Save.sfx_vol)
	Sfx.set_bus_volume("Music", Save.music_vol)
	hud = Hud.new()
	hud.sfx = sfx
	hud.buzz = _buzz
	add_child(hud)
	hud.pause_pressed.connect(set_paused.bind(true))
	hud.resume_pressed.connect(set_paused.bind(false))
	hud.restart_pressed.connect(_restart_flight)
	hud.quit_pressed.connect(_quit_flight)
	hud.volume_changed.connect(_on_volume)
	hud.fx_arrived.connect(_on_fx_arrived)
	hud.launch_pressed.connect(launch)
	hud.buy_pressed.connect(_on_buy)
	hud.frame_pressed.connect(_on_frame)
	hud.cosmetic_pressed.connect(_on_cosmetic)
	hud.daily_pressed.connect(launch_daily)
	hud.ad_double_pressed.connect(_on_ad_double)
	hud.ad_boost_pressed.connect(_on_ad_boost)
	hud.launcher_pressed.connect(_on_launcher)
	Save.changed.connect(_on_save_changed)
	if DebugFlags.tune_enabled():
		tune_panel = TunePanel.new()
		add_child(tune_panel)
		tune_panel.build()
		tune_panel.changed.connect(_on_tuning_changed)
	_to_shop(false)
	if DebugFlags.prewarm_enabled():
		_prewarm()
	elif tune_panel:
		tune_panel.set_available(true)

# ---------------------------------------------------------------------------------------------
# Pre-warm: the first time fonts, canvas batches and the GL state get used is slow (and mobile
# browsers may compile in the background), so at boot, behind a splash, draw EVERYTHING for real
# (a maxed glider on the ramp, one of every thing, every particle kind, every label and panel) and
# keep drawing until frame times settle. Everything stays alive for the whole session, so this runs once.
# ---------------------------------------------------------------------------------------------

var _prewarm_zone_idx := -1
var prewarm_zones_seen := {}   # zones whose scenery was drawn during the pre-warm
var prewarm_frames_seen := {}
var prewarm_launchers_seen := {}
var prewarm_air_seen := {}      # skins of the air objects drawn during the pre-warm
var _prewarm_levels := {}

## Pre-warm: show zone `zi`'s scenery with one of every thing, so each zone's shapes are drawn once at boot.
func _prewarm_zone(zi: int) -> void:
	_prewarm_zone_idx = zi
	prewarm_zones_seen[zi] = true
	var lo := _prewarm_levels.duplicate()
	lo["frame"] = Tuning.frames[zi % Tuning.frames.size()]["id"]
	lo["launcher"] = Tuning.launchers[zi % Tuning.launchers.size()]["id"]
	prewarm_frames_seen[lo["frame"]] = true
	prewarm_launchers_seen[lo["launcher"]] = true
	flight.reset(lo, 1)
	flight.best_x = 18.0
	flight.boost_left = 5.0
	flight.stall_amount = 1.0
	if lo["launcher"] == "sling":
		flight.set_aim(0.8, 35.0)
		flight.phase = Flight.PH_AIM
	flight.clear_things()
	var x0 := Tuning.zone_start(zi) + (0.0 if zi == 0 else 6.0)
	cam_x = x0 - 6.0
	var raise: Array = Zones.list[zi]["raise"]
	var base := float(raise[1]) * 0.5
	for i in 6:
		flight.add_thing(Flight.K_NUT, x0 + i * 3.0, 20.0)
	flight.add_thing(Flight.K_GEAR, x0 + 16.0, 21.0)
	flight.add_thing(Flight.K_PAD, x0 + 4.0, base)
	flight.add_thing(Flight.K_FAN, x0 + 12.0, base)
	flight.add_thing(Flight.K_BIRD, x0 + 18.0, 12.0)
	# every kind of air object, in this zone's own skins (the zones together cover every skin)
	flight.add_thing(Flight.K_BALLOON, x0 + 24.0, 24.0, 0.0, zi % 3)
	flight.add_thing(Flight.K_KITE, x0 + 30.0, 14.0, 0.0, zi % 3)
	flight.add_thing(Flight.K_GOOSE, x0 + 34.0, 40.0, 0.0, zi % 6)
	flight.add_thing(Flight.K_RING, x0 + 22.0, 34.0)
	flight.add_thing(Flight.K_STREAM, x0 + 8.0, 46.0, 0.0, 0, 30.0)
	flight.add_thing(Flight.K_BLIMP, x0 + 36.0, 52.0, 0.0, zi % 3)
	flight.add_thing(Flight.K_STORM, x0 + 44.0, 34.0, 0.0, zi % 3)
	flight.add_thing(Flight.K_FIND, x0 + 28.0, 62.0, 0.0, zi % 4, 80.0)
	prewarm_air_seen["balloon%d" % (zi % 3)] = true
	prewarm_air_seen["flock%d" % (zi % 6)] = true
	prewarm_air_seen["kite%d" % (zi % 3)] = true
	prewarm_air_seen["storm%d" % (zi % 3)] = true
	prewarm_air_seen["find%d" % (zi % 4)] = true
	prewarm_air_seen["blimp%d" % (zi % 3)] = true
	if flight.phase != Flight.PH_AIM and zi % 2 == 0:
		flight.phase = Flight.PH_AIR
		flight.x = x0 + 8.0
		flight.y = 14.0
		flight.theta = 0.1
	_apply_camera()

func _prewarm() -> void:
	_warming = true
	hud.show_splash(true)
	hud.prewarm_show(true)
	if tune_panel:
		tune_panel.prewarm_show(true)
	var maxed := {}
	for u in Tuning.upgrades:
		maxed[u["id"]] = u["max"]
	_prewarm_levels = maxed
	world.best_text = "BEST 99 m"
	world.show_aura = true
	cam_ppm = 20.0
	cam_bottom = -6.0
	_prewarm_zone(0)
	var t_start := Time.get_ticks_msec()
	var t_last := t_start
	var calm := 0
	var t_refresh := -100000
	while true:
		var now := Time.get_ticks_msec()
		var zi := int((now - t_start) / 110) % Zones.COUNT
		if zi != _prewarm_zone_idx:
			_prewarm_zone(zi)
		if now - t_refresh > 300:
			t_refresh = now
			for k in 8:
				world.spawn(k, 4.0 + k * 3.0, 6.0, 1.0, 1.0, 0.6, 0.35, Color(1, 0.8, 0.3))
			for k in 4:
				hud.popup("BOUNCE! +%d" % (10 + k), Vector2(300 + k * 150, 800), Color.WHITE)
		world.update_particles(0.016)
		_apply_camera()
		await get_tree().process_frame
		var t := Time.get_ticks_msec()
		calm = calm + 1 if (t - t_last) < Tuning.prewarm_stable_ms else 0
		t_last = t
		var elapsed := (t - t_start) / 1000.0
		if elapsed >= Tuning.prewarm_max_seconds:
			break
		if elapsed >= Tuning.prewarm_min_seconds and calm >= Tuning.prewarm_stable_frames:
			break
	world.clear_particles()
	world.show_aura = false
	hud.prewarm_show(false)
	hud.show_splash(false)
	if tune_panel:
		tune_panel.prewarm_show(false)
		tune_panel.set_available(true)
	_warming = false
	_to_shop(false)
	hud.play_intro()

# ---------------------------------------------------------------------------------------------
# State changes
# ---------------------------------------------------------------------------------------------

## Back to the shop with a fresh glider on the ramp (also run in place after a landing).
func _to_shop(snap: bool = true, results: bool = false) -> void:
	state = STATE_SHOP
	_finish_timer = -1.0
	world.clear_particles()
	world.show_aura = false
	Save.ensure_missions(rng)
	Save.refresh_daily()
	Tuning.current_launcher = Save.launcher
	_apply_style()
	flight.reset(Save.loadout())
	flight.best_x = Save.best_distance
	_set_best_text()
	paused = false
	sfx.set_music("garage")
	sfx.set_wind(0.0)
	sfx.set_rumble(false)
	world.rumble = 0.0
	world.speed_fx = 0.0
	world.tumble = 0.0
	world.hop = 0.0
	_tumble_a = 0.0
	_hop_y = 0.0
	_prev_phase = -1
	world.ambience = true
	hud.set_mode(Hud.MODE_SHOP)
	hud.refresh_shop(last_result, bonus_charge > 0)
	hud.show_results(results and not last_result.is_empty())
	_snap_camera = snap or _snap_camera

func _set_best_text() -> void:
	world.best_x = Save.best_distance
	world.best_text = "BEST %s m" % Tuning.fmt(Save.best_distance) if Save.best_distance > 0.0 else ""
	hud.set_best(Save.best_distance)

## LAUNCH pressed: start a run, in place.
func launch() -> void:
	_start_flight(false)

## The Daily Launch: today's seeded world, with a target distance flag.
func launch_daily() -> void:
	_start_flight(true)

func _start_flight(daily: bool) -> void:
	if state != STATE_SHOP or _warming or hud.ad_active:
		return
	state = STATE_FLIGHT
	daily_mode = daily
	restart_count += 1
	_skip_frames = Tuning.resume_skip_frames
	_note_event("daily run started" if daily else "run started")
	Save.refresh_daily()
	flight.reset(Save.loadout(), Save.daily_seed() if daily else -1)
	flight.best_x = Save.best_distance
	flight.target_x = float(Save.daily_target) if daily else 0.0
	world.target_x = flight.target_x
	if daily:
		Save.daily_plays += 1
	if bonus_charge > 0:   # a free boost from a rewarded ad, for this flight only
		flight.charges += bonus_charge
		flight.charges_max += bonus_charge
		bonus_charge = 0
	_set_best_text()
	world.clear_particles()
	world.show_aura = flight.lv_magnet > 0
	for i in MAX_TOUCHES:
		_touch_hold[i] = 0
		_touch_boost[i] = 0
	world.ambience = false
	sfx.set_music("flight")
	_scrap_sum = 0
	_scrap_t = 0.0
	_prev_phase = -1
	_dust_left = 0.0
	hud.set_mode(Hud.MODE_FLIGHT)
	if daily:
		hud.set_daily_target(Save.daily_target)
	for mm in Save.missions:
		mm["fresh"] = false
		mm["moved"] = false
	for i in Missions.SLOTS:
		_toast_val[i] = 0
	hud.show_hint(Save.runs < 2)
	flight.launch()

func _finish_run() -> void:
	var best_before := Save.best_distance
	var claim := Save.claim_zones(flight.zone_max)
	var stats := {"distance": flight.distance, "picked_value": flight.picked_value, "pad_bounces": flight.pad_bounces, "skips": flight.skips,
			"fan_entries": flight.fan_entries, "boosts_used": flight.boosts_used, "gears_picked": flight.gears_picked,
			"bird_hits": flight.bird_hits, "zone_max": flight.zone_max, "rings_hit": flight.rings_hit, "balloon_hits": flight.balloon_hits,
			"blimp_hits": flight.blimp_hits, "stream_time": flight.stream_time, "high_time": flight.band_time[2] + flight.band_time[3], "finds": flight.finds}
	var done := Missions.evaluate(Save, stats, rng)
	var mission_bonus := 0
	for md in done:
		mission_bonus += int(md["reward"])
	var new_missions: Array[String] = []
	for mn in Save.missions:
		if mn.get("fresh", false):
			new_missions.append(Missions.describe(mn))
	var daily_info := {}
	var daily_bonus := 0
	if daily_mode:
		Save.daily_best = maxf(Save.daily_best, floorf(flight.distance))
		if flight.distance >= Save.daily_target and not Save.daily_claimed:
			Save.daily_claimed = true
			daily_bonus = Save.daily_reward()
		daily_info = {"distance": floorf(flight.distance), "target": Save.daily_target, "bonus": daily_bonus}
	var earned: int = flight.scrap_total() + int(claim["bonus"]) + mission_bonus + daily_bonus
	Save.flights_since_ad += 1
	var new_best := Save.record_run(flight.distance, earned)
	var line := Rusty.comment({"new_best": new_best, "distance": flight.distance, "best_before": best_before, "mission_done": not done.is_empty(),
			"new_zone": claim["new"] > 0, "daily_reached": daily_bonus > 0, "stall_time": flight.stall_time, "bird_hits": flight.bird_hits, "run": Save.runs})
	runs_this_session += 1
	last_result = {
		"distance": floorf(flight.distance), "earned": earned, "dist_scrap": flight.scrap_for_distance(),
		"picked": flight.picked_value, "picked_count": flight.picked_count, "new_best": new_best,
		"zone_bonus": claim["bonus"], "zone": flight.zone_max, "new_zones": claim["new"],
		"mission_bonus": mission_bonus, "height_bonus": int(roundf(flight.bonus_scrap)), "missions": done, "new_missions": new_missions, "rusty": line, "daily": daily_info, "doubled": false,
	}
	_finish_timer = 0.0

## The glider swells and glows with a burst of sparks: the change you just paid for.
func _preview_pulse() -> void:
	world.pulse = 1.0
	world.burst(WorldView.P_SPARK, flight.x, flight.y, 16, 9.0, 0.8, 0.42, Hud.C_GOLD, rng)

func _on_buy(id: String) -> void:
	if state == STATE_SHOP and Save.buy(id):
		var idx := 0
		for i in Tuning.upgrades.size():
			if Tuning.upgrades[i]["id"] == id:
				idx = i
		# card flash, level pip, scrap flying to the glider; the part bolts on when it lands (_on_fx_arrived)
		hud.buy_fx(idx, world.to_screen(flight.x, flight.y))

func _on_fx_arrived(tag: String) -> void:
	if tag == "buy":
		sfx.play("clank")
		_preview_pulse()

func set_paused(on: bool) -> void:
	if on and (state != STATE_FLIGHT or flight.phase == Flight.PH_DONE):
		return
	paused = on
	if on:
		sfx.set_wind(0.0)
		sfx.set_rumble(false)
	hud.show_pause(on)
	clear_input()
	if not on:
		_skip_frames = Tuning.resume_skip_frames
		_release_audio()    # the player tapped Resume: sound may run again

func _restart_flight() -> void:
	set_paused(false)
	var daily := daily_mode
	_to_shop(true, false)
	_start_flight(daily)

func _quit_flight() -> void:
	set_paused(false)
	_to_shop(true, false)

func _on_volume(bus: String, v: float) -> void:
	if bus == "SFX":
		Save.sfx_vol = v
	else:
		Save.music_vol = v
	Sfx.set_bus_volume(bus, v)
	Save.save_game()
	sfx.play("toggle")

## A frames row was pressed: equip it if owned, buy it (and equip) if not.
func _on_frame(id: String) -> void:
	if state != STATE_SHOP:
		return
	if (Save.equip_frame(id) if Save.owns_frame(id) else Save.buy_frame(id)):
		_preview_pulse()

func _on_cosmetic(kind: String, id: String) -> void:
	if state != STATE_SHOP:
		return
	if (Save.equip_cosmetic(kind, id) if Save.owns_cosmetic(kind, id) else Save.buy_cosmetic(kind, id)):
		_preview_pulse()

## Hand the equipped paint and hat to the renderer.
func _apply_style() -> void:
	world.paint_color = Cosmetics.def("paint", Save.paint)["color"]
	world.hat_id = Save.hat

# ---- ad stubs (rewarded: double scrap after a flight, a free boost before a launch; interstitial between flights) ----

func _on_ad_double() -> void:
	if state != STATE_SHOP or hud.ad_active or last_result.is_empty() or last_result.get("doubled", true) or not Tuning.ads_enabled:
		return
	hud.show_ad("AD PLAYING", "double scrap (+%s)" % Tuning.fmt(last_result["earned"]), Tuning.ad_seconds, _grant_double)

func _grant_double() -> void:
	if last_result.is_empty() or last_result.get("doubled", true):
		return
	last_result["doubled"] = true
	Save.flights_since_ad = 0
	Save.add_scrap(float(last_result["earned"]))   # (saves and refreshes the shop)

func _on_ad_boost() -> void:
	if state != STATE_SHOP or hud.ad_active or bonus_charge > 0 or not Tuning.ads_enabled:
		return
	hud.show_ad("AD PLAYING", "a free boost charge for your next launch", Tuning.ad_seconds, _grant_boost)

func _grant_boost() -> void:
	bonus_charge = 1
	Save.flights_since_ad = 0
	hud.refresh_shop(last_result, true)

## Between flights only, never in the first few, at most every Tuning.interstitial_every flights.
func _maybe_interstitial() -> void:
	if not Tuning.ads_enabled or hud.ad_active or Save.runs < Tuning.interstitial_first_flight or Save.flights_since_ad < Tuning.interstitial_every:
		return
	hud.show_ad("AD BREAK", "", Tuning.ad_seconds * 0.7, _interstitial_done)

func _interstitial_done() -> void:
	Save.flights_since_ad = 0
	Save.save_game()

func _on_launcher(id: String) -> void:
	if state != STATE_SHOP:
		return
	if (Save.equip_launcher(id) if Save.owns_launcher(id) else Save.buy_launcher(id)):
		_preview_pulse()

func _on_save_changed() -> void:
	Tuning.current_launcher = Save.launcher
	_apply_style()
	if state == STATE_SHOP and not _warming:
		flight.reset(Save.loadout())
		flight.best_x = Save.best_distance
		hud.refresh_shop(last_result, bonus_charge > 0)

func _on_tuning_changed(_property: String) -> void:
	flight.refresh_derived()
	if state == STATE_SHOP:
		flight.reset(Save.loadout())
		hud.refresh_shop(last_result, bonus_charge > 0)

# ---------------------------------------------------------------------------------------------
# Input
# ---------------------------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and event.pressed:
		if not _haptic_warmed:
			_haptic_warmed = true
			sfx.unlock()      # browsers only let audio run after a tap
		if _audio_hold and not paused:
			_release_audio()  # a tap on the launch screen brings the sound back
	if hud.intro_active:   # the logo intro: a tap skips it and is not a game touch
		if (event is InputEventScreenTouch and event.pressed) or (event is InputEventMouseButton and event.pressed):
			hud.skip_intro()
		return
	if event is InputEventScreenTouch:
		_touch_seen = true
		var i: int = event.index
		if i < 0 or i >= MAX_TOUCHES:
			return
		if not event.pressed:
			_touch_hold[i] = 0
			_touch_boost[i] = 0
			if i == _aim_index:
				_aim_index = -1
				if flight.phase == Flight.PH_AIM and not flight.fire():
					flight.set_aim(0.0, flight.aim_angle)   # too weak a pull: try again
			return
		if state != STATE_FLIGHT or paused or TunePanel.button_hit(event.position) or hud.pause_rect().has_point(event.position):
			return
		if flight.phase == Flight.PH_AIM:
			_aim_index = i
			_aim_start = event.position
			return
		if hud.boost_rect().has_point(event.position):
			_touch_boost[i] = 1
			flight.boost()
		else:
			_touch_hold[i] = 1
	elif event is InputEventScreenDrag:
		if event.index == _aim_index and flight.phase == Flight.PH_AIM:
			_aim_from_drag(event.position - _aim_start)
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_B or event.keycode == KEY_SHIFT:
			if state == STATE_FLIGHT:
				flight.boost()
		elif (event.keycode == KEY_ENTER or event.keycode == KEY_SPACE) and state == STATE_SHOP and not (tune_panel and tune_panel.is_open):
			launch()

## Slingshot: a pull of `d` pixels (screen) sets power by its length and the angle from its direction.
func _aim_from_drag(d: Vector2) -> void:
	var power := clampf(d.length() / Tuning.sling_pull_px, 0.0, 1.0)
	var ang := rad_to_deg(atan2(d.y, maxf(-d.x, 0.001)))   # pull down-left to launch up-right
	flight.set_aim(power, ang)

func is_holding() -> bool:
	for i in MAX_TOUCHES:
		if _touch_hold[i] != 0:
			return true
	return _key_hold

func clear_input() -> void:
	for i in MAX_TOUCHES:
		_touch_hold[i] = 0
		_touch_boost[i] = 0

# ---------------------------------------------------------------------------------------------
# Frame time: the simulation can never run ahead of the clock
# ---------------------------------------------------------------------------------------------

func _note_event(what: String) -> void:
	_event = what
	_event_frame = Engine.get_process_frames()

## The part of this real frame (`raw` seconds) the simulation may use: 0 to skip it.
func _frame_delta(raw: float) -> float:
	var used := 0.0
	var why := ""
	if _suspended:
		why = "window in the background"
	elif _skip_frames > 0:
		_skip_frames -= 1
		why = "skipped (resuming)"
	elif raw > Tuning.stall_delta:
		_skip_frames = Tuning.resume_skip_frames
		why = "stall dropped"
	else:
		used = minf(raw, Tuning.max_frame_delta)
		why = "clamped" if raw > Tuning.max_frame_delta else ""
	if raw > 0.05 and DebugFlags.perf_enabled():
		hud.note_hitch(raw, used, why, _hitch_context())
	return used

func _hitch_context() -> String:
	var parts: Array[String] = []
	if Engine.get_process_frames() - _event_frame <= 4 and _event != "":
		parts.append(_event)
	parts.append("state %s, phase %d" % ["flight" if state == STATE_FLIGHT else "shop", flight.phase])
	return ", ".join(parts)

func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_WM_WINDOW_FOCUS_OUT:
			if not _suspended:
				_suspended = true
				_note_event("window went to the background")
			_background()     # silence, and pause a flight in progress (auto-pause on focus loss)
		NOTIFICATION_APPLICATION_FOCUS_IN, NOTIFICATION_APPLICATION_RESUMED, NOTIFICATION_WM_WINDOW_FOCUS_IN:
			if _suspended:
				_suspended = false
				_skip_frames = Tuning.resume_skip_frames
				clear_input()
				_foreground()
				_note_event("window came back")

# ---------------------------------------------------------------------------------------------
# Background audio
# ---------------------------------------------------------------------------------------------

## The page was hidden, blurred or the phone locked: silence everything and pause a flight in progress. Nothing resumes by
## itself: the player has to come back and tap Resume (or, on the launch screen, tap anywhere).
func _background() -> void:
	_page_hidden = true
	if not _audio_hold:
		_audio_hold = true
		sfx.hold()
	if state == STATE_FLIGHT and not paused and not _warming:
		set_paused(true)
	_publish_state()

func _foreground() -> void:
	_page_hidden = false
	_publish_state()

## The player is back and has tapped (Resume, or any tap on the launch screen): sound may run again.
func _release_audio() -> void:
	if _page_hidden:
		return
	if _audio_hold:
		_audio_hold = false
		sfx.release()
		if OS.has_feature("web"):
			JavaScriptBridge.eval("window.__pwRelease && window.__pwRelease()")
	_publish_state()

## Web: the page tells us about visibility too (a hidden tab, a locked phone), and we publish our state (and where the
## buttons are, in page pixels) for the automated audio check.
func _poll_page(delta: float) -> void:
	if not OS.has_feature("web"):
		return
	_poll_t += delta
	if _poll_t < 0.25:
		return
	_poll_t = 0.0
	var hidden := bool(JavaScriptBridge.eval("!!window.__pwHidden"))
	if hidden and not _page_hidden:
		_background()
	elif not hidden and _page_hidden:
		_foreground()
	else:
		_publish_state()

func _css_center(c: Control, sc: float) -> String:
	var p := c.get_global_rect().get_center() * sc
	return "[%.1f, %.1f]" % [p.x, p.y]

func _publish_state() -> void:
	if not OS.has_feature("web"):
		return
	var ready_now := not _warming and not hud.intro_active
	var sc := float(JavaScriptBridge.eval("window.innerWidth")) / get_viewport().get_visible_rect().size.x
	JavaScriptBridge.eval("window.__pwGameReady = true; window.__pw = {ready: %s, paused: %s, muted: %s, held: %s, launch: %s, pause: %s, resume: %s, garage: %s, close: %s}" % [
			str(ready_now).to_lower(), str(paused).to_lower(), str(AudioServer.is_bus_mute(0)).to_lower(), str(_audio_hold).to_lower(),
			_css_center(hud._launch_btn, sc), _css_center(hud._pause_btn, sc), _css_center(hud._resume_btn, sc), _css_center(hud._nav_buttons[0], sc), _css_center(hud._sheet_close, sc)])

func _process(raw_delta: float) -> void:
	_poll_page(raw_delta)
	_key_hold = Input.is_key_pressed(KEY_SPACE) or Input.is_key_pressed(KEY_UP)
	if _warming:
		return
	frame(_frame_delta(raw_delta), raw_delta)

## One frame of the game with `delta` seconds of simulation (0 = nothing moves, e.g. a skipped frame).
## Public so tests can step the game with fixed time.
func frame(delta: float, raw_delta: float = 0.0) -> void:
	if paused:
		delta = 0.0
	if delta > 0.0:
		world.update_particles(delta)   # (also on the launch screen: the glider keeps its little idle animations)
	if state == STATE_FLIGHT and delta > 0.0:
		flight.advance(delta, is_holding())
		_handle_events()
		_flight_fx(delta)
		if flight.boost_left > 0.0:
			_boost_flames()
		if flight.phase == Flight.PH_AIR and Save.trail != "none":
			_trail_t -= delta
			if _trail_t <= 0.0:
				_trail_t = Tuning.trail_rate
				_spawn_trail()
		if flight.phase == Flight.PH_DONE and _finish_timer < 0.0:
			_finish_run()
		if _finish_timer >= 0.0:
			_finish_timer += delta
			if _finish_timer >= FINISH_DELAY:
				_to_shop(true, true)
				_maybe_interstitial()
	if state == STATE_FLIGHT and flight.phase == Flight.PH_AIM:
		hud.set_flight(0.0, flight.charges, flight.charges_max, false, false)
		hud.show_aim(true, flight.aim_power, flight.aim_angle)
	elif state == STATE_FLIGHT:
		hud.show_aim(false, 0.0, 0.0)
		hud.set_flight(flight.distance, flight.charges, flight.charges_max, flight.boost_left > 0.0, flight.stall_amount > 0.0, flight.band)
		_mission_toasts()
		if flight.phase == Flight.PH_AIR and flight.time_in_air > 4.0:
			hud.show_hint(false)
	_time += delta
	if state == STATE_SHOP and world.ambience and delta > 0.0:
		_grinder_t -= delta
		if _grinder_t <= 0.0:
			_grinder_t = 0.07 + rng.randf() * 0.1
			var gp := world.grinder_pos()
			for k in 2:
				world.spawn(WorldView.P_SPARK, gp.x, gp.y, 2.5 + rng.randf() * 3.0, 1.0 + rng.randf() * 3.5, 0.45, 0.14, Color(1.0, 0.75 + rng.randf() * 0.2, 0.3))
	_kick = maxf(_kick - delta * Tuning.boost_kick_decay, 0.0)
	world.boost_fx = clampf(flight.boost_left / maxf(Tuning.booster_time, 0.01), 0.0, 1.0) if state == STATE_FLIGHT else 0.0
	_update_camera(maxf(raw_delta, delta))
	_apply_camera()
	if DebugFlags.perf_enabled():
		hud.set_perf_extra("things %d  particles %d  spd %.0f alt %.0f  x %.0f" % [flight.thing_count, world.live_particles(), flight.speed(), flight.altitude(), flight.x])

## Brief toasts when a mission makes progress ("Bounces 2/3"); nothing permanent on the flight screen.
func _mission_toasts() -> void:
	for i in mini(Save.missions.size(), Missions.SLOTS):
		var mi: Dictionary = Save.missions[i]
		var t: String = mi["type"]
		if t == "noboost_zone" or t == "nobird":
			continue   # these can only be judged at the end of the flight
		var tgt := int(mi["target"])
		var cur := Missions.value_live(mi, flight)
		if t == "distance":
			var quarter := cur * 4 / maxi(tgt, 1)   # toast at half, three quarters and done
			if quarter > _toast_val[i] and quarter >= 2:
				_toast_val[i] = quarter
				hud.toast(Missions.progress_text(mi, cur) if quarter < 4 else "MISSION DONE: %s" % Missions.progress_text(mi, tgt))
			elif quarter > _toast_val[i]:
				_toast_val[i] = quarter
		elif cur > _toast_val[i]:
			_toast_val[i] = cur
			hud.toast(Missions.progress_text(mi, cur) if cur < tgt else "MISSION DONE: %s" % Missions.progress_text(mi, tgt))

# ---------------------------------------------------------------------------------------------
# Camera
# ---------------------------------------------------------------------------------------------

func _view_size() -> Vector2:
	return get_viewport_rect().size

func _update_camera(dt: float) -> void:
	var size := _view_size()
	var tx: float
	var tb: float
	var tp: float
	var kx: float
	var ky: float
	if state == STATE_SHOP:
		# Frame the ramp in the upper part of the screen, above the shop panel.
		var ramp_h := flight.ramp_top.y + 6.0
		var ground_sy := size.y - Hud.PANEL_H - 20.0   # just above the clipboard
		var avail := ground_sy - 170.0
		tp = minf(Tuning.view_scale, avail / ramp_h)
		tb = (ground_sy - size.y) / tp
		tx = flight.ramp_top.x - 6.0
		kx = 6.0
		ky = 6.0
	else:
		tp = Tuning.view_scale
		var view_w := size.x / tp
		var view_h := size.y / tp
		tx = flight.x - Tuning.glider_screen_x * view_w
		tb = maxf(-Tuning.ground_margin, flight.y - Tuning.glider_screen_y * view_h)
		kx = 8.0
		ky = Tuning.camera_follow
	if _snap_camera:
		cam_x = tx
		cam_bottom = tb
		cam_ppm = tp
		_snap_camera = false
		return
	var ax := 1.0 - exp(-kx * dt)
	var ay := 1.0 - exp(-ky * dt)
	cam_x = lerpf(cam_x, tx, ax)
	cam_bottom = lerpf(cam_bottom, tb, ay)
	cam_ppm = lerpf(cam_ppm, tp, 1.0 - exp(-4.0 * dt))

func _apply_camera() -> void:
	world.cam_x = cam_x - _kick * Tuning.boost_kick_m + sin(_time * 70.0) * 0.12 * _kick
	world.cam_bottom = cam_bottom + cos(_time * 83.0) * 0.1 * _kick
	world.ppm = cam_ppm * (1.0 + Tuning.boost_kick_zoom * _kick)

# ---------------------------------------------------------------------------------------------
# Effects from the simulation's events
# ---------------------------------------------------------------------------------------------

func _buzz(ms: int) -> void:
	if _touch_seen:
		Input.vibrate_handheld(ms)

func _handle_events() -> void:
	for k in flight.ev_n:
		var ex := flight.ev_x[k]
		var ey := flight.ev_y[k]
		match flight.ev_kind[k]:
			Flight.EV_SCRAP:
				world.burst(WorldView.P_SPARK, ex, ey, 5, 6.0, 0.4, 0.3, Hud.C_GOLD, rng)
				sfx.play_clink()
				var first_scrap := Save.mark_seen("scrap")
				if first_scrap or flight.ev_val[k] >= Tuning.scrap_gear_value:
					var scrap_text := "SCRAP! +%d" % flight.ev_val[k] if first_scrap else "+%d" % flight.ev_val[k]
					if flight.ev_aux[k] > 10:
						scrap_text += " " + Tuning.mult_text(flight.ev_aux[k] / 10.0)
					hud.popup(scrap_text, world.to_screen(ex, ey) + Vector2(0, -50), Hud.C_GOLD, "scrap")
				else:
					# nuts arrive in streams: one popup for a few of them ("+7 x2"), not a pile of little ones
					_scrap_sum += flight.ev_val[k]
					_scrap_mult = flight.ev_aux[k]
					_scrap_pos = world.to_screen(ex, ey) + Vector2(0, -50)
					if _scrap_t <= 0.0:
						_scrap_t = 0.3
			Flight.EV_PAD:
				world.burst(WorldView.P_RUBBER, ex, ey + 0.5, 8, 7.0, 0.5, 0.4, Color(0.2, 0.2, 0.22), rng)
				var pad_text := "BOUNCE! +speed" if Save.mark_seen("pad") else "BOUNCE! +%d m/s" % flight.ev_val[k]
				hud.popup(pad_text, world.to_screen(ex, ey) + Vector2(0, -160), Hud.C_ACCENT, "bounce")
				_buzz(25)
				sfx.play("boing")
				_dust_left = 0.6
			Flight.EV_BIRD:
				world.burst(WorldView.P_FEATHER, ex, ey, 9, 7.0, 0.8, 0.5, Color(0.8, 0.75, 0.95), rng)
				var bird_text := "BIRD! -speed" if Save.mark_seen("bird") else "BIRD! -%d m/s" % flight.ev_val[k]
				hud.popup(bird_text, world.to_screen(ex, ey) + Vector2(0, -100), Hud.C_DANGER, "nobird")
				_buzz(60)
				sfx.play("squawk", 0.9 + rng.randf() * 0.25)
			Flight.EV_FAN:
				sfx.play("fan")
				var fan_text := "UPDRAFT! +height" if Save.mark_seen("fan") else "UPDRAFT!"
				hud.popup(fan_text, world.to_screen(ex, ey) + Vector2(0, -140), Hud.C_TEXT, "updraft")
			Flight.EV_BOOST:
				_kick = 1.0
				sfx.play("boost")
				hud.popup("BOOST +%d m/s" % flight.ev_val[k], world.to_screen(ex, ey) + Vector2(0, -160), Hud.C_ACCENT, "boost")
				_buzz(40)
			Flight.EV_LAND:
				# a chunky crunch: a big burst of dust and bolts, a hard camera kick, then the glider tumbles along
				world.burst(WorldView.P_DUST, ex, 0.3, 16, 8.0, 0.9, 0.8, Color(0.7, 0.6, 0.45), rng)
				world.burst(WorldView.P_SCRAP, ex, 0.6, 12, 9.0, 1.0, 0.4, Color(0.6, 0.6, 0.62), rng)
				world.burst(WorldView.P_SPARK, ex, 0.4, 8, 7.0, 0.5, 0.3, Color(1.0, 0.8, 0.3), rng)
				_kick = 1.0
				sfx.play("crunch")
				_tumble_w = clampf(flight.vx * 0.3, 3.0, 10.0)
				_tumble_a = 0.0
				_hop_y = 0.0
				_hop_v = clampf(flight.vx * 0.12, 2.5, 7.0)
				_buzz(80)
			Flight.EV_ZONE:
				var zn := Tuning.zone_name(flight.ev_val[k])
				if flight.ev_val[k] > Save.zone_best:
					sfx.play("unlock")
					hud.banner("NEW ZONE!\n%s\n+%s scrap" % [zn.to_upper(), Tuning.fmt(Tuning.zone_bonus(flight.ev_val[k]))], Hud.C_ACCENT)
					_buzz(70)
				else:
					hud.banner(zn.to_upper(), Hud.C_TEXT)
			Flight.EV_SKIP:
				var cloud := flight.ev_val[k] == 2
				sfx.play("boing" if cloud else "splash")
				world.burst(WorldView.P_SPARK, ex, 0.4, 7, 6.0, 0.5, 0.35, Color(1, 1, 1) if cloud else Color(0.6, 0.85, 1.0), rng)
				var skip_text := ("BOING!" if cloud else "SKIP!") + (" +bounce" if Save.mark_seen("cloud" if cloud else "water") else "")
				hud.popup(skip_text, world.to_screen(ex, 1.5) + Vector2(0, -100), Hud.C_TEXT, "skip")
				_buzz(20)
				_dust_left = 0.4
			Flight.EV_LAUNCH:
				_launch_fx()
			Flight.EV_STALL:
				sfx.play("stall")
			Flight.EV_BALLOON:
				world.burst(WorldView.P_FEATHER, ex, ey, 7, 6.0, 0.7, 0.45, Color(1.0, 0.85, 0.7), rng)
				sfx.play("boing")
				hud.popup("BALLOON! bounce on its top" if Save.mark_seen("balloon") else "BALLOON! +%d" % flight.ev_aux[k], world.to_screen(ex, ey) + Vector2(0, -150), Hud.C_ACCENT, "balloon")
				_buzz(25)
			Flight.EV_RING:
				world.burst(WorldView.P_SPARK, ex, ey, 14, 9.0, 0.7, 0.4, Color(1.0, 0.8, 0.3), rng)
				sfx.play_accent("ring")
				_kick = maxf(_kick, 0.6)
				hud.popup("RING! fly through for speed" if Save.mark_seen("ring") else "RING! +%d" % flight.ev_aux[k], world.to_screen(ex, ey) + Vector2(0, -150), Hud.C_ACCENT, "ring")
				_buzz(30)
			Flight.EV_BLIMP:
				world.burst(WorldView.P_DUST, ex, ey, 6, 5.0, 0.5, 0.5, Color(1, 1, 1), rng)
				sfx.play_accent("skim")
				hud.popup("BLIMP! skim the top for speed" if Save.mark_seen("blimp") else "SKIM! +%d" % flight.ev_aux[k], world.to_screen(ex, ey) + Vector2(0, -150), Hud.C_ACCENT, "blimp")
				_buzz(30)
			Flight.EV_STORM:
				_kick = maxf(_kick, 0.4)
				sfx.play("storm")
				hud.popup("STORM! go over or under" if Save.mark_seen("storm") else "STORM!", world.to_screen(ex, ey) + Vector2(0, -140), Hud.C_DANGER, "highair")
				_buzz(50)
			Flight.EV_STREAM:
				sfx.play_accent("gust")
				hud.popup("TAILWIND! stay inside" if Save.mark_seen("stream") else "TAILWIND!", world.to_screen(ex, ey) + Vector2(0, -140), Hud.C_TEXT, "tailwind")
			Flight.EV_HAZARD:
				var goose: bool = flight.ev_aux[k] == Flight.K_GOOSE
				world.burst(WorldView.P_FEATHER, ex, ey, 7, 6.0, 0.7, 0.45, Color(0.85, 0.85, 0.9), rng)
				sfx.play("squawk" if goose else "stall")
				hud.popup(("FLOCK! -%d m/s" if goose else "KITE! -%d m/s") % flight.ev_val[k], world.to_screen(ex, ey) + Vector2(0, -100), Hud.C_DANGER, "nobird")
				_buzz(50)
			Flight.EV_FIND:
				world.burst(WorldView.P_SPARK, ex, ey, 24, 11.0, 1.0, 0.5, Color(1.0, 0.9, 0.4), rng)
				sfx.play_find()
				_kick = maxf(_kick, 0.8)
				hud.popup("%s! +%d" % [Tuning.FIND_NAMES[clampi(flight.ev_aux[k], 0, 3)], flight.ev_val[k]], world.to_screen(ex, ey) + Vector2(0, -150), Hud.C_GOLD, "find")
				_buzz(70)
			Flight.EV_BAND:
				var nb: int = flight.ev_val[k]
				sfx.play("band")
				hud.toast("%s AIR  %s" % [Tuning.BAND_NAMES[nb], Tuning.mult_text(Tuning.band_mult(nb))])
			Flight.EV_TARGET:
				hud.popup("TARGET REACHED!", Vector2(_view_size().x * 0.5, 330.0), Hud.C_ACCENT, "flag")
			Flight.EV_BEST:
				hud.popup("NEW BEST!", Vector2(_view_size().x * 0.5, 330.0), Hud.C_ACCENT, "trophy")
	if flight.chain >= 2 and flight.chain != _chain_shown:
		hud.toast("CHAIN x%d: +%d%% on prizes" % [flight.chain, int(Tuning.chain_bonus * 100.0) * (flight.chain - 1)])
	_chain_shown = flight.chain
	flight.ev_n = 0

## The launch, per launcher: ramp rumble (see frame), slingshot snap, catapult swing, rocket sled ignition.
func _launch_fx() -> void:
	match flight.launcher_id:
		"sling":
			var fork := Vector2(0.0, 5.0)
			sfx.play("snap")
			world.burst(WorldView.P_SPARK, fork.x, fork.y, 10, 8.0, 0.5, 0.3, Color(0.95, 0.4, 0.3), rng)
			_kick = 1.0
			_buzz(60)
		"catapult":
			sfx.play("swing")
			world.burst(WorldView.P_DUST, flight.pivot.x, 0.4, 12, 6.0, 0.8, 0.7, Color(0.7, 0.6, 0.45), rng)
			_kick = 0.5
			_buzz(40)
		"sled":
			sfx.play("ignite")
			world.burst(WorldView.P_FLAME, flight.x - 2.5, flight.y, 14, 7.0, 0.6, 1.0, Color(1.0, 0.6, 0.15), rng)
			world.burst(WorldView.P_DUST, flight.x - 2.5, flight.y, 10, 5.0, 0.9, 0.9, Color(0.75, 0.75, 0.78), rng)
			_kick = 0.7
			_buzz(60)
		_:
			world.burst(WorldView.P_DUST, flight.x, flight.y, 6, 4.0, 0.6, 0.5, Color(0.7, 0.6, 0.45), rng)
			_buzz(25)

## Off the lip: a camera kick and a puff, bigger for the bigger launchers.
func _lip_fx() -> void:
	var k := 0.7
	match flight.launcher_id:
		"sling":
			k = 0.8
		"catapult":
			k = 1.1
		"sled":
			k = 1.3
	_kick = maxf(_kick, k)
	world.burst(WorldView.P_DUST, flight.x, flight.y - 1.0, 8, 6.0, 0.6, 0.6, Color(0.8, 0.75, 0.65), rng)
	world.burst(WorldView.P_SPARK, flight.x, flight.y - 0.5, 6, 7.0, 0.4, 0.28, Color(1.0, 0.85, 0.4), rng)
	_buzz(45)

## Per-frame flight effects (all pooled particles): rumble, speed lines, wind, dust trail, the landing tumble.
func _flight_fx(delta: float) -> void:
	var ph := flight.phase
	if _scrap_t > 0.0:
		_scrap_t -= delta
		if _scrap_t <= 0.0 and _scrap_sum > 0:
			hud.popup("+%d%s" % [_scrap_sum, (" " + Tuning.mult_text(_scrap_mult / 10.0)) if _scrap_mult > 10 else ""], _scrap_pos, Hud.C_GOLD, "scrap")
			_scrap_sum = 0
	if _prev_phase == Flight.PH_RAMP and ph == Flight.PH_AIR:
		_lip_fx()
	_prev_phase = ph
	var rumbling := ph == Flight.PH_RAMP and (flight.launcher_id == "ramp" or flight.launcher_id == "sled")
	world.rumble = clampf(flight.ramp_speed / maxf(flight.lip_speed, 1.0), 0.25, 1.0) if rumbling else 0.0
	sfx.set_rumble(rumbling)
	if rumbling and flight.launcher_id == "sled":
		_smoke_t -= delta
		if _smoke_t <= 0.0:
			_smoke_t = 0.05
			world.spawn(WorldView.P_DUST, flight.x - 3.0, flight.y - 0.4, -4.0 - rng.randf() * 3.0, rng.randf() * 2.0, 0.7, 0.9, Color(0.8, 0.8, 0.82))
	var spd := flight.speed() if ph == Flight.PH_AIR else 0.0
	world.speed_fx = clampf((spd - 30.0) / 60.0, 0.0, 1.0)
	sfx.set_wind(clampf(spd / 90.0, 0.0, 1.0) if not paused else 0.0)
	var music_speed := flight.speed() if ph == Flight.PH_AIR or ph == Flight.PH_SLIDE else 0.0
	sfx.set_flight(music_speed, flight.band, ph == Flight.PH_READY or ph == Flight.PH_AIM or ph == Flight.PH_RAMP)
	if spd > 36.0:
		_wind_t -= delta
		if _wind_t <= 0.0:
			_wind_t = 0.05
			world.spawn(WorldView.P_WIND, flight.x + 4.0 + rng.randf() * 16.0, flight.y + (rng.randf() - 0.5) * 13.0, -spd * 0.25, 0.0, 0.5, 0.5, Color.WHITE)
	if _dust_left > 0.0:
		_dust_left -= delta
		_dust_t -= delta
		if _dust_t <= 0.0 and flight.altitude() < 6.0:
			_dust_t = 0.04
			world.spawn(WorldView.P_DUST, flight.x - 1.5, 0.35, -2.0, 1.0 + rng.randf(), 0.6, 0.7, Color(0.72, 0.62, 0.46))
	if ph == Flight.PH_SLIDE:
		_tumble_a += _tumble_w * delta
		_tumble_w *= maxf(1.0 - 2.4 * delta, 0.0)
		_hop_y += _hop_v * delta
		_hop_v -= 30.0 * delta
		if _hop_y <= 0.0:
			_hop_y = 0.0
			if _hop_v < -1.5:
				_hop_v = -_hop_v * 0.45
				world.burst(WorldView.P_SCRAP, flight.x, 0.5, 4, 6.0, 0.7, 0.35, Color(0.6, 0.6, 0.62), rng)
				world.burst(WorldView.P_DUST, flight.x, 0.3, 6, 5.0, 0.7, 0.6, Color(0.7, 0.6, 0.45), rng)
				_kick = maxf(_kick, 0.35)
			else:
				_hop_v = 0.0
		_dust_t -= delta
		if _dust_t <= 0.0:
			_dust_t = 0.045
			world.spawn(WorldView.P_DUST, flight.x - 1.2, 0.3, -3.0, 1.0 + rng.randf() * 2.0, 0.7, 0.8, Color(0.72, 0.62, 0.46))
	elif ph != Flight.PH_DONE:
		_tumble_a = 0.0
		_hop_y = 0.0
	world.tumble = _tumble_a
	world.hop = _hop_y

func _boost_flames() -> void:
	var c := cos(flight.theta)
	var s := sin(flight.theta)
	for k in 3:
		var jitter := (rng.randf() - 0.5) * 1.2
		world.spawn(WorldView.P_FLAME, flight.x - (2.6 + k * 0.5) * c - jitter * s, flight.y - (2.6 + k * 0.5) * s + jitter * c,
				-flight.vx * 0.12 - 4.0 * c, -flight.vy * 0.12 - 4.0 * s, 0.55, 1.0 - k * 0.2,
				Color(1.0, 0.45 + rng.randf() * 0.45, 0.08))

## One trail particle behind the glider, by the equipped trail.
func _spawn_trail() -> void:
	var c := cos(flight.theta)
	var s := sin(flight.theta)
	var px := flight.x - 2.8 * c
	var py := flight.y - 2.8 * s
	match Save.trail:
		"sparkle":
			world.spawn(WorldView.P_SPARK, px + (rng.randf() - 0.5) * 0.8, py + (rng.randf() - 0.5) * 0.8, -1.0, rng.randf() * 2.0, 0.5, 0.3, Color(1.0, 0.9, 0.35))
		"smoke":
			world.spawn(WorldView.P_DUST, px, py, -0.5, 0.8, 0.9, 0.9, Color(0.75, 0.75, 0.78))
		"bubbles":
			world.spawn(WorldView.P_BUBBLE, px + (rng.randf() - 0.5) * 0.6, py, -0.6, 0.5, 1.1, 0.6 + rng.randf() * 0.5, Color(0.7, 0.9, 1.0))
		"rainbow":
			world.spawn(WorldView.P_SPARK, px, py, 0.0, 0.0, 0.7, 0.55, Color.from_hsv(fmod(_time * 0.8, 1.0), 0.85, 1.0))
