extends RefCounted
## AC-03: 히트박스는 데이터에 정의된 활성 프레임([발동+1, 발동+활성])에서만 켜진다.
## AC-02: 입력 버퍼는 정확히 5f.

const H := preload("res://tests/t_help.gd")

const SLOT_BTN := {"light": SimC.B_L, "medium": SimC.B_M, "heavy": SimC.B_H, "tech": SimC.B_T}


static func run(t, _args: Dictionary) -> void:
	t.suite("프레임 데이터 (AC-03)")

	var roster := Registry.load_all().size()
	for ci in roster:
		var opp := (ci + 1) % roster
		for slot in ["light", "medium", "heavy", "tech"]:
			var w := H.mk(ci, opp)
			w.debug_set_x(0, -450)   # 멀리 → 휘두르기만
			w.debug_set_x(1, 450)
			var mv: Dictionary = w.chars[0]["moves"][slot]
			var su: int = mv["su"]
			var act: int = mv["act"]
			var total: int = mv["total"]
			w.step(SLOT_BTN[slot], 0)   # st_f = 1
			var all_good := true
			for f in range(1, total + 1):
				var boxes := w.active_weapon_rects(0)
				var expect: bool = f >= su + 1 and f <= su + act
				if boxes.is_empty() == expect:
					all_good = false
				w.step(0, 0)
			t.ok(all_good, w.chars[0]["id"] + "/" + slot + " 활성 창 [" + str(su + 1) + "," + str(su + act) + "] 정확")

	t.suite("공격 루트 모션")
	for ci in roster:
		var wm := H.mk(ci, (ci + 1) % roster)
		for slot in ["light", "medium", "heavy"]:
			t.ok(not wm.chars[0]["moves"][slot]["motion"].is_empty(),
				wm.chars[0]["id"] + "/" + slot + " 몸 중심 이동 데이터")
	var wr := H.mk()
	wr.debug_set_x(0, -450)
	wr.debug_set_x(1, 450)
	var root_x0: int = wr.s["p"][0]["x"]
	wr.step(SimC.B_H, 0)
	H.run(wr, wr.chars[0]["moves"]["heavy"]["su"] + wr.chars[0]["moves"]["heavy"]["act"])
	t.ok(wr.s["p"][0]["x"] > root_x0 + 10 * SimC.FP, "강공격 발 디딤이 몸 중심을 전진시킴")

	t.suite("입력 버퍼 5f (AC-02)")
	# 약베기 휘두르기(19f) 후딜 종료 직전 버퍼: 4틱 전 입력은 발동, 5틱 전 입력은 만료
	var w := H.mk()
	w.debug_set_x(0, -450)
	w.debug_set_x(1, 450)
	var lt: Dictionary = w.chars[0]["moves"]["light"]
	var free_tick: int = lt["total"]   # st_f가 total 넘는 틱에 IDLE 복귀+행동 선택
	w.step(SimC.B_L, 0)
	for k in range(1, free_tick + 1):
		var word := 0
		if k == free_tick - 4:
			word = SimC.B_M
		w.step(word, 0)
	t.eq(w.s["p"][0]["move"], "arin_medium", "4틱 전 버퍼 입력은 발동")

	var w2 := H.mk()
	w2.debug_set_x(0, -450)
	w2.debug_set_x(1, 450)
	w2.step(SimC.B_L, 0)
	for k in range(1, free_tick + 1):
		var word := 0
		if k == free_tick - 5:
			word = SimC.B_M
		w2.step(word, 0)
	t.ok(w2.s["p"][0]["move"] != "arin_medium", "5틱 전 버퍼 입력은 만료")
