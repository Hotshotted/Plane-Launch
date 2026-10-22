# Junkyard Launch: style guide

Made by **Clear Prop Games**. This game uses the studio's shared identity (the same system as Pattern Control):
**friendly, chunky, high-contrast, sunny**. A dark navy interface floats over the bright world; gold means scrap and
rewards, green means go, red means trouble. Everything lives in code: `scripts/Style.gd` (tokens), `scripts/Glyphs.gd`
(icons), `scripts/Hud.gd` (screens). Change the token, not the call site.

## Palette (shared tokens, identical to the studio's other games)

| Role | Token | Hex | Use |
|---|---|---|---|
| Primary | `PRIMARY` | `#3d8bff` | navigation chips, selection |
| Primary dark | `PRIMARY_DARK` | `#2459c4` | lip of blue buttons |
| Accent | `ACCENT` | `#ffc933` | scrap, rewards, "you can afford this" |
| Accent dark | `ACCENT_DARK` | `#c98a0b` | reward text on paper |
| Success | `SUCCESS` | `#35c98a` | LAUNCH and every buy button: go |
| Success dark | `SUCCESS_DARK` | `#1a8a5a` | lip of the primary button |
| Warning / Danger | `WARNING` `DANGER` | `#ff9f2e` `#ff5c4d` | stall, birds, badges |
| Ink | `INK` | `#0a1020` | outlines, deepest dark |
| Surfaces | `SURFACE_DARK` `SURFACE_DARK_2` | `#14213d` `#1d3157` | cards, sheets, raised rows |
| Text | `TEXT` `TEXT_SOFT` `TEXT_QUIET` | `#ffffff` `#bcd0ec` `#8497b8` | primary, secondary, disabled |
| Scrim | `SCRIM` | `#060b18` | shade behind results and sheets |

### Deviation: junkyard accents

The family look stays; the junkyard shows up in accents only (`Style.gd`, "junkyard accents"):

| Token | Hex | Use |
|---|---|---|
| `RUST` `RUST_DARK` | `#c8683a` `#8a3f1f` | the clipboard's border and tag, rusty trim |
| `STEEL` `STEEL_DARK` | `#8f9bb0` `#4b566b` | bolts, plates |
| `PAPER` `PAPER_INK` `PAPER_SOFT` | `#f3ead2` `#3a2d1c` `#7a6a4f` | Rusty's clipboard (the one light surface) |

The flame orange of the boost button (`Glyphs.FLAME`) is the other game-specific colour.

## Typography

Fredoka SemiBold (display: titles, every number, XL and M text) and Nunito Bold (text), both SIL OFL (licences in
`assets/fonts/`). Three sizes: **XL 110**, **M 56**, **S 30**; at most three on any screen (checked by the smoke test).
Text over the world carries an ink outline.

## Shape, shadow, buttons

