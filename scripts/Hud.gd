class_name Hud
extends CanvasLayer
## All UI. One primary thing per screen, big and high contrast; everything else smaller and quieter,
## or behind a tap:
##   FLIGHT   distance (huge), a quiet best-distance line, the boost button with its charges, brief
##            popups / toasts. Nothing else.
##   LAUNCH   the glider on its launcher (the world), Rusty's mission clipboard, four nav buttons and a
##            huge LAUNCH button. Upgrades, garage, style and daily open as a sheet over the clipboard.
##   RESULTS  a card over the world: the distance, then scrap, missions done, new missions, Rusty.
## Three text sizes (HERO / BODY / SMALL) and one accent colour (orange; gold only for scrap).
## Every node is created once in _ready(); afterwards things are only shown, hidden or get new text.

signal launch_pressed
signal buy_pressed(id: String)
signal frame_pressed(id: String)       # buy or equip a frame
signal launcher_pressed(id: String)    # buy or equip a launcher
signal cosmetic_pressed(kind: String, id: String)   # buy or equip a paint, hat or trail
signal daily_pressed
signal ad_double_pressed
signal ad_boost_pressed

const HERO := Style.SZ_XL
const BODY := Style.SZ_M
const SMALL := Style.SZ_S
const PANEL_H := 1000          # height of the launch screen's bottom stack (the world gets the rest)
const POPUPS := 6
const MODE_SHOP := 0
const MODE_FLIGHT := 1

# palette: ink on dark, one accent, gold for scrap, red only for danger
const C_PANEL := Style.SURFACE_DARK
const C_CARD := Style.SURFACE_DARK_2
const C_TEXT := Style.TEXT
const C_MUTED := Style.TEXT_SOFT
const C_ACCENT := Style.ACCENT          # gold: rewards, highlights
const C_GO := Style.SUCCESS             # green: the thing to press
const C_GOLD := Style.ACCENT
const C_OFF := Style.SURFACE_DARK_2
const C_DANGER := Style.DANGER
const C_PAPER := Style.PAPER
const C_INK := Style.PAPER_INK
const C_INK_SOFT := Style.PAPER_SOFT
const C_ON_GO := Color.WHITE

var mode := MODE_SHOP

# ---- flight ----
var _flight_root: Control
var _dist: Label
var _best: Label
var _toast: Label
var _toast_born := -10.0
var _stall: Label
var _hint: Label
var _banner: Label
var _banner_born := -10.0
var _boost_panel: PanelContainer
var _boost_pips: Label
var _boost_style: StyleBoxFlat
var _pop_labels: Array[Label] = []
var _pop_born := PackedFloat32Array()
var _pop_y := PackedFloat32Array()
var _next_pop := 0
var _last_dist := -1
var _last_pips := -1

# ---- launch screen ----
var _shop_root: Control
var _shop_scrap: Label
var _shop_best: Label
var _zone_label: Label
var _shop_bar := {}
var _shop_bar_key := -1
var _clip: PanelContainer
var _clip_t := 0.0                # 0 closed .. 1 open (animated)
var _clip_target := 0.0
var _clip_hold := 0.0             # > 0: close by itself after this many seconds
var _bubble: Button
var _badge: Label
var _cards_box: VBoxContainer
var _card_panels: Array[PanelContainer] = []
var _card_styles: Array[StyleBoxFlat] = []
var _card_pips: Array[LevelPips] = []
var _card_icons: Array[UpgradeIcon] = []
var _rusty: Rusty
var _rusty_says: Label
var _mission_icons: Array[GlyphView] = []
var _mission_rows: Array[Label] = []
var _mission_rewards: Array[Label] = []
var _mission_counts: Array[Label] = []
var _mission_fills: Array[ColorRect] = []
var _mission_new: Array[Label] = []
var _nav_buttons: Array[Button] = []
var _launch_btn: Button
var _ad_boost_btn: Button

# ---- sheet (upgrades / garage / style / daily) ----
var _sheet: PanelContainer
var _sheet_title: Label
var _sub_tabs: HBoxContainer
var _sub_buttons: Array[Button] = []
var _tab_pages: Array[VBoxContainer] = []
var _tab := 0
var _row_name: Array[Label] = []
var _row_effect: Array[Label] = []
var _row_btn: Array[Button] = []
var _row_ids: Array[String] = []
var _frame_rows: Array[Dictionary] = []
var _launcher_rows: Array[Dictionary] = []
var _style_cat := 0
var _style_cat_buttons: Array[Button] = []
var _style_rows: Array[Dictionary] = []
var _daily_title: Label
var _daily_info: Label
var _daily_btn: Button
var _sb_accent: StyleBoxFlat
var _sb_off: StyleBoxFlat
var _sb_done: StyleBoxFlat
var _sb_card: StyleBoxFlat
var _sb_tab: StyleBoxFlat
var _pressed_of := {}
var _padded_cache := {}
var _scrim: ColorRect
var _top_row: HBoxContainer
var _stack: VBoxContainer

# ---- results ----
var _results: Control
var _res_caption: Label
var _res_dist: Label
var _res_badge: Label
var _res_scrap: Label
var _res_detail: Label
var _res_mcap: Label
var _res_missions: Label
var _res_new: Label
var _res_rusty_pic: Rusty
var _res_rusty: Label
var _res_continue: Button
var _ad_double_btn: Button

# ---- splash / ad / debug ----
var _splash: Control
var _ad_screen: Control
var _ad_title: Label
var _ad_sub: Label
var _ad_left := 0.0
var _ad_callback := Callable()
var ad_active := false
var _stamp: Label
var _perf_label: Label
var _perf_worst := 0.0
var _perf_window_start := 0
var _perf_shown := 0.0
var _hitch_count := 0
var _hitch_log: Array[String] = []
var _perf_extra := ""
var _aim_key := -1
var _time := 0.0

# the logo intro: studio logo, then the title; any tap skips it
static var intro_enabled := true
const STUDIO_NAME := "Clear Prop\nGames"
const INTRO_LOGO := 1.3
const INTRO_TITLE := 2.5
const INTRO_END := 3.0
var _intro: Control
var _intro_logo: Control
var _intro_mark: GlyphView
var _intro_title: Control
var _intro_t := -1.0
var intro_active := false

func _ready() -> void:
	layer = 10
	Style.detect_safe(Vector2(1080, 1920))
	_make_styles()
	_build_flight_hud()
	_build_launch_screen()
	_build_sheet()
	_build_results()
	_build_splash()
	_build_ad_screen()
	_build_intro()
	move_child(_ad_screen, _splash.get_index())   # the splash stays on top of it during the pre-warm
	_build_stamp()
	_apply_safe()
	set_mode(MODE_SHOP)

## Keep everything out of the notch, rounded corners and home indicator (Style.safe_*): top-anchored pieces move
## down, bottom-anchored ones up, the launch stack and the sheet in from the sides.
func _apply_safe() -> void:
	var st := Style.safe_top
	var sb := Style.safe_bottom
	var sl := Style.safe_left
	var sr := Style.safe_right
	for c in [_dist, _best, _toast, _scrim, _top_row, _shop_bar["row"], _ad_boost_btn, _bubble, _clip]:
		c.offset_top += st
		c.offset_bottom += st
	for c in [_boost_panel, _boost_pips]:
		c.offset_top -= sb
		c.offset_bottom -= sb
	for c in [_stack, _sheet]:
		c.offset_bottom -= sb
		c.offset_left += sl
		c.offset_right -= sr
	_sheet.offset_top -= sb
	_stack.offset_top -= sb
	for c in [_top_row, _shop_bar["row"], _ad_boost_btn]:
		c.offset_left += sl
	for c in [_top_row, _shop_bar["row"]]:
		c.offset_right -= sr
	for c in [_bubble, _clip, _boost_panel]:
		c.offset_right -= sr
	_boost_pips.offset_right -= sr
	_boost_pips.offset_left -= sr
	_boost_panel.offset_left -= sr
	_bubble.offset_left -= sr
	_clip.offset_left -= sr
	_stamp.offset_top -= sb
	_stamp.offset_left += sl

