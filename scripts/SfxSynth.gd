class_name SfxSynth
extends RefCounted
## Renders every sound of the game (see docs/style.md, "Audio") as float samples. Run offline by tools/render_audio.gd, which
## writes the 44.1 kHz 16-bit WAV files in assets/audio/ that the game loads; the game itself never synthesises anything.
## Soft sines and filtered noise, raised-cosine envelopes, a baked-in room, everything in C major pentatonic.
## (No autoload references: the smoke test re-renders everything and compares it with the committed files.)

const STEPS := 8               # scrap plucks: this many steps up the scale
const BEAT := 0.5              # music: 120 BPM, seconds per beat; 16 beats (4 bars of 4) per loop (8 s)
const BAR := BEAT * 4.0
const LOOP := BAR * 4.0
const C4 := 261.6256
const PENTA := [0, 2, 4, 7, 9]  # C D E G A

# Loudness by role (peak, linear). The SFX bus sits at -1.9 dB. Every gameplay sound is quieter than the music's calm
# layer at its garage level (the web audio check in CI fails if one is not), so the music always sits on top.
const LVL_UI := 0.08
const LVL_GAME := 0.15
const LVL_BIG := 0.20

var rate := 44100

## Every one-shot: name -> samples.
func clips() -> Dictionary:
	var out := {}
	_build_effects_into(out)
	return out

## Every loop: name -> samples. The music is four equally long, phase-locked layers (garage: the light theme; groove, perc and
## lead: the flight layers that build with speed and height), then the wind and the ramp rumble.
func loops() -> Dictionary:
	var m := _music()
	return {"garage": m["garage"], "groove": m["groove"], "perc": m["perc"], "lead": m["lead"], "wind": _wind_loop(), "rumble": _rumble_loop()}

# ---------- The key ----------

## Frequency of scale degree `deg` of C major pentatonic: 0 = C4, 1 = D4, 2 = E4, 3 = G4, 4 = A4, 5 = C5, ...
static func note_hz(deg: int) -> float:
	var oct := floori(float(deg) / 5.0)
	return C4 * pow(2.0, float(PENTA[posmod(deg, 5)] + 12 * oct) / 12.0)

# ---------- The clips ----------

