extends VBoxContainer
## Online account (port of RN screens/Account.tsx + OnlineProfileCard.tsx + OnlineCard.tsx).
## As a screen ("account"): header + account panel + online profile card.
## Embeddable pieces for other workers (no header):
##   preload("res://src/screens/account.gd").make_account_panel()      → settings sheet "حساب آنلاین"
##   preload("res://src/screens/account.gd").make_profile_card()       → profile tab online section
##   preload("res://src/screens/account.gd").make_online_card()        → Home/Play "آنلاین" entry card
## params: {embedded?: bool, part?: "account"|"profile"}
## Auth: Supa.sign_in_email / sign_up_email / sign_in_anon / reset_password / sign_out; guest→email upgrade,
## resend and username via OUI. Tables: profiles (username, avatar_url, avatar, bio), xp_events, leagues;
## storage bucket "avatars".

const REASON_FA := {"match": "مسابقه‌ی آنلاین", "tournament": "جایزه‌ی تورنمنت", "challenge": "چالش روزانه", "offline": "برد مقابل ربات"}

var params: Dictionary = {}
var embedded := false
var part := ""
# account panel state
var mode := "up"
var email_v := ""
var pass_v := ""
var pass2_v := ""
var name_v := ""
var edit_name := false
var busy := false
var sent := ""
var err_msg := ""
var sure_out := false
var acc_box: VBoxContainer
# profile card state
var events: Variant = null
var up_busy := false
var bio_v := ""
var edit_bio := false
var prof_box: VBoxContainer
var _last_xp := -1


static func make_account_panel() -> Control:
	var a: Control = load("res://src/screens/account.gd").new()
	a.setup({"embedded": true, "part": "account"})
	return a


static func make_profile_card() -> Control:
	var a: Control = load("res://src/screens/account.gd").new()
	a.setup({"embedded": true, "part": "profile"})
	return a


func setup(p: Dictionary) -> void:
	params = p
	embedded = bool(p.get("embedded", false))
	part = OUI.s(p.get("part", ""))


func _ready() -> void:
	layout_direction = Control.LAYOUT_DIRECTION_RTL
	add_theme_constant_override("separation", OUI.px(OUI.S_S))
	OUI.boot()
	OUI.ebus().profile_changed.connect(_on_profile)
	if not Supa.auth_changed.is_connected(_on_auth):
		Supa.auth_changed.connect(_on_auth)
	if not embedded:
		Nav.chrome(false)
		set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(OUI.header("حساب آنلاین", "ACCOUNT", func() -> void: Nav.back()))
		var sc := OUI.scroll()
		sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
		add_child(sc)
		var v := OUI.vbox(OUI.S_M)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sc.add_child(OUI.margin(v, OUI.S_L, OUI.S_M, OUI.S_L, OUI.S_XL * 2))
		acc_box = OUI.vbox(0)
		prof_box = OUI.vbox(OUI.S_S)
		v.add_child(acc_box)
		v.add_child(prof_box)
	else:
		if part != "profile":
			acc_box = OUI.vbox(0)
			add_child(acc_box)
		if part != "account":
			prof_box = OUI.vbox(OUI.S_S)
			add_child(prof_box)
	_render_all()
	if OUI.uid() != "":
		OUI.refresh_profile()


func leave() -> void:
	if not embedded:
		Nav.chrome(true)


func on_back() -> bool:
	return false


## Supa.auth_changed(event, session)
func _on_auth(_event: Variant = "", _session: Variant = null) -> void:
	_render_all()


func _on_profile(p: Dictionary) -> void:
	if OUI.i(p.get("xp"), -1) != _last_xp:
		events = null
	_render_all()


func _render_all() -> void:
	if not is_inside_tree():
		return
	if acc_box:
		_render_account()
	if prof_box:
		_render_profile()


