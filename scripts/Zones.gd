class_name Zones
extends RefCounted
## The journey: named zones by distance. Pure data (no autoload references), read by Flight (what
## spawns, gravity, what the ground does) and WorldView (palette and scenery). Distances are
## meters at zone_distance_mult = 1 (Tuning scales them for the ?tune panel).
##
## Palette order: 0 sky top, 1 sky middle, 2 sky low, 3 far hills, 4 near hills, 5 mid layer, 6 mid layer dark,
##                7 dirt, 8 ground top, 9 water / accent.
## Ground: 0 dirt, 1 water (skim it to skip), 2 cloud (bounces), 3 cheese, 4 disco floor.
## Far layer: 0 mountains, 1 skyline, 2 cloud bumps.
## Mid layer: 0 junk piles, 1 barns and silos, 2 houses, 3 trees, 4 pines, 5 skyscrapers, 6 palms, 7 cloud towers, 8 volcanoes.
## Props near the ground: 0 junk, 1 farm, 2 reeds, 3 town, 4 nature, 5 city, 6 beach, 7 clouds, 8 moon, 9 dino, 10 disco.
## Skins: pad 0 tyre, 1 hay bale, 2 awning, 3 beach ball; fan 0 fan, 1 windmill, 2 heat vent, 3 geyser.
## Weights: pattern chances [arc, line, pad, fan, bird, gear, low] times Tuning's own weights.

const COUNT := 11

