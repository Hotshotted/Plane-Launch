class_name Hud
extends CanvasLayer
## Everything on top of the world: the flight HUD (distance, best, scrap, boost button), the
## between-runs panel (last result, the upgrade shop, LAUNCH), the start-up splash, the build stamp
## and the ?perf readout. Every node is created once in _ready(); afterwards things are only shown,
## hidden or get new text (and text is only set when the number it shows changed).

signal launch_pressed
signal buy_pressed(id: String)

const POPUPS := 6
const MODE_SHOP := 0
const MODE_FLIGHT := 1

var mode := MODE_SHOP

# flight HUD
var _flight_root: Control
var _dist: Label
var _best: Label
var _scrap: Label
var _gauge: Label
var _stall: Label
var _hint: Label
var _boost_panel: PanelContainer
var _boost_pips: Label
var _boost_style: StyleBoxFlat
var _pop_labels: Array[Label] = []
var _pop_born := PackedFloat32Array()
var _pop_y := PackedFloat32Array()
var _next_pop := 0
var _last_dist := -1
var _last_scrap := -1
var _last_gauge := -1
var _last_pips := -1
var _last_pips_max := -1

# shop
var _shop_root: Control
var _shop_scrap: Label
var _shop_best: Label
var _result: Label
var _row_name: Array[Label] = []
var _row_effect: Array[Label] = []
var _row_btn: Array[Button] = []
var _row_ids: Array[String] = []
var _launch_btn: Button
var _btn_afford: StyleBoxFlat
var _btn_poor: StyleBoxFlat
var _btn_max: StyleBoxFlat

# splash / debug
var _splash: Control
var _stamp: Label
var _perf_label: Label
var _perf_worst := 0.0
var _perf_window_start := 0
var _perf_shown := 0.0
var _hitch_count := 0
var _hitch_log: Array[String] = []
var _perf_extra := ""
var _time := 0.0

func _ready() -> void:
	layer = 10
	_build_flight_hud()
	_build_shop()
	_build_splash()
	_build_stamp()
	set_mode(MODE_SHOP)

# ---------------------------------------------------------------------------------------------
# Building
# ---------------------------------------------------------------------------------------------

func _label(size: int, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_CENTER, outline: int = 8) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", outline)
	l.horizontal_alignment = align
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _style(bg: Color, border: Color = Color.BLACK, radius: int = 18, bw: int = 4) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(radius)
	s.content_margin_left = 18
	s.content_margin_right = 18
	s.content_margin_top = 10
	s.content_margin_bottom = 10
	return s

func _full(c: Control) -> void:
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE

func _build_flight_hud() -> void:
	_flight_root = Control.new()
	_full(_flight_root)
	add_child(_flight_root)
	_dist = _label(120)
	_dist.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_dist.offset_top = 40
	_flight_root.add_child(_dist)
	_best = _label(38)
	_best.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_best.offset_top = 190
	_best.modulate = Color(1, 0.95, 0.6)
	_flight_root.add_child(_best)
	_scrap = _label(44, HORIZONTAL_ALIGNMENT_RIGHT)
	_scrap.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_scrap.offset_left = -420
	_scrap.offset_right = -30
	_scrap.offset_top = 250
	_scrap.modulate = Color(1, 0.85, 0.3)
	_flight_root.add_child(_scrap)
	_gauge = _label(32, HORIZONTAL_ALIGNMENT_LEFT, 6)
	_gauge.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_gauge.offset_left = 30
	_gauge.offset_top = 250
	_gauge.modulate = Color(1, 1, 1, 0.85)
	_flight_root.add_child(_gauge)
	_stall = _label(90)
	_stall.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_stall.offset_left = -400
	_stall.offset_right = 400
	_stall.offset_top = -420
	_stall.offset_bottom = -300
	_stall.text = "STALL!"
	_stall.modulate = Color(1, 0.3, 0.25)
	_stall.visible = false
	_flight_root.add_child(_stall)
	_hint = _label(46)
	_hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_hint.offset_left = -480
	_hint.offset_right = 480
	_hint.offset_top = -360
	_hint.offset_bottom = -220
	_hint.text = "HOLD = nose up\nRELEASE = nose down"
	_hint.visible = false
	_flight_root.add_child(_hint)
	# the boost button: bottom-right, handled by Main's input (rect hit test), never eats touches itself
	_boost_panel = PanelContainer.new()
	_boost_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_boost_panel.offset_left = -270
	_boost_panel.offset_right = -40
	_boost_panel.offset_top = -300
	_boost_panel.offset_bottom = -70
	_boost_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_boost_style = _style(Color(0.95, 0.5, 0.1), Color.BLACK, 40, 6)
	_boost_panel.add_theme_stylebox_override("panel", _boost_style)
	var bv := VBoxContainer.new()
	bv.alignment = BoxContainer.ALIGNMENT_CENTER
	bv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_boost_panel.add_child(bv)
	var bl := _label(48)
	bl.text = "BOOST"
	bv.add_child(bl)
	_boost_pips = _label(40)
	bv.add_child(_boost_pips)
	_flight_root.add_child(_boost_panel)
	for i in POPUPS:
		var p := _label(56)
		p.visible = false
		p.size = Vector2(500, 80)
		_flight_root.add_child(p)
		_pop_labels.append(p)
	_pop_born.resize(POPUPS)
	_pop_y.resize(POPUPS)

