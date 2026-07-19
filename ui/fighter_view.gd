extends Node2D
## 파이터 뷰. 시뮬 상태를 읽어 그리기만 한다 (게임플레이 영향 없음).
## 전투 중에는 관절형 수묵 파이터를 그려 발·무릎·골반·몸통·손·무기가 실제로 연결되어 움직인다.
## 원화/절차 시트는 선택 화면 자산과 호환 폴백으로만 유지한다.

const SPRITE_SCALE := 1.34         # hurt_h 대비 스프라이트 높이 배율
const COMBAT_SKINS_ENABLED := false # 스킨 적용 전 관절형 기본 몸체 단계
const ATLAS_COLS := 4
const ATLAS_ROWS := 2
const ATLAS_FOOT_RATIO := {
	"arin": [0.93, 0.93, 0.93, 0.93, 0.80, 0.80, 0.89, 0.80],
	"daeru": [0.89, 0.89, 0.89, 0.89, 0.75, 0.76, 0.80, 0.71],
	"han": [0.93, 0.93, 0.93, 0.93, 0.72, 0.78, 0.77, 0.68],
	"myo": [0.91, 0.91, 0.91, 0.91, 0.80, 0.81, 0.83, 0.79],
}
const ATLAS_ATTACK_BODY_BACK := {"arin": 28.0, "daeru": 24.0, "han": 30.0, "myo": 20.0}

var world: CombatWorld
var idx := 0
var body_col := UiKit.INK
var light_body := false
var weapon_len := 95.0
var fighter_id := "arin"

var sprite_tex: Texture2D = null   # 단일 포즈 폴백
var combat_atlas: Texture2D = null # 실제 자세가 다른 4×2 전투 키 포즈
var sheet_meta := {}               # cell_w, cell_h, foot_y, anims
var strips := {}                   # anim → Texture2D (가로 스트립)
var has_sheets := false
var weapon_kind := "sword"         # sword / polescythe / daggers / chain

var _st := SimC.ST_IDLE
var _prev_st := -1
var _st_f := 0
var _facing := 1
var _nerve := 0
var _scars: Array = []
var _mv := {}
var _wboxes: Array = []
var _eboxes: Array = []
var _hitstop := 0
var _anim := "idle"
var _prev_anim := ""
var _anim_ticks := 0
# 런타임 2차 모션
var _squash := 1.0                 # <1 납작 / >1 늘어남 (발 고정)
var _shake := Vector2.ZERO
var _impact_kick := Vector2.ZERO   # 피격 순간 접촉 방향으로 밀리는 시각 반동
var _contact_screen := Vector2.ZERO
var _contact_time := 0.0           # 적중 히트스톱 동안 실제 접점까지 무기를 고정
var _contact_edge := false


func setup(w: CombatWorld, i: int, fd_color: Color, char_id: String) -> void:
	world = w
	idx = i
	body_col = fd_color
	fighter_id = char_id
	light_body = fd_color.v > 0.5
	weapon_len = {"daeru": 140.0, "mujin": 118.0}.get(char_id, 95.0)
	weapon_kind = {"arin": "sword", "daeru": "polescythe", "han": "daggers",
			"myo": "chain", "mujin": "sword"}.get(char_id, "sword")
	# 현재 아트 방향은 스킨 없는 관절형 수묵 실루엣. 꺼진 스킨·시트는 모바일 메모리에도 싣지 않는다.
	if COMBAT_SKINS_ENABLED:
		sprite_tex = _load_tex("res://art/sprites/%s.png" % char_id)
		combat_atlas = _load_tex("res://art/combat_atlas/%s.png" % char_id)
		_load_sheets(char_id)
	else:
		sprite_tex = null
		combat_atlas = null
		has_sheets = false
		strips.clear()
		sheet_meta.clear()


func _load_tex(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path)
	var abs_path := ProjectSettings.globalize_path(path)
	if FileAccess.file_exists(abs_path):
		var img := Image.load_from_file(abs_path)
		if img != null:
			return ImageTexture.create_from_image(img)
	return null


func _load_sheets(char_id: String) -> void:
	has_sheets = false
	strips = {}
	sheet_meta = {}
	var json_path := "res://art/sheets/%s.json" % char_id
	if not FileAccess.file_exists(json_path):
		return
	var fa := FileAccess.open(json_path, FileAccess.READ)
	if fa == null:
		return
	var parsed = JSON.parse_string(fa.get_as_text())
	if not (parsed is Dictionary):
		return
	sheet_meta = parsed
	for anim in sheet_meta.get("anims", {}):
		var tex := _load_tex("res://art/sheets/%s_%s.png" % [char_id, anim])
		if tex != null:
			strips[anim] = tex
	has_sheets = strips.has("idle") and strips.has("attack")


func sync() -> void:
	var p: Dictionary = world.s["p"][idx]
	position = Vector2(640.0 + p["x"] / 1000.0, 620.0 - p["y"] / 1000.0)
	_st = p["state"]
	_st_f = p["st_f"]
	_facing = p["facing"]
	_nerve = p["nerve"]
	_scars = p["scars"]
	_hitstop = p["hitstop"]
	_mv = {}
	if _st == SimC.ST_ATTACK or _st == SimC.ST_GRABBING or _st == SimC.ST_AIR_ATTACK:
		_mv = world.chars[idx]["moves_by_id"].get(p["move"], {})
	var dbg := world.debug_boxes(idx)
	_wboxes = dbg["weapon"]
	_eboxes = dbg["edge"]

	# 애니메이션 진행 (히트스톱 중엔 정지 → 타격감 유지)
	_anim = _anim_for_state()
	if _anim != _prev_anim:
		_anim_ticks = 0
		_prev_anim = _anim
	elif _hitstop == 0:
		_anim_ticks += 1
	# 상태 진입 순간의 충격 반동
	if _st != _prev_st:
		if _st == SimC.ST_HITSTUN or _st == SimC.ST_RECOIL or _st == SimC.ST_AIR_HIT:
			_squash = 0.82
		elif _st == SimC.ST_ATTACK or _st == SimC.ST_AIR_ATTACK:
			_squash = 1.06
		elif _st == SimC.ST_PREJUMP:
			_squash = 0.86        # 웅크렸다 도약
		elif _st == SimC.ST_LAND:
			_squash = 0.80        # 착지 스쿼시
		_prev_st = _st
	queue_redraw()


