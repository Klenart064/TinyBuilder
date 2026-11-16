## Забег живой земли. Забег делится на спринты: на каждом шаге выбор из нескольких островов,
## последний остров спринта может быть боссом, после спринта — рынок.
## Остров: 3 хода, рука 4 карты, до 2 построек за ход, после хода ходит земля (если не спокойно).
## Доход островов копится в казну и тратится на рынке. Жизни теряются от недовольства
## и нехватки на боссах; задания островов только дают награду.
extends RefCounted

const Deck = preload("res://scripts/core/deck.gd")
const LandField = preload("res://scripts/land/land_field.gd")
const LandGen = preload("res://scripts/land/land_gen.gd")
const LandEvents = preload("res://scripts/land/land_events.gd")

var data
var rng := RandomNumberGenerator.new()
var deck = Deck.new()

var lives := 0
var stock: Dictionary = {}

## Номер острова в забеге (1…)
var field_index := 0
var sprint := 0           # индекс спринта
var layer := 0            # шаг внутри спринта (0…layers-1)
## Текущий остров: {"field", "event", "task", "danger", "reward", "task_reward", "boss"}
var island: Dictionary = {}
## Варианты следующего острова (карта): [остров, ...]
var choices: Array = []
## Что делать после итога острова: "map", "market", "over"
var phase := "map"

var field
var event_type := ""
var intent: Dictionary = {}
var task: Dictionary = {}
var turn := 1
var plays_left := 0
var hand: Array = []

## Контракт рынка на спринт: {"res", "amount", "reward", "progress", "sprint"} или {}
var contract: Dictionary = {}
## Предложения рынка: {"buy": [id...], "contract": {...}, "bought": [bool...]}
var market: Dictionary = {}

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
	stock = data.zero_res()
	for r in data.run.get("start_treasury", {}):
		stock[r] = int(data.run["start_treasury"][r])
	field_index = 0
	sprint = 0
	layer = 0
	contract = {}
	market = {}
	game_over = false
	victory = false
	hand = []
	island = {}
	field = LandField.new()
	event_type = ""
	intent = {}
	task = {}
	turn = 1
	plays_left = 0
	phase = "map"
	_make_choices()


# ---------------------------------------------------------------- карта забега

func sprints() -> Array:
	return data.run["sprints"]


func sprint_info() -> Dictionary:
	return sprints()[sprint]


func total_islands() -> int:
	var n := 0
	for s in sprints():
		n += int(s["layers"])
	return n


## Остров с боссом на этом шаге? (последний шаг спринта с boss)
func _boss_here() -> Dictionary:
	var s: Dictionary = sprint_info()
	if s.has("boss") and layer == int(s["layers"]) - 1:
		return s["boss"]
	return {}


## Ближайший босс впереди (для подсказки): {"name", "need", "islands_left"} или {}
func next_boss() -> Dictionary:
	var left := 0
	for si in range(sprint, sprints().size()):
		var s: Dictionary = sprints()[si]
		var from := layer if si == sprint else 0
		for li in range(from, int(s["layers"])):
			if s.has("boss") and li == int(s["layers"]) - 1:
				var b: Dictionary = s["boss"].duplicate()
				b["islands_left"] = left
				return b
			left += 1
	return {}


func _make_choices() -> void:
	choices = []
	var boss := _boss_here()
	var n := 1 if not boss.is_empty() else int(data.run.get("choices", 2))
	for _k in n:
		var isl: Dictionary = LandGen.make_field(data, rng, field_index + 1)
		if not boss.is_empty():
			isl["boss"] = boss
			isl["task"] = {}
			isl["event"] = ""
			isl["danger"] = false
		choices.append(isl)


## Выбор острова на карте и вход на него.
func choose_island(i: int) -> void:
	if phase != "map" or i < 0 or i >= choices.size():
		return
	island = choices[i]
	choices = []
	field_index += 1
	field = island["field"]
	event_type = island["event"]
	task = island["task"]
	deck.discard(hand)
	hand = deck.draw(int(data.run["hand_size"]))
	turn = 1
	plays_left = int(data.run["plays_per_turn"])
	_history.clear()
	intent = LandEvents.plan(event_type, field, data, rng)
	phase = "island"