Radii S 14, M 26 (cards), L 40 (buttons, sheets), pill 60. Panels have the soft shadow (`#030814` 45 %, blur 16,
offset 0/8). **Primary**: big, green, with a 10 px dark lip; pressing sinks the face onto a 3 px lip. **Secondary**:
blue (navigation) or raised surface (tabs, close, can't-yet). **Ghost**: translucent, light outline, for "already so"
and the ad chips. Disabled: flat, quiet text.

## Icons

One vector set (`Glyphs.gd`, drawn by `GlyphView` / `UpgradeIcon`): bold filled silhouettes and thick round strokes,
no text, no emoji; two-tone only where the colour is the meaning (scrap gold, flame orange, danger red). The same icon
always stands for the same thing:

* upgrades: `ramp` `wings` `body` `booster` `magnet`; launchers: `ramp` `sling` `catapult` `sled`
* frames: `scrapper` `feather` `anvil` `pogo`; cosmetics: `paint` (a swatch), `hat_*`, `trail_*`
* missions: `bounce` `scrap` `distance` `noboost_zone` `skip` `updraft` `boost` `gear` `nobird`
* stats: `scrap` (a hex nut) `trophy` `flag` `star` `speed` `altitude` `clock`
* buttons: `rocket` (LAUNCH) `garage` `style` `daily` `ad` `play` `pause` `restart` `home` `back` `close` `check` `lock` `speaker` `note`
* studio: `propeller`

## Spacing and safe areas

Scale 8, 16, 24, 40, 64; gutter 40. One primary element per screen. `Style.safe_*` (device safe area, or the page's
`env(safe-area-inset-*)` on the web) is added to everything pinned to an edge (`Hud._apply_safe`); the world still runs
edge to edge.

## Motion

`T_FAST` 0.12 press/release, `T_BASE` 0.30 transitions, `T_SLOW` 0.5 celebrations, `STAGGER` 0.05. Ease-out-cubic for
arrivals, ease-in-cubic for exits, ease-out-back for things that land. Anything skippable can be skipped.

### Motion in practice (Phase 2)

* **Buttons:** pressing squashes to 0.93 in `T_FAST` with a soft click; releasing bounces back (ease-out-back) with a bright blip and a light haptic. Back/close use the falling "back" sound.
* **Directions:** forward things arrive by rising (sheets, from the bottom edge) or popping (results, pause: scale 0.8 to 1 with overshoot); leaving is the quick reverse (`T_FAST` x 1.5, ease-in). Switching between the launch screen and a flight fades; the upgrade cards then rise in with `STAGGER`.
* **Buying:** the card flashes, the newest level dot pops, scrap hops from the counter to the glider, and when it lands the part bolts on (clank, sparks, glider pulse).
* **Results:** the distance counts up with ticks, NEW BEST stamps in with a star burst and fanfare, the scrap flies to the counter, completed missions stamp in.
* **Zones:** a tilted paper postcard (rusty border, flag stamp) sweeps in from the left and out to the right.
* **Rusty:** the bubble's clipboard drops with a spring; his portrait nods, grins or facepalms.
* **Launch screen:** Rusty hammers at a bench, a grinder throws sparks, a crow sits on the junk heap (no outlines on scenery).
* **Pause:** a ghost button in the top-right corner; Resume (primary), Restart, Quit, and SFX and music sliders; the game also pauses by itself when the window loses focus.
* Everything runs through one small animator in `Hud`, which the tests switch off (`Hud.animate`) so transitions complete instantly.

### In the world (Phase 3)

* **Outlines on interactive things only:** the glider, launchers, scrap, pads, fans and birds keep the black outline; hills, heaps, props, ground, signs and the launch-screen ambience have none. Depth comes from parallax: a faint far ridge (0.09), hills (0.22), heaps (0.5), the ground (1), and tufts rushing past in front (1.5).
* **Glider:** every Wings, Body, Booster, Ramp and Magnet level shows (ribs, struts, cross-wires, winglets, rivets, seams, pods, fatter wheels); each frame has its own decals; Whiskers always has his eye, nose, whiskers, scarf and hat above the wings. Wings flex with the climb and rattle at speed.
* **Launches:** Ramp rumbles and puffs dust; Slingshot snaps with sparks and a hard kick; Catapult swings and kicks at release; Rocket Sled ignites, smokes and rumbles. Each ends with a camera kick off the lip.
* **Flight:** speed lines and wind streaks scale with speed, bounces lay a dust trail, touchdown is a crunch (debris, kick) followed by a tumble that hops along the ground.
* **Feedback popups** are chips: a dark pill with a coloured rim, the icon of what happened and the words, popping in and floating up.

## Audio

**Direction: soft, satisfying and musical, in the spirit of Mini Metro and Alto's Adventure: calm, rounded, cozy.** Every game from this studio sounds like it belongs to the same room (this is Pattern Control's audio direction).

