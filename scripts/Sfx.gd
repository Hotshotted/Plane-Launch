class_name Sfx
extends Node
## The game's sound: soft, rounded, musical (docs/style.md, "Audio"). Nothing is synthesised at run time: every sound is a
## pre-rendered 44.1 kHz 16-bit WAV in assets/audio/ (made by tools/render_audio.gd from scripts/SfxSynth.gd). One-shots
## play from a small pool of players, always on a free one so nothing is cut off. The looping layers (the garage and flight
## music, the wind, the ramp rumble) are the problem on the web: Godot's web samples loop by restarting a buffer from the
## main thread, which leaves a gap at every wrap when a phone is busy. So on the web the PAGE plays the loops itself
## (PWAudio in web/shell.html: native, gapless AudioBufferSource loops off the main thread) and this script only sends the
## level (and the wind's rate) of each layer. Everywhere else (the editor, the tests) the loops are ordinary looping players.
## The buses come from default_bus_layout.tres and are never created at run time.
## The music is Plane-Launch's own (docs/style.md, "Plane-Launch's music"): 120 BPM, four phase-locked layers. The garage plays
## the light theme; in flight the groove is the base, percussion joins as the speed rises and the whistled lead in the high
## and sky bands, and they fall away again as the glider slows and lands. Pickups and accents are in-key plucks that wait for
## the music's grid, so the scrap arc plays a run of notes in time.

const POOL := 8
const STEPS := 8               # scrap plucks: this many steps up the scale
const BEAT := 0.5              # the music: 120 BPM, seconds per beat; 4 bars of 4 beats per loop (8 s)
const BAR := BEAT * 4.0
const GRID := BEAT / 4.0       # scrap plucks wait for the next sixteenth of the music
const ACCENT := BEAT / 2.0     # rings, skims and tailwinds wait for the next eighth (on the beat or half way to the next)
const CLINK_WINDOW := 1200     # ms: pickups closer together than this climb the scale
const QMAX := 16               # sounds waiting for their slot in the music
const NAMES := ["press", "tap", "back", "toggle", "error", "whoosh", "pause", "tick", "buy", "clank", "stamp", "best", "unlock", "clink",
		"boing", "fan", "squawk", "boost", "stall", "crunch", "splash", "snap", "swing", "ignite", "ring", "storm", "band", "find",
		"skim", "gust", "find_ping"]
const FILES := ["press", "tap", "back", "toggle", "error", "whoosh", "pause", "tick", "buy", "clank", "stamp", "best", "unlock",
		"boing", "fan", "squawk", "boost", "stall", "crunch", "splash", "snap", "swing", "ignite", "ring", "storm", "band", "find",
		"skim", "gust", "find_ping"]
const MUSIC := ["garage", "groove", "perc", "lead"]
const LAYERS := ["garage", "groove", "perc", "lead", "wind", "rumble"]
const FADE_DB_PER_S := 60.0    # every level change is a glide (at most this fast), never a cut
const BUILD_DB_PER_S := 30.0   # the flight layers build in at this rate...
const FALL_DB_PER_S := 14.0    # ...and fall away slower, so a slowing glider loses them smoothly
const GARAGE_DB := -2.0        # the garage theme
const GROOVE_DB := -3.0        # the flight's base groove at full
const GROOVE_LOW_DB := -14.0   # ...and when the glider has slowed to a stop
const PERC_DB := -5.0          # extra percussion at full speed
const LEAD_HIGH_DB := -8.0     # the whistled lead in the high band
const LEAD_SKY_DB := -4.0      # ...and in the sky band
const PERC_FROM := 30.0        # m/s: the percussion starts to come in here...
const PERC_FULL := 55.0        # ...and is full here
const LEAD_FROM := 26.0        # m/s: the lead needs at least this speed (it fades in over the next 14)

var enabled := true
var plays := {}                # sound name -> how many times it was triggered
var wind_level := 0.0          # 0..1 (follows the speed); the wind layer's level and rate rise with it
var rumbling := false          # the ramp / sled rumble layer is on
var music_mode := "off"        # "garage", "flight" or "off"
var held := false              # audio is held (the page went to the background): the Master bus is muted
var web_loops := false         # the page plays the loops (web build)
var phase_override := -1.0     # tests only: a made-up position in the music loop
var unlocked := false          # the first user gesture has happened (browsers keep audio suspended until then)