# ================================================================ account panel
func _render_account() -> void:
	OUI.clear(acc_box)
	var u := OUI.uid()
	var guest := OUI.is_guest()
	var prof := OUI.profile
	var signed_email := u != "" and not guest
	var pn := OUI.panel(OUI.CYAN)
	var v := OUI.vbox(OUI.S_S)
	var h := OUI.hbox(OUI.S_M)
	if not prof.is_empty():
		var eq := OUI.s(prof.get("equipped_disc"))
		h.add_child(NetImg.avatar(eq if eq != "" else prof.get("avatar"), prof.get("avatar_url"), 48))
	else:
		h.add_child(OUI.img(OUI.ui2("c_profile"), 44))
	var tv := OUI.vbox(1)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.add_child(OUI.lbl("حساب آنلاین", 15, OUI.TEXT, "bold"))
	var st := "وارد نشده‌ای" if u == "" else ("مهمان · %s" % OUI.s(prof.get("username")) if guest else "%s · %s" % [OUI.email(), OUI.s(prof.get("username"))])
	tv.add_child(OUI.lbl(st, OUI.TS_CAP, OUI.DIM))
	h.add_child(tv)
	if not prof.is_empty():
		h.add_child(OUI.lbl("سطح %s" % OUI.fa(OUI.i(prof.get("level"), 1)), OUI.TS_CAP, OUI.GOLD, "bold"))
	v.add_child(h)
	# username
	if not prof.is_empty():
		if edit_name:
			var nf := OUI.field("نام کاربری جدید (۳ تا ۲۰ کاراکتر)", "", 20)
			var le: LineEdit = nf.get_meta("input")
			le.text = name_v
			le.text_changed.connect(func(t: String) -> void: name_v = t)
			v.add_child(nf)
			var bh := OUI.hbox(OUI.S_S)
			var sb := OUI.btn("…" if busy else "ذخیره", _save_name, "primary", true)
			sb.disabled = busy
			sb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var cb := OUI.btn("انصراف", func() -> void:
				edit_name = false
				err_msg = ""
				_render_account(), "dark", true)
			cb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			bh.add_child(sb)
			bh.add_child(cb)
			v.add_child(bh)
		else:
			var t := OUI.tap(OUI.lbl("✎ تغییر نام کاربری", OUI.TS_SMALL, OUI.CYAN), func() -> void:
				name_v = OUI.s(OUI.profile.get("username"))
				edit_name = true
				_render_account())
			t.custom_minimum_size.y = OUI.px(44)
			v.add_child(t)
	if sent != "":
		var sp := PanelContainer.new()
		sp.add_theme_stylebox_override("panel", OUI.sb(Color(61 / 255.0, 1, 168 / 255.0, 0.08), 14, Color(OUI.GREEN, 0.33), 1, OUI.S_M))
		var sv := OUI.vbox(OUI.S_S)
		var msg := "لینک تغییر رمز به ایمیلت فرستاده شد. لینک را روی همین گوشی باز کن تا رمز جدید را این‌جا وارد کنی." if sent == "reset" else ("لینک تأیید به ایمیلت فرستاده شد. بعد از باز کردن لینک، حساب مهمانت با همه‌ی پیشرفت‌ها به ایمیل وصل می‌شود." if sent == "upgrade" else "حسابت ساخته شد! لینک تأیید را در ایمیلت باز کن، سپس وارد شو.")
		sv.add_child(OUI.lbl(msg, OUI.TS_SMALL, OUI.TEXT, "body", HORIZONTAL_ALIGNMENT_RIGHT, true, 0))
		var sh := OUI.hbox(OUI.S_S)
		if sent == "confirm":
			var rb := OUI.btn("ارسال دوباره", func() -> void:
				var r: Dictionary = await Supa.resend(email_v)
				_done(r, "دوباره فرستاده شد"), "dark", true)
			rb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			sh.add_child(rb)
		var okb := OUI.btn("باشه", func() -> void:
			if sent == "confirm":
				mode = "in"
			sent = ""
			_render_account(), "primary", true)
		okb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sh.add_child(okb)
		sv.add_child(sh)
		sp.add_child(sv)
		v.add_child(sp)
	elif not signed_email:
		v.add_child(OUI.segment([["up", "ثبت ایمیل" if guest else "ثبت‌نام"], ["in", "ورود"], ["forgot", "فراموشی رمز"]], mode, func(x: Variant) -> void:
			mode = str(x)
			err_msg = ""
			_render_account()))
		var hint := ""
		if mode == "up":
			hint = "با ثبت ایمیل، پیشرفت حساب مهمان حفظ می‌شود و روی هر گوشی وارد می‌شوی." if guest else "حساب بساز تا پیشرفتت روی سرور ذخیره شود."
		elif mode == "in":
			hint = "ورود به حساب دیگر، حساب مهمان فعلی را کنار می‌گذارد." if guest else "با ایمیل و رمز وارد شو."
		else:
			hint = "ایمیلت را وارد کن تا لینک تغییر رمز برایت ارسال شود."
		v.add_child(OUI.lbl(hint, OUI.TS_CAP, OUI.DIM, "body", HORIZONTAL_ALIGNMENT_RIGHT, true, 3))
		var ef := OUI.line_edit("ایمیل", 120, false, true)
		ef.text = email_v
		ef.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_EMAIL_ADDRESS
		ef.text_changed.connect(func(t: String) -> void: email_v = t)
		v.add_child(ef)
		if mode != "forgot":
			var pf := OUI.line_edit("رمز عبور", 72, true, true)
			pf.text = pass_v
			pf.text_changed.connect(func(t: String) -> void: pass_v = t)
			v.add_child(pf)
		if mode == "up":
			var p2 := OUI.line_edit("تکرار رمز عبور", 72, true, true)
			p2.text = pass2_v
			p2.text_changed.connect(func(t: String) -> void: pass2_v = t)
			v.add_child(p2)
		if err_msg != "":
			v.add_child(OUI.lbl(err_msg, OUI.TS_SMALL, OUI.RED, "body", HORIZONTAL_ALIGNMENT_RIGHT, true, 3))
		var label := "ارسال لینک"
		if mode == "up":
			label = "ثبت ایمیل و حفظ پیشرفت" if guest else "ساخت حساب"
		elif mode == "in":
			label = "ورود"
		if busy:
			label = "لطفاً صبر کن…"
		var go := OUI.btn(label, _submit, "primary" if mode == "in" else "green", true)
		go.disabled = busy
		v.add_child(go)
		if u == "":
			var gb := OUI.btn("ادامه به‌عنوان مهمان", func() -> void:
				busy = true
				_render_account()
				var id: String = await OUI.ensure()
				busy = false
				OUI.toast("به‌عنوان مهمان وارد شدی" if id != "" else "اتصال برقرار نشد")
				_render_all(), "dark", true)
			gb.disabled = busy
			v.add_child(gb)
	elif err_msg != "":
		v.add_child(OUI.lbl(err_msg, OUI.TS_SMALL, OUI.RED, "body", HORIZONTAL_ALIGNMENT_RIGHT, true, 3))
	if u != "":
		var ob := OUI.btn(("پیشرفت مهمان از دست می‌رود! دوباره بزن" if guest else "مطمئنی؟ دوباره بزن") if sure_out else "خروج از حساب", func() -> void:
			if not sure_out:
				sure_out = true
				_render_account()
				return
			sure_out = false
			await OUI.sign_out()
			Nav.toast("از حساب خارج شدی", "ok")
			_render_all(), "red", true)
		v.add_child(OUI.spacer(OUI.S_XS))
		v.add_child(ob)
	pn.add_child(v)
	acc_box.add_child(pn)


