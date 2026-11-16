## Ход живой земли. У поля один тип события; перед каждым ходом игрока земля
## выбирает клетки (намерение, его видно), а после хода игрока выполняет его.
extends RefCounted

const LandField = preload("res://scripts/land/land_field.gd")


## Намерение: {"type", "cells": [клетки], "target": клетка или -1}
## swap: cells = [a, b]; destroy: cells = [...]; growth/collapse/lair: target.
static func plan(type: String, field, data, rng: RandomNumberGenerator) -> Dictionary:
	var ev: Dictionary = data.events.get(type, {})
	var intent := {"type": type, "cells": [], "target": -1}
	match type:
		"swap":
			var land: Array = field.land_cells()
			# Хотя бы на одной из клеток что-то есть (или будет можно построить) — иначе обмен пустой
			var interesting := []
			for i in land:
				if field.content[i] != "" or field.terrain[i] != "":
					interesting.append(i)
			if land.size() >= 2:
				var a: int = interesting[rng.randi_range(0, interesting.size() - 1)] if not interesting.is_empty() and rng.randf() < 0.6 else land[rng.randi_range(0, land.size() - 1)]
				var others := []
				for i in land:
					if i != a and not (i in LandField.neighbors(a)):
						others.append(i)
				if others.is_empty():
					for i in land:
						if i != a:
							others.append(i)
				var b: int = others[rng.randi_range(0, others.size() - 1)]
				intent["cells"] = [a, b]
		"destroy":
			# Трещины чаще идут по свободным клеткам (там нельзя строить в этот ход),
			# с шансом hit_built задевают уже стоящую постройку.
			var free: Array = field.free_cells()
			var built := []
			for i in field.land_cells():
				var k: String = data.kind(field.content[i])
				if k == "building" or k == "threat":
					built.append(i)
			_shuffle(free, rng)
			_shuffle(built, rng)
			var n := int(ev.get("cells", 2))
			if not built.is_empty() and rng.randf() < float(ev.get("hit_built", 0.35)):
				intent["cells"].append(built[0])
			for i in free:
				if intent["cells"].size() >= n:
					break
				intent["cells"].append(i)
		"growth":
			var spots := []
			for i in LandField.N:
				if field.exists[i]:
					continue
				for j in LandField.neighbors(i):
					if field.exists[j]:
						spots.append(i)
						break
			if not spots.is_empty():
				intent["target"] = spots[rng.randi_range(0, spots.size() - 1)]
		"collapse":
			var min_cells := int(ev.get("min_cells", 6))
			if field.cell_count() > min_cells:
				var spots := []
				for i in field.land_cells():
					if _is_edge(field, i) and field.is_contiguous(i):
						spots.append(i)
				if not spots.is_empty():
					intent["target"] = spots[rng.randi_range(0, spots.size() - 1)]
		"lair":
			var spots: Array = field.free_cells()
			if spots.is_empty():
				for i in field.land_cells():
					if data.kind(field.content[i]) != "obstacle" and data.kind(field.content[i]) != "threat":
						spots.append(i)
			if not spots.is_empty():
				var t: int = spots[rng.randi_range(0, spots.size() - 1)]
				intent["target"] = t
				# Смотрит на соседнее здание (если есть), иначе на любую соседнюю землю
				var dirs := []
				var any := []
				for d in 4:
					var j := LandField.step(t, d)
					if j >= 0 and field.exists[j]:
						any.append(d)
						if data.is_building(field.content[j]) and data.color_of(field.content[j]) != "force":
							dirs.append(d)
				if dirs.is_empty():
					dirs = any
				intent["dir"] = dirs[rng.randi_range(0, dirs.size() - 1)] if not dirs.is_empty() else 0
	return intent


## Выполняет намерение. Отчёт для анимации:
## {"type", "moved": [[a, b]], "destroyed": [{"cell", "id"}], "grown": клетка, "fell": {"cell", "id"}, "spawned": клетка}
static func apply(intent: Dictionary, field, data) -> Dictionary:
	var rep := {"type": intent.get("type", ""), "moved": [], "destroyed": [], "grown": -1, "fell": {}, "spawned": -1}
	var t: int = intent.get("target", -1)
	match intent.get("type", ""):
		"swap":
			if intent["cells"].size() == 2:
				var a: int = intent["cells"][0]
				var b: int = intent["cells"][1]
				if field.exists[a] and field.exists[b]:
					for arr in [field.content, field.prebuilt, field.terrain, field.facing]:
						var tmp = arr[a]
						arr[a] = arr[b]
						arr[b] = tmp
					rep["moved"].append([a, b])
		"destroy":
			for i in intent["cells"]:
				var id: String = field.content[i]
				if field.exists[i] and id != "" and data.kind(id) != "obstacle":
					rep["destroyed"].append({"cell": i, "id": id})
					field.content[i] = ""
					field.prebuilt[i] = false
					field.facing[i] = -1
		"growth":
			if t >= 0 and not field.exists[t]:
				field.exists[t] = true
				field.content[t] = ""
				field.prebuilt[t] = false
				field.terrain[t] = ""
				field.facing[t] = -1
				rep["grown"] = t
		"collapse":
			if t >= 0 and field.exists[t]:
				rep["fell"] = {"cell": t, "id": field.content[t], "terrain": field.terrain[t]}
				field.exists[t] = false
				field.content[t] = ""
				field.prebuilt[t] = false
				field.terrain[t] = ""
				field.facing[t] = -1
		"lair":
			if t >= 0 and field.exists[t] and data.kind(field.content[t]) != "obstacle":
				var id: String = field.content[t]
				if id != "" and data.kind(id) != "threat":
					rep["destroyed"].append({"cell": t, "id": id})
				field.content[t] = "lair"
				field.prebuilt[t] = true
				field.facing[t] = int(intent.get("dir", 0))
				rep["spawned"] = t
	return rep


## Клетки, которых коснётся намерение (для подсветки и предупреждений).
static func touched_cells(intent: Dictionary) -> Array:
	var out: Array = intent.get("cells", []).duplicate()
	if intent.get("target", -1) >= 0:
		out.append(intent["target"])
	return out


## Строит ли игрок на клетке, которую земля разрушит/обрушит/займёт логовом.
static func endangers(intent: Dictionary, cell: int) -> bool:
	match intent.get("type", ""):
		"destroy":
			return cell in intent["cells"]
		"collapse", "lair":
			return cell == intent.get("target", -1)
	return false


## Текст намерения для интерфейса.
static func describe(intent: Dictionary) -> String:
	match intent.get("type", ""):
		"swap":
			return "Подсвеченные клетки поменяются местами" if intent["cells"].size() == 2 else "Земля спокойна"
		"destroy":
			return "Постройки на %d подсвеченных клетках рухнут" % intent["cells"].size() if not intent["cells"].is_empty() else "Земля спокойна"
		"growth":
			return "К полю прирастёт клетка" if intent["target"] >= 0 else "Расти некуда"
		"collapse":
			return "Подсвеченная клетка обрушится" if intent["target"] >= 0 else "Земля держится"
		"lair":
			return "На подсвеченной клетке появится Логово" if intent["target"] >= 0 else "Логову негде появиться"
	return "Земля спокойна"


static func _is_edge(field, i: int) -> bool:
	if LandField.neighbors(i).size() < 4:
		return true
	for j in LandField.neighbors(i):
		if not field.exists[j]:
			return true
	return false


static func _shuffle(a: Array, rng: RandomNumberGenerator) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = a[i]
		a[i] = a[j]
		a[j] = t