# ---------------------------------------------------------------------------------------------
# Building blocks
# ---------------------------------------------------------------------------------------------

func _make_styles() -> void:
	_sb_accent = _chunky(Style.SUCCESS, Style.SUCCESS_DARK)         # primary: the thing to press
	_sb_off = _chunky(Style.SURFACE_DARK_2, Style.INK)               # secondary, can't yet
	_sb_done = _ghost()                                              # ghost: already so
	_sb_card = _chunky(Style.PRIMARY, Style.PRIMARY_DARK)            # secondary: navigation, tabs
	_sb_tab = _chunky(Style.SURFACE_DARK_2, Style.INK)

## A panel in the shared style: soft shadow, light inner border (Style.box), with this screen's content margins.
func _box(bg: Color, border: Color = Style.INK, radius: int = Style.R_M, bw: int = 3) -> StyleBoxFlat:
	var s := Style.box(bg, border, radius, bw)
	s.content_margin_left = Style.SP_2
	s.content_margin_right = Style.SP_2
	s.content_margin_top = 10
	s.content_margin_bottom = 10
	return s

## The chunky button: a rounded face over a dark "lip" (the bottom border). Pressing sinks the face onto the lip.
func _chunky(face: Color, lip: Color, pressed: bool = false) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = face.darkened(0.08) if pressed else face
	s.border_color = lip
	s.border_width_bottom = 3 if pressed else int(Style.LIP)
	s.set_corner_radius_all(Style.R_L)
	s.anti_aliasing = true
	s.content_margin_left = Style.SP_2
	s.content_margin_right = Style.SP_2
	s.content_margin_top = 6 + (int(Style.LIP) - 3 if pressed else 0)
	s.content_margin_bottom = 6
	if not pressed:
		s.shadow_color = Style.SHADOW_COLOR
		s.shadow_size = 10
		s.shadow_offset = Style.SHADOW_OFFSET
	if not _pressed_of.has(s) and not pressed:
		_pressed_of[s] = _chunky(face, lip, true)
	return s

## The ghost button: no fill, a light outline.
func _ghost() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(Style.SURFACE_DARK, 0.35)
	s.border_color = Style.LINE
	s.set_border_width_all(2)
	s.set_corner_radius_all(Style.R_L)
	s.anti_aliasing = true
	s.content_margin_left = Style.SP_2
	s.content_margin_right = Style.SP_2
	s.content_margin_top = 6
	s.content_margin_bottom = 6
	return s

func _label(size: int, color: Color = C_TEXT, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_CENTER, outline: int = 0) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_font_override("font", Style.display() if size >= Style.SZ_M else Style.text())
	l.add_theme_color_override("font_color", color)
	if outline > 0:
		l.add_theme_color_override("font_outline_color", Style.INK)
		l.add_theme_constant_override("outline_size", outline)
	l.horizontal_alignment = align
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _full(c: Control) -> void:
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE

func _style_button(b: Button, st: StyleBoxFlat, text_color: Color = C_TEXT) -> void:
	b.set_meta("st", st)
	b.set_meta("tc", text_color)
	var down: StyleBoxFlat = _pressed_of.get(st, st)
	if _icon_shown(b):     # room for the icon beside the centred text
		var extra: float = (b.get_meta("ico") as GlyphView).custom_minimum_size.x + 14.0
		st = _padded(st, extra)
		down = _padded(down, extra)
	for sn in ["normal", "hover", "disabled", "focus"]:
		b.add_theme_stylebox_override(sn, st)
	b.add_theme_stylebox_override("pressed", down)
	for cn in ["font_color", "font_hover_color", "font_pressed_color", "font_disabled_color", "font_focus_color"]:
		b.add_theme_color_override(cn, text_color)

func _button(text: String, size: int, min_h: float, st: StyleBoxFlat, text_color: Color = C_TEXT) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, min_h)
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_font_override("font", Style.display() if size >= Style.SZ_M else Style.text())
	b.focus_mode = Control.FOCUS_NONE
	_style_button(b, st, text_color)
	return b

## Set a button to the accent (something to do), off (can't yet) or done (already so) look.
func _look(b: Button, kind: int, text: String) -> void:
	b.text = text
	match kind:
		0:
			_style_button(b, _sb_accent, C_ON_GO)
			b.disabled = false
		1:
			_style_button(b, _sb_off, Style.TEXT_QUIET)
			b.disabled = false
		_:
			_style_button(b, _sb_done, Style.TEXT_QUIET)
			b.disabled = true
	_place_icon(b)

## `st` with `extra` more left padding (cached).
func _padded(st: StyleBoxFlat, extra: float) -> StyleBoxFlat:
	var key := "%d_%d" % [st.get_instance_id(), int(extra)]
	if not _padded_cache.has(key):
		var d: StyleBoxFlat = st.duplicate()
		d.content_margin_left = st.content_margin_left + extra
		_padded_cache[key] = d
	return _padded_cache[key]

func _icon_shown(b: Button) -> bool:
	if not b.has_meta("ico"):
		return false
	return b.get_meta("always", false) or (b.text != "" and b.text.unicode_at(0) >= 48 and b.text.unicode_at(0) <= 57)

## A small icon control.
func _icon(id: String, px: float, col: Color = C_TEXT) -> GlyphView:
	var g := GlyphView.new()
	g.custom_minimum_size = Vector2(px, px)
	g.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	g.set_glyph(id, col)
	return g

## Put an icon just left of a button's centred text (the button's text stays as it is, for tests and screen readers).
func _attach_icon(b: Button, glyph: String, px: float, col: Color = C_ON_GO) -> GlyphView:
	var g := _icon(glyph, px, col)
	g.anchor_left = 0.5
	g.anchor_right = 0.5
	g.anchor_top = 0.5
	g.anchor_bottom = 0.5
	b.add_child(g)
	b.set_meta("ico", g)
	if b.has_meta("st"):
		_style_button(b, b.get_meta("st"), b.get_meta("tc"))
	_place_icon(b)
	return g

