extends Node
## 화면 라우터: 부팅 → 메뉴 → 선택 → 경기 → 결과.

const SCREENS := {
	"menu": preload("res://ui/menu.gd"),
	"select": preload("res://ui/char_select.gd"),
	"settings": preload("res://ui/settings_screen.gd"),
	"match": preload("res://ui/match_screen.gd"),
}
const MobileGuard := preload("res://ui/mobile_guard.gd")
const Responsive := preload("res://ui/responsive_layout.gd")

var current: Node = null
var mobile_guard: Control = null


func _ready() -> void:
	GameState.router = self
	get_viewport().size_changed.connect(_layout_viewport)
	AudioManager.play_bgm()
	# 로스터 렌더 캡처용 개발 전용 선택 오버라이드.
	var roster_last := Registry.FIGHTER_PATHS.size() - 1
	if OS.get_environment("ECLIPSE_P1_CHAR") != "":
		GameState.p1_char = clampi(int(OS.get_environment("ECLIPSE_P1_CHAR")), 0, roster_last)
	if OS.get_environment("ECLIPSE_P2_CHAR") != "":
		GameState.p2_char = clampi(int(OS.get_environment("ECLIPSE_P2_CHAR")), 0, roster_last)
	# 스모크 테스트용 자동 시작 (ECLIPSE_AUTOSTART=match|training)
	match OS.get_environment("ECLIPSE_AUTOSTART"):
		"match":
			GameState.mode = GameState.Mode.VS_CPU
			goto("match")
		"training":
			GameState.mode = GameState.Mode.TRAINING
			goto("match")
		"select":
			GameState.mode = GameState.Mode.VS_CPU
			goto("select")
		"settings":
			goto("settings")
		_:
			goto("menu")
	if OS.get_environment("ECLIPSE_UI_SHOT") != "":
		add_child(preload("res://ui/ui_shot_helper.gd").new())
	mobile_guard = MobileGuard.new()
	add_child(mobile_guard)
	_layout_viewport()


func goto(screen: String) -> void:
	get_tree().paused = false
	AudioManager.play_bgm("battle" if screen == "match" else "menu")
	if current:
		current.queue_free()
	current = SCREENS[screen].new()
	# 라우터는 일반 Node라 Control의 FULL_RECT 앵커 기준 크기를 제공하지 않는다.
	# 자식 _ready가 실행되기 전에 논리 화면 크기를 지정해야 스크롤/HUD/팝업이 0×0이 되지 않는다.
	if current is Control:
		current.size = Responsive.BASE_SIZE
		# ThemeDB 폴백만 바꾸면 웹의 일부 Button/Label이 초기 기본 글꼴을 계속 쓴다.
		# 화면 루트 테마에 내장 한글 글꼴을 명시해 모든 자식 Control에 상속한다.
		var screen_theme := Theme.new()
		screen_theme.default_font = ThemeDB.fallback_font
		current.theme = screen_theme
	add_child(current)
	_layout_viewport()
	# 개발용 스크린샷 훅
	if screen == "match" and OS.get_environment("ECLIPSE_SHOT") != "":
		var helper := preload("res://ui/shot_helper.gd").new()
		helper.match_screen = current
		add_child(helper)


func _layout_viewport() -> void:
	var viewport_size := get_viewport().get_visible_rect().size
	if current is Control:
		current.set_anchors_preset(Control.PRESET_TOP_LEFT)
		current.position = Responsive.content_offset_for_size(viewport_size)
		current.size = Responsive.BASE_SIZE
		current.queue_redraw()
	if mobile_guard != null:
		mobile_guard.set_anchors_preset(Control.PRESET_TOP_LEFT)
		mobile_guard.position = Vector2.ZERO
		mobile_guard.size = viewport_size
		mobile_guard.queue_redraw()
