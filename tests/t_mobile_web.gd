extends RefCounted
## 모바일 방향 안내, 안전영역 터치 배치, 웹 경량화 설정 회귀 검증.

const MobileGuard := preload("res://ui/mobile_guard.gd")
const TouchControls := preload("res://ui/touch_controls.gd")


static func run(t, _args: Dictionary) -> void:
	t.suite("모바일 웹 배포")
	t.ok(MobileGuard.is_portrait_size(Vector2i(390, 844)), "iPhone 세로 크기 감지")
	t.ok(not MobileGuard.is_portrait_size(Vector2i(844, 390)), "가로 크기에서는 회전 안내 해제")
	t.ok(not MobileGuard.is_portrait_size(Vector2i(720, 720)), "정사각형 창을 세로로 오인하지 않음")
	var settings_file := FileAccess.open("res://autoload/settings_manager.gd", FileAccess.READ)
	var settings_source := settings_file.get_as_text() if settings_file != null else ""
	t.ok(settings_source.contains('"touch_ui": true'), "터치 UI 기본 활성")
	t.ok(settings_source.contains('"touch_size": 100'), "터치 크기 기본값 유효")
	t.ok(settings_source.contains("NotoSansKR-Game.ttf"), "웹 한글 폰트 명시적 등록")
	t.ok(load("res://fonts/NotoSansKR-Game.ttf") is Font, "웹 한글 폰트 리소스 로드")
	t.eq(ProjectSettings.get_setting("display/window/handheld/orientation"), "landscape",
			"모바일 가로 방향 선언")

	var preset_file := FileAccess.open("res://export_presets.cfg", FileAccess.READ)
	var preset := preset_file.get_as_text() if preset_file != null else ""
	t.ok(preset.contains("variant/thread_support=false"), "iOS 호환 단일 스레드 웹 빌드")
	t.ok(preset.contains("viewport-fit=cover"), "iPhone 노치 대응 viewport")
	t.ok(preset.contains("art/combat_atlas/*") and preset.contains("art/sheets/*") \
			and preset.contains("art/sprites/*"), "비활성 전투 스킨을 웹 패키지에서 제외")

	var fighter_file := FileAccess.open("res://ui/fighter_view.gd", FileAccess.READ)
	var fighter_source := fighter_file.get_as_text() if fighter_file != null else ""
	t.ok(fighter_source.contains("if COMBAT_SKINS_ENABLED:"), "꺼진 스킨은 런타임에도 지연 로드")
	var main_file := FileAccess.open("res://ui/main.gd", FileAccess.READ)
	var main_source := main_file.get_as_text() if main_file != null else ""
	t.ok(main_source.contains("screen_theme.default_font = ThemeDB.fallback_font"),
			"웹 Control 전체에 내장 한글 폰트 상속")

	var layout := TouchControls.layout_for_size(120)
	var joy_center: Vector2 = layout["joy_center"]
	var joy_radius: float = layout["joy_radius"]
	var joy_safe: bool = joy_center.x - joy_radius >= 55.5 \
			and 720.0 - (joy_center.y + joy_radius) >= 55.5
	t.ok(joy_safe, "최대 크기 조이스틱 안전영역")
	var attacks_safe := true
	for b in layout["buttons"].values():
		var center: Vector2 = b["c"]
		var radius: float = b["r"]
		attacks_safe = attacks_safe and center.x + radius <= 1232.0 \
				and center.y + radius <= 672.0
	t.ok(attacks_safe, "최대 크기 공격 버튼 노치·홈 인디케이터 여백")
	var pause_rect: Rect2 = layout["pause_rect"]
	t.ok(pause_rect.position.x >= 600.0 and pause_rect.end.x <= 680.0 \
			and pause_rect.position.y >= 88.0, "일시정지 버튼이 캐릭터 이름·체력바와 분리")
