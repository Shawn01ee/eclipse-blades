class_name CpuBrain
extends RefCounted
## 읽기 쉬운 Utility CPU (기획서 §7).
## - 관찰: 거리, 상대 상태(공개 정보), 체력, 사맥
## - 난이도는 반응 지연·오차·후보 빈도·확정 상황 대응을 바꾼다
## - 플레이어 "입력"을 읽지 않는다: 화면에 보이는 상태(발동 모션)에만 지연 반응
## - 자체 시드 난수만 사용 → 같은 시드·같은 상태 = 같은 행동 (결정론 유지)

const MAX_LEVEL := 6
const CADENCE := [16, 12, 8, 4, 2, 1]          # 난이도별 재판단 주기
const REACT_DELAY := [14, 10, 7, 4, 2, 1]      # 보이는 공격 모션을 확인할 프레임
const BLOCK_PROB := [15, 35, 60, 88, 95, 99]   # 공격 목격 시 가드 확률(%)
const ERR_PROB := [35, 22, 12, 4, 1, 0]        # 무작위 행동 확률(%)
const ANTI_AIR_PROB := [35, 45, 55, 76, 90, 98]
const AIR_ATTACK_PROB := [25, 32, 40, 60, 76, 90]
const SUPER_PROB := [22, 28, 35, 55, 72, 88]
const HAN_CHAIN_PROB := [25, 35, 45, 72, 88, 98]
const ARIN_CHAIN_PROB := [20, 28, 35, 72, 88, 98]
const ActionLibrary := preload("res://ai/cpu_action_library.gd")

var pi: int
var level: int
var rng: int
var plan: Array = []       # 예약된 입력 워드 큐 (오의 커맨드 등)
var hold_dir := 0          # -1 후퇴 / 0 정지 / 1 접근
var cool := 0
var block_ticks := 0
var react_delay := 0

var _reach := {}           # slot → px


func _init(player_index: int, difficulty: int, rng_seed: int) -> void:
	pi = player_index
	level = clampi(difficulty, 1, MAX_LEVEL)
	rng = maxi(rng_seed, 1)
	react_delay = REACT_DELAY[level - 1]


func _roll(bound: int) -> int:
	var r := SimC.rng_next(rng, bound)
	rng = r[0]
	return r[1]


func _dir_word(rel: int, facing: int) -> int:
	return ActionLibrary.direction_word(rel, facing)


func _start_action(action: int, facing: int) -> int:
	plan = ActionLibrary.frames(action, facing)
	return plan.pop_front() if not plan.is_empty() else 0


func _reach_of(w: CombatWorld, slot: String) -> int:
	if _reach.has(slot):
		return _reach[slot]
	var mv: Dictionary = w.chars[pi]["moves"].get(slot, {})
	var best := 0
	if not mv.is_empty():
		for b in mv["boxes"]:
			best = maxi(best, int(b[2]) + int(b[4]))
	_reach[slot] = best
	return best


func _can_use_slot(w: CombatWorld, me: Dictionary, slot: String) -> bool:
	var mv: Dictionary = w.chars[pi]["moves"].get(slot, {})
	return not mv.is_empty() and int(me["energy"]) >= int(mv.get("energy_cost", 0))


