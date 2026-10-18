extends SceneTree
## Balance sim:  godot --headless --path . --script res://tests/glide_sim.gd
## Flies the real physics with a simple pilot (no rendering) over many seeds and prints how far each
## upgrade level gets, plus an "upgrade ladder" showing the economy: a player who always buys the
## cheapest affordable upgrade. Used to tune Tuning.gd; the smoke test checks the same properties.

const SEEDS := 10

var tn: Node

func fly(levels: Dictionary, seed_value: int, mode: int = 0):
	var f = load("res://scripts/Flight.gd").new()
	f.reset(levels, seed_value)
	f.launch()
	var t := 0.0
	var hold := false
	while not f.is_over() and t < 400.0:
		match mode:
			0: hold = f.pilot(1.0 / 60.0, 1.0)      # good pilot
			1: hold = f.pilot(1.0 / 60.0, 3.0)      # sluggish pilot
			2: hold = false                          # never touches the screen
			3: hold = true                           # holds forever
		f.advance(1.0 / 60.0, hold)
		f.ev_n = 0
		t += 1.0 / 60.0
	return f

func avg(levels: Dictionary, mode: int = 0) -> Dictionary:
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
		if run <= 12 or run % 10 == 0:
			print("  run %3d: %.0f m  scrap/run %.0f  upgrades bought %d  levels r%d w%d b%d bo%d m%d" % [run, a["dist"], a["scrap"], bought, levels["ramp"], levels["wings"], levels["body"], levels["booster"], levels["magnet"]])
		var done := true
		for u in tn.upgrades:
			if levels[u["id"]] < u["max"]:
				done = false
		if done:
			print("  everything maxed after %d runs" % run)
			break
	quit(0)
