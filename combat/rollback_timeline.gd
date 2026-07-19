class_name RollbackTimeline
extends RefCounted
## 온라인 입력을 즉시 시뮬하고, 늦게 도착한 상대 입력만 짧게 되감아 보정한다.

const MAX_PREDICTION := 8
const INPUT_DELAY := 2
const HISTORY_TICKS := 120
const HASH_INTERVAL := 120
const DIRECTION_MASK := SimC.B_LEFT | SimC.B_RIGHT | SimC.B_UP | SimC.B_DOWN

var world: CombatWorld
var local_slot := 0
var current_tick := 0
var confirmed_through := -1

var _snapshots := {}
var _used_inputs := {}
var _event_keys := {}
var _checkpoint_hashes := {}
var _next_hash_tick := HASH_INTERVAL
var _next_local_tick := 0


func _init(world_ref: CombatWorld, slot: int) -> void:
	world = world_ref
	local_slot = clampi(slot, 0, 1)


## 한 렌더 틱의 로컬 입력을 전송하고, 가능한 경우 즉시 한 틱 전진한다.
func frame(local_word: int, channel: Object) -> Dictionary:
	# 같은 틱을 보내고 즉시 예측하던 방식은 왕복 60ms에서도 공격 입력마다
	# 2~4틱 재연산을 만들었다. 두 틱 앞 입력을 미리 보내 짧은 입력 지연으로
	# 대부분의 롤백을 피한다. 첫 프레임의 앞 두 틱은 중립 입력이다.
	var send_through := current_tick + INPUT_DELAY
	while _next_local_tick <= send_through:
		var word := local_word if _next_local_tick == send_through else 0
		channel.submit_input(_next_local_tick, word)
		_next_local_tick += 1
	var result := sync(channel)
	result["stepped"] = false
	if current_tick > confirmed_through + MAX_PREDICTION:
		return result

	_snapshots[current_tick] = world.snapshot()
	var pair := _pair_for_tick(current_tick, channel)
	var events := world.step(int(pair[0]), int(pair[1]))
	_used_inputs[current_tick] = pair
	_event_keys[current_tick] = _keys_for(events)
	result["events"].append_array(events)
	result["record_updates"].append([current_tick, pair])
	current_tick += 1
	result["stepped"] = true
	_store_checkpoint()
	_prune(channel)
	return result


func needs_local_input(channel: Object) -> bool:
	return _next_local_tick <= current_tick + INPUT_DELAY


## 새 원격 입력만 반영한다. 테스트와 일시적인 렌더 정지 뒤 재동기화에도 사용한다.
func sync(channel: Object) -> Dictionary:
	var result := {
		"events": [],
		"record_updates": [],
		"hashes": [],
		"corrected_ticks": 0,
	}
	# 확정 구간은 순서대로만 늘어난다(WebSocket도 메시지 순서를 보장).
	# 이미 확인한 120틱 전체를 매 프레임 다시 훑지 않고 새 확정분만 비교한다.
	var previous_confirmed := confirmed_through
	_advance_confirmed(channel)
	var earliest := _first_mismatch(channel, previous_confirmed + 1, confirmed_through + 1)
	if earliest >= 0:
		var replay_end := current_tick
		world.restore(_snapshots[earliest])
		for tick in range(earliest, replay_end):
			_snapshots[tick] = world.snapshot()
			var pair := _pair_for_tick(tick, channel)
			var old_keys: Array = _event_keys.get(tick, [])
			var events := world.step(int(pair[0]), int(pair[1]))
			var new_keys := _keys_for(events)
			for i in events.size():
				if not old_keys.has(new_keys[i]):
					result["events"].append(events[i])
			_used_inputs[tick] = pair
			_event_keys[tick] = new_keys
			result["record_updates"].append([tick, pair])
			result["corrected_ticks"] += 1
			_store_checkpoint(tick + 1)

	while _next_hash_tick <= confirmed_through + 1:
		if _checkpoint_hashes.has(_next_hash_tick):
			result["hashes"].append([_next_hash_tick, int(_checkpoint_hashes[_next_hash_tick])])
		_next_hash_tick += HASH_INTERVAL
	return result


func is_current_state_confirmed() -> bool:
	return current_tick == 0 or confirmed_through >= current_tick - 1


func used_pair(tick: int) -> Array:
	return _used_inputs.get(tick, [])


func _first_mismatch(channel: Object, from_tick: int, to_tick: int) -> int:
	var remote_slot := 1 - local_slot
	for tick in range(maxi(0, from_tick), mini(current_tick, to_tick)):
		if not channel.has_input(remote_slot, tick):
			continue
		var used: Array = _used_inputs.get(tick, [])
		if used.size() == 2 and int(used[remote_slot]) != channel.get_input(remote_slot, tick, 0):
			return tick
	return -1


func _pair_for_tick(tick: int, channel: Object) -> Array:
	var remote_slot := 1 - local_slot
	var local_word: int = channel.get_input(local_slot, tick, 0)
	var remote_word: int
	if channel.has_input(remote_slot, tick):
		remote_word = channel.get_input(remote_slot, tick, 0)
	else:
		remote_word = _predict_remote_direction(tick, channel)
	return [local_word, remote_word] if local_slot == 0 else [remote_word, local_word]


func _predict_remote_direction(tick: int, channel: Object) -> int:
	var remote_slot := 1 - local_slot
	for previous in range(tick - 1, maxi(-1, tick - HISTORY_TICKS), -1):
		if channel.has_input(remote_slot, previous):
			return channel.get_input(remote_slot, previous, 0) & DIRECTION_MASK
	return 0


func _advance_confirmed(channel: Object) -> void:
	while channel.has_input(0, confirmed_through + 1) and channel.has_input(1, confirmed_through + 1):
		confirmed_through += 1


func _store_checkpoint(completed_ticks: int = current_tick) -> void:
	if completed_ticks > 0 and completed_ticks % HASH_INTERVAL == 0:
		_checkpoint_hashes[completed_ticks] = world.state_hash()


func _prune(channel: Object) -> void:
	var before := current_tick - HISTORY_TICKS
	if before <= 0:
		return
	_snapshots.erase(before - 1)
	_used_inputs.erase(before - 1)
	_event_keys.erase(before - 1)
	channel.discard_inputs_before(before)


func _keys_for(events: Array) -> Array:
	var keys: Array = []
	for i in events.size():
		var event: Dictionary = events[i]
		keys.append("%d:%s:%s:%s:%s" % [i, event.get("t", ""), event.get("p", ""),
				event.get("id", ""), event.get("kind", "")])
	return keys
