extends Control
## 경기 화면: 시뮬 구동(60TPS) + 뷰 동기화 + 이벤트 연출 + 훈련/일시정지/결과.
## 렌더 FPS와 무관하게 _physics_process(60틱)에서만 시뮬을 진행한다 (AC-01).

const FighterView := preload("res://ui/fighter_view.gd")
const StageView := preload("res://ui/stage_view.gd")
const FxLayer := preload("res://ui/fx_layer.gd")
const Hud := preload("res://ui/hud.gd")
const Overlay := preload("res://ui/training_overlay.gd")
const TouchControls := preload("res://ui/touch_controls.gd")

var world: CombatWorld
var match_seed := 1
var brain: CpuBrain = null
var scene_root: Node2D
var views: Array = []
var fx
var hud
var overlay
var touch = null
var pause_panel: PanelContainer = null
var results_panel: PanelContainer = null

var recording: Array = []
var replay_mode := false
var replay_words: Array = []
var replay_i := 0

var dummy_mode := 0
var neutral_ticks := 0

var _comb := [{}, {}]
var _shake := 0.0
var _flash: ColorRect
var _flash_a := 0.0
var _dim: ColorRect
var _dim_a := 0.0
var _ended := false
var _bgm_danger := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	AudioManager.play_bgm("battle")
	set_anchors_preset(Control.PRESET_FULL_RECT)
	for i in 2:
		_comb[i] = {"prev_l": false, "prev_m": false, "prev_h": false, "prev_t": false, "pend_l": 0, "pend_m": 0}

	var fds := Registry.load_all()
	var a: FighterData = fds[GameState.p1_char]
	var b: FighterData = fds[GameState.p2_char]
	match_seed = GameState.next_match_seed()
	world = CombatWorld.new(Registry.bake(a), Registry.bake(b), match_seed)
	if GameState.mode != GameState.Mode.VS_2P:
		brain = CpuBrain.new(1, GameState.cpu_level, match_seed + 999)

	scene_root = Node2D.new()
	add_child(scene_root)
	scene_root.add_child(StageView.new())
	for i in 2:
		var fv := FighterView.new()
		fv.setup(world, i, (a if i == 0 else b).color, (a if i == 0 else b).id)
		scene_root.add_child(fv)
		views.append(fv)
	fx = FxLayer.new()
	scene_root.add_child(fx)
	hud = Hud.new()
	hud.setup(world)
	add_child(hud)
	overlay = Overlay.new()
	overlay.world = world
	overlay.visible = GameState.mode == GameState.Mode.TRAINING
	add_child(overlay)
	# 터치 컨트롤 (모바일/웹/터치 기기)
	if TouchControls.should_show(bool(SettingsManager.data.get("touch_ui", true))):
		touch = TouchControls.new()
		touch.size_percent = int(SettingsManager.data.get("touch_size", 100))
		touch.pause_pressed.connect(_toggle_pause)
		add_child(touch)
	_flash = ColorRect.new()
	_flash.color = UiKit.PAPER_LIGHT
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.modulate.a = 0.0
	add_child(_flash)
	_dim = ColorRect.new()
	_dim.color = Color(0.05, 0.045, 0.04)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dim.modulate.a = 0.0
	add_child(_dim)
	hud.banner("제 1 합", "준비", 1.5)
	_sync_views()


# ---------------------------------------------------------------- 스텝

func _physics_process(_dt: float) -> void:
	if get_tree().paused or _ended:
		return
	var w1 := 0
	var w2 := 0
	if replay_mode:
		if replay_i < replay_words.size():
			w1 = replay_words[replay_i][0]
			w2 = replay_words[replay_i][1]
			replay_i += 1
		else:
			replay_mode = false
			overlay.replay_note = ""
	else:
		w1 = _read_word(1)
		match GameState.mode:
			GameState.Mode.VS_2P:
				w2 = _read_word(2)
			GameState.Mode.VS_CPU:
				w2 = brain.think(world)
			GameState.Mode.TRAINING:
				w2 = CpuBrain.dummy_word(dummy_mode, world, 1, brain)
	recording.append([w1, w2])
	var evs := world.step(w1, w2)
	for e in evs:
		_handle_event(e)
	_training_refill()
	_sync_bgm_intensity()
	_sync_views()
	if world.s["phase"] == SimC.PH_MATCH_END and not _ended:
		_show_results()


