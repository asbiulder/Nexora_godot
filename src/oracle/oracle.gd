class_name OracleScreen
extends Control
## ORACLE panel (port of the OraclePanel + smart actions of RN src/oracle/Oracle.tsx):
## chat-like Q&A over the local knowledge base (OracleKB) + smart actions (quick match, claim rewards,
## challenges, disc advice, stats, navigation). Screen name "oracle". params: {ask?: String}
## OracleScreen.run_action(id) is shared with the floating bubble (OracleCoach).
## RPC/tables: get_daily_challenges, claim_challenge, claim_season_reward, leagues, discs, inventory.

var msgs: Array = []
var busy := false
var list: VBoxContainer
var sc: ScrollContainer
var hero: OracleCoach.Sprite2Fade
var txt: LineEdit
var send_b: Button
var params: Dictionary = {}


func setup(p: Dictionary) -> void:
	params = p


func _ready() -> void:
	Nav.chrome(false)
	OUI.boot()
	var pg := OUI.page(self, "اوراکل", "ORACLE · ASSISTANT", func() -> void: Nav.back(), null, OUI.CYAN)
	var root: VBoxContainer = pg["root"]
	var old_sc: ScrollContainer = pg["scroll"]
	root.remove_child(old_sc)
	old_sc.queue_free()
	# hero
	var hh := CenterContainer.new()
	hh.custom_minimum_size.y = OUI.px(120)
	var glow := ColorRect.new()
	glow.color = Color(OUI.CYAN, 0.25)
	glow.custom_minimum_size = Vector2(OUI.px(120), OUI.px(10))
	var hv := VBoxContainer.new()
	hv.add_theme_constant_override("separation", -OUI.px(14))
	hero = OracleCoach.Sprite2Fade.new(110, "wave", true)
	hv.add_child(hero)
	glow.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	hv.add_child(glow)
	hh.add_child(hv)
	root.add_child(hh)
	var bob := hero.create_tween().set_loops()
	bob.tween_property(hero, "position:y", -OUI.px(4), 1.1).as_relative().set_trans(Tween.TRANS_SINE)
	bob.tween_property(hero, "position:y", OUI.px(4), 1.1).as_relative().set_trans(Tween.TRANS_SINE)
	# messages
	sc = OUI.scroll()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(sc)
	list = OUI.vbox(OUI.S_S)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(OUI.margin(list, OUI.S_M, OUI.S_S, OUI.S_M, OUI.S_S))
	# question chips
	var qs := OUI.hscroll()
	qs.custom_minimum_size.y = OUI.px(42)
	var qh := OUI.hbox(6)
	for q in OracleKB.QUESTION_CHIPS:
		var qq: String = q
		qh.add_child(OUI.pill(qq, func() -> void: ask(qq), OUI.CYAN, 0, 34))
	qs.add_child(qh)
	root.add_child(OUI.margin(qs, OUI.S_M, 0, OUI.S_M, 6))
	# input
	var row := OUI.hbox(8)
	row.layout_direction = Control.LAYOUT_DIRECTION_LTR
	send_b = OUI.pill("➤", func() -> void: ask(txt.text), OUI.CYAN, 46, 46)
	row.add_child(send_b)
	txt = OUI.line_edit("از اوراکل بپرس…", 200, false, false, 46)
	txt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	txt.text_submitted.connect(func(t: String) -> void: ask(t))
	row.add_child(txt)
	var ip := PanelContainer.new()
	ip.add_theme_stylebox_override("panel", OUI.sb(Color(4 / 255.0, 8 / 255.0, 24 / 255.0, 0.96), 0, OUI.LINE, 1, 10))
	ip.add_child(row)
	root.add_child(ip)
	_push({"from": "oracle", "text": "سلام کاپیتان! 👋 هر سؤالی درباره‌ی بازی داری بپرس یا یکی از کارهای سریع رو انتخاب کن.", "mood": "wave", "actions": OracleKB.SUGGESTIONS})
	var a := OUI.s(params.get("ask", ""))
	if a != "":
		ask(a)