func _process(delta: float) -> void:
	# 스쿼시·흔들림 감쇠 (프레임 무관, 부드럽게)
	_squash = lerpf(_squash, 1.0, clampf(delta * 11.0, 0, 1))
	if _st == SimC.ST_HITSTUN and _hitstop > 0:
		_shake = Vector2(randf_range(-3, 3), randf_range(-1.5, 1.5))
	else:
		_shake = _shake.lerp(Vector2.ZERO, clampf(delta * 14.0, 0, 1))
	_impact_kick = _impact_kick.lerp(Vector2.ZERO, clampf(delta * 17.0, 0, 1))
	_contact_time = maxf(_contact_time - delta, 0.0)
	if absf(_squash - 1.0) > 0.001 or _shake.length() > 0.05 \
			or _impact_kick.length() > 0.05 or _contact_time > 0.0:
		queue_redraw()


## MatchScreen의 실제 hit 이벤트 좌표를 받아, 히트스톱 동안 무기 끝을 접점에 고정한다.
func show_blade_contact(screen_pos: Vector2, kind: String, edge: bool) -> void:
	_contact_screen = screen_pos
	_contact_edge = edge
	_contact_time = {"light": 0.10, "medium": 0.13, "heavy": 0.18, "tech": 0.11,
			"super": 0.22}.get(kind, 0.12)
	queue_redraw()


func receive_impact(direction: int, kind: String) -> void:
	var power: float = {"light": 5.0, "medium": 8.0, "heavy": 13.0, "tech": 6.0,
			"super": 16.0}.get(kind, 7.0)
	_impact_kick = Vector2(float(direction) * power, -power * 0.18)
	_squash = 0.78 if kind == "heavy" or kind == "super" else 0.86
	queue_redraw()


func _anim_for_state() -> String:
	match _st:
		SimC.ST_IDLE, SimC.ST_WIN, SimC.ST_PREJUMP, SimC.ST_LAND: return "idle"
		SimC.ST_WALK_F, SimC.ST_WALK_B: return "walk"
		SimC.ST_JUMP: return "idle"          # 공중 대기(전용 시트 없음 → 기울기로 표현)
		SimC.ST_ATTACK, SimC.ST_GRABBING, SimC.ST_AIR_ATTACK: return "attack"
		SimC.ST_HITSTUN, SimC.ST_RECOIL, SimC.ST_GRABBED, SimC.ST_AIR_HIT: return "hit"
		SimC.ST_BLOCKSTUN: return "guard"
		SimC.ST_KO: return "ko"
		_: return "idle"


func _cur_frame(anim: String) -> int:
	var info: Dictionary = sheet_meta["anims"].get(anim, {"frames": 1, "fps": 8, "loop": true})
	var nf: int = info["frames"]
	if anim == "attack" and not _mv.is_empty():
		# 발동→활성→후딜을 코일→베기→회복 프레임에 매핑
		var su: int = _mv["su"]
		var act: int = _mv["act"]
		var rec: int = maxi(_mv["rec"], 1)
		var pp: float
		if _st_f <= su:
			pp = 0.2 * float(_st_f) / maxf(su, 1)
		elif _st_f <= su + act:
			pp = 0.2 + 0.32 * float(_st_f - su) / maxf(act, 1)
		else:
			pp = 0.52 + 0.48 * clampf(float(_st_f - su - act) / rec, 0, 1)
		return clampi(int(round(pp * (nf - 1))), 0, nf - 1)
	var fstep := int(_anim_ticks * int(info["fps"]) / 60)
	if info.get("loop", true):
		return fstep % nf
	return mini(fstep, nf - 1)


func _draw() -> void:
	var ch: Dictionary = world.chars[idx]
	var hh: float = ch["hurt_h"] / 1000.0
	var hw: float = ch["hurt_hw"] / 1000.0

	# 그림자 — 공중이면 지면에 남고 높이에 따라 작아짐
	var air_h := 620.0 - position.y
	var sh_scale := clampf(1.0 - air_h / 700.0, 0.35, 1.0)
	draw_circle(Vector2(0, 2 + air_h), hw * 1.25 * (2.0 - _squash) * sh_scale, Color(UiKit.INK, 0.14 * sh_scale))

	if COMBAT_SKINS_ENABLED and combat_atlas != null:
		_draw_combat_atlas(hh, hw)
	else:
		_draw_rig(hh, hw)


# ---------------------------------------------------------------- 전투 키 포즈 아틀라스

func _atlas_frame() -> int:
	match _st:
		SimC.ST_WALK_F, SimC.ST_WALK_B:
			var phase := (int(_anim_ticks / 7) % 2)
			if _st == SimC.ST_WALK_B:
				phase = 1 - phase
			return 1 + phase
		SimC.ST_ATTACK, SimC.ST_GRABBING:
			if _mv.is_empty():
				return 4
			return 4 if _st_f > int(_mv["su"]) and _st_f <= int(_mv["su"]) + int(_mv["act"]) else 3
		SimC.ST_BLOCKSTUN:
			return 5
		SimC.ST_HITSTUN, SimC.ST_RECOIL, SimC.ST_GRABBED, SimC.ST_AIR_HIT, SimC.ST_KO:
			return 6
		SimC.ST_JUMP, SimC.ST_AIR_ATTACK:
			return 7
		_:
			return 0