static func _email_ok(e: String) -> bool:
	return RegEx.create_from_string("^[^\\s@]+@[^\\s@]+\\.[^\\s@]{2,}$").search(e.strip_edges()) != null


func _done(r: Dictionary, ok_msg: String = "") -> bool:
	if not r.get("ok", false):
		err_msg = OUI.s(r.get("error"), "خطا")
		if err_msg == "":
			err_msg = "خطا"
		OUI.buzz("heavy")
		return false
	err_msg = ""
	if ok_msg != "":
		Nav.toast(ok_msg, "ok")
	OUI.buzz("success")
	return true


func _submit() -> void:
	err_msg = ""
	if not _email_ok(email_v):
		err_msg = "ایمیل معتبر نیست"
		_render_account()
		return
	if mode != "forgot" and pass_v.length() < 6:
		err_msg = "رمز عبور حداقل ۶ کاراکتر"
		_render_account()
		return
	if mode == "up" and pass_v != pass2_v:
		err_msg = "تکرار رمز عبور یکسان نیست"
		_render_account()
		return
	busy = true
	_render_account()
	var em := email_v.strip_edges()
	if mode == "forgot":
		if _done(await Supa.reset_password(em)):
			sent = "reset"
	elif mode == "in":
		if _done(await Supa.sign_in_email(em, pass_v), "وارد شدی"):
			pass_v = ""
	elif OUI.uid() != "" and OUI.is_guest():
		if _done(await Supa.upgrade(em, pass_v)):
			sent = "upgrade"
	else:
		var r: Dictionary = await Supa.sign_up_email(em, pass_v, "")
		if _done(r):
			# e-mail confirmation is ON: no session until the link is opened
			sent = "confirm" if OUI.s(OUI.d(r.get("data")).get("info")) == "confirm" else ""
	busy = false
	if is_inside_tree():
		_render_all()


