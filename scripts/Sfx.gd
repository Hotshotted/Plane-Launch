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

const POOL := 8
const STEPS := 7               # scrap plinks: this many steps up the scale
const BEAT := 0.75             # the music: seconds per beat, 8 beats per loop (6 s)
const GRID := BEAT / 4.0       # scrap plinks wait for the next sixteenth of the music
const NAMES := ["press", "tap", "back", "toggle", "error", "whoosh", "pause", "tick", "buy", "clank", "stamp", "best", "unlock", "clink",
		"boing", "fan", "squawk", "boost", "stall", "crunch", "splash", "snap", "swing", "ignite"]
const FILES := ["press", "tap", "back", "toggle", "error", "whoosh", "pause", "tick", "buy", "clank", "stamp", "best", "unlock",
		"boing", "fan", "squawk", "boost", "stall", "crunch", "splash", "snap", "swing", "ignite"]
const LAYERS := ["calm", "hot", "wind", "rumble"]
const FADE_DB_PER_S := 60.0    # every level change is a glide (at most this fast), never a cut
const GARAGE_CALM_DB := -2.0
const FLIGHT_CALM_DB := -4.0
const FLIGHT_HOT_DB := -6.0

var enabled := true
var plays := {}                # sound name -> how many times it was triggered
var wind_level := 0.0          # 0..1 (follows the speed); the wind layer's level and rate rise with it
var rumbling := false          # the ramp / sled rumble layer is on
var music_mode := "off"        # "garage", "flight" or "off"
var held := false              # audio is held (the page went to the background): the Master bus is muted
var web_loops := false         # the page plays the loops (web build)
var unlocked := false          # the first user gesture has happened (browsers keep audio suspended until then)

var _streams := {}
var _pool: Array[AudioStreamPlayer] = []
var _next := 0
var _players := {}             # layer -> its looping player (not on the web)
var _cur := {"calm": -80.0, "hot": -80.0, "wind": -80.0, "rumble": -80.0}     # where each layer is now (dB)
var _tgt := {"calm": -80.0, "hot": -80.0, "wind": -80.0, "rumble": -80.0}     # and where it is gliding to
var _js_sent := {}             # layer -> the level last sent to the page
var _js_rate := 1.0
var _queue: Array = []         # [fire_at_msec, stream key]: plinks waiting for their sixteenth
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
		_streams["clink_%d" % k] = load("res://assets/audio/clink_%d.wav" % k)
	for i in POOL:
		_pool.append(_player("SFX"))
	if not web_loops and not OS.has_feature("web"):
		for l in LAYERS:
			_players[l] = _loop_player(l, "Music" if l == "calm" or l == "hot" else "SFX")

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

## A scrap plink: pickups in quick succession climb the C major pentatonic scale, and each plink waits for the next
## sixteenth of the music (at most 0.19 s), so a streak lands on the beat and sounds like a little melody.
func play_clink() -> void:
	var now := Time.get_ticks_msec()
	_clink_step = 0 if now - _clink_last > 1400 else mini(_clink_step + 1, STEPS - 1)
	_clink_last = now
	plays["clink"] = int(plays["clink"]) + 1
	if not enabled:
		return
	var key := "clink_%d" % _clink_step
	var wait := _beat_wait()
	if wait <= 0.01:
		_fire(_streams[key], 1.0)
	else:
		_queue.append([now + int(wait * 1000.0), key])

## Seconds until the next sixteenth of the music (0 when no music is playing).
func _beat_wait() -> float:
	if _cur["calm"] < -60.0:
		return 0.0
	var phase := -1.0
	if web_loops:
		phase = float(JavaScriptBridge.eval("window.PWAudio && PWAudio.phase ? PWAudio.phase() : -1"))
	elif _players.has("calm") and _players["calm"].playing:
		phase = _players["calm"].get_playback_position()
	if phase < 0.0:
		return 0.0
	var w := GRID - fposmod(phase, GRID)
	return 0.0 if w > GRID * 0.999 else w

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

## "garage" (the calm layer) or "flight" (calm plus the driving layer) or "off": the layers glide to their levels. The key
## never changes (the music is never pitch-shifted).
func set_music(mode: String) -> void:
	music_mode = mode
	match mode:
		"garage":
			_tgt["calm"] = GARAGE_CALM_DB
			_tgt["hot"] = -80.0
		"flight":
			_tgt["calm"] = FLIGHT_CALM_DB
			_tgt["hot"] = FLIGHT_HOT_DB
		_:
			_tgt["calm"] = -80.0
			_tgt["hot"] = -80.0

func _process(delta: float) -> void:
	if not enabled:
		return
	for l in LAYERS:
		_cur[l] = move_toward(_cur[l], _tgt[l], (FADE_DB_PER_S * 2.0 if l == "rumble" else FADE_DB_PER_S) * delta)
		_apply(l)
	if not _queue.is_empty():
		var now := Time.get_ticks_msec()
		for i in range(_queue.size() - 1, -1, -1):
			if now >= int(_queue[i][0]):
				_fire(_streams[_queue[i][1]], 1.0)
				_queue.remove_at(i)
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
	var idx := AudioServer.get_bus_index("Music" if layer == "calm" or layer == "hot" else "SFX")
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
