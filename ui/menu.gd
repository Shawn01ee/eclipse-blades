extends Control
## 메인 메뉴 — 키아트(있으면) + 일식 문장 + 붓글씨 느낌 타이틀.

const Responsive := preload("res://ui/responsive_layout.gd")

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
	# 타이틀 띠(218~340)와 메뉴 영역(360~616)을 완전히 분리한다.
	v.position = Vector2(450, 360)
	v.size = Vector2(380, 256)
	v.custom_minimum_size = Vector2(380, 0)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 0)
	add_child(v)

	var buttons := [
		["온라인 대전", func(): _online()],
		["대전 — 2인", func(): _start(GameState.Mode.VS_2P)],
		["대전 — CPU", func(): _start(GameState.Mode.VS_CPU)],
		["훈련", func(): _start(GameState.Mode.TRAINING)],
		["설정", func(): GameState.goto("settings")],
		["종료", func(): get_tree().quit()],
	]
	var first: Button = null
	for b in buttons:
		var btn := UiKit.button(b[0])
		btn.pressed.connect(b[1])
		btn.focus_entered.connect(func(): AudioManager.play("ui_move"))
		v.add_child(btn)
		if first == null:
			first = btn
	first.grab_focus()


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
		# 버튼 배경 띠
		draw_rect(Rect2(450, 356, 380, 260), Color(UiKit.PAPER_LIGHT, 0.72))
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