func event_info() -> Dictionary:
	return data.events.get(event_type, {"name": "Спокойная земля", "desc": "Земля на этом острове не двигается."})


func is_boss() -> bool:
	return island.has("boss")


# ---------------------------------------------------------------- остров

func score() -> Dictionary:
	return field.score(data)


func can_place(hand_idx: int, cell: int) -> bool:
	return phase == "island" and plays_left > 0 and hand_idx >= 0 and hand_idx < hand.size() and field.is_free(cell)


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


## Конец хода игрока: ход земли, добор руки, при последнем ходе — итог острова.
func end_turn() -> Dictionary:
	if phase != "island":
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


## Задание острова выполнено (произведено на острове сейчас)?
func task_done(sc: Dictionary = {}) -> bool:
	if task.is_empty():
		return false
	if sc.is_empty():
		sc = score()
	for r in task:
		if int(sc["total"].get(r, 0)) < int(task[r]):
			return false
	return true


## Забрать остров досрочно (когда задание выполнено): земля больше не ходит.
func finish_early() -> Dictionary:
	if phase != "island" or not task_done():
		return {}
	_history.clear()
	return {"land": {}, "field_done": true, "early": true, "result": _finish_field()}


## Сколько всего производит остров (джокеры тоже) — для босса.
static func total_of(sc: Dictionary) -> int:
	var n := 0
	for r in sc["total"]:
		n += int(sc["total"][r])
	return n


func _add_stock(d: Dictionary) -> void:
	for r in d:
		stock[r] = int(stock.get(r, 0)) + int(d[r])


func _finish_field() -> Dictionary:
	var sc: Dictionary = score()
	var prod: Dictionary = sc["total"]
	var res := {"prod": prod, "lives_before": lives, "island": island}
	_add_stock(prod)
	_add_stock(island.get("reward", {}))
	res["reward"] = island.get("reward", {})
	res["task"] = task.duplicate()
	res["task_done"] = task_done(sc)
	if res["task_done"]:
		_add_stock(island.get("task_reward", {}))
	var lost := int(sc["discontent"])
	res["discontent"] = int(sc["discontent"])
	res["joy"] = int(sc.get("joy", 0))
	if is_boss():
		var b: Dictionary = island["boss"]
		var total := total_of(sc)
		res["boss"] = b
		res["boss_total"] = total
		res["boss_missing"] = maxi(0, int(b["need"]) - total)
		lost += int(res["boss_missing"]) * int(b.get("life_per_missing", 1))
	# Контракт спринта
	if not contract.is_empty() and int(contract["sprint"]) == sprint:
		contract["progress"] = int(contract["progress"]) + int(prod.get(contract["res"], 0))
	lives = mini(lives + int(res["joy"]), int(data.run["lives"])) - lost
	res["lives_after"] = lives
	deck.discard(hand)
	hand = []

	var last_layer := layer >= int(sprint_info()["layers"]) - 1
	if lives <= 0:
		lives = 0
		game_over = true
		phase = "over"
	elif last_layer and sprint >= sprints().size() - 1:
		game_over = true
		victory = true
		phase = "over"
	elif last_layer:
		res["contract"] = _settle_contract()
		phase = "market"
		_make_market()
	else:
		layer += 1
		phase = "map"
		_make_choices()
	res["stock_after"] = stock.duplicate()
	return res


func _settle_contract() -> Dictionary:
	if contract.is_empty() or int(contract["sprint"]) != sprint:
		return {}
	var c := contract.duplicate()
	c["done"] = int(c["progress"]) >= int(c["amount"])
	if c["done"]:
		_add_stock(c["reward"])
	contract = {}
	return c


# ---------------------------------------------------------------- рынок

func market_cfg() -> Dictionary:
	return data.run["market"]


func _make_market() -> void:
	var pool: Array = data.run["buy_pool"].duplicate()
	var buy := []
	for _k in int(market_cfg().get("buy_offers", 3)):
		if pool.is_empty():
			break
		var i := rng.randi_range(0, pool.size() - 1)
		buy.append(pool[i])
		pool.remove_at(i)
	var cc: Dictionary = market_cfg().get("contract", {})
	var colors: Array = data.colors
	var con := {"res": colors[rng.randi_range(0, colors.size() - 1)],
		"amount": rng.randi_range(int(cc["amount"][0]), int(cc["amount"][1])),
		"reward": cc.get("reward", {}), "progress": 0}
	market = {"buy": buy, "bought": buy.map(func(_x): return false), "contract": con, "contract_taken": false}


