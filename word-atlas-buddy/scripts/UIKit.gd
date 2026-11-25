extends Reference
class_name UIKit

# 640x480 固定布局的绘制辅助。所有界面在 App._draw() 里直接画，
# 不建控件树：3000 词条的列表如果全用 Control 节点，掌机内存会很难看。

const FONT_UI := "res://assets/fonts/ui.ttf"
const FONT_IPA := "res://assets/fonts/ipa.ttf"

const BG := Color("0e1524")
const PANEL := Color("172033")
const PANEL_HI := Color("22304a")
const LINE := Color("2e3d5a")
const TEXT := Color("eef2f8")
const MUTED := Color("93a3bb")
const DIM := Color("5b6b85")
const ACCENT := Color("4fd1c5")
const GOLD := Color("f6c26b")
const RED := Color("f2777a")
const BLUE := Color("7aa2f7")

const CEFR_COLORS := [
	Color("6ee7a8"), Color("7fc9f5"), Color("f6c26b"),
	Color("f0a3c8"), Color("b39dfb"), Color("f2777a"),
]

var _fonts := {}
var _ipa_fonts := {}


func font(size: int) -> DynamicFont:
	if _fonts.has(size):
		return _fonts[size]
	var f := DynamicFont.new()
	f.font_data = load(FONT_UI)
	f.size = size
	f.use_filter = false
	_fonts[size] = f
	return f


func ipa_font(size: int) -> DynamicFont:
	if _ipa_fonts.has(size):
		return _ipa_fonts[size]
	var f := DynamicFont.new()
	var data = load(FONT_IPA)
	f.font_data = data if data != null else load(FONT_UI)
	f.size = size
	f.use_filter = false
	_ipa_fonts[size] = f
	return f


# ---------------------------------------------------------------- 形状

func panel(ci: CanvasItem, rect: Rect2, bg: Color = PANEL, border: Color = LINE, radius := 8) -> void:
	ci.draw_rect(rect, bg, true)
	if border.a > 0.0:
		# Godot 3.5 没有圆角矩形绘制，用四边线模拟（视觉上足够）
		ci.draw_rect(rect, border, false, 1.0)


func hline(ci: CanvasItem, x0: float, x1: float, y: float, color: Color = LINE) -> void:
	ci.draw_line(Vector2(x0, y), Vector2(x1, y), color, 1.0)


func bar(ci: CanvasItem, rect: Rect2, value: float, color: Color = ACCENT, back: Color = Color("233049")) -> void:
	ci.draw_rect(rect, back, true)
	var w := rect.size.x * clamp(value, 0.0, 1.0)
	if w > 0.0:
		ci.draw_rect(Rect2(rect.position, Vector2(w, rect.size.y)), color, true)


# ---------------------------------------------------------------- 文本

func text(ci: CanvasItem, value: String, pos: Vector2, size := 18, color: Color = TEXT, max_width := 0.0) -> void:
	var f := font(size)
	var drawn := value
	if max_width > 0.0:
		drawn = ellipsis(f, value, max_width)
	ci.draw_string(f, pos, drawn, color)


func text_center(ci: CanvasItem, value: String, center_x: float, y: float, size := 18, color: Color = TEXT) -> void:
	var f := font(size)
	var w := f.get_string_size(value).x
	ci.draw_string(f, Vector2(center_x - w * 0.5, y), value, color)


func text_right(ci: CanvasItem, value: String, right_x: float, y: float, size := 18, color: Color = TEXT) -> void:
	var f := font(size)
	var w := f.get_string_size(value).x
	ci.draw_string(f, Vector2(right_x - w, y), value, color)


func ipa(ci: CanvasItem, value: String, pos: Vector2, size := 15, color: Color = MUTED) -> void:
	ci.draw_string(ipa_font(size), pos, value, color)


func ellipsis(f: Font, value: String, max_width: float) -> String:
	if f.get_string_size(value).x <= max_width:
		return value
	var out := value
	while out.length() > 1 and f.get_string_size(out + "…").x > max_width:
		out = out.substr(0, out.length() - 1)
	return out + "…"


