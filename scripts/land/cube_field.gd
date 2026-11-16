## Босс-куб: остров из 6 граней 3×3 (54 клетки). Клетка = грань*9 + ряд*3 + столбец.
## Соседство и внутри грани, и через рёбра куба (здание на краю видит здание соседней грани).
## На каждой грани печать (сколько ресурса нужно). Игрок катит куб на соседнюю грань,
## строит на верхней, в конце хода верхнюю грань проверяют.
extends "res://scripts/land/land_field.gd"

const FACES := 6
const CELLS := 54
## Нормали граней в «своей» системе куба (до поворотов).
const NORMALS := [Vector3(0, 1, 0), Vector3(0, -1, 0), Vector3(0, 0, 1), Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3(-1, 0, 0)]

static var _adj: Array = []
static var _center: Array = []

## Поворот куба: мир = orient * свои координаты.
var orient := Basis.IDENTITY
## Печати граней: [{res: n}] и сняты ли они.
var seals: Array = []
var broken: Array = []


func _init() -> void:
	_alloc(CELLS)
	for i in CELLS:
		exists[i] = true
	seals = []
	broken = []
	for f in FACES:
		seals.append({})
		broken.append(false)
	_geometry()


static func _axes(n: Vector3) -> Array:
	var a := Vector3(1, 0, 0) if n.x == 0 else Vector3(0, 1, 0)
	return [a, n.cross(a)]


## Центр клетки в своих координатах куба (ребро куба = 3, центр куба в нуле).
static func center(i: int) -> Vector3:
	_geometry()
	return _center[i]


static func face_of(i: int) -> int:
	return i / 9


static func _geometry() -> void:
	if not _center.is_empty():
		return
	for f in FACES:
		var n: Vector3 = NORMALS[f]
		var ax := _axes(n)
		for r in 3:
			for c in 3:
				_center.append(n * 1.5 + ax[0] * (c - 1) + ax[1] * (r - 1))
	for i in CELLS:
		var row := []
		for j in CELLS:
			if i == j:
				continue
			var d: float = _center[i].distance_to(_center[j])
			var same := i / 9 == j / 9
			if (same and d < 1.01) or (not same and d < 0.8):
				row.append(j)
		_adj.append(row)


func nbs(i: int) -> Array:
	return _adj[i]


func clone():
	var f = super.clone()
	f.orient = orient
	f.seals = seals.duplicate(true)
	f.broken = broken.duplicate()
	return f


# ---------------------------------------------------------------- повороты

## Нормаль грани в мире.
func world_normal(f: int) -> Vector3:
	return (orient * NORMALS[f]).round()


## Какая грань сейчас в направлении dir (Vector3.UP — верхняя).
func face_at(dir: Vector3) -> int:
	for f in FACES:
		if world_normal(f).is_equal_approx(dir):
			return f
	return -1


func top() -> int:
	return face_at(Vector3.UP)


func on_top(i: int) -> bool:
	return i >= 0 and i < CELLS and face_of(i) == top()


## Грани-соседи верхней: {грань: направление в мире (вперёд/назад/влево/вправо)}.
func side_faces() -> Dictionary:
	var out := {}
	for d in [Vector3(0, 0, 1), Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3(-1, 0, 0)]:
		out[face_at(d)] = d
	return out


## Ось и знак поворота, чтобы грань f стала верхней (на 90°).
func roll_axis(f: int) -> Vector3:
	return world_normal(f).cross(Vector3.UP).normalized()


func roll_to(f: int) -> bool:
	if not side_faces().has(f):
		return false
	var b := Basis(roll_axis(f), PI / 2.0) * orient
	# убрать погрешность: все элементы — целые
	orient = Basis(b.x.round(), b.y.round(), b.z.round())
	return true


# ---------------------------------------------------------------- строительство и доход

## Строить можно только на верхней грани.
func is_free(i: int) -> bool:
	return on_top(i) and content[i] == ""


func free_cells() -> Array:
	var out := []
	var t := top()
	for k in 9:
		if content[t * 9 + k] == "":
			out.append(t * 9 + k)
	return out


## Доход как у острова; total — только верхняя грань, faces — доход каждой грани.
func score(data) -> Dictionary:
	var sc: Dictionary = super.score(data)
	var faces := []
	for f in FACES:
		var t: Dictionary = data.zero_res()
		for k in 9:
			var y: Dictionary = sc["cells"][f * 9 + k]["yield"]
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
	for f in FACES:
		if not broken[f]:
			out.append(f)
	return out


# ---------------------------------------------------------------- генерация

## Куб для боя: камни/горы на гранях, печати из cfg (числа × scale, часть — двухцветные).
static func make(data, rng: RandomNumberGenerator, cfg: Dictionary):
	var f = load("res://scripts/land/cube_field.gd").new()
	var pool: Dictionary = cfg.get("obstacles", {"rock": 1})
	var per_face: Array = cfg.get("obstacles_per_face", [1, 1])
	for face in FACES:
		var n := rng.randi_range(int(per_face[0]), int(per_face[1]))
		var cells := range(9)
		for _k in n:
			var k: int = cells.pop_at(rng.randi_range(0, cells.size() - 1))
			var id := _weighted(pool, rng)
			f.content[face * 9 + k] = id
			f.prebuilt[face * 9 + k] = true
	var amounts: Array = cfg.get("seals", [3, 4, 4, 5, 5, 6]).duplicate()
	var cols: Array = data.colors + data.colors
	for i in range(amounts.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = amounts[i]
		amounts[i] = amounts[j]
		amounts[j] = t
		var u = cols[i]
		cols[i] = cols[j]
		cols[j] = u
	var scale := float(cfg.get("scale", 1.0))
	for face in FACES:
		var a := maxi(1, roundi(float(amounts[face % amounts.size()]) * scale))
		var col: String = cols[face % cols.size()]
		if a >= 3 and rng.randf() < float(cfg.get("dual_chance", 0.33)):
			var others: Array = data.colors.filter(func(c): return c != col)
			var c2: String = others[rng.randi_range(0, others.size() - 1)]
			var h := a / 2 + 1
			f.seals[face] = {col: h, c2: a + 1 - h}
		else:
			f.seals[face] = {col: a}
	# Стартовое положение: случайная грань сверху
	var start := rng.randi_range(0, FACES - 1)
	if start != 0:
		var sides: Dictionary = f.side_faces()
		if sides.has(start):
			f.roll_to(start)
		else:
			f.roll_to(sides.keys()[0])
			f.roll_to(start)
	return f


## Сталь: печати ×mult (вверх).
func scale_seals(mult: float) -> void:
	for face in FACES:
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
