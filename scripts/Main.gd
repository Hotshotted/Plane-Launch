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
var tune_panel: TunePanel
var rng := RandomNumberGenerator.new()

var state := STATE_SHOP
var last_result := {}          # distance, earned, dist_scrap, picked, picked_count, new_best
var runs_this_session := 0
var restart_count := 0

# camera (smoothed)
var cam_x := 0.0
var cam_bottom := 0.0
var cam_ppm := 28.0
var _snap_camera := true

# input
var _touch_hold := PackedByteArray()
var _touch_boost := PackedByteArray()
var _key_hold := false
var _touch_seen := false

# frame time
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
	hud = Hud.new()
	add_child(hud)
	hud.launch_pressed.connect(launch)
	hud.buy_pressed.connect(_on_buy)
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

func _prewarm() -> void:
	_warming = true
	hud.show_splash(true)
	hud.prewarm_show(true)
	if tune_panel:
		tune_panel.prewarm_show(true)
	var maxed := {}
	for u in Tuning.upgrades:
		maxed[u["id"]] = u["max"]
	flight.reset(maxed, 1)
	flight.best_x = 18.0
	flight.boost_left = 5.0
	flight.stall_amount = 1.0
	world.best_text = "BEST 99 m"
	world.show_aura = true
	for i in 6:
		flight.add_thing(Flight.K_NUT, -6.0 + i * 3.0, 20.0)
	flight.add_thing(Flight.K_GEAR, 10.0, 21.0)
	flight.add_thing(Flight.K_PAD, 4.0, 0.0)
	flight.add_thing(Flight.K_FAN, 9.0, 0.0)
	flight.add_thing(Flight.K_BIRD, 14.0, 12.0)
	cam_x = flight.ramp_top.x - 6.0
	cam_ppm = 20.0
	cam_bottom = -6.0
	_apply_camera()
	var t_start := Time.get_ticks_msec()
	var t_last := t_start
	var calm := 0
	var t_refresh := -100000
	while true:
		var now := Time.get_ticks_msec()
		if now - t_refresh > 300:
			t_refresh = now
			for k in 6:
				world.spawn(k, 4.0 + k * 3.0, 6.0, 1.0, 1.0, 0.6, 0.35, Color(1, 0.8, 0.3))
			for k in 4:
				hud.popup("BOUNCE! +%d" % (10 + k), Vector2(300 + k * 150, 800), Color.WHITE)
		world.update_particles(0.016)
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

# ---------------------------------------------------------------------------------------------
# State changes
# ---------------------------------------------------------------------------------------------

## Back to the shop with a fresh glider on the ramp (also run in place after a landing).
func _to_shop(snap: bool = true) -> void:
	state = STATE_SHOP
	_finish_timer = -1.0
	world.clear_particles()
	world.show_aura = false
	flight.reset(Save.levels)
	flight.best_x = Save.best_distance
	_set_best_text()
	hud.set_mode(Hud.MODE_SHOP)
	hud.refresh_shop(last_result)
	_snap_camera = snap or _snap_camera

func _set_best_text() -> void:
	world.best_x = Save.best_distance
	world.best_text = "BEST %s m" % Tuning.fmt(Save.best_distance) if Save.best_distance > 0.0 else ""
	hud.set_best(Save.best_distance)

## LAUNCH pressed: start a run, in place.
func launch() -> void:
	if state != STATE_SHOP or _warming:
		return
	state = STATE_FLIGHT
	restart_count += 1
	_skip_frames = Tuning.resume_skip_frames
	_note_event("run started")
	flight.reset(Save.levels)
	flight.best_x = Save.best_distance
	_set_best_text()
	world.clear_particles()
	world.show_aura = flight.lv_magnet > 0
	for i in MAX_TOUCHES:
		_touch_hold[i] = 0
		_touch_boost[i] = 0
	hud.set_mode(Hud.MODE_FLIGHT)
	hud.show_hint(Save.runs < 2)
	flight.launch()

func _finish_run() -> void:
	var earned := flight.scrap_total()
	var new_best := Save.record_run(flight.distance, earned)
	runs_this_session += 1
	last_result = {
		"distance": floorf(flight.distance), "earned": earned, "dist_scrap": flight.scrap_for_distance(),
		"picked": flight.picked_value, "picked_count": flight.picked_count, "new_best": new_best,
	}
	_finish_timer = 0.0

func _on_buy(id: String) -> void:
	if state == STATE_SHOP:
		Save.buy(id)

func _on_save_changed() -> void:
	if state == STATE_SHOP and not _warming:
		flight.reset(Save.levels)
		flight.best_x = Save.best_distance
		hud.refresh_shop(last_result)

func _on_tuning_changed(_property: String) -> void:
	flight.refresh_derived()
	if state == STATE_SHOP:
		flight.reset(Save.levels)
		hud.refresh_shop(last_result)

