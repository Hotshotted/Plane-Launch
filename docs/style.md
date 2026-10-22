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

All procedural (`scripts/Sfx.gd`, no audio files), on two buses: **SFX** and **Music**, with their volumes in the pause menu (saved). Short, soft and rounded.

* **UI:** a soft click when a finger goes down (`press`), a bright blip going forward (`tap`), a falling pair going back (`back`), a rising ping for a purchase (`buy`), a metal `clank` when a part bolts on, a `stamp` on paper, `tick`s while the distance counts up, a small fanfare for a new best (`best`).
* **World:** scrap `clink`s (pitch varies), pads `boing`, birds `squawk`, fans whoosh (`fan`), the booster roars (`boost`), water `splash`es, the landing `crunch`es, a stall buzzes.
* **Launchers:** the ramp and sled rumble (a loop that stops at the lip), the slingshot `snap`s, the catapult `swing`s, the sled `ignite`s.
* **Wind:** a loop whose volume and pitch rise with speed; silent when paused.
* **Music:** a calm layer for the garage; flight adds a driving layer. Layers glide between levels (at most 40 dB a second), never cut, so garage to flight to garage is one continuous mix.

## App icon, splash, performance

* **Icon** (`icon.svg`, rendered to `icons/` by `tools/make_icons.gd`): Whiskers in his top hat in the gold glider leaving a rusty ramp, on the family sky-blue rounded square with the top highlight. **Splash** (`assets/splash.png`): the icon and the studio propeller on the brand navy `#14213d`, the same colour as the web loading page and the boot colour, so there is no seam from the page to the game.
* **Performance** (`?perf`): the CPU cost of a flight frame (simulation, drawing, UI) is under 9 ms in every zone (headless run through all 11 zones). Under software GL (no GPU) at 540 x 960 frames average 18 to 24 ms, with a handful of single frames up to 37 ms (Hills, Disco Planet, Junkyard) out of 2,000; real devices render far faster. Nothing is created in flight: particles, popups, coins and stars are pooled and pre-warmed.

## Studio mark and loading

The studio is **Clear Prop Games**; its mark is a bold three-blade propeller over a gold hub, with the name set in
Fredoka below it. The in-game logo intro (propeller spins up, wordmark, then the title; any tap skips) and the boot
splash use it. The web loading page (`web/shell.html`) is the same mark on the brand navy with a green progress bar and
no other text. The build stamp is hidden from players: it only shows with `?debug`, `?tune` or `?perf`, small, bottom-left.
