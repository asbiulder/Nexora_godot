extends Control
## Public profile of any player (port of RN social/PublicProfile.tsx): avatar/photo, level, league,
## stats, followers, follow / unfollow, message, block, club.
## params: {id: user uuid}
## Tables/RPC: profiles, profile_stats (view), follows (select/insert/delete), user_blocks
## (select/insert/delete), clubs, leagues; rpc open_dm.

var id := ""
var p: Dictionary = {}
var stats: Dictionary = {}
var club: Dictionary = {}
var following := false
var blocked := false
var busy := false
var body: VBoxContainer
var title_l: Label


func setup(prm: Dictionary) -> void:
	id = OUI.s(prm.get("id", ""))


func _ready() -> void:
	Nav.chrome(false)
	OUI.boot()
	var pg := OUI.page(self, "پروفایل", "PILOT PROFILE", func() -> void: Nav.back(), null, OUI.CYAN, _load)
	body = pg["body"]
	title_l = pg["header"].get_meta("title")
	var cc := CenterContainer.new()
	cc.custom_minimum_size.y = OUI.px(300)
	cc.add_child(OUI.spinner(36))
	body.add_child(cc)
	_load()


func leave() -> void:
	Nav.chrome(true)


func on_back() -> bool:
	return false


func _load() -> void:
	OUI.load_leagues()
	OUI.load_discs()
	var r: Dictionary = await OUI.get_rows("profiles?select=*&id=eq." + id)
	if not is_inside_tree():
		return
	var pr: Variant = OUI.one(r)
	if not OUI.ok(r) or pr == null:
		OUI.clear(body)
		body.add_child(OUI.error_state(OUI.err(r) if not OUI.ok(r) else "بازیکن پیدا نشد", _load))
		return
	p = pr
	var u := OUI.uid()
	var s: Dictionary = await OUI.get_rows("profile_stats?select=*&id=eq." + id)
	var f: Dictionary = {}
	var b: Dictionary = {}
	if u != "":
		f = await OUI.get_rows("follows?select=followee&follower=eq.%s&followee=eq.%s" % [u, id])
		b = await OUI.get_rows("user_blocks?select=blocked&blocker=eq.%s&blocked=eq.%s" % [u, id])
	var c: Dictionary = {}
	if OUI.s(p.get("club_id")) != "":
		c = await OUI.get_rows("clubs?select=id,name,tag,emblem&id=eq." + OUI.s(p.get("club_id")))
	await OUI.load_leagues()
	if not is_inside_tree():
		return
	stats = OUI.d(OUI.one(s))
	following = OUI.one(f) != null
	blocked = OUI.one(b) != null
	club = OUI.d(OUI.one(c))
	_render()