var _streams := {}
var _pool: Array[AudioStreamPlayer] = []
var _next := 0
var _players := {}             # layer -> its looping player (not on the web)
var _cur := {"garage": -80.0, "groove": -80.0, "perc": -80.0, "lead": -80.0, "wind": -80.0, "rumble": -80.0}     # where each layer is now (dB)
var _tgt := {"garage": -80.0, "groove": -80.0, "perc": -80.0, "lead": -80.0, "wind": -80.0, "rumble": -80.0}     # and where it is gliding to
var _js_sent := {}             # layer -> the level last sent to the page
var _js_rate := 1.0
var _q_at := PackedInt64Array()   # sounds waiting for their slot in the music: when (msec),
var _q_key: Array[String] = []    # ...which stream,
var _q_n := 0                     # ...and how many (fixed arrays: nothing is allocated in flight)
var _clink_keys: Array[String] = []
var _clink_step := 0
var _clink_last := -100000
var _rng := RandomNumberGenerator.new()

## Set a bus's volume from a 0..1 slider (the buses themselves come from default_bus_layout.tres).
static func set_bus_volume(bus: String, v: float) -> void:
	var i := AudioServer.get_bus_index(bus)
	if i >= 0:
		AudioServer.set_bus_volume_db(i, linear_to_db(clampf(v, 0.0001, 1.0)))
		AudioServer.set_bus_mute(i, v <= 0.001)

func _ready() -> void:
	_rng.randomize()
	for n in NAMES:
		plays[n] = 0
	web_loops = OS.has_feature("web") and bool(JavaScriptBridge.eval("!!(window.PWAudio && window.PWAudio.enabled)"))
	for f in FILES:
		_streams[f] = load("res://assets/audio/%s.wav" % f)
	for k in STEPS:
		_clink_keys.append("clink_%d" % k)
		_streams[_clink_keys[k]] = load("res://assets/audio/clink_%d.wav" % k)
	_q_at.resize(QMAX)
	_q_key.resize(QMAX)
	for i in POOL:
		_pool.append(_player("SFX"))
	if not web_loops and not OS.has_feature("web"):
		for l in LAYERS:
			_players[l] = _loop_player(l, "Music" if MUSIC.has(l) else "SFX")

