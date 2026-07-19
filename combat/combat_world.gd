class_name CombatWorld
extends RefCounted
## 60 TPS 고정 틱 전투 시뮬레이션.
##
## 결정론 규약:
##  - 상태(s)는 int / String / Array / Dictionary 만 담는다. float 금지.
##  - 같은 초기화 + 같은 입력 열 → 같은 상태 해시 (AC-02, AC-09)
##  - 렌더·사운드는 events 배열로만 내보낸다 (스냅샷 제외 대상).
##
## 틱 처리 순서 (기획서 §6):
##  입력 캡처 → 버퍼 갱신 → 상태 전이 → 이동/Pushbox → 히트박스 활성
##  → 경합 → 패리 → 가드 → 타격 → 피해/경직/넉백 → 이벤트 발행

var chars: Array = []          # [baked_p1, baked_p2] (Registry.bake 결과)
var opts: Dictionary = {}
var s: Dictionary = {}         # 시뮬 상태 전체
var events: Array = []         # 이번 틱 이벤트 (뷰/오디오 소비용)

var _seed_init: int = 1


func _init(baked_a: Dictionary, baked_b: Dictionary, rng_seed: int = 1, options: Dictionary = {}) -> void:
	chars = [baked_a, baked_b]
	opts = {
		"timer_ticks": options.get("timer_ticks", SimC.ROUND_TICKS),
		"skip_intro": options.get("skip_intro", false),
		"wins_needed": options.get("wins_needed", 2),
	}
	_seed_init = rng_seed if rng_seed != 0 else 1
	reset_match()


## 경기 전체 초기화 (훈련 리셋 = AC-07: 위치·체력·사맥·상태·타이머·난수 복원)
func reset_match() -> void:
	s = {
		"tick": 0,
		"rng": _seed_init,
		"timer": opts["timer_ticks"],
		"phase": SimC.PH_FIGHT if opts["skip_intro"] else SimC.PH_INTRO,
		"phase_t": 0,
		"round_no": 1,
		"wins": [0, 0],
		"winner": -1,
		"round_result": -1,
		"round_reason": "",
		"p": [_new_fighter(0), _new_fighter(1)],
	}
	events = []


func _new_fighter(i: int) -> Dictionary:
	var side := -1 if i == 0 else 1
	return {
		"x": SimC.START_X * side,
		"facing": -side,
		"hp": chars[i]["hp"],
		"nerve": 0,
		"energy": SimC.ENERGY_MAX,
		"energy_regen": 0,
		"state": SimC.ST_IDLE,
		"st_f": 0,
		"move": "",
		"move_conn": 0,        # 0 없음 / 1 히트 / 2 가드 / 3 패리
		"hitstop": 0,
		"stun": 0,
		"push_v": 0,
		"push_d": 0,
		"vx": 0,                # 지상 수평 속도 (가속·마찰 적용)
		"y": 0,                # 지면 위 높이 (fp, >=0)
		"vy": 0,               # 수직 속도 (fp/틱, 아래로 +)
		"jvx": 0,              # 공중 수평 속도
		"air_done": false,     # 이번 점프에서 공중 공격 소진 여부
		"cur_in": 0,
		"prev_in": 0,
		"bt": 0,               # 버퍼 시계 (히트스톱 중 정지 → 버퍼 유지, AC-06)
		"buf": {SimC.B_L: -100000, SimC.B_M: -100000, SimC.B_H: -100000,
			SimC.B_T: -100000, SimC.B_SUPER: -100000},
		"back_age": 0,
		"dirh": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
		"dirh_i": 0,
		"combo": 0,
		"scars": [],
	}


func _reset_round() -> void:
	var wins: Array = s["wins"]
	var round_no: int = s["round_no"]
	var tick: int = s["tick"]
	var rng: int = s["rng"]
	s["timer"] = opts["timer_ticks"]
	s["phase"] = SimC.PH_FIGHT if opts["skip_intro"] else SimC.PH_INTRO
	s["phase_t"] = 0
	s["round_result"] = -1
	s["round_reason"] = ""
	s["p"] = [_new_fighter(0), _new_fighter(1)]
	s["wins"] = wins
	s["round_no"] = round_no
	s["tick"] = tick
	s["rng"] = rng


# ---------------------------------------------------------------- 메인 스텝

func step(in1: int, in2: int) -> Array:
	events = []
	var ins := [in1, in2]
	var frozen := [false, false]

	# 0) 히트스톱 판정 (이번 틱 동결 여부) — 위치·타이머 정지, 입력은 계속 기록
	for i in 2:
		var p: Dictionary = s["p"][i]
		if p["hitstop"] > 0:
			frozen[i] = true
			p["hitstop"] -= 1

	# 1) 입력 캡처·버퍼 갱신
	for i in 2:
		_update_input(i, ins[i], frozen[i])

	# 2) 페이즈 진행
	match s["phase"]:
		SimC.PH_INTRO:
			s["phase_t"] += 1
			if s["phase_t"] >= SimC.INTRO_TICKS:
				s["phase"] = SimC.PH_FIGHT
				s["phase_t"] = 0
				_ev({"t": "fight_start"})
			s["tick"] += 1
			return events
		SimC.PH_ROUND_END:
			_advance_states(frozen)
			_apply_movement(frozen, false)
			s["phase_t"] += 1
			if s["phase_t"] >= SimC.ROUND_END_TICKS:
				_next_round_or_end()
			s["tick"] += 1
			return events
		SimC.PH_MATCH_END:
			s["tick"] += 1
			return events

	# --- FIGHT ---
	# 3) 타이머 (히트스톱 중 정지, AC-06)
	if not frozen[0] and not frozen[1]:
		s["timer"] -= 1

	# 4) 상태 프레임 진행 + 5) 행동 선택
	_advance_states(frozen)
	_recover_energy(frozen)
	for i in 2:
		if not frozen[i]:
			_select_action(i)

	# 6) 이동·Pushbox·벽
	_apply_movement(frozen, true)

	# 7) 얼굴 방향 갱신 (양쪽 중립일 때만)
	_update_facing()

	# 8) 판정: 경합 → (패리 → 가드 → 타격은 접촉 처리 내부 순서)
	_resolve_combat(frozen)

	# 9) 라운드 종료 판정
	_check_round_end()

	s["tick"] += 1
	return events