func _render() -> void:
	OUI.clear(body)
	title_l.text = OUI.s(p.get("username"))
	var lg: Dictionary = {}
	for l in OUI.leagues:
		if OUI.s(l.get("id")) == OUI.s(p.get("league")):
			lg = l
	var lc := OUI.league_color(lg) if not lg.is_empty() else OUI.CYAN
	var lp := OUI.level_progress(OUI.i(p.get("xp")))
	var wins := OUI.i(p.get("wins"))
	var played := wins + OUI.i(p.get("losses")) + OUI.i(p.get("draws"))
	var wr := int(round(float(wins) / played * 100.0)) if played > 0 else 0
	var me := OUI.uid() == id
	var on := OUI.is_online(p.get("online_at"))
	# hero
	var hp := OUI.panel(lc, OUI.S_L, true)
	var hv := OUI.vbox(OUI.S_S)
	var eq := OUI.s(p.get("equipped_disc"))
	var av := NetImg.avatar(eq if eq != "" else p.get("avatar"), p.get("avatar_url"), 104, lc)
	if on:
		av.dot = OUI.GREEN
	hv.add_child(av)
	hv.add_child(OUI.lbl(OUI.s(p.get("username")), 20, OUI.TEXT, "title", HORIZONTAL_ALIGNMENT_CENTER))
	hv.add_child(OUI.lbl("آنلاین" if on else "آخرین بازدید %s پیش" % OUI.time_ago(p.get("online_at")), OUI.TS_CAP, OUI.GREEN if on else OUI.DIM, "body", HORIZONTAL_ALIGNMENT_CENTER))
	if OUI.s(p.get("bio")) != "":
		hv.add_child(OUI.lbl(OUI.s(p.get("bio")), OUI.TS_SMALL, Color("#cfe0ff"), "body", HORIZONTAL_ALIGNMENT_CENTER, true, 0))
	var bf := HFlowContainer.new()
	bf.alignment = FlowContainer.ALIGNMENT_CENTER
	bf.add_theme_constant_override("h_separation", OUI.px(4))
	bf.add_theme_constant_override("v_separation", OUI.px(4))
	bf.add_child(OUI.badge("سطح %s" % OUI.fa(OUI.i(p.get("level"), 1)), OUI.GOLD))
	if not lg.is_empty():
		bf.add_child(OUI.badge("لیگ %s" % OUI.s(lg.get("name_fa")), lc))
	if bool(p.get("is_guest", false)):
		bf.add_child(OUI.badge("مهمان", OUI.DIM))
	if not club.is_empty():
		bf.add_child(OUI.badge("[%s] %s" % [OUI.s(club.get("tag")), OUI.s(club.get("name"))], OUI.ORANGE))
	hv.add_child(bf)
	hv.add_child(OUI.spacer(OUI.S_XS))
	hv.add_child(OUI.bar(lp["frac"], OUI.CYAN, OUI.VIOLET, 8))
	hv.add_child(OUI.lbl("%s / %s XP تا سطح %s" % [OUI.fa(lp["cur"]), OUI.fa(lp["need"]), OUI.fa(lp["level"] + 1)], OUI.TS_TINY, OUI.DIM, "body", HORIZONTAL_ALIGNMENT_CENTER))
	var sh := OUI.hbox(0)
	for it in [[OUI.i(stats.get("followers")), "دنبال‌کننده"], [OUI.i(stats.get("following")), "دنبال‌شده"], [OUI.i(p.get("trophies")), "جام"]]:
		var sv := OUI.vbox(0)
		sv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sv.add_child(OUI.lbl(OUI.fa(it[0]), 18, OUI.TEXT, "title", HORIZONTAL_ALIGNMENT_CENTER))
		sv.add_child(OUI.lbl(it[1], OUI.TS_TINY, OUI.DIM, "body", HORIZONTAL_ALIGNMENT_CENTER))
		sh.add_child(sv)
	hv.add_child(sh)
	if not me:
		var ah := OUI.hbox(OUI.S_S)
		var fb := OUI.btn("دنبال می‌کنی ✓" if following else "دنبال کردن", _toggle_follow, "dark" if following else "primary", true)
		fb.disabled = busy
		fb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var mb := OUI.btn("پیام", _message, "green", true)
		mb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ah.add_child(fb)
		ah.add_child(mb)
		hv.add_child(ah)
	hp.add_child(hv)
	body.add_child(hp)
	OUI.enter(hp, 0)
	# stat grid
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", OUI.px(8))
	grid.add_theme_constant_override("v_separation", OUI.px(8))
	var cells := [["x_ball", "بازی", OUI.fa(played)], ["x_medal", "برد", OUI.fa(wins)], ["x_shield", "باخت", OUI.fa(OUI.i(p.get("losses")))], ["x_star", "درصد برد", "%s٪" % OUI.fa(wr)], ["x_statue", "گل", OUI.fa(OUI.i(p.get("goals")))], ["x_crown", "آرنا", OUI.fa(OUI.i(p.get("arena_points")))]]
	var k := 1
	for cl in cells:
		var cp := OUI.panel(null, OUI.S_S)
		cp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var cv := OUI.vbox(2)
		var im := OUI.img(OUI.ui2(cl[0]), 34)
		im.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		cv.add_child(im)
		cv.add_child(OUI.lbl(cl[2], 16, OUI.TEXT, "title", HORIZONTAL_ALIGNMENT_CENTER))
		cv.add_child(OUI.lbl(cl[1], OUI.TS_TINY, OUI.DIM, "body", HORIZONTAL_ALIGNMENT_CENTER))
		cp.add_child(cv)
		grid.add_child(cp)
		OUI.enter(cp, k)
		k += 1
	body.add_child(grid)
	# active disc
	var dp := OUI.panel(null)
	var dh := OUI.hbox(OUI.S_M)
	dh.add_child(OUI.img(OUI.disc_tex(eq), 56))
	var dv := OUI.vbox(OUI.S_XS)
	dv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dv.add_child(OUI.lbl("دیسک فعال", OUI.TS_SMALL, OUI.TEXT, "bold"))
	var ds := OUI.disc_stats(eq)
	dv.add_child(OUI.stat_bars(ds["power"], ds["accuracy"]))
	dh.add_child(dv)
	if not lg.is_empty():
		dh.add_child(OUI.img(OUI.league_tex(lg.get("id")), 48))
	dp.add_child(dh)
	body.add_child(dp)
	if not club.is_empty():
		var cid := OUI.s(club.get("id"))
		body.add_child(OUI.btn("باشگاه %s" % OUI.s(club.get("name")), func() -> void: Nav.go("club", {"id": cid}), "gold", true))
	if not me:
		var bl := OUI.tap(OUI.lbl("رفع مسدودی" if blocked else "مسدود کردن این کاربر", OUI.TS_SMALL, OUI.RED, "body", HORIZONTAL_ALIGNMENT_CENTER), _toggle_block)
		bl.custom_minimum_size.y = OUI.px(44)
		body.add_child(bl)


func _toggle_follow() -> void:
	var u := OUI.uid()
	if u == "" or busy:
		return
	busy = true
	var r: Dictionary
	if following:
		r = await OUI.del("follows?follower=eq.%s&followee=eq.%s" % [u, id])
	else:
		r = await OUI.post("follows", {"follower": u, "followee": id})
	busy = false
	if not is_inside_tree():
		return
	if not OUI.ok(r):
		OUI.toast_err(OUI.err(r))
		_render()
		return
	stats["followers"] = OUI.i(stats.get("followers")) + (-1 if following else 1)
	following = not following
	OUI.buzz("medium")
	if following:
		OUI.sfx("ready")
	_render()


func _message() -> void:
	var r: Dictionary = await Supa.call_rpc("open_dm", {"p_user": id})
	if OUI.ok(r):
		Nav.go("chat", {"id": OUI.s(r.get("data"))})
	else:
		OUI.toast_err(OUI.err(r))


func _toggle_block() -> void:
	var u := OUI.uid()
	if u == "":
		return
	var r: Dictionary
	if blocked:
		r = await OUI.del("user_blocks?blocker=eq.%s&blocked=eq.%s" % [u, id])
	else:
		r = await OUI.post("user_blocks", {"blocker": u, "blocked": id})
	if not is_inside_tree():
		return
	if not OUI.ok(r):
		OUI.toast_err(OUI.err(r))
		return
	OUI.toast("از مسدودی خارج شد" if blocked else "کاربر مسدود شد")
	blocked = not blocked
	_render()