func _save_name() -> void:
	busy = true
	_render_account()
	var r: Dictionary = await OUI.set_username(name_v)
	busy = false
	if _done(r, "نام کاربری تغییر کرد"):
		edit_name = false
	if is_inside_tree():
		_render_account()


# ================================================================ online profile card
func _render_profile() -> void:
	OUI.clear(prof_box)
	var u := OUI.uid()
	var prof := OUI.profile
	if u == "" or prof.is_empty():
		var pn := OUI.panel(OUI.CYAN)
		var h := OUI.hbox(OUI.S_M)
		h.add_child(OUI.img(OUI.ui("portal_globe"), 56))
		var tv := OUI.vbox(2)
		tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tv.add_child(OUI.lbl("پروفایل آنلاین", OUI.TS_H, OUI.TEXT, "bold"))
		tv.add_child(OUI.lbl("سطح، لیگ و آمار آنلاین بعد از ورود نمایش داده می‌شود", OUI.TS_CAP, OUI.DIM, "body", HORIZONTAL_ALIGNMENT_RIGHT, true, 2))
		h.add_child(tv)
		var holder: Array = [null]
		var b := OUI.btn("ورود", func() -> void:
			var bb: Button = holder[0]
			if is_instance_valid(bb):
				bb.text = "…"
			var id: String = await OUI.ensure()
			if id == "":
				OUI.toast("اتصال برقرار نشد")
			_render_all(), "primary", true)
		holder[0] = b
		b.custom_minimum_size.x = OUI.px(80)
		h.add_child(b)
		pn.add_child(h)
		prof_box.add_child(pn)
		return
	OUI.load_leagues()
	var lp := OUI.level_progress(OUI.i(prof.get("xp")))
	var rating := OUI.i(prof.get("rating"))
	var cn := OUI.league_for(rating)
	var cur: Variant = cn[0]
	var nxt: Variant = cn[1]
	var cc := OUI.league_color(cur) if cur != null else OUI.CYAN
	var played := OUI.i(prof.get("wins")) + OUI.i(prof.get("losses")) + OUI.i(prof.get("draws"))
	var pn2 := OUI.panel(cc, OUI.S_M, true)
	var v := OUI.vbox(OUI.S_S)
	var h2 := OUI.hbox(OUI.S_M)
	var avw := Control.new()
	avw.custom_minimum_size = Vector2(OUI.px(76), OUI.px(76))
	var av := NetImg.avatar(prof.get("equipped_disc"), prof.get("avatar_url"), 76, cc)
	avw.add_child(av)
	var cam := PanelContainer.new()
	cam.add_theme_stylebox_override("panel", OUI.sb(Color("#0e1640"), 14, OUI.CYAN, 1))
	cam.custom_minimum_size = Vector2(OUI.px(28), OUI.px(28))
	cam.position = Vector2(-OUI.px(2), OUI.px(50))
	if up_busy:
		cam.add_child(OUI.spinner(20))
	else:
		cam.add_child(OUI.lbl("📷", 13, OUI.TEXT, "body", HORIZONTAL_ALIGNMENT_CENTER))
	avw.add_child(cam)
	var avt := OUI.tap(avw, _upload)
	avt.disabled = up_busy
	h2.add_child(avt)
	var iv := OUI.vbox(OUI.S_XS)
	iv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	iv.add_child(OUI.lbl(OUI.s(prof.get("username")), 18, OUI.TEXT, "title"))
	var bf := HFlowContainer.new()
	bf.add_theme_constant_override("h_separation", OUI.px(4))
	bf.add_child(OUI.badge("سطح %s" % OUI.fa(lp["level"]), OUI.GOLD))
	if cur != null:
		bf.add_child(OUI.badge(OUI.s(cur.get("name_fa")), cc))
	if OUI.is_guest():
		bf.add_child(OUI.badge("مهمان", OUI.DIM))
	iv.add_child(bf)
	if OUI.s(prof.get("avatar_url")) != "":
		var rp := OUI.tap(OUI.lbl("حذف عکس", OUI.TS_TINY, OUI.DIM), func() -> void:
			await OUI.patch("profiles?id=eq." + OUI.uid(), {"avatar_url": null})
			OUI.profile["avatar_url"] = null
			OUI.toast("عکس حذف شد؛ دیسک فعال نمایش داده می‌شود")
			_render_all())
		rp.custom_minimum_size.y = OUI.px(32)
		iv.add_child(rp)
	h2.add_child(iv)
	v.add_child(h2)
	# bio
	if edit_bio:
		var ta := OUI.text_area("چند کلمه درباره‌ی خودت…", 72)
		ta.text = bio_v
		ta.text_changed.connect(func() -> void:
			if ta.text.length() > 160:
				ta.text = ta.text.substr(0, 160)
			bio_v = ta.text)
		v.add_child(ta)
		var bh := OUI.hbox(OUI.S_S)
		var sb := OUI.btn("ذخیره", _save_bio, "primary", true)
		sb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var cb := OUI.btn("انصراف", func() -> void:
			edit_bio = false
			_render_profile(), "dark", true)
		cb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bh.add_child(sb)
		bh.add_child(cb)
		v.add_child(bh)
	else:
		var bio := OUI.s(prof.get("bio"))
		var bt := OUI.tap(OUI.lbl(bio if bio != "" else "✎ افزودن بیو", OUI.TS_SMALL, Color("#d6e6ff") if bio != "" else OUI.CYAN, "body", HORIZONTAL_ALIGNMENT_RIGHT, true, 3), func() -> void:
			bio_v = OUI.s(OUI.profile.get("bio"))
			edit_bio = true
			_render_profile())
		bt.custom_minimum_size.y = OUI.px(44)
		v.add_child(bt)
	v.add_child(OUI.bar(lp["frac"], OUI.CYAN, OUI.VIOLET, 10))
	v.add_child(OUI.lbl("%s / %s XP تا سطح %s" % [OUI.fa(lp["cur"]), OUI.fa(lp["need"]), OUI.fa(lp["level"] + 1)], OUI.TS_TINY, OUI.DIM, "body", HORIZONTAL_ALIGNMENT_CENTER))
	var sh := OUI.hbox(0)
	for it in [[OUI.fa(rating), "امتیاز"], [OUI.fa(OUI.i(prof.get("arena_points"))), "آرنا"], ["🔥%s" % OUI.fa(OUI.i(prof.get("win_streak"))), "برد پیاپی"], [OUI.fa(played), "بازی آنلاین"]]:
		var sv := OUI.vbox(0)
		sv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sv.add_child(OUI.lbl(it[0], 15, OUI.TEXT, "title", HORIZONTAL_ALIGNMENT_CENTER))
		sv.add_child(OUI.lbl(it[1], OUI.TS_TINY, OUI.DIM, "body", HORIZONTAL_ALIGNMENT_CENTER))
		sh.add_child(sv)
	v.add_child(sh)
	pn2.add_child(v)
	prof_box.add_child(pn2)
	# league card
	if cur != null:
		var lpn := OUI.panel(cc)
		var lh := OUI.hbox(OUI.S_M)
		lh.add_child(OUI.img(OUI.league_tex(cur.get("id")), 52))
		var lv := OUI.vbox(OUI.S_XS)
		lv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lv.add_child(OUI.lbl("لیگ %s" % OUI.s(cur.get("name_fa")), OUI.TS_BODY, cc, "bold"))
		var frac := 1.0
		if nxt != null:
			frac = float(rating - OUI.i(cur.get("min_rating"))) / float(maxi(1, OUI.i(nxt.get("min_rating")) - OUI.i(cur.get("min_rating"))))
		lv.add_child(OUI.bar(frac, cc, OUI.INDIGO, 6))
		lv.add_child(OUI.lbl(("%s امتیاز تا %s" % [OUI.fa(OUI.i(nxt.get("min_rating")) - rating), OUI.s(nxt.get("name_fa"))]) if nxt != null else "بالاترین لیگ!", OUI.TS_TINY, OUI.DIM))
		lh.add_child(lv)
		lpn.add_child(lh)
		prof_box.add_child(OUI.tap(lpn, func() -> void: Nav.go("ranks", {"tab": "leagues"})))
	# xp history
	var th := OUI.vbox(0)
	th.add_child(OUI.lbl("RECENT XP", 9, OUI.CYAN, "head"))
	th.add_child(OUI.lbl("تاریخچه‌ی XP", OUI.TS_H, OUI.TEXT, "title"))
	prof_box.add_child(OUI.margin(th, 0, OUI.S_M, 0, OUI.S_XS))
	var ev_box := OUI.vbox(0)
	prof_box.add_child(ev_box)
	if events == null:
		ev_box.add_child(OUI.spinner())
		_load_events()
	elif (events as Array).is_empty():
		ev_box.add_child(OUI.lbl("هنوز XP آنلاینی نگرفتی؛ یک مسابقه‌ی سریع بزن!", OUI.TS_SMALL, OUI.DIM, "body", HORIZONTAL_ALIGNMENT_CENTER, true, 2))
	else:
		for e in events:
			var eh := OUI.hbox(OUI.S_S)
			eh.custom_minimum_size.y = OUI.px(44)
			var reason := OUI.s(e.get("reason"))
			eh.add_child(OUI.img(OUI.ui2("x_trophy" if reason == "tournament" else ("c_calendar" if reason == "challenge" else "x_star")), 28))
			eh.add_child(OUI.flbl(REASON_FA.get(reason, reason), OUI.TS_SMALL))
			eh.add_child(OUI.lbl(OUI.time_ago(e.get("created_at")), OUI.TS_TINY, OUI.DIM))
			var amt := OUI.i(e.get("amount"))
			var al := OUI.lbl("%s%s XP" % ["+" if amt >= 0 else "", OUI.fa(amt)], OUI.TS_SMALL, OUI.GREEN if amt >= 0 else OUI.RED, "bold", HORIZONTAL_ALIGNMENT_LEFT)
			al.custom_minimum_size.x = OUI.px(64)
			eh.add_child(al)
			ev_box.add_child(eh)
			ev_box.add_child(OUI.divider())


