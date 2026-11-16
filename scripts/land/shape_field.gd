## Босс-фигура: остров на гранях объёмной фигуры. Клетки — многоугольники на гранях,
## соседи — клетки с общим ребром (и внутри грани, и через рёбра фигуры).
##   cube  — куб, 6 граней 3×3, катится на любую соседнюю грань
##   tetra — тетраэдр, 4 треугольные грани по 9 треугольников, каждая грань соседка всех
##   drum  — барабан (шестигранная призма), 6 граней 3×3 по кругу, крутится только вперёд
## На каждой грани печать. Верхняя грань (нормаль смотрит вверх) — та, где строят и которую проверяют.
extends "res://scripts/land/land_field.gd"

const SHAPES := ["cube", "tetra", "drum"]
## Сторона треугольной клетки тетраэдра (квадратная клетка = 1)
const TRI := 1.9

static var _geo: Dictionary = {}

var shape := "cube"
## Поворот фигуры: мир = orient * свои координаты (центр фигуры в нуле).
var orient := Basis.IDENTITY
## Печати граней: [{res: n}] и сняты ли они.
var seals: Array = []
var broken: Array = []


func _init(shape_: String = "cube") -> void:
	setup(shape_)


func setup(shape_: String) -> void:
	shape = shape_
	var g: Dictionary = geo(shape)
	_alloc(g["centers"].size())
	for i in exists.size():
		exists[i] = true
	seals = []
	broken = []
	for f in g["faces"].size():
		seals.append({})
		broken.append(false)
	orient = Basis.IDENTITY


func clone():
	var f = get_script().new(shape)
	f.exists = exists.duplicate()
	f.content = content.duplicate()
	f.prebuilt = prebuilt.duplicate()
	f.terrain = terrain.duplicate()
	f.facing = facing.duplicate()
	f.orient = orient
	f.seals = seals.duplicate(true)
	f.broken = broken.duplicate()
	return f


# ---------------------------------------------------------------- геометрия

static func geo(s: String) -> Dictionary:
	if not _geo.has(s):
		_geo[s] = _build(s)
	return _geo[s]


static func _square_face(faces: Array, cells: Array, n: Vector3, a: Vector3, v: Vector3, dist: float) -> void:
	var f := faces.size()
	var fc := n * dist
	faces.append({"normal": n, "poly": [fc - a * 1.5 - v * 1.5, fc + a * 1.5 - v * 1.5, fc + a * 1.5 + v * 1.5, fc - a * 1.5 + v * 1.5], "dist": dist})
	for r in 3:
		for c in 3:
			var ce := fc + a * (c - 1) + v * (r - 1)
			cells.append({"face": f, "center": ce, "poly": [ce - a * 0.5 - v * 0.5, ce + a * 0.5 - v * 0.5, ce + a * 0.5 + v * 0.5, ce - a * 0.5 + v * 0.5]})


