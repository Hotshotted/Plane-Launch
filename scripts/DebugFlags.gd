class_name DebugFlags
extends RefCounted
## Debug switches, read from the page URL on web (or "--flag=value" user args elsewhere), so a
## suspected cause of a hitch can be switched off from a phone without a new build:
##   ?noprewarm     skip the start-up pre-warm and splash
##   ?perf          show a worst-frame-time readout (and a log of every frame over 50 ms)
##   ?tune          show the on-screen tuning panel (TUNE button, top-right)
##   ?debug         show the build stamp (also shown with ?tune or ?perf); players never see it
## Combine with "&", e.g.  ?perf&tune
## The active flags are printed under the build stamp.

static var _loaded := false
static var _bad: Array[String] = []    # unknown names (typos), shown in the summary
static var noprewarm := false
static var perf := false
static var tune := false
static var debug := false

static func prewarm_enabled() -> bool:
	_load()
	return not noprewarm

static func perf_enabled() -> bool:
	_load()
	return perf

## The build stamp is for us, not for players: only with ?debug, ?tune or ?perf.
static func stamp_visible() -> bool:
	_load()
	return debug or tune or perf

static func tune_enabled() -> bool:
	_load()
	return tune

## One-line description of the active flags ("" when none), shown next to the build stamp.
static func summary() -> String:
	_load()
	var parts: Array[String] = []
	if noprewarm:
		parts.append("noprewarm")
	if perf:
		parts.append("perf")
	if tune:
		parts.append("tune")
	if debug:
		parts.append("debug")
	for b in _bad:
		parts.append("?" + b)
	return " ".join(parts)

static func _load() -> void:
	if _loaded:
		return
	var args: Array[String] = []
	if OS.has_feature("web"):
		var q = JavaScriptBridge.eval("window.location.search")
		if q is String:
			for part in (q as String).trim_prefix("?").split("&", false):
				args.append(part)
	for a in OS.get_cmdline_user_args():
		args.append(a.trim_prefix("--"))
	parse(args)

## Parse "key" / "key=value" strings. Public so tests can feed it.
static func parse(args: Array[String]) -> void:
	_loaded = true
	_bad.clear()
	noprewarm = false
	perf = false
	tune = false
	debug = false
	for a in args:
		var kv := a.split("=", true, 1)
		var key := kv[0].uri_decode().to_lower()
		match key:
			"noprewarm":
				noprewarm = true
			"perf":
				perf = true
			"tune":
				tune = true
			"debug":
				debug = true
			"v":
				pass  # cache-busting parameter added by the page, not a flag
			_:
				_bad.append(key)
