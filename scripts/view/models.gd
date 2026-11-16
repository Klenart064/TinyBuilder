## Low-poly модели зданий из примитивов Godot. Каждое здание — узнаваемый силуэт
## и цветной акцент своего ресурса (еда — жёлто-зелёный, золото — золотой, сила — красный).
## Используются и на острове, и для картинок на картах.
extends RefCounted

const FOOD := Color("#e8c547")
const GOLD := Color("#f2c94c")
const FORCE := Color("#d94545")
const WOOD := Color("#8a5a3a")
const WOOD_DARK := Color("#5e3d27")
const STONE := Color("#9a9a9f")
const STONE_DARK := Color("#6e6e75")
const PLASTER := Color("#efe6d2")
const ROOF := Color("#8a3b2a")
const ECHO := Color("#5fe3ff")

var alpha := 1.0
var root: Node3D


static func build(id: String, alpha_: float = 1.0) -> Node3D:
	var m = new()
	m.alpha = alpha_
	m.root = Node3D.new()
	var bid := id.trim_suffix("+").trim_suffix("-")
	var echo_lv := 0
	if bid.contains("*"):
		echo_lv = int(bid.get_slice("*", 1))
		bid = bid.get_slice("*", 0)
	match bid:
		"field": m._field()
		"mill": m._mill()
		"mine": m._mine()
		"smithy": m._smithy()
		"barracks": m._barracks()
		"tower": m._tower()
		"house": m._house()
		"manor": m._manor()
		"market": m._market()
		"tavern": m._tavern()
		"mountain": m._mountain()
		"anvil": m._anvil()
		_: return null
	if id.ends_with("+"):
		m._upgrade_flag()
	if echo_lv > 0:
		m._echo_rings(echo_lv)
	return m.root


## Эхо: голубые светящиеся кольца у основания (сколько уровень — столько колец).
func _echo_rings(n: int) -> void:
	for k in n:
		var t := TorusMesh.new()
		t.inner_radius = 0.42 + k * 0.07
		t.outer_radius = 0.46 + k * 0.07
		t.rings = 24
		t.ring_segments = 6
		_put(t, Vector3(0, 0.05 + k * 0.05, 0), ECHO, Vector3.ZERO, true)


