## Скриншоты босса-куба (нужен экран или xvfb):
##   godot --path . -s tests/cube_screenshot.gd -- out_dir
## Бот доигрывает до куба, потом кадры: карта с кубом, выбор поворота, стройка, куб с постройками.
extends SceneTree

const LandBot = preload("res://scripts/land/land_bot.gd")

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
	main._new_run(7)
	var r = main.run
	# Бот доигрывает до босса-куба
	while not (r.phase == "map" and r.choices.size() == 1 and r.choices[0].has("boss") and r.choices[0]["boss"].has("cube")):
		if r.phase == "map":
			r.choose_island(LandBot.pick_island(r, true))
		elif r.phase == "market":
			LandBot.shop(r, true)
			r.leave_market()
		LandBot.play_turn(r, true)
		r.end_turn()
		if r.game_over:
			print("бот проиграл до куба")
			quit()
			return
	r.lives = maxi(r.lives, 9)
	main._show_map()
	main.map_hover = r.choices[0]
	main._refresh_map_detail()
	await _frames(8)
	_save("cube_map.png")
	main._on_choose_island(0)
	main.toast.visible = false
	await _frames(4)
	# Выбор поворота: курсор на правой стороне
	var opts: Array = r.roll_options()
	main.roll_hover = r.field.face_at(Vector3(1, 0, 0))
	main._full_refresh()
	await _frames(8)
	_save("cube_roll.png")
	# Пара ходов ботом, потом свой ход с призраком карты
	for _t in 3:
		LandBot.play_turn(r, true)
		r.end_turn()
	if r.cube_roll:
		LandBot.roll_cube(r, true)
	main.roll_hover = -1
	main._full_refresh()
	main.toast.visible = false
	main.selected = 0
	main.hover = r.field.free_cells()[0] if not r.field.free_cells().is_empty() else -1
	main._full_refresh()
	await _frames(8)
	_save("cube_build.png")
	# Анимация поворота: середина
	LandBot.play_turn(r, true)
	r.end_turn()
	main.selected = -1
	main.hover = -1
	main._full_refresh()
	main.toast.visible = false
	await _frames(4)
	_save("cube_roll2.png")
	if not r.roll_options().is_empty():
		main._on_roll(r.roll_options()[0])
		await _seconds(0.3)
		_save("cube_rolling.png")
		await _seconds(0.6)
	main.toast.visible = false
	await _frames(4)
	_save("cube_after_roll.png")
	# Доиграть бой и показать итог
	while r.phase == "island":
		LandBot.play_turn(r, true)
		var res: Dictionary = r.end_turn()
		if res.get("field_done", false):
			main._full_refresh()
			main._show_field_result(res["result"])
	await _frames(8)
	_save("cube_result.png")
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
