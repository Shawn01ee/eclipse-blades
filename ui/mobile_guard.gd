class_name MobileGuard
extends Control
## 모바일 세로 화면에서는 전투를 가리고 회전을 안내한다.

const TouchControls := preload("res://ui/touch_controls.gd")

var _last_window_size := Vector2i.ZERO
var _paused_by_guard := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	z_index = 1000
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_sync_orientation()


static func is_portrait_size(window_size: Vector2i) -> bool:
	return window_size.x > 0 and window_size.y > window_size.x


func _process(_delta: float) -> void:
	var window_size := DisplayServer.window_get_size()
	if window_size != _last_window_size:
		_last_window_size = window_size
		_sync_orientation()
	elif visible and _paused_by_guard and not get_tree().paused:
		# 화면 전환 코드가 pause를 풀어도 세로 안내 중에는 경기가 진행되지 않게 한다.
		get_tree().paused = true


func _sync_orientation() -> void:
	var want_guard := TouchControls.is_mobile_target() \
			and is_portrait_size(DisplayServer.window_get_size())
	if want_guard == visible:
		return
	visible = want_guard
	if want_guard:
		if not get_tree().paused:
			get_tree().paused = true
			_paused_by_guard = true
	else:
		if _paused_by_guard:
			get_tree().paused = false
		_paused_by_guard = false
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), UiKit.PAPER)
	var f := ThemeDB.fallback_font
	# 가로로 눕힌 휴대폰과 회전 화살표.
	var phone := Rect2(490, 195, 300, 160)
	draw_rect(phone, UiKit.PAPER_LIGHT)
	draw_rect(phone, UiKit.INK, false, 7.0)
	draw_circle(Vector2(515, 275), 6, UiKit.INK)
	draw_arc(Vector2(640, 275), 120, -2.65, -0.45, 32, UiKit.SEAL, 8.0)
	var arrow_tip := Vector2(748, 222)
	draw_colored_polygon(PackedVector2Array([
		arrow_tip, arrow_tip + Vector2(-30, -3), arrow_tip + Vector2(-9, 25)]), UiKit.SEAL)
	var title := "가로로 돌려주세요"
	var title_w := f.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 58).x
	draw_string(f, Vector2(640 - title_w * 0.5, 445), title,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 58, UiKit.INK)
	var sub := "전투 화면과 터치 조작은 가로 모드에 맞춰져 있습니다"
	var sub_w := f.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 27).x
	draw_string(f, Vector2(640 - sub_w * 0.5, 500), sub,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 27, UiKit.GRAY)