## Цена карты на рынке: {res: n}; у жилья и городских — {"any": n}.
func buy_price(id: String) -> Dictionary:
	var n := int(market_cfg()["buy_cost"].get(data.role(id), 4))
	var c: String = data.color_of(id)
	return {c: n} if data.colors.has(c) else {"any": n}


func upgrade_price(id: String) -> Dictionary:
	var n := int(market_cfg().get("upgrade_cost", 5))
	var c: String = data.color_of(id)
	return {c: n} if data.colors.has(c) else {"any": n}


## Хватает ли казны на цену (any — любые ресурсы, своего цвета не хватает — джокеры).
func can_afford(price: Dictionary) -> bool:
	var pool := stock.duplicate()
	return _pay_into(pool, price)


func _pay_into(pool: Dictionary, price: Dictionary) -> bool:
	for r in price:
		var n := int(price[r])
		if r == "any":
			var total := 0
			for k in pool:
				total += int(pool[k])
			if total < n:
				return false
			# Сначала самые большие кучи, джокеры в последнюю очередь
			while n > 0:
				var best := ""
				for k in pool:
					if k == "wild" and best != "":
						continue
					if best == "" or (int(pool[k]) > int(pool[best]) and k != "wild") or best == "wild":
						if int(pool[k]) > 0:
							best = k
				if best == "":
					return false
				pool[best] = int(pool[best]) - 1
				n -= 1
		else:
			var own := mini(int(pool.get(r, 0)), n)
			pool[r] = int(pool.get(r, 0)) - own
			var d := n - own
			if int(pool.get("wild", 0)) < d:
				return false
			pool["wild"] = int(pool.get("wild", 0)) - d
	return true


func _spend(price: Dictionary) -> bool:
	var pool := stock.duplicate()
	if not _pay_into(pool, price):
		return false
	stock = pool
	return true


func buy(i: int) -> bool:
	if phase != "market" or i < 0 or i >= market["buy"].size() or market["bought"][i]:
		return false
	var id: String = market["buy"][i]
	if not _spend(buy_price(id)):
		return false
	deck.add_card(id)
	market["bought"][i] = true
	return true


## Все карты колоды (для экрана колоды и рынка).
func all_cards() -> Array:
	return deck.draw_pile + deck.discard_pile + hand


func upgrade(id: String) -> bool:
	if phase != "market" or not data.can_upgrade(id) or not _has_card(id):
		return false
	if not _spend(upgrade_price(id)):
		return false
	_replace_card(id, id + "+")
	return true


func remove(id: String) -> bool:
	if phase != "market" or not _has_card(id) or all_cards().size() <= int(data.run["hand_size"]) + 2:
		return false
	if not _spend({"any": int(market_cfg().get("remove_cost", 3))}):
		return false
	_replace_card(id, "")
	return true


func heal() -> bool:
	if phase != "market" or lives >= int(data.run["lives"]):
		return false
	if not _spend({"any": int(market_cfg().get("heal_cost", 4))}):
		return false
	lives = mini(lives + int(market_cfg().get("heal_lives", 2)), int(data.run["lives"]))
	return true


func take_contract() -> bool:
	if phase != "market" or market.get("contract_taken", false):
		return false
	contract = market["contract"].duplicate()
	contract["sprint"] = sprint + 1
	market["contract_taken"] = true
	return true


## Уйти с рынка в следующий спринт.
func leave_market() -> void:
	if phase != "market":
		return
	sprint += 1
	layer = 0
	market = {}
	phase = "map"
	_make_choices()


func _has_card(id: String) -> bool:
	return id in all_cards()


func _replace_card(id: String, to: String) -> void:
	for pile in [deck.draw_pile, deck.discard_pile, hand]:
		var k: int = pile.find(id)
		if k >= 0:
			if to == "":
				pile.remove_at(k)
			else:
				pile[k] = to
			return