func _draw_combat_atlas(hh: float, hw: float) -> void:
	var frame := _atlas_frame()
	var cell_w := float(combat_atlas.get_width()) / ATLAS_COLS
	var cell_h := float(combat_atlas.get_height()) / ATLAS_ROWS
	var col := frame % ATLAS_COLS
	var row := frame / ATLAS_COLS
	var target_cell_h := hh * 1.74
	var scale := target_cell_h / cell_h
	var foot_ratios: Array = ATLAS_FOOT_RATIO.get(fighter_id, ATLAS_FOOT_RATIO["arin"])
	var foot_y: float = cell_h * float(foot_ratios[frame])
	var rot := deg_to_rad(_lean_deg()) * _facing
	var offset := _shake + _impact_kick
	var body_back := _atlas_attack_body_back(frame)
	offset.x -= float(_facing) * body_back
	if _st == SimC.ST_IDLE:
		offset.y += sin(float(_anim_ticks) * 0.10) * 1.5
	elif _st == SimC.ST_WALK_F or _st == SimC.ST_WALK_B:
		offset.y += absf(sin(float(_anim_ticks) * 0.45)) * 3.0
	elif _st == SimC.ST_KO:
		rot = deg_to_rad(78.0) * _facing
		offset.y += 4.0

	# 생성 포즈는 모두 오른쪽을 향한다. 월드 facing으로 좌우 반전하고 발을 물리 원점에 고정한다.
	var volume_x := 2.0 - _squash
	draw_set_transform(offset, rot, Vector2(_facing * scale * volume_x, scale * _squash))
	draw_texture_rect_region(combat_atlas,
			Rect2(-cell_w * 0.5, -foot_y, cell_w, cell_h),
			Rect2(col * cell_w, row * cell_h, cell_w, cell_h), _state_tint())
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# 그림 자체는 자세를 담당하고, 활성 궤적은 실제 시뮬 히트박스 끝까지 맞춘다.
	if _contact_time <= 0.0:
		_draw_atlas_active_trail()
	_draw_contact_weapon()
	_draw_overlays(hh, hw, false)


func _atlas_attack_body_back(frame: int = -1) -> float:
	var f := _atlas_frame() if frame < 0 else frame
	if f != 4 or (_st != SimC.ST_ATTACK and _st != SimC.ST_GRABBING):
		return 0.0
	return float(ATLAS_ATTACK_BODY_BACK.get(fighter_id, 24.0))


func _draw_contact_weapon() -> void:
	if _contact_time <= 0.0:
		return
	var tip := _contact_screen - position
	var fx := float(_facing)
	# 활성 포즈의 몸을 뒤로 뺀 만큼 손잡이도 같은 위치에서 시작한다.
	var grip := Vector2((24.0 - _atlas_attack_body_back()) * fx, -94.0)
	# 비정상적으로 먼 이벤트 좌표에도 화면을 가르는 무한 칼이 생기지 않도록 제한한다.
	var delta := tip - grip
	var max_len := 235.0 if weapon_kind == "chain" else (205.0 if weapon_kind == "polescythe" else 175.0)
	if delta.length() > max_len:
		tip = grip + delta.normalized() * max_len
	var edge_col := UiKit.SEAL if _contact_edge else Color(0.76, 0.10, 0.08)
	match weapon_kind:
		"sword":
			_wp_blade(grip, tip, 5.5, edge_col, true)
		"daggers":
			_wp_daggers(grip, tip, edge_col, true)
		"polescythe":
			_wp_polescythe(grip, tip, edge_col, true)
		"chain":
			_wp_chain(grip, tip, edge_col, true)
		_:
			_wp_blade(grip, tip, 5.5, edge_col, true)
	_draw_tip_glint(tip, fx, 0.96)


func _draw_atlas_active_trail() -> void:
	if (_st != SimC.ST_ATTACK and _st != SimC.ST_AIR_ATTACK) or _mv.is_empty():
		return
	if world.active_weapon_rects(idx, true).is_empty():
		return
	var far_x := 0.0
	var center_y := -90.0
	for b in _mv.get("boxes", []):
		if _st_f < int(b[0]) or _st_f > int(b[1]):
			continue
		far_x = maxf(far_x, float(int(b[2]) + int(b[4])))
		center_y = -float(int(b[3])) - float(int(b[5])) * 0.5
	var fx := float(_facing)
	var finish := Vector2(far_x * fx, center_y)
	# 포즈 속 무기를 덧그리지 않고, 실제 판정 끝에 짧은 칼결 섬광만 표시한다.
	var slash := Vector2(7.0 * fx, -13.0)
	draw_line(finish - slash, finish + slash, Color(UiKit.PAPER_LIGHT, 0.82), 6.0, true)
	draw_line(finish - slash, finish + slash, Color(UiKit.SEAL, 0.90), 2.2, true)
	draw_circle(finish, 3.5, Color(UiKit.PAPER_LIGHT, 0.92))


# ---------------------------------------------------------------- 관절형 전투 파이터