func _sync_views() -> void:
	for v in views:
		v.sync()
	hud.sync()
	if overlay.visible:
		overlay.history = recording
		overlay.dummy_mode = dummy_mode
		overlay.sync()


func _sync_bgm_intensity() -> void:
	if GameState.mode == GameState.Mode.TRAINING:
		return
	var p0: Dictionary = world.s["p"][0]
	var p1: Dictionary = world.s["p"][1]
	var low_hp: bool = int(p0["hp"]) * 100 <= int(world.chars[0]["hp"]) * 30 \
			or int(p1["hp"]) * 100 <= int(world.chars[1]["hp"]) * 30
	var match_point: bool = int(world.s["wins"][0]) >= int(world.opts["wins_needed"]) - 1 \
			or int(world.s["wins"][1]) >= int(world.opts["wins_needed"]) - 1
	var last_seconds: bool = int(world.s["timer"]) <= 10 * SimC.TPS
	var danger: bool = low_hp or match_point or last_seconds
	if danger != _bgm_danger:
		_bgm_danger = danger
		AudioManager.play_bgm("danger" if danger else "battle")


## 키보드/패드 → 입력 워드. A+S 동시(2틱 유예) = 기술.
func _read_word(pn: int) -> int:
	var pre := "p%d_" % pn
	var c: Dictionary = _comb[pn - 1]
	var w := 0
	if Input.is_action_pressed(pre + "left"):
		w |= SimC.B_LEFT
	if Input.is_action_pressed(pre + "right"):
		w |= SimC.B_RIGHT
	if Input.is_action_pressed(pre + "up"):
		w |= SimC.B_UP
	if Input.is_action_pressed(pre + "down"):
		w |= SimC.B_DOWN
	if Input.is_action_pressed(pre + "super"):
		w |= SimC.B_SUPER
	var l := Input.is_action_pressed(pre + "light")
	var m := Input.is_action_pressed(pre + "medium")
	var h := Input.is_action_pressed(pre + "heavy")
	var tc := Input.is_action_pressed(pre + "tech")
	var lj: bool = l and not c["prev_l"]
	var mj: bool = m and not c["prev_m"]
	var hj: bool = h and not c["prev_h"]
	var tj: bool = tc and not c["prev_t"]
	c["prev_l"] = l
	c["prev_m"] = m
	c["prev_h"] = h
	c["prev_t"] = tc
	if lj:
		c["pend_l"] = 3
	if mj:
		c["pend_m"] = 3
	if c["pend_l"] > 0 and c["pend_m"] > 0:
		w |= SimC.B_T
		c["pend_l"] = 0
		c["pend_m"] = 0
	else:
		if c["pend_l"] == 1:
			w |= SimC.B_L
		if c["pend_m"] == 1:
			w |= SimC.B_M
		c["pend_l"] = maxi(c["pend_l"] - 1, 0)
		c["pend_m"] = maxi(c["pend_m"] - 1, 0)
	if hj:
		w |= SimC.B_H
	if tj:
		w |= SimC.B_T
	return w


# ---------------------------------------------------------------- 이벤트 연출

