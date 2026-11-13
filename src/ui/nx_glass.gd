class_name NxGlass
extends PanelContainer
## Glass panel: dark navy body, cyan-ish border, soft shadow/glow, top sheen + accent line.

var accent := Color.TRANSPARENT
var glow := false

func _init(accent_ := Color.TRANSPARENT, glow_ := false, pad := -1.0) -> void:
	accent = accent_
	glow = glow_
	var sb := NX.glass_box(accent, glow)
	if pad >= 0:
		sb.content_margin_left = pad
		sb.content_margin_right = pad
		sb.content_margin_top = pad
		sb.content_margin_bottom = pad
	add_theme_stylebox_override("panel", sb)
	mouse_filter = Control.MOUSE_FILTER_PASS

func set_pad(h: float, v := -1.0) -> NxGlass:
	var sb := get_theme_stylebox("panel") as StyleBoxFlat
	sb.content_margin_left = h
	sb.content_margin_right = h
	sb.content_margin_top = v if v >= 0 else h
	sb.content_margin_bottom = v if v >= 0 else h
	return self

func _draw() -> void:
	var w := size.x
	var h := size.y
	# top sheen
	var top := 4.0
	var hh: float = h * 0.42
	var pts := PackedVector2Array([Vector2(18, top), Vector2(w - 18, top), Vector2(w - 6, hh), Vector2(6, hh)])
	var cols := PackedColorArray([Color(1, 1, 1, 0.075), Color(1, 1, 1, 0.075), Color(1, 1, 1, 0), Color(1, 1, 1, 0)])
	draw_polygon(pts, cols)
	if accent.a > 0:
		draw_line(Vector2(72, 2), Vector2(w - 72, 2), NX.hdr(accent, 1.6), 4.0, true)