func _draw_rig(hh: float, hw: float) -> void:
	var pose := _rig_pose(hh, hw)
	var bulk := 1.18 if fighter_id == "mujin" else 1.0
	var main := body_col.lerp(UiKit.INK, 0.30 if light_body else 0.08)
	var shade := main.lerp(UiKit.INK, 0.42)
	var cloth := main.lerp(UiKit.PAPER_LIGHT, 0.16)
	var skin := Color(0.67, 0.55, 0.43)
	var tint := _state_tint()
	main *= tint
	shade *= tint
	cloth *= tint

	draw_set_transform(_shake, 0.0, Vector2(_facing, 1.0))

	# 뒤쪽 다리부터 그려 관절의 앞뒤 관계를 유지한다.
	_draw_limb(pose["hip_back"], pose["knee_back"], 13.0 * bulk, shade)
	_draw_limb(pose["knee_back"], pose["foot_back"], 11.0 * bulk, shade)
	_draw_foot(pose["foot_back"], shade)

	# 도포/갑옷은 골반과 흉곽을 연결하며, 보행·공격 때 실제 중심을 따라간다.
	var skirt_left_x := minf(pose["foot_front"].x, pose["foot_back"].x) - 7.0
	var skirt_right_x := maxf(pose["foot_front"].x, pose["foot_back"].x) + 7.0
	var skirt_y := maxf(pose["foot_front"].y, pose["foot_back"].y) - 5.0
	var robe := PackedVector2Array([
		pose["shoulder_back"] + Vector2(-5, 8), pose["shoulder_front"] + Vector2(7, 8),
		pose["hip_front"] + Vector2(15, 7), Vector2(skirt_right_x, skirt_y),
		Vector2(skirt_left_x, skirt_y), pose["hip_back"] + Vector2(-15, 7),
	])
	draw_polygon(robe, [cloth])
	var robe_line := robe.duplicate()
	robe_line.append(robe[0])
	draw_polyline(robe_line, UiKit.INK, 3.0)

	# 몸통 축과 머리. 축이 휘면 피격·가드·공중 자세가 함께 변한다.
	_draw_limb(pose["hip"], pose["chest"], 25.0 * bulk, main)
	draw_circle(pose["head"], 15.0 * bulk, UiKit.INK)
	draw_circle(pose["head"] + Vector2(1.5, 1.0), 11.5 * bulk, skin * tint)
	draw_line(pose["head"] + Vector2(3, -1), pose["head"] + Vector2(10, 1), UiKit.INK, 1.8)
	# 상투/머리끈으로 실루엣 방향을 또렷하게 한다.
	draw_circle(pose["head"] + Vector2(-5, -15), 6.0, UiKit.INK)
	draw_line(pose["head"] + Vector2(-9, -13), pose["head"] + Vector2(-21, -7), UiKit.INK, 3.0)
	if fighter_id == "mujin":
		# 큰 묶음머리는 스킨 없이도 중량 검객의 실루엣을 즉시 구분한다.
		var tail := PackedVector2Array([
			pose["head"] + Vector2(-7, -16), pose["head"] + Vector2(-27, -28),
			pose["head"] + Vector2(-46, -17), pose["head"] + Vector2(-39, 2),
			pose["head"] + Vector2(-25, 12),
		])
		draw_polyline(tail, UiKit.INK, 11.0, true)
		draw_polyline(tail, shade, 5.5, true)

	# 뒤팔 → 무기 → 앞팔 순서. 손과 무기 손잡이는 같은 좌표를 공유한다.
	_draw_limb(pose["shoulder_back"], pose["elbow_back"], 10.0 * bulk, shade)
	_draw_limb(pose["elbow_back"], pose["hand_back"], 8.0 * bulk, shade)
	_draw_rig_weapon(pose["grip"], pose["tip"], pose["weapon_active"])
	_draw_limb(pose["shoulder_front"], pose["elbow_front"], 11.0 * bulk, main)
	_draw_limb(pose["elbow_front"], pose["hand_front"], 8.5 * bulk, main)
	draw_circle(pose["hand_front"], 5.0, skin * tint)
	draw_circle(pose["hand_back"], 4.5, skin * tint)

	# 앞다리는 최상단에 두어 전진/후퇴 보폭이 읽히게 한다.
	_draw_limb(pose["hip_front"], pose["knee_front"], 14.0 * bulk, main)
	_draw_limb(pose["knee_front"], pose["foot_front"], 12.0 * bulk, main)
	_draw_foot(pose["foot_front"], main)

	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_draw_overlays(hh, hw, false)


func _rig_pose(hh: float, hw: float) -> Dictionary:
	var u := hh / 180.0
	var hip := Vector2(0, -70) * u
	var chest := Vector2(2, -126) * u
	var head := Vector2(5, -159) * u
	var foot_front := Vector2(20, 0) * u
	var foot_back := Vector2(-19, 0) * u
	var knee_front := Vector2(18, -36) * u
	var knee_back := Vector2(-17, -37) * u
	var shoulder_front := chest + Vector2(11, -2) * u
	var shoulder_back := chest + Vector2(-11, 1) * u

	var walk_phase := sin(float(_anim_ticks) * 0.34)
	if _st == SimC.ST_WALK_F or _st == SimC.ST_WALK_B:
		var dir := 1.0 if _st == SimC.ST_WALK_F else -0.75
		var stride := walk_phase * dir
		foot_front = Vector2(28 * stride + 12, -maxf(stride, 0.0) * 10) * u
		foot_back = Vector2(-28 * stride - 12, -maxf(-stride, 0.0) * 10) * u
		knee_front = hip.lerp(foot_front, 0.52) + Vector2(9, -10) * u
		knee_back = hip.lerp(foot_back, 0.52) + Vector2(-8, -9) * u
		hip.y += absf(walk_phase) * 4.0 * u
		chest.x += 7.0 * dir * u
		head.x += 5.0 * dir * u
	elif _st == SimC.ST_PREJUMP or _st == SimC.ST_LAND:
		var crouch := 14.0 if _st == SimC.ST_PREJUMP else 10.0
		hip.y += crouch * u
		chest.y += crouch * 0.65 * u
		head.y += crouch * 0.45 * u
		knee_front = Vector2(28, -26) * u
		knee_back = Vector2(-29, -25) * u
		foot_front = Vector2(32, 0) * u
		foot_back = Vector2(-31, 0) * u
	elif _st == SimC.ST_JUMP or _st == SimC.ST_AIR_ATTACK or _st == SimC.ST_AIR_HIT:
		var rise: bool = world.s["p"][idx]["vy"] > 0
		hip += Vector2(5 if rise else -2, -4) * u
		chest += Vector2(10 if rise else -4, 0) * u
		head += Vector2(12 if rise else -5, 2) * u
		knee_front = hip + Vector2(24, 26) * u
		knee_back = hip + Vector2(-22, 20) * u
		foot_front = knee_front + Vector2(20, 23) * u
		foot_back = knee_back + Vector2(-15, 25) * u
		if _st == SimC.ST_AIR_HIT:
			chest.x -= 24 * u
			head.x -= 31 * u
	elif _st == SimC.ST_ATTACK:
		var ap := _attack_pose_progress()
		var drive := sin(ap * PI)
		hip.x += drive * 13.0 * u
		chest.x += drive * 25.0 * u
		head.x += drive * 20.0 * u
		foot_front = Vector2(32 + drive * 12, 0) * u
		foot_back = Vector2(-28, 0) * u
		knee_front = hip.lerp(foot_front, 0.54) + Vector2(8, -12) * u
		knee_back = hip.lerp(foot_back, 0.53) + Vector2(-7, -10) * u
	elif _st == SimC.ST_HITSTUN or _st == SimC.ST_RECOIL or _st == SimC.ST_GRABBED:
		chest.x -= 22 * u
		head.x -= 31 * u
		hip.x -= 7 * u
		knee_front.x += 10 * u
		knee_back.x -= 5 * u
	elif _st == SimC.ST_BLOCKSTUN:
		chest.x -= 10 * u
		head.x -= 13 * u
		foot_front = Vector2(28, 0) * u
		foot_back = Vector2(-27, 0) * u
	elif _st == SimC.ST_KO:
		hip = Vector2(-22, -25) * u
		chest = Vector2(27, -34) * u
		head = Vector2(64, -24) * u
		foot_front = Vector2(42, 0) * u
		foot_back = Vector2(-56, 0) * u
		knee_front = Vector2(15, -12) * u
		knee_back = Vector2(-35, -14) * u

	shoulder_front = chest + Vector2(12, -3) * u
	shoulder_back = chest + Vector2(-12, 1) * u
	var weapon := _rig_weapon_solution(chest, shoulder_front, hh, hw)
	var hand_front: Vector2 = weapon["grip"]
	var blade_dir: Vector2 = (weapon["tip"] - weapon["grip"]).normalized()
	var hand_back := hand_front - blade_dir * (13.0 * u)
	if weapon_kind == "daggers":
		hand_back = chest + Vector2(-8, 22) * u
	var elbow_front := _bent_joint(shoulder_front, hand_front, 13.0 * u)
	var elbow_back := _bent_joint(shoulder_back, hand_back, -11.0 * u)

	return {
		"hip": hip, "chest": chest, "head": head,
		"hip_front": hip + Vector2(8, 2) * u, "hip_back": hip + Vector2(-8, 3) * u,
		"knee_front": knee_front, "knee_back": knee_back,
		"foot_front": foot_front, "foot_back": foot_back,
		"shoulder_front": shoulder_front, "shoulder_back": shoulder_back,
		"elbow_front": elbow_front, "elbow_back": elbow_back,
		"hand_front": hand_front, "hand_back": hand_back,
		"grip": weapon["grip"], "tip": weapon["tip"], "weapon_active": weapon["active"],
	}


