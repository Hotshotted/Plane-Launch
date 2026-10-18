extends Node
## Persistent progress in one small JSON file in user:// (in the web build that is the browser's
## IndexedDB, so it survives reloads). Only written when something changes between runs (a run
## ends, a purchase, a debug button), never while flying. Autoload name: Save.

## Emitted whenever the stored data changed (the shop refreshes its texts from it).
signal changed

## Bump when the file layout changes, and teach _migrate() how to read the old one.
##   1: scrap, best_distance, runs, total_distance, levels
##   2: seen (which things have been explained by a first-time popup)
##   3: zone_best (farthest zone reached; each zone pays its bonus once)
##   4: missions (three active), missions_done
##   5: frames owned + equipped, launchers owned + equipped
const VERSION := 5

var path := "user://save.json"      # (tests point this somewhere else)
var scrap := 0.0
var best_distance := 0.0            # meters, the farthest touchdown so far
var runs := 0
var total_distance := 0.0
var levels := {}                    # upgrade id -> level
var frames_owned := {"scrapper": true}
var frame := "scrapper"            # equipped frame
var launchers_owned := {"ramp": true}
var launcher := "ramp"             # equipped launcher
var missions: Array = []             # three active missions (see Missions.gd)
var missions_done := 0
var zone_best := 0                  # index of the farthest zone ever reached
var seen := {}                      # thing id -> true once its first-time popup was shown (saved when a run ends)

func _ready() -> void:
	load_game()

func _defaults() -> void:
	scrap = 0.0
	best_distance = 0.0
	runs = 0
	total_distance = 0.0
	levels = {}
	seen = {}
	zone_best = 0
	missions = []
	missions_done = 0
	frames_owned = {"scrapper": true}
	frame = "scrapper"
	launchers_owned = {"ramp": true}
	launcher = "ramp"
	for u in Tuning.upgrades:
		levels[u["id"]] = 0

## Read the save file; a missing, unreadable or corrupt file just means a fresh start.
func load_game() -> void:
	_defaults()
	if FileAccess.file_exists(path):
		var f := FileAccess.open(path, FileAccess.READ)
		if f != null:
			var parsed: Variant = JSON.parse_string(f.get_as_text())
			f.close()
			if parsed is Dictionary:
				_apply(_migrate(parsed))
	changed.emit()

## Bring an older file layout up to the current one. Version 0 = a file without a "version" field.
## Unknown extra fields are ignored, missing ones fall back to defaults.
func _migrate(d: Dictionary) -> Dictionary:
	var v := int(d.get("version", 0))
	if v < 1:
		d["version"] = 1   # v0 -> v1: same fields, just stamped with a version
		v = 1
	if v < 2:
		if not d.has("seen"):
			d["seen"] = {}     # v1 -> v2: nothing explained yet
		d["version"] = 2
		v = 2
	if v < 3:
		if not d.has("zone_best"):
			d["zone_best"] = 0  # v2 -> v3: no zones reached yet
		d["version"] = 3
		v = 3
	if v < 4:
		if not d.has("missions"):
			d["missions"] = []  # v3 -> v4: missions are made on first load
		if not d.has("missions_done"):
			d["missions_done"] = 0
		d["version"] = 4
		v = 4
	if v < 5:
		d["version"] = 5   # v4 -> v5: frames and launchers (the starters are always owned)
	return d

func _apply(d: Dictionary) -> void:
	scrap = maxf(float(d.get("scrap", 0.0)), 0.0)
	best_distance = maxf(float(d.get("best_distance", 0.0)), 0.0)
	runs = maxi(int(d.get("runs", 0)), 0)
	total_distance = maxf(float(d.get("total_distance", 0.0)), 0.0)
	var lv: Variant = d.get("levels", {})
	if lv is Dictionary:
		for u in Tuning.upgrades:
			levels[u["id"]] = clampi(int(lv.get(u["id"], 0)), 0, int(u["max"]))
	zone_best = clampi(int(d.get("zone_best", 0)), 0, Zones.COUNT - 1)
	missions_done = maxi(int(d.get("missions_done", 0)), 0)
	var ms: Variant = d.get("missions", [])
	if ms is Array:
		for m in ms:
			if m is Dictionary and Missions.TYPES.has(String(m.get("type", ""))):
				missions.append({"type": String(m["type"]), "target": maxi(int(m.get("target", 1)), 1), "reward": maxi(int(m.get("reward", 5)), 0), "zone": clampi(int(m.get("zone", 0)), 0, Zones.COUNT - 1)})
		missions = missions.slice(0, Missions.SLOTS)
	var fo: Variant = d.get("frames_owned", {})
	if fo is Dictionary:
		for f in Tuning.frames:
			if bool(fo.get(f["id"], false)):
				frames_owned[f["id"]] = true
	frame = String(d.get("frame", "scrapper"))
	if not frames_owned.has(frame):
		frame = "scrapper"
	var lo: Variant = d.get("launchers_owned", {})
	if lo is Dictionary:
		for l in Tuning.launchers:
			if bool(lo.get(l["id"], false)):
				launchers_owned[l["id"]] = true
	launcher = String(d.get("launcher", "ramp"))
	if not launchers_owned.has(launcher):
		launcher = "ramp"
	var sn: Variant = d.get("seen", {})
	if sn is Dictionary:
		for k in sn:
			if bool(sn[k]):
				seen[String(k)] = true

