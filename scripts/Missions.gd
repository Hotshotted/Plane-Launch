class_name Missions
extends RefCounted
## Three active missions at a time. Each is a small dictionary {type, target, reward, zone} stored in
## the save. They are checked when a flight ends against that flight's stats; a completed one pays its
## scrap and is replaced by a new one (never the same type as another active mission). Targets and
## rewards follow how far the player has got, so they are always a stretch but reachable.

const SLOTS := 3
const TYPES := ["bounce", "scrap", "distance", "noboost_zone", "skip", "updraft", "boost", "gear", "nobird"]

## Reward weight per type (harder missions pay more).
const WEIGHT := {"bounce": 0.9, "scrap": 0.9, "distance": 1.0, "noboost_zone": 1.6, "skip": 1.0, "updraft": 0.8, "boost": 0.7, "gear": 0.9, "nobird": 1.1}

static func _round5(v: float) -> int:
	return maxi(5, int(roundf(v / 5.0)) * 5)

## Can this type be offered right now (the player can actually do it)?
static func available(type: String, save: Node) -> bool:
	match type:
		"skip":
			return save.zone_best >= 2
		"boost":
			return save.level("booster") >= 1
		"noboost_zone":
			return save.zone_best + 1 < Zones.COUNT and Tuning.zone_start(save.zone_best + 1) <= maxf(save.best_distance, 60.0) * 1.7 + 60.0
	return true

## A new mission of `type` for the player's progress.
static func make(type: String, save: Node) -> Dictionary:
	var p := maxf(save.best_distance, 60.0)
	var target := 1
	var zone := 0
	match type:
		"bounce":
			target = mini(2 + int(p / 250.0), 8)
		"scrap":
			target = _round5(8.0 + p * 0.10)
		"distance":
			target = _round5(p * 1.25 + 20.0)
		"noboost_zone":
			zone = save.zone_best + 1
			target = zone
		"skip":
			target = mini(3 + int(p / 400.0), 8)
		"updraft":
			target = mini(2 + int(p / 300.0), 6)
		"boost":
			target = mini(save.level("booster"), 2 + int(p / 500.0))
		"gear":
			target = mini(1 + int(p / 200.0), 5)
		"nobird":
			target = _round5(p * 0.9 + 30.0)
	var reward := _round5((30.0 + p * 0.25) * float(WEIGHT[type]) * Tuning.mission_reward_mult)
	return {"type": type, "target": target, "reward": reward, "zone": zone, "best": 0, "fresh": false}

## A mission of a type not already active (and available).
static func pick(save: Node, active: Array, rng: RandomNumberGenerator) -> Dictionary:
	var pool: Array[String] = []
	for t in TYPES:
		var taken := false
		for m in active:
			if m["type"] == t:
				taken = true
		if not taken and available(t, save):
			pool.append(t)
	if pool.is_empty():
		pool.append("distance")
	return make(pool[rng.randi() % pool.size()], save)

## Top the list up to SLOTS missions.
static func fill(save: Node, rng: RandomNumberGenerator) -> void:
	while save.missions.size() < SLOTS:
		save.missions.append(pick(save, save.missions, rng))

static func describe(m: Dictionary) -> String:
	match m["type"]:
		"bounce":
			return "Bounce %d time%s in one flight" % [m["target"], "" if m["target"] == 1 else "s"]
		"scrap":
			return "Collect %d scrap in one flight" % m["target"]
		"distance":
			return "Fly %d m in one flight" % m["target"]
		"noboost_zone":
			return "Reach %s without boosting" % ("the " + Tuning.zone_name(m["zone"]) if m["zone"] in [2, 3, 4, 5, 6] else Tuning.zone_name(m["zone"]))
		"skip":
			return "Skip off the water %d times" % m["target"]
		"updraft":
			return "Ride %d updrafts in one flight" % m["target"]
		"boost":
			return "Use %d boost%s in one flight" % [m["target"], "" if m["target"] == 1 else "s"]
		"gear":
			return "Collect %d gear%s in one flight" % [m["target"], "" if m["target"] == 1 else "s"]
		"nobird":
			return "Fly %d m without hitting a bird" % m["target"]
	return "?"

