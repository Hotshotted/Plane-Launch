class_name Cosmetics
extends RefCounted
## Purely visual unlocks, bought with scrap: paint jobs for the glider, hats for the pilot (Whiskers),
## and trails. Each kind has a default (free, owned) and four to buy. Nothing here changes the physics.

const KINDS := ["paint", "hat", "trail"]
const KIND_NAMES := {"paint": "PAINT", "hat": "HATS", "trail": "TRAILS"}

## id, name, price. "color" (paint) is the body colour; "none" / "default" cost nothing.
static var paints: Array[Dictionary] = [
	{"id": "default", "name": "Junkyard Rust", "cost": 0.0, "color": Color(0, 0, 0, 0)},
	{"id": "red", "name": "Racing Red", "cost": 120.0, "color": Color(0.85, 0.15, 0.15)},
	{"id": "sky", "name": "Sky Blue", "cost": 200.0, "color": Color(0.25, 0.6, 0.95)},
	{"id": "lime", "name": "Lime Zest", "cost": 320.0, "color": Color(0.55, 0.85, 0.2)},
	{"id": "gold", "name": "Gold Plate", "cost": 700.0, "color": Color(0.98, 0.78, 0.2)},
]
static var hats: Array[Dictionary] = [
	{"id": "none", "name": "No Hat", "cost": 0.0},
	{"id": "cap", "name": "Baseball Cap", "cost": 80.0},
	{"id": "tophat", "name": "Top Hat", "cost": 180.0},
	{"id": "party", "name": "Party Hat", "cost": 280.0},
	{"id": "crown", "name": "Golden Crown", "cost": 650.0},
]
static var trails: Array[Dictionary] = [
	{"id": "none", "name": "No Trail", "cost": 0.0},
	{"id": "sparkle", "name": "Sparkles", "cost": 150.0},
	{"id": "smoke", "name": "Smoke Puffs", "cost": 250.0},
	{"id": "bubbles", "name": "Bubbles", "cost": 400.0},
	{"id": "rainbow", "name": "Rainbow", "cost": 900.0},
]

static func list_of(kind: String) -> Array[Dictionary]:
	match kind:
		"hat":
			return hats
		"trail":
			return trails
	return paints

static func def(kind: String, id: String) -> Dictionary:
	for d in list_of(kind):
		if d["id"] == id:
			return d
	return list_of(kind)[0]

## The free starter of a kind.
static func starter(kind: String) -> String:
	return list_of(kind)[0]["id"]
