## Тест-меню: быстрый запуск любого босса или типа острова.
## Бот доигрывает до нужного спринта (чтобы колода была как в настоящем забеге),
## потом подменяет следующий остров выбранным и входит в него.
extends RefCounted

const LandGen = preload("res://scripts/land/land_gen.gd")
const LandBot = preload("res://scripts/land/land_bot.gd")
const ShapeField = preload("res://scripts/land/shape_field.gd")

## Боссы: id, название, описание, спринт по умолчанию (0-based).
const BOSSES := [
	{"id": "tetra", "name": "Хрустальный тетраэдр", "desc": "4 треугольные грани, катить на любую, 6 ходов", "stage": 0},
	{"id": "cube", "name": "Каменный куб", "desc": "6 граней 3×3, катить на соседнюю, 10 ходов", "stage": 1},
	{"id": "drum", "name": "Жерновой барабан", "desc": "6 граней по кругу, крутится сам вперёд", "stage": 2},
	{"id": "raid", "name": "Набег (старый)", "desc": "Обычный остров: набрать 24 всего за 3 хода", "stage": 1},
	{"id": "king", "name": "Осада короля", "desc": "Финал: набрать 33 всего за 3 хода", "stage": 3},
]

## Острова: id, название, описание.
const ISLANDS := [
	{"id": "calm", "name": "Обычный", "desc": "Спокойная земля, 3 хода"},
	{"id": "big", "name": "Большой", "desc": "11–13 клеток, 4 хода"},
	{"id": "task", "name": "С заданием", "desc": "Произвести N одного цвета"},
	{"id": "forge", "name": "Кузница", "desc": "Наковальня: рецепт даёт сталь"},
	{"id": "market", "name": "Рынок", "desc": "Сразу на рынок после спринта"},
]

## Живая земля: события острова.
const LAND := [
	{"id": "swap", "name": "Блуждающая земля", "desc": "Две клетки меняются местами"},
	{"id": "growth", "name": "Растущая земля", "desc": "Каждый ход +1 клетка"},
	{"id": "lair", "name": "Логова", "desc": "Логово выключает здание"},
	{"id": "destroy", "name": "Трещины (опасный)", "desc": "Постройки на трещинах рушатся"},
	{"id": "collapse", "name": "Обрыв (опасный)", "desc": "Край острова обрушивается"},
]


static func boss_stage(kind: String) -> int:
	for b in BOSSES:
		if b["id"] == kind:
			return int(b["stage"])
	return 0


## Бот играет новый забег до начала спринта stage (на карте, шаг 1). Жизни не дают умереть.
static func prepare(run, data, stage: int) -> void:
	run.start(data, -1)
	var guard := 0
	while not (run.phase == "map" and run.sprint >= stage and run.layer == 0) and guard < 400:
		guard += 1
		if run.phase == "map":
			run.choose_island(LandBot.pick_island(run, true))
		elif run.phase == "market":
			LandBot.shop(run, true)
			run.leave_market()
			continue
		LandBot.play_turn(run, true)
		run.lives = maxi(run.lives, 30)
		run.end_turn()
	run.lives = int(data.run["lives"])


## Остров выбранного типа (как из генератора карты).
static func make_island(run, data, kind: String) -> Dictionary:
	var rng: RandomNumberGenerator = run.rng
	var idx: int = run.field_index + 1
	var isl: Dictionary = {}
	for _k in 300:
		isl = LandGen.make_field(data, rng, idx)
		if kind == "big" and not isl["big"]:
			continue
		if kind != "big" and isl["big"]:
			continue
		break
	var ev := ""
	if kind in data.events:
		ev = kind
	isl["event"] = ev
	isl["danger"] = bool(data.events.get(ev, {}).get("danger", false))
	isl["reward"] = (data.run.get("danger_reward", {}) if isl["danger"] else data.run.get("island_reward", {})).duplicate()
	if kind == "calm":
		isl["task"] = {}
	if kind == "task" and isl["task"].is_empty():
		isl["task"] = LandGen.make_task(data, rng, idx)
	if kind == "forge":
		LandGen.add_forge(isl, data, rng)
	var boss := _boss_cfg(data, kind)
	if not boss.is_empty():
		isl["boss"] = boss
		isl["task"] = {}
		isl["event"] = ""
		isl["danger"] = false
		isl["big"] = false
		isl["turns"] = int(data.run["turns_per_field"])
		if boss.has("cube"):
			isl["field"] = ShapeField.make(data, rng, boss["cube"])
			isl["turns"] = int(boss["cube"].get("max_turns", 12))
	isl["lane"] = (int(data.run.get("lanes", 3)) - 1) / 2
	isl["sprint"] = run.sprint
	isl["layer"] = run.layer
	isl["next"] = range(int(data.run.get("lanes", 3)))
	isl["visited"] = false
	isl["test"] = true
	return isl


static func _boss_cfg(data, kind: String) -> Dictionary:
	for s in data.run["sprints"]:
		if not s.has("boss"):
			continue
		var b: Dictionary = s["boss"]
		if kind in ["tetra", "cube", "drum"] and b.get("cube", {}).get("shape", "") == kind:
			return b.duplicate(true)
		if kind == "king" and b.get("final", false):
			return b.duplicate(true)
	if kind == "raid":
		return {"name": "Набег", "need": 24, "life_per_missing": 1}
	return {}


## Полный прыжок: подготовить колоду и войти в остров (или на рынок).
static func jump(run, data, kind: String, stage: int) -> void:
	if kind == "market":
		# После последнего спринта рынка нет
		stage = mini(stage, data.run["sprints"].size() - 2)
	prepare(run, data, stage)
	if kind == "market":
		run.phase = "market"
		run._make_market()
		return
	run.choices = [make_island(run, data, kind)]
	run.choose_island(0)
