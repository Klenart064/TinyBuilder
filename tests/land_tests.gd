## Тесты правил живой земли:
##   godot --headless --path . -s tests/land_tests.gd
extends SceneTree

const LandData = preload("res://scripts/land/land_data.gd")
const LandField = preload("res://scripts/land/land_field.gd")
const LandEvents = preload("res://scripts/land/land_events.gd")
const LandGen = preload("res://scripts/land/land_gen.gd")
const LandRun = preload("res://scripts/land/land_run.gd")
const LandBot = preload("res://scripts/land/land_bot.gd")

var failures := 0
var data


func _initialize() -> void:
	data = LandData.new()
	_check(data.load_all(), "данные загружаются и валидны")
	test_scoring()
	test_house_and_terrain()
	test_lair()
	test_events()
	test_generation()
	test_run_flow()
	test_undo()
	test_finish_early()
	test_treasury()
	test_echo()
	test_forge()
	test_cube()
	test_menu()
	test_parts()
	print("\n%s" % ("ВСЕ ТЕСТЫ ПРОШЛИ" if failures == 0 else "ПРОВАЛЕНО: %d" % failures))
	quit(1 if failures > 0 else 0)


func _square() -> LandField:
	var f := LandField.new()
	for i in [0, 1, 2, 4, 5, 6, 8, 9, 10]:
		f.exists[i] = true
	return f


func test_scoring() -> void:
	var f := _square()
	f.content[0] = "field"
	var sc: Dictionary = f.score(data)
	_check(sc["total"]["food"] == 2, "Поле (добыча) даёт +2 еды")
	f.content[1] = "mill"
	sc = f.score(data)
	_check(sc["total"]["food"] == 5, "Мельница рядом с Полем: 2 + 1 + 2 = 5 еды (%d)" % sc["total"]["food"])
	f.content[4] = "field"
	f.content[5] = "field"
	sc = f.score(data)
	_check(sc["total"]["food"] == 2 * 3 + 1 + 2 * 2, "Мельница: +2 за каждое соседнее Поле (%d)" % sc["total"]["food"])
	f.content[4] = ""
	f.content[5] = ""
	f.content[1] = "mine"
	sc = f.score(data)
	_check(sc["discontent"] == 1, "Поле рядом с Шахтой: +1 недовольство")
	_check(sc["total"]["gold"] == 2 and sc["total"]["food"] == 2, "разные цвета всё равно дают своё")
	f.content[1] = "smithy"
	_check(f.score(data)["total"]["gold"] == 1, "Кузница без Шахты рядом: только +1")

func test_house_and_terrain() -> void:
	var f := _square()
	f.content[5] = "house"
	f.content[1] = "field"
	f.content[4] = "mine"
	var sc: Dictionary = f.score(data)
	_check(sc["discontent"] == 0, "Домик не ссорится с соседями")
	_check(sc["total"]["wild"] == 1, "Домик даёт +1 джокер")
	f.content[6] = "manor"
	_check(f.score(data)["total"]["wild"] == 3, "Усадьба даёт +2 джокера")
	var m := _square()
	m.content[5] = "market"
	m.content[1] = "field"
	m.content[4] = "mine"
	m.content[9] = "mill"
	var ms: Dictionary = m.score(data)
	_check(ms["total"]["food"] == 2 + 1 + 2 and ms["total"]["gold"] == 2 + 2, "Рынок: +2 за каждый цвет соседей (еда %d, золото %d)" % [ms["total"]["food"], ms["total"]["gold"]])
	var t := _square()
	t.content[5] = "tavern"
	t.content[1] = "house"
	t.content[4] = "manor"
	_check(t.score(data)["joy"] == 2, "Таверна: +1 жизнь за каждое соседнее жильё")
	var g := _square()
	g.content[0] = "field"
	g.terrain[0] = "fertile_food"
	_check(g.score(data)["total"]["food"] == 3, "плодородная земля +1 зелёному")
	g.terrain[0] = "swamp"
	_check(g.score(data)["total"]["food"] == 1, "болото -1")
	g.terrain[0] = ""
	g.content[1] = "lake"
	_check(g.score(data)["total"]["food"] == 3, "озеро +1 соседнему зелёному")

