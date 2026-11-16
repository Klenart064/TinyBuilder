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
const ShapeField = preload("res://scripts/land/shape_field.gd")

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
## Карта забега: [спринт][шаг] → [остров, ...]; pos_lane — дорожка, где стоит игрок (-1 — начало спринта)
var run_map: Array = []
var pos_lane := -1
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

## Доход острова от Эхо (сверх обычного, уже лежит в казне)
var echo_gain: Dictionary = {}
## Сталь с островов-кузниц: босс тратит одну и требует меньше
var steel := 0

var _history: Array = []

## Босс-куб: нужно выбрать, куда катить (в начале каждого хода)
var cube_roll := false
## Эхо, накопленное до начала этого хода (на печать идёт только эхо текущего хода)
var cube_echo_base: Dictionary = {}
## Жизни, снятые печатями за бой
var cube_lost := 0


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
	pos_lane = -1
	steel = 0
	_gen_map()
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


## Вся карта забега генерируется сразу: map[спринт][шаг] = [остров, ...].
## У острова "lane" (дорожка) и "next" — дорожки следующего шага, куда из него можно пойти.
## Последний шаг спринта с боссом — один остров. После спринта — рынок, с него можно на любой остров.
func _gen_map() -> void:
	run_map = []
	var lanes := int(data.run.get("lanes", 3))
	var idx := 0
	for si in sprints().size():
		var s: Dictionary = sprints()[si]
		var layers := []
		for li in int(s["layers"]):
			idx += 1
			var boss: Dictionary = s["boss"] if s.has("boss") and li == int(s["layers"]) - 1 else {}
			var n := 1 if not boss.is_empty() else lanes
			var row := []
			for k in n:
				var isl: Dictionary = LandGen.make_field(data, rng, idx)
				isl["lane"] = k if boss.is_empty() else (lanes - 1) / 2
				isl["sprint"] = si
				isl["layer"] = li
				isl["next"] = []
				isl["visited"] = false
				if not boss.is_empty():
					isl["boss"] = boss
					isl["task"] = {}
					isl["event"] = ""
					isl["danger"] = false
					isl["reward"] = s.get("boss_reward", isl["reward"])
					isl["big"] = false
					isl["turns"] = int(data.run["turns_per_field"])
					if boss.has("cube"):
						isl["field"] = ShapeField.make(data, rng, boss["cube"])
						isl["turns"] = int(boss["cube"].get("max_turns", 12))
				row.append(isl)
			layers.append(row)
		# Острова-кузницы: по forges_per_sprint на спринт среди обычных островов
		var pool := []
		for row in layers:
			for isl in row:
				if not isl.has("boss"):
					pool.append(isl)
		for _k in int(data.run.get("forges_per_sprint", 0)):
			if pool.is_empty():
				break
			var fi := rng.randi_range(0, pool.size() - 1)
			LandGen.add_forge(pool[fi], data, rng)
			pool.remove_at(fi)
		# Связи между шагами: соседние дорожки, у каждого острова 1–2 выхода, у каждого есть вход
		for li in layers.size() - 1:
			var cur: Array = layers[li]
			var nxt: Array = layers[li + 1]
			if nxt.size() == 1 or cur.size() == 1:
				for isl in cur:
					isl["next"] = range(nxt.size())
				continue
			for isl in cur:
				var l: int = isl["lane"]
				var opts := [l]
				if l > 0 and rng.randf() < 0.5:
					opts.append(l - 1)
				if l < nxt.size() - 1 and rng.randf() < 0.5:
					opts.append(l + 1)
				isl["next"] = opts
			for t in nxt.size():
				var has_in := false
				for isl in cur:
					if t in isl["next"]:
						has_in = true
				if not has_in:
					cur[clampi(t, 0, cur.size() - 1)]["next"].append(t)
		run_map.append(layers)


## Острова, доступные на текущем шаге (по пути от предыдущего острова).
func _make_choices() -> void:
	var row: Array = run_map[sprint][layer]
	if layer == 0 or pos_lane < 0:
		choices = row.duplicate()
		return
	var prev: Dictionary = {}
	for isl in run_map[sprint][layer - 1]:
		if int(isl["lane"]) == pos_lane:
			prev = isl
	choices = []
	for isl in row:
		if int(isl["lane"]) in prev.get("next", []) or row.size() == 1:
			choices.append(isl)


