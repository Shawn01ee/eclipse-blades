extends Node
## 이벤트 이름 → 사운드 재생. 파일이 없어도 경고 로그 후 무음 진행 (AC-10).

const EVENT_FILES := {
	"hit_l": "res://fx/audio/hit_l.wav",
	"hit_m": "res://fx/audio/hit_m.wav",
	"hit_h": "res://fx/audio/hit_h.wav",
	"block": "res://fx/audio/block.wav",
	"parry": "res://fx/audio/parry.wav",
	"clash": "res://fx/audio/clash.wav",
	"whiff": "res://fx/audio/whiff.wav",
	"swing_arin": "res://fx/audio/swing_arin.wav",
	"swing_daeru": "res://fx/audio/swing_daeru.wav",
	"swing_han": "res://fx/audio/swing_han.wav",
	"swing_myo": "res://fx/audio/swing_myo.wav",
	"swing_mujin": "res://fx/audio/swing_mujin.wav",
	"grab": "res://fx/audio/grab.wav",
	"ko": "res://fx/audio/ko.wav",
	"super": "res://fx/audio/super.wav",
	"nerve": "res://fx/audio/nerve.wav",
	"round": "res://fx/audio/round.wav",
	"ui_move": "res://fx/audio/ui_move.wav",
	"ui_ok": "res://fx/audio/ui_ok.wav",
}
const BGM_FILES := {
	"menu": "res://fx/audio/bgm.wav",
	"battle": "res://fx/audio/battle_bgm.wav",
	"danger": "res://fx/audio/battle_danger.wav",
}
const BGM_CROSSFADE := 0.45
const POOL_SIZE := 10

var _streams := {}
var _warned := {}
var _pool: Array = []
var _pool_i := 0
var _bgm_warned := {}
var _bgm_streams := {}
var _bgm_players: Array = []
var _bgm_mode := ""
var _bgm_active := -1
var _bgm_fade_from := -1
var _bgm_fade_t := 1.0


func _ready() -> void:
	for ev in EVENT_FILES:
		var path: String = EVENT_FILES[ev]
		if ResourceLoader.exists(path):
			_streams[ev] = load(path)
	for k in POOL_SIZE:
		var pl := AudioStreamPlayer.new()
		add_child(pl)
		_pool.append(pl)
	# 웹에서는 경기 도중 WAV를 처음 읽고 복제하면 같은 메인 스레드의 렌더와
	# 오디오 공급이 함께 밀린다. 로딩 화면이 남아 있을 때 세 곡을 한 번만 준비한다.
	if DisplayServer.get_name() != "headless" and OS.get_environment("ECLIPSE_SHOT") == "":
		for mode in BGM_FILES:
			_bgm_stream(mode)


func play(ev: String, pitch: float = 1.0, gain_scale: float = 1.0) -> void:
	if not _streams.has(ev):
		if not _warned.has(ev):
			_warned[ev] = true
			push_warning("사운드 없음(%s) — 무음 대체 (AC-10)" % ev)
		return
	var pl: AudioStreamPlayer = _pool[_pool_i]
	_pool_i = (_pool_i + 1) % POOL_SIZE
	pl.stream = _streams[ev]
	var gain: float = SettingsManager.sfx_gain() * gain_scale
	pl.volume_db = linear_to_db(maxf(gain, 0.001))
	pl.pitch_scale = pitch
	pl.play()


## 활성 판정과 동시에 무기 고유의 휘두름을 재생한다. 등급은 피치·무게로 구분한다.
func play_weapon_swing(char_id: String, kind: String, move_key: String = "") -> void:
	var ev := "swing_" + char_id
	var pitch: float = {"light": 1.18, "medium": 1.02, "heavy": 0.84,
			"tech": 1.08, "air": 0.96, "super": 0.76}.get(kind, 1.0)
	var gain: float = {"light": 0.58, "medium": 0.72, "heavy": 0.90,
			"tech": 0.80, "air": 0.70, "super": 1.0}.get(kind, 0.72)
	if move_key.begins_with("motion_"):
		pitch *= 0.93
		gain = minf(gain + 0.10, 1.0)
	play(ev, pitch, gain)