func test_lair() -> void:
	var f := _square()
	f.content[4] = "field"
	f.content[5] = "mill"
	f.content[6] = "lair"
	var sc: Dictionary = f.score(data)
	f.facing[6] = 2
	sc = f.score(data)
	_check(5 in sc["disabled"] and sc["disabled"].size() == 1, "Логово выключает соседа по стрелке")
	_check(sc["total"]["food"] == 2, "выключенная Мельница ничего не даёт")
	f.content[5] = "tower"
	_check(not (5 in f.score(data)["disabled"]), "Логово не выключает военные здания")
	f.content[5] = "mill"
	var run := LandRun.new()
	run.start(data, 1)
	run.choose_island(0)
	run.field = f
	run.hand = ["tower"]
	run.plays_left = 2
	var r: Dictionary = run.place(0, 2)
	_check(r["ok"] and 6 in r["razed"] and run.field.content[6] == "", "🛡-здание рядом сносит Логово")


func test_events() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var f := _square()
	f.content[0] = "field"
	var it := {"type": "swap", "cells": [0, 10], "target": -1}
	LandEvents.apply(it, f, data)
	_check(f.content[10] == "field" and f.content[0] == "", "обмен переносит постройку")
	it = {"type": "destroy", "cells": [10], "target": -1}
	var rep: Dictionary = LandEvents.apply(it, f, data)
	_check(f.content[10] == "" and rep["destroyed"].size() == 1, "разрушение сносит постройку")
	f.content[1] = "rock"
	LandEvents.apply({"type": "destroy", "cells": [1], "target": -1}, f, data)
	_check(f.content[1] == "rock", "камень не разрушается")
	var p: Dictionary = LandEvents.plan("growth", f, data, rng)
	_check(p["target"] >= 0 and not f.exists[p["target"]], "рост выбирает пустоту рядом с полем")
	LandEvents.apply(p, f, data)
	_check(f.exists[p["target"]] and f.cell_count() == 10, "клетка приросла")
	for _k in 10:
		var c: Dictionary = LandEvents.plan("collapse", f, data, rng)
		if c["target"] < 0:
			break
		LandEvents.apply(c, f, data)
		_check(f.is_contiguous(), "после обрушения поле связное")
	_check(f.cell_count() >= 6, "обрушение не делает поле меньше 6 клеток")
	var l: Dictionary = LandEvents.plan("lair", f, data, rng)
	LandEvents.apply(l, f, data)
	_check(f.content[l["target"]] == "lair", "логово появилось")


func test_generation() -> void:
	var rng := RandomNumberGenerator.new()
	var bad := 0
	var calm := 0
	var danger := 0
	var tasks := 0
	for s in 300:
		rng.seed = s
		var fd: Dictionary = LandGen.make_field(data, rng, 1 + s % 12)
		var f = fd["field"]
		var n: int = f.cell_count()
		var lo := 11 if fd["big"] else 8
		var hi := 13 if fd["big"] else 10
		if n < lo or n > hi or fd["turns"] != (4 if fd["big"] else 3) or not f.is_contiguous() or f.free_cells().size() < 6:
			bad += 1
		if fd["event"] == "":
			calm += 1
		if fd["danger"]:
			danger += 1
			if int(fd["reward"].get("wild", 0)) <= int(data.run["island_reward"].get("wild", 0)):
				bad += 1
		if not fd["task"].is_empty():
			tasks += 1
			if fd["task"].size() != 1:
				bad += 1
	_check(bad == 0, "300 полей: 8–10 клеток (большие 11–13, 4 хода), связные, свободных ≥6, опасные с повышенной наградой (плохих: %d)" % bad)
	_check(calm > 60 and danger < calm and danger > 0, "спокойных островов много (%d), опасных мало (%d)" % [calm, danger])
	_check(tasks > 100 and tasks < 300, "задания не на каждом острове (%d из 300)" % tasks)


## Прогон до конца с ботом; возвращает забег.
func _play(seed: int, smart: bool = true):
	var run := LandRun.new()
	run.start(data, seed)
	var guard := 0
	while not run.game_over and guard < 300:
		if run.phase == "map":
			run.choose_island(LandBot.pick_island(run, smart))
		elif run.phase == "market":
			LandBot.shop(run, smart)
			run.leave_market()
		LandBot.play_turn(run, smart)
		run.end_turn()
		guard += 1
	return run


