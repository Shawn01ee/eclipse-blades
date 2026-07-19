extends RefCounted
## 캐릭터별 중·강·기술 역할과 위험/보상 차별화 회귀 검증.

const H := preload("res://tests/t_help.gd")


static func _reach(mv: Dictionary) -> int:
	var best := 0
	for box in mv["boxes"]:
		best = maxi(best, int(box[2]) + int(box[4]))
	return best


static func run(t, _args: Dictionary) -> void:
	t.suite("6인 기술 역할·밸런스")
	var fds := Registry.load_all()
	var baked: Array = []
	for fd in fds:
		var fighter := Registry.bake(fd)
		baked.append(fighter)
		var roles_ok := true
		for slot in ["medium", "heavy", "tech"]:
			roles_ok = roles_ok and String(fighter["moves"][slot]["role"]) != ""
		t.ok(roles_ok, fighter["id"] + " 중·강·기술 역할 설명")
		var med: Dictionary = fighter["moves"]["medium"]
		var heavy: Dictionary = fighter["moves"]["heavy"]
		t.ok(heavy["dmg"] > med["dmg"] and heavy["su"] > med["su"] \
				and heavy["rec"] > med["rec"] and heavy["prio"] > med["prio"],
				fighter["id"] + " 중=안정 / 강=고위험 고보상")

	var arin_cw: Dictionary = baked[0]["moves"]["medium"]["cancels"][0]
	t.ok(arin_cw["targets"] == ["arin_heavy"] and arin_cw["on"] == ["hit"],
			"아야메 중공격은 적중 확인 후 강공격")
	t.ok(baked[1]["moves"]["medium"]["cancels"].is_empty() \
			and int(baked[1]["moves"]["heavy"]["boxes"][0][5]) >= 100,
			"이와오는 연계 대신 장거리·대공 판정")
	var han_cw: Dictionary = baked[2]["moves"]["medium"]["cancels"][0]
	t.ok(han_cw["targets"].has("han_heavy") and han_cw["targets"].has("han_tech") \
			and han_cw["on"].has("block"), "하야테는 가드 중에도 강·기술 연속 압박")
	t.ok(baked[3]["moves"]["tech"]["push_hit"] < 0 \
			and int(baked[3]["moves"]["heavy"]["boxes"][0][2]) >= 80,
			"카게로는 끌어오기와 초장거리 근접 사각")
	t.ok(baked[4]["moves"].has("motion_light") and baked[4]["moves"].has("motion_heavy") \
			and baked[4]["moves"]["heavy"]["dmg"] > baked[1]["moves"]["heavy"]["dmg"],
			"무진은 파도 커맨드와 로스터 최고 단발")
	var jiko_light_cancel: Dictionary = baked[5]["moves"]["light"]["cancels"][0]
	var jiko_medium_cancel: Dictionary = baked[5]["moves"]["medium"]["cancels"][0]
	var jiko_tech_motion: Array = baked[5]["moves"]["tech"]["motion"]
	t.ok(jiko_light_cancel["targets"].has("jiko_medium") \
			and jiko_medium_cancel["targets"].has("jiko_heavy") \
			and jiko_medium_cancel["on"].has("block"),
			"지코는 약→중→강으로 가드 중에도 이어지는 3단 압박")
	t.ok(int(jiko_tech_motion[0][2]) < 0 and int(jiko_tech_motion[1][2]) > 0,
			"지코 기술은 먼저 물러난 뒤 다시 파고드는 역박자")

	# 공통 밸런스 가드레일: 강공격은 즉사기가 아니며 최소 14f 이상 보고 대응 가능.
	var guardrails := true
	for fighter in baked:
		var hv: Dictionary = fighter["moves"]["heavy"]
		guardrails = guardrails and hv["dmg"] >= 160 and hv["dmg"] <= 350 and hv["su"] >= 14
	t.ok(guardrails, "전원 강공격 피해 160~350·발동 14f 이상")
	t.ok(_reach(baked[3]["moves"]["heavy"]) > _reach(baked[1]["moves"]["heavy"]) \
			and _reach(baked[1]["moves"]["medium"]) > _reach(baked[0]["moves"]["medium"]),
			"카게로 초장거리 > 이와오 장거리 > 아야메 표준거리")

	# 0.4.1 육검 조율의 핵심 수치가 후속 작업에서 실수로 되돌아가지 않게 고정한다.
	t.ok(baked[0]["hp"] == 900 \
			and baked[0]["moves"]["tech"]["su"] == 9 \
			and baked[0]["moves"]["light"]["cancels"][0]["on"] == ["hit"],
			"아야메는 낮은 체력·반응 가능한 발도·적중 전용 약 연계")
	t.ok(baked[2]["hp"] == 975 \
			and baked[2]["moves"]["tech"]["dmg"] == 30 \
			and baked[2]["moves"]["tech"]["energy_cost"] == 50,
			"하야테는 보강된 체력과 기력을 거는 저피해 파고들기")
	t.ok(baked[3]["moves"]["medium"]["su"] == 11 \
			and baked[3]["moves"]["heavy"]["su"] == 21 \
			and baked[3]["moves"]["tech"]["su"] == 9,
			"카게로 사슬 견제 발동 1프레임 개선")
	t.ok(baked[4]["hp"] == 1125 \
			and baked[4]["moves"]["medium"]["dmg"] == 155 \
			and baked[4]["moves"]["heavy"]["dmg"] == 310,
			"무진은 중량 정체성을 유지하며 체력·단발 피해 절제")
	t.ok(baked[5]["hp"] == 1060 \
			and baked[5]["moves"]["medium"]["dmg"] == 112 \
			and baked[5]["moves"]["tech"]["dmg"] == 125,
			"지코는 허리치기·중단 찌르기의 적중 보상 강화")

	# 카게로 낚아채기는 수치 표기만이 아니라 실제로 상대를 공격자 쪽으로 당긴다.
	var pullw := H.mk(3, 0, 303)
	pullw.debug_set_x(0, -200)
	pullw.debug_set_x(1, 80)
	var before_x: int = pullw.s["p"][1]["x"]
	var pull_evs: Array = []
	pull_evs.append_array(pullw.step(SimC.B_T, 0))
	pull_evs.append_array(H.run(pullw, 28))
	t.ok(H.has_ev(pull_evs, "hit"), "카게로 사슬낚아채기 실제 적중")
	t.ok(pullw.s["p"][1]["x"] < before_x, "적중 상대를 카게로 방향으로 끌어옴")
