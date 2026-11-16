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
		var loss := {"missing": 0, "discontent": 0, "global": 0}
		var by_event := {}
		var prod_sum := 0
		var globals := [0, 0]
		var reached := {}
		for s in runs:
			var run = LandRun.new()
			run.start(data, s)
			while not run.game_over:
				LandBot.play_turn(run, smart)
				var ev: String = run.event_type
				var r: Dictionary
				if smart and run.task_done() and run.event_type != "growth":
					r = run.finish_early()
				else:
					r = run.end_turn()
				if not r.get("field_done", false):
					continue
				var res: Dictionary = r["result"]
				fields += 1
				loss["missing"] += res["missing"]
				loss["discontent"] += res["discontent"]
				for k in res["prod"]:
					prod_sum += int(res["prod"][k])
				if res.get("global_checked", false):
					globals[0] += 1
					if not res["global_passed"]:
						globals[1] += 1
						loss["global"] += int(res["global"].get("penalty", 3))
				if not by_event.has(ev):
					by_event[ev] = [0, 0, 0]
				by_event[ev][0] += 1
				by_event[ev][1] += res["missing"] + res["discontent"]
				for k in res["prod"]:
					by_event[ev][2] += int(res["prod"][k])
				if not run.game_over:
					# Бот берёт отдых, если жизней мало, иначе первую карту
					run.choose_reward(-1 if run.lives <= 3 else 0)
			if run.victory:
				wins += 1
			reached[run.field_index] = reached.get(run.field_index, 0) + 1
		print("\n=== Бот: %s, забегов %d ===" % ["жадный" if smart else "случайный", runs])
		print("Победы: %d%%, полей в среднем: %.1f" % [100 * wins / runs, float(fields) / runs])
		print("Доход за поле: %.1f" % (float(prod_sum) / fields))
		print("Потери жизней за поле: задание %.2f, недовольство %.2f, глоб. угроза %.2f" % [
			float(loss["missing"]) / fields, float(loss["discontent"]) / fields, float(loss["global"]) / fields])
		print("Глобальные угрозы провалены: %d из %d" % [globals[1], globals[0]])
		for ev in by_event:
			var b: Array = by_event[ev]
			print("  %-9s полей %4d  потери/поле %.2f  доход/поле %.1f" % [ev, b[0], float(b[1]) / b[0], float(b[2]) / b[0]])
		var keys := reached.keys()
		keys.sort()
		var line := "Дошли до поля: "
		for k in keys:
			line += "%d:%d " % [k, reached[k]]
		print(line)
	quit()
