extends RefCounted
## AC-05: 동시 타격/경합/패리/가드 우선순위 고정.

const H := preload("res://tests/t_help.gd")


static func run(t, _args: Dictionary) -> void:
	t.suite("경합/우선순위 (AC-05)")

	# 같은 우선순위(약 vs 약) 무기 교차 → 경합: 둘 다 취소, 피해 없음
	var w := H.mk()
	w.debug_set_x(0, 0)
	w.debug_set_x(1, 200)
	var evs: Array = []
	evs.append_array([w.step(SimC.B_L, SimC.B_L)])
	var flat: Array = []
	for k in 10:
		flat.append_array(w.step(0, 0))
	for e in evs:
		for ee in e:
			flat.append(ee)
	t.ok(H.has_ev(flat, "clash"), "동일 우선순위 → 경합 발생")
	t.eq(w.s["p"][0]["hp"], w.chars[0]["hp"], "경합은 피해 없음 (P1)")
	t.eq(w.s["p"][1]["hp"], w.chars[1]["hp"], "경합은 피해 없음 (P2)")
	t.ok(not H.has_ev(flat, "hit"), "경합 틱에 타격 없음")

	# 우선순위 차이(중 vs 약) → 낮은 쪽 무기 튕김(beaten), 높은 쪽 지속
	var w2 := H.mk()
	w2.debug_set_x(0, 0)
	w2.debug_set_x(1, 200)
	var f2: Array = []
	f2.append_array(w2.step(SimC.B_M, 0))
	f2.append_array(w2.step(0, 0))
	f2.append_array(w2.step(0, 0))
	f2.append_array(w2.step(0, SimC.B_L))
	for k in 12:
		f2.append_array(w2.step(0, 0))
	var beaten := H.get_ev(f2, "beaten")
	t.ok(not beaten.is_empty(), "우선순위 낮은 쪽 무기 튕김")
	if not beaten.is_empty():
		t.eq(beaten["p"], 1, "약베기(낮은 우선순위)가 튕긴다")

	t.suite("정밀 방어 / 가드 (AC-05)")

	# 피격 2틱 전 뒤 입력 → 정밀 방어: 칩 0, 사맥 +1, 공격자 밀림
	var w3 := H.mk()
	w3.debug_set_x(0, 0)
	w3.debug_set_x(1, 130)
	var f3: Array = []
	f3.append_array(w3.step(SimC.B_L, 0))
	for k in 3:
		f3.append_array(w3.step(0, 0))
	f3.append_array(w3.step(0, SimC.B_RIGHT))
	f3.append_array(w3.step(0, SimC.B_RIGHT))   # 접촉 틱, back_age=2
	for k in 6:
		f3.append_array(w3.step(0, SimC.B_RIGHT))
	t.ok(H.has_ev(f3, "parry"), "3f 내 뒤 입력 → 정밀 방어")
	t.eq(w3.s["p"][1]["hp"], 1000, "정밀 방어 칩 피해 0")
	t.eq(w3.s["p"][1]["nerve"], 1, "정밀 방어 사맥 +1")
	t.ok(not H.has_ev(f3, "hit"), "정밀 방어 시 타격 없음")

	# 오래 누르고 있던 가드 → 일반 가드: 칩 피해
	var w4 := H.mk()
	w4.debug_set_x(0, 0)
	w4.debug_set_x(1, 110)
	var f4: Array = []
	f4.append_array(w4.step(SimC.B_L, SimC.B_RIGHT))
	for k in 10:
		f4.append_array(w4.step(0, SimC.B_RIGHT))
	t.ok(H.has_ev(f4, "block"), "지속 가드 → 일반 가드")
	t.eq(w4.s["p"][1]["hp"], 993, "가드 칩 피해 7")
	t.ok(not H.has_ev(f4, "parry"), "3f 초과 유지는 정밀 방어 아님")

	# 경계: 접촉 시점 back_age 4 → 일반 가드 (창은 정확히 3f)
	var w5 := H.mk()
	w5.debug_set_x(0, 0)
	w5.debug_set_x(1, 130)
	var f5: Array = []
	f5.append_array(w5.step(SimC.B_L, 0))
	f5.append_array(w5.step(0, 0))
	for k in 4:
		f5.append_array(w5.step(0, SimC.B_RIGHT))
	for k in 6:
		f5.append_array(w5.step(0, SimC.B_RIGHT))
	t.ok(H.has_ev(f5, "block") and not H.has_ev(f5, "parry"), "back_age 4틱 → 일반 가드")
