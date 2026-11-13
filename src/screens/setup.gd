extends Control
## Match setup sheet (RN Setup.tsx): mode art, desc, reward, versus row (change team / reroll
## opponent), cup bracket, difficulty / rule / turn time segments, loadout row, start →
## builds the Launch exactly like RN buildLaunch and calls Nav.go("match", launch).

var mode := {}
var lvl := 1
var rule := "g3"
var tt := 15
var opp := {}
var opp_img: TextureRect
var opp_name: Label

func setup(params: Dictionary) -> void:
	var m = params.get("mode", "quick")
	mode = m if m is Dictionary else Launch.mode(str(m))
	var p := UD.p()
	lvl = int(p.get("aiLvl", 1))
	rule = "g5" if int(p.get("limit", 3)) == 5 else "g3"
	tt = int(p.get("turnTime", 15))
	opp = params.get("opp", Launch.pick_opp())

func sheet_opts() -> Dictionary:
	return {"title": mode["name"], "en": mode["en"], "accent": mode["color"], "height": 0.9}

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var k: String = mode["k"]
	var col: Color = mode["color"]
	var p := UD.p()
	var me := UD.team_by_id(str(p.get("team", "club0")))
	var sl := Kit.scroll_list(20)
	var sc: ScrollContainer = sl[0]
	sc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(sc)
	var outer: VBoxContainer = sl[1]
	var v := Kit.vbox(20)
	outer.add_child(Kit.margin(v, NX.PAD, 0, NX.PAD, 120))
	# art
	var st := Kit.stage(400, 390)
	st.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	Kit.put(st, Kit.pulse(312, Color(col.r, col.g, col.b, 0.45)), 200, 195)
	var art := Kit.img(UD.ui(mode["img"]), Vector2(364, 390))
	Kit.put(st, art, 200, 195)
	Kit.bob(art, 13, 2.6)
	v.add_child(st)
	v.add_child(Kit.para(mode["desc"], 36, Color("#c8e2ff"), HORIZONTAL_ALIGNMENT_CENTER))
	var rw := PanelContainer.new()
	var rsb := NX.box(Color(col.r, col.g, col.b, 0.1), 42, 3, Color(col.r, col.g, col.b, 0.42))
	rsb.content_margin_left = 30; rsb.content_margin_right = 30; rsb.content_margin_top = 8; rsb.content_margin_bottom = 8
	rw.add_theme_stylebox_override("panel", rsb)
	rw.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var rh := Kit.hbox(14, true)
	rh.add_child(Kit.img(UD.ui2("c_coin"), 57))
	rh.add_child(Kit.label(mode["reward"], 31, Color("#ffe9a8")))
	rw.add_child(rh)
	v.add_child(rw)
	# versus
	var vs := PanelContainer.new()
	var vsb := NX.box(Color(0.04, 0.07, 0.19, 0.85), 52, 3, NX.LINE)
	vsb.content_margin_top = 36; vsb.content_margin_bottom = 36; vsb.content_margin_left = 20; vsb.content_margin_right = 20
	vs.add_theme_stylebox_override("panel", vsb)
	var vg := NxGrad.new([Color(0.31, 0.89, 1.0, 0.18), Color(0.03, 0.047, 0.133, 0.0), Color(1, 0.29, 0.35, 0.18)], 50, 0.0, 0.0)
	vs.add_child(vg)
	var vh := Kit.hbox(10)
	vh.alignment = BoxContainer.ALIGNMENT_CENTER
	vh.add_child(_side(UD.team_tex(me), me["name"], "تغییر تیم", NX.CYAN, _team))
	vh.add_child(Kit.img(UD.ui("vs"), Vector2(182, 156)))
	var local := k == "local"
	var right := _side(UD.team_tex(me) if local else UD.team_tex(opp), "بازیکن ۲" if local else opp["name"], " " if local else "حریف دیگر ↻", NX.RED, Callable() if local else _reroll)
	opp_img = right.get_meta("img")
	opp_name = right.get_meta("name")
	vh.add_child(right)
	vs.add_child(vh)
	v.add_child(vs)
	# cup bracket
	if k == "cup":
		var cup := PanelContainer.new()
		var csb := NX.box(Color(1, 0.82, 0.34, 0.07), 47, 3, Color(1, 0.82, 0.34, 0.25))
		csb.content_margin_top = 26; csb.content_margin_bottom = 26
		cup.add_theme_stylebox_override("panel", csb)
		var ch := Kit.hbox(0, true)
		var stages := ["یک‌چهارم", "نیمه‌نهایی", "فینال"]
		var diffs := ["آسان", "معمولی", "سخت"]
		for i in 3:
			var c := Kit.vbox(2)
			c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var im := Kit.img(UD.ui2("x_trophy" if i == 2 else "x_medal"), 120)
			im.modulate.a = 1.0 if i == 0 else 0.55
			c.add_child(Kit.center(im))
			var a := Kit.label(stages[i], 29, NX.GOLD if i == 0 else NX.DIM)
			a.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			c.add_child(a)
			var b := Kit.label(diffs[i], 26, NX.DIM2)
			b.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			c.add_child(b)
			ch.add_child(c)
		cup.add_child(ch)
		v.add_child(cup)
	if k == "quick":
		v.add_child(_row("سختی", Kit.tabs(["آسان", "معمولی", "سخت"], func(i): lvl = i, lvl)))
	if k == "quick" or k == "local":
		var rules := ["g3", "g5", "t3"]
		v.add_child(_row("قانون", Kit.tabs(["تا ۳ گل", "تا ۵ گل", "۳ دقیقه"], func(i): rule = rules[i], rules.find(rule), NX.VIOLET)))
	if k != "train":
		var tts := [0, 10, 15, 20]
		var ti := tts.find(tt)
		v.add_child(_row("زمان نوبت", Kit.tabs(["خاموش", "۱۰ث", "۱۵ث", "۲۰ث"], func(i): tt = tts[i], 2 if ti < 0 else ti, NX.GREEN)))
	# loadout
	var ld := PanelContainer.new()
	var lsb := NX.box(Color(0.04, 0.07, 0.19, 0.85), 42, 3, NX.LINE)
	lsb.content_margin_left = 26; lsb.content_margin_right = 26; lsb.content_margin_top = 22; lsb.content_margin_bottom = 22
	ld.add_theme_stylebox_override("panel", lsb)
	var lh := Kit.hbox(26, true)
	lh.add_child(Kit.img(UD.ball_tex(int(p.get("ball", 0))), 99))
	var lc := Kit.vbox(2)
	lc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lc.add_child(Kit.label("%s · %s" % [UD.ball_name(int(p.get("ball", 0))), UD.field(int(p.get("field", 0)))["name"]], 31, NX.TEXT, true))
	lc.add_child(Kit.label("ترکیب %s · تجهیزات" % UD.forms()[int(p.get("form", 0))][0], 29, NX.DIM))
	lh.add_child(lc)
	lh.add_child(Kit.img(UD.field_thumb(int(p.get("field", 0))), Vector2(78, 104), "cover"))
	ld.add_child(lh)
	Kit.tap(ld, _team, 0.97)
	v.add_child(ld)
	v.add_child(Kit.gap(16))
	v.add_child(Kit.button("شروع جام" if k == "cup" else "شروع بازی", _go, "gold" if k == "cup" else "primary"))