func test_run_flow() -> void:
	var run := LandRun.new()
	run.start(data, 7)
	_check(run.phase == "map" and run.choices.size() == int(data.run["lanes"]), "забег начинается с карты: на первом шаге доступны все дорожки")
	var total := 0
	var linked := true
	for sp in run.run_map:
		for li in sp.size():
			total += sp[li].size()
			for isl in sp[li]:
				if li < sp.size() - 1 and isl["next"].is_empty():
					linked = false
	_check(run.run_map.size() == 4 and linked, "вся карта забега сгенерирована сразу, у каждого острова есть путь дальше (%d островов)" % total)
	run.choose_island(1)
	_check(run.deck.discard_pile.is_empty() and run.deck.draw_pile.size() + run.hand.size() == run.all_cards().size(), "на острове колода собрана заново и перемешана")
	var from: Dictionary = run.island
	_check(run.phase == "island" and run.hand.size() == 5 and run.turn == 1 and run.field_index == 1, "остров выбран: рука 5, ход 1")
	var ev := run.event_type
	LandBot.play_turn(run)
	var r: Dictionary = run.end_turn()
	_check(r.has("land") and run.turn == 2 and run.hand.size() == 5, "после хода земли — ход 2, рука снова 5")
	_check(run.event_type == ev, "тип события острова не меняется")
	run.end_turn()
	var stock_before: Dictionary = run.stock.duplicate()
	var prod: Dictionary = run.income()
	r = run.end_turn()
	var lanes_ok := run.choices.size() >= 1
	for isl in run.choices:
		if not (int(isl["lane"]) in from["next"]):
			lanes_ok = false
	run.choose_island(0)
	_check(run.deck.discard_pile.is_empty() and run.all_cards().size() == 15, "следующий остров снова с полной колодой")
	_check(r["field_done"] and lanes_ok, "после 3 ходов — карта, доступны только связанные острова")
	var ok := true
	for res in prod:
		if int(run.stock[res]) < int(stock_before[res]) + int(prod[res]):
			ok = false
	_check(ok, "весь доход острова (поле + Эхо) ушёл в казну, платы нет")
	# Конец первого спринта: босс-тетраэдр
	run.choose_island(0)
	for _t in 3:
		run.end_turn()
	_check(run.choices.size() == 1 and run.choices[0].has("boss"), "перед боссом — один остров с боссом")
	run.choose_island(0)
	_check(run.is_cube() and run.cube_roll and run.field.shape == "tetra", "босс 1-го спринта — тетраэдр, сначала нужно катить")
	_check(run.end_turn().is_empty(), "без поворота проверить печать нельзя")
	var opts: Array = run.roll_options()
	_check(opts.size() == 3, "тетраэдр катится на любую из 3 других граней")
	run.roll(opts[0])
	_check(run.field.top() == opts[0] and not run.cube_roll and run.plays_left == run.plays_per_turn(), "фигура повернулась, можно строить")
	var lives := run.lives
	var miss: int = run.cube_shortfall()
	r = run.end_turn()
	_check(r.has("cube") and r["cube"]["miss"] == miss and run.lives == lives - miss, "пустая грань: минус жизнь за каждую недостающую единицу (%d)" % miss)
	_check(run.cube_roll and run.turn == 2, "следующий ход снова начинается с поворота")
	run.lives = 99
	var guard := 0
	while run.phase == "island" and guard < 20:
		LandBot.play_turn(run, true)
		run.end_turn()
		guard += 1
	_check(run.phase == "market" and run.market["buy"].size() == 3, "после босса спринта — рынок с 3 картами")
	run.leave_market()
	_check(run.phase == "map" and run.sprint == 1, "с рынка — в следующий спринт")
	# Барабан катится сам и только вперёд
	var ShapeField = LandRun.ShapeField
	var d = ShapeField.new("drum")
	var t0: int = d.top()
	_check(d.one_way() and d.roll_targets() == [(t0 + 1) % 6], "барабан: следующая грань одна, назад нельзя")
	var run2 = _play(11)
	_check(run2.game_over, "забег ботом доходит до конца (остров %d, жизни %d)" % [run2.field_index, run2.lives])
	var wins := 0
	for s in 10:
		if _play(100 + s).victory:
			wins += 1
	_check(wins >= 4, "жадный бот выигрывает часть забегов (%d/10)" % wins)


