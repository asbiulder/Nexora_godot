extends NxScreen
## Home hub (RN v4 Home): hero pedestal + hovering disc + mascot, quick play, league strip,
## quick actions, game-mode rail, command-deck plates, daily reward, loadout, missions.

var hero: Control
var _hero_y := 0.0
var _say: Control = null
var _say_tw: Tween = null

func build() -> void:
	# menu track on Home (Sfx picks menu_music.mp3, else music.mp3); Settings' music toggle wins
	if bool(UD.pv("music", true)):
		UD.menu_music(true)
	make_scroll(20)
	_fill()
	end_body()
	scroll.get_v_scroll_bar().value_changed.connect(_on_scroll)

var _ch_card: Control

func on_store_changed() -> void:
	# keep the online challenges card alive across rebuilds (it owns a realtime channel)
	if _ch_card and is_instance_valid(_ch_card) and _ch_card.get_parent():
		_ch_card.get_parent().remove_child(_ch_card)
	rebuild(_fill)

func _exit_tree() -> void:
	if _ch_card and is_instance_valid(_ch_card) and not _ch_card.is_inside_tree():
		_ch_card.queue_free()

## RN HomeChallenges (OUI: ChallengesScreen.make_home_card()) when available
func _challenges_card() -> Control:
	if _ch_card and is_instance_valid(_ch_card):
		return _ch_card
	var path := "res://src/online/challenges.gd"
	if not ResourceLoader.exists(path):
		return null
	var sc = load(path)
	if sc is GDScript and (sc as GDScript).can_instantiate():
		var c = sc.call("make_home_card")
		if c is Control:
			_ch_card = c
	return _ch_card

func _on_scroll(v: float) -> void:
	# parallax: hero drifts slower than content and fades
	if hero:
		hero.position.y = v * 0.35
		hero.modulate.a = clampf(1.0 - v / 700.0, 0.35, 1.0)
	if Nav.main and Nav.main.backdrop:
		Nav.main.backdrop.set_drift(v)

