extends SceneTree
## Balance sim:  godot --headless --path . --script res://tests/glide_sim.gd
## Flies the real physics with a simple pilot (no rendering) over many seeds and prints how far each
## upgrade level gets, plus an "upgrade ladder" showing the economy: a player who always buys the
## cheapest affordable upgrade. Used to tune Tuning.gd; the smoke test checks the same properties.
##   -- bands   time in each altitude band, interactions per flight (by kind and band) and the empty-sky gaps
##   -- ladder  just the economy ladder          -- gear  frames and launchers

const SEEDS := 10

var tn: Node

func fly(levels: Dictionary, seed_value: int, mode: int = 0):
	var f = load("res://scripts/Flight.gd").new()
	f.reset(levels, seed_value)
	f.launch_auto()
	var t := 0.0
	var hold := false
	while not f.is_over() and t < 400.0:
		match mode:
			0: hold = f.pilot(1.0 / 60.0, 1.0)      # good pilot
			1: hold = f.pilot(1.0 / 60.0, 3.0)      # sluggish pilot
			2: hold = false                          # never touches the screen
			3: hold = true                           # holds forever
			4: hold = f.pilot(1.0 / 60.0, 1.0, true) # a player who goes for the prizes (rings, balloons, blimps, streams, scrap)
		f.advance(1.0 / 60.0, hold)
		f.ev_n = 0
		t += 1.0 / 60.0
	return f

var _cache := {}

func avg(levels: Dictionary, mode: int = 0) -> Dictionary:
	var key := str(levels) + str(mode)
	if _cache.has(key):
		return _cache[key]
	var r := _avg(levels, mode)
	_cache[key] = r
	return r

func _avg(levels: Dictionary, mode: int) -> Dictionary:
	var sum := 0.0
	var scrap := 0.0
	var mx := 0.0
	var mn := 1e9
	for s in SEEDS:
		var f = fly(levels, 1000 + s, mode)
		sum += f.distance
		scrap += f.scrap_total()
		mx = maxf(mx, f.distance)
		mn = minf(mn, f.distance)
	return {"dist": sum / SEEDS, "scrap": scrap / SEEDS, "min": mn, "max": mx}

func lv(r := 0, w := 0, b := 0, bo := 0, m := 0) -> Dictionary:
	return {"ramp": r, "wings": w, "body": b, "booster": bo, "magnet": m}

func _initialize() -> void:
	tn = root.get_node("Tuning")
	var args := OS.get_cmdline_user_args()
	if args.has("bands"):
		bands()
	elif args.has("gear"):
		gear()
	else:
		if not args.has("ladder"):
			singles()
		ladder()
	quit(0)

## Altitude bands: how a typical flight spends its time in each band, what it reacts to, and whether the sky is ever empty.
## Two pilots: 0 = passive (just glides well) and 4 = a player who goes for the prizes. Printed per upgrade level.
func bands() -> void:
	var seeds := 12
	var names := ["pads", "fans", "scrap", "birds", "balloons", "kites", "geese", "rings", "streams", "blimps", "storms", "finds", "skips"]
	for lvl in [0, 3, 6, 10]:
		for mode in [0, 4]:
			var levels := lv(lvl, lvl, lvl, mini(lvl, 8), 0)
			var share := [0.0, 0.0, 0.0, 0.0]
			var hits := [0.0, 0.0, 0.0, 0.0]
			var kinds := {}
			for n in names:
				kinds[n] = 0.0
			var dist := 0.0
			var scrap := 0.0
			var bonus := 0.0
			var inter := 0.0
			var air_t := 0.0
			var worst_gap := 0.0
			var long_gap_flights := 0
			var gap_total := 0.0
			for sd in seeds:
				var f = load("res://scripts/Flight.gd").new()
				f.reset(levels, 2000 + sd)
				f.launch_auto()
				var t := 0.0
				var gap := 0.0
				var fgap := 0.0
				while not f.is_over() and t < 400.0:
					var hold: bool = f.pilot(1.0 / 60.0, 1.0, mode == 4)
					f.advance(1.0 / 60.0, hold)
					f.ev_n = 0
					t += 1.0 / 60.0
					if f.phase == f.PH_AIR:
						# is there something worth reacting to on screen? (the screen shows about 24 m ahead and 24 m up and down)
						var any := false
						for i in f.MAX_THINGS:
							if f.t_active[i] != 0 and f.t_x[i] >= f.x - 4.0 and f.t_x[i] < f.x + 24.0 and absf(f.t_y[i] - f.y) <= 24.0:
								any = true
								break
						if any:
							gap = 0.0
						else:
							gap += 1.0 / 60.0
							gap_total += 1.0 / 60.0
							fgap = maxf(fgap, gap)
				worst_gap = maxf(worst_gap, fgap)
				if fgap > 2.0:
					long_gap_flights += 1
				dist += f.distance
				scrap += f.scrap_total()
				bonus += f.bonus_scrap
				inter += f.interactions
				for b in 4:
					share[b] += f.band_time[b]
					hits[b] += f.band_hits[b]
					air_t += f.band_time[b]
				kinds["pads"] += f.pad_bounces
				kinds["fans"] += f.fan_entries
				kinds["scrap"] += f.picked_count
				kinds["birds"] += f.bird_hits - f.goose_hits
				kinds["balloons"] += f.balloon_hits
				kinds["kites"] += f.kite_hits
				kinds["geese"] += f.goose_hits
				kinds["rings"] += f.rings_hit
				kinds["streams"] += f.stream_entries
				kinds["blimps"] += f.blimp_hits
				kinds["storms"] += f.storm_entries
				kinds["finds"] += f.finds
				kinds["skips"] += f.skips
			var line := "L%-2d %-8s %5.0f m  scrap %5.0f (height bonus %4.0f)  time in LOW/MID/HIGH/SKY: %2.0f/%2.0f/%2.0f/%2.0f%%  interactions %4.1f (by band %.1f/%.1f/%.1f/%.1f)" % [lvl, "passive" if mode == 0 else "seeking", dist / seeds, scrap / seeds, bonus / seeds,
					100.0 * share[0] / air_t, 100.0 * share[1] / air_t, 100.0 * share[2] / air_t, 100.0 * share[3] / air_t, inter / seeds, hits[0] / seeds, hits[1] / seeds, hits[2] / seeds, hits[3] / seeds]
			print(line)
			var kl := "      per flight:"
			for n in names:
				if kinds[n] > 0.0:
					kl += " %s %.1f" % [n, kinds[n] / seeds]
			kl += "   | interactions per 100 m %.1f, empty-sky: worst gap %.1f s, %d of %d flights over 2 s, %.1f s per flight" % [100.0 * inter / maxf(dist, 1.0), worst_gap, long_gap_flights, seeds, gap_total / seeds]
			print(kl)