func test_cube() -> void:
	var ShapeField = LandRun.ShapeField
	var c = ShapeField.new()
	var four := true
	for i in 54:
		if c.nbs(i).size() != 4:
			four = false
	_check(four, "куб: у каждой клетки 4 соседа (через рёбра тоже)")
	var cross := 0
	for j in c.nbs(0):
		if c.face_of(j) != 0:
			cross += 1
	_check(cross == 2, "угловая клетка грани соседствует с двумя другими гранями")
	var t0: int = c.top()
	var sides: Dictionary = c.side_faces()
	var f: int = sides.keys()[0]
	c.roll_to(f)
	_check(c.top() == f and c.side_faces().has(t0), "поворот: соседняя грань наверху, бывшая верхняя — сбоку")
	# Мастерская на ребре видит добычу соседней грани
	var top: int = c.top()
	var edge := -1
	var other := -1
	for i in range(top * 9, top * 9 + 9):
		for j in c.nbs(i):
			if c.face_of(j) != top and edge < 0:
				edge = i
				other = j
	c.content[edge] = "mill"
	c.content[other] = "field"
	var sc: Dictionary = c.score(data)
	_check(int(sc["total"].get("food", 0)) == data.val("mill", "self") + data.val("mill", "per_base"), "Мельница на ребре получает бонус от Поля на соседней грани")
	_check(int(sc["faces"][c.face_of(other)].get("food", 0)) == data.val("field", "base"), "Поле считается на своей грани")
	c.seals[top] = {"food": 5, "gold": 1}
	_check(ShapeField.shortfall({"food": 4, "wild": 1}, c.seals[top]) == 1, "печать: джокер закрывает одну недостающую единицу")
	_check(not c.is_free(other), "на боковой грани строить нельзя")
	# Бой: снятая печать, итог
	var run := LandRun.new()
	run.start(data, 5)
	var guard := 0
	while not run.is_cube() and guard < 500:
		if run.phase == "map":
			run.choose_island(0)
		elif run.phase == "market":
			run.leave_market()
		run.end_turn()
		guard += 1
	run.lives = 99
	var faces_seen := {}
	var res := {}
	guard = 0
	while run.phase == "island" and guard < 30:
		LandBot.play_turn(run, true)
		var r: Dictionary = run.end_turn()
		if r.has("cube"):
			faces_seen[r["cube"]["face"]] = true
		if r.get("field_done", false):
			res = r["result"]
		guard += 1
	_check(res.has("cube") and int(res["cube"]["turns"]) <= int(run.cube_cfg().get("max_turns", 12)), "бой с фигурой заканчивается (снято %d из %d за %d ходов)" % [res.get("cube", {}).get("broken", -1), res.get("cube", {}).get("faces", -1), res.get("cube", {}).get("turns", -1)])
	_check(run.phase == "market", "после босса-фигуры — рынок")
	# Тетраэдр и барабан: соседство клеток и граней
	var t = ShapeField.new("tetra")
	var tri := true
	for i in t.cells_n():
		if t.nbs(i).size() != 3:
			tri = false
	_check(t.cells_n() == 36 and tri and t.roll_targets().size() == 3, "тетраэдр: 36 треугольных клеток по 3 соседа, все грани рядом")
	var d = ShapeField.new("drum")
	var ok := d.cells_n() == 54
	for i in d.cells_n():
		if not (d.nbs(i).size() in [3, 4]):
			ok = false
	_check(ok and d.side_faces().size() == 2, "барабан: 6 граней по кругу, у верхней 2 соседние")


func test_finish_early() -> void:
	var run := LandRun.new()
	run.start(data, 9)
	var k := 0
	while run.choices[k]["task"].is_empty() and k < run.choices.size() - 1:
		k += 1
	run.choose_island(k)
	if run.task.is_empty():
		_check(run.finish_early().is_empty(), "без задания остров досрочно не забрать")
		return
	_check(run.finish_early().is_empty(), "задание не выполнено — досрочно не забрать")
	var f = run.field
	var res: String = run.task.keys()[0]
	var base: String = {"food": "field", "gold": "mine", "force": "tower"}[res]
	for c in f.free_cells():
		run.hand = [base]
		run.plays_left = 1
		run.place(0, c)
	var wild_before := int(run.stock["wild"])
	var r2: Dictionary = run.finish_early()
	_check(r2.get("field_done", false) and r2["result"]["task_done"], "задание выполнено — остров можно забрать")
	_check(int(run.stock["wild"]) >= wild_before + int(run.island["task_reward"]["wild"]), "награда за задание — в казну")


