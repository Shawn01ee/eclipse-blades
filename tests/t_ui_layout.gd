extends RefCounted
## 작은 창에서도 중앙 크롭 대신 전체 16:9 UI가 보이는 프로젝트 설정 회귀 검증.


static func run(t, _args: Dictionary) -> void:
	t.suite("UI 논리 화면·비율 유지")
	t.eq(ProjectSettings.get_setting("display/window/stretch/aspect"), "keep",
			"창 축소 시 전체 UI 비율 유지")
	var logical := Vector2i(
			int(ProjectSettings.get_setting("display/window/size/viewport_width")),
			int(ProjectSettings.get_setting("display/window/size/viewport_height")))
	t.eq(logical, Vector2i(1280, 720), "UI 논리 화면 1280×720")
