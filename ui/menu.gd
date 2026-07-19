extends Control
## 메인 메뉴 — 키아트(있으면) + 일식 문장 + 붓글씨 느낌 타이틀.

const Responsive := preload("res://ui/responsive_layout.gd")

const MODE_PANEL_RECT := Rect2(320, 348, 640, 270)
const MODE_CARD_SIZE := Vector2(304, 76)
const UTILITY_BUTTON_SIZE := Vector2(304, 46)

var keyart: Texture2D = null


func _ready() -> void:
	var path := "res://art/key/keyart.png"
	if ResourceLoader.exists(path):
		keyart = load(path)
	else:
		var abs_path := ProjectSettings.globalize_path(path)
		if FileAccess.file_exists(abs_path):
			var img := Image.load_from_file(abs_path)
			if img != null:
				keyart = ImageTexture.create_from_image(img)
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var v := VBoxContainer.new()
	# 플레이 모드는 2×2 카드, 설정/종료는 작은 보조 메뉴로 분리한다.
	v.position = MODE_PANEL_RECT.position + Vector2(10, 6)
	v.size = MODE_PANEL_RECT.size - Vector2(20, 12)
	v.custom_minimum_size = Vector2(620, 0)
	v.add_theme_constant_override("separation", 9)
	add_child(v)

	var heading := UiKit.label("대전 방식 선택", 17, UiKit.GRAY)
	heading.custom_minimum_size = Vector2(620, 20)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(heading)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.custom_minimum_size = Vector2(620, 162)
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 10)
	v.add_child(grid)
	var modes := [
		["온라인 대전", "방 코드로 친구와 대전", func(): _online()],
		["CPU 대전", "CPU 검객과 대전", func(): _start(GameState.Mode.VS_CPU)],
		["2인 대전", "한 기기에서 마주 대전", func(): _start(GameState.Mode.VS_2P)],
		["훈련", "기술과 연계를 연습하기", func(): _start(GameState.Mode.TRAINING)],
	]
	var first: Button = null
	for mode in modes:
		var btn := _mode_button(mode[0], mode[1])
		btn.pressed.connect(mode[2])
		btn.focus_entered.connect(func(): AudioManager.play("ui_move"))
		grid.add_child(btn)
		if first == null:
			first = btn

	var utility := HBoxContainer.new()
	utility.add_theme_constant_override("separation", 12)
	v.add_child(utility)
	var settings := UiKit.button("설정", 19)
	settings.custom_minimum_size = UTILITY_BUTTON_SIZE
	settings.pressed.connect(func(): GameState.goto("settings"))
	utility.add_child(settings)
	var quit := UiKit.button("종료", 19)
	quit.custom_minimum_size = UTILITY_BUTTON_SIZE
	quit.pressed.connect(func(): get_tree().quit())
	utility.add_child(quit)
	first.grab_focus()


func _mode_button(title: String, subtitle: String) -> Button:
	var button := UiKit.button(title + "\n" + subtitle, 20)
	button.custom_minimum_size = MODE_CARD_SIZE
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(UiKit.PAPER_LIGHT, 0.78)
	normal.border_color = UiKit.INK_FAINT
	normal.set_border_width_all(1)
	normal.border_width_left = 4
	normal.set_corner_radius_all(2)
	normal.content_margin_left = 18
	normal.content_margin_right = 14
	normal.content_margin_top = 8
	normal.content_margin_bottom = 8
	var active: StyleBoxFlat = normal.duplicate()
	active.bg_color = Color(UiKit.PAPER_LIGHT, 0.94)
	active.border_color = UiKit.SEAL
	active.border_width_left = 6
	active.border_width_bottom = 3
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", active)
	button.add_theme_stylebox_override("focus", active)
	button.add_theme_stylebox_override("pressed", active)
	return button


func _online() -> void:
	AudioManager.play("ui_ok")
	GameState.goto("online")


func _start(mode: int) -> void:
	AudioManager.play("ui_ok")
	GameState.mode = mode
	GameState.goto("select")


func _draw() -> void:
	var full_rect := Responsive.expanded_rect_for_size(get_viewport_rect().size)
	# 화지 바탕
	draw_rect(full_rect, UiKit.PAPER)
	var f := ThemeDB.fallback_font
	if keyart != null:
		# 화면을 꽉 채우되 원본 비율을 지키고 넘치는 쪽만 중앙 크롭한다.
		var texture_size := Vector2(keyart.get_width(), keyart.get_height())
		var source_rect := Responsive.cover_source_rect(texture_size, full_rect.size)
		draw_texture_rect_region(keyart, full_rect, source_rect)
		draw_rect(full_rect, Color(UiKit.PAPER, 0.30))
		# 타이틀 띠
		draw_rect(Rect2(340, 218, 600, 122), Color(UiKit.PAPER_LIGHT, 0.82))
		draw_rect(Rect2(340, 218, 600, 3), UiKit.INK)
		draw_rect(Rect2(340, 337, 600, 3), UiKit.INK)
		# 모드 카드 배경 띠
		draw_rect(MODE_PANEL_RECT, Color(UiKit.PAPER_LIGHT, 0.70))
		draw_rect(Rect2(MODE_PANEL_RECT.position, Vector2(MODE_PANEL_RECT.size.x, 2)), UiKit.INK_FAINT)
	else:
		for k in 14:
			UiKit.dry_stroke(self, Vector2(60, 60 + k * 46.0), 1160, UiKit.INK_FAINT, 100 + k)
		# 일식 문장
		var c := Vector2(640, 168)
		draw_circle(c, 74, Color(UiKit.GRAY, 0.25))
		draw_circle(c, 62, UiKit.INK)
		draw_arc(c, 68, 0, TAU, 64, Color(UiKit.PAPER_LIGHT, 0.9), 2.5)
		UiKit.splatter(self, c + Vector2(46, -40), 34, 26, UiKit.INK_SOFT, 7)
		var pts := PackedVector2Array([Vector2(520, 236), Vector2(760, 96), Vector2(752, 104), Vector2(532, 240)])
		draw_polygon(pts, [UiKit.SEAL_SOFT])
	# 타이틀
	draw_string(f, Vector2(640 - 174, 296), "일 식 검 담", HORIZONTAL_ALIGNMENT_LEFT, -1, 62, UiKit.INK)
	draw_string(f, Vector2(640 - 116, 330), "E C L I P S E   B L A D E S", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, UiKit.GRAY)
	# 인장
	draw_rect(Rect2(1150, 600, 56, 56), UiKit.SEAL)
	draw_string(f, Vector2(1157, 638), "해원", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, UiKit.PAPER_LIGHT)
	draw_string(f, Vector2(70, 690), "칼날 끝 두 치가 승부를 가른다 — 해원국 검담", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, UiKit.GRAY)