func test_treasury() -> void:
	var run := LandRun.new()
	run.start(data, 4)
	run.phase = "market"
	run._make_market()
	_check(run.all_cards().size() == 15 and "field-" in run.all_cards() and not ("field" in run.all_cards()), "стартовая колода: 15 слабых карт")
	run.market["buy"] = ["mill", "manor", "tower+"]
	run.market["bought"] = [false, false, false]
	run.stock = data.zero_res()
	_check(not run.buy(0), "без денег не купить")
	run.stock = {"food": 0, "gold": 0, "force": 0, "wild": 30}
	var n: int = run.all_cards().size()
	_check(run.buy(0) and run.all_cards().size() == n and "mill" in run.all_cards() and run.all_cards().count("mill-") == 1, "покупка Мельницы заменяет слабую Мельницу")
	_check(run.buy(1) and run.all_cards().size() == n + 1, "Усадьба (нет слабой) добавляется")
	_check(int(run.buy_price("tower+")["force"]) == int(run.buy_price("tower")["force"]) + int(data.run["market"]["offer_extra"]), "улучшенная карта на рынке дороже")
	_check(not run.buy(0), "одну карту не купить дважды")
	run.stock = {"food": 20, "gold": 0, "force": 0, "wild": 0}
	_check(run.upgrade("field-") and "field" in run.all_cards() and run.stock["food"] == 20 - int(data.run["market"]["upgrade_cost"]), "слабое Поле улучшается до обычного (платится едой)")
	_check(run.upgrade("field") and "field+" in run.all_cards(), "обычное Поле — до Поле+")
	_check(run.all_cards().size() == n + 1, "улучшение заменяет карту, а не добавляет")
	_check(not run.upgrade("field+") and data.echo_next("field-") == "", "Поле+ дальше не улучшить; у слабой карты нет Эхо")
	var f := _square()
	f.place_building(data, 4, "field+")
	f.place_building(data, 0, "field-")
	f.place_building(data, 8, "mill-")
	_check(int(f.score(data)["total"]["food"]) == 3 + 1 + 0 + 1, "Поле+ +3, слабое Поле +1, слабая Мельница 0 и +1 за добычу")
	var before := run.all_cards().count("mine-")
	run.stock = {"food": 0, "gold": 5, "force": 5, "wild": 0}
	_check(run.remove("mine-") and run.all_cards().count("mine-") == before - 1, "удаление карты")
	run.lives = 5
	run.stock = {"food": 10, "gold": 0, "force": 0, "wild": 0}
	_check(run.heal() and run.lives == 5 + int(data.run["market"]["heal_lives"]), "лечение")
	_check(run.take_contract() and run.contract["sprint"] == run.sprint + 1, "контракт на следующий спринт")
	run.leave_market()
	_check(run.phase == "map" and run.sprint == 1, "уход с рынка")


func test_undo() -> void:
	var run := LandRun.new()
	run.start(data, 3)
	run.choose_island(0)
	var before: Array = run.hand.duplicate()
	var cell: int = run.field.free_cells()[0]
	run.place(0, cell)
	_check(run.field.content[cell] != "" and run.plays_left == 1, "карта поставлена")
	run.undo()
	_check(run.field.content[cell] == "" and run.hand == before and run.plays_left == 2, "отмена возвращает карту")
	_check(not (before[0] in run.deck.discard_pile) or run.deck.discard_pile.count(before[0]) == 0, "карта не осталась в сбросе")


