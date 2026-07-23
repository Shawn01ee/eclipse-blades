extends Control
## 설치나 계정 없이 방 코드로 만나는 온라인 1대1 로비.

var fds: Array = []
var entry_panel: VBoxContainer
var room_panel: VBoxContainer
var code_input: LineEdit
var status_label: Label
var players_label: Label
var ping_label: Label
var fighter_buttons: Array = []
var ready_button: Button


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	fds = Registry.load_all()
	_build_entry()
	_build_room()
	OnlineSession.connection_changed.connect(_on_connection_changed)
	OnlineSession.room_changed.connect(_refresh)
	OnlineSession.match_started.connect(_on_match_started)
	OnlineSession.network_error.connect(_show_error)
	_refresh()


func _build_entry() -> void:
	entry_panel = VBoxContainer.new()
	entry_panel.position = Vector2(400, 220)
	entry_panel.size = Vector2(480, 390)
	entry_panel.add_theme_constant_override("separation", 12)
	add_child(entry_panel)

	var explainer := UiKit.label("친구 한 명과 방 코드를 공유해 대전합니다", 19, UiKit.GRAY)
	explainer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	entry_panel.add_child(explainer)
	entry_panel.add_child(UiKit.vspace(10))
	var create := UiKit.button("방 만들기", 30)
	create.custom_minimum_size = Vector2(480, 64)
	create.pressed.connect(_create_room)
	entry_panel.add_child(create)

	var divider := UiKit.label("— 또는 받은 코드 입력 —", 17, UiKit.GRAY)
	divider.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	entry_panel.add_child(divider)
	code_input = LineEdit.new()
	code_input.placeholder_text = "방 코드 4자리 숫자"
	code_input.max_length = 4
	code_input.alignment = HORIZONTAL_ALIGNMENT_CENTER
	code_input.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER
	code_input.virtual_keyboard_enabled = true
	code_input.virtual_keyboard_show_on_focus = true
	code_input.add_theme_font_size_override("font_size", 30)
	code_input.add_theme_color_override("font_color", UiKit.INK)
	code_input.add_theme_color_override("font_placeholder_color", UiKit.GRAY)
	var input_box := StyleBoxFlat.new()
	input_box.bg_color = Color(UiKit.PAPER_LIGHT, 0.82)
	input_box.border_color = UiKit.INK_FAINT
	input_box.set_border_width_all(2)
	input_box.set_corner_radius_all(2)
	code_input.add_theme_stylebox_override("normal", input_box)
	var input_focus: StyleBoxFlat = input_box.duplicate()
	input_focus.border_color = UiKit.SEAL
	input_focus.set_border_width_all(3)
	code_input.add_theme_stylebox_override("focus", input_focus)
	code_input.custom_minimum_size = Vector2(480, 58)
	code_input.text_changed.connect(func(value: String):
		var clean := OnlineSession.sanitize_room_code(value)
		if clean != value:
			code_input.text = clean
			code_input.caret_column = clean.length())
	code_input.text_submitted.connect(func(_value: String): _join_room())
	code_input.gui_input.connect(_on_code_input_event)
	entry_panel.add_child(code_input)
	var join_row := HBoxContainer.new()
	join_row.add_theme_constant_override("separation", 12)
	entry_panel.add_child(join_row)
	var paste := UiKit.button("코드 붙여넣기", 22)
	paste.custom_minimum_size = Vector2(234, 60)
	paste.pressed.connect(_paste_code)
	join_row.add_child(paste)
	var join := UiKit.button("방 참가", 28)
	join.custom_minimum_size = Vector2(234, 60)
	join.pressed.connect(_join_room)
	join_row.add_child(join)
	var back := UiKit.button("뒤로", 22)
	back.pressed.connect(_back_to_menu)
	entry_panel.add_child(back)


func _build_room() -> void:
	room_panel = VBoxContainer.new()
	room_panel.position = Vector2(100, 132)
	room_panel.size = Vector2(1080, 520)
	room_panel.add_theme_constant_override("separation", 10)
	room_panel.visible = false
	add_child(room_panel)

	var header := HBoxContainer.new()
	header.alignment = BoxContainer.ALIGNMENT_CENTER
	header.add_theme_constant_override("separation", 18)
	room_panel.add_child(header)
	status_label = UiKit.label("서버 연결 중", 22, UiKit.GRAY)
	status_label.custom_minimum_size = Vector2(390, 46)
	status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(status_label)
	var copy := UiKit.button("방 코드 복사", 20)
	copy.pressed.connect(_copy_code)
	header.add_child(copy)
	ping_label = UiKit.label("", 16, UiKit.GRAY)
	ping_label.custom_minimum_size = Vector2(130, 46)
	ping_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(ping_label)

	players_label = UiKit.label("", 20, UiKit.INK)
	players_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	room_panel.add_child(players_label)

	var fighter_row := HBoxContainer.new()
	fighter_row.alignment = BoxContainer.ALIGNMENT_CENTER
	fighter_row.add_theme_constant_override("separation", 12)
	room_panel.add_child(fighter_row)
	for i in fds.size():
		var fd: FighterData = fds[i]
		var button := UiKit.button(fd.display_name + "\n" + fd.weapon_name, 20)
		button.custom_minimum_size = Vector2(190, 112)
		button.pressed.connect(_choose.bind(i))
		fighter_row.add_child(button)
		fighter_buttons.append(button)

	var note := UiKit.label("검객을 고른 뒤 준비를 누르세요 · 양쪽이 준비하면 동시에 시작", 18, UiKit.GRAY)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	room_panel.add_child(note)
	ready_button = UiKit.button("준비", 30)
	ready_button.custom_minimum_size = Vector2(480, 66)
	ready_button.pressed.connect(_toggle_ready)
	ready_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	room_panel.add_child(ready_button)
	var leave := UiKit.button("방 나가기", 20)
	leave.pressed.connect(_leave_room)
	leave.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	room_panel.add_child(leave)