func to_dict() -> Dictionary:
	return {"version": VERSION, "scrap": scrap, "best_distance": best_distance, "runs": runs,
			"total_distance": total_distance, "levels": levels.duplicate(), "seen": seen.duplicate(), "zone_best": zone_best, "missions": missions.duplicate(true), "missions_done": missions_done,
			"frames_owned": frames_owned.duplicate(), "frame": frame, "launchers_owned": launchers_owned.duplicate(), "launcher": launcher}

func save_game() -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(to_dict()))
		f.close()
	changed.emit()

func level(id: String) -> int:
	return int(levels.get(id, 0))

func is_maxed(id: String) -> bool:
	return level(id) >= Tuning.max_level(id)

func cost_of_next(id: String) -> float:
	return Tuning.upgrade_cost(id, level(id))

func can_buy(id: String) -> bool:
	return not is_maxed(id) and scrap >= cost_of_next(id)

## Buy the next level of an upgrade. Returns false (and changes nothing) if maxed or too poor.
func buy(id: String) -> bool:
	if not can_buy(id):
		return false
	scrap -= cost_of_next(id)
	levels[id] = level(id) + 1
	save_game()
	return true

## End of a run: store the scrap earned, the best distance and the counters.
## Returns true if it is a new best distance.
func record_run(distance: float, earned: float) -> bool:
	distance = floorf(maxf(distance, 0.0))
	var best := distance > best_distance
	if best:
		best_distance = distance
	scrap += floorf(maxf(earned, 0.0))
	runs += 1
	total_distance += distance
	save_game()
	return best

## True the first time `id` is seen (and remembers it; written to the file when the run ends, never mid-flight).
func mark_seen(id: String) -> bool:
	if seen.has(id):
		return false
	seen[id] = true
	return true

## A run reached zone `zone_max`: every zone beyond the farthest one so far pays its bonus (once, ever).
## Returns {"bonus": scrap, "new": number of new zones}. Written by the record_run() that follows.
func claim_zones(zone_max: int) -> Dictionary:
	var bonus := 0
	var n := 0
	for i in range(zone_best + 1, mini(zone_max, Zones.COUNT - 1) + 1):
		bonus += Tuning.zone_bonus(i)
		n += 1
	zone_best = maxi(zone_best, mini(zone_max, Zones.COUNT - 1))
	return {"bonus": bonus, "new": n}

## Keep three missions active (made from the player's progress).
func ensure_missions(rng: RandomNumberGenerator) -> void:
	if missions.size() < Missions.SLOTS:
		Missions.fill(self, rng)

## Everything the flight needs to build the glider and its launcher: upgrade levels plus the equipped frame and launcher.
func loadout() -> Dictionary:
	var d := levels.duplicate()
	d["frame"] = frame
	d["launcher"] = launcher
	return d

func owns_frame(id: String) -> bool:
	return frames_owned.has(id)

func buy_frame(id: String) -> bool:
	var cost := Tuning.frame_cost(id)
	if owns_frame(id) or scrap < cost:
		return false
	scrap -= cost
	frames_owned[id] = true
	frame = id
	save_game()
	return true

func equip_frame(id: String) -> bool:
	if not owns_frame(id):
		return false
	frame = id
	save_game()
	return true

func owns_launcher(id: String) -> bool:
	return launchers_owned.has(id)

## Launchers are bought in order: the one before must be owned.
func can_buy_launcher(id: String) -> bool:
	var i := Tuning.launcher_index(id)
	return not owns_launcher(id) and i > 0 and owns_launcher(Tuning.launchers[i - 1]["id"]) and scrap >= Tuning.launcher_cost(id)

func buy_launcher(id: String) -> bool:
	if not can_buy_launcher(id):
		return false
	scrap -= Tuning.launcher_cost(id)
	launchers_owned[id] = true
	launcher = id
	save_game()
	return true

func equip_launcher(id: String) -> bool:
	if not owns_launcher(id):
		return false
	launcher = id
	save_game()
	return true

func add_scrap(n: float) -> void:
	scrap = maxf(scrap + n, 0.0)
	save_game()

func reset_all() -> void:
	_defaults()
	save_game()