func test_echo() -> void:
	_check(data.objects.has("mill*1") and data.echo_level("field*3") == 3 and data.base_id("mill*2") == "mill", "у добычи и мастерских есть версии с Эхо I–III")
	var run := LandRun.new()
	run.start(data, 5)
	run.choose_island(0)
	var f := _square()
	run.field = f
	run.stock = data.zero_res()
	run.plays_left = 4
	# Без Эхо ничего не срабатывает при постройке: доход только в конце острова
	run.hand = ["mill", "field"]
	run.place(0, 5)
	var r: Dictionary = run.place(0, 4)
	_check(r["echo"].is_empty() and run.stock["food"] == 0, "обычная карта: доход в конце острова, не сразу")
	# Эхо I: соседи срабатывают ещё раз сверх обычного
	run.hand = ["field*1"]
	r = run.place(0, 6)
	_check(r["echo"].size() == 1 and r["echo"][0]["cell"] == 5 and int(r["gain"]["food"]) == 1 + 2 + 2, "Эхо I: Мельница рядом срабатывает ещё раз (+5 сразу, %s)" % str(r["gain"]))
	_check(run.stock["food"] == 5 and run.income()["food"] == run.score()["total"]["food"] + 5, "доход Эхо сразу в казне и идёт в доход острова")
	run.undo()
	_check(run.stock["food"] == 0 and int(run.echo_gain["food"]) == 0, "отмена возвращает казну")
	# Эхо II: волна на 2 шага по связкам (Поле 2 — Мельница 1? нет; Мельница 5 — Поле 4 — дальше нет связки)
	var g := _square()
	g.content[0] = "field"
	g.content[1] = "mill"
	g.content[2] = "field"
	g.content[4] = "mine"
	g.place_building(data, 5, "mill*2")
	var cells := g.echo(data, 5, 2).map(func(x): return x["cell"])
	_check(1 in cells and 0 in cells and 2 in cells and not (4 in cells), "Эхо II: волна по связкам на 2 шага, Шахта без связки не срабатывает (%s)" % str(cells))
	var c1 := g.echo(data, 5, 1).map(func(x): return x["cell"])
	_check(1 in c1 and 4 in c1 and not (0 in c1), "Эхо I: все соседи, но не дальше (%s)" % str(c1))
	# Эхо III: вся связанная сеть
	g.content[6] = "field"
	g.content[10] = "mill"
	g.content[9] = "field"
	var c3 := g.echo(data, 5, 3).map(func(x): return x["cell"])
	_check(9 in c3 and 0 in c3, "Эхо III: вся связанная сеть (%s)" % str(c3))
	_check(g.workshop_level(data, 1) == 2 and g.workshop_level(data, 10) == 2, "уровень мастерской = добыча своего цвета рядом")
	_check(g.level(data, 0) == 1 and g.level(data, 9) == 2, "уровень добычи = мастерские своего цвета рядом")
	var h := _square()
	h.content[4] = "mine"
	h.content[5] = "mountain"
	h.content[0] = "house"
	h.content[1] = "field"
	_check(int(h.score(data)["total"]["gold"]) == 4 and h.level(data, 4) == 1, "Гора: соседней Шахте +2 и уровень")
	h.content[6] = "mill"
	_check(int(h.score(data)["total"]["food"]) == 2 + 1, "Гора не даёт бонус Мельнице и Полю")
	_check(h.level(data, 0) == 2, "уровень жилья = здания рядом")
	# Рынок: выбор +1 или Эхо I, Эхо II только со 2-го рынка
	run.phase = "market"
	run.stock = {"food": 50, "gold": 50, "force": 50, "wild": 0}
	run.sprint = 0
	_check(run.echo("mill") and "mill*1" in run.all_cards(), "рынок 1: Эхо I за цену улучшения")
	_check(not run.echo("mill*1"), "Эхо II на первом рынке недоступно")
	run.sprint = 1
	_check(run.echo("mill*1") and "mill*2" in run.all_cards(), "рынок 2: Эхо II")
	_check(not data.can_upgrade("mill*2") and run.echo_next("mill*2") == "", "Эхо III только редким предложением")
	run.market["echo3"] = "mill"
	_check(run.buy_echo3() and "mill*3" in run.all_cards() and not ("mill*2" in run.all_cards()), "редкое Эхо III улучшает карту с Эхо")


func test_forge() -> void:
	var run := LandRun.new()
	run.start(data, 8)
	var forges := 0
	for sp in run.run_map:
		var n := 0
		for row in sp:
			for isl in row:
				if isl.has("forge"):
					n += 1
					_check(isl["field"].content.has("anvil") and not isl.has("boss"), "у кузницы есть Наковальня, кузница не на боссе")
		if n == 1:
			forges += 1
	_check(forges == 4, "по одной кузнице на спринт")
	var f := _square()
	f.content[4] = "anvil"
	_check(not f.recipe_met(data, "gold2"), "без зданий рецепт не собран")
	f.place_building(data, 0, "mine")
	f.place_building(data, 5, "smithy-")
	_check(f.recipe_met(data, "gold2") and not f.recipe_met(data, "colors3"), "рецепт «2 золотых»: Шахта и Кузница рядом")
	f.place_building(data, 8, "field")
	_check(f.recipe_progress(data, "colors3")[0] == 2, "«3 цвета»: пока 2")
	run.steel = 1
	_check(run.boss_need({"need": 24}) == 21, "сталь снижает босса 24 → 21 (×0,85)")


