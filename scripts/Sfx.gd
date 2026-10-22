class_name Sfx
extends Node
## All sound is generated in code at start-up (no audio files). One-shots go through a small pool of players on the
## "SFX" bus; the music and the wind loop have their own players on "Music" / "SFX". Nothing is created or generated
## during play, and `plays` counts what was triggered (for the tests).

const RATE := 11025
const LOOP_RATE := 8000
const POOL := 10
const NAMES := ["press", "tap", "back", "toggle", "buy", "error", "whoosh", "unlock", "clank", "stamp", "tick", "best", "clink", "pause",
		"boing", "fan", "squawk", "boost", "stall", "crunch", "splash", "snap", "swing", "ignite"]
const BEAT := 0.6              # music: seconds per beat, 8 beats per loop
const FADE_DB_PER_S := 40.0    # music crossfades glide at this rate: no jumps, no clicks

var enabled := true
var plays := {}
var wind_level := 0.0          # 0..1 (follows the speed); the wind loop's volume and pitch rise with it
var rumbling := false          # the ramp / sled rumble loop is on
var music_mode := "off"        # "garage", "flight" or "off"
var _streams := {}
var _pool: Array[AudioStreamPlayer] = []
var _next := 0
var _wind: AudioStreamPlayer
var _rumble: AudioStreamPlayer
var _calm: AudioStreamPlayer
var _hot: AudioStreamPlayer
var _wind_db := -80.0
var _wind_target := -80.0
var _calm_db := -80.0
var _hot_db := -80.0
var _calm_target := -80.0
var _hot_target := -80.0
var _rumble_db := -80.0
var _rumble_target := -80.0
const GARAGE_CALM_DB := -17.0
const FLIGHT_CALM_DB := -14.0
const FLIGHT_HOT_DB := -13.0

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
	_wind = _loop_player("SFX", _wav(_wind_loop(), LOOP_RATE, true))
	_rumble = _loop_player("SFX", _wav(_rumble_loop(), LOOP_RATE, true))
	_calm = _loop_player("Music", _wav(_music(false), LOOP_RATE, true))
	_hot = _loop_player("Music", _wav(_music(true), LOOP_RATE, true))

func _loop_player(bus: String, stream: AudioStreamWAV) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = bus
	p.stream = stream
	p.volume_db = -80.0
	add_child(p)
	return p

## The wind: volume and pitch rise with the speed (0..1).
func set_wind(level: float) -> void:
	wind_level = clampf(level, 0.0, 1.0)
	_wind_target = linear_to_db(wind_level) - 12.0 if wind_level > 0.02 else -80.0

## The ramp / rocket-sled rumble before the launch.
func set_rumble(on: bool) -> void:
	rumbling = on
	_rumble_target = -14.0 if on else -80.0

## "garage" (calm, quieter) or "flight" (calm plus the driving layer) or "off": the layers glide to their levels.
func set_music(mode: String) -> void:
	music_mode = mode
	match mode:
		"garage":
			_calm_target = GARAGE_CALM_DB
			_hot_target = -80.0
		"flight":
			_calm_target = FLIGHT_CALM_DB
			_hot_target = FLIGHT_HOT_DB
		_:
			_calm_target = -80.0
			_hot_target = -80.0
	if enabled and _calm != null and not _calm.playing and _calm_target > -70.0:
		_calm.play()
		_hot.play()

func _process(delta: float) -> void:
	if not enabled or _calm == null:
		return
	_wind_db = move_toward(_wind_db, _wind_target, FADE_DB_PER_S * delta)
	_rumble_db = move_toward(_rumble_db, _rumble_target, 80.0 * delta)
	_calm_db = move_toward(_calm_db, _calm_target, FADE_DB_PER_S * delta)
	_hot_db = move_toward(_hot_db, _hot_target, FADE_DB_PER_S * delta)
	_wind.volume_db = _wind_db
	_wind.pitch_scale = 0.75 + 0.7 * wind_level
	for pair in [[_wind, _wind_db], [_rumble, _rumble_db]]:
		var pl: AudioStreamPlayer = pair[0]
		if pair[1] > -70.0 and not pl.playing:
			pl.play()
		elif pair[1] <= -75.0 and pl.playing:
			pl.stop()
	_rumble.volume_db = _rumble_db
	_calm.volume_db = _calm_db
	_hot.volume_db = _hot_db
	if _calm.playing and _calm_db <= -75.0 and _hot_db <= -75.0 and _calm_target <= -70.0:
		_calm.stop()
		_hot.stop()

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
	# a bounce pad: a rubbery "boing", a quick upward sweep with a wobble
	_streams["boing"] = _wav(_boing(0.34, RATE))
	# an updraft fan: air rushing up
	_streams["fan"] = _wav(_noise_sweep(0.45, 0.04, 0.5, 0.5, RATE))
	# a bird: a rough two-part squawk (a sawtooth falling in pitch, twice)
	_streams["squawk"] = _wav(_mix(_squawk(0.13, 760.0, 420.0, RATE, 0.0), _squawk(0.16, 640.0, 300.0, RATE, 0.14)))
	# the booster lighting: a roar that opens up
	_streams["boost"] = _wav(_mix(_noise_sweep(0.6, 0.35, 0.05, 0.8, RATE), _sweep(110.0, 260.0, 0.5, 0.5, RATE)))
	# stall: a falling warning buzz
	_streams["stall"] = _wav(_seq([[330.0, 0.07, 0.4], [262.0, 0.1, 0.4]], RATE, 0.7, true))
	# landing: a heavy crunch (low thud, metal rattle, noise)
	_streams["crunch"] = _wav(_mix(_mix(_sweep(130.0, 38.0, 0.35, 1.0, RATE), _noise_tick(0.28, RATE)), _seq([[420.0, 0.1, 0.3], [610.0, 0.12, 0.25]], RATE, 0.9, false, true)))
	# skipping off water
	_streams["splash"] = _wav(_noise_sweep(0.22, 0.05, 0.3, 0.7, RATE))
	# the slingshot: a twang
	_streams["snap"] = _wav(_mix(_sweep(920.0, 180.0, 0.28, 0.7, RATE), _noise_tick(0.03, RATE)))
	# the catapult arm: a low heavy swing
	_streams["swing"] = _wav(_mix(_noise_sweep(0.4, 0.02, 0.2, 0.6, RATE), _sweep(90.0, 55.0, 0.4, 0.7, RATE)))
	# the sled's rockets: ignition whump and a rising roar
	_streams["ignite"] = _wav(_mix(_noise_sweep(0.9, 0.04, 0.5, 0.9, RATE), _sweep(60.0, 190.0, 0.8, 0.6, RATE)))

