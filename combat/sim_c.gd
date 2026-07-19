class_name SimC
## 전투 시뮬레이션 공통 상수·유틸.
## 결정론 규칙: 시뮬 내부는 정수만 사용한다. 위치·속도는 밀리픽셀(px * 1000) 고정소수점.

const FP := 1000                    # 1px = 1000 (고정소수점 스케일)
const TPS := 60                     # 전투 판정 틱레이트
const ROUND_TICKS := 60 * TPS       # 라운드 60초
const STAGE_HALF := 540 * FP        # 벽 위치 (±540px)
const START_X := 230 * FP           # 라운드 시작 좌우 거리
const BUFFER_TICKS := 5             # 입력 버퍼 5f (누른 틱 포함 5틱 동안 유효)
const PARRY_WINDOW := 3             # 정밀 방어: 피격 직전 3f 안에 뒤 입력
const PUSH_DUR := 8                 # 넉백 적용 틱 수
const NERVE_MAX := 3                # 사맥 최대 3칸
const ENERGY_MAX := 100             # 기술용 기력. 기본 베기는 소비하지 않는다.
const ENERGY_REGEN_TICKS := 3       # 비공격 상태에서 3틱마다 1 회복(초당 20)
const INTRO_TICKS := 90
const ROUND_END_TICKS := 150
const MAX_ROUNDS := 5
const COMBO_SCALE := [100, 90, 80, 70, 60, 50, 50, 50, 50, 50]

# 입력 비트
const B_LEFT := 1
const B_RIGHT := 2
const B_DOWN := 4
const B_L := 8
const B_M := 16
const B_H := 32
const B_T := 64
const B_UP := 128
const B_SUPER := 256                  # 접근성용 오의 전용 입력(사맥 3 필요)
const BTN_BITS := [B_L, B_M, B_H, B_T, B_SUPER]

# 점프 물리 (fp). y=지면 위 높이(양수=위), vy 양수=상승. g로 감속·낙하.
# vy0=15000, g=625 → 체공 ~48틱, 정점 ~180px
const GRAVITY := 625
const JUMP_VY := 15000
const JUMP_VX_F := 4600           # 전진 점프 수평 속도
const JUMP_VX_B := 4000           # 후퇴 점프
const PREJUMP := 4                # 도약 준비(지상, 잡기/타격 가능)
const LAND_RECOVERY := 4          # 착지 경직
const AIR_HIT_POP := 7000         # 공중 피격 시 뜨는 속도(위)
const AIR_HITSTUN := 22
const MAX_AIR_H := 300 * FP       # 천장 (저글 무한 상승 방지)
const GROUND_ACCEL := 900          # 지상 가속도 (fp/틱²)
const GROUND_FRICTION := 1200      # 입력 해제/행동 중 감속 (fp/틱²)

# 상대 방향 비트 (방향 히스토리용)
const D_FWD := 1
const D_BACK := 2
const D_DOWN := 4

# 파이터 상태
const ST_IDLE := 0
const ST_WALK_F := 1
const ST_WALK_B := 2
const ST_ATTACK := 3
const ST_HITSTUN := 4
const ST_BLOCKSTUN := 5
const ST_RECOIL := 6      # 경합 패배/경합 반동
const ST_GRABBING := 7
const ST_GRABBED := 8
const ST_KO := 9
const ST_WIN := 10
const ST_PREJUMP := 11
const ST_JUMP := 12
const ST_LAND := 13
const ST_AIR_ATTACK := 14
const ST_AIR_HIT := 15

const ST_NAMES := {
	ST_IDLE: "idle", ST_WALK_F: "walk_f", ST_WALK_B: "walk_b",
	ST_ATTACK: "attack", ST_HITSTUN: "hitstun", ST_BLOCKSTUN: "blockstun",
	ST_RECOIL: "recoil", ST_GRABBING: "grabbing", ST_GRABBED: "grabbed",
	ST_KO: "ko", ST_WIN: "win", ST_PREJUMP: "prejump", ST_JUMP: "jump",
	ST_LAND: "land", ST_AIR_ATTACK: "air_attack", ST_AIR_HIT: "air_hit",
}

# 경기 페이즈
const PH_INTRO := 0
const PH_FIGHT := 1
const PH_ROUND_END := 2
const PH_MATCH_END := 3

const GRAB_CINE_TICKS := 26   # 잡기 연출 길이
const GRAB_DMG_TICK := 20     # 연출 중 피해 적용 시점
const CLASH_RECOIL := 14
const BEATEN_RECOIL := 18
const PARRY_STUN_DEF := 6     # 정밀 방어 성공 시 방어자 경직
const PARRY_STOP_DEF := 6
const PARRY_STOP_ATK := 14
const PARRY_PUSH_ATK := 40 * FP


## 열린 구간 겹침 판정 (모두 fp 단위). 변끼리 정확히 닿기만 하면 미겹침.
static func overlap(a_min: int, a_max: int, b_min: int, b_max: int) -> bool:
	return a_min < b_max and b_min < a_max


## rect = [x_min, y_min, x_max, y_max] (fp)
static func rect_overlap(a: Array, b: Array) -> bool:
	return overlap(a[0], a[2], b[0], b[2]) and overlap(a[1], a[3], b[1], b[3])


## xorshift64 — 시뮬 내부 결정론적 난수. 상태와 결과 [new_state, value(0..bound-1)] 반환.
static func rng_next(state: int, bound: int) -> Array:
	var x := state
	x = (x ^ (x << 13)) & 0x7FFFFFFFFFFFFFFF
	x = (x ^ (x >> 7)) & 0x7FFFFFFFFFFFFFFF
	x = (x ^ (x << 17)) & 0x7FFFFFFFFFFFFFFF
	if x == 0:
		x = 0x2545F4914F6CDD1D
	return [x, (x >> 17) % bound]


## FNV-1a 32비트 해시 (바이트 단위, 곱셈 오버플로 없음)
static func fnv32(bytes: PackedByteArray) -> int:
	var h := 0x811C9DC5
	for b in bytes:
		h = h ^ b
		h = (h * 0x01000193) & 0xFFFFFFFF
	return h


## 정타(칼결) 피해: ×1.25 반올림 (70→88, 125→156, 260→325)
static func edge_damage_of(base: int) -> int:
	return (base * 125 + 50) / 100
