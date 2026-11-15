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
	main.run.start(main.data, 3)
	# Разыгрываем пару карт, выбираем третью и наводимся на клетку
	for k in 2:
		var free: Array = main.run.board.free_cells()
		main.run.place(0, free[k])
	main.selected = 0 if main.run.hand.size() > 0 else -1
	main.hover_cell = main.run.board.free_cells()[0]
	main._refresh()
	await _frames(10)
	_save("shot_board.png")
	main._on_finish()
	await _frames(10)
	_save("shot_summary.png")
	quit()


func _frames(n: int) -> void:
	for _i in n:
		await process_frame


func _save(name: String) -> void:
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(out_dir.path_join(name))
	print("saved ", out_dir.path_join(name))
