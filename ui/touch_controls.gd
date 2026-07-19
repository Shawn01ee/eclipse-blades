extends Control
## 모바일/웹용 온스크린 터치 컨트롤 (P1 전용).
## 방식: 터치 버튼이 기존 InputMap 액션(p1_*)을 눌러 준다 → _read_word/콤보 로직 그대로 재사용.
## 멀티터치: InputEventScreenTouch/Drag 를 인덱스별로 추적한다.
##
## 좌: 가상 조이스틱(←→ 이동/가드, ↑ 점프, ↓ 숙임)
## 우: 약·중·강·기술·오의 버튼
## 상단: 일시정지

signal pause_pressed

const DEADZONE := 26.0
const DIR_THRESH := 30.0
const JUMP_THRESH := 34.0
const SAFE_EDGE := 56.0

var joy_center := Vector2(170, 570)
var joy_radius := 92.0
var _joy_index := -1
var _joy_vec := Vector2.ZERO

# 버튼: 이름 → {rect, action, label, sub}
var buttons := {}
var _btn_touch := {}          # touch_index → button_name
var _held_actions := {}       # action → true (현재 눌림)

var pause_rect := Rect2(608, 94, 64, 50)
var _pause_index := -1
var _ui_scale := 1.0
var size_percent := 100


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE   # _input 에서 직접 처리
	var layout := layout_for_size(size_percent)
	_ui_scale = layout["scale"]
	joy_radius = layout["joy_radius"]
	joy_center = layout["joy_center"]
	pause_rect = layout["pause_rect"]
	buttons = layout["buttons"]


## 우측 공격 버튼과 조이스틱을 iPhone 가로 노치/홈 인디케이터 안쪽에 배치한다.
static func layout_for_size(percent: int) -> Dictionary:
	var scale := clampf(float(percent) / 100.0, 0.85, 1.2)
	var jr := 92.0 * scale
	var r := 54.0 * scale
	return {
		"scale": scale,
		"joy_radius": jr,
		"joy_center": Vector2(SAFE_EDGE + jr, 720.0 - SAFE_EDGE - jr),
		"pause_rect": Rect2(608, 94, 64, 50),
		"buttons": {
			"light": {"c": Vector2(970, 605), "r": r, "action": "p1_light", "label": "약", "col": UiKit.INK},
			"medium": {"c": Vector2(1072, 574), "r": r, "action": "p1_medium", "label": "중", "col": UiKit.INK},
			"heavy": {"c": Vector2(1160, 522), "r": r + 3.0 * scale, "action": "p1_heavy", "label": "강", "col": UiKit.INK},
			"tech": {"c": Vector2(1008, 493), "r": r - 3.0 * scale, "action": "p1_tech", "label": "기", "col": UiKit.GRAY},
			"super": {"c": Vector2(1108, 454), "r": r - 3.0 * scale, "action": "p1_super", "label": "오의", "col": UiKit.SEAL},
		},
	}


func _exit_tree() -> void:
	_release_all()


func _release_all() -> void:
	for a in _held_actions.keys():
		if InputMap.has_action(a):
			Input.action_release(a)
	_held_actions.clear()


func _press(action: String) -> void:
	if not _held_actions.has(action) and InputMap.has_action(action):
		Input.action_press(action)
		_held_actions[action] = true


func _release(action: String) -> void:
	if _held_actions.has(action) and InputMap.has_action(action):
		Input.action_release(action)
		_held_actions.erase(action)


func _btn_at(pos: Vector2) -> String:
	for name in buttons:
		var b: Dictionary = buttons[name]
		if pos.distance_to(b["c"]) <= b["r"] * 1.18:
			return name
	return ""


func _input(event: InputEvent) -> void:
	# 일시정지/결과 패널이 뜨면 터치를 메뉴에 양보
	if get_tree().paused:
		if not _held_actions.is_empty():
			_release_all()
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			_on_down(event.index, event.position)
		else:
			_on_up(event.index)
	elif event is InputEventScreenDrag:
		if event.index == _joy_index:
			_joy_vec = event.position - joy_center
			_apply_joy()


