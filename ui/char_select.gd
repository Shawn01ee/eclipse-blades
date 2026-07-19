extends Control
## 캐릭터 선택: 좌우 상세 패널 + 중앙 3×2 로스터.
## 일러스트가 없는 파이터는 교체 가능한 절차 실루엣을 사용한다.

const GRID_COLUMNS := 3
const CARD_SIZE := Vector2(162, 94)
const CARD_GAP := Vector2(12, 14)
const LEFT_DETAIL_RECT := Rect2(28, 94, 300, 440)
const RIGHT_DETAIL_RECT := Rect2(952, 94, 300, 440)
const STAGE_RECT := Rect2(370, 360, 512, 174)


class PortraitPlate:
	extends Control
	var fighter: FighterData
	var portrait: Texture2D

	func set_fighter(fd: FighterData, tex: Texture2D) -> void:
		fighter = fd
		portrait = tex
		queue_redraw()

	func _draw() -> void:
		if fighter == null:
			return
		draw_rect(Rect2(Vector2.ZERO, size), Color(UiKit.PAPER_DIM, 0.55))
		if portrait != null:
			var image_size := Vector2(portrait.get_width(), portrait.get_height())
			var target_ratio := size.x / size.y
			var source := Rect2(Vector2.ZERO, image_size)
			if image_size.x / image_size.y > target_ratio:
				source.size.x = image_size.y * target_ratio
				source.position.x = (image_size.x - source.size.x) * 0.5
			else:
				source.size.y = image_size.x / target_ratio
				source.position.y = (image_size.y - source.size.y) * 0.5
			draw_texture_rect_region(portrait, Rect2(Vector2.ZERO, size), source)
			draw_rect(Rect2(0, size.y - 46, size.x, 46), Color(UiKit.PAPER_LIGHT, 0.72))
			return

		# 새 일러스트가 들어오기 전에도 캐릭터 체급과 무기 성격이 보이는 임시 실루엣.
		for k in 9:
			var x := -size.y + float(k) * 54.0
			draw_line(Vector2(x, size.y), Vector2(x + size.y, 0), Color(fighter.color, 0.12), 2.0)
		var center := Vector2(size.x * 0.5, size.y * 0.42)
		var bulky := 1.16 if fighter.id == "mujin" else (1.08 if fighter.id == "jiko" else 1.0)
		var body_col := fighter.color.lerp(UiKit.INK, 0.22)
		draw_circle(center + Vector2(0, -62), 22.0 * bulky, UiKit.INK)
		draw_circle(center + Vector2(2, -59), 16.0 * bulky, Color(0.67, 0.55, 0.43))
		var robe := PackedVector2Array([
			center + Vector2(-37, -38) * bulky, center + Vector2(33, -38) * bulky,
			center + Vector2(51, 92) * bulky, center + Vector2(-52, 92) * bulky,
		])
		draw_polygon(robe, [body_col])
		var outline := robe.duplicate()
		outline.append(robe[0])
		draw_polyline(outline, UiKit.INK, 4.0)
		var grip := center + Vector2(18, -18)
		var tip := center + Vector2(110, -94)
		if fighter.id == "daeru":
			tip = center + Vector2(126, -126)
		elif fighter.id == "myo":
			tip = center + Vector2(124, -30)
		draw_line(grip, tip, UiKit.INK, 8.0, true)
		draw_line(grip + (tip - grip).normalized() * 12.0, tip, UiKit.PAPER_LIGHT, 3.0, true)
		if fighter.id == "jiko":
			for k in 3:
				var off := Vector2(-20.0 + k * 18.0, 28.0 + k * 7.0)
				draw_line(center + off, center + off + Vector2(92, -52), Color(UiKit.SEAL, 0.34), 3.0)


