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
		if n < 8 or n > 10 or not f.is_contiguous() or f.free_cells().size() < 6:
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
	_check(bad == 0, "300 полей: 8–10 клеток, связные, свободных ≥6, опасные с повышенной наградой (плохих: %d)" % bad)
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
	_check(run.phase == "island" and run.hand.size() == 4 and run.turn == 1 and run.field_index == 1, "остров выбран: рука 4, ход 1")
	var ev := run.event_type
	LandBot.play_turn(run)
	var r: Dictionary = run.end_turn()
	_check(r.has("land") and run.turn == 2 and run.hand.size() == 4, "после хода земли — ход 2, рука снова 4")
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
	_check(run.deck.discard_pile.is_empty() and run.all_cards().size() == 20, "следующий остров снова с полной колодой")
	_check(r["field_done"] and lanes_ok, "после 3 ходов — карта, доступны только связанные острова")
	var ok := true
	for res in prod:
		if int(run.stock[res]) < int(stock_before[res]) + int(prod[res]):
			ok = false
	_check(ok, "весь доход острова (поле + Эхо) ушёл в казну, платы нет")
	# Конец первого спринта — рынок
	for _k in 2:
		run.choose_island(0)
		for _t in 3:
			run.end_turn()
	_check(run.phase == "market" and run.market["buy"].size() == 3, "после спринта — рынок с 3 картами")
	run.leave_market()
	_check(run.phase == "map" and run.sprint == 1, "с рынка — в следующий спринт")
	# Босс на последнем острове 2-го спринта
	run.choose_island(0)
	for _t in 3:
		run.end_turn()
	run.choose_island(0)
	for _t in 3:
		run.end_turn()
	_check(run.choices.size() == 1 and run.choices[0].has("boss"), "перед боссом — один остров с боссом")
	run.choose_island(0)
	for _t in 2:
		run.end_turn()
	var lives := run.lives
	var need := int(run.island["boss"]["need"]) - run.income_total()
	r = run.end_turn()
	_check(r["result"]["boss_missing"] == maxi(0, need), "босс считает весь доход острова (не хватило %d)" % r["result"]["boss_missing"])
	_check(run.game_over or run.lives <= lives - r["result"]["boss_missing"] + r["result"]["joy"], "нехватка на боссе снимает жизни")
	var run2 = _play(11)
	_check(run2.game_over, "забег ботом доходит до конца (остров %d, жизни %d)" % [run2.field_index, run2.lives])
	var wins := 0
	for s in 10:
		if _play(100 + s).victory:
			wins += 1
	_check(wins >= 4, "жадный бот выигрывает часть забегов (%d/10)" % wins)


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
	var id: String = run.market["buy"][0]
	run.stock = data.zero_res()
	_check(not run.buy(0), "без денег не купить")
	run.stock = {"food": 0, "gold": 0, "force": 0, "wild": 20}
	var n: int = run.all_cards().size()
	_check(run.buy(0) and run.all_cards().size() == n + 1 and id in run.all_cards(), "покупка добавляет карту в колоду")
	_check(not run.buy(0), "одну карту не купить дважды")
	run.stock = {"food": 20, "gold": 0, "force": 0, "wild": 0}
	_check(run.upgrade("field") and "field+" in run.all_cards() and run.stock["food"] == 20 - int(data.run["market"]["upgrade_cost"]), "улучшение Поля платится едой")
	_check(run.all_cards().size() == n + 1, "улучшение заменяет карту, а не добавляет")
	_check(not run.upgrade("field+"), "улучшенное не улучшить второй раз")
	var f := _square()
	f.place_building(data, 4, "field+")
	_check(int(f.score(data)["total"]["food"]) == 3, "Поле+ даёт +3")
	var before := run.all_cards().count("mine")
	run.stock = {"food": 0, "gold": 5, "force": 5, "wild": 0}
	_check(run.remove("mine") and run.all_cards().count("mine") == before - 1, "удаление карты")
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


func _check(ok: bool, name: String) -> void:
	if ok:
		print("  ok  ", name)
	else:
		failures += 1
		print("FAIL  ", name)
