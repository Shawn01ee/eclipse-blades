extends Node
## 화면 간 공유 상태 (경기 설정 등). 시뮬 결정론과 무관한 셸 레이어.

enum Mode { VS_2P, VS_CPU, TRAINING, ONLINE }

var mode: int = Mode.VS_CPU
var p1_char := 0
var p2_char := 1
var cpu_level := 2
var router: Node = null          # ui/main.gd 가 등록
var last_replay := {}            # {"chars":[..], "seed":int, "words":[[w1,w2],..]}

var _seed_rng := RandomNumberGenerator.new()


func _ready() -> void:
	_seed_rng.randomize()
	cpu_level = clampi(int(SettingsManager.data["cpu_level"]), 1, CpuBrain.MAX_LEVEL)


func next_match_seed() -> int:
	# 경기 시작 시 한 번 뽑는 시드 — 경기 내부는 이 시드로 완전 결정론
	return int(_seed_rng.randi() % 100000000) + 1


func goto(screen: String) -> void:
	if router:
		router.goto(screen)