func _place_icon(b: Button) -> void:
	if not b.has_meta("ico"):
		return
	var g: GlyphView = b.get_meta("ico")
	var px := g.custom_minimum_size.x
	var f: Font = b.get_theme_font("font")
	var fs := b.get_theme_font_size("font_size")
	var tw := f.get_string_size(b.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x if b.text != "" else 0.0
	g.offset_left = -tw * 0.5 - px - 14.0 + (px + 14.0) * 0.5
	g.offset_right = g.offset_left + px
	g.offset_top = -px * 0.5
	g.offset_bottom = px * 0.5
	g.visible = _icon_shown(b)

# ---------------------------------------------------------------------------------------------
# FLIGHT: distance, best, boost, brief popups
# ---------------------------------------------------------------------------------------------

func _build_flight_hud() -> void:
	_flight_root = Control.new()
	_full(_flight_root)
	add_child(_flight_root)
	_dist = _label(HERO, C_TEXT, HORIZONTAL_ALIGNMENT_CENTER, 14)
	_dist.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_dist.offset_top = 44
	_flight_root.add_child(_dist)
	_best = _label(SMALL, C_MUTED, HORIZONTAL_ALIGNMENT_CENTER, 6)
	_best.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_best.offset_top = 188
	_flight_root.add_child(_best)
	_toast = _label(BODY, C_ACCENT, HORIZONTAL_ALIGNMENT_CENTER, 6)
	_toast.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_toast.offset_top = 240
	_toast.visible = false
	_flight_root.add_child(_toast)
	_stall = _label(HERO, C_DANGER, HORIZONTAL_ALIGNMENT_CENTER, 12)
	_stall.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_stall.offset_left = -400
	_stall.offset_right = 400
	_stall.offset_top = -420
	_stall.offset_bottom = -280
	_stall.text = "STALL!"
	_stall.visible = false
	_flight_root.add_child(_stall)
	_banner = _label(BODY, C_TEXT, HORIZONTAL_ALIGNMENT_CENTER, 7)
	_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_banner.offset_left = -520
	_banner.offset_right = 520
	_banner.offset_top = -560
	_banner.offset_bottom = -380
	_banner.visible = false
	_flight_root.add_child(_banner)
	_hint = _label(BODY, C_TEXT, HORIZONTAL_ALIGNMENT_CENTER, 8)
	_hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_hint.offset_left = -480
	_hint.offset_right = 480
	_hint.offset_top = -420
	_hint.offset_bottom = -280
	_hint.text = "HOLD = nose up\nRELEASE = nose down"
	_hint.visible = false
	_flight_root.add_child(_hint)
	# the boost button: bottom-right; Main's input hit-tests its rect, it never eats touches itself
	_boost_panel = PanelContainer.new()
	_boost_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_boost_panel.offset_left = -270
	_boost_panel.offset_right = -40
	_boost_panel.offset_top = -300
	_boost_panel.offset_bottom = -70
	_boost_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_boost_style = _box(Glyphs.FLAME, Style.INK, Style.R_L, 4)
	_boost_panel.add_theme_stylebox_override("panel", _boost_style)
	var bl := _label(BODY, C_ON_GO)
	bl.text = "BOOST"
	bl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_boost_panel.add_child(bl)
	_flight_root.add_child(_boost_panel)
	_boost_pips = _label(BODY, Glyphs.FLAME, HORIZONTAL_ALIGNMENT_RIGHT, 8)
	_boost_pips.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_boost_pips.offset_left = -640
	_boost_pips.offset_right = -290
	_boost_pips.offset_top = -210
	_boost_pips.offset_bottom = -150
	_flight_root.add_child(_boost_pips)
	for i in POPUPS:
		var p := _label(BODY, C_TEXT, HORIZONTAL_ALIGNMENT_CENTER, 6)
		p.visible = false
		p.size = Vector2(560, 70)
		_flight_root.add_child(p)
		_pop_labels.append(p)
	_pop_born.resize(POPUPS)
	_pop_y.resize(POPUPS)

## The best-distance line under the distance ("" hides it).
func set_best(best: float) -> void:
	_best.text = "BEST %s m" % Tuning.fmt(best) if best > 0.0 else ""

## During the Daily Launch the same quiet line shows the target instead.
func set_daily_target(target: int) -> void:
	if target > 0:
		_best.text = "DAILY TARGET %s m" % Tuning.fmt(target)

func set_flight(distance: float, charges: int, charges_max: int, boosting: bool, stalled: bool) -> void:
	var d := int(distance)
	if d != _last_dist:
		_last_dist = d
		_dist.text = "%d m" % d
	_stall.visible = stalled and (int(_time * 8.0) % 2 == 0)
	var pips_key := charges * 100 + charges_max
	if pips_key != _last_pips:
		_last_pips = pips_key
		var s := ""
		for i in charges_max:
			s += "●" if i < charges else "○"
		_boost_pips.text = s
	_boost_panel.visible = charges_max > 0
	_boost_pips.visible = charges_max > 0
	_boost_style.bg_color = Style.ACCENT if boosting else (Glyphs.FLAME if charges > 0 else Style.SURFACE_DARK_2)

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
	l.add_theme_color_override("font_color", color)
	l.size = Vector2(560, 70)
	l.position = pos - Vector2(280, 35)
	l.modulate = Color.WHITE
	l.visible = true
	_pop_born[i] = _time
	_pop_y[i] = l.position.y

## A short line under the distance ("Bounces 2/3"); replaced by the next one, gone after about two seconds.
func toast(text: String) -> void:
	_toast.text = text
	_toast.modulate = Color.WHITE
	_toast.visible = true
	_toast_born = _time

## Big centred banner ("NEW ZONE!" ...), fading after about two seconds.
func banner(text: String, color: Color) -> void:
	_banner.text = text
	_banner.add_theme_color_override("font_color", color)
	_banner.modulate = Color.WHITE
	_banner.visible = true
	_banner_born = _time

## Slingshot: the aim read-out and hint while pulling back.
func show_aim(on: bool, power: float, angle: float) -> void:
	if not on:
		if _aim_key != -1:
			_aim_key = -1
			_hint.text = "HOLD = nose up\nRELEASE = nose down"
			_hint.visible = false
		return
	var key := int(power * 100.0) * 1000 + int(angle)
	if key != _aim_key:
		_aim_key = key
		_hint.text = "PULL BACK, THEN LET GO!\nPOWER %d%%   ANGLE %d°" % [int(power * 100.0), int(angle)]
	_hint.visible = true

# ---------------------------------------------------------------------------------------------
# LAUNCH SCREEN: the glider (world), the clipboard, nav, LAUNCH
# ---------------------------------------------------------------------------------------------

func _build_launch_screen() -> void:
	_shop_root = Control.new()
	_full(_shop_root)
	add_child(_shop_root)
	# a quiet top line: scrap, farthest zone, best (on a soft dark strip so it reads over clouds)
	var scrim := ColorRect.new()
	_scrim = scrim
	scrim.color = Color(Style.SCRIM, 0.5)
	scrim.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	scrim.offset_bottom = 112
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shop_root.add_child(scrim)
	var top := HBoxContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 28
	top.offset_right = -28
	top.offset_top = 24
	top.offset_bottom = 84
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shop_root.add_child(top)
	_top_row = top
	top.add_child(_icon("scrap", 52))
	_shop_scrap = _label(BODY, C_GOLD, HORIZONTAL_ALIGNMENT_LEFT, 8)
	_shop_scrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_shop_scrap)
	top.add_child(_icon("flag", 36))
	_zone_label = _label(SMALL, C_MUTED, HORIZONTAL_ALIGNMENT_LEFT, 6)
	_zone_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_zone_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(_zone_label)
	top.add_child(_icon("trophy", 40))
	_shop_best = _label(SMALL, C_MUTED, HORIZONTAL_ALIGNMENT_RIGHT, 6)
	_shop_best.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(_shop_best)
	_shop_bar = _make_bar(_shop_root, 92.0)
	_ad_boost_btn = _button("FREE BOOST", SMALL, 56, _sb_done, C_MUTED)
	_ad_boost_btn.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_ad_boost_btn.offset_left = 28
	_ad_boost_btn.offset_right = 330
	_ad_boost_btn.offset_top = 126
	_ad_boost_btn.offset_bottom = 182
	_ad_boost_btn.set_meta("always", true)
	_attach_icon(_ad_boost_btn, "ad", 30, Style.TEXT_SOFT)
	_ad_boost_btn.pressed.connect(func(): ad_boost_pressed.emit())
	_shop_root.add_child(_ad_boost_btn)
	# the bottom stack: the five upgrade cards (the main thing), the nav, LAUNCH
	var stack := VBoxContainer.new()
	stack.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	stack.offset_left = 24
	stack.offset_right = -24
	stack.offset_bottom = -24
	stack.offset_top = -PANEL_H + 24
	stack.add_theme_constant_override("separation", 12)
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shop_root.add_child(stack)
	_stack = stack
	_cards_box = VBoxContainer.new()
	_cards_box.add_theme_constant_override("separation", 8)
	_cards_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_child(_cards_box)
	var nav := HBoxContainer.new()
	nav.add_theme_constant_override("separation", 12)
	stack.add_child(nav)
	for entry in [["GARAGE", 1], ["STYLE", 3], ["DAILY", 4]]:
		var nb := _button(entry[0], BODY, 84, _sb_card)
		nb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nb.set_meta("always", true)
		_attach_icon(nb, ["garage", "style", "daily"][_nav_buttons.size()], 44, C_ON_GO)
		nb.pressed.connect(show_tab.bind(entry[1]))
		nav.add_child(nb)
		_nav_buttons.append(nb)
	_launch_btn = _button("LAUNCH!", HERO, 170, _sb_accent, C_ON_GO)
	_launch_btn.add_theme_font_size_override("font_size", HERO)
	_launch_btn.set_meta("always", true)
	_attach_icon(_launch_btn, "rocket", 86, C_ON_GO)
	_launch_btn.pressed.connect(func():
		close_missions()
		launch_pressed.emit())
	stack.add_child(_launch_btn)
	_build_mission_bubble()

