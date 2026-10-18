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
	f.launch()
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
	tn = root.get_node("Tuning")
	sv = root.get_node("Save")
	FlightS = load("res://scripts/Flight.gd")
	sv.path = "user://smoke_test_save.json"   # never touch a real save
	sv.reset_all()
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
	var scraps: Array[float] = []
	for run in 3:
		check(main.state == main.STATE_SHOP, "run %d: starts in the shop" % (run + 1))
		main.hud._launch_btn.pressed.emit()
		check(main.state == main.STATE_FLIGHT and main.hud._flight_root.visible and not main.hud._shop_root.visible, "run %d: LAUNCH starts the flight" % (run + 1))
		var secs := fly_main(main)
		check(main.state == main.STATE_SHOP, "run %d: back in the shop after the touchdown (%.1f s flown)" % [run + 1, secs])
		check(main.last_result.get("distance", 0.0) > 20.0 and main.hud._result.text.contains("LANDED"), "run %d: the result is shown (%s)" % [run + 1, main.hud._result.text.replace("\n", " | ")])
		check(sv.runs == run + 1 and sv.scrap > (scraps[-1] if scraps.size() > 0 else 0.0) - 1.0, "run %d: scrap and run count are saved" % (run + 1))
		scraps.append(sv.scrap)
		# buy the cheapest thing we can
		var bought := false
		for u in tn.upgrades:
			if sv.can_buy(u["id"]) and not bought:
				var before: int = sv.level(u["id"])
				main.hud._row_btn[tn.upgrades.find(u)].pressed.emit()
				bought = sv.level(u["id"]) == before + 1
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
	main.hud.set_flight(main.flight.distance, 0, 10.0, 10.0, false, main.flight.charges, main.flight.charges_max, false)
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
