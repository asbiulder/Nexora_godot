extends Control
## App root: Backdrop · ScreenHost · Chrome · SheetLayer · ToastLayer · Veil (+ WorldEnvironment glow).

@onready var backdrop: NxSpace = $Backdrop
@onready var host: Control = $ScreenHost
@onready var chrome_node: NxChrome = $Chrome
@onready var sheet_layer: Control = $SheetLayer
@onready var toast_layer: Control = $ToastLayer
@onready var veil: ColorRect = $Veil

func _ready() -> void:
	get_tree().set_auto_accept_quit(false)
	get_tree().quit_on_go_back = false
	_update_safe_area()
	get_viewport().size_changed.connect(_update_safe_area)
	# Chrome's _ready laid out before the insets were known: lay it out again now
	if chrome_node.has_method("_layout"):
		chrome_node.call("_layout")
	veil.color = Color(NX.VEIL, 0.0)
	veil.visible = false
	chrome_node.visible = false
	Nav.attach(self)
	# online UI boot (password-recovery deep link etc.); guarded so the offline shell runs without it
	if ResourceLoader.exists("res://src/online/oui.gd"):
		var oui = load("res://src/online/oui.gd")
		if oui is GDScript and (oui as GDScript).can_instantiate() and "boot" in (oui as GDScript).get_script_method_list().map(func(m): return m["name"]):
			oui.call("boot")
	UD.apply_prefs()
	_apply_quality()
	var st := UD.node("Store")
	if st and st.has_signal("changed"):
		st.connect("changed", _apply_quality)
	var first := "intro"
	if OS.has_environment("NX_START"):
		first = OS.get_environment("NX_START")
	# test hook (Android emulator smoke test): am start ... --esa command_line_params --nx-start=<screen|quickmatch>
	for arg in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		if str(arg).begins_with("--nx-start="):
			first = str(arg).get_slice("=", 1)
	print("NX_BOOT main ready, first=", first)
	if first == "quickmatch":
		Nav.go("match", Launch.build("quick", UD.p(), {"lvl": 1}))
		print("NX_TEST quick match started")
	else:
		Nav.go(first)
	# test hook: NX_WALK=1 runs tests/ui_walk.gd (navigates every screen, optional screenshots)
	if OS.has_environment("NX_WALK") and ResourceLoader.exists("res://tests/ui_walk.gd"):
		var w = load("res://tests/ui_walk.gd").new()
		add_child(w)

func _apply_quality() -> void:
	var hq := str(UD.pv("quality", "high")) != "low"
	backdrop.set_stars(hq)
	var env := ($WorldEnvironment as WorldEnvironment).environment
	if env:
		env.glow_enabled = hq

func _update_safe_area() -> void:
	var vp := get_viewport_rect().size
	if not OS.has_feature("mobile"):
		NX.safe_top = 0.0
		NX.safe_bottom = 0.0
		if OS.has_environment("NX_SAFE"):  # simulate a notch on desktop: NX_SAFE=top,bottom
			var a := OS.get_environment("NX_SAFE").split(",")
			NX.safe_top = float(a[0])
			NX.safe_bottom = float(a[1]) if a.size() > 1 else 0.0
		if chrome_node and chrome_node.is_node_ready():
			chrome_node.call("_layout")
		return
	var win := Vector2(DisplayServer.window_get_size())
	var sa := DisplayServer.get_display_safe_area()
	var scr := Vector2(DisplayServer.screen_get_size())
	if win.x <= 0 or scr.x <= 0:
		return
	var k := vp.x / win.x
	NX.safe_top = maxf(0.0, sa.position.y) * k
	NX.safe_bottom = maxf(0.0, scr.y - (sa.position.y + sa.size.y)) * k
	NX.safe_left = maxf(0.0, sa.position.x) * k
	NX.safe_right = maxf(0.0, scr.x - (sa.position.x + sa.size.x)) * k
	if chrome_node and chrome_node.has_method("_layout"):
		chrome_node.call("_layout")

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		Nav.back()
	elif what == NOTIFICATION_WM_CLOSE_REQUEST:
		get_tree().quit()
	elif what == NOTIFICATION_APPLICATION_RESUMED:
		if chrome_node and chrome_node.visible:
			chrome_node.refresh()

func _unhandled_input(ev: InputEvent) -> void:
	if ev.is_action_pressed("ui_cancel"):
		Nav.back()
		get_viewport().set_input_as_handled()
