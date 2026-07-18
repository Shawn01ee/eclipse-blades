extends RefCounted
## 테스트 공용 헬퍼

class Ctx:
	var fails: Array = []
	var count: int = 0
	var suite_name: String = ""

	func suite(n: String) -> void:
		suite_name = n
		print("  [스위트] ", n)

	func ok(cond: bool, msg: String) -> void:
		count += 1
		if not cond:
			fails.append(suite_name + " :: " + msg)
			print("    실패: ", msg)

	func eq(a, b, msg: String) -> void:
		count += 1
		if a != b:
			fails.append(suite_name + " :: " + msg + " (기대=" + str(b) + " 실제=" + str(a) + ")")
			print("    실패: ", msg, " 기대=", b, " 실제=", a)


## 캐릭터 인덱스(0=아린, 1=대루)로 월드 생성. 기본: 인트로 생략, 타이머 사실상 무한.
static func mk(a_idx: int = 0, b_idx: int = 1, rng_seed: int = 1, extra: Dictionary = {}) -> CombatWorld:
	var fds := Registry.load_all()
	var opts := {"skip_intro": true, "timer_ticks": 999999}
	opts.merge(extra, true)
	return CombatWorld.new(Registry.bake(fds[a_idx]), Registry.bake(fds[b_idx]), rng_seed, opts)


## n틱 진행, 이벤트 누적 반환
static func run(w: CombatWorld, n: int, w1: int = 0, w2: int = 0) -> Array:
	var evs: Array = []
	for k in n:
		evs.append_array(w.step(w1, w2))
	return evs


static func has_ev(evs: Array, type: String) -> bool:
	for e in evs:
		if e["t"] == type:
			return true
	return false


static func get_ev(evs: Array, type: String) -> Dictionary:
	for e in evs:
		if e["t"] == type:
			return e
	return {}


## 32비트 LCG — 테스트 입력 스크립트용 (시뮬 난수와 별개)
static func lcg(x: int) -> int:
	return (1103515245 * x + 12345) % 2147483648


## 무작위 원숭이 입력 (양쪽) — 방향 위주 + 간헐적 버튼
static func monkey_word(x: int) -> int:
	var word := 0
	var d := x % 16
	if d < 5:
		word |= SimC.B_LEFT
	elif d < 10:
		word |= SimC.B_RIGHT
	if (x >> 4) % 9 == 0:
		word |= SimC.B_DOWN
	elif (x >> 4) % 9 == 1:
		word |= SimC.B_UP
	var b := (x >> 8) % 23
	if b == 0:
		word |= SimC.B_L
	elif b == 1:
		word |= SimC.B_M
	elif b == 2:
		word |= SimC.B_H
	elif b == 3:
		word |= SimC.B_T
	return word