## Rusty's bubble (top right, with a badge) and the clipboard that drops down from it.
func _build_mission_bubble() -> void:
	_bubble = Button.new()
	_bubble.focus_mode = Control.FOCUS_NONE
	_bubble.add_theme_font_size_override("font_size", SMALL)
	var bs := _box(C_PAPER, Style.RUST_DARK, 70, 5)
	for sn in ["normal", "hover", "pressed", "focus", "disabled"]:
		_bubble.add_theme_stylebox_override(sn, bs)
	_bubble.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_bubble.offset_left = -190
	_bubble.offset_right = -36
	_bubble.offset_top = 132
	_bubble.offset_bottom = 286
	_bubble.pressed.connect(toggle_missions)
	_shop_root.add_child(_bubble)
	_rusty = Rusty.new()
	_rusty.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rusty.offset_left = 14
	_rusty.offset_right = -14
	_rusty.offset_top = 14
	_rusty.offset_bottom = -14
	_rusty.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bubble.add_child(_rusty)
	var badge := Panel.new()
	badge.add_theme_stylebox_override("panel", _box(Style.DANGER, Style.INK, 28, 3))
	badge.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	badge.offset_left = -50
	badge.offset_right = 12
	badge.offset_top = -12
	badge.offset_bottom = 50
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bubble.add_child(badge)
	_badge = _label(SMALL, C_ON_GO)
	_full(_badge)
	_badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge.add_child(_badge)
	# the clipboard
	_clip = PanelContainer.new()
	var paper := _box(C_PAPER, Style.RUST_DARK, Style.R_M, 5)
	paper.content_margin_top = 14
	paper.content_margin_bottom = 16
	_clip.add_theme_stylebox_override("panel", paper)
	_clip.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_clip.offset_left = -936
	_clip.offset_right = -36
	_clip.offset_top = 300
	_clip.offset_bottom = 300
	_clip.visible = false
	_shop_root.add_child(_clip)
	var cv := VBoxContainer.new()
	cv.add_theme_constant_override("separation", 8)
	_clip.add_child(cv)
	var ct := _label(SMALL, C_INK_SOFT, HORIZONTAL_ALIGNMENT_LEFT)
	ct.text = "RUSTY'S MISSIONS"
	cv.add_child(ct)
	_rusty_says = _label(SMALL, C_INK, HORIZONTAL_ALIGNMENT_LEFT)
	_rusty_says.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_rusty_says.custom_minimum_size = Vector2(0, 58)
	cv.add_child(_rusty_says)
	for i in Missions.SLOTS:
		var mv := VBoxContainer.new()
		mv.add_theme_constant_override("separation", 2)
		cv.add_child(mv)
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 12)
		mv.add_child(line)
		var mic := _icon("bounce", 44, C_INK)
		line.add_child(mic)
		_mission_icons.append(mic)
		var desc := _label(SMALL, C_INK, HORIZONTAL_ALIGNMENT_LEFT)
		desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		desc.clip_text = true
		line.add_child(desc)
		var tag := _label(SMALL, Style.RUST, HORIZONTAL_ALIGNMENT_RIGHT)
		tag.text = "NEW"
		tag.visible = false
		line.add_child(tag)
		var reward := _label(BODY, Style.ACCENT_DARK, HORIZONTAL_ALIGNMENT_RIGHT)
		reward.custom_minimum_size = Vector2(130, 0)
		line.add_child(reward)
		var barline := HBoxContainer.new()
		barline.add_theme_constant_override("separation", 12)
		mv.add_child(barline)
		var bar := Control.new()
		bar.custom_minimum_size = Vector2(0, 18)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var bg := ColorRect.new()
		bg.color = Style.PAPER.darkened(0.14)
		_full(bg)
		bar.add_child(bg)
		var fill := ColorRect.new()
		fill.color = C_ACCENT
		fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		fill.anchor_top = 0.0
		fill.anchor_bottom = 1.0
		fill.anchor_left = 0.0
		fill.anchor_right = 0.0
		fill.offset_left = 0
		fill.offset_right = 0
		fill.offset_top = 0
		fill.offset_bottom = 0
		bar.add_child(fill)
		barline.add_child(bar)
		var cnt := _label(SMALL, C_INK_SOFT, HORIZONTAL_ALIGNMENT_RIGHT)
		cnt.custom_minimum_size = Vector2(260, 0)
		barline.add_child(cnt)
		_mission_rows.append(desc)
		_mission_rewards.append(reward)
		_mission_counts.append(cnt)
		_mission_fills.append(fill)
		_mission_new.append(tag)

## Open / close the clipboard. It grows down from the bubble and fades in; `seconds` > 0 closes it again by itself.
func drop_missions(seconds: float = 0.0) -> void:
	_clip_target = 1.0
	_clip_hold = seconds
	if _sheet.visible:
		_sheet.visible = false

func close_missions() -> void:
	_clip_target = 0.0
	_clip_hold = 0.0

func toggle_missions() -> void:
	if _clip_target > 0.5:
		close_missions()
	else:
		drop_missions()

func missions_open() -> bool:
	return _clip_target > 0.5

func _animate_clip(delta: float) -> void:
	var step := delta * 7.0
	_clip_t = move_toward(_clip_t, _clip_target, step)
	if _clip_target > 0.5 and _clip_hold > 0.0:
		_clip_hold -= delta
		if _clip_hold <= 0.0:
			_clip_target = 0.0
	var on := _clip_t > 0.01
	if on != _clip.visible:
		_clip.visible = on
	if on:
		var e := _clip_t * _clip_t * (3.0 - 2.0 * _clip_t)
		_clip.pivot_offset = Vector2(_clip.size.x, 0.0)
		_clip.scale = Vector2(1.0, e)
		_clip.modulate.a = e

# ---- zone progress bar (one thin segment per zone) ----

func _make_bar(parent: Control, top: float) -> Dictionary:
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	row.offset_left = 28
	row.offset_right = -28
	row.offset_top = top
	row.offset_bottom = top + 14.0
	row.add_theme_constant_override("separation", 4)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(row)
	var fills: Array[ColorRect] = []
	for i in Zones.COUNT:
		var seg := Control.new()
		seg.custom_minimum_size = Vector2(0, 14)
		seg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		seg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var edge := ColorRect.new()
		edge.color = Style.INK
		_full(edge)
		seg.add_child(edge)
		var bg := ColorRect.new()
		bg.color = C_OFF
		_full(bg)
		bg.offset_left = 2
		bg.offset_top = 2
		bg.offset_right = -2
		bg.offset_bottom = -2
		seg.add_child(bg)
		var fill := ColorRect.new()
		fill.color = C_ACCENT
		fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		fill.anchor_top = 0.0
		fill.anchor_bottom = 1.0
		fill.anchor_left = 0.0
		fill.anchor_right = 0.0
		fill.offset_left = 2
		fill.offset_top = 2
		fill.offset_bottom = -2
		fill.offset_right = 0
		seg.add_child(fill)
		row.add_child(seg)
		fills.append(fill)
	return {"fills": fills, "row": row}

## Zones up to `reached` are filled, the next one fills with `progress` (0..1).
func _set_bar(bar: Dictionary, reached: int, progress: float) -> void:
	var fills: Array = bar["fills"]
	for i in Zones.COUNT:
		var f: ColorRect = fills[i]
		if i <= reached:
			f.anchor_right = 1.0
			f.offset_right = -2
			f.color = C_ACCENT
		elif i == reached + 1:
			f.anchor_right = clampf(progress, 0.0, 1.0)
			f.offset_right = -2 if progress >= 1.0 else 0
			f.color = C_ACCENT.darkened(0.35)
		else:
			f.anchor_right = 0.0
			f.offset_right = 0

func _zone_progress(distance: float, reached: int) -> float:
	var nxt := mini(reached + 1, Zones.COUNT - 1)
	var a := Tuning.zone_start(reached)
	var b := Tuning.zone_start(nxt)
	return clampf((distance - a) / maxf(b - a, 1.0), 0.0, 1.0)

