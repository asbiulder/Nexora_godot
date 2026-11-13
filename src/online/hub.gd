extends Control
## Online hub (port of RN Hub.tsx + the connect/quick parts of OnlineRoot.tsx):
## profile strip, quick match, shortcuts, create / join by code, live room list with mode filter.
## params: {quick?: "1v1"|"2v2"|"3v3"} (Oracle "find me a quick match")
## Tables/RPC: room_list (select), realtime rooms/room_players (hub:rooms), rpc quick_match, join_room, create_room.

var params: Dictionary = {}
var rows_data: Array = []
var loaded := false
var err_msg := ""
var filter := "all"
var busy := ""
var ch: Variant = null
var vl: OUI.VList
var hdr: VBoxContainer
var count_lbl: Label
var code_in: LineEdit
var profile_slot: Control
var quick_btns: Dictionary = {}
var debounce: Timer
var poll: Timer
var _quick_done := false
var _create_busy := false


func setup(p: Dictionary) -> void:
	params = p


func _ready() -> void:
	Nav.chrome(false)
	set_anchors_preset(Control.PRESET_FULL_RECT)
	layout_direction = Control.LAYOUT_DIRECTION_RTL
	OUI.boot()
	_connect()


func leave() -> void:
	if ch != null:
		Supa.remove_channel(ch)
		ch = null
	Nav.chrome(true)


func on_back() -> bool:
	# leave the room link (if any); Nav handles the actual navigation
	if OUI.link != null:
		OUI.leave_room(false)
	return false


func _back() -> void:
	if OUI.link != null:
		OUI.leave_room(false)
	Nav.back()


# ---------------------------------------------------------------- connect (guests sign in anonymously)
func _connect() -> void:
	OUI.clear(self)
	var cc := CenterContainer.new()
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(cc)
	var v := OUI.vbox(OUI.S_M)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	cc.add_child(v)
	var sp := OUI.spinner(40)
	sp.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(sp)
	v.add_child(OUI.lbl("در حال اتصال به سرور…", OUI.TS_BODY, OUI.DIM, "body", HORIZONTAL_ALIGNMENT_CENTER))
	var back := OUI.btn("بازگشت", _back, "dark", true)
	back.custom_minimum_size.x = OUI.px(160)
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(back)
	var id: String = await OUI.ensure()
	if not is_inside_tree():
		return
	if id == "":
		OUI.clear(v)
		v.add_child(OUI.error_state("اتصال به سرور برقرار نشد", _connect))
		var b2 := OUI.btn("بازگشت", _back, "dark", true)
		b2.custom_minimum_size.x = OUI.px(160)
		b2.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		v.add_child(b2)
		return
	_build()


func _build() -> void:
	OUI.clear(self)
	var root := OUI.vbox(0)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	root.add_child(OUI.header("آنلاین", "ONLINE ARENA", _back, null, OUI.CYAN, _refresh))
	vl = OUI.VList.new(132, _make_row, _bind_row, 8)
	root.add_child(vl)
	hdr = _make_header()
	vl.set_header(hdr)
	_set_empty()
	OUI.fade_in(root)
	OUI.ebus().profile_changed.connect(_on_profile)
	_load()
	# live room list
	debounce = Timer.new()
	debounce.one_shot = true
	debounce.wait_time = 0.6
	debounce.timeout.connect(_load)
	add_child(debounce)
	poll = Timer.new()
	poll.wait_time = 20.0
	poll.timeout.connect(_load)
	add_child(poll)
	poll.start()
	ch = Supa.channel("hub:rooms", {})
	ch.on_postgres("*", "public", "rooms", "", func(_r: Variant) -> void: _soon())
	ch.on_postgres("*", "public", "room_players", "", func(_r: Variant) -> void: _soon())
	ch.subscribe(func(_s: Variant) -> void: pass)
	# Oracle "find me a quick match": once connected, run quick_match and drop straight into the lobby
	var q := OUI.s(params.get("quick", ""))
	if q != "" and not _quick_done:
		_quick_done = true
		_quick(q)


func _soon() -> void:
	if is_instance_valid(debounce):
		debounce.start()


func _on_profile(_p: Dictionary) -> void:
	if is_instance_valid(profile_slot):
		_fill_profile()


func _refresh() -> void:
	await _load()
	if is_inside_tree():
		OUI.toast("به‌روز شد", "ok")


func _load() -> void:
	var r: Dictionary = await OUI.get_rows("room_list?select=*&order=created_at.desc&limit=60")
	if not is_inside_tree():
		return
	if not OUI.ok(r):
		err_msg = OUI.err(r)
	else:
		err_msg = ""
		rows_data = OUI.rows(r)
		loaded = true
	_apply()


