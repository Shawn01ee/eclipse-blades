extends Control
## 훈련 오버레이: 판정 박스 / 프레임 정보 / 입력 히스토리 / 더미 모드 표시.

var world: CombatWorld
var show_boxes := false
var show_frames := false
var dummy_mode := 0
var history: Array = []          # [[w1, w2], ...] match_screen이 채움
var last_adv := 0
var replay_note := ""

const DUMMY_NAMES := ["서기", "전부 가드", "정밀 가드 시도", "CPU"]


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func sync() -> void:
	queue_redraw()


func _draw() -> void:
	if world == null:
		return
	var f := ThemeDB.fallback_font
	# 어두운 지면 위에서도 도움말과 입력 히스토리가 읽히도록 화지 띠를 둔다.
	draw_rect(Rect2(0, 615, 1280, 105), Color(UiKit.PAPER_LIGHT, 0.88))
	draw_line(Vector2(0, 615), Vector2(1280, 615), Color(UiKit.INK, 0.35), 1.0)
	if show_boxes:
		for i in 2:
			var d := world.debug_boxes(i)
			_rect_fp(d["push"], Color(UiKit.GRAY, 0.0), Color(UiKit.GRAY, 0.9))
			_rect_fp(d["hurt"], Color(0.25, 0.5, 0.3, 0.22), Color(0.2, 0.45, 0.25, 0.9))
			for r in d["weapon"]:
				_rect_fp(r, Color(UiKit.INK, 0.35), UiKit.INK)
			for r in d["edge"]:
				_rect_fp(r, Color(UiKit.SEAL, 0.5), UiKit.SEAL)
	if show_frames:
		var y := 200.0
		for i in 2:
			var p: Dictionary = world.s["p"][i]
			var line := "P%d %s" % [i + 1, world.state_name(i)]
			if p["state"] == SimC.ST_ATTACK or p["state"] == SimC.ST_AIR_ATTACK:
				var mv: Dictionary = world.chars[i]["moves_by_id"][p["move"]]
				line += " %s f%d/%d (%s) 발%d 활%d 후%d" % [p["move"], p["st_f"], mv["total"],
					world.move_phase(i), mv["su"], mv["act"], mv["rec"]]
			draw_string(f, Vector2(70, y), line, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, UiKit.INK)
			y += 24.0
		var gap: int = absi(world.s["p"][0]["x"] - world.s["p"][1]["x"]) / SimC.FP
		draw_string(f, Vector2(70, y), "거리 %dpx · 최근 이득 %+d" % [gap, last_adv],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 16, UiKit.INK)
	# 입력 히스토리 (최근 14개, 변화 시점만)
	_history_strip(f, 0, 700.0)
	_history_strip(f, 1, 668.0)
	var help := "1 리셋 · 2 판정 박스 · 3 프레임 · 4 더미(%s) · 5 리플레이 저장 · 6 재생" % DUMMY_NAMES[dummy_mode]
	if replay_note != "":
		help = replay_note + " · " + help
	draw_string(f, Vector2(70, 640), help, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(UiKit.INK, 0.75))


func _history_strip(f: Font, pi: int, y: float) -> void:
	if history.is_empty():
		return
	var entries: Array = []
	var prev := -1
	for k in range(maxi(history.size() - 240, 0), history.size()):
		var w: int = history[k][pi]
		if w != prev:
			entries.append(w)
			prev = w
	var x := 70.0
	var start := maxi(entries.size() - 14, 0)
	for k in range(start, entries.size()):
		var w2: int = entries[k]
		if w2 == 0:
			continue
		draw_string(f, Vector2(x, y), _glyph(w2), HORIZONTAL_ALIGNMENT_LEFT, -1, 16,
			Color(UiKit.INK, 0.45 + 0.55 * float(k - start) / 14.0))
		x += 74.0


func _glyph(w: int) -> String:
	var s := ""
	if w & SimC.B_LEFT:
		s += "◀"
	if w & SimC.B_RIGHT:
		s += "▶"
	if w & SimC.B_DOWN:
		s += "▼"
	if w & SimC.B_UP:
		s += "▲"
	if w & SimC.B_L:
		s += "약"
	if w & SimC.B_M:
		s += "중"
	if w & SimC.B_H:
		s += "강"
	if w & SimC.B_T:
		s += "기"
	if w & SimC.B_SUPER:
		s += "오의"
	return s


func _rect_fp(r: Array, fill: Color, line: Color) -> void:
	var rr := Rect2(640.0 + r[0] / 1000.0, 620.0 - r[3] / 1000.0,
		(r[2] - r[0]) / 1000.0, (r[3] - r[1]) / 1000.0)
	if fill.a > 0.01:
		draw_rect(rr, fill)
	draw_rect(rr, line, false, 1.5)
