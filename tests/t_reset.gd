extends RefCounted
## AC-07: 훈련 리셋이 위치·체력·사맥·상태·난수·틱을 초기값으로 복구.

const H := preload("res://tests/t_help.gd")


static func run(t, _args: Dictionary) -> void:
	t.suite("훈련 리셋 (AC-07)")

	var fresh := H.mk(0, 1, 42)
	var h0 := fresh.state_hash()

	var w := H.mk(0, 1, 42)
	var x := 3
	for k in 200:
		x = H.lcg(x)
		w.step(H.monkey_word(x), H.monkey_word(x >> 3))
	t.ok(w.state_hash() != h0, "플레이 후 상태 변화 확인")
	w.reset_match()
	t.eq(w.state_hash(), h0, "리셋 후 초기 상태 해시 일치")
