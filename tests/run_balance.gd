extends SceneTree
## 개발용 5인 CPU 매치업 표. 정식 테스트와 별개로 수치 조정 때 실행한다.
## godot --headless --path . --script res://tests/run_balance.gd

const ROUNDS_PER_SIDE := 16


func _initialize() -> void:
	var fds := Registry.load_all()
	var wins := {}
	var games := {}
	var pair_wins := {}
	for fd in fds:
		wins[fd.id] = 0
		games[fd.id] = 0
	for a in fds.size():
		for b in range(a + 1, fds.size()):
			var pair_key := "%s/%s" % [fds[a].id, fds[b].id]
			pair_wins[pair_key] = [0, 0]
			for swap in 2:
				for n in ROUNDS_PER_SIDE:
					var left := b if swap else a
					var right := a if swap else b
					var seed := 70000 + a * 1000 + b * 100 + swap * 20 + n
					var w := CombatWorld.new(Registry.bake(fds[left]), Registry.bake(fds[right]), seed,
							{"skip_intro": true, "timer_ticks": 30 * SimC.TPS, "wins_needed": 1})
					var c0 := CpuBrain.new(0, 4, seed + 11)
					var c1 := CpuBrain.new(1, 4, seed + 29)
					for tick in 3600:
						w.step(c0.think(w), c1.think(w))
						if w.s["phase"] == SimC.PH_MATCH_END:
							break
					games[fds[left].id] += 1
					games[fds[right].id] += 1
					if w.s["winner"] == 0:
						wins[fds[left].id] += 1
						pair_wins[pair_key][0 if left == a else 1] += 1
					elif w.s["winner"] == 1:
						wins[fds[right].id] += 1
						pair_wins[pair_key][0 if right == a else 1] += 1
	print("=== 5인 CPU 밸런스 표 (각 대진 좌우 %d경기) ===" % ROUNDS_PER_SIDE)
	for fd in fds:
		var rate := 100.0 * float(wins[fd.id]) / maxf(float(games[fd.id]), 1.0)
		print("%s(%s): %d/%d = %.1f%%" % [fd.display_name, fd.id, wins[fd.id], games[fd.id], rate])
	print("--- 대진별 (앞 캐릭터 승 : 뒤 캐릭터 승) ---")
	for key in pair_wins:
		print("%s = %d:%d" % [key, pair_wins[key][0], pair_wins[key][1]])
	quit()