static var list: Array[Dictionary] = [
	{"id": "junkyard", "name": "Junkyard", "start": 0.0, "bonus": 0,
		"pal": [Color(0.36, 0.64, 0.88), Color(0.58, 0.80, 0.93), Color(0.85, 0.92, 0.90), Color(0.52, 0.68, 0.74), Color(0.45, 0.58, 0.55), Color(0.50, 0.44, 0.40), Color(0.38, 0.34, 0.33), Color(0.42, 0.32, 0.24), Color(0.55, 0.44, 0.30), Color(0.4, 0.6, 0.8)],
		"ground": 0, "far": 0, "mid": 0, "props": 0, "pad_skin": 0, "fan_skin": 0, "gravity": 1.0, "bird_scale": 1.0, "raise": [0.0, 0.0], "fan_mult": 1.0, "bounce": 0.0,
		"weights": [3.0, 2.0, 1.5, 1.0, 1.0, 0.5, 0.6], "bird_color": Color(0.4, 0.34, 0.55)},
	{"id": "farmland", "name": "Farmland", "start": 150.0, "bonus": 120,
		"pal": [Color(0.40, 0.70, 0.95), Color(0.64, 0.86, 0.96), Color(0.92, 0.96, 0.84), Color(0.58, 0.78, 0.52), Color(0.46, 0.68, 0.42), Color(0.74, 0.30, 0.25), Color(0.55, 0.22, 0.2), Color(0.48, 0.36, 0.22), Color(0.45, 0.72, 0.30), Color(0.4, 0.6, 0.8)],
		"ground": 0, "far": 0, "mid": 1, "props": 1, "pad_skin": 1, "fan_skin": 1, "gravity": 1.0, "bird_scale": 1.0, "raise": [0.0, 0.0], "fan_mult": 1.0, "bounce": 0.0,
		"weights": [3.0, 2.0, 1.6, 1.2, 1.0, 0.5, 0.6], "bird_color": Color(0.15, 0.15, 0.18)},
	{"id": "river", "name": "River", "start": 350.0, "bonus": 220,
		"pal": [Color(0.34, 0.68, 0.95), Color(0.58, 0.84, 0.97), Color(0.88, 0.96, 0.94), Color(0.45, 0.70, 0.66), Color(0.36, 0.60, 0.50), Color(0.30, 0.55, 0.30), Color(0.22, 0.42, 0.24), Color(0.62, 0.55, 0.38), Color(0.78, 0.72, 0.5), Color(0.22, 0.55, 0.88)],
		"ground": 1, "far": 0, "mid": 3, "props": 2, "pad_skin": 0, "fan_skin": 0, "gravity": 1.0, "bird_scale": 1.0, "raise": [0.0, 0.0], "fan_mult": 1.0, "bounce": 0.0,
		"weights": [3.0, 2.8, 0.2, 0.9, 1.0, 0.6, 2.0], "bird_color": Color(0.5, 0.5, 0.55)},
	{"id": "town", "name": "Town", "start": 650.0, "bonus": 380,
		"pal": [Color(0.44, 0.66, 0.92), Color(0.68, 0.82, 0.95), Color(0.92, 0.92, 0.88), Color(0.62, 0.62, 0.78), Color(0.52, 0.55, 0.68), Color(0.82, 0.62, 0.45), Color(0.62, 0.45, 0.35), Color(0.45, 0.4, 0.38), Color(0.62, 0.6, 0.58), Color(0.4, 0.6, 0.8)],
		"ground": 0, "far": 0, "mid": 2, "props": 3, "pad_skin": 2, "fan_skin": 0, "gravity": 1.0, "bird_scale": 1.0, "raise": [3.0, 6.0], "fan_mult": 1.0, "bounce": 0.0,
		"weights": [3.0, 2.0, 1.8, 1.0, 1.0, 0.5, 0.6], "bird_color": Color(0.5, 0.45, 0.4)},
	{"id": "hills", "name": "Hills", "start": 1000.0, "bonus": 600,
		"pal": [Color(0.42, 0.62, 0.9), Color(0.7, 0.8, 0.94), Color(0.94, 0.9, 0.86), Color(0.5, 0.7, 0.55), Color(0.35, 0.58, 0.4), Color(0.25, 0.5, 0.3), Color(0.18, 0.38, 0.24), Color(0.4, 0.34, 0.26), Color(0.4, 0.62, 0.32), Color(0.4, 0.6, 0.8)],
		"ground": 0, "far": 0, "mid": 4, "props": 4, "pad_skin": 0, "fan_skin": 3, "gravity": 1.0, "bird_scale": 1.1, "raise": [0.0, 0.0], "fan_mult": 1.15, "bounce": 0.0,
		"weights": [3.0, 2.0, 1.2, 1.8, 1.1, 0.8, 0.5], "bird_color": Color(0.45, 0.3, 0.2)},
	{"id": "city", "name": "City", "start": 1500.0, "bonus": 900,
		"pal": [Color(0.46, 0.56, 0.74), Color(0.66, 0.74, 0.86), Color(0.88, 0.88, 0.9), Color(0.55, 0.6, 0.7), Color(0.42, 0.47, 0.58), Color(0.40, 0.45, 0.55), Color(0.28, 0.32, 0.42), Color(0.3, 0.3, 0.33), Color(0.5, 0.5, 0.54), Color(0.4, 0.6, 0.8)],
		"ground": 0, "far": 1, "mid": 5, "props": 5, "pad_skin": 0, "fan_skin": 2, "gravity": 1.0, "bird_scale": 1.0, "raise": [6.0, 16.0], "fan_mult": 1.1, "bounce": 0.0,
		"weights": [2.5, 2.0, 2.2, 1.8, 1.0, 0.7, 0.3], "bird_color": Color(0.5, 0.5, 0.52)},
	{"id": "coast", "name": "Coast", "start": 2200.0, "bonus": 1300,
		"pal": [Color(0.3, 0.72, 0.96), Color(0.55, 0.88, 0.98), Color(0.96, 0.96, 0.88), Color(0.5, 0.8, 0.78), Color(0.4, 0.7, 0.65), Color(0.3, 0.65, 0.4), Color(0.2, 0.5, 0.32), Color(0.85, 0.76, 0.52), Color(0.95, 0.88, 0.62), Color(0.18, 0.62, 0.9)],
		"ground": 1, "far": 0, "mid": 6, "props": 6, "pad_skin": 3, "fan_skin": 0, "gravity": 1.0, "bird_scale": 1.0, "raise": [0.0, 0.0], "fan_mult": 1.0, "bounce": 0.0,
		"weights": [3.0, 2.8, 0.2, 1.0, 1.2, 0.6, 2.0], "bird_color": Color(0.95, 0.95, 0.95)},
	{"id": "clouds", "name": "Cloud Kingdom", "start": 3000.0, "bonus": 1900,
		"pal": [Color(0.55, 0.5, 0.9), Color(0.82, 0.7, 0.95), Color(0.98, 0.88, 0.94), Color(0.78, 0.7, 0.95), Color(0.7, 0.62, 0.92), Color(0.96, 0.9, 0.98), Color(0.82, 0.76, 0.94), Color(0.88, 0.84, 0.98), Color(1.0, 1.0, 1.0), Color(0.9, 0.6, 0.9)],
		"ground": 2, "far": 2, "mid": 7, "props": 7, "pad_skin": 0, "fan_skin": 0, "gravity": 1.0, "bird_scale": 1.0, "raise": [0.0, 0.0], "fan_mult": 1.0, "bounce": 0.72,
		"weights": [3.0, 2.5, 0.4, 1.2, 0.7, 1.0, 0.8], "bird_color": Color(1.0, 0.8, 0.9)},
	{"id": "moon", "name": "Cheese Moon", "start": 4000.0, "bonus": 2600,
		"pal": [Color(0.04, 0.05, 0.16), Color(0.1, 0.1, 0.28), Color(0.26, 0.22, 0.4), Color(0.4, 0.38, 0.55), Color(0.32, 0.3, 0.46), Color(0.95, 0.8, 0.3), Color(0.8, 0.62, 0.2), Color(0.9, 0.72, 0.22), Color(1.0, 0.86, 0.38), Color(0.9, 0.9, 1.0)],
		"ground": 3, "far": 0, "mid": 8, "props": 8, "pad_skin": 0, "fan_skin": 0, "gravity": 0.6, "bird_scale": 0.8, "raise": [0.0, 0.0], "fan_mult": 1.0, "bounce": 0.0,
		"weights": [3.0, 2.0, 1.5, 1.0, 1.0, 1.0, 0.6], "bird_color": Color(0.7, 0.7, 0.75)},
	{"id": "dino", "name": "Dino Valley", "start": 5500.0, "bonus": 3600,
		"pal": [Color(0.92, 0.5, 0.3), Color(0.98, 0.7, 0.4), Color(1.0, 0.88, 0.6), Color(0.65, 0.4, 0.3), Color(0.5, 0.32, 0.25), Color(0.42, 0.55, 0.28), Color(0.3, 0.42, 0.2), Color(0.5, 0.35, 0.2), Color(0.38, 0.56, 0.22), Color(0.9, 0.35, 0.15)],
		"ground": 0, "far": 0, "mid": 8, "props": 9, "pad_skin": 0, "fan_skin": 3, "gravity": 1.0, "bird_scale": 1.7, "raise": [0.0, 0.0], "fan_mult": 1.2, "bounce": 0.0,
		"weights": [3.0, 2.0, 1.4, 1.0, 1.8, 0.7, 0.5], "bird_color": Color(0.35, 0.55, 0.35)},
	{"id": "disco", "name": "Disco Planet", "start": 7500.0, "bonus": 5000,
		"pal": [Color(0.2, 0.05, 0.35), Color(0.5, 0.1, 0.55), Color(0.9, 0.3, 0.7), Color(0.4, 0.15, 0.6), Color(0.3, 0.1, 0.5), Color(0.2, 0.9, 0.9), Color(0.9, 0.2, 0.8), Color(0.15, 0.08, 0.25), Color(0.3, 0.2, 0.5), Color(1.0, 0.9, 0.2)],
		"ground": 4, "far": 1, "mid": 5, "props": 10, "pad_skin": 0, "fan_skin": 2, "gravity": 0.9, "bird_scale": 1.0, "raise": [0.0, 0.0], "fan_mult": 1.3, "bounce": 0.0,
		"weights": [3.0, 2.0, 2.0, 2.4, 0.8, 1.0, 0.5], "bird_color": Color(1.0, 0.5, 0.9)},
]

