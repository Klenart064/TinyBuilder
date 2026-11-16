## Остров из частей (тест-меню):
##   pair — парные острова: два острова с общей границей ≥ 3 клеток, строите по очереди то на одном, то на другом;
##   spin — вращающиеся: два острова 3×3 рядом, после каждого хода один из них (по очереди) поворачивается
##          на 90° по часовой — меняется, какие клетки смотрят на соседа;
##   flip — перевёртыш: две стороны (верх и низ), после каждого хода остров переворачивается,
##          строите на той стороне, что сверху; клетки края связаны через ребро с той же клеткой другой стороны.
## Клетки — в «единицах клеток»: x — столбец, z — строка, y — высота. Соседство считается по положению.
extends "res://scripts/land/land_field.gd"

const GAP := 0.3     # зазор между островами (мосты)
const THICK := 1.0   # толщина перевёртыша

var kind := "pair"
var parts: Array = []     # [{w, h, ox, oz, rot}]
var part_of: Array = []   # часть каждой клетки
var loc: Array = []       # Vector2i(столбец, строка) внутри части
var active := 0           # где можно строить (pair, flip); у spin — везде
var spin_next := 0        # spin: какой остров повернётся после хода
var flipped := false      # flip: сверху нижняя сторона
var _mid := Vector3.ZERO
var _adj: Array = []


func _init(kind_ := "pair") -> void:
	kind = kind_


## Собрать части: [{w, h, ox, oz}] (у flip — две стороны одного размера).
func setup(parts_: Array) -> void:
	parts = []
	part_of = []
	loc = []
	for p in parts_.size():
		var d: Dictionary = parts_[p].duplicate()
		d["rot"] = 0
		parts.append(d)
		for r in int(d["h"]):
			for c in int(d["w"]):
				part_of.append(p)
				loc.append(Vector2i(c, r))
	_alloc(part_of.size())
	for i in exists.size():
		exists[i] = true
	_mid = Vector3.ZERO
	var lo := Vector3(INF, 0, INF)
	var hi := Vector3(-INF, 0, -INF)
	for i in exists.size():
		var w := _raw(i)
		lo = Vector3(minf(lo.x, w.x), 0, minf(lo.z, w.z))
		hi = Vector3(maxf(hi.x, w.x), 0, maxf(hi.z, w.z))
	_mid = (lo + hi) / 2
	_adj = []


func clone():
	var f = get_script().new(kind)
	f.parts = parts.duplicate(true)
	f.part_of = part_of.duplicate()
	f.loc = loc.duplicate()
	f.active = active
	f.spin_next = spin_next
	f.flipped = flipped
	f._mid = _mid
	f.exists = exists.duplicate()
	f.content = content.duplicate()
	f.prebuilt = prebuilt.duplicate()
	f.terrain = terrain.duplicate()
	f.facing = facing.duplicate()
	return f


## Положение клетки до центрирования.
func _raw(i: int) -> Vector3:
	var p: Dictionary = parts[part_of[i]]
	var l: Vector2i = loc[i]
	if kind == "flip":
		var h := int(p["h"])
		var y := 0.0 if part_of[i] == 0 else -THICK
		var z := float(l.y)
		if flipped:
			y = -THICK - y
			z = (h - 1) - z
		return Vector3(l.x, y, z)
	var rc := _rot_local(l, int(p["w"]), int(p["h"]), int(p["rot"]))
	return Vector3(float(p["ox"]) + rc.x, 0, float(p["oz"]) + rc.y)


## Поворот на rot × 90° по часовой (вид сверху) внутри квадрата части.
static func _rot_local(l: Vector2i, w: int, _h: int, rot: int) -> Vector2:
	var x := l.x
	var z := l.y
	for _k in rot % 4:
		var nx := w - 1 - z
		var nz := x
		x = nx
		z = nz
	return Vector2(x, z)


## Центр клетки в мире (в единицах клеток, остров по центру).
func world(i: int) -> Vector3:
	return _raw(i) - _mid


## Куда смотрит клетка.
func up(i: int) -> Vector3:
	if kind != "flip":
		return Vector3.UP
	var top: bool = (part_of[i] == 0) != flipped
	return Vector3.UP if top else Vector3.DOWN


## Центр части в мире.
func part_center(p: int) -> Vector3:
	var s := Vector3.ZERO
	var n := 0
	for i in exists.size():
		if part_of[i] == p:
			s += world(i)
			n += 1
	return s / maxi(1, n)


func part_count() -> int:
	return parts.size()


func nbs(i: int) -> Array:
	if _adj.is_empty():
		_build_adj()
	return _adj[i]


func _build_adj() -> void:
	_adj = []
	var w := []
	for i in exists.size():
		w.append(_raw(i))
		_adj.append([])
	for i in exists.size():
		for j in range(i + 1, exists.size()):
			if _touch(i, j, w[i], w[j]):
				_adj[i].append(j)
				_adj[j].append(i)


