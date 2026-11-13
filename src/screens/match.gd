extends Control
## Offline match screen — port of src/screens/Match.tsx + App.tsx onFinish (rewards / progression).
## Params = Launch dict from Data.build_launch: {cfg, teams:[teamDict, teamDict], names:[a, b], mode, stage}
## Test-only extras: bots:bool (AI plays both sides), steps:int (engine updates per frame), seed:int.
## Nav kind "fs": no chrome, no backdrop. Android back toggles the pause menu (on_back).

signal match_event(ev: Dictionary)
signal finished(params: Dictionary)

const D := preload("res://src/core/data.gd")
const U := 2.6                      # RN dp -> px
const COACH_PATH := "res://src/oracle/coach.gd"
const TEAM_COL := [Color("#39d5ff"), Color("#ff4a5a")]
const BAR_COL := [[Color("#39d5ff"), Color("#3b82ff")], [Color("#ff4a5a"), Color("#ff8a3a")]]

var launch: Dictionary = {}
var cfg: Dictionary = {}
var teams: Array = []
var names: Array = ["", ""]
var mode := "quick"
var eng: NxEngine
var view: MatchView
var paused := false
var ended := false
var bots := false
var steps := 1
var co := {"shot_team": -1, "touched": false, "last_tip": -100000, "misses": 0, "reminded": -1, "turn_n": 0}
var _coach = null                   # OracleCoach script (loaded dynamically: owned by another worker)
var _quality := "high"
var _dragging := false

# HUD nodes
var touch: Control
var hud: Control
var pause_btn: Control
var board: NxGlass
var score_l: Label
var clock_l: Label
var side_logo: Array = [null, null]
var side_name: Array = [null, null]
var side_turn: Array = [null, null]
var turn_bar: _TurnBar
var banner: Control
var banner_img: TextureRect
var banner_t: Label
var banner_s: Label
var _banner_tw: Tween
var pause_layer: Control
var _hud_state := {}

# ------------------------------------------------------------------ setup
func setup(params: Dictionary) -> void:
	launch = params
	cfg = (params.get("cfg", {}) as Dictionary).duplicate(true)
	teams = params.get("teams", [])
	if teams.size() < 2:
		var ids: Array = cfg.get("teams", ["club0", "club1"])
		teams = [D.team_by_id(String(ids[0])), D.team_by_id(String(ids[1]))]
	var nm = params.get("names", null)
	if nm is Array and nm.size() >= 2: names = [String(nm[0]), String(nm[1])]
	else: names = [String(teams[0].get("name", "")), String(teams[1].get("name", ""))]
	mode = String(params.get("mode", "quick"))
	bots = bool(params.get("bots", false))
	steps = maxi(1, int(params.get("steps", 1)))
	if params.has("seed"): cfg["seed"] = int(params.seed)
	if not cfg.has("teams"): cfg["teams"] = [String(teams[0].get("id", "club0")), String(teams[1].get("id", "club1"))]

func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bgc := ColorRect.new()
	bgc.color = Color("#02040c")
	bgc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bgc.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bgc)
	eng = NxEngine.new(cfg)
	if bots: eng.ai_teams = [true, true]
	_quality = String(UD.pv("quality", "high"))
	view = MatchView.new()
	view.setup(eng, {"ball": int(cfg.get("ball", 0)), "teams": cfg.get("teams"), "quality": _quality})
	add_child(view)
	touch = Control.new()
	touch.name = "Touch"
	touch.mouse_filter = Control.MOUSE_FILTER_STOP
	touch.set_anchors_preset(Control.PRESET_FULL_RECT)
	touch.gui_input.connect(_on_touch)
	add_child(touch)
	_build_hud()
	_build_banner()
	resized.connect(_layout)
	_layout()
	_coach = _load_coach()
	_coach_call("set_scene", ["match"])
	var sfx := UD.node("Sfx")
	if sfx:
		sfx.play("whistle")
		sfx.crowd(true)
		sfx.menu_music(false)
	var st := UD.node("Store")
	if st and st.has_signal("changed"): st.connect("changed", _on_store)

func leave() -> void:
	var sfx := UD.node("Sfx")
	if sfx: sfx.crowd(false)
	_coach_call("set_scene", ["ui"])
	set_process(false)

func _exit_tree() -> void:
	var sfx := UD.node("Sfx")
	if sfx: sfx.crowd(false)

func on_back() -> bool:
	if ended: return true
	_set_paused(not paused)
	return true

