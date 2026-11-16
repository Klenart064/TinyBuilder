## Генерация полей живой земли: форма, препятствия, местность, событие, задание.
extends RefCounted

const LandField = preload("res://scripts/land/land_field.gd")


## Новое поле: {"field", "event": id, "task": {res: n}}
static func make_field(data, rng: RandomNumberGenerator, index: int) -> Dictionary:
	var cfg: Dictionary = data.run
	var field = null
	for _attempt in 30:
		field = _shape(rng, _rand_range(rng, cfg["shape_cells"]))
		_place_obstacles(field, data, rng)
		_place_terrain(field, data, rng)
		if field.free_cells().size() >= int(cfg.get("min_free_cells", 6)):
			break
	return {"field": field, "event": pick_event(data, rng, index), "task": make_task(data, rng, index)}


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
	var pool := {}
	for e in data.run["events"]:
		if index >= int(e.get("from_field", 1)):
			pool[e["id"]] = e.get("weight", 1)
	return _weighted(rng, pool)


## Задание поля: шаблон по номеру поля, числа раздаются случайным ресурсам.
static func make_task(data, rng: RandomNumberGenerator, index: int) -> Dictionary:
	var tiers: Array = data.run["tasks"]
	var tier: Dictionary = tiers[tiers.size() - 1]
	for t in tiers:
		if index >= int(t["fields"][0]) and index <= int(t["fields"][1]):
			tier = t
			break
	var patterns: Array = tier["patterns"]
	var pat: Array = patterns[rng.randi_range(0, patterns.size() - 1)].duplicate()
	var res: Array = data.resources.keys()
	_shuffle(res, rng)
	var task := {}
	for k in mini(pat.size(), res.size()):
		task[res[k]] = int(pat[k])
	return task


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
