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
	_check(ms["total"]["food"] == 2 + 1 + 1 and ms["total"]["gold"] == 2 + 1, "Рынок: +1 за каждый цвет соседей (еда %d, золото %d)" % [ms["total"]["food"], ms["total"]["gold"]])
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
	for s in 300:
		rng.seed = s
		var fd: Dictionary = LandGen.make_field(data, rng, 1 + s % 12)
		var f = fd["field"]
		var n: int = f.cell_count()
		if n < 8 or n > 10 or not f.is_contiguous() or f.free_cells().size() < 6 or fd["task"].is_empty():
			bad += 1
	_check(bad == 0, "300 полей: 8–10 клеток, связные, свободных ≥6 (плохих: %d)" % bad)


func test_run_flow() -> void:
	var run := LandRun.new()
	run.start(data, 7)
	_check(run.hand.size() == 4 and run.turn == 1 and run.field_index == 1, "старт: рука 4, ход 1, поле 1")
	_check(not run.next_field.is_empty(), "следующее поле видно заранее")
	var ev := run.event_type
	LandBot.play_turn(run)
	var r: Dictionary = run.end_turn()
	_check(r.has("land") and run.turn == 2 and run.hand.size() == 4, "после хода земли — ход 2, рука снова 4")
	_check(run.event_type == ev, "тип события поля не меняется")
	run.end_turn()
	r = run.end_turn()
	_check(r["field_done"], "после 3 ходов поле завершено")
	_check(r["result"]["lives_after"] == run.lives, "жизни посчитаны")
	if not run.game_over:
		run.choose_reward(0)
		_check(run.field_index == 2 and run.turn == 1, "следующее поле")
	# Полный забег ботом не падает
	var run2 := LandRun.new()
	run2.start(data, 11)
	var guard := 0
	while not run2.game_over and guard < 200:
		LandBot.play_turn(run2)
		var rr: Dictionary = run2.end_turn()
		if rr.get("field_done", false) and not run2.game_over:
			run2.choose_reward(0)
		guard += 1
	_check(run2.game_over, "забег ботом доходит до конца (поле %d, жизни %d)" % [run2.field_index, run2.lives])


func test_finish_early() -> void:
	var run := LandRun.new()
	run.start(data, 9)
	_check(run.finish_early().is_empty(), "без платы острова досрочно не закончить")
	for r in run.task:
		run.stock[r] = 99
	var r2: Dictionary = run.finish_early()
	_check(r2.get("field_done", false) and r2["result"]["missing"] == 0, "плата есть — остров можно забрать досрочно")
	_check(int(run.stock[run.task.keys()[0]]) < 99, "плата острова списана из казны")

func test_treasury() -> void:
	var pool := {"food": 2, "gold": 0, "force": 0, "wild": 3}
	var p: Dictionary = LandRun.pay(pool, {"food": 4, "gold": 2})
	_check(p["missing"] == 1 and pool["wild"] == 0 and pool["food"] == 0, "джокеры закрывают нехватку, остаток — недостача (%s)" % str(p))
	var run := LandRun.new()
	run.start(data, 4)
	run.stock = {"food": 10, "gold": 10, "force": 10, "wild": 0}
	var before := 0
	for r in run.stock:
		before += int(run.stock[r])
	for _t in 3:
		run.end_turn()
	var after := 0
	for r in run.stock:
		after += int(run.stock[r])
	var need := 0
	for r in run.task:
		need += int(run.task[r])
	_check(not run.game_over, "казна пережила остров")


func test_undo() -> void:
	var run := LandRun.new()
	run.start(data, 3)
	var before: Array = run.hand.duplicate()
	var cell: int = run.field.free_cells()[0]
	run.place(0, cell)
	_check(run.field.content[cell] != "" and run.plays_left == 1, "карта поставлена")
	run.undo()
	_check(run.field.content[cell] == "" and run.hand == before and run.plays_left == 2, "отмена возвращает карту")
	_check(not (before[0] in run.deck.discard_pile) or run.deck.discard_pile.count(before[0]) == 0, "карта не осталась в сбросе")


func _check(ok: bool, name: String) -> void:
	if ok:
		print("  ok  ", name)
	else:
		failures += 1
		print("FAIL  ", name)
