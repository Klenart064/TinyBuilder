## Состояние забега: колода, рука, текущее поле, запасы, задание поля и угрозы.
## Здесь нет графики — только правила, чтобы их можно было тестировать без экрана.
extends RefCounted

const Board = preload("res://scripts/core/board.gd")
const Deck = preload("res://scripts/core/deck.gd")

var data
var rng := RandomNumberGenerator.new()
var deck = Deck.new()
var board = Board.new()

var hand: Array = []
var stock: Dictionary = {}
var field_number := 0
## {"resource": "food", "target": 8, "reward": {"gold": 6}}
var goal: Dictionary = {}
var threat_index := 0
var fields_until_threat := 0
## Ходы на текущем поле для отмены: [{"cell", "hand_index", "card"}]
var history: Array = []
var game_over := false
var victory := false
## Карты на выбор после отбитой угрозы (пусто, если выбирать нечего).
var reward_options: Array = []


func start(data_, seed_value: int = -1) -> void:
	data = data_
	if seed_value >= 0:
		rng.seed = seed_value
	else:
		rng.randomize()
	deck = Deck.new()
	deck.setup(data.starter_deck, rng)
	stock = data.zero_resources()
	field_number = 0
	threat_index = 0
	game_over = false
	victory = false
	reward_options = []
	var t = current_threat()
	fields_until_threat = int(t.get("fields", 4))
	next_field()


## Новое поле. Рука тянется первой, потом генератор подбирает поле и задание под неё:
## задание всегда выполнимо этой рукой, а его сложность растёт с номером поля.
func next_field() -> void:
	field_number += 1
	history.clear()
	hand = deck.draw(_rand_range(data.run.get("hand_size", [3, 5])))
	var gen: Dictionary = data.run.get("generation", {})
	var attempts := int(gen.get("max_attempts", 10))
	for attempt in attempts:
		_generate_board(gen)
		if not _has_free_pair():
			continue
		if _pick_goal(board.best_totals(data, hand)):
			return
	# Не нашли хорошее поле — берём пустое, на нём задание точно решаемо.
	board = Board.new()
	if not _pick_goal(board.best_totals(data, hand)):
		_fallback_goal(board.best_totals(data, hand))


func _generate_board(gen: Dictionary) -> void:
	board = Board.new()
	var forbidden: Array = []
	for c in gen.get("rock_forbidden_cells", [4]):
		forbidden.append(int(c))  # JSON отдаёт числа как float
	_place_random("rock", _rand_range(data.run.get("rock_cells", [0, 0])), forbidden)
	var pool: Array = data.run.get("prebuilt_pool", [])
	for _k in _rand_range(data.run.get("prebuilt_cells", [0, 0])):
		if pool.is_empty():
			break
		_place_random(pool[rng.randi_range(0, pool.size() - 1)], 1, [])


## Есть ли хотя бы две свободные соседние клетки (место под комбо).
func _has_free_pair() -> bool:
	for i in board.free_cells():
		for n in Board.neighbors(i):
			if board.is_free(n):
				return true
	return false


## Доля от максимально возможного результата, которую требует задание.
func goal_difficulty() -> float:
	var gen: Dictionary = data.run.get("generation", {})
	var d: Array = gen.get("goal_difficulty", [0.6, 0.95])
	var ramp := float(gen.get("difficulty_ramp_fields", 16))
	var t := clampf(float(field_number - 1) / maxf(ramp, 1.0), 0.0, 1.0)
	var spread := float(gen.get("goal_difficulty_spread", 0.1))
	return clampf(lerpf(float(d[0]), float(d[1]), t) + rng.randf_range(-spread, spread), 0.0, 1.0)


func can_place(hand_index: int, cell: int) -> bool:
	return not game_over and hand_index >= 0 and hand_index < hand.size() and board.is_free(cell)


func place(hand_index: int, cell: int) -> bool:
	if not can_place(hand_index, cell):
		return false
	var card: String = hand[hand_index]
	board.cells[cell] = card
	hand.remove_at(hand_index)
	history.append({"cell": cell, "hand_index": hand_index, "card": card})
	return true


func can_undo() -> bool:
	return not history.is_empty()


func undo() -> bool:
	if history.is_empty():
		return false
	var h: Dictionary = history.pop_back()
	board.cells[h["cell"]] = ""
	hand.insert(mini(h["hand_index"], hand.size()), h["card"])
	return true