func _touch(i: int, j: int, a: Vector3, b: Vector3) -> bool:
	if kind == "flip":
		if part_of[i] == part_of[j]:
			return absf(a.y - b.y) < 0.01 and absf(a.x - b.x) + absf(a.z - b.z) < 1.01
		# через ребро: та же клетка другой стороны, если она на краю
		if loc[i] != loc[j]:
			return false
		var p: Dictionary = parts[part_of[i]]
		var l: Vector2i = loc[i]
		return l.x == 0 or l.y == 0 or l.x == int(p["w"]) - 1 or l.y == int(p["h"]) - 1
	var dx := absf(a.x - b.x)
	var dz := absf(a.z - b.z)
	var step := 1.0 if part_of[i] == part_of[j] else 1.0 + GAP
	return (absf(dx - step) < 0.01 and dz < 0.01) or (absf(dz - step) < 0.01 and dx < 0.01)


func is_free(i: int) -> bool:
	if not super.is_free(i):
		return false
	return kind == "spin" or part_of[i] == active


## Конец хода: смена активного острова / поворот / переворот. Возвращает, что случилось (для анимации).
func advance() -> Dictionary:
	match kind:
		"pair":
			var from := active
			active = (active + 1) % parts.size()
			return {"kind": "pair", "from": from, "to": active}
		"spin":
			var p := spin_next
			var center := part_center(p)
			parts[p]["rot"] = (int(parts[p]["rot"]) + 1) % 4
			spin_next = (spin_next + 1) % parts.size()
			_adj = []
			return {"kind": "spin", "part": p, "center": center}
		"flip":
			flipped = not flipped
			active = 1 - active
			return {"kind": "flip"}
	return {}


## Путь дороги между соседними клетками a и b: точки и «верх» каждого отрезка.
## [{"p": Vector3, "q": Vector3, "up": Vector3, "bridge": bool}]
func link_path(a: int, b: int) -> Array:
	var pa := world(a)
	var pb := world(b)
	if part_of[a] == part_of[b]:
		return [{"p": pa, "q": pb, "up": up(a), "bridge": false}]
	if kind == "flip":
		# через ребро: до края своей стороны, по торцу вниз, к клетке другой стороны
		var out := _edge_dir(a)
		var ea := pa + out * 0.5
		var eb := pb + out * 0.5
		return [{"p": pa, "q": ea, "up": up(a), "bridge": false},
			{"p": ea, "q": eb, "up": out, "bridge": false},
			{"p": eb, "q": pb, "up": up(b), "bridge": false}]
	var d := (pb - pa).normalized()
	var ea2 := pa + d * 0.5
	var eb2 := pb - d * 0.5
	return [{"p": pa, "q": ea2, "up": Vector3.UP, "bridge": false},
		{"p": ea2, "q": eb2, "up": Vector3.UP, "bridge": true},
		{"p": eb2, "q": pb, "up": Vector3.UP, "bridge": false}]


## Перевёртыш: куда (наружу) уходит край клетки (первый подходящий край).
func _edge_dir(i: int) -> Vector3:
	var p: Dictionary = parts[part_of[i]]
	var l: Vector2i = loc[i]
	var w := world(i)
	var c := Vector3(0, w.y, 0)
	var dirs := []
	if l.x == 0 or l.x == int(p["w"]) - 1:
		dirs.append(Vector3(signf(w.x - c.x) if absf(w.x) > 0.01 else 1.0, 0, 0))
	if l.y == 0 or l.y == int(p["h"]) - 1:
		dirs.append(Vector3(0, 0, signf(w.z) if absf(w.z) > 0.01 else 1.0))
	return dirs[0] if not dirs.is_empty() else Vector3.RIGHT


## Сколько зданий на части.
func buildings_on(data, p: int) -> int:
	var n := 0
	for i in exists.size():
		if part_of[i] == p and data.is_building(content[i]):
			n += 1
	return n


## Генерация: тип острова и rng. Камни по одному на часть (у pair/spin), у flip — по одному на сторону.
static func make(kind_: String, rng: RandomNumberGenerator, size := "3x3"):
	var f = load("res://scripts/land/multi_field.gd").new(kind_)
	match kind_:
		"pair":
			# Левый 3×4 (выше), правый 3×3 со сдвигом: общая граница 3 клетки
			var oz := rng.randi_range(0, 1)
			f.setup([{"w": 3, "h": 4, "ox": 0.0, "oz": 0.0}, {"w": 3, "h": 3, "ox": 3.0 + GAP, "oz": float(oz)}])
		"spin":
			f.setup([{"w": 3, "h": 3, "ox": 0.0, "oz": 0.0}, {"w": 3, "h": 3, "ox": 3.0 + GAP, "oz": 0.0}])
		"flip":
			var w := 2 if size == "2x3" else 3
			f.setup([{"w": w, "h": 3, "ox": 0.0, "oz": 0.0}, {"w": w, "h": 3, "ox": 0.0, "oz": 0.0}])
	for p in f.parts.size():
		var cells := []
		for i in f.exists.size():
			if f.part_of[i] == p:
				cells.append(i)
		var rock: int = cells[rng.randi_range(0, cells.size() - 1)]
		f.content[rock] = "rock"
		f.prebuilt[rock] = true
	return f