## Выбор острова на карте и вход на него.
func choose_island(i: int) -> void:
	if phase != "map" or i < 0 or i >= choices.size():
		return
	island = choices[i]
	island["visited"] = true
	pos_lane = int(island["lane"])
	choices = []
	field_index += 1
	field = island["field"]
	event_type = island["event"]
	task = island["task"]
	# Колода заново на каждом острове: все карты перемешиваются в добор
	deck.draw_pile = all_cards()
	deck.discard_pile = []
	deck._shuffle(deck.draw_pile)
	hand = deck.draw(int(data.run["hand_size"]))
	echo_gain = data.zero_res()
	turn = 1
	plays_left = plays_per_turn()
	_history.clear()
	intent = LandEvents.plan(event_type, field, data, rng)
	phase = "island"
	cube_roll = is_cube() and not field.one_way()
	cube_lost = 0
	cube_echo_base = echo_gain.duplicate()
	if is_cube() and steel > 0 and not island.get("steel_applied", false):
		field.scale_seals(float(data.run.get("steel_boss_mult", 1.0)))
		island["steel_applied"] = true
		steel -= 1


## Ходов на этом острове (большие — больше).
func turns_here() -> int:
	return int(island.get("turns", data.run["turns_per_field"]))


## Требование босса с учётом стали.
func boss_need(b: Dictionary = {}) -> int:
	if b.is_empty():
		b = island.get("boss", {})
	var n := int(b.get("need", 0))
	if steel > 0:
		n = int(ceil(n * float(data.run.get("steel_boss_mult", 1.0))))
	return n


func event_info() -> Dictionary:
	return data.events.get(event_type, {"name": "Спокойная земля", "desc": "Земля на этом острове не двигается."})


func is_boss() -> bool:
	return island.has("boss")


## Сколько построек за ход (у куба может быть своё число).
func plays_per_turn() -> int:
	if is_cube():
		return int(cube_cfg().get("plays_per_turn", data.run["plays_per_turn"]))
	return int(data.run["plays_per_turn"])


## Бой с кубом: остров из 6 граней с печатями.
func is_cube() -> bool:
	return island.has("boss") and island["boss"].has("cube")


func cube_cfg() -> Dictionary:
	return island.get("boss", {}).get("cube", {})


## Куда можно катить куб: на любую соседнюю грань. Грань без печати — передышка
## (не бьёт, можно готовить рёбра для соседних граней), но ходов в бою ограничено.
func roll_options() -> Array:
	if not is_cube() or not cube_roll:
		return []
	return field.roll_targets()


func roll(face: int) -> bool:
	if phase != "island" or not (face in roll_options()):
		return false
	field.roll_to(face)
	cube_roll = false
	cube_echo_base = echo_gain.duplicate()
	_history.clear()
	return true


## Что верхняя грань даст на печать сейчас: доход грани + Эхо этого хода.
func cube_have(sc: Dictionary = {}) -> Dictionary:
	if sc.is_empty():
		sc = score()
	var t: Dictionary = sc["total"].duplicate()
	for r in echo_gain:
		t[r] = int(t.get(r, 0)) + int(echo_gain[r]) - int(cube_echo_base.get(r, 0))
	return t


func cube_shortfall(face: int = -1, sc: Dictionary = {}) -> int:
	if face < 0:
		face = field.top()
	if sc.is_empty():
		sc = score()
	var have: Dictionary = cube_have(sc) if face == field.top() else sc["faces"][face]
	return ShapeField.shortfall(have, field.seals[face])


# ---------------------------------------------------------------- остров

func score() -> Dictionary:
	return field.score(data)


func can_place(hand_idx: int, cell: int) -> bool:
	if is_cube() and cube_roll:
		return false
	return phase == "island" and plays_left > 0 and hand_idx >= 0 and hand_idx < hand.size() and field.is_free(cell)


## Ставит карту из руки. Возвращает {"ok", "razed": [клетки снесённых логов]}.
func place(hand_idx: int, cell: int) -> Dictionary:
	if not can_place(hand_idx, cell):
		return {"ok": false, "razed": []}
	_history.append({"field": field.to_dict(), "hand": hand.duplicate(), "plays": plays_left, "stock": stock.duplicate(), "echo": echo_gain.duplicate()})
	var id: String = hand[hand_idx]
	hand.remove_at(hand_idx)
	var razed: Array = field.place_building(data, cell, id)
	plays_left -= 1
	deck.discard([id])
	var steps: Array = field.echo(data, cell, data.echo_level(id))
	var gain: Dictionary = LandField.cascade_total(steps)
	_add_stock(gain)
	for r in gain:
		echo_gain[r] = int(echo_gain.get(r, 0)) + int(gain[r])
	return {"ok": true, "razed": razed, "echo": steps, "gain": gain}


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
	stock = h["stock"]
	echo_gain = h["echo"]
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
	if is_cube():
		return _cube_end_turn()
	var land: Dictionary = LandEvents.apply(intent, field, data)
	_history.clear()
	var out := {"land": land, "field_done": false}
	if turn >= turns_here():
		out["field_done"] = true
		out["result"] = _finish_field()
		return out
	# Остров из частей: смена острова, поворот или переворот
	if field.has_method("advance"):
		out["shift"] = field.advance()
	turn += 1
	plays_left = plays_per_turn()
	var need := int(data.run["hand_size"]) - hand.size()
	if need > 0:
		hand.append_array(deck.draw(need))
	intent = LandEvents.plan(event_type, field, data, rng)
	return out