## The air in each zone (what flies above the ground), by zone index.
## balloon skin: 0 hot air balloon, 1 parasailer, 2 party balloons.  flock skin (slows you): 0 geese, 1 seagulls, 2 crows, 3 helicopters,
## 4 pterodactyls, 5 UFOs.  kite skin (slows you): 0 kite, 1 paper plane, 2 drone.  storm skin: 0 storm cloud, 1 ash cloud, 2 neon cloud.
## Weights [balloon, kite, flock, weave, ring, stream, blimp, storm, find] are times Tuning's own chances: each zone leans on its own air.
static var air: Array[Dictionary] = [
	{"balloon": 0, "flock": 2, "kite": 0, "storm": 0, "w": [1.4, 1.2, 1.0, 1.0, 1.0, 1.0, 0.7, 1.0, 1.0], "flavor": "patched balloons, crows, newspaper kites"},
	{"balloon": 0, "flock": 0, "kite": 0, "storm": 0, "w": [1.5, 1.2, 1.2, 1.0, 1.0, 1.0, 0.8, 0.9, 1.0], "flavor": "balloons, geese, kites"},
	{"balloon": 0, "flock": 0, "kite": 0, "storm": 0, "w": [1.2, 1.0, 1.4, 1.1, 1.0, 1.2, 0.8, 1.0, 1.0], "flavor": "geese on the river"},
	{"balloon": 2, "flock": 2, "kite": 1, "storm": 0, "w": [1.4, 1.3, 1.0, 1.0, 1.0, 1.0, 0.9, 0.9, 1.0], "flavor": "party balloons, crows, paper planes"},
	{"balloon": 0, "flock": 0, "kite": 0, "storm": 0, "w": [1.3, 1.0, 1.2, 1.1, 1.2, 1.3, 0.8, 1.2, 1.0], "flavor": "balloons, geese, big weather"},
	{"balloon": 0, "flock": 3, "kite": 2, "storm": 0, "w": [1.0, 1.4, 1.6, 1.0, 1.1, 1.0, 1.4, 0.9, 1.0], "flavor": "helicopters, drones, blimps"},
	{"balloon": 1, "flock": 1, "kite": 0, "storm": 0, "w": [1.8, 1.2, 1.4, 1.0, 1.0, 1.4, 0.8, 0.8, 1.0], "flavor": "parasailers, seagulls, kites"},
	{"balloon": 2, "flock": 0, "kite": 1, "storm": 0, "w": [1.5, 1.0, 0.9, 1.1, 1.3, 1.2, 1.0, 0.7, 1.2], "flavor": "party balloons in the clouds"},
	{"balloon": 2, "flock": 5, "kite": 1, "storm": 0, "w": [1.0, 0.9, 1.4, 1.0, 1.3, 1.0, 1.0, 0.8, 1.6], "flavor": "UFOs and floating cheese balloons"},
	{"balloon": 0, "flock": 4, "kite": 0, "storm": 1, "w": [1.0, 1.0, 1.6, 1.0, 1.0, 1.0, 0.7, 1.6, 1.2], "flavor": "pterodactyls and ash clouds"},
	{"balloon": 2, "flock": 5, "kite": 2, "storm": 2, "w": [1.2, 1.1, 1.3, 1.0, 1.5, 1.2, 1.0, 1.3, 1.4], "flavor": "UFOs, drones, neon storms"},
]

## Start of zone i in meters, scaled by Tuning's zone_distance_mult (passed in so this file needs no autoload).
static func start_of(i: int, dist_mult: float) -> float:
	return float(list[clampi(i, 0, COUNT - 1)]["start"]) * dist_mult

## Index of the zone containing x meters.
static func index_at(x: float, dist_mult: float) -> int:
	var idx := 0
	for i in range(1, COUNT):
		if x >= float(list[i]["start"]) * dist_mult:
			idx = i
		else:
			break
	return idx
