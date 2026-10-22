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
##   6: cosmetics (owned + equipped paint, hat, trail), the daily launch (day, target, best, claimed), ad counters
const VERSION := 6

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
var cosmetics_owned := {}            # "paint:red" -> true ...
var paint := "default"
var hat := "none"
var trail := "none"
var daily_key := 0                   # the day (YYYYMMDD, UTC) the daily numbers belong to
var daily_target := 0                # meters to reach for the bonus
var daily_best := 0.0
var daily_claimed := false
var daily_plays := 0
var flights_since_ad := 0            # flights since the last interstitial stub
var day_key_override := 0            # (tests set a day)
var missions: Array = []             # three active missions (see Missions.gd)
var missions_done := 0
var zone_best := 0                  # index of the farthest zone ever reached
var sfx_vol := 1.0                  # settings (pause menu sliders), 0..1
var music_vol := 1.0
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
	sfx_vol = 1.0
	music_vol = 1.0
	missions = []
	missions_done = 0
	frames_owned = {"scrapper": true}
	frame = "scrapper"
	launchers_owned = {"ramp": true}
	launcher = "ramp"
	cosmetics_owned = {}
	paint = "default"
	hat = "none"
	trail = "none"
	daily_key = 0
	daily_target = 0
	daily_best = 0.0
	daily_claimed = false
	daily_plays = 0
	flights_since_ad = 0
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
		v = 5
	if v < 6:
		d["version"] = 6   # v5 -> v6: cosmetics, the daily launch (nothing owned / no day yet)
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
	sfx_vol = clampf(float(d.get("sfx_vol", 1.0)), 0.0, 1.0)
	music_vol = clampf(float(d.get("music_vol", 1.0)), 0.0, 1.0)
	missions_done = maxi(int(d.get("missions_done", 0)), 0)
	var ms: Variant = d.get("missions", [])
	if ms is Array:
		for m in ms:
			if m is Dictionary and Missions.TYPES.has(String(m.get("type", ""))):
				missions.append({"type": String(m["type"]), "target": maxi(int(m.get("target", 1)), 1), "reward": maxi(int(m.get("reward", 5)), 0), "zone": clampi(int(m.get("zone", 0)), 0, Zones.COUNT - 1), "best": maxi(int(m.get("best", 0)), 0), "fresh": false})
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
	var co: Variant = d.get("cosmetics_owned", {})
	if co is Dictionary:
		for k in co:
			if bool(co[k]) and String(k).contains(":"):
				cosmetics_owned[String(k)] = true
	paint = _equipped("paint", String(d.get("paint", "default")))
	hat = _equipped("hat", String(d.get("hat", "none")))
	trail = _equipped("trail", String(d.get("trail", "none")))
	daily_key = maxi(int(d.get("daily_key", 0)), 0)
	daily_target = maxi(int(d.get("daily_target", 0)), 0)
	daily_best = maxf(float(d.get("daily_best", 0.0)), 0.0)
	daily_claimed = bool(d.get("daily_claimed", false))
	daily_plays = maxi(int(d.get("daily_plays", 0)), 0)
	flights_since_ad = maxi(int(d.get("flights_since_ad", 0)), 0)
	var sn: Variant = d.get("seen", {})
	if sn is Dictionary:
		for k in sn:
			if bool(sn[k]):
				seen[String(k)] = true

func to_dict() -> Dictionary:
	return {"version": VERSION, "scrap": scrap, "best_distance": best_distance, "runs": runs,
			"total_distance": total_distance, "levels": levels.duplicate(), "seen": seen.duplicate(), "zone_best": zone_best, "missions": missions.duplicate(true), "missions_done": missions_done,
			"frames_owned": frames_owned.duplicate(), "frame": frame, "launchers_owned": launchers_owned.duplicate(), "launcher": launcher,
			"cosmetics_owned": cosmetics_owned.duplicate(), "paint": paint, "hat": hat, "trail": trail,
			"daily_key": daily_key, "daily_target": daily_target, "daily_best": daily_best, "daily_claimed": daily_claimed, "daily_plays": daily_plays,
			"flights_since_ad": flights_since_ad, "sfx_vol": sfx_vol, "music_vol": music_vol}

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

# ---- cosmetics ----
## The equipped id of a kind if it is owned (or the free starter), else the starter.
func _equipped(kind: String, id: String) -> String:
	return id if owns_cosmetic(kind, id) else Cosmetics.starter(kind)

func owns_cosmetic(kind: String, id: String) -> bool:
	return id == Cosmetics.starter(kind) or cosmetics_owned.has(kind + ":" + id)

func equipped(kind: String) -> String:
	match kind:
		"hat":
			return hat
		"trail":
			return trail
	return paint

func _set_equipped(kind: String, id: String) -> void:
	match kind:
		"hat":
			hat = id
		"trail":
			trail = id
		_:
			paint = id

func buy_cosmetic(kind: String, id: String) -> bool:
	var d := Cosmetics.def(kind, id)
	if d["id"] != id or owns_cosmetic(kind, id) or scrap < float(d["cost"]):
		return false
	scrap -= float(d["cost"])
	cosmetics_owned[kind + ":" + id] = true
	_set_equipped(kind, id)
	save_game()
	return true

func equip_cosmetic(kind: String, id: String) -> bool:
	if not owns_cosmetic(kind, id):
		return false
	_set_equipped(kind, id)
	save_game()
	return true

# ---- the daily launch ----
## Today as YYYYMMDD (UTC).
func day_key() -> int:
	if day_key_override > 0:
		return day_key_override
	var d := Time.get_date_dict_from_system(true)
	return int(d["year"]) * 10000 + int(d["month"]) * 100 + int(d["day"])

## The seed of today's world: the same for everyone on the same day.
func daily_seed(key: int = 0) -> int:
	return hash("junkyard-launch-%d" % (key if key > 0 else day_key())) & 0x7fffffff

## A new day starts a fresh target (stretching from the player's best) and clears yesterday's result.
## Returns true if a new day began. Not saved here: the next save writes it.
func refresh_daily() -> bool:
	var key := day_key()
	if key == daily_key and daily_target > 0:
		return false
	daily_key = key
	var r := RandomNumberGenerator.new()
	r.seed = daily_seed(key) + 17
	var base := maxf(best_distance, 120.0)
	daily_target = int(roundf(base * r.randf_range(0.8, 1.25) / 5.0)) * 5
	daily_best = 0.0
	daily_claimed = false
	daily_plays = 0
	return true

## Scrap for reaching today's target (paid once per day).
func daily_reward() -> int:
	return int(roundf((daily_target * 0.8 + 100.0) * Tuning.daily_reward_mult / 5.0)) * 5

func add_scrap(n: float) -> void:
	scrap = maxf(scrap + n, 0.0)
	save_game()

func reset_all() -> void:
	_defaults()
	save_game()