## One second of airy wind (many soft partials at whole Hz: a seamless loop).
func _wind_loop() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(LOOP_RATE)
	for i in LOOP_RATE:
		var s := float(i) / LOOP_RATE
		var v := 0.0
		for k in 14:
			v += 0.1 * sin(TAU * (260.0 + 47.0 * k) * s + k * 1.9) * (0.65 + 0.35 * sin(TAU * (1.0 + k % 3) * s + k))
		out[i] = v * 0.7
	return out

## A low rumble: a few low partials with a rattling amplitude.
func _rumble_loop() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(LOOP_RATE)
	for i in LOOP_RATE:
		var s := float(i) / LOOP_RATE
		var v := sin(TAU * 38.0 * s) + 0.7 * sin(TAU * 57.0 * s + 1.0) + 0.4 * sin(TAU * 83.0 * s)
		out[i] = v * (0.55 + 0.45 * sin(TAU * 14.0 * s)) * 0.45
	return out

## An 8-beat loop (A minor: Am F C G, two beats each). The calm layer is a pad and a bass; the driving layer is a
## plucked arpeggio and a kick on every beat. Both layers are the same length, so they stay in step through a crossfade.
func _music(hot: bool) -> PackedFloat32Array:
	var chords := [[220.0, 261.6, 329.6], [174.6, 220.0, 261.6], [261.6, 329.6, 392.0], [196.0, 246.9, 293.7]]
	var count := int(BEAT * 8.0 * LOOP_RATE)
	var out := PackedFloat32Array()
	out.resize(count)
	for i in count:
		var t := float(i) / LOOP_RATE
		var beat := t / BEAT
		var ch: Array = chords[int(beat / 2.0) % 4]
		var v := 0.0
		if not hot:
			for f in ch:
				v += 0.18 * sin(TAU * f * t * 0.5)
			var bt := fmod(beat, 2.0)
			v += 0.3 * sin(TAU * ch[0] * 0.25 * t) * (1.0 - 0.4 * bt)
		else:
			var step := fmod(beat * 2.0, 1.0)
			var note: float = ch[int(beat * 2.0) % 3] * 2.0
			v += 0.35 * sin(TAU * note * t) * exp(-step * 5.0)
			var kb := fmod(beat, 1.0)
			v += 0.5 * sin(TAU * lerpf(110.0, 45.0, minf(kb * 8.0, 1.0)) * kb * BEAT) * exp(-kb * 9.0)
		out[i] = v * 0.5
	return out

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

## A rubber "boing": a rising sweep with a fast wobble.
func _boing(secs: float, rate: int) -> PackedFloat32Array:
	var count := int(secs * rate)
	var out := PackedFloat32Array()
	out.resize(count)
	var ph := 0.0
	for i in count:
		var k := float(i) / count
		ph += TAU * (170.0 + 520.0 * (1.0 - exp(-k * 5.0)) + sin(k * 70.0) * 35.0) / rate
		out[i] = sin(ph) * 0.7 * exp(-k * 3.5) * minf(float(i) / 30.0, 1.0)
	return out

## Filtered noise whose brightness glides from `lo` to `hi` (0..1) with a swell, `vol` loud.
func _noise_sweep(secs: float, lo: float, hi: float, vol: float, rate: int) -> PackedFloat32Array:
	var count := int(secs * rate)
	var out := PackedFloat32Array()
	out.resize(count)
	var seed_v := 31337
	var lp := 0.0
	for i in count:
		seed_v = (seed_v * 1103515245 + 12345) & 0x7fffffff
		var noise := float(seed_v) / 1073741823.5 - 1.0
		var k := float(i) / count
		lp += (noise - lp) * lerpf(lo, hi, k)
		out[i] = lp * sin(PI * minf(k * 1.4, 1.0)) * vol * (1.0 - k * 0.5)
	return out

## A bird's squawk: a rough sawtooth gliding from f0 to f1, starting after `delay` seconds.
func _squawk(secs: float, f0: float, f1: float, rate: int, delay: float) -> PackedFloat32Array:
	var lead := int(delay * rate)
	var count := int(secs * rate)
	var out := PackedFloat32Array()
	out.resize(lead + count)
	var ph := 0.0
	for i in count:
		var k := float(i) / count
		ph += lerpf(f0, f1, k) / rate
		var saw := fmod(ph, 1.0) * 2.0 - 1.0
		out[lead + i] = saw * 0.45 * (1.0 - k) * minf(float(i) / 40.0, 1.0)
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
