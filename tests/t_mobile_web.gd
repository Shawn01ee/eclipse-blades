extends RefCounted
## 모바일 방향 안내, 안전영역 터치 배치, 웹 경량화 설정 회귀 검증.

const MobileGuard := preload("res://ui/mobile_guard.gd")
const TouchControls := preload("res://ui/touch_controls.gd")
const Responsive := preload("res://ui/responsive_layout.gd")


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
	t.eq(ProjectSettings.get_setting("display/window/stretch/aspect"), "expand",
			"기기 비율에 맞춰 논리 시야 확장")
	t.eq(Responsive.content_offset_for_size(Vector2(1558, 720)), Vector2(139, 0),
			"긴 모바일 화면에서 1280 콘텐츠 중앙 정렬")
	t.eq(Responsive.content_offset_for_size(Vector2(1280, 720)), Vector2.ZERO,
			"16:9 화면에서 기준 콘텐츠 위치 유지")
	t.eq(Responsive.content_offset_for_size(Vector2(1280, 960)), Vector2(0, 120),
			"4:3 화면에서 기준 콘텐츠 세로 중앙 정렬")
	t.eq(Responsive.expanded_rect_for_size(Vector2(1558, 720)),
			Rect2(-139, 0, 1558, 720), "긴 모바일 화면 전체를 덮는 배경 영역")
	var wide_source := Responsive.cover_source_rect(Vector2(1672, 941), Vector2(1558, 720))
	t.ok(absf(wide_source.size.x / wide_source.size.y - 1558.0 / 720.0) < 0.001,
			"메뉴 키아트 비율 유지 화면 채우기")
	t.eq(ProjectSettings.get_setting("input_devices/pointing/emulate_mouse_from_touch"), false,
			"모바일 터치가 호환 마우스를 거쳐 중복 입력되지 않음")

	var preset_file := FileAccess.open("res://export_presets.cfg", FileAccess.READ)
	var preset := preset_file.get_as_text() if preset_file != null else ""
	t.ok(preset.contains("variant/thread_support=false"), "iOS 호환 단일 스레드 웹 빌드")
	t.ok(preset.contains("viewport-fit=cover"), "iPhone 노치 대응 viewport")
	t.ok(preset.contains("requestFullscreen") \
			and preset.contains("screen.orientation.lock('landscape')"),
			"모바일 첫 터치에서 전체화면·가로 잠금 요청")
	t.ok(preset.contains("'pointerdown',enterMobileMode") \
			and preset.contains("'touchstart',enterMobileMode") \
			and preset.contains("'click',enterMobileMode") \
			and not preset.contains("once:true"),
			"전체화면 성공 전에는 다음 포인터·터치에서 재시도")
	t.ok(preset.contains("'fullscreenchange',fit") \
			and preset.contains("dispatchEvent(new Event('resize'))"),
			"전체화면 전환 직후 캔버스 크기 다시 계산")
	t.ok(preset.contains("progressive_web_app/enabled=true") \
			and preset.contains("progressive_web_app/display=0") \
			and preset.contains("progressive_web_app/orientation=1"),
			"홈 화면 실행은 fullscreen·landscape PWA")
	t.ok(preset.contains("art/combat_atlas/*") and preset.contains("art/sheets/*") \
			and preset.contains("art/sprites/*"), "비활성 전투 스킨을 웹 패키지에서 제외")

	var fighter_file := FileAccess.open("res://ui/fighter_view.gd", FileAccess.READ)
	var fighter_source := fighter_file.get_as_text() if fighter_file != null else ""
	t.ok(fighter_source.contains("if COMBAT_SKINS_ENABLED:"), "꺼진 스킨은 런타임에도 지연 로드")
	var main_file := FileAccess.open("res://ui/main.gd", FileAccess.READ)
	var main_source := main_file.get_as_text() if main_file != null else ""
	t.ok(main_source.contains("screen_theme.default_font = ThemeDB.fallback_font"),
			"웹 Control 전체에 내장 한글 폰트 상속")
	var kit_file := FileAccess.open("res://ui/ui_kit.gd", FileAccess.READ)
	var kit_source := kit_file.get_as_text() if kit_file != null else ""
	t.ok(kit_source.contains("ACTION_MODE_BUTTON_PRESS"), "iOS 첫 터치에서 버튼 즉시 실행")
	var select_file := FileAccess.open("res://ui/char_select.gd", FileAccess.READ)
	var select_source := select_file.get_as_text() if select_file != null else ""
	t.ok(select_source.contains("event is InputEventScreenTouch") \
			and select_source.contains("_last_card_touch_ms < 500"),
			"캐릭터 카드 ScreenTouch 입력·호환 마우스 중복 방지")
	t.ok(select_source.contains("card.gui_input.connect(_on_card_input.bind(k))") \
			and select_source.contains("touch_bar.visible = step == 2"),
			"캐릭터 카드·난이도·시작 터치 경로 연결")
	var touch_file := FileAccess.open("res://ui/touch_controls.gd", FileAccess.READ)
	var touch_source := touch_file.get_as_text() if touch_file != null else ""
	t.ok(touch_source.contains("get_global_transform_with_canvas().affine_inverse()") \
			and touch_source.contains("_local_touch_position(event.position)"),
			"확장 화면의 전역 터치를 컨트롤 로컬 좌표로 보정")
	var stage_file := FileAccess.open("res://ui/stage_view.gd", FileAccess.READ)
	var stage_source := stage_file.get_as_text() if stage_file != null else ""
	t.ok(stage_source.contains("get_viewport().size_changed.connect(queue_redraw)"),
			"화면 회전·리사이즈 뒤 확장 무대 다시 그리기")

	var layout := TouchControls.layout_for_size(120)
	var joy_center: Vector2 = layout["joy_center"]
	var joy_radius: float = layout["joy_radius"]
	var joy_safe: bool = joy_center.x - joy_radius >= 55.5 \
			and 720.0 - (joy_center.y + joy_radius) >= 55.5
	t.ok(joy_safe, "최대 크기 조이스틱 안전영역")
	var attacks_safe := true
	var attack_buttons: Array = layout["buttons"].values()
	for b in attack_buttons:
		var center: Vector2 = b["c"]
		var radius: float = b["r"]
		attacks_safe = attacks_safe and center.x + radius <= 1232.0 \
				and center.y + radius <= 672.0
	t.ok(attacks_safe, "최대 크기 공격 버튼 노치·홈 인디케이터 여백")
	var wide_layout := TouchControls.layout_for_size(100, Vector2(1558, 720))
	var wide_heavy: Dictionary = wide_layout["buttons"]["heavy"]
	t.eq(wide_heavy["c"].x, 1301.0,
			"긴 모바일 화면에서 공격 버튼 묶음을 우측 확장 영역으로 이동")
	var attacks_separated := true
	for i in attack_buttons.size():
		for j in range(i + 1, attack_buttons.size()):
			var a: Dictionary = attack_buttons[i]
			var b: Dictionary = attack_buttons[j]
			attacks_separated = attacks_separated \
					and a["c"].distance_to(b["c"]) >= a["r"] + b["r"] + 6.0
	t.ok(attacks_separated, "최대 크기 공격 버튼과 터치 판정 사이 최소 6px 간격")
	var pause_rect: Rect2 = layout["pause_rect"]
	t.ok(pause_rect.position.x >= 600.0 and pause_rect.end.x <= 680.0 \
			and pause_rect.position.y >= 88.0, "일시정지 버튼이 캐릭터 이름·체력바와 분리")
