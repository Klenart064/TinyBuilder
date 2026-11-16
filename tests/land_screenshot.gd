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
	for ev in ["swap", "lair", "destroy", "growth", "collapse"]:
		main._new_run(4)
		main.toast.visible = false
		var run = main.run
		run.event_type = ev
		run.intent = main.LandEvents.plan(ev, run.field, run.data, run.rng)
		# Пара построек для наглядности
		var free: Array = run.field.free_cells()
		if ev != "growth":
			run.place(0, free[0])
			free = run.field.free_cells()
			run.place(0, free[free.size() - 1])
			run.intent = main.LandEvents.plan(ev, run.field, run.data, run.rng)
		main._full_refresh()
		main.selected = 0
		main.hover = run.field.free_cells()[0]
		run.plays_left = 1
		main._full_refresh()
		await _frames(8)
		_save("land_%s.png" % ev)
	# Насыщенная раскладка: пары, Дом, конфликт, озеро, местность, логово
	main._new_run(4)
	main.toast.visible = false
	var r = main.run
	var f = r.field
	for i in 16:
		f.exists[i] = i in [1, 2, 4, 5, 6, 7, 8, 9, 10, 13]
		f.content[i] = ""
		f.terrain[i] = ""
		f.facing[i] = -1
	f.content[5] = "field"
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
	r.intent = {"type": "swap", "cells": [8, 2], "target": -1}
	r.hand = ["barracks", "tower", "smithy", "house"]
	main.selected = 0
	main.hover = 8
	main._full_refresh()
	await _frames(8)
	_save("land_board.png")
	main._toggle_rules()
	await _frames(5)
	_save("land_rules.png")
	main._toggle_rules()
	r.hand = ["field", "mill", "mine", "barracks"]
	r.carry = {"food": 2, "gold": 0, "force": 3}
	main.selected = -1
	main.hover = -1
	main._full_refresh()
	await _frames(8)
	_save("land_cards2.png")
	for res in r.task:
		r.carry[res] = int(r.task[res])
	main._full_refresh()
	await _frames(5)
	_save("land_claim.png")
	main._new_run(4)
	main.toast.visible = false
	# Ход земли с анимацией и итог поля
	main.run.event_type = "swap"
	main.run.intent = main.LandEvents.plan("swap", main.run.field, main.run.data, main.run.rng)
	main.selected = -1
	main._on_end_turn()
	await _seconds(0.35)
	_save("land_anim.png")
	await _seconds(1.0)
	main.run.end_turn()
	main._on_end_turn()
	await _seconds(1.5)
	_save("land_result.png")
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
