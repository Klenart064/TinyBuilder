## Забег живой земли: острова по 3 хода, рука 4 карты, до 2 построек за ход,
## после каждого хода ходит земля. Доход копится в казну на весь забег; плата острова,
## боссы и финальная угроза берутся из казны. Жизни теряются от недовольства и нехватки.
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
## Казна на весь забег.
var stock: Dictionary = {}
## Следующее поле (видно заранее): {"field", "event", "task"}
var next_field: Dictionary = {}

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
	stock = data.zero_res()
	for r in data.run.get("start_treasury", {}):
		stock[r] = int(data.run["start_treasury"][r])
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


## Ближайшая угроза после плат острова: босс или финальная. {"name", "cost", "at_field", "final"}
func next_boss() -> Dictionary:
	for b in data.run.get("bosses", []):
		if int(b["at_field"]) >= field_index:
			var d: Dictionary = b.duplicate()
			d["final"] = false
			return d
	var f: Dictionary = data.run.get("final_threat", {}).duplicate()
	f["at_field"] = int(data.run["fields_to_win"])
	f["final"] = true
	return f


## Платёж из пула: свой цвет, нехватку закрывают джокеры. Пул меняется.
## {"missing": n, "wild_used": n, "short": {res: n}}
static func pay(pool: Dictionary, cost: Dictionary) -> Dictionary:
	var out := {"missing": 0, "wild_used": 0, "short": {}}
	for r in cost:
		var c := int(cost[r])
		var own := mini(int(pool.get(r, 0)), c)
		pool[r] = int(pool.get(r, 0)) - own
		var d := c - own
		var w := mini(int(pool.get("wild", 0)), d)
		pool["wild"] = int(pool.get("wild", 0)) - w
		out["wild_used"] += w
		d -= w
		if d > 0:
			out["short"][r] = d
			out["missing"] += d
	return out


## Казна + доход острова сейчас.
func projected(sc: Dictionary = {}) -> Dictionary:
	if sc.is_empty():
		sc = score()
	var p := stock.duplicate()
	for r in sc["total"]:
		p[r] = int(p.get(r, 0)) + int(sc["total"][r])
	return p


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


## Хватает ли казны с доходом острова на плату острова.
func task_done(sc: Dictionary = {}) -> bool:
	return pay(projected(sc), task)["missing"] == 0


## Забрать остров досрочно: плата острова уже есть, оставшиеся ходы земли не наступают.
func finish_early() -> Dictionary:
	if game_over or not task_done():
		return {}
	_history.clear()
	return {"land": {}, "field_done": true, "early": true, "result": _finish_field()}


## Прогресс платы острова: {res: {"have", "need"}}, have — свой цвет + выделенные джокеры.
func task_progress(sc: Dictionary = {}) -> Dictionary:
	var pool := projected(sc)
	var out := {}
	for r in task:
		var need := int(task[r])
		var own := mini(int(pool.get(r, 0)), need)
		pool[r] = int(pool.get(r, 0)) - own
		var w := mini(int(pool.get("wild", 0)), need - own)
		pool["wild"] = int(pool.get("wild", 0)) - w
		out[r] = {"have": own + w, "need": need, "wild": w}
	return out


func _finish_field() -> Dictionary:
	var sc: Dictionary = score()
	var prod: Dictionary = sc["total"]
	var res := {"prod": prod, "task": task.duplicate(), "lives_before": lives, "stock_before": stock.duplicate()}
	for r in prod:
		stock[r] = int(stock.get(r, 0)) + int(prod[r])
	var lpm := int(data.run.get("life_per_missing", 1))
	var t: Dictionary = pay(stock, task)
	res["missing"] = int(t["missing"])
	var lost: int = int(t["missing"]) * lpm
	var discontent := int(sc["discontent"])
	res["discontent"] = discontent
	lost += discontent
	var joy := int(sc.get("joy", 0))
	res["joy"] = joy

	# Босс или финальная угроза на этом острове
	var b: Dictionary = next_boss()
	if int(b.get("at_field", -1)) == field_index:
		var bp: Dictionary = pay(stock, b.get("cost", {}))
		res["boss"] = b
		res["boss_missing"] = int(bp["missing"])
		lost += int(bp["missing"]) * int(b.get("life_per_missing", lpm))
	lives = mini(lives + joy, int(data.run["lives"])) - lost
	res["stock_after"] = stock.duplicate()
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