func _filtered() -> Array:
	if filter == "all":
		return rows_data
	return rows_data.filter(func(x: Variant) -> bool: return OUI.s(x.get("mode")) == filter)


func _apply() -> void:
	var data := _filtered() if loaded else []
	if is_instance_valid(count_lbl):
		count_lbl.text = ("%s اتاق" % OUI.fa(data.size())) if loaded else ""
	vl.set_items(data)
	_set_empty()


func _set_empty() -> void:
	if err_msg != "":
		vl.set_empty(OUI.error_state(err_msg, _load))
	elif not loaded:
		vl.set_empty(OUI.skeleton(4))
	else:
		vl.set_empty(OUI.empty(OUI.ui2("x_ball"), "فعلاً اتاقی باز نیست", "یک اتاق بساز و دوستانت را با کد دعوت کن", "ساخت اتاق", _open_create))


# ---------------------------------------------------------------- header (profile, quick match, shortcuts, join)
func _make_header() -> VBoxContainer:
	var v := OUI.vbox(OUI.S_M)
	var m := OUI.margin(v, OUI.S_L, OUI.S_M, OUI.S_L, OUI.S_S)
	var outer := OUI.vbox(0)
	outer.add_child(m)
	# my online card
	profile_slot = OUI.vbox(0)
	v.add_child(profile_slot)
	_fill_profile()
	# quick match
	var qp := OUI.panel(OUI.CYAN, OUI.S_M, true)
	var qv := OUI.vbox(OUI.S_S)
	var qh := OUI.hbox(OUI.S_S)
	qh.add_child(OUI.img(OUI.ui2("x_ball"), 36))
	var qt := OUI.vbox(0)
	qt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	qt.add_child(OUI.lbl("مسابقه‌ی سریع", OUI.TS_H, OUI.TEXT, "title"))
	qt.add_child(OUI.lbl("هم‌سطح‌ترین حریف آنلاین را پیدا کن", OUI.TS_CAP, OUI.DIM))
	qh.add_child(qt)
	qv.add_child(qh)
	var qb := OUI.hbox(OUI.S_S)
	var styles := ["primary", "violet", "gold"]
	for k in 3:
		var mode: String = OUI.MODES[k]
		var b := OUI.btn(mode.to_upper(), func() -> void: _quick(mode), styles[k], true, OUI.MODE_FA[mode])
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		quick_btns[mode] = b
		qb.add_child(b)
	qv.add_child(qb)
	qp.add_child(qv)
	OUI.enter(qp, 1)
	v.add_child(qp)
	# shortcuts
	var sh := OUI.hbox(OUI.S_S)
	for it in [["arena", "آرنا", "x_crown", OUI.VIOLET], ["tournaments", "تورنمنت", "x_trophy", OUI.ORANGE], ["ranks", "رده‌بندی", "x_medal", OUI.GOLD], ["challenges", "چالش‌ها", "c_calendar", OUI.GREEN]]:
		var tile := PanelContainer.new()
		tile.add_theme_stylebox_override("panel", OUI.sb(Color(it[3], 0.14), 18, Color(it[3], 0.4), 1))
		tile.custom_minimum_size.y = OUI.px(76)
		var tv := OUI.vbox(2)
		tv.alignment = BoxContainer.ALIGNMENT_CENTER
		var im := OUI.img(OUI.ui2(it[2]), 36)
		im.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		tv.add_child(im)
		tv.add_child(OUI.lbl(it[1], OUI.TS_CAP, OUI.TEXT, "bold", HORIZONTAL_ALIGNMENT_CENTER))
		tile.add_child(tv)
		var target: String = it[0]
		var t := OUI.tap(tile, func() -> void: Nav.go(target, {}))
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sh.add_child(t)
	v.add_child(sh)
	# create / join by code
	var cj := OUI.hbox(OUI.S_S)
	var cb := OUI.btn("ساخت اتاق", _open_create, "green", true)
	cb.custom_minimum_size.x = OUI.px(128)
	cj.add_child(cb)
	code_in = OUI.line_edit("کد ۶ رقمی", 6, false, false, 44)
	code_in.alignment = HORIZONTAL_ALIGNMENT_CENTER
	code_in.add_theme_font_override("font", OUI.font("head"))
	code_in.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	code_in.text_changed.connect(_on_code)
	code_in.text_submitted.connect(func(_t: String) -> void: _join_code())
	cj.add_child(code_in)
	cj.add_child(OUI.pill("ورود", _join_code, OUI.CYAN, 64, 44))
	v.add_child(cj)
	# rooms title + filter
	var th := OUI.hbox(OUI.S_S)
	th.add_child(OUI.lbl("اتاق‌های باز", OUI.TS_H, OUI.TEXT, "bold"))
	th.add_child(OUI.expand())
	count_lbl = OUI.lbl("", OUI.TS_CAP, OUI.DIM)
	th.add_child(count_lbl)
	v.add_child(th)
	v.add_child(OUI.segment([["all", "همه"], ["1v1", "1v1"], ["2v2", "2v2"], ["3v3", "3v3"]], filter, func(val: Variant) -> void:
		filter = str(val)
		_apply()))
	return outer