func _check(ok: bool, name: String) -> void:
	if ok:
		print("  ok  ", name)
	else:
		failures += 1
		print("FAIL  ", name)


func test_menu() -> void:
	var LandTest = load("res://scripts/land/land_test.gd")
	var ok := true
	var bad := ""
	for e in LandTest.BOSSES + LandTest.ISLANDS + LandTest.LAND + LandTest.PARTS:
		var run := LandRun.new()
		LandTest.jump(run, data, e["id"], 0)
		var want := "market" if e["id"] == "market" else "island"
		var good: bool = run.phase == want
		if e["id"] in ["tetra", "cube", "drum"]:
			good = good and run.is_cube() and run.field.shape == e["id"]
		elif e["id"] in ["raid", "king"]:
			good = good and run.is_boss() and not run.is_cube()
		elif e["id"] == "big":
			good = good and run.island["big"] and run.turns_here() == int(data.run["big_turns"])
		elif e["id"] == "forge":
			good = good and run.island.has("forge")
		elif e["id"] == "task":
			good = good and not run.task.is_empty()
		elif LandTest.PART_TURNS.has(e["id"]):
			good = good and run.field.has_method("advance") and run.turns_here() == int(LandTest.PART_TURNS[e["id"]])
		elif e["id"] in data.events:
			good = good and run.event_type == e["id"]
		if not good:
			ok = false
			bad += e["id"] + " "
	_check(ok, "тест-меню: каждый босс и остров запускается как надо %s" % bad)


func test_parts() -> void:
	var MF = load("res://scripts/land/multi_field.gd")
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	# Парные: общая граница 3 клетки, строить можно только на активном
	var p = MF.make("pair", rng)
	var cross := 0
	for i in p.cells_n():
		for j in p.nbs(i):
			if p.part_of[i] == 0 and p.part_of[j] == 1:
				cross += 1
	_check(cross == 3, "парные острова: общая граница 3 клетки (%d)" % cross)
	var free0 := true
	for i in p.free_cells():
		if p.part_of[i] != 0:
			free0 = false
	p.advance()
	var free1 := true
	for i in p.free_cells():
		if p.part_of[i] != 1:
			free1 = false
	_check(free0 and free1 and p.active == 1, "парные: строить можно только на активном острове, после хода — на другом")
	# Вращающиеся: после поворота меняется, кто смотрит на соседа
	var s = MF.make("spin", rng)
	var edge_before := []
	for i in s.cells_n():
		for j in s.nbs(i):
			if s.part_of[i] == 0 and s.part_of[j] == 1:
				edge_before.append(i)
	var sh: Dictionary = s.advance()
	var edge_after := []
	for i in s.cells_n():
		for j in s.nbs(i):
			if s.part_of[i] == 0 and s.part_of[j] == 1:
				edge_after.append(i)
	edge_before.sort()
	edge_after.sort()
	_check(sh["part"] == 0 and edge_after.size() == 3 and edge_before != edge_after and s.spin_next == 1, "вращающиеся: левый повернулся, к соседу теперь другие клетки, следующим повернётся правый")
	# Перевёртыш: край связан через ребро, после переворота строим на другой стороне
	var f = MF.make("flip", rng, "2x3")
	var four := true
	for i in f.cells_n():
		if f.nbs(i).size() < 3:
			four = false
	var top0: int = f.active
	f.advance()
	var up_ok := true
	for i in f.cells_n():
		if (f.part_of[i] == f.active) != (f.up(i).y > 0):
			up_ok = false
	_check(four and f.active != top0 and up_ok, "перевёртыш: у каждой клетки сосед через ребро, после переворота сверху другая сторона")
	# Мельница на краю видит Поле на другой стороне
	var g = MF.make("flip", rng, "3x3")
	for i in g.cells_n():
		g.content[i] = ""
	var a := -1
	var b := -1
	for i in g.cells_n():
		for j in g.nbs(i):
			if g.part_of[i] == 0 and g.part_of[j] == 1 and a < 0:
				a = i
				b = j
	g.content[a] = "mill"
	g.content[b] = "field"
	var sc: Dictionary = g.score(data)
	_check(int(sc["cells"][a]["yield"].get("food", 0)) == data.val("mill", "self") + data.val("mill", "per_base"), "перевёртыш: Мельница на ребре получает бонус от Поля снизу")
