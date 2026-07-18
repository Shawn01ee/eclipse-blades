extends RefCounted
## AC-02 / AC-09: 같은 입력 로그 → 같은 상태. 10,000틱 재생 해시 일치.
## 롤백 대비: 스냅샷 복원 후 같은 입력 재생 시 해시 일치.

const H := preload("res://tests/t_help.gd")


static func run(t, _args: Dictionary) -> void:
	t.suite("결정론 (AC-02, AC-09)")

	# 1,000틱 (첫 마일스톤 기준) + 10,000틱 재생 해시 비교
	for ticks in [1000, 10000]:
		var hashes: Array = []
		for rep in 2:
			var w := H.mk(0, 1, 7, {"skip_intro": false, "timer_ticks": SimC.ROUND_TICKS})
			var x1 := 11
			var x2 := 77
			for k in ticks:
				x1 = H.lcg(x1)
				x2 = H.lcg(x2)
				w.step(H.monkey_word(x1), H.monkey_word(x2))
			hashes.append(w.state_hash())
		t.eq(hashes[0], hashes[1], str(ticks) + "틱 재생 해시 일치")

	# 스냅샷 → 복원 → 동일 입력 재생 = 동일 해시
	var w := H.mk(0, 1, 3)
	var log: Array = []
	var x1 := 5
	var x2 := 9
	for k in 500:
		x1 = H.lcg(x1)
		x2 = H.lcg(x2)
		w.step(H.monkey_word(x1), H.monkey_word(x2))
	var snap := w.snapshot()
	log.clear()
	for k in 300:
		x1 = H.lcg(x1)
		x2 = H.lcg(x2)
		log.append([H.monkey_word(x1), H.monkey_word(x2)])
		w.step(log[k][0], log[k][1])
	var h_a := w.state_hash()
	w.restore(snap)
	for pair in log:
		w.step(pair[0], pair[1])
	t.eq(w.state_hash(), h_a, "스냅샷 복원 후 재생 해시 일치")