# ---------------------------------------------------------------------------------------------
# SHEET: upgrades | garage (frames, launchers) | style | daily
# ---------------------------------------------------------------------------------------------

func _build_sheet() -> void:
	_sheet = PanelContainer.new()
	_sheet.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_sheet.offset_left = 24
	_sheet.offset_right = -24
	_sheet.offset_bottom = -24 - 170 - 4
	_sheet.offset_top = -24 - 170 - 4 - 810
	_sheet.add_theme_stylebox_override("panel", _box(Style.SURFACE_DARK, Style.LINE, Style.R_L, 3))
	_sheet.visible = false
	_shop_root.add_child(_sheet)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	_sheet.add_child(col)
	var head := HBoxContainer.new()
	col.add_child(head)
	_sheet_title = _label(BODY, C_TEXT, HORIZONTAL_ALIGNMENT_LEFT)
	_sheet_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sheet_title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_sheet_title)
	var close := _button("CLOSE", SMALL, 64, _sb_tab)
	close.custom_minimum_size = Vector2(180, 64)
	close.pressed.connect(close_sheet)
	head.add_child(close)
	_sub_tabs = HBoxContainer.new()
	_sub_tabs.add_theme_constant_override("separation", 10)
	col.add_child(_sub_tabs)
	for k in 2:
		var sb := _button(["FRAMES", "LAUNCHERS"][k], SMALL, 60, _sb_tab)
		sb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sb.pressed.connect(show_tab.bind(k + 1))
		_sub_tabs.add_child(sb)
		_sub_buttons.append(sb)
	var holder := Control.new()
	holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	holder.custom_minimum_size = Vector2(0, 530)
	holder.clip_contents = true
	col.add_child(holder)
	for ti in 5:
		var page := VBoxContainer.new()
		page.add_theme_constant_override("separation", 10)
		page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		page.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(page)
		_tab_pages.append(page)
	for u in Tuning.upgrades:
		var c := _make_card(u["id"])
		c["btn"].pressed.connect(func(): buy_pressed.emit(u["id"]))
		_row_name.append(c["name"])
		_row_effect.append(c["eff"])
		_row_btn.append(c["btn"])
		_row_ids.append(u["id"])
	for f in Tuning.frames:
		var r2 := _make_row(_tab_pages[1])
		r2["btn"].pressed.connect(func(): frame_pressed.emit(f["id"]))
		_frame_rows.append(r2)
	for l in Tuning.launchers:
		var r3 := _make_row(_tab_pages[2])
		r3["btn"].pressed.connect(func(): launcher_pressed.emit(l["id"]))
		_launcher_rows.append(r3)
	# STYLE: a category switch and five rows that show paints, hats or trails
	var cats := HBoxContainer.new()
	cats.add_theme_constant_override("separation", 10)
	_tab_pages[3].add_child(cats)
	for ci in 3:
		var cb := _button(Cosmetics.KIND_NAMES[Cosmetics.KINDS[ci]], SMALL, 60, _sb_tab)
		cb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cb.pressed.connect(set_style_cat.bind(ci))
		cats.add_child(cb)
		_style_cat_buttons.append(cb)
	for k in 5:
		var sr := _make_row(_tab_pages[3])
		sr["btn"].pressed.connect(_on_style_row.bind(k))
		_style_rows.append(sr)
	# DAILY: today's target and a button that starts today's seeded world
	var dp: VBoxContainer = _tab_pages[4]
	_daily_title = _label(BODY, C_TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	dp.add_child(_daily_title)
	_daily_info = _label(SMALL, C_MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	_daily_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_daily_info.custom_minimum_size = Vector2(0, 300)
	_daily_info.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	dp.add_child(_daily_info)
	_daily_btn = _button("START DAILY LAUNCH", BODY, 110, _sb_accent, C_ON_GO)
	_daily_btn.pressed.connect(func(): daily_pressed.emit())
	dp.add_child(_daily_btn)
	set_style_cat(0)
	show_tab(0)
	_sheet.visible = false

## An upgrade card on the main screen: icon, name + level pips, one line of effect, and the cost button.
func _make_card(id: String) -> Dictionary:
	var card := PanelContainer.new()
	var st := _box(C_CARD, Style.INK, Style.R_M, 3)
	st.content_margin_top = 5
	st.content_margin_bottom = 5
	card.add_theme_stylebox_override("panel", st)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 16)
	card.add_child(h)
	var icon := UpgradeIcon.new()
	icon.custom_minimum_size = Vector2(88, 88)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.set_kind(id)
	h.add_child(icon)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	v.add_theme_constant_override("separation", 2)
	h.add_child(v)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 14)
	v.add_child(top)
	var nm := _label(BODY, C_TEXT, HORIZONTAL_ALIGNMENT_LEFT)
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(nm)
	var pips := LevelPips.new()
	pips.custom_minimum_size = Vector2(230, 24)
	pips.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(pips)
	var ef := _label(SMALL, C_MUTED, HORIZONTAL_ALIGNMENT_LEFT)
	ef.clip_text = true
	v.add_child(ef)
	var b := _button("", BODY, 84, _sb_accent, C_ON_GO)
	b.custom_minimum_size = Vector2(250, 84)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_attach_icon(b, "scrap", 40, Style.ACCENT)
	h.add_child(b)
	_cards_box.add_child(card)
	_card_panels.append(card)
	_card_styles.append(st)
	_card_pips.append(pips)
	_card_icons.append(icon)
	return {"name": nm, "eff": ef, "btn": b}

## One sheet row: a name, a quiet one-line description, and a button on the right.
func _make_row(page: Control) -> Dictionary:
	var row := PanelContainer.new()
	var rs := _box(C_CARD, Style.INK, Style.R_M, 3)
	rs.content_margin_top = 6
	rs.content_margin_bottom = 6
	row.add_theme_stylebox_override("panel", rs)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	row.add_child(h)
	var ic := UpgradeIcon.new()
	ic.custom_minimum_size = Vector2(76, 76)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(ic)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	v.add_theme_constant_override("separation", 0)
	h.add_child(v)
	var nm := _label(BODY, C_TEXT, HORIZONTAL_ALIGNMENT_LEFT)
	nm.clip_text = true
	var ef := _label(SMALL, C_MUTED, HORIZONTAL_ALIGNMENT_LEFT)
	ef.clip_text = true
	v.add_child(nm)
	v.add_child(ef)
	var b := _button("", BODY, 78, _sb_accent, C_ON_GO)
	b.custom_minimum_size = Vector2(250, 78)
	_attach_icon(b, "scrap", 40, Style.ACCENT)
	h.add_child(b)
	page.add_child(row)
	return {"name": nm, "eff": ef, "btn": b, "icon": ic}

func show_tab(i: int) -> void:
	_tab = i
	if i == 0:   # the upgrades are on the main screen: 0 just closes the sheet
		_sheet.visible = false
		return
	close_missions()
	_sheet.visible = true
	for k in _tab_pages.size():
		_tab_pages[k].visible = k == i
	_sheet_title.text = ["", "GARAGE", "GARAGE", "STYLE", "DAILY LAUNCH"][i]
	_sub_tabs.visible = i == 1 or i == 2
	for k in _sub_buttons.size():
		var on := (k + 1) == i
		_style_button(_sub_buttons[k], _sb_accent if on else _sb_tab, C_ON_GO if on else C_TEXT)

func close_sheet() -> void:
	_sheet.visible = false

func set_style_cat(i: int) -> void:
	_style_cat = i
	for k in _style_cat_buttons.size():
		var on := k == i
		_style_button(_style_cat_buttons[k], _sb_accent if on else _sb_tab, C_ON_GO if on else C_TEXT)
	_refresh_style()

func _on_style_row(k: int) -> void:
	var kind: String = Cosmetics.KINDS[_style_cat]
	cosmetic_pressed.emit(kind, Cosmetics.list_of(kind)[k]["id"])

