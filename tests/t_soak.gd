extends RefCounted
## AC-12: 자동 경기 다수 실행 — 크래시·상태 교착·무한 콤보·범위 이탈 없음.
## 기본 10경기, 명령줄 인자 soak=100 으로 확장.

const H := preload("res://tests/t_help.gd")

const VALID_STATES := [SimC.ST_IDLE, SimC.ST_WALK_F, SimC.ST_WALK_B, SimC.ST_ATTACK,
	SimC.ST_HITSTUN, SimC.ST_BLOCKSTUN, SimC.ST_RECOIL, SimC.ST_GRABBING,
	SimC.ST_GRABBED, SimC.ST_KO, SimC.ST_WIN, SimC.ST_PREJUMP, SimC.ST_JUMP,
	SimC.ST_LAND, SimC.ST_AIR_ATTACK, SimC.ST_AIR_HIT]


static func run(t, args: Dictionary) -> void:
	var n: int = args.get("soak", 10)
	t.suite("자동 경기 소크 ×" + str(n) + " (AC-12)")

	var max_ticks := 5 * (SimC.INTRO_TICKS + SimC.ROUND_TICKS + SimC.ROUND_END_TICKS) + 2000
	var roster := Registry.load_all().size()
	var bad := 0
	for m in n:
		var a := m % roster
		var b := (m / roster) % roster
		var w := H.mk(a, b, 1000 + m * 17, {"skip_intro": false, "timer_ticks": SimC.ROUND_TICKS})
		var x1 := 31 + m
		var x2 := 900 + m * 3
		var ended := false
		var max_combo := 0
		for k in max_ticks:
			x1 = H.lcg(x1)
			x2 = H.lcg(x2)
			w.step(H.monkey_word(x1), H.monkey_word(x2))
			for i in 2:
				var p: Dictionary = w.s["p"][i]
				if p["hp"] < 0 or p["hp"] > w.chars[i]["hp"]:
					bad += 1
				if absi(p["x"]) > SimC.STAGE_HALF:
					bad += 1
				if not VALID_STATES.has(p["state"]):
					bad += 1
				if p["y"] < 0 or p["y"] > 400 * SimC.FP:
					bad += 1
				max_combo = maxi(max_combo, p["combo"])
			if w.s["phase"] == SimC.PH_MATCH_END:
				ended = true
				break
		if not ended:
			bad += 1
			print("    경기 ", m, " 미종료 (교착 의심)")
		if max_combo > 12:
			bad += 1
			print("    경기 ", m, " 콤보 ", max_combo, " — 무한 콤보 의심")
	t.eq(bad, 0, "모든 경기 정상 종료·불변식 유지")