func leave() -> void:
	Nav.chrome(true)


func on_back() -> bool:
	return false


func _push(m: Dictionary) -> void:
	msgs.append(m)
	if m.get("from") == "oracle":
		hero.set_mood(str(m.get("mood", "idle")))
	var me: bool = m.get("from") == "me"
	var outer := HBoxContainer.new()
	outer.layout_direction = Control.LAYOUT_DIRECTION_LTR
	outer.alignment = BoxContainer.ALIGNMENT_BEGIN if me else BoxContainer.ALIGNMENT_END
	var pc := PanelContainer.new()
	var st := OUI.sb(Color(79 / 255.0, 227 / 255.0, 1, 0.16) if me else Color(20 / 255.0, 30 / 255.0, 70 / 255.0, 0.94), 16, Color(79 / 255.0, 227 / 255.0, 1, 0.35) if me else OUI.LINE, 1)
	st.content_margin_left = OUI.px(12)
	st.content_margin_right = OUI.px(12)
	st.content_margin_top = OUI.px(8)
	st.content_margin_bottom = OUI.px(8)
	if me:
		st.corner_radius_bottom_left = OUI.px(4)
	else:
		st.corner_radius_bottom_right = OUI.px(4)
	pc.add_theme_stylebox_override("panel", st)
	var v := OUI.vbox(8)
	v.layout_direction = Control.LAYOUT_DIRECTION_RTL
	var text := str(m.get("text", ""))
	var l := OUI.lbl(text, 13, OUI.TEXT, "body", HORIZONTAL_ALIGNMENT_RIGHT, true, 0)
	var maxw: float = sc.size.x * 0.84 if sc.size.x > 0 else float(OUI.px(330))
	var w := 0.0
	for line in text.split("\n"):
		w = maxf(w, l.get_theme_font("font").get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, l.get_theme_font_size("font_size")).x)
	l.custom_minimum_size.x = clampf(w + 8, OUI.px(40), maxw)
	v.add_child(l)
	var acts: Array = m.get("actions", [])
	if not acts.is_empty():
		var fl := HFlowContainer.new()
		fl.custom_minimum_size.x = l.custom_minimum_size.x
		fl.add_theme_constant_override("h_separation", 6)
		fl.add_theme_constant_override("v_separation", 6)
		for aid in acts:
			var a_id := str(aid)
			fl.add_child(OUI.pill(str(OracleKB.ACTION_LABEL.get(a_id, a_id)), func() -> void: _do_action(a_id), OUI.CYAN, 0, 34))
		v.add_child(fl)
	pc.add_child(v)
	outer.add_child(pc)
	list.add_child(outer)
	OUI.fade_in(outer, 0.18)
	_scroll_end()


func _scroll_end() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if is_instance_valid(sc):
		sc.scroll_vertical = int(sc.get_v_scroll_bar().max_value)


func _set_busy(b: bool) -> void:
	busy = b
	if is_instance_valid(send_b):
		send_b.text = "…" if b else "➤"


func _do_action(a: String) -> void:
	if busy:
		return
	_set_busy(true)
	_push({"from": "me", "text": str(OracleKB.ACTION_LABEL.get(a, a))})
	var r: Dictionary = await run_action(a)
	if not is_inside_tree():
		return
	_set_busy(false)
	if not r.is_empty():
		r["from"] = "oracle"
		_push(r)


