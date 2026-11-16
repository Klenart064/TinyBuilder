## Простой бот для симуляций баланса: на каждом ходу жадно ставит карты,
## учитывая задание, недовольство и намерение земли. smart=false — ставит случайно.
extends RefCounted

const LandEvents = preload("res://scripts/land/land_events.gd")


static func play_turn(run, smart: bool = true) -> void:
	while run.plays_left > 0 and not run.hand.is_empty():
		var free: Array = run.field.free_cells()
		if free.is_empty():
			return
		if not smart:
			run.place(run.rng.randi_range(0, run.hand.size() - 1), free[run.rng.randi_range(0, free.size() - 1)])
			continue
		var best_v := value(run, run.field)
		var best := []
		for h in run.hand.size():
			for c in free:
				var f = run.field.clone()
				f.place_building(run.data, c, run.hand[h])
				var v := value(run, f)
				if v > best_v + 0.001:
					best_v = v
					best = [h, c]
		if best.is_empty():
			return
		run.place(best[0], best[1])


## Оценка поля после хода земли: доход в казну, нехватка на плату и босса, недовольство.
static func value(run, f) -> float:
	var g = f.clone()
	LandEvents.apply(run.intent, g, run.data)
	var sc: Dictionary = g.score(run.data)
	var v := 0.0
	for r in sc["total"]:
		v += float(sc["total"][r]) * (1.3 if r == "wild" else 1.0)
	var pool: Dictionary = run.projected(sc)
	var miss: int = run.pay(pool, run.task)["missing"]
	var b: Dictionary = run.next_boss()
	if int(b.get("at_field", -1)) == run.field_index:
		miss += run.pay(pool, b.get("cost", {}))["missing"]
	v -= 3.5 * float(miss)
	v -= 3.5 * float(sc["discontent"])
	v += 3.0 * float(mini(int(sc.get("joy", 0)), int(run.data.run["lives"]) - run.lives))
	return v