func _side(tex: Texture2D, nm: String, sub: String, col: Color, cb: Callable) -> Control:
	var c := Kit.vbox(4)
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var d := Panel.new()
	d.custom_minimum_size = Vector2(187, 187)
	d.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	d.add_theme_stylebox_override("panel", NX.box(Color("#050816"), 94, 8, NX.hdr(col, 1.3), 30, Color(col.r, col.g, col.b, 0.7)))
	var im := Kit.img(tex, 166)
	im.position = Vector2(10, 10)
	d.add_child(im)
	c.add_child(d)
	var n := Kit.label(nm, 31, NX.TEXT, true)
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	n.clip_text = true
	n.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	n.custom_minimum_size.x = 300
	c.add_child(n)
	var s := Kit.label(sub, 26, col)
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	c.add_child(s)
	c.set_meta("img", im)
	c.set_meta("name", n)
	if cb.is_valid():
		Kit.tap(c, cb, 0.94)
	return c

func _row(label: String, w: Control) -> Control:
	var v := Kit.vbox(12)
	v.add_child(Kit.gap(10))
	v.add_child(Kit.label(label, 34, NX.DIM, true))
	v.add_child(w)
	return v

func _reroll() -> void:
	opp = Launch.pick_opp()
	opp_img.texture = UD.team_tex(opp)
	opp_name.text = opp["name"]
	var d := opp_img.get_parent() as Control
	d.pivot_offset = d.size * 0.5
	var tw := d.create_tween()
	tw.tween_property(d, "rotation", TAU, 0.45).from(0.0).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _team() -> void:
	Nav.close_sheet()
	Nav.go("team")

func _go() -> void:
	UD.set_p({"aiLvl": lvl, "limit": 5 if rule == "g5" else 3, "turnTime": tt})
	var launch := Launch.build(mode["k"], UD.p(), {"lvl": lvl, "rule": rule, "tt": tt, "opp": opp, "stage": 0})
	Nav.close_sheet()
	Nav.go("match", launch)
