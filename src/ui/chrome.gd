class_name NxChrome
extends Control
## App chrome (RN Chrome.tsx): top HUD (profile/level/XP, gems, coins, daily gift, settings)
## + floating animated bottom tab bar (Home, Team, Play, Shop, Profile).

const TABS := [
	["home", "خانه", "ic_home"],
	["team", "تیم", "shield_star"],
	["play", "بازی", "ic_play"],
	["shop", "فروشگاه", "ic_shop"],
	["profile", "پروفایل", "ic_trophy"],
]

var hud: Control
var hud_bg: TextureRect
var tabbar: Control
var bar_bg: NxGrad
var hl: NxGrad
var hl_dot: ColorRect
var tab_btns: Array[Control] = []
var tab_icons: Array[TextureRect] = []
var tab_labels: Array[Label] = []
var tab_badges: Array[Control] = []
var cur := 0
var _hl_x := 0.0
var _hl_tw: Tween

# hud widgets
var name_l: Label
var xp_bar: NxBar
var lvl_l: Label
var av_holder: Control
var gem_l: Label
var coin_l: Label
var gift: Control
var gift_art: TextureRect
var gift_badge: Control
var _gift_tw: Tween
var _last_sig := ""

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_hud()
	_build_tabbar()
	resized.connect(_layout)
	var st := UD.node("Store")
	if st and st.has_signal("changed"):
		st.connect("changed", refresh)
	var sp := UD.node("Supa")
	if sp and sp.has_signal("profile_changed"):
		sp.connect("profile_changed", func(_p): refresh())
	var tm := Timer.new()
	tm.wait_time = 20.0
	tm.autostart = true
	tm.timeout.connect(refresh)
	add_child(tm)
	_layout()
	refresh()

# ------------------------------------------------------------------ HUD
func _build_hud() -> void:
	hud = Control.new()
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hud)
	hud_bg = TextureRect.new()
	hud_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	hud_bg.stretch_mode = TextureRect.STRETCH_SCALE
	var g := Gradient.new()
	g.colors = PackedColorArray([Color(0.008, 0.016, 0.055, 0.92), Color(0.008, 0.016, 0.055, 0.55), Color(0.008, 0.016, 0.055, 0)])
	g.offsets = PackedFloat32Array([0, 0.55, 1])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_to = Vector2(0, 1)
	gt.width = 4
	gt.height = 128
	hud_bg.texture = gt
	hud.add_child(hud_bg)

	var row := HBoxContainer.new()
	row.name = "Row"
	row.add_theme_constant_override("separation", 8)
	row.alignment = BoxContainer.ALIGNMENT_BEGIN
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(row)

	# profile pill
	var me := PanelContainer.new()
	var sb := NX.box(Color(0.03, 0.055, 0.157, 0.82), 68, 3, Color(0.36, 0.88, 1.0, 0.35))
	sb.content_margin_left = 30; sb.content_margin_right = 8; sb.content_margin_top = 8; sb.content_margin_bottom = 8
	me.add_theme_stylebox_override("panel", sb)
	var mh := Kit.hbox(18)
	me.add_child(mh)
	var col := Kit.vbox(8)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	name_l = Kit.label("Pilot", 34, NX.TEXT, true)
	name_l.custom_minimum_size.x = 210  # room for a 10-char pilot name at the larger text size
	name_l.clip_text = true
	name_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	col.add_child(name_l)
	xp_bar = NxBar.new(0.0, NX.CYAN, NX.CYAN, 13)
	xp_bar.custom_minimum_size = Vector2(210, 13)
	col.add_child(xp_bar)
	mh.add_child(col)
	var avs := Control.new()
	avs.custom_minimum_size = Vector2(104, 104)
	avs.mouse_filter = Control.MOUSE_FILTER_IGNORE
	av_holder = Control.new()
	av_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	avs.add_child(av_holder)
	var lv := PanelContainer.new()
	var lsb := NX.box(NX.GOLD, 22)
	lsb.content_margin_left = 10; lsb.content_margin_right = 10
	lv.add_theme_stylebox_override("panel", lsb)
	lv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lvl_l = Kit.title("1", 24, NX.DARK_TXT)
	lvl_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lv.add_child(lvl_l)
	lv.position = Vector2(26, 76)
	lv.custom_minimum_size = Vector2(52, 40)
	avs.add_child(lv)
	mh.add_child(avs)
	me.mouse_filter = Control.MOUSE_FILTER_PASS
	Kit.tap(me, func(): Nav.go("profile"), 0.95)
	row.add_child(me)

	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(sp)

	var gp := _pill(UD.menu("g_gem"), false)
	gem_l = gp.get_meta("label")
	row.add_child(gp)
	var cp := _pill(UD.menu("g_coin"), true)
	coin_l = cp.get_meta("label")
	coin_l.add_theme_color_override("font_color", NX.GOLD)
	row.add_child(cp)

	gift = Control.new()
	gift.custom_minimum_size = Vector2(94, 104)
	gift_art = Kit.img(UD.menu("ic_gift"), 88)
	gift_art.position = Vector2(3, 8)
	gift_art.pivot_offset = Vector2(44, 44)
	gift.add_child(gift_art)
	gift_badge = Kit.badge_dot(true)
	gift_badge.position = Vector2(2, 4)
	gift.add_child(gift_badge)
	Kit.tap(gift, func(): Nav.go("daily"), 0.88)
	row.add_child(gift)
	row.add_child(Kit.icon_button(UD.menu("ic_settings"), func(): Nav.go("settings"), 86.0))