## Уровень мастерской на острове (0–4): пристройки по углам клетки и значок с точками.
## Только вид — доход не меняется. Пристройка по цвету: еда — стог и мешки, золото — ящики и слиток, сила — шатёр и знамя.
static func add_level(root_: Node3D, id: String, level: int, alpha_: float = 1.0) -> void:
	if level <= 0:
		return
	var m = new()
	m.alpha = alpha_
	m.root = Node3D.new()
	root_.add_child(m.root)
	var corners := [Vector3(-0.36, 0, 0.36), Vector3(0.36, 0, 0.36), Vector3(0.36, 0, -0.36), Vector3(-0.36, 0, -0.36)]
	var bid := id.trim_suffix("+").trim_suffix("-").get_slice("*", 0)
	for k in mini(level, 4):
		var c: Vector3 = corners[k]
		match bid:
			"mill":
				# Амбар со стогом
				m.box(Vector3(0.2, 0.16, 0.18), c + Vector3(0, 0.08, 0), WOOD)
				m.roof(0.22, 0.1, 0.2, c + Vector3(0, 0.21, 0), ROOF)
				m.cyl(0.0, 0.11, 0.2, c + Vector3(0.12, 0.1, -0.1), FOOD, 8)
			"smithy":
				# Склад с ящиками и слитком
				m.box(Vector3(0.18, 0.14, 0.18), c + Vector3(0, 0.07, 0), WOOD)
				m.box(Vector3(0.12, 0.1, 0.12), c + Vector3(0.02, 0.19, 0.02), WOOD_DARK)
				m.box(Vector3(0.12, 0.06, 0.07), c + Vector3(0, 0.27, 0), GOLD, Vector3.ZERO, true)
			"field":
				# Стог и тележка
				m.cyl(0.0, 0.12, 0.22, c + Vector3(0, 0.11, 0), FOOD, 8)
				m.box(Vector3(0.16, 0.06, 0.1), c + Vector3(0.1, 0.06, -0.1), WOOD)
			"mine":
				# Вагонетка с рудой
				m.box(Vector3(0.18, 0.08, 0.12), c + Vector3(0, 0.08, 0), STONE_DARK)
				m.ball(0.06, c + Vector3(-0.03, 0.15, 0), GOLD, true)
				m.ball(0.05, c + Vector3(0.05, 0.14, 0.02), GOLD, true)
			"tower":
				# Кусок стены с зубцом
				m.box(Vector3(0.24, 0.18, 0.08), c + Vector3(0, 0.09, 0), STONE)
				m.box(Vector3(0.07, 0.07, 0.08), c + Vector3(-0.08, 0.215, 0), STONE_DARK)
				m.box(Vector3(0.07, 0.07, 0.08), c + Vector3(0.08, 0.215, 0), STONE_DARK)
			"house", "manor":
				# Грядка, колодец, забор, дерево — по очереди
				match k:
					0:
						m.box(Vector3(0.22, 0.05, 0.14), c + Vector3(0, 0.025, 0), Color("#6b4a2e"))
						for q in 3:
							m.ball(0.035, c + Vector3(-0.07 + q * 0.07, 0.07, 0), Color("#7cc45a"))
					1:
						m.cyl(0.07, 0.07, 0.1, c + Vector3(0, 0.05, 0), STONE, 10)
						m.roof(0.16, 0.07, 0.12, c + Vector3(0, 0.2, 0), ROOF)
					2:
						for q in 3:
							m.box(Vector3(0.025, 0.1, 0.025), c + Vector3(-0.08 + q * 0.08, 0.05, 0), WOOD)
						m.box(Vector3(0.2, 0.02, 0.02), c + Vector3(0, 0.08, 0), WOOD)
					_:
						m.cyl(0.02, 0.025, 0.14, c + Vector3(0, 0.07, 0), WOOD_DARK, 6)
						m.ball(0.09, c + Vector3(0, 0.2, 0), Color("#5d9a3e"))
			"market":
				# Лоток с навесом
				m.box(Vector3(0.18, 0.08, 0.12), c + Vector3(0, 0.04, 0), WOOD)
				m.box(Vector3(0.22, 0.02, 0.16), c + Vector3(0, 0.2, 0), [FOOD, GOLD, FORCE][k % 3])
				m.box(Vector3(0.02, 0.12, 0.02), c + Vector3(-0.09, 0.14, 0.06), WOOD_DARK)
				m.box(Vector3(0.02, 0.12, 0.02), c + Vector3(0.09, 0.14, 0.06), WOOD_DARK)
			"tavern":
				# Бочка и стол
				m.cyl(0.06, 0.06, 0.14, c + Vector3(-0.06, 0.07, 0), WOOD, 10)
				m.box(Vector3(0.12, 0.02, 0.1), c + Vector3(0.08, 0.1, 0), WOOD_DARK)
				m.box(Vector3(0.02, 0.1, 0.02), c + Vector3(0.08, 0.05, 0), WOOD_DARK)
			_:
				# Шатёр со знаменем
				m.cyl(0.0, 0.16, 0.26, c + Vector3(0, 0.13, 0), Color("#d8cfc0"), 6)
				m.box(Vector3(0.025, 0.42, 0.025), c + Vector3(0.12, 0.21, 0), WOOD_DARK)
				m.box(Vector3(0.14, 0.09, 0.015), c + Vector3(0.19, 0.37, 0), FORCE)


## Гора: две вершины со снегом и золотой жилой (Шахтам рядом +2).
func _mountain() -> void:
	cyl(0.0, 0.4, 0.85, Vector3(0.05, 0.425, 0.05), Color("#7d7a78"), 7)
	cyl(0.0, 0.12, 0.25, Vector3(0.05, 0.73, 0.05), Color("#f2f2f2"), 7)
	cyl(0.0, 0.26, 0.55, Vector3(-0.25, 0.275, 0.22), Color("#6e6b69"), 6)
	cyl(0.0, 0.08, 0.15, Vector3(-0.25, 0.48, 0.22), Color("#f2f2f2"), 6)
	box(Vector3(0.05, 0.22, 0.03), Vector3(0.18, 0.25, 0.33), GOLD, Vector3(0, 0, 25), true)