func _handle_event(e: Dictionary) -> void:
	var pos := Vector2(640.0 + e.get("x", 0) / 1000.0, 620.0 - e.get("y", 66000) / 1000.0)
	match e["t"]:
		"move_start":
			var mv: Dictionary = world.chars[e["p"]]["moves_by_id"].get(e["id"], {})
			if not mv.is_empty():
				hud.move_callout(e["p"], mv["name"], mv.get("role", ""), e["kind"])
		"move_active":
			_spawn_move_signature(e)
		"hit":
			var kind: String = e["kind"]
			var snd: String = {"light": "hit_l", "medium": "hit_m", "heavy": "hit_h", "tech": "hit_l", "super": "hit_h"}.get(kind, "hit_l")
			var edge: bool = e.get("edge", false)
			AudioManager.play(snd, 1.15 if edge else 1.0)
			fx.spawn("hit_edge" if edge else "hit", pos, {"light": 0.8, "medium": 1.1, "heavy": 1.6, "tech": 0.8, "super": 2.0}.get(kind, 1.0))
			var dir: int = world.s["p"][e["p"]]["facing"]
			# 그림 속 무기, 피격 반동, 이펙트 모두 시뮬이 계산한 같은 접촉 좌표를 사용한다.
			views[e["p"]].show_blade_contact(pos, kind, edge)
			views[1 - e["p"]].receive_impact(dir, kind)
			fx.spawn("blade_hit", pos,
					{"light": 0.75, "medium": 1.0, "heavy": 1.35, "tech": 0.8,
					"super": 1.65}.get(kind, 1.0), {"dir": dir, "edge": edge})
			var gush: bool = edge or kind == "heavy" or kind == "super"
			fx.spray_blood(pos, dir, e.get("dmg", 80) / 42.0, gush)
			_add_shake({"light": 2.0, "medium": 4.0, "heavy": 9.0, "tech": 2.0, "super": 12.0}.get(kind, 2.0) + (3.0 if edge else 0.0))
			if kind == "heavy" or edge:
				_flash_hit(0.3)
			if edge:
				_dim_hit(0.35)
			_rumble(1 - e["p"], 0.4 if kind != "heavy" else 0.7)
			if overlay.visible:
				overlay.last_adv = e.get("adv", 0)
		"block":
			AudioManager.play("block")
			fx.spawn("block", pos)
			_add_shake(1.5)
			if overlay.visible:
				overlay.last_adv = e.get("adv", 0)
		"parry":
			AudioManager.play("parry")
			fx.spawn("parry", pos)
			_add_shake(3.0)
			_flash_hit(0.4)
		"clash":
			AudioManager.play("clash")
			fx.spawn("clash", pos)
			_add_shake(6.0)
		"beaten":
			AudioManager.play("clash", 0.8)
			fx.spawn("clash", pos, 0.7)
		"whiff":
			# 휘두름은 이미 실제 활성 프레임에 재생된다. 여기서 겹쳐 울리지 않는다.
			pass
		"jump":
			AudioManager.play("whiff", 1.4, 0.45)
		"land":
			_add_shake(1.5)
		"grab":
			AudioManager.play("grab")
			fx.spawn("grab", pos)
		"grab_hit":
			AudioManager.play("hit_h", 0.9)
			fx.spawn("hit", pos, 1.5)
			fx.spray_blood(pos, world.s["p"][e["p"]]["facing"], 4.0, true)
			_add_shake(8.0)
			_rumble(1 - e["p"], 0.7)
		"grab_break":
			AudioManager.play("block", 0.7)
			fx.spawn("clash", pos, 0.6)
		"ko":
			AudioManager.play("ko")
			fx.spawn("ko", pos)
			var kdir: int = world.s["p"][1 - e["p"]]["facing"]
			fx.spray_blood(pos, kdir, 9.0, true)
			fx.add_stain(Vector2(640.0 + world.s["p"][e["p"]]["x"] / 1000.0, 0), 26.0)
			_add_shake(14.0)
			_flash_hit(0.5)
			_dim_hit(0.4)
			_rumble(e["p"], 1.0)
		"super":
			AudioManager.play("super")
			fx.spawn("super", Vector2(640, 400))
			_dim_hit(0.5)
		"nerve_art":
			AudioManager.play("super", 0.82)
			fx.spawn("super", pos, 0.72)
			_add_shake(5.0)
			_dim_hit(0.22)
		"nerve_gain":
			AudioManager.play("nerve")
		"nerve_cancel":
			AudioManager.play("nerve", 1.3)
		"fight_start":
			AudioManager.play("round")
			hud.banner("베어라!", "", 0.8, UiKit.SEAL)
		"round_start":
			fx.clear_stains()
			hud.banner("제 %d 합" % e["round"], "준비", 1.5)
		"round_end":
			var reason: String = e["reason"]
			if reason == "ko":
				hud.banner("절명", "", 2.2, UiKit.SEAL)
			elif reason == "time":
				hud.banner("시간", "", 2.2)
			else:
				hud.banner("상격", "동시 절명", 2.2, UiKit.SEAL)
		"match_end":
			pass


