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


func next_field() -> void:
	field_number += 1
	board = Board.new()
	history.clear()
	_place_random("rock", _rand_range(data.run.get("rock_cells", [0, 0])))
	var pool: Array = data.run.get("prebuilt_pool", [])
	for _k in _rand_range(data.run.get("prebuilt_cells", [0, 0])):
		if pool.is_empty():
			break
		_place_random(pool[rng.randi_range(0, pool.size() - 1)], 1)
	_pick_goal()
	hand = deck.draw(_rand_range(data.run.get("hand_size", [3, 5])))


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


func _pick_goal() -> void:
	var goals: Array = data.run.get("goals", [])
	if goals.is_empty():
		goal = {"resource": "food", "target": 0, "reward": {}}
		return
	var g: Dictionary = goals[rng.randi_range(0, goals.size() - 1)]
	goal = {
		"resource": g["resource"],
		"target": _rand_range(g["target"]),
		"reward": g.get("reward", {}).duplicate(),
	}


func _place_random(id: String, count: int) -> void:
	for _k in count:
		var free: Array = board.free_cells()
		if free.size() <= 3:
			return  # оставляем место для игры
		var cell: int = free[rng.randi_range(0, free.size() - 1)]
		board.cells[cell] = id
		board.prebuilt[cell] = true


func _rand_range(r) -> int:
	if r is Array and r.size() >= 2:
		return rng.randi_range(int(r[0]), int(r[1]))
	return int(r)