func _build_shop() -> void:
	_shop_root = Control.new()
	_full(_shop_root)
	add_child(_shop_root)
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	panel.offset_top = -1090
	panel.add_theme_stylebox_override("panel", _style(Color(0.13, 0.15, 0.2, 0.97), Color.BLACK, 36, 6))
	_shop_root.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	panel.add_child(col)
	var head := HBoxContainer.new()
	_shop_scrap = _label(54, HORIZONTAL_ALIGNMENT_LEFT, 0)
	_shop_scrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_shop_scrap.modulate = Color(1, 0.85, 0.3)
	_shop_best = _label(40, HORIZONTAL_ALIGNMENT_RIGHT, 0)
	_shop_best.modulate = Color(1, 0.95, 0.6)
	head.add_child(_shop_scrap)
	head.add_child(_shop_best)
	col.add_child(head)
	_result = _label(36, HORIZONTAL_ALIGNMENT_CENTER, 0)
	_result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_result.custom_minimum_size = Vector2(0, 100)
	_result.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	col.add_child(_result)
	_btn_afford = _style(Color(0.2, 0.62, 0.3), Color.BLACK, 16, 4)
	_btn_poor = _style(Color(0.3, 0.3, 0.34), Color.BLACK, 16, 4)
	_btn_max = _style(Color(0.55, 0.45, 0.15), Color.BLACK, 16, 4)
	for u in Tuning.upgrades:
		var row := PanelContainer.new()
		row.add_theme_stylebox_override("panel", _style(Color(0.2, 0.23, 0.3), Color.BLACK, 16, 4))
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 14)
		row.add_child(h)
		var v := VBoxContainer.new()
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.add_theme_constant_override("separation", 0)
		h.add_child(v)
		var nm := _label(40, HORIZONTAL_ALIGNMENT_LEFT, 0)
		var ef := _label(30, HORIZONTAL_ALIGNMENT_LEFT, 0)
		ef.modulate = Color(0.75, 0.9, 1.0)
		v.add_child(nm)
		v.add_child(ef)
		var b := Button.new()
		b.custom_minimum_size = Vector2(250, 92)
		b.add_theme_font_size_override("font_size", 38)
		for st in ["normal", "hover", "pressed", "disabled", "focus"]:
			b.add_theme_stylebox_override(st, _btn_afford)
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(_on_buy.bind(u["id"]))
		h.add_child(b)
		col.add_child(row)
		_row_name.append(nm)
		_row_effect.append(ef)
		_row_btn.append(b)
		_row_ids.append(u["id"])
	_launch_btn = Button.new()
	_launch_btn.text = "LAUNCH!"
	_launch_btn.custom_minimum_size = Vector2(0, 150)
	_launch_btn.add_theme_font_size_override("font_size", 70)
	var ls := _style(Color(0.95, 0.55, 0.1), Color.BLACK, 30, 6)
	for st in ["normal", "hover", "pressed", "focus"]:
		_launch_btn.add_theme_stylebox_override(st, ls)
	_launch_btn.focus_mode = Control.FOCUS_NONE
	_launch_btn.pressed.connect(func(): launch_pressed.emit())
	col.add_child(_launch_btn)

