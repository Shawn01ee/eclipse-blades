class_name Registry
## 캐릭터 로스터 로더. 시뮬이 Resource 객체를 직접 만지지 않도록
## MoveData/FighterData를 순수 int/String Dictionary로 변환해 넘긴다.

const FIGHTER_PATHS := [
	"res://data/fighters/arin.tres",
	"res://data/fighters/daeru.tres",
	"res://data/fighters/han.tres",
	"res://data/fighters/myo.tres",
	"res://data/fighters/mujin.tres",
	"res://data/fighters/jiko.tres",
]

const SLOT_BUTTON := {
	"light": SimC.B_L, "medium": SimC.B_M, "heavy": SimC.B_H, "tech": SimC.B_T,
}

const EXTRA_SLOT_KIND := {
	"motion_light": "light", "motion_medium": "medium", "motion_heavy": "heavy",
	"motion_nerve": "heavy",
}


static func load_all() -> Array:
	var out: Array = []
	for p in FIGHTER_PATHS:
		var fd: FighterData = load(p)
		assert(fd != null, "파이터 데이터 로드 실패: " + p)
		out.append(fd)
	return out


## FighterData → 시뮬용 순수 데이터 딕셔너리
static func bake(fd: FighterData) -> Dictionary:
	var moves := {}
	var by_id := {}
	var slots: Array = fd.moves.keys()
	slots.sort()
	for slot in slots:
		var mv: MoveData = fd.moves.get(slot)
		if mv == null:
			continue
		var edge_dmg := mv.edge_damage
		if edge_dmg < 0:
			edge_dmg = SimC.edge_damage_of(mv.damage)
		var baked := {
			"id": mv.id, "slot": EXTRA_SLOT_KIND.get(slot, slot), "move_key": slot,
			"name": mv.display_name, "role": mv.role_note,
			"su": mv.startup_frames, "act": mv.active_frames, "rec": mv.recovery_frames,
			"total": mv.startup_frames + mv.active_frames + mv.recovery_frames,
			"dmg": mv.damage, "dmg_edge": edge_dmg, "chip": mv.chip_damage,
			"prio": mv.priority,
			"stop": mv.hitstop, "stop_edge": mv.hitstop_edge,
			"hitstun": mv.hitstun, "blockstun": mv.blockstun,
			"push_hit": mv.pushback_hit * SimC.FP, "push_block": mv.pushback_block * SimC.FP,
			"meter_cost": mv.meter_cost, "energy_cost": mv.energy_cost,
			"cancels": mv.cancel_windows,
			"boxes": mv.hitboxes_by_frame,
			"motion": mv.motion_frames,
			"edge": mv.edge_enabled,
			"grab": mv.is_grab, "grab_range": mv.grab_range * SimC.FP,
			"unblockable": mv.unblockable,
			"sfx": mv.sound_event, "vfx": mv.vfx_event, "cam": mv.camera_event,
		}
		moves[slot] = baked
		by_id[mv.id] = baked
	return {
		"id": fd.id, "name": fd.display_name, "weapon": fd.weapon_name,
		"hp": fd.max_hp, "walk_f": fd.walk_f, "walk_b": fd.walk_b,
		"push_hw": fd.pushbox_hw * SimC.FP,
		"hurt_hw": fd.hurtbox_hw * SimC.FP, "hurt_h": fd.hurtbox_h * SimC.FP,
		"edge_pct": fd.edge_ratio_pct,
		"moves": moves, "moves_by_id": by_id,
	}