func _build_effects_into(clips: Dictionary) -> void:
	# UI: very quiet, very short, soft clicks.
	clips["press"] = _norm(_knock(330.0, 0.05), LVL_UI * 0.7)
	clips["tap"] = _norm(_knock(520.0, 0.06), LVL_UI)
	clips["back"] = _norm(_mix_at(_knock(440.0, 0.05), _knock(330.0, 0.07), int(0.05 * rate)), LVL_UI)
	clips["toggle"] = _norm(_knock(720.0, 0.04), LVL_UI * 0.8)
	clips["error"] = _norm(_soft(note_hz(2) * 0.5, 0.16, 0.9), LVL_UI * 1.5)
	clips["whoosh"] = _norm(_whoosh(0.25, 500.0, 1100.0), LVL_UI * 1.1)
	clips["pause"] = _norm(_mix_at(_knock(520.0, 0.05), _knock(390.0, 0.08), int(0.06 * rate)), LVL_UI)
	clips["tick"] = _norm(_knock(640.0, 0.05), LVL_UI * 1.2)               # the distance counting up
	# A purchase: three soft plinks up the scale.
	var buy := _mix_at(_mix_at(_bell(note_hz(7), 0.4, 1.0, 1.0), _bell(note_hz(9), 0.4, 0.9, 1.0), int(0.07 * rate)), _bell(note_hz(10), 0.6, 0.9, 1.0), int(0.14 * rate))
	clips["buy"] = _norm(_reverb(buy, 0.3, 0.5), LVL_GAME)
	# A part bolting on: a low muffled bell (E3) with a soft knock.
	clips["clank"] = _norm(_reverb(_mix_at(_bell(note_hz(-3), 0.55, 1.0, 0.5), _knock(780.0, 0.05), 0), 0.25, 0.3), LVL_GAME)
	# A stamp on paper: a warm thud with a faint knock.
	clips["stamp"] = _norm(_reverb(_mix_at(_thud(0.3), _knock(300.0, 0.05), int(0.01 * rate)), 0.15, 0.2), LVL_GAME)
	# A new best and a new zone: little melodies up the scale.
	var best := PackedFloat32Array()
	for k in 5:
		best = _mix_at(best, _bell(note_hz([7, 8, 10, 12, 14][k]), 0.9, 1.0, 0.9), int(k * 0.1 * rate))
	clips["best"] = _norm(_reverb(best, 0.45, 0.8), LVL_BIG)
	var un := PackedFloat32Array()
	for k in 5:
		un = _mix_at(un, _bell(note_hz([5, 7, 8, 10, 12][k]), 0.9, 1.0, 0.9), int(k * 0.12 * rate))
	clips["unlock"] = _norm(_reverb(un, 0.45, 0.8), LVL_BIG)
	# Scrap: a short tin-and-ukulele pluck; a streak of pickups climbs the scale (the game quantizes them to the music).
	for k in STEPS:
		clips["clink_%d" % k] = _norm(_reverb(_tinpluck(note_hz(5 + k), 0.3), 0.2, 0.3), LVL_GAME * 0.8)
	# Bounce pad: a rubbery sine gliding up to G with a quick wobble.
	clips["boing"] = _norm(_lp(_glide(note_hz(-2), note_hz(3), 0.34, 14.0), 1800.0), LVL_GAME)
	# Updraft fan: air rushing up.
	clips["fan"] = _norm(_reverb(_whoosh(0.5, 250.0, 900.0), 0.2, 0.3), LVL_GAME * 0.8)
	# Bird: two soft falling coos (E to C, then A to E), a touch of breath.
	var coo := _mix_at(_coo(note_hz(2), note_hz(0), 0.13), _coo(note_hz(4), note_hz(2), 0.18), int(0.15 * rate))
	clips["squawk"] = _norm(_reverb(coo, 0.2, 0.25), LVL_GAME)
	# Booster: an engine swell that opens up.
	clips["boost"] = _norm(_reverb(_swell(0.8), 0.2, 0.3), LVL_GAME)
	# Stall: a gentle falling pair (E to C).
	clips["stall"] = _norm(_mix_at(_soft(note_hz(2), 0.14, 0.9), _soft(note_hz(0), 0.22, 0.9), int(0.13 * rate)), LVL_GAME * 0.8)
	# Landing: a heavy but rounded crunch: a deep thud, a low-passed noise burst and a low bell (A2).
	clips["crunch"] = _norm(_reverb(_mix_at(_mix_at(_thud(0.5), _noise_burst(0.22, 900.0), 0), _bell(note_hz(-1) * 0.5, 0.7, 0.5, 0.4), int(0.02 * rate)), 0.2, 0.35), LVL_BIG)
	# Water skip: a bright soft splash.
	clips["splash"] = _norm(_whoosh(0.28, 900.0, 2200.0), LVL_GAME * 0.8)
	# Slingshot: a plucked sine falling from G5, with a knock.
	clips["snap"] = _norm(_reverb(_mix_at(_pluck(note_hz(8), note_hz(3), 0.32), _knock(900.0, 0.03), 0), 0.2, 0.25), LVL_GAME)
	# Catapult: a low whoosh and thud.
	clips["swing"] = _norm(_reverb(_mix_at(_whoosh(0.45, 180.0, 520.0), _thud(0.35), int(0.3 * rate)), 0.2, 0.3), LVL_GAME)
	# A boost ring: a quick plucked arpeggio up the key (C, E, G, C), on the beat.
	var ring := PackedFloat32Array()
	for k in 4:
		ring = _mix_at(ring, _tinpluck(note_hz([5, 7, 8, 10][k]), 0.45), int(k * 0.0625 * rate))
	clips["ring"] = _norm(_reverb(ring, 0.3, 0.4), LVL_GAME)
	# A blimp skim: a whistle swooping up from G to C.
	clips["skim"] = _norm(_reverb(_whistle(note_hz(10), 0.5, 1.0, note_hz(8)), 0.25, 0.3), LVL_GAME)
	# A tailwind: a soft airy whistle rising a fifth (C to G) over a breath of wind.
	clips["gust"] = _norm(_reverb(_mix_at(_whistle(note_hz(8), 0.7, 0.8, note_hz(5)), _whoosh(0.7, 300.0, 1100.0), 0), 0.3, 0.4), LVL_GAME * 0.85)
	# A storm cloud: a soft low rumble swelling in.
	clips["storm"] = _norm(_reverb(_mix_at(_whoosh(0.6, 120.0, 420.0), _thud(0.5), int(0.1 * rate)), 0.2, 0.3), LVL_GAME * 0.9)
	# A new altitude band: a small two-note chime (G then C).
	clips["band"] = _norm(_reverb(_mix_at(_bell(note_hz(3), 0.35, 1.0, 0.8), _bell(note_hz(5), 0.5, 0.9, 0.8), int(0.08 * rate)), 0.25, 0.3), LVL_UI * 1.4)
	# A joke find: the game plays a ping on the next sixteenth and this fanfare on the next bar line: a silly plucked run up
	# the key (all pentatonic, so it suits every chord of the loop) into a whistled, wobbling top note.
	var fnd := PackedFloat32Array()
	for k in 6:
		fnd = _mix_at(fnd, _tinpluck(note_hz([5, 7, 8, 9, 10, 12][k]), 0.4), int(k * 0.0625 * rate))
	fnd = _mix_at(fnd, _whistle(note_hz(12), 0.8, 1.0, note_hz(10)), int(0.4 * rate))
	clips["find"] = _norm(_reverb(fnd, 0.4, 0.7), LVL_BIG)
	clips["find_ping"] = _norm(_reverb(_mix_at(_tinpluck(note_hz(8), 0.25), _tinpluck(note_hz(10), 0.35), int(0.06 * rate)), 0.2, 0.3), LVL_GAME)
	# Rocket sled: a big low swell.
	clips["ignite"] = _norm(_reverb(_swell(1.1), 0.25, 0.4), LVL_BIG * 0.9)

