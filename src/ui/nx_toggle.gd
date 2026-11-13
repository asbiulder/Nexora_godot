class_name NxToggle
extends Control
## iOS-like switch with spring knob (RN Toggle).

var on := false
var t := 0.0
var accent := NX.CYAN
var cb: Callable
var _tw: Tween

func _init(on_ := false, cb_ := Callable(), accent_ := NX.CYAN) -> void:
	on = on_
	t = 1.0 if on else 0.0
	cb = cb_
	accent = accent_
	custom_minimum_size = Vector2(140, 78)
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mouse_filter = Control.MOUSE_FILTER_STOP

func _draw() -> void:
	var r := size.y * 0.5
	var bgc := Color(1, 1, 1, 0.12).lerp(NX.hdr(accent, 1.15), t)
	draw_style_box(NX.box(bgc, int(r)), Rect2(Vector2.ZERO, size))
	var kr := r - 8.0
	var x := lerpf(r, size.x - r, t)
	draw_circle(Vector2(x, r + 3), kr, Color(0, 0, 0, 0.3), true, -1.0, true)
	draw_circle(Vector2(x, r), kr, Color.WHITE, true, -1.0, true)

func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and not ev.pressed:
		UD.sfx("ui")
		UD.haptic("light")
		set_on(not on)
		if cb.is_valid():
			cb.call(on)

func set_on(v: bool) -> void:
	on = v
	if _tw:
		_tw.kill()
	_tw = create_tween()
	_tw.tween_method(func(x): t = x; queue_redraw(), t, 1.0 if on else 0.0, 0.4).set_trans(Tween.TRANS_SPRING).set_ease(Tween.EASE_OUT)