## What a finished flight (stats) amounts to for this mission, in the mission's own units.
static func value_of(m: Dictionary, st: Dictionary) -> int:
	match m["type"]:
		"bounce":
			return int(st["pad_bounces"])
		"scrap":
			return int(st["picked_value"])
		"distance":
			return int(st["distance"])
		"noboost_zone":
			return int(st["zone_max"]) if st["boosts_used"] == 0 else 0
		"skip":
			return int(st["skips"])
		"updraft":
			return int(st["fan_entries"])
		"boost":
			return int(st["boosts_used"])
		"gear":
			return int(st["gears_picked"])
		"nobird":
			return int(st["distance"]) if st["bird_hits"] == 0 else 0
	return 0

## The same, read straight from a flight in progress (no allocation).
static func value_live(m: Dictionary, f) -> int:
	match m["type"]:
		"bounce":
			return f.pad_bounces
		"scrap":
			return f.picked_value
		"distance":
			return int(f.distance)
		"noboost_zone":
			return f.zone_max if f.boosts_used == 0 else 0
		"skip":
			return f.skips
		"updraft":
			return f.fan_entries
		"boost":
			return f.boosts_used
		"gear":
			return f.gears_picked
		"nobird":
			return int(f.distance) if f.bird_hits == 0 else 0
	return 0

## The short name used in toasts and next to the progress bar: "Bounces", "Scrap" ...
static func short_name(m: Dictionary) -> String:
	match m["type"]:
		"bounce":
			return "Bounces"
		"scrap":
			return "Scrap"
		"distance":
			return "Distance"
		"noboost_zone":
			return Tuning.zone_name(m["zone"]) + " (no boost)"
		"skip":
			return "Skips"
		"updraft":
			return "Updrafts"
		"boost":
			return "Boosts"
		"gear":
			return "Gears"
		"nobird":
			return "No birds"
	return "?"

## "Bounces 2/3" (distance ones add " m").
static func progress_text(m: Dictionary, value: int) -> String:
	var unit := " m" if m["type"] == "distance" or m["type"] == "nobird" else ""
	return "%s %d/%d%s" % [short_name(m), mini(value, int(m["target"])), int(m["target"]), unit]

## Best single-flight progress so far, 0..1 (for the bar on the clipboard).
static func fraction(m: Dictionary) -> float:
	return clampf(float(m.get("best", 0)) / maxf(float(m["target"]), 1.0), 0.0, 1.0)

## Is the mission done by a flight with these stats?
## stats: distance, picked_value, pad_bounces, skips, fan_entries, boosts_used, gears_picked, bird_hits, zone_max.
static func is_done(m: Dictionary, st: Dictionary) -> bool:
	match m["type"]:
		"bounce":
			return st["pad_bounces"] >= m["target"]
		"scrap":
			return st["picked_value"] >= m["target"]
		"distance":
			return st["distance"] >= m["target"]
		"noboost_zone":
			return st["zone_max"] >= m["zone"] and st["boosts_used"] == 0
		"skip":
			return st["skips"] >= m["target"]
		"updraft":
			return st["fan_entries"] >= m["target"]
		"boost":
			return st["boosts_used"] >= m["target"]
		"gear":
			return st["gears_picked"] >= m["target"]
		"nobird":
			return st["distance"] >= m["target"] and st["bird_hits"] == 0
	return false

## Check every active mission against a finished flight. Completed ones are replaced; returns them as
## [{text, reward}] (the caller pays the scrap).
static func evaluate(save: Node, st: Dictionary, rng: RandomNumberGenerator) -> Array[Dictionary]:
	var done: Array[Dictionary] = []
	for i in save.missions.size():
		var m: Dictionary = save.missions[i]
		m["best"] = maxi(int(m.get("best", 0)), mini(value_of(m, st), int(m["target"])))
		if is_done(m, st):
			done.append({"text": describe(m), "reward": m["reward"]})
	if not done.is_empty():
		var kept: Array = []
		for m in save.missions:
			if not is_done(m, st):
				kept.append(m)
		var n_kept := kept.size()
		save.missions = kept
		fill(save, rng)
		for i in range(n_kept, save.missions.size()):
			save.missions[i]["fresh"] = true
		save.missions_done += done.size()
	return done