## Soft wind: slow breaths of filtered noise (a two-second loop; its ends are crossfaded so it is seamless).
func _wind_loop() -> PackedFloat32Array:
	var n := rate * 2
	var fade := rate / 4
	var raw := PackedFloat32Array()
	raw.resize(n + fade)
	var seed_v := 1717
	var lp := 0.0
	var lp2 := 0.0
	var fa := 1.0 - exp(-TAU * 190.0 / rate)
	var fb := 1.0 - exp(-TAU * 380.0 / rate)
	for i in n + fade:
		seed_v = (seed_v * 1103515245 + 12345) & 0x7fffffff
		var noise := float(seed_v) / 1073741823.5 - 1.0
		lp += (noise - lp) * fa
		lp2 += (lp - lp2) * fb
		raw[i] = lp2 * (0.7 + 0.3 * sin(TAU * 0.5 * float(i) / rate))
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		if i < fade:
			var a := float(i) / fade
			out[i] = raw[i] * a + raw[n + i] * (1.0 - a)
		else:
			out[i] = raw[i]
	return _norm(out, 0.3)

## The ramp / sled rumble: low sines at whole-Hz frequencies with a slow tremble (a seamless one-second loop).
func _rumble_loop() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(rate)
	for i in rate:
		var s := float(i) / rate
		out[i] = (sin(TAU * 41.0 * s) + 0.6 * sin(TAU * 62.0 * s + 1.0) + 0.3 * sin(TAU * 83.0 * s + 2.0)) * (0.7 + 0.3 * sin(TAU * 6.0 * s))
	return _norm(out, 0.25)

## A sine gliding from f0 to f1 with a wobble (Hz, `wob`) that dies away: a rubbery bounce.
func _glide(f0: float, f1: float, dur: float, wob: float) -> PackedFloat32Array:
	var n := int(dur * rate)
	var out := PackedFloat32Array()
	out.resize(n)
	var a_n := int(0.008 * rate)
	var r_n := int(0.06 * rate)
	var ph := 0.0
	for i in n:
		var t := float(i) / rate
		var k := float(i) / n
		ph += TAU * (lerpf(f0, f1, 1.0 - exp(-k * 5.0)) + sin(TAU * 11.0 * t) * wob * (1.0 - k)) / rate
		out[i] = sin(ph) * exp(-t * 4.0) * _win(i, n, a_n, r_n)
	return out

## A soft coo: a sine gliding from f0 to f1 with a little vibrato and a breath of filtered noise.
func _coo(f0: float, f1: float, dur: float) -> PackedFloat32Array:
	var n := int(dur * rate)
	var out := PackedFloat32Array()
	out.resize(n)
	var a_n := int(0.02 * rate)
	var r_n := int(0.05 * rate)
	var ph := 0.0
	var seed_v := 555
	for i in n:
		var t := float(i) / rate
		var k := float(i) / n
		seed_v = (seed_v * 1103515245 + 12345) & 0x7fffffff
		var noise := float(seed_v) / 1073741823.5 - 1.0
		ph += TAU * (lerpf(f0, f1, k) * (1.0 + 0.015 * sin(TAU * 26.0 * t))) / rate
		out[i] = (sin(ph) + 0.25 * sin(2.0 * ph) + 0.08 * noise) * (1.0 - 0.5 * k) * _win(i, n, a_n, r_n)
	return _lp(_lp(out, 1500.0), 1800.0)

## A plucked sine: a fast attack, an exponential decay and a falling pitch (f0 to f1).
func _pluck(f0: float, f1: float, dur: float) -> PackedFloat32Array:
	var n := int(dur * rate)
	var out := PackedFloat32Array()
	out.resize(n)
	var a_n := int(0.004 * rate)
	var r_n := int(0.05 * rate)
	var ph := 0.0
	for i in n:
		var t := float(i) / rate
		var k := float(i) / n
		ph += TAU * lerpf(f0, f1, 1.0 - exp(-k * 6.0)) / rate
		out[i] = (sin(ph) + 0.2 * sin(2.0 * ph)) * exp(-t * 11.0) * _win(i, n, a_n, r_n)
	return _lp(out, 2400.0)

## A short burst of low-passed noise with a soft start and a rounded decay.
func _noise_burst(dur: float, fc: float) -> PackedFloat32Array:
	var n := int(dur * rate)
	var out := PackedFloat32Array()
	out.resize(n)
	var a_n := int(0.008 * rate)
	var r_n := int(0.06 * rate)
	var seed_v := 2024
	for i in n:
		seed_v = (seed_v * 1103515245 + 12345) & 0x7fffffff
		var noise := float(seed_v) / 1073741823.5 - 1.0
		out[i] = noise * exp(-float(i) / rate * 14.0) * _win(i, n, a_n, r_n)
	return _lp(_lp(out, fc), fc)

# ---------- The music: Plane-Launch's own theme ----------
# 120 BPM, four bars of four beats (8 s): C, Am, F, G, one chord a bar, and one tune (docs/style.md, "Plane-Launch's music").
# Junkyard flavour: tin cans and hand claps for percussion, a plucky bass, ukulele strums and a whistled lead. Every layer is
# one loop of the same length starting on the same downbeat, so any mix of them is in time, and in one key.

