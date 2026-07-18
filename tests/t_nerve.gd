extends RefCounted
## 사맥 순환: 휘두르기 처벌 +1, 자세 취소(1칸), 오의(3칸).

const H := preload("res://tests/t_help.gd")


static func run(t, _args: Dictionary) -> void:
	t.suite("사맥 획득/소비")

	# 휘두르기 처벌: 대루 장월꿰기 헛침 → 후딜에 아린 약베기 적중 → 아린 사맥 +1
	var w := H.mk()
	w.debug_set_x(0, 220)
	w.debug_set_x(1, 300)
	w.step(0, 0)   # 방향 갱신
	var f: Array = []
	f.append_array(w.step(0, SimC.B_T))
	for k in 13:
		f.append_array(w.step(0, 0))
	f.append_array(w.step(SimC.B_L, 0))
	for k in 10:
		f.append_array(w.step(0, 0))
	var hit := H.get_ev(f, "hit")
	t.ok(H.has_ev(f, "whiff"), "장월꿰기 헛침 발생")
	t.ok(not hit.is_empty() and hit.get("punish", false), "후딜 타격 = 휘두르기 처벌")
	t.eq(w.s["p"][0]["nerve"], 1, "처벌로 사맥 +1")

	# 자세 취소: 후딜 중 뒤+기술, 사맥 1 소비
	var w2 := H.mk()
	w2.debug_set_x(0, -450)
	w2.debug_set_x(1, 450)
	w2.debug_set_nerve(0, 1)
	w2.step(SimC.B_L, 0)
	for k in 9:
		w2.step(0, 0)   # st_f 10 → 후딜(9..19)
	var f2 := w2.step(SimC.B_LEFT | SimC.B_T, 0)
	t.ok(H.has_ev(f2, "nerve_cancel"), "자세 취소 발동")
	t.eq(w2.s["p"][0]["state"], SimC.ST_IDLE, "후딜 취소 → 중립 복귀")
	t.eq(w2.s["p"][0]["nerve"], 0, "사맥 1칸 소비")

	# 오의: 사맥 3 + ↓↘→ + 강+기술
	var w3 := H.mk()
	w3.debug_set_x(0, -450)
	w3.debug_set_x(1, 450)
	w3.debug_set_nerve(0, 3)
	var f3: Array = []
	f3.append_array(w3.step(SimC.B_DOWN, 0))
	f3.append_array(w3.step(SimC.B_DOWN | SimC.B_RIGHT, 0))
	f3.append_array(w3.step(SimC.B_RIGHT, 0))
	f3.append_array(w3.step(SimC.B_RIGHT | SimC.B_H | SimC.B_T, 0))
	t.ok(H.has_ev(f3, "super"), "오의 발동")
	t.eq(w3.s["p"][0]["move"], "arin_super", "오의 기술 진입")
	t.eq(w3.s["p"][0]["nerve"], 0, "사맥 3칸 전부 소비")

	# 사맥 없이는 오의 불가
	var w4 := H.mk()
	w4.debug_set_x(0, -450)
	w4.debug_set_x(1, 450)
	var f4: Array = []
	f4.append_array(w4.step(SimC.B_SUPER, 0))
	t.ok(not H.has_ev(f4, "super"), "사맥 0 → 오의 불발")

	# 접근성 입력: 사맥 3이면 Q/P/패드 숄더에 매핑되는 한 버튼으로 즉시 오의.
	var w5 := H.mk()
	w5.debug_set_x(0, -450)
	w5.debug_set_x(1, 450)
	w5.debug_set_nerve(0, 3)
	var f5 := w5.step(SimC.B_SUPER, 0)
	t.ok(H.has_ev(f5, "super"), "오의 전용키 한 번으로 발동")
	t.eq(w5.s["p"][0]["move"], "arin_super", "전용키도 같은 오의 기술 진입")
	t.eq(w5.s["p"][0]["nerve"], 0, "전용키도 사맥 3칸 소비")
