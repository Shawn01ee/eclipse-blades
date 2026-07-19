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

	# 1~3은 기존 학습 구간, 4부터 반응·가드·실수율이 큰 폭으로 강화된다.
	t.eq(CpuBrain.MAX_LEVEL, 6, "CPU 최대 난이도 6단계")
	t.eq(CpuBrain.new(0, 0, 1).level, 1, "CPU 난이도 하한 보정")
	t.eq(CpuBrain.new(0, 99, 1).level, 6, "CPU 난이도 상한 보정")
	t.eq(CpuBrain.CADENCE.size(), 6, "판단 주기 6단계 프로필")
	t.ok(CpuBrain.REACT_DELAY[3] <= 4 and CpuBrain.CADENCE[3] <= 4,
			"4단계부터 4프레임 이내 반응·재판단")
	t.ok(CpuBrain.BLOCK_PROB[3] >= 85 and CpuBrain.ERR_PROB[3] <= 5,
			"4단계부터 높은 가드율·낮은 실수율")
	t.ok(CpuBrain.REACT_DELAY[5] == 1 and CpuBrain.BLOCK_PROB[5] >= 98 \
			and CpuBrain.ERR_PROB[5] == 0, "6단계 최고 반응·가드·정확도")

	# 같은 긴 재판단 대기 중이어도 4단계부터는 공개된 상대 후딜을 즉시 처벌한다.
	var punish_world := H.mk(0, 1, 7701)
	punish_world.s["p"][1]["state"] = SimC.ST_RECOIL
	punish_world.s["p"][1]["x"] = punish_world.s["p"][0]["x"] + 20 * SimC.FP
	var normal := CpuBrain.new(0, 3, 88)
	var expert := CpuBrain.new(0, 4, 88)
	normal.cool = 99
	expert.cool = 99
	var facing: int = punish_world.s["p"][0]["facing"]
	t.eq(normal.think(punish_world), 0, "3단계는 기존 판단 주기를 기다림")
	t.eq(expert.think(punish_world), A.frames(A.Action.MEDIUM, facing)[0],
			"4단계는 보이는 후딜을 즉시 중베기로 처벌")

	# 같은 월드/CPU 시드에서는 매 틱 입력과 최종 상태가 완전히 같아야 한다.
	var wa := H.mk(0, 1, 20260718)
	var wb := H.mk(0, 1, 20260718)
	var a1 := CpuBrain.new(0, 6, 101)
	var a2 := CpuBrain.new(1, 6, 202)
	var b1 := CpuBrain.new(0, 6, 101)
	var b2 := CpuBrain.new(1, 6, 202)
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
	var cpu1 := CpuBrain.new(0, 6, 303)
	var cpu2 := CpuBrain.new(1, 6, 404)
	for tick in 6000:
		fight.step(cpu1.think(fight), cpu2.think(fight))
		if fight.s["phase"] == SimC.PH_MATCH_END:
			break
	t.eq(fight.s["phase"], SimC.PH_MATCH_END, "CPU 대 CPU 경기가 제한 틱 안에 종료")