func _build_splash() -> void:
	_splash = Control.new()
	_full(_splash)
	_splash.mouse_filter = Control.MOUSE_FILTER_STOP
	_splash.visible = false
	var bg := ColorRect.new()
	bg.color = Color(0.1, 0.12, 0.17, 0.97)
	_full(bg)
	_splash.add_child(bg)
	var t := _label(100)
	_full(t)
	t.text = "JUNKYARD\nLAUNCH"
	t.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_splash.add_child(t)
	add_child(_splash)

func _build_stamp() -> void:
	_stamp = _label(26, HORIZONTAL_ALIGNMENT_LEFT, 6)
	_stamp.text = "%s  %s" % [BuildInfo.COMMIT, BuildInfo.TIME]
	var flags := DebugFlags.summary()
	if flags != "":
		_stamp.text += "\n" + flags
	_stamp.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_stamp.offset_left = 14
	_stamp.offset_top = -48 if flags == "" else -84
	_stamp.modulate = Color(1, 1, 1, 0.55)
	add_child(_stamp)
	if DebugFlags.perf_enabled():
		_perf_label = _label(26, HORIZONTAL_ALIGNMENT_LEFT, 6)
		_perf_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		_perf_label.offset_left = 14
		_perf_label.offset_top = 14
		_perf_label.modulate = Color(0.6, 1, 0.6, 0.9)
		add_child(_perf_label)

# ---------------------------------------------------------------------------------------------
# Modes
# ---------------------------------------------------------------------------------------------

func set_mode(m: int) -> void:
	mode = m
	_flight_root.visible = m == MODE_FLIGHT
	_shop_root.visible = m == MODE_SHOP
	_stall.visible = false
	for p in _pop_labels:
		p.visible = false
	_last_dist = -1
	_last_scrap = -1
	_last_gauge = -1
	_last_pips = -1

func show_splash(on: bool) -> void:
	_splash.visible = on

## Pre-warm: draw every part of the UI at once (under the splash) so fonts and styles are set up.
func prewarm_show(on: bool) -> void:
	_flight_root.visible = on
	_shop_root.visible = on
	_stall.visible = on
	_hint.visible = on
	for p in _pop_labels:
		p.visible = on
		p.text = "BOUNCE! +12 NEW BEST!"
	if on:
		_dist.text = "1234 m"
		_best.text = "BEST 1234 m"
		_scrap.text = "SCRAP +99"
		_gauge.text = "SPD 99  ALT 99"
		_boost_pips.text = "●●●●○○"
	else:
		_hint.visible = false

# ---------------------------------------------------------------------------------------------
# Flight HUD updates
# ---------------------------------------------------------------------------------------------

func set_best(best: float) -> void:
	_best.text = "BEST %s m" % Tuning.fmt(best) if best > 0.0 else ""

func set_flight(distance: float, scrap_value: int, speed: float, alt: float, stalled: bool, charges: int, charges_max: int, boosting: bool) -> void:
	var d := int(distance)
	if d != _last_dist:
		_last_dist = d
		_dist.text = "%d m" % d
	if scrap_value != _last_scrap:
		_last_scrap = scrap_value
		_scrap.text = "SCRAP +%d" % scrap_value
	var g := int(speed) * 1000 + mini(int(alt), 999)
	if g != _last_gauge:
		_last_gauge = g
		_gauge.text = "SPD %d  ALT %d" % [int(speed), int(alt)]
	_stall.visible = stalled and (int(_time * 8.0) % 2 == 0)
	var pips_key := charges * 100 + charges_max
	if pips_key != _last_pips:
		_last_pips = pips_key
		var s := ""
		for i in charges_max:
			s += "●" if i < charges else "○"
		_boost_pips.text = s
	_boost_panel.visible = charges_max > 0
	_boost_style.bg_color = Color(1.0, 0.85, 0.2) if boosting else (Color(0.95, 0.5, 0.1) if charges > 0 else Color(0.4, 0.38, 0.36))

func show_hint(on: bool) -> void:
	_hint.visible = on

## Screen rectangle of the BOOST button (for Main's hit test); empty when there is no booster.
func boost_rect() -> Rect2:
	if not _boost_panel.visible or mode != MODE_FLIGHT:
		return Rect2()
	return _boost_panel.get_global_rect()