## 실제 활성 무기 판정의 끝점에 캐릭터 고유 붓 이펙트를 맞춘다.
func _spawn_move_signature(e: Dictionary) -> void:
	var pi: int = e["p"]
	var fighter: Dictionary = world.chars[pi]
	var mv: Dictionary = fighter["moves_by_id"].get(e["id"], {})
	if mv.is_empty():
		return
	var dir: int = e.get("facing", world.s["p"][pi]["facing"])
	var origin := Vector2(640.0 + e.get("x", 0) / 1000.0,
			620.0 - e.get("y", 0) / 1000.0)
	var target := origin + Vector2(dir * 100.0, -100.0)
	var rects: Array = e.get("rects", [])
	if not rects.is_empty():
		var tip_x: int = int(rects[0][2] if dir > 0 else rects[0][0])
		var low_y: int = int(rects[0][1])
		var high_y: int = int(rects[0][3])
		for rect in rects:
			tip_x = maxi(tip_x, int(rect[2])) if dir > 0 else mini(tip_x, int(rect[0]))
			low_y = mini(low_y, int(rect[1]))
			high_y = maxi(high_y, int(rect[3]))
		target = Vector2(640.0 + tip_x / 1000.0,
				620.0 - (low_y + high_y) / 2000.0)
	var kind: String = e["kind"]
	if kind == "grab":
		return
	AudioManager.play_weapon_swing(fighter["id"], kind, mv.get("move_key", kind))
	var strength: float = {"light": 0.55, "medium": 0.82, "heavy": 1.08,
			"tech": 0.94, "air": 0.78, "super": 1.32}.get(kind, 0.75)
	var life: float = {"light": 9.0, "medium": 13.0, "heavy": 18.0,
			"tech": 16.0, "air": 13.0, "super": 24.0}.get(kind, 13.0)
	fx.spawn("signature", origin, strength, {
			"char": fighter["id"], "move_key": mv.get("move_key", kind),
			"slot": kind, "dir": dir, "target": target, "life": life})


func _add_shake(v: float) -> void:
	if SettingsManager.data["fx_shake"]:
		_shake = maxf(_shake, v)


func _flash_hit(v: float) -> void:
	if SettingsManager.data["fx_flash"]:
		_flash_a = maxf(_flash_a, v)


func _dim_hit(v: float) -> void:
	if SettingsManager.data["fx_highlight"]:
		_dim_a = maxf(_dim_a, v)


func _rumble(pi: int, strength: float) -> void:
	if SettingsManager.data["fx_rumble"] and Input.get_connected_joypads().has(pi):
		Input.start_joy_vibration(pi, strength * 0.5, strength, 0.18)


func _process(delta: float) -> void:
	if _shake > 0.05:
		_shake = lerpf(_shake, 0.0, delta * 9.0)
		scene_root.position = Vector2(randf_range(-_shake, _shake), randf_range(-_shake, _shake))
	else:
		scene_root.position = Vector2.ZERO
	_flash_a = maxf(_flash_a - delta * 1.8, 0.0)
	_flash.modulate.a = _flash_a
	_dim_a = maxf(_dim_a - delta * 1.2, 0.0)
	_dim.modulate.a = _dim_a


# ---------------------------------------------------------------- 훈련

func _training_refill() -> void:
	if GameState.mode != GameState.Mode.TRAINING:
		return
	var neutral := true
	for i in 2:
		var st: int = world.s["p"][i]["state"]
		if st != SimC.ST_IDLE and st != SimC.ST_WALK_F and st != SimC.ST_WALK_B:
			neutral = false
	neutral_ticks = neutral_ticks + 1 if neutral else 0
	if neutral_ticks >= 120:
		for i in 2:
			if world.s["p"][i]["hp"] < world.chars[i]["hp"]:
				world.debug_set_hp(i, world.chars[i]["hp"])


func _training_reset() -> void:
	world.reset_match()
	recording.clear()
	replay_mode = false
	overlay.replay_note = ""
	neutral_ticks = 0
	hud.banner("리셋", "", 0.6)
	_sync_views()


func _save_replay() -> void:
	DirAccess.make_dir_recursive_absolute("user://replays")
	var fa := FileAccess.open("user://replays/last.json", FileAccess.WRITE)
	fa.store_string(JSON.stringify({"chars": [GameState.p1_char, GameState.p2_char],
		"seed": match_seed, "words": recording}))
	hud.banner("리플레이 저장", "user://replays/last.json", 1.2)