## Наковальня острова-кузницы: каменная плита, наковальня, горн с огнём.
func _anvil() -> void:
	box(Vector3(0.8, 0.08, 0.8), Vector3(0, 0.04, 0), STONE_DARK)
	box(Vector3(0.14, 0.18, 0.14), Vector3(0, 0.17, 0), Color("#2e2e33"))
	box(Vector3(0.42, 0.1, 0.18), Vector3(0, 0.31, 0), Color("#3d3d44"))
	cyl(0.0, 0.07, 0.16, Vector3(0.27, 0.31, 0), Color("#3d3d44"), 8, Vector3(0, 0, 90))
	cyl(0.2, 0.22, 0.2, Vector3(-0.22, 0.18, -0.25), STONE, 10)
	ball(0.1, Vector3(-0.22, 0.3, -0.25), Color("#ff7a2a"), true)


## Улучшенная карта: золотой флажок на углу клетки.
func _upgrade_flag() -> void:
	box(Vector3(0.04, 0.9, 0.04), Vector3(-0.4, 0.45, 0.4), WOOD_DARK)
	box(Vector3(0.02, 0.18, 0.26), Vector3(-0.4, 0.8, 0.27), GOLD, Vector3.ZERO, true)
	ball(0.05, Vector3(-0.4, 0.92, 0.4), GOLD, true)


# ---------------------------------------------------------------- примитивы