func _rig_weapon_solution(chest: Vector2, shoulder: Vector2, hh: float, hw: float) -> Dictionary:
	var u := hh / 180.0
	var grip := shoulder + Vector2(18, 22) * u
	var rest_angle := deg_to_rad(-28.0)
	var tip := grip + Vector2(cos(rest_angle), sin(rest_angle)) * weapon_len
	var active := false
	if _st == SimC.ST_ATTACK or _st == SimC.ST_AIR_ATTACK:
		var reach := weapon_len
		for b in _mv.get("boxes", []):
			reach = maxf(reach, float(int(b[2]) + int(b[4])))
		var su: int = _mv.get("su", 1)
		var act: int = _mv.get("act", 1)
		var rec: int = maxi(_mv.get("rec", 1), 1)
		var rest := grip + Vector2(reach * 0.52, -hh * 0.16)
		var coil := grip + Vector2(-reach * 0.28, -hh * 0.38)
		var hi := grip + Vector2(reach * 0.92, -hh * 0.56)
		var lo := grip + Vector2(reach, -hh * (0.08 if _st == SimC.ST_AIR_ATTACK else 0.22))
		var slot: String = _mv.get("slot", "medium")
		if slot == "light" or slot == "tech":
			hi = grip + Vector2(reach, -hh * 0.26)
			lo = grip + Vector2(reach, -hh * 0.18)
		elif slot == "heavy":
			hi = grip + Vector2(reach * 0.55, -hh * 0.78)
			lo = grip + Vector2(reach, -hh * 0.10)
		if _st_f <= su:
			tip = rest.lerp(coil, _ease(float(_st_f) / maxf(su, 1)))
		elif _st_f <= su + act:
			active = true
			tip = hi.lerp(lo, _ease(float(_st_f - su) / maxf(act, 1)))
		else:
			tip = lo.lerp(rest, _ease(clampf(float(_st_f - su - act) / rec, 0, 1)))
	elif _st == SimC.ST_BLOCKSTUN:
		grip = chest + Vector2(24, 20) * u
		tip = grip + Vector2(10, -weapon_len)
	elif _st == SimC.ST_HITSTUN or _st == SimC.ST_RECOIL or _st == SimC.ST_AIR_HIT:
		grip = chest + Vector2(4, 26) * u
		tip = grip + Vector2(-weapon_len * 0.55, weapon_len * 0.45)
	elif _st == SimC.ST_KO:
		grip = chest + Vector2(15, 13) * u
		tip = grip + Vector2(weapon_len, 8)
	# 관절형 몸체도 아틀라스와 동일하게 히트 이벤트의 실제 충돌점을 사용한다.
	# draw transform이 facing으로 x를 뒤집으므로 화면 좌표를 로컬 정면 좌표로 되돌린다.
	if _contact_time > 0.0 and (_st == SimC.ST_ATTACK or _st == SimC.ST_AIR_ATTACK):
		var contact_delta := _contact_screen - position
		tip = Vector2(contact_delta.x * float(_facing), contact_delta.y)
		active = true
	return {"grip": grip, "tip": tip, "active": active}


func _attack_pose_progress() -> float:
	if _mv.is_empty():
		return 0.0
	var total: int = maxi(_mv["total"], 1)
	return clampf(float(_st_f) / total, 0.0, 1.0)


func _bent_joint(a: Vector2, b: Vector2, bend: float) -> Vector2:
	var d := b - a
	if d.length_squared() < 0.001:
		return a
	var n := Vector2(-d.y, d.x).normalized()
	return a.lerp(b, 0.52) + n * bend


