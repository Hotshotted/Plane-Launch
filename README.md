# Plane-Launch
Junkyard Launch: launch a junkyard glider and slowly upgrade to go farther and farther.

By **Clear Prop Games**. Style guide: `docs/style.md`. Debug switches on the page URL: `?debug` (build stamp), `?perf`, `?tune`.

Audio is pre-rendered (`scripts/SfxSynth.gd` is the recipe): after editing it run `godot --headless --path . --script tools/render_audio.gd` and commit the WAVs. CI plays the exported game in headless Chrome and checks the sound (`tools/web_audio_check.js`).