func _pill(icon: Texture2D, plus: bool) -> Control:
	var p := PanelContainer.new()
	var sb := NX.box(Color(0.024, 0.04, 0.118, 0.8), 42, 3, NX.LINE)
	sb.content_margin_left = 8; sb.content_margin_right = 8 if plus else 22; sb.content_margin_top = 4; sb.content_margin_bottom = 4
	p.add_theme_stylebox_override("panel", sb)
	p.custom_minimum_size.y = 84
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var h := Kit.hbox(10)
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	p.add_child(h)
	h.add_child(Kit.img(icon, 58))
	var l := Kit.title("0", 31, NX.TEXT, "head")
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(l)
	if plus:
		var pl := PanelContainer.new()
		pl.add_theme_stylebox_override("panel", NX.box(NX.hdr(NX.GREEN, 1.1), 27))
		pl.custom_minimum_size = Vector2(48, 48)
		pl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		pl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var t := Kit.title("+", 32, NX.DARK_TXT)
		t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		t.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		pl.add_child(t)
		h.add_child(pl)
	p.set_meta("label", l)
	Kit.tap(p, func(): Nav.go("shop"), 0.92)
	return p

# ------------------------------------------------------------------ tab bar
func _build_tabbar() -> void:
	tabbar = Control.new()
	tabbar.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(tabbar)
	bar_bg = NxGrad.new([Color(0.086, 0.133, 0.337, 0.97), Color(0.06, 0.09, 0.24, 0.97), Color(0.03, 0.047, 0.141, 0.98)], 68.0, 1.57, 0.06)
	bar_bg.set_border(3.0, Color(0.36, 0.88, 1.0, 0.3))
	bar_bg.set_glow(Color(0.3, 0.42, 1.0, 0.45), 40.0, 44.0)
	tabbar.add_child(bar_bg)
	var line := ColorRect.new()
	line.name = "Line"
	line.color = Color(0.63 * 1.4, 0.9 * 1.4, 1.4, 0.45)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tabbar.add_child(line)
	hl = NxGrad.new([Color(0.31, 0.89, 1.0, 0.30), Color(0.4, 0.5, 1.0, 0.18), Color(0.43, 0.36, 1.0, 0.10)], 52.0, 1.57, 0.1)
	hl.set_border(3.0, Color(0.31, 0.89, 1.0, 0.5))
	tabbar.add_child(hl)
	hl_dot = ColorRect.new()
	hl_dot.color = NX.hdr(NX.CYAN, 2.2)
	hl_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hl_dot.custom_minimum_size = Vector2(48, 8)
	hl.add_child(hl_dot)
	for i in TABS.size():
		var b := Control.new()
		b.mouse_filter = Control.MOUSE_FILTER_STOP
		var ic := Kit.img(UD.menu(TABS[i][2]), 80)
		ic.pivot_offset = Vector2(40, 40)
		b.add_child(ic)
		var l := Kit.label(TABS[i][1], 26, NX.DIM, true)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.add_child(l)
		var bd := Kit.badge_dot(true)
		bd.visible = false
		b.add_child(bd)
		var idx := i
		b.gui_input.connect(func(ev): _tab_input(ev, idx))
		tabbar.add_child(b)
		tab_btns.append(b)
		tab_icons.append(ic)
		tab_labels.append(l)
		tab_badges.append(bd)