func _fill() -> void:
	var p := UD.p()
	var me := UD.team_by_id(str(p.get("team", "club0")))
	var W := 1080.0
	# ---------------- hero
	var hw := 560.0
	var hh := hw + 400.0
	var wrap := Kit.stage(W, hh)
	wrap.clip_contents = false
	hero = Control.new()
	hero.mouse_filter = Control.MOUSE_FILTER_PASS
	hero.size = Vector2(W, hh)
	wrap.add_child(hero)
	var logo := Kit.img(UD.menu("logo"), Vector2(600, 290))
	Kit.put(hero, logo, W * 0.5, 145)
	var pulse := Kit.pulse(hw * 0.9, Color(0.31, 0.55, 1.0, 0.5))
	Kit.put(hero, pulse, W * 0.5, hh - 360)
	var ped := Kit.img(UD.menu("pedestal"), Vector2(hw * 1.5, hw * 1.5 * 0.42))
	Kit.put(hero, ped, W * 0.5, hh - hw * 0.315)
	# mascot drifting on the left
	var mtex := UD.ui2("mascot")
	if mtex:  # the sheet crop carries a sliver of the next sprite on its right edge
		var at := AtlasTexture.new()
		at.atlas = mtex
		at.region = Rect2(0, 0, 356, 520)
		mtex = at
	var mas := Kit.img(mtex, Vector2(240, 350))
	Kit.put(hero, mas, 150, hh - 300)
	Kit.bob(mas, 14, 2.4, 0.4)
	Kit.tap(mas, func(): UD.sfx("ui"); _mascot_say("سلام کاپیتان! آماده‌ی بازی هستی؟"), 0.9)
	# hovering disc
	var dsz := hw * 0.78
	var disc := Panel.new()
	disc.mouse_filter = Control.MOUSE_FILTER_PASS
	disc.custom_minimum_size = Vector2(dsz, dsz)
	var dsb := NX.box(Color("#05040E"), int(dsz / 2), 8, NX.hdr(Color(0.47, 0.86, 1.0, 0.95), 1.3), 30, Color(0.31, 0.89, 1.0, 0.6))
	disc.add_theme_stylebox_override("panel", dsb)
	var dimg := Kit.img(UD.team_tex(me), dsz - 26)
	dimg.position = Vector2(13, 13)
	disc.add_child(dimg)
	Kit.put(hero, disc, W * 0.5, 300 + dsz * 0.5)
	Kit.bob(disc, 14, 2.8)
	var tilt := disc.create_tween().set_loops()
	tilt.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tilt.tween_property(disc, "scale:x", 0.93, 2.8)
	tilt.tween_property(disc, "scale:x", 1.0, 2.8)
	Kit.tap(disc, func(): Nav.go("team"), 0.93)
	body.add_child(wrap)

	var link := Kit.label("%s  ·  تغییر تیم ›" % me["name"], 31, NX.DIM, true)
	link.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	link.custom_minimum_size.y = 100
	link.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	Kit.tap(link, func(): Nav.go("team"))
	body.add_child(link)

	# ---------------- play button (shine sweep)
	var play := NxButton.new("شروع بازی", func(): Nav.go("setup", {"mode": "quick"}), "primary", false, UD.menu("ic_play"), "QUICK MATCH")
	play.custom_minimum_size.y = 176
	play.lbl.add_theme_font_size_override("font_size", 60)
	var sh := play.create_tween().set_loops()
	sh.tween_method(func(v): play.bg.shine = v, 0.0, 1.0, 1.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	sh.tween_interval(0.9)
	body.add_child(ent(padx(play), 0))

	# ---------------- league strip
	body.add_child(ent(padx(_league_strip(p)), 1))

	# ---------------- quick actions (max 4)
	var qrow := Kit.hbox(18, true)
	var quick := [
		[UD.menu("ic_friends"), "آنلاین", func(): Nav.online("hub"), false],
		[UD.menu("ic_trophy"), "جام نکسورا", func(): Nav.go("setup", {"mode": "cup"}), false],
		[UD.menu("shield_star"), "تیم من", func(): Nav.go("team"), false],
		[UD.menu("ic_gift"), "صندوقچه", func(): Nav.open_chest(false), UD.chest_ready()],
	]
	for q in quick:
		var c := PanelContainer.new()
		c.add_theme_stylebox_override("panel", NX.box(Color(0.04, 0.055, 0.157, 0.82), 47, 3, NX.LINE))
		c.custom_minimum_size = Vector2(0, 218)
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var v := Kit.vbox(8)
		v.alignment = BoxContainer.ALIGNMENT_CENTER
		v.add_child(Kit.center(Kit.img(q[0], 104)))
		var l := Kit.label(q[1], 29, NX.TEXT, true)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(l)
		c.add_child(v)
		if q[3]:
			var b := Kit.badge_dot(true)
			b.position = Vector2(20, 14)
			c.add_child(b)
			b.top_level = false
		Kit.tap(c, q[2], 0.94)
		qrow.add_child(c)
	body.add_child(ent(Kit.margin(qrow, 30, 10, 30, 0), 2))

	# ---------------- game mode rail
	body.add_child(Kit.section("حالت‌های بازی", "GAME MODES", NX.VIOLET, "همه ›", func(): Nav.go("play")))
	var hs := Kit.hscroll(24)
	var rail: HBoxContainer = hs[1]
	(hs[0] as ScrollContainer).custom_minimum_size.y = 420
	rail.add_child(Kit.gap(0, 20))
	for m in Launch.modes():
		rail.add_child(_mode_card(m))
	rail.add_child(Kit.gap(0, 20))
	body.add_child(ent(hs[0], 3))

	# ---------------- command deck plates
	body.add_child(Kit.section("مرکز فرمان", "COMMAND DECK", NX.CYAN))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 22)
	grid.add_theme_constant_override("v_separation", 22)
	grid.layout_direction = Control.LAYOUT_DIRECTION_RTL
	var plates := [
		["portal_globe", "آنلاین", "۱ به ۱، ۲ به ۲، ۳ به ۳", NX.CYAN, func(): Nav.online("hub")],
		["portal_friends", "اجتماعی", "دوستان، کلاب، گفتگو", NX.PINK, func(): Nav.go("social")],
		["portal_shop", "فروشگاه", "صندوقچه و پیشنهاد روز", NX.GOLD, func(): Nav.go("shop")],
		["portal_profile", "رده‌بندی", "بهترین‌های نکسورا", NX.VIOLET, func(): Nav.online("ranks")],
	]
	for pl in plates:
		grid.add_child(_plate(pl))
	body.add_child(ent(padx(grid), 4))

	# ---------------- daily reward
	body.add_child(Kit.section("جایزه‌ی روزانه", "DAILY REWARD", NX.GOLD))
	var dr := UD.daily_ready()
	var dp := Kit.glass(NX.GOLD if dr else Color.TRANSPARENT, dr)
	dp.set_pad(32, 26)
	var dh := Kit.hbox(26, true)
	dh.add_child(Kit.img(UD.menu("ic_gift"), 104))
	var dc := Kit.vbox(2)
	dc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dc.alignment = BoxContainer.ALIGNMENT_CENTER
	dc.add_child(Kit.label("جایزه‌ی امروز آماده‌ست!" if dr else "روز %s از ۷" % NX.fa(int(p.get("streak", 0))), 36, NX.TEXT, true))
	dc.add_child(Kit.label("سکه و الماس رایگان؛ هر روز بزرگ‌تر" if dr else "فردا دوباره سر بزن", 29, NX.DIM))
	dh.add_child(dc)
	var cta := Kit.chip("دریافت" if dr else "جزئیات", NX.GOLD if dr else NX.DIM, dr)
	cta.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dh.add_child(cta)
	dp.add_child(dh)
	Kit.tap(dp, func(): Nav.go("daily"), 0.98)
	body.add_child(ent(padx(dp), 5))

	# ---------------- loadout
	body.add_child(Kit.section("تجهیزات", "LOADOUT", NX.GREEN, "تغییر ›", func(): Nav.go("team")))
	body.add_child(ent(padx(_loadout(p, me)), 6))

	# ---------------- missions
	body.add_child(Kit.section("مأموریت‌ها", "MISSIONS", NX.GREEN, "چالش‌ها ›", func(): Nav.online("challenges")))
	var mv := Kit.vbox(18)
	var shown := 0
	for a in UD.ACHS:
		if a["id"] in (p.get("claimedAch", []) as Array):
			continue
		mv.add_child(_mission(a, p))
		shown += 1
		if shown >= 3:
			break
	if shown == 0:
		mv.add_child(Kit.para("همه‌ی مأموریت‌ها رو انجام دادی، اسطوره!", 31, NX.DIM, HORIZONTAL_ALIGNMENT_CENTER))
	var occ := _challenges_card()
	if occ:
		mv.add_child(occ)
	var ch := Kit.list_row(UD.ui2("c_calendar"), "چالش‌های امروز", "چالش‌های روزانه‌ی آنلاین · الماس جایزه", Kit.img(UD.menu("g_chevrons"), 60), func(): Nav.online("challenges"))
	mv.add_child(ch)
	body.add_child(ent(padx(mv), 7))