func _create_room() -> void:
	AudioManager.play("ui_ok")
	OnlineSession.connect_room(OnlineSession.make_room_code())
	_refresh()


func _join_room() -> void:
	AudioManager.play("ui_ok")
	if OnlineSession.connect_room(code_input.text):
		_refresh()


func _on_code_input_event(event: InputEvent) -> void:
	if event is InputEventScreenTouch and event.pressed:
		code_input.grab_focus()
		DisplayServer.virtual_keyboard_show(code_input.text, code_input.get_global_rect(),
				DisplayServer.KEYBOARD_TYPE_NUMBER, OnlineSession.ROOM_CODE_LEN, code_input.caret_column, code_input.caret_column)
		code_input.accept_event()


func _paste_code() -> void:
	AudioManager.play("ui_move")
	var clean := OnlineSession.sanitize_room_code(DisplayServer.clipboard_get())
	if clean.length() != OnlineSession.ROOM_CODE_LEN:
		_show_error("복사한 방 코드를 찾지 못했습니다.")
		return
	code_input.text = clean
	code_input.caret_column = clean.length()


func _choose(index: int) -> void:
	AudioManager.play("ui_move")
	OnlineSession.choose_character(index)


func _toggle_ready() -> void:
	if OnlineSession.role < 0 or OnlineSession.peer_count < 2:
		_show_error("상대가 들어올 때까지 기다려주세요.")
		return
	AudioManager.play("ui_ok")
	OnlineSession.set_ready(not OnlineSession.ready_players[OnlineSession.role])


func _copy_code() -> void:
	DisplayServer.clipboard_set(OnlineSession.room_code)
	_show_error("방 코드가 복사되었습니다.")


func _leave_room() -> void:
	OnlineSession.disconnect_session()
	_refresh()


func _back_to_menu() -> void:
	OnlineSession.disconnect_session()
	GameState.goto("menu")


func _on_connection_changed(_new_status: String) -> void:
	_refresh()


func _on_match_started() -> void:
	GameState.mode = GameState.Mode.ONLINE
	GameState.p1_char = OnlineSession.selections[0]
	GameState.p2_char = OnlineSession.selections[1]
	GameState.goto("match")


func _show_error(message: String) -> void:
	if status_label != null and room_panel.visible:
		status_label.text = message
	elif code_input != null:
		code_input.placeholder_text = message


func _refresh() -> void:
	if entry_panel == null:
		return
	var in_room := OnlineSession.status not in ["idle", "error", "disconnected"]
	entry_panel.visible = not in_room
	room_panel.visible = in_room
	if not in_room:
		queue_redraw()
		return
	var role_name := "방장" if OnlineSession.role == 0 else ("참가자" if OnlineSession.role == 1 else "연결 중")
	status_label.text = "방 %s · %s" % [OnlineSession.room_code, role_name]
	ping_label.text = ("지연 %dms" % OnlineSession.ping_ms) if OnlineSession.ping_ms >= 0 else "지연 측정 중"
	var names := ["—", "—"]
	for slot in 2:
		var index: int = clampi(OnlineSession.selections[slot], 0, fds.size() - 1)
		names[slot] = fds[index].display_name + (" ✓" if OnlineSession.ready_players[slot] else "")
	players_label.text = "P1  %s     대     P2  %s" % [names[0], names[1]]
	for i in fighter_buttons.size():
		var selected: bool = OnlineSession.role >= 0 and OnlineSession.selections[OnlineSession.role] == i
		fighter_buttons[i].modulate = Color.WHITE if selected else Color(1, 1, 1, 0.58)
		fighter_buttons[i].disabled = OnlineSession.role < 0 or OnlineSession.status == "starting"
	var mine_ready: bool = OnlineSession.role >= 0 and OnlineSession.ready_players[OnlineSession.role]
	ready_button.text = "준비 취소" if mine_ready else "준비"
	ready_button.disabled = OnlineSession.peer_count < 2 or OnlineSession.role < 0
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		_back_to_menu()


func _draw() -> void:
	draw_rect(Rect2(0, 0, 1280, 720), UiKit.PAPER)
	for k in 9:
		UiKit.dry_stroke(self, Vector2(70, 75 + k * 70.0), 1140, UiKit.INK_FAINT, 820 + k)
	var f := ThemeDB.fallback_font
	draw_string(f, Vector2(90, 90), "온라인 검담", HORIZONTAL_ALIGNMENT_LEFT, -1, 44, UiKit.INK)
	draw_string(f, Vector2(90, 121), "방 코드 1대1 · 입력 동기화", HORIZONTAL_ALIGNMENT_LEFT, -1, 17, UiKit.GRAY)
	draw_rect(Rect2(1118, 66, 64, 64), UiKit.SEAL)
	draw_string(f, Vector2(1128, 108), "연결", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, UiKit.PAPER_LIGHT)
