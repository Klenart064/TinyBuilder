## Поле живой земли: до 16 клеток в рамке 4×4. Клетка либо есть (земля), либо пустота.
## На клетке может стоять объект (здание, препятствие, логово) и лежать местность.
extends RefCounted

const SIZE := 4
const N := SIZE * SIZE

var exists: Array = []     # bool — есть ли земля
var content: Array = []    # String — id объекта или ""
var prebuilt: Array = []   # bool — объект стоял на поле заранее
var terrain: Array = []    # String — id местности или ""
var facing: Array = []     # int — куда смотрит логово: 0 вверх, 1 вниз, 2 влево, 3 вправо; -1 нет


func _init() -> void:
	for i in N:
		exists.append(false)
		content.append("")
		prebuilt.append(false)
		terrain.append("")
		facing.append(-1)


func clone():
	var f = get_script().new()
	f.exists = exists.duplicate()
	f.content = content.duplicate()
	f.prebuilt = prebuilt.duplicate()
	f.terrain = terrain.duplicate()
	f.facing = facing.duplicate()
	return f


func to_dict() -> Dictionary:
	return {"exists": exists.duplicate(), "content": content.duplicate(), "prebuilt": prebuilt.duplicate(), "terrain": terrain.duplicate(), "facing": facing.duplicate()}


func from_dict(d: Dictionary) -> void:
	exists = d["exists"].duplicate()
	content = d["content"].duplicate()
	prebuilt = d["prebuilt"].duplicate()
	terrain = d["terrain"].duplicate()
	facing = d["facing"].duplicate()


## Соседняя клетка в направлении dir (0 вверх, 1 вниз, 2 влево, 3 вправо) или -1.
static func step(i: int, dir: int) -> int:
	var r := i / SIZE
	var c := i % SIZE
	match dir:
		0: r -= 1
		1: r += 1
		2: c -= 1
		3: c += 1
		_: return -1
	if r < 0 or r >= SIZE or c < 0 or c >= SIZE:
		return -1
	return r * SIZE + c


static func neighbors(i: int) -> Array:
	var out := []
	var r := i / SIZE
	var c := i % SIZE
	if r > 0:
		out.append(i - SIZE)
	if r < SIZE - 1:
		out.append(i + SIZE)
	if c > 0:
		out.append(i - 1)
	if c < SIZE - 1:
		out.append(i + 1)
	return out


func is_free(i: int) -> bool:
	return i >= 0 and i < N and exists[i] and content[i] == ""


func free_cells() -> Array:
	var out := []
	for i in N:
		if is_free(i):
			out.append(i)
	return out


func land_cells() -> Array:
	var out := []
	for i in N:
		if exists[i]:
			out.append(i)
	return out


func cell_count() -> int:
	return land_cells().size()


## Связна ли земля, если убрать клетку skip.
func is_contiguous(skip: int = -1) -> bool:
	var cells := []
	for i in N:
		if exists[i] and i != skip:
			cells.append(i)
	if cells.is_empty():
		return true
	var seen := {cells[0]: true}
	var stack := [cells[0]]
	while not stack.is_empty():
		var i: int = stack.pop_back()
		for j in neighbors(i):
			if exists[j] and j != skip and not seen.has(j):
				seen[j] = true
				stack.append(j)
	return seen.size() == cells.size()


## Ставит здание игрока. 🛡-здание сносит соседние логова. Возвращает снесённые клетки.
func place_building(data, cell: int, id: String) -> Array:
	content[cell] = id
	prebuilt[cell] = false
	var razed := []
	if data.color_of(id) == "force":
		for j in neighbors(cell):
			if exists[j] and data.kind(content[j]) == "threat":
				content[j] = ""
				prebuilt[j] = false
				facing[j] = -1
				razed.append(j)
	return razed


## Каскад: доход в момент постройки. Сначала срабатывает новое здание, потом по очереди
## каждое соседнее здание — ещё раз, со своим текущим доходом (после постройки).
## Возвращает [{"cell", "yield": {res: n}}] — только сработавшие с ненулевым доходом.
func cascade(data, cell: int) -> Array:
	var sc: Dictionary = score(data)
	var out := []
	for i in [cell] + neighbors(cell):
		if i != cell and not (exists[i] and data.is_building(content[i])):
			continue
		var y: Dictionary = sc["cells"][i]["yield"]
		var sum := 0
		for r in y:
			sum += int(y[r])
		if sum > 0:
			out.append({"cell": i, "yield": y.duplicate()})
	return out


