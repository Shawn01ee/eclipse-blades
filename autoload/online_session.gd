extends Node
## WebSocket 방 연결과 결정론적 입력 큐를 화면 밖에서 유지한다.
## 서버는 전투 상태를 계산하지 않고 두 플레이어의 틱 입력만 검증·중계한다.

signal connection_changed(state: String)
signal room_changed
signal match_started
signal peer_left
signal network_error(message: String)
signal desync_detected(tick: int)

const PROTOCOL := 1
const INPUT_MASK := 1023
const ROOM_ALPHABET := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
const DEFAULT_RELAY_URL := ""

var relay_url := DEFAULT_RELAY_URL
var room_code := ""
var role := -1
var status := "idle"
var selections := [0, 1]
var ready_players := [false, false]
var peer_count := 0
var match_seed := 0
var ping_ms := -1

var _socket: WebSocketPeer = null
var _intentional_close := false
var _opened := false
var _ping_elapsed := 0.0
var _inputs := [{}, {}]


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var configured := String(ProjectSettings.get_setting("network/relay_url", DEFAULT_RELAY_URL))
	var env_url := OS.get_environment("ECLIPSE_RELAY_URL")
	relay_url = env_url if env_url != "" else configured


func _process(delta: float) -> void:
	if _socket == null:
		return
	_socket.poll()
	var ws_state := _socket.get_ready_state()
	if ws_state == WebSocketPeer.STATE_OPEN:
		if not _opened:
			_opened = true
			_set_status("connected")
		while _socket.get_available_packet_count() > 0:
			_receive_packet(_socket.get_packet().get_string_from_utf8())
		_ping_elapsed += delta
		if _ping_elapsed >= 2.0:
			_ping_elapsed = 0.0
			_send({"t": "ping", "n": Time.get_ticks_msec()})
	elif ws_state == WebSocketPeer.STATE_CLOSED:
		var was_intentional := _intentional_close
		_socket = null
		_opened = false
		role = -1
		peer_count = 0
		if not was_intentional:
			_set_status("disconnected")
			network_error.emit("온라인 서버와 연결이 끊겼습니다.")


func connect_room(raw_code: String) -> bool:
	var code := sanitize_room_code(raw_code)
	if code.length() != 6:
		network_error.emit("방 코드는 영문·숫자 6자리입니다.")
		return false
	if relay_url.strip_edges() == "":
		network_error.emit("온라인 서버 주소가 아직 설정되지 않았습니다.")
		return false
	disconnect_session()
	room_code = code
	role = -1
	peer_count = 0
	selections = [0, 1]
	ready_players = [false, false]
	match_seed = 0
	_inputs = [{}, {}]
	_socket = WebSocketPeer.new()
	_intentional_close = false
	_opened = false
	_ping_elapsed = 0.0
	_set_status("connecting")
	var url := relay_url.trim_suffix("/") + "/room/" + code + "?v=" + str(PROTOCOL)
	var err := _socket.connect_to_url(url)
	if err != OK:
		_socket = null
		_set_status("error")
		network_error.emit("온라인 서버에 연결할 수 없습니다. (%s)" % error_string(err))
		return false
	return true


func disconnect_session() -> void:
	_intentional_close = true
	if _socket != null:
		_socket.close(1000, "leaving")
	_socket = null
	_opened = false
	role = -1
	peer_count = 0
	_inputs = [{}, {}]
	_set_status("idle")


func choose_character(index: int) -> void:
	if role < 0:
		return
	selections[role] = index
	ready_players[role] = false
	_send({"t": "select", "c": index})
	room_changed.emit()


func set_ready(value: bool) -> void:
	if role < 0:
		return
	ready_players[role] = value
	_send({"t": "ready", "v": value})
	room_changed.emit()


func submit_input(tick: int, word: int) -> void:
	if role < 0 or status != "playing":
		return
	var clean_word := word & INPUT_MASK
	_inputs[role][tick] = clean_word
	_send({"t": "input", "k": tick, "w": clean_word})


