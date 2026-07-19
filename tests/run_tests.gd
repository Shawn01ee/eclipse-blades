extends SceneTree
## 헤드리스 테스트 러너.
## 실행: godot --headless --path . --script res://tests/run_tests.gd
## 소크 확장: godot --headless --path . --script res://tests/run_tests.gd -- soak=100

const SUITES := [
	preload("res://tests/t_compile.gd"),
	preload("res://tests/t_determinism.gd"),
	preload("res://tests/t_framedata.gd"),
	preload("res://tests/t_edge.gd"),
	preload("res://tests/t_resolution.gd"),
	preload("res://tests/t_hitstop.gd"),
	preload("res://tests/t_nerve.gd"),
	preload("res://tests/t_energy.gd"),
	preload("res://tests/t_reset.gd"),
	preload("res://tests/t_jump.gd"),
	preload("res://tests/t_ai_actions.gd"),
	preload("res://tests/t_visual_assets.gd"),
	preload("res://tests/t_bgm.gd"),
	preload("res://tests/t_sfx.gd"),
	preload("res://tests/t_ui_layout.gd"),
	preload("res://tests/t_mobile_web.gd"),
	preload("res://tests/t_online.gd"),
	preload("res://tests/t_character_identity.gd"),
	preload("res://tests/t_han.gd"),
	preload("res://tests/t_signature_fx.gd"),
	preload("res://tests/t_mujin.gd"),
	preload("res://tests/t_jiko.gd"),
	preload("res://tests/t_soak.gd"),
]


func _initialize() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("soak="):
			args["soak"] = int(a.substr(5))
	print("=== 일식검담 테스트 시작 ===")
	var t = preload("res://tests/t_help.gd").Ctx.new()
	var t_start := Time.get_ticks_msec()
	for suite in SUITES:
		suite.run(t, args)
	var elapsed := Time.get_ticks_msec() - t_start
	print("=== 검사 ", t.count, "건 / 실패 ", t.fails.size(), "건 / ", elapsed, "ms ===")
	for f in t.fails:
		print("  ✗ ", f)
	quit(0 if t.fails.is_empty() else 1)