# ---------------------------------------------------------------- 입력

func _update_input(i: int, word: int, frozen_now: bool) -> void:
	var p: Dictionary = s["p"][i]
	p["prev_in"] = p["cur_in"]
	p["cur_in"] = word
	if not frozen_now:
		p["bt"] += 1
	# 버튼 프레스 → 버퍼 스탬프 (히트스톱 중에도 기록 = 유지)
	var pressed: int = word & ~p["prev_in"]
	for b in SimC.BTN_BITS:
		if pressed & b:
			p["buf"][b] = p["bt"]
	if not frozen_now:
		var rel := _rel_dirs(i, word)
		# 뒤 유지 시간 (정밀 방어 창 판정)
		if rel & SimC.D_BACK:
			p["back_age"] += 1
		else:
			p["back_age"] = 0
		# 방향 히스토리 (오의 커맨드)
		p["dirh"][p["dirh_i"]] = rel
		p["dirh_i"] = (p["dirh_i"] + 1) % 14


## 절대 입력 → 상대 방향 비트 (SOCD: 좌+우 = 중립)
func _rel_dirs(i: int, word: int) -> int:
	var p: Dictionary = s["p"][i]
	var l := (word & SimC.B_LEFT) != 0
	var r := (word & SimC.B_RIGHT) != 0
	var out := 0
	if l != r:
		var dir := -1 if l else 1
		if dir == p["facing"]:
			out |= SimC.D_FWD
		else:
			out |= SimC.D_BACK
	if word & SimC.B_DOWN:
		out |= SimC.D_DOWN
	return out


func _press_valid(p: Dictionary, b: int) -> bool:
	return p["bt"] - p["buf"][b] < SimC.BUFFER_TICKS


func _consume(p: Dictionary, b: int) -> void:
	p["buf"][b] = -100000


func _back_held(i: int) -> bool:
	return (_rel_dirs(i, s["p"][i]["cur_in"]) & SimC.D_BACK) != 0


func _fwd_held(i: int) -> bool:
	return (_rel_dirs(i, s["p"][i]["cur_in"]) & SimC.D_FWD) != 0


## 오의 커맨드 ↓↘→ 검사 (방향 히스토리에서 순서대로 등장)
func _motion_ok(i: int) -> bool:
	var p: Dictionary = s["p"][i]
	var seq: Array = []
	for k in 14:
		seq.append(p["dirh"][(p["dirh_i"] + k) % 14])   # 오래된 것부터
	var stage := 0
	for d in seq:
		match stage:
			0:
				if (d & SimC.D_DOWN) and not (d & SimC.D_FWD):
					stage = 1
			1:
				if (d & SimC.D_DOWN) and (d & SimC.D_FWD):
					stage = 2
			2:
				if (d & SimC.D_FWD) and not (d & SimC.D_DOWN):
					return true
	return false


# ---------------------------------------------------------------- 상태 진행

func _move_of(i: int) -> Dictionary:
	return chars[i]["moves_by_id"][s["p"][i]["move"]]


func _to_idle(p: Dictionary) -> void:
	p["state"] = SimC.ST_IDLE
	p["st_f"] = 0
	p["move"] = ""
	p["move_conn"] = 0


func _advance_states(frozen: Array) -> void:
	for i in 2:
		if frozen[i]:
			continue
		var p: Dictionary = s["p"][i]
		var o: Dictionary = s["p"][1 - i]
		match p["state"]:
			SimC.ST_ATTACK:
				p["st_f"] += 1
				var mv := _move_of(i)
				if p["st_f"] == mv["su"] + 1:
					_emit_move_active(i, mv)
				if p["st_f"] == mv["su"] + mv["act"] + 1 and p["move_conn"] == 0:
					_ev({"t": "whiff", "p": i, "kind": mv["slot"]})
				if p["st_f"] > mv["total"]:
					_to_idle(p)
			SimC.ST_HITSTUN:
				p["stun"] -= 1
				if p["stun"] <= 0:
					_to_idle(p)
					p["combo"] = 0
			SimC.ST_BLOCKSTUN, SimC.ST_RECOIL:
				p["stun"] -= 1
				if p["stun"] <= 0:
					_to_idle(p)
			SimC.ST_GRABBING:
				p["st_f"] += 1
				if p["st_f"] == SimC.GRAB_DMG_TICK and o["state"] == SimC.ST_GRABBED:
					var gmv := _move_of(i)
					var dmg: int = gmv["dmg"]
					o["hp"] = max(o["hp"] - dmg, 0)
					_ev({"t": "grab_hit", "p": i, "dmg": dmg, "x": o["x"], "y": 100 * SimC.FP})
					if o["hp"] == 0:
						o["state"] = SimC.ST_KO
						o["st_f"] = 0
						_start_push(o, 6 * SimC.FP, 20, -p["facing"])
						_to_idle(p)
				if p["st_f"] >= SimC.GRAB_CINE_TICKS and p["state"] == SimC.ST_GRABBING:
					_to_idle(p)
					if o["state"] == SimC.ST_GRABBED:
						o["state"] = SimC.ST_HITSTUN
						o["stun"] = 14
						o["st_f"] = 0
						_start_push(o, _move_of_id(i, "grab")["push_hit"], SimC.PUSH_DUR, p["facing"])
			SimC.ST_GRABBED:
				p["st_f"] += 1
			SimC.ST_KO, SimC.ST_WIN:
				p["st_f"] += 1
			SimC.ST_PREJUMP:
				p["st_f"] += 1
				if p["st_f"] >= SimC.PREJUMP:
					# 도약 발진
					p["state"] = SimC.ST_JUMP
					p["st_f"] = 0
					p["vy"] = SimC.JUMP_VY
					p["air_done"] = false
			SimC.ST_JUMP, SimC.ST_AIR_HIT:
				p["st_f"] += 1   # 착지는 _apply_movement에서 처리
			SimC.ST_LAND:
				p["st_f"] += 1
				if p["st_f"] >= SimC.LAND_RECOVERY:
					_to_idle(p)
			SimC.ST_AIR_ATTACK:
				p["st_f"] += 1
				var amv := _move_of(i)
				if p["st_f"] == amv["su"] + 1:
					_emit_move_active(i, amv)
				if p["st_f"] == amv["su"] + amv["act"] + 1 and p["move_conn"] == 0:
					_ev({"t": "whiff", "p": i, "kind": amv["slot"]})
				# 공중 공격은 착지 또는 프레임 종료로 끝난다 (착지는 _apply_movement)
				if p["st_f"] > amv["total"]:
					p["state"] = SimC.ST_JUMP
					p["st_f"] = 0
					p["move"] = ""
					p["move_conn"] = 0
			_:
				pass