func _refresh_style() -> void:
	var kind: String = Cosmetics.KINDS[_style_cat]
	var list := Cosmetics.list_of(kind)
	for k in _style_rows.size():
		var r: Dictionary = _style_rows[k]
		var d: Dictionary = list[k]
		var on: bool = Save.equipped(kind) == d["id"]
		r["icon"].set_glyph(kind if kind == "paint" else ("hat_" + d["id"] if kind == "hat" and d["id"] != "none" else ("trail_" + d["id"] if kind == "trail" and d["id"] != "none" else "close")), Style.TEXT, d.get("color", Color(0, 0, 0, 0)) if kind == "paint" else Color(0, 0, 0, 0))
		r["name"].text = d["name"] + ("   ✓" if on else "")
		r["eff"].text = "Whiskers' hat" if kind == "hat" else ("Paint job" if kind == "paint" else "Trail")
		if on:
			_look(r["btn"], 2, "WORN")
		elif Save.owns_cosmetic(kind, d["id"]):
			_look(r["btn"], 0, "WEAR")
		else:
			_look(r["btn"], 0 if Save.scrap >= float(d["cost"]) else 1, Tuning.fmt(float(d["cost"])))

# ---------------------------------------------------------------------------------------------
# RESULTS: a card over the world
# ---------------------------------------------------------------------------------------------

func _build_results() -> void:
	_results = Control.new()
	_full(_results)
	_results.mouse_filter = Control.MOUSE_FILTER_STOP
	_results.visible = false
	_shop_root.add_child(_results)
	var dim := ColorRect.new()
	dim.color = Color(Style.SCRIM, 0.86)
	_full(dim)
	_results.add_child(dim)
	var card := PanelContainer.new()
	card.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	card.offset_left = -470
	card.offset_right = 470
	card.grow_vertical = Control.GROW_DIRECTION_BOTH
	card.add_theme_stylebox_override("panel", _box(C_PANEL, Style.LINE, Style.R_L, 3))
	_results.add_child(card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_child(v)
	_res_caption = _label(SMALL, C_MUTED)
	v.add_child(_res_caption)
	_res_dist = _label(HERO, C_TEXT)
	v.add_child(_res_dist)
	_res_badge = _label(BODY, C_ACCENT)
	v.add_child(_res_badge)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 14)
	v.add_child(gap)
	_res_scrap = _label(BODY, C_GOLD)
	v.add_child(_res_scrap)
	_res_detail = _label(SMALL, C_MUTED)
	_res_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_res_detail)
	var gap2 := Control.new()
	gap2.custom_minimum_size = Vector2(0, 14)
	v.add_child(gap2)
	_res_mcap = _label(SMALL, C_ACCENT)
	_res_mcap.text = "MISSION DONE"
	v.add_child(_res_mcap)
	_res_missions = _label(BODY, C_TEXT)
	_res_missions.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_res_missions)
	_res_new = _label(SMALL, C_MUTED)
	_res_new.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_res_new)
	var gap3 := Control.new()
	gap3.custom_minimum_size = Vector2(0, 14)
	v.add_child(gap3)
	var rr := HBoxContainer.new()
	rr.add_theme_constant_override("separation", 14)
	v.add_child(rr)
	_res_rusty_pic = Rusty.new()
	_res_rusty_pic.custom_minimum_size = Vector2(100, 100)
	_res_rusty_pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rr.add_child(_res_rusty_pic)
	_res_rusty = _label(SMALL, C_MUTED, HORIZONTAL_ALIGNMENT_LEFT)
	_res_rusty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_res_rusty.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_res_rusty.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rr.add_child(_res_rusty)
	_ad_double_btn = _button("DOUBLE SCRAP", SMALL, 64, _sb_done, C_MUTED)
	_ad_double_btn.set_meta("always", true)
	_attach_icon(_ad_double_btn, "ad", 30, Style.TEXT_SOFT)
	_ad_double_btn.pressed.connect(func(): ad_double_pressed.emit())
	v.add_child(_ad_double_btn)
	_res_continue = _button("CONTINUE", BODY, 140, _sb_accent, C_ON_GO)
	_res_continue.pressed.connect(func(): show_results(false))
	v.add_child(_res_continue)

func show_results(on: bool) -> void:
	var closing := _results.visible and not on
	_results.visible = on
	if closing:
		for m in Save.missions:
			if m.get("moved", false) or m.get("fresh", false):
				drop_missions(2.8)   # show what changed, then it tucks itself away
				break

func results_visible() -> bool:
	return _results.visible

## All the text on the results card, for tests and logs.
func result_text() -> String:
	return "\n".join([_res_caption.text, _res_dist.text, _res_badge.text, _res_scrap.text, _res_detail.text, (_res_mcap.text if _res_mcap.visible else ""), _res_missions.text, _res_new.text, _res_rusty.text])

func _fill_results(last: Dictionary) -> void:
	var daily: Dictionary = last.get("daily", {})
	_res_caption.text = "DAILY LAUNCH" if daily.size() > 0 else "LANDED"
	_res_dist.text = "%s m" % Tuning.fmt(last["distance"])
	_res_badge.text = "NEW BEST!" if last["new_best"] else ""
	_res_badge.visible = last["new_best"]
	_res_scrap.text = "+%s scrap" % Tuning.fmt(last["earned"])
	var parts: Array[String] = ["%s distance" % Tuning.fmt(last["dist_scrap"]), "%s from %d pickups" % [Tuning.fmt(last["picked"]), last["picked_count"]]]
	if last["zone_bonus"] > 0:
		parts.append("%s zone bonus" % Tuning.fmt(last["zone_bonus"]))
	if last["mission_bonus"] > 0:
		parts.append("%s missions" % Tuning.fmt(last["mission_bonus"]))
	var detail := "  ·  ".join(parts) + "\nFarthest zone: %s" % Tuning.zone_name(last["zone"])
	if daily.size() > 0:
		detail += "\nDAILY: %s / %s m%s" % [Tuning.fmt(daily["distance"]), Tuning.fmt(daily["target"]), "   BONUS +" + Tuning.fmt(daily["bonus"]) if daily["bonus"] > 0 else ""]
	_res_detail.text = detail
	var ml := ""
	for m in last["missions"]:
		ml += "%s✓ %s   +%s" % ["\n" if ml != "" else "", m["text"], Tuning.fmt(m["reward"])]
	_res_missions.text = ml
	_res_missions.visible = ml != ""
	_res_mcap.visible = ml != ""
	var nl := ""
	for t in last.get("new_missions", []):
		nl += ("\n" if nl != "" else "") + "New mission: " + String(t)
	_res_new.text = nl
	_res_new.visible = nl != ""
	_res_rusty.text = "Rusty: " + last["rusty"]

# ---------------------------------------------------------------------------------------------
# Refreshing every text from the save
# ---------------------------------------------------------------------------------------------

