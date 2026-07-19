extends Node2D
## 타격 이펙트 + 피 연출. 뷰 전용(시뮬과 무관).
## - sparks: 먹 튀김·붓 획 (기존)
## - blood: 중력 적용 핏방울 → 지면에 닿으면 stain(핏자국)으로 굳음
## - stains: 라운드 동안 지면에 남는 핏자국 (round_start 때 clear)

const GROUND_Y := 620.0
const GRAV := 0.42                      # px/틱^2
const MAX_BLOOD := 220
const MAX_STAINS := 90

# 흑백 세계의 유일한 유채 = 피. 신선한 선혈 → 굳은 검붉은 자국.
const BLOOD_FRESH := Color(0.60, 0.055, 0.045)
const BLOOD_DARK := Color(0.42, 0.045, 0.04)
const BLOOD_MIST := Color(0.55, 0.09, 0.07)

var sparks: Array = []
var blood: Array = []
var stains: Array = []
var _id := 0


func spawn(kind: String, pos: Vector2, strength: float = 1.0, data: Dictionary = {}) -> void:
	_id += 1
	var spark := {"kind": kind, "pos": pos, "age": 0.0, "life": _life(kind),
			"s": strength, "seed": _id}
	for key in data:
		spark[key] = data[key]
	sparks.append(spark)
	queue_redraw()


## 피 분출. dir=공격 진행 방향(+1/-1), amount=대략 피해/50, gush=크게 터짐
func spray_blood(pos: Vector2, dir: int, amount: float, gush := false) -> void:
	var n := int(clampf(amount * (3.5 if gush else 2.2), 3, 46))
	for k in n:
		var spread := 1.15 if gush else 0.8
		# 주 분사: 공격 방향 위쪽으로 원뿔, 일부는 사방으로 튐
		var base_ang := (-0.5 if dir >= 0 else PI + 0.5)
		var ang: float
		if randf() < 0.25:
			ang = randf() * TAU                                   # 사방 미세 비산
		else:
			ang = base_ang + randf_range(-spread, spread)
		var spd := randf_range(2.5, 8.5) * (1.5 if gush else 1.0)
		var vel := Vector2(cos(ang), sin(ang)) * spd
		vel.x += dir * randf_range(0.5, 2.5)                      # 진행 방향 편향
		blood.append({
			"p": pos + Vector2(randf_range(-6, 6), randf_range(-10, 6)),
			"v": vel, "r": randf_range(1.4, 4.2) * (1.35 if gush else 1.0),
			"life": randf_range(28, 70), "age": 0.0,
			"trail": randf() < 0.5,
		})
	# 순간 핏빛 안개
	if gush:
		for k in int(amount):
			sparks.append({"kind": "mist", "pos": pos + Vector2(randf_range(-14, 14), randf_range(-14, 6)),
				"age": 0.0, "life": 16.0, "s": 1.0, "seed": _id + k})
	if blood.size() > MAX_BLOOD:
		blood = blood.slice(blood.size() - MAX_BLOOD)
	queue_redraw()


## 지면 핏자국 직접 추가 (KO 등)
func add_stain(pos: Vector2, size: float) -> void:
	stains.append({"p": Vector2(pos.x, GROUND_Y + randf_range(2, 10)), "r": size,
		"seed": _id, "drips": randi() % 4})
	_id += 1
	if stains.size() > MAX_STAINS:
		stains = stains.slice(stains.size() - MAX_STAINS)


func clear_stains() -> void:
	stains.clear()
	blood.clear()
	queue_redraw()


func _life(kind: String) -> float:
	match kind:
		"ko": return 50.0
		"clash", "parry", "super": return 30.0
		"blade_hit": return 16.0
		"mist": return 16.0
		"signature": return 14.0
		_: return 20.0


func _process(delta: float) -> void:
	var step := delta * 60.0
	# 핏방울 물리
	if not blood.is_empty():
		for b in blood:
			b["age"] += step
			b["v"].y += GRAV * step
			b["v"].x *= 0.99
			b["p"] += b["v"] * step
			if b["p"].y >= GROUND_Y and b["v"].y > 0:
				add_stain(b["p"], b["r"] * randf_range(1.6, 3.0))
				b["age"] = 9999.0
		blood = blood.filter(func(b): return b["age"] < b["life"])
	if not sparks.is_empty():
		for sp in sparks:
			sp["age"] += step
		sparks = sparks.filter(func(sp): return sp["age"] < sp["life"])
	if not blood.is_empty() or not sparks.is_empty():
		queue_redraw()


