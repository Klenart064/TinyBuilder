## Скриншоты прототипа живой земли (нужен экран или xvfb):
##   godot --path . -s tests/land_screenshot.gd -- out_dir
extends SceneTree

var main
var out_dir := "user://"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	main = load("res://scenes/land.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func _run() -> void:
	await _frames(5)
	# Карта маршрута в начале забега
	main._new_run(4)
	await _frames(8)
	_save("land_map.png")
	main._show_deck()
	await _frames(8)
	_save("land_deck.png")
	main._close_deck()
	main._on_choose_island(0)
	main.toast.visible = false
	for ev in ["swap", "lair", "destroy", "growth", "collapse"]:
		var run = main.run
		run.event_type = ev
		run.island["danger"] = ev in ["destroy", "collapse"]
		run.intent = main.LandEvents.plan(ev, run.field, run.data, run.rng)
		main._full_refresh()
		main.selected = 0
		main.hover = run.field.free_cells()[0]
		main._full_refresh()
		await _frames(8)
		_save("land_%s.png" % ev)
	# Насыщенная раскладка с заданием
	var r = main.run
	var f = r.field
	for i in 16:
		f.exists[i] = i in [1, 2, 4, 5, 6, 7, 8, 9, 10, 13]
		f.content[i] = ""
		f.terrain[i] = ""
		f.facing[i] = -1
	f.content[5] = "field+"
	f.content[6] = "mill"
	f.content[9] = "house"
	f.content[10] = "mine"
	f.content[1] = "lake"
	f.terrain[8] = "fertile_force"
	f.content[7] = "lair"
	f.facing[7] = 2
	f.content[2] = "smithy"
	f.terrain[13] = "swamp"
	r.event_type = "swap"
	r.island["danger"] = false
	r.task = {"food": 6}
	r.island["task"] = r.task
	r.intent = {"type": "swap", "cells": [8, 2], "target": -1}
	r.hand = ["field+", "mill", "mine", "barracks"]
	r.stock = {"food": 9, "gold": 4, "force": 6, "wild": 3}
	main.selected = 0
	main.hover = 8
	main._full_refresh()
	await _frames(8)
	_save("land_board.png")
	main._toggle_rules()
	await _frames(5)
	_save("land_rules.png")
	main._toggle_rules()
	# Итог острова
	main.selected = -1
	main.hover = -1
	r.end_turn()
	r.end_turn()
	main._on_end_turn()
	await _seconds(1.5)
	_save("land_result.png")
	# Рынок: прокрутить спринт ботом
	main._hide_overlay()
	while r.phase != "market":
		if r.phase == "map":
			r.choose_island(0)
		for _t in 3:
			r.end_turn()
	r.stock = {"food": 14, "gold": 9, "force": 11, "wild": 5}
	r.lives = 8
	main._full_refresh()
	main.market_tab = 0
	main._show_market()
	await _frames(8)
	_save("land_market.png")
	main.market_tab = 1
	main._show_market()
	await _frames(8)
	_save("land_market_deck.png")
	r.upgrade("mill")
	r.upgrade("field")
	main._show_market()
	main._on_leave_market()
	await _frames(8)
	_save("land_map2.png")
	# Босс
	while not (r.choices.size() == 1 and r.choices[0].has("boss")):
		if r.phase == "market":
			r.leave_market()
		r.choose_island(0)
		for _t in 3:
			r.end_turn()
	main._show_map()
	await _frames(8)
	_save("land_boss_map.png")
	main._on_choose_island(0)
	main.toast.visible = false
	var free: Array = r.field.free_cells()
	r.hand = ["field+", "mill+", "manor", "field"]
	r.place(0, free[0])
	main._full_refresh()
	await _frames(8)
	_save("land_boss.png")
	quit()


func _seconds(t: float) -> void:
	await create_timer(t).timeout


func _frames(n: int) -> void:
	for _i in n:
		await process_frame


func _save(name: String) -> void:
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(out_dir.path_join(name))
	print("saved ", out_dir.path_join(name))
