extends SceneTree
## Headless smoke test:  godot --headless --path . --script res://tests/smoke_test.gd
## Exits with code 1 if anything below fails (CI runs this before exporting).
##   1. boot: the splash pre-warm draws everything, lasts long enough, then hands over to the shop
##   2. glide physics: diving gains speed, climbing trades it away, too slow stalls, pads bounce, fans lift,
##      birds slow, scrap is collected (the magnet reaches further), the booster pushes, touchdown ends the run
##   3. upgrades: Ramp, Wings, Body and Booster each clearly add distance; early runs are short
##   4. game loop: LAUNCH -> fly with real touch events -> touchdown -> result + shop -> buy -> LAUNCH again,
##      three runs in place, and NO new nodes or resources are created after the first one
##   5. the BOOST button takes touches without pitching; the best distance sets the marker in the world
##   6. save: versioned round trip, corrupt file falls back to defaults
##   7. ?tune panel: opens over the paused game, sliders edit Tuning live, Copy and Reset work, absent without ?tune
##   8. ?perf / ?tune / ?noprewarm flags parse

var failures: Array[String] = []
var tn: Node
var sv: Node
var FlightS: GDScript

func check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		failures.append(what)

func real_wait(sec: float) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < sec * 1000.0:
		await process_frame

func snapshot(n: Node) -> Dictionary:
	var nodes := {}
	_walk(n, nodes)
	return {"nodes": nodes, "node_count": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
			"resource_count": Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)}

func _walk(n: Node, nodes: Dictionary) -> void:
	nodes[n.get_instance_id()] = true
	for c in n.get_children():
		_walk(c, nodes)

func same_world(a: Dictionary, b: Dictionary) -> bool:
	return a["nodes"].hash() == b["nodes"].hash() and a["node_count"] == b["node_count"] and a["resource_count"] == b["resource_count"]

func describe(a: Dictionary) -> String:
	return "%d nodes, %d engine nodes, %d resources" % [a["nodes"].size(), a["node_count"], a["resource_count"]]

func lv(r := 0, w := 0, b := 0, bo := 0, m := 0) -> Dictionary:
	return {"ramp": r, "wings": w, "body": b, "booster": bo, "magnet": m}

## A fresh Flight already in the air at the given state (no ramp), for the physics rules.
func air(x := 0.0, y := 200.0, vx := 20.0, vy := 0.0, theta_deg := 0.0, levels := {}):
	var f = FlightS.new()
	f.reset(levels if not levels.is_empty() else lv(), 5)
	f.clear_things()
	f.gen_x = 1.0e9      # no random world
	f.phase = FlightS.PH_AIR
	f.x = x
	f.y = y
	f.vx = vx
	f.vy = vy
	f.theta = deg_to_rad(theta_deg)
	return f

func run_pilot(levels: Dictionary, seed_value: int, skill: float = 1.0):
	var f = FlightS.new()
	f.reset(levels, seed_value)
	f.launch_auto()
	var t := 0.0
	while not f.is_over() and t < 150.0:
		f.advance(1.0 / 60.0, f.pilot(1.0 / 60.0, skill))
		f.ev_n = 0
		t += 1.0 / 60.0
	return f

func avg_distance(levels: Dictionary, seeds: int = 3) -> float:
	var sum := 0.0
	for s in seeds:
		sum += run_pilot(levels, 100 + s).distance
	return sum / seeds

## The distinct font sizes of the labels and buttons currently visible under `n`.
func font_sizes(n: Node, out: Dictionary) -> void:
	if n is Control and not (n as Control).visible:
		return
	if n is Label or n is Button:
		out[(n as Control).get_theme_font_size("font_size")] = true
	for c in n.get_children():
		font_sizes(c, out)

## The visible Labels under `n` that have some text.
func visible_texts(n: Node, out: Array) -> void:
	if n is Control and not (n as Control).visible:
		return
	if n is Label and (n as Label).text != "":
		out.append(n)
	for c in n.get_children():
		visible_texts(c, out)

func total_levels() -> int:
	var n := 0
	for u in tn.upgrades:
		n += sv.level(u["id"])
	return n

func touch(main: Node, pos: Vector2, pressed: bool, index: int = 0) -> void:
	var ev := InputEventScreenTouch.new()
	ev.index = index
	ev.position = pos
	ev.pressed = pressed
	main._input(ev)

## Fly the main scene's current run with fixed 1/60 s frames and a holding finger driven by the pilot.
func fly_main(main: Node, max_seconds: float = 120.0) -> float:
	var t := 0.0
	var finger := false
	while main.state == main.STATE_FLIGHT and t < max_seconds:
		var want: bool = main.flight.pilot(1.0 / 60.0, 1.0)
		if want and not finger:
			touch(main, Vector2(500, 900), true)
			finger = true
		elif not want and finger:
			touch(main, Vector2(500, 900), false)
			finger = false
		main.frame(1.0 / 60.0, 1.0 / 60.0)
		t += 1.0 / 60.0
	if finger:
		touch(main, Vector2(500, 900), false)
	return t