func has_inputs(tick: int) -> bool:
	return _inputs[0].has(tick) and _inputs[1].has(tick)


func has_input(slot: int, tick: int) -> bool:
	return slot in [0, 1] and _inputs[slot].has(tick)


func get_input(slot: int, tick: int, default_value: int = 0) -> int:
	if not has_input(slot, tick):
		return default_value
	return int(_inputs[slot][tick])


func discard_inputs_before(tick: int) -> void:
	for slot in 2:
		for key in _inputs[slot].keys():
			if int(key) < tick:
				_inputs[slot].erase(key)


func take_inputs(tick: int) -> Array:
	if not has_inputs(tick):
		return []
	var pair := [int(_inputs[0][tick]), int(_inputs[1][tick])]
	_inputs[0].erase(tick)
	_inputs[1].erase(tick)
	return pair


func send_hash(tick: int, hash_value: int) -> void:
	_send({"t": "hash", "k": tick, "h": hash_value})


func begin_play() -> void:
	_inputs = [{}, {}]
	_set_status("playing")


func is_online_match() -> bool:
	return role >= 0 and status in ["starting", "playing"]


func _send(payload: Dictionary) -> void:
	if _socket != null and _socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_socket.send_text(JSON.stringify(payload))


func _receive_packet(text: String) -> void:
	var data = JSON.parse_string(text)
	if not (data is Dictionary):
		return
	match String(data.get("t", "")):
		"welcome":
			role = int(data.get("slot", -1))
			peer_count = int(data.get("peers", 1))
			_apply_room_state(data)
			_set_status("lobby")
			room_changed.emit()
		"peer_joined":
			peer_count = int(data.get("peers", 2))
			room_changed.emit()
		"select":
			var slot := int(data.get("slot", -1))
			if slot in [0, 1]:
				selections[slot] = int(data.get("c", selections[slot]))
				ready_players[slot] = false
				room_changed.emit()
		"ready":
			var slot := int(data.get("slot", -1))
			if slot in [0, 1]:
				ready_players[slot] = bool(data.get("v", false))
				room_changed.emit()
		"start":
			match_seed = int(data.get("seed", 1))
			var chars: Array = data.get("chars", [0, 1])
			if chars.size() == 2:
				selections = [int(chars[0]), int(chars[1])]
			_set_status("starting")
			match_started.emit()
		"input":
			var slot := int(data.get("slot", -1))
			var tick := int(data.get("k", -1))
			if slot in [0, 1] and tick >= 0:
				_inputs[slot][tick] = int(data.get("w", 0)) & INPUT_MASK
		"pong":
			ping_ms = maxi(Time.get_ticks_msec() - int(data.get("n", 0)), 0)
			room_changed.emit()
		"peer_left":
			peer_count = 1
			ready_players = [false, false]
			peer_left.emit()
			room_changed.emit()
		"desync":
			desync_detected.emit(int(data.get("k", -1)))
		"error":
			network_error.emit(String(data.get("message", "온라인 서버 오류")))


func _apply_room_state(data: Dictionary) -> void:
	var chars: Array = data.get("chars", [0, 1])
	var readies: Array = data.get("ready", [false, false])
	if chars.size() == 2:
		selections = [int(chars[0]), int(chars[1])]
	if readies.size() == 2:
		ready_players = [bool(readies[0]), bool(readies[1])]


func _set_status(value: String) -> void:
	if status == value:
		return
	status = value
	connection_changed.emit(status)


static func sanitize_room_code(raw: String) -> String:
	var out := ""
	for ch in raw.to_upper():
		if ROOM_ALPHABET.contains(ch):
			out += ch
		if out.length() == 6:
			break
	return out


static func make_room_code() -> String:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var out := ""
	for _i in 6:
		out += ROOM_ALPHABET[rng.randi_range(0, ROOM_ALPHABET.length() - 1)]
	return out
