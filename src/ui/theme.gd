class_name NX
extends RefCounted
## NEXORA design tokens (colours, fonts, gradients, sizes) — port of src/ui/theme.ts.
## All sizes are in viewport pixels for the 1080-wide base (1 RN dp ≈ 2.6 px).

const U := 2.6  # RN dp -> px

# ---- colours (RN theme.ts + SPEC) ----
const BG := Color("#040510")
const BG2 := Color("#060b22")
const CYAN := Color("#39d5ff")
const SKY := Color("#7fc8ff")
const BLUE := Color("#3b82ff")
const INDIGO := Color("#6d5bff")
const VIOLET := Color("#a35bff")
const PINK := Color("#ff4a7a")
const ROSE := Color("#ff7bd5")
const GOLD := Color("#ffd257")
const ORANGE := Color("#ff8a3a")
const RED := Color("#ff4a5a")
const GREEN := Color("#4dff8a")
const MINT := Color("#3dffa8")
const TEXT := Color("#eaf4ff")
const DIM := Color("#8ea3d6")
const DIM2 := Color("#5f6f9e")
const LINE := Color(0.43, 0.67, 1.0, 0.24)
const LINE_HI := Color(0.47, 0.86, 1.0, 0.75)
const PANEL := Color(0.043, 0.071, 0.188, 0.78)  # 0x0b1230 @ .78
const DARK_TXT := Color("#04122a")
const VEIL := Color("#02030b")

# emissive (HDR > 1) accents: picked up by the WorldEnvironment glow in main
static func hdr(c: Color, k := 1.8) -> Color:
	return Color(c.r * k, c.g * k, c.b * k, c.a)

static func a(c: Color, alpha: float) -> Color:
	return Color(c.r, c.g, c.b, alpha)

# ---- gradients (3 stops like RN G.*) ----
const G := {
	"primary": [Color("#4fe3ff"), Color("#5b8cff"), Color("#a35bff")],
	"gold": [Color("#8a5200"), Color("#d39420"), Color("#ffe08a")],
	"green": [Color("#0a6b4a"), Color("#16b77a"), Color("#5dffbf")],
	"red": [Color("#5a0f24"), Color("#a3203f"), Color("#ff5b74")],
	"danger": [Color("#5a0f24"), Color("#a3203f"), Color("#ff5b74")],
	"dark": [Color("#151f4a"), Color("#1d2b63"), Color("#2a3f86")],
	"ghost": [Color(0.08, 0.12, 0.29, 0.85), Color(0.11, 0.17, 0.39, 0.85), Color(0.16, 0.25, 0.53, 0.85)],
	"violet": [Color("#3a1d8a"), Color("#6d3bff"), Color("#c08bff")],
}

static func grad(style: String) -> Array:
	return G.get(style, G["primary"])

# ---- fonts ----
const FONT_PATHS := {
	"title": "res://assets/fonts/Orbitron_900Black.ttf",
	"head": "res://assets/fonts/Orbitron_700Bold.ttf",
	"body": "res://assets/fonts/Exo2_700Bold.ttf",
	"medium": "res://assets/fonts/Exo2_500Medium.ttf",
	"bold": "res://assets/fonts/Exo2_800ExtraBold.ttf",
	"fa": "res://assets/fonts/Vazirmatn_500Medium.ttf",
	"fa_r": "res://assets/fonts/Vazirmatn_400Regular.ttf",
	"faB": "res://assets/fonts/Vazirmatn_800ExtraBold.ttf",
	"fa_b": "res://assets/fonts/Vazirmatn_700Bold.ttf",
}
static var _fonts := {}

static func font(kind := "body") -> Font:
	if _fonts.has(kind):
		return _fonts[kind]
	var path: String = FONT_PATHS.get(kind, FONT_PATHS["body"])
	var f: Font = load(path)
	var fv := FontVariation.new()
	fv.base_font = f
	if not kind.begins_with("fa"):
		# latin fonts fall back to Vazirmatn so mixed strings never show tofu
		fv.fallbacks = [load(FONT_PATHS["faB"] if kind in ["title", "head", "bold"] else FONT_PATHS["fa"]), emoji_font()]
	else:
		fv.fallbacks = [load(FONT_PATHS["bold"]), emoji_font()]
	_fonts[kind] = fv
	return fv

static var _emoji: Font = null

## system colour-emoji font (Android ships Noto Color Emoji) so 🔥💎👋 don't render as boxes
static func emoji_font() -> Font:
	if _emoji == null:
		var sf := SystemFont.new()
		sf.font_names = PackedStringArray(["Noto Color Emoji", "NotoColorEmoji", "Apple Color Emoji", "Segoe UI Emoji", "emoji"])
		_emoji = sf
	return _emoji

# ---- Persian helpers ----
const FA_DIGITS := "۰۱۲۳۴۵۶۷۸۹"
static var _fa_re: RegEx

static func is_fa(s: String) -> bool:
	if _fa_re == null:
		_fa_re = RegEx.create_from_string("[\\x{0600}-\\x{06FF}]")
	return _fa_re.search(s) != null

## Persian digits (like String.replace in faNum)
static func fa_num(v) -> String:
	var s := str(v)
	var o := ""
	for ch in s:
		var c := ch.unicode_at(0)
		o += FA_DIGITS[c - 48] if c >= 48 and c <= 57 else ch
	return o

## number formatted like toLocaleString('fa-IR') ("۱٬۲۳۴")
static func fa(n) -> String:
	var neg: bool = float(n) < 0
	var s := str(absi(int(round(float(n)))))
	var o := ""
	var cnt := 0
	for i in range(s.length() - 1, -1, -1):
		o = s[i] + o
		cnt += 1
		if cnt % 3 == 0 and i > 0:
			o = "٬" + o
	return ("-" if neg else "") + fa_num(o)

static func en_num(n) -> String:
	var s := str(absi(int(n)))
	var o := ""
	var cnt := 0
	for i in range(s.length() - 1, -1, -1):
		o = s[i] + o
		cnt += 1
		if cnt % 3 == 0 and i > 0:
			o = "," + o
	return ("-" if int(n) < 0 else "") + o

# ---- layout ----
const HUD_H := 150.0
const TAB_H := 186.0
const RADIUS := 44
const PAD := 42.0

## safe-area insets in viewport pixels (filled by main.gd)
static var safe_top := 0.0
static var safe_bottom := 0.0
static var safe_left := 0.0
static var safe_right := 0.0

# ---- styleboxes ----
static func box(bg: Color, radius := 44, border := 0.0, border_col := Color.TRANSPARENT, shadow := 0, shadow_col := Color(0, 0, 0, 0.5)) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(radius)
	if border > 0:
		sb.set_border_width_all(int(round(border)))
		sb.border_color = border_col
	if shadow > 0:
		sb.shadow_size = shadow
		sb.shadow_color = shadow_col
	sb.anti_aliasing = true
	sb.corner_detail = 10
	return sb

static func glass_box(accent := Color.TRANSPARENT, glow := false) -> StyleBoxFlat:
	var bc := LINE if accent.a == 0 else Color(accent.r, accent.g, accent.b, 0.42)
	var sb := box(PANEL, RADIUS, 3, bc, 26 if glow else 14, Color(accent.r, accent.g, accent.b, 0.35) if glow else Color(0, 0, 0, 0.45))
	sb.content_margin_left = 30
	sb.content_margin_right = 30
	sb.content_margin_top = 28
	sb.content_margin_bottom = 28
	return sb

static func empty_box() -> StyleBoxEmpty:
	return StyleBoxEmpty.new()