# ---------------------------------------------------------------------------------------------
# Input
# ---------------------------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_touch_seen = true
		var i: int = event.index
		if i < 0 or i >= MAX_TOUCHES:
			return
		if not event.pressed:
			_touch_hold[i] = 0
			_touch_boost[i] = 0
			return
		if state != STATE_FLIGHT or TunePanel.button_hit(event.position):
			return
		if hud.boost_rect().has_point(event.position):
			_touch_boost[i] = 1
			flight.boost()
		else:
			_touch_hold[i] = 1
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_B or event.keycode == KEY_SHIFT:
			if state == STATE_FLIGHT:
				flight.boost()
		elif (event.keycode == KEY_ENTER or event.keycode == KEY_SPACE) and state == STATE_SHOP and not (tune_panel and tune_panel.is_open):
			launch()

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
		NOTIFICATION_APPLICATION_FOCUS_IN, NOTIFICATION_APPLICATION_RESUMED, NOTIFICATION_WM_WINDOW_FOCUS_IN:
			if _suspended:
				_suspended = false
				_skip_frames = Tuning.resume_skip_frames
				clear_input()
				_note_event("window came back")

func _process(raw_delta: float) -> void:
	_key_hold = Input.is_key_pressed(KEY_SPACE) or Input.is_key_pressed(KEY_UP)
	if _warming:
		return
	frame(_frame_delta(raw_delta), raw_delta)

## One frame of the game with `delta` seconds of simulation (0 = nothing moves, e.g. a skipped frame).
## Public so tests can step the game with fixed time.
func frame(delta: float, raw_delta: float = 0.0) -> void:
	if state == STATE_FLIGHT and delta > 0.0:
		flight.advance(delta, is_holding())
		_handle_events()
		world.update_particles(delta)
		if flight.boost_left > 0.0:
			_boost_flames()
		if flight.phase == Flight.PH_DONE and _finish_timer < 0.0:
			_finish_run()
		if _finish_timer >= 0.0:
			_finish_timer += delta
			if _finish_timer >= FINISH_DELAY:
				_to_shop()
	if state == STATE_FLIGHT:
		hud.set_flight(flight.distance, flight.picked_value, flight.speed(), flight.altitude(),
				flight.stall_amount > 0.0, flight.charges, flight.charges_max, flight.boost_left > 0.0)
		if flight.phase == Flight.PH_AIR and flight.time_in_air > 4.0:
			hud.show_hint(false)
	_update_camera(maxf(raw_delta, delta))
	_apply_camera()
	if DebugFlags.perf_enabled():
		hud.set_perf_extra("things %d  particles %d  spd %.0f alt %.0f  x %.0f" % [flight.thing_count, world.live_particles(), flight.speed(), flight.altitude(), flight.x])

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
		var avail := 640.0
		tp = minf(Tuning.view_scale, avail / ramp_h)
		var ground_sy := minf(790.0, avail + 150.0)
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
	world.cam_x = cam_x
	world.cam_bottom = cam_bottom
	world.ppm = cam_ppm

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
				world.burst(WorldView.P_SPARK, ex, ey, 5, 6.0, 0.4, 0.3, Color(1.0, 0.9, 0.4), rng)
				hud.popup("+%d" % flight.ev_val[k], world.to_screen(ex, ey) + Vector2(0, -50), Color(1, 0.9, 0.4))
			Flight.EV_PAD:
				world.burst(WorldView.P_RUBBER, ex, ey + 0.5, 8, 7.0, 0.5, 0.4, Color(0.2, 0.2, 0.22), rng)
				hud.popup("BOUNCE!", world.to_screen(ex, ey) + Vector2(0, -120), Color(1.0, 0.6, 0.2))
				_buzz(25)
			Flight.EV_BIRD:
				world.burst(WorldView.P_FEATHER, ex, ey, 9, 7.0, 0.8, 0.5, Color(0.8, 0.75, 0.95), rng)
				hud.popup("BIRD!", world.to_screen(ex, ey) + Vector2(0, -100), Color(1.0, 0.35, 0.3))
				_buzz(60)
			Flight.EV_BOOST:
				hud.popup("BOOST!", world.to_screen(ex, ey) + Vector2(0, -140), Color(1.0, 0.8, 0.2))
			Flight.EV_LAND:
				world.burst(WorldView.P_DUST, ex, 0.3, 10, 6.0, 0.7, 0.6, Color(0.7, 0.6, 0.45), rng)
				world.burst(WorldView.P_SCRAP, ex, 0.6, 5, 7.0, 0.8, 0.35, Color(0.6, 0.6, 0.62), rng)
				_buzz(80)
			Flight.EV_BEST:
				hud.popup("NEW BEST!", Vector2(_view_size().x * 0.5, 330.0), Color(1.0, 0.95, 0.4))
	flight.ev_n = 0

func _boost_flames() -> void:
	var c := cos(flight.theta)
	var s := sin(flight.theta)
	world.spawn(WorldView.P_FLAME, flight.x - 3.0 * c, flight.y - 3.0 * s, -flight.vx * 0.2 - 3.0 * c, -flight.vy * 0.2 - 3.0 * s, 0.35, 0.7, Color(1.0, 0.6 + rng.randf() * 0.3, 0.1))
