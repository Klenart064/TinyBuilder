## Забег живой земли: поля по 3 хода, рука 4 карты, до 2 построек за ход,
## после каждого хода ходит земля. Жизни теряются от недовольства и невыполненных заданий.
extends RefCounted

const Deck = preload("res://scripts/core/deck.gd")
const LandField = preload("res://scripts/land/land_field.gd")
const LandGen = preload("res://scripts/land/land_gen.gd")
const LandEvents = preload("res://scripts/land/land_events.gd")

var data
var rng := RandomNumberGenerator.new()
var deck = Deck.new()

var lives := 0
var field_index := 0
var field
var event_type := ""
var intent: Dictionary = {}
var task: Dictionary = {}
var turn := 1
var plays_left := 0
var hand: Array = []
## Излишки прошлого поля (живут одно поле).
var carry: Dictionary = {}
## Следующее поле (видно заранее): {"field", "event", "task"}
var next_field: Dictionary = {}

var global_index := 0
var global_progress := 0
var global_start := 1

var reward_options: Array = []
var game_over := false
var victory := false

var _history: Array = []


func start(data_, seed: int = -1) -> void:
	data = data_
	if seed >= 0:
		rng.seed = seed
	else:
		rng.randomize()
	deck = Deck.new()
	deck.setup(data.starter_deck, rng)
	lives = int(data.run["lives"])
	field_index = 0
	carry = data.zero_res()
	global_index = 0
	global_progress = 0
	global_start = 1
	game_over = false
	victory = false
	reward_options = []
	next_field = LandGen.make_field(data, rng, 1)
	_enter_next_field()


func _enter_next_field() -> void:
	field_index += 1
	field = next_field["field"]
	event_type = next_field["event"]
	task = next_field["task"]
	next_field = LandGen.make_field(data, rng, field_index + 1)
	deck.discard(hand)
	hand = deck.draw(int(data.run["hand_size"]))
	turn = 1
	plays_left = int(data.run["plays_per_turn"])
	_history.clear()
	intent = LandEvents.plan(event_type, field, data, rng)


func event_info() -> Dictionary:
	return data.events.get(event_type, {})


func global_threat() -> Dictionary:
	var list: Array = data.run["global_threats"]
	return list[global_index % list.size()]


func global_end_field() -> int:
	return global_start + int(global_threat()["fields"]) - 1


func score() -> Dictionary:
	return field.score(data)


func can_place(hand_idx: int, cell: int) -> bool:
	return not game_over and plays_left > 0 and hand_idx >= 0 and hand_idx < hand.size() and field.is_free(cell)


## Ставит карту из руки. Возвращает {"ok", "razed": [клетки снесённых логов]}.
func place(hand_idx: int, cell: int) -> Dictionary:
	if not can_place(hand_idx, cell):
		return {"ok": false, "razed": []}
	_history.append({"field": field.to_dict(), "hand": hand.duplicate(), "plays": plays_left})
	var id: String = hand[hand_idx]
	hand.remove_at(hand_idx)
	var razed: Array = field.place_building(data, cell, id)
	plays_left -= 1
	deck.discard([id])
	return {"ok": true, "razed": razed}


func can_undo() -> bool:
	return not _history.is_empty()


func undo() -> bool:
	if _history.is_empty():
		return false
	var h: Dictionary = _history.pop_back()
	field.from_dict(h["field"])
	# Карта возвращается в руку из сброса
	var placed := _diff_card(h["hand"], hand)
	if placed != "":
		var k: int = deck.discard_pile.rfind(placed)
		if k >= 0:
			deck.discard_pile.remove_at(k)
	hand = h["hand"]
	plays_left = h["plays"]
	return true


static func _diff_card(before: Array, after: Array) -> String:
	var rest := after.duplicate()
	for id in before:
		var k := rest.find(id)
		if k >= 0:
			rest.remove_at(k)
		else:
			return id
	return ""


## Конец хода игрока: ход земли, добор руки, при последнем ходе — итог поля.
## {"land": отчёт земли, "field_done": bool, "result": итог поля (если field_done)}
func end_turn() -> Dictionary:
	if game_over:
		return {}
	var land: Dictionary = LandEvents.apply(intent, field, data)
	_history.clear()
	var out := {"land": land, "field_done": false}
	if turn >= int(data.run["turns_per_field"]):
		out["field_done"] = true
		out["result"] = _finish_field()
		return out
	turn += 1
	plays_left = int(data.run["plays_per_turn"])
	var need := int(data.run["hand_size"]) - hand.size()
	if need > 0:
		hand.append_array(deck.draw(need))
	intent = LandEvents.plan(event_type, field, data, rng)
	return out