func _load_events() -> void:
	var u := OUI.uid()
	if u == "":
		return
	_last_xp = OUI.i(OUI.profile.get("xp"), -1)
	events = []
	var r: Dictionary = await OUI.get_rows("xp_events?select=id,amount,reason,created_at&user_id=eq.%s&order=created_at.desc&limit=10" % u)
	if not is_inside_tree():
		return
	events = OUI.rows(r)
	_render_profile()


func _save_bio() -> void:
	var b := bio_v.strip_edges().substr(0, 160)
	var r: Dictionary = await OUI.patch("profiles?id=eq." + OUI.uid(), {"bio": b if b != "" else null})
	if not OUI.ok(r):
		OUI.toast(OUI.err(r))
		return
	OUI.profile["bio"] = b if b != "" else null
	edit_bio = false
	OUI.toast("ذخیره شد")
	if is_inside_tree():
		_render_profile()


func _upload() -> void:
	if up_busy:
		return
	up_busy = true
	_render_profile()
	OUI.pick_and_upload("avatars", 512, true, func(r: Dictionary) -> void:
		if r.get("ok", false):
			var pr: Dictionary = await OUI.patch("profiles?id=eq." + OUI.uid(), {"avatar_url": r.get("url")})
			if OUI.ok(pr):
				OUI.profile["avatar_url"] = r.get("url")
				OUI.toast("عکس پروفایل به‌روز شد")
				OUI.buzz("success")
			else:
				OUI.toast(OUI.err(pr))
		elif r.get("unsupported", false):
			_preset_picker()
		elif not r.get("cancelled", false):
			OUI.toast(OUI.s(r.get("error")))
		up_busy = false
		if is_inside_tree():
			_render_all())


