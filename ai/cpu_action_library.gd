class_name CpuActionLibrary
extends RefCounted
## CPU가 선택한 의미 행동을 결정론적인 프레임별 입력 열로 변환한다.

enum Action {
	IDLE,
	APPROACH,
	RETREAT,
	JUMP_IN,
	LIGHT,
	MEDIUM,
	HEAVY,
	TECH,
	GRAB,
	SUPER,
	MOTION_LIGHT,
	MOTION_MEDIUM,
	MOTION_HEAVY,
}


static func direction_word(relative_direction: int, facing: int) -> int:
	if relative_direction == 0:
		return 0
	var absolute_direction := relative_direction * facing
	return SimC.B_RIGHT if absolute_direction > 0 else SimC.B_LEFT


## 한 행동을 틱마다 하나씩 소비할 입력 워드 배열로 만든다.
## facing은 월드 절대방향(-1=왼쪽, 1=오른쪽)이다.
static func frames(action: int, facing: int) -> Array:
	var fwd := direction_word(1, facing)
	var back := direction_word(-1, facing)
	match action:
		Action.APPROACH:
			return [fwd]
		Action.RETREAT:
			return [back]
		Action.JUMP_IN:
			# 도약 준비가 끝날 때까지 접근 방향을 유지해 행동이 재판단으로 끊기지 않게 한다.
			return [SimC.B_UP | fwd, fwd, fwd, fwd, fwd, fwd]
		Action.LIGHT:
			return [SimC.B_L]
		Action.MEDIUM:
			return [SimC.B_M]
		Action.HEAVY:
			return [SimC.B_H]
		Action.TECH:
			return [SimC.B_T]
		Action.GRAB:
			return [fwd | SimC.B_M]
		Action.SUPER:
			return [SimC.B_SUPER]
		Action.MOTION_LIGHT:
			return [SimC.B_DOWN, SimC.B_DOWN | fwd, fwd, fwd | SimC.B_L]
		Action.MOTION_MEDIUM:
			return [SimC.B_DOWN, SimC.B_DOWN | fwd, fwd, fwd | SimC.B_M]
		Action.MOTION_HEAVY:
			return [SimC.B_DOWN, SimC.B_DOWN | fwd, fwd, fwd | SimC.B_H]
		_:
			return [0]