func _on_down(index: int, pos: Vector2) -> void:
	if pause_rect.has_point(pos):
		_pause_index = index
		return
	# 조이스틱: 화면 좌측 절반
	if pos.x < 620 and _joy_index == -1:
		_joy_index = index
		joy_center = Vector2(
				clampf(pos.x, SAFE_EDGE + joy_radius, 500.0),
				clampf(pos.y, 360.0 + joy_radius * 0.2, 720.0 - SAFE_EDGE - joy_radius))
		_joy_vec = Vector2.ZERO
		_apply_joy()
		accept_event()
		return
	# 공격 버튼
	var name := _btn_at(pos)
	if name != "":
		_btn_touch[index] = name
		_press(buttons[name]["action"])
		accept_event()


func _on_up(index: int) -> void:
	if index == _pause_index:
		_pause_index = -1
		pause_pressed.emit()
		return
	if index == _joy_index:
		_joy_index = -1
		_joy_vec = Vector2.ZERO
		_release("p1_left")
		_release("p1_right")
		_release("p1_up")
		_release("p1_down")
		queue_redraw()
		return
	if _btn_touch.has(index):
		_release(buttons[_btn_touch[index]]["action"])
		_btn_touch.erase(index)
		queue_redraw()


func _apply_joy() -> void:
	var v := _joy_vec
	if v.length() < DEADZONE:
		v = Vector2.ZERO
	# 좌우
	if v.x <= -DIR_THRESH:
		_press("p1_left")
		_release("p1_right")
	elif v.x >= DIR_THRESH:
		_press("p1_right")
		_release("p1_left")
	else:
		_release("p1_left")
		_release("p1_right")
	# 상(점프)/하(숙임)
	if v.y <= -JUMP_THRESH:
		_press("p1_up")
		_release("p1_down")
	elif v.y >= JUMP_THRESH:
		_press("p1_down")
		_release("p1_up")
	else:
		_release("p1_up")
		_release("p1_down")
	queue_redraw()


func _draw() -> void:
	# 조이스틱 베이스
	draw_circle(joy_center, joy_radius, Color(UiKit.INK, 0.08))
	draw_arc(joy_center, joy_radius, 0, TAU, 48, Color(UiKit.INK, 0.35), 2.5)
	# 방향 힌트
	var f := ThemeDB.fallback_font
	for d in [[Vector2(-1, 0), "◀"], [Vector2(1, 0), "▶"], [Vector2(0, -1), "▲ 점프"], [Vector2(0, 1), "▼"]]:
		var dir: Vector2 = d[0]
		var p := joy_center + dir * (joy_radius - 22)
		draw_string(f, p - Vector2(10, -6), d[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(UiKit.INK, 0.4))
	# 노브
	var knob := joy_center + _joy_vec.limit_length(joy_radius - 20)
	draw_circle(knob, 34, Color(UiKit.PAPER_LIGHT, 0.85))
	draw_arc(knob, 34, 0, TAU, 32, Color(UiKit.INK, 0.7), 2.5)

	# 공격 버튼
	for name in buttons:
		var b: Dictionary = buttons[name]
		var pressed: bool = _held_actions.has(b["action"])
		var fill: Color = Color(b["col"], 0.88) if pressed else Color(UiKit.PAPER_LIGHT, 0.60)
		draw_circle(b["c"], b["r"], fill)
		draw_arc(b["c"], b["r"], 0, TAU, 40, Color(b["col"], 0.9), 2.5)
		var tcol: Color = UiKit.PAPER_LIGHT if pressed else b["col"]
		var sz := 26 if b["label"].length() < 2 else 20
		var tw := f.get_string_size(b["label"], HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
		draw_string(f, b["c"] - Vector2(tw * 0.5, -8), b["label"], HORIZONTAL_ALIGNMENT_LEFT, -1, sz, tcol)

	# 일시정지
	draw_rect(pause_rect, Color(UiKit.PAPER_LIGHT, 0.7))
	draw_rect(pause_rect, UiKit.INK, false, 2.0)
	var cx := pause_rect.position.x + pause_rect.size.x * 0.5
	var cy := pause_rect.position.y + pause_rect.size.y * 0.5
	draw_rect(Rect2(cx - 9, cy - 11, 6, 22), UiKit.INK)
	draw_rect(Rect2(cx + 3, cy - 11, 6, 22), UiKit.INK)


## 터치 UI를 보여줄지 판단
static func should_show(enabled: bool = true) -> bool:
	if not enabled:
		return false
	return is_mobile_target()


static func is_mobile_target() -> bool:
	if OS.get_environment("ECLIPSE_TOUCH") == "1":
		return true
	if OS.has_feature("web") or OS.has_feature("mobile"):
		return true
	return DisplayServer.is_touchscreen_available()
