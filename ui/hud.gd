extends Control
## HUD: 체력·기력·사맥 3칸·라운드·타이머 (기획 원칙: 정보 최소화).

var world: CombatWorld
var names := ["", ""]
var weapons := ["", ""]

var _hp := [1000.0, 1000.0]
var _ghost := [1000.0, 1000.0]
var _max_hp := [1000.0, 1000.0]
var _nerve := [0, 0]
var _energy := [SimC.ENERGY_MAX, SimC.ENERGY_MAX]
var _wins := [0, 0]
var _timer := 60
var _combo := [0, 0]
var _combo_a := [0.0, 0.0]
var _move_name := ["", ""]
var _move_role := ["", ""]
var _move_kind := ["", ""]
var _move_a := [0.0, 0.0]

var timer_label: Label
var banner_label: Label
var banner_sub: Label
var _banner_t := 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	timer_label = UiKit.label("60", 46, UiKit.INK)
	timer_label.position = Vector2(608, 22)
	timer_label.custom_minimum_size = Vector2(64, 0)
	timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(timer_label)
	banner_label = UiKit.label("", 78, UiKit.INK)
	banner_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	banner_label.position = Vector2(0, 250)
	banner_label.size = Vector2(1280, 110)
	banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(banner_label)
	banner_sub = UiKit.label("", 26, UiKit.GRAY)
	banner_sub.position = Vector2(0, 370)
	banner_sub.size = Vector2(1280, 40)
	banner_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(banner_sub)


func setup(w: CombatWorld) -> void:
	world = w
	for i in 2:
		names[i] = w.chars[i]["name"]
		weapons[i] = w.chars[i]["weapon"]
		_max_hp[i] = float(w.chars[i]["hp"])
		_hp[i] = _max_hp[i]
		_ghost[i] = _max_hp[i]


func sync() -> void:
	for i in 2:
		_hp[i] = float(world.s["p"][i]["hp"])
		_nerve[i] = world.s["p"][i]["nerve"]
		_energy[i] = world.s["p"][i]["energy"]
		_combo[i] = world.s["p"][i]["combo"]
		if _combo[i] >= 2:
			_combo_a[i] = 1.5
	_wins = [world.s["wins"][0], world.s["wins"][1]]
	_timer = int(ceil(world.s["timer"] / 60.0))
	timer_label.text = str(clampi(_timer, 0, 99))
	queue_redraw()


func banner(text: String, sub: String = "", dur: float = 1.6, color: Color = UiKit.INK) -> void:
	banner_label.text = text
	banner_label.add_theme_color_override("font_color", color)
	banner_sub.text = sub
	_banner_t = dur


func move_callout(i: int, move_name: String, role: String, kind: String) -> void:
	if kind == "light" or kind == "air" or role == "":
		return
	_move_name[i] = move_name
	_move_role[i] = role
	_move_kind[i] = kind
	_move_a[i] = 1.15 if kind == "super" else 0.82


func _process(delta: float) -> void:
	for i in 2:
		_ghost[i] = maxf(lerpf(_ghost[i], _hp[i], delta * 3.0), _hp[i])
		_combo_a[i] = maxf(_combo_a[i] - delta, 0.0)
		_move_a[i] = maxf(_move_a[i] - delta, 0.0)
	if _banner_t > 0.0:
		_banner_t -= delta
		if _banner_t <= 0.0:
			banner_label.text = ""
			banner_sub.text = ""
	queue_redraw()