func _fill_profile() -> void:
	OUI.clear(profile_slot)
	var p := OUI.profile
	if p.is_empty():
		return
	var lp := OUI.level_progress(OUI.i(p.get("xp")))
	var pn := OUI.panel(OUI.GOLD, OUI.S_M)
	var h := OUI.hbox(OUI.S_M)
	h.add_child(NetImg.avatar(OUI.s(p.get("equipped_disc", "")) if OUI.s(p.get("equipped_disc", "")) != "" else p.get("avatar"), p.get("avatar_url"), 52, OUI.GOLD))
	var mid := OUI.vbox(OUI.S_XS)
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var nh := OUI.hbox(OUI.S_XS)
	var nl := OUI.lbl(OUI.s(p.get("username")), OUI.TS_H, OUI.TEXT, "bold")
	nl.custom_minimum_size.x = OUI.px(60)
	nh.add_child(nl)
	nh.add_child(OUI.badge("سطح %s" % OUI.fa(OUI.i(p.get("level"), 1)), OUI.GOLD))
	nh.add_child(OUI.expand())
	mid.add_child(nh)
	mid.add_child(OUI.bar(lp["frac"], OUI.CYAN, OUI.VIOLET, 6))
	mid.add_child(OUI.lbl("%s / %s XP · امتیاز %s" % [OUI.fa(lp["cur"]), OUI.fa(lp["need"]), OUI.fa(OUI.i(p.get("rating")))], OUI.TS_TINY, OUI.DIM))
	h.add_child(mid)
	h.add_child(OUI.img(OUI.league_tex(p.get("league")), 48))
	pn.add_child(h)
	var t := OUI.tap(pn, func() -> void: Nav.go("ranks", {}))
	profile_slot.add_child(t)
	OUI.enter(t, 0)


func _on_code(t: String) -> void:
	var clean := ""
	for ch2 in t.to_upper():
		if (ch2 >= "A" and ch2 <= "Z") or (ch2 >= "0" and ch2 <= "9"):
			clean += ch2
	clean = clean.substr(0, 6)
	if clean != t:
		var c := code_in.caret_column
		code_in.text = clean
		code_in.caret_column = mini(c, clean.length())


# ---------------------------------------------------------------- actions
func _act(key: String, fn: Callable) -> void:
	if busy != "":
		return
	busy = key
	_busy_ui()
	var r: Dictionary = await fn.call()
	if not is_inside_tree():
		if OUI.ok(r):
			OUI.enter_room(r.get("data"))
		return
	busy = ""
	_busy_ui()
	if OUI.ok(r):
		OUI.sfx("join")
		OUI.buzz("medium")
		OUI.enter_room(r.get("data"))
	else:
		OUI.toast_err(OUI.err(r))
		OUI.buzz("heavy")


func _busy_ui() -> void:
	for m in quick_btns:
		var b: Button = quick_btns[m]
		if is_instance_valid(b):
			b.disabled = busy != ""
			b.text = ("…" if busy == "quick" + m else m.to_upper()) + "\n" + OUI.MODE_FA[m]
	vl.refresh_rows()


func _quick(m: String) -> void:
	OracleCoach.react("search")
	_act("quick" + m, func() -> Dictionary: return await Supa.call_rpc("quick_match", {"p_mode": m, "p_kind": "quick"}))


func _join(id: String, spectate: bool) -> void:
	_act(("w" if spectate else "j") + id, func() -> Dictionary: return await Supa.call_rpc("join_room", {"p_room": id, "p_spectate": spectate}))


func _join_code() -> void:
	var c := code_in.text.strip_edges().to_upper()
	if c.length() != 6:
		OUI.toast_err("کد اتاق ۶ کاراکتر است")
		return
	_act("code", func() -> Dictionary: return await Supa.call_rpc("join_room", {"p_code": c}))