func _draw_limb(a: Vector2, b: Vector2, width: float, fill: Color) -> void:
	draw_line(a, b, UiKit.INK, width + 4.0, true)
	draw_line(a, b, fill, width, true)
	draw_circle(a, width * 0.48, fill)


func _draw_foot(p: Vector2, fill: Color) -> void:
	draw_line(p + Vector2(-7, -2), p + Vector2(10, 0), UiKit.INK, 9.0, true)
	draw_line(p + Vector2(-6, -3), p + Vector2(9, -1), fill, 5.0, true)


func _draw_rig_weapon(grip: Vector2, tip: Vector2, active: bool) -> void:
	var edge_col := UiKit.SEAL if active else UiKit.INK
	if active:
		var dir := tip - grip
		var prev := grip + dir.rotated(-0.32) * 0.92
		var sweep := PackedVector2Array([grip, prev, tip])
		draw_polygon(sweep, [Color(UiKit.INK, 0.13)])
	match weapon_kind:
		"sword": _wp_blade(grip, tip, 4.5, edge_col, active)
		"daggers": _wp_daggers(grip, tip, edge_col, active)
		"polescythe": _wp_polescythe(grip, tip, edge_col, active)
		"chain": _wp_chain(grip, tip, edge_col, active)
		_: _wp_blade(grip, tip, 4.5, edge_col, active)


# ---------------------------------------------------------------- 시트 렌더

func _draw_sheet(hh: float, hw: float) -> void:
	var cw: float = sheet_meta["cell_w"]
	var cell_h: float = sheet_meta["cell_h"]
	var foot_y: float = sheet_meta["foot_y"]
	var s := (hh * SPRITE_SCALE) / 360.0
	var frame := _cur_frame(_anim)
	var strip: Texture2D = strips[_anim]

	var lean := _lean_deg()
	var rot := deg_to_rad(lean) * _facing
	var sqx := 2.0 - _squash          # 납작할수록 좌우로 퍼짐(부피 보존 근사)
	var tint := _state_tint()

	# 발(원점) 고정 회전 + 스쿼시 + 좌우 반전
	draw_set_transform(_shake, rot, Vector2(-_facing * s * sqx, s * _squash))
	draw_texture_rect_region(strip, Rect2(-cw * 0.5, -foot_y, cw, cell_h),
		Rect2(frame * cw, 0.0, cw, cell_h), tint)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	_draw_overlays(hh, hw)


# ---------------------------------------------------------------- 단일 포즈 폴백

func _draw_sprite_single(hh: float, hw: float) -> void:
	var target_h := hh * 1.30
	var s := target_h / sprite_tex.get_height()
	var w := sprite_tex.get_width() * s
	var rot := deg_to_rad(_lean_deg()) * _facing
	var y_off := 0.0
	if _st == SimC.ST_KO:
		rot = deg_to_rad(-80.0) * _facing
		y_off = -hw * 0.6
	draw_set_transform(Vector2(0, y_off) + _shake, rot, Vector2(-_facing * (2.0 - _squash), _squash) * s)
	draw_texture_rect(sprite_tex, Rect2(-w * 0.5, -target_h, w, target_h), false, _state_tint())
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_draw_overlays(hh, hw)


func _state_tint() -> Color:
	match _st:
		SimC.ST_HITSTUN, SimC.ST_GRABBED:
			return Color(1.0, 0.66, 0.60)
		SimC.ST_BLOCKSTUN:
			return Color(0.82, 0.83, 0.86)
		SimC.ST_RECOIL:
			return Color(0.95, 0.82, 0.80)
		SimC.ST_KO:
			return Color(0.62, 0.55, 0.53)
		_:
			return Color.WHITE


## 스프라이트 위 공통 오버레이: 무기 스트라이크, 상처(+피 흐름), 사맥 만개
func _draw_overlays(hh: float, hw: float, include_strike: bool = true) -> void:
	# 무기가 상대 히트박스까지 뻗어 베는/찌르는 연출
	if include_strike and (_st == SimC.ST_ATTACK or _st == SimC.ST_AIR_ATTACK) \
			and not _mv.is_empty() and not _mv.get("grab", false):
		_draw_strike(hh, hw)
	# 상처 + 흐르는 피 (현실감)
	for sc in _scars:
		var sx: float = float(sc[0]) * 0.8
		var sy: float = -float(sc[1])
		var ang := deg_to_rad(float(sc[2]))
		var dv := Vector2(cos(ang), sin(ang)) * 11.0
		draw_line(Vector2(sx, sy) - dv, Vector2(sx, sy) + dv, UiKit.SEAL, 2.5)
		# 아래로 스며 흐르는 핏자국
		draw_line(Vector2(sx, sy), Vector2(sx + 1.5, sy + 10.0 + (sc[1] % 9)), Color(0.5, 0.05, 0.04, 0.75), 2.0)
	# 사맥 만개 (오의 가능)
	if _nerve >= SimC.NERVE_MAX:
		var pulse := 0.5 + 0.5 * sin(float(world.s["tick"]) * 0.2)
		draw_rect(Rect2(-hw * 0.95, -hh * 1.06, hw * 1.9, hh * 1.08), Color(UiKit.SEAL, 0.35 + 0.35 * pulse), false, 2.5)


# ---------------------------------------------------------------- 먹 실루엣 폴백