## 기술 고유 이펙트가 판정과 어긋나지 않도록 활성 첫 프레임의 실제 무기 영역을 함께 보낸다.
func _emit_move_active(i: int, mv: Dictionary) -> void:
	var p: Dictionary = s["p"][i]
	_ev({"t": "move_active", "p": i, "kind": mv["slot"], "id": mv["id"],
			"x": p["x"], "y": p["y"], "facing": p["facing"],
			"rects": active_weapon_rects(i, true)})


func _move_of_id(i: int, slot: String) -> Dictionary:
	return chars[i]["moves"][slot]


## 공격 중에는 멈추고, 중립·이동·방어·피격 중에는 천천히 기력을 회복한다.
func _recover_energy(frozen: Array) -> void:
	for i in 2:
		if frozen[i]:
			continue
		var p: Dictionary = s["p"][i]
		if int(p["energy"]) >= SimC.ENERGY_MAX:
			p["energy"] = SimC.ENERGY_MAX
			p["energy_regen"] = 0
			continue
		if p["state"] in [SimC.ST_ATTACK, SimC.ST_AIR_ATTACK, SimC.ST_GRABBING]:
			p["energy_regen"] = 0
			continue
		p["energy_regen"] += 1
		if int(p["energy_regen"]) >= SimC.ENERGY_REGEN_TICKS:
			p["energy"] += 1
			p["energy_regen"] = 0


# ---------------------------------------------------------------- 행동 선택