# 中英混排换行：中文按字断，英文优先在空格断。
func wrap_lines(f: Font, value: String, max_width: float) -> Array:
	var lines := []
	var current := ""
	var i := 0
	var n := value.length()
	while i < n:
		var ch := value[i]
		if ch == "\n":
			lines.append(current)
			current = ""
			i += 1
			continue
		var candidate := current + ch
		if f.get_string_size(candidate).x > max_width and current != "":
			# 拉丁词尽量不拆开：回退到上一个空格
			var space_at := current.rfind(" ")
			if space_at > 0 and ch != " " and not _is_cjk(ch):
				lines.append(current.substr(0, space_at))
				current = current.substr(space_at + 1) + ch
			else:
				lines.append(current)
				current = ch
		else:
			current = candidate
		i += 1
	if current != "":
		lines.append(current)
	return lines


func _is_cjk(ch: String) -> bool:
	if ch == "":
		return false
	var c := ch.ord_at(0)
	return (c >= 0x4E00 and c <= 0x9FFF) or (c >= 0x3000 and c <= 0x303F) or (c >= 0xFF00 and c <= 0xFFEF)


# 画一段自动换行文本，返回实际占用的高度。
func paragraph(ci: CanvasItem, value: String, pos: Vector2, max_width: float, size := 15,
		color: Color = TEXT, line_gap := 4, max_lines := 0) -> float:
	var f := font(size)
	var lines := wrap_lines(f, value, max_width)
	if max_lines > 0 and lines.size() > max_lines:
		lines.resize(max_lines)
		lines[max_lines - 1] = ellipsis(f, lines[max_lines - 1] + "…", max_width)
	var line_h := f.get_height() + line_gap
	var ascent := f.get_ascent()
	for i in range(lines.size()):
		ci.draw_string(f, Vector2(pos.x, pos.y + ascent + i * line_h), lines[i], color)
	return lines.size() * line_h


# ---------------------------------------------------------------- 语义

# ---------------------------------------------------------------- 图标

# 喇叭图标（pos 为左上角，size 为高度）。Godot 3.5 没有图标字体，
# 这里用多边形 + 圆弧拼一个，保证任何分辨率都清晰。
func speaker(ci: CanvasItem, pos: Vector2, size: float, color: Color = ACCENT) -> void:
	var h := size
	var w := size
	var body := PoolVector2Array([
		pos + Vector2(w * 0.06, h * 0.36),
		pos + Vector2(w * 0.28, h * 0.36),
		pos + Vector2(w * 0.50, h * 0.16),
		pos + Vector2(w * 0.50, h * 0.84),
		pos + Vector2(w * 0.28, h * 0.64),
		pos + Vector2(w * 0.06, h * 0.64),
	])
	ci.draw_colored_polygon(body, color)
	var c := pos + Vector2(w * 0.52, h * 0.5)
	var lw: float = max(1.4, size * 0.085)
	ci.draw_arc(c, h * 0.20, -0.85, 0.85, 10, color, lw, true)
	ci.draw_arc(c, h * 0.35, -0.85, 0.85, 12, color, lw, true)


# 带底框的喇叭按钮：屏幕上更醒目，一眼能看出「这里可以发音」
func speaker_button(ci: CanvasItem, rect: Rect2, color: Color = ACCENT, active := false) -> void:
	var a := 0.32 if active else 0.16
	panel(ci, rect, Color(color.r, color.g, color.b, a), Color(color.r, color.g, color.b, 0.55))
	var s: float = rect.size.y * 0.66
	speaker(ci, rect.position + Vector2((rect.size.x - s) * 0.5, (rect.size.y - s) * 0.5), s, color)


func cefr_color(cefr: String) -> Color:
	var idx := ["A1", "A2", "B1", "B2", "C1", "C2"].find(cefr)
	if idx < 0:
		return MUTED
	return CEFR_COLORS[idx]


func draw_chip(ci: CanvasItem, value: String, pos: Vector2, size := 12, color: Color = ACCENT) -> float:
	var f := font(size)
	var w := f.get_string_size(value).x + 10
	var rect := Rect2(pos, Vector2(w, 17))
	ci.draw_rect(rect, Color(color.r, color.g, color.b, 0.16), true)
	ci.draw_rect(rect, Color(color.r, color.g, color.b, 0.55), false, 1.0)
	ci.draw_string(f, Vector2(pos.x + 5, pos.y + 13), value, color)
	return w