* **Waveforms:** sines (with a touch of triangle for the muted thuds) and gently filtered noise. No square, no saw, no harsh noise; everything is low-passed, almost nothing above 4 kHz.
* **Envelopes:** every sound has a soft raised-cosine attack (4 to 12 ms for UI, up to 0.25 s for pads), a natural exponential decay and a smooth release. Nothing starts or stops hard: no clicks.
* **Space:** a short shared "room" (four damped combs) is baked into every chime, plink and fanfare and into the music's arpeggio.
* **One key:** C major pentatonic (C D E G A), the key of the music (chords C, Am, F, G). All pitched sounds come from it (`SfxSynth.note_hz(degree)`), so anything that overlaps harmonises. The music is never pitch-shifted. Repeated sounds get about +-3% random pitch and a hair of random level.
* **On the beat:** scrap plinks wait for the next sixteenth of the music (at most 0.19 s) and a streak climbs the scale one step per pickup, so collecting scrap plays a little melody in time with the music.
* **Mix:** peak by role: UI 0.08 (the quietest), gameplay 0.15, big moments (landing, new best, new zone, ignition) 0.20. The music's calm layer sits above all of them at its garage level, so **no gameplay sound is ever louder than the music** (the smoke test checks the files; the CI check checks the recording). Wind and rumble are quiet beds under the music. Level changes always glide (at most 60 dB a second).
* **Rendering:** nothing is synthesised on the phone. `scripts/SfxSynth.gd` is the recipe and `tools/render_audio.gd` bakes it into 44.1 kHz 16-bit mono WAVs: one-shots in `assets/audio/`, loops (`calm`, `hot`, `wind`, `rumble`) in `assets/audio/loops/`. They are committed; re-run `godot --headless --path . --script tools/render_audio.gd` after editing the recipe (the smoke test fails if they differ). One-shots play from a pool of 8 players, always taking a free one so a sound that is still ringing is never cut off.
* **Buses:** `SFX` and `Music`, and a hard limiter (ceiling -1 dB) on Master, all come from `default_bus_layout.tres`. No bus is ever created at run time (that silences the single-threaded web export).
* **Loops on the web:** Godot's web samples loop by restarting a buffer from the main thread, which leaves a gap at every wrap when a phone is busy. So the loading page (`PWAudio` in `web/shell.html`) plays the loops itself as native `AudioBufferSource` loops (gapless, off the main thread, phase-locked, through a limiter); the game only sends each layer's level and the wind's rate. The loops ship beside the page, not in the pck.
* **First tap and background:** browsers keep audio suspended until a tap, so the page resumes every `AudioContext` on the first tap. When the page is hidden, the phone is locked or the tab loses focus (`visibilitychange`, `pagehide`, `blur`) the page suspends every `AudioContext`, even before the game has loaded, and the game mutes Master and pauses a flight. Sound stays off when the page comes back until the player taps Resume (on the launch screen, any tap).
* **CI:** `tools/web_audio_check.js` loads the exported build in headless Chrome under a 4x CPU slowdown, taps through the game (first tap, garage music, UI sounds, LAUNCH, a flight, hide, show, Resume, landing and results) and records what reaches the speakers. It fails on silence, clicks, dropouts, repeated buffers, clipping, background leaks, an `AudioContext` still running while hidden, sound that returns without a Resume tap, or any one-shot whose peak is above the music's.
* **Export:** docs, tests and tools are left out of the export, as are the page-played loops (`assets/audio/loops/*`).

| Moment | Sound |
|---|---|
| UI | very quiet, very short soft knocks, each kind a little different (press, tap, back, toggle, pause, whoosh for sheets) |
| Buying | three rising plinks; when the part lands, a low muffled bell with a knock (clank) |
| Scrap | a soft bell plink, one scale step higher per pickup in a streak, on the beat |
| Bounce pad | a rubbery sine gliding up to G with a quick wobble |
| Updraft fan | air rushing up |
| Bird | two soft falling coos (E to C, then A to E) |
| Booster | an engine swell that opens up |
| Stall | a gentle falling pair (E to C) |
| Water skip | a bright soft splash |
| Landing | a deep thud, a low-passed noise burst and a low bell (A2) |
| Launchers | ramp and sled: a low rumble loop that stops at the lip; slingshot: a plucked sine falling from G5; catapult: low whoosh and thud; sled: a big low swell |
| Results | soft ticks while the distance counts up, a stamp thud, a five-note melody for a new best |
| New zone | a five-note rising melody |
| Wind | filtered air whose level and rate rise with speed |
| Music | garage: a warm pad with a soft bass; flight adds a plucked pentatonic arpeggio with a very soft pulse; the layers crossfade |

## App icon, splash, performance

* **Icon** (`icon.svg`, rendered to `icons/` by `tools/make_icons.gd`): Whiskers in his top hat in the gold glider leaving a rusty ramp, on the family sky-blue rounded square with the top highlight. **Splash** (`assets/splash.png`): the icon and the studio propeller on the brand navy `#14213d`, the same colour as the web loading page and the boot colour, so there is no seam from the page to the game.
* **Performance** (`?perf`): the CPU cost of a flight frame (simulation, drawing, UI) is under 9 ms in every zone (headless run through all 11 zones). Under software GL (no GPU) at 540 x 960 frames average 18 to 24 ms, with a handful of single frames up to 37 ms (Hills, Disco Planet, Junkyard) out of 2,000; real devices render far faster. Nothing is created in flight: particles, popups, coins and stars are pooled and pre-warmed.

## Studio mark and loading

The studio is **Clear Prop Games**; its mark is a bold three-blade propeller over a gold hub, with the name set in
Fredoka below it. The in-game logo intro (propeller spins up, wordmark, then the title; any tap skips) and the boot
splash use it. The web loading page (`web/shell.html`) is the same mark on the brand navy with a green progress bar and
no other text. The build stamp is hidden from players: it only shows with `?debug`, `?tune` or `?perf`, small, bottom-left.