## devices without a native image picker: choose one of the free discs as avatar instead
func _preset_picker() -> void:
	var sc := OUI.scroll()
	var v := OUI.vbox(OUI.S_S)
	sc.add_child(OUI.margin(v, OUI.S_L, 0, OUI.S_L, OUI.S_XL))
	v.add_child(OUI.lbl("انتخاب عکس روی این دستگاه ممکن نیست؛ یکی از نشان‌ها را به‌عنوان آواتار انتخاب کن.", OUI.TS_SMALL, OUI.DIM, "body", HORIZONTAL_ALIGNMENT_RIGHT, true, 3))
	var grid := HFlowContainer.new()
	grid.add_theme_constant_override("h_separation", OUI.px(8))
	grid.add_theme_constant_override("v_separation", OUI.px(8))
	var keys: Array = []
	for k in 24:
		keys.append("club%d" % k)
	for k in 24:
		keys.append("nat%d" % k)
	for key in keys:
		var kk: String = key
		var pc := PanelContainer.new()
		pc.custom_minimum_size = Vector2(OUI.px(60), OUI.px(60))
		pc.add_theme_stylebox_override("panel", OUI.sb(Color(0, 0, 0, 0), 14, OUI.LINE, 1, 4))
		pc.add_child(OUI.img(OUI.disc_tex(kk), 48))
		grid.add_child(OUI.tap(pc, func() -> void:
			var r: Dictionary = await OUI.patch("profiles?id=eq." + OUI.uid(), {"avatar": kk, "avatar_url": null})
			if OUI.ok(r):
				OUI.profile["avatar"] = kk
				OUI.profile["avatar_url"] = null
				OUI.ebus().profile_changed.emit(OUI.profile)
				OUI.toast("آواتار به‌روز شد")
				Nav.close_sheet()
			else:
				OUI.toast(OUI.err(r))))
	v.add_child(grid)
	OUI.open_sheet("انتخاب آواتار", "AVATAR", sc, OUI.CYAN, 0.7)


