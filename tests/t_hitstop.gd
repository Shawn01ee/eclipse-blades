extends RefCounted
## AC-06: 히트스톱 중 입력 버퍼 유지, 위치·타이머 정지.

const H := preload("res://tests/t_help.gd")


static func run(t, _args: Dictionary) -> void:
	t.suite("히트스톱 (AC-06)")

	var w := H.mk(0, 1, 1, {"timer_ticks": SimC.ROUND_TICKS})
	w.debug_set_x(0, 0)
	w.debug_set_x(1, 110)
	w.step(SimC.B_L, 0)
	for k in 4:
		w.step(0, 0)   # 접촉 틱(t0+5)까지
	var evs := w.step(0, 0)
	# 접촉 직후 히트스톱 5틱
	t.ok(w.s["p"][0]["hitstop"] > 0, "타격 후 공격자 히트스톱")
	var x1_before: int = w.s["p"][1]["x"]
	var timer_before: int = w.s["timer"]
	# 동결 중: 상대가 이동 입력해도 위치 불변, 타이머 정지, 버튼은 버퍼에 기록
	w.step(SimC.B_M, SimC.B_LEFT)
	t.eq(w.s["p"][1]["x"], x1_before, "히트스톱 중 위치 동결")
	t.eq(w.s["timer"], timer_before, "히트스톱 중 타이머 정지")
	# 동결 해제 후 버퍼된 중베기가 캔슬로 발동 (약→중 캔슬 창)
	for k in 8:
		w.step(0, 0)
	t.eq(w.s["p"][0]["move"], "arin_medium", "히트스톱 중 입력이 유지되어 캔슬 발동")
