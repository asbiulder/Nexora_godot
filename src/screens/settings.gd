extends Control
## Settings sheet (RN Settings.tsx): account entry, sound / music / haptics / oracle toggles,
## volume, graphics quality, default AI, replay intro, reset progress (tap twice), version.

var sure := false
var reset_btn: NxButton

func setup(_params: Dictionary) -> void:
	pass

func sheet_opts() -> Dictionary:
	return {"title": "تنظیمات", "en": "SYSTEMS", "accent": NX.SKY, "height": 0.78}

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var sl := Kit.scroll_list(22)
	var sc: ScrollContainer = sl[0]
	sc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(sc)
	var v: VBoxContainer = sl[1]
	var p := UD.p()
	var i := 0
	# account entry (OUI owns the account screen)
	var op := UD.online_profile()
	var acc_sub := "وارد شده: %s" % str(op.get("username", "")) if not op.is_empty() else "ورود، ثبت‌نام یا بازی به‌عنوان مهمان"
	v.add_child(_pad(Kit.enter(Kit.list_row(UD.ui2("c_profile"), "حساب کاربری", acc_sub, Kit.img(UD.menu("g_chevrons"), 60), func(): Nav.go("account")), i)))
	var rows := [["c_mega", "صداها", "ضربه، گل، تماشاگر", "sound"], ["c_bell", "موسیقی", "موسیقی منو", "music"], ["x_gear", "لرزش", "بازخورد لمسی هنگام برخورد", "haptics"], ["oracle", "نمایش اوراکل", "دستیار شناور، مربی بازی و راهنما", "oracle"]]
	for r in rows:
		i += 1
		var key: String = r[3]
		var icon: Texture2D = UD.tex("res://assets/g/oracle/oracle_idle.webp") if r[0] == "oracle" else UD.ui2(r[0])
		if icon == null:
			icon = UD.ui2("c_star")
		var tg := Kit.toggle(bool(p.get(key, true)), func(on): UD.set_p({key: on}); UD.apply_prefs())
		v.add_child(_pad(Kit.enter(Kit.list_row(icon, r[1], r[2], tg), i)))
	# volume
	var vols := [0.25, 0.5, 0.75, 1.0]
	var vi := vols.find(snappedf(float(p.get("volume", 1.0)), 0.25))
	v.add_child(_pad(Kit.enter(_seg_panel("بلندی صدا", "", ["۲۵٪", "۵۰٪", "۷۵٪", "۱۰۰٪"], 3 if vi < 0 else vi, func(k): UD.set_p({"volume": vols[k]}); UD.apply_prefs(), NX.CYAN), 5)))
	v.add_child(_pad(Kit.enter(_seg_panel("کیفیت گرافیک", "روی گوشی‌های ضعیف «روان» را انتخاب کن", ["بالا", "روان"], 1 if str(p.get("quality", "high")) == "low" else 0, func(k): UD.set_p({"quality": "low" if k == 1 else "high"}), NX.VIOLET), 6)))
	v.add_child(_pad(Kit.enter(_seg_panel("سختی پیش‌فرض ربات", "", ["آسان", "معمولی", "سخت"], int(p.get("aiLvl", 1)), func(k): UD.set_p({"aiLvl": k}), NX.CYAN), 7)))
	v.add_child(Kit.gap(8))
	v.add_child(_pad(Kit.button_small("پخش دوباره‌ی اینترو", func():
		Nav.close_sheet()
		UD.menu_music(false)
		Nav.go("intro"), "dark")))
	reset_btn = Kit.button_small("پاک کردن پیشرفت", _reset, "danger")
	v.add_child(_pad(reset_btn))
	var ver := Kit.caps("NEXORA · Finger Soccer · v5.0", 26, NX.DIM2, 4)
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(Kit.gap(30))
	v.add_child(ver)
	v.add_child(Kit.gap(100))

func _pad(c: Control) -> Control:
	return Kit.margin(c, NX.PAD, 0, NX.PAD, 0)

func _seg_panel(title: String, sub: String, items: Array, idx: int, cb: Callable, acc: Color) -> Control:
	var pn := Kit.glass()
	var v := Kit.vbox(12)
	v.add_child(Kit.label(title, 39, NX.TEXT, true))
	if sub != "":
		v.add_child(Kit.label(sub, 29, NX.DIM))
	v.add_child(Kit.tabs(items, cb, idx, acc))
	pn.add_child(v)
	return pn

func _reset() -> void:
	if not sure:
		sure = true
		reset_btn.set_text("مطمئنی؟ دوباره بزن")
		return
	UD.reset_store()
	sure = false
	reset_btn.set_text("پاک کردن پیشرفت")
	Nav.toast("پیشرفت پاک شد", "ok")
	Nav.refresh_chrome()
