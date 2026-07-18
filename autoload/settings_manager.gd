extends Node
## 설정 저장/적용 + InputMap 구성 + 한글 폰트 폴백.
## 키보드·게임패드가 같은 액션(명령 스트림)에 묶인다 (AC-08).

const SAVE_PATH := "user://settings.json"

# 기본 키보드 배치: P1 = 방향키 이동 + A/S/D 공격 (기술 = A+S 동시 / 패드 버튼)
#                  P2 = J/K/L 이동 + U/I/O 공격 (패드 권장)
const DEFAULT_KEYS := {
	"p1_left": KEY_LEFT, "p1_right": KEY_RIGHT, "p1_up": KEY_UP, "p1_down": KEY_DOWN,
	"p1_light": KEY_A, "p1_medium": KEY_S, "p1_heavy": KEY_D, "p1_tech": 0, "p1_super": KEY_Q,
	"p2_left": KEY_J, "p2_right": KEY_L, "p2_up": KEY_8, "p2_down": KEY_K,
	"p2_light": KEY_U, "p2_medium": KEY_I, "p2_heavy": KEY_O, "p2_tech": 0, "p2_super": KEY_P,
	"pause": KEY_ESCAPE,
}

const ACTION_LABELS := {
	"p1_left": "P1 왼쪽", "p1_right": "P1 오른쪽", "p1_up": "P1 점프", "p1_down": "P1 아래",
	"p1_light": "P1 약베기", "p1_medium": "P1 중베기", "p1_heavy": "P1 강베기", "p1_tech": "P1 기술",
	"p1_super": "P1 오의",
	"p2_left": "P2 왼쪽", "p2_right": "P2 오른쪽", "p2_up": "P2 점프", "p2_down": "P2 아래",
	"p2_light": "P2 약베기", "p2_medium": "P2 중베기", "p2_heavy": "P2 강베기", "p2_tech": "P2 기술",
	"p2_super": "P2 오의",
	"pause": "일시정지",
}

var data := {
	"vol_master": 80, "vol_bgm": 70, "vol_sfx": 80,
	"fx_shake": true, "fx_flash": true, "fx_rumble": true, "fx_highlight": true,
	"cpu_level": 2,
	"keys": {},
}


func _ready() -> void:
	_setup_korean_font()
	load_settings()
	apply_input_map()


func _setup_korean_font() -> void:
	var f := SystemFont.new()
	f.font_names = ["Apple SD Gothic Neo", "AppleGothic", "Malgun Gothic",
		"Noto Sans KR", "Noto Sans CJK KR", "NanumGothic"]
	if f.font_names.is_empty():
		push_warning("시스템 한글 폰트를 찾지 못함 — 기본 폰트로 진행 (AC-10 대체 동작)")
	ThemeDB.fallback_font = f


func load_settings() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		var fa := FileAccess.open(SAVE_PATH, FileAccess.READ)
		var parsed = JSON.parse_string(fa.get_as_text())
		if parsed is Dictionary:
			for k in parsed:
				if data.has(k):
					data[k] = parsed[k]
	if not (data["keys"] is Dictionary):
		data["keys"] = {}


func save_settings() -> void:
	var fa := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	fa.store_string(JSON.stringify(data, "  "))


func key_of(action: String) -> int:
	var stored: Dictionary = data["keys"]
	if stored.has(action):
		return int(stored[action])
	return int(DEFAULT_KEYS.get(action, 0))


func key_label(action: String) -> String:
	var code := key_of(action)
	if code == 0:
		return "패드/조합"
	return OS.get_keycode_string(code)


func rebind(action: String, physical_keycode: int) -> void:
	data["keys"][action] = physical_keycode
	apply_input_map()
	save_settings()


func reset_binds() -> void:
	data["keys"] = {}
	apply_input_map()
	save_settings()


func apply_input_map() -> void:
	for action in DEFAULT_KEYS:
		if InputMap.has_action(action):
			InputMap.action_erase_events(action)
		else:
			InputMap.add_action(action, 0.4)
		var code := key_of(action)
		if code != 0:
			var ev := InputEventKey.new()
			ev.physical_keycode = code as Key
			InputMap.action_add_event(action, ev)
	# 게임패드: P1 = 장치 0, P2 = 장치 1 (키보드와 같은 액션 = 같은 명령 스트림)
	for pi in 2:
		var dev := pi
		var pre := "p%d_" % (pi + 1)
		_joy_axis(pre + "left", dev, JOY_AXIS_LEFT_X, -1.0)
		_joy_axis(pre + "right", dev, JOY_AXIS_LEFT_X, 1.0)
		_joy_axis(pre + "down", dev, JOY_AXIS_LEFT_Y, 1.0)
		_joy_axis(pre + "up", dev, JOY_AXIS_LEFT_Y, -1.0)
		_joy_btn(pre + "left", dev, JOY_BUTTON_DPAD_LEFT)
		_joy_btn(pre + "right", dev, JOY_BUTTON_DPAD_RIGHT)
		_joy_btn(pre + "down", dev, JOY_BUTTON_DPAD_DOWN)
		_joy_btn(pre + "up", dev, JOY_BUTTON_DPAD_UP)
		_joy_btn(pre + "light", dev, JOY_BUTTON_X)
		_joy_btn(pre + "medium", dev, JOY_BUTTON_Y)
		_joy_btn(pre + "heavy", dev, JOY_BUTTON_B)
		_joy_btn(pre + "tech", dev, JOY_BUTTON_A)
		_joy_btn(pre + "super", dev, JOY_BUTTON_LEFT_SHOULDER)
		_joy_btn("pause", dev, JOY_BUTTON_START)


func _joy_btn(action: String, device: int, btn: int) -> void:
	var ev := InputEventJoypadButton.new()
	ev.device = device
	ev.button_index = btn as JoyButton
	InputMap.action_add_event(action, ev)


func _joy_axis(action: String, device: int, axis: int, value: float) -> void:
	var ev := InputEventJoypadMotion.new()
	ev.device = device
	ev.axis = axis as JoyAxis
	ev.axis_value = value
	InputMap.action_add_event(action, ev)


# ---- 볼륨/연출 헬퍼 ----

func sfx_gain() -> float:
	return (data["vol_master"] / 100.0) * (data["vol_sfx"] / 100.0)


func bgm_gain() -> float:
	return (data["vol_master"] / 100.0) * (data["vol_bgm"] / 100.0)
