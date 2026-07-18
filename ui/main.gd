extends Node
## 화면 라우터: 부팅 → 메뉴 → 선택 → 경기 → 결과.

const SCREENS := {
	"menu": preload("res://ui/menu.gd"),
	"select": preload("res://ui/char_select.gd"),
	"settings": preload("res://ui/settings_screen.gd"),
	"match": preload("res://ui/match_screen.gd"),
}

var current: Node = null


func _ready() -> void:
	GameState.router = self
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


func goto(screen: String) -> void:
	get_tree().paused = false
	AudioManager.play_bgm("battle" if screen == "match" else "menu")
	if current:
		current.queue_free()
	current = SCREENS[screen].new()
	# 라우터는 일반 Node라 Control의 FULL_RECT 앵커 기준 크기를 제공하지 않는다.
	# 자식 _ready가 실행되기 전에 논리 화면 크기를 지정해야 스크롤/HUD/팝업이 0×0이 되지 않는다.
	if current is Control:
		current.position = Vector2.ZERO
		current.size = Vector2(1280, 720)
	add_child(current)
	# 개발용 스크린샷 훅
	if screen == "match" and OS.get_environment("ECLIPSE_SHOT") != "":
		var helper := preload("res://ui/shot_helper.gd").new()
		helper.match_screen = current
		add_child(helper)