func _player(bus: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = bus if AudioServer.get_bus_index(bus) >= 0 else "Master"      # (a missing bus must never be named: the web build aborts)
	add_child(p)
	return p

## A looping layer as an ordinary looping player (the editor and the tests; on the web the page does this).
func _loop_player(layer: String, bus: String) -> AudioStreamPlayer:
	var p := _player(bus)
	var path := "res://assets/audio/loops/%s.wav" % layer
	if ResourceLoader.exists(path):
		var st = load(path)
		if st is AudioStreamWAV:
			st.loop_mode = AudioStreamWAV.LOOP_FORWARD
			st.loop_begin = 0
			st.loop_end = st.data.size() / 2
			p.stream = st
	p.volume_db = -80.0
	return p

# ---------- Playing ----------

## A one-shot. `pitch` is a ratio (1 = as rendered); every play also gets about +-3% random pitch and a hair of random
## level, so repeated sounds never feel mechanical.
func play(sound: String, pitch: float = 1.0) -> void:
	plays[sound] = int(plays.get(sound, 0)) + 1
	if not enabled or not _streams.has(sound):
		return
	_fire(_streams[sound], pitch)

## A scrap pluck: pickups in quick succession climb the C major pentatonic scale, and each pluck waits for the next
## sixteenth of the music (at most 0.125 s), so a scrap arc plays a little run in time.
func play_clink() -> void:
	var now := Time.get_ticks_msec()
	_clink_step = 0 if now - _clink_last > CLINK_WINDOW else mini(_clink_step + 1, STEPS - 1)
	_clink_last = now
	plays["clink"] = int(plays["clink"]) + 1
	if not enabled:
		return
	_on_grid(_clink_keys[_clink_step], GRID)

## An in-key accent (a ring, a blimp skim, a tailwind): it waits for the next eighth of the music.
func play_accent(sound: String) -> void:
	plays[sound] = int(plays.get(sound, 0)) + 1
	if not enabled or not _streams.has(sound):
		return
	_on_grid(sound, ACCENT)

## A joke find: a ping on the next sixteenth right away, and the fanfare on the next bar line.
func play_find() -> void:
	plays["find"] = int(plays["find"]) + 1
	if not enabled:
		return
	_on_grid("find_ping", GRID)
	_on_grid("find", BAR)

## Play `key` at the next multiple of `grid` seconds of the music (at once when no music is playing or it is already there).
func _on_grid(key: String, grid: float) -> void:
	var wait := _beat_wait(grid)
	if wait <= 0.01 or _q_n >= QMAX:
		_fire(_streams[key], 1.0)
	else:
		_q_at[_q_n] = Time.get_ticks_msec() + int(wait * 1000.0)
		_q_key[_q_n] = key
		_q_n += 1

## Seconds into the music loop (-1 when it is not playing). (`phase_override` >= 0 stands in for it in the tests.)
func music_phase() -> float:
	if phase_override >= 0.0:
		return phase_override
	if _music_level() < -60.0:
		return -1.0
	if web_loops:
		return float(JavaScriptBridge.eval("window.PWAudio && PWAudio.phase ? PWAudio.phase() : -1"))
	for l in MUSIC:
		if _players.has(l) and _players[l].playing:
			return _players[l].get_playback_position()
	return -1.0

## Seconds until the next multiple of `grid` of the music (0 when no music is playing).
func _beat_wait(grid: float) -> float:
	var phase := music_phase()
	return 0.0 if phase < 0.0 else wait_for(phase, grid)

## Seconds from `phase` (into the loop) to the next multiple of `grid` (0 when already on it).
static func wait_for(phase: float, grid: float) -> float:
	var w := grid - fposmod(phase, grid)
	return 0.0 if w > grid * 0.999 else w

func _music_level() -> float:
	var m := -80.0
	for l in MUSIC:
		m = maxf(m, _cur[l])
	return m

func _fire(stream: AudioStream, pitch: float) -> void:
	var p := _pool[_next]
	for k in POOL:     # a free player first: taking over one that is still sounding would cut it off with a click
		var q := _pool[(_next + k) % POOL]
		if not q.playing:
			p = q
			_next = (_next + k) % POOL
			break
	_next = (_next + 1) % POOL
	p.stream = stream
	p.pitch_scale = pitch * _rng.randf_range(0.97, 1.03)
	p.volume_db = _rng.randf_range(-0.5, 0.3)
	p.play()

## The first touch: browsers only let audio run after a gesture. Looping players that were started while the page was
## still locked are restarted now, so they begin cleanly with the audio context running.
func unlock() -> void:
	if unlocked:
		return
	unlocked = true
	if not enabled:
		return
	for p in _players.values():
		if p.playing:
			p.stop()
			p.play()

## The page went to the background (or the phone was locked): hold everything silent. Nothing resumes until `release()`.
func hold() -> void:
	held = true
	AudioServer.set_bus_mute(0, true)
	if web_loops:
		JavaScriptBridge.eval("window.PWAudio && PWAudio.setHeld(true)")

## The player is back and tapped (Resume): sound may run again.
func release() -> void:
	held = false
	AudioServer.set_bus_mute(0, false)
	if web_loops:
		JavaScriptBridge.eval("window.PWAudio && PWAudio.setHeld(false)")

# ---------- The layers ----------

## The wind: its level and rate rise with the speed (0..1).
func set_wind(level: float) -> void:
	wind_level = clampf(level, 0.0, 1.0)
	_tgt["wind"] = lerpf(-24.0, -9.0, wind_level) if wind_level > 0.02 else -80.0

## The ramp / rocket-sled rumble before the launch.
func set_rumble(on: bool) -> void:
	rumbling = on
	_tgt["rumble"] = -10.0 if on else -80.0

## "garage" (the light theme) or "flight" (the groove, which `set_flight` then shapes) or "off": the layers glide to their
## levels. The key never changes (the music is never pitch-shifted).
func set_music(mode: String) -> void:
	music_mode = mode
	_tgt["perc"] = -80.0
	_tgt["lead"] = -80.0
	match mode:
		"garage":
			_tgt["garage"] = GARAGE_DB
			_tgt["groove"] = -80.0
		"flight":
			_tgt["garage"] = -80.0
			_tgt["groove"] = GROOVE_DB
		_:
			_tgt["garage"] = -80.0
			_tgt["groove"] = -80.0

## Shape the flight music from the flight: `speed` (m/s), the altitude `band` (0 low .. 3 sky) and whether the glider is
## still on the launcher. The groove is the base from the launch; percussion builds with speed; the lead joins in the high
## and sky bands; everything falls away smoothly as the glider slows and lands.
func set_flight(speed: float, band: int, launching: bool) -> void:
	if music_mode != "flight":
		return
	if launching:
		_tgt["groove"] = GROOVE_DB
		_tgt["perc"] = -80.0
		_tgt["lead"] = -80.0
		return
	_tgt["groove"] = lerpf(GROOVE_LOW_DB, GROOVE_DB, smoothstep(4.0, 18.0, speed))
	var p := smoothstep(PERC_FROM, PERC_FULL, speed)
	_tgt["perc"] = lerpf(-30.0, PERC_DB, p) if p > 0.02 else -80.0
	if band >= 2 and speed > LEAD_FROM:
		var top := LEAD_HIGH_DB if band == 2 else LEAD_SKY_DB
		_tgt["lead"] = top - (1.0 - smoothstep(LEAD_FROM, LEAD_FROM + 14.0, speed)) * 14.0
	else:
		_tgt["lead"] = -80.0

func _process(delta: float) -> void:
	if not enabled:
		return
	for l in LAYERS:
		var rate := FADE_DB_PER_S * 2.0 if l == "rumble" else FADE_DB_PER_S
		if l == "groove" or l == "perc" or l == "lead":
			rate = BUILD_DB_PER_S if _tgt[l] > _cur[l] else FALL_DB_PER_S
			if _tgt[l] > -60.0 and _cur[l] < -60.0:
				_cur[l] = -60.0      # (nothing is audible down there: don't spend the build on silence)
		_cur[l] = move_toward(_cur[l], _tgt[l], rate * delta)
		_apply(l)
	if _q_n > 0:
		var now := Time.get_ticks_msec()
		var i := _q_n - 1
		while i >= 0:
			if now >= _q_at[i]:
				_fire(_streams[_q_key[i]], 1.0)
				_q_n -= 1
				_q_at[i] = _q_at[_q_n]
				_q_key[i] = _q_key[_q_n]
			i -= 1
	if web_loops:
		_push_levels()

func _apply(layer: String) -> void:
	var p: AudioStreamPlayer = _players.get(layer)
	if p == null:
		return
	p.volume_db = _cur[layer]
	if layer == "wind":
		p.pitch_scale = 0.8 + 0.6 * wind_level
	if _cur[layer] > -70.0 and not p.playing and p.stream != null:
		p.play()
	elif _cur[layer] <= -75.0 and _tgt[layer] <= -70.0 and p.playing:
		p.stop()

## The bus a layer sits on: Music for the music, SFX for the rest (their volume sliders and mutes apply).
func _bus_db(layer: String) -> float:
	var idx := AudioServer.get_bus_index("Music" if MUSIC.has(layer) else "SFX")
	if idx < 0:
		return 0.0
	return -80.0 if AudioServer.is_bus_mute(idx) else AudioServer.get_bus_volume_db(idx)

## Tell the page the level of every layer that changed (one small call per frame at most).
func _push_levels() -> void:
	var changed := ""
	for n in LAYERS:
		var out_db := maxf(_cur[n] + _bus_db(n), -80.0)
		if not _js_sent.has(n) or absf(out_db - float(_js_sent[n])) > 0.05:
			_js_sent[n] = out_db
			changed += "%s:%.2f," % [n, out_db]
	var rate := 0.8 + 0.6 * wind_level
	if absf(rate - _js_rate) > 0.01:
		_js_rate = rate
		JavaScriptBridge.eval("window.PWAudio.setRate('wind', %.3f)" % rate)
	if changed != "":
		JavaScriptBridge.eval("window.PWAudio.setMany({" + changed + "})")
