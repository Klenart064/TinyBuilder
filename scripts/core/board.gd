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
## Возвращает {"total": {res: n}, "cells": [{"yield": {res: n}, "notes": [текст комбо]}]}
func evaluate(data) -> Dictionary:
	var total: Dictionary = data.zero_resources()
	var per_cell := []
	for i in CELL_COUNT:
		var info := {"yield": {}, "notes": []}
		var id: String = cells[i]
		if id != "":
			var b: Dictionary = data.buildings[id]
			_add(info["yield"], b.get("yield", {}), 1)
			for rule in data.combos:
				if rule.get("building", "") != id:
					continue
				var times := combo_times(i, rule, data)
				if times > 0:
					_add(info["yield"], rule.get("bonus", {}), times)
					var text: String = rule.get("text", "")
					info["notes"].append(text if times == 1 else "%s ×%d" % [text, times])
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
