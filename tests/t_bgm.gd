extends RefCounted
## 메뉴/전투/위기 BGM 자산과 동기 전환 전제 검증.

const BGM_PATHS := {
	"menu": "res://fx/audio/bgm.wav",
	"battle": "res://fx/audio/battle_bgm.wav",
	"danger": "res://fx/audio/battle_danger.wav",
}


static func run(t, _args: Dictionary) -> void:
	t.suite("상황 적응형 전투 BGM")
	for mode in ["menu", "battle", "danger"]:
		var path: String = BGM_PATHS[mode]
		var stream = load(path)
		t.ok(stream is AudioStreamWAV and stream.mix_rate == 44100 \
				and stream.get_length() > 20.0, "%s BGM 44.1kHz·20초 이상" % mode)
	var battle: AudioStreamWAV = load(BGM_PATHS["battle"])
	var danger: AudioStreamWAV = load(BGM_PATHS["danger"])
	t.ok(absf(battle.get_length() - danger.get_length()) < 0.01,
			"전투/위기 트랙 길이 일치로 박자 위치 유지")
	t.ok(BGM_PATHS["menu"] != BGM_PATHS["battle"],
			"메뉴와 전투 음악 자산 분리")
	var source := FileAccess.get_file_as_string("res://autoload/audio_manager.gd")
	t.ok(source.contains("if _bgm_streams.has(mode):"),
			"전투 중 BGM을 다시 읽거나 복제하지 않도록 캐시 사용")
