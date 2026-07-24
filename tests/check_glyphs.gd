extends SceneTree
## 글자 깨짐(tofu) 검사: 코드/데이터의 UI 문자열에 쓰인 모든 비ASCII 글자가
## 번들 서브셋 폰트(NotoSansKR-Game.ttf)에 존재하는지 확인한다.
## 실행: godot --headless --path . --script res://tests/check_glyphs.gd

const FONT_PATH := "res://fonts/NotoSansKR-Game.ttf"


func _initialize() -> void:
	var font: FontFile = load(FONT_PATH)
	if font == null:
		push_error("폰트 로드 실패: " + FONT_PATH)
		quit(1)
		return

	var used := {}          # codepoint → 예시 문자열
	var files: Array = []
	_scan_dir("res://", files)
	for path in files:
		var fa := FileAccess.open(path, FileAccess.READ)
		if fa == null:
			continue
		var text := fa.get_as_text()
		# 문자열 리터럴("..." / '...')만 검사해 코드 식별자·주석 잡음을 줄인다.
		for lit in _string_literals(text):
			for cp in lit:
				var code: int = cp.unicode_at(0)
				if code >= 0x20 and code < 0x7F:
					continue          # ASCII는 폰트에 항상 있음
				if code == 0x0A or code == 0x09:
					continue
				if not used.has(code):
					used[code] = lit.strip_edges().substr(0, 24)

	var missing: Array = []
	for code in used:
		if not font.has_char(code):
			missing.append(code)
	missing.sort()

	print("=== 글자 깨짐 검사 ===")
	print("검사한 파일: ", files.size(), " / 고유 비ASCII 글자: ", used.size())
	if missing.is_empty():
		print("결과: 통과 — 모든 사용 글자가 폰트에 존재합니다.")
		quit(0)
	else:
		print("결과: 누락 ", missing.size(), "자 (tofu로 깨짐):")
		for code in missing:
			print("  U+%04X '%s'  (예: %s)" % [code, char(code), used[code]])
		quit(1)


func _string_literals(text: String) -> Array:
	var out: Array = []
	var n := text.length()
	var i := 0
	while i < n:
		var ch := text[i]
		if ch == "#":
			# 줄 주석 건너뛰기
			while i < n and text[i] != "\n":
				i += 1
		elif ch == "\"" or ch == "'":
			var quote := ch
			var start := i + 1
			i += 1
			while i < n and text[i] != quote:
				if text[i] == "\\":
					i += 1
				i += 1
			out.append(text.substr(start, i - start))
			i += 1
		else:
			i += 1
	return out


func _scan_dir(path: String, out: Array) -> void:
	var d := DirAccess.open(path)
	if d == null:
		return
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		if name.begins_with("."):
			name = d.get_next()
			continue
		var full := path.path_join(name)
		if d.current_is_dir():
			# 화면에 렌더되지 않는 디렉터리(테스트·도구·서버·빌드)는 제외한다.
			if name in ["build", "online-server", "node_modules", "tests", "fx"]:
				name = d.get_next()
				continue
			_scan_dir(full, out)
		elif name.ends_with(".gd") or name.ends_with(".tres"):
			out.append(full)
		name = d.get_next()
	d.list_dir_end()
