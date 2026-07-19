extends Control
## 캐릭터 선택: P1 → 상대(P2/CPU) → (CPU 난이도) → 시작.
## art/portraits/<id>.png 가 있으면 초상화로 사용, 없으면 먹 실루엣 카드.

var fds: Array = []
var step := 0            # 0 P1 선택 / 1 상대 선택 / 2 CPU 난이도 / 3 시작
var p1_sel := 0
var p2_sel := 1
var cpu_level := 2
var cards: Array = []
var prompt: Label
var diff_label: Label
var touch_bar: HBoxContainer
var _portraits := {}
var _last_card_touch_ms := -1000


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	fds = Registry.load_all()
	cpu_level = GameState.cpu_level
	p2_sel = 1 if fds.size() > 1 else 0

	# 카드 크기를 인원수에 맞춰 조정 (2~5명)
	var n := fds.size()
	var gap := 28
	var total_w := 1160
	var card_w: int = clampi((total_w - gap * (n - 1)) / maxi(n, 1), 200, 360)
	# 제목·카드·하단 안내가 서로 침범하지 않는 고정 안전영역.
	var card_h := 380
	var img_h := 220
	var row_w := card_w * n + gap * (n - 1)
	var h := HBoxContainer.new()
	h.position = Vector2((1280 - row_w) / 2.0, 150)
	h.add_theme_constant_override("separation", gap)
	add_child(h)
	for k in n:
		var fd: FighterData = fds[k]
		var card := PanelContainer.new()
		card.custom_minimum_size = Vector2(card_w, card_h)
		card.add_theme_stylebox_override("panel", UiKit.panel_box())
		card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		card.gui_input.connect(_on_card_input.bind(k))
		var v := VBoxContainer.new()
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(v)
		var tex := _portrait(fd.id)
		if tex != null:
			var tr := TextureRect.new()
			tr.texture = tex
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			tr.clip_contents = true
			tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
			tr.custom_minimum_size = Vector2(card_w - 40, img_h)
			v.add_child(tr)
		else:
			var ph := ColorRect.new()
			ph.color = Color(fd.color, 0.9) if fd.color.v < 0.5 else Color(UiKit.GRAY, 0.35)
			ph.mouse_filter = Control.MOUSE_FILTER_IGNORE
			ph.custom_minimum_size = Vector2(card_w - 40, img_h)
			v.add_child(ph)
		var name_l := UiKit.label(fd.display_name, 30)
		name_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(name_l)
		var wname := UiKit.label(fd.weapon_name, 17, UiKit.SEAL)
		wname.mouse_filter = Control.MOUSE_FILTER_IGNORE
		wname.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(wname)
		var wep := UiKit.label(fd.style_note, 13, UiKit.GRAY)
		wep.mouse_filter = Control.MOUSE_FILTER_IGNORE
		wep.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		wep.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		wep.max_lines_visible = 2
		wep.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		v.add_child(wep)
		h.add_child(card)
		cards.append(card)

	diff_label = UiKit.label("", 26)
	diff_label.position = Vector2(0, 545)
	diff_label.size = Vector2(1280, 40)
	diff_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(diff_label)
	prompt = UiKit.label("", 20, UiKit.GRAY)
	prompt.position = Vector2(0, 600)
	prompt.size = Vector2(1280, 40)
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(prompt)

	# CPU 난이도와 시작을 키보드 없이 마칠 수 있는 하단 터치 바.
	touch_bar = HBoxContainer.new()
	touch_bar.position = Vector2(356, 590)
	touch_bar.size = Vector2(568, 58)
	touch_bar.add_theme_constant_override("separation", 8)
	add_child(touch_bar)
	_add_touch_button("◀ 난이도", func(): _change_cpu(-1), 130)
	_add_touch_button("시작", _start, 150)
	_add_touch_button("난이도 ▶", func(): _change_cpu(1), 130)
	_add_touch_button("뒤로", _back_step, 130)
	_refresh()


func _add_touch_button(text: String, callback: Callable, width: int) -> void:
	var button := UiKit.button(text, 21)
	button.custom_minimum_size = Vector2(width, 56)
	button.pressed.connect(callback)
	touch_bar.add_child(button)


func _on_card_input(event: InputEvent, index: int) -> void:
	# Web에서 한 손가락 입력 뒤 호환 MouseButton이 한 번 더 올 수 있다.
	# 같은 탭이 P1과 상대를 동시에 확정하지 않도록 후속 마우스 이벤트를 버린다.
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
	get_viewport().set_input_as_handled()
	AudioManager.play("ui_ok")
	if step == 0:
		p1_sel = index
		step = 1
	elif step == 1:
		p2_sel = index
		if GameState.mode == GameState.Mode.VS_2P:
			_start()
			return
		step = 2
	else:
		return
	_refresh()


