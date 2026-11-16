## Прогоняет много забегов «жадным» ботом, чтобы прикинуть баланс.
##   godot --headless --path . -s tests/simulate.gd -- 500
## Бот на каждом шаге ставит карту туда, где она даёт больше всего (с учётом задания и угрозы).
extends SceneTree

const GameData = preload("res://scripts/core/game_data.gd")
const RunState = preload("res://scripts/core/run_state.gd")


func _initialize() -> void:
	var runs := 300
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		runs = int(args[0])
	var data = GameData.new()
	data.load_all()
	var threats_beaten := {}
	var wins := 0
	var goal_hits := 0
	var fields := 0
	var income_sum: Dictionary = data.zero_resources()
	for s in runs:
		var run = RunState.new()
		run.start(data, s)
		while not run.game_over:
			_play_greedy(run)
			var rep: Dictionary = run.finish_field()
			fields += 1
			if rep["goal_done"]:
				goal_hits += 1
			for res in rep["income"]:
				income_sum[res] += rep["income"][res]
			if not run.reward_options.is_empty():
				run.choose_reward(_best_reward(run))
			if not run.game_over:
				run.make_path_options()
				run.choose_path(run.rng.randi_range(0, run.path_options.size() - 1))
		threats_beaten[run.threat_index] = threats_beaten.get(run.threat_index, 0) + 1
		if run.victory:
			wins += 1
	print("Забегов: %d, побед: %d (%.0f%%)" % [runs, wins, 100.0 * wins / runs])
	print("Заданий выполнено: %.0f%% полей" % (100.0 * goal_hits / fields))
	var avg := []
	for res in income_sum:
		avg.append("%s %.1f" % [res, float(income_sum[res]) / fields])
	print("Средний доход за поле: ", ", ".join(avg))
	var keys := threats_beaten.keys()
	keys.sort()
	for k in keys:
		print("  отбито угроз %d: %d забегов" % [k, threats_beaten[k]])
	quit()


## Бот берёт награду случайно — живой игрок выбирает умнее.
func _best_reward(run) -> int:
	return run.rng.randi_range(0, run.reward_options.size() - 1)


## Бот находит лучшую расстановку всей руки (перебором) с учётом угрозы и задания.
func _play_greedy(run) -> void:
	var threat: Dictionary = run.current_threat()
	var need: Dictionary = threat.get("need", {})
	var weights := {}
	for res in run.data.resources:
		weights[res] = 2.0 if need.has(res) and run.stock.get(res, 0) < need[res] else 1.0
	var gr: String = run.goal["resource"]
	var target: int = run.goal["target"]
	var cells: Array = run.board.best_arrangement(run.data, run.hand, weights,
		func(total): return 8.0 if total.get(gr, 0) >= target else 0.0)
	for cell in cells.size():
		if run.board.cells[cell] == "" and cells[cell] != "":
			run.place(run.hand.find(cells[cell]), cell)