func ask(q: String) -> void:
	var t := q.strip_edges()
	if t == "" or busy:
		return
	txt.text = ""
	_push({"from": "me", "text": t})
	var res := OracleKB.match_intent(t)
	var action := str(res.get("action", ""))
	if action != "":
		_set_busy(true)
		var r: Dictionary = await run_action(action)
		if not is_inside_tree():
			return
		_set_busy(false)
		if not r.is_empty():
			r["from"] = "oracle"
			_push(r)
		return
	var it: Variant = res.get("intent")
	if it is Dictionary:
		_push({"from": "oracle", "text": it["answer"], "mood": it["mood"], "actions": it.get("actions", [])})
		OUI.sfx("chat")
		return
	_push({"from": "oracle", "text": "هممم… این رو متوجه نشدم 🤔 می‌تونی دربار‌ه‌ی شوت، الماس، دیسک‌ها، تورنمنت، آرنا، باشگاه یا حساب بپرسی، یا یکی از این‌ها رو بزنی:", "mood": "confused", "actions": OracleKB.SUGGESTIONS})


# ================================================================ smart actions
static func _need_online() -> bool:
	if OUI.uid() != "":
		return true
	var u: String = await OUI.ensure()
	return u != ""


## -> {text, mood, actions?} or {} ; navigation actions leave the panel
static func run_action(id: String) -> Dictionary:
	match id:
		"quick":
			Nav.go("hub", {"quick": "1v1"})
			return {"text": "دارم یک حریف هم‌سطح برات پیدا می‌کنم… 🔭", "mood": "spin"}
		"shop":
			Nav.go("shop", {})
			return {"text": "فروشگاه باز شد! 🛍", "mood": "happy"}
		"tours":
			Nav.go("tournaments", {})
			return {"text": "بریم سراغ تورنمنت‌ها! 🏆", "mood": "excited"}
		"clubs", "messages":
			Nav.go("social", {"tab": "club" if id == "clubs" else "msg"})
			return {"text": "باشگاه‌ها در تب «اجتماعی» هستن 🛡" if id == "clubs" else "پیام‌هات این‌جاست 💬", "mood": "curious"}
		"online":
			Nav.go("hub", {})
			return {"text": "به بخش آنلاین خوش اومدی! 🌐", "mood": "wave"}
		"arena":
			Nav.go("arena", {})
			return {"text": "آرنا منتظرته! ⚔️", "mood": "excited"}
		"leagues":
			Nav.go("ranks", {"tab": "leagues"})
			return {"text": "لیگ‌ها و جایزه‌های فصل 🥇", "mood": "present"}
		"team":
			Nav.go("team", {})
			return {"text": "تیم و دیسک‌هات این‌جاست ⚽", "mood": "present"}
		"settings":
			Nav.go("settings", {})
			return {"text": "تنظیمات باز شد ⚙️", "mood": "neutral"}
		"challenges":
			if not await _need_online():
				return {"text": "برای چالش‌ها باید آنلاین باشی 📶", "mood": "alert"}
			var r: Dictionary = await ChallengesScreen.load_challenges()
			if not r["ok"]:
				return {"text": r["error"], "mood": "alert"}
			var lines: Array = []
			var any_ready := false
			for c in r["list"]:
				var done: bool = OUI.i(c.get("progress")) >= OUI.i(c.get("target"), 1)
				var cl := bool(c.get("claimed", false))
				if done and not cl:
					any_ready = true
				lines.append("%s %s — %s/%s (💎%s)" % ["✅" if cl else ("🎁" if done else "▫️"), OUI.s(c.get("title_fa")), OUI.fa(mini(OUI.i(c.get("progress")), OUI.i(c.get("target"), 1))), OUI.fa(OUI.i(c.get("target"), 1)), OUI.fa(OUI.i(c.get("reward_gems")))])
			return {"text": "چالش‌های امروز:\n" + "\n".join(lines), "mood": "present", "actions": ["claim"] if any_ready else []}
		"claim":
			if not await _need_online():
				return {"text": "برای گرفتن جایزه باید آنلاین باشی 📶", "mood": "alert"}
			var gems := 0
			var xp := 0
			var n := 0
			var r2: Dictionary = await ChallengesScreen.load_challenges()
			if r2["ok"]:
				for c in r2["list"]:
					if OUI.i(c.get("progress")) >= OUI.i(c.get("target"), 1) and not bool(c.get("claimed", false)):
						var cr: Dictionary = await Supa.call_rpc("claim_challenge", {"p_def": OUI.s(c.get("def_id"))})
						if OUI.ok(cr):
							gems += OUI.i(OUI.d(cr.get("data")).get("gems"))
							xp += OUI.i(OUI.d(cr.get("data")).get("xp"))
							n += 1
			var season := 0
			var sr: Dictionary = await Supa.call_rpc("claim_season_reward", {})
			if OUI.ok(sr):
				season = OUI.i(OUI.d(sr.get("data")).get("gems"))
				gems += season
			if n == 0 and season == 0:
				return {"text": "فعلاً جایزه‌ی آماده‌ای نداری. چالش‌های امروز رو کامل کن تا الماس بگیری! 💪", "mood": "calm", "actions": ["challenges"]}
			OUI.sfx("win")
			OUI.buzz("success")
			OUI.refresh_profile()
			var parts := ""
			if n > 0:
				parts += "%s چالش" % OUI.fa(n)
			if n > 0 and season > 0:
				parts += " و "
			if season > 0:
				parts += "جایزه‌ی فصل"
			return {"text": "گرفتمشون! 🎉 %s: +%s الماس%s" % [parts, OUI.fa(gems), (" · +%s XP" % OUI.fa(xp)) if xp > 0 else ""], "mood": "joy"}
		"disc":
			return await _disc_advice()
		"stats":
			return await _stats()
	return {}


