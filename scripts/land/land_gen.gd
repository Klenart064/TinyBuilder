## Генерация полей живой земли: форма, препятствия, местность, событие, задание.
extends RefCounted

const LandField = preload("res://scripts/land/land_field.gd")


## Новый остров: {"field", "event": id или "" (спокойно), "task": {res: n} или {}, "danger": bool, "reward": {res: n}, "task_reward": {res: n}}
static func make_field(data, rng: RandomNumberGenerator, index: int) -> Dictionary:
	var cfg: Dictionary = data.run
	var field = null
	for _attempt in 30:
		field = _shape(rng, _rand_range(rng, cfg["shape_cells"]))
		_place_obstacles(field, data, rng)
		_place_terrain(field, data, rng)
		if field.free_cells().size() >= int(cfg.get("min_free_cells", 6)):
			break
	var ev := pick_event(data, rng, index)
	var danger: bool = data.events.get(ev, {}).get("danger", false)
	var task := {}
	if rng.randf() < float(cfg.get("task_chance", 0.5)):
		task = make_task(data, rng, index)
	var reward: Dictionary = (cfg.get("danger_reward", {}) if danger else cfg.get("island_reward", {})).duplicate()
	var task_reward: Dictionary = cfg.get("task_reward", {}).duplicate()
	if danger:
		for r in task_reward:
			task_reward[r] = int(task_reward[r]) * int(cfg.get("danger_task_mult", 2))
	return {"field": field, "event": ev, "task": task, "danger": danger, "reward": reward, "task_reward": task_reward}


## Связный кусок из n клеток в рамке 4×4 (растёт от случайной клетки).
static func _shape(rng: RandomNumberGenerator, n: int):
	var f = LandField.new()
	var start := rng.randi_range(0, LandField.N - 1)
	f.exists[start] = true
	var count := 1
	while count < n:
		var frontier := []
		for i in LandField.N:
			if f.exists[i]:
				continue
			var k := 0
			for j in LandField.neighbors(i):
				if f.exists[j]:
					k += 1
			# Клетки с меньшим числом соседей чуть вероятнее — формы получаются разнообразнее
			for _w in (3 if k == 1 else 2):
				if k > 0:
					frontier.append(i)
		if frontier.is_empty():
			break
		f.exists[frontier[rng.randi_range(0, frontier.size() - 1)]] = true
		count += 1
	return f


static func _place_obstacles(field, data, rng: RandomNumberGenerator) -> void:
	var cfg: Dictionary = data.run
	var n := _rand_range(rng, cfg["obstacles"])
	var cells: Array = field.land_cells()
	_shuffle(cells, rng)
	for k in mini(n, cells.size()):
		var i: int = cells[k]
		var what := _weighted(rng, cfg["obstacle_pool"])
		if what == "prebuilt":
			var pool: Array = cfg["prebuilt_pool"]
			field.content[i] = pool[rng.randi_range(0, pool.size() - 1)]
		else:
			field.content[i] = what
		field.prebuilt[i] = true


static func _place_terrain(field, data, rng: RandomNumberGenerator) -> void:
	var cfg: Dictionary = data.run
	var n := _rand_range(rng, cfg["terrain"])
	var cells := []
	for i in field.land_cells():
		if data.kind(field.content[i]) != "obstacle":
			cells.append(i)
	_shuffle(cells, rng)
	for k in mini(n, cells.size()):
		field.terrain[cells[k]] = _weighted(rng, cfg["terrain_pool"])


static func pick_event(data, rng: RandomNumberGenerator, index: int) -> String:
	if rng.randf() < float(data.run.get("calm_chance", 0.0)):
		return ""
	var pool := {}
	for e in data.run["events"]:
		if index >= int(e.get("from_field", 1)):
			pool[e["id"]] = e.get("weight", 1)
	return _weighted(rng, pool)


## Задание острова: произвести на острове amount одного цвета.
static func make_task(data, rng: RandomNumberGenerator, index: int) -> Dictionary:
	var tier: Dictionary = {}
	for t in data.run["tasks"]:
		if index >= int(t["from_island"]):
			tier = t
	if tier.is_empty():
		return {}
	var colors: Array = data.colors
	var r: String = colors[rng.randi_range(0, colors.size() - 1)]
	return {r: _rand_range(rng, tier["amount"])}


static func _rand_range(rng: RandomNumberGenerator, r: Array) -> int:
	return rng.randi_range(int(r[0]), int(r[1]))


static func _weighted(rng: RandomNumberGenerator, pool: Dictionary) -> String:
	var total := 0.0
	for k in pool:
		total += float(pool[k])
	var x := rng.randf() * total
	for k in pool:
		x -= float(pool[k])
		if x <= 0.0:
			return k
	return pool.keys()[pool.size() - 1]


static func _shuffle(a: Array, rng: RandomNumberGenerator) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = a[i]
		a[i] = a[j]
		a[j] = t
