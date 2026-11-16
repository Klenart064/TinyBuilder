## Поле 3×3: что где стоит и сколько это производит.
extends RefCounted

const SIZE := 3
const CELL_COUNT := SIZE * SIZE

## id здания в клетке или "" если пусто.
var cells: Array = []
## true, если здание стояло на поле заранее (не из руки игрока).
var prebuilt: Array = []


func _init() -> void:
	cells.resize(CELL_COUNT)
	cells.fill("")
	prebuilt.resize(CELL_COUNT)
	prebuilt.fill(false)


func is_free(i: int) -> bool:
	return i >= 0 and i < CELL_COUNT and cells[i] == ""


func free_cells() -> Array:
	var out := []
	for i in CELL_COUNT:
		if cells[i] == "":
			out.append(i)
	return out


static func neighbors(i: int, diagonal: bool = false) -> Array:
	var out := []
	var r := i / SIZE
	var c := i % SIZE
	for dr in [-1, 0, 1]:
		for dc in [-1, 0, 1]:
			if dr == 0 and dc == 0:
				continue
			if not diagonal and dr != 0 and dc != 0:
				continue
			var nr: int = r + dr
			var nc: int = c + dc
			if nr >= 0 and nr < SIZE and nc >= 0 and nc < SIZE:
				out.append(nr * SIZE + nc)
	return out


## Считает доход всего поля.
## Возвращает {"total": {res: n}, "cells": [{"yield", "notes", "combos"}]}
## combos — сработавшие комбо клетки: [{"id", "partners": [клетки-соседи], "bonus": {res: n}}]
func evaluate(data) -> Dictionary:
	var total: Dictionary = data.zero_resources()
	var per_cell := []
	for i in CELL_COUNT:
		var info := {"yield": {}, "notes": [], "combos": []}
		var id: String = cells[i]
		if id != "":
			var b: Dictionary = data.buildings[id]
			_add(info["yield"], b.get("yield", {}), 1)
			for rule in data.combos:
				if rule.get("building", "") != id:
					continue
				var times := combo_times(i, rule, data)
				if times > 0:
					var bonus := {}
					_add(bonus, rule.get("bonus", {}), times)
					_add(info["yield"], bonus, 1)
					var text: String = rule.get("text", "")
					info["notes"].append(text if times == 1 else "%s ×%d" % [text, times])
					info["combos"].append({"id": data.combo_id(rule), "partners": combo_partners(i, rule, data), "bonus": bonus})
		_add(total, info["yield"], 1)
		per_cell.append(info)
	return {"total": total, "cells": per_cell}


## Сколько раз срабатывает правило комбо для здания в клетке i.
func combo_times(i: int, rule: Dictionary, data) -> int:
	var wanted: Array = data.neighbor_list(rule)
	var count := 0
	for n in neighbors(i, rule.get("diagonal", false)):
		if cells[n] in wanted:
			count += 1
	var need := int(rule.get("min", 1))
	if count < need:
		return 0
	if rule.get("per", false):
		return count
	return 1


## Максимум каждого ресурса, который можно получить на поле, разыграв карты hand
## (каждый ресурс максимизируется отдельно). Перебирает все расстановки.
## Доход от построек только растёт, поэтому ставим столько карт, сколько влезает.
func best_totals(data, hand: Array) -> Dictionary:
	var cards := hand.duplicate()
	cards.sort()  # одинаковые карты рядом — так проще отсечь повторы
	var ctx := {
		"res": data.resources.keys(),
		"rules": _rules_by_building(data),
		"yields": {},
		"nbr": [],
		"best": data.zero_resources(),
	}
	for id in data.buildings:
		ctx["yields"][id] = data.buildings[id].get("yield", {})
	for i in CELL_COUNT:
		ctx["nbr"].append([neighbors(i, false), neighbors(i, true)])
	_search(ctx, cards, 0, free_cells().size(), -1)
	return ctx["best"]


