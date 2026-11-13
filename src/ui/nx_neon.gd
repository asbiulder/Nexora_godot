class_name NxNeon
extends PanelContainer
## v2 neon glass tile (home mockup): deep indigo glass, violet edge, cyan -> pink glow along the
## bottom edge and a soft top sheen. Used for the home tiles, level card, shop categories, mode cards.

var c1 := Color("#39d5ff")
var c2 := Color("#ff4f8b")
var radius := 40
var strength := 1.0

func _init(r := 40, pad := 20.0, c1_ := Color("#39d5ff"), c2_ := Color("#ff4f8b")) -> void:
	radius = r
	c1 = c1_
	c2 = c2_
	var sb := NX.box(Color(0.06, 0.05, 0.18, 0.84), r, 3, Color(0.56, 0.5, 1.0, 0.34), 18, Color(0.02, 0.0, 0.08, 0.55))
	sb.content_margin_left = pad
	sb.content_margin_right = pad
	sb.content_margin_top = pad
	sb.content_margin_bottom = pad
	add_theme_stylebox_override("panel", sb)
	mouse_filter = Control.MOUSE_FILTER_PASS
	resized.connect(queue_redraw)

func _draw() -> void:
	var w := size.x
	var h := size.y
	if w < 10 or h < 10:
		return
	var r := float(radius)
	# bottom glow wash
	var y0 := h * 0.5
	var g := PackedVector2Array([Vector2(r * 0.4, y0), Vector2(w - r * 0.4, y0), Vector2(w - 5, h - r * 0.45), Vector2(5, h - r * 0.45)])
	var gc := PackedColorArray([Color(c1, 0.0), Color(c2, 0.0), Color(c2, 0.16 * strength), Color(c1, 0.16 * strength)])
	draw_polygon(g, gc)
	# top sheen
	var s := PackedVector2Array([Vector2(r * 0.6, 4), Vector2(w - r * 0.6, 4), Vector2(w - 6, h * 0.36), Vector2(6, h * 0.36)])
	draw_polygon(s, PackedColorArray([Color(1, 1, 1, 0.07), Color(1, 1, 1, 0.07), Color(1, 1, 1, 0), Color(1, 1, 1, 0)]))
	# neon edge along the bottom (fades out at the corners)
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	var n := 24
	for i in n + 1:
		var t := float(i) / n
		pts.append(Vector2(lerpf(r * 0.7, w - r * 0.7, t), h - 2.5))
		var c := c1.lerp(c2, t)
		cols.append(Color(c.r * 1.5, c.g * 1.5, c.b * 1.5, 0.95 * pow(sin(PI * t), 0.6) * strength))
	draw_polyline_colors(pts, cols, 4.0, true)


## small red notification dot (28px) for tiles / round buttons; never stretched by a container
static func dot(pos := Vector2(12, 10)) -> Control:
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var d := _Dot.new()
	d.position = pos
	d.size = Vector2(28, 28)
	holder.add_child(d)
	return holder

class _Dot extends Control:
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		draw_circle(size * 0.5, 14, Color("#0b0a24"), true, -1.0, true)
		draw_circle(size * 0.5, 10.5, NX.hdr(NX.RED, 1.3), true, -1.0, true)
