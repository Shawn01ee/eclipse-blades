extends Node2D
## 무대 "달그늘 나루" — 수묵 배경: 화지 하늘, 일식, 먹 산세, 마른 붓 지면.
## 시뮬 좌표: x=0 이 화면 640, 지면 y=620. 벽 ±540px → 화면 100/1180.

const Responsive := preload("res://ui/responsive_layout.gd")
const GROUND_Y := 620.0


func _ready() -> void:
	get_viewport().size_changed.connect(queue_redraw)


func _draw() -> void:
	var full_rect := Responsive.expanded_rect_for_size(get_viewport_rect().size)
	# 화지
	draw_rect(full_rect, UiKit.PAPER)
	draw_rect(Rect2(full_rect.position, Vector2(full_rect.size.x, 240.0 - full_rect.position.y)),
			Color(UiKit.PAPER_LIGHT, 0.5))
	# 일식 (개기 직전)
	var c := Vector2(950, 130)
	draw_circle(c, 58, Color(UiKit.GRAY, 0.18))
	draw_circle(c, 46, Color(0.16, 0.145, 0.12, 0.96))
	draw_arc(c, 49.5, -0.4, TAU - 0.4, 64, Color(UiKit.PAPER_LIGHT, 0.85), 3.0)
	UiKit.splatter(self, c + Vector2(30, -26), 26, 18, Color(UiKit.INK, 0.35), 21)
	# 먼 산세 (먹 농담 3겹)
	_mountain(340.0, 470.0, 260.0, Color(UiKit.INK, 0.10), 31)
	_mountain(760.0, 500.0, 300.0, Color(UiKit.INK, 0.16), 32)
	_mountain(1120.0, 520.0, 200.0, Color(UiKit.INK, 0.12), 33)
	# 물안개 띠
	for k in 5:
		UiKit.dry_stroke(self, Vector2(80.0 + k * 40.0, 540.0 + k * 9.0), 1100.0 - k * 90.0, UiKit.INK_FAINT, 40 + k)
	# 지면: 먹 번짐 띠
	draw_rect(Rect2(full_rect.position.x, GROUND_Y, full_rect.size.x,
			maxf(full_rect.end.y - GROUND_Y, 100.0)), Color(0.30, 0.28, 0.245))
	draw_rect(Rect2(full_rect.position.x, GROUND_Y, full_rect.size.x, 6), Color(UiKit.INK, 0.85))
	for k in 12:
		UiKit.dry_stroke(self, Vector2(20.0 + k * 105.0, GROUND_Y + 18.0 + (k % 4) * 18.0), 130.0, Color(UiKit.INK, 0.35), 60 + k)
	# 경기장 벽 (나루 말뚝)
	for wx in [100.0, 1180.0]:
		draw_rect(Rect2(wx - 7.0, GROUND_Y - 120.0, 14.0, 120.0), Color(UiKit.INK, 0.8))
		draw_rect(Rect2(wx - 10.0, GROUND_Y - 132.0, 20.0, 14.0), Color(UiKit.INK, 0.9))
		UiKit.splatter(self, Vector2(wx, GROUND_Y - 4.0), 18.0, 10, UiKit.INK_SOFT, int(wx))


func _mountain(cx: float, base: float, hw: float, col: Color, seed_v: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var pts := PackedVector2Array()
	pts.append(Vector2(cx - hw, base))
	var n := 7
	for k in range(1, n):
		var t := float(k) / n
		var x := cx - hw + t * hw * 2.0
		var h := sin(t * PI) * hw * 0.55 * rng.randf_range(0.7, 1.15)
		pts.append(Vector2(x, base - h))
	pts.append(Vector2(cx + hw, base))
	draw_polygon(pts, [col])
