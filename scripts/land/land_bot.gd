## Простой бот для симуляций баланса: на каждом ходу жадно ставит карты,
## учитывая задание, недовольство и намерение земли. smart=false — ставит случайно.
extends RefCounted

const LandEvents = preload("res://scripts/land/land_events.gd")


static func play_turn(run, smart: bool = true) -> void:
	while run.plays_left > 0 and not run.hand.is_empty():
		var free: Array = run.field.free_cells()
		if free.is_empty():
			return
		if not smart:
			run.place(run.rng.randi_range(0, run.hand.size() - 1), free[run.rng.randi_range(0, free.size() - 1)])
			continue
		var best_v := value(run, run.field, {})
		var best := []
		for h in run.hand.size():
			for c in free:
				var f = run.field.clone()
				f.place_building(run.data, c, run.hand[h])
				var gain: Dictionary = f.cascade_total(f.echo(run.data, c, run.data.echo_level(run.hand[h])))
				var v := value(run, f, gain)
				if v > best_v + 0.001:
					best_v = v
					best = [h, c]
		if best.is_empty():
			return
		run.place(best[0], best[1])


## Оценка: доход каскада сейчас + потенциал поля (будущие каскады), задание, босс, недовольство.
static func value(run, f, gain: Dictionary) -> float:
	var g = f.clone()
	LandEvents.apply(run.intent, g, run.data)
	var sc: Dictionary = g.score(run.data)
	var v := 0.0
	for r in gain:
		v += float(gain[r]) * (1.3 if r == "wild" else 1.0)
	for r in sc["total"]:
		v += float(sc["total"][r]) * (1.3 if r == "wild" else 1.0)
	var have: Dictionary = sc["total"].duplicate()
	for r in run.echo_gain:
		have[r] = int(have.get(r, 0)) + int(run.echo_gain[r]) + int(gain.get(r, 0))
	if not run.task.is_empty():
		var short := 0
		for r in run.task:
			short += maxi(0, int(run.task[r]) - int(have.get(r, 0)))
		var rew := 0
		for r in run.island.get("task_reward", {}):
			rew += int(run.island["task_reward"][r])
		v += float(rew) * 1.3 if short == 0 else -0.3 * float(short)
	if run.is_boss():
		var miss := maxi(0, run.boss_need() - run.sum_res(have))
		v -= 3.5 * float(miss)
	if run.island.has("forge") and g.recipe_met(run.data, run.island["forge"]):
		v += 5.0
	v -= 3.5 * float(sc["discontent"])
	v += 3.0 * float(mini(int(sc.get("joy", 0)), int(run.data.run["lives"]) - run.lives))
	return v


## Выбор острова на карте: спокойные проще, опасные дают больше; задание — плюс.
static func pick_island(run, smart: bool = true) -> int:
	if not smart:
		return run.rng.randi_range(0, run.choices.size() - 1)
	var best := 0
	var best_v := -999.0
	for i in run.choices.size():
		var isl: Dictionary = run.choices[i]
		var v := 0.0
		for r in isl.get("reward", {}):
			v += float(isl["reward"][r])
		if not isl.get("task", {}).is_empty():
			for r in isl.get("task_reward", {}):
				v += 0.6 * float(isl["task_reward"][r])
		if isl.has("forge") and run.steel == 0:
			v += 3.0
		if isl.get("big", false):
			v += 2.0
		var ev: String = isl.get("event", "")
		if ev != "":
			v -= 1.0
		if isl.get("danger", false):
			v -= 2.0 if run.lives > 6 else 6.0
		if v > best_v:
			best_v = v
			best = i
	return best


## Рынок: лечение при малом запасе жизней, улучшения добычи/мастерских, покупка, контракт.
static func shop(run, smart: bool = true) -> void:
	if not smart:
		run.take_contract()
		return
	run.take_contract()
	while run.lives <= int(run.data.run["lives"]) - 4 and run.heal():
		pass
	run.buy_echo3()
	var changed := true
	while changed:
		changed = false
		var cards: Array = run.all_cards()
		cards.sort_custom(func(a, b): return _prio(run, a) > _prio(run, b))
		for id in cards:
			if run.data.echo_level(id) == 1 and run.echo(id):
				changed = true
				break
		if changed:
			continue
		var n_echo := 0
		for id in cards:
			if run.data.echo_level(id) > 0:
				n_echo += 1
		for id in cards:
			if n_echo < 4 and run.data.role(id) == "workshop" and run.data.echo_level(id) == 0 and not run.data.is_upgraded(id) and run.echo(id):
				changed = true
				break
		if changed:
			continue
		cards.sort_custom(func(a, b): return _prio(run, a) > _prio(run, b))
		for id in cards:
			if run.data.can_upgrade(id) and run.upgrade(id):
				changed = true
				break
		if changed:
			continue
		for i in run.market["buy"].size():
			if run.data.is_producer(run.market["buy"][i]) and run.buy(i):
				changed = true
				break
	while run.lives < int(run.data.run["lives"]) and run.heal():
		pass


static func _prio(run, id: String) -> int:
	match run.data.role(id):
		"workshop": return 3
		"base": return 2
		"housing": return 1
	return 0
