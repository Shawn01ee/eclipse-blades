extends RefCounted
## CPU 입력 유효성·방향 대칭·결정론·실전 종료를 검증한다.

const H := preload("res://tests/t_help.gd")
const A := preload("res://ai/cpu_action_library.gd")
const VALID_INPUT_MASK := SimC.B_LEFT | SimC.B_RIGHT | SimC.B_DOWN | SimC.B_UP \
		| SimC.B_L | SimC.B_M | SimC.B_H | SimC.B_T | SimC.B_SUPER


static func run(t, _args: Dictionary) -> void:
	t.suite("CPU 다중 프레임 행동")

	var right_jump := A.frames(A.Action.JUMP_IN, 1)
	var left_jump := A.frames(A.Action.JUMP_IN, -1)
	t.ok(right_jump.size() > SimC.PREJUMP, "점프 진입은 도약 준비보다 오래 전진 유지")
	t.eq(right_jump[0], SimC.B_UP | SimC.B_RIGHT, "오른쪽 점프 진입 첫 입력")
	t.eq(left_jump[0], SimC.B_UP | SimC.B_LEFT, "왼쪽 점프 진입 방향 대칭")
	t.eq(right_jump[1], SimC.B_RIGHT, "점프 진입 후속 프레임 전진 유지")

	var super_right := A.frames(A.Action.SUPER, 1)
	t.eq(super_right, [SimC.B_SUPER], "CPU도 접근성 오의 전용 입력 사용")
	t.eq(A.frames(A.Action.GRAB, -1), [SimC.B_LEFT | SimC.B_M], "왼쪽을 보는 잡기 입력")
	t.eq(A.frames(A.Action.MOTION_HEAVY, 1), [SimC.B_DOWN,
			SimC.B_DOWN | SimC.B_RIGHT, SimC.B_RIGHT, SimC.B_RIGHT | SimC.B_H],
			"무진 강 파도 연계 입력 열")

	var words_valid := true
	for action in A.Action.values():
		for facing in [-1, 1]:
			for word in A.frames(action, facing):
				if (word & ~VALID_INPUT_MASK) != 0 or ((word & SimC.B_LEFT) and (word & SimC.B_RIGHT)):
					words_valid = false
	t.ok(words_valid, "모든 액션이 유효한 입력 비트와 SOCD 규칙 사용")

	# 같은 월드/CPU 시드에서는 매 틱 입력과 최종 상태가 완전히 같아야 한다.
	var wa := H.mk(0, 1, 20260718)
	var wb := H.mk(0, 1, 20260718)
	var a1 := CpuBrain.new(0, 4, 101)
	var a2 := CpuBrain.new(1, 4, 202)
	var b1 := CpuBrain.new(0, 4, 101)
	var b2 := CpuBrain.new(1, 4, 202)
	var deterministic := true
	for tick in 1800:
		var wa1 := a1.think(wa)
		var wa2 := a2.think(wa)
		var wb1 := b1.think(wb)
		var wb2 := b2.think(wb)
		if wa1 != wb1 or wa2 != wb2:
			deterministic = false
		wa.step(wa1, wa2)
		wb.step(wb1, wb2)
	t.ok(deterministic and wa.state_hash() == wb.state_hash(), "동일 CPU 시드 1,800틱 결정론")

	# 짧은 1선승 실전에서 양 CPU가 교착 없이 경기를 끝낸다.
	var fight := H.mk(2, 3, 909, {"timer_ticks": 20 * SimC.TPS, "wins_needed": 1})
	var cpu1 := CpuBrain.new(0, 4, 303)
	var cpu2 := CpuBrain.new(1, 4, 404)
	for tick in 6000:
		fight.step(cpu1.think(fight), cpu2.think(fight))
		if fight.s["phase"] == SimC.PH_MATCH_END:
			break
	t.eq(fight.s["phase"], SimC.PH_MATCH_END, "CPU 대 CPU 경기가 제한 틱 안에 종료")