func _draw_ink(hh: float, hw: float) -> void:
	var lean := _lean_deg()
	draw_set_transform(_shake, deg_to_rad(lean) * _facing, Vector2(_facing, _squash))
	if _st == SimC.ST_KO:
		var body := Rect2(-hh * 0.5, -hw * 1.2, hh * 0.85, hw * 1.1)
		UiKit.brush_rect(self, body, Color(body_col, 0.85), idx * 100 + 9)
		draw_rect(body, Color(UiKit.INK, 0.8), false, 2.0)
		draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
		return
	var fill := body_col
	var robe := PackedVector2Array([
		Vector2(-hw * 0.72, -hh * 0.52), Vector2(hw * 0.78, -hh * 0.52),
		Vector2(hw * 1.05, 0), Vector2(-hw * 1.15, 0)])
	draw_polygon(robe, [fill])
	draw_polyline(robe, UiKit.INK, 2.5)
	var torso := Rect2(-hw * 0.62, -hh * 0.9, hw * 1.3, hh * 0.42)
	UiKit.brush_rect(self, torso, fill, idx * 100 + 3)
	draw_rect(torso, UiKit.INK, false, 2.5)
	var head_c := Vector2(hw * 0.1, -hh * 0.99)
	draw_circle(head_c, hh * 0.085, UiKit.INK)
	_draw_weapon(hh, hw)
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
	_draw_overlays(hh, hw)


func _draw_weapon(hh: float, hw: float) -> void:
	var grip := Vector2(hw * 0.55, -hh * 0.62)
	var a := _weapon_angle()
	var dirv := Vector2(cos(deg_to_rad(a)), sin(deg_to_rad(a)))
	var tip := grip + dirv * weapon_len
	draw_line(Vector2(0, -hh * 0.75), grip, UiKit.INK, 4.0)
	draw_line(grip, tip, UiKit.SEAL if _st == SimC.ST_ATTACK else UiKit.INK, 4.5)
	draw_circle(grip, 4.0, UiKit.INK)


## 무기 스트라이크: 발동(움츠림)→활성(뻗어 벰)→후딜(거둠).
## 활성 구간엔 실제 히트박스 far edge까지 무기 끝이 도달해 상대에게 꽂힌다.
func _draw_strike(hh: float, hw: float) -> void:
	var fx := float(_facing)
	var su: int = _mv["su"]
	var act: int = _mv["act"]
	var rec: int = maxi(_mv["rec"], 1)
	# 히트박스에서 사거리(far edge)와 근접(front) 추출
	var reach := weapon_len
	var front := hw * 0.9
	for b in _mv.get("boxes", []):
		reach = maxf(reach, float(int(b[2]) + int(b[4])))
		front = minf(front, float(int(b[2])))
	var grip := Vector2(hw * 0.28 * fx, -hh * 0.60)
	var rest := grip + Vector2(reach * 0.34 * fx, -hh * 0.05)
	var back := grip + Vector2(-reach * 0.30 * fx, -hh * 0.32)
	var hi := Vector2(reach * fx, -hh * 0.80)
	var lo := Vector2(reach * fx, -hh * 0.30)

	var tip: Vector2
	var active := false
	if _st_f <= su:
		tip = rest.lerp(back, _ease(float(_st_f) / maxf(su, 1)))
	elif _st_f <= su + act:
		active = true
		tip = hi.lerp(lo, _ease(float(_st_f - su) / maxf(act, 1)))
	else:
		tip = lo.lerp(rest, _ease(clampf(float(_st_f - su - act) / rec, 0, 1)))

	# 활성 궤적(잔상) — 이번 스윙이 지나온 부채꼴
	if active:
		var swept := PackedVector2Array([grip, hi, (hi + tip) * 0.5, tip])
		draw_polygon(swept, [Color(UiKit.INK, 0.16)])

	var edge_col := UiKit.SEAL if active else UiKit.INK   # 활성 중 칼끝에 핏빛
	match weapon_kind:
		"sword": _wp_blade(grip, tip, 4.5, edge_col, active)
		"daggers": _wp_daggers(grip, tip, edge_col, active)
		"polescythe": _wp_polescythe(grip, tip, edge_col, active)
		"chain": _wp_chain(grip, tip, edge_col, active)
		_: _wp_blade(grip, tip, 4.5, edge_col, active)

	# 활성 순간 칼끝 번쩍임
	if active:
		_draw_tip_glint(tip, fx, 0.82)


func _ease(t: float) -> float:
	return t * t * (3.0 - 2.0 * t)


func _wp_blade(grip: Vector2, tip: Vector2, w: float, edge_col: Color, active: bool) -> void:
	var axis := tip - grip
	if axis.length() < 14.0:
		return
	var dir := axis.normalized()
	var perp := Vector2(-dir.y, dir.x)
	var blade_base := grip + dir * 7.0
	var point_base := tip - dir * maxf(10.0, w * 2.4)

	# 먹 외곽 안에 강철 면을 채운 오각 칼몸. 양 변이 마지막 10px에서 한 점으로 수렴한다.
	var outer := PackedVector2Array([
		blade_base - perp * w * 0.95,
		point_base - perp * w * 0.46,
		tip,
		point_base + perp * w * 0.18,
		blade_base + perp * w * 0.60,
	])
	draw_polygon(outer, [UiKit.INK])
	var inner_base := blade_base + dir * 2.0
	var inner_tip := tip - dir * 1.6
	var steel := PackedVector2Array([
		inner_base - perp * w * 0.56,
		point_base - perp * w * 0.20,
		inner_tip,
		point_base + perp * w * 0.04,
		inner_base + perp * w * 0.28,
	])
	draw_polygon(steel, [Color(0.91, 0.90, 0.84)])

	# 칼등은 어둡고 날은 얇고 밝게 분리한다. 활성 시 날 끝만 주홍으로 달아오른다.
	draw_line(blade_base - perp * w * 0.72, point_base - perp * w * 0.36,
			Color(0.20, 0.19, 0.17), 1.4, true)
	var edge_start := blade_base.lerp(point_base, 0.56) + perp * w * 0.18
	draw_line(edge_start, inner_tip, edge_col if active else Color(0.98, 0.97, 0.92),
			2.0 if active else 1.2, true)

	# 손잡이와 가드는 칼몸과 분리해 실제 칼의 구조가 읽히게 한다.
	var handle_end := grip - dir * 15.0
	draw_line(handle_end, grip + dir * 3.0, UiKit.INK, w + 3.2, true)
	draw_line(handle_end + dir * 2.0, grip + dir * 1.0, Color(0.30, 0.20, 0.13), w, true)
	var guard_c := grip + dir * 4.0
	draw_line(guard_c - perp * (w + 4.0), guard_c + perp * (w + 4.0), UiKit.INK, 3.2, true)
	draw_circle(handle_end, 2.6, UiKit.INK)


