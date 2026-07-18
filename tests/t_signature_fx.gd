extends RefCounted
## 모든 캐릭터의 주요 공격이 실제 활성 프레임에 고유 이펙트용 영역을 방출하는지 검증한다.

const H := preload("res://tests/t_help.gd")


static func run(t, _args: Dictionary) -> void:
	t.suite("캐릭터·공격별 시그니처 이펙트")
	var buttons := {
		"light": SimC.B_L, "medium": SimC.B_M, "heavy": SimC.B_H,
		"tech": SimC.B_T, "super": SimC.B_SUPER,
	}
	var fds := Registry.load_all()
	for fighter_i in fds.size():
		var fighter: Dictionary = Registry.bake(fds[fighter_i])
		for slot in buttons:
			var opponent_i := 1 if fighter_i == 0 else 0
			var world := H.mk(fighter_i, opponent_i, 800 + fighter_i * 10 + buttons.keys().find(slot))
			world.debug_set_x(0, -300)
			world.debug_set_x(1, 300)
			if slot == "super":
				world.debug_set_nerve(0, SimC.NERVE_MAX)
			var events: Array = world.step(buttons[slot], 0)
			events.append_array(H.run(world, int(fighter["moves"][slot]["su"]) + 3))
			var active := H.get_ev(events, "move_active")
			var valid: bool = not active.is_empty() \
					and active.get("id", "") == fighter["moves"][slot]["id"] \
					and active.get("kind", "") == slot \
					and not active.get("rects", []).is_empty()
			t.ok(valid, fighter["id"] + " " + slot + " 활성 판정과 이펙트 영역 일치")