# ------------------------------------------------------------------ coach (OracleCoach, optional)
func _load_coach():
	if not ResourceLoader.exists(COACH_PATH): return null
	var s = load(COACH_PATH)
	if s is GDScript and (s as GDScript).can_instantiate(): return s
	return null

func _coach_call(m: String, args: Array) -> void:
	if _coach == null: return
	if not (_coach as GDScript).has_method(m): return
	_coach.callv(m, args)

func _coach_miss(power: float, misses: int) -> String:
	if _coach == null or not (_coach as GDScript).has_method("coach_miss"): return ""
	return String(_coach.coach_miss(power, misses))

# ------------------------------------------------------------------ layout
func _top() -> float: return NX.safe_top

func _layout() -> void:
	if view == null or size.x <= 0: return
	view.fit(size, _top() + 86 * U, NX.safe_bottom + 22 * U)
	hud.position = Vector2(10 * U, _top() + 8 * U)
	hud.size = Vector2(size.x - 20 * U, 60 * U)
	turn_bar.position = Vector2(60 * U, _top() + 76 * U)
	turn_bar.size = Vector2(size.x - 72 * U, 4 * U)
	banner.size = Vector2(size.x, 120 * U)
	banner.position = Vector2(0, size.y * 0.38 - 30 * U)
	banner.pivot_offset = Vector2(size.x * 0.5, 40 * U)
	if pause_layer: pause_layer.size = size

# ------------------------------------------------------------------ HUD
func _build_hud() -> void:
	hud = Control.new()
	hud.name = "Hud"
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hud)
	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.add_theme_constant_override("separation", int(8 * U))
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(row)
	# pause button (RN: 40dp rounded square, "II")
	var pb := PanelContainer.new()
	pb.custom_minimum_size = Vector2(40 * U, 40 * U)
	pb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pb.add_theme_stylebox_override("panel", NX.box(Color(8 / 255.0, 12 / 255.0, 34 / 255.0, 0.85), int(12 * U), 3, NX.LINE))
	var pl := Kit.title("II", int(14 * U), NX.TEXT)
	pl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	pb.add_child(pl)
	Kit.tap(pb, func(): _set_paused(true), 0.9)
	pause_btn = pb
	row.add_child(pb)
	board = Kit.glass(TEAM_COL[0], false)
	board.set_pad(8 * U, 0)
	board.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(board)
	var b := HBoxContainer.new()
	b.add_theme_constant_override("separation", int(4 * U))
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	board.add_child(b)
	b.add_child(_side(0))
	var mid := VBoxContainer.new()
	mid.alignment = BoxContainer.ALIGNMENT_CENTER
	mid.add_theme_constant_override("separation", -6)
	mid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mid.custom_minimum_size.x = 92 * U
	score_l = Kit.title("0 : 0", int(26 * U), Color.WHITE)
	score_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	Kit.glow_text(score_l, NX.CYAN, 10)
	mid.add_child(score_l)
	clock_l = Kit.caps("", int(9 * U), NX.DIM, 5)
	clock_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mid.add_child(clock_l)
	b.add_child(mid)
	b.add_child(_side(1))
	turn_bar = _TurnBar.new()
	turn_bar.visible = float(cfg.get("turn_time", 15)) > 0
	add_child(turn_bar)

func _side(i: int) -> Control:
	var h := HBoxContainer.new()
	h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_theme_constant_override("separation", int(6 * U))
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if i == 1: h.layout_direction = Control.LAYOUT_DIRECTION_RTL
	var logo := Panel.new()
	logo.custom_minimum_size = Vector2(40 * U, 40 * U)
	logo.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	logo.add_theme_stylebox_override("panel", _logo_box(i, false))
	var t := Kit.round_img(D.team_tex(String(teams[i].get("id", "club0"))), 34 * U)
	t.position = Vector2(3 * U, 3 * U)
	logo.add_child(t)
	h.add_child(logo)
	side_logo[i] = logo
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", -4)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var n := Kit.label(names[i], int(12 * U), NX.DIM, true)
	n.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	n.clip_text = true
	n.custom_minimum_size.x = 20
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if i == 0 else HORIZONTAL_ALIGNMENT_RIGHT
	col.add_child(n)
	side_name[i] = n
	var tl := Kit.label("نوبت توئه", int(8 * U), NX.hdr(TEAM_COL[i], 1.3), true)
	tl.horizontal_alignment = n.horizontal_alignment
	tl.modulate.a = 0.0
	col.add_child(tl)
	side_turn[i] = tl
	h.add_child(col)
	return h

