extends RefCounted
## 기술 남용을 막는 결정론적 기력 소모·회복·기본기 대체 검사.

const H := preload("res://tests/t_help.gd")


static func run(t, _args: Dictionary) -> void:
	t.suite("기력 소모·회복")
	var w := H.mk(0, 1, 301)
	var tech: Dictionary = w.chars[0]["moves"]["tech"]
	t.eq(w.s["p"][0]["energy"], SimC.ENERGY_MAX, "라운드 시작 기력 최대")
	w.step(SimC.B_T, 0)
	t.eq(w.s["p"][0]["move"], "arin_tech", "기력이 있으면 고유 기술 발동")
	t.eq(w.s["p"][0]["energy"], SimC.ENERGY_MAX - int(tech["energy_cost"]),
			"고유 기술별 기력 소모")
	H.run(w, int(tech["total"]) - 1)
	t.eq(w.s["p"][0]["energy"], SimC.ENERGY_MAX - int(tech["energy_cost"]),
			"공격 동작 중 기력 회복 정지")
	H.run(w, SimC.ENERGY_REGEN_TICKS)
	t.eq(w.s["p"][0]["energy"], SimC.ENERGY_MAX - int(tech["energy_cost"]) + 1,
			"비공격 상태에서 3틱마다 기력 회복")

	var empty := H.mk(0, 1, 302)
	empty.debug_set_energy(0, 0)
	var denied: Array = empty.step(SimC.B_T, 0)
	t.ok(H.has_ev(denied, "energy_empty"), "기력 부족 피드백 이벤트")
	t.eq(empty.s["p"][0]["move"], "arin_light", "기력 부족 기술 입력은 기본 약베기로 대체")
	t.eq(empty.s["p"][0]["energy"], 0, "기력은 음수가 되지 않음")

	var fds := Registry.load_all()
	for fd in fds:
		var baked: Dictionary = Registry.bake(fd)
		t.eq(int(baked["moves"]["light"]["energy_cost"]), 0,
				"%s 기본 약공격은 무료" % baked["name"])
		t.ok(int(baked["moves"]["tech"]["energy_cost"]) >= 30,
				"%s 고유 기술은 기력 소모" % baked["name"])
		t.eq(int(baked["moves"]["super"]["energy_cost"]), 0,
				"%s 오의는 기존 사맥만 사용" % baked["name"])

	var mujin := H.mk(4, 0, 303)
	var light_wave: Dictionary = mujin.chars[0]["moves"]["motion_light"]
	mujin.step(SimC.B_DOWN, 0)
	mujin.step(SimC.B_DOWN | SimC.B_RIGHT, 0)
	mujin.step(SimC.B_RIGHT, 0)
	mujin.step(SimC.B_RIGHT | SimC.B_L, 0)
	t.eq(mujin.s["p"][0]["energy"], SimC.ENERGY_MAX - int(light_wave["energy_cost"]),
			"무진 커맨드 파도도 강도별 기력 소모")

	var fallback_wave := H.mk(4, 0, 304)
	fallback_wave.debug_set_nerve(0, SimC.NERVE_MAX)
	fallback_wave.debug_set_energy(0, 55)
	fallback_wave.step(SimC.B_DOWN, 0)
	fallback_wave.step(SimC.B_DOWN | SimC.B_RIGHT, 0)
	fallback_wave.step(SimC.B_RIGHT, 0)
	fallback_wave.step(SimC.B_RIGHT | SimC.B_H, 0)
	t.eq(fallback_wave.s["p"][0]["move"], "mujin_motion_heavy",
			"강화기 기력이 부족하면 일반 해일파로 자연스럽게 대체")
	t.eq(fallback_wave.s["p"][0]["nerve"], SimC.NERVE_MAX,
			"강화기가 아니면 사맥을 소비하지 않음")