func think(w: CombatWorld) -> int:
	var me: Dictionary = w.s["p"][pi]
	var op: Dictionary = w.s["p"][1 - pi]
	var facing: int = me["facing"]

	if not plan.is_empty():
		return plan.pop_front()

	# 캐릭터별 중공격 후속 선택. 플레이어와 같은 캔슬 창·접촉 결과만 사용한다.
	if me["state"] == SimC.ST_ATTACK and me["move_conn"] > 0:
		var current: Dictionary = w.chars[pi]["moves_by_id"].get(me["move"], {})
		if not current.is_empty() and not current["cancels"].is_empty():
			for cw in current["cancels"]:
				if me["st_f"] < int(cw["from"]) or me["st_f"] > int(cw["to"]):
					continue
				var on_block: bool = me["move_conn"] == 2 and cw["on"].has("block")
				var on_hit: bool = me["move_conn"] == 1 and cw["on"].has("hit")
				if not on_block and not on_hit:
					continue
				var targets: Array = cw["targets"]
				if w.chars[pi]["id"] == "han" and targets.has("han_tech") \
						and _roll(100) < HAN_CHAIN_PROB[level - 1]:
					return SimC.B_T
				if w.chars[pi]["id"] == "arin" \
						and _roll(100) >= ARIN_CHAIN_PROB[level - 1]:
					return 0
				if not targets.is_empty():
					var follow: Dictionary = w.chars[pi]["moves_by_id"].get(targets[0], {})
					if int(me["energy"]) >= int(follow.get("energy_cost", 0)):
						return Registry.SLOT_BUTTON.get(follow.get("slot", ""), 0)

	# 공중: 접근했으면 공중 공격 1회
	if me["state"] == SimC.ST_JUMP and not me["air_done"]:
		var agap: int = absi(me["x"] - op["x"]) / SimC.FP
		if me["y"] < 130 * SimC.FP and agap < 130 \
				and _roll(100) < AIR_ATTACK_PROB[level - 1]:
			return SimC.B_M
		return 0

	var busy: bool = me["state"] != SimC.ST_IDLE and me["state"] != SimC.ST_WALK_F \
			and me["state"] != SimC.ST_WALK_B
	if busy:
		return 0

	# 상대 공중 → 대공(강베기)
	if (op["state"] == SimC.ST_JUMP or op["state"] == SimC.ST_AIR_ATTACK) \
			and absi(me["x"] - op["x"]) / SimC.FP < 145 \
			and _roll(100) < ANTI_AIR_PROB[level - 1]:
		return _start_action(ActionLibrary.Action.HEAVY, facing)

	# 상대 공격 목격 → 지연 후 가드 (반응 지연 = 발동 프레임 경과로 근사)
	if op["state"] == SimC.ST_ATTACK and block_ticks <= 0:
		var omv: Dictionary = w.chars[1 - pi]["moves_by_id"].get(op["move"], {})
		if not omv.is_empty() and op["st_f"] >= react_delay \
				and op["st_f"] <= omv["su"] + omv["act"]:
			if _roll(100) < BLOCK_PROB[level - 1]:
				block_ticks = 14 + _roll(10)
	if block_ticks > 0:
		block_ticks -= 1
		return _dir_word(-1, facing)

	var gap: int = absi(me["x"] - op["x"]) / SimC.FP
	var r_l := _reach_of(w, "light")
	var r_m := _reach_of(w, "medium")
	var r_h := _reach_of(w, "heavy")
	var r_t := _reach_of(w, "tech")
	var punishable := _is_punishable(w, op)

	# 4단계부터는 화면에 드러난 후딜과 무기 튕김을 일반 판단 주기와 무관하게
	# 바로 처벌한다. 입력을 훔쳐보는 대신 이미 발생한 공개 상태만 사용한다.
	if level >= 4 and punishable:
		return _punish(facing, gap, r_m, r_h)

	if cool > 0:
		cool -= 1
		return _dir_word(hold_dir, facing)
	cool = CADENCE[level - 1] + _roll(5)

	# 실수 주입 (난이도가 낮을수록 잦음)
	if _roll(100) < ERR_PROB[level - 1]:
		var junk := _roll(6)
		match junk:
			0: return _start_action(ActionLibrary.Action.LIGHT, facing)
			1: return _start_action(ActionLibrary.Action.MEDIUM, facing)
			2: return _dir_word(1, facing)
			3: return _dir_word(-1, facing)
			_: return 0

	# 오의 시도
	if me["nerve"] >= 3 and gap < r_h + 60 \
			and _roll(100) < SUPER_PROB[level - 1]:
		return _start_action(ActionLibrary.Action.SUPER, facing)

	# 무진은 원거리에서 파도 연계로 압박한다. 사맥이 가득 차면 강 연계가
	# 자동으로 1칸 강화되어, 같은 입력 체계 안에서 고유 자원 운용이 생긴다.
	var mujin_motion_chance := 48
	match w.chars[1 - pi]["id"]:
		"arin": mujin_motion_chance = 18
		"han": mujin_motion_chance = 24
		"daeru": mujin_motion_chance = 60
	if w.chars[pi]["id"] == "mujin" and gap > 90 and gap <= 245 \
			and _roll(100) < mujin_motion_chance:
		if me["nerve"] >= SimC.NERVE_MAX and gap <= 220 \
				and _can_use_slot(w, me, "motion_nerve"):
			return _start_action(ActionLibrary.Action.MOTION_HEAVY, facing)
		if gap > 175 and _can_use_slot(w, me, "motion_heavy"):
			return _start_action(ActionLibrary.Action.MOTION_HEAVY, facing)
		if gap <= 155 and _can_use_slot(w, me, "motion_medium"):
			return _start_action(ActionLibrary.Action.MOTION_MEDIUM, facing)
		if _can_use_slot(w, me, "motion_light"):
			return _start_action(ActionLibrary.Action.MOTION_LIGHT, facing)

	# 카게로는 근접 난타보다 사슬 끝거리와 끌어오기를 우선한다.
	if w.chars[pi]["id"] == "myo" and gap > 125:
		var hook_chance := 62 if w.chars[1 - pi]["id"] == "arin" else 42
		if gap <= r_t + 20 and _can_use_slot(w, me, "tech") and _roll(100) < hook_chance:
			return _start_action(ActionLibrary.Action.TECH, facing)
		if gap >= 185 and gap <= r_h + 15 and _roll(100) < 32:
			return _start_action(ActionLibrary.Action.HEAVY, facing)
	if w.chars[pi]["id"] == "myo" and w.chars[1 - pi]["id"] == "han" and gap <= 145:
		var anti_rush := _roll(100)
		if anti_rush < 52:
			return _start_action(ActionLibrary.Action.LIGHT, facing)
		if anti_rush < 82:
			return _dir_word(-1, facing)

	# 하야테는 짧은 단도 사거리 밖에서 파고들기로 중거리 벽을 넘는다.
	if w.chars[pi]["id"] == "han" and gap > 105 and gap <= 195 \
			and _can_use_slot(w, me, "tech") and _roll(100) < 38:
		return _start_action(ActionLibrary.Action.TECH, facing)

	# 1~3단계는 기존처럼 일반 판단 타이밍에만 후딜을 처벌한다.
	if punishable:
		return _punish(facing, gap, r_m, r_h)

	# 근접
	if gap <= 95:
		var c := _roll(100)
		if c < 18 and _can_use_slot(w, me, "grab"):
			return _start_action(ActionLibrary.Action.GRAB, facing)
		elif c < 45:
			return _start_action(ActionLibrary.Action.LIGHT, facing)
		elif c < 65:
			return _start_action(ActionLibrary.Action.MEDIUM, facing)
		elif c < 85:
			hold_dir = -1
			return _dir_word(-1, facing)
		else:
			return 0

	# 견제 거리
	if gap <= r_m + 25:
		var c2 := _roll(100)
		if c2 < 30:
			return _start_action(ActionLibrary.Action.MEDIUM, facing)
		elif c2 < 45 and gap <= r_l + 10:
			return _start_action(ActionLibrary.Action.LIGHT, facing)
		elif c2 < 58 and gap >= r_h - 40:
			return _start_action(ActionLibrary.Action.HEAVY, facing)
		elif c2 < 75:
			hold_dir = -1
			return _dir_word(-1, facing)
		else:
			hold_dir = 1
			return _dir_word(1, facing)

	# 원거리: 접근 (+ 긴 기술 견제, 가끔 점프 인)
	if r_t > r_m and gap <= r_t + 15 and _can_use_slot(w, me, "tech") \
			and _roll(100) < 30:
		return _start_action(ActionLibrary.Action.TECH, facing)
	if gap > 130 and gap < 360 and level >= 2 and _roll(100) < 12:
		return _start_action(ActionLibrary.Action.JUMP_IN, facing)
	hold_dir = 1
	if me["hp"] < 250 and _roll(100) < 30:
		hold_dir = -1
	return _dir_word(hold_dir, facing)