static func cascade_total(steps: Array) -> Dictionary:
	var t := {}
	for st in steps:
		for r in st["yield"]:
			t[r] = int(t.get(r, 0)) + int(st["yield"][r])
	return t


## Клетки, выключенные логовами: логово выключает одного соседа, на которого смотрит.
## Военные здания (цвет force) логово не выключает.
func disabled_cells(data) -> Array:
	var out := []
	for i in N:
		if exists[i] and data.kind(content[i]) == "threat":
			var j := step(i, facing[i])
			if j >= 0 and exists[j] and data.is_building(content[j]) and data.color_of(content[j]) != "force" and not (j in out):
				out.append(j)
	return out


## Доход и недовольство поля.
## {"total": {res: n}, "discontent": n, "joy": n, "cells": [{"yield": {}, "notes": []}],
##  "links": [{"a", "b", "type": pair|house|market|tavern|conflict, "res"}], "disabled": [клетки]}
func score(data) -> Dictionary:
	var rules: Dictionary = data.rules
	var disabled := disabled_cells(data)
	var cells := []
	for i in N:
		cells.append({"yield": {}, "notes": []})
	var links := []
	var discontent := 0
	var joy := 0
	for i in N:
		if not exists[i]:
			continue
		var id: String = content[i]
		if not data.is_building(id) or i in disabled:
			continue
		var role: String = data.role(id)
		var col: String = data.color_of(id)
		match role:
			"base":
				_add(cells[i], col, data.val(id, "base"), "")
			"workshop":
				_add(cells[i], col, data.val(id, "self"), "")
			"housing":
				_add(cells[i], "wild", data.val(id, "wild"), "")
		if data.is_producer(id):
			var t: String = terrain[i]
			if t != "":
				var td: Dictionary = data.terrain[t]
				if td["color"] == col or td["color"] == "any":
					_add(cells[i], col, int(td["bonus"]), td["name"])
		var market_colors := {}
		for j in neighbors(i):
			if not exists[j]:
				continue
			var nid: String = content[j]
			if data.kind(nid) == "obstacle" and data.is_producer(id):
				var bonus: Dictionary = data.objects[nid].get("bonus_to_neighbors", {})
				if bonus.has(col):
					_add(cells[i], col, int(bonus[col]), data.obj_name(nid))
			if not data.is_building(nid) or j in disabled:
				continue
			var nrole: String = data.role(nid)
			var ncol: String = data.color_of(nid)
			if role == "workshop" and nrole == "base" and ncol == col:
				_add(cells[i], col, data.val(id, "per_base"), data.obj_name(nid))
				links.append({"a": i, "b": j, "type": "pair", "res": col})
			elif data.base_id(id) == "market" and data.is_producer(nid) and not market_colors.has(ncol):
				market_colors[ncol] = true
				_add(cells[i], ncol, data.val(id, "per_color"), "рынок")
				links.append({"a": i, "b": j, "type": "house", "res": ncol})
			elif data.base_id(id) == "tavern" and nrole == "housing":
				joy += data.val(id, "per_housing")
				links.append({"a": i, "b": j, "type": "tavern", "res": ""})
			if j > i and data.is_producer(id) and data.is_producer(nid) and ncol != col:
				discontent += int(rules["conflict"])
				links.append({"a": i, "b": j, "type": "conflict", "res": ""})
	var total: Dictionary = data.zero_res()
	for i in N:
		for r in cells[i]["yield"]:
			total[r] = int(total.get(r, 0)) + int(cells[i]["yield"][r])
	for r in total:
		total[r] = maxi(0, int(total[r]))
	return {"total": total, "discontent": discontent, "joy": joy, "cells": cells, "links": links, "disabled": disabled}


static func _add(cell: Dictionary, res: String, v: int, note: String) -> void:
	if v == 0:
		return
	cell["yield"][res] = int(cell["yield"].get(res, 0)) + v
	if note != "":
		cell["notes"].append("%s %+d" % [note, v])