const ROOTS := [65.41, 55.0, 87.31, 98.0]                    # bass roots: C2, A1, F2, G2
const UKE := [[196.0, 261.63, 329.63, 392.0], [220.0, 261.63, 329.63, 440.0], [220.0, 261.63, 349.23, 440.0], [196.0, 293.66, 392.0, 493.88]]
const PAD := [[130.81, 196.0, 261.63, 329.63], [110.0, 164.81, 220.0, 261.63], [87.31, 130.81, 174.61, 220.0], [98.0, 146.83, 196.0, 246.94]]
# the tune: [bar, sixteenth, scale degree (note_hz), length in sixteenths]
const TUNE := [
	[0, 0, 7, 3], [0, 3, 8, 3], [0, 6, 9, 2], [0, 8, 8, 3], [0, 11, 7, 2], [0, 13, 6, 3],
	[1, 0, 10, 3], [1, 3, 9, 3], [1, 6, 8, 2], [1, 8, 9, 4], [1, 12, 7, 4],
	[2, 0, 9, 3], [2, 3, 8, 3], [2, 6, 7, 2], [2, 8, 8, 3], [2, 11, 9, 2], [2, 13, 10, 3],
	[3, 0, 11, 4], [3, 4, 10, 2], [3, 6, 9, 2], [3, 8, 8, 4], [3, 12, 6, 2], [3, 14, 7, 2]]
# the bass: [sixteenth, 0 root / 1 octave / 2 fifth, length in sixteenths], the same every bar (bouncy, syncopated)
const BASS := [[0, 0, 3], [3, 0, 2], [6, 1, 2], [8, 2, 3], [10, 0, 2], [12, 0, 2], [14, 1, 2]]

## The four music layers, each exactly LOOP long and seamless: garage (the light theme), groove (bass, tin-can kick, hand
## claps, ukulele off-beats), perc (more percussion) and lead (the whistled tune with a pluck doubling it).
func _music() -> Dictionary:
	var n := int(LOOP * rate)
	var sx := BEAT / 4.0
	var garage := PackedFloat32Array()
	var groove := PackedFloat32Array()
	var perc := PackedFloat32Array()
	var lead := PackedFloat32Array()
	garage.resize(n)
	groove.resize(n)
	perc.resize(n)
	lead.resize(n)
	var kick := _kick()
	var clap := _clap(1.0)
	var soft_clap := _clap(0.6)
	var tin_hi := _tin(note_hz(8), 0.09)
	var tin_lo := _tin(note_hz(5), 0.09)
	var shake := _shaker(1.0)
	var shake_soft := _shaker(0.55)
	for bar in 4:
		var b0 := float(bar) * BAR
		# the pad bed: keeps the garage alive between plucks
		var pad := _padchord(PAD[bar], BAR + 0.5)
		_put(garage, pad, int((b0 - 0.25) * rate), 0.55)
		# bass: full in the groove, roots only (and softer) in the garage
		for bp in BASS:
			var root: float = ROOTS[bar]
			var f: float = root * (1.0 if bp[1] == 0 else 2.0 if bp[1] == 1 else 1.5)
			var note := _bass(f, float(bp[2]) * sx * 1.4)
			var at := int((b0 + float(bp[0]) * sx) * rate)
			_put(groove, note, at, 1.0)
			if bp[0] == 0 or bp[0] == 8:
				_put(garage, note, at, 0.55)
		# tin-can kick on 1, the "and" of 2 and 3, hand claps on 2 and 4
		for k in [0, 6, 8]:
			_put(groove, kick, int((b0 + float(k) * sx) * rate), 1.0 if k != 6 else 0.7)
		_put(groove, clap, int((b0 + 4.0 * sx) * rate), 0.8)
		_put(groove, clap, int((b0 + 12.0 * sx) * rate), 0.8)
		_put(garage, soft_clap, int((b0 + 4.0 * sx) * rate), 0.35)
		_put(garage, soft_clap, int((b0 + 12.0 * sx) * rate), 0.35)
		# ukulele: up-strums on the "and" of every beat (a skank) in the groove, two soft down-strums in the garage
		for k in [2, 6, 10, 14]:
			_put(groove, _strum(UKE[bar], 0.34, 0.016, false), int((b0 + float(k) * sx) * rate), 0.55)
		for k in [4, 12]:
			_put(garage, _strum(UKE[bar], 0.7, 0.02, true), int((b0 + float(k) * sx) * rate), 0.5)
		# extra percussion: shaker sixteenths, tin cans on the off-beats, a ghost clap before the bar line
		for k in 16:
			_put(perc, shake if k % 4 == 2 else shake_soft, int((b0 + float(k) * sx) * rate), 0.7 if k % 2 == 0 else 0.35)
		for k in [2, 7, 10, 15]:
			_put(perc, tin_hi if k != 7 else tin_lo, int((b0 + float(k) * sx) * rate), 0.8)
		_put(perc, soft_clap, int((b0 + 14.0 * sx) * rate), 0.5)
		_put(perc, tin_lo, int((b0 + 9.0 * sx) * rate), 0.5)
	for tn_note in TUNE:
		var at2 := int((float(tn_note[0]) * BAR + float(tn_note[1]) * sx) * rate)
		var f2 := note_hz(tn_note[2])
		var len_s := float(tn_note[3]) * sx
		_put(lead, _whistle(f2, len_s + 0.12, 1.0, f2 * 0.94), at2, 1.0)
		_put(lead, _tinpluck(f2 * 0.5, 0.35), at2, 0.45)           # a soft pluck an octave down under every whistle note
		if tn_note[1] == 0 or tn_note[1] == 8:
			_put(garage, _tinpluck(f2, 0.5), at2, 0.9)         # the garage plays the tune's main notes on soft plucks
	garage = _norm(_reverb_loop(garage, 0.35), 0.5)
	groove = _reverb_loop(groove, 0.2)
	perc = _reverb_loop(perc, 0.15)
	lead = _reverb_loop(lead, 0.35)
	# one gain for the three flight layers (so their balance is the one written above): the groove peaks at 0.5
	var g := 0.5 / _peak(groove)
	return {"garage": garage, "groove": _scale(groove, g), "perc": _scale(perc, g * 1.1), "lead": _scale(lead, g * 0.5)}

