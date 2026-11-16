## Баланс живой земли: прогоняет забеги ботом.
##   godot --headless --path . -s tests/land_simulate.gd -- 200
## Жадный бот (видит намерение земли, выбирает маршрут, закупается на рынке) против случайного.
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
		var loss := {"discontent": 0, "boss": 0}
		var joy := 0
		var tasks := [0, 0]
		var contracts := [0, 0]
		var danger := 0
		var prod_by_sprint := {}
		var cnt_by_sprint := {}
		var boss_total := {}
		var upgrades := 0
		var deck_size := 0
		var reached := {}
		for s in runs:
			var run = LandRun.new()
			run.start(data, s)
			while not run.game_over:
				if run.phase == "map":
					run.choose_island(LandBot.pick_island(run, smart))
				elif run.phase == "market":
					LandBot.shop(run, smart)
					run.leave_market()
				LandBot.play_turn(run, smart)
				var sp: int = run.sprint
				var r: Dictionary = run.end_turn()
				if not r.get("field_done", false):
					continue
				var res: Dictionary = r["result"]
				fields += 1
				if res["island"].get("danger", false):
					danger += 1
				loss["discontent"] += res["discontent"]
				loss["boss"] += res.get("boss_missing", 0)
				joy += res["joy"]
				if not res["task"].is_empty():
					tasks[1] += 1
					if res["task_done"]:
						tasks[0] += 1
				if res.has("contract") and not res["contract"].is_empty():
					contracts[1] += 1
					if res["contract"]["done"]:
						contracts[0] += 1
				var p := 0
				for k in res["prod"]:
					p += int(res["prod"][k])
				prod_by_sprint[sp] = prod_by_sprint.get(sp, 0) + p
				cnt_by_sprint[sp] = cnt_by_sprint.get(sp, 0) + 1
				if res.has("boss"):
					var bt: Array = boss_total.get(res["boss"]["name"], [0, 0, 0])
					bt[0] += res["boss_total"]
					bt[1] += 1
					bt[2] += 1 if res["boss_missing"] == 0 else 0
					boss_total[res["boss"]["name"]] = bt
			if run.victory:
				wins += 1
			for id in run.all_cards():
				if run.data.is_upgraded(id):
					upgrades += 1
			deck_size += run.all_cards().size()
			reached[run.field_index] = reached.get(run.field_index, 0) + 1
		print("\n=== Бот: %s, забегов %d ===" % ["жадный" if smart else "случайный", runs])
		print("Победы: %d%%, островов в среднем: %.1f, опасных: %.2f за забег" % [100 * wins / runs, float(fields) / runs, float(danger) / runs])
		var line := "Доход за остров по спринтам: "
		var ks := prod_by_sprint.keys()
		ks.sort()
		for k in ks:
			line += "%d: %.1f  " % [k + 1, float(prod_by_sprint[k]) / cnt_by_sprint[k]]
		print(line)
		for b in boss_total:
			var bt: Array = boss_total[b]
			print("Босс «%s»: в среднем %.1f, без потерь %d%%" % [b, float(bt[0]) / bt[1], 100 * bt[2] / bt[1]])
		print("Потери жизней за остров: недовольство %.2f; за забег боссы %.2f; таверна +%.2f за остров" % [
			float(loss["discontent"]) / fields, float(loss["boss"]) / runs, float(joy) / fields])
		print("Задания: %d/%d, контракты: %d/%d" % [tasks[0], tasks[1], contracts[0], contracts[1]])
		print("В конце: колода %.1f карт, улучшено %.1f" % [float(deck_size) / runs, float(upgrades) / runs])
		var keys := reached.keys()
		keys.sort()
		line = "Дошли до острова: "
		for k in keys:
			line += "%d:%d " % [k, reached[k]]
		print(line)
	quit()
