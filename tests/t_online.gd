extends RefCounted
## 온라인 방 코드와 틱 입력 큐의 결정론적 경계 검사.

const SessionScript := preload("res://autoload/online_session.gd")


static func run(t, _args: Dictionary) -> void:
	t.suite("온라인 방·입력 동기화")
	t.eq(SessionScript.sanitize_room_code("ab-i0o1-2z9x"), "AB2Z9X",
			"혼동 문자를 제외하고 안전한 6자리 방 코드로 정리")
	var generated: String = SessionScript.make_room_code()
	t.eq(generated.length(), 6, "새 방 코드는 6자리")
	t.eq(SessionScript.sanitize_room_code(generated), generated, "새 방 코드는 허용 문자만 사용")

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