func _mat(color: Color, glow: bool = false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(color, alpha)
	m.roughness = 0.85
	if glow:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m


func _put(mesh: Mesh, pos: Vector3, color: Color, rot: Vector3 = Vector3.ZERO, glow: bool = false, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.rotation_degrees = rot
	mi.material_override = _mat(color, glow)
	(parent if parent != null else root).add_child(mi)
	return mi


func box(size: Vector3, pos: Vector3, color: Color, rot: Vector3 = Vector3.ZERO, glow: bool = false) -> MeshInstance3D:
	var m := BoxMesh.new()
	m.size = size
	return _put(m, pos, color, rot, glow)


func cyl(r_top: float, r_bot: float, h: float, pos: Vector3, color: Color, segs: int = 12, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var m := CylinderMesh.new()
	m.top_radius = r_top
	m.bottom_radius = r_bot
	m.height = h
	m.radial_segments = segs
	m.rings = 1
	return _put(m, pos, color, rot)


func ball(r: float, pos: Vector3, color: Color, glow: bool = false) -> MeshInstance3D:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2
	m.radial_segments = 10
	m.rings = 5
	return _put(m, pos, color, Vector3.ZERO, glow)


## Двускатная крыша: призма вдоль оси X.
func roof(w: float, h: float, d: float, pos: Vector3, color: Color, rot_y: float = 0.0) -> MeshInstance3D:
	var m := PrismMesh.new()
	m.size = Vector3(d, h, w)
	return _put(m, pos, color, Vector3(0, 90 + rot_y, 0))


# ---------------------------------------------------------------- здания

## Поле: пашня и ряды колосьев.
func _field() -> void:
	box(Vector3(0.94, 0.08, 0.94), Vector3(0, 0.04, 0), Color("#7a5634"))
	for row in 4:
		var z := -0.33 + row * 0.22
		box(Vector3(0.84, 0.05, 0.1), Vector3(0, 0.1, z), Color("#5e4128"))
		for k in 5:
			var x := -0.34 + k * 0.17
			cyl(0.0, 0.055, 0.26, Vector3(x, 0.24, z), FOOD, 6)
	# Пугало
	box(Vector3(0.04, 0.5, 0.04), Vector3(0.36, 0.33, 0.36), WOOD_DARK)
	box(Vector3(0.3, 0.04, 0.04), Vector3(0.36, 0.46, 0.36), WOOD_DARK)
	ball(0.07, Vector3(0.36, 0.6, 0.36), Color("#d9b26a"))


## Мельница: каменная башня, конусная крыша, четыре больших лопасти.
func _mill() -> void:
	cyl(0.24, 0.33, 0.85, Vector3(0, 0.425, 0), PLASTER, 10)
	cyl(0.0, 0.32, 0.38, Vector3(0, 1.04, 0), Color("#6b8f3a"), 10)
	box(Vector3(0.16, 0.24, 0.05), Vector3(0, 0.12, 0.32), WOOD_DARK)
	var hub := Node3D.new()
	hub.position = Vector3(0, 0.82, 0.3)
	root.add_child(hub)
	var hm := CylinderMesh.new()
	hm.top_radius = 0.06
	hm.bottom_radius = 0.06
	hm.height = 0.12
	_put(hm, Vector3.ZERO, WOOD_DARK, Vector3(90, 0, 0), false, hub)
	for k in 4:
		var arm := Node3D.new()
		arm.rotation_degrees = Vector3(0, 0, 20 + k * 90)
		hub.add_child(arm)
		var stick := BoxMesh.new()
		stick.size = Vector3(0.05, 0.62, 0.03)
		_put(stick, Vector3(0, 0.33, 0.04), WOOD, Vector3.ZERO, false, arm)
		var sail := BoxMesh.new()
		sail.size = Vector3(0.17, 0.46, 0.015)
		_put(sail, Vector3(0.1, 0.38, 0.05), Color("#f4ecd8"), Vector3.ZERO, false, arm)


## Шахта: каменный холм, деревянный вход, рельсы и вагонетка с золотом.
func _mine() -> void:
	ball(0.42, Vector3(-0.05, 0.12, -0.12), STONE_DARK)
	ball(0.3, Vector3(0.25, 0.08, -0.22), STONE)
	ball(0.26, Vector3(-0.3, 0.06, 0.1), STONE)
	box(Vector3(0.36, 0.38, 0.1), Vector3(0, 0.19, 0.22), Color("#1a1410"))
	box(Vector3(0.06, 0.44, 0.08), Vector3(-0.2, 0.22, 0.27), WOOD)
	box(Vector3(0.06, 0.44, 0.08), Vector3(0.2, 0.22, 0.27), WOOD)
	box(Vector3(0.5, 0.07, 0.09), Vector3(0, 0.46, 0.27), WOOD)
	for x in [-0.09, 0.09]:
		box(Vector3(0.03, 0.03, 0.42), Vector3(x, 0.02, 0.45), STONE_DARK)
	box(Vector3(0.28, 0.14, 0.2), Vector3(0, 0.12, 0.5), WOOD_DARK)
	for k in 3:
		ball(0.06, Vector3(-0.08 + k * 0.08, 0.22, 0.5), GOLD)


## Кузница: каменный дом, высокая труба с огнём, наковальня у входа.
func _smithy() -> void:
	box(Vector3(0.7, 0.45, 0.6), Vector3(-0.05, 0.225, -0.05), STONE)
	roof(0.7, 0.28, 0.6, Vector3(-0.05, 0.59, -0.05), Color("#3f3f48"))
	box(Vector3(0.18, 0.75, 0.18), Vector3(0.22, 0.6, -0.2), STONE_DARK)
	box(Vector3(0.12, 0.06, 0.12), Vector3(0.22, 1.0, -0.2), Color("#ff8a2a"), Vector3.ZERO, true)
	box(Vector3(0.22, 0.26, 0.04), Vector3(-0.12, 0.13, 0.26), Color("#ff7a1a"), Vector3.ZERO, true)
	# Наковальня
	box(Vector3(0.1, 0.12, 0.08), Vector3(0.22, 0.06, 0.38), Color("#2c2c33"))
	box(Vector3(0.24, 0.07, 0.11), Vector3(0.22, 0.155, 0.38), Color("#3a3a44"))
	box(Vector3(0.08, 0.05, 0.08), Vector3(0.35, 0.165, 0.38), Color("#3a3a44"))
	ball(0.05, Vector3(0.18, 0.22, 0.38), GOLD)


## Казарма: длинный деревянный дом, щит на стене, флаг.
func _barracks() -> void:
	box(Vector3(0.84, 0.12, 0.52), Vector3(0, 0.06, 0), STONE_DARK)
	box(Vector3(0.82, 0.3, 0.5), Vector3(0, 0.27, 0), WOOD_DARK)
	roof(0.88, 0.3, 0.58, Vector3(0, 0.57, 0), Color("#a83232"))
	box(Vector3(0.14, 0.24, 0.03), Vector3(0.12, 0.12, 0.26), Color("#2a1c12"))
	# Щит
	var sh := CylinderMesh.new()
	sh.top_radius = 0.09
	sh.bottom_radius = 0.09
	sh.height = 0.03
	sh.radial_segments = 8
	_put(sh, Vector3(-0.12, 0.26, 0.26), Color("#c0c0c8"), Vector3(90, 0, 0))
	box(Vector3(0.04, 0.12, 0.04), Vector3(-0.12, 0.26, 0.28), FORCE)
	# Флаг на коньке крыши
	box(Vector3(0.035, 0.5, 0.035), Vector3(0.0, 0.88, 0), WOOD_DARK)
	box(Vector3(0.28, 0.18, 0.02), Vector3(0.15, 1.02, 0), FORCE)
	# Знамёна на стене
	for x in [-0.3, 0.3]:
		box(Vector3(0.1, 0.22, 0.02), Vector3(x, 0.24, 0.26), FORCE)
	# Копья
	for k in 3:
		box(Vector3(0.025, 0.42, 0.025), Vector3(0.28 + k * 0.06, 0.21, 0.36), WOOD_DARK, Vector3(0, 0, -8))


## Башня: круглая каменная, зубцы, красный флаг.
func _tower() -> void:
	cyl(0.27, 0.32, 1.0, Vector3(0, 0.5, 0), STONE, 10)
	cyl(0.34, 0.3, 0.12, Vector3(0, 1.04, 0), STONE_DARK, 10)
	for k in 8:
		var a := k * TAU / 8
		box(Vector3(0.1, 0.12, 0.1), Vector3(cos(a) * 0.29, 1.16, sin(a) * 0.29), STONE_DARK, Vector3(0, -rad_to_deg(a), 0))
	box(Vector3(0.1, 0.18, 0.03), Vector3(0, 0.6, 0.3), Color("#1a1a1f"))
	box(Vector3(0.03, 0.45, 0.03), Vector3(0, 1.3, 0), WOOD_DARK)
	box(Vector3(0.24, 0.14, 0.02), Vector3(0.13, 1.44, 0), FORCE)


## Дом: белёные стены, коричневая крыша, труба, окна.
func _house() -> void:
	box(Vector3(0.62, 0.4, 0.5), Vector3(0, 0.2, 0), PLASTER)
	roof(0.7, 0.34, 0.6, Vector3(0, 0.57, 0), ROOF)
	box(Vector3(0.1, 0.3, 0.1), Vector3(0.18, 0.72, -0.08), Color("#7a6a5a"))
	box(Vector3(0.13, 0.24, 0.03), Vector3(-0.12, 0.12, 0.26), WOOD_DARK)
	box(Vector3(0.12, 0.11, 0.03), Vector3(0.15, 0.24, 0.26), Color("#7fb6e0"))
	box(Vector3(0.03, 0.11, 0.11), Vector3(0.32, 0.24, 0.05), Color("#7fb6e0"))
	# Заборчик
	for k in 4:
		box(Vector3(0.03, 0.12, 0.03), Vector3(-0.36 + k * 0.1, 0.06, 0.4), WOOD)
	box(Vector3(0.34, 0.025, 0.02), Vector3(-0.21, 0.09, 0.4), WOOD)


## Усадьба: большой двухэтажный дом с башенкой и садом.
func _manor() -> void:
	box(Vector3(0.78, 0.52, 0.5), Vector3(0, 0.26, -0.05), PLASTER)
	roof(0.86, 0.34, 0.6, Vector3(0, 0.69, -0.05), Color("#6a4a8a"))
	cyl(0.13, 0.13, 0.8, Vector3(0.36, 0.4, 0.2), PLASTER, 8)
	cyl(0.0, 0.18, 0.3, Vector3(0.36, 0.95, 0.2), Color("#6a4a8a"), 8)
	box(Vector3(0.16, 0.28, 0.03), Vector3(-0.05, 0.14, 0.21), WOOD_DARK)
	for x in [-0.28, 0.14]:
		box(Vector3(0.11, 0.11, 0.03), Vector3(x, 0.38, 0.21), Color("#7fb6e0"))
	box(Vector3(0.11, 0.11, 0.03), Vector3(-0.28, 0.16, 0.21), Color("#7fb6e0"))
	ball(0.09, Vector3(-0.36, 0.09, 0.38), Color("#4f8a3a"))
	ball(0.07, Vector3(-0.2, 0.07, 0.4), Color("#4f8a3a"))


## Рынок: прилавки под полосатыми навесами, корзины с товаром трёх цветов.
func _market() -> void:
	box(Vector3(0.9, 0.04, 0.9), Vector3(0, 0.02, 0), Color("#b8a888"))
	var awn := [Color("#d94545"), Color("#e8c547"), Color("#6aa84f")]
	for k in 2:
		var x := -0.22 + k * 0.44
		for c in [[-0.15, -0.15], [0.15, -0.15], [-0.15, 0.15], [0.15, 0.15]]:
			box(Vector3(0.03, 0.42, 0.03), Vector3(x + c[0], 0.21, c[1]), WOOD_DARK)
		box(Vector3(0.36, 0.1, 0.34), Vector3(x, 0.17, 0), WOOD)
		box(Vector3(0.42, 0.04, 0.42), Vector3(x, 0.45, 0), awn[k], Vector3(0, 0, 8 if k == 0 else -8))
		box(Vector3(0.42, 0.045, 0.1), Vector3(x, 0.47, 0), Color("#f4ecd8"), Vector3(0, 0, 8 if k == 0 else -8))
	ball(0.06, Vector3(-0.28, 0.26, 0.0), FOOD)
	ball(0.06, Vector3(-0.16, 0.26, 0.05), Color("#6aa84f"))
	ball(0.06, Vector3(0.18, 0.26, 0.0), GOLD)
	ball(0.06, Vector3(0.28, 0.26, 0.05), FORCE)
	cyl(0.08, 0.06, 0.1, Vector3(0, 0.05, 0.36), WOOD)


## Таверна: деревянный дом с вывеской-кружкой и бочками.
func _tavern() -> void:
	box(Vector3(0.72, 0.18, 0.52), Vector3(0, 0.09, 0), STONE)
	box(Vector3(0.72, 0.3, 0.52), Vector3(0, 0.33, 0), Color("#a9784a"))
	roof(0.8, 0.32, 0.62, Vector3(0, 0.64, 0), Color("#5a7a3a"))
	box(Vector3(0.14, 0.24, 0.03), Vector3(-0.12, 0.12, 0.27), WOOD_DARK)
	box(Vector3(0.24, 0.03, 0.03), Vector3(0.25, 0.46, 0.34), WOOD_DARK)
	box(Vector3(0.14, 0.14, 0.02), Vector3(0.3, 0.37, 0.34), Color("#f2c94c"))
	box(Vector3(0.06, 0.08, 0.025), Vector3(0.3, 0.37, 0.35), Color("#f4ecd8"))
	for k in 2:
		cyl(0.08, 0.08, 0.18, Vector3(0.38 - k * 0.12, 0.09, 0.4 - k * 0.04), WOOD, 8)
	box(Vector3(0.08, 0.25, 0.08), Vector3(-0.22, 0.85, -0.1), STONE_DARK)