func _is_punishable(w: CombatWorld, op: Dictionary) -> bool:
	if op["state"] == SimC.ST_RECOIL:
		return true
	if op["state"] == SimC.ST_ATTACK:
		var omv: Dictionary = w.chars[1 - pi]["moves_by_id"].get(op["move"], {})
		return not omv.is_empty() and op["st_f"] > omv["su"] + omv["act"]
	return false


func _punish(facing: int, gap: int, medium_reach: int, heavy_reach: int) -> int:
	if gap <= medium_reach:
		return _start_action(ActionLibrary.Action.MEDIUM, facing)
	if gap <= heavy_reach:
		return _start_action(ActionLibrary.Action.HEAVY, facing)
	hold_dir = 1
	return _dir_word(1, facing)


## 훈련 더미: 0 서기 / 1 전부 가드 / 2 정밀 가드 시도 / 3 CPU
static func dummy_word(mode: int, w: CombatWorld, di: int, brain: CpuBrain) -> int:
	match mode:
		0:
			return 0
		1:
			var me: Dictionary = w.s["p"][di]
			return SimC.B_RIGHT if me["facing"] == -1 else SimC.B_LEFT
		2:
			var op: Dictionary = w.s["p"][1 - di]
			if op["state"] == SimC.ST_ATTACK:
				var omv: Dictionary = w.chars[1 - di]["moves_by_id"].get(op["move"], {})
				if not omv.is_empty() and op["st_f"] >= omv["su"] - 2 and op["st_f"] <= omv["su"] + omv["act"]:
					var me2: Dictionary = w.s["p"][di]
					return SimC.B_RIGHT if me2["facing"] == -1 else SimC.B_LEFT
			return 0
		_:
			return brain.think(w) if brain else 0