func _draw() -> void:
	# --- 지면 핏자국 (가장 아래) ---
	for st in stains:
		var rng := RandomNumberGenerator.new()
		rng.seed = st["seed"] * 131 + 7
		var c: Vector2 = st["p"]
		var r: float = st["r"]
		draw_circle(c, r, Color(BLOOD_DARK, 0.72))
		# 불규칙 얼룩
		for k in 5:
			var a := rng.randf() * TAU
			var d := rng.randf() * r * 1.3
			draw_circle(c + Vector2(cos(a), sin(a)) * d, rng.randf_range(0.3, 0.5) * r, Color(BLOOD_DARK, 0.5))
		# 흘러내림 자국
		for k in st["drips"]:
			var dx := rng.randf_range(-r, r)
			var dl := rng.randf_range(4, 16)
			draw_line(c + Vector2(dx, 0), c + Vector2(dx + rng.randf_range(-2, 2), dl), Color(BLOOD_DARK, 0.55), rng.randf_range(1.5, 3.0))

	# --- 먹 스파크 ---
	for sp in sparks:
		var t: float = sp["age"] / sp["life"]
		var fade := 1.0 - t
		var pos: Vector2 = sp["pos"]
		var s: float = sp["s"]
		var rng2 := RandomNumberGenerator.new()
		rng2.seed = sp["seed"] * 977
		match sp["kind"]:
			"signature":
				_draw_signature(sp, t, fade)
			"blade_hit":
				if sp.get("char", "") == "jiko":
					_draw_shinai_contact(sp, t, fade)
				else:
					# 실제 접점 중심의 짧은 절단선. 첫 수 프레임은 히트스톱과 함께 거의 고정된다.
					var direction := float(sp.get("dir", 1))
					var edge: bool = sp.get("edge", false)
					var cut_dir := Vector2(0.34 * direction, -1.0).normalized()
					var cut_len := (24.0 + 20.0 * s) * (0.90 + 0.15 * t)
					draw_line(pos - cut_dir * cut_len, pos + cut_dir * cut_len,
							Color(UiKit.INK, 0.82 * fade), 10.0 * (1.0 - 0.55 * t), true)
					draw_line(pos - cut_dir * cut_len, pos + cut_dir * cut_len,
							Color(UiKit.PAPER_LIGHT, 0.96 * fade), 4.5 * (1.0 - 0.45 * t), true)
					draw_line(pos - cut_dir * cut_len * 0.34, pos + cut_dir * cut_len * 0.34,
							Color(UiKit.SEAL if edge else BLOOD_FRESH, 0.95 * fade), 2.2, true)
					draw_arc(pos, 8.0 + 28.0 * t * s, 0, TAU, 28,
							Color(UiKit.PAPER_LIGHT, 0.75 * fade), 2.5)
			"hit", "hit_edge":
				var n := 6 + int(s * 3.0)
				for k in n:
					var ang := rng2.randf() * TAU
					var ln := (10.0 + rng2.randf() * 22.0 * s) * (0.4 + t)
					var v := Vector2(cos(ang), sin(ang))
					draw_line(pos + v * 6.0, pos + v * (6.0 + ln), Color(UiKit.INK, 0.6 * fade), rng2.randf_range(1.5, 3.5))
				UiKit.splatter(self, pos, 20.0 * s * (0.5 + t), 8, Color(UiKit.INK, 0.5 * fade), sp["seed"])
			"mist":
				draw_circle(pos, (6.0 + 20.0 * t) * s, Color(BLOOD_MIST, 0.20 * fade))
			"block":
				draw_arc(pos, 18.0 + 8.0 * t, -1.2, 1.2, 16, Color(UiKit.GRAY, 0.8 * fade), 4.0)
			"parry":
				draw_arc(pos, 10.0 + 42.0 * t, 0, TAU, 40, Color(UiKit.PAPER_LIGHT, 0.95 * fade), 3.0)
				draw_arc(pos, 6.0 + 30.0 * t, 0, TAU, 40, Color(UiKit.SEAL, 0.9 * fade), 2.0)
			"clash":
				for k in 2:
					var ang3 := 0.6 + k * (PI * 0.5) + rng2.randf() * 0.2
					var v3 := Vector2(cos(ang3), sin(ang3))
					draw_line(pos - v3 * (30.0 + 20.0 * t), pos + v3 * (30.0 + 20.0 * t), Color(UiKit.INK, 0.85 * fade), 5.0 - 3.0 * t)
				UiKit.splatter(self, pos, 34.0, 16, Color(UiKit.INK, 0.7 * fade), sp["seed"])
			"whiff":
				draw_arc(pos, 26.0, -0.5, 0.9, 12, Color(UiKit.INK, 0.25 * fade), 2.0)
			"grab":
				draw_arc(pos, 16.0 + 6.0 * t, 0, TAU, 20, Color(UiKit.INK, 0.8 * fade), 3.5)
			"ko":
				UiKit.splatter(self, pos, 50.0 + 50.0 * t, 20, Color(UiKit.INK, 0.6 * fade), sp["seed"])
			"super":
				draw_arc(pos, 12.0 + 70.0 * t, 0, TAU, 48, Color(UiKit.INK, 0.8 * fade), 5.0)

	# --- 공중 핏방울 (가장 위) ---
	for b in blood:
		var ft: float = 1.0 - (b["age"] / b["life"])
		var col: Color = BLOOD_FRESH.lerp(BLOOD_DARK, 0.4)
		if b["trail"] and b["v"].length() > 2.0:
			var tail: Vector2 = b["p"] - b["v"].normalized() * b["r"] * 2.6
			draw_line(tail, b["p"], Color(col, 0.55 * ft), b["r"] * 0.9)
		draw_circle(b["p"], b["r"] * (0.6 + 0.4 * ft), Color(col, 0.9 * ft))


