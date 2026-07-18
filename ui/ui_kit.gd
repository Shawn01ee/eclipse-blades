class_name UiKit
## 수묵(먹·붓) 스타일 공통 팔레트와 위젯 헬퍼.
## 원칙: 화지(양피지) 바탕 + 먹 흑백 + 인장 주홍 한 가지 강조색.

const PAPER := Color(0.847, 0.807, 0.714)
const PAPER_DIM := Color(0.78, 0.742, 0.655)
const PAPER_LIGHT := Color(0.90, 0.868, 0.79)
const INK := Color(0.11, 0.10, 0.085)
const INK_SOFT := Color(0.11, 0.10, 0.085, 0.55)
const INK_FAINT := Color(0.11, 0.10, 0.085, 0.22)
const GRAY := Color(0.42, 0.40, 0.36)
const SEAL := Color(0.658, 0.208, 0.145)      # 인장 주홍 (유일한 유채색)
const SEAL_SOFT := Color(0.658, 0.208, 0.145, 0.6)


static func label(text: String, size: int = 22, color: Color = INK) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


static func button(text: String, size: int = 26) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_color_override("font_color", INK)
	b.add_theme_color_override("font_hover_color", SEAL)
	b.add_theme_color_override("font_focus_color", SEAL)
	b.add_theme_color_override("font_pressed_color", SEAL)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(PAPER_LIGHT, 0.0)
	normal.border_color = INK_FAINT
	normal.set_border_width_all(0)
	normal.border_width_bottom = 2
	normal.content_margin_left = 26
	normal.content_margin_right = 26
	normal.content_margin_top = 8
	normal.content_margin_bottom = 8
	var focus: StyleBoxFlat = normal.duplicate()
	focus.border_color = SEAL
	focus.border_width_bottom = 3
	focus.border_width_left = 3
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", focus)
	b.add_theme_stylebox_override("focus", focus)
	b.add_theme_stylebox_override("pressed", focus)
	return b


static func panel_box() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = PAPER_LIGHT
	sb.border_color = INK
	sb.set_border_width_all(3)
	sb.set_content_margin_all(24)
	return sb


static func vspace(h: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c


## 거친 붓 사각형: 본체 + 흔들리는 가장자리 획 (CanvasItem._draw 안에서 호출)
static func brush_rect(ci: CanvasItem, rect: Rect2, color: Color, rough_seed: int = 1) -> void:
	ci.draw_rect(rect, color)
	var rng := RandomNumberGenerator.new()
	rng.seed = rough_seed
	var edge := Color(color, color.a * 0.55)
	for k in 6:
		var t := rng.randf()
		var w := rng.randf_range(6, 22)
		var h := rng.randf_range(1.5, 4.0)
		ci.draw_rect(Rect2(rect.position.x + t * rect.size.x - w * 0.5,
			rect.position.y - h * 0.7, w, h), edge)
		ci.draw_rect(Rect2(rect.position.x + rng.randf() * rect.size.x - w * 0.5,
			rect.end.y - h * 0.3, w, h), edge)


## 마른 붓 가로획 (배경 질감)
static func dry_stroke(ci: CanvasItem, from: Vector2, length: float, color: Color, rough_seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = rough_seed
	var segs := int(length / 14.0)
	for k in segs:
		if rng.randf() < 0.25:
			continue
		var x := from.x + k * 14.0
		ci.draw_rect(Rect2(x, from.y + rng.randf_range(-1.5, 1.5),
			rng.randf_range(6, 13), rng.randf_range(1, 3)), Color(color, color.a * rng.randf_range(0.3, 1.0)))


## 먹 튀김 (점묘)
static func splatter(ci: CanvasItem, center: Vector2, radius: float, n: int, color: Color, rough_seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = rough_seed
	for k in n:
		var ang := rng.randf() * TAU
		var d := rng.randf() * radius
		var r := rng.randf_range(1.0, 3.5) * (1.0 - d / (radius + 1.0)) + 0.6
		ci.draw_circle(center + Vector2(cos(ang), sin(ang)) * d, r, Color(color, color.a * rng.randf_range(0.4, 1.0)))