var fds: Array = []
var step := 0            # 0 P1 선택 / 1 상대 선택 / 2 CPU 난이도
var p1_sel := 0
var p2_sel := 1
var cpu_level := 2
var cards: Array = []
var prompt: Label
var diff_label: Label
var touch_bar: HBoxContainer
var nav_bar: HBoxContainer
var confirm_button: Button
var left_detail: Dictionary
var right_detail: Dictionary
var _portraits := {}
var _last_card_touch_ms := -1000


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	fds = Registry.load_all()
	cpu_level = GameState.cpu_level
	p2_sel = 1 if fds.size() > 1 else 0

	left_detail = _make_detail(LEFT_DETAIL_RECT, "1P", UiKit.SEAL)
	right_detail = _make_detail(RIGHT_DETAIL_RECT,
			"2P" if GameState.mode == GameState.Mode.VS_2P else "CPU", UiKit.INK)

	for k in fds.size():
		var row := k / GRID_COLUMNS
		var col := k % GRID_COLUMNS
		var card := Panel.new()
		card.position = Vector2(370 + col * (CARD_SIZE.x + CARD_GAP.x),
				124 + row * (CARD_SIZE.y + CARD_GAP.y))
		card.size = CARD_SIZE
		card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		card.gui_input.connect(_on_card_input.bind(k))
		add_child(card)

		var slot := UiKit.label(str(k + 1).pad_zeros(2), 13, UiKit.GRAY)
		slot.position = Vector2(10, 7)
		slot.size = Vector2(34, 18)
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(slot)
		var name_l := UiKit.label(fds[k].display_name, 23)
		name_l.position = Vector2(8, 25)
		name_l.size = Vector2(CARD_SIZE.x - 16, 30)
		name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(name_l)
		var weapon_l := UiKit.label(fds[k].weapon_name, 14, UiKit.GRAY)
		weapon_l.position = Vector2(8, 58)
		weapon_l.size = Vector2(CARD_SIZE.x - 16, 22)
		weapon_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		weapon_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(weapon_l)
		var marker := UiKit.label("", 13, UiKit.SEAL)
		marker.position = Vector2(CARD_SIZE.x - 74, 7)
		marker.size = Vector2(64, 18)
		marker.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(marker)
		cards.append({"panel": card, "marker": marker})

	var stage_panel := Panel.new()
	stage_panel.position = STAGE_RECT.position
	stage_panel.size = STAGE_RECT.size
	stage_panel.add_theme_stylebox_override("panel", _panel_style(UiKit.INK, 3, Color(UiKit.PAPER_LIGHT, 0.58)))
	stage_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(stage_panel)
	var stage_kicker := UiKit.label("STAGE 01", 14, UiKit.SEAL)
	stage_kicker.position = Vector2(18, 15)
	stage_kicker.size = Vector2(150, 20)
	stage_panel.add_child(stage_kicker)
	var stage_name := UiKit.label("달 그림자 나루", 25)
	stage_name.position = Vector2(18, 38)
	stage_name.size = Vector2(476, 34)
	stage_panel.add_child(stage_name)
	var stage_note := UiKit.label("현재 스테이지 고정 · 이후 선택 추가", 15, UiKit.GRAY)
	stage_note.position = Vector2(18, 132)
	stage_note.size = Vector2(476, 24)
	stage_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	stage_panel.add_child(stage_note)

	diff_label = UiKit.label("", 20)
	diff_label.position = Vector2(340, 548)
	diff_label.size = Vector2(600, 32)
	diff_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(diff_label)
	prompt = UiKit.label("", 17, UiKit.GRAY)
	prompt.position = Vector2(210, 583)
	prompt.size = Vector2(860, 30)
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(prompt)

	nav_bar = HBoxContainer.new()
	nav_bar.position = Vector2(432, 625)
	nav_bar.size = Vector2(416, 58)
	nav_bar.add_theme_constant_override("separation", 16)
	add_child(nav_bar)
	confirm_button = _add_button(nav_bar, "확정", _confirm_current, 200)
	_add_button(nav_bar, "취소", _back_step, 200)

	# CPU 난이도 역시 키보드 없이 마칠 수 있다.
	touch_bar = HBoxContainer.new()
	touch_bar.position = Vector2(340, 625)
	touch_bar.size = Vector2(600, 58)
	touch_bar.add_theme_constant_override("separation", 8)
	add_child(touch_bar)
	_add_touch_button("◀ 난이도", func(): _change_cpu(-1), 135)
	_add_touch_button("시작", _start, 150)
	_add_touch_button("난이도 ▶", func(): _change_cpu(1), 135)
	_add_touch_button("취소", _back_step, 130)
	_refresh()


func _make_detail(rect: Rect2, marker_text: String, accent: Color) -> Dictionary:
	var panel := Panel.new()
	panel.position = rect.position
	panel.size = rect.size
	panel.clip_contents = true
	panel.add_theme_stylebox_override("panel", _panel_style(accent, 3, Color(UiKit.PAPER_LIGHT, 0.76)))
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)
	var plate := PortraitPlate.new()
	plate.position = Vector2(3, 3)
	plate.size = Vector2(rect.size.x - 6, 292)
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(plate)
	var marker := UiKit.label(marker_text, 18, accent)
	marker.position = Vector2(14, 10)
	marker.size = Vector2(90, 26)
	marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(marker)
	var ready := UiKit.label("ILLUSTRATION / 교체 예정", 12, Color(accent, 0.82))
	ready.position = Vector2(12, 270)
	ready.size = Vector2(rect.size.x - 24, 18)
	ready.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ready.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(ready)
	var name_l := UiKit.label("", 29)
	name_l.position = Vector2(16, 305)
	name_l.size = Vector2(rect.size.x - 32, 38)
	name_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(name_l)
	var weapon_l := UiKit.label("", 17, accent)
	weapon_l.position = Vector2(16, 345)
	weapon_l.size = Vector2(rect.size.x - 32, 24)
	weapon_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(weapon_l)
	var style_l := UiKit.label("", 14, UiKit.GRAY)
	style_l.position = Vector2(16, 374)
	style_l.size = Vector2(rect.size.x - 32, 52)
	style_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	style_l.max_lines_visible = 2
	style_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(style_l)
	return {"panel": panel, "plate": plate, "marker": marker,
			"name": name_l, "weapon": weapon_l, "style": style_l}


