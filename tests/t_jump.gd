extends RefCounted
## 점프 시스템: 도약 아크, 착지, 공중 공격, 공중 저글, 결정론.

const H := preload("res://tests/t_help.gd")


static func run(t, _args: Dictionary) -> void:
	t.suite("점프 아크 / 착지")

	var w := H.mk()
	w.debug_set_x(0, -100)
	w.debug_set_x(1, 300)
	# 중립 점프 (↑)
	w.step(SimC.B_UP, 0)
	# 프리점프 후 공중 진입
	var launched := false
	var max_y := 0
	var landed := false
	for k in 90:
		w.step(0, 0)
		var p: Dictionary = w.s["p"][0]
		if p["state"] == SimC.ST_JUMP:
			launched = true
			max_y = maxi(max_y, p["y"])
		if launched and (p["state"] == SimC.ST_LAND or p["state"] == SimC.ST_IDLE) and p["y"] == 0:
			landed = true
			break
	t.ok(launched, "↑ 입력 → 도약")
	t.ok(max_y > 100 * SimC.FP and max_y < 260 * SimC.FP, "점프 정점 높이 합리적 (%dpx)" % (max_y / SimC.FP))
	t.ok(landed, "결국 착지해 지면 복귀")
	t.eq(w.s["p"][0]["y"], 0, "착지 후 높이 0")

	t.suite("전진 점프 이동")
	var w2 := H.mk()
	w2.debug_set_x(0, -200)
	w2.debug_set_x(1, 300)
	w2.step(0, 0)   # 방향 확정 (facing +)
	var x0: int = w2.s["p"][0]["x"]
	w2.step(SimC.B_RIGHT | SimC.B_UP, 0)
	for k in 40:
		w2.step(SimC.B_RIGHT, 0)
	t.ok(w2.s["p"][0]["x"] > x0 + 40 * SimC.FP, "전진 점프로 전진 이동")

	t.suite("지상 가속 / 관성 / 마찰")
	var wg := H.mk()
	wg.debug_set_x(0, -300)
	wg.debug_set_x(1, 300)
	wg.step(SimC.B_RIGHT, 0)
	var v1: int = wg.s["p"][0]["vx"]
	for k in 5:
		wg.step(SimC.B_RIGHT, 0)
	var v6: int = wg.s["p"][0]["vx"]
	t.ok(v1 < v6 and v6 <= wg.chars[0]["walk_f"], "걷기 속도가 즉시이동 대신 가속")
	var release_x: int = wg.s["p"][0]["x"]
	wg.step(0, 0)
	wg.step(0, 0)
	t.ok(wg.s["p"][0]["x"] > release_x, "입력 해제 직후 관성 이동")
	for k in 8:
		wg.step(0, 0)
	t.eq(wg.s["p"][0]["vx"], 0, "마찰로 지상 속도 정지")

	t.suite("공중 공격")
	var w3 := H.mk()
	w3.debug_set_x(0, -60)
	w3.debug_set_x(1, 40)
	w3.step(0, 0)
	w3.step(SimC.B_UP, 0)
	var air_atk := false
	var evs: Array = []
	for k in 20:
		var p: Dictionary = w3.s["p"][0]
		var word := 0
		if p["state"] == SimC.ST_JUMP and p["vy"] > 0:   # 상승 중 공격
			word = SimC.B_M
		evs.append_array(w3.step(word, 0))
		if w3.s["p"][0]["state"] == SimC.ST_AIR_ATTACK:
			air_atk = true
			t.eq(w3.move_phase(0), "startup", "공중 공격도 프레임 단계를 제공")
			break
	t.ok(air_atk, "상승 중 공격 → 공중 공격 발동")

	t.suite("공중 저글 (공중 상대 타격 → 뜸)")
	var w4 := H.mk()
	w4.debug_set_x(0, 0)
	w4.debug_set_x(1, 60)
	# 판정 타이밍을 고정해 P2를 공중에 둔다.
	w4.s["p"][1]["state"] = SimC.ST_JUMP
	w4.s["p"][1]["y"] = 180 * SimC.FP
	w4.s["p"][1]["vy"] = 0
	t.ok(w4.s["p"][1]["state"] == SimC.ST_JUMP, "P2 공중 상태")
	# P1 강베기로 공중의 P2 가격
	var f4: Array = []
	f4.append_array(w4.step(SimC.B_H, 0))
	for k in 24:
		f4.append_array(w4.step(0, 0))
	var hit := H.get_ev(f4, "hit")
	t.ok(not hit.is_empty(), "공중 상대에게 강베기 적중")
	t.ok(hit.get("air", false), "공중 상대 타격은 air 플래그")
	t.ok(w4.s["p"][1]["state"] == SimC.ST_AIR_HIT or w4.s["p"][1]["state"] == SimC.ST_LAND
		or w4.s["p"][1]["hp"] < w4.chars[1]["hp"], "공중 피격 처리됨")

	t.suite("점프 포함 결정론")
	var seeds := [5, 5]
	var hashes: Array = []
	for rep in 2:
		var wr := H.mk(0, 1, 5)
		var a := 21
		var b := 88
		for k in 1500:
			a = H.lcg(a)
			b = H.lcg(b)
			wr.step(H.monkey_word(a), H.monkey_word(b))
		hashes.append(wr.state_hash())
	t.eq(hashes[0], hashes[1], "점프 포함 1500틱 재생 해시 일치")