## Лучшая расстановка руки по взвешенной сумме ресурсов (для бота и будущих подсказок).
## bonus_fn(total: Dictionary) -> float — дополнительные очки (например, за выполнение задания).
## Возвращает клетки поля после лучшей расстановки.
func best_arrangement(data, hand: Array, weights: Dictionary, bonus_fn: Callable = Callable()) -> Array:
	var cards := hand.duplicate()
	cards.sort()
	var ctx := {
		"res": data.resources.keys(),
		"rules": _rules_by_building(data),
		"yields": {},
		"nbr": [],
		"best": data.zero_resources(),
		"weights": weights,
		"best_score": -INF,
		"best_cells": cells.duplicate(),
	}
	if bonus_fn.is_valid():
		ctx["bonus_fn"] = bonus_fn
	for id in data.buildings:
		ctx["yields"][id] = data.buildings[id].get("yield", {})
	for i in CELL_COUNT:
		ctx["nbr"].append([neighbors(i, false), neighbors(i, true)])
	_search(ctx, cards, 0, free_cells().size(), -1)
	return ctx["best_cells"]


func _rules_by_building(data) -> Dictionary:
	var out := {}
	for rule in data.combos:
		var b: String = rule.get("building", "")
		if not out.has(b):
			out[b] = []
		out[b].append({
			"wanted": data.neighbor_list(rule),
			"min": int(rule.get("min", 1)),
			"per": rule.get("per", false),
			"diag": 1 if rule.get("diagonal", false) else 0,
			"bonus": rule.get("bonus", {}),
		})
	return out


func _search(ctx: Dictionary, cards: Array, idx: int, free_left: int, prev_cell: int) -> void:
	if idx == cards.size() or free_left == 0:
		_fast_score(ctx)
		return
	if cards.size() - idx > free_left:
		_search(ctx, cards, idx + 1, free_left, -1)  # эту карту не играем
	var same_as_prev: bool = idx > 0 and cards[idx] == cards[idx - 1]
	for cell in CELL_COUNT:
		if cells[cell] != "":
			continue
		if same_as_prev and cell < prev_cell:
			continue
		cells[cell] = cards[idx]
		_search(ctx, cards, idx + 1, free_left - 1, cell)
		cells[cell] = ""


## Упрощённый evaluate для перебора: без описаний, сразу обновляет максимумы.
func _fast_score(ctx: Dictionary) -> void:
	var total := {}
	for res in ctx["res"]:
		total[res] = 0
	var rules: Dictionary = ctx["rules"]
	var yields: Dictionary = ctx["yields"]
	for i in CELL_COUNT:
		var id: String = cells[i]
		if id == "":
			continue
		var y: Dictionary = yields[id]
		for res in y:
			total[res] += int(y[res])
		if not rules.has(id):
			continue
		for r in rules[id]:
			var count := 0
			for n in ctx["nbr"][i][r["diag"]]:
				if cells[n] in r["wanted"]:
					count += 1
			if count < r["min"]:
				continue
			var times: int = count if r["per"] else 1
			for res in r["bonus"]:
				total[res] += int(r["bonus"][res]) * times
	var best: Dictionary = ctx["best"]
	for res in total:
		if total[res] > best[res]:
			best[res] = total[res]
	if ctx.has("weights"):
		var score := 0.0
		var w: Dictionary = ctx["weights"]
		for res in total:
			score += total[res] * float(w.get(res, 1.0))
		if ctx.has("bonus_fn"):
			score += ctx["bonus_fn"].call(total)
		if score > ctx["best_score"]:
			ctx["best_score"] = score
			ctx["best_cells"] = cells.duplicate()


## Клетки-соседи, которые участвуют в правиле для клетки i.
func combo_partners(i: int, rule: Dictionary, data) -> Array:
	var wanted: Array = data.neighbor_list(rule)
	var out := []
	for n in neighbors(i, rule.get("diagonal", false)):
		if cells[n] in wanted:
			out.append(n)
	return out


## Насколько изменится общий доход поля, если поставить здание id в клетку i.
func preview_delta(data, i: int, id: String) -> Dictionary:
	var before: Dictionary = evaluate(data)["total"]
	cells[i] = id
	var after: Dictionary = evaluate(data)["total"]
	cells[i] = ""
	var delta := {}
	for res in after:
		delta[res] = int(after[res]) - int(before.get(res, 0))
	return delta


static func _add(target: Dictionary, amounts: Dictionary, times: int) -> void:
	for res in amounts:
		target[res] = int(target.get(res, 0)) + int(amounts[res]) * times