func _select_action(i: int) -> void:
	var p: Dictionary = s["p"][i]
	var o: Dictionary = s["p"][1 - i]

	if p["state"] == SimC.ST_ATTACK:
		var mv := _move_of(i)
		# 사맥 1칸: 자세 취소 (후딜 중 뒤 + 기술 버튼)
		if p["st_f"] > mv["su"] + mv["act"] and p["nerve"] >= 1 \
				and _back_held(i) and _press_valid(p, SimC.B_T):
			_consume(p, SimC.B_T)
			p["nerve"] -= 1
			_to_idle(p)
			_ev({"t": "nerve_cancel", "p": i})
			return
		# 캔슬 윈도우
		for cw in mv["cancels"]:
			if p["st_f"] < int(cw["from"]) or p["st_f"] > int(cw["to"]):
				continue
			if not _conn_matches(p["move_conn"], cw["on"]):
				continue
			for tid in cw["targets"]:
				var tmv: Dictionary = chars[i]["moves_by_id"].get(tid, {})
				if tmv.is_empty():
					continue
				var btn: int = Registry.SLOT_BUTTON.get(tmv["slot"], 0)
				if btn != 0 and _press_valid(p, btn):
					_consume(p, btn)
					_start_move(i, tmv)
					return
		return

	# 공중 공격 (점프당 1회) — 아무 공격 버튼이나 공중기로 발동
	if p["state"] == SimC.ST_JUMP and not p["air_done"]:
		var abest := -100000
		var abtn := 0
		for b in [SimC.B_H, SimC.B_M, SimC.B_L, SimC.B_T]:
			if _press_valid(p, b) and p["buf"][b] > abest:
				abest = p["buf"][b]
				abtn = b
		if abtn != 0:
			var am: Dictionary = chars[i]["moves"].get("air", {})
			if not am.is_empty():
				_consume(p, abtn)
				p["air_done"] = true
				p["state"] = SimC.ST_AIR_ATTACK
				p["st_f"] = 1
				p["move"] = am["id"]
				p["move_conn"] = 0
				_ev({"t": "move_start", "p": i, "kind": "air", "id": am["id"]})
		return

	if p["state"] != SimC.ST_IDLE and p["state"] != SimC.ST_WALK_F and p["state"] != SimC.ST_WALK_B:
		return

	# 점프: ↑ 눌림 (전/후/중립 점프)
	if (p["cur_in"] & SimC.B_UP) and not (p["prev_in"] & SimC.B_UP):
		p["state"] = SimC.ST_PREJUMP
		p["st_f"] = 0
		var rel0 := _rel_dirs(i, p["cur_in"])
		if rel0 & SimC.D_FWD:
			p["jvx"] = maxi(absi(p["vx"]), SimC.JUMP_VX_F) * p["facing"]
		elif rel0 & SimC.D_BACK:
			p["jvx"] = -maxi(absi(p["vx"]), SimC.JUMP_VX_B) * p["facing"]
		else:
			p["jvx"] = p["vx"]
		_ev({"t": "jump", "p": i})
		return

	# 오의: 사맥 3칸 + 전용키. 기존 ↓↘→+강+기술 커맨드도 계속 지원한다.
	var sup: Dictionary = chars[i]["moves"].get("super", {})
	var super_shortcut: bool = _press_valid(p, SimC.B_SUPER)
	var super_legacy: bool = _press_valid(p, SimC.B_H) and _press_valid(p, SimC.B_T) \
			and absi(p["buf"][SimC.B_H] - p["buf"][SimC.B_T]) <= 4 and _motion_ok(i)
	if not sup.is_empty() and p["nerve"] >= sup["meter_cost"] \
			and (super_shortcut or super_legacy):
		if super_shortcut:
			_consume(p, SimC.B_SUPER)
		else:
			_consume(p, SimC.B_H)
			_consume(p, SimC.B_T)
		p["nerve"] -= sup["meter_cost"]
		_start_move(i, sup)
		_ev({"t": "super", "p": i})
		return

	# 무진 파도 연계: ↓↘→+약/중/강. 사맥 3에서 강은 1칸을 써서 강화한다.
	if chars[i]["id"] == "mujin" and _motion_ok(i):
		var motion_btn := 0
		var motion_key := ""
		for pair in [[SimC.B_H, "motion_heavy"], [SimC.B_M, "motion_medium"],
				[SimC.B_L, "motion_light"]]:
			if _press_valid(p, int(pair[0])):
				motion_btn = int(pair[0])
				motion_key = String(pair[1])
				break
		if motion_btn != 0:
			var nerve_move: Dictionary = chars[i]["moves"].get("motion_nerve", {})
			var nerve_art: bool = motion_key == "motion_heavy" \
					and int(p["nerve"]) >= SimC.NERVE_MAX \
					and int(p["energy"]) >= int(nerve_move.get("energy_cost", 0))
			if nerve_art:
				motion_key = "motion_nerve"
			var motion_move: Dictionary = chars[i]["moves"].get(motion_key, {})
			if not motion_move.is_empty():
				_consume(p, motion_btn)
				var started: bool = _start_move(i, motion_move)
				if started and nerve_art:
					p["nerve"] -= 1
				if started and nerve_art:
					_ev({"t": "nerve_art", "p": i, "x": p["x"], "y": 90 * SimC.FP})
				if not started:
					var base_slot: String = Registry.EXTRA_SLOT_KIND.get(motion_key, "light")
					_start_move(i, chars[i]["moves"].get(base_slot, {}))
				return

	# 잡기: 전방 유지 + 중베기 + 근접
	var grab: Dictionary = chars[i]["moves"].get("grab", {})
	if not grab.is_empty() and _fwd_held(i) and _press_valid(p, SimC.B_M) \
			and absi(p["x"] - o["x"]) <= grab["grab_range"]:
		_consume(p, SimC.B_M)
		if not _start_move(i, grab):
			_start_move(i, chars[i]["moves"].get("medium", {}))
		return

	# 일반기: 가장 최근에 누른 버튼 (동시엔 강 > 중 > 약 > 기술)
	var best_btn := 0
	var best_t := -100000
	for b in [SimC.B_H, SimC.B_M, SimC.B_L, SimC.B_T]:
		if _press_valid(p, b) and p["buf"][b] > best_t:
			best_t = p["buf"][b]
			best_btn = b
	if best_btn != 0:
		var slot := ""
		for k in Registry.SLOT_BUTTON:
			if Registry.SLOT_BUTTON[k] == best_btn:
				slot = k
		var m: Dictionary = chars[i]["moves"].get(slot, {})
		if not m.is_empty():
			_consume(p, best_btn)
			if not _start_move(i, m) and slot == "tech":
				_start_move(i, chars[i]["moves"].get("light", {}))
			return

	# 이동 자세
	var rel := _rel_dirs(i, p["cur_in"])
	if rel & SimC.D_FWD:
		p["state"] = SimC.ST_WALK_F
	elif rel & SimC.D_BACK:
		p["state"] = SimC.ST_WALK_B
	else:
		p["state"] = SimC.ST_IDLE
	p["st_f"] = 0


func _conn_matches(conn: int, on: Array) -> bool:
	if conn == 1 and on.has("hit"):
		return true
	if conn == 2 and on.has("block"):
		return true
	if conn == 0 and on.has("whiff"):
		return true
	return false


func _start_move(i: int, mv: Dictionary) -> bool:
	if mv.is_empty():
		return false
	var p: Dictionary = s["p"][i]
	var cost: int = int(mv.get("energy_cost", 0))
	if int(p["energy"]) < cost:
		_ev({"t": "energy_empty", "p": i, "need": cost, "energy": p["energy"]})
		return false
	p["energy"] -= cost
	p["energy_regen"] = 0
	p["state"] = SimC.ST_ATTACK
	p["st_f"] = 1
	p["move"] = mv["id"]
	p["move_conn"] = 0
	_ev({"t": "move_start", "p": i, "kind": mv["slot"], "id": mv["id"]})
	return true


# ---------------------------------------------------------------- 이동

func _start_push(p: Dictionary, total_fp: int, dur: int, dir: int) -> void:
	p["push_v"] = (total_fp / dur) * dir
	p["push_d"] = dur


