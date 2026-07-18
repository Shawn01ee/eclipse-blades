extends RefCounted
## 전체 스크립트/리소스/씬 로드 검사 — 파스 오류를 헤드리스에서 잡는다.

static func run(t, _args: Dictionary) -> void:
	t.suite("전체 리소스 로드")
	var files: Array = []
	_scan("res://", files)
	var loaded := 0
	for f in files:
		var res = load(f)
		if res == null:
			t.ok(false, "로드 실패: " + f)
		elif res is Script and not res.can_instantiate():
			t.ok(false, "스크립트 컴파일 실패: " + f)
		else:
			loaded += 1
	t.ok(loaded > 0, "리소스 " + str(loaded) + "개 로드")


static func _scan(path: String, out: Array) -> void:
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
			_scan(full, out)
		elif name.ends_with(".gd") or name.ends_with(".tres") or name.ends_with(".tscn"):
			out.append(full)
		name = d.get_next()
	d.list_dir_end()