static func _build(s: String) -> Dictionary:
	var faces := []
	var cells := []
	match s:
		"drum":
			var ap := 1.5 * sqrt(3.0)
			for k in 6:
				var th := deg_to_rad(90.0 - 60.0 * k)
				var n := Vector3(0, cos(th), sin(th))
				var t := Vector3(0, -sin(th), cos(th))
				_square_face(faces, cells, n, Vector3.RIGHT, t, ap)
		"tetra":
			var e := 3.0 * TRI
			var rr := e * sqrt(6.0) / 4.0
			var d := rr / 3.0
			var rc := e / sqrt(3.0)
			var pts := []
			for ang in [90.0, 210.0, 330.0]:
				pts.append(Vector3(rc * cos(deg_to_rad(ang)), d, rc * sin(deg_to_rad(ang))))
			var apex := Vector3(0, -rr, 0)
			for tri in [[pts[0], pts[1], pts[2]], [pts[0], pts[1], apex], [pts[1], pts[2], apex], [pts[2], pts[0], apex]]:
				var ce: Vector3 = (tri[0] + tri[1] + tri[2]) / 3.0
				var n: Vector3 = (tri[1] - tri[0]).cross(tri[2] - tri[0]).normalized()
				if n.dot(ce) < 0:
					n = -n
				var f := faces.size()
				faces.append({"normal": n, "poly": tri, "dist": ce.dot(n)})
				var p0: Vector3 = tri[0]
				var p1: Vector3 = tri[1]
				var p2: Vector3 = tri[2]
				var q := func(i: int, j: int) -> Vector3:
					return p0 + (p1 - p0) * i / 3.0 + (p2 - p0) * j / 3.0
				for i in 3:
					for j in 3 - i:
						var up := [q.call(i, j), q.call(i + 1, j), q.call(i, j + 1)]
						cells.append({"face": f, "center": (up[0] + up[1] + up[2]) / 3.0, "poly": up})
						if i + j <= 1:
							var dn := [q.call(i + 1, j), q.call(i + 1, j + 1), q.call(i, j + 1)]
							cells.append({"face": f, "center": (dn[0] + dn[1] + dn[2]) / 3.0, "poly": dn})
		_:
			for n in [Vector3(0, 1, 0), Vector3(0, -1, 0), Vector3(0, 0, 1), Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3(-1, 0, 0)]:
				var a := Vector3(1, 0, 0) if n.x == 0 else Vector3(0, 1, 0)
				_square_face(faces, cells, n, a, n.cross(a), 1.5)
	# Соседство: общая сторона = 2 общие вершины
	var keys := []
	for c in cells:
		var ks := {}
		for p in c["poly"]:
			ks[_key(p)] = true
		keys.append(ks)
	var adj := []
	for i in cells.size():
		var row := []
		for j in cells.size():
			if i != j and _shared(keys[i], keys[j]) >= 2:
				row.append(j)
		adj.append(row)
	var fkeys := []
	for f in faces:
		var ks := {}
		for p in f["poly"]:
			ks[_key(p)] = true
		fkeys.append(ks)
	var fnb := []
	var cells_of := []
	for f in faces.size():
		var row := []
		for g in faces.size():
			if g != f and _shared(fkeys[f], fkeys[g]) >= 2:
				row.append(g)
		fnb.append(row)
		cells_of.append([])
	var centers := []
	var face_of_ := []
	for i in cells.size():
		centers.append(cells[i]["center"])
		face_of_.append(cells[i]["face"])
		cells_of[cells[i]["face"]].append(i)
	return {"cells": cells, "centers": centers, "face_of": face_of_, "adj": adj, "faces": faces, "fnb": fnb, "cells_of": cells_of}


static func _key(p: Vector3) -> String:
	return "%d,%d,%d" % [roundi(p.x * 1000), roundi(p.y * 1000), roundi(p.z * 1000)]


static func _shared(a: Dictionary, b: Dictionary) -> int:
	var n := 0
	for k in a:
		if b.has(k):
			n += 1
	return n


func g() -> Dictionary:
	return geo(shape)


func nbs(i: int) -> Array:
	return g()["adj"][i]


func center(i: int) -> Vector3:
	return g()["centers"][i]


## Многоугольник клетки в своих координатах.
func poly(i: int) -> Array:
	return g()["cells"][i]["poly"]


func face_of(i: int) -> int:
	return g()["face_of"][i]


func face_count() -> int:
	return g()["faces"].size()


func face_cells(f: int) -> Array:
	return g()["cells_of"][f]


func face_poly(f: int) -> Array:
	return g()["faces"][f]["poly"]


## Расстояние от центра фигуры до грани (у куба 1.5).
func face_dist(f: int) -> float:
	return g()["faces"][f]["dist"]


func is_tri() -> bool:
	return shape == "tetra"


## Крутится только вперёд (барабан): выбора поворота нет.
func one_way() -> bool:
	return shape == "drum"


## Середина общего ребра двух граней (свои координаты).
func shared_edge_mid(a: int, b: int) -> Vector3:
	var acc := Vector3.ZERO
	var n := 0
	for p in face_poly(a):
		for q in face_poly(b):
			if (p as Vector3).distance_to(q) < 0.01:
				acc += p
				n += 1
	return acc / maxf(1.0, float(n))


# ---------------------------------------------------------------- повороты

func world_normal(f: int) -> Vector3:
	return orient * g()["faces"][f]["normal"]


func top() -> int:
	var best := 0
	var by := -2.0
	for f in face_count():
		var y := world_normal(f).y
		if y > by:
			by = y
			best = f
	return best


func on_top(i: int) -> bool:
	return i >= 0 and i < exists.size() and face_of(i) == top()


## Грани, соседние с верхней: {грань: направление в мире по земле (нормализовано)}.
func side_faces() -> Dictionary:
	var out := {}
	for f in g()["fnb"][top()]:
		var n := world_normal(f)
		out[f] = Vector3(n.x, 0, n.z).normalized()
	return out


## Куда можно катить: соседние грани; у барабана — только следующая.
func roll_targets() -> Array:
	if one_way():
		return [(top() + 1) % face_count()]
	return g()["fnb"][top()].duplicate()