func _apply_movement(frozen: Array, allow_walk: bool) -> void:
	for i in 2:
		if frozen[i]:
			continue
		var p: Dictionary = s["p"][i]
		var o: Dictionary = s["p"][1 - i]
		var vel := 0
		var airborne := _is_air(p)
		if airborne:
			vel = p["jvx"]
			# 중력 적분 (y=높이 양수 위, vy 양수 상승)
			p["vy"] -= SimC.GRAVITY
			p["y"] += p["vy"]
			if p["y"] > SimC.MAX_AIR_H:      # 천장
				p["y"] = SimC.MAX_AIR_H
				if p["vy"] > 0:
					p["vy"] = 0
			if p["y"] <= 0 and p["vy"] < 0:
				# 착지
				p["y"] = 0
				p["vy"] = 0
				p["vx"] = p["jvx"]
				p["jvx"] = 0
				if p["state"] == SimC.ST_AIR_HIT:
					p["combo"] = 0
				p["state"] = SimC.ST_LAND
				p["st_f"] = 0
				_ev({"t": "land", "p": i, "x": p["x"]})
		else:
			var target_v := 0
			if allow_walk and p["state"] == SimC.ST_WALK_F:
				target_v = chars[i]["walk_f"] * p["facing"]
			elif allow_walk and p["state"] == SimC.ST_WALK_B:
				target_v = -chars[i]["walk_b"] * p["facing"]
			p["vx"] = _approach_int(p["vx"], target_v,
				SimC.GROUND_ACCEL if target_v != 0 else SimC.GROUND_FRICTION)
			vel = p["vx"]
			if allow_walk and p["state"] == SimC.ST_ATTACK:
				var mv := _move_of(i)
				for m in mv["motion"]:
					if p["st_f"] >= int(m[0]) and p["st_f"] <= int(m[1]):
						vel += int(m[2]) * p["facing"]
		var pushed := false
		if p["push_d"] > 0:
			vel += p["push_v"]
			p["push_d"] -= 1
			pushed = true
		if vel == 0:
			continue
		var hw: int = chars[i]["push_hw"]
		var intended: int = p["x"] + vel
		var clamped: int = clampi(intended, -SimC.STAGE_HALF + hw, SimC.STAGE_HALF - hw)
		p["x"] = clamped
		if clamped != intended and signi(p["vx"]) == signi(vel):
			p["vx"] = 0
		# 벽에 밀린 넉백은 상대(공격자)에게 반작용으로 전달 (지상끼리만)
		var leftover := intended - clamped
		if leftover != 0 and pushed and not airborne and not _is_air(o):
			var ohw: int = chars[1 - i]["push_hw"]
			o["x"] = clampi(o["x"] - leftover, -SimC.STAGE_HALF + ohw, SimC.STAGE_HALF - ohw)

	_separate_pushboxes(frozen)


func _approach_int(value: int, target: int, amount: int) -> int:
	if value < target:
		return mini(value + amount, target)
	if value > target:
		return maxi(value - amount, target)
	return value


func _is_air(p: Dictionary) -> bool:
	var st: int = p["state"]
	return st == SimC.ST_JUMP or st == SimC.ST_AIR_ATTACK or st == SimC.ST_AIR_HIT


func _separate_pushboxes(frozen: Array) -> void:
	if s["p"][0]["state"] == SimC.ST_GRABBED or s["p"][1]["state"] == SimC.ST_GRABBED:
		return   # 잡기 연출 중 겹침 허용
	if _is_air(s["p"][0]) or _is_air(s["p"][1]):
		return   # 공중이면 겹침 허용 (넘어가기/크로스업)
	var hw_sum: int = chars[0]["push_hw"] + chars[1]["push_hw"]
	# 왼쪽/오른쪽 인덱스 결정 (동일 x면 P1의 방향으로 결정 — 결정론 유지)
	var li := 0
	if s["p"][0]["x"] > s["p"][1]["x"]:
		li = 1
	elif s["p"][0]["x"] == s["p"][1]["x"] and s["p"][0]["facing"] == 1:
		li = 0
	var ri := 1 - li
	var L: Dictionary = s["p"][li]
	var R: Dictionary = s["p"][ri]
	var over: int = hw_sum - (R["x"] - L["x"])
	if over <= 0:
		return
	if frozen[li] and frozen[ri]:
		return
	elif frozen[li]:
		R["x"] += over
	elif frozen[ri]:
		L["x"] -= over
	else:
		var half: int = over / 2
		L["x"] -= half
		R["x"] += over - half
	for i in 2:
		var hw: int = chars[i]["push_hw"]
		s["p"][i]["x"] = clampi(s["p"][i]["x"], -SimC.STAGE_HALF + hw, SimC.STAGE_HALF - hw)
	# 벽 끼임: 한쪽이 벽에 붙었으면 반대쪽이 물러남
	over = hw_sum - (R["x"] - L["x"])
	if over > 0:
		if L["x"] <= -SimC.STAGE_HALF + chars[li]["push_hw"]:
			R["x"] = clampi(R["x"] + over, -SimC.STAGE_HALF + chars[ri]["push_hw"], SimC.STAGE_HALF - chars[ri]["push_hw"])
		elif R["x"] >= SimC.STAGE_HALF - chars[ri]["push_hw"]:
			L["x"] = clampi(L["x"] - over, -SimC.STAGE_HALF + chars[li]["push_hw"], SimC.STAGE_HALF - chars[li]["push_hw"])


func _update_facing() -> void:
	var neutral := [SimC.ST_IDLE, SimC.ST_WALK_F, SimC.ST_WALK_B]
	var a: Dictionary = s["p"][0]
	var b: Dictionary = s["p"][1]
	if neutral.has(a["state"]) and neutral.has(b["state"]):
		if a["x"] < b["x"]:
			a["facing"] = 1
			b["facing"] = -1
		elif a["x"] > b["x"]:
			a["facing"] = -1
			b["facing"] = 1


# ---------------------------------------------------------------- 판정

## 현재 틱 활성 무기 박스 (fp rect 배열). full=true면 연결 여부 무시(뷰 표시용).
func active_weapon_rects(i: int, include_connected: bool = false) -> Array:
	var p: Dictionary = s["p"][i]
	if p["state"] != SimC.ST_ATTACK and p["state"] != SimC.ST_AIR_ATTACK:
		return []
	if not include_connected and p["move_conn"] != 0:
		return []
	var mv := _move_of(i)
	var out: Array = []
	for bx in mv["boxes"]:
		if p["st_f"] < int(bx[0]) or p["st_f"] > int(bx[1]):
			continue
		out.append(_box_to_rect(p, int(bx[2]), int(bx[3]), int(bx[4]), int(bx[5])))
	return out


