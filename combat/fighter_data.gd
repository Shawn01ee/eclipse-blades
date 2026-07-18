class_name FighterData
extends Resource
## 캐릭터 데이터 (.tres). 이동 속도는 px/틱 ×1000 (fp).

@export var id: String = ""
@export var display_name: String = ""
@export var weapon_name: String = ""
@export var style_note: String = ""
@export var color: Color = Color.WHITE
@export var max_hp: int = 1000
@export var walk_f: int = 4200                  # fp/틱
@export var walk_b: int = 3400
@export var pushbox_hw: int = 33                # px 반너비
@export var hurtbox_hw: int = 40
@export var hurtbox_h: int = 172                # px 높이 (지면 기준)
@export var edge_ratio_pct: int = 20            # 무기 끝 칼결 구간 비율(%)
## 슬롯: light / medium / heavy / tech / grab / super → MoveData
@export var moves: Dictionary = {}
