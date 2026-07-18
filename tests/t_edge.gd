extends RefCounted
## AC-04: WeaponEdge(칼끝 20%)가 먼저 닿을 때만 정타 배율(×1.25) 적용.

const H := preload("res://tests/t_help.gd")


static func run(t, _args: Dictionary) -> void:
	t.suite("칼결 정타 (AC-04)")

	# 아린 약베기: 박스 x28 w88 → 도달 116px, 칼결 구간 [98.4, 116]
	# 대루 hurtbox 반너비 46 → 앞면 100px 지점이면 칼결만 닿음.
	# 공격 루트 모션만큼 상대 시작점을 함께 옮겨 활성 프레임의 접촉 거리를 고정한다.
	var w := H.mk()
	w.debug_set_x(0, 0)
	var light: Dictionary = w.chars[0]["moves"]["light"]
	var root_to_active := _root_motion_until(light, light["su"] + 1)
	w.s["p"][1]["x"] = 146 * SimC.FP + root_to_active
	var evs := [] as Array
	w.step(SimC.B_L, 0)
	evs.append_array(H.run(w, 10))
	var hit := H.get_ev(evs, "hit")
	t.ok(not hit.is_empty(), "정타 거리에서 히트 발생")
	if not hit.is_empty():
		t.eq(hit["edge"], true, "칼결 정타 판정")
		t.eq(hit["dmg"], 88, "정타 피해 70→88 (×1.25)")
	t.eq(w.s["p"][0]["nerve"], 1, "정타로 사맥 +1")
	t.eq(w.s["p"][1]["scars"].size(), 1, "정타는 상처를 남긴다")
	t.eq(w.s["p"][1]["hp"], 912, "정타 피해 적용")

	# 몸통(안쪽 80%)이 같이 닿으면 일반 히트
	var w2 := H.mk()
	w2.debug_set_x(0, 0)
	w2.s["p"][1]["x"] = 126 * SimC.FP + root_to_active
	var evs2 := [] as Array
	w2.step(SimC.B_L, 0)
	evs2.append_array(H.run(w2, 10))
	var hit2 := H.get_ev(evs2, "hit")
	t.ok(not hit2.is_empty(), "근거리에서 히트 발생")
	if not hit2.is_empty():
		t.eq(hit2["edge"], false, "몸통 접촉은 일반 히트")
		t.eq(hit2["dmg"], 70, "일반 피해 70")
	t.eq(w2.s["p"][0]["nerve"], 0, "일반 히트는 사맥 없음")


static func _root_motion_until(mv: Dictionary, through_frame: int) -> int:
	var total := 0
	# 기술은 입력 틱 끝에 st_f=1로 시작하므로 실제 이동 적분은 f2부터다.
	for f in range(2, through_frame + 1):
		for m in mv["motion"]:
			if f >= int(m[0]) and f <= int(m[1]):
				total += int(m[2])
	return total