func _initialize() -> void:
	var HudIntro: GDScript = load("res://scripts/Hud.gd")
	HudIntro.intro_enabled = false
	HudIntro.animate = false     # transitions complete instantly (a section below turns them on)
	tn = root.get_node("Tuning")
	sv = root.get_node("Save")
	FlightS = load("res://scripts/Flight.gd")
	sv.path = "user://smoke_test_save.json"   # never touch a real save
	sv.reset_all()
	tn.ads_enabled = false       # (the fake ad screens are tested on their own, in 2i)
	tn.ad_seconds = 0.05
	DebugFlags.parse(["tune"])   # the whole run has the tuning panel, so it is part of the "nothing new" baseline

	print("1. boot and the visible pre-warm")
	var t_boot := Time.get_ticks_msec()
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	await process_frame
	await process_frame
	check(main._warming, "pre-warm is running at boot")
	check(main.hud._splash.visible, "splash screen is shown during the pre-warm")
	check(main.hud._flight_root.visible and main.hud._shop_root.visible, "every UI part is drawn during the pre-warm")
	check(main.flight.thing_count >= 10 and main.world.live_particles() > 0, "world things and particles are drawn during the pre-warm")
	check(main.tune_panel != null and main.tune_panel._panel.visible and main.tune_panel._panel_layer.layer == 0,
			"?tune: the panel is drawn during the pre-warm, under the splash (layer 0)")
	check(not main.tune_panel._button.visible, "?tune: the TUNE button stays hidden while starting up")
	while main._warming and Time.get_ticks_msec() - t_boot < 15000:
		await process_frame
	var boot_s := (Time.get_ticks_msec() - t_boot) / 1000.0
	check(not main._warming, "pre-warm finishes (%.1f s)" % boot_s)
	check(boot_s >= tn.prewarm_min_seconds, "pre-warm lasts at least prewarm_min_seconds")
	check(not main.hud._splash.visible and main.state == main.STATE_SHOP and main.hud._shop_root.visible and not main.hud._flight_root.visible,
			"the shop is shown after the pre-warm")
	check(main.tune_panel._button.visible and not main.tune_panel._panel.visible, "?tune: TUNE button shows, panel hidden, after start-up")
	check(main.flight.phase == FlightS.PH_READY and main.flight.thing_count == 0, "a fresh glider waits on the ramp, world empty")
	check(main.hud._row_btn.size() == 5, "the shop lists 5 upgrades")

	print("2. glide physics")
	var f = air(0, 200, 15, 0, -30)
	var s0: float = f.speed()
	f.advance(2.0, false)
	check(f.speed() > s0 + 5.0, "diving gains speed (%.1f -> %.1f m/s)" % [s0, f.speed()])
	f = air(0, 200, 30, 0, 20)
	s0 = f.speed()
	var y0: float = f.y
	f.advance(2.0, true)
	check(f.speed() < s0 - 5.0 and f.y > y0 + 5.0, "climbing trades speed for height (%.1f -> %.1f m/s, +%.0f m)" % [s0, f.speed(), f.y - y0])
	f = air(0, 200, 8, 0, 25)
	f.advance(0.4, true)
	check(f.stall_amount > 0.0, "too slow with the nose up stalls")
	var f2 = air(0, 200, 8, 0, 25)
	f2.advance(1.5, true)
	var f3 = air(0, 200, 8, 0, 25)
	f3.advance(1.5, false)
	check(f2.vy < -3.0, "a stalled glider falls (vy %.1f)" % f2.vy)
	f = air(0, 1.2, 12, -8, -10)
	f.add_thing(FlightS.K_PAD, 1.0, 0.0)
	f.advance(0.1, false)
	check(f.vy > tn.pad_min_kick - 2.0 and f.pad_bounces == 1, "a bounce pad throws the glider up (vy %.1f)" % f.vy)
	var fa = air(0, 3.0, 18, 0, 0)
	fa.add_thing(FlightS.K_FAN, 4.0, 0.0)
	var fb = air(0, 3.0, 18, 0, 0)
	fa.advance(0.5, false)
	fb.advance(0.5, false)
	check(fa.y > fb.y + 1.0, "an updraft fan lifts (%.1f vs %.1f m)" % [fa.y, fb.y])
	f = air(0, 30, 20, 0, 0)
	f.add_thing(FlightS.K_BIRD, 3.0, 30.0, 0.0)
	var sp0: float = f.speed()
	f.advance(0.3, false)
	check(f.bird_hits == 1 and f.speed() < sp0 * 0.85, "a bird slows you (%.1f -> %.1f)" % [sp0, f.speed()])
	f = air(0, 30, 15, 0, 0)
	f.add_thing(FlightS.K_NUT, 4.0, 30.0)
	f.add_thing(FlightS.K_GEAR, 8.0, 29.3)
	f.advance(1.2, false)
	check(f.picked_value == tn.scrap_nut_value + tn.scrap_gear_value, "scrap in the glider's path is collected (%d)" % f.picked_value)
	f = air(0, 30, 15, 0, 0)
	f.add_thing(FlightS.K_NUT, 8.0, 34.5)
	f.advance(0.8, true)
	var no_magnet: int = f.picked_value
	f = air(0, 30, 15, 0, 0, lv(0, 0, 0, 0, 8))
	f.add_thing(FlightS.K_NUT, 8.0, 34.5)
	f.advance(0.8, true)
	check(no_magnet == 0 and f.picked_value == tn.scrap_nut_value, "the Scrap Magnet pulls in scrap the glider would miss")
	check(tn.magnet_radius(8) > tn.magnet_radius(0) * 3.0, "magnet reach grows a lot with levels")
	f = air(0, 100, 20, 0, 0, lv(0, 0, 0, 3, 0))
	var charges0: int = f.charges
	var sp1: float = f.speed()
	check(f.boost() and f.charges == charges0 - 1 and not f.boost(), "BOOST uses one charge and ignores a second tap while firing")
	f.advance(0.6, false)
	var sp_noboost = air(0, 100, 20, 0, 0, lv(0, 0, 0, 3, 0))
	sp_noboost.advance(0.6, false)
	check(f.speed() > sp_noboost.speed() + 1.5, "a boost pushes the glider (%.1f vs %.1f m/s)" % [f.speed(), sp_noboost.speed()])
	f = air(37.0, 4.0, 14, -6, -20)
	f.advance(1.0, false)
	check(f.is_over() or f.phase == FlightS.PH_SLIDE, "touching the ground ends the flight")
	check(absf(f.distance - 37.0) < 20.0 and f.distance > 37.0, "distance is where it touched down (%.1f m)" % f.distance)
	f = run_pilot(lv(), 3)
	check(f.is_over() and f.scrap_total() == f.scrap_for_distance() + f.picked_value, "a pilot run ends and its scrap adds up")

	print("2b. clarity and boost")
	f = air(0, 3.0, 18, 0, 0)
	f.add_thing(FlightS.K_FAN, 4.0, 0.0)
	var got_fan := false
	for i in 60:
		f.step(1.0 / 120.0, false)
		for k in f.ev_n:
			if f.ev_kind[k] == FlightS.EV_FAN:
				got_fan = true
	check(got_fan, "flying into an updraft raises an event")
	f = air(0, 1.2, 12, -8, -10)
	f.add_thing(FlightS.K_PAD, 1.0, 0.0)
	f.advance(0.1, false)
	var pad_gain := 0
	var bird_loss := 0
	for k in f.ev_n:
		if f.ev_kind[k] == FlightS.EV_PAD:
			pad_gain = f.ev_val[k]
	check(pad_gain > 5, "a bounce reports the speed it gave (+%d m/s)" % pad_gain)
	f = air(0, 30, 20, 0, 0)
	f.add_thing(FlightS.K_BIRD, 3.0, 30.0, 0.0)
	f.advance(0.3, false)
	for k in f.ev_n:
		if f.ev_kind[k] == FlightS.EV_BIRD:
			bird_loss = f.ev_val[k]
	check(bird_loss > 3, "a bird hit reports the speed it cost (-%d m/s)" % bird_loss)
	f = air(0, 100, 20, 0, 0, lv(0, 0, 0, 3, 0))
	f.boost()
	var boost_val := 0
	for k in f.ev_n:
		if f.ev_kind[k] == FlightS.EV_BOOST:
			boost_val = f.ev_val[k]
	check(boost_val == roundi(tn.booster_thrust(3) * tn.booster_time) and boost_val > 3, "a boost reports the speed it adds (+%d m/s)" % boost_val)
	check(tn.upgrade_cost("booster", 0) >= 80.0 and tn.upgrade_cost("booster", 3) > tn.upgrade_cost("ramp", 3) * 1.5, "Booster is the pricey upgrade (%.0f scrap for the first)" % tn.upgrade_cost("booster", 0))
	sv.reset_all()
	check(sv.mark_seen("pad") and not sv.mark_seen("pad"), "a first-time popup is announced once")
	sv.record_run(10.0, 5.0)
	sv.load_game()
	check(sv.seen.has("pad") and not sv.mark_seen("pad"), "...and remembered across saves")
	sv.reset_all()
	main._to_shop()
	main.hud._launch_btn.pressed.emit()
	for i in 20:
		main.frame(1.0 / 60.0, 1.0 / 60.0)
	main.flight.push_event(FlightS.EV_PAD, main.flight.x, 1.0, 9)
	main._handle_events()
	var latest: String = main.hud._pop_labels[(main.hud._next_pop + main.hud.POPUPS - 1) % main.hud.POPUPS].text
	check(latest == "BOUNCE! +speed", "the first bounce names its effect (%s)" % latest)
	main.flight.push_event(FlightS.EV_PAD, main.flight.x, 1.0, 9)
	main._handle_events()
	latest = main.hud._pop_labels[(main.hud._next_pop + main.hud.POPUPS - 1) % main.hud.POPUPS].text
	check(latest == "BOUNCE! +9 m/s", "later bounces show the number (%s)" % latest)
	main.flight.push_event(FlightS.EV_FAN, main.flight.x, 5.0)
	main._handle_events()
	latest = main.hud._pop_labels[(main.hud._next_pop + main.hud.POPUPS - 1) % main.hud.POPUPS].text
	check(latest == "UPDRAFT! +height", "the first updraft names its effect (%s)" % latest)
	main.flight.push_event(FlightS.EV_BIRD, main.flight.x, 5.0, 4)
	main._handle_events()
	latest = main.hud._pop_labels[(main.hud._next_pop + main.hud.POPUPS - 1) % main.hud.POPUPS].text
	check(latest == "BIRD! -speed", "the first bird names its effect (%s)" % latest)
	fly_main(main)
	sv.reset_all()
	sv.levels["booster"] = 3
	main._to_shop()
	main.hud._launch_btn.pressed.emit()
	for i in 90:
		main.frame(1.0 / 60.0, 1.0 / 60.0)
	check(main.hud._boost_pips.visible and main.hud._boost_pips.text == "●●●", "boost charges show as pips beside the button (%s)" % main.hud._boost_pips.text)
	var rect_b: Rect2 = main.hud.boost_rect()
	var cam0: float = main.world.cam_x
	touch(main, rect_b.get_center(), true, 4)
	touch(main, rect_b.get_center(), false, 4)
	main.frame(1.0 / 60.0, 1.0 / 60.0)
	check(main._kick > 0.8 and main.world.boost_fx > 0.5, "a boost kicks the camera and starts the speed lines")
	check(main.hud._boost_pips.text == "●●○", "a charge is spent (%s)" % main.hud._boost_pips.text)
	var flames: int = main.world.live_particles()
	check(flames >= 3, "the flame trail spawns particles (%d)" % flames)
	for i in 120:
		main.frame(1.0 / 60.0, 1.0 / 60.0)
	check(main._kick == 0.0 and main.world.boost_fx == 0.0, "the kick and speed lines die away")
	fly_main(main)
	sv.reset_all()
	main._to_shop()

	print("2c. zones")
	check(Zones.COUNT == 11 and Zones.list.size() == 11 and Zones.list[0]["name"] == "Junkyard" and Zones.list[1]["name"] == "Farmland" and Zones.list[2]["name"] == "River" and Zones.list[3]["name"] == "Town" and Zones.list[4]["name"] == "Hills" and Zones.list[5]["name"] == "City" and Zones.list[6]["name"] == "Coast", "the journey starts Junkyard, Farmland, River, Town, Hills, City, Coast")
	var zones_ok := true
	for i in range(1, Zones.COUNT):
		if not (Zones.list[i]["start"] > Zones.list[i - 1]["start"] and Zones.list[i]["bonus"] > Zones.list[i - 1]["bonus"] and Zones.list[i]["pal"].size() == 10):
			zones_ok = false
	check(zones_ok and Zones.list[0]["start"] == 0.0, "zones get farther apart and richer, each with a full palette")
	check(tn.zone_index(0.0) == 0 and tn.zone_index(149.9) == 0 and tn.zone_index(150.0) == 1 and tn.zone_index(99999.0) == 10, "zone lookup by distance")
	f = air(140.0, 40.0, 25, 0, 0)
	var zone_events := 0
	var zone_val := -1
	for i in 120:
		f.step(1.0 / 120.0, false)
		for k in f.ev_n:
			if f.ev_kind[k] == FlightS.EV_ZONE:
				zone_events += 1
				zone_val = f.ev_val[k]
		f.ev_n = 0
	check(zone_events == 1 and zone_val == 1 and f.zone == 1 and f.zone_max == 1, "crossing into Farmland raises one zone event")
	f = air(400.0, 0.62, 18, -3, 0)
	f.advance(0.05, false)
	check(f.skips == 1 and f.vy > 0.0 and not f.is_over() and f.phase == FlightS.PH_AIR, "River: skimming the water skips you back up (vy %.1f)" % f.vy)
	f = air(400.0, 0.62, 18, -13, -10)
	f.advance(0.1, false)
	check(f.phase != FlightS.PH_AIR and f.skips == 0, "River: a steep dive sinks")
	f = air(400.0, 0.62, 6, -2, 0)
	f.advance(0.1, false)
	check(f.phase != FlightS.PH_AIR, "River: too slow to skip, you sink")
	f = air(2300.0, 0.62, 18, -3, 0)
	f.advance(0.05, false)
	check(f.skips == 1, "Coast: the sea skips too")
	f = air(3100.0, 0.62, 16, -10, -10)
	f.advance(0.05, false)
	check(f.skips == 1 and f.vy > 5.0 and f.phase == FlightS.PH_AIR, "Cloud Kingdom: the ground is bouncy (vy %.1f)" % f.vy)
	f = air(100.0, 0.62, 16, -3, 0)
	f.advance(0.05, false)
	check(f.phase != FlightS.PH_AIR, "Junkyard: dirt ends the run")
	var fm = air(4100.0, 200.0, 10, 0, 0)
	var fe = air(100.0, 200.0, 10, 0, 0)
	fm.advance(1.0, false)
	fe.advance(1.0, false)
	check(absf(fm.vy) < absf(fe.vy) * 0.8, "Cheese Moon: low gravity (vy %.1f vs %.1f)" % [fm.vy, fe.vy])
	f = air(1600.0, 11.4, 14, -5, -5)
	f.add_thing(FlightS.K_PAD, 1601.0, 10.0)
	f.advance(0.1, false)
	check(f.pad_bounces == 1 and f.vy > 5.0, "City: a rooftop pad bounces you (base 10 m)")
	f = air(1600.0, 2.0, 14, -2, -5)
	f.add_thing(FlightS.K_PAD, 1601.0, 10.0)
	f.advance(0.3, false)
	check(f.pad_bounces == 0, "...but you do not bounce off a rooftop from the street")
	var fv = air(1600.0, 13.0, 14, 0, 0)
	fv.add_thing(FlightS.K_FAN, 1600.0, 10.0)
	var fvn = air(1600.0, 13.0, 14, 0, 0)
	fv.advance(0.2, false)
	fvn.advance(0.2, false)
	check(fv.y > fvn.y + 0.3, "City: a heat vent on a roof lifts you (%.1f vs %.1f m)" % [fv.y, fvn.y])
	var roof_pads := 0
	var street_pads := 0
	var river_pads := 0
	var junk_pads := 0
	for z_start in [1600.0, 700.0, 380.0, 20.0]:
		f = air(0, 50, 20)
		f.rng.seed = 11
		for c in 60:
			f.clear_things()
			f.gen_x = z_start
			f._gen_chunk()
			for i in FlightS.MAX_THINGS:
				if f.t_active[i] != 0 and f.t_kind[i] == FlightS.K_PAD:
					if z_start == 1600.0 and f.t_y[i] >= 6.0:
						roof_pads += 1
					if z_start == 700.0 and f.t_y[i] >= 3.0 and f.t_y[i] <= 6.0:
						street_pads += 1
					if z_start == 380.0:
						river_pads += 1
					if z_start == 20.0:
						junk_pads += 1
	check(roof_pads > 3 and street_pads > 3, "City and Town generate raised pads (%d roof, %d awning)" % [roof_pads, street_pads])
	check(river_pads * 3 < junk_pads, "the River has far fewer pads than the Junkyard (%d vs %d)" % [river_pads, junk_pads])
	sv.reset_all()
	var claim: Dictionary = sv.claim_zones(2)
	check(claim["bonus"] == tn.zone_bonus(1) + tn.zone_bonus(2) and claim["new"] == 2 and sv.zone_best == 2, "reaching new zones pays their bonuses (%d scrap)" % claim["bonus"])
	check(sv.claim_zones(2)["bonus"] == 0 and sv.claim_zones(1)["bonus"] == 0, "...only once")
	check(tn.zone_bonus(1) > 100, "a zone bonus is large next to a first run (%d vs ~40 scrap)" % tn.zone_bonus(1))
	sv.reset_all()
	main._to_shop()
	main.hud._launch_btn.pressed.emit()
	main.flight.zone_max = 1
	fly_main(main)
	check(main.last_result["zone_bonus"] == tn.zone_bonus(1) and main.last_result["zone"] == 1 and sv.zone_best == 1 and main.hud.result_text().contains("zone bonus"), "a run into Farmland pays the bonus at the end and says so")
	main.hud._launch_btn.pressed.emit()
	main.flight.zone_max = 1
	fly_main(main)
	check(main.last_result["zone_bonus"] == 0, "the same zone pays nothing the second time")
	sv.reset_all()
	main._to_shop()
	main.hud._launch_btn.pressed.emit()
	for i in 10:
		main.frame(1.0 / 60.0, 1.0 / 60.0)
	main.flight.push_event(FlightS.EV_ZONE, main.flight.x, 10.0, 1)
	main._handle_events()
	check(main.hud._banner.visible and main.hud._banner.text.contains("NEW ZONE!") and main.hud._banner.text.contains("FARMLAND"), "a new zone shows a banner with its bonus (%s)" % main.hud._banner.text.replace("\n", " | "))
	sv.zone_best = 1
	main.flight.push_event(FlightS.EV_ZONE, main.flight.x, 10.0, 1)
	main._handle_events()
	check(main.hud._banner.text == "FARMLAND", "an old zone only shows its name")
	sv.zone_best = 2
	sv.best_distance = 400.0
	main.hud.refresh_shop(main.last_result)
	var fills: Array = main.hud._shop_bar["fills"]
	check(fills[0].anchor_right == 1.0 and fills[2].anchor_right == 1.0 and fills[3].anchor_right > 0.0 and fills[3].anchor_right < 1.0 and fills[5].anchor_right == 0.0, "the zone bar on the launch screen marks the zones reached and fills toward the next")
	check(main.hud._zone_label.text == "RIVER", "the farthest zone is named on the launch screen")
	fly_main(main)
	var pal_ok := true
	for z in range(1, Zones.COUNT):
		var zx: float = tn.zone_start(z)
		var w: Node2D = main.world
		w._size = Vector2(1080, 1920)
		w._ppm = 28.0
		w.cam_x = zx - 540.0 / 28.0 - 1.0
		w._update_palette()
		var before: Color = w._pal[1]
		w.cam_x = zx - 540.0 / 28.0 + 1.0
		w._update_palette()
		var after: Color = w._pal[1]
		w.cam_x = zx - 540.0 / 28.0 + 200.0
		w._update_palette()
		var far_after: Color = w._pal[1]
		var target: Color = Zones.list[z]["pal"][1]
		if z != 10 and (absf(before.r - after.r) + absf(before.g - after.g) + absf(before.b - after.b) > 0.06 or absf(far_after.r - target.r) + absf(far_after.g - target.g) > 0.01):
			pal_ok = false
	check(pal_ok, "the sky fades smoothly across every zone border and settles on the zone's colours")
	check(main.prewarm_zones_seen.size() == Zones.COUNT, "the pre-warm drew every zone's scenery (%d zones)" % main.prewarm_zones_seen.size())
	sv.reset_all()
	main._to_shop()

	print("2d. missions and Rusty")
	var MissionsS: GDScript = load("res://scripts/Missions.gd")
	var RustyS: GDScript = load("res://scripts/Rusty.gd")
	var mrng := RandomNumberGenerator.new()
	mrng.seed = 5
	sv.reset_all()
	check(sv.missions.is_empty(), "a fresh save has no missions yet")
	sv.ensure_missions(mrng)
	var types := {}
	var all_ok := true
	for m in sv.missions:
		types[m["type"]] = true
		if m["target"] <= 0 or m["reward"] <= 0 or MissionsS.describe(m).contains("?") or MissionsS.describe(m) == "":
			all_ok = false
	check(sv.missions.size() == 3 and types.size() == 3 and all_ok, "three different, readable missions with rewards")
	var never_seen := true
	for i in 200:
		var mm: Dictionary = MissionsS.pick(sv, sv.missions, mrng)
		if mm["type"] == "skip" or mm["type"] == "boost":
			never_seen = false
	check(never_seen, "no water-skip or boost missions before the River / a Booster")
	sv.zone_best = 3
	sv.levels["booster"] = 2
	var saw_skip := false
	var saw_boost := false
	for i in 300:
		var mm2: Dictionary = MissionsS.pick(sv, [], mrng)
		saw_skip = saw_skip or mm2["type"] == "skip"
		saw_boost = saw_boost or mm2["type"] == "boost"
	check(saw_skip and saw_boost, "...and they appear once they can be done")
	sv.reset_all()
	var stats := {"distance": 100.0, "picked_value": 30, "pad_bounces": 3, "skips": 4, "fan_entries": 2, "boosts_used": 0, "gears_picked": 2, "bird_hits": 0, "zone_max": 2}
	var done_all := true
	for t in MissionsS.TYPES:
		var mt := {"type": t, "target": 2, "reward": 10, "zone": 2}
		var st_t := stats.duplicate()
		if t == "boost":
			st_t["boosts_used"] = 3
		if not MissionsS.is_done(mt, st_t):
			done_all = false
	check(done_all, "every mission type recognises a flight that meets it")
	var stats2 := stats.duplicate()
	stats2["boosts_used"] = 1
	stats2["bird_hits"] = 1
	stats2["pad_bounces"] = 1
	check(not MissionsS.is_done({"type": "noboost_zone", "target": 2, "reward": 10, "zone": 2}, stats2) and not MissionsS.is_done({"type": "nobird", "target": 50, "reward": 10, "zone": 0}, stats2) and not MissionsS.is_done({"type": "bounce", "target": 2, "reward": 10, "zone": 0}, stats2), "boosting, a bird hit or too few bounces fail the matching missions")
	sv.missions = [{"type": "distance", "target": 50, "reward": 40, "zone": 0}, {"type": "bounce", "target": 9, "reward": 50, "zone": 0}, {"type": "gear", "target": 1, "reward": 60, "zone": 0}]
	var completed: Array = MissionsS.evaluate(sv, stats, mrng)
	var new_types := {}
	for m in sv.missions:
		new_types[m["type"]] = true
	check(completed.size() == 2 and completed[0]["reward"] + completed[1]["reward"] == 100 and sv.missions.size() == 3 and new_types.size() == 3 and sv.missions_done == 2, "completing missions pays them and draws new ones (%d done)" % completed.size())
	check(MissionsS.evaluate(sv, {"distance": 1.0, "picked_value": 0, "pad_bounces": 0, "skips": 0, "fan_entries": 0, "boosts_used": 0, "gears_picked": 0, "bird_hits": 0, "zone_max": 0}, mrng).is_empty(), "a poor flight completes nothing")
	sv.missions = [{"type": "scrap", "target": 12, "reward": 33, "zone": 0}, {"type": "updraft", "target": 4, "reward": 44, "zone": 0}, {"type": "distance", "target": 80, "reward": 55, "zone": 0}]
	sv.save_game()
	sv.load_game()
	check(sv.missions.size() == 3 and sv.missions[1]["type"] == "updraft" and sv.missions[2]["reward"] == 55, "missions survive a save round trip")
	var fw2 := FileAccess.open(sv.path, FileAccess.WRITE)
	fw2.store_string(JSON.stringify({"scrap": 5, "missions": [{"type": "bogus", "target": 3}, {"type": "gear", "target": 2, "reward": 9}, 7]}))
	fw2.close()
	sv.load_game()
	check(sv.missions.size() == 1 and sv.missions[0]["type"] == "gear", "bad mission entries in a save are dropped (%s)" % str(sv.missions))
	var rctx := {"new_best": true, "distance": 200.0, "best_before": 100.0, "mission_done": false, "new_zone": false, "stall_time": 0.0, "bird_hits": 0, "run": 0}
	check(RustyS.RECORD.has(RustyS.comment(rctx)), "Rusty cheers a record")
	rctx["new_best"] = false
	rctx["distance"] = 30.0
	check(RustyS.BAD.has(RustyS.comment(rctx)), "Rusty is sympathetic about a short flight")
	rctx["stall_time"] = 2.0
	check(RustyS.STALL.has(RustyS.comment(rctx)), "Rusty explains stalling")
	rctx["stall_time"] = 0.0
	rctx["bird_hits"] = 3
	check(RustyS.BIRD.has(RustyS.comment(rctx)), "Rusty warns about birds")
	rctx["bird_hits"] = 0
	rctx["distance"] = 95.0
	check(RustyS.GOOD.has(RustyS.comment(rctx)), "Rusty approves of a decent flight")
	rctx["mission_done"] = true
	check(RustyS.MISSION.has(RustyS.comment(rctx)), "Rusty congratulates a finished mission")
	var lines := {}
	rctx["mission_done"] = false
	for r in 4:
		rctx["run"] = r
		lines[RustyS.comment(rctx)] = true
	check(lines.size() >= 2, "Rusty varies his lines (%d different)" % lines.size())
	sv.reset_all()
	main._to_shop()
	check(main.hud._rusty != null and main.hud._rusty.is_visible_in_tree() and main.hud._rusty_says.text.contains("Rusty"), "Rusty is on the launch screen with a greeting")
	check(main.hud._mission_rows[0].text != "" and main.hud._mission_rewards[2].text.begins_with("+"), "the three missions are listed on the launch screen")
	sv.missions = [{"type": "distance", "target": 5, "reward": 77, "zone": 0}, sv.missions[1], sv.missions[2]]
	main.hud.refresh_shop(main.last_result)
	var sc0: float = sv.scrap
	main.hud._launch_btn.pressed.emit()
	fly_main(main)
	check(main.last_result["missions"].size() >= 1 and main.last_result["mission_bonus"] >= 77 and main.last_result["rusty"] != "", "a flight completes the mission and Rusty comments")
	check(sv.scrap == sc0 + main.last_result["earned"] and main.hud.result_text().contains("MISSION DONE") and main.hud._rusty_says.text.begins_with("Rusty: "), "the reward is paid and shown (%s)" % main.hud._rusty_says.text)
	check(sv.missions.size() == 3 and sv.missions[0]["target"] != 5, "the finished mission was replaced")
	sv.reset_all()
	main._to_shop()

	print("2e. frames")
	var fs = air(0, 300, 20, 0, 0, {"ramp": 0, "wings": 0, "body": 0, "booster": 0, "magnet": 0, "frame": "scrapper"})
	var ff = air(0, 300, 20, 0, 0, {"ramp": 0, "wings": 0, "body": 0, "booster": 0, "magnet": 0, "frame": "feather"})
	check(ff.lift_k_eff > fs.lift_k_eff * 1.15 and ff.tr_slow > 0.0 and ff.tr_gravity < 1.0, "Featherweight: more lift, lighter, but it bleeds speed")
	var wings5 = air(0, 300, 20, 0, 0, {"wings": 5, "frame": "feather"})
	check(absf(wings5.lift_k_eff / ff.lift_k_eff - tn.wing_lift_k(5) / tn.wing_lift_k(0)) < 0.001, "upgrades apply to every frame (Wings 5 on a Featherweight)")
	fs = air(0, 300, 40, 0, 0)
	ff = air(0, 300, 40, 0, 0, {"frame": "feather"})
	fs.advance(1.5, false)
	ff.advance(1.5, false)
	check(ff.speed() < fs.speed(), "Featherweight slows faster at speed (%.1f vs %.1f m/s)" % [ff.speed(), fs.speed()])
	var scr_d := avg_distance(lv())
	var fea_d := avg_distance({"ramp": 0, "wings": 0, "body": 0, "booster": 0, "magnet": 0, "frame": "feather"})
	check(fea_d > scr_d * 1.1, "Featherweight glides farther (%.0f m vs %.0f m)" % [fea_d, scr_d])
	fs = air(0, 28.0, 25, 0, 20)
	var fan_ = air(0, 28.0, 25, 0, 20, {"frame": "anvil"})
	fs.advance(1.5, true)
	fan_.advance(1.5, true)
	check(fan_.y - 28.0 < (fs.y - 28.0) * 0.8, "Anvil climbs badly (+%.0f m vs +%.0f m)" % [fan_.y - 28.0, fs.y - 28.0])
	fs = air(0, 300, 20, 0, -30)
	fan_ = air(0, 300, 20, 0, -30, {"frame": "anvil"})
	fs.advance(2.0, false)
	fan_.advance(2.0, false)
	check(fan_.speed() > fs.speed() + 1.0, "Anvil dives fast (%.1f vs %.1f m/s)" % [fan_.speed(), fs.speed()])
	f = air(0, 30, 20, 0, 0, {"frame": "anvil"})
	f.add_thing(FlightS.K_BIRD, 3.0, 30.0, 0.0)
	var an_sp: float = f.speed()
	f.advance(0.3, false)
	var an_loss: float = an_sp - f.speed()
	f = air(0, 30, 20, 0, 0)
	f.add_thing(FlightS.K_BIRD, 3.0, 30.0, 0.0)
	var sc_sp: float = f.speed()
	f.advance(0.3, false)
	check(an_loss < (sc_sp - f.speed()) * 0.7, "Anvil shrugs off birds (-%.1f vs -%.1f m/s)" % [an_loss, sc_sp - f.speed()])
	var kick := {}
	for fr in ["scrapper", "pogo"]:
		f = air(0, 1.2, 12, -8, -10, {"frame": fr})
		f.add_thing(FlightS.K_PAD, 1.0, 0.0)
		f.advance(0.1, false)
		kick[fr] = f.vy
		f = air(400.0, 0.62, 18, -3, 0, {"frame": fr})
		f.advance(0.05, false)
		kick[fr + "_skip"] = f.vy
		f = air(3100.0, 0.62, 16, -10, -10, {"frame": fr})
		f.advance(0.05, false)
		kick[fr + "_cloud"] = f.vy
	check(kick["pogo"] > kick["scrapper"] * 1.3 and kick["pogo_skip"] > kick["scrapper_skip"] * 1.3 and kick["pogo_cloud"] > kick["scrapper_cloud"] * 1.3, "Pogo bounces more off pads, water and clouds (pad %.1f vs %.1f)" % [kick["pogo"], kick["scrapper"]])
	sv.reset_all()
	check(sv.frame == "scrapper" and sv.owns_frame("scrapper") and not sv.owns_frame("feather"), "everyone starts with the Scrapper")
	check(not sv.buy_frame("feather") and sv.scrap == 0.0, "can't buy a frame without the scrap")
	sv.add_scrap(tn.frame_cost("feather") + 5.0)
	check(sv.buy_frame("feather") and sv.owns_frame("feather") and sv.frame == "feather" and sv.scrap == 5.0, "buying a frame pays for it and equips it")
	check(not sv.buy_frame("feather") and sv.equip_frame("scrapper") and sv.frame == "scrapper" and not sv.equip_frame("anvil"), "owned frames can be swapped, unowned ones can't be equipped")
	sv.equip_frame("feather")
	sv.load_game()
	check(sv.frame == "feather" and sv.owns_frame("feather") and sv.owns_frame("scrapper"), "frames survive a save round trip")
	var fo := FileAccess.open(sv.path, FileAccess.WRITE)
	fo.store_string(JSON.stringify({"version": 4, "scrap": 9, "frame": "pogo"}))
	fo.close()
	sv.load_game()
	check(sv.frame == "scrapper" and sv.launcher == "ramp" and sv.scrap == 9.0, "an older save (no frames) starts on the Scrapper and the Ramp")
	sv.reset_all()
	sv.add_scrap(5000.0)
	main._to_shop()
	main.hud.show_tab(1)
	check(main.hud._tab_pages[1].visible and not main.hud._tab_pages[0].visible, "the FRAMES tab shows its page")
	check(main.hud._frame_rows.size() == 4 and main.hud._frame_rows[0]["btn"].text == "FLYING" and main.hud._frame_rows[1]["btn"].text == tn.fmt(tn.frame_cost("feather")), "frame rows show FLYING and prices")
	main.hud._frame_rows[1]["btn"].pressed.emit()
	check(sv.frame == "feather" and main.flight.frame_id == "feather" and main.hud._frame_rows[1]["btn"].text == "FLYING" and main.hud._frame_rows[0]["btn"].text == "FLY", "pressing a frame buys and equips it, and the glider on the ramp changes")
	main.hud._frame_rows[0]["btn"].pressed.emit()
	check(sv.frame == "scrapper" and sv.scrap == 5000.0 - tn.frame_cost("feather"), "pressing an owned frame just equips it")
	main.hud.show_tab(0)

	print("2f. launchers")
	check(tn.launchers.size() == 4 and tn.launchers[0]["name"] == "Ramp" and tn.launchers[1]["name"] == "Slingshot" and tn.launchers[2]["name"] == "Catapult" and tn.launchers[3]["name"] == "Rocket Sled", "Ramp, Slingshot, Catapult, Rocket Sled")
	check(tn.launchers[1]["cost"] < tn.launchers[2]["cost"] and tn.launchers[2]["cost"] < tn.launchers[3]["cost"] and tn.launchers[1]["cost"] >= 1000.0, "launchers are big purchases and get pricier")
	sv.reset_all()
	sv.add_scrap(100000.0)
	check(not sv.can_buy_launcher("catapult") and not sv.buy_launcher("sled") and sv.can_buy_launcher("sling"), "launchers are bought in order")
	check(sv.buy_launcher("sling") and sv.launcher == "sling" and sv.owns_launcher("sling") and sv.can_buy_launcher("catapult"), "buying the Slingshot equips it and opens the Catapult")
	check(sv.equip_launcher("ramp") and sv.launcher == "ramp" and sv.equip_launcher("sling") and not sv.equip_launcher("sled"), "owned launchers can be swapped back")
	sv.load_game()
	check(sv.owns_launcher("sling") and sv.launcher == "sling", "launchers survive a save round trip")
	for id in ["ramp", "sling", "catapult", "sled"]:
		var lf = FlightS.new()
		lf.reset({"ramp": 2, "launcher": id}, 3)
		lf.gen_x = 1.0e9
		lf.launch_auto()
		var guard := 0
		while lf.phase == FlightS.PH_RAMP and guard < 3000:
			lf.step(1.0 / 120.0, false)
			guard += 1
		var spd: float = lf.speed()
		var want: float = tn.launcher_speed(id, 2)
		check(lf.phase == FlightS.PH_AIR and absf(spd - want) < 0.5, "%s: leaves at its launch speed (%.1f of %.1f m/s)" % [id, spd, want])
		if id == "catapult":
			check(absf(rad_to_deg(atan2(lf.vy, lf.vx)) - 38.0) < 3.0, "Catapult: the arm flings you up at about 38 degrees")
		if id == "sled":
			check(absf(rad_to_deg(atan2(lf.vy, lf.vx)) - 22.0) < 3.0, "Rocket Sled: the rails kick up at 22 degrees")
		if id == "sling":
			check(absf(rad_to_deg(atan2(lf.vy, lf.vx)) - tn.sling_default_angle) < 2.0, "Slingshot: you go along the aim")
	f = FlightS.new()
	f.reset({"launcher": "sling"}, 1)
	f.launch()
	check(f.phase == FlightS.PH_AIM and not f.fire(), "Slingshot: LAUNCH starts the aim, and a zero pull can't fire")
	f.set_aim(0.1, 40.0)
	check(not f.fire(), "...nor can a feeble one")
	f.set_aim(0.5, 100.0)
	check(f.aim_angle <= tn.sling_angle_max + 0.01, "the aim angle is limited")
	var half_speed: float = f.lip_speed
	f.set_aim(1.0, 30.0)
	check(f.lip_speed > half_speed * 1.1 and absf(f.lip_speed - tn.launcher_speed("sling", 0)) < 0.01, "a harder pull launches faster (%.1f vs %.1f m/s)" % [f.lip_speed, half_speed])
	check(f.fire() and f.phase == FlightS.PH_RAMP, "a firm pull fires")
	var dist_by := {}
	for id in ["ramp", "sling", "catapult", "sled"]:
		dist_by[id] = avg_distance({"ramp": 3, "wings": 3, "body": 3, "booster": 0, "magnet": 0, "launcher": id})
	check(dist_by["ramp"] < dist_by["sling"] * 0.9 and dist_by["sling"] < dist_by["catapult"] * 0.9 and dist_by["catapult"] < dist_by["sled"] * 0.9, "each launcher clearly goes farther (%.0f, %.0f, %.0f, %.0f m)" % [dist_by["ramp"], dist_by["sling"], dist_by["catapult"], dist_by["sled"]])
	sv.reset_all()
	sv.launchers_owned["sling"] = true
	sv.launcher = "sling"
	sv.save_game()
	main._to_shop()
	main.hud._launch_btn.pressed.emit()
	check(main.state == main.STATE_FLIGHT and main.flight.phase == FlightS.PH_AIM, "Slingshot: LAUNCH waits for the pull in the game")
	touch(main, Vector2(500, 900), true)
	var drag_ev := InputEventScreenDrag.new()
	drag_ev.index = 0
	drag_ev.position = Vector2(500, 900) + Vector2(-130, 130)
	main._input(drag_ev)
	check(main.flight.aim_power > 0.5 and main.flight.aim_angle > 30.0 and main.flight.aim_angle < 60.0, "pulling down-left aims up-right (power %.2f, %.0f deg)" % [main.flight.aim_power, main.flight.aim_angle])
	main.frame(1.0 / 60.0, 1.0 / 60.0)
	check(main.hud._hint.visible and main.hud._hint.text.contains("POWER"), "the pull shows power and angle (%s)" % main.hud._hint.text.replace("\n", " | "))
	touch(main, Vector2(630, 1030), false)
	check(main.flight.phase == FlightS.PH_RAMP, "letting go fires the slingshot")
	for i in 90:
		main.frame(1.0 / 60.0, 1.0 / 60.0)
	check(main.flight.phase == FlightS.PH_AIR and not main.hud._hint.visible, "...and the aim read-out goes away in flight")
	fly_main(main)
	main._to_shop()
	main.hud._launch_btn.pressed.emit()
	touch(main, Vector2(500, 900), true)
	drag_ev.position = Vector2(500, 900) + Vector2(-5, 5)
	main._input(drag_ev)
	touch(main, Vector2(505, 905), false)
	check(main.flight.phase == FlightS.PH_AIM and main.flight.aim_power == 0.0, "a tap without a real pull does not fire; you can try again")
	touch(main, Vector2(500, 900), true)
	drag_ev.position = Vector2(500, 900) + Vector2(-200, 150)
	main._input(drag_ev)
	touch(main, Vector2(300, 1050), false)
	fly_main(main)
	check(main.state == main.STATE_SHOP and main.last_result["distance"] > 30.0, "a slingshot flight completes (%.0f m)" % main.last_result["distance"])
	sv.reset_all()
	sv.add_scrap(100000.0)
	main._to_shop()
	main.hud.show_tab(2)
	check(main.hud._tab_pages[2].visible and main.hud._launcher_rows[0]["btn"].text == "IN USE" and main.hud._launcher_rows[1]["btn"].text == tn.fmt(tn.launcher_cost("sling")) and main.hud._launcher_rows[2]["btn"].text == "LOCKED", "launcher rows: equipped, price, locked")
	main.hud._launcher_rows[1]["btn"].pressed.emit()
	check(sv.launcher == "sling" and main.flight.launcher_id == "sling" and main.hud._launcher_rows[2]["btn"].text == tn.fmt(tn.launcher_cost("catapult")), "buying the Slingshot equips it and unlocks the Catapult row")
	main.hud._launcher_rows[2]["btn"].pressed.emit()
	main.hud._launcher_rows[3]["btn"].pressed.emit()
	check(sv.launcher == "sled" and main.hud._launcher_rows[0]["btn"].text == "USE", "all four can be bought in turn")
	main.hud.show_tab(0)
	check(main.hud._row_effect[0].text.contains("m/s") and tn.current_launcher == "sled", "the launch-power row follows the equipped launcher (%s)" % main.hud._row_effect[0].text)
	main.hud._launch_btn.pressed.emit()
	fly_main(main)
	check(main.state == main.STATE_SHOP and main.last_result["distance"] > 100.0, "a Rocket Sled flight completes (%.0f m)" % main.last_result["distance"])
	sv.reset_all()
	main._to_shop()
	var tp2: Node = main.tune_panel
	tp2.unlock_all_gear()
	check(sv.owns_frame("pogo") and sv.owns_launcher("sled"), "?tune: Unlock frames + launchers")
	check(main.prewarm_frames_seen.size() == 4 and main.prewarm_launchers_seen.size() == 4, "the pre-warm drew every frame and launcher")
	sv.reset_all()
	main._to_shop()

	print("2g. cosmetics")
	for kind in Cosmetics.KINDS:
		var list := Cosmetics.list_of(kind)
		var asc := true
		for i in range(1, list.size()):
			if list[i]["cost"] <= list[i - 1]["cost"]:
				asc = false
		check(list.size() == 5 and list[0]["cost"] == 0.0 and asc, "%s: a free default and four to buy, getting pricier" % kind)
	check(Cosmetics.hats.size() == 5 and Cosmetics.hats[1]["name"] == "Baseball Cap", "hats for Whiskers")
	sv.reset_all()
	check(sv.owns_cosmetic("paint", "default") and sv.owns_cosmetic("hat", "none") and sv.owns_cosmetic("trail", "none") and not sv.owns_cosmetic("hat", "crown"), "the defaults are owned from the start")
	check(not sv.buy_cosmetic("hat", "cap") and sv.scrap == 0.0, "can't buy a hat without the scrap")
	sv.add_scrap(1000.0)
	check(sv.buy_cosmetic("hat", "cap") and sv.hat == "cap" and sv.scrap == 1000.0 - 80.0, "buying a hat pays and wears it")
	check(not sv.buy_cosmetic("hat", "cap") and sv.equip_cosmetic("hat", "none") and sv.hat == "none" and not sv.equip_cosmetic("hat", "crown"), "owned hats can be swapped, unowned can't be worn")
	check(sv.buy_cosmetic("paint", "red") and sv.buy_cosmetic("trail", "sparkle") and sv.paint == "red" and sv.trail == "sparkle", "paints and trails work the same way")
	sv.load_game()
	check(sv.paint == "red" and sv.trail == "sparkle" and sv.owns_cosmetic("hat", "cap"), "cosmetics survive a save round trip")
	var fc := FileAccess.open(sv.path, FileAccess.WRITE)
	fc.store_string(JSON.stringify({"version": 5, "scrap": 3, "paint": "gold", "hat": "crown", "trail": "bogus"}))
	fc.close()
	sv.load_game()
	check(sv.paint == "default" and sv.hat == "none" and sv.trail == "none", "a save wearing things it doesn't own falls back to the defaults")
	sv.reset_all()
	sv.add_scrap(5000.0)
	main._to_shop()
	var style_nodes := snapshot(main)
	main.hud.show_tab(3)
	main.hud.set_style_cat(1)
	check(main.hud._tab_pages[3].visible and main.hud._style_rows[0]["name"].text.begins_with("No Hat") and main.hud._style_rows[1]["btn"].text == tn.fmt(80.0), "the STYLE tab lists the hats with prices")
	main.hud._style_rows[3]["btn"].pressed.emit()
	check(sv.hat == "party" and main.world.hat_id == "party" and main.hud._style_rows[3]["btn"].text == "WORN", "buying a hat puts it on the pilot in the world")
	main.hud.set_style_cat(0)
	main.hud._style_rows[1]["btn"].pressed.emit()
	check(sv.paint == "red" and main.world.paint_color.r > 0.8 and main.world.paint_color.a > 0.0, "a paint job recolours the glider")
	main.hud._style_rows[0]["btn"].pressed.emit()
	check(sv.paint == "default" and main.world.paint_color.a == 0.0, "the free default paint comes back")
	main.hud.set_style_cat(2)
	main.hud._style_rows[1]["btn"].pressed.emit()
	check(sv.trail == "sparkle", "a trail is bought and worn")
	main.hud.show_tab(0)
	check(same_world(style_nodes, snapshot(main)), "the STYLE tab creates nothing")
	for tid in ["sparkle", "smoke", "bubbles", "rainbow", "none"]:
		sv.trail = tid
		main._to_shop()
		main.hud._launch_btn.pressed.emit()
		main.flight.gen_x = 1.0e9
		main.flight.clear_things()
		for i in 130:
			main.frame(1.0 / 60.0, 1.0 / 60.0)
		var live: int = main.world.live_particles()
		check((tid == "none" and live == 0) or (tid != "none" and live >= 5), "trail %s: %d particles behind the glider" % [tid, live])
		fly_main(main)
	sv.reset_all()
	main._to_shop()

	print("2h. daily launch")
	sv.reset_all()
	sv.day_key_override = 20261018
	var seed_a: int = sv.daily_seed()
	sv.day_key_override = 20261019
	var seed_b: int = sv.daily_seed()
	sv.day_key_override = 20261018
	check(seed_a == sv.daily_seed() and seed_a != seed_b and seed_a >= 0, "a day has one seed, a new day another")
	check(sv.refresh_daily() and sv.daily_key == 20261018 and sv.daily_target >= 90 and sv.daily_target % 5 == 0, "a new day gets a target (%d m)" % sv.daily_target)
	var target0: int = sv.daily_target
	sv.best_distance = 900.0
	check(not sv.refresh_daily() and sv.daily_target == target0, "the target stays put for the rest of the day")
	sv.daily_best = 77.0
	sv.daily_claimed = true
	sv.day_key_override = 20261019
	check(sv.refresh_daily() and sv.daily_best == 0.0 and not sv.daily_claimed and sv.daily_target > target0, "the next day starts fresh, stretching from your best (%d m)" % sv.daily_target)
	sv.day_key_override = 20261018
	sv.daily_key = 0
	sv.daily_target = 0
	sv.refresh_daily()
	sv.daily_best = 123.0
	sv.save_game()
	sv.load_game()
	check(sv.daily_key == 20261018 and sv.daily_best == 123.0 and sv.daily_target > 0, "the daily state survives a save round trip")
	var wa = FlightS.new()
	var wb = FlightS.new()
	var wc = FlightS.new()
	wa.reset({}, sv.daily_seed())
	wb.reset({}, sv.daily_seed())
	wc.reset({}, seed_b)
	wa.clear_things()
	wb.clear_things()
	wc.clear_things()
	for k in 6:
		wa._gen_chunk()
		wb._gen_chunk()
		wc._gen_chunk()
	var same_world_a := true
	var diff_c := false
	for i in FlightS.MAX_THINGS:
		if wa.t_active[i] != wb.t_active[i] or wa.t_x[i] != wb.t_x[i] or wa.t_y[i] != wb.t_y[i] or wa.t_kind[i] != wb.t_kind[i]:
			same_world_a = false
		if wa.t_x[i] != wc.t_x[i] or wa.t_kind[i] != wc.t_kind[i]:
			diff_c = true
	check(same_world_a and diff_c, "the daily world is the same every time today and differs tomorrow")
	f = air(0, 40, 25, 0, 0)
	f.target_x = 30.0
	var got_target := false
	for i in 240:
		f.step(1.0 / 120.0, false)
		for k in f.ev_n:
			if f.ev_kind[k] == FlightS.EV_TARGET:
				got_target = true
		f.ev_n = 0
	check(got_target and f.passed_target, "passing the target raises one event")
	sv.reset_all()
	sv.day_key_override = 20261018
	main._to_shop()
	main.hud.show_tab(4)
	check(main.hud._tab_pages[4].visible and main.hud._daily_info.text.contains("Target %s m" % tn.fmt(sv.daily_target)) and main.hud._daily_title.text.contains("2026-10-18"), "the DAILY tab shows the date and target (%s)" % main.hud._daily_info.text.replace("\n", " | "))
	sv.daily_target = 5
	sv.daily_best = 0.0
	main.hud.refresh_shop(main.last_result)
	var reward5: int = sv.daily_reward()
	var sc_before: float = sv.scrap
	main.hud._daily_btn.pressed.emit()
	check(main.state == main.STATE_FLIGHT and main.daily_mode and main.flight.target_x == 5.0 and main.world.target_x == 5.0 and main.hud._best.text.contains("DAILY TARGET"), "the daily button starts today's flight with a target flag")
	var seed_check: int = main.flight.rng.seed
	check(seed_check == sv.daily_seed(), "...in today's seeded world")
	fly_main(main)
	check(main.last_result["daily"]["bonus"] == reward5 and sv.daily_claimed and main.hud.result_text().contains("DAILY:") and main.hud.result_text().contains("BONUS"), "reaching the target pays the daily bonus (+%d) and says so" % reward5)
	check(RustyS.DAILY.has(main.last_result["rusty"]), "Rusty comments on the daily")
	main.hud._daily_btn.pressed.emit()
	fly_main(main)
	check(main.last_result["daily"]["bonus"] == 0 and sv.daily_plays == 2, "the bonus is only paid once a day")
	main.hud._launch_btn.pressed.emit()
	check(not main.daily_mode and main.flight.target_x == 0.0 and not main.hud._best.text.contains("DAILY"), "a normal LAUNCH has no target flag")
	fly_main(main)
	main.tune_panel.reset_daily()
	check(not sv.daily_claimed and sv.daily_target > 5 and sv.daily_plays == 0, "?tune: New daily starts a fresh one")
	main.tune_panel.unlock_all_cosmetics()
	check(sv.owns_cosmetic("hat", "crown") and sv.owns_cosmetic("trail", "rainbow") and sv.owns_cosmetic("paint", "gold"), "?tune: Unlock cosmetics")
	main.hud.show_tab(0)
	sv.day_key_override = 0
	sv.reset_all()
	main._to_shop()

	print("2i. ad stubs")
	tn.ads_enabled = true
	sv.reset_all()
	main.bonus_charge = 0
	main.last_result = {}
	main._to_shop()
	check(not main.hud._ad_double_btn.visible and main.hud._ad_boost_btn.visible, "the free-boost ad is on the launch screen; 'double scrap' waits for a flight")
	main.hud._ad_boost_btn.pressed.emit()
	check(main.hud.ad_active and main.hud._ad_screen.visible and main.hud._ad_title.text == "AD PLAYING" and main.hud._ad_sub.text.contains("free boost"), "a rewarded ad shows the fake 'Ad playing' screen")
	main.hud._launch_btn.pressed.emit()
	check(main.state == main.STATE_SHOP, "nothing can be launched while an ad plays")
	await real_wait(0.3)
	check(not main.hud.ad_active and not main.hud._ad_screen.visible and main.bonus_charge == 1 and main.hud._ad_boost_btn.text.contains("READY") and main.hud._ad_boost_btn.disabled, "the ad ends and grants the free boost charge")
	main.hud._launch_btn.pressed.emit()
	main.frame(1.0 / 60.0, 1.0 / 60.0)
	check(main.flight.charges == 1 and main.flight.charges_max == 1 and main.bonus_charge == 0 and main.hud._boost_pips.text == "●", "the free charge is in the next flight (a BOOST button even without a Booster)")
	touch(main, Vector2(500, 900), false)
	fly_main(main)
	check(main.bonus_charge == 0 and main.hud._ad_boost_btn.text.contains("FREE BOOST"), "it is used up after one launch")
	check(not main.hud._ad_double_btn.disabled and main.last_result["earned"] > 0, "after a flight the double-scrap ad is on offer")
	var sc1: float = sv.scrap
	var earned1: int = main.last_result["earned"]
	main.hud._ad_double_btn.pressed.emit()
	check(main.hud.ad_active and main.hud._ad_sub.text.contains("double scrap"), "the double-scrap ad plays")
	await real_wait(0.3)
	check(sv.scrap == sc1 + earned1 and main.hud._ad_double_btn.disabled and main.hud._ad_double_btn.text.contains("DOUBLED"), "the flight's scrap is doubled (+%d)" % earned1)
	main.hud._ad_double_btn.pressed.emit()
	check(not main.hud.ad_active and sv.scrap == sc1 + earned1, "...once only")
	sv.reset_all()
	sv.flights_since_ad = 0
	tn.interstitial_every = 3
	tn.interstitial_first_flight = 3
	main.last_result = {}
	main._to_shop()
	var shown: Array[bool] = []
	for r in 5:
		main.hud._launch_btn.pressed.emit()
		fly_main(main)
		shown.append(main.hud.ad_active)
		if main.hud.ad_active:
			check(main.state == main.STATE_SHOP and main.hud._ad_sub.text.contains("stub"), "the interstitial only shows between flights")
		await real_wait(0.2)
	check(shown == [false, false, true, false, false], "an interstitial every few flights, never in the first ones (%s)" % str(shown))
	tn.ads_enabled = false
	sv.flights_since_ad = 50
	main._to_shop()
	main.hud._launch_btn.pressed.emit()
	fly_main(main)
	check(not main.hud.ad_active and not main.hud._ad_double_btn.visible and not main.hud._ad_boost_btn.visible, "with ads off there is no ad and no ad button")
	tn.interstitial_every = 4
	tn.interstitial_first_flight = 4
	sv.reset_all()
	main._to_shop()

	print("2j. visual hierarchy, missions panel, toasts, results card, hats")
	var HudS: GDScript = load("res://scripts/Hud.gd")
	sv.reset_all()
	sv.runs = 6
	sv.levels["booster"] = 2
	sv.missions = [{"type": "bounce", "target": 4, "reward": 55, "zone": 0, "best": 2, "fresh": true}, {"type": "scrap", "target": 25, "reward": 45, "zone": 0, "best": 10, "fresh": false}, {"type": "distance", "target": 320, "reward": 60, "zone": 0, "best": 0, "fresh": false}]
	sv.best_distance = 120.0
	main.last_result = {}
	main._to_shop()
	# --- launch screen: LAUNCH is the biggest thing; at most three text sizes; the sheet and results are closed
	var sizes := {}
	font_sizes(main.hud._shop_root, sizes)
	check(sizes.size() <= 3, "launch screen: at most three text sizes (%s)" % str(sizes.keys()))
	var biggest_other := 0.0
	for b in [main.hud._nav_buttons[0], main.hud._nav_buttons[1], main.hud._nav_buttons[2], main.hud._ad_boost_btn, main.hud._row_btn[0]]:
		biggest_other = maxf(biggest_other, b.custom_minimum_size.y)
	check(main.hud._launch_btn.custom_minimum_size.y > biggest_other * 1.8 and main.hud._launch_btn.get_theme_font_size("font_size") > 80 and main.hud._launch_btn.get_theme_font_size("font_size") > HudS.BODY * 1.5, "launch screen: LAUNCH stays the biggest control (%.0f px, font %d)" % [main.hud._launch_btn.custom_minimum_size.y, main.hud._launch_btn.get_theme_font_size("font_size")])
	check(not main.hud._sheet.visible and not main.hud.results_visible(), "launch screen: garage, style and daily stay behind small nav buttons")
	check(main.hud._nav_buttons.size() == 3 and main.hud._nav_buttons[0].text == "GARAGE" and main.hud._nav_buttons[1].text == "STYLE" and main.hud._nav_buttons[2].text == "DAILY", "launch screen: GARAGE, STYLE and DAILY are the small nav buttons")
	# --- the five upgrade cards sit on the main screen: icon, name, level pips, one line of effect, cost
	var cards_ok: bool = main.hud._cards_box.is_visible_in_tree() and main.hud._row_btn.size() == 5
	for i in 5:
		cards_ok = cards_ok and main.hud._card_panels[i].is_visible_in_tree() and main.hud._row_btn[i].is_visible_in_tree() and main.hud._card_icons[i].is_visible_in_tree() and main.hud._card_pips[i].is_visible_in_tree() and main.hud._row_effect[i].text != "" and main.hud._row_name[i].text != ""
	check(cards_ok, "upgrade cards: Ramp, Wings, Body, Booster and Magnet are on the main screen, not in a sheet")
	check(main.hud._row_name[0].text == "Ramp" and main.hud._row_name[1].text == "Wings" and main.hud._row_name[4].text == "Scrap Magnet", "upgrade cards: names (%s)" % main.hud._row_name[0].text)
	var pips_ok: bool = true
	for i in 5:
		var id: String = main.hud._row_ids[i]
		pips_ok = pips_ok and main.hud._card_pips[i].level == sv.level(id) and main.hud._card_pips[i].max_level == tn.max_level(id)
	check(pips_ok and main.hud._card_pips[3].max_level == 8, "upgrade cards: level pips show level out of max")
	sv.scrap = 50.0
	main.hud.refresh_shop(main.last_result)
	var hi_ok: bool = main.hud._card_styles[0].border_color == HudS.C_ACCENT and main.hud._card_styles[1].border_color == HudS.C_ACCENT and main.hud._card_styles[4].border_color == HudS.C_ACCENT
	var lo_ok: bool = main.hud._card_styles[3].border_color != HudS.C_ACCENT
	check(hi_ok and lo_ok, "upgrade cards: the ones you can afford are highlighted (50 scrap: Ramp, Wings, Magnet yes, Booster no)")
	sv.scrap = 5000.0
	sv.levels["wings"] = 10
	main.hud.refresh_shop(main.last_result)
	check(main.hud._row_btn[1].text == "MAX" and main.hud._card_styles[1].border_color != HudS.C_ACCENT, "upgrade cards: a maxed upgrade says MAX and isn't highlighted")
	sv.levels["wings"] = 0
	sv.scrap = 5000.0
	# buying updates the glider preview straight away
	var lv_before: int = main.flight.lv_wings
	main.hud._row_btn[1].pressed.emit()
	check(sv.level("wings") == 1 and main.flight.lv_wings == lv_before + 1 and main.world.pulse > 0.9 and main.world.live_particles() >= 8, "buying an upgrade rebuilds the glider preview at once, with a pulse and sparks")
	main.hud._row_btn[0].pressed.emit()
	check(main.flight.lv_ramp == 1 and main.flight.ramp_pts[0].y > 0.0, "...the Ramp card changes the ramp in the preview too")
	main.frame(0.3, 0.3)
	check(main.world.pulse < 0.5, "the pulse fades away")
	sv.scrap = 0.0
	sv.levels["wings"] = 0
	sv.levels["ramp"] = 0
	main._to_shop()
	# --- Rusty's bubble: a count badge; the clipboard drops down on a tap and closes again
	check(main.hud._bubble.is_visible_in_tree() and main.hud._badge.text == "3" and main.hud._rusty.is_visible_in_tree(), "missions: Rusty's bubble with a count badge is on the launch screen")
	check(not main.hud.missions_open() and not main.hud._clip.visible, "missions: the clipboard is collapsed by default")
	main.hud._bubble.pressed.emit()
	for k in 12:
		main.hud._process(0.05)
	check(main.hud.missions_open() and main.hud._clip.visible and main.hud._clip.modulate.a > 0.95 and main.hud._clip.scale.y > 0.95, "missions: tapping the bubble drops the clipboard down")
	check(main.hud._mission_rows[0].text == "Bounce 4 times in one flight" and main.hud._mission_rewards[0].text == "+55", "clipboard: each mission shows its text and reward")
	check(absf(main.hud._mission_fills[0].anchor_right - 0.5) < 0.001 and absf(main.hud._mission_fills[1].anchor_right - 0.4) < 0.001 and main.hud._mission_fills[2].anchor_right == 0.0, "clipboard: progress bars show the best flight so far (50%, 40%, 0%)")
	check(main.hud._mission_counts[0].text.contains("Bounces 2/4") and main.hud._mission_counts[1].text.contains("Scrap 10/25") and main.hud._mission_new[0].visible and main.hud._mission_new[0].text == "NEW" and not main.hud._mission_new[1].visible, "clipboard: counts and a NEW tag for a mission just drawn")
	var clip_sizes := {}
	font_sizes(main.hud._clip, clip_sizes)
	check(clip_sizes.size() <= 2, "clipboard: two text sizes (%s)" % str(clip_sizes.keys()))
	main.hud._bubble.pressed.emit()
	for k in 12:
		main.hud._process(0.05)
	check(not main.hud.missions_open() and not main.hud._clip.visible, "missions: tapping again tucks it away")
	main.hud.drop_missions(1.0)
	main.hud._process(0.1)
	check(main.hud.missions_open(), "missions: a timed drop opens...")
	for k in 40:
		main.hud._process(0.05)
	check(not main.hud.missions_open() and not main.hud._clip.visible, "...and closes by itself")
	main.hud.drop_missions()
	main.hud._process(0.2)
	main.hud._launch_btn.pressed.emit()
	check(not main.hud.missions_open() and not main.hud._clip.visible and main.state == main.STATE_FLIGHT, "missions: pressing LAUNCH closes the clipboard")
	fly_main(main)
	main.hud.show_results(false)
	main.hud.close_missions()
	main._to_shop()
	main.hud._nav_buttons[0].pressed.emit()
	check(main.hud._sheet.visible and main.hud._tab_pages[1].visible, "the GARAGE button opens the garage sheet")
	var shop_sizes := {}
	font_sizes(main.hud._sheet, shop_sizes)
	check(shop_sizes.size() <= 3, "garage sheet: at most three text sizes (%s)" % str(shop_sizes.keys()))
	main.hud.close_sheet()
	check(not main.hud._sheet.visible, "the sheet closes")
	# --- flight screen: only the distance, the best line, the boost button and its pips
	main.hud._launch_btn.pressed.emit()
	for i in 40:
		main.frame(1.0 / 60.0, 1.0 / 60.0)
	var flight_labels: Array = []
	visible_texts(main.hud._flight_root, flight_labels)
	var names: Array[String] = []
	for l in flight_labels:
		names.append(l.text)
	check(flight_labels.size() == 4 and main.hud._dist in flight_labels and main.hud._best in flight_labels and main.hud._boost_pips in flight_labels, "flight screen: only distance, best line, boost button and pips are on screen (%s)" % str(names))
	var fsizes := {}
	font_sizes(main.hud._flight_root, fsizes)
	check(fsizes.size() <= 3 and main.hud._dist.get_theme_font_size("font_size") == HudS.HERO, "flight screen: distance is the biggest text, at most three sizes (%s)" % str(fsizes.keys()))
	# --- mission toasts, no permanent clutter
	check(main.hud._toast.visible == false, "no mission text sits on the flight screen")
	main.flight.pad_bounces = 1
	main._mission_toasts()
	check(main.hud._toast.visible and main.hud._toast.text == "Bounces 1/4", "a bounce toasts the progress (%s)" % main.hud._toast.text)
	main.flight.pad_bounces = 4
	main._mission_toasts()
	check(main.hud._toast.text == "MISSION DONE: Bounces 4/4", "finishing it says so (%s)" % main.hud._toast.text)
	main.flight.picked_value = 12
	main._mission_toasts()
	check(main.hud._toast.text == "Scrap 12/25", "scrap progress toasts too (%s)" % main.hud._toast.text)
	main.flight.distance = 170.0
	main._mission_toasts()
	check(main.hud._toast.text.begins_with("Distance 170/320"), "distance toasts at the halfway mark (%s)" % main.hud._toast.text)
	main.hud._process(2.6)
	check(not main.hud._toast.visible, "toasts fade away on their own")
	main.flight.pad_bounces = 0
	check(MissionsS.value_live(sv.missions[0], main.flight) == 0 and MissionsS.value_of(sv.missions[0], {"pad_bounces": 3}) == 3, "mission progress is read live from the flight and from end-of-flight stats")
	fly_main(main)
	# --- results card
	sv.reset_all()
	sv.runs = 6
	sv.missions = [{"type": "distance", "target": 5, "reward": 77, "zone": 0, "best": 0, "fresh": false}, {"type": "scrap", "target": 9999, "reward": 45, "zone": 0, "best": 3, "fresh": false}, {"type": "bounce", "target": 99, "reward": 50, "zone": 0, "best": 0, "fresh": false}]
	main.last_result = {}
	main._to_shop()
	main.hud._launch_btn.pressed.emit()
	fly_main(main)
	check(main.hud.results_visible() and main.hud._res_dist.text.contains("m") and main.hud._res_dist.get_theme_font_size("font_size") == HudS.HERO, "results: a card with the distance, big, appears after the flight")
	var rsizes := {}
	font_sizes(main.hud._results, rsizes)
	check(rsizes.size() <= 3 and main.hud._res_dist.get_theme_font_size("font_size") == rsizes.keys().max(), "results: the distance is the biggest text, at most three sizes (%s)" % str(rsizes.keys()))
	check(main.hud._res_missions.visible and main.hud._res_missions.text.contains("+77") and main.hud._res_mcap.text == "MISSION DONE", "results: completed missions with their rewards (%s)" % main.hud._res_missions.text)
	check(main.hud._res_new.visible and main.hud._res_new.text.begins_with("New mission: ") and main.last_result["new_missions"].size() == 1, "results: the new mission that was drawn (%s)" % main.hud._res_new.text)
	check(main.hud._res_scrap.text == "+%s scrap" % tn.fmt(main.last_result["earned"]) and main.hud._res_rusty.text.begins_with("Rusty: "), "results: scrap earned and Rusty's comment")
	check(main.hud._mission_new[2].visible and main.hud._mission_rows[2].text == MissionsS.describe(sv.missions[2]), "clipboard: the new mission is tagged NEW behind the card")
	main.hud._res_continue.pressed.emit()
	check(not main.hud.results_visible() and main.hud.missions_open(), "CONTINUE closes the card; the clipboard drops down by itself to show what changed")
	check(main.hud._mission_new[2].visible and (main.hud._mission_new[0].visible or main.hud._mission_new[1].visible or true), "...with the new mission tagged")
	for k in 80:
		main.hud._process(0.05)
	check(not main.hud.missions_open(), "...then it collapses again by itself")
	var kept := {"best": -1}
	for mm in sv.missions:
		if mm["type"] == "scrap":
			kept = mm
	check(kept["best"] >= 3 and sv.missions.size() == 3, "an unfinished mission keeps its best progress (%d)" % kept["best"])
	main.hud._launch_btn.pressed.emit()
	var fresh_left := 0
	for mm in sv.missions:
		if mm.get("fresh", false):
			fresh_left += 1
	check(fresh_left == 0, "NEW tags clear when the next flight starts")
	fly_main(main)
	# --- Whiskers and his hat are always above the wings, on every frame
	main.hud._res_continue.pressed.emit()
	main.world.log_layers = true
	var order_ok := true
	var hat_ok := true
	var worn := 0
	for fid in ["scrapper", "feather", "anvil", "pogo"]:
		for hid in ["none", "cap", "tophat", "party", "crown"]:
			var lo := {"wings": 10, "body": 9, "frame": fid}
			main.flight.reset(lo, 1)
			main.world.hat_id = hid
			await process_frame
			await process_frame
			var lg: PackedStringArray = main.world.layer_log
			var fw := lg.find("front_wing")
			var hd := lg.find("head")
			var ht := lg.find("hat")
			if not (fw >= 0 and hd > fw and (lg.find("rear_wing") < fw)):
				order_ok = false
			if (hid == "none") != (ht < 0) or (hid != "none" and ht < hd):
				hat_ok = false
			if hid != "none" and ht > hd:
				worn += 1
	check(order_ok, "Whiskers is drawn after the front wing on every frame (wings at level 10)")
	check(hat_ok and worn == 16, "every hat is drawn after Whiskers, above the wings, on every frame (%d of 16)" % worn)
	main.world.log_layers = false
	main.world.hat_id = "none"
	sv.reset_all()
	main._to_shop()

	print("3. upgrades and the early game")
	var base := avg_distance(lv())
	check(base > 40.0 and base < 150.0, "a level-0 run is short (%.0f m)" % base)
	check(run_pilot(lv(), 100, 3.0).distance < base * 1.05 + 5.0 and run_pilot(lv(), 100, 3.0).distance > 15.0, "a sluggish player gets a similar short run")
	var first_cost: float = 1e9
	for u in tn.upgrades:
		first_cost = minf(first_cost, tn.upgrade_cost(u["id"], 0))
	check(first_cost <= base * tn.scrap_per_meter * 1.5 + 5.0, "the first upgrade is affordable after about one run (%.0f scrap)" % first_cost)
	for pair in [["ramp", lv(5)], ["wings", lv(0, 5)], ["body", lv(0, 0, 5)], ["booster", lv(0, 0, 0, 5)]]:
		var d := avg_distance(pair[1])
		check(d > base * 1.25, "%s level 5 clearly adds distance (%.0f m vs %.0f m)" % [pair[0], d, base])
	var mid := avg_distance(lv(3, 3, 3, 3, 3))
	var top := avg_distance(lv(10, 10, 10, 8, 8))
	check(mid > base * 2.0 and top > mid * 2.0, "upgrades compound (%.0f m -> %.0f m -> %.0f m)" % [base, mid, top])
	check(tn.glide_ratio(10, 10) > tn.glide_ratio(0, 0) * 1.5, "Wings and Body raise the glide ratio")
	for u in tn.upgrades:
		var costs_up: bool = tn.upgrade_cost(u["id"], 3) > tn.upgrade_cost(u["id"], 2)
		check(costs_up, "%s gets pricier each level" % u["name"])

	print("4. the game loop: launch, fly, land, shop, buy, launch again (in place)")
	sv.reset_all()
	main._to_shop()
	await process_frame
	var baseline: Dictionary = {}
	var scraps_expected := 0.0
	for run in 3:
		check(main.state == main.STATE_SHOP, "run %d: starts in the shop" % (run + 1))
		main.hud._launch_btn.pressed.emit()
		check(main.state == main.STATE_FLIGHT and main.hud._flight_root.visible and not main.hud._shop_root.visible, "run %d: LAUNCH starts the flight" % (run + 1))
		var secs := fly_main(main)
		check(main.state == main.STATE_SHOP, "run %d: back in the shop after the touchdown (%.1f s flown)" % [run + 1, secs])
		check(main.last_result.get("distance", 0.0) > 20.0 and main.hud.result_text().contains("LANDED"), "run %d: the result is shown (%s)" % [run + 1, main.hud.result_text().replace("\n", " | ")])
		check(sv.runs == run + 1 and sv.scrap >= main.last_result["earned"] and sv.scrap == scraps_expected + main.last_result["earned"], "run %d: scrap and run count are saved (+%d scrap)" % [run + 1, main.last_result["earned"]])
		scraps_expected = sv.scrap
		# buy the cheapest thing we can
		var bought := false
		for u in tn.upgrades:
			if sv.can_buy(u["id"]) and not bought:
				var before: int = sv.level(u["id"])
				main.hud._row_btn[tn.upgrades.find(u)].pressed.emit()
				bought = sv.level(u["id"]) == before + 1
				scraps_expected = sv.scrap
				check(bought, "run %d: buying %s raises its level" % [run + 1, u["name"]])
				check(main.flight.lv_ramp + main.flight.lv_wings + main.flight.lv_body + main.flight.lv_booster + main.flight.lv_magnet == total_levels(), "run %d: the glider on the ramp is rebuilt with the new level" % (run + 1))
		if run == 0:
			baseline = snapshot(main)
			print("  baseline after run 1: " + describe(baseline))
		else:
			var now := snapshot(main)
			check(same_world(baseline, now), "run %d: nothing new was created (%s)" % [run + 1, describe(now)])
	check(sv.best_distance > 20.0 and main.flight.best_x == sv.best_distance and main.world.best_text.contains("BEST"), "the best distance sets the marker in the world (%s)" % main.world.best_text)
	check(main.hud._shop_best.text.contains(tn.fmt(sv.best_distance)), "the best distance is shown in the shop")

	print("5. the BOOST button")
	sv.reset_all()
	sv.levels["booster"] = 2
	main._to_shop()
	main.hud._launch_btn.pressed.emit()
	for i in 90:
		main.frame(1.0 / 60.0, 1.0 / 60.0)
	main.hud.set_flight(main.flight.distance, main.flight.charges, main.flight.charges_max, false, false)
	var rect: Rect2 = main.hud.boost_rect()
	check(rect.size.x > 100.0, "the BOOST button is up while flying with a booster (%s)" % str(rect))
	var ch0: int = main.flight.charges
	touch(main, rect.get_center(), true, 3)
	check(main.flight.charges == ch0 - 1 and main.flight.boost_left > 0.0 and not main.is_holding(), "tapping BOOST fires a burst and does not pitch up")
	touch(main, rect.get_center(), false, 3)
	touch(main, Vector2(300, 600), true, 0)
	check(main.is_holding(), "a touch elsewhere holds the pitch-up")
	touch(main, Vector2(300, 600), false, 0)
	check(not main.is_holding(), "letting go releases it")
	fly_main(main)
	sv.reset_all()
	main._to_shop()

	print("5b. shared style: tokens, icons, buttons, safe areas, intro")
	var StyleS: GDScript = load("res://scripts/Style.gd")
	var GlyphsS: GDScript = load("res://scripts/Glyphs.gd")
	check(StyleS.SZ_XL == 110 and StyleS.SZ_M == 56 and StyleS.SZ_S == 30 and HudS.HERO == 110 and HudS.BODY == 56 and HudS.SMALL == 30, "the three text sizes are the shared Style sizes")
	check(StyleS.display() != null and StyleS.text() != null and StyleS.display().get_string_size("1234 m", HORIZONTAL_ALIGNMENT_LEFT, -1, 56).x > 50.0, "the shared fonts (Fredoka, Nunito) load and measure text")
	var icon_host := Control.new()
	main.add_child(icon_host)
	var missing := 0
	for gid in GlyphsS.ALL:
		var gv := GlyphView.new()
		gv.size = Vector2(64, 64)
		gv.set_glyph(gid)
		icon_host.add_child(gv)
	await process_frame
	check(GlyphsS.ALL.size() >= 50 and icon_host.get_child_count() == GlyphsS.ALL.size(), "the icon set draws every glyph (%d)" % GlyphsS.ALL.size())
	icon_host.queue_free()
	var need_icons: Array[String] = []
	for u in tn.upgrades:
		need_icons.append(u["id"])
	for fd5 in tn.frames:
		need_icons.append(fd5["id"])
	for ld5 in tn.launchers:
		need_icons.append(ld5["id"])
	for hd5 in Cosmetics.hats:
		if hd5["id"] != "none":
			need_icons.append("hat_" + hd5["id"])
	for td5 in Cosmetics.trails:
		if td5["id"] != "none":
			need_icons.append("trail_" + td5["id"])
	for mt5 in MissionsS.TYPES:
		need_icons.append(mt5)
	var not_in_set: Array[String] = []
	for gid in need_icons:
		if not GlyphsS.ALL.has(gid):
			not_in_set.append(gid)
	check(not_in_set.is_empty(), "every upgrade, frame, launcher, hat, trail and mission has an icon (missing: %s)" % str(not_in_set))
	check(main.hud._launch_btn.get_theme_stylebox("normal").bg_color == StyleS.SUCCESS and main.hud._launch_btn.get_theme_stylebox("pressed") != main.hud._launch_btn.get_theme_stylebox("normal"), "LAUNCH is the primary button: green with a lip, and a distinct pressed look")
	# safe areas: a second HUD built with insets keeps everything inside them
	StyleS.set_safe(120.0, 90.0, 0.0, 0.0)
	var safe_hud: Node = HudS.new()
	main.add_child(safe_hud)
	check(safe_hud._dist.offset_top >= 120.0 and safe_hud._top_row.offset_top >= 120.0 and safe_hud._stack.offset_bottom <= -90.0, "safe areas: top pieces sit below the notch, the launch stack above the home indicator")
	safe_hud.queue_free()
	StyleS.set_safe(0.0, 0.0, 0.0, 0.0)
	# the logo intro: studio name then the title, any tap skips it
	HudS.intro_enabled = true
	main.hud.play_intro()
	check(main.hud.intro_active and main.hud._intro.visible, "the logo intro plays when enabled")
	touch(main, Vector2(500, 900), true)
	touch(main, Vector2(500, 900), false)
	for k in 200:
		main.hud._process(0.016)
	check(not main.hud.intro_active and not main.hud._intro.visible, "a tap skips the intro, and it ends by itself")
	HudS.intro_enabled = false

	print("5c. motion and screens (transitions on)")
	HudS.animate = true
	main.hud.settle()
	main._to_shop()
	main.hud.settle()
	var hm: Node = main.hud
	# a sheet rises in and sinks out
	hm.show_tab(1)
	hm._process(0.05)
	check(hm._sheet.visible and hm._sheet.modulate.a < 1.0 and hm._sheet.scale.x < 1.0, "the garage sheet rises in (alpha %.2f, scale %.2f)" % [hm._sheet.modulate.a, hm._sheet.scale.x])
	for k in 40:
		hm._process(0.02)
	check(hm._sheet.visible and is_equal_approx(hm._sheet.modulate.a, 1.0) and is_equal_approx(hm._sheet.scale.x, 1.0), "the sheet settles at full size")
	hm.close_sheet()
	hm._process(0.03)
	check(hm._sheet.visible, "closing is a short animation, not a cut")
	for k in 30:
		hm._process(0.02)
	check(not hm._sheet.visible, "and then the sheet is gone")
	# buttons squash on press, bounce back on release, with sound
	var press_before5c := int(main.sfx.plays["press"])
	var tap_before5c := int(main.sfx.plays["tap"])
	hm._nav_buttons[2].button_down.emit()
	hm._process(0.12)
	check(hm._nav_buttons[2].scale.x < 0.96, "a pressed button squashes (%.3f)" % hm._nav_buttons[2].scale.x)
	hm._nav_buttons[2].button_up.emit()
	hm._nav_buttons[2].pressed.emit()
	for k in 40:
		hm._process(0.02)
	check(is_equal_approx(hm._nav_buttons[2].scale.x, 1.0) and int(main.sfx.plays["press"]) == press_before5c + 1 and int(main.sfx.plays["tap"]) == tap_before5c + 1, "released: back to size, with the press and tap sounds")
	hm.close_sheet()
	for k in 30:
		hm._process(0.02)
	# the buy sequence: card flash, pip pop, scrap flies to the glider, then the part bolts on with a clank
	sv.add_scrap(2000.0)
	main.world.pulse = 0.0
	var clanks5c := int(main.sfx.plays["clank"])
	var lvb5c: int = sv.level("wings")
	hm._row_btn[1].pressed.emit()
	check(sv.level("wings") == lvb5c + 1 and hm._card_flash[1] > 0.9 and hm._card_pips[1].pop > 0.9, "buying: the card flashes and the new level pip pops")
	var flying := 0
	for n in hm._fly_nodes:
		if n.visible:
			flying += 1
	check(flying >= 3 and main.world.pulse == 0.0, "scrap flies off the counter first (%d coins), the glider has not changed yet" % flying)
	for k in 60:
		hm._process(0.02)
	check(main.world.pulse > 0.0 and int(main.sfx.plays["clank"]) == clanks5c + 1, "when the scrap lands the part bolts on: pulse and a clank")
	# results: the distance counts up, a new best stamps in, scrap flies to the counter
	main.last_result = {"distance": 321.0, "earned": 90, "dist_scrap": 40, "picked": 50, "picked_count": 5, "new_best": true, "zone_bonus": 0, "zone": 2,
			"new_zones": 0, "mission_bonus": 0, "missions": [], "new_missions": [], "rusty": "Hi.", "daily": {}, "doubled": false}
	hm.refresh_shop(main.last_result)
	hm.show_results(true)
	hm._process(0.5)
	check(hm._res_dist.text != "321 m" and hm._res_badge.modulate.a < 1.0, "results: the distance is still counting (%s) and NEW BEST has not landed" % hm._res_dist.text)
	for k in 90:
		hm._process(0.02)
	check(hm._res_dist.text == "321 m" and hm._res_badge.modulate.a > 0.9 and int(main.sfx.plays["best"]) >= 1 and int(main.sfx.plays["tick"]) > 3, "results: counted up to 321 m, NEW BEST stamped in with its fanfare")
	for k in 120:
		hm._process(0.02)
	check(hm._shop_scrap.text == "SCRAP  %s" % tn.fmt(sv.scrap), "results: the scrap reached the counter")
	hm.show_results(false)
	for k in 30:
		hm._process(0.02)
	# a zone postcard sweeps across
	hm.set_mode(0)
	hm.settle()
	hm.set_mode(1)
	hm.banner("NEW ZONE!\nRIVER\n+120 scrap", HudS.C_ACCENT)
	hm._process(0.1)
	check(hm._banner.visible and hm._banner.offset_left < -460.0, "zone postcard: sweeping in from the left")
	for k in 40:
		hm._process(0.02)
	check(is_equal_approx(hm._banner.offset_left, -460.0), "zone postcard: rests in the middle")
	for k in 100:
		hm._process(0.02)
	check(not hm._banner.visible, "zone postcard: swept out and gone")
	hm.set_mode(0)
	hm.settle()
	# Rusty reacts
	hm._rusty.react("grin")
	check(hm._rusty.mood == "grin", "Rusty's portrait reacts")
	# the launch screen is alive
	check(main.world.ambience, "the launch screen has its ambience on")
	main.world.clear_particles()
	for k in 30:
		main.frame(0.05, 0.05)
	check(main.world.live_particles() > 0, "the grinder throws sparks (%d live)" % main.world.live_particles())
	# pause: the button, the card, freezing the flight, restart, quit, volume, focus loss
	main._to_shop()
	hm.settle()
	main.launch()
	for k in 5:
		main.frame(1.0 / 60.0, 1.0 / 60.0)
	check(hm.pause_rect().size.x > 50.0, "flight: a pause button is in the top corner")
	touch(main, hm.pause_rect().get_center(), true)
	check(not main.is_holding(), "touching the pause button does not steer")
	touch(main, hm.pause_rect().get_center(), false)
	hm._pause_btn.pressed.emit()
	check(main.paused and hm.pause_active and hm._pause.visible, "the pause card opens")
	var px05c: float = main.flight.x
	for k in 20:
		main.frame(1.0 / 60.0, 1.0 / 60.0)
	check(main.flight.x == px05c, "paused: nothing moves")
	main._on_volume("SFX", 0.4)
	main._on_volume("Music", 0.0)
	check(is_equal_approx(sv.sfx_vol, 0.4) and sv.music_vol == 0.0 and is_equal_approx(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("SFX")), linear_to_db(0.4)), "the sliders set the SFX and music volumes (and save them)")
	hm.resume_pressed.emit()
	check(not main.paused and not hm.pause_active, "Resume closes the card")
	for k in 40:
		main.frame(1.0 / 60.0, 1.0 / 60.0)
	check(main.flight.x > px05c, "and the flight carries on")
	main._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(main.paused, "losing focus pauses the flight by itself")
	main._notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	var rc5c: int = main.restart_count
	hm.restart_pressed.emit()
	check(main.state == main.STATE_FLIGHT and not main.paused and main.restart_count == rc5c + 1 and main.flight.x < px05c + 5.0, "Restart starts a fresh flight")
	main.set_paused(true)
	hm.quit_pressed.emit()
	check(main.state == main.STATE_SHOP and not main.paused and not hm.pause_active, "Quit goes back to the launch screen")
	sv.sfx_vol = 1.0
	sv.music_vol = 1.0
	main._on_volume("SFX", 1.0)
	main._on_volume("Music", 1.0)
	HudS.animate = false
	hm.settle()

	print("5d. in-game polish: launch sequences, flight fx, landing, popups, outlines")
	main._to_shop()
	# each launcher has a launch sequence: rumble (ramp, sled) before the lip and a camera kick at it
	for lid5d in ["ramp", "sling", "catapult", "sled"]:
		sv.launchers_owned[lid5d] = true
		sv.launcher = lid5d
		main._to_shop()
		main.launch()
		if main.flight.phase == main.flight.PH_AIM:
			main.flight.set_aim(1.0, tn.sling_default_angle)
			main.flight.fire()
		var max_rumble := 0.0
		var max_kick := 0.0
		var steps := 0
		while main.flight.phase != main.flight.PH_AIR and steps < 900:
			main.frame(1.0 / 60.0, 1.0 / 60.0)
			max_rumble = maxf(max_rumble, main.world.rumble)
			steps += 1
		for k in 4:
			main.frame(1.0 / 60.0, 1.0 / 60.0)
			max_kick = maxf(max_kick, main._kick)
		var wants_rumble: bool = lid5d == "ramp" or lid5d == "sled"
		check((max_rumble > 0.2) == wants_rumble and max_kick > 0.4, "%s launch: rumble %.2f, camera kick %.2f at the lip" % [lid5d, max_rumble, max_kick])
	sv.launcher = "ramp"
	# speed lines and wind at speed
	main._to_shop()
	main.launch()
	while main.flight.phase != main.flight.PH_AIR:
		main.frame(1.0 / 60.0, 1.0 / 60.0)
	main.world.clear_particles()
	main.flight.vx = 60.0
	main.flight.vy = 0.0
	for k in 40:
		main.frame(1.0 / 60.0, 1.0 / 60.0)
		main.flight.vx = maxf(main.flight.vx, 55.0)
	check(main.world.speed_fx > 0.3 and main.world.live_particles() > 0, "at speed: speed lines (%.2f) and wind streaks (%d particles)" % [main.world.speed_fx, main.world.live_particles()])
	# a chunky landing: debris, a hard kick, then the glider tumbles and hops along
	main._kick = 0.0
	main.flight._touch_down()
	for k in 3:
		main.frame(1.0 / 60.0, 1.0 / 60.0)
	check(main._kick > 0.6 and main.world.live_particles() > 8, "landing: a hard camera kick (%.2f) and a burst of debris (%d)" % [main._kick, main.world.live_particles()])
	var tumble_seen := 0.0
	for k in 20:
		main.frame(1.0 / 60.0, 1.0 / 60.0)
		tumble_seen = maxf(tumble_seen, absf(main.world.tumble))
	check(tumble_seen > 0.5, "landing: the glider tumbles (%.2f rad)" % tumble_seen)
	main._to_shop()
	check(main.world.tumble == 0.0 and main.world.hop == 0.0 and main.world.rumble == 0.0, "back on the launch screen the glider is upright again")
	# feedback popups are chips: a pill with an icon, sized to the words
	main.hud.set_mode(1)
	main.hud.popup("BOUNCE! +speed", Vector2(540, 800), HudS.C_ACCENT, "bounce")
	main.hud.popup("OK", Vector2(540, 600), HudS.C_GOLD, "scrap")
	var pc_long: Control = main.hud._pop_labels[(main.hud._next_pop + main.hud.POPUPS - 2) % main.hud.POPUPS]
	var pc_short: Control = main.hud._pop_labels[(main.hud._next_pop + main.hud.POPUPS - 1) % main.hud.POPUPS]
	check(pc_long.size.x > pc_short.size.x + 150.0 and pc_long.size.y >= 80.0, "popup chips are sized to their words (%.0f vs %.0f px)" % [pc_long.size.x, pc_short.size.x])
	check(main.hud._pop_icons[(main.hud._next_pop + main.hud.POPUPS - 2) % main.hud.POPUPS].id == "bounce", "and carry the icon of what happened")
	main.hud.set_mode(0)
	# scenery has no outlines; interactive objects keep theirs
	main.world._outline = false
	check(main.world._ink().a == 0.0, "scenery lines are invisible (no outlines on scenery)")
	main.world._outline = true
	check(main.world._ink() == Color(0, 0, 0), "interactive objects keep their black outline")
	main._to_shop()

	print("6. save file")
	sv.reset_all()
	sv.add_scrap(321.0)
	sv.levels["wings"] = 4
	sv.record_run(222.7, 150.0)
	var fcheck := FileAccess.open(sv.path, FileAccess.READ)
	var parsed = JSON.parse_string(fcheck.get_as_text())
	fcheck.close()
	check(parsed is Dictionary and int(parsed["version"]) == sv.VERSION, "the save is versioned JSON")
	sv.load_game()
	check(sv.level("wings") == 4 and sv.best_distance == 222.0 and sv.scrap == 471.0 and sv.runs == 1, "save round trip (scrap %s, best %s)" % [sv.scrap, sv.best_distance])
	var fw := FileAccess.open(sv.path, FileAccess.WRITE)
	fw.store_string("{ not json")
	fw.close()
	sv.load_game()
	check(sv.scrap == 0.0 and sv.level("wings") == 0, "a corrupt save falls back to a fresh start")
	fw = FileAccess.open(sv.path, FileAccess.WRITE)
	fw.store_string(JSON.stringify({"scrap": 50, "levels": {"ramp": 99, "bogus": 3}}))
	fw.close()
	sv.load_game()
	check(sv.scrap == 50.0 and sv.level("ramp") == tn.max_level("ramp"), "an old/odd save is migrated and clamped")
	sv.reset_all()
	check(not sv.buy("ramp") and sv.scrap == 0.0, "can't buy without enough scrap")
	sv.add_scrap(tn.upgrade_cost("ramp", 0))
	check(sv.buy("ramp") and sv.level("ramp") == 1 and sv.scrap == 0.0, "buying spends the scrap and raises the level")
	sv.reset_all()
	main._to_shop()

	print("7. ?tune panel")
	var tp: Node = main.tune_panel
	check(tp != null and tp.ENTRIES.size() >= 30, "the tuning panel has %d sliders" % tp.ENTRIES.size())
	var before_nodes := snapshot(main)
	tp.open()
	check(paused and tp.is_open and tp._panel.visible, "opening the panel pauses the game")
	var g0: float = tn.gravity
	tp._sliders["gravity"].value = 6.0
	check(is_equal_approx(tn.gravity, 6.0), "a slider edits Tuning live")
	tp._sliders["lift_k"].value = 0.05
	check(tp.changed_text().contains("gravity = 6.0") and tp.changed_text().contains("lift_k = 0.050"), "Copy values lists only what changed")
	tp.copy_values()
	check(tp.last_copied_text.contains("gravity"), "Copy values fills the clipboard text")
	tp.reset_defaults()
	check(is_equal_approx(tn.gravity, g0) and tp.changed_text() == "(no changes)", "Reset restores the defaults")
	sv.reset_all()
	sv.ensure_missions(RandomNumberGenerator.new())
	var old_missions: Array = sv.missions.duplicate(true)
	var old_rewards := 0
	for m in old_missions:
		old_rewards += int(m["reward"])
	tp.complete_all_missions()
	check(sv.scrap == old_rewards and sv.missions.size() == 3, "?tune: Complete missions pays them and draws new ones (+%d)" % old_rewards)
	tp.close()
	check(not paused and not tp._panel.visible, "closing resumes")
	check(same_world(before_nodes, snapshot(main)), "using the panel creates nothing")
	DebugFlags.parse([])
	check(not DebugFlags.tune_enabled(), "no ?tune, no panel")

	print("8. debug flags")
	DebugFlags.parse(["perf", "tune", "noprewarm", "v=abc123", "bogus"])
	check(DebugFlags.perf and DebugFlags.tune and DebugFlags.noprewarm and DebugFlags.summary().contains("?bogus") and not DebugFlags.summary().contains("v"), "?perf ?tune ?noprewarm parse, ?v= is ignored, typos are listed")
	DebugFlags.parse([])
	check(DebugFlags.summary() == "" and DebugFlags.prewarm_enabled(), "no flags, no summary")
	check(not DebugFlags.stamp_visible(), "players never see the build stamp")
	DebugFlags.parse(["debug"])
	check(DebugFlags.stamp_visible(), "?debug shows the build stamp")
	DebugFlags.parse(["tune"])
	check(DebugFlags.stamp_visible(), "?tune shows the build stamp")
	DebugFlags.parse([])
	var plain_hud: Node = HudS.new()
	main.add_child(plain_hud)
	check(not plain_hud._stamp.visible and main.hud._stamp.visible, "the HUD's stamp is hidden by default and shown with ?tune")
	plain_hud.queue_free()
	check(HudS.STUDIO_NAME.replace("\n", " ") == "Clear Prop Games", "the studio name is Clear Prop Games")

	var fd := DirAccess.open("user://")
	if fd != null:
		fd.remove("smoke_test_save.json")
	if failures.is_empty():
		print("SMOKE TEST PASSED")
		quit(0)
	else:
		print("SMOKE TEST FAILED: %d" % failures.size())
		for x in failures:
			print("  - " + x)
		quit(1)