func _ensure_bgm_players() -> void:
	if not _bgm_players.is_empty():
		return
	for i in 2:
		var pl := AudioStreamPlayer.new()
		pl.volume_db = -80.0
		add_child(pl)
		_bgm_players.append(pl)


func _bgm_stream(mode: String):
	if _bgm_streams.has(mode):
		return _bgm_streams[mode]
	var path: String = BGM_FILES.get(mode, "")
	if path == "" or not ResourceLoader.exists(path):
		if not _bgm_warned.has(mode):
			_bgm_warned[mode] = true
			push_warning("BGM 없음(%s) — 무음 진행 (AC-10)" % mode)
		return null
	var stream = load(path)
	# 공유 리소스의 loop 값을 건드리지 않도록 플레이어별 복제본을 사용한다.
	if stream is AudioStreamWAV:
		stream = stream.duplicate()
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = stream.data.size() / 2   # 16bit mono
	_bgm_streams[mode] = stream
	return stream


func play_bgm(mode: String = "menu") -> void:
	if DisplayServer.get_name() == "headless" or OS.get_environment("ECLIPSE_SHOT") != "":
		return
	if not BGM_FILES.has(mode):
		mode = "menu"
	if _bgm_mode == mode and _bgm_active >= 0:
		return
	var stream = _bgm_stream(mode)
	if stream == null:
		return
	_ensure_bgm_players()
	var target := 0 if _bgm_active < 0 else 1 - _bgm_active
	var target_player: AudioStreamPlayer = _bgm_players[target]
	target_player.stop()
	target_player.stream = stream
	target_player.volume_db = -80.0
	var keep_phase: bool = _bgm_mode in ["battle", "danger"] and mode in ["battle", "danger"]
	var start_at := 0.0
	if keep_phase and _bgm_active >= 0:
		start_at = _bgm_players[_bgm_active].get_playback_position()
	target_player.play(start_at)
	if _bgm_active < 0:
		_bgm_active = target
		_bgm_fade_from = -1
		_bgm_fade_t = 1.0
	else:
		_bgm_fade_from = _bgm_active
		_bgm_active = target
		_bgm_fade_t = 0.0
	_bgm_mode = mode


func stop_bgm() -> void:
	for pl in _bgm_players:
		if is_instance_valid(pl):
			pl.stop()
			pl.stream = null
			pl.free()
	_bgm_players.clear()
	_bgm_mode = ""
	_bgm_active = -1
	_bgm_fade_from = -1
	_bgm_fade_t = 1.0


func stop_all() -> void:
	stop_bgm()
	for pl in _pool:
		if is_instance_valid(pl):
			pl.stop()
			pl.stream = null
	_streams.clear()
	_bgm_streams.clear()


func _process(dt: float) -> void:
	if _bgm_active < 0 or _bgm_players.is_empty():
		return
	# 동일 박자의 전투/위기 트랙을 짧게 교차시켜 악구가 끊기지 않게 한다.
	var gain := SettingsManager.bgm_gain() * 0.8
	if _bgm_fade_from >= 0:
		_bgm_fade_t = minf(_bgm_fade_t + dt / BGM_CROSSFADE, 1.0)
		var fade_in := sqrt(_bgm_fade_t)
		var fade_out := sqrt(1.0 - _bgm_fade_t)
		_bgm_players[_bgm_active].volume_db = linear_to_db(maxf(gain * fade_in, 0.0001))
		_bgm_players[_bgm_fade_from].volume_db = linear_to_db(maxf(gain * fade_out, 0.0001))
		if _bgm_fade_t >= 1.0:
			_bgm_players[_bgm_fade_from].stop()
			_bgm_players[_bgm_fade_from].stream = null
			_bgm_fade_from = -1
	else:
		_bgm_players[_bgm_active].volume_db = linear_to_db(maxf(gain, 0.0001))


func _exit_tree() -> void:
	# 실행 종료 시 재생 핸들이 WAV 리소스를 붙잡지 않도록 명시적으로 분리한다.
	stop_all()
	for pl in _pool:
		if is_instance_valid(pl):
			pl.stop()
			pl.stream = null
	_pool.clear()
