extends RefCounted
## 하야테의 저피해 고속 연속기와 기력 기반 진입·이탈 검증.

const H := preload("res://tests/t_help.gd")


static func run(t, _args: Dictionary) -> void:
	t.suite("하야테 고속 진입·연속기·이탈")
	var han: Dictionary = Registry.bake(Registry.load_all()[2])
	var light: Dictionary = han["moves"]["light"]
	var medium: Dictionary = han["moves"]["medium"]
	var heavy: Dictionary = han["moves"]["heavy"]
	var tech: Dictionary = han["moves"]["tech"]
	t.ok(light["su"] == 4 and medium["su"] == 7 and heavy["su"] == 14,
			"약 4F·중 7F·강 14F의 빠른 공격 속도")
	t.ok(light["dmg"] == 40 and medium["dmg"] == 72 and heavy["dmg"] == 160,
			"단발 피해를 낮추고 연속 적중에 보상 집중")
	t.ok(tech["energy_cost"] == 50 and tech["dmg"] == 30,
			"파고들기는 두 번이면 기력을 소진하는 저피해 이동기")
	t.ok(int(tech["motion"][0][2]) > 0 and int(tech["motion"][-1][2]) < 0,
			"파고들기 후 입력하지 않으면 자동 이탈")
	t.ok(tech["cancels"][0]["targets"] == ["han_light", "han_medium"] \
			and tech["cancels"][0]["on"] == ["hit"],
			"파고들기 적중 때만 기본 연속기로 전환")

	var retreat := H.mk(2, 0, 721)
	retreat.debug_set_x(0, -300)
	retreat.debug_set_x(1, 300)
	var start_x: int = retreat.s["p"][0]["x"]
	retreat.step(SimC.B_T, 0)
	t.eq(retreat.s["p"][0]["energy"], SimC.ENERGY_MAX - 50,
			"대시 1회에 기력 50 소모")
	var farthest_x: int = int(retreat.s["p"][0]["x"])
	for tick in int(tech["total"]) + 2:
		retreat.step(0, 0)
		farthest_x = maxi(farthest_x, int(retreat.s["p"][0]["x"]))
	t.ok(farthest_x > start_x + 55 * SimC.FP \
			and retreat.s["p"][0]["x"] < farthest_x - 35 * SimC.FP,
			"헛친 대시는 크게 진입한 뒤 유의미하게 이탈")

	var chain := H.mk(2, 0, 722)
	chain.debug_set_x(0, 0)
	chain.debug_set_x(1, 112)
	chain.step(SimC.B_T, 0)
	var hit := false
	var light_started := false
	for tick in 14:
		var events := chain.step(0, 0)
		if H.has_ev(events, "hit"):
			hit = true
			chain.step(SimC.B_L, 0)
			for follow_tick in 12:
				chain.step(0, 0)
				light_started = light_started or chain.s["p"][0]["move"] == "han_light"
			break
	t.ok(hit and light_started,
			"파고들기 적중 후 약공격으로 즉시 연속")
