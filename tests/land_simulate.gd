## Баланс живой земли: прогоняет забеги ботом.
##   godot --headless --path . -s tests/land_simulate.gd -- 200
## Жадный бот (видит намерение земли) против случайного.
extends SceneTree

const LandData = preload("res://scripts/land/land_data.gd")
const LandRun = preload("res://scripts/land/land_run.gd")
const LandBot = preload("res://scripts/land/land_bot.gd")


func _initialize() -> void:
	var runs := 200
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		runs = int(args[0])
	var data = LandData.new()
	data.load_all()
	for smart in [true, false]:
		var wins := 0
		var fields := 0
		var loss := {"missing": 0, "discontent": 0, "boss": 0}
		var joy := 0
		var prod_sum := 0
		var stock_end := 0
		var reached := {}
		var final_short := 0
		for s in runs:
			var run = LandRun.new()
			run.start(data, s)
			while not run.game_over:
				LandBot.play_turn(run, smart)
				var r: Dictionary = run.end_turn()
				if not r.get("field_done", false):
					continue
				var res: Dictionary = r["result"]
				fields += 1
				loss["missing"] += res["missing"]
				loss["discontent"] += res["discontent"]
				loss["boss"] += res.get("boss_missing", 0)
				joy += res["joy"]
				for k in res["prod"]:
					prod_sum += int(res["prod"][k])
				if res.has("boss") and res["boss"].get("final", false):
					final_short += res["boss_missing"]
				if not run.game_over:
					run.choose_reward(-1 if run.lives <= 4 else 0)
			if run.victory:
				wins += 1
				for k in run.stock:
					stock_end += int(run.stock[k])
			reached[run.field_index] = reached.get(run.field_index, 0) + 1
		print("\n=== Бот: %s, забегов %d ===" % ["жадный" if smart else "случайный", runs])
		print("Победы: %d%%, островов в среднем: %.1f" % [100 * wins / runs, float(fields) / runs])
		print("Доход за остров: %.1f" % (float(prod_sum) / fields))
		print("Потери жизней за остров: плата %.2f, недовольство %.2f, боссы %.2f; таверна +%.2f" % [
			float(loss["missing"]) / fields, float(loss["discontent"]) / fields, float(loss["boss"]) / runs, float(joy) / fields])
		print("Остаток казны у победителей: %.1f" % (float(stock_end) / maxi(wins, 1)))
		var keys := reached.keys()
		keys.sort()
		var line := "Дошли до острова: "
		for k in keys:
			line += "%d:%d " % [k, reached[k]]
		print(line)
	quit()