# ================================================================ online entry card (Home / Play)
static func make_online_card() -> Control:
	return OnlineCard.new()


class OnlineCard extends VBoxContainer:
	var info_l: Label
	var card: PanelContainer
	var shine: ColorRect
	func _ready() -> void:
		layout_direction = Control.LAYOUT_DIRECTION_RTL
		add_theme_constant_override("separation", OUI.px(8))
		card = PanelContainer.new()
		var st := OUI.sb(Color("#1b2f8f"), 24, Color(160 / 255.0, 220 / 255.0, 1, 0.55), 1.5)
		st.shadow_color = Color(OUI.VIOLET, 0.6)
		st.shadow_size = OUI.px(14)
		st.content_margin_left = OUI.px(14)
		st.content_margin_right = OUI.px(14)
		card.add_theme_stylebox_override("panel", st)
		card.custom_minimum_size.y = OUI.px(112)
		card.clip_contents = true
		var grad := TextureRect.new()
		var g := Gradient.new()
		g.set_color(0, Color("#3a1d8a"))
		g.set_color(1, Color("#0a5a8a"))
		g.add_point(0.5, Color("#1b2f8f"))
		var gt := GradientTexture2D.new()
		gt.gradient = g
		gt.fill_from = Vector2(0, 0)
		gt.fill_to = Vector2(1, 1)
		grad.texture = gt
		grad.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		grad.stretch_mode = TextureRect.STRETCH_SCALE
		grad.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var clip := Control.new()
		clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		clip.clip_contents = true
		clip.add_child(grad)
		grad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		shine = ColorRect.new()
		shine.color = Color(1, 1, 1, 0.22)
		shine.size = Vector2(OUI.px(50), OUI.px(220))
		shine.rotation = deg_to_rad(20)
		shine.position = Vector2(-OUI.px(120), -OUI.px(40))
		shine.mouse_filter = Control.MOUSE_FILTER_IGNORE
		clip.add_child(shine)
		card.add_child(clip)
		var h := OUI.hbox(8)
		h.add_child(OUI.img(OUI.ui("portal_globe"), 84))
		var v := OUI.vbox(2)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.alignment = BoxContainer.ALIGNMENT_CENTER
		var th := OUI.hbox(8)
		var tl := OUI.lbl("آنلاین", 24, Color.WHITE, "title")
		tl.add_theme_color_override("font_shadow_color", Color(OUI.CYAN, 0.8))
		tl.add_theme_constant_override("shadow_outline_size", OUI.px(6))
		th.add_child(tl)
		var live := PanelContainer.new()
		var ls := OUI.sb(OUI.RED, 9)
		ls.content_margin_left = OUI.px(6)
		ls.content_margin_right = OUI.px(6)
		live.add_theme_stylebox_override("panel", ls)
		live.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var lh := OUI.hbox(4)
		lh.layout_direction = Control.LAYOUT_DIRECTION_LTR
		var dot := ColorRect.new()
		dot.color = Color.WHITE
		dot.custom_minimum_size = Vector2(OUI.px(6), OUI.px(6))
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		lh.add_child(dot)
		lh.add_child(OUI.lbl("LIVE", 9, Color.WHITE, "head"))
		live.add_child(lh)
		th.add_child(live)
		th.add_child(OUI.expand())
		v.add_child(th)
		v.add_child(OUI.lbl("مسابقه با بازیکن‌های واقعی · ۱ به ۱، ۲ به ۲، ۳ به ۳", 12, Color("#d6e6ff"), "body", HORIZONTAL_ALIGNMENT_RIGHT, true, 2))
		info_l = OUI.lbl("", 11, OUI.GOLD, "bold")
		v.add_child(info_l)
		h.add_child(v)
		card.add_child(h)
		var t := OUI.tap(card, func() -> void:
			OUI.buzz("medium")
			Nav.go("hub", {}))
		add_child(t)
		var links := OUI.hbox(8)
		for it in [["arena", "آرنا", "x_crown", {}], ["tournaments", "تورنمنت", "x_trophy", {}], ["ranks", "لیگ", "x_medal", {"tab": "leagues"}], ["challenges", "چالش", "c_calendar", {}]]:
			var pc := PanelContainer.new()
			pc.add_theme_stylebox_override("panel", OUI.sb(Color(10 / 255.0, 16 / 255.0, 44 / 255.0, 0.85), 14, OUI.LINE, 1))
			pc.custom_minimum_size.y = OUI.px(44)
			var ph := OUI.hbox(4, BoxContainer.ALIGNMENT_CENTER)
			ph.add_child(OUI.img(OUI.ui2(it[2]), 26))
			ph.add_child(OUI.lbl(it[1], 11, OUI.TEXT, "bold"))
			pc.add_child(ph)
			var target: String = it[0]
			var prm: Dictionary = it[3]
			var lb := OUI.tap(pc, func() -> void: Nav.go(target, prm))
			lb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			links.add_child(lb)
		add_child(links)
		OUI.boot()
		OUI.ebus().profile_changed.connect(_on_profile)
		_on_profile(OUI.profile)
		var tw := create_tween().set_loops()
		tw.tween_interval(1.8)
		tw.tween_property(shine, "position:x", float(OUI.px(500)), 1.3).from(float(-OUI.px(120))).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
	func _on_profile(p: Dictionary) -> void:
		if not is_instance_valid(info_l):
			return
		info_l.visible = not p.is_empty()
		info_l.text = "امتیاز %s · 💎 %s" % [OUI.fa(OUI.i(p.get("rating"))), OUI.fa(OUI.i(p.get("gems")))]