func _draw() -> void:
	var f := ThemeDB.fallback_font
	# 체력 바 (바깥에서 안으로 소모)
	_bar(Rect2(60, 38, 500, 26), _hp[0] / _max_hp[0], _ghost[0] / _max_hp[0], false)
	_bar(Rect2(720, 38, 500, 26), _hp[1] / _max_hp[1], _ghost[1] / _max_hp[1], true)
	_energy_bar(Rect2(60, 68, 180, 6), float(_energy[0]) / SimC.ENERGY_MAX, false)
	_energy_bar(Rect2(1040, 68, 180, 6), float(_energy[1]) / SimC.ENERGY_MAX, true)
	draw_string(f, Vector2(246, 76), "기력", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UiKit.GRAY)
	draw_string(f, Vector2(994, 76), "기력", HORIZONTAL_ALIGNMENT_RIGHT, 40, 12, UiKit.GRAY)
	draw_string(f, Vector2(62, 88), names[0] + " · " + weapons[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 18, UiKit.INK)
	draw_string(f, Vector2(1000, 88), names[1] + " · " + weapons[1], HORIZONTAL_ALIGNMENT_RIGHT, 218, 18, UiKit.INK)
	# 사맥 3칸 (마름모)
	for i in 2:
		for k in 3:
			var cx := 70.0 + k * 34.0 if i == 0 else 1210.0 - k * 34.0
			var c := Vector2(cx, 106)
			var pts := PackedVector2Array([c + Vector2(0, -9), c + Vector2(9, 0), c + Vector2(0, 9), c + Vector2(-9, 0)])
			if k < _nerve[i]:
				draw_polygon(pts, [UiKit.SEAL if _nerve[i] >= 3 else UiKit.INK])
			pts.append(pts[0])
			draw_polyline(pts, UiKit.INK, 1.5)
		if _nerve[i] >= SimC.NERVE_MAX:
			var ready_text := "Q / LB  오의" if i == 0 else "P / LB  오의"
			var ready_x := 178.0 if i == 0 else 802.0
			var ready_align := HORIZONTAL_ALIGNMENT_LEFT if i == 0 else HORIZONTAL_ALIGNMENT_RIGHT
			draw_string(f, Vector2(ready_x, 113), ready_text, ready_align, 300, 16, UiKit.SEAL)
	# 라운드 점
	for i in 2:
		for k in 2:
			var cx2 := 585.0 - k * 22.0 if i == 0 else 695.0 + k * 22.0
			var c2 := Vector2(cx2, 51)
			if k < _wins[i]:
				draw_circle(c2, 7.0, UiKit.SEAL)
			draw_arc(c2, 7.0, 0, TAU, 24, UiKit.INK, 1.5)
	# 콤보
	for i in 2:
		if _combo_a[i] > 0.0 and _combo[i] >= 2:
			var a := minf(_combo_a[i], 1.0)
			var x := 80.0 if i == 1 else 1050.0
			draw_string(f, Vector2(x, 170), str(_combo[i]) + " 연격", HORIZONTAL_ALIGNMENT_LEFT, -1, 34, Color(UiKit.SEAL, a))
	# 중·강·고유 기술의 이름과 용도를 짧게 보여 입력 차이를 학습시킨다.
	for i in 2:
		if _move_a[i] <= 0.0:
			continue
		var ma := minf(_move_a[i] * 1.8, 1.0)
		var mx := 62.0 if i == 0 else 718.0
		var align := HORIZONTAL_ALIGNMENT_LEFT if i == 0 else HORIZONTAL_ALIGNMENT_RIGHT
		var col := UiKit.SEAL if _move_kind[i] == "heavy" or _move_kind[i] == "super" else UiKit.INK
		draw_string(f, Vector2(mx, 148), _move_name[i], align, 500, 20, Color(col, ma))
		draw_string(f, Vector2(mx, 170), _move_role[i], align, 500, 14, Color(UiKit.GRAY, ma))
	# 배너 띠
	if banner_label.text != "":
		draw_rect(Rect2(240, 255, 800, 104), Color(UiKit.PAPER_LIGHT, 0.75))
		draw_rect(Rect2(240, 255, 800, 3), UiKit.INK)
		draw_rect(Rect2(240, 356, 800, 3), UiKit.INK)


func _bar(r: Rect2, ratio: float, ghost: float, mirror: bool) -> void:
	draw_rect(r.grow(3), UiKit.PAPER_LIGHT)
	draw_rect(r.grow(3), UiKit.INK, false, 2.5)
	var gw := r.size.x * clampf(ghost, 0, 1)
	var w := r.size.x * clampf(ratio, 0, 1)
	if mirror:
		draw_rect(Rect2(r.position.x, r.position.y, gw, r.size.y), UiKit.GRAY)
		draw_rect(Rect2(r.position.x, r.position.y, w, r.size.y), UiKit.INK)
	else:
		draw_rect(Rect2(r.end.x - gw, r.position.y, gw, r.size.y), UiKit.GRAY)
		draw_rect(Rect2(r.end.x - w, r.position.y, w, r.size.y), UiKit.INK)


func _energy_bar(r: Rect2, ratio: float, mirror: bool) -> void:
	draw_rect(r, Color(UiKit.GRAY, 0.28))
	var w := r.size.x * clampf(ratio, 0.0, 1.0)
	var x := r.end.x - w if mirror else r.position.x
	draw_rect(Rect2(x, r.position.y, w, r.size.y), UiKit.SEAL)
	draw_rect(r.grow(1), UiKit.INK, false, 1.0)
