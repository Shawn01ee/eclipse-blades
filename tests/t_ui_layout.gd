extends RefCounted
## 화면 비율이 달라도 논리 UI가 찌그러지지 않고 시야가 확장되는 설정 회귀 검증.

static func run(t, _args: Dictionary) -> void:
	t.suite("UI 논리 화면·비율 유지")
	t.eq(ProjectSettings.get_setting("display/window/stretch/aspect"), "expand",
			"기기 비율에 맞춰 왜곡 없이 논리 시야 확장")
	var logical := Vector2i(
			int(ProjectSettings.get_setting("display/window/size/viewport_width")),
			int(ProjectSettings.get_setting("display/window/size/viewport_height")))
	t.eq(logical, Vector2i(1280, 720), "UI 논리 화면 1280×720")
	var menu_file := FileAccess.open("res://ui/menu.gd", FileAccess.READ)
	var menu_source := menu_file.get_as_text() if menu_file != null else ""
	t.ok(menu_source.contains("grid.columns = 2") \
			and menu_source.contains("MODE_CARD_SIZE := Vector2(304, 76)"),
			"플레이 모드를 겹치지 않는 2×2 카드로 배치")
	t.ok(menu_source.contains("var utility := HBoxContainer.new()") \
			and menu_source.contains("UTILITY_BUTTON_SIZE := Vector2(304, 46)"),
			"설정·종료를 별도 하단 보조 메뉴로 분리")