## Frames and launchers: same upgrades, different gear.
func gear() -> void:
	for lvl in [0, 3, 6]:
		var base := lv(lvl, lvl, lvl, mini(lvl, 3), 0)
		var line := "levels %d:" % lvl
		for f in tn.frames:
			var d := base.duplicate()
			d["frame"] = f["id"]
			var a := avg(d)
			line += "  %s %.0f m (%.0f scrap)" % [f["id"], a["dist"], a["scrap"]]
		print(line)
	for lvl in [0, 3, 6]:
		var base := lv(lvl, lvl, lvl, mini(lvl, 3), 0)
		var line := "launchers at level %d:" % lvl
		for l in tn.launchers:
			var d := base.duplicate()
			d["launcher"] = l["id"]
			var a := avg(d)
			line += "  %s %.0f m" % [l["id"], a["dist"]]
		print(line)
	var top := lv(10, 10, 10, 8, 8)
	var line2 := "maxed:"
	for l in tn.launchers:
		var d2 := top.duplicate()
		d2["launcher"] = l["id"]
		line2 += "  %s %.0f m" % [l["id"], avg(d2)["dist"]]
	print(line2)

func singles() -> void:
	var base := avg(lv())
	print("BASE (all level 0), good pilot: %.0f m avg (min %.0f max %.0f), scrap %.0f" % [base["dist"], base["min"], base["max"], base["scrap"]])
	for mode in [1, 2, 3]:
		var a := avg(lv(), mode)
		print("  pilot mode %d: %.0f m (min %.0f max %.0f)" % [mode, a["dist"], a["min"], a["max"]])
	for id in ["ramp", "wings", "body", "booster", "magnet"]:
		var line := "%-8s" % id
		for l in [1, 2, 3, 5, 8, 10]:
			if l > tn.max_level(id):
				continue
			var d := lv()
			d[id] = l
			line += "  L%d: %.0f m" % [l, avg(d)["dist"]]
		print(line)
	print("ALL +1 / +2 / +3 / +5 / +8 / max:")
	for l in [1, 2, 3, 5, 8, 10]:
		var a := avg(lv(l, l, l, mini(l, 8), mini(l, 8)))
		print("  all L%d: %.0f m avg, scrap %.0f (min %.0f max %.0f)" % [l, a["dist"], a["scrap"], a["min"], a["max"]])
	# The economy: always buy the cheapest affordable upgrade, runs until everything is maxed.

func ladder() -> void:
	print("LADDER (buys the cheapest upgrade it can afford after each run):")
	var levels := lv()
	var scrap := 0.0
	var run := 0
	var bought := 0
	while run < 400:
		run += 1
		var a := avg(levels)
		scrap += a["scrap"]
		var changed := true
		while changed:
			changed = false
			var best_id := ""
			var best_cost := INF
			for u in tn.upgrades:
				var id: String = u["id"]
				if levels[id] < u["max"]:
					var c: float = tn.upgrade_cost(id, levels[id])
					if c <= scrap and c < best_cost:
						best_cost = c
						best_id = id
			if best_id != "":
				scrap -= best_cost
				levels[best_id] += 1
				bought += 1
				changed = true
		if run <= 12 or run % 5 == 0:
			print("  run %3d: %.0f m  scrap/run %.0f  upgrades bought %d  levels r%d w%d b%d bo%d m%d" % [run, a["dist"], a["scrap"], bought, levels["ramp"], levels["wings"], levels["body"], levels["booster"], levels["magnet"]])
		var done := true
		for u in tn.upgrades:
			if levels[u["id"]] < u["max"]:
				done = false
		if done:
			print("  everything maxed after %d runs" % run)
			break
	quit(0)