static func _disc_advice() -> Dictionary:
	var dz: Variant = Supa.discs
	if dz == null:
		return {"text": "کاتالوگ دیسک‌ها هنوز بارگذاری نشده؛ یک لحظه بعد دوباره بپرس.", "mood": "confused"}
	var cat_d: Dictionary = dz.catalog if dz.catalog is Dictionary else {}
	if cat_d.is_empty():
		dz.load_catalog()
		return {"text": "کاتالوگ دیسک‌ها هنوز بارگذاری نشده؛ یک لحظه بعد دوباره بپرس.", "mood": "confused"}
	var cat: Array = cat_d.values()
	var gems := OUI.i(OUI.profile.get("gems"))
	var score := func(x: Dictionary) -> int: return OUI.i(x.get("power")) + OUI.i(x.get("accuracy"))
	var afford: Array = cat.filter(func(x: Variant) -> bool: return not dz.has(OUI.s(x.get("id"))) and OUI.i(x.get("price_gems")) > 0 and OUI.i(x.get("price_gems")) <= gems)
	afford.sort_custom(func(x: Variant, y: Variant) -> bool:
		if score.call(x) != score.call(y):
			return score.call(x) > score.call(y)
		return OUI.i(x.get("price_gems")) < OUI.i(y.get("price_gems")))
	var owned: Array = cat.filter(func(x: Variant) -> bool: return dz.has(OUI.s(x.get("id"))))
	owned.sort_custom(func(x: Variant, y: Variant) -> bool: return score.call(x) > score.call(y))
	var nxt: Array = cat.filter(func(x: Variant) -> bool: return not dz.has(OUI.s(x.get("id"))) and OUI.i(x.get("price_gems")) > gems)
	nxt.sort_custom(func(x: Variant, y: Variant) -> bool:
		if OUI.i(x.get("price_gems")) != OUI.i(y.get("price_gems")):
			return OUI.i(x.get("price_gems")) < OUI.i(y.get("price_gems"))
		return score.call(x) > score.call(y))
	var lines: Array = []
	if not afford.is_empty():
		var a: Dictionary = afford[0]
		lines.append("با %s الماست بهترین انتخاب «%s» است: قدرت %s، دقت %s به قیمت 💎%s." % [OUI.fa(gems), OUI.s(a.get("name")), OUI.fa(OUI.i(a.get("power"))), OUI.fa(OUI.i(a.get("accuracy"))), OUI.fa(OUI.i(a.get("price_gems")))])
	if not owned.is_empty():
		var o: Dictionary = owned[0]
		var team := OUI.s((Store.p as Dictionary).get("team", "")) if Store.p is Dictionary else ""
		lines.append("بهترین دیسکی که الان داری «%s» است (قدرت %s، دقت %s)%s" % [OUI.s(o.get("name")), OUI.fa(OUI.i(o.get("power"))), OUI.fa(OUI.i(o.get("accuracy"))), " — مجهزش کن!" if team != OUI.s(o.get("id")) else " و فعاله ✅"])
	if afford.is_empty() and not nxt.is_empty():
		var nx: Dictionary = nxt[0]
		lines.append("هدف بعدی: «%s» با 💎%s؛ %s الماس دیگه لازم داری." % [OUI.s(nx.get("name")), OUI.fa(OUI.i(nx.get("price_gems"))), OUI.fa(OUI.i(nx.get("price_gems")) - gems)])
	return {"text": "\n".join(lines) if not lines.is_empty() else "همه‌ی دیسک‌ها رو داری، اسطوره! 🤯", "mood": "idea", "actions": ["team", "shop"]}