func _wp_daggers(grip: Vector2, tip: Vector2, edge_col: Color, active: bool) -> void:
	var dir := (tip - grip)
	var perp := Vector2(-dir.y, dir.x).normalized()
	# 짧은 쌍단도 (사거리 짧음) — 두 자루 살짝 벌려
	var tip_a := grip + dir * 0.9 + perp * 6.0
	var tip_b := grip + dir * 0.78 - perp * 7.0
	_wp_blade(grip + perp * 2.5, tip_a, 3.2, edge_col, active)
	_wp_blade(grip - perp * 2.5, tip_b, 3.0, edge_col, active)


func _wp_polescythe(grip: Vector2, tip: Vector2, edge_col: Color, active: bool) -> void:
	# 긴 자루 + 끝의 굽은 낫날
	var pole_end := grip.lerp(tip, 0.80)
	draw_line(grip, pole_end, UiKit.INK, 6.5)
	draw_line(grip, pole_end, Color(0.30, 0.27, 0.23), 4.0)   # 나무 자루(먹톤)
	var dir := (tip - grip).normalized()
	var perp := Vector2(-dir.y, dir.x)
	# 낫날: pole_end에서 갈고리처럼 휘어 tip으로
	var hook := PackedVector2Array([
		pole_end, pole_end + perp * 26.0 - dir * 4.0,
		pole_end + perp * 30.0 + dir * 34.0, tip + perp * 4.0, tip])
	draw_polyline(hook, UiKit.INK, 7.0)
	draw_polyline(hook, UiKit.PAPER_LIGHT, 3.5)
	_draw_sharp_cap(tip, hook[3], 6.0, edge_col if active else UiKit.PAPER_LIGHT)
	if active:
		draw_polyline(hook.slice(2), edge_col, 3.0)


func _wp_chain(grip: Vector2, tip: Vector2, edge_col: Color, active: bool) -> void:
	# 사슬(연결 원) + 끝의 쇠구슬·낫
	var n := 9
	for k in range(1, n):
		var p := grip.lerp(tip, float(k) / n)
		p.y += sin(float(k) * 1.3 + float(world.s["tick"]) * 0.3) * (3.0 if not active else 1.0)
		draw_circle(p, 2.6, UiKit.INK)
	var ball := grip.lerp(tip, 0.86)
	draw_circle(ball, 8.0, UiKit.INK)
	draw_circle(ball + Vector2(-2, -2), 3.0, Color(UiKit.PAPER_LIGHT, 0.7))
	# 낫 갈고리
	var dir := (tip - grip).normalized()
	var perp := Vector2(-dir.y, dir.x)
	var hook := PackedVector2Array([tip - dir * 14.0, tip, tip + perp * 18.0 - dir * 6.0])
	draw_polyline(hook, UiKit.INK, 6.0)
	draw_polyline(hook, UiKit.PAPER_LIGHT, 2.8)
	_draw_sharp_cap(hook[2], hook[1], 5.0, edge_col if active else UiKit.PAPER_LIGHT)


func _draw_sharp_cap(point: Vector2, approach: Vector2, width: float, fill: Color) -> void:
	var axis := point - approach
	if axis.length_squared() < 0.01:
		return
	var dir := axis.normalized()
	var perp := Vector2(-dir.y, dir.x)
	var base := point - dir * maxf(8.0, width * 1.8)
	var outer := PackedVector2Array([base - perp * width * 0.72, point,
			base + perp * width * 0.72])
	draw_polygon(outer, [UiKit.INK])
	var inner := PackedVector2Array([base - perp * width * 0.34, point - dir * 1.2,
			base + perp * width * 0.28])
	draw_polygon(inner, [fill])


func _draw_tip_glint(tip: Vector2, facing: float, alpha: float) -> void:
	# 둥근 원 대신 교차하는 가는 선만 사용해 날카로운 종단을 보존한다.
	var c := Color(UiKit.PAPER_LIGHT, alpha)
	draw_line(tip - Vector2(5.0 * facing, 0), tip + Vector2(5.0 * facing, 0), c, 1.2, true)
	draw_line(tip - Vector2(0, 4.0), tip + Vector2(0, 4.0), c, 1.0, true)


func _weapon_angle() -> float:
	match _st:
		SimC.ST_ATTACK:
			if _mv.is_empty():
				return 35.0
			var su: int = _mv["su"]
			var act: int = _mv["act"]
			if _st_f <= su:
				return lerpf(35.0, -75.0, float(_st_f) / maxf(su, 1))
			elif _st_f <= su + act:
				return lerpf(-75.0, 18.0, float(_st_f - su) / maxf(act, 1))
			else:
				return lerpf(18.0, 35.0, minf(float(_st_f - su - act) / 10.0, 1.0))
		SimC.ST_BLOCKSTUN: return -85.0
		SimC.ST_HITSTUN, SimC.ST_GRABBED: return 70.0
		SimC.ST_WIN: return -80.0
		SimC.ST_RECOIL: return -30.0
		_: return 35.0


func _lean_deg() -> float:
	match _st:
		SimC.ST_WALK_F: return 4.0
		SimC.ST_WALK_B: return -4.0
		SimC.ST_ATTACK:
			return 10.0 if world.move_phase(idx) != "startup" else -3.0
		SimC.ST_AIR_ATTACK: return 12.0
		SimC.ST_HITSTUN: return -16.0
		SimC.ST_BLOCKSTUN: return -7.0
		SimC.ST_RECOIL: return -12.0
		SimC.ST_GRABBED: return -22.0
		SimC.ST_AIR_HIT: return -24.0
		SimC.ST_WIN: return -4.0
		SimC.ST_JUMP:
			# 상승 중 앞으로, 하강 중 뒤로 살짝
			var vy: int = world.s["p"][idx]["vy"]
			return -6.0 if vy < 0 else 5.0
		_: return 0.0