func _tab_input(ev: InputEvent, i: int) -> void:
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and not ev.pressed:
		if i != cur:
			UD.sfx("ui")
			UD.haptic("light")
		Nav.go(TABS[i][0])

func _bar_w() -> float:
	return minf(size.x - 52, 1352)

func _cell_x(i: int) -> float:
	# RTL: home is the right-most cell
	var cw := _bar_w() / TABS.size()
	return _bar_w() - cw * (i + 1)

func _layout() -> void:
	var W := size.x
	# hud
	var top := NX.safe_top
	hud.position = Vector2.ZERO
	hud.size = Vector2(W, top + NX.HUD_H + 40)
	hud_bg.size = hud.size
	var row := hud.get_node("Row") as Control
	row.position = Vector2(26 + NX.safe_left, top + 14)
	row.size = Vector2(W - 52 - NX.safe_left - NX.safe_right, 120)
	# tab bar
	var bw := _bar_w()
	var bh := NX.TAB_H - 20
	var bottom := maxf(26, NX.safe_bottom)
	tabbar.size = Vector2(bw, bh)
	tabbar.position = Vector2((W - bw) * 0.5, size.y - bottom - bh)
	bar_bg.position = Vector2(-bar_bg.pad, -bar_bg.pad)
	bar_bg.size = tabbar.size + Vector2(bar_bg.pad * 2, bar_bg.pad * 2)
	var line := tabbar.get_node("Line") as ColorRect
	line.position = Vector2(104, 1)
	line.size = Vector2(bw - 208, 3)
	var cw := bw / TABS.size()
	for i in tab_btns.size():
		var b := tab_btns[i]
		b.position = Vector2(_cell_x(i), 0)
		b.size = Vector2(cw, bh)
		tab_icons[i].position = Vector2(cw * 0.5 - 40, bh * 0.5 - 62)
		tab_labels[i].position = Vector2(0, bh * 0.5 + 18)
		tab_labels[i].size = Vector2(cw, 40)
		tab_badges[i].position = Vector2(cw * 0.66, 18)
	hl.size = Vector2(cw - 30, bh - 26)
	hl_dot.position = Vector2(hl.size.x * 0.5 - 24, hl.size.y - 12)
	hl_dot.size = Vector2(48, 8)
	if _hl_tw == null or not _hl_tw.is_running():
		_hl_x = _cell_x(cur) + 15
	hl.position = Vector2(_hl_x, 13)
	_style_tabs(false)

## highlight a tab by screen name ("" = none, e.g. online screens)
func set_tab(name: String) -> void:
	var idx := -1
	for i in TABS.size():
		if TABS[i][0] == name:
			idx = i
	if idx < 0:
		return
	if idx == cur and _hl_x != 0.0:
		return
	cur = idx
	if _hl_tw:
		_hl_tw.kill()
	_hl_tw = create_tween()
	_hl_tw.tween_method(func(v): _hl_x = v; hl.position.x = v, hl.position.x, _cell_x(cur) + 15, 0.5).set_trans(Tween.TRANS_SPRING).set_ease(Tween.EASE_OUT)
	_style_tabs(true)

