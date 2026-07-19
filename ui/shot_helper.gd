extends Node
## 개발용 스크린샷 도구. ECLIPSE_SHOT 환경변수가 있으면 지정 프레임에 캡처.
## 시뮬/게임플레이에 영향 없음 — 순수 뷰 캡처.

var frame := 0
var shot_at := 60
var out_path := "user://_shot.png"
var match_screen: Node = null
var _injected := false
var _capture_pending := false
var _capturing := false
var _warmup_ticks := 0
var _ready_ticks := 0
var scenario := "air"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	shot_at = int(OS.get_environment("ECLIPSE_SHOT"))
	if OS.get_environment("ECLIPSE_SHOT_SCENE") != "":
		scenario = OS.get_environment("ECLIPSE_SHOT_SCENE")
	if OS.get_environment("ECLIPSE_SHOT_OUT") != "":
		out_path = OS.get_environment("ECLIPSE_SHOT_OUT")


func _physics_process(_dt: float) -> void:
	if match_screen == null or match_screen.world == null:
		return
	var world = match_screen.world
	if world.s["phase"] != SimC.PH_FIGHT:
		return
	_warmup_ticks += 1
	if not _injected and _warmup_ticks >= 55:
		# 전투 배너가 사라진 뒤 시나리오별 결정론 입력을 주입한다.
		_reset_fighter_for_shot(world, 0)
		_reset_fighter_for_shot(world, 1)
		match_screen.replay_mode = true
		match_screen.replay_words = []
		_build_scenario(world)
		match_screen.replay_i = 0
		_injected = true
	if _injected and _scenario_ready(world):
		_ready_ticks += 1
		# 시그니처 먹선이 실제 활성 프레임에서 3틱만큼 펼쳐진 뒤 캡처한다.
		if _ready_ticks >= 3:
			_capture_pending = true
			get_tree().paused = true
	else:
		_ready_ticks = 0


func _reset_fighter_for_shot(world, i: int) -> void:
	var p: Dictionary = world.s["p"][i]
	p["state"] = SimC.ST_IDLE
	p["st_f"] = 0
	p["move"] = ""
	p["cur_in"] = 0
	p["prev_in"] = 0
	p["vx"] = 0
	p["y"] = 0
	p["vy"] = 0
	p["jvx"] = 0
	for b in SimC.BTN_BITS:
		p["buf"][b] = -100000


func _build_scenario(world) -> void:
	match scenario:
		"walk":
			world.debug_set_x(0, -280)
			world.debug_set_x(1, 280)
			for i in 50:
				match_screen.replay_words.append([SimC.B_RIGHT if i < 34 else 0, 0])
		"attack":
			world.debug_set_x(0, -190)
			world.debug_set_x(1, 190)
			for i in 70:
				match_screen.replay_words.append([SimC.B_H if i == 0 else 0, 0])
		"hit":
			world.debug_set_x(0, 0)
			world.debug_set_x(1, 125)
			for i in 45:
				match_screen.replay_words.append([SimC.B_L if i == 0 else 0, 0])
		"kendo_light", "kendo_medium", "kendo_heavy", "kendo_tech", "kendo_super":
			world.debug_set_x(0, 0)
			world.debug_set_x(1, 132)
			if scenario == "kendo_super":
				world.debug_set_nerve(0, SimC.NERVE_MAX)
			var button: int = {"kendo_light": SimC.B_L, "kendo_medium": SimC.B_M,
					"kendo_heavy": SimC.B_H, "kendo_tech": SimC.B_T,
					"kendo_super": SimC.B_SUPER}.get(scenario, SimC.B_L)
			for i in 90:
				match_screen.replay_words.append([button if i == 0 else 0, 0])
		"mujin_nerve":
			# 무진의 사맥 강화 파도 연계. 커맨드·자원 소비·활성 칼 판정을 한 화면에 검수한다.
			world.debug_set_x(0, -155)
			world.debug_set_x(1, 90)
			world.debug_set_nerve(0, SimC.NERVE_MAX)
			for i in 70:
				var wd := 0
				if i == 0:
					wd = SimC.B_DOWN
				elif i == 1:
					wd = SimC.B_DOWN | SimC.B_RIGHT
				elif i == 2:
					wd = SimC.B_RIGHT
				elif i == 3:
					wd = SimC.B_RIGHT | SimC.B_H
				match_screen.replay_words.append([wd, 0])
		"pause":
			match_screen._toggle_pause()
		"result":
			match_screen._show_results()
		_:
			world.debug_set_x(0, -150)
			world.debug_set_x(1, 95)
			for i in 60:
				var wd := 0
				if i == 0:
					wd = SimC.B_UP | SimC.B_RIGHT
				elif i <= 30:
					wd = SimC.B_RIGHT
				if i == 22:
					wd |= SimC.B_M
				match_screen.replay_words.append([wd, 0])


func _scenario_ready(world) -> bool:
	match scenario:
		"walk":
			return match_screen.replay_i >= 16 and world.s["p"][0]["state"] == SimC.ST_WALK_F
		"attack":
			return world.s["p"][0]["state"] == SimC.ST_ATTACK \
				and not world.active_weapon_rects(0, true).is_empty()
		"hit":
			return world.s["p"][1]["state"] == SimC.ST_HITSTUN
		"kendo_light", "kendo_medium", "kendo_heavy", "kendo_tech", "kendo_super":
			return world.s["p"][1]["state"] == SimC.ST_HITSTUN
		"mujin_nerve":
			return world.s["p"][0]["move"] == "mujin_motion_nerve" \
				and world.s["p"][0]["state"] == SimC.ST_ATTACK \
				and not world.active_weapon_rects(0, true).is_empty()
		"pause":
			return match_screen.pause_panel != null
		"result":
			return match_screen.results_panel != null
		_:
			return world.s["p"][0]["state"] == SimC.ST_AIR_ATTACK \
				and not world.active_weapon_rects(0, true).is_empty()


func _process(_dt: float) -> void:
	frame += 1
	if not _capturing and (_capture_pending or (shot_at > 0 and frame == shot_at and not _injected)):
		_capturing = true
		_capture_after_draw()


func _capture_after_draw() -> void:
	# Metal의 다중 버퍼에서 현재 프레임을 읽지 않도록 한 프레임을 완전히 넘긴다.
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	RenderingServer.force_sync()
	var img := get_viewport().get_texture().get_image()
	if img == null:
		push_error("스크린샷 실패: 현재 렌더러에서 뷰포트 이미지를 읽을 수 없음")
		AudioManager.stop_all()
		get_tree().quit(1)
		return
	var err := img.save_png(out_path)
	if err != OK:
		push_error("스크린샷 저장 실패(%s): %s" % [err, out_path])
		AudioManager.stop_all()
		get_tree().quit(1)
		return
	if match_screen != null and match_screen.world != null:
		var w = match_screen.world
		print("P1 state=", w.state_name(0), " x=", w.s["p"][0]["x"], " move=", w.s["p"][0]["move"], " stf=", w.s["p"][0]["st_f"])
		print("P2 hp=", w.s["p"][1]["hp"], " state=", w.state_name(1), " x=", w.s["p"][1]["x"],
			" blood=", match_screen.fx.blood.size(), " stains=", match_screen.fx.stains.size(),
			" replay_i=", match_screen.replay_i, " rmode=", match_screen.replay_mode)
	print("스크린샷 저장: ", out_path, " (frame ", frame, ")")
	AudioManager.stop_all()
	await get_tree().process_frame
	get_tree().quit()