## Ось и угол поворота, чтобы грань f стала верхней.
func roll_axis(f: int) -> Vector3:
	var a := world_normal(f).cross(Vector3.UP)
	if a.length() < 0.001:
		return Vector3.RIGHT
	return a.normalized()


func roll_angle(f: int) -> float:
	return acos(clampf(world_normal(f).dot(Vector3.UP), -1.0, 1.0))


func roll_to(f: int) -> bool:
	if f == top() or f < 0 or f >= face_count():
		return false
	orient = (Basis(roll_axis(f), roll_angle(f)) * orient).orthonormalized()
	return true


# ---------------------------------------------------------------- строительство и доход

func is_free(i: int) -> bool:
	return on_top(i) and content[i] == ""


func free_cells() -> Array:
	var out := []
	for i in face_cells(top()):
		if content[i] == "":
			out.append(i)
	return out


## Доход как у острова; total — только верхняя грань, faces — доход каждой грани, all — всей фигуры.
func score(data) -> Dictionary:
	var sc: Dictionary = super.score(data)
	var faces := []
	for f in face_count():
		var t: Dictionary = data.zero_res()
		for i in face_cells(f):
			var y: Dictionary = sc["cells"][i]["yield"]
			for r in y:
				t[r] = int(t.get(r, 0)) + int(y[r])
		faces.append(t)
	sc["all"] = sc["total"]
	sc["faces"] = faces
	sc["total"] = faces[top()].duplicate()
	return sc


## Нехватка до печати: недостающие единицы, джокеры закрывают любую.
static func shortfall(prod: Dictionary, seal: Dictionary) -> int:
	var miss := 0
	for r in seal:
		miss += maxi(0, int(seal[r]) - int(prod.get(r, 0)))
	return maxi(0, miss - int(prod.get("wild", 0)))


func sealed_faces() -> Array:
	var out := []
	for f in face_count():
		if not broken[f]:
			out.append(f)
	return out


# ---------------------------------------------------------------- генерация

## Фигура для боя: камни/горы на гранях, печати из cfg (числа × scale, часть — двухцветные).
static func make(data, rng: RandomNumberGenerator, cfg: Dictionary):
	var f = load("res://scripts/land/shape_field.gd").new(cfg.get("shape", "cube"))
	var pool: Dictionary = cfg.get("obstacles", {"rock": 1})
	var per_face: Array = cfg.get("obstacles_per_face", [1, 1])
	var nf: int = f.face_count()
	for face in nf:
		var n := rng.randi_range(int(per_face[0]), int(per_face[1]))
		var cells: Array = f.face_cells(face).duplicate()
		for _k in n:
			var c: int = cells.pop_at(rng.randi_range(0, cells.size() - 1))
			f.content[c] = _weighted(pool, rng)
			f.prebuilt[c] = true
	var tpl: Array = cfg.get("seals", [3, 4, 4, 5, 5, 6])
	var amounts := []
	var cols := []
	for k in nf:
		amounts.append(tpl[k % tpl.size()])
		cols.append(data.colors[k % data.colors.size()])
	for i in range(nf - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = amounts[i]
		amounts[i] = amounts[j]
		amounts[j] = t
		var u = cols[i]
		cols[i] = cols[j]
		cols[j] = u
	var scale := float(cfg.get("scale", 1.0))
	for face in nf:
		var a := maxi(1, roundi(float(amounts[face]) * scale))
		var col: String = cols[face]
		if a >= 3 and rng.randf() < float(cfg.get("dual_chance", 0.33)):
			var others: Array = data.colors.filter(func(c): return c != col)
			var c2: String = others[rng.randi_range(0, others.size() - 1)]
			var h := a / 2 + 1
			f.seals[face] = {col: h, c2: a + 1 - h}
		else:
			f.seals[face] = {col: a}
	# Стартовое положение: случайная грань сверху (через соседей)
	var start := rng.randi_range(0, nf - 1)
	var guard := 0
	while f.top() != start and guard < 6:
		var tg: Array = f.g()["fnb"][f.top()]
		f.roll_to(start if start in tg else tg[0])
		guard += 1
	return f


## Сталь: печати ×mult (вверх).
func scale_seals(mult: float) -> void:
	for face in face_count():
		for r in seals[face]:
			seals[face][r] = int(ceil(int(seals[face][r]) * mult))


static func _weighted(pool: Dictionary, rng: RandomNumberGenerator) -> String:
	var total := 0.0
	for k in pool:
		total += float(pool[k])
	var x := rng.randf() * total
	for k in pool:
		x -= float(pool[k])
		if x <= 0:
			return k
	return pool.keys()[0]