## 캐릭터마다 무기의 성격이 읽히는 절제된 먹선. 공격 등급은 굵기·선 수·인주색으로 구분한다.
func _draw_signature(sp: Dictionary, t: float, fade: float) -> void:
	var ground: Vector2 = sp["pos"]
	var target: Vector2 = sp.get("target", ground + Vector2(float(sp.get("dir", 1)) * 100.0, -100.0))
	var dir: float = float(sp.get("dir", 1))
	var strength: float = sp["s"]
	var slot: String = sp.get("slot", "light")
	var move_key: String = sp.get("move_key", slot)
	var heavy: bool = slot == "heavy" or slot == "super" or move_key == "motion_nerve"
	var accent: bool = slot == "tech" or heavy or move_key.begins_with("motion_")
	var alpha := (0.42 + strength * 0.28) * fade
	var ink := Color(UiKit.INK, alpha * 0.72)
	var paper := Color(UiKit.PAPER_LIGHT, alpha)
	var seal := Color(UiKit.SEAL, alpha * (0.78 if accent else 0.0))
	var width := 1.4 + strength * 1.55
	var base := ground + Vector2(dir * 22.0, -98.0)
	var delta := target - base
	if delta.length() < 12.0:
		delta = Vector2(dir * 90.0, -10.0)
		target = base + delta
	var along := delta.normalized()
	var normal := Vector2(-along.y, along.x)
	# 첫 활성 프레임부터 형태가 읽히고, 2~3틱 안에 실제 판정 끝까지 도달한다.
	var grow := clampf(0.22 + t * 5.0, 0.0, 1.0)
	var end := base.lerp(target, grow)

	match String(sp.get("char", "arin")):
		"arin":
			# 아야메: 한 호흡에 뽑히는 초승달 발도선.
			var lift := 24.0 + 28.0 * strength
			var control := (base + end) * 0.5 + Vector2(0.0, -lift)
			var arc := _quadratic_points(base, control, end, 18)
			draw_polyline(arc, ink, width + 3.0, true)
			draw_polyline(arc, paper, width, true)
			if accent:
				var inner := _quadratic_points(base + normal * 6.0, control + normal * 2.0, end, 18)
				draw_polyline(inner, seal, maxf(1.2, width * 0.48), true)

		"daeru":
			# 이와오: 월도의 중량이 바닥까지 꿰뚫는 낙하선과 균열.
			var impact := Vector2(target.x, ground.y - 7.0)
			var overhead := end + Vector2(-dir * 24.0, -58.0 - 34.0 * strength)
			var strike_end := impact if slot == "medium" or heavy else end
			draw_line(overhead, strike_end, ink, width + 4.0, true)
			draw_line(overhead, strike_end, paper, width, true)
			if slot == "medium" or heavy:
				var crack_grow := clampf((t - 0.06) * 5.0, 0.0, 1.0)
				var cracks := 2 + int(strength * 2.0)
				for k in cracks:
					var side := -1.0 if k % 2 == 0 else 1.0
					var crack_end := impact + Vector2(side * (18.0 + k * 9.0) * crack_grow, -(4.0 + k * 2.0) * crack_grow)
					draw_line(impact, crack_end, ink, maxf(1.2, width * 0.62), true)
			if accent:
				draw_circle(impact, 3.0 + strength * 2.0, seal)

		"han":
			# 하야테: 쌍검이 남기는 두 개의 빠른 평행 궤적.
			var gap := 7.0 + strength * 4.0
			for side in [-1.0, 1.0]:
				var off: Vector2 = normal * gap * side
				draw_line(base + off, end + off, ink, width + 2.5, true)
				draw_line(base + off, end + off, paper, maxf(1.2, width * 0.72), true)
			if accent:
				draw_line(end - normal * 14.0, end + normal * 14.0, seal, maxf(1.5, width * 0.62), true)

		"myo":
			# 카게로: 사슬 마디와 낫끝의 포획 파문.
			var links := 4 + int(strength * 3.0)
			draw_line(base, end, ink, width + 1.5, true)
			for k in links:
				var u := float(k + 1) / float(links + 1)
				if u > grow:
					continue
				var lp := base.lerp(target, u) + normal * sin(u * PI * 4.0) * 3.0
				draw_arc(lp, 2.4 + strength, 0.0, TAU, 10, paper, maxf(1.0, width * 0.45))
			var rings := 1 + (1 if slot != "light" else 0) + (1 if heavy else 0)
			for k in rings:
				draw_arc(end, (8.0 + k * 7.0) * (0.65 + t), 0.0, TAU, 24,
						seal if accent and k == rings - 1 else paper, maxf(1.2, width * 0.55))

		"mujin":
			# 무진: 검압이 수면처럼 겹쳐 흐르는 파형.
			var waves := 1 + (1 if slot != "light" else 0) + (1 if heavy or move_key.begins_with("motion_") else 0)
			for k in waves:
				var pts := PackedVector2Array()
				var wave_off := (float(k) - float(waves - 1) * 0.5) * 7.0
				for j in 19:
					var u := float(j) / 18.0
					if u > grow:
						break
					var amp := (7.0 + strength * 5.0) * sin(u * PI)
					pts.append(base.lerp(target, u) + normal * (wave_off + sin(u * TAU * 1.5 + k) * amp))
				if pts.size() >= 2:
					draw_polyline(pts, ink, width + 2.0, true)
					draw_polyline(pts, seal if accent and k == waves - 1 else paper,
							maxf(1.1, width * 0.55), true)

		"jiko":
			# 지코: 손목·허리·머리·찌르기의 검도 타격선을 각기 다른 방향으로 분리한다.
			match slot:
				"light":
					# 손목 — 작고 빠른 직선과 손목 보호구를 닮은 짧은 괄호.
					draw_line(base, end, ink, width + 2.0, true)
					draw_line(base, end, paper, maxf(1.2, width * 0.62), true)
					draw_arc(end, 7.0 + strength * 3.0, -PI * 0.70, PI * 0.70,
							16, Color(UiKit.SEAL, alpha * 0.58), 1.8, true)
				"medium":
					# 허리 — 몸통을 가로지르는 넓은 대각선 두 겹.
					var control := (base + end) * 0.5 + normal * 28.0 * dir
					var do_arc := _quadratic_points(base, control, end, 18)
					draw_polyline(do_arc, ink, width + 3.0, true)
					draw_polyline(do_arc, paper, width, true)
					var do_inner := _quadratic_points(base + normal * 8.0,
							control + normal * 5.0, end + normal * 5.0, 18)
					draw_polyline(do_inner, Color(UiKit.SEAL, alpha * 0.54), 1.7, true)
				"heavy":
					# 머리 — 흔들림 없는 수직 내려치기와 머리 보호구 반원.
					var men_top := Vector2(end.x - dir * 12.0, minf(base.y, end.y) - 66.0)
					draw_line(men_top, end, ink, width + 4.0, true)
					draw_line(men_top, end, paper, width, true)
					draw_arc(end, 12.0 + 12.0 * t, PI, TAU, 22,
							Color(UiKit.SEAL, alpha * 0.72), 2.2, true)
				"tech":
					# 중단 찌르기 — 한 점으로 수렴하는 중심선과 두 번의 잔잔한 파문.
					draw_line(base - along * 20.0, end, ink, width + 3.0, true)
					draw_line(base - along * 20.0, end, paper, width, true)
					for ring in 2:
						draw_arc(end, (7.0 + ring * 8.0) * (0.65 + t), 0.0, TAU, 24,
								Color(UiKit.SEAL if ring == 1 else UiKit.PAPER_LIGHT,
								alpha * (0.72 if ring == 1 else 0.86)), 1.8, true)
				"super":
					# 기검체일치 — 네 타격을 한 호흡 안에서 겹치되 선 수는 절제한다.
					var span := 28.0 + strength * 8.0
					draw_line(base - normal * 10.0, end - normal * 10.0, ink, width + 2.0, true)
					draw_line(base - normal * 10.0, end - normal * 10.0, paper, width, true)
					var super_arc := _quadratic_points(base + normal * span,
							(base + end) * 0.5 - normal * span, end, 18)
					draw_polyline(super_arc, ink, width + 2.5, true)
					draw_line(Vector2(end.x - dir * 10.0, end.y - 70.0), end,
							Color(UiKit.SEAL, alpha * 0.76), width, true)
					draw_arc(end, 10.0 + 18.0 * t, 0.0, TAU, 28, paper, 2.0, true)
				_:
					draw_line(base, end, ink, width + 2.0, true)
					draw_line(base, end, paper, width, true)