func _box_to_rect(p: Dictionary, x: int, y: int, w: int, h: int) -> Array:
	var fx := x * SimC.FP
	var fw := w * SimC.FP
	var ay: int = p["y"]           # 공중 높이 오프셋
	if p["facing"] == 1:
		return [p["x"] + fx, y * SimC.FP + ay, p["x"] + fx + fw, (y + h) * SimC.FP + ay]
	return [p["x"] - fx - fw, y * SimC.FP + ay, p["x"] - fx, (y + h) * SimC.FP + ay]


func hurt_rect(i: int) -> Array:
	var p: Dictionary = s["p"][i]
	var ay: int = p["y"]
	return [p["x"] - chars[i]["hurt_hw"], ay, p["x"] + chars[i]["hurt_hw"], chars[i]["hurt_h"] + ay]


func push_rect(i: int) -> Array:
	var p: Dictionary = s["p"][i]
	var ay: int = p["y"]
	return [p["x"] - chars[i]["push_hw"], ay, p["x"] + chars[i]["push_hw"], chars[i]["hurt_h"] + ay]


## rect를 [칼결(끝 20%) rect, 몸통 rect]로 분할
func _split_edge(i: int, rect: Array) -> Array:
	var p: Dictionary = s["p"][i]
	var w: int = rect[2] - rect[0]
	var ew: int = w * chars[i]["edge_pct"] / 100
	if p["facing"] == 1:
		return [[rect[2] - ew, rect[1], rect[2], rect[3]], [rect[0], rect[1], rect[2] - ew, rect[3]]]
	return [[rect[0], rect[1], rect[0] + ew, rect[3]], [rect[0] + ew, rect[1], rect[2], rect[3]]]


func _resolve_combat(frozen: Array) -> void:
	var boxes := [[], []]
	for i in 2:
		if not frozen[i]:
			boxes[i] = active_weapon_rects(i)

	# --- 경합 (양쪽 무기 하틳이 같은 틱에 교차) ---
	if not boxes[0].is_empty() and not boxes[1].is_empty():
		var mva := _move_of(0)
		var mvb := _move_of(1)
		if not mva["grab"] and not mvb["grab"]:
			var crossed := false
			for ra in boxes[0]:
				for rb in boxes[1]:
					if SimC.rect_overlap(ra, rb):
						crossed = true
			if crossed:
				var pa: int = mva["prio"]
				var pb: int = mvb["prio"]
				var mid_x: int = (s["p"][0]["x"] + s["p"][1]["x"]) / 2
				if pa == pb:
					for i in 2:
						var p: Dictionary = s["p"][i]
						p["state"] = SimC.ST_RECOIL
						p["stun"] = SimC.CLASH_RECOIL
						p["st_f"] = 0
						p["move"] = ""
						p["hitstop"] = 9
						_start_push(p, 45 * SimC.FP, SimC.PUSH_DUR, -p["facing"])
					_ev({"t": "clash", "x": mid_x, "y": 110 * SimC.FP})
					return
				var loser := 0 if pa < pb else 1
				var lp: Dictionary = s["p"][loser]
				lp["state"] = SimC.ST_RECOIL
				lp["stun"] = SimC.BEATEN_RECOIL
				lp["st_f"] = 0
				lp["move"] = ""
				lp["hitstop"] = 7
				_start_push(lp, 30 * SimC.FP, SimC.PUSH_DUR, -lp["facing"])
				_ev({"t": "beaten", "p": loser, "x": mid_x, "y": 110 * SimC.FP})
				boxes[loser] = []

	# --- 접촉 수집 (동시 히트 = 상쇄 트레이드 지원) ---
	var contacts: Array = []
	for i in 2:
		if boxes[i].is_empty():
			continue
		var hr := hurt_rect(1 - i)
		var d: Dictionary = s["p"][1 - i]
		if d["state"] == SimC.ST_KO or d["state"] == SimC.ST_GRABBED:
			continue
		var any_edge := false
		var any_flat := false
		var cx := 0
		for r in boxes[i]:
			if not SimC.rect_overlap(r, hr):
				continue
			var parts := _split_edge(i, r)
			if SimC.rect_overlap(parts[0], hr):
				any_edge = true
			if SimC.rect_overlap(parts[1], hr):
				any_flat = true
			cx = clampi(d["x"] - chars[1 - i]["hurt_hw"] * s["p"][i]["facing"], mini(r[0], hr[0]), maxi(r[2], hr[2]))
		if any_edge or any_flat:
			var mv := _move_of(i)
			var clean: bool = mv["edge"] and any_edge and not any_flat
			contacts.append({"atk": i, "clean": clean, "x": cx, "mv": mv})

	# 잡기 vs 잡기 동시 → 잡기 풀림
	if contacts.size() == 2 and contacts[0]["mv"]["grab"] and contacts[1]["mv"]["grab"]:
		for i in 2:
			var p: Dictionary = s["p"][i]
			p["state"] = SimC.ST_RECOIL
			p["stun"] = 12
			p["st_f"] = 0
			p["move"] = ""
			_start_push(p, 50 * SimC.FP, SimC.PUSH_DUR, -p["facing"])
		_ev({"t": "grab_break", "x": (s["p"][0]["x"] + s["p"][1]["x"]) / 2, "y": 100 * SimC.FP})
		return

	for c in contacts:
		_apply_contact(c["atk"], c["clean"], c["x"], c["mv"])