static func _stats() -> Dictionary:
	var pr := OUI.profile
	if not pr.is_empty():
		var wins := OUI.i(pr.get("wins"))
		var pl := wins + OUI.i(pr.get("losses")) + OUI.i(pr.get("draws"))
		var wr := int(round(float(wins) / pl * 100.0)) if pl > 0 else 0
		var lp := OUI.level_progress(OUI.i(pr.get("xp")))
		var lg: Array = await OUI.load_leagues()
		var rating := OUI.i(pr.get("rating"))
		var nx: Variant = null
		var sorted := lg.duplicate()
		sorted.sort_custom(func(x: Variant, y: Variant) -> bool: return OUI.i(x.get("min_rating")) < OUI.i(y.get("min_rating")))
		for l in sorted:
			if OUI.i(l.get("min_rating")) > rating:
				nx = l
				break
		var tail := (" — %s تا لیگ %s" % [OUI.fa(OUI.i(nx.get("min_rating")) - rating), OUI.s(nx.get("name_fa"))]) if nx != null else " — بالاترین لیگ!"
		var text := "📊 %s\n• سطح %s — %s XP تا سطح بعد\n• %s بازی آنلاین، درصد برد %s٪\n• برد پیاپی %s (رکورد %s)\n• امتیاز %s%s\n• آرنا %s · 💎 %s" % [OUI.s(pr.get("username")), OUI.fa(lp["level"]), OUI.fa(lp["need"] - lp["cur"]), OUI.fa(pl), OUI.fa(wr), OUI.fa(OUI.i(pr.get("win_streak"))), OUI.fa(OUI.i(pr.get("best_streak"))), OUI.fa(rating), tail, OUI.fa(OUI.i(pr.get("arena_points"))), OUI.fa(OUI.i(pr.get("gems")))]
		return {"text": text, "mood": "present", "actions": ["leagues"]}
	var p: Dictionary = Store.p if Store.p is Dictionary else {}
	var played := OUI.i(p.get("played"))
	var wr2 := int(round(float(OUI.i(p.get("wins"))) / played * 100.0)) if played > 0 else 0
	# local (offline) level: store.ts level() — need starts at 100 and grows ×1.25
	var l2 := 1
	var need := 100
	var x := OUI.i(p.get("xp"))
	while x >= need:
		x -= need
		l2 += 1
		need = int(round(need * 1.25))
	return {"text": "📊 آمار آفلاین\n• سطح %s\n• %s بازی، درصد برد %s٪\n• بهترین برد پیاپی %s\nبرای آمار آنلاین وارد بخش آنلاین شو." % [OUI.fa(l2), OUI.fa(played), OUI.fa(wr2), OUI.fa(OUI.i(p.get("bestStreak")))], "mood": "present", "actions": ["online"]}