## Ход с кубом: проверка верхней печати. Хватает — печать снята, нет — минус жизни за нехватку.
func _cube_end_turn() -> Dictionary:
	if cube_roll:
		return {}
	_history.clear()
	var f: int = field.top()
	var sc: Dictionary = score()
	var judge := {"face": f, "seal": field.seals[f].duplicate(), "have": cube_have(sc), "miss": 0, "broken": false, "was_broken": field.broken[f]}
	if not field.broken[f]:
		var miss := cube_shortfall(f, sc)
		judge["miss"] = miss
		if miss == 0:
			field.broken[f] = true
			judge["broken"] = true
		else:
			var lost := miss * int(island["boss"].get("life_per_missing", 1))
			lives -= lost
			cube_lost += lost
	var out := {"land": {}, "field_done": false, "cube": judge}
	if lives <= 0 or field.sealed_faces().is_empty() or turn >= turns_here():
		out["field_done"] = true
		out["result"] = _finish_field()
		return out
	turn += 1
	plays_left = plays_per_turn()
	var need := int(data.run["hand_size"]) - hand.size()
	if need > 0:
		hand.append_array(deck.draw(need))
	cube_roll = true
	return out


## Задание острова выполнено (произведено на острове сейчас)?
func task_done(_sc: Dictionary = {}) -> bool:
	if task.is_empty():
		return false
	var inc := income()
	for r in task:
		if int(inc.get(r, 0)) < int(task[r]):
			return false
	return true


## Забрать остров досрочно (когда задание выполнено): земля больше не ходит.
func finish_early() -> Dictionary:
	if phase != "island" or not task_done():
		return {}
	_history.clear()
	return {"land": {}, "field_done": true, "early": true, "result": _finish_field()}


## Сколько всего в словаре ресурсов (джокеры тоже) — для босса.
static func sum_res(d: Dictionary) -> int:
	var n := 0
	for r in d:
		n += int(d[r])
	return n


## Доход острова сейчас: то, что поле даст в конце, плюс уже полученное от Эхо.
func income(sc: Dictionary = {}) -> Dictionary:
	if sc.is_empty():
		sc = score()
	if is_cube():
		return cube_have(sc)
	var t: Dictionary = sc["total"].duplicate()
	for r in echo_gain:
		t[r] = int(t.get(r, 0)) + int(echo_gain[r])
	return t


func income_total() -> int:
	return sum_res(income())


func _add_stock(d: Dictionary) -> void:
	for r in d:
		stock[r] = int(stock.get(r, 0)) + int(d[r])