func _apply_contact(i: int, clean: bool, cx: int, mv: Dictionary) -> void:
	var p: Dictionary = s["p"][i]
	var d: Dictionary = s["p"][1 - i]
	var cy := 110 * SimC.FP
	# 동시 접촉(트레이드)으로 이미 상태가 바뀐 경우 방어
	if d["state"] == SimC.ST_KO or d["state"] == SimC.ST_GRABBED:
		return

	# --- 잡기 ---
	if mv["grab"]:
		if p["state"] != SimC.ST_ATTACK:
			return
		var grabbable := [SimC.ST_IDLE, SimC.ST_WALK_F, SimC.ST_WALK_B, SimC.ST_ATTACK, SimC.ST_RECOIL]
		if not grabbable.has(d["state"]):
			return
		p["move_conn"] = 1
		p["state"] = SimC.ST_GRABBING
		p["st_f"] = 0
		d["state"] = SimC.ST_GRABBED
		d["st_f"] = 0
		d["move"] = ""
		d["x"] = clampi(p["x"] + p["facing"] * 70 * SimC.FP,
				-SimC.STAGE_HALF + chars[1 - i]["push_hw"], SimC.STAGE_HALF - chars[1 - i]["push_hw"])
		_ev({"t": "grab", "p": i, "x": d["x"], "y": cy})
		return

	# --- 가드 판정 ---
	var guardable: bool = (d["state"] == SimC.ST_IDLE or d["state"] == SimC.ST_WALK_B
			or d["state"] == SimC.ST_BLOCKSTUN)
	if guardable and _back_held(1 - i) and not mv["unblockable"]:
		if d["back_age"] >= 1 and d["back_age"] <= SimC.PARRY_WINDOW:
			# 정밀 방어: 칩 0, 방어자 사맥 +1, 공격자 크게 밀림 (AC-05 순서: 경합→패리→가드→타격)
			p["move_conn"] = 3
			d["state"] = SimC.ST_BLOCKSTUN
			d["stun"] = SimC.PARRY_STUN_DEF
			d["st_f"] = 0
			d["hitstop"] = SimC.PARRY_STOP_DEF
			p["hitstop"] = SimC.PARRY_STOP_ATK
			_start_push(p, SimC.PARRY_PUSH_ATK, SimC.PUSH_DUR, -p["facing"])
			_gain_nerve(1 - i, "parry")
			_ev({"t": "parry", "p": 1 - i, "x": cx, "y": cy,
				"adv": _adv_calc(i, mv, SimC.PARRY_STUN_DEF, SimC.PARRY_STOP_DEF, SimC.PARRY_STOP_ATK)})
			return
		# 일반 가드: 칩 피해 (칩으로는 죽지 않음)
		p["move_conn"] = 2
		d["hp"] = maxi(d["hp"] - mv["chip"], 1)
		d["state"] = SimC.ST_BLOCKSTUN
		d["stun"] = mv["blockstun"]
		d["st_f"] = 0
		d["hitstop"] = mv["stop"]
		p["hitstop"] = mv["stop"]
		_start_push(d, mv["push_block"], SimC.PUSH_DUR, p["facing"])
		_ev({"t": "block", "p": i, "kind": mv["slot"], "chip": mv["chip"], "x": cx, "y": cy,
			"adv": _adv_calc(i, mv, mv["blockstun"], mv["stop"], mv["stop"])})
		return

	# --- 타격 ---
	var in_combo: bool = d["state"] == SimC.ST_HITSTUN or d["state"] == SimC.ST_AIR_HIT
	var combo: int = d["combo"] + 1 if in_combo else 1
	d["combo"] = combo
	var scale: int = SimC.COMBO_SCALE[mini(combo - 1, SimC.COMBO_SCALE.size() - 1)]
	var base: int = mv["dmg_edge"] if clean else mv["dmg"]
	var dmg: int = maxi(base * scale / 100, 1)

	# 휘두르기 처벌 (상대 후딜/반동 중 타격) → 사맥 +1
	var punish := false
	if d["state"] == SimC.ST_RECOIL:
		punish = true
	elif d["state"] == SimC.ST_ATTACK or d["state"] == SimC.ST_AIR_ATTACK:
		var dmv := _move_of(1 - i)
		if d["st_f"] > dmv["su"] + dmv["act"]:
			punish = true

	var d_air := _is_air(d)
	d["hp"] = maxi(d["hp"] - dmg, 0)
	d["st_f"] = 0
	d["move"] = ""
	var stop: int = mv["stop_edge"] if clean else mv["stop"]
	d["hitstop"] = stop
	p["hitstop"] = stop
	var cyy := cy
	if d_air:
		# 공중 피격 → 저글 (떠오름)
		d["state"] = SimC.ST_AIR_HIT
		d["vy"] = SimC.AIR_HIT_POP
		d["jvx"] = p["facing"] * 3000
		if d["y"] <= 0:
			d["y"] = 1
		cyy = cy + d["y"]
	else:
		d["state"] = SimC.ST_HITSTUN
		d["stun"] = mv["hitstun"]
		_start_push(d, mv["push_hit"], SimC.PUSH_DUR, p["facing"])
	p["move_conn"] = 1

	if clean:
		_gain_nerve(i, "edge")
		_add_scar(1 - i)
	if punish:
		_gain_nerve(i, "punish")

	_ev({"t": "hit", "p": i, "kind": mv["slot"], "dmg": dmg, "edge": clean,
		"combo": combo, "punish": punish, "air": d_air, "x": cx, "y": cyy,
		"adv": _adv_calc(i, mv, mv["hitstun"], stop, stop)})

	if d["hp"] == 0:
		d["state"] = SimC.ST_KO
		d["st_f"] = 0
		d["move"] = ""
		d["y"] = 0
		d["vy"] = 0
		_start_push(d, 120 * SimC.FP, 20, p["facing"])
		_ev({"t": "ko", "p": 1 - i, "x": cx, "y": cy})


## 프레임 이득 계산 (훈련 표시용): 방어자 해방 틱 - 공격자 해방 틱
func _adv_calc(atk_i: int, mv: Dictionary, stun: int, stop_def: int, stop_atk: int) -> int:
	var p: Dictionary = s["p"][atk_i]
	var atk_free: int = stop_atk + (mv["total"] - p["st_f"])
	var def_free: int = stop_def + stun
	return def_free - atk_free