func _league_strip(p: Dictionary) -> Control:
	var tr := int(p.get("trophies", 0))
	var lg := UD.league(tr)
	var pn := Kit.glass(NX.GOLD, false)
	pn.set_pad(30, 18)
	var h := Kit.hbox(24, true)
	var medal := Kit.img(UD.ui(UD.MEDAL[mini(int(lg["idx"]), 5)]), 120)
	h.add_child(medal)
	var col := Kit.vbox(8)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	var top := Kit.hbox(12, true)
	top.add_child(Kit.label("لیگ %s" % UD.LEAGUE_FA[lg["name"]], 38, NX.TEXT, true))
	var sp := Control.new(); sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL; top.add_child(sp)
	top.add_child(Kit.label("%s / %s" % [NX.fa(tr), NX.fa(lg["to"])], 29, NX.GOLD))
	col.add_child(top)
	var bar := Kit.progress(float(tr - int(lg["from"])) / maxf(1.0, float(int(lg["to"]) - int(lg["from"]))), NX.GOLD, NX.ORANGE, 18)
	bar.layout_direction = Control.LAYOUT_DIRECTION_LTR
	col.add_child(bar)
	h.add_child(col)
	pn.add_child(h)
	Kit.tap(pn, func(): Nav.go("play"), 0.98)
	return pn