## 죽도는 살을 베는 절단선 대신 맞은 부위에서 짧게 멈추는 타격표식으로 표현한다.
func _draw_shinai_contact(sp: Dictionary, t: float, fade: float) -> void:
	var pos: Vector2 = sp["pos"]
	var s: float = sp["s"]
	var direction := float(sp.get("dir", 1))
	var slot: String = sp.get("slot", "light")
	var axis := Vector2(direction, 0.0)
	if slot == "medium":
		axis = Vector2(direction, 0.72).normalized()
	elif slot == "heavy" or slot == "super":
		axis = Vector2(0.08 * direction, 1.0).normalized()
	var normal := Vector2(-axis.y, axis.x)
	var half_len := 18.0 + s * 15.0
	var ink := Color(UiKit.INK, 0.82 * fade)
	var paper := Color(UiKit.PAPER_LIGHT, 0.94 * fade)
	draw_line(pos - axis * half_len, pos + axis * half_len, ink,
			8.0 * (1.0 - 0.45 * t), true)
	draw_line(pos - axis * half_len, pos + axis * half_len, paper,
			3.0 * (1.0 - 0.35 * t), true)
	draw_line(pos - normal * (9.0 + s * 3.0), pos + normal * (9.0 + s * 3.0),
			Color(UiKit.SEAL, 0.72 * fade), 2.0, true)
	for ring in 2:
		draw_arc(pos, (7.0 + ring * 9.0 + 24.0 * t * s), 0.0, TAU, 28,
				Color(UiKit.PAPER_LIGHT if ring == 0 else UiKit.SEAL,
				(0.72 if ring == 0 else 0.42) * fade), 1.8, true)


func _quadratic_points(a: Vector2, control: Vector2, b: Vector2, count: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	for k in count:
		var u := float(k) / float(count - 1)
		points.append(a * (1.0 - u) * (1.0 - u) + control * 2.0 * (1.0 - u) * u + b * u * u)
	return points
