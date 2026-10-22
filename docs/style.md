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

## Studio mark and loading

The studio is **Clear Prop Games**; its mark is a bold three-blade propeller over a gold hub, with the name set in
Fredoka below it. The in-game logo intro (propeller spins up, wordmark, then the title; any tap skips) and the boot
splash use it. The web loading page (`web/shell.html`) is the same mark on the brand navy with a green progress bar and
no other text. The build stamp is hidden from players: it only shows with `?debug`, `?tune` or `?perf`, small, bottom-left.