func _mode_card(m: Dictionary) -> Control:
	var col: Color = m["color"]
	var c := PanelContainer.new()
	c.custom_minimum_size = Vector2(300, 380)
	c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var sb := NX.box(Color(0.04, 0.06, 0.18, 0.9), 52, 4, Color(col.r, col.g, col.b, 0.55), 16, Color(col.r, col.g, col.b, 0.3))
	c.add_theme_stylebox_override("panel", sb)
	var st := Kit.stage(300, 380)
	var g := NxGrad.new([Color(col.r, col.g, col.b, 0.35), Color(0.055, 0.086, 0.25, 0.6), Color(0.02, 0.03, 0.09, 0.0)], 50, 1.57, 0.0)
	g.position = Vector2.ZERO
	g.size = Vector2(300, 380)
	st.add_child(g)
	var art := Kit.img(UD.ui(m["img"]), Vector2(220, 230))
	Kit.put(st, art, 150, 140)
	Kit.bob(art, 8, 2.2 + randf() * 0.6)
	var e := Kit.caps(m["en"], 19, NX.hdr(col, 1.3), 3)
	e.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	e.position = Vector2(0, 275)
	e.size = Vector2(300, 30)
	st.add_child(e)
	var n := Kit.label(m["name"], 38, NX.TEXT, true)
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	n.position = Vector2(0, 300)
	n.size = Vector2(300, 60)
	st.add_child(n)
	c.add_child(st)
	var k: String = m["k"]
	Kit.tap(c, func(): Nav.go("setup", {"mode": k}), 0.94)
	return c

func _plate(pl: Array) -> Control:
	var col: Color = pl[3]
	var pn := PanelContainer.new()
	pn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pn.custom_minimum_size.y = 200
	var sb := NX.box(Color(0.045, 0.07, 0.19, 0.86), 44, 3, Color(col.r, col.g, col.b, 0.42))
	sb.content_margin_left = 24; sb.content_margin_right = 24; sb.content_margin_top = 16; sb.content_margin_bottom = 16
	pn.add_theme_stylebox_override("panel", sb)
	var g := NxGrad.new([Color(col.r, col.g, col.b, 0.22), Color(col.r, col.g, col.b, 0.06), Color(0, 0, 0, 0)], 40, 0.0, 0.1)
	g.layout_direction = Control.LAYOUT_DIRECTION_LTR
	pn.add_child(g)
	var h := Kit.hbox(14, true)
	h.add_child(Kit.img(UD.ui(pl[0]), 128))
	var v := Kit.vbox(0)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(Kit.label(pl[1], 38, NX.TEXT, true))
	var s := Kit.label(pl[2], 25, NX.DIM)
	s.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(s)
	h.add_child(v)
	pn.add_child(h)
	Kit.tap(pn, pl[4], 0.95)
	return pn

func _loadout(p: Dictionary, me: Dictionary) -> Control:
	var pn := Kit.glass()
	pn.set_pad(26, 22)
	var h := Kit.hbox(18, true)
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	var bi := int(p.get("ball", 0))
	var fi := int(p.get("field", 0))
	var fo := int(p.get("form", 0))
	var items := [
		[UD.team_tex(me), "دیسک", me["name"], false],
		[UD.ball_tex(bi), "توپ", UD.ball_name(bi), false],
		[UD.field_thumb(fi), "زمین", UD.field(fi)["name"], true],
		[UD.menu("g_chevrons"), "ترکیب", UD.forms()[fo][0], false],
	]
	for it in items:
		var v := Kit.vbox(6)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var holder := PanelContainer.new()
		holder.add_theme_stylebox_override("panel", NX.box(Color(0.02, 0.03, 0.09, 0.7), 34, 2, NX.LINE))
		holder.custom_minimum_size = Vector2(170, 170)
		holder.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		var im := Kit.img(it[0], Vector2(100, 136) if it[3] else Vector2(136, 136), "cover" if it[3] else "contain")
		holder.add_child(Kit.center(im))
		v.add_child(holder)
		var a := Kit.label(it[1], 25, NX.DIM)
		a.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(a)
		var b := Kit.label(it[2], 27, NX.TEXT, true)
		b.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.clip_text = true
		b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		b.custom_minimum_size.x = 180
		v.add_child(b)
		h.add_child(v)
	pn.add_child(h)
	Kit.tap(pn, func(): Nav.go("team"), 0.98)
	return pn