# ---------------------------------------------------------------- room rows
class RoomRow extends PanelContainer:
	var av: NetImg.Avatar
	var name_l: Label
	var sub_l: Label
	var badges: HBoxContainer
	var cnt_l: Label
	var spec_l: Label
	var join_b: Button
	var watch_b: Button
	var id := ""


func _make_row() -> Control:
	var r := RoomRow.new()
	r.add_theme_stylebox_override("panel", OUI.sb(OUI.PANEL_BG, 22, OUI.LINE, 1.5, OUI.S_M))
	var v := OUI.vbox(OUI.S_S)
	var h := OUI.hbox(OUI.S_S)
	r.av = NetImg.avatar(null, null, 44)
	h.add_child(r.av)
	var mid := OUI.vbox(2)
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.name_l = OUI.lbl("", OUI.TS_BODY, OUI.TEXT, "bold")
	r.sub_l = OUI.lbl("", OUI.TS_CAP, OUI.DIM)
	r.badges = OUI.hbox(OUI.S_XS)
	mid.add_child(r.name_l)
	mid.add_child(r.sub_l)
	mid.add_child(r.badges)
	h.add_child(mid)
	var cv := OUI.vbox(0)
	cv.custom_minimum_size.x = OUI.px(64)
	r.cnt_l = OUI.lbl("", OUI.TS_H, OUI.TEXT, "title", HORIZONTAL_ALIGNMENT_CENTER)
	r.spec_l = OUI.lbl("", OUI.TS_TINY, OUI.DIM, "body", HORIZONTAL_ALIGNMENT_CENTER)
	cv.add_child(r.cnt_l)
	cv.add_child(r.spec_l)
	h.add_child(cv)
	v.add_child(h)
	var bh := OUI.hbox(OUI.S_S)
	r.join_b = OUI.btn("ورود", func() -> void: _join(r.id, false), "primary", true)
	r.join_b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.watch_b = OUI.btn("تماشا", func() -> void: _join(r.id, true), "dark", true)
	r.watch_b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bh.add_child(r.join_b)
	bh.add_child(r.watch_b)
	v.add_child(bh)
	r.add_child(v)
	return r


func _bind_row(c: Control, item: Variant, _idx: int) -> void:
	var r := c as RoomRow
	var it := OUI.d(item)
	r.id = OUI.s(it.get("id"))
	var players := OUI.i(it.get("players"))
	var cap := OUI.i(it.get("capacity"), 2)
	var full := players >= cap
	var playing := OUI.s(it.get("status")) == "playing"
	var kind: Array = OUI.KIND_FA.get(OUI.s(it.get("kind")), OUI.KIND_FA["casual"])
	r.av.set_data(it.get("host_avatar"), it.get("host_avatar_url"), OUI.RED if playing else OUI.CYAN)
	r.name_l.text = OUI.s(it.get("name"))
	r.sub_l.text = "%s · سطح %s · %s" % [OUI.s(it.get("host_name")), OUI.fa(OUI.i(it.get("host_level"), 1)), OUI.rule_label(it.get("settings"))]
	OUI.clear(r.badges)
	r.badges.add_child(OUI.badge(OUI.s(it.get("mode")).to_upper(), OUI.SKY))
	r.badges.add_child(OUI.badge(kind[0], kind[1]))
	r.badges.add_child(OUI.badge("زنده", OUI.RED, true) if playing else OUI.badge("در انتظار", OUI.GREEN))
	r.cnt_l.text = "%s/%s" % [OUI.fa(players), OUI.fa(cap)]
	r.cnt_l.add_theme_color_override("font_color", OUI.ORANGE if full else OUI.TEXT)
	r.spec_l.text = "👁 %s" % OUI.fa(OUI.i(it.get("spectators")))
	r.join_b.visible = not playing and not full
	r.join_b.text = "…" if busy == "j" + r.id else "ورود"
	r.watch_b.text = "…" if busy == "w" + r.id else "تماشا"
	r.join_b.disabled = busy != ""
	r.watch_b.disabled = busy != ""


