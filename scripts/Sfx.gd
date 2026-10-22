class_name Sfx
extends Node
## All sound is generated in code at start-up (no audio files). One-shots go through a small pool of players on the
## "SFX" bus; the music and the wind loop have their own players on "Music" / "SFX". Nothing is created or generated
## during play, and `plays` counts what was triggered (for the tests).

const RATE := 11025
const LOOP_RATE := 8000
const POOL := 10
const NAMES := ["press", "tap", "back", "toggle", "buy", "error", "whoosh", "unlock", "clank", "stamp", "tick", "best", "clink", "pause"]

var enabled := true
var plays := {}
var _streams := {}
var _pool: Array[AudioStreamPlayer] = []
var _next := 0

## Make the SFX and Music buses (once) and set their volumes from 0..1 sliders.
static func setup_buses() -> void:
	for b in ["SFX", "Music"]:
		if AudioServer.get_bus_index(b) < 0:
			AudioServer.add_bus()
			var i := AudioServer.get_bus_count() - 1
			AudioServer.set_bus_name(i, b)
			AudioServer.set_bus_send(i, "Master")

static func set_bus_volume(bus: String, v: float) -> void:
	var i := AudioServer.get_bus_index(bus)
	if i >= 0:
		AudioServer.set_bus_volume_db(i, linear_to_db(clampf(v, 0.0001, 1.0)))
		AudioServer.set_bus_mute(i, v <= 0.001)

func _ready() -> void:
	for n in NAMES:
		plays[n] = 0
	if DisplayServer.get_name() == "headless":
		enabled = false      # (tests, CI): nothing to hear it, nothing to generate
		return
	_build()
	for i in POOL:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_pool.append(p)

func play(sound: String, pitch: float = 1.0) -> void:
	plays[sound] = int(plays.get(sound, 0)) + 1
	if not enabled or not _streams.has(sound):
		return
	var p := _pool[_next]
	_next = (_next + 1) % POOL
	p.stream = _streams[sound]
	p.pitch_scale = pitch
	p.play()

func _build() -> void:
	_streams["press"] = _wav(_seq([[420.0, 0.03, 0.25]], RATE, 0.9))                       # a finger goes down: a soft low click
	_streams["tap"] = _wav(_seq([[740.0, 0.05, 0.35], [988.0, 0.06, 0.3]], RATE))        # a button: a bright blip
	_streams["back"] = _wav(_seq([[560.0, 0.04, 0.3], [415.0, 0.07, 0.3]], RATE))         # going back: a falling pair
	_streams["toggle"] = _wav(_seq([[920.0, 0.03, 0.35]], RATE, 0.8))
	_streams["buy"] = _wav(_seq([[784.0, 0.06, 0.4], [1047.0, 0.06, 0.4], [1568.0, 0.2, 0.4]], RATE, 0.5, false, true))
	_streams["error"] = _wav(_seq([[196.0, 0.08, 0.3], [147.0, 0.14, 0.3]], RATE, 0.7, true))
	_streams["whoosh"] = _wav(_whoosh(0.24, RATE))
	_streams["unlock"] = _wav(_seq([[523.0, 0.1, 0.4], [659.0, 0.1, 0.4], [784.0, 0.1, 0.4], [1047.0, 0.45, 0.45]], RATE, 0.6, false, true))
	# a bolt going on: a metallic clank (two inharmonic partials, fast decay) over a short noise tick
	_streams["clank"] = _wav(_mix(_seq([[310.0, 0.16, 0.5], [517.0, 0.12, 0.35]], RATE, 0.95, false, true), _noise_tick(0.05, RATE)))
	# a stamp on paper: a dull thud and a slap
	_streams["stamp"] = _wav(_mix(_sweep(150.0, 60.0, 0.16, 0.9, RATE), _noise_tick(0.04, RATE)))
	_streams["tick"] = _wav(_seq([[1500.0, 0.02, 0.4]], RATE, 0.6, true))                  # the distance counting up
	_streams["best"] = _wav(_seq([[523.0, 0.09, 0.4], [659.0, 0.09, 0.4], [784.0, 0.09, 0.4], [1047.0, 0.09, 0.4], [1319.0, 0.4, 0.45]], RATE, 0.6, false, true))
	_streams["clink"] = _wav(_seq([[1760.0, 0.05, 0.35], [2349.0, 0.12, 0.3]], RATE, 0.5, false, true))   # scrap
	_streams["pause"] = _wav(_seq([[660.0, 0.05, 0.3], [495.0, 0.08, 0.3]], RATE))

func _seq(notes: Array, rate: int, decay: float = 0.6, square: bool = false, bell: bool = false) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for n in notes:
		var count := int(float(n[1]) * rate)
		var base := out.size()
		out.resize(base + count)
		for i in count:
			var t := float(i) / rate
			var env := (1.0 - float(i) / count) if not bell else exp(-t * 6.0)
			env = lerpf(1.0, env, decay) * minf(float(i) / 40.0, 1.0)
			var ph := TAU * float(n[0]) * t
			var v := signf(sin(ph)) * 0.6 if square else sin(ph)
			if bell:
				v += 0.4 * sin(ph * 2.76)
			out[base + i] = v * float(n[2]) * env
	return out

func _sweep(f0: float, f1: float, secs: float, vol: float, rate: int) -> PackedFloat32Array:
	var count := int(secs * rate)
	var out := PackedFloat32Array()
	out.resize(count)
	var ph := 0.0
	for i in count:
		var k := float(i) / count
		ph += TAU * lerpf(f0, f1, k) / rate
		out[i] = sin(ph) * vol * (1.0 - k) * minf(float(i) / 30.0, 1.0)
	return out

func _whoosh(secs: float, rate: int) -> PackedFloat32Array:
	var count := int(secs * rate)
	var out := PackedFloat32Array()
	out.resize(count)
	var seed_v := 777
	var lp := 0.0
	for i in count:
		seed_v = (seed_v * 1103515245 + 12345) & 0x7fffffff
		var noise := float(seed_v) / 1073741823.5 - 1.0
		var k := float(i) / count
		lp += (noise - lp) * lerpf(0.05, 0.5, sin(PI * k))
		out[i] = lp * sin(PI * k) * 0.5
	return out

func _noise_tick(secs: float, rate: int) -> PackedFloat32Array:
	var count := int(secs * rate)
	var out := PackedFloat32Array()
	out.resize(count)
	var seed_v := 4242
	for i in count:
		seed_v = (seed_v * 1103515245 + 12345) & 0x7fffffff
		out[i] = (float(seed_v) / 1073741823.5 - 1.0) * 0.5 * (1.0 - float(i) / count)
	return out

func _mix(a: PackedFloat32Array, b: PackedFloat32Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(maxi(a.size(), b.size()))
	for i in out.size():
		out[i] = (a[i] if i < a.size() else 0.0) + (b[i] if i < b.size() else 0.0)
	return out

func _wav(samples: PackedFloat32Array, rate: int = RATE, loop: bool = false) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = bytes
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = samples.size()
	return w