func production() -> Dictionary:
	return board.evaluate(data)


func goal_progress() -> int:
	return int(production()["total"].get(goal.get("resource", ""), 0))


func current_threat() -> Dictionary:
	var list: Array = data.run.get("threats", [])
	if threat_index < list.size():
		return list[threat_index]
	return {}


## Завершает поле: доход идёт в запасы, проверяется задание и угроза.
## Возвращает отчёт для экрана итогов.
func finish_field() -> Dictionary:
	var report := {}
	var total: Dictionary = production()["total"]
	report["income"] = total.duplicate()
	_add_stock(total, 1)

	var goal_done := int(total.get(goal["resource"], 0)) >= int(goal["target"])
	report["goal"] = goal.duplicate(true)
	report["goal_done"] = goal_done
	if goal_done:
		_add_stock(goal["reward"], 1)

	# Сыгранные и несыгранные карты уходят в сброс. Заранее построенное — не карты игрока.
	var used := []
	for h in history:
		used.append(h["card"])
	deck.discard(used)
	deck.discard(hand)
	hand = []
	history.clear()

	fields_until_threat -= 1
	if fields_until_threat <= 0:
		var threat := current_threat()
		var need: Dictionary = threat.get("need", {})
		var passed := has_resources(need)
		report["threat"] = threat.duplicate(true)
		report["threat_passed"] = passed
		if passed:
			_add_stock(need, -1)
			threat_index += 1
			reward_options = _roll_rewards()
			report["rewards"] = reward_options.duplicate()
			var next := current_threat()
			if next.is_empty():
				victory = true
				game_over = true
			else:
				fields_until_threat = int(next.get("fields", 4))
		else:
			game_over = true
	report["stock"] = stock.duplicate()
	return report


## Игрок выбрал награду: карта добавляется в колоду.
func choose_reward(index: int) -> void:
	if index >= 0 and index < reward_options.size():
		deck.add_card(reward_options[index])
	reward_options = []


func _roll_rewards() -> Array:
	var pool: Array = data.run.get("reward_pool", []).duplicate()
	var out := []
	for _k in int(data.run.get("reward_choices", 3)):
		if pool.is_empty():
			break
		var i := rng.randi_range(0, pool.size() - 1)
		out.append(pool[i])
		pool.remove_at(i)
	return out


func has_resources(need: Dictionary) -> bool:
	for res in need:
		if int(stock.get(res, 0)) < int(need[res]):
			return false
	return true


func _add_stock(amounts: Dictionary, sign_: int) -> void:
	for res in amounts:
		stock[res] = int(stock.get(res, 0)) + int(amounts[res]) * sign_


## Выбирает задание, которое можно выполнить этой рукой. false — подходящих нет.
func _pick_goal(best: Dictionary) -> bool:
	var options := []
	for g in data.run.get("goals", []):
		if int(best.get(g["resource"], 0)) >= int(g.get("min_target", 1)):
			options.append(g)
	if options.is_empty():
		return false
	var g: Dictionary = options[rng.randi_range(0, options.size() - 1)]
	var top := int(best[g["resource"]])
	var target := clampi(roundi(top * goal_difficulty()), int(g.get("min_target", 1)), top)
	goal = {
		"resource": g["resource"],
		"target": target,
		"best": top,
		"reward": g.get("reward", {}).duplicate(),
	}
	return true


func _fallback_goal(best: Dictionary) -> void:
	var res: String = data.resources.keys()[0]
	for r in best:
		if int(best[r]) > int(best[res]):
			res = r
	var reward := {}
	var goals: Array = data.run.get("goals", [])
	if not goals.is_empty():
		reward = goals[0].get("reward", {}).duplicate()
	goal = {"resource": res, "target": maxi(int(best[res]), 0), "best": int(best[res]), "reward": reward}


func _place_random(id: String, count: int, forbidden: Array) -> void:
	for _k in count:
		var free: Array = []
		for c in board.free_cells():
			if not (c in forbidden):
				free.append(c)
		if board.free_cells().size() <= 4 or free.is_empty():
			return  # оставляем место для игры
		var cell: int = free[rng.randi_range(0, free.size() - 1)]
		board.cells[cell] = id
		board.prebuilt[cell] = true


func _rand_range(r) -> int:
	if r is Array and r.size() >= 2:
		return rng.randi_range(int(r[0]), int(r[1]))
	return int(r)
