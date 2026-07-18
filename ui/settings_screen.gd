extends Control
## 설정: 볼륨 / 연출 토글(AC-11) / CPU 난이도 / 키 리맵.

var capturing := ""
var key_buttons := {}


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.offset_left = 340
	scroll.offset_right = -340
	scroll.offset_top = 90
	scroll.offset_bottom = -20
	add_child(scroll)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 10)
	scroll.add_child(v)

	v.add_child(UiKit.label("소리", 30))
	_slider(v, "마스터", "vol_master")
	_slider(v, "배경 음악", "vol_bgm")
	_slider(v, "효과음", "vol_sfx")
	v.add_child(UiKit.vspace(14))

	v.add_child(UiKit.label("연출", 30))
	_toggle(v, "화면 흔들림", "fx_shake")
	_toggle(v, "히트 플래시", "fx_flash")
	_toggle(v, "패드 진동", "fx_rumble")
	_toggle(v, "정타 하이라이트", "fx_highlight")
	v.add_child(UiKit.vspace(14))

	v.add_child(UiKit.label("대전", 30))
	_slider(v, "CPU 난이도", "cpu_level", 1, 4)
	v.add_child(UiKit.vspace(14))

	v.add_child(UiKit.label("조작 (키보드 리맵)", 30))
	v.add_child(UiKit.label("기술은 패드 버튼 또는 약+중 동시 입력으로도 나갑니다.", 14, UiKit.GRAY))
	for action in SettingsManager.ACTION_LABELS:
		_key_row(v, action)
	v.add_child(UiKit.vspace(14))

	var reset := UiKit.button("키 기본값 복원", 22)
	reset.pressed.connect(func():
		SettingsManager.reset_binds()
		_refresh_keys())
	v.add_child(reset)
	var back := UiKit.button("뒤로", 22)
	back.pressed.connect(func(): GameState.goto("menu"))
	v.add_child(back)
	back.grab_focus()


func _slider(v: VBoxContainer, text: String, key: String, lo := 0, hi := 100) -> void:
	var h := HBoxContainer.new()
	var l := UiKit.label(text, 20)
	l.custom_minimum_size = Vector2(180, 0)
	h.add_child(l)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = 1 if hi <= 10 else 5
	s.value = int(SettingsManager.data[key])
	s.custom_minimum_size = Vector2(300, 24)
	s.value_changed.connect(func(val):
		SettingsManager.data[key] = int(val)
		if key == "cpu_level":
			GameState.cpu_level = int(val)
		SettingsManager.save_settings())
	h.add_child(s)
	var vl := UiKit.label(str(int(s.value)), 18, UiKit.GRAY)
	vl.custom_minimum_size = Vector2(50, 0)
	s.value_changed.connect(func(val): vl.text = str(int(val)))
	h.add_child(vl)
	v.add_child(h)


func _toggle(v: VBoxContainer, text: String, key: String) -> void:
	var row := HBoxContainer.new()
	var l := UiKit.label(text, 20)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	var c := CheckButton.new()
	c.button_pressed = bool(SettingsManager.data[key])
	c.toggled.connect(func(on):
		SettingsManager.data[key] = on
		SettingsManager.save_settings())
	row.add_child(c)
	v.add_child(row)


func _key_row(v: VBoxContainer, action: String) -> void:
	var h := HBoxContainer.new()
	var l := UiKit.label(SettingsManager.ACTION_LABELS[action], 18)
	l.custom_minimum_size = Vector2(220, 0)
	h.add_child(l)
	var b := UiKit.button(SettingsManager.key_label(action), 18)
	b.custom_minimum_size = Vector2(200, 0)
	b.pressed.connect(func():
		capturing = action
		b.text = "키를 누르세요…")
	h.add_child(b)
	key_buttons[action] = b
	v.add_child(h)


func _refresh_keys() -> void:
	for action in key_buttons:
		key_buttons[action].text = SettingsManager.key_label(action)


func _unhandled_key_input(event: InputEvent) -> void:
	if capturing == "":
		if event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE:
			GameState.goto("menu")
		return
	if event is InputEventKey and event.pressed:
		if event.physical_keycode != KEY_ESCAPE:
			SettingsManager.rebind(capturing, event.physical_keycode)
		capturing = ""
		_refresh_keys()
		get_viewport().set_input_as_handled()


func _draw() -> void:
	draw_rect(Rect2(0, 0, 1280, 720), UiKit.PAPER)
	var f := ThemeDB.fallback_font
	draw_string(f, Vector2(340, 62), "설정", HORIZONTAL_ALIGNMENT_LEFT, -1, 40, UiKit.INK)
	draw_string(f, Vector2(430, 62), "ESC 뒤로", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, UiKit.GRAY)