func _style_tabs(animate: bool) -> void:
	for i in tab_btns.size():
		var on := i == cur
		tab_labels[i].add_theme_color_override("font_color", NX.hdr(NX.CYAN, 1.3) if on else NX.DIM)
		var ic := tab_icons[i]
		var target_y := (tabbar.size.y * 0.5 - 62) - (6 if on else 0)
		var mod := Color(1.15, 1.15, 1.2, 1) if on else Color(1, 1, 1, 0.62)
		if animate:
			var tw := ic.create_tween().set_parallel(true)
			tw.tween_property(ic, "position:y", target_y, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tw.tween_property(ic, "modulate", mod, 0.25)
			if on:
				var pop := ic.create_tween()
				pop.tween_property(ic, "scale", Vector2(1.18, 1.18), 0.1)
				pop.tween_property(ic, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
		else:
			ic.position.y = target_y
			ic.modulate = mod
		tab_labels[i].modulate.a = 1.0 if on else 0.6

func show_hud(v: bool) -> void:
	hud.visible = v

func show_tabs(v: bool) -> void:
	tabbar.visible = v

# ------------------------------------------------------------------ data refresh
func refresh() -> void:
	var p := UD.p()
	var op := UD.online_profile()
	var xp := int(op.get("xp", p.get("xp", 0))) if not op.is_empty() else int(p.get("xp", 0))
	var lv := UD.level(xp)
	var nm := str(op.get("username", "")) if not op.is_empty() else ""
	if nm == "":
		nm = str(p.get("name", "Pilot"))
	var gems := int(op.get("gems", p.get("gems", 0))) if not op.is_empty() else int(p.get("gems", 0))
	var av_key = op.get("avatar_url", null) if not op.is_empty() else null
	if av_key == null or str(av_key) == "":
		av_key = op.get("equipped_disc", null) if not op.is_empty() else null
	if av_key == null or str(av_key) == "":
		av_key = str(p.get("team", "club0"))
	var sig := "%s|%s" % [av_key, nm]
	name_l.text = nm
	name_l.text_direction = Control.TEXT_DIRECTION_RTL if NX.is_fa(nm) else Control.TEXT_DIRECTION_AUTO
	name_l.add_theme_font_override("font", NX.font("faB" if NX.is_fa(nm) else "bold"))
	lvl_l.text = str(lv["level"])
	xp_bar.set_frac(maxf(0.04, float(lv["cur"]) / maxf(1.0, float(lv["need"]))))
	_count(gem_l, gems)
	_count(coin_l, int(p.get("coins", 0)))
	if sig != _last_sig:
		_last_sig = sig
		for c in av_holder.get_children():
			c.queue_free()
		av_holder.add_child(Kit.avatar(av_key, 110))
	var dr := UD.daily_ready()
	gift_badge.visible = dr
	if dr and _gift_tw == null:
		_gift_tw = gift_art.create_tween().set_loops()
		_gift_tw.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_gift_tw.tween_property(gift_art, "rotation", deg_to_rad(8), 0.9)
		_gift_tw.parallel().tween_property(gift_art, "scale", Vector2(1.08, 1.08), 0.9)
		_gift_tw.tween_property(gift_art, "rotation", deg_to_rad(-8), 0.9)
		_gift_tw.parallel().tween_property(gift_art, "scale", Vector2.ONE, 0.9)
	elif not dr and _gift_tw:
		_gift_tw.kill()
		_gift_tw = null
		gift_art.rotation = 0
		gift_art.scale = Vector2.ONE
	tab_badges[3].visible = UD.chest_ready()

## animated count-up for currency changes
func _count(l: Label, v: int) -> void:
	var old := int(l.get_meta("v", -1))
	l.set_meta("v", v)
	if old < 0 or old == v or not is_inside_tree():
		l.text = NX.en_num(v)
		return
	var tw := l.create_tween()
	tw.tween_method(func(x: float): l.text = NX.en_num(int(x)), float(old), float(v), 0.6).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	var pop := l.create_tween()
	l.pivot_offset = l.size * 0.5
	pop.tween_property(l, "scale", Vector2(1.2, 1.2), 0.1)
	pop.tween_property(l, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