func _play_replay() -> void:
	if not FileAccess.file_exists("user://replays/last.json"):
		hud.banner("리플레이 없음", "", 1.0)
		return
	var fa := FileAccess.open("user://replays/last.json", FileAccess.READ)
	var parsed = JSON.parse_string(fa.get_as_text())
	if not (parsed is Dictionary):
		return
	var fds := Registry.load_all()
	match_seed = int(parsed["seed"])
	world = CombatWorld.new(Registry.bake(fds[int(parsed["chars"][0])]),
		Registry.bake(fds[int(parsed["chars"][1])]), match_seed)
	for i in 2:
		views[i].setup(world, i, fds[int(parsed["chars"][i])].color, fds[int(parsed["chars"][i])].id)
	hud.setup(world)
	overlay.world = world
	replay_words = []
	for pair in parsed["words"]:
		replay_words.append([int(pair[0]), int(pair[1])])
	replay_i = 0
	replay_mode = true
	recording = []
	overlay.replay_note = "리플레이 재생 중"
	hud.banner("리플레이", "", 1.0)


# ---------------------------------------------------------------- 입력(메타)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and not _ended:
		_toggle_pause()
		return
	if GameState.mode == GameState.Mode.TRAINING and event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_1, KEY_F1:
				_training_reset()
			KEY_2, KEY_F2:
				overlay.show_boxes = not overlay.show_boxes
			KEY_3, KEY_F3:
				overlay.show_frames = not overlay.show_frames
			KEY_4, KEY_F4:
				dummy_mode = (dummy_mode + 1) % 4
				if dummy_mode == 3 and brain == null:
					brain = CpuBrain.new(1, GameState.cpu_level, match_seed + 999)
			KEY_5, KEY_F5:
				_save_replay()
			KEY_6, KEY_F6:
				_play_replay()


# ---------------------------------------------------------------- 일시정지/결과

func _toggle_pause() -> void:
	if get_tree().paused:
		get_tree().paused = false
		if pause_panel:
			pause_panel.queue_free()
			pause_panel = null
	else:
		get_tree().paused = true
		if touch:
			touch._release_all()
		pause_panel = _make_panel("멈춤", [
			["계속", _toggle_pause],
			["경기 재시작", _restart_match],
			["캐릭터 선택", _goto_select],
			["메인 메뉴", _goto_menu],
		], _controls_text())


func _restart_match() -> void:
	get_tree().paused = false
	GameState.goto("match")


func _goto_select() -> void:
	GameState.goto("select")


func _goto_menu() -> void:
	GameState.goto("menu")


func _show_results() -> void:
	_ended = true
	AudioManager.play_bgm("menu")
	var text := "무승부"
	var winner: int = world.s["winner"]
	if winner == 0 or winner == 1:
		text = "승리 — " + world.chars[winner]["name"]
	results_panel = _make_panel(text, [
		["재경기", _restart_match],
		["캐릭터 선택", _goto_select],
		["메인 메뉴", _goto_menu],
	], "")


func _make_panel(title: String, buttons: Array, foot: String) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.process_mode = Node.PROCESS_MODE_ALWAYS
	panel.add_theme_stylebox_override("panel", UiKit.panel_box())
	# 긴 조작 설명이 있는 일시정지 창과 짧은 결과 창의 폭을 따로 잡아
	# 버튼/설명/화면 가장자리가 서로 겹치지 않게 한다.
	var panel_w := 720.0 if foot != "" else 440.0
	panel.position = Vector2((1280.0 - panel_w) * 0.5, 105.0 if foot != "" else 190.0)
	panel.custom_minimum_size = Vector2(panel_w, 0)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(v)
	var t := UiKit.label(title, 40)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	v.add_child(UiKit.vspace(12))
	var first: Button = null
	for b in buttons:
		var btn := UiKit.button(b[0], 24)
		btn.pressed.connect(b[1])
		v.add_child(btn)
		if first == null:
			first = btn
	if foot != "":
		v.add_child(UiKit.vspace(10))
		var fl := UiKit.label(foot, 14, UiKit.GRAY)
		fl.custom_minimum_size = Vector2(panel_w - 48.0, 0)
		fl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		fl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(fl)
	add_child(panel)
	first.grab_focus()
	return panel


func _controls_text() -> String:
	return "P1  이동 ←→ · 약 A · 중 S · 강 D · 기술 A+S · 오의 Q\nP2  이동 J/L · 약 U · 중 I · 강 O · 기술 U+I · 오의 P\n중=핵심 견제/연계 · 강=느린 고위험 결정타 · 기술=캐릭터 고유 전술\n잡기 →+중(근접) · 정밀방어 피격 직전 3f 내 뒤 · 오의 사맥 3"