## Refresh the launch screen, the sheet and the results card from the save. `last` = the last flight's result
## or empty; `boost_ready` = a free boost from an ad is waiting.
func refresh_shop(last: Dictionary, boost_ready: bool = false) -> void:
	_shop_scrap.text = "SCRAP  %s" % Tuning.fmt(Save.scrap)
	_shop_best.text = "BEST  %s m" % Tuning.fmt(Save.best_distance)
	_zone_label.text = Tuning.zone_name(Save.zone_best).to_upper()
	var sk := Save.zone_best * 1000 + int(_zone_progress(Save.best_distance, Save.zone_best) * 50.0)
	if sk != _shop_bar_key:
		_shop_bar_key = sk
		_set_bar(_shop_bar, Save.zone_best, _zone_progress(Save.best_distance, Save.zone_best))
	if last.is_empty():
		_rusty_says.text = ("Rusty: " + Rusty.GREETING) if Save.runs == 0 else "Rusty: Back for more? Beat these and I'll pay up."
	else:
		_fill_results(last)
		_rusty_says.text = "Rusty: " + last["rusty"]
	for i in _row_ids.size():
		var id := _row_ids[i]
		var u := Tuning.upgrade_def(id)
		var lv := Save.level(id)
		var name_text: String = u["name"]
		var icon_kind := id
		if id == "ramp":   # the first card is the launch power of whatever you launch from
			name_text = Tuning.launcher_def(Save.launcher)["name"]
			icon_kind = Save.launcher if Save.launcher != "ramp" else "ramp"
		_row_name[i].text = name_text
		_row_effect[i].text = Tuning.effect_text(id, lv)
		_card_icons[i].set_kind(icon_kind)
		_card_pips[i].set_level(lv, int(u["max"]))
		var can := Save.can_buy(id)
		_card_styles[i].border_color = C_ACCENT if can else Style.INK
		_card_styles[i].bg_color = C_CARD.lerp(C_ACCENT, 0.10) if can else C_CARD
		_card_styles[i].set_border_width_all(4 if can else 3)
		if Save.is_maxed(id):
			_look(_row_btn[i], 2, "MAX")
		elif can:
			_look(_row_btn[i], 0, Tuning.fmt(Save.cost_of_next(id)))
		else:
			_look(_row_btn[i], 1, Tuning.fmt(Save.cost_of_next(id)))
	for i in Tuning.frames.size():
		var fd: Dictionary = Tuning.frames[i]
		var fr: Dictionary = _frame_rows[i]
		fr["icon"].set_kind(fd["id"])
		fr["name"].text = fd["name"] + ("   ✓" if Save.frame == fd["id"] else "")
		fr["eff"].text = fd["desc"]
		if Save.frame == fd["id"]:
			_look(fr["btn"], 2, "FLYING")
		elif Save.owns_frame(fd["id"]):
			_look(fr["btn"], 0, "FLY")
		else:
			_look(fr["btn"], 0 if Save.scrap >= Tuning.frame_cost(fd["id"]) else 1, Tuning.fmt(Tuning.frame_cost(fd["id"])))
	for i in Tuning.launchers.size():
		var ld: Dictionary = Tuning.launchers[i]
		var lr: Dictionary = _launcher_rows[i]
		lr["icon"].set_kind(ld["id"])
		lr["name"].text = ld["name"] + ("   ✓" if Save.launcher == ld["id"] else "")
		lr["eff"].text = "%s  (%d m/s)" % [ld["desc"], roundi(Tuning.launcher_speed(ld["id"], Save.level("ramp")))]
		if Save.launcher == ld["id"]:
			_look(lr["btn"], 2, "IN USE")
		elif Save.owns_launcher(ld["id"]):
			_look(lr["btn"], 0, "USE")
		elif i > 0 and not Save.owns_launcher(Tuning.launchers[i - 1]["id"]):
			_look(lr["btn"], 2, "LOCKED")
		else:
			_look(lr["btn"], 0 if Save.can_buy_launcher(ld["id"]) else 1, Tuning.fmt(Tuning.launcher_cost(ld["id"])))
	_refresh_style()
	_refresh_daily()
	_refresh_missions()
	_refresh_ads(last, boost_ready)

func _refresh_missions() -> void:
	_badge.text = str(Save.missions.size())
	for i in Missions.SLOTS:
		if i < Save.missions.size():
			var m: Dictionary = Save.missions[i]
			_mission_icons[i].set_glyph(m["type"], C_INK)
			_mission_rows[i].text = Missions.describe(m)
			_mission_rewards[i].text = "+%s" % Tuning.fmt(m["reward"])
			_mission_counts[i].text = "best %s" % Missions.progress_text(m, int(m.get("best", 0)))
			_mission_fills[i].anchor_right = Missions.fraction(m)
			var is_new: bool = m.get("fresh", false)
			_mission_new[i].text = "NEW" if is_new else "UP"
			_mission_new[i].visible = is_new or m.get("moved", false)
		else:
			_mission_rows[i].text = ""
			_mission_rewards[i].text = ""
			_mission_counts[i].text = ""
			_mission_fills[i].anchor_right = 0.0
			_mission_new[i].visible = false

func _refresh_daily() -> void:
	var key := Save.daily_key
	_daily_title.text = "%d-%02d-%02d" % [key / 10000, (key / 100) % 100, key % 100]
	var status := "Reached! Today's bonus is yours." if Save.daily_claimed else "Not reached yet. Fly %s m or more for the bonus." % Tuning.fmt(Save.daily_target)
	_daily_info.text = "Same world for everyone today.\nTarget %s m   ·   Bonus +%s scrap\nBest today %s m   ·   %d flight%s\n%s" % [Tuning.fmt(Save.daily_target), Tuning.fmt(Save.daily_reward()), Tuning.fmt(Save.daily_best), Save.daily_plays, "" if Save.daily_plays == 1 else "s", status]

## The ad chips: a free boost before a launch (launch screen), double scrap after a flight (results card).
func _refresh_ads(last: Dictionary, boost_ready: bool) -> void:
	var on := Tuning.ads_enabled
	var can_double: bool = on and not last.is_empty() and last["earned"] > 0 and not last.get("doubled", false)
	_ad_boost_btn.visible = on
	_ad_boost_btn.disabled = boost_ready
	_ad_boost_btn.text = "BOOST READY" if boost_ready else "FREE BOOST"
	_place_icon(_ad_boost_btn)
	_ad_double_btn.visible = on and not last.is_empty() and last["earned"] > 0
	_ad_double_btn.disabled = not can_double
	_ad_double_btn.text = "DOUBLE SCRAP" if (last.is_empty() or can_double or not on) else "SCRAP DOUBLED"
	_place_icon(_ad_double_btn)

# ---------------------------------------------------------------------------------------------
# Splash, fake ad, stamp
# ---------------------------------------------------------------------------------------------

func _build_splash() -> void:
	_splash = Control.new()
	_full(_splash)
	_splash.mouse_filter = Control.MOUSE_FILTER_STOP
	_splash.visible = false
	var bg := ColorRect.new()
	bg.color = Color(Style.SURFACE_DARK, 0.99)
	_full(bg)
	_splash.add_child(bg)
	var t := _label(HERO, C_TEXT)
	_full(t)
	t.text = "JUNKYARD\nLAUNCH"
	t.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_splash.add_child(t)
	var sm := _icon("propeller", 150, Style.TEXT_SOFT)
	sm.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	sm.offset_left = -75
	sm.offset_right = 75
	sm.offset_top = -420
	sm.offset_bottom = -270
	_splash.add_child(sm)
	var sn := _label(SMALL, Style.TEXT_QUIET)
	sn.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	sn.offset_left = -400
	sn.offset_right = 400
	sn.offset_top = 260
	sn.offset_bottom = 310
	sn.text = "CLEAR PROP GAMES"
	_splash.add_child(sn)
	add_child(_splash)

func _build_ad_screen() -> void:
	_ad_screen = Control.new()
	_full(_ad_screen)
	_ad_screen.mouse_filter = Control.MOUSE_FILTER_STOP
	_ad_screen.visible = false
	var bg := ColorRect.new()
	bg.color = Color(Style.SCRIM, 0.98)
	_full(bg)
	_ad_screen.add_child(bg)
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	box.offset_left = -480
	box.offset_right = 480
	box.offset_top = -260
	box.offset_bottom = 260
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ad_screen.add_child(box)
	_ad_title = _label(HERO, C_TEXT)
	_ad_title.text = "AD PLAYING"
	box.add_child(_ad_title)
	_ad_sub = _label(SMALL, C_MUTED)
	_ad_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_ad_sub)
	add_child(_ad_screen)

## The fake ad: a full-screen "AD PLAYING" for `seconds`, then `done` is called. A real ad SDK would be called
## here instead; nothing else in the game needs to change. `reward_text` ("" for an interstitial) says what it pays.
func show_ad(title: String, reward_text: String, seconds: float, done: Callable) -> void:
	if ad_active:
		return
	ad_active = true
	_ad_left = seconds
	_ad_callback = done
	_ad_title.text = title
	_ad_sub.text = ("Reward: %s\n\n(stub - a real ad would play here)" % reward_text) if reward_text != "" else "(stub - a real ad would play here)"
	_ad_screen.visible = true

func _end_ad() -> void:
	ad_active = false
	_ad_screen.visible = false
	var cb := _ad_callback
	_ad_callback = Callable()
	if cb.is_valid():
		cb.call()