func _change_cpu(delta: int) -> void:
	cpu_level = clampi(cpu_level + delta, 1, 4)
	AudioManager.play("ui_move")
	_refresh()


func _back_step() -> void:
	step = maxi(step - 1, 0)
	AudioManager.play("ui_move")
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


func _refresh() -> void:
	for k in cards.size():
		var sb: StyleBoxFlat = UiKit.panel_box()
		var marks: Array = []
		if k == p1_sel:
			marks.append("P1")
		if step >= 1 and k == p2_sel:
			marks.append("P2" if GameState.mode == GameState.Mode.VS_2P else "상대")
		if k == p1_sel and step == 0:
			sb.border_color = UiKit.SEAL
			sb.set_border_width_all(5)
		elif step >= 1 and k == p2_sel:
			sb.border_color = UiKit.SEAL
			sb.set_border_width_all(5)
		cards[k].add_theme_stylebox_override("panel", sb)
	var is_cpu := GameState.mode != GameState.Mode.VS_2P
	if step == 2 and is_cpu:
		diff_label.text = "CPU 난이도  ◀ %d ▶" % cpu_level
	else:
		var selected: int = p1_sel if step == 0 else p2_sel
		var sm: MoveData = fds[selected].moves["medium"]
		var sh: MoveData = fds[selected].moves["heavy"]
		var st: MoveData = fds[selected].moves["tech"]
		diff_label.text = "중: %s · 강: %s · 기술: %s" % [sm.role_note, sh.role_note, st.role_note]
	match step:
		0:
			prompt.text = "검객을 터치해 P1 선택 · ←→ 선택 · A 확정"
		1:
			if GameState.mode == GameState.Mode.VS_2P:
				prompt.text = "검객을 터치해 P2 선택 · J/L 선택 · U 확정"
			else:
				prompt.text = "상대를 터치해 선택 · ←→ 선택 · A 확정"
		2:
			prompt.text = ""
		_:
			prompt.text = ""
	touch_bar.visible = step == 2 and is_cpu
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		GameState.goto("menu")
		return
	var is_2p := GameState.mode == GameState.Mode.VS_2P
	match step:
		0:
			if event.is_action_pressed("p1_left") or event.is_action_pressed("p1_right"):
				var delta := -1 if event.is_action_pressed("p1_left") else 1
				p1_sel = posmod(p1_sel + delta, fds.size())
				AudioManager.play("ui_move")
			elif event.is_action_pressed("p1_light"):
				step = 1
				AudioManager.play("ui_ok")
		1:
			var pre := "p2_" if is_2p else "p1_"
			if event.is_action_pressed(pre + "left") or event.is_action_pressed(pre + "right"):
				var delta := -1 if event.is_action_pressed(pre + "left") else 1
				p2_sel = posmod(p2_sel + delta, fds.size())
				AudioManager.play("ui_move")
			elif event.is_action_pressed(pre + "light"):
				AudioManager.play("ui_ok")
				if is_2p:
					_start()
				else:
					step = 2
			elif event.is_action_pressed(pre + "heavy"):
				step = 0
		2:
			if event.is_action_pressed("p1_left"):
				cpu_level = maxi(cpu_level - 1, 1)
				AudioManager.play("ui_move")
			elif event.is_action_pressed("p1_right"):
				cpu_level = mini(cpu_level + 1, 4)
				AudioManager.play("ui_move")
			elif event.is_action_pressed("p1_light"):
				AudioManager.play("ui_ok")
				_start()
			elif event.is_action_pressed("p1_heavy"):
				step = 1
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
		UiKit.dry_stroke(self, Vector2(80, 80 + k * 80.0), 1120, UiKit.INK_FAINT, 300 + k)
	var f := ThemeDB.fallback_font
	draw_string(f, Vector2(90, 100), "출전 검객", HORIZONTAL_ALIGNMENT_LEFT, -1, 44, UiKit.INK)
	var mode_name: String = {GameState.Mode.VS_2P: "대전 — 2인", GameState.Mode.VS_CPU: "대전 — CPU", GameState.Mode.TRAINING: "훈련"}[GameState.mode]
	draw_string(f, Vector2(90, 130), mode_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, UiKit.GRAY)
