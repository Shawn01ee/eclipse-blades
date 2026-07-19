extends RefCounted
## 5번째 오리지널 중량 검객 무진의 등록·역할·오의 입력 검증.

const H := preload("res://tests/t_help.gd")


static func run(t, _args: Dictionary) -> void:
	t.suite("무진 로스터/기술")
	var fds := Registry.load_all()
	t.eq(fds.size(), 6, "로스터 6명")
	t.eq(fds[4].id, "mujin", "5번째 파이터 무진 등록")
	var w := H.mk(4, 0, 77)
	t.eq(w.chars[0]["moves"].size(), 11, "무진 기본 7개 + 파도 연계 4개")
	t.ok(w.chars[0]["hp"] > w.chars[1]["hp"] and w.chars[0]["walk_f"] < w.chars[1]["walk_f"],
			"높은 체력·느린 보행의 중량 역할")
	t.ok(w.chars[0]["moves"]["heavy"]["dmg"] >= 330 \
			and w.chars[0]["moves"]["heavy"]["stop"] >= 15, "강공격 단발 피해·히트스톱")

	w.debug_set_x(0, -450)
	w.debug_set_x(1, 450)
	w.debug_set_nerve(0, 3)
	var evs: Array = []
	evs.append_array(w.step(SimC.B_DOWN, 0))
	evs.append_array(w.step(SimC.B_DOWN | SimC.B_RIGHT, 0))
	evs.append_array(w.step(SimC.B_RIGHT, 0))
	evs.append_array(w.step(SimC.B_RIGHT | SimC.B_H | SimC.B_T, 0))
	t.ok(H.has_ev(evs, "super") and w.s["p"][0]["move"] == "mujin_super",
			"무진 고유 오의 진입")

	# 같은 ↓↘→ 궤적이 버튼 강도에 따라 서로 다른 실제 프레임 데이터로 이어진다.
	var motion_specs := [
		[SimC.B_L, "mujin_motion_light"],
		[SimC.B_M, "mujin_motion_medium"],
		[SimC.B_H, "mujin_motion_heavy"],
	]
	for spec in motion_specs:
		var mw := H.mk(4, 0, 81)
		mw.debug_set_x(0, -450)
		mw.debug_set_x(1, 450)
		mw.step(SimC.B_DOWN, 0)
		mw.step(SimC.B_DOWN | SimC.B_RIGHT, 0)
		mw.step(SimC.B_RIGHT, 0)
		mw.step(SimC.B_RIGHT | int(spec[0]), 0)
		t.eq(mw.s["p"][0]["move"], String(spec[1]), "%s 커맨드 진입" % String(spec[1]))

	var nw := H.mk(4, 0, 91)
	nw.debug_set_x(0, -450)
	nw.debug_set_x(1, 450)
	nw.debug_set_nerve(0, SimC.NERVE_MAX)
	var nevs: Array = []
	nevs.append_array(nw.step(SimC.B_DOWN, 0))
	nevs.append_array(nw.step(SimC.B_DOWN | SimC.B_RIGHT, 0))
	nevs.append_array(nw.step(SimC.B_RIGHT, 0))
	nevs.append_array(nw.step(SimC.B_RIGHT | SimC.B_H, 0))
	t.ok(nw.s["p"][0]["move"] == "mujin_motion_nerve" and nw.s["p"][0]["nerve"] == 2,
			"사맥 최대 강 연계는 강화기로 바뀌고 1칸 소비")
	t.ok(H.has_ev(nevs, "nerve_art"), "사맥 강화 연출 이벤트 발생")

	var hitw := H.mk(4, 0, 92)
	hitw.debug_set_x(0, -155)
	hitw.debug_set_x(1, 90)
	hitw.debug_set_nerve(0, SimC.NERVE_MAX)
	var hit_evs: Array = []
	hit_evs.append_array(hitw.step(SimC.B_DOWN, 0))
	hit_evs.append_array(hitw.step(SimC.B_DOWN | SimC.B_RIGHT, 0))
	hit_evs.append_array(hitw.step(SimC.B_RIGHT, 0))
	hit_evs.append_array(hitw.step(SimC.B_RIGHT | SimC.B_H, 0))
	hit_evs.append_array(H.run(hitw, 28))
	var hit_ev := H.get_ev(hit_evs, "hit")
	t.ok(not hit_ev.is_empty() and hit_ev["kind"] == "heavy", "홍해일파 실제 강 판정 적중")
	t.eq(hitw.s["p"][1]["hp"], hitw.chars[1]["hp"] - 360, "홍해일파 실제 피해 360")