func _gain_nerve(i: int, why: String) -> void:
	var p: Dictionary = s["p"][i]
	if p["nerve"] < SimC.NERVE_MAX:
		p["nerve"] += 1
		_ev({"t": "nerve_gain", "p": i, "why": why, "nerve": p["nerve"]})


func _add_scar(i: int) -> void:
	var p: Dictionary = s["p"][i]
	if p["scars"].size() >= 12:
		return
	var r := SimC.rng_next(s["rng"], 1000)
	s["rng"] = r[0]
	var r2 := SimC.rng_next(s["rng"], 1000)
	s["rng"] = r2[0]
	var r3 := SimC.rng_next(s["rng"], 120)
	s["rng"] = r3[0]
	p["scars"].append([int(r[1]) % 60 - 30, 30 + int(r2[1]) % 110, int(r3[1]) - 60])


# ---------------------------------------------------------------- 라운드/경기

func _check_round_end() -> void:
	if s["phase"] != SimC.PH_FIGHT:
		return
	var a: Dictionary = s["p"][0]
	var b: Dictionary = s["p"][1]
	var k0: bool = a["hp"] <= 0
	var k1: bool = b["hp"] <= 0
	var result := -1
	var reason := ""
	if k0 and k1:
		result = 2
		reason = "double_ko"
	elif k0 or k1:
		result = 0 if k1 else 1
		reason = "ko"
	elif s["timer"] <= 0:
		reason = "time"
		if a["hp"] > b["hp"]:
			result = 0
		elif b["hp"] > a["hp"]:
			result = 1
		else:
			result = 2
	else:
		return
	s["round_result"] = result
	s["round_reason"] = reason
	if result == 0 or result == 1:
		s["wins"][result] += 1
		var w: Dictionary = s["p"][result]
		if w["state"] != SimC.ST_KO:
			w["state"] = SimC.ST_WIN
			w["st_f"] = 0
			w["move"] = ""
		var l: Dictionary = s["p"][1 - result]
		if reason == "time" and l["state"] != SimC.ST_KO:
			l["state"] = SimC.ST_IDLE
			l["move"] = ""
	s["phase"] = SimC.PH_ROUND_END
	s["phase_t"] = 0
	_ev({"t": "round_end", "result": result, "reason": reason, "wins": [s["wins"][0], s["wins"][1]]})


func _next_round_or_end() -> void:
	var need: int = opts["wins_needed"]
	if s["wins"][0] >= need or s["wins"][1] >= need or s["round_no"] >= SimC.MAX_ROUNDS:
		s["phase"] = SimC.PH_MATCH_END
		s["phase_t"] = 0
		if s["wins"][0] > s["wins"][1]:
			s["winner"] = 0
		elif s["wins"][1] > s["wins"][0]:
			s["winner"] = 1
		else:
			s["winner"] = 2
		_ev({"t": "match_end", "winner": s["winner"]})
	else:
		s["round_no"] += 1
		_reset_round()
		_ev({"t": "round_start", "round": s["round_no"]})


# ---------------------------------------------------------------- 스냅샷/해시

func snapshot() -> Dictionary:
	return s.duplicate(true)


func restore(snap: Dictionary) -> void:
	s = snap.duplicate(true)


## 상태 전체를 순서 고정 배열로 직렬화 → 해시 (AC-09)
func canonical_array() -> Array:
	var out: Array = [s["tick"], s["rng"], s["timer"], s["phase"], s["phase_t"],
		s["round_no"], s["wins"][0], s["wins"][1], s["winner"], s["round_result"]]
	for i in 2:
		var p: Dictionary = s["p"][i]
		out.append_array([p["x"], p["facing"], p["hp"], p["nerve"], p["energy"],
			p["energy_regen"], p["state"], p["st_f"],
			p["move"], p["move_conn"], p["hitstop"], p["stun"], p["push_v"], p["push_d"],
			p["cur_in"], p["prev_in"], p["bt"], p["back_age"], p["dirh_i"], p["combo"],
			p["vx"], p["y"], p["vy"], p["jvx"], 1 if p["air_done"] else 0])
		for b in SimC.BTN_BITS:
			out.append(p["buf"][b])
		out.append_array(p["dirh"])
		for sc in p["scars"]:
			out.append_array(sc)
	return out


func state_hash() -> int:
	return SimC.fnv32(var_to_bytes(canonical_array()))


# ---------------------------------------------------------------- 디버그/뷰 지원

## 테스트 전용 배치 헬퍼 (px 단위)
func debug_set_x(i: int, px: int) -> void:
	s["p"][i]["x"] = px * SimC.FP


func debug_set_nerve(i: int, n: int) -> void:
	s["p"][i]["nerve"] = clampi(n, 0, SimC.NERVE_MAX)


func debug_set_energy(i: int, value: int) -> void:
	s["p"][i]["energy"] = clampi(value, 0, SimC.ENERGY_MAX)
	s["p"][i]["energy_regen"] = 0


func debug_set_hp(i: int, hp: int) -> void:
	s["p"][i]["hp"] = hp


func debug_boxes(i: int) -> Dictionary:
	var weapon := active_weapon_rects(i, true)
	var edges: Array = []
	for r in weapon:
		edges.append(_split_edge(i, r)[0])
	return {"hurt": hurt_rect(i), "push": push_rect(i), "weapon": weapon, "edge": edges}


func state_name(i: int) -> String:
	return SimC.ST_NAMES.get(s["p"][i]["state"], "?")


func move_phase(i: int) -> String:
	var p: Dictionary = s["p"][i]
	if p["state"] != SimC.ST_ATTACK and p["state"] != SimC.ST_AIR_ATTACK:
		return ""
	var mv := _move_of(i)
	if p["st_f"] <= mv["su"]:
		return "startup"
	if p["st_f"] <= mv["su"] + mv["act"]:
		return "active"
	return "recovery"


func _ev(e: Dictionary) -> void:
	e["tick"] = s["tick"]
	events.append(e)