# ---------------------------------------------------------------- create room sheet
func _open_create() -> void:
	var st := {"name": "", "mode": "1v1", "priv": false, "ranked": true, "voice": true, "rule": "g3", "turn": 15, "field": 0}
	var sc := OUI.scroll()
	var v := OUI.vbox(OUI.S_XS)
	sc.add_child(OUI.margin(v, OUI.S_L, 0, OUI.S_L, OUI.S_XL * 2))
	var nf := OUI.field("نام اتاق", "مثلاً: فینال کهکشانی", 40)
	v.add_child(nf)
	v.add_child(OUI.cap_label("حالت"))
	var mi: Array = []
	for m in OUI.MODES:
		mi.append([m, OUI.MODE_FA[m]])
	v.add_child(OUI.segment(mi, "1v1", func(x: Variant) -> void: st["mode"] = x))
	v.add_child(OUI.cap_label("قانون"))
	v.add_child(OUI.segment(OUI.RULES, "g3", func(x: Variant) -> void: st["rule"] = x, OUI.VIOLET))
	v.add_child(OUI.cap_label("زمان هر نوبت"))
	v.add_child(OUI.segment(OUI.TURNS, 15, func(x: Variant) -> void: st["turn"] = x, OUI.GREEN))
	v.add_child(OUI.cap_label("زمین"))
	v.add_child(field_picker(0, func(i: int) -> void: st["field"] = i))
	v.add_child(OUI.spacer(OUI.S_M))
	v.add_child(OUI.opt_row("خصوصی", "فقط با کد اتاق می‌شود وارد شد", false, func(x: bool) -> void: st["priv"] = x))
	v.add_child(OUI.opt_row("رتبه‌ای", "نتیجه روی امتیاز و لیگ اثر دارد", true, func(x: bool) -> void: st["ranked"] = x))
	v.add_child(OUI.opt_row("چت صوتی", "بازیکن‌ها می‌توانند صحبت کنند", true, func(x: bool) -> void: st["voice"] = x))
	v.add_child(OUI.spacer(OUI.S_L))
	var go := OUI.btn("ساخت اتاق", Callable(), "green")
	go.pressed.connect(func() -> void:
		if busy != "":
			return
		go.text = "در حال ساخت…"
		go.disabled = true
		var nm := OUI.field_value(nf).strip_edges()
		var settings := OUI.rule_to_settings(str(st["rule"]))
		settings["field"] = st["field"]
		settings["turn"] = st["turn"]
		settings["ball"] = 0
		var args := {"p_mode": st["mode"], "p_name": nm if nm != "" else null, "p_private": st["priv"], "p_ranked": st["ranked"], "p_voice": st["voice"], "p_settings": settings}
		busy = "create"
		var r: Dictionary = await Supa.call_rpc("create_room", args)
		busy = ""
		if OUI.ok(r):
			Nav.close_sheet()
			OUI.sfx("join")
			OUI.buzz("medium")
			OUI.enter_room(r.get("data"))
		else:
			if is_instance_valid(go):
				go.text = "ساخت اتاق"
				go.disabled = false
			OUI.toast_err(OUI.err(r))
			OUI.buzz("heavy"))
	v.add_child(go)
	OUI.open_sheet("ساخت اتاق", "CREATE ROOM", sc, OUI.GREEN, 0.88)


## horizontal field thumbnails (RN FieldPicker) — shared with lobby settings
static func field_picker(value: int, cb: Callable) -> Control:
	var sc := OUI.hscroll()
	sc.custom_minimum_size.y = OUI.px(96)
	var h := OUI.hbox(OUI.S_S)
	sc.add_child(h)
	var boxes: Array = []
	for k in OUI.field_count():
		var pc := PanelContainer.new()
		pc.custom_minimum_size = Vector2(OUI.px(78), OUI.px(88))
		var v := OUI.vbox(2)
		v.alignment = BoxContainer.ALIGNMENT_CENTER
		var th := OUI.img(OUI.field_thumb(k), 44, 58)
		th.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		th.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		v.add_child(th)
		var nl := OUI.lbl(OUI.field_name(k), OUI.TS_TINY, OUI.DIM, "body", HORIZONTAL_ALIGNMENT_CENTER)
		v.add_child(nl)
		pc.add_child(v)
		boxes.append([pc, nl])
		var idx := k
		var set_sel := func(sel: int) -> void:
			for j in boxes.size():
				var on: bool = j == sel
				(boxes[j][0] as PanelContainer).add_theme_stylebox_override("panel", OUI.sb(Color(79 / 255.0, 227 / 255.0, 1, 0.12) if on else Color(0, 0, 0, 0), 12, OUI.CYAN if on else OUI.LINE, 1, 4))
				(boxes[j][1] as Label).add_theme_color_override("font_color", OUI.TEXT if on else OUI.DIM)
		var t := OUI.tap(pc, func() -> void:
			set_sel.call(idx)
			cb.call(idx))
		h.add_child(t)
		if k == OUI.field_count() - 1:
			set_sel.call(value)
	return sc
