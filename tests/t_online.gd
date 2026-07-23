extends RefCounted
## 온라인 방 코드와 틱 입력 큐의 결정론적 경계 검사.

const SessionScript := preload("res://autoload/online_session.gd")
const Rollback := preload("res://combat/rollback_timeline.gd")
const H := preload("res://tests/t_help.gd")


class FakeChannel extends RefCounted:
	var local_slot := 0
	var inputs := [{}, {}]

	func _init(slot: int = 0) -> void:
		local_slot = slot

	func submit_input(tick: int, word: int) -> void:
		inputs[local_slot][tick] = word

	func has_input(slot: int, tick: int) -> bool:
		return inputs[slot].has(tick)

	func get_input(slot: int, tick: int, default_value: int = 0) -> int:
		return int(inputs[slot].get(tick, default_value))

	func discard_inputs_before(tick: int) -> void:
		for slot in 2:
			for key in inputs[slot].keys():
				if int(key) < tick:
					inputs[slot].erase(key)


static func run(t, _args: Dictionary) -> void:
	t.suite("온라인 방·입력 동기화")
	t.eq(SessionScript.sanitize_room_code("ab-0 4 2 7-xx99"), "0427",
			"숫자만 남긴 4자리 방 코드로 정리")
	var generated: String = SessionScript.make_room_code()
	t.eq(generated.length(), 4, "새 방 코드는 4자리")
	t.eq(SessionScript.sanitize_room_code(generated), generated, "새 방 코드는 숫자만 사용")
	var versioned_url := SessionScript.room_url("wss://relay.example/", "0427")
	t.ok(versioned_url.contains("v=2") \
			and versioned_url.contains("b=2026-07-20-hayate-rushdown"),
			"릴레이 연결에 프로토콜과 시뮬레이션 빌드 ID 포함")

	var session = SessionScript.new()
	session.role = 0
	session.status = "playing"
	session.submit_input(7, SimC.B_RIGHT | SimC.B_L)
	t.ok(not session.has_inputs(7), "상대 입력 전에는 틱 진행을 막음")
	session._receive_packet(JSON.stringify({"t": "input", "slot": 1, "k": 7, "w": SimC.B_LEFT}))
	t.ok(session.has_inputs(7), "양쪽 입력이 모이면 틱 진행 가능")
	t.eq(session.take_inputs(7), [SimC.B_RIGHT | SimC.B_L, SimC.B_LEFT],
			"P1/P2 슬롯 순서로 입력 반환")
	t.ok(not session.has_inputs(7), "소비한 틱 입력은 큐에서 제거")
	session.free()

	var stale_session = SessionScript.new()
	var stale_messages: Array[String] = []
	stale_session.network_error.connect(func(message: String): stale_messages.append(message))
	stale_session._receive_packet(JSON.stringify({
		"t": "error",
		"code": "version_mismatch",
		"message": "게임이 갱신되었습니다. 두 기기에서 화면을 다시 열어주세요.",
	}))
	t.eq(stale_session.status, "error", "구버전 연결은 로비 전에 중단")
	t.ok(stale_messages.size() == 1 and stale_messages[0].contains("갱신"),
			"구버전 사용자에게 재실행 안내")
	stale_session.free()

	# 상대 입력이 4틱 늦게 와도 로컬은 매 프레임 진행하고, 도착 뒤 권위 상태로 복원한다.
	var predicted_world := H.mk(0, 1, 31)
	var authoritative := H.mk(0, 1, 31)
	var timeline = Rollback.new(predicted_world, 0)
	var channel := FakeChannel.new(0)
	var p1_words: Array = []
	var p2_words: Array = []
	var captured_p1: Array = []
	var captured_p2: Array = []
	for tick in 180:
		var p1 := SimC.B_RIGHT if tick < 35 else (SimC.B_L if tick in [48, 92] else 0)
		var p2 := SimC.B_LEFT if tick < 45 else (SimC.B_H if tick in [52, 104] else 0)
		captured_p1.append(p1)
		captured_p2.append(p2)
		p1_words.append(0 if tick < Rollback.INPUT_DELAY else captured_p1[tick - Rollback.INPUT_DELAY])
		p2_words.append(0 if tick < Rollback.INPUT_DELAY else captured_p2[tick - Rollback.INPUT_DELAY])
		authoritative.step(p1_words[tick], p2_words[tick])
	var corrected := 0
	for frame in 180:
		if frame >= 4:
			channel.inputs[1][frame - 4] = p2_words[frame - 4]
		var result: Dictionary = timeline.frame(captured_p1[frame], channel)
		corrected += int(result["corrected_ticks"])
	for tick in range(176, 180):
		channel.inputs[1][tick] = p2_words[tick]
	var final_sync: Dictionary = timeline.sync(channel)
	corrected += int(final_sync["corrected_ticks"])
	t.eq(timeline.current_tick, 180, "4틱 원격 지연에도 로컬 시뮬은 매 프레임 진행")
	t.ok(corrected > 0, "늦게 온 공격·방향 입력 구간을 실제로 롤백 보정")
	t.eq(predicted_world.state_hash(), authoritative.state_hash(),
			"모든 입력 도착 뒤 권위 시뮬 상태와 해시 일치")

	# 연결이 멎으면 8틱까지만 예측하고 이후에는 미리 보낸 입력 틱을 보존한다.
	var capped_world := H.mk(0, 1, 41)
	var capped := Rollback.new(capped_world, 0)
	var silent := FakeChannel.new(0)
	for frame in Rollback.MAX_PREDICTION + Rollback.INPUT_DELAY + 8:
		var word := SimC.B_L if frame == Rollback.MAX_PREDICTION else 0
		capped.frame(word, silent)
	t.eq(capped.current_tick, Rollback.MAX_PREDICTION, "원격 단절 시 MAX_PREDICTION 틱 뒤 안전 정지")
	t.eq(silent.get_input(0, Rollback.MAX_PREDICTION + Rollback.INPUT_DELAY, -1), SimC.B_L,
			"정지 중 같은 틱 로컬 입력을 덮어쓰지 않음")

	# 첫 프레임에 중립 2틱과 현재 입력을 미래 틱으로 연속 전송한다.
	var delayed_world := H.mk(0, 1, 51)
	var delayed := Rollback.new(delayed_world, 0)
	var delayed_channel := FakeChannel.new(0)
	delayed.frame(SimC.B_H, delayed_channel)
	t.eq(delayed_channel.get_input(0, 0, -1), 0, "입력 지연 첫 틱은 중립")
	t.eq(delayed_channel.get_input(0, 1, -1), 0, "입력 지연 둘째 틱도 중립")
	t.eq(delayed_channel.get_input(0, Rollback.INPUT_DELAY, -1), SimC.B_H,
			"현재 조작은 INPUT_DELAY틱 앞서 전송")