## Floating text at a screen position ("+1", "BOUNCE!").
func popup(text: String, pos: Vector2, color: Color) -> void:
	var i := _next_pop
	_next_pop = (_next_pop + 1) % POPUPS
	var l := _pop_labels[i]
	l.text = text
	l.modulate = color
	l.size = Vector2(500, 80)
	l.position = pos - Vector2(250, 40)
	l.visible = true
	_pop_born[i] = _time
	_pop_y[i] = l.position.y

# ---------------------------------------------------------------------------------------------
# Shop
# ---------------------------------------------------------------------------------------------

func _on_buy(id: String) -> void:
	buy_pressed.emit(id)

## Refresh every text in the shop from the save. `last` = the last run's result, or empty.
func refresh_shop(last: Dictionary) -> void:
	_shop_scrap.text = "SCRAP  %s" % Tuning.fmt(Save.scrap)
	_shop_best.text = "BEST  %s m" % Tuning.fmt(Save.best_distance)
	if last.is_empty():
		_result.text = "Hold the screen to pitch up, let go to dive.\nDive for speed, climb to trade it for height. Too slow and you stall!" if Save.runs == 0 else ""
	else:
		var t := "LANDED  %s m" % Tuning.fmt(last["distance"])
		if last["new_best"]:
			t += "   NEW BEST!"
		t += "\n+%s scrap  (%s from distance, %s from %d pickups)" % [Tuning.fmt(last["earned"]), Tuning.fmt(last["dist_scrap"]), Tuning.fmt(last["picked"]), last["picked_count"]]
		_result.text = t
		_result.modulate = Color(1, 0.95, 0.5) if last["new_best"] else Color(1, 1, 1)
	for i in _row_ids.size():
		var id := _row_ids[i]
		var u := Tuning.upgrade_def(id)
		var lv := Save.level(id)
		_row_name[i].text = "%s   %d/%d" % [u["name"], lv, u["max"]]
		_row_effect[i].text = Tuning.effect_text(id, lv)
		var b := _row_btn[i]
		var st := _btn_max if Save.is_maxed(id) else (_btn_afford if Save.can_buy(id) else _btn_poor)
		for sn in ["normal", "hover", "pressed", "disabled", "focus"]:
			b.add_theme_stylebox_override(sn, st)
		b.text = "MAX" if Save.is_maxed(id) else Tuning.fmt(Save.cost_of_next(id))
		b.disabled = Save.is_maxed(id)

# ---------------------------------------------------------------------------------------------
# Per frame, ?perf
# ---------------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	_time += delta
	for i in POPUPS:
		var l := _pop_labels[i]
		if not l.visible or mode != MODE_FLIGHT:
			continue
		var age := _time - _pop_born[i]
		if age > 0.9:
			l.visible = false
		else:
			l.position.y = _pop_y[i] - age * 120.0
			var m := l.modulate
			m.a = clampf(1.0 - age / 0.9, 0.0, 1.0)
			l.modulate = m
	_update_perf(delta)

func set_perf_extra(text: String) -> void:
	_perf_extra = text

## ?perf: a frame took more than 50 ms. `raw` = the real frame, `used` = what the simulation took of it.
func note_hitch(raw: float, used: float, why: String, context: String) -> void:
	_hitch_count += 1
	var line := "#%d %.0f ms (simulated %.0f ms) %s | %s" % [_hitch_count, raw * 1000.0, used * 1000.0, why, context]
	_hitch_log.append(line)
	if _hitch_log.size() > 5:
		_hitch_log.pop_front()
	print("[hitch] " + line)   # (also in the browser console)

func _update_perf(delta: float) -> void:
	if _perf_label == null:
		return
	var ms := delta * 1000.0
	_perf_worst = maxf(_perf_worst, ms)
	var now := Time.get_ticks_msec()
	if now - _perf_window_start > 3000:
		_perf_shown = _perf_worst
		_perf_worst = 0.0
		_perf_window_start = now
	_perf_label.text = "worst frame (3s): %.0f ms   fps %d\n%s\nhitches (over 50 ms):\n%s" % [_perf_shown, Engine.get_frames_per_second(), _perf_extra, "\n".join(_hitch_log)]