## Выполнено ли задание прямо сейчас (с учётом запаса).
func task_done(sc: Dictionary = {}) -> bool:
	var prog := task_progress(sc)
	for r in prog:
		if prog[r]["have"] < prog[r]["need"]:
			return false
	return true


## Забрать остров досрочно: задание выполнено, оставшиеся ходы земли не наступают.
func finish_early() -> Dictionary:
	if game_over or not task_done():
		return {}
	_history.clear()
	return {"land": {}, "field_done": true, "early": true, "result": _finish_field()}


## Излишки сверх задания прямо сейчас: {res: n}
func surplus(sc: Dictionary = {}) -> Dictionary:
	if sc.is_empty():
		sc = score()
	var out: Dictionary = data.zero_res()
	for r in data.resources:
		var p := int(sc["total"].get(r, 0))
		var need := int(task.get(r, 0))
		var still := need - mini(int(carry.get(r, 0)), need)
		out[r] = maxi(0, p - still)
	return out


func wagon_capacity() -> int:
	return int(data.run.get("wagon_capacity", 3))


## Повозка: что из излишков поедет на следующий остров. Кладётся только то,
## что нужно в задании следующего острова (сначала больший спрос), не больше вместимости.
func wagon_load(sc: Dictionary = {}) -> Dictionary:
	var sur := surplus(sc)
	var need: Dictionary = next_field.get("task", {})
	var order: Array = need.keys()
	order.sort_custom(func(a, b): return int(need[a]) > int(need[b]))
	var load: Dictionary = data.zero_res()
	var room := wagon_capacity()
	for r in order:
		var k := mini(mini(int(sur.get(r, 0)), int(need[r])), room)
		load[r] = k
		room -= k
	return load


## Совместимость: то же, что wagon_load.
func carry_preview(sc: Dictionary = {}) -> Dictionary:
	return wagon_load(sc)

func task_progress(sc: Dictionary = {}) -> Dictionary:
	if sc.is_empty():
		sc = score()
	var out := {}
	for r in task:
		var prod := int(sc["total"].get(r, 0))
		var c := int(carry.get(r, 0))
		out[r] = {"have": prod + c, "need": int(task[r]), "carry": c, "prod": prod}
	return out


func _finish_field() -> Dictionary:
	var sc: Dictionary = score()
	var prod: Dictionary = sc["total"]
	var missing := 0
	var new_carry: Dictionary = wagon_load(sc)
	for r in data.resources:
		var p := int(prod.get(r, 0))
		var need := int(task.get(r, 0))
		var from_carry := mini(int(carry.get(r, 0)), need)
		var still := need - from_carry
		missing += maxi(0, still - p)
	var discontent := int(sc["discontent"])
	var res := {"prod": prod, "task": task.duplicate(), "carry_in": carry.duplicate(), "carry_out": new_carry,
		"missing": missing, "discontent": discontent, "lives_before": lives, "surplus": surplus(sc)}
	lives -= missing + discontent
	carry = new_carry

	# Глобальная угроза
	var g: Dictionary = global_threat()
	global_progress += int(prod.get(g["resource"], 0))
	res["global"] = g
	res["global_progress"] = global_progress
	if field_index >= global_end_field():
		res["global_checked"] = true
		res["global_passed"] = global_progress >= int(g["need"])
		if not res["global_passed"]:
			lives -= int(g.get("penalty", 3))
		global_index += 1
		global_progress = 0
		global_start = field_index + 1
	res["lives_after"] = lives

	if lives <= 0:
		lives = 0
		game_over = true
	elif field_index >= int(data.run["fields_to_win"]):
		game_over = true
		victory = true
	else:
		reward_options = _make_rewards()
	return res


func _make_rewards() -> Array:
	var pool: Array = data.run["reward_pool"].duplicate()
	var out := []
	for _k in int(data.run.get("reward_choices", 3)):
		if pool.is_empty():
			break
		var i := rng.randi_range(0, pool.size() - 1)
		out.append(pool[i])
		pool.remove_at(i)
	return out


## Выбор после поля: индекс карты из reward_options или -1 = отдых (+жизнь). Затем следующее поле.
func choose_reward(i: int) -> void:
	if i >= 0 and i < reward_options.size():
		deck.add_card(reward_options[i])
	else:
		lives = mini(lives + int(data.run.get("rest_heal", 1)), int(data.run["lives"]))
	reward_options = []
	_enter_next_field()
