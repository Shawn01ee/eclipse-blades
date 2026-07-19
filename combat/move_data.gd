class_name MoveData
extends Resource
## 기술 데이터. 모든 수치는 여기(.tres)에서 수정한다 — 코드 하드코딩 금지.
## 프레임 규약: 기술 프레임 f는 1부터 시작. 활성 구간 = [startup+1, startup+active].
## 거리 단위: px (시뮬에서 ×1000 고정소수점으로 변환).

@export var id: String = ""
@export var display_name: String = ""
@export var input_command: String = ""          # 표기용 (예: "L", "→+M")
@export var role_note: String = ""               # 선택/HUD에 표시할 전술적 용도
@export var allowed_states: Array = ["idle", "walk"]
@export var startup_frames: int = 5
@export var active_frames: int = 3
@export var recovery_frames: int = 11
@export var damage: int = 70
@export var edge_damage: int = -1               # -1이면 damage×1.25 자동 계산
@export var chip_damage: int = 0
@export var hit_level: String = "mid"
@export var priority: int = 1                   # 경합 우선순위 (높으면 이김)
@export var hitstop: int = 5
@export var hitstop_edge: int = 7
@export var hitstun: int = 16
@export var blockstun: int = 11
@export var pushback_hit: int = 30              # px, PUSH_DUR 틱에 걸쳐 적용
@export var pushback_block: int = 26
@export var meter_gain: int = 0
@export var meter_cost: int = 0
@export var energy_cost: int = 0              # 기술 남용 방지용 기력 소모(0=기본기)
## [{"targets": ["move_id"], "from": f, "to": f, "on": ["hit","block"]}]
@export var cancel_windows: Array = []
## [[from_f, to_f, x, y, w, h], ...]  x=몸 중심에서 전방 오프셋(px), y=지면 기준 아래변, w 전방, h 위
@export var hitboxes_by_frame: Array = []
## [[from_f, to_f, vel_px_per_tick_fp]] 전진(+)/후퇴(-) 이동, fp 단위(px*1000)
@export var motion_frames: Array = []
@export var edge_enabled: bool = true           # 칼결(WeaponEdge) 정타 적용 여부
@export var is_grab: bool = false
@export var grab_range: int = 0                 # 잡기 시도 가능 중심 거리(px)
@export var unblockable: bool = false
@export var sound_event: String = ""
@export var vfx_event: String = ""
@export var camera_event: String = ""