func _finish_field() -> Dictionary:
	var sc: Dictionary = score()
	var prod: Dictionary = income(sc)
	var res := {"prod": prod, "lives_before": lives, "island": island, "echo": echo_gain.duplicate()}
	if is_cube():
		# В казну — доля дохода всего куба
		var share := float(cube_cfg().get("treasury_share", 0.5))
		var gain: Dictionary = data.zero_res()
		for r in sc["all"]:
			gain[r] = int(floor(int(sc["all"][r]) * share))
		prod = gain
		res["prod"] = gain
		_add_stock(gain)
	else:
		_add_stock(sc["total"])
	_add_stock(island.get("reward", {}))
	res["reward"] = island.get("reward", {})
	res["task"] = task.duplicate()
	res["task_done"] = task_done(sc)
	if res["task_done"]:
		_add_stock(island.get("task_reward", {}))
	var lost := int(sc["discontent"])
	res["discontent"] = int(sc["discontent"])
	res["joy"] = int(sc.get("joy", 0))
	if island.has("forge"):
		res["forge"] = island["forge"]
		res["steel"] = field.recipe_met(data, island["forge"])
		if res["steel"]:
			steel += 1
	if is_cube():
		# Оставшиеся печати бьют разом (нехватка по нынешнему доходу грани)
		var strike := 0
		for f in field.sealed_faces():
			strike += ShapeField.shortfall(sc["faces"][f], field.seals[f]) * int(island["boss"].get("life_per_missing", 1))
		res["boss"] = island["boss"].duplicate()
		res["cube"] = {"broken": field.face_count() - field.sealed_faces().size(), "faces": field.face_count(), "lost_turns": cube_lost, "strike": strike, "turns": turn}
		res["boss_missing"] = cube_lost + strike
		res["boss_total"] = field.face_count() - field.sealed_faces().size()
		lost += strike
		res["lives_before"] = lives + cube_lost
	elif is_boss():
		var b: Dictionary = island["boss"].duplicate()
		var total := sum_res(prod)
		b["need"] = boss_need(b)
		res["steel_used"] = steel > 0
		if steel > 0:
			steel -= 1
		res["boss"] = b
		res["boss_total"] = total
		res["boss_missing"] = maxi(0, int(b["need"]) - total)
		lost += int(res["boss_missing"]) * int(b.get("life_per_missing", 1))
	# Контракт спринта
	if not contract.is_empty() and int(contract["sprint"]) == sprint:
		contract["progress"] = int(contract["progress"]) + int(prod.get(contract["res"], 0))
	lives = mini(lives + int(res["joy"]), int(data.run["lives"])) - lost
	res["lives_after"] = maxi(0, lives)
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
		var id: String = pool[i]
		pool.remove_at(i)
		var roll := rng.randf()
		if data.role(id) == "workshop" and roll < float(market_cfg().get("offer_echo", 0.0)):
			id = id + "*1"
		elif roll > 1.0 - float(market_cfg().get("offer_upgraded", 0.0)) and data.objects.has(id + "+"):
			id = id + "+"
		buy.append(id)
	var cc: Dictionary = market_cfg().get("contract", {})
	var colors: Array = data.colors
	var con := {"res": colors[rng.randi_range(0, colors.size() - 1)],
		"amount": rng.randi_range(int(cc["amount"][0]), int(cc["amount"][1])),
		"reward": cc.get("reward", {}), "progress": 0}
	market = {"buy": buy, "bought": buy.map(func(_x): return false), "contract": con, "contract_taken": false, "echo3": ""}
	# Редкое Эхо III: одно предложение на рынок, с нужного спринта
	var ec: Dictionary = market_cfg().get("echo", {})
	if market_no() >= int(ec.get("echo3_from_sprint", 3)) and rng.randf() < float(ec.get("echo3_chance", 0.5)):
		var cand := []
		for id in all_cards():
			if data.is_producer(id) and data.echo_level(id) < 3 and not data.is_upgraded(id) and not (data.base_id(id) in cand):
				cand.append(data.base_id(id))
		if not cand.is_empty():
			market["echo3"] = cand[rng.randi_range(0, cand.size() - 1)]


## Номер рынка: 1 — после первого спринта.
func market_no() -> int:
	return sprint + 1


## Следующий шаг Эхо для карты на этом рынке ("" — нельзя).
func echo_next(id: String) -> String:
	var nx: String = data.echo_next(id)
	if nx == "":
		return ""
	if data.echo_level(nx) == 2 and market_no() < int(market_cfg().get("echo", {}).get("echo2_from_sprint", 2)):
		return ""
	return nx


func echo_price(id: String, level: int) -> Dictionary:
	var ec: Dictionary = market_cfg().get("echo", {})
	var n := int(ec.get("echo%d_cost" % level, 10))
	var c: String = data.color_of(id)
	return {c: n} if data.colors.has(c) else {"any": n}


## Карте — следующий шаг Эхо (I → II). Заменяет одну копию.
func echo(id: String) -> bool:
	if phase != "market" or not _has_card(id):
		return false
	var nx := echo_next(id)
	if nx == "" or not _spend(echo_price(id, data.echo_level(nx))):
		return false
	_replace_card(id, nx)
	return true


## Купить редкое Эхо III: одна карта этого здания (лучше уже с Эхо) получает Эхо III.
func buy_echo3() -> bool:
	if phase != "market" or market.get("echo3", "") == "":
		return false
	var bid: String = market["echo3"]
	var best := ""
	for id in all_cards():
		if data.base_id(id) == bid and data.echo_level(id) < 3 and not data.is_upgraded(id):
			if best == "" or data.echo_level(id) > data.echo_level(best):
				best = id
	if best == "" or not _spend(echo_price(bid, 3)):
		return false
	_replace_card(best, bid + "*3")
	market["echo3"] = ""
	return true


## Цена карты на рынке: {res: n}; у жилья и городских — {"any": n}.
func buy_price(id: String) -> Dictionary:
	var n := int(market_cfg()["buy_cost"].get(data.role(id), 4))
	if data.is_upgraded(id) or data.echo_level(id) > 0:
		n += int(market_cfg().get("offer_extra", 2))
	var c: String = data.color_of(id)
	return {c: n} if data.colors.has(c) else {"any": n}


## Какую слабую карту заменит покупка ("" — карта добавится).
func buy_replaces(id: String) -> String:
	var weak: String = data.base_id(id) + "-"
	return weak if weak in all_cards() else ""


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
	var weak := buy_replaces(id)
	if weak != "":
		_replace_card(weak, id)
	else:
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
	_replace_card(id, data.upgrade_of(id))
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
	pos_lane = -1
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