func _panel_style(border: Color, width: int, background: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = background
	box.border_color = border
	box.set_border_width_all(width)
	return box


func _add_button(parent: HBoxContainer, text: String, callback: Callable, width: int) -> Button:
	var button := UiKit.button(text, 21)
	button.custom_minimum_size = Vector2(width, 56)
	button.pressed.connect(callback)
	parent.add_child(button)
	return button


func _add_touch_button(text: String, callback: Callable, width: int) -> void:
	_add_button(touch_bar, text, callback, width)


func _on_card_input(event: InputEvent, index: int) -> void:
	# Web에서 한 손가락 입력 뒤 호환 MouseButton이 한 번 더 올 수 있다.
	if event is InputEventScreenTouch:
		if not event.pressed:
			return
		_last_card_touch_ms = Time.get_ticks_msec()
	elif event is InputEventMouseButton:
		if event.button_index != MOUSE_BUTTON_LEFT or not event.pressed \
				or Time.get_ticks_msec() - _last_card_touch_ms < 500:
			return
	else:
		return
	if step == 2:
		return
	get_viewport().set_input_as_handled()
	if step == 0:
		p1_sel = index
	else:
		p2_sel = index
	AudioManager.play("ui_move")
	_refresh()


func _confirm_current() -> void:
	AudioManager.play("ui_ok")
	if step == 0:
		step = 1
	elif step == 1:
		if GameState.mode == GameState.Mode.VS_2P:
			_start()
			return
		step = 2
	else:
		_start()
	_refresh()


func _change_cpu(delta: int) -> void:
	cpu_level = clampi(cpu_level + delta, 1, CpuBrain.MAX_LEVEL)
	AudioManager.play("ui_move")
	_refresh()


func _back_step() -> void:
	AudioManager.play("ui_move")
	if step == 0:
		GameState.goto("menu")
		return
	step -= 1
	_refresh()


func _portrait(id: String) -> Texture2D:
	if _portraits.has(id):
		return _portraits[id]
	var tex: Texture2D = null
	for ext in ["png", "jpg", "jpeg", "webp"]:
		var path := "res://art/portraits/%s.%s" % [id, ext]
		if ResourceLoader.exists(path):
			tex = load(path)
			break
		var abs_path := ProjectSettings.globalize_path(path)
		if FileAccess.file_exists(abs_path):
			var img := Image.load_from_file(abs_path)
			if img != null:
				tex = ImageTexture.create_from_image(img)
				break
	_portraits[id] = tex
	return tex


func _refresh_detail(detail: Dictionary, fd: FighterData) -> void:
	detail["plate"].set_fighter(fd, _portrait(fd.id))
	detail["name"].text = "%s  %s" % [fd.display_name, fd.id.to_upper()]
	detail["weapon"].text = "%s · HP %d" % [fd.weapon_name, fd.max_hp]
	detail["style"].text = fd.style_note


func _refresh() -> void:
	_refresh_detail(left_detail, fds[p1_sel])
	_refresh_detail(right_detail, fds[p2_sel])
	left_detail["panel"].add_theme_stylebox_override("panel",
			_panel_style(UiKit.SEAL, 5 if step == 0 else 3, Color(UiKit.PAPER_LIGHT, 0.76)))
	right_detail["panel"].add_theme_stylebox_override("panel",
			_panel_style(UiKit.INK, 5 if step == 1 else 3, Color(UiKit.PAPER_LIGHT, 0.76)))

	for k in cards.size():
		var is_p1 := k == p1_sel
		var is_p2 := k == p2_sel
		var marker_parts: Array[String] = []
		if is_p1:
			marker_parts.append("1P")
		if is_p2:
			marker_parts.append("2P" if GameState.mode == GameState.Mode.VS_2P else "CPU")
		cards[k]["marker"].text = "·".join(marker_parts)
		var active := (step == 0 and is_p1) or (step >= 1 and is_p2)
		var border := UiKit.SEAL if is_p1 else (UiKit.INK if is_p2 else UiKit.INK_FAINT)
		var bg := Color(fds[k].color, 0.16 if active else 0.07)
		cards[k]["panel"].add_theme_stylebox_override("panel",
				_panel_style(border, 4 if active else (2 if is_p1 or is_p2 else 1), bg))

	var is_cpu := GameState.mode != GameState.Mode.VS_2P
	if step == 2 and is_cpu:
		diff_label.text = "CPU 난이도  %d / %d" % [cpu_level, CpuBrain.MAX_LEVEL]
		diff_label.add_theme_color_override("font_color", UiKit.SEAL if cpu_level >= 4 else UiKit.INK)
		prompt.text = "4단계부터 반응·압박·방어가 크게 강화됩니다"
	else:
		diff_label.add_theme_color_override("font_color", UiKit.INK)
		var selected: int = p1_sel if step == 0 else p2_sel
		var sm: MoveData = fds[selected].moves["medium"]
		var sh: MoveData = fds[selected].moves["heavy"]
		var st: MoveData = fds[selected].moves["tech"]
		diff_label.text = "중 %s  ·  강 %s  ·  기술 %s" % [sm.display_name, sh.display_name, st.display_name]
		prompt.text = "P1 검객 선택 · 카드 터치/←→ · 확정" if step == 0 else \
				("P2 검객 선택 · J/L · 확정" if GameState.mode == GameState.Mode.VS_2P \
				else "CPU 상대 선택 · 카드 터치/←→ · 확정")
	nav_bar.visible = step != 2
	touch_bar.visible = step == 2 and is_cpu
	confirm_button.text = "P1 확정" if step == 0 else "상대 확정"
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		_back_step()
		return
	var is_2p := GameState.mode == GameState.Mode.VS_2P
	match step:
		0:
			if event.is_action_pressed("p1_left") or event.is_action_pressed("p1_right"):
				var delta := -1 if event.is_action_pressed("p1_left") else 1
				p1_sel = posmod(p1_sel + delta, fds.size())
				AudioManager.play("ui_move")
			elif event.is_action_pressed("p1_light"):
				_confirm_current()
		1:
			var pre := "p2_" if is_2p else "p1_"
			if event.is_action_pressed(pre + "left") or event.is_action_pressed(pre + "right"):
				var delta := -1 if event.is_action_pressed(pre + "left") else 1
				p2_sel = posmod(p2_sel + delta, fds.size())
				AudioManager.play("ui_move")
			elif event.is_action_pressed(pre + "light"):
				_confirm_current()
			elif event.is_action_pressed(pre + "heavy"):
				_back_step()
		2:
			if event.is_action_pressed("p1_left"):
				_change_cpu(-1)
			elif event.is_action_pressed("p1_right"):
				_change_cpu(1)
			elif event.is_action_pressed("p1_light"):
				_start()
			elif event.is_action_pressed("p1_heavy"):
				_back_step()
	_refresh()


func _start() -> void:
	GameState.p1_char = p1_sel
	GameState.p2_char = p2_sel
	GameState.cpu_level = cpu_level
	SettingsManager.data["cpu_level"] = cpu_level
	SettingsManager.save_settings()
	GameState.goto("match")


func _draw() -> void:
	draw_rect(Rect2(0, 0, 1280, 720), UiKit.PAPER)
	for k in 8:
		UiKit.dry_stroke(self, Vector2(40, 74 + k * 82.0), 1200, UiKit.INK_FAINT, 300 + k)
	var f := ThemeDB.fallback_font
	draw_string(f, Vector2(0, 49), "캐릭터 선택  CHARACTER SELECT",
			HORIZONTAL_ALIGNMENT_CENTER, 1280, 30, UiKit.INK)
	var mode_name: String = {GameState.Mode.VS_2P: "대전 — 2인",
			GameState.Mode.VS_CPU: "대전 — CPU", GameState.Mode.TRAINING: "훈련"}[GameState.mode]
	draw_string(f, Vector2(0, 78), mode_name, HORIZONTAL_ALIGNMENT_CENTER, 1280, 15, UiKit.GRAY)

	# 스테이지 미리보기: 실제 무대의 산·나루 실루엣을 작은 프레임으로 축약.
	var stage_origin := STAGE_RECT.position + Vector2(3, 3)
	var stage_size := STAGE_RECT.size - Vector2(6, 6)
	draw_rect(Rect2(stage_origin, stage_size), Color(UiKit.PAPER_DIM, 0.38))
	var ridge := PackedVector2Array([
		stage_origin + Vector2(0, 113), stage_origin + Vector2(84, 66),
		stage_origin + Vector2(162, 103), stage_origin + Vector2(260, 50),
		stage_origin + Vector2(356, 108), stage_origin + Vector2(stage_size.x, 82),
		stage_origin + Vector2(stage_size.x, 125), stage_origin + Vector2(0, 125),
	])
	draw_polygon(ridge, [Color(UiKit.GRAY, 0.20)])
	draw_line(stage_origin + Vector2(18, 124), stage_origin + Vector2(stage_size.x - 18, 124),
			Color(UiKit.INK, 0.32), 2.0)
