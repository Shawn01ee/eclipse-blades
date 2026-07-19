extends RefCounted
## 6번째 오리지널 검객 지코의 3단 압박과 역박자 이동 검증.

const H := preload("res://tests/t_help.gd")


static func run(t, _args: Dictionary) -> void:
	t.suite("지코 야차 연계")
	var fds := Registry.load_all()
	t.eq(fds[5].id, "jiko", "6번째 파이터 지코 등록")
	t.eq(fds[5].weapon_name, "죽도", "지코 무기는 죽도로 표시")
	t.eq(fds[5].moves["light"].display_name, "손목치기", "약공격은 빠른 손목 타격")
	t.eq(fds[5].moves["medium"].display_name, "허리치기", "중공격은 대각선 허리 타격")
	t.eq(fds[5].moves["heavy"].display_name, "머리치기", "강공격은 큰 머리 내려치기")
	t.eq(fds[5].moves["tech"].display_name, "중단 찌르기", "기술은 간격을 재는 중심선 찌르기")
	t.ok(fds[5].moves["super"].display_name.contains("기검체일치"), "오의는 검도식 기검체일치")
	t.ok(fds[5].moves["light"].startup_frames < fds[5].moves["medium"].startup_frames \
			and fds[5].moves["medium"].startup_frames < fds[5].moves["heavy"].startup_frames,
			"손목→허리→머리 순서로 동작 크기와 발동 시간이 증가")
	t.ok(fds[5].moves["heavy"].hitboxes_by_frame[0][3] \
			> fds[5].moves["medium"].hitboxes_by_frame[0][3],
			"머리치기 판정이 허리치기보다 높은 부위를 노림")
	var fx_source := FileAccess.get_file_as_string("res://ui/fx_layer.gd")
	var match_source := FileAccess.get_file_as_string("res://ui/match_screen.gd")
	t.ok(fx_source.contains("func _draw_shinai_contact") \
			and fx_source.contains('"light":') and fx_source.contains('"tech":'),
			"검도 타격별 궤적과 죽도 접촉 이펙트 분리")
	t.ok(match_source.contains('attacker_id == "jiko"') \
			and match_source.contains("blood_scale := 0.42"),
			"죽도 타격음 추가 및 칼날식 출혈 연출 절제")
	var view_source := FileAccess.get_file_as_string("res://ui/fighter_view.gd")
	t.ok(view_source.contains('"jiko": "shinai"') and view_source.contains("func _wp_shinai"),
			"지코 전투 모델에 전용 죽도 렌더러 연결")
	var w := H.mk(5, 0, 607)
	w.debug_set_x(0, 0)
	w.debug_set_x(1, 112)
	w.step(SimC.B_L, 0)
	var light_hit := false
	for k in 24:
		var events := w.step(0, 0)
		if H.has_ev(events, "hit"):
			light_hit = true
			w.step(SimC.B_M, 0)
			break
	var medium_started := false
	var medium_hit := false
	for k in 50:
		var events := w.step(0, 0)
		medium_started = medium_started or w.s["p"][0]["move"] == "jiko_medium"
		if H.has_ev(events, "hit") and w.s["p"][0]["move"] == "jiko_medium":
			medium_hit = true
			w.step(SimC.B_H, 0)
			break
	var heavy_started := false
	for k in 32:
		w.step(0, 0)
		heavy_started = heavy_started or w.s["p"][0]["move"] == "jiko_heavy"
	t.ok(light_hit and medium_started and medium_hit and heavy_started,
			"실제 적중 중 약→중→강 3단 연계가 이어짐")

	var feint := H.mk(5, 0, 608)
	feint.debug_set_x(0, -400)
	feint.debug_set_x(1, 400)
	var origin: int = feint.s["p"][0]["x"]
	feint.step(SimC.B_T, 0)
	H.run(feint, 3)
	var retreat_x: int = feint.s["p"][0]["x"]
	H.run(feint, 7)
	var return_x: int = feint.s["p"][0]["x"]
	t.ok(retreat_x < origin and return_x > retreat_x + 35 * SimC.FP,
			"기술은 먼저 물러나고 크게 되돌아 들어옴")
