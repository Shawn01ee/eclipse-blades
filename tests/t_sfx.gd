extends RefCounted
## 6인 무기별 휘두름 효과음 자산과 이벤트 등록 검증.

const SWING_PATHS := {
	"arin": "res://fx/audio/swing_arin.wav",
	"daeru": "res://fx/audio/swing_daeru.wav",
	"han": "res://fx/audio/swing_han.wav",
	"myo": "res://fx/audio/swing_myo.wav",
	"mujin": "res://fx/audio/swing_mujin.wav",
	"jiko": "res://fx/audio/swing_jiko.wav",
}


static func run(t, _args: Dictionary) -> void:
	t.suite("캐릭터별 무기 휘두름 효과음")
	for fighter_id in SWING_PATHS:
		var stream = load(SWING_PATHS[fighter_id])
		var valid: bool = stream is AudioStreamWAV and stream.mix_rate == 44100 \
				and stream.get_length() >= 0.20 and stream.get_length() <= 0.50
		t.ok(valid, fighter_id + " 휘두름 WAV 44.1kHz·적정 길이")
	var source_file := FileAccess.open("res://autoload/audio_manager.gd", FileAccess.READ)
	var source := source_file.get_as_text() if source_file != null else ""
	var registered: bool = source != ""
	for fighter_id in SWING_PATHS:
		registered = registered and source.contains('"swing_%s": "%s"' % [fighter_id, SWING_PATHS[fighter_id]])
	t.ok(registered, "6인 휘두름 이벤트가 오디오 풀에 등록됨")