func _build_stamp() -> void:
	_stamp = _label(SMALL, Color(1, 1, 1, 0.5), HORIZONTAL_ALIGNMENT_LEFT, 6)
	_stamp.visible = DebugFlags.stamp_visible()    # players never see the build stamp
	_stamp.text = "%s  %s" % [BuildInfo.COMMIT, BuildInfo.TIME]
	var flags := DebugFlags.summary()
	if flags != "":
		_stamp.text += "\n" + flags
	_stamp.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_stamp.offset_left = 14
	_stamp.offset_top = -44 if flags == "" else -80
	_stamp.add_theme_font_size_override("font_size", 22)
	add_child(_stamp)
	if DebugFlags.perf_enabled():
		_perf_label = _label(SMALL, Color(0.6, 1, 0.6, 0.9), HORIZONTAL_ALIGNMENT_LEFT, 6)
		_perf_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		_perf_label.offset_left = 14
		_perf_label.offset_top = 14
		add_child(_perf_label)

# ---------------------------------------------------------------------------------------------
# Modes, pre-warm
# ---------------------------------------------------------------------------------------------

func set_mode(m: int) -> void:
	mode = m
	_flight_root.visible = m == MODE_FLIGHT
	_shop_root.visible = m == MODE_SHOP
	_stall.visible = false
	_toast.visible = false
	_banner.visible = false
	for p in _pop_labels:
		p.visible = false
	_last_dist = -1
	_last_pips = -1
	_hint.text = "HOLD = nose up\nRELEASE = nose down"
	_aim_key = -1
	if m == MODE_FLIGHT:
		_results.visible = false
		_sheet.visible = false
		close_missions()
		_clip_t = 0.0
		_clip.visible = false

func show_splash(on: bool) -> void:
	_splash.visible = on

func _build_intro() -> void:
	_intro = Control.new()
	_full(_intro)
	_intro.mouse_filter = Control.MOUSE_FILTER_STOP
	_intro.visible = false
	var bg := ColorRect.new()
	bg.color = Style.SURFACE_DARK
	_full(bg)
	_intro.add_child(bg)
	# the studio logo: the propeller mark over the wordmark (the propeller spins up as it appears)
	_intro_logo = Control.new()
	_full(_intro_logo)
	_intro.add_child(_intro_logo)
	_intro_mark = _icon("propeller", 300, Style.TEXT)
	_intro_mark.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_intro_mark.offset_left = -150
	_intro_mark.offset_right = 150
	_intro_mark.offset_top = -470
	_intro_mark.offset_bottom = -170
	_intro_mark.pivot_offset = Vector2(150, 150)
	_intro_logo.add_child(_intro_mark)
	var nm := _label(HERO, C_TEXT)
	nm.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	nm.offset_left = -500
	nm.offset_right = 500
	nm.offset_top = -110
	nm.offset_bottom = 170
	nm.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	nm.text = STUDIO_NAME
	_intro_logo.add_child(nm)
	# the title
	_intro_title = Control.new()
	_full(_intro_title)
	_intro.add_child(_intro_title)
	var tl := _label(HERO, C_TEXT, HORIZONTAL_ALIGNMENT_CENTER, 0)
	tl.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	tl.offset_left = -520
	tl.offset_right = 520
	tl.offset_top = -200
	tl.offset_bottom = 120
	tl.text = "JUNKYARD\nLAUNCH"
	tl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_intro_title.add_child(tl)
	var tg := _label(SMALL, Style.TEXT_SOFT)
	tg.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	tg.offset_left = -500
	tg.offset_right = 500
	tg.offset_top = 150
	tg.offset_bottom = 200
	tg.text = "TAP TO SKIP"
	_intro_title.add_child(tg)
	add_child(_intro)

## Start the intro (Main calls this when the pre-warm is over). Does nothing when `intro_enabled` is off.
func play_intro() -> void:
	if not intro_enabled:
		return
	intro_active = true
	_intro_t = 0.0
	_intro.visible = true
	_intro.modulate.a = 1.0

func skip_intro() -> void:
	if intro_active and _intro_t < INTRO_TITLE:
		_intro_t = INTRO_TITLE

func _animate_intro(delta: float) -> void:
	_intro_t += delta
	var t := _intro_t
	# logo pops in (0..0.45), holds, hands over to the title (1.3..1.7), title holds, everything fades (2.5..3.0)
	var lp := Style.ease_out_back(t / 0.45)
	_intro_mark.rot = (1.0 - Style.ease_out_cubic(t / 1.1)) * TAU * 1.5
	_intro_mark.queue_redraw()
	_intro_logo.pivot_offset = _intro_logo.size * 0.5
	_intro_logo.scale = Vector2.ONE * lerpf(0.7, 1.0, lp)
	_intro_logo.modulate.a = clampf(t / 0.3, 0.0, 1.0) * (1.0 - clampf((t - INTRO_LOGO) / 0.4, 0.0, 1.0))
	var tp := clampf((t - INTRO_LOGO) / 0.4, 0.0, 1.0)
	_intro_title.pivot_offset = _intro_title.size * 0.5
	_intro_title.scale = Vector2.ONE * lerpf(0.85, 1.0, Style.ease_out_back(tp))
	_intro_title.modulate.a = tp
	_intro.modulate.a = 1.0 - Style.ease_in_cubic(clampf((t - INTRO_TITLE) / (INTRO_END - INTRO_TITLE), 0.0, 1.0))
	if t >= INTRO_END:
		intro_active = false
		_intro.visible = false

## Pre-warm: draw every part of the UI at once (under the splash) so fonts and styles are set up.
func prewarm_show(on: bool) -> void:
	_flight_root.visible = on
	_shop_root.visible = on
	_results.visible = on
	_sheet.visible = on
	_clip.visible = on
	if on:
		_clip.scale = Vector2.ONE
		_clip.modulate.a = 1.0
	_stall.visible = on
	_hint.visible = on
	_toast.visible = on
	_banner.visible = on
	_ad_screen.visible = on   # (drawn under the splash)
	for p in _pop_labels:
		p.visible = on
		p.text = "BOUNCE! +12 NEW BEST!"
	if on:
		_dist.text = "1234 m"
		_best.text = "BEST 1234 m"
		_toast.text = "Bounces 2/3"
		_banner.text = "NEW ZONE!\nCLOUD KINGDOM\n+1,900 scrap"
		_boost_pips.text = "●●●●○○"
		_res_caption.text = "LANDED"
		_res_dist.text = "1,234 m"
		_res_badge.text = "NEW BEST!"
		_res_scrap.text = "+999 scrap"
		_res_detail.text = "88 distance  ·  7 from 3 pickups  ·  4 zone bonus\nFarthest zone: Cheese Moon"
		_res_mcap.visible = true
		_res_missions.text = "✓ Collect 40 scrap in one flight   +45"
		_res_new.text = "New mission: Reach the River without boosting"
		_res_rusty.text = "Rusty: " + Rusty.GREETING
		_set_bar(_shop_bar, 3, 0.5)
		_mission_rows[0].text = "Reach the River without boosting"
		_mission_rewards[0].text = "+120"
		_mission_counts[0].text = "best Bounces 2/3"
		_mission_fills[0].anchor_right = 0.6
		_mission_new[0].visible = true
	else:
		_hint.visible = false

# ---------------------------------------------------------------------------------------------
# Per frame, ?perf
# ---------------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	_time += delta
	if intro_active:
		_animate_intro(delta)
	_animate_clip(delta)
	if ad_active:
		_ad_left -= delta
		if _ad_left <= 0.0:
			_end_ad()
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
	if _toast.visible and mode == MODE_FLIGHT:
		var ta := _time - _toast_born
		if ta > 2.0:
			_toast.visible = false
		else:
			var tm := _toast.modulate
			tm.a = clampf(2.0 - ta, 0.0, 1.0)
			_toast.modulate = tm
	if _banner.visible and mode == MODE_FLIGHT:
		var ba := _time - _banner_born
		if ba > 2.4:
			_banner.visible = false
		else:
			var bm := _banner.modulate
			bm.a = clampf(2.4 - ba, 0.0, 1.0)
			_banner.modulate = bm
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