## Add `src` * `gain` into the loop `dst` at sample `at`, wrapping round the end (so tails run into the start of the loop).
func _put(dst: PackedFloat32Array, src: PackedFloat32Array, at: int, gain: float) -> void:
	var n := dst.size()
	for i in src.size():
		dst[(at + i) % n] += src[i] * gain

func _peak(x: PackedFloat32Array) -> float:
	var m := 0.0001
	for v in x:
		m = maxf(m, absf(v))
	return m

func _scale(x: PackedFloat32Array, g: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(x.size())
	for i in x.size():
		out[i] = x[i] * g
	return out

## A plucky bass: a sine with a little second and third harmonic, a quick decay and a tiny pitch settle, low-passed.
func _bass(f: float, dur: float) -> PackedFloat32Array:
	var n := int(dur * rate)
	var out := PackedFloat32Array()
	out.resize(n)
	var a_n := int(0.004 * rate)
	var r_n := int(0.03 * rate)
	var ph := 0.0
	for i in n:
		var t := float(i) / rate
		ph += TAU * f * (1.0 + 0.03 * exp(-t * 40.0)) / rate
		out[i] = (sin(ph) + 0.45 * sin(2.0 * ph) + 0.15 * sin(3.0 * ph)) * exp(-t * 8.0) * _win(i, n, a_n, r_n)
	return _norm(_lp(out, 700.0), 0.5)

## The tin-can kick: a pitch-dropping thump with the hollow ring of a can on top.
func _kick() -> PackedFloat32Array:
	var n := int(0.24 * rate)
	var out := PackedFloat32Array()
	out.resize(n)
	var a_n := int(0.004 * rate)
	var r_n := int(0.05 * rate)
	var ph := 0.0
	for i in n:
		var t := float(i) / rate
		ph += TAU * (62.0 + 95.0 * exp(-t * 26.0)) / rate
		out[i] = (sin(ph) * exp(-t * 14.0) + 0.22 * sin(TAU * 410.0 * t) * exp(-t * 60.0) + 0.1 * sin(TAU * 986.0 * t) * exp(-t * 80.0)) * _win(i, n, a_n, r_n)
	return _norm(_lp(out, 1500.0), 0.7)

## A hand clap: three quick bursts of band-limited noise and a short tail (soft starts: no clicks).
func _clap(amp: float) -> PackedFloat32Array:
	var n := int(0.22 * rate)
	var out := PackedFloat32Array()
	out.resize(n)
	var seed_v := 31337
	var lo := 0.0
	var hi := 0.0
	var fa := 1.0 - exp(-TAU * 3000.0 / rate)
	var fb := 1.0 - exp(-TAU * 700.0 / rate)
	var r_n := int(0.05 * rate)
	for i in n:
		var t := float(i) / rate
		seed_v = (seed_v * 1103515245 + 12345) & 0x7fffffff
		var noise := float(seed_v) / 1073741823.5 - 1.0
		lo += (noise - lo) * fa
		hi += (lo - hi) * fb
		var e := 0.0
		for tk in [0.0, 0.012, 0.025]:
			if t >= tk:
				e += exp(-(t - tk) * 110.0) * smoothstep(0.0, 0.004, t - tk)
		e += exp(-(t - 0.025) * 20.0) * 0.35 * smoothstep(0.025, 0.04, t)
		out[i] = (lo - hi) * e * _win(i, n, 1, r_n)
	return _norm(_lp(out, 3200.0), 0.6 * amp)

## A shaker: a very short breath of band-limited noise.
func _shaker(amp: float) -> PackedFloat32Array:
	var n := int(0.09 * rate)
	var out := PackedFloat32Array()
	out.resize(n)
	var seed_v := 777
	var lo := 0.0
	var hi := 0.0
	var fa := 1.0 - exp(-TAU * 3200.0 / rate)
	var fb := 1.0 - exp(-TAU * 1500.0 / rate)
	for i in n:
		var t := float(i) / rate
		seed_v = (seed_v * 1103515245 + 12345) & 0x7fffffff
		var noise := float(seed_v) / 1073741823.5 - 1.0
		lo += (noise - lo) * fa
		hi += (lo - hi) * fb
		out[i] = (lo - hi) * exp(-t * 55.0) * smoothstep(0.0, 0.006, t) * _win(i, n, 1, int(0.03 * rate))
	return _norm(_lp(_lp(out, 3000.0), 3000.0), 0.3 * amp)

## A tuned tin can: a short, hollow, slightly metallic knock at pitch f.
func _tin(f: float, dur: float) -> PackedFloat32Array:
	var n := int(dur * rate)
	var out := PackedFloat32Array()
	out.resize(n)
	var a_n := int(0.003 * rate)
	var r_n := int(0.03 * rate)
	for i in n:
		var t := float(i) / rate
		out[i] = (sin(TAU * f * t) + 0.5 * sin(TAU * f * 2.32 * t) * exp(-t * 90.0) + 0.2 * sin(TAU * f * 3.9 * t) * exp(-t * 130.0)) * exp(-t * 45.0) * _win(i, n, a_n, r_n)
	return _norm(_lp(_lp(out, 3200.0), 3200.0), 0.35)

## A plucked tin-and-ukulele note: a bright-but-soft string-like pluck (a few decaying harmonics), low-passed.
func _tinpluck(f: float, dur: float) -> PackedFloat32Array:
	var n := int(dur * rate)
	var out := PackedFloat32Array()
	out.resize(n)
	var a_n := int(0.003 * rate)
	var r_n := int(minf(0.05, dur * 0.4) * rate)
	for i in n:
		var t := float(i) / rate
		var v := sin(TAU * f * t) * exp(-t * 7.0)
		if f * 2.0 < 3600.0:
			v += 0.4 * sin(TAU * f * 2.0 * t) * exp(-t * 14.0)
		if f * 3.0 < 3600.0:
			v += 0.12 * sin(TAU * f * 3.0 * t) * exp(-t * 22.0)
		out[i] = v * _win(i, n, a_n, r_n)
	return _norm(_lp(out, 3600.0), 0.5)

## A ukulele string (Karplus-Strong): a smoothed noise burst on a delay line that rings and fades; low-passed, soft start.
func _uke(f: float, dur: float) -> PackedFloat32Array:
	var n := int(dur * rate)
	var d := maxi(int(round(rate / f - 0.5)), 2)
	var buf := PackedFloat32Array()
	buf.resize(d)
	var seed_v := 4242 + int(f)
	var sm := 0.0
	for i in d:
		seed_v = (seed_v * 1103515245 + 12345) & 0x7fffffff
		sm += 0.45 * ((float(seed_v) / 1073741823.5 - 1.0) - sm)
		buf[i] = sm
	var out := PackedFloat32Array()
	out.resize(n)
	var idx := 0
	var a_n := int(0.004 * rate)
	var r_n := int(minf(0.06, dur * 0.3) * rate)
	for i in n:
		var nxt := (idx + 1) % d
		out[i] = buf[idx] * _win(i, n, a_n, r_n)
		buf[idx] = 0.996 * 0.5 * (buf[idx] + buf[nxt])
		idx = nxt
	return _norm(_lp(out, 3200.0), 0.5)

## A ukulele strum: the chord's strings a few milliseconds apart, down (low to high) or up (high to low).
func _strum(freqs: Array, dur: float, spread: float, down: bool) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var cnt := freqs.size()
	for k in cnt:
		var idx := k if down else cnt - 1 - k
		out = _mix_at(out, _uke(float(freqs[k]), dur), int(float(idx) * spread * rate))
	return _norm(out, 0.5)

## A whistle: a sine with a breath of noise that slides from `from_f` to `f` in the first 70 ms, then wobbles with a late
## vibrato and fades; soft start and release. (Pass from_f = f for no slide.)
func _whistle(f: float, dur: float, amp: float, from_f: float = 0.0) -> PackedFloat32Array:
	var n := int(dur * rate)
	var out := PackedFloat32Array()
	out.resize(n)
	var a_n := int(0.02 * rate)
	var r_n := int(minf(0.08, dur * 0.4) * rate)
	var slide := 0.07 if from_f > 0.0 and absf(from_f - f) < f * 0.2 else minf(0.35, dur * 0.7)
	var f0 := from_f if from_f > 0.0 else f
	var ph := 0.0
	var seed_v := 909
	var lp := 0.0
	for i in n:
		var t := float(i) / rate
		seed_v = (seed_v * 1103515245 + 12345) & 0x7fffffff
		var noise := float(seed_v) / 1073741823.5 - 1.0
		lp += 0.25 * (noise - lp)
		var cur := lerpf(f0, f, smoothstep(0.0, slide, t))
		ph += TAU * cur * (1.0 + 0.007 * sin(TAU * 5.5 * t) * smoothstep(0.1, 0.3, t)) / rate
		out[i] = (sin(ph) + 0.06 * sin(2.0 * ph) + 0.05 * lp) * exp(-t * 1.1) * _win(i, n, a_n, r_n)
	return _norm(_lp(out, 3000.0), 0.5 * amp)

## One bar of pad: four sines, a raised-cosine in and out (so the bars blend into each other).
func _padchord(freqs: Array, dur: float) -> PackedFloat32Array:
	var n := int(dur * rate)
	var out := PackedFloat32Array()
	out.resize(n)
	var a_n := int(0.45 * rate)
	for i in n:
		var t := float(i) / rate
		var v := 0.0
		for f in freqs:
			v += sin(TAU * float(f) * t) + 0.2 * sin(TAU * float(f) * 2.0 * t)
		out[i] = v * 0.12 * _win(i, n, a_n, a_n)
	return out

# ---------- Voices and DSP ----------

## Smooth fade in over `a` samples and out over `r` samples (raised-cosine): no clicks, ever.
static func _win(i: int, n: int, a: int, r: int) -> float:
	var v := 1.0
	if i < a:
		var s := sin(PI * 0.5 * float(i) / maxf(a, 1))
		v = s * s
	var j := n - 1 - i
	if j < r:
		var s2 := sin(PI * 0.5 * float(j) / maxf(r, 1))
		v *= s2 * s2
	return v

## A bell: a sine with two softer, quicker-fading overtones. `bright` scales the overtones.
func _bell(f: float, dur: float, amp: float, bright: float = 1.0) -> PackedFloat32Array:
	var n := int(dur * rate)
	var out := PackedFloat32Array()
	out.resize(n)
	var a_n := int(0.008 * rate)
	var r_n := int(0.04 * rate)
	for i in n:
		var t := float(i) / rate
		var v := sin(TAU * f * t) * exp(-t * 4.5)
		if f * 2.0 < rate * 0.5:
			v += 0.3 * bright * sin(TAU * f * 2.0 * t) * exp(-t * 8.0)
		if f * 3.0 < rate * 0.5:
			v += 0.08 * bright * sin(TAU * f * 3.0 * t) * exp(-t * 13.0)
		out[i] = v * amp * _win(i, n, a_n, r_n)
	return out

## A soft, slightly hollow tone (a sine with a touch of triangle), lowpassed: for the muted "bonk" and the descending pair.
func _soft(f: float, dur: float, amp: float) -> PackedFloat32Array:
	var n := int(dur * rate)
	var out := PackedFloat32Array()
	out.resize(n)
	var a_n := int(0.012 * rate)
	var r_n := int(0.06 * rate)
	for i in n:
		var t := float(i) / rate
		var ph := fposmod(f * t, 1.0)
		var tri := 4.0 * absf(ph - 0.5) - 1.0
		out[i] = (0.8 * sin(TAU * f * t) + 0.2 * tri) * exp(-t * 6.0) * amp * _win(i, n, a_n, r_n)
	return _lp(out, 900.0)

## A warm chord: sines with a slow bloom and a long release.
func _chord(freqs: Array, dur: float) -> PackedFloat32Array:
	var n := int(dur * rate)
	var out := PackedFloat32Array()
	out.resize(n)
	var a_n := int(0.25 * rate)
	var r_n := int(0.5 * rate)
	for i in n:
		var t := float(i) / rate
		var v := 0.0
		for f in freqs:
			v += sin(TAU * float(f) * t) + 0.2 * sin(TAU * float(f) * 2.0 * t)
		out[i] = v / freqs.size() * exp(-t * 1.6) * _win(i, n, a_n, r_n)
	return out

## A low thud: a sine falling from C3 to C2 with a soft attack and a rounded decay.
func _thud(dur: float) -> PackedFloat32Array:
	var n := int(dur * rate)
	var out := PackedFloat32Array()
	out.resize(n)
	var a_n := int(0.01 * rate)
	var r_n := int(0.08 * rate)
	var ph := 0.0
	for i in n:
		var t := float(i) / rate
		ph += TAU * lerpf(130.81, 65.41, minf(t * 5.0, 1.0)) / rate     # C3 down to C2: tuned to the key
		out[i] = sin(ph) * exp(-t * 9.0) * _win(i, n, a_n, r_n)
	return _lp(out, 500.0)

## A tiny soft knock: a short sine with a rounded start.
func _knock(f: float, dur: float) -> PackedFloat32Array:
	var n := int(dur * rate)
	var out := PackedFloat32Array()
	out.resize(n)
	var a_n := int(0.006 * rate)
	var r_n := int(0.014 * rate)
	for i in n:
		var t := float(i) / rate
		out[i] = sin(TAU * f * t) * exp(-t * 60.0) * _win(i, n, a_n, r_n)
	return _lp(out, 1400.0)

## The tire chirp: a brief breath of filtered noise and a faint, falling squeak.
func _chirp() -> PackedFloat32Array:
	var n := int(0.11 * rate)
	var out := PackedFloat32Array()
	out.resize(n)
	var a_n := int(0.012 * rate)
	var r_n := int(0.04 * rate)
	var seed_v := 99
	var ph := 0.0
	for i in n:
		var t := float(i) / rate
		seed_v = (seed_v * 1103515245 + 12345) & 0x7fffffff
		var noise := float(seed_v) / 1073741823.5 - 1.0
		ph += TAU * lerpf(1050.0, 820.0, t / 0.11) / rate
		out[i] = (0.5 * noise + 0.5 * sin(ph)) * exp(-t * 22.0) * _win(i, n, a_n, r_n)
	return _lp(_lp(out, 2200.0), 2200.0)

## Filtered noise that rises and falls in brightness: a swish.
func _whoosh(dur: float, f0: float, f1: float) -> PackedFloat32Array:
	var n := int(dur * rate)
	var out := PackedFloat32Array()
	out.resize(n)
	var seed_v := 777
	var lp := 0.0
	var lp2 := 0.0
	for i in n:
		seed_v = (seed_v * 1103515245 + 12345) & 0x7fffffff
		var noise := float(seed_v) / 1073741823.5 - 1.0
		var k := float(i) / n
		var fc := lerpf(f0, f1, sin(PI * k))
		var a := 1.0 - exp(-TAU * fc / rate)
		lp += (noise - lp) * a
		lp2 += (lp - lp2) * a
		out[i] = lp2 * sin(PI * k)
	return out

## The go-around: a whoosh with a rising engine note (a sine climbing 90 -> 170 Hz and swelling).
func _swell(dur: float) -> PackedFloat32Array:
	var n := int(dur * rate)
	var wh := _whoosh(dur, 300.0, 900.0)
	var out := PackedFloat32Array()
	out.resize(n)
	var ph := 0.0
	for i in n:
		var k := float(i) / n
		ph += TAU * lerpf(90.0, 170.0, k * k) / rate
		var env := sin(PI * minf(k * 1.1, 1.0)) * k
		out[i] = 0.9 * wh[i] * 0.6 + (sin(ph) + 0.4 * sin(2.0 * ph)) * env * 0.5
	return _lp(out, 1200.0)

## One-pole lowpass (applied to taste: twice is 12 dB per octave).
func _lp(x: PackedFloat32Array, fc: float) -> PackedFloat32Array:
	var a := 1.0 - exp(-TAU * fc / rate)
	var y := 0.0
	var out := PackedFloat32Array()
	out.resize(x.size())
	for i in x.size():
		y += a * (x[i] - y)
		out[i] = y
	return out

## Scale a clip so its peak is `peak`.
func _norm(x: PackedFloat32Array, peak: float) -> PackedFloat32Array:
	var m := 0.0001
	for v in x:
		m = maxf(m, absf(v))
	var g := peak / m
	var out := PackedFloat32Array()
	out.resize(x.size())
	for i in x.size():
		out[i] = x[i] * g
	return out

## Add `src` into `dst` starting at sample `at` (growing `dst` as needed).
func _mix_at(dst: PackedFloat32Array, src: PackedFloat32Array, at: int) -> PackedFloat32Array:
	var out := dst.duplicate()
	if out.size() < at + src.size():
		out.resize(at + src.size())
	for i in src.size():
		out[at + i] += src[i]
	return out

## A short shared "room": four damped combs and a tail, mixed in at `wet`. The clip grows by `tail` seconds.
func _reverb(x: PackedFloat32Array, wet: float, tail: float) -> PackedFloat32Array:
	var n := x.size() + int(tail * rate)
	var out := PackedFloat32Array()
	out.resize(n)
	var d := [int(0.0297 * rate), int(0.0371 * rate), int(0.0411 * rate), int(0.0437 * rate)]
	var fb := [0.74, 0.72, 0.7, 0.68]
	var b0 := PackedFloat32Array()
	var b1 := PackedFloat32Array()
	var b2 := PackedFloat32Array()
	var b3 := PackedFloat32Array()
	b0.resize(d[0])
	b1.resize(d[1])
	b2.resize(d[2])
	b3.resize(d[3])
	var i0 := 0
	var i1 := 0
	var i2 := 0
	var i3 := 0
	var s0 := 0.0
	var s1 := 0.0
	var s2 := 0.0
	var s3 := 0.0
	for i in n:
		var inp := x[i] if i < x.size() else 0.0
		var o0 := b0[i0]
		var o1 := b1[i1]
		var o2 := b2[i2]
		var o3 := b3[i3]
		s0 += 0.45 * (o0 - s0)
		s1 += 0.45 * (o1 - s1)
		s2 += 0.45 * (o2 - s2)
		s3 += 0.45 * (o3 - s3)
		b0[i0] = inp + s0 * fb[0]
		b1[i1] = inp + s1 * fb[1]
		b2[i2] = inp + s2 * fb[2]
		b3[i3] = inp + s3 * fb[3]
		i0 = (i0 + 1) % d[0]
		i1 = (i1 + 1) % d[1]
		i2 = (i2 + 1) % d[2]
		i3 = (i3 + 1) % d[3]
		var tailv := t_fade(i, x.size(), n)
		out[i] = inp + wet * 0.25 * (o0 + o1 + o2 + o3) * tailv
	return out

## The tail fades out smoothly over the last third of its length (so a clip never ends on a sound).
static func t_fade(i: int, body: int, n: int) -> float:
	var tail := n - body
	if tail <= 0 or i < n - tail / 3:
		return 1.0
	var k := float(n - i) / maxf(tail / 3.0, 1.0)
	return k * k

## The room for a loop: run the loop twice through the reverb and keep the second pass (a seamless tail).
func _reverb_loop(x: PackedFloat32Array, wet: float) -> PackedFloat32Array:
	var two := PackedFloat32Array()
	two.resize(x.size() * 2)
	for i in x.size():
		two[i] = x[i]
		two[x.size() + i] = x[i]
	var r := _reverb(two, wet, 0.0)
	return r.slice(x.size(), x.size() * 2)