func _mission(a: Dictionary, p: Dictionary) -> Control:
	var mx := int(a["max"])
	var cur := mini(mx, UD.ach_cur(a, p))
	var done := cur >= mx
	var pn := Kit.glass(NX.GREEN if done else Color.TRANSPARENT, done)
	pn.set_pad(26, 20)
	var h := Kit.hbox(22, true)
	h.add_child(Kit.img(UD.ui2(a["icon"]), 110))
	var v := Kit.vbox(6)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var t := Kit.hbox(8, true)
	t.add_child(Kit.label(a["name"], 34, NX.TEXT, true))
	var sp := Control.new(); sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL; t.add_child(sp)
	t.add_child(Kit.label("%s/%s" % [NX.fa(cur), NX.fa(mx)], 29, NX.GREEN if done else NX.DIM))
	v.add_child(t)
	v.add_child(Kit.label(a["desc"], 28, NX.DIM))
	var bar := Kit.progress(float(cur) / mx, NX.GREEN if done else NX.CYAN, NX.INDIGO, 15)
	bar.layout_direction = Control.LAYOUT_DIRECTION_LTR
	v.add_child(bar)
	h.add_child(v)
	if done:
		var id: String = a["id"]
		var b := Kit.button_small("دریافت", func(): UD.claim_ach(id), "green")
		b.custom_minimum_size.x = 200
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(b)
	else:
		var r := Kit.vbox(0)
		r.alignment = BoxContainer.ALIGNMENT_CENTER
		r.add_child(Kit.center(Kit.img(UD.ui2("c_coin"), 62)))
		var c := Kit.title("+%d" % int(a["coins"]), 26, NX.GOLD, "head")
		c.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		r.add_child(c)
		r.custom_minimum_size.x = 150
		h.add_child(r)
	pn.add_child(h)
	return pn


## speech bubble beside the mascot (was a toast that collapsed into a one-letter column):
## right of the mascot, max 70% of the screen width, auto height, auto-dismiss.
func _mascot_say(text: String) -> void:
	if hero == null or not is_instance_valid(hero):
		return
	if _say and is_instance_valid(_say):
		_say.queue_free()
	if _say_tw:
		_say_tw.kill()
	var W := 1080.0
	var b := Kit.speech(text, W * 0.7, 38)
	b.mouse_filter = Control.MOUSE_FILTER_STOP
	b.z_index = 5
	hero.add_child(b)
	b.reset_size()
	var sz := b.get_combined_minimum_size()
	b.size = sz
	# mascot box: x 30..270, y (hh-475)..(hh-125); bubble's tail corner points at its head
	var hh := hero.size.y
	b.position = Vector2(clampf(286.0, 20.0, W - sz.x - 20.0), maxf(20.0, hh - 470.0 - sz.y * 0.5))
	b.pivot_offset = Vector2(0, sz.y)
	(func():
		if is_instance_valid(b):
			b.size = Vector2.ZERO
			b.reset_size()).call_deferred()
	var tail := Polygon2D.new()
	tail.color = Color(0.04, 0.07, 0.2, 0.97)
	tail.polygon = PackedVector2Array([Vector2(4, sz.y - 70), Vector2(-26, sz.y - 30), Vector2(4, sz.y - 40)])
	b.add_child(tail)
	Kit.tap(b, func(): _hide_say(), 0.97)
	_say = b
	b.modulate.a = 0.0
	b.scale = Vector2(0.85, 0.85)
	_say_tw = b.create_tween()
	_say_tw.set_parallel(true)
	_say_tw.tween_property(b, "modulate:a", 1.0, 0.2)
	_say_tw.tween_property(b, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_say_tw.chain().tween_interval(clampf(2.2 + text.length() * 0.06, 2.5, 7.0))
	_say_tw.chain().tween_callback(_hide_say)

func _hide_say() -> void:
	var b := _say
	_say = null
	if b == null or not is_instance_valid(b):
		return
	var tw := b.create_tween()
	tw.tween_property(b, "modulate:a", 0.0, 0.22)
	tw.tween_callback(b.queue_free)
