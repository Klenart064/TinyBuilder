## Делает скриншоты прототипа (нужен экран или xvfb):
##   godot --path . -s tests/screenshot.gd -- out_dir
extends SceneTree

var main
var out_dir := "user://"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out_dir = args[0]
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func _run() -> void:
	await _frames(5)
	main.book.reset()
	main.run.start(main.data, 3)
	# Заготовленная раскладка, чтобы скриншоты были одинаковыми
	var b = main.run.board
	for i in 9:
		b.cells[i] = ""
		b.prebuilt[i] = false
	b.cells[3] = "field"
	b.cells[7] = "field"
	b.cells[2] = "rock"
	b.prebuilt[3] = true
	b.prebuilt[7] = true
	b.prebuilt[2] = true
	main.run.hand = ["house", "mill", "market", "barracks"]
	main._refresh()
	await _frames(5)
	# Ставим домик в центр, как будто кликнули
	var before: Dictionary = main.run.production()
	main.run.place(0, 4)
	main._refresh()
	main._play_combo_effects(before, 4)
	await _seconds(0.35)
	_save("shot_combo.png")
	await _seconds(1.5)
	# Выбираем мельницу и наводимся на клетку между полями
	main.selected = 0
	main.hover_cell = 6
	main._refresh()
	await _frames(5)
	_save("shot_board.png")
	main._on_finish()
	await _frames(10)
	_save("shot_summary.png")
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