func _logo_box(i: int, on: bool) -> StyleBoxFlat:
	var c: Color = TEAM_COL[i]
	var sb := NX.box(Color("#050816"), int(20 * U), 5, NX.hdr(c, 1.4) if on else Color(1, 1, 1, 0.15), 26 if on else 0, Color(c.r, c.g, c.b, 0.85))
	return sb

func _refresh_hud(force := false) -> void:
	var mt := float(cfg.get("match_time", 0))
	var tt := float(cfg.get("turn_time", 15))
	var clock := ""
	if mt > 0:
		if eng.sudden: clock = "گل طلایی"
		else:
			var m := maxi(0, int(ceil(eng.mleft)))
			clock = "%d:%02d" % [m / 60, m % 60]
	else:
		clock = "تا %d گل" % int(cfg.get("limit", 3))
	var tl := maxf(0.0, eng.tleft / tt) if (tt > 0 and eng.phase == "aim") else 1.0
	var s := {"s0": eng.score[0], "s1": eng.score[1], "turn": eng.turn, "clock": clock, "sudden": eng.sudden}
	if force or s != _hud_state:
		var turn_changed: bool = force or int(_hud_state.get("turn", -1)) != eng.turn
		var score_changed: bool = not force and (int(_hud_state.get("s0", 0)) != eng.score[0] or int(_hud_state.get("s1", 0)) != eng.score[1])
		_hud_state = s
		score_l.text = "%d : %d" % [eng.score[0], eng.score[1]]
		if clock_l.text != clock:
			# Persian text needs the Vazirmatn label, Latin the Orbitron caption
			_set_clock(clock, eng.sudden)
		if turn_changed: _on_turn_hud()
		if score_changed:
			score_l.pivot_offset = score_l.size * 0.5
			var tw := score_l.create_tween()
			tw.tween_property(score_l, "scale", Vector2(1.35, 1.35), 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			tw.tween_property(score_l, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	turn_bar.set_state(tl, eng.turn)

func _set_clock(text: String, sudden: bool) -> void:
	var col := NX.hdr(NX.GOLD, 1.3) if sudden else NX.DIM
	var parent := clock_l.get_parent()
	var idx := clock_l.get_index()
	var nl: Label
	if NX.is_fa(text): nl = Kit.label(text, int(9 * U * 1.2), col, true)
	else: nl = Kit.caps(text, int(9 * U), col, 5)
	nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.remove_child(clock_l)
	clock_l.queue_free()
	parent.add_child(nl)
	parent.move_child(nl, idx)
	clock_l = nl

func _on_turn_hud() -> void:
	var t := eng.turn
	board.accent = TEAM_COL[t]
	var sb := board.get_theme_stylebox("panel") as StyleBoxFlat
	if sb: sb.border_color = Color(TEAM_COL[t].r, TEAM_COL[t].g, TEAM_COL[t].b, 0.42)
	board.queue_redraw()
	for i in 2:
		var on := i == t
		(side_logo[i] as Panel).add_theme_stylebox_override("panel", _logo_box(i, on))
		(side_name[i] as Label).add_theme_color_override("font_color", Color.WHITE if on else NX.DIM)
		var tl: Label = side_turn[i]
		var tw := tl.create_tween()
		tw.tween_property(tl, "modulate:a", 1.0 if on else 0.0, 0.2)

# ------------------------------------------------------------------ banner
func _build_banner() -> void:
	banner = Control.new()
	banner.name = "Banner"
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.modulate.a = 0.0
	add_child(banner)
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", int(2 * U))
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.add_child(v)
	banner_img = Kit.img(D.menu("banner_goal"), Vector2(250 * U, 250 * U * 149.0 / 235.0))
	banner_img.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(banner_img)
	banner_t = Kit.title("", int(54 * U), Color.WHITE)
	banner_t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(banner_t)
	banner_s = Kit.label("", int(13 * U), NX.GOLD, true)
	banner_s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(banner_s)

## goal art banner (img=true) or a text banner (title t); sub line s in colour c
func show_banner(t: String, s: String, c: Color, img := false) -> void:
	banner_img.visible = img
	banner_t.visible = not img
	if not img:
		var nl := Kit.title(t, int(54 * U * (0.62 if NX.is_fa(t) else 1.0)), Color.WHITE)
		nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		Kit.glow_text(nl, c, 24)
		var p := banner_t.get_parent()
		var i := banner_t.get_index()
		p.remove_child(banner_t); banner_t.queue_free()
		p.add_child(nl); p.move_child(nl, i)
		banner_t = nl
	banner_s.text = s
	banner_s.visible = s != ""
	banner_s.add_theme_color_override("font_color", Color(minf(1, c.r * 1.25 + 0.15), minf(1, c.g * 1.25 + 0.15), minf(1, c.b * 1.25 + 0.15)))
	banner_s.add_theme_color_override("font_outline_color", Color(0.01, 0.02, 0.07, 0.9))
	banner_s.add_theme_constant_override("outline_size", 14)
	if _banner_tw: _banner_tw.kill()
	banner.scale = Vector2(0.3, 0.3)
	banner.modulate.a = 0.0
	_banner_tw = banner.create_tween()
	_banner_tw.set_parallel(true)
	_banner_tw.tween_property(banner, "scale", Vector2.ONE, 0.55).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	_banner_tw.tween_property(banner, "modulate:a", 1.0, 0.12)
	_banner_tw.chain().tween_interval(1.1)
	_banner_tw.chain().tween_property(banner, "scale", Vector2(1.25, 1.25), 0.3)
	_banner_tw.parallel().tween_property(banner, "modulate:a", 0.0, 0.3)

# ------------------------------------------------------------------ pause
func _set_paused(on: bool) -> void:
	if on == paused: return
	paused = on
	if on:
		if eng: eng.cancel()
		_dragging = false
		_build_pause()
		UD.sfx("ui")
	elif pause_layer:
		var pl := pause_layer
		pause_layer = null
		pl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var tw := pl.create_tween()
		tw.tween_property(pl, "modulate:a", 0.0, 0.15)
		tw.tween_callback(pl.queue_free)

func _build_pause() -> void:
	var root := ColorRect.new()
	root.name = "Pause"
	root.color = Color(2 / 255.0, 4 / 255.0, 14 / 255.0, 0.7)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.size = size
	add_child(root)
	pause_layer = root
	var pn := Kit.glass(NX.CYAN, true, 22 * U)
	pn.custom_minimum_size.x = size.x * 0.82
	var v := Kit.vbox(int(12 * U))
	pn.add_child(v)
	var t := Kit.title("توقف", int(24 * U))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	v.add_child(Kit.gap(6 * U))
	v.add_child(Kit.button("ادامه", func(): _set_paused(false), "primary"))
	v.add_child(Kit.button_small("شروع دوباره", _restart, "dark"))
	v.add_child(Kit.button("خروج", _quit, "danger"))
	# graphics quality (Store.quality -> MatchView.set_quality, same key as the settings sheet)
	v.add_child(Kit.gap(2 * U))
	var ql := Kit.label("کیفیت گرافیک", int(11 * U), NX.DIM, true)
	ql.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(ql)
	var seg := Kit.tabs(["بالا", "روان"], func(k): UD.set_p({"quality": "low" if int(k) == 1 else "high"}), 1 if _quality == "low" else 0, NX.VIOLET)
	v.add_child(seg)
	root.add_child(pn)
	var place := func():
		pn.reset_size()
		pn.position = (root.size - pn.size) * 0.5
		pn.pivot_offset = pn.size * 0.5
	pn.resized.connect(place)
	place.call()
	root.modulate.a = 0.0
	pn.scale = Vector2(0.85, 0.85)
	var tw := root.create_tween().set_parallel(true)
	tw.tween_property(root, "modulate:a", 1.0, 0.18)
	tw.tween_property(pn, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _restart() -> void:
	eng.score = [0, 0]
	eng.mleft = float(cfg.get("match_time", 0))
	eng.sudden = false
	eng.events.clear()
	eng.reset(0)
	ended = false
	co = {"shot_team": -1, "touched": false, "last_tip": -100000, "misses": 0, "reminded": -1, "turn_n": 0}
	_set_paused(false)
	_refresh_hud(true)
	UD.sfx("whistle")

func _quit() -> void:
	var sfx := UD.node("Sfx")
	if sfx: sfx.crowd(false)
	ended = true
	Nav.go("home")

func _on_store() -> void:
	var q := String(UD.pv("quality", "high"))
	if q != _quality:
		_quality = q
		if view: view.set_quality(q)

# ------------------------------------------------------------------ input
func _on_touch(ev: InputEvent) -> void:
	if paused or ended or eng == null: return
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
		var w := view.to_world(ev.position)
		if ev.pressed:
			if eng.pick(w.x, w.y):
				_dragging = true
				UD.haptic("light")
		elif _dragging:
			_dragging = false
			eng.move(w.x, w.y)
			eng.release()
		accept_event()
	elif ev is InputEventMouseMotion and _dragging:
		var w2 := view.to_world(ev.position)
		eng.move(w2.x, w2.y)
		accept_event()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		if _dragging and eng:
			_dragging = false
			eng.cancel()
		if not ended and not paused and is_inside_tree(): _set_paused(true)

# ------------------------------------------------------------------ loop
func _human(t: int) -> bool:
	if bots: return false
	return not (bool(cfg.get("ai", false)) and t == 1)

func _process(delta: float) -> void:
	if eng == null: return
	if not paused:
		for i in steps: eng.update(delta)
	if not eng.events.is_empty():
		var evs := eng.events.duplicate()
		eng.events.clear()
		for ev in evs: _on_event(ev)
	var tt := float(cfg.get("turn_time", 15))
	if tt > 0 and eng.phase == "aim" and eng.tleft < 5 and eng.tleft > 0 and _human(eng.turn) and int(co.reminded) != int(co.turn_n) and not paused:
		co.reminded = co.turn_n
		_coach_call("coach", ["۵ ثانیه وقت داری! ⏱ یک ضربه بزن.", "alert"])
	if _dragging and eng.drag == null: _dragging = false
	_refresh_hud()

func _on_event(ev: Dictionary) -> void:
	var sfx := UD.node("Sfx")
	match String(ev.get("t", "")):
		"hit":
			var pw := float(ev.get("power", 0))
			if ev.get("ball", false): co.touched = true
			if sfx: sfx.play("hitb" if ev.get("ball", false) else "hitp", pw)
			if pw > 0.35: UD.haptic("medium" if pw > 0.7 else "light")
		"wall":
			if sfx: sfx.play("wall", float(ev.get("power", 0)))
		"post":
			if sfx: sfx.play("post", float(ev.get("power", 0)))
			UD.haptic("medium")
		"shot":
			UD.haptic("light")
			co.shot_team = int(ev.get("team", 0)); co.touched = false
		"turn":
			co.turn_n = int(co.turn_n) + 1
			if int(co.shot_team) >= 0 and _human(int(co.shot_team)) and not bool(co.touched):
				co.misses = int(co.misses) + 1
				var tip := _coach_miss(eng.last_power, int(co.misses))
				var now := Time.get_ticks_msec()
				if tip != "" and now - int(co.last_tip) > 18000:
					co.last_tip = now
					_coach_call("coach", [tip, "focus" if eng.last_power > 0.9 else "idea"])
			co.shot_team = -1
		"goal":
			if ev.get("nogoal", false):
				show_banner("گل مردود", "با ضربه‌ی اول نمی‌شه گل زد", NX.DIM)
			else:
				var tm := int(ev.get("team", 0))
				co.touched = true
				if sfx:
					sfx.play("goal"); sfx.play("roar")
				UD.haptic("heavy")
				show_banner("گل!", names[tm], NX.CYAN if tm == 0 else NX.RED, true)
				if _human(tm): _coach_call("react", ["goal"])
		"clock":
			show_banner("گل طلایی", "گل بعدی برنده‌ست", NX.GOLD)
		"end":
			if not ended:
				ended = true
				_dragging = false
				if sfx:
					sfx.play("final"); sfx.crowd(false)
				var sc: Array = ev.get("score", [eng.score[0], eng.score[1]])
				get_tree().create_timer(0.9).timeout.connect(func():
					if is_inside_tree(): _finish([int(sc[0]), int(sc[1])]))
	view.on_event(ev)
	match_event.emit(ev)

# ------------------------------------------------------------------ finish (App.tsx onFinish)
## Pure reward / progression maths (RN onFinish). Returns {reward, cup, level_up, patch, win, draw}.
static func compute_finish(l: Dictionary, p: Dictionary, score: Array) -> Dictionary:
	var c: Dictionary = l.get("cfg", {})
	var md := String(l.get("mode", "quick"))
	var a := int(score[0])
	var b := int(score[1])
	var win := a > b
	var draw := a == b
	var out := {"reward": null, "cup": null, "level_up": 0, "patch": {}, "win": win, "draw": draw}
	if not bool(c.get("ai", false)): return out
	var lvl := clampi(int(c.get("ai_lvl", 1)), 0, 2)
	var mult: float = [1.0, 1.5, 2.2][lvl] * float(D.MULT.get(md, 1.0))
	var cup = null
	if md == "cup":
		var st := int(l.get("stage", 0))
		cup = {"stage": st, "won": win, "champion": win and st >= 2}
	var rw := {
		"coins": int(roundf((60.0 if win else (25.0 if draw else 12.0)) * mult + a * 5)),
		"xp": int(roundf((50.0 if win else 20.0) * maxf(0.3, mult))),
		"trophies": 0 if md == "train" else (int(roundf(20 * mult)) if win else (0 if draw else -8)),
		"gems": 0,
	}
	if cup != null and cup.champion: rw.coins += 400
	var xp := int(p.get("xp", 0))
	var before := int(D.level(xp).level)
	var after := int(D.level(xp + rw.xp).level)
	var lu := after if after > before else 0
	var ws := int(p.get("winStreak", 0)) + 1 if win else 0
	out.patch = {
		"coins": int(p.get("coins", 0)) + rw.coins + (100 if lu else 0), "gems": int(p.get("gems", 0)) + rw.gems, "xp": xp + rw.xp,
		"trophies": maxi(0, int(p.get("trophies", 0)) + rw.trophies), "played": int(p.get("played", 0)) + 1,
		"wins": int(p.get("wins", 0)) + (1 if win else 0), "losses": int(p.get("losses", 0)) + (1 if (not win and not draw) else 0),
		"draws": int(p.get("draws", 0)) + (1 if draw else 0), "goalsFor": int(p.get("goalsFor", 0)) + a, "goalsAgainst": int(p.get("goalsAgainst", 0)) + b,
		"winStreak": ws, "bestStreak": maxi(int(p.get("bestStreak", 0)), ws), "cupsWon": int(p.get("cupsWon", 0)) + (1 if (cup != null and cup.champion) else 0),
	}
	out.reward = rw
	out.cup = cup
	out.level_up = lu
	return out

func _finish(score: Array) -> void:
	var f := compute_finish(launch, UD.p(), score)
	if f.reward != null:
		UD.set_p(f.patch)
		if f.win: UD.haptic("success")
		# offline bot wins feed the server-side "beat the bot" daily challenge
		if mode != "train" and UD.signed_in():
			var supa := UD.node("Supa")
			if supa and supa.has_method("call_rpc"):
				supa.call("call_rpc", "report_offline", {"p_won": bool(f.win)})
	var r := {"score": [int(score[0]), int(score[1])], "teams": teams, "ai": bool(cfg.get("ai", false)), "ai_lvl": int(cfg.get("ai_lvl", 1))}
	var params := {"r": r, "reward": f.reward, "cup": f.cup, "level_up": f.level_up, "names": names, "launch": launch}
	finished.emit(params)
	Nav.go("result", params)

# ------------------------------------------------------------------ turn bar
class _TurnBar extends Control:
	var frac := 1.0
	var team := 0
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func set_state(f: float, t: int) -> void:
		if absf(f - frac) < 0.002 and t == team: return
		frac = f; team = t
		queue_redraw()
	func _draw() -> void:
		var r := size.y * 0.5
		draw_style_box(_box(Color(1, 1, 1, 0.08), r), Rect2(Vector2.ZERO, size))
		var w := size.x * clampf(frac, 0, 1)
		if w < 1: return
		var cs: Array = [[Color("#39d5ff"), Color("#3b82ff")], [Color("#ff4a5a"), Color("#ff8a3a")]][team]
		var x0 := 0.0 if team == 0 else size.x - w
		var n := 24
		var pts := PackedVector2Array()
		var cols := PackedColorArray()
		for i in n + 1:
			var k := float(i) / n
			var x := x0 + w * k
			var c: Color = (cs[0] as Color).lerp(cs[1], k)
			c = Color(c.r * 1.5, c.g * 1.5, c.b * 1.5, 1.0)
			pts.append(Vector2(x, 0)); cols.append(c)
		var poly := PackedVector2Array()
		var pc := PackedColorArray()
		for i in pts.size():
			poly.append(pts[i]); pc.append(cols[i])
		for i in range(pts.size() - 1, -1, -1):
			poly.append(Vector2(pts[i].x, size.y)); pc.append(cols[i])
		draw_polygon(poly, pc)
	static func _box(c: Color, r: float) -> StyleBoxFlat:
		var sb := StyleBoxFlat.new()
		sb.bg_color = c
		sb.set_corner_radius_all(int(r))
		return sb