# ================================================================ password recovery (RN RecoveryModal)
## Opened when an e-mail recovery link signs the user in (Supa.recovery / PASSWORD_RECOVERY).
static func show_recovery() -> void:
	var st := {"p1": "", "p2": "", "busy": false}
	var v := OUI.vbox(OUI.S_S)
	var m := OUI.margin(v, OUI.S_L, OUI.S_L, OUI.S_L, OUI.S_L)
	v.add_child(OUI.lbl("رمز عبور جدید", 20, OUI.TEXT, "title", HORIZONTAL_ALIGNMENT_CENTER))
	var f1 := OUI.line_edit("رمز جدید", 72, true, true)
	f1.text_changed.connect(func(t: String) -> void: st["p1"] = t)
	v.add_child(f1)
	var f2 := OUI.line_edit("تکرار رمز جدید", 72, true, true)
	f2.text_changed.connect(func(t: String) -> void: st["p2"] = t)
	v.add_child(f2)
	var el := OUI.lbl("", OUI.TS_SMALL, OUI.RED, "body", HORIZONTAL_ALIGNMENT_RIGHT, true, 3)
	el.visible = false
	v.add_child(el)
	var save := OUI.btn("ذخیره", Callable(), "primary")
	save.pressed.connect(func() -> void:
		if st["busy"]:
			return
		var p1: String = st["p1"]
		if p1.length() < 6:
			el.text = "رمز عبور حداقل ۶ کاراکتر"
			el.visible = true
			return
		if p1 != st["p2"]:
			el.text = "تکرار رمز یکسان نیست"
			el.visible = true
			return
		st["busy"] = true
		save.text = "…"
		var r: Dictionary = await Supa.set_new_password(p1)
		st["busy"] = false
		if not is_instance_valid(save):
			return
		save.text = "ذخیره"
		if not OUI.ok(r):
			el.text = OUI.err(r)
			el.visible = true
			return
		Nav.toast("رمز عبور تغییر کرد", "ok")
		Nav.close_modal())
	v.add_child(save)
	v.add_child(OUI.btn("بعداً", func() -> void:
		Supa.recovery = false
		Nav.close_modal(), "dark", true))
	Nav.modal(m, OUI.CYAN, 0.86)
