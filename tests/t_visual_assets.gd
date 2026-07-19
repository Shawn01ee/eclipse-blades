extends RefCounted
## 전투 포즈 아틀라스가 네 캐릭터 모두 존재하고 투명 배경으로 읽히는지 검증한다.


static func run(t, _args: Dictionary) -> void:
	t.suite("전투 포즈 아틀라스")
	var jiko_portrait := Image.load_from_file(
			ProjectSettings.globalize_path("res://art/portraits/Jiko.png"))
	t.ok(jiko_portrait != null and jiko_portrait.get_width() >= 1000 \
			and jiko_portrait.get_height() >= 1000, "지코 선택 화면 일러스트 로드")
	for fighter_id in ["arin", "daeru", "han", "myo"]:
		var path := ProjectSettings.globalize_path("res://art/combat_atlas/%s.png" % fighter_id)
		var img := Image.load_from_file(path)
		var valid := img != null and img.get_width() >= 1500 and img.get_height() >= 900
		if valid:
			valid = img.get_pixel(0, 0).a < 0.05 \
					and img.get_pixel(img.get_width() - 1, img.get_height() - 1).a < 0.05
		t.ok(valid, fighter_id + " 4×2 투명 전투 아틀라스 로드")
