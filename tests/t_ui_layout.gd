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
