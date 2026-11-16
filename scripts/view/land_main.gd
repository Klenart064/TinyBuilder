## Прототип «живая земля»: поле до 4×4, ход игрока (до 2 построек), потом ход земли.
## Логика — в scripts/land, здесь только отображение и ввод.
extends Node3D

const LandData = preload("res://scripts/land/land_data.gd")
const LandRun = preload("res://scripts/land/land_run.gd")
const LandField = preload("res://scripts/land/land_field.gd")
const LandEvents = preload("res://scripts/land/land_events.gd")
const Models = preload("res://scripts/view/models.gd")
const LandBot = preload("res://scripts/land/land_bot.gd")
const ShapeField = preload("res://scripts/land/shape_field.gd")
const LandTest = preload("res://scripts/land/land_test.gd")

const STEP := 1.15
const TILE_COLOR := Color("#5d7a3a")
const TILE_FREE_COLOR := Color("#7fa04f")
const TILE_HOVER_COLOR := Color("#a8cf6a")
const TILE_DANGER_COLOR := Color("#b0563f")
const PAIR_COLOR := Color("#ffd866")
const HOUSE_COLOR := Color("#f4e7d0")
const CONFLICT_COLOR := Color("#ff4d4d")
const LAND_COLOR := Color("#c58cff")
const DANGER_COLOR := Color("#ff5a3c")
const GROW_COLOR := Color("#7dffa0")
const GREY_COLOR := Color("#b9b2a6")
const ECHO_COLOR := Color("#5fe3ff")
const ROAD_COLOR := Color("#e8c47c")
const PATH_COLOR := Color("#efe2c4")
const BRIDGE_COLOR := Color("#8a5a33")
const SEAL_COLOR := Color("#ffb347")
const SEAL_DONE_COLOR := Color("#6fcf97")
const CAMERA_BASE := Vector3(7.3, 7.1, 7.3)
const SHAPE_WORD := {"cube": "куб", "tetra": "тетраэдр", "drum": "барабан"}
const SHAPE_DESC := {
	"cube": "Куб: 6 граней 3×3, на каждой печать (схема слева). Каждый ход катите куб на любую соседнюю грань.",
	"tetra": "Тетраэдр: 4 треугольные грани по 9 клеток, на каждой печать (схема слева). Каждая грань соседствует со всеми остальными — катите на любую. Клетки треугольные: у каждой 3 соседа.",
	"drum": "Барабан: 6 граней 3×3 по кругу, на каждой печать (схема слева). Крутится сам и только вперёд — порядок граней виден заранее, выбирать нельзя. Готовьте следующие грани заранее.",
}

## Куб: на какую грань сейчас наведена мышь (для выбора поворота)
var roll_hover := -1
## Куб: поворот камеры вокруг куба (Q/E), радианы
var cam_yaw := 0.0
var part_roots: Array = []
var cross_nodes: Array = []
var under_nodes: Array = []
## Масштаб значков над полем (у больших фигур камера дальше)
var badge_k := 1.0
var _cam_turning := false

var data
var run

var selected := -1
var hover := -1
var busy := false
var show_rules := false

# 3D
var camera: Camera3D
var board_root: Node3D
var intent_root: Node3D
var hover_root: Node3D
var tiles: Array = []      # MeshInstance3D или null
var tile_mats: Array = []  # StandardMaterial3D или null
var tile_base: Array = []  # базовый цвет клетки
var objs: Array = []       # Node3D или null
var ghost: Node3D
var ghost_key := ""
var pulse_mats: Array = []
var _time := 0.0

# UI
var info_box: VBoxContainer
var side_box: VBoxContainer
var hint_text: RichTextLabel
var hand_box: HBoxContainer
var undo_btn: Button
var end_btn: Button
var claim_btn: Button
var treasury_box: HBoxContainer
var overlay: Control
var overlay_text: RichTextLabel
var overlay_buttons: HBoxContainer
var overlay_body: VBoxContainer
var overlay_box: PanelContainer
var overlay_mode := ""  # "", "result", "map", "market", "deck"
var toast: RichTextLabel


func _ready() -> void:
	data = LandData.new()
	if not data.load_all():
		push_error("Ошибка в файлах data/land/*.json — смотрите вывод выше")
	run = LandRun.new()
	_build_world()
	_build_ui()
	_new_run()


func _new_run(seed: int = -1) -> void:
	run.start(data, seed)
	selected = -1
	busy = false
	_hide_overlay()
	_full_refresh()
	_show_map()


func _process(delta: float) -> void:
	_time += delta
	var a := 0.45 + 0.35 * sin(_time * 4.0)
	for m in pulse_mats:
		if is_instance_valid(m):
			m.albedo_color.a = a


# ---------------------------------------------------------------- 3D мир

func _build_world() -> void:
	var env_node := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#232a35")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.85, 0.9, 1.0)
	env.ambient_light_energy = 0.55
	env_node.environment = env
	add_child(env_node)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-60, -30, 0)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	add_child(sun)

	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 7.8
	add_child(camera)
	camera.position = Vector3(7, 8, 7) + Vector3(0.3, 0, 0.3)
	camera.look_at(Vector3(0.3, 0, 0.3), Vector3.UP)
	camera.position += Vector3(0, -0.9, 0)

	board_root = Node3D.new()
	add_child(board_root)
	intent_root = Node3D.new()
	add_child(intent_root)
	hover_root = Node3D.new()
	add_child(hover_root)


func cell_pos(i: int) -> Vector3:
	if _is_cube():
		return run.field.orient * run.field.center(i) * STEP + _cube_off()
	if _is_multi():
		return run.field.world(i) * STEP
	return Vector3((i % LandField.SIZE - 1.5) * STEP, 0, (i / LandField.SIZE - 1.5) * STEP)


## Куда «вверх» смотрит клетка (у куба — нормаль её грани).
func cell_up(i: int) -> Vector3:
	if _is_cube():
		return run.field.world_normal(run.field.face_of(i))
	if _is_multi():
		return run.field.up(i)
	return Vector3.UP


func _shape_word() -> String:
	return SHAPE_WORD.get(run.field.shape, "куб") if _is_cube() else "куб"


## Остров из частей: парные, вращающиеся, перевёртыш.
func _is_multi() -> bool:
	return run != null and run.field != null and run.field.has_method("advance")


## Куда класть узлы клетки: у острова из частей — в узел своей части (чтобы её можно было вращать).
func _cell_parent(i: int) -> Node3D:
	if _is_multi() and run.field.kind == "spin" and part_roots.size() > 0:
		return part_roots[run.field.part_of[i]]
	return board_root


func _multi_info() -> void:
	var f = run.field
	var side := ["левом", "правом"]
	match f.kind:
		"pair":
			var mb := _section(info_box, "Парные острова", ECHO_COLOR, 18)
			mb.add_child(_rich_line("Сейчас стройте на [b]%s[/b] острове, после хода — на %s. Здания у общей границы — соседи через мост." % [side[f.active], side[1 - f.active]], 15))
		"spin":
			var sb := _section(info_box, "Вращающиеся острова", ECHO_COLOR, 18)
			var last: bool = run.turn >= run.turns_here()
			if last:
				sb.add_child(_rich_line("Последний ход: острова больше не повернутся.", 15))
			else:
				sb.add_child(_rich_line("После хода [b]%s[/b] остров повернётся на четверть по часовой (голубая стрелка). Соседи через мост сменятся." % ("левый" if f.spin_next == 0 else "правый"), 15))
		"flip":
			var fb := _section(info_box, "Перевёртыш", ECHO_COLOR, 18)
			var under: int = f.buildings_on(data, 1 - f.active)
			fb.add_child(_rich_line("Сверху сторона [b]%s[/b]. После хода остров перевернётся. Снизу зданий: %d — они тоже приносят доход, а клетки края связаны через ребро." % ["А" if f.active == 0 else "Б", under], 15))


func _is_cube() -> bool:
	return run != null and run.field != null and run.field.has_method("roll_to")


## Центр куба: верхняя грань на высоте обычного острова (y = 0).
func _cube_off() -> Vector3:
	return Vector3(0, -run.field.face_dist(0) * STEP, 0)


## Видна ли клетка с камеры (верх, +X, +Z).
func _cell_visible(i: int) -> bool:
	var n := cell_up(i)
	return n.y > 0.5 or n.dot(Vector3(1, 0, 1).rotated(Vector3.UP, cam_yaw)) > 0.5


## Плитка-призма: многоугольник pts (мир) — верх, толщина вниз по -n.
static func _poly_prism(pts: Array, n: Vector3, depth: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	var bot := []
	for p in pts:
		bot.append(p - n * depth)
	var k := pts.size()
	# порядок обхода так, чтобы верх смотрел по n
	var ccw: bool = (pts[1] - pts[0]).cross(pts[2] - pts[0]).dot(n) > 0
	for t in range(1, k - 1):
		if ccw:
			st.add_vertex(pts[0]); st.add_vertex(pts[t + 1]); st.add_vertex(pts[t])
			st.add_vertex(bot[0]); st.add_vertex(bot[t]); st.add_vertex(bot[t + 1])
		else:
			st.add_vertex(pts[0]); st.add_vertex(pts[t]); st.add_vertex(pts[t + 1])
			st.add_vertex(bot[0]); st.add_vertex(bot[t + 1]); st.add_vertex(bot[t])
	for a in k:
		var b := (a + 1) % k
		if ccw:
			st.add_vertex(pts[a]); st.add_vertex(pts[b]); st.add_vertex(bot[b])
			st.add_vertex(pts[a]); st.add_vertex(bot[b]); st.add_vertex(bot[a])
		else:
			st.add_vertex(pts[a]); st.add_vertex(bot[b]); st.add_vertex(pts[b])
			st.add_vertex(pts[a]); st.add_vertex(bot[a]); st.add_vertex(bot[b])
	st.generate_normals()
	return st.commit()


## Поворот, который кладёт «верх» модели на нормаль n.
static func _face_basis(n: Vector3) -> Basis:
	if n.is_equal_approx(Vector3.UP):
		return Basis.IDENTITY
	var t := Vector3.RIGHT if absf(n.x) < 0.5 else Vector3.BACK
	var x := (t - n * t.dot(n)).normalized()
	return Basis(x, n, x.cross(n))


func _mat(color: Color, alpha: float = 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(color, alpha)
	m.roughness = 0.9
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m


func _glow_mat(color: Color, alpha: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(color, alpha)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m


func _add_mesh(parent: Node3D, mesh: Mesh, pos: Vector3, color: Color, alpha: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.material_override = _mat(color, alpha)
	parent.add_child(mi)
	return mi


func _box_mesh(size: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	return m


## «Кубиковая» модель объекта по shape/tint/height из data/land/cards.json.
func _make_object(id: String, alpha: float = 1.0, facing: int = -1) -> Node3D:
	var model: Node3D = Models.build(id, alpha)
	if model != null:
		return model
	var b: Dictionary = data.objects[id]
	var root := Node3D.new()
	var color := Color(b.get("tint", "#cccccc"))
	var h := float(b.get("height", 0.5))
	match b.get("shape", "box"):
		"flat":
			_add_mesh(root, _box_mesh(Vector3(0.95, h, 0.95)), Vector3(0, h / 2, 0), color, alpha)
			for k in 3:
				_add_mesh(root, _box_mesh(Vector3(0.9, 0.03, 0.08)), Vector3(0, h + 0.015, -0.3 + k * 0.3), color.darkened(0.25), alpha)
		"house":
			_add_mesh(root, _box_mesh(Vector3(0.7, h, 0.55)), Vector3(0, h / 2, 0), color, alpha)
			var roof := PrismMesh.new()
			roof.size = Vector3(0.8, 0.35, 0.65)
			_add_mesh(root, roof, Vector3(0, h + 0.175, 0), Color("#7a6a5a"), alpha)
		"tower":
			var m := CylinderMesh.new()
			m.top_radius = 0.28
			m.bottom_radius = 0.34
			m.height = h
			_add_mesh(root, m, Vector3(0, h / 2, 0), color, alpha)
			var top := CylinderMesh.new()
			top.top_radius = 0.0
			top.bottom_radius = 0.36
			top.height = 0.35
			_add_mesh(root, top, Vector3(0, h + 0.175, 0), Color("#8a2f2f"), alpha)
		"mill":
			var m := CylinderMesh.new()
			m.top_radius = 0.22
			m.bottom_radius = 0.32
			m.height = h
			_add_mesh(root, m, Vector3(0, h / 2, 0), color, alpha)
			for k in 2:
				var bi := _add_mesh(root, _box_mesh(Vector3(0.9, 0.08, 0.04)), Vector3(0, h * 0.8, 0.26), Color("#9cc85a"), alpha)
				bi.rotation_degrees = Vector3(0, 0, 45 + 90 * k)
		"mine":
			_add_mesh(root, _box_mesh(Vector3(0.8, h, 0.8)), Vector3(0, h / 2, 0), color, alpha)
			_add_mesh(root, _box_mesh(Vector3(0.36, 0.3, 0.05)), Vector3(0, h * 0.5, 0.41), Color("#1c1611"), alpha)
			for k in 3:
				var g := SphereMesh.new()
				g.radius = 0.09
				g.height = 0.18
				_add_mesh(root, g, Vector3(-0.2 + k * 0.2, h + 0.06, -0.15), Color("#f2c94c"), alpha)
		"rock":
			var m := SphereMesh.new()
			m.radius = 0.42
			m.height = 0.6
			_add_mesh(root, m, Vector3(0.05, 0.2, 0), color, alpha)
			var m2 := SphereMesh.new()
			m2.radius = 0.25
			m2.height = 0.4
			_add_mesh(root, m2, Vector3(-0.25, 0.15, 0.25), color.lightened(0.1), alpha)
		"lake":
			var m := CylinderMesh.new()
			m.top_radius = 0.46
			m.bottom_radius = 0.46
			m.height = 0.06
			var mi := _add_mesh(root, m, Vector3(0, 0.03, 0), color, alpha)
			mi.material_override.metallic = 0.3
			mi.material_override.roughness = 0.2
		"lair":
			var m := CylinderMesh.new()
			m.top_radius = 0.12
			m.bottom_radius = 0.4
			m.height = h
			m.radial_segments = 5
			_add_mesh(root, m, Vector3(0, h / 2, 0), color, alpha)
			for k in 3:
				var sp := CylinderMesh.new()
				sp.top_radius = 0.0
				sp.bottom_radius = 0.08
				sp.height = 0.45
				var s := _add_mesh(root, sp, Vector3(cos(k * 2.1) * 0.25, h * 0.55, sin(k * 2.1) * 0.25), Color("#7a2a4a"), alpha)
				s.rotation_degrees = Vector3(sin(k * 2.1) * 25, 0, -cos(k * 2.1) * 25)
			var eye := SphereMesh.new()
			eye.radius = 0.1
			eye.height = 0.2
			var e := MeshInstance3D.new()
			e.mesh = eye
			e.position = Vector3(0, h + 0.05, 0)
			e.material_override = _glow_mat(Color("#ff3355"), alpha)
			root.add_child(e)
			if facing >= 0:
				root.add_child(_arrow_node(facing, Color("#ff3355"), alpha))
		_:
			_add_mesh(root, _box_mesh(Vector3(0.75, h, 0.75)), Vector3(0, h / 2, 0), color, alpha)
	return root


## Стрелка логова: из центра клетки к соседу в направлении dir.
func _arrow_node(dir: int, color: Color, alpha: float) -> Node3D:
	var root := Node3D.new()
	var v := Vector3.ZERO
	match dir:
		0: v = Vector3(0, 0, -1)
		1: v = Vector3(0, 0, 1)
		2: v = Vector3(-1, 0, 0)
		3: v = Vector3(1, 0, 0)
	var shaft := MeshInstance3D.new()
	var horizontal := absf(v.x) > 0.5
	shaft.mesh = _box_mesh(Vector3(0.35 if horizontal else 0.1, 0.05, 0.1 if horizontal else 0.35))
	shaft.position = v * 0.4 + Vector3(0, 0.08, 0)
	shaft.material_override = _glow_mat(color, alpha)
	root.add_child(shaft)
	var head := MeshInstance3D.new()
	var pm := PrismMesh.new()
	pm.size = Vector3(0.3, 0.22, 0.05)
	head.mesh = pm
	head.position = v * 0.66 + Vector3(0, 0.08, 0)
	# Призма смотрит вершиной вверх (+Y): кладём её и поворачиваем вершиной по направлению
	head.rotation = Vector3(-PI / 2, 0, 0)
	head.rotate_y(atan2(-v.x, -v.z))
	head.material_override = _glow_mat(color, alpha)
	root.add_child(head)
	return root


func _tile_color(i: int) -> Color:
	var t: String = run.field.terrain[i]
	if t != "":
		return Color(data.terrain[t].get("tint", "#5d7a3a"))
	return TILE_COLOR


func _rebuild_board() -> void:
	for c in board_root.get_children():
		c.queue_free()
	tiles = []
	tile_mats = []
	tile_base = []
	objs = []
	var f = run.field
	var sc: Dictionary = run.score()
	var cube := _is_cube()
	var multi := _is_multi()
	part_roots = []
	cross_nodes = []
	under_nodes = []
	board_root.transform = Transform3D.IDENTITY
	_update_camera()
	if multi:
		for k in f.part_count():
			var pr := Node3D.new()
			board_root.add_child(pr)
			part_roots.append(pr)
		if f.kind == "flip":
			# Тело перевёртыша между сторонами
			var body := MeshInstance3D.new()
			var w: int = f.parts[0]["w"]
			var h: int = f.parts[0]["h"]
			body.mesh = _box_mesh(Vector3(w * STEP - 0.05, f.THICK * STEP - 0.62, h * STEP - 0.05))
			body.position = Vector3(0, -f.THICK * STEP / 2, 0)
			body.material_override = _mat(Color("#4a3a2a"))
			board_root.add_child(body)
		elif f.kind == "spin":
			_spin_marker(f)
	if cube:
		# Барабан: торцы-шестиугольники
		if f.shape == "drum":
			for sx in [-1.0, 1.0]:
				var hex := []
				for face in f.face_count():
					for v in f.face_poly(face):
						if absf(v.x - sx * 1.5) < 0.01:
							var dup := false
							for h in hex:
								if (h as Vector3).distance_to(v) < 0.01:
									dup = true
							if not dup:
								hex.append(v)
				hex.sort_custom(func(a, b): return atan2(a.y, a.z) < atan2(b.y, b.z))
				var pts := []
				var n: Vector3 = f.orient * Vector3(sx, 0, 0)
				for v in hex:
					pts.append(f.orient * v * STEP + _cube_off() + n * 0.05)
				var cap := MeshInstance3D.new()
				cap.mesh = _poly_prism(pts, n, 0.3)
				cap.material_override = _mat(Color("#8a8178"))
				board_root.add_child(cap)
		# Тело фигуры: пластины граней чуть под клетками
		for face in f.face_count():
			var n: Vector3 = f.world_normal(face)
			var pts := []
			for v in f.face_poly(face):
				pts.append(f.orient * v * STEP + _cube_off() - n * 0.22)
			var core := MeshInstance3D.new()
			core.mesh = _poly_prism(pts, n, 0.12)
			core.material_override = _mat(Color("#4a3a2a"))
			board_root.add_child(core)
	for i in f.cells_n():
		tiles.append(null)
		tile_mats.append(null)
		tile_base.append(TILE_COLOR)
		objs.append(null)
		var p := cell_pos(i)
		if not f.exists[i]:
			# Пустота: тонкая рамка, чтобы видеть границы 4×4
			var mi := MeshInstance3D.new()
			mi.mesh = _box_mesh(Vector3(1.0, 0.02, 1.0))
			mi.position = p + Vector3(0, -0.35, 0)
			mi.material_override = _mat(Color("#2f3946"), 0.6)
			board_root.add_child(mi)
			continue
		var tile := MeshInstance3D.new()
		if cube:
			var pts := []
			var cw: Vector3 = p
			for v in f.poly(i):
				var w: Vector3 = f.orient * v * STEP + _cube_off()
				pts.append(cw + (w - cw) * 0.93)
			tile.mesh = _poly_prism(pts, cell_up(i), 0.3)
		else:
			tile.mesh = _box_mesh(Vector3(1.05, 0.3, 1.05))
			tile.position = p - cell_up(i) * 0.15
			if multi:
				tile.basis = _face_basis(cell_up(i))
		var base := _tile_color(i)
		if cube and f.broken[run.field.face_of(i)]:
			base = base.lerp(Color("#9bbf6a"), 0.35)
		if multi and f.kind == "pair" and f.part_of[i] != f.active:
			base = base.darkened(0.35)
		var mat := _mat(base)
		tile.material_override = mat
		_cell_parent(i).add_child(tile)
		tiles[i] = tile
		tile_mats[i] = mat
		tile_base[i] = base
		# Земляной «бок» под клеткой
		if not cube and not (multi and f.kind == "flip"):
			var dirt := MeshInstance3D.new()
			dirt.mesh = _box_mesh(Vector3(1.0, 0.4, 1.0))
			dirt.position = Vector3(0, -0.3, 0)
			dirt.material_override = _mat(Color("#4a3a2a"))
			tile.add_child(dirt)
		if f.terrain[i] != "":
			_terrain_label(i)
		var id: String = f.content[i]
		if id != "":
			var node := _make_object(id, 1.0, f.facing[i])
			Models.add_level(node, id, f.level(data, i))
			node.position = p
			if cube:
				node.basis = _face_basis(cell_up(i))
				if f.is_tri():
					node.basis = node.basis.scaled(Vector3.ONE * 0.72)
			elif multi:
				node.basis = _face_basis(cell_up(i))
				if cell_up(i).y < 0:
					# нижняя сторона перевёртыша: видна только во время переворота
					node.visible = false
					under_nodes.append(node)
			_cell_parent(i).add_child(node)
			objs[i] = node

	# Связи: пары, дом, конфликты
	for l in sc["links"]:
		if cube and not (_cell_visible(l["a"]) and _cell_visible(l["b"])):
			continue
		if multi and (cell_up(l["a"]).y < 0 or cell_up(l["b"]).y < 0) and not (cell_up(l["a"]).y > 0 or cell_up(l["b"]).y > 0):
			continue
		match l["type"]:
			"pair":
				_road(l["a"], l["b"], 0.34, ROAD_COLOR)
			"house", "tavern":
				_road(l["a"], l["b"], 0.22, PATH_COLOR)
			"conflict":
				board_root.add_child(_link_mesh(l["a"], l["b"], 0.12, 0.03, _glow_mat(CONFLICT_COLOR, 0.9)))
				var mid: Vector3 = (cell_pos(l["a"]) + cell_pos(l["b"])) / 2 + (cell_up(l["a"]) + cell_up(l["b"])).normalized() * 0.6
				var hb := _heart_badge(-1, 30)
				hb.position = mid
				board_root.add_child(hb)

	# Доход над зданиями
	for i in f.cells_n():
		if not f.exists[i] or not data.is_building(f.content[i]):
			continue
		if cube and not _cell_visible(i):
			continue
		if multi and cell_up(i).y < 0:
			continue
		var holder := Node3D.new()
		holder.position = cell_pos(i) + cell_up(i) * (float(data.objects[f.content[i]].get("height", 0.9)) + 0.3)
		_cell_parent(i).add_child(holder)
		var lv: int = f.level(data, i)
		if lv > 0:
			var lb := _text_badge("ур. %d" % lv, 26, Color("#f2c94c"))
			lb.position = Vector3(0, 0.32, 0)
			holder.add_child(lb)
		if i in sc["disabled"]:
			holder.add_child(_text_badge("выкл", 30, Color("#c0c0c0")))
			_dim(objs[i])
		else:
			var y: Dictionary = sc["cells"][i]["yield"]
			if y.is_empty():
				holder.add_child(_text_badge("0", 30, Color("#9aa4ae")))
			else:
				holder.add_child(_make_badge(y, 30, Color.WHITE, 5))


	if cube:
		_cube_extras(sc)


func _terrain_label(i: int) -> void:
	var t: Dictionary = data.terrain[run.field.terrain[i]]
	var node: Node3D
	if t["color"] == "any":
		node = _text_badge("−1", 26, Color("#ffb0a0"))
	else:
		node = _make_badge({t["color"]: int(t["bonus"])}, 26, Color.WHITE, 3)
	node.position = cell_pos(i) + Vector3(-0.28, 0.12, 0.28)
	_cell_parent(i).add_child(node)

func _dim(node: Node3D) -> void:
	if node == null:
		return
	for c in node.get_children():
		if c is MeshInstance3D and c.material_override is StandardMaterial3D:
			c.material_override.albedo_color = c.material_override.albedo_color.darkened(0.55)


## Дорога между связанными зданиями: идёт по клеткам, через ребро фигуры перегибается,
## между островами — мост.
func _road(a: int, b: int, width: float, color: Color) -> void:
	var f = run.field
	var segs := []
	if _is_multi():
		for sg in f.link_path(a, b):
			segs.append({"p": sg["p"] * STEP, "q": sg["q"] * STEP, "up": sg["up"], "bridge": sg["bridge"]})
	elif _is_cube() and f.face_of(a) != f.face_of(b):
		var shared := []
		for v in f.poly(a):
			for u in f.poly(b):
				if (v as Vector3).distance_to(u) < 0.01:
					shared.append(v)
		var mid := Vector3.ZERO
		for v in shared:
			mid += v
		mid = f.orient * (mid / maxi(1, shared.size())) * STEP + _cube_off()
		segs.append({"p": cell_pos(a), "q": mid, "up": cell_up(a), "bridge": false})
		segs.append({"p": mid, "q": cell_pos(b), "up": cell_up(b), "bridge": false})
	else:
		segs.append({"p": cell_pos(a), "q": cell_pos(b), "up": cell_up(a), "bridge": false})
	var parent: Node3D = board_root
	if _is_multi() and f.kind == "spin" and f.part_of[a] == f.part_of[b]:
		parent = part_roots[f.part_of[a]]
	for sg in segs:
		var up: Vector3 = sg["up"]
		var pa: Vector3 = sg["p"] + up * 0.035
		var pb: Vector3 = sg["q"] + up * 0.035
		var length := pa.distance_to(pb)
		if length < 0.01:
			continue
		var bas := Basis.looking_at(pb - pa, up)
		var node := Node3D.new()
		node.transform = Transform3D(bas, (pa + pb) / 2)
		parent.add_child(node)
		if parent == board_root and _is_multi():
			cross_nodes.append(node)
		if sg["bridge"]:
			# Мост: доски и перила
			var deck := MeshInstance3D.new()
			deck.mesh = _box_mesh(Vector3(width + 0.14, 0.06, length + 0.2))
			deck.material_override = _mat(BRIDGE_COLOR)
			node.add_child(deck)
			for sx in [-1.0, 1.0]:
				var rail := MeshInstance3D.new()
				rail.mesh = _box_mesh(Vector3(0.04, 0.05, length + 0.2))
				rail.position = Vector3(sx * (width / 2 + 0.09), 0.14, 0)
				rail.material_override = _mat(BRIDGE_COLOR.darkened(0.3))
				node.add_child(rail)
				for pz in [-0.5, 0.5]:
					var post := MeshInstance3D.new()
					post.mesh = _box_mesh(Vector3(0.05, 0.16, 0.05))
					post.position = Vector3(sx * (width / 2 + 0.09), 0.07, pz * (length + 0.1))
					post.material_override = rail.material_override
					node.add_child(post)
		else:
			# Дорога: светлая полоса с тёмной обочиной
			var edge := MeshInstance3D.new()
			edge.mesh = _box_mesh(Vector3(width + 0.07, 0.025, length + 0.07))
			edge.material_override = _mat(color.darkened(0.45))
			node.add_child(edge)
			var top := MeshInstance3D.new()
			top.mesh = _box_mesh(Vector3(width, 0.03, length + 0.02))
			top.position = Vector3(0, 0.012, 0)
			top.material_override = _mat(color)
			node.add_child(top)


## Вращающиеся острова: голубая круговая стрелка вокруг острова, который повернётся после хода.
func _spin_marker(f) -> void:
	var c: Vector3 = f.part_center(f.spin_next) * STEP
	var r := 1.95 * STEP
	var mat := _glow_mat(ECHO_COLOR, 0.85)
	var t0 := -PI * 0.75
	var steps := 22
	var span := PI * 1.5
	for k in steps:
		var a0 := t0 + span * k / steps
		var a1 := t0 + span * (k + 1) / steps
		var p0 := c + Vector3(cos(a0), 0, sin(a0)) * r + Vector3(0, 0.08, 0)
		var p1 := c + Vector3(cos(a1), 0, sin(a1)) * r + Vector3(0, 0.08, 0)
		var mi := MeshInstance3D.new()
		mi.mesh = _box_mesh(Vector3(0.1, 0.05, p0.distance_to(p1) + 0.02))
		mi.transform = Transform3D(Basis.looking_at(p1 - p0, Vector3.UP), (p0 + p1) / 2)
		mi.material_override = mat
		board_root.add_child(mi)
	var ae := t0 + span
	var tip := c + Vector3(cos(ae), 0, sin(ae)) * r + Vector3(0, 0.08, 0)
	var dir := Vector3(-sin(ae), 0, cos(ae))
	var head := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.2
	cone.height = 0.4
	head.mesh = cone
	head.material_override = mat
	# конус смотрит вдоль dir
	head.transform = Transform3D(Basis.looking_at(dir, Vector3.UP) * Basis(Vector3.RIGHT, -PI / 2), tip + dir * 0.15)
	board_root.add_child(head)
	cross_nodes.append(head)


## Анимация конца хода у острова из частей. Доска ещё показывает старое состояние.
func _animate_shift(sh: Dictionary) -> void:
	match sh.get("kind", ""):
		"spin":
			for n in cross_nodes:
				if is_instance_valid(n):
					n.visible = false
			var pr: Node3D = part_roots[int(sh["part"])]
			var c: Vector3 = sh["center"] * STEP
			var tw := create_tween()
			tw.tween_method(func(t: float):
				var lift := 0.9 * clampf(t / 0.25, 0.0, 1.0) * clampf((1.0 - t) / 0.25, 0.0, 1.0)
				var ang := -PI / 2 * smoothstep(0.25, 0.75, t)
				var b := Basis(Vector3.UP, ang)
				pr.transform = Transform3D(b, c + Vector3(0, lift, 0) - b * c), 0.0, 1.0, 1.1)
			await tw.finished
		"flip":
			for n in under_nodes:
				if is_instance_valid(n):
					n.visible = true
			var pivot := Vector3(0, -run.field.THICK * STEP / 2, 0)
			var tw2 := create_tween()
			tw2.tween_method(func(t: float):
				var lift := 1.6 * clampf(t / 0.2, 0.0, 1.0) * clampf((1.0 - t) / 0.2, 0.0, 1.0)
				var ang := PI * smoothstep(0.2, 0.8, t)
				var b := Basis(Vector3.RIGHT, ang)
				board_root.transform = Transform3D(b, pivot + Vector3(0, lift, 0) - b * pivot), 0.0, 1.0, 1.2)
			await tw2.finished
		"pair":
			_show_toast("[center][b]Теперь стройте на %s острове[/b][/center]" % ("левом" if int(sh["to"]) == 0 else "правом"))


func _link_mesh(a: int, b: int, width: float, y: float, mat: Material) -> MeshInstance3D:
	var pa := cell_pos(a) + cell_up(a) * y
	var pb := cell_pos(b) + cell_up(b) * y
	var mi := MeshInstance3D.new()
	var length := pa.distance_to(pb)
	mi.mesh = _box_mesh(Vector3(width, 0.04, length))
	var up := (cell_up(a) + cell_up(b)).normalized()
	mi.transform = Transform3D(Basis.looking_at(pb - pa, up), (pa + pb) / 2)
	mi.material_override = mat
	return mi


## Рамка вокруг клетки.
func _frame(i: int, color: Color, parent: Node3D, pulse: bool, y: float = 0.03) -> void:
	var p := cell_pos(i)
	var mat := _glow_mat(color, 0.9)
	if pulse:
		pulse_mats.append(mat)
	for k in 4:
		var mi := MeshInstance3D.new()
		var horizontal := k < 2
		mi.mesh = _box_mesh(Vector3(1.08 if horizontal else 0.09, 0.05, 0.09 if horizontal else 1.08))
		var off := 0.5
		match k:
			0: mi.position = p + Vector3(0, y, -off)
			1: mi.position = p + Vector3(0, y, off)
			2: mi.position = p + Vector3(-off, y, 0)
			3: mi.position = p + Vector3(off, y, 0)
		mi.material_override = mat
		parent.add_child(mi)


func _rebuild_intent() -> void:
	for c in intent_root.get_children():
		c.queue_free()
	pulse_mats = []
	var it: Dictionary = run.intent
	var t: int = it.get("target", -1)
	match it.get("type", ""):
		"swap":
			if it["cells"].size() == 2:
				var a: int = it["cells"][0]
				var b: int = it["cells"][1]
				_frame(a, LAND_COLOR, intent_root, true)
				_frame(b, LAND_COLOR, intent_root, true)
				_arc(a, b, LAND_COLOR)
				_intent_label(a, "обмен", LAND_COLOR)
				_intent_label(b, "обмен", LAND_COLOR)
		"destroy":
			for i in it["cells"]:
				_frame(i, DANGER_COLOR, intent_root, true)
				_cross(i, DANGER_COLOR)
				_intent_label(i, "рухнет", DANGER_COLOR)
		"growth":
			if t >= 0:
				var mi := MeshInstance3D.new()
				mi.mesh = _box_mesh(Vector3(1.0, 0.3, 1.0))
				mi.position = cell_pos(t) + Vector3(0, -0.15, 0)
				var m := _glow_mat(GROW_COLOR, 0.5)
				pulse_mats.append(m)
				mi.material_override = m
				intent_root.add_child(mi)
				_intent_label(t, "+ земля", GROW_COLOR)
		"collapse":
			if t >= 0:
				_frame(t, DANGER_COLOR, intent_root, true)
				_cross(t, DANGER_COLOR)
				_intent_label(t, "обвал", DANGER_COLOR)
		"lair":
			if t >= 0:
				var g := _make_object("lair", 0.4, int(it.get("dir", 0)))
				g.position = cell_pos(t)
				intent_root.add_child(g)
				_frame(t, DANGER_COLOR, intent_root, true)
				_intent_label(t, "логово", DANGER_COLOR)
				var j := LandField.step(t, int(it.get("dir", 0)))
				if j >= 0 and run.field.exists[j]:
					_frame(j, Color("#ff9f43"), intent_root, false, 0.05)


## Подписи намерений на поле убраны (видно по подсветке), имя оставлено для простоты.
func _intent_label(_i: int, _text: String, _color: Color) -> void:
	pass

func _cross(i: int, color: Color) -> void:
	var m := _glow_mat(color, 0.7)
	pulse_mats.append(m)
	for k in 2:
		var mi := MeshInstance3D.new()
		mi.mesh = _box_mesh(Vector3(0.9, 0.03, 0.08))
		mi.position = cell_pos(i) + Vector3(0, 0.02, 0)
		mi.rotation_degrees = Vector3(0, 45 + 90 * k, 0)
		mi.material_override = m
		intent_root.add_child(mi)


## Дуга из шариков между двумя клетками (обмен).
func _arc(a: int, b: int, color: Color) -> void:
	var pa := cell_pos(a)
	var pb := cell_pos(b)
	var n := 14
	var m := _glow_mat(color, 0.9)
	pulse_mats.append(m)
	for k in range(1, n):
		var t := float(k) / n
		var p := pa.lerp(pb, t) + Vector3(0, 0.4 + sin(t * PI) * 1.3, 0)
		var s := SphereMesh.new()
		s.radius = 0.05
		s.height = 0.1
		var mi := MeshInstance3D.new()
		mi.mesh = s
		mi.position = p
		mi.material_override = m
		intent_root.add_child(mi)


## Подсветка клеток, призрак карты и предпросмотр дохода под курсором.
func _update_hover() -> void:
	for c in hover_root.get_children():
		c.queue_free()
	var f = run.field
	var card := ""
	if selected >= 0 and selected < run.hand.size() and run.plays_left > 0:
		card = run.hand[selected]
	for i in f.cells_n():
		if tile_mats.size() <= i or tile_mats[i] == null:
			continue
		var c: Color = tile_base[i]
		if card != "" and f.is_free(i):
			c = c.lerp(TILE_FREE_COLOR, 0.5)
			if LandEvents.endangers(run.intent, i):
				c = c.lerp(TILE_DANGER_COLOR, 0.5)
			if i == hover:
				c = TILE_HOVER_COLOR
		elif _is_cube() and run.cube_roll and roll_hover >= 0 and run.field.face_of(i) == roll_hover:
			c = c.lerp(SEAL_COLOR, 0.45)
		tile_mats[i].albedo_color = c

	var want := ""
	if card != "" and f.is_free(hover):
		want = "%s@%d" % [card, hover]
	if want != ghost_key:
		if ghost != null:
			ghost.queue_free()
			ghost = null
		ghost_key = want
		if want != "":
			ghost = _make_object(card, 0.55)
			ghost.position = cell_pos(hover)
			add_child(ghost)
	if want == "":
		return
	# Что изменится, если поставить сюда
	var before: Dictionary = run.score()
	var g = f.clone()
	var razed: Array = g.place_building(data, hover, card)
	var after: Dictionary = g.score(data)
	var d := {}
	for r in data.resources:
		var v := int(after["total"].get(r, 0)) - int(before["total"].get(r, 0))
		if v != 0:
			d[r] = v
	var badge := _make_badge(d, 40, Color(1, 0.95, 0.6), 8)
	badge.position = cell_pos(hover) + Vector3(0, 1.8, 0)
	hover_root.add_child(badge)
	# Эхо: какие здания сработают ещё раз (голубая рамка и их цифры)
	for st in g.echo(data, hover, data.echo_level(card)):
		var eb := _make_badge(st["yield"], 30, ECHO_COLOR, 8)
		eb.position = cell_pos(st["cell"]) + Vector3(0, 1.45, 0)
		hover_root.add_child(eb)
		_frame(st["cell"], ECHO_COLOR, hover_root, true, 0.06)
	var dd := int(after["discontent"]) - int(before["discontent"])
	if dd > 0:
		var hb := _heart_badge(-dd, 36)
		hb.position = cell_pos(hover) + Vector3(0, 2.25, 0)
		hover_root.add_child(hb)
	for l in after["links"]:
		if l["a"] != hover and l["b"] != hover:
			continue
		var col := PAIR_COLOR if l["type"] == "pair" else (CONFLICT_COLOR if l["type"] == "conflict" else HOUSE_COLOR)
		hover_root.add_child(_link_mesh(l["a"], l["b"], 0.16, 0.2, _glow_mat(col, 0.75)))
	for j in razed:
		_frame(j, GROW_COLOR, hover_root, false, 0.08)


# ---------------------------------------------------------------- Значки над полем

func _text_badge(text: String, size: int, color: Color) -> Label3D:
	var lbl := Label3D.new()
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.no_depth_test = true
	lbl.render_priority = 6
	lbl.outline_render_priority = 5
	lbl.font_size = size
	lbl.outline_size = int(size * 0.4)
	lbl.outline_modulate = Color(0, 0, 0, 0.85)
	lbl.pixel_size = 0.006 * badge_k
	lbl.text = text
	lbl.modulate = color
	return lbl


## «−1 ♥»: потеря жизни от недовольства.
func _heart_badge(v: int, size: int) -> Node3D:
	var root := Node3D.new()
	var lbl := _text_badge("%d" % v, size, Color("#ff8080"))
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	lbl.offset = Vector2(-size * 0.05, 0)
	root.add_child(lbl)
	var spr := Sprite3D.new()
	spr.texture = _icon_tex("res://assets/icons/heart.svg")
	spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	spr.no_depth_test = true
	spr.render_priority = 6
	spr.pixel_size = 0.006 * badge_k * size * 1.0 / 64.0
	var k_px := 64.0 / (size * 1.0)
	spr.offset = Vector2(size * 0.6 * k_px, 0)
	root.add_child(spr)
	return root


func _make_badge(amounts: Dictionary, font_size: int, tint: Color, priority: int) -> Node3D:
	var root := Node3D.new()
	var lines := []
	for res in data.resources:
		var v := int(amounts.get(res, 0))
		if v != 0:
			lines.append([res, v])
	var line_h := font_size * 1.15
	var top := (lines.size() - 1) * line_h / 2.0
	for k in lines.size():
		var res: String = lines[k][0]
		var v: int = lines[k][1]
		var y := top - k * line_h
		var lbl := Label3D.new()
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.no_depth_test = true
		lbl.render_priority = priority
		lbl.outline_render_priority = priority - 1
		lbl.font_size = font_size
		lbl.outline_size = int(font_size * 0.4)
		lbl.outline_modulate = Color(0, 0, 0, 0.85 * tint.a)
		lbl.pixel_size = 0.006 * badge_k
		lbl.text = "%s%d" % ["+" if v > 0 else "", v]
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		lbl.offset = Vector2(-font_size * 0.05, y)
		lbl.modulate = Color(Color(_res_color(res)).lerp(Color.WHITE, 0.35) * tint, tint.a)
		root.add_child(lbl)
		var spr := Sprite3D.new()
		spr.texture = _icon(res)
		spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		spr.no_depth_test = true
		spr.render_priority = priority
		spr.pixel_size = 0.006 * badge_k * font_size * 1.1 / 64.0
		var k_px := 64.0 / (font_size * 1.1)
		spr.offset = Vector2(font_size * 0.6 * k_px, y * k_px)
		spr.modulate = Color(1, 1, 1, tint.a)
		root.add_child(spr)
	return root


func _set_badge_alpha(root: Node3D, a: float) -> void:
	for c in root.get_children():
		if c is Label3D:
			c.modulate.a = a
			c.outline_modulate.a = 0.85 * a
		elif c is Sprite3D:
			c.modulate.a = a


var _icon_cache: Dictionary = {}

func _icon_tex(path: String) -> Texture2D:
	if not _icon_cache.has(path):
		_icon_cache[path] = load(path) if path != "" else null
	return _icon_cache[path]


func _icon(res: String) -> Texture2D:
	return _icon_tex(data.resources.get(res, {}).get("icon", ""))


# ---------------------------------------------------------------- Эффекты

func _float_badge(cell: int, amounts: Dictionary) -> void:
	if amounts.is_empty():
		return
	var badge := _make_badge(amounts, 56, Color.WHITE, 10)
	var start := cell_pos(cell) + Vector3(0, 1.0, 0)
	badge.position = start
	add_child(badge)
	var t := create_tween()
	t.tween_property(badge, "scale", Vector3.ONE * 1.3, 0.12).from(Vector3.ONE * 0.5)
	t.tween_property(badge, "scale", Vector3.ONE, 0.15)
	t.parallel().tween_property(badge, "position", start + Vector3(0, 1.2, 0), 1.2).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	t.parallel().tween_method(func(a): _set_badge_alpha(badge, a), 1.0, 0.0, 0.5).set_delay(0.8)
	t.tween_callback(badge.queue_free)


func _flash_tile(cell: int, color: Color) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = _box_mesh(Vector3(1.1, 0.02, 1.1))
	mi.position = cell_pos(cell) + Vector3(0, 0.03, 0)
	var mat := _glow_mat(color, 0.85)
	mi.material_override = mat
	add_child(mi)
	var t := create_tween()
	t.tween_property(mat, "albedo_color:a", 0.0, 0.8)
	t.tween_callback(mi.queue_free)


## Анимация хода земли на старых узлах, потом поле перестраивается.
func _animate_land(rep: Dictionary) -> float:
	for c in intent_root.get_children():
		c.queue_free()
	pulse_mats = []
	var dur := 0.0
	for pair in rep.get("moved", []):
		var a: int = pair[0]
		var b: int = pair[1]
		for k in 2:
			var from_c: int = a if k == 0 else b
			var to_c: int = b if k == 0 else a
			var nodes := [objs[from_c], tiles[from_c]]
			for n in nodes:
				if n == null:
					continue
				var base_y: float = n.position.y
				var to: Vector3 = cell_pos(to_c) + Vector3(0, base_y, 0)
				var t := create_tween()
				t.tween_property(n, "position:y", base_y + 1.2, 0.25).set_ease(Tween.EASE_OUT)
				t.tween_property(n, "position", to + Vector3(0, 1.2, 0), 0.4).set_trans(Tween.TRANS_SINE)
				t.tween_property(n, "position:y", base_y, 0.2).set_ease(Tween.EASE_IN)
		dur = maxf(dur, 0.9)
	for d in rep.get("destroyed", []):
		var n: Node3D = objs[d["cell"]]
		_flash_tile(d["cell"], DANGER_COLOR)
		if n != null:
			var t := create_tween()
			t.tween_property(n, "rotation_degrees:z", 25.0, 0.15)
			t.tween_property(n, "scale", Vector3(1.2, 0.05, 1.2), 0.35).set_ease(Tween.EASE_IN)
		dur = maxf(dur, 0.6)
	if rep.get("grown", -1) >= 0:
		var g: int = rep["grown"]
		var mi := MeshInstance3D.new()
		mi.mesh = _box_mesh(Vector3(1.05, 0.3, 1.05))
		mi.material_override = _mat(TILE_COLOR)
		mi.position = cell_pos(g) + Vector3(0, -2.0, 0)
		board_root.add_child(mi)
		var t := create_tween()
		t.tween_property(mi, "position:y", -0.15, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		dur = maxf(dur, 0.6)
	if not rep.get("fell", {}).is_empty():
		var c: int = rep["fell"]["cell"]
		for n in [tiles[c], objs[c]]:
			if n == null:
				continue
			var t := create_tween()
			t.tween_property(n, "position:y", n.position.y - 4.0, 0.7).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		dur = maxf(dur, 0.75)
	if rep.get("spawned", -1) >= 0:
		var s: int = rep["spawned"]
		var node := _make_object("lair", 1.0, run.field.facing[s])
		node.position = cell_pos(s)
		node.scale = Vector3(0.1, 0.1, 0.1)
		board_root.add_child(node)
		var t := create_tween()
		t.tween_property(node, "scale", Vector3.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_flash_tile(s, DANGER_COLOR)
		dur = maxf(dur, 0.55)
	return dur


func _show_toast(text: String) -> void:
	toast.text = text
	toast.visible = true
	toast.modulate.a = 1.0
	var t := create_tween()
	t.tween_interval(2.2)
	t.tween_property(toast, "modulate:a", 0.0, 0.6)
	t.tween_callback(func(): toast.visible = false)


func _announce_field() -> void:
	var ev: Dictionary = run.event_info()
	_show_toast("[center][b]Остров %d: %s[/b]\n[font_size=16]%s[/font_size][/center]" % [run.field_index, ev.get("name", ""), ev.get("desc", "")])


# ---------------------------------------------------------------- Интерфейс

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)

	var left := _panel(root, 300)
	left.position = Vector2(12, 12)
	info_box = VBoxContainer.new()
	info_box.add_theme_constant_override("separation", 8)
	left.add_child(info_box)

	var right := _panel(root, 260)
	right.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	right.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 12)
	side_box = VBoxContainer.new()
	side_box.add_theme_constant_override("separation", 8)
	right.add_child(side_box)

	var tpanel := PanelContainer.new()
	var tsb := StyleBoxFlat.new()
	tsb.bg_color = Color(0.08, 0.1, 0.13, 0.92)
	tsb.set_corner_radius_all(10)
	tsb.set_content_margin_all(10)
	tsb.border_color = Color("#f2c94c")
	tsb.border_width_bottom = 3
	tpanel.add_theme_stylebox_override("panel", tsb)
	tpanel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 10)
	tpanel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	root.add_child(tpanel)
	treasury_box = HBoxContainer.new()
	treasury_box.add_theme_constant_override("separation", 18)
	tpanel.add_child(treasury_box)

	var bottom := VBoxContainer.new()
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bottom.offset_bottom = -12
	bottom.offset_left = 12
	bottom.offset_right = -12
	bottom.add_theme_constant_override("separation", 6)
	root.add_child(bottom)

	hint_text = RichTextLabel.new()
	hint_text.bbcode_enabled = true
	hint_text.fit_content = true
	hint_text.scroll_active = false
	hint_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint_text.add_theme_font_size_override("normal_font_size", 20)
	hint_text.add_theme_font_size_override("bold_font_size", 20)
	hint_text.add_theme_constant_override("outline_size", 6)
	hint_text.add_theme_color_override("font_outline_color", Color.BLACK)
	bottom.add_child(hint_text)

	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	bottom.add_child(row)

	hand_box = HBoxContainer.new()
	hand_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hand_box.add_theme_constant_override("separation", 10)
	row.add_child(hand_box)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(24, 0)
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(spacer)

	var buttons := VBoxContainer.new()
	buttons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	buttons.alignment = BoxContainer.ALIGNMENT_END
	row.add_child(buttons)
	undo_btn = Button.new()
	undo_btn.text = "Отменить (Z)"
	undo_btn.custom_minimum_size = Vector2(170, 44)
	undo_btn.add_theme_font_size_override("font_size", 16)
	undo_btn.focus_mode = Control.FOCUS_NONE
	undo_btn.pressed.connect(_on_undo)
	buttons.add_child(undo_btn)
	end_btn = Button.new()
	end_btn.custom_minimum_size = Vector2(170, 76)
	end_btn.add_theme_font_size_override("font_size", 19)
	end_btn.focus_mode = Control.FOCUS_NONE
	end_btn.pressed.connect(_on_end_turn)
	buttons.add_child(end_btn)
	claim_btn = Button.new()
	claim_btn.text = "Забрать остров\n(Enter)"
	claim_btn.custom_minimum_size = Vector2(170, 70)
	claim_btn.add_theme_font_size_override("font_size", 18)
	claim_btn.focus_mode = Control.FOCUS_NONE
	var cb := StyleBoxFlat.new()
	cb.bg_color = Color("#2f6b45")
	cb.set_corner_radius_all(6)
	claim_btn.add_theme_stylebox_override("normal", cb)
	var cbh := cb.duplicate()
	cbh.bg_color = Color("#3d8a5a")
	claim_btn.add_theme_stylebox_override("hover", cbh)
	claim_btn.tooltip_text = "Задание выполнено: закончить остров сейчас, земля больше не ходит"
	claim_btn.pressed.connect(_on_claim)
	buttons.add_child(claim_btn)
	buttons.move_child(claim_btn, 0)

	overlay = ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.6)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(overlay)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	var box := PanelContainer.new()
	overlay_box = box
	box.custom_minimum_size = Vector2(600, 0)
	var box_sb := StyleBoxFlat.new()
	box_sb.bg_color = Color("#1d2430")
	box_sb.border_color = Color("#c58cff")
	box_sb.set_border_width_all(2)
	box_sb.set_corner_radius_all(10)
	box.add_theme_stylebox_override("panel", box_sb)
	center.add_child(box)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	box.add_child(margin)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	margin.add_child(v)
	overlay_text = RichTextLabel.new()
	overlay_text.bbcode_enabled = true
	overlay_text.fit_content = true
	overlay_text.scroll_active = false
	overlay_text.add_theme_font_size_override("normal_font_size", 16)
	overlay_text.add_theme_font_size_override("bold_font_size", 16)
	v.add_child(overlay_text)
	overlay_body = VBoxContainer.new()
	overlay_body.add_theme_constant_override("separation", 12)
	v.add_child(overlay_body)
	overlay_buttons = HBoxContainer.new()
	overlay_buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	overlay_buttons.add_theme_constant_override("separation", 10)
	v.add_child(overlay_buttons)
	overlay.visible = false

	toast = RichTextLabel.new()
	toast.bbcode_enabled = true
	toast.fit_content = true
	toast.scroll_active = false
	toast.custom_minimum_size = Vector2(560, 0)
	toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 16)
	toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast.add_theme_font_size_override("normal_font_size", 22)
	toast.add_theme_font_size_override("bold_font_size", 22)
	toast.add_theme_color_override("default_color", Color("#e7d4ff"))
	toast.add_theme_constant_override("outline_size", 8)
	toast.add_theme_color_override("font_outline_color", Color.BLACK)
	toast.visible = false
	root.add_child(toast)


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _rich_line(bb: String, size: int = 14) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.add_theme_font_size_override("normal_font_size", size)
	r.add_theme_font_size_override("bold_font_size", size)
	r.text = bb
	return r


func _icon_rect(tex: Texture2D, size: int) -> TextureRect:
	var tr := TextureRect.new()
	tr.texture = tex
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.custom_minimum_size = Vector2(size, size)
	tr.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tr


func _section(parent: VBoxContainer, title: String, color: Color, title_size: int = 15) -> VBoxContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#1a212b")
	sb.border_color = color
	sb.border_width_left = 3
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(8)
	p.add_theme_stylebox_override("panel", sb)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	var l := _label(title, title_size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(l)
	p.add_child(v)
	parent.add_child(p)
	return v


func _progress_row(res: String, have: int, need: int, extra: String = "") -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.add_child(_icon_rect(_icon(res), 30))
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.max_value = maxi(need, 1)
	bar.value = mini(have, need)
	bar.custom_minimum_size = Vector2(0, 26)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color("#0e1319")
	bg.set_corner_radius_all(4)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(_res_color(res)).darkened(0.15)
	fill.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fill)
	var txt := _label("%d / %d%s%s" % [have, need, extra, "  ✔" if have >= need else ""], 16, Color.WHITE)
	txt.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	txt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	txt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	txt.add_theme_constant_override("outline_size", 5)
	txt.add_theme_color_override("font_outline_color", Color.BLACK)
	bar.add_child(txt)
	row.add_child(bar)
	return row


func _panel(parent: Control, width: float) -> PanelContainer:
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(width, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.1, 0.13, 0.92)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(12)
	p.add_theme_stylebox_override("panel", sb)
	parent.add_child(p)
	return p


func _clear(box: Container) -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()


func _res_color(res: String) -> String:
	if res == "grey":
		return GREY_COLOR.to_html(false)
	if res == "city":
		return "#b07ad9"
	return data.resources.get(res, {}).get("color", "#ffffff")


func _img(res: String, size: int = 18) -> String:
	return "[img=%dx%d]%s[/img]" % [size, size, data.resources.get(res, {}).get("icon", "")]


func _heart_img(size: int = 16) -> String:
	return "[img=%dx%d]res://assets/icons/heart.svg[/img]" % [size, size]


func _fmt(amounts: Dictionary, plus: bool = false) -> String:
	var parts := []
	for res in data.resources:
		var v := int(amounts.get(res, 0))
		if v == 0:
			continue
		parts.append("[color=%s]%s%d[/color]%s" % [_res_color(res), "+" if plus and v > 0 else "", v, _img(res)])
	return " ".join(parts) if not parts.is_empty() else "ничего"


static func _plural(n: int, one: String, few: String, many: String) -> String:
	var m10 := n % 10
	var m100 := n % 100
	if m10 == 1 and m100 != 11:
		return one
	if m10 >= 2 and m10 <= 4 and (m100 < 10 or m100 >= 20):
		return few
	return many


func _full_refresh() -> void:
	if selected >= run.hand.size():
		selected = -1
	ghost_key = "?"
	_rebuild_board()
	_rebuild_intent()
	_refresh_ui()
	_update_hover()


func _refresh_ui() -> void:
	_refresh_info()
	_refresh_treasury()
	_refresh_side()
	_refresh_hand()
	_refresh_hint()
	undo_btn.disabled = not run.can_undo() or busy
	var last: bool = run.turn >= run.turns_here()
	end_btn.text = "%s\n(Пробел)" % ("Ход земли и итог" if last else "Ход земли")
	end_btn.disabled = busy or run.game_over or run.phase != "island"
	if _is_cube() and run.phase == "island":
		end_btn.text = "Проверить\n(Пробел)"
		end_btn.disabled = end_btn.disabled or run.cube_roll
	claim_btn.visible = not run.game_over and run.phase == "island" and run.task_done()
	claim_btn.disabled = busy


func _refresh_info() -> void:
	_clear(info_box)
	var sc: Dictionary = run.score()
	var sp: Dictionary = run.sprint_info()

	var head := HBoxContainer.new()
	head.add_child(_label("Остров %d/%d" % [maxi(run.field_index, 1), run.total_islands()], 24, Color.WHITE))
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(gap)
	head.add_child(_label("Ход %d/%d" % [run.turn, run.turns_here()], 24, LAND_COLOR))
	info_box.add_child(head)

	# Жизни: полупрозрачные сердца — столько снимет текущее недовольство
	var hearts := HBoxContainer.new()
	hearts.add_theme_constant_override("separation", 0)
	var heart: Texture2D = _icon_tex("res://assets/icons/heart.svg")
	var danger := int(sc["discontent"])
	for k in int(data.run["lives"]):
		var tr := _icon_rect(heart, 22)
		if k >= run.lives:
			tr.modulate = Color(0.3, 0.3, 0.3, 0.5)
		elif k >= run.lives - danger:
			tr.modulate = Color(1, 1, 1, 0.35)
		hearts.add_child(tr)
	info_box.add_child(hearts)
	if danger > 0:
		info_box.add_child(_rich_line("[color=#ff8080]Разные цвета рядом: −%d%s в конце острова[/color]" % [danger, _heart_img(16)], 15))

	# Земля: название и что она сделает сейчас (полное описание — в подсказке)
	var ev: Dictionary = run.event_info()
	if run.is_cube():
		ev = {"name": "", "desc": ""}
	var danger_isl: bool = run.island.get("danger", false)
	if not run.is_cube():
		var lb := _section(info_box, ev.get("name", "") + ("  · опасно" if danger_isl else ""), DANGER_COLOR if danger_isl else LAND_COLOR, 19)
		lb.get_parent().tooltip_text = ev.get("desc", "")
		lb.get_parent().mouse_filter = Control.MOUSE_FILTER_PASS
		lb.add_child(_rich_line(LandEvents.describe(run.intent), 15))

	if _is_multi():
		_multi_info()

	# Задание острова (не на каждом): выполнил — награда
	if not run.task.is_empty():
		var ok: bool = run.task_done(sc)
		var tb := _section(info_box, "Задание: %s" % _plain_fmt(run.island.get("task_reward", {})), Color("#6fcf97") if ok else Color("#f2c94c"), 18)
		tb.get_parent().tooltip_text = "Произведите на этом острове столько ресурса — получите награду в казну. Не выполнили — ничего не теряете."
		tb.get_parent().mouse_filter = Control.MOUSE_FILTER_PASS
		for r in run.task:
			tb.add_child(_progress_row(r, int(run.income(sc).get(r, 0)), int(run.task[r])))
		if ok:
			tb.add_child(_rich_line("[color=#6fcf97]Готово! Можно забрать остров (Enter)[/color]", 14))

	# Кузница: рецепт из соседей Наковальни
	if run.island.has("forge"):
		var rp: Array = run.field.recipe_progress(data, run.island["forge"])
		var fb := _section(info_box, "Кузница: сталь для босса", Color("#ff9f43"), 17)
		fb.get_parent().tooltip_text = "Соберите рецепт из зданий вокруг Наковальни к концу острова — получите сталь. Босс с ней требует ×%s." % str(data.run.get("steel_boss_mult", 0.85))
		fb.get_parent().mouse_filter = Control.MOUSE_FILTER_PASS
		fb.add_child(_rich_line("%s рядом с Наковальней: [b]%d/%d[/b]%s" % [_recipe_text(run.island["forge"]), rp[0], rp[1], "  [color=#6fcf97]✔[/color]" if rp[0] >= rp[1] else ""], 15))

	# Босс на этом острове или впереди
	if run.is_cube():
		_cube_info(sc)
	elif run.is_boss():
		var b: Dictionary = run.island["boss"]
		var bb := _section(info_box, "Босс: %s" % b["name"], Color("#eb5757"), 19)
		bb.get_parent().tooltip_text = "Нужно произвести на этом острове столько всего (любые ресурсы и джокеры). Каждая недостающая единица — минус жизнь."
		bb.get_parent().mouse_filter = Control.MOUSE_FILTER_PASS
		bb.add_child(_progress_row("wild", run.sum_res(run.income(sc)), run.boss_need(), " всего"))
		if run.steel > 0:
			bb.add_child(_rich_line("[color=#ff9f43]Сталь: требование ×%s (было %d)[/color]" % [str(data.run.get("steel_boss_mult", 0.85)), int(b["need"])], 13))
	else:
		var nb: Dictionary = run.next_boss()
		if not nb.is_empty():
			var left := int(nb["islands_left"])
			if nb.has("cube"):
				info_box.add_child(_rich_line("[color=#eb5757]%s[/color] через %d %s: печати на гранях фигуры (%s)" % [nb["name"], left, _plural(left, "остров", "острова", "островов"), SHAPE_WORD.get(nb["cube"].get("shape", "cube"), "куб")], 14))
			else:
				info_box.add_child(_rich_line("[color=#eb5757]%s[/color] через %d %s: нужно [b]%d[/b] за остров" % [nb["name"], left, _plural(left, "остров", "острова", "островов"), run.boss_need(nb)], 14))

	# Контракт с рынка
	if not run.contract.is_empty() and int(run.contract["sprint"]) == run.sprint:
		var c: Dictionary = run.contract
		var have := int(c["progress"]) + int(run.income(sc).get(c["res"], 0))
		var cb := _section(info_box, "Контракт спринта · %s" % _plain_fmt(c["reward"]), Color("#56ccf2"), 16)
		cb.get_parent().tooltip_text = "Взят на рынке: произвести за этот спринт. Награда — на следующем рынке."
		cb.get_parent().mouse_filter = Control.MOUSE_FILTER_PASS
		cb.add_child(_progress_row(c["res"], have, int(c["amount"])))


func _recipe_text(recipe: String) -> String:
	if recipe == "colors3":
		return "3 цвета (%s%s%s)" % [_img("food", 16), _img("gold", 16), _img("force", 16)]
	return "2 золотых здания %s" % _img("gold", 16)


## Награда текстом с иконками, без цвета (для заголовков-лейблов).
func _plain_fmt(amounts: Dictionary) -> String:
	var parts := []
	for r in data.resources:
		var v := int(amounts.get(r, 0))
		if v != 0:
			parts.append("+%d %s" % [v, "джокер" if r == "wild" and v == 1 else ("джокера" if r == "wild" and v < 5 else ("джокеров" if r == "wild" else data.resources[r].get("name", r)))])
	return ", ".join(parts)


func _refresh_treasury() -> void:
	_clear(treasury_box)
	var sc: Dictionary = run.score()
	treasury_box.add_child(_label("Казна", 20, Color("#c9d1d9")))
	for r in data.resources:
		var chip := HBoxContainer.new()
		chip.add_theme_constant_override("separation", 4)
		chip.add_child(_icon_rect(_icon(r), 34))
		var shown: Dictionary = _treasury_shown if _treasury_shown != null else run.stock
		chip.add_child(_label(str(int(shown.get(r, 0))), 28, Color.WHITE))
		var inc := int(run.income(sc).get(r, 0))
		if inc > 0:
			chip.add_child(_label("+%d" % inc, 18, Color("#6fcf97")))
		treasury_box.add_child(chip)
	if run.steel > 0:
		treasury_box.add_child(_label("Сталь %d" % run.steel, 24, Color("#ff9f43")))
	var joy := int(sc.get("joy", 0))
	if joy > 0:
		var j := HBoxContainer.new()
		j.add_child(_icon_rect(_icon_tex("res://assets/icons/heart.svg"), 26))
		j.add_child(_label("+%d" % joy, 18, Color("#6fcf97")))
		treasury_box.add_child(j)


func _refresh_side() -> void:
	_clear(side_box)
	var sp: Dictionary = run.sprint_info()
	var rb0 := _section(side_box, "Спринт %d из %d" % [run.sprint + 1, run.sprints().size()], Color("#8ab4f8"), 19)
	var steps := ""
	for li in int(sp["layers"]):
		var boss: bool = sp.has("boss") and li == int(sp["layers"]) - 1
		var col := "#6fcf97" if li < run.layer else ("#ffffff" if li == run.layer else "#6b7480")
		steps += "[color=%s]%s[/color]  " % [col, ("[b]Босс[/b]" if boss else "Остров %d" % (li + 1)) if li == run.layer else ("Б" if boss else str(li + 1))]
	steps += "[color=#f2c94c]Рынок[/color]" if run.sprint < run.sprints().size() - 1 else "[color=#f2c94c]Финал[/color]"
	rb0.add_child(_rich_line(steps, 15))
	if run.is_cube() and _is_cube():
		var nb := _section(side_box, "Грани: %s" % _shape_word(), SEAL_COLOR, 17)
		nb.get_parent().tooltip_text = "Схема как на экране: в центре верхняя грань, вокруг — 4 стороны, куда можно катить. Число — сколько грань даёт сейчас / сколько нужно."
		nb.get_parent().mouse_filter = Control.MOUSE_FILTER_PASS
		var cc := CenterContainer.new()
		cc.add_child(_cube_net(run.field, run.cube_roll and run.phase == "island", run.score()))
		nb.add_child(cc)
		var cam := HBoxContainer.new()
		cam.alignment = BoxContainer.ALIGNMENT_CENTER
		for k in [[1, "<  Q"], [-1, "E  >"]]:
			var b := Button.new()
			b.text = k[1]
			b.focus_mode = Control.FOCUS_NONE
			b.custom_minimum_size = Vector2(70, 32)
			b.pressed.connect(_turn_camera.bind(k[0]))
			cam.add_child(b)
			if k[0] == 1:
				cam.add_child(_label("камера", 14, Color("#a9b4c0")))
		nb.add_child(cam)

	var deck_btn := Button.new()
	deck_btn.text = "Колода: %d карт (D)" % run.all_cards().size()
	deck_btn.focus_mode = Control.FOCUS_NONE
	deck_btn.custom_minimum_size = Vector2(0, 36)
	deck_btn.pressed.connect(_show_deck)
	side_box.add_child(deck_btn)

	var help_btn := Button.new()
	help_btn.text = "Скрыть правила (H)" if show_rules else "Правила (H)"
	help_btn.focus_mode = Control.FOCUS_NONE
	help_btn.custom_minimum_size = Vector2(0, 36)
	help_btn.pressed.connect(_toggle_rules)
	side_box.add_child(help_btn)
	if not show_rules:
		return
	var rb := _section(side_box, "Правила", Color("#8a96a3"), 16)
	var force := _img("force", 16)
	var t := ""
	t += "[color=#5fe3ff][b]Эхо[/b][/color] — навык карты с рынка: при постройке здания вокруг срабатывают ещё раз, доход сразу в казну. I — соседи, II — волна на 2 шага по связкам, III — вся связанная сеть.\n"
	t += "[color=#f2c94c]Уровни зданий[/color] (пристройки на модели): добыча — мастерские своего цвета, гора/озеро, плодородная земля; мастерская — добыча своего цвета; жильё — здания рядом; Рынок — цвета рядом; Таверна — жильё рядом.\n"
	t += "[color=#ff9f43][b]Кузница[/b][/color] (1 остров на спринт): соберите рецепт из соседей Наковальни — сталь; босс со сталью требует ×0,85.\n"
	t += "[b]Гора[/b]: Шахтам рядом +2%s. [b]Озеро[/b]: Полю и Мельнице рядом +1%s.\n" % [_img("gold", 14), _img("food", 14)]
	t += "Весь доход островов идёт в [b]казну[/b]. Казна тратится на [b]рынке[/b] после спринта: новые карты, улучшения, удаление, лечение.\n"
	t += "Задание острова — по желанию, за него награда. Опасные острова (рушат постройки) дают больше.\n"
	t += "[color=#eb5757]Босс[/color]: на его острове нужно произвести N всего, иначе −1%s за единицу.\n" % _heart_img(14)
	t += "[color=#ffb347]Тетраэдр[/color]: 4 треугольные грани, каждая соседка всех остальных — катите на любую. [color=#ffb347]Барабан[/color]: 6 граней по кругу, крутится только вперёд сам, всё видно заранее.\n"
	t += "[color=#ffb347]Каменный куб[/color]: 6 граней с печатями. Каждый ход катите куб на соседнюю грань и стройте на верхней. В конце хода печать верхней грани проверяют: хватает — снята, нет — −1%s за каждую недостающую единицу. Здания на краю — соседи зданий соседней грани.\n" % _heart_img(14)
	t += "[color=#ff8080]Добыча и мастерские разных цветов рядом: −1%s[/color].\n" % _heart_img(14)
	t += "Логово выключает здание по стрелке, %s рядом сносит его.\n" % force
	t += "[color=#8a96a3]1–4 карта, ПКМ снять, Z отмена, D колода, F11 полный экран, F2 куб, F3 тетраэдр, F4 барабан — сразу к боссу; Q/E вращать камеру[/color]"
	rb.add_child(_rich_line(t, 13))


func _toggle_rules() -> void:
	show_rules = not show_rules
	_refresh_side()

func _refresh_hand() -> void:
	_clear(hand_box)
	for i in run.hand.size():
		hand_box.add_child(_card_button(i, run.hand[i]))


func _card_button(i: int, id: String) -> Button:
	var col: String = data.color_of(id)
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(206, 196)
	btn.focus_mode = Control.FOCUS_NONE
	btn.disabled = run.plays_left <= 0 or busy
	var res_col := Color(_res_color(col))
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var sb := StyleBoxFlat.new()
		var sel := i == selected
		sb.bg_color = Color("#3a4656") if sel else Color("#1d2430")
		if state == "hover" and not sel:
			sb.bg_color = Color("#2a3442")
		if state == "disabled":
			sb.bg_color = Color("#161b23")
		sb.border_color = Color.WHITE if sel else res_col
		sb.set_border_width_all(4 if sel else 3)
		sb.border_width_top = 16
		sb.set_corner_radius_all(10)
		if sel:
			sb.expand_margin_top = 14
		btn.add_theme_stylebox_override(state, sb)
	btn.pressed.connect(_select.bind(i))

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	margin.add_theme_constant_override("margin_top", 16)
	btn.add_child(margin)
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", 2)
	margin.add_child(v)
	var pic := TextureRect.new()
	pic.texture = _card_tex(id)
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pic.custom_minimum_size = Vector2(0, 104)
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(pic)
	var title := _label(_card_title(id), 20, _title_color(id))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	var t := _card_rules(id)
	var stats := _rich_line("[center]%s[/center]" % t, 15)
	v.add_child(stats)
	return btn

## Короткое правило карты иконками (числа — из data/land/cards.json, у улучшенных свои).
func _card_rules(id: String, small: bool = false) -> String:
	var base_rules := _card_rules_plain(id, small)
	var lv: int = data.echo_level(id)
	if lv == 0:
		return base_rules
	return base_rules + "\n[color=#5fe3ff][b]Эхо %s[/b][/color]" % ["I", "II", "III"][lv - 1]


## Чем здание набирает уровень (для подсказки и правил).
func _level_rule(id: String) -> String:
	match data.role(id):
		"base": return "мастерские своего цвета, гора/озеро рядом, плодородная земля"
		"workshop": return "добыча своего цвета рядом"
		"housing": return "здания рядом"
	return "разные цвета рядом" if data.base_id(id) == "market" else "жильё рядом"


func _echo_desc(lv: int) -> String:
	return ["соседи срабатывают ещё раз", "волна на 2 шага по связкам", "вся связанная сеть срабатывает"][lv - 1]


func _card_title(id: String) -> String:
	return data.obj_name(data.base_id(id)) if data.echo_level(id) > 0 else data.obj_name(id)


func _title_color(id: String) -> Color:
	if data.is_weak(id):
		return Color("#9aa4ae")
	if data.echo_level(id) > 0:
		return ECHO_COLOR
	return Color("#f2c94c") if data.is_upgraded(id) else Color.WHITE


func _card_rules_plain(id: String, small: bool = false) -> String:
	var col: String = data.color_of(id)
	var big := 18 if small else 22
	var ic := 20 if small else 26
	match data.role(id):
		"base":
			return "[font_size=%d][b]+%d[/b][/font_size]%s" % [big, data.val(id, "base"), _img(col, ic)]
		"workshop":
			var partners := []
			for p in data.pair_partners(id):
				partners.append(data.objects[p].get("acc", data.obj_name(p)))
			if small:
				return "[b]+%d[/b]%s [color=#ffd866][b]+%d[/b][/color]%s за %s" % [data.val(id, "self"), _img(col, 16), data.val(id, "per_base"), _img(col, 16), "/".join(partners)]
			return "[b]+%d[/b]%s  [color=#ffd866][b]+%d[/b][/color]%s за %s" % [data.val(id, "self"), _img(col, 20), data.val(id, "per_base"), _img(col, 20), "/".join(partners)]
		"housing":
			if small:
				return "[font_size=%d][b]+%d[/b][/font_size]%s" % [big, data.val(id, "wild"), _img("wild", ic)]
			return "[font_size=%d][b]+%d[/b][/font_size]%s [color=#a9b4c0]любой цвет[/color]" % [big, data.val(id, "wild"), _img("wild", ic)]
	match data.base_id(id):
		"market":
			if small:
				return "[b]+%d[/b] за цвет рядом" % data.val(id, "per_color")
			return "[b]+%d[/b] за каждый цвет рядом %s%s%s" % [data.val(id, "per_color"), _img("food", 16), _img("gold", 16), _img("force", 16)]
		"tavern":
			return "[b]+%d[/b]%s за жильё рядом" % [data.val(id, "per_housing"), _heart_img(18)]
	return ""



## Картинка здания для карты: модель рендерится в отдельном мире (SubViewport).
var _card_tex_cache: Dictionary = {}
var _card_studio: Node

func _card_tex(id: String) -> Texture2D:
	if _card_tex_cache.has(id):
		return _card_tex_cache[id]
	if _card_studio == null:
		_card_studio = Node.new()
		add_child(_card_studio)
	var vp := SubViewport.new()
	vp.size = Vector2i(270, 180)
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_card_studio.add_child(vp)
	var env_node := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.85, 0.9, 1.0)
	env.ambient_light_energy = 0.7
	env_node.environment = env
	vp.add_child(env_node)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -30, 0)
	sun.light_energy = 1.1
	vp.add_child(sun)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 1.6
	vp.add_child(cam)
	cam.position = Vector3(4, 4.2, 4)
	cam.look_at(Vector3(0, 0.5, 0), Vector3.UP)
	var model := _make_object(id)
	vp.add_child(model)
	var tex := vp.get_texture()
	_card_tex_cache[id] = tex
	return tex


func _refresh_hint() -> void:
	var s := ""
	var f = run.field
	if busy and _treasury_shown != null:
		s = "[color=#5fe3ff][b]Эхо ×%d![/b] Здания срабатывают ещё раз…[/color]" % _echo_count
	elif busy and _is_cube():
		s = "[color=#ffb347]%s поворачивается…[/color]" % _shape_word().capitalize()
	elif busy:
		s = "[color=#c58cff]Ходит земля…[/color]"
	elif _is_cube() and run.phase == "island" and run.cube_roll:
		if roll_hover >= 0:
			s = "Катить куб сюда: печать %s" % _seal_text(roll_hover, 20)
			if f.broken[roll_hover]:
				s += "  [color=#6fcf97](уже снята — передышка)[/color]"
		else:
			if f.one_way():
				s = "Барабан поворачивается к следующей грани..."
			else:
				s = "[color=#ffb347][b]Куда катить %s?[/b][/color] Кликните по стороне фигуры или по грани на схеме справа" % _shape_word()
	elif run.plays_left <= 0:
		s = "Нажмите [b]Ход земли[/b]"
	elif selected >= 0 and selected < run.hand.size() and f.is_free(hover):
		var id: String = run.hand[selected]
		var before: Dictionary = run.score()
		var g = f.clone()
		var razed: Array = g.place_building(data, hover, id)
		var after: Dictionary = g.score(data)
		var d := {}
		for r in data.resources:
			d[r] = int(after["total"].get(r, 0)) - int(before["total"].get(r, 0))
		s = _fmt(d, true)
		var steps: Array = g.echo(data, hover, data.echo_level(id))
		if not steps.is_empty():
			s += "   [color=#5fe3ff]Эхо: сработают ещё %d → сразу %s[/color]" % [steps.size(), _fmt(g.cascade_total(steps), true)]
		var dd := int(after["discontent"]) - int(before["discontent"])
		if dd > 0:
			s += "   [color=#ff8080]−%d[/color]%s" % [dd, _heart_img(20)]
		if not razed.is_empty():
			s += "   [color=#7dffa0]Логово снесено[/color]"
		if LandEvents.endangers(run.intent, hover):
			s += "   [color=#ff5a3c][b]земля это разрушит![/b][/color]"
	elif selected < 0 and hover >= 0 and f.exists[hover] and data.is_building(f.content[hover]):
		var cellinfo: Dictionary = run.score()["cells"][hover]
		s = data.obj_name(f.content[hover]) + ": "
		if hover in run.score()["disabled"]:
			s += "[color=#c0c0c0]выключено Логовом[/color]"
		else:
			s += _fmt(cellinfo["yield"], true)
			var lv: int = f.level(data, hover)
			if lv > 0:
				s += "   [color=#f2c94c]уровень %d — %s[/color]" % [lv, _level_rule(f.content[hover])]
	else:
		s = "[color=#a9b4c0]Построек в этом ходу: %d[/color]" % run.plays_left
	hint_text.text = "[center]%s[/center]" % s

func _select(i: int) -> void:
	if overlay.visible or busy or run.plays_left <= 0:
		return
	selected = -1 if selected == i else i
	_refresh_hand()
	_refresh_hint()
	_update_hover()


## F11 или Alt+Enter — полный экран и обратно.
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F11 or (event.keycode == KEY_ENTER and event.alt_pressed):
			var full := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED if full else DisplayServer.WINDOW_MODE_FULLSCREEN)
			get_viewport().set_input_as_handled()
		elif (event.keycode == KEY_Q or event.keycode == KEY_E) and _is_cube() and not overlay.visible:
			_turn_camera(1 if event.keycode == KEY_Q else -1)
			get_viewport().set_input_as_handled()
		elif event.keycode in [KEY_F2, KEY_F3, KEY_F4] and not busy:
			_test_jump({KEY_F2: "cube", KEY_F3: "tetra", KEY_F4: "drum"}[event.keycode])
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_F1 and not busy:
			if overlay_mode == "test":
				_close_test_menu()
			else:
				_show_test_menu()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_D and not busy:
			_show_deck()
			get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if overlay.visible or busy:
		return
	if _is_cube() and run.phase == "island" and run.cube_roll:
		if event is InputEventMouseMotion:
			var rf := _cube_face_at(event.position)
			if rf != roll_hover:
				roll_hover = rf
				_update_hover()
				_refresh_hint()
			return
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			var rf := _cube_face_at(event.position)
			if rf >= 0:
				_on_roll(rf)
			return
	if event is InputEventMouseMotion:
		var c := _cell_at(event.position)
		if c != hover:
			hover = c
			_update_hover()
			_refresh_hint()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_try_place(_cell_at(event.position))
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			selected = -1
			_refresh_ui()
			_update_hover()
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1, KEY_2, KEY_3, KEY_4, KEY_5:
				var i: int = event.keycode - KEY_1
				if i < run.hand.size():
					_select(i)
			KEY_ESCAPE:
				selected = -1
				_refresh_ui()
				_update_hover()
			KEY_Z:
				_on_undo()
			KEY_H:
				_toggle_rules()
			KEY_SPACE:
				_on_end_turn()
			KEY_ENTER, KEY_KP_ENTER:
				if not event.alt_pressed:
					_on_claim()


func _try_place(cell: int) -> void:
	if selected < 0 or not run.can_place(selected, cell):
		return
	var shown: Dictionary = run.stock.duplicate()
	var before: Dictionary = run.score()
	var r: Dictionary = run.place(selected, cell)
	if not r["ok"]:
		return
	selected = -1
	_treasury_shown = shown if not r["echo"].is_empty() else null
	_full_refresh()
	var after: Dictionary = run.score()
	var d := {}
	for res in data.resources:
		var v := int(after["total"].get(res, 0)) - int(before["total"].get(res, 0))
		if v != 0:
			d[res] = v
	_float_badge(cell, d)
	for l in after["links"]:
		if (l["a"] == cell or l["b"] == cell) and l["type"] == "pair":
			_flash_tile(l["a"] if l["b"] == cell else l["b"], PAIR_COLOR)
	if not r["razed"].is_empty():
		_show_toast("[center][b]Логово снесено![/b][/center]")
	if not r["echo"].is_empty():
		await get_tree().create_timer(0.3).timeout
		await _play_cascade(r["echo"])
		_full_refresh()


## Эхо: здания срабатывают по очереди — вспышка, подпрыгивание, всплывающие цифры, казна растёт.
var _treasury_shown = null
const CASCADE_STEP := 0.38

var _echo_count := 0

func _play_cascade(steps: Array) -> void:
	_echo_count = steps.size()
	busy = true
	_refresh_ui()
	for k in steps.size():
		var st: Dictionary = steps[k]
		var c: int = st["cell"]
		_flash_tile(c, ECHO_COLOR)
		var n: Node3D = objs[c] if c < objs.size() else null
		if n != null:
			var t := create_tween()
			t.tween_property(n, "scale", Vector3(1.15, 1.3, 1.15), 0.1)
			t.tween_property(n, "scale", Vector3.ONE, 0.18).set_trans(Tween.TRANS_BACK)
		_float_badge(c, st["yield"])
		if _treasury_shown != null:
			for res in st["yield"]:
				_treasury_shown[res] = int(_treasury_shown.get(res, 0)) + int(st["yield"][res])
			_refresh_treasury()
		await get_tree().create_timer(CASCADE_STEP).timeout
	_treasury_shown = null
	busy = false
	_refresh_ui()


func _cell_at(screen_pos: Vector2) -> int:
	var from := camera.project_ray_origin(screen_pos)
	var dir := camera.project_ray_normal(screen_pos)
	if absf(dir.y) < 0.0001:
		return -1
	var t := -from.y / dir.y
	if t < 0:
		return -1
	var p := from + dir * t
	if _is_multi():
		for i in run.field.cells_n():
			if cell_up(i).y < 0.5:
				continue
			var c := cell_pos(i)
			if absf(p.x - c.x) <= 0.55 and absf(p.z - c.z) <= 0.55:
				return i
		return -1
	if _is_cube():
		if run.cube_roll:
			return -1
		for i in _top_cells():
			var c := cell_pos(i)
			if absf(p.x - c.x) <= 0.55 and absf(p.z - c.z) <= 0.55:
				return i
		return -1
	var col := roundi(p.x / STEP + 1.5)
	var row := roundi(p.z / STEP + 1.5)
	if col < 0 or col >= LandField.SIZE or row < 0 or row >= LandField.SIZE:
		return -1
	var i := row * LandField.SIZE + col
	var center := cell_pos(i)
	if absf(p.x - center.x) > 0.55 or absf(p.z - center.z) > 0.55:
		return -1
	return i


func _on_undo() -> void:
	if busy or overlay.visible:
		return
	if run.undo():
		_full_refresh()


func _on_end_turn() -> void:
	if busy or overlay.visible or run.game_over or run.phase != "island":
		return
	selected = -1
	busy = true
	_refresh_ui()
	if ghost != null:
		ghost.queue_free()
		ghost = null
		ghost_key = ""
	for c in hover_root.get_children():
		c.queue_free()
	var r: Dictionary = run.end_turn()
	if r.is_empty():
		busy = false
		_refresh_ui()
		return
	var dur := _animate_land(r.get("land", {}))
	if r.has("cube"):
		dur = maxf(dur, _cube_judge_fx(r["cube"]))
	if dur > 0.0:
		await get_tree().create_timer(dur + 0.15).timeout
	if r.has("shift"):
		await _animate_shift(r["shift"])
	busy = false
	_full_refresh()
	if r.get("field_done", false):
		_show_field_result(r["result"])
	elif _is_cube() and run.cube_roll and run.field.one_way():
		await get_tree().create_timer(0.35).timeout
		_on_roll(run.roll_options()[0])


func _on_claim() -> void:
	if busy or overlay.visible or run.game_over or run.phase != "island" or not run.task_done():
		return
	selected = -1
	var r: Dictionary = run.finish_early()
	if r.is_empty():
		return
	_full_refresh()
	_show_field_result(r["result"])


func _show_field_result(res: Dictionary) -> void:
	_clear_overlay()
	overlay_mode = "result"
	var isl: Dictionary = res["island"]
	var s := "[center][b][font_size=24]Остров %d пройден[/font_size][/b][/center]\n\n" % run.field_index
	if res.has("cube"):
		s += "Добыча куба в казну (%d%%): %s\n" % [roundi(100.0 * float(res["island"]["boss"]["cube"].get("treasury_share", 0.5))), _fmt(res["prod"], true)]
	else:
		s += "Доход острова в казну: %s\n" % _fmt(res["prod"], true)
	if run.sum_res(res.get("echo", {})) > 0:
		s += ("[color=#5fe3ff]Эхо за бой (уже в казне):[/color] %s\n" if res.has("cube") else "[color=#5fe3ff]Из них от Эхо:[/color] %s\n") % _fmt(res["echo"], true)
	if not res["reward"].is_empty():
		s += "Награда за остров%s: %s\n" % [" (опасный!)" if isl.get("danger", false) else "", _fmt(res["reward"], true)]
	if not res["task"].is_empty():
		if res["task_done"]:
			s += "[color=#6fcf97]Задание выполнено:[/color] %s\n" % _fmt(isl.get("task_reward", {}), true)
		else:
			s += "[color=#a9b4c0]Задание не выполнено — без награды[/color]\n"
	if res.has("forge"):
		s += ("[color=#ff9f43]Кузница: рецепт собран — +1 сталь для босса[/color]\n" if res["steel"] else "[color=#a9b4c0]Кузница: рецепт не собран[/color]\n")
	if res.get("steel_used", false):
		s += "[color=#ff9f43]Сталь потрачена: требование босса снижено[/color]\n"
	if res["discontent"] > 0:
		s += "[color=#eb5757]Недовольство: −%d%s[/color]\n" % [res["discontent"], _heart_img()]
	if res["joy"] > 0:
		s += "[color=#6fcf97]Таверна: +%d%s[/color]\n" % [res["joy"], _heart_img()]
	if res.has("cube"):
		var cb: Dictionary = res["cube"]
		var bn: String = res["boss"]["name"]
		if cb["broken"] == cb["faces"]:
			s += "\n[color=#6fcf97][b]%s повержен: сняты все %d печатей за %d ходов[/b][/color]\n" % [bn, cb["faces"], cb["turns"]]
		else:
			s += "\n[color=#eb5757][b]%s: снято печатей %d из %d[/b][/color]\n" % [bn, cb["broken"], cb["faces"]]
		if cb["lost_turns"] > 0:
			s += "[color=#eb5757]Удары печатей в бою: −%d%s[/color]\n" % [cb["lost_turns"], _heart_img()]
		if cb["strike"] > 0:
			s += "[color=#eb5757]Оставшиеся печати бьют разом: −%d%s[/color]\n" % [cb["strike"], _heart_img()]
	elif res.has("boss"):
		var b: Dictionary = res["boss"]
		if res["boss_missing"] == 0:
			s += "\n[color=#6fcf97][b]%s отбит: %d из %d[/b][/color]\n" % [b["name"], res["boss_total"], int(b["need"])]
		else:
			s += "\n[color=#eb5757][b]%s: %d из %d, не хватило %d[/b][/color] → −%d%s\n" % [b["name"], res["boss_total"], int(b["need"]), res["boss_missing"], res["boss_missing"] * int(b.get("life_per_missing", 1)), _heart_img()]
	var c: Dictionary = res.get("contract", {})
	if not c.is_empty():
		if c["done"]:
			s += "[color=#56ccf2]Контракт выполнен (%d/%d):[/color] %s\n" % [c["progress"], c["amount"], _fmt(c["reward"], true)]
		else:
			s += "[color=#a9b4c0]Контракт не выполнен (%d/%d)[/color]\n" % [c["progress"], c["amount"]]
	s += "\nКазна: %s\n" % _fmt(res["stock_after"])
	s += "Жизни: %d → [b]%d[/b]%s" % [res["lives_before"], res["lives_after"], _heart_img()]

	if run.victory:
		s += "\n\n[center][b][font_size=26][color=#f2c94c]Победа! Земля покорена.[/color][/font_size][/b][/center]"
		_overlay_button("Новый забег", _new_run)
	elif run.game_over:
		s += "\n\n[center][b][font_size=26][color=#eb5757]Забег окончен[/color][/font_size][/b]\nОстровов пройдено: %d[/center]" % run.field_index
		_overlay_button("Новый забег", _new_run)
	elif run.phase == "market":
		_overlay_button("На рынок", _show_market)
	else:
		_overlay_button("К карте маршрута", _show_map)
	if res["island"].get("test", false):
		_overlay_button("Тест-меню (F1)", _show_test_menu)
	_show_overlay(s, 600)


# ---------------------------------------------------------------- Карта маршрута

var map_detail: VBoxContainer
var map_hover: Dictionary = {}

func _show_map() -> void:
	_clear_overlay()
	overlay_mode = "map"
	var sp: Dictionary = run.sprint_info()
	var s := "[center][b][font_size=24]Карта забега · спринт %d из %d, шаг %d из %d[/font_size][/b]\n" % [run.sprint + 1, run.sprints().size(), run.layer + 1, int(sp["layers"])]
	s += "[color=#a9b4c0]Светлая рамка — куда можно пойти сейчас. Наведите на остров, чтобы увидеть подробности.[/color][/center]"
	overlay_body.add_child(_map_canvas())
	map_detail = VBoxContainer.new()
	map_detail.custom_minimum_size = Vector2(0, 150)
	overlay_body.add_child(map_detail)
	map_hover = run.choices[0] if not run.choices.is_empty() else {}
	_refresh_map_detail()
	var deck_b := _overlay_button("Колода (D)", _show_deck)
	deck_b.custom_minimum_size = Vector2(150, 44)
	var test_b := _overlay_button("Тест-меню (F1)", _show_test_menu)
	test_b.custom_minimum_size = Vector2(170, 44)
	_show_overlay(s, 1220)


const MAP_COL := 72.0
const MAP_ROW := 74.0
const MAP_NODE := 60.0

## Холст карты: колонки — шаги (между спринтами — рынок), строки — дорожки.
func _map_canvas() -> Control:
	var lanes := int(data.run.get("lanes", 3))
	var canvas := Control.new()
	var cols := 0
	for si in run.run_map.size():
		cols += run.run_map[si].size() + (1 if si < run.run_map.size() - 1 else 0)
	canvas.custom_minimum_size = Vector2(cols * MAP_COL + 10, lanes * MAP_ROW + 34)
	var pos := {}      # остров (по id) → центр
	var markets := []  # центры рынков
	var col := 0
	var heads := []
	for si in run.run_map.size():
		var start_x := col * MAP_COL
		for li in run.run_map[si].size():
			for isl in run.run_map[si][li]:
				var y := 30 + (float(isl["lane"]) + 0.5) * MAP_ROW
				var c := Vector2(col * MAP_COL + MAP_COL / 2 + 5, y)
				pos[_isl_key(isl)] = c
				canvas.add_child(_map_node(isl, c))
			col += 1
		heads.append([start_x, col * MAP_COL, si])
		if si < run.run_map.size() - 1:
			var mc := Vector2(col * MAP_COL + MAP_COL / 2 + 5, 30 + lanes * MAP_ROW / 2.0)
			markets.append(mc)
			var ml := _label("Рынок", 14, Color("#f2c94c"))
			ml.position = mc - Vector2(24, 34)
			canvas.add_child(ml)
			col += 1
	for h in heads:
		var lbl := _label("Спринт %d" % (h[2] + 1), 15, Color.WHITE if h[2] == run.sprint else Color("#8a96a3"))
		lbl.position = Vector2(h[0] + 8, 0)
		canvas.add_child(lbl)
	canvas.draw.connect(func(): _draw_map(canvas, pos, markets))
	return canvas


func _isl_key(isl: Dictionary) -> String:
	return "%d_%d_%d" % [int(isl["sprint"]), int(isl["layer"]), int(isl["lane"])]


func _draw_map(canvas: Control, pos: Dictionary, markets: Array) -> void:
	var dim := Color(1, 1, 1, 0.18)
	var lit := Color("#f2c94c")
	for si in run.run_map.size():
		var layers: Array = run.run_map[si]
		for li in layers.size():
			for isl in layers[li]:
				var a: Vector2 = pos[_isl_key(isl)]
				if li < layers.size() - 1:
					for t in layers[li + 1]:
						if int(t["lane"]) in isl["next"]:
							var on: bool = isl["visited"] and t["visited"]
							canvas.draw_line(a, pos[_isl_key(t)], lit if on else dim, 4.0 if on else 2.0, true)
				elif si < markets.size():
					canvas.draw_line(a, markets[si], lit if isl["visited"] else dim, 4.0 if isl["visited"] else 2.0, true)
			if li == 0 and si > 0:
				for isl in layers[0]:
					canvas.draw_line(markets[si - 1], pos[_isl_key(isl)], lit if isl["visited"] else dim, 4.0 if isl["visited"] else 2.0, true)
	for m in markets:
		canvas.draw_circle(m, 16, Color("#3a3220"))
		canvas.draw_arc(m, 16, 0, TAU, 24, Color("#f2c94c"), 3, true)
		var tex := _icon("gold")
		canvas.draw_texture_rect(tex, Rect2(m - Vector2(11, 11), Vector2(22, 22)), false)


## Остров на карте: схема 4×4 в рамке цвета земли; доступные — яркие и кликабельные.
func _map_node(isl: Dictionary, c: Vector2) -> Button:
	var avail: bool = run.phase == "map" and isl in run.choices
	var visited: bool = isl["visited"]
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.size = Vector2(MAP_NODE, MAP_NODE)
	b.position = c - b.size / 2
	var accent := _island_accent(isl)
	for state in ["normal", "hover", "pressed", "disabled"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color("#2a3442") if state == "hover" else Color("#1b222c")
		sb.border_color = Color.WHITE if (avail and state == "hover") else accent
		sb.set_border_width_all(4 if avail else 2)
		sb.set_corner_radius_all(8)
		if avail:
			sb.shadow_color = Color(accent, 0.6)
			sb.shadow_size = 6
		b.add_theme_stylebox_override(state, sb)
	if not avail:
		b.modulate = Color(1, 1, 1, 0.45 if visited or isl["layer"] < run.layer or isl["sprint"] < run.sprint else 0.8)
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if isl.has("boss"):
		var bl := _label("БОСС", 15, Color("#eb5757"))
		cc.add_child(bl)
	else:
		cc.add_child(_mini_field(isl["field"], 10))
	b.add_child(cc)
	if not isl.get("task", {}).is_empty():
		var tr := _icon_rect(_icon(isl["task"].keys()[0]), 20)
		tr.position = Vector2(MAP_NODE - 16, -6)
		b.add_child(tr)
	var tag := ""
	if isl.has("forge"):
		tag = "кузница"
	elif isl.get("big", false):
		tag = "4 хода"
	if tag != "":
		var tl := _label(tag, 11, Color("#ff9f43") if isl.has("forge") else Color("#8ab4f8"))
		tl.position = Vector2(4, MAP_NODE - 4)
		tl.add_theme_constant_override("outline_size", 4)
		tl.add_theme_color_override("font_outline_color", Color.BLACK)
		b.add_child(tl)
	if visited:
		var v := _label("✔", 18, Color("#6fcf97"))
		v.position = Vector2(-4, -10)
		b.add_child(v)
	b.mouse_entered.connect(func(): map_hover = isl; _refresh_map_detail())
	if avail:
		b.pressed.connect(_on_choose_island.bind(run.choices.find(isl)))
	return b


func _island_accent(isl: Dictionary) -> Color:
	if isl.has("boss"):
		return Color("#eb5757")
	if isl.get("danger", false):
		return DANGER_COLOR
	return LAND_COLOR if isl["event"] != "" else Color("#6fcf97")


## Подробности острова под картой.
func _refresh_map_detail() -> void:
	if map_detail == null or not is_instance_valid(map_detail):
		return
	_clear(map_detail)
	if map_hover.is_empty():
		return
	var isl := map_hover
	var avail: bool = isl in run.choices
	var p := _box_panel(_island_accent(isl), 760)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 16)
	p.get_child(0).add_child(h)
	if isl["field"].has_method("roll_to"):
		h.add_child(_cube_net(isl["field"], false))
	else:
		h.add_child(_mini_field(isl["field"], 24))
	var t := ""
	if isl.has("boss") and isl["boss"].has("cube"):
		var cc_: Dictionary = isl["boss"]["cube"]
		t += "[font_size=20][b][color=#eb5757]Босс: %s[/color][/b][/font_size]\n%s Стройте [b]%d[/b] карты на верхней грани. В конце хода её печать проверяют: не хватило — −1%s за единицу. Снимите все печати за %d ходов.\n" % [isl["boss"]["name"], SHAPE_DESC.get(cc_.get("shape", "cube"), ""), int(cc_.get("plays_per_turn", 2)), _heart_img(), int(cc_.get("max_turns", 12))]
	elif isl.has("boss"):
		t += "[font_size=20][b][color=#eb5757]Босс: %s[/color][/b][/font_size]\nПроизведите на острове [b]%d[/b] всего, иначе −1%s за каждую недостающую единицу.\n" % [isl["boss"]["name"], run.boss_need(isl["boss"]), _heart_img()]
	else:
		var ev: Dictionary = data.events.get(isl["event"], {"name": "Спокойная земля", "desc": "Земля на этом острове не двигается."})
		t += "[font_size=20][b][color=%s]%s[/color][/b][/font_size]%s\n[color=#c9d1d9]%s[/color]\n" % [_island_accent(isl).to_html(false), ev["name"], "  [color=#ff8a70]опасно[/color]" if isl.get("danger", false) else "", ev.get("desc", "")]
	if isl.has("forge"):
		t += "[color=#ff9f43]Кузница: %s рядом с Наковальней → сталь (босс ×%s)[/color]\n" % [_recipe_text(isl["forge"]), str(data.run.get("steel_boss_mult", 0.85))]
	if isl.get("big", false):
		t += "[color=#8ab4f8]Большой остров: %d хода[/color]\n" % int(isl.get("turns", 4))
	t += "Награда: %s" % (_fmt(isl.get("reward", {}), true) if not isl.get("reward", {}).is_empty() else "нет")
	if not isl.get("task", {}).is_empty():
		var tt := ""
		for r in isl["task"]:
			tt += "%d%s" % [int(isl["task"][r]), _img(r, 20)]
		t += "     Задание: произвести %s → %s" % [tt, _fmt(isl.get("task_reward", {}), true)]
	var info := _rich_line(t, 15)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(info)
	if avail:
		var go := Button.new()
		go.text = "Плыть сюда"
		go.focus_mode = Control.FOCUS_NONE
		go.custom_minimum_size = Vector2(140, 60)
		go.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		go.pressed.connect(_on_choose_island.bind(run.choices.find(isl)))
		h.add_child(go)
	var cc := CenterContainer.new()
	cc.add_child(p)
	map_detail.add_child(cc)


## Схема острова 4×4: земля, камни, озёра, готовые здания и местность.
func _mini_field(f, cell: int) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = LandField.SIZE
	grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grid.add_theme_constant_override("h_separation", 3)
	grid.add_theme_constant_override("v_separation", 3)
	for i in LandField.N:
		var c := PanelContainer.new()
		c.custom_minimum_size = Vector2(cell, cell)
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var st := StyleBoxFlat.new()
		st.set_corner_radius_all(4)
		if not f.exists[i]:
			st.bg_color = Color(0, 0, 0, 0)
		else:
			st.bg_color = TILE_FREE_COLOR
			var tr: String = f.terrain[i]
			if tr != "":
				st.bg_color = Color(data.terrain[tr].get("tint", "#7fa04f"))
			var id: String = f.content[i]
			if id == "rock":
				st.bg_color = Color("#8d8d93")
			elif id == "anvil":
				st.bg_color = Color("#ff9f43")
			elif id == "mountain":
				st.bg_color = Color("#5e5a57")
				st.border_color = Color("#f2c94c")
				st.set_border_width_all(2)
			elif id == "lake":
				st.bg_color = Color("#4a8fc8")
			elif id != "" and data.is_building(id):
				st.border_color = Color(_res_color(data.color_of(id)))
				st.set_border_width_all(5)
				st.bg_color = st.bg_color.darkened(0.3)
		c.add_theme_stylebox_override("panel", st)
		grid.add_child(c)
	return grid


func _on_choose_island(i: int) -> void:
	run.choose_island(i)
	_hide_overlay()
	selected = -1
	_full_refresh()
	_announce_field()


# ---------------------------------------------------------------- Рынок

var market_tab := 0

func _show_market() -> void:
	_clear_overlay()
	overlay_mode = "market"
	var s := "[center][b][font_size=24][color=#f2c94c]Рынок[/color] · после спринта %d[/font_size][/b]\n" % (run.sprint + 1)
	s += "Казна: %s     Жизни: [b]%d[/b]/%d%s[/center]" % [_fmt(run.stock), run.lives, int(data.run["lives"]), _heart_img()]
	var tabs := HBoxContainer.new()
	tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	tabs.add_theme_constant_override("separation", 8)
	overlay_body.add_child(tabs)
	for k in 2:
		var tb := Button.new()
		tb.text = ["Купить карту · лечение · контракт", "Улучшить или убрать карты колоды"][k]
		tb.toggle_mode = true
		tb.button_pressed = market_tab == k
		tb.focus_mode = Control.FOCUS_NONE
		tb.custom_minimum_size = Vector2(320, 40)
		tb.add_theme_font_size_override("font_size", 16)
		tb.pressed.connect(func(): market_tab = k; _show_market())
		tabs.add_child(tb)
	if market_tab == 0:
		_market_shop()
	else:
		_market_deck()
	var deck_b := _overlay_button("Колода (D)", _show_deck)
	deck_b.custom_minimum_size = Vector2(150, 50)
	var go := _overlay_button("В путь: спринт %d" % (run.sprint + 2), _on_leave_market)
	go.custom_minimum_size = Vector2(220, 50)
	_show_overlay(s, 1000)


func _price_text(price: Dictionary, compact: bool = false) -> String:
	var t := ""
	for r in price:
		if r == "any":
			t += "%d люб." % int(price[r]) if compact else "%d любых" % int(price[r])
		else:
			t += "%d%s" % [int(price[r]), _img(r, 18)]
	return t


func _market_shop() -> void:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	overlay_body.add_child(row)
	for i in run.market["buy"].size():
		var id: String = run.market["buy"][i]
		var tile := _mini_card(id, 1, 200, 96)
		var bought: bool = run.market["bought"][i]
		var price: Dictionary = run.buy_price(id)
		var rep: String = run.buy_replaces(id)
		if rep != "" and not bought:
			tile.get_child(0).add_child(_rich_line("[center][color=#a9b4c0]заменит: %s[/color][/center]" % data.obj_name(rep), 13))
		var btn := _rich_button("Куплено" if bought else "Купить за " + _price_text(price), bought or not run.can_afford(price))
		btn.pressed.connect(func(): if run.buy(i): _show_market())
		tile.get_child(0).add_child(btn)
		row.add_child(tile)

	var row2 := HBoxContainer.new()
	row2.alignment = BoxContainer.ALIGNMENT_CENTER
	row2.add_theme_constant_override("separation", 14)
	overlay_body.add_child(row2)
	# Лечение
	var hb := _box_panel(Color("#eb5757"), 240)
	var hv: VBoxContainer = hb.get_child(0)
	hv.add_child(_rich_line("[b]Лекарь[/b]: +%d%s" % [int(run.market_cfg()["heal_lives"]), _heart_img(18)], 17))
	var hprice := {"any": int(run.market_cfg()["heal_cost"])}
	var heal_b := _rich_button("Лечиться за " + _price_text(hprice), run.lives >= int(data.run["lives"]) or not run.can_afford(hprice))
	heal_b.pressed.connect(func(): if run.heal(): _show_market())
	hv.add_child(heal_b)
	row2.add_child(hb)
	# Контракт
	var c: Dictionary = run.market["contract"]
	var cbx := _box_panel(Color("#56ccf2"), 380)
	var cv: VBoxContainer = cbx.get_child(0)
	cv.add_child(_rich_line("[b]Контракт на следующий спринт[/b]: произвести за спринт %d%s → %s" % [int(c["amount"]), _img(c["res"], 20), _fmt(c["reward"], true)], 16))
	var taken: bool = run.market.get("contract_taken", false)
	var cb := _rich_button("Взят" if taken else "Взять (бесплатно, без штрафа)", taken)
	cb.pressed.connect(func(): if run.take_contract(): _show_market())
	cv.add_child(cb)
	row2.add_child(cbx)
	# Редкое Эхо III
	var e3: String = run.market.get("echo3", "")
	if e3 != "":
		var ebx := _box_panel(ECHO_COLOR, 260)
		var ev: VBoxContainer = ebx.get_child(0)
		ev.add_child(_rich_line("[b][color=#5fe3ff]Редкое: Эхо III[/color][/b] для карты [b]%s[/b] — вся связанная сеть срабатывает" % data.obj_name(e3), 15))
		var ep: Dictionary = run.echo_price(e3, 3)
		var b3 := _rich_button("Купить за " + _price_text(ep), not run.can_afford(ep))
		b3.pressed.connect(func(): if run.buy_echo3(): _show_market())
		ev.add_child(b3)
		row2.add_child(ebx)


func _market_deck() -> void:
	overlay_body.add_child(_rich_line("[center][color=#a9b4c0]Слабая карта улучшается до обычной. Обычная получает либо [color=#f2c94c]+1[/color] к доходу, либо [color=#5fe3ff]Эхо I[/color] (при постройке соседи срабатывают ещё раз). Эхо II — со 2-го рынка. Платится цветом карты.[/color][/center]", 14))
	var grid := GridContainer.new()
	grid.columns = 7
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	var cc := CenterContainer.new()
	cc.add_child(grid)
	overlay_body.add_child(cc)
	var counts := _deck_counts()
	var rprice := {"any": int(run.market_cfg()["remove_cost"])}
	for id in counts:
		var tile := _mini_card(id, counts[id], 132, 48, true)
		var v: VBoxContainer = tile.get_child(0)
		if data.can_upgrade(id):
			var up_price: Dictionary = run.upgrade_price(id)
			var ub := _rich_button(("Улучшить: " if data.is_weak(id) else "+1: ") + _price_text(up_price, true), not run.can_afford(up_price), 12)
			ub.tooltip_text = "Станет: " + data.obj_name(data.upgrade_of(id))
			ub.pressed.connect(func(): if run.upgrade(id): _show_market())
			v.add_child(ub)
		var nx: String = run.echo_next(id)
		if nx != "":
			var lv: int = data.echo_level(nx)
			var ep: Dictionary = run.echo_price(id, lv)
			var eb := _rich_button("[color=#5fe3ff]Эхо %s[/color]: %s" % [["I", "II", "III"][lv - 1], _price_text(ep, true)], not run.can_afford(ep), 12)
			eb.tooltip_text = "Эхо %s: при постройке %s." % [["I", "II", "III"][lv - 1], _echo_desc(lv)]
			eb.pressed.connect(func(): if run.echo(id): _show_market())
			v.add_child(eb)
		var rb := _rich_button("Убрать " + _price_text(rprice, true), not run.can_afford(rprice) or run.all_cards().size() <= int(data.run["hand_size"]) + 2, 12)
		rb.pressed.connect(func(): if run.remove(id): _show_market())
		v.add_child(rb)
		grid.add_child(tile)


func _on_leave_market() -> void:
	run.leave_market()
	_show_map()


## Карты колоды по id с количеством, в порядке: добыча, мастерские, жильё, городские; улучшенные после обычных.
func _deck_counts() -> Dictionary:
	var ids: Array = []
	var counts := {}
	for id in run.all_cards():
		if not counts.has(id):
			ids.append(id)
			counts[id] = 0
		counts[id] += 1
	var order: Array = data.objects.keys()
	ids.sort_custom(func(a, b):
		var ia := order.find(data.base_id(a)) * 2 + (1 if data.is_upgraded(a) else 0)
		var ib := order.find(data.base_id(b)) * 2 + (1 if data.is_upgraded(b) else 0)
		return ia < ib)
	var out := {}
	for id in ids:
		out[id] = counts[id]
	return out


## Маленькая карта: картинка, имя, (количество), правило.
func _mini_card(id: String, count: int, width: int, pic_h: int, compact: bool = false) -> PanelContainer:
	var up: bool = data.is_upgraded(id)
	var p := _box_panel(ECHO_COLOR if data.echo_level(id) > 0 else (Color("#f2c94c") if up else Color(_res_color(data.color_of(id)))), width)
	var v: VBoxContainer = p.get_child(0)
	var pic := TextureRect.new()
	pic.texture = _card_tex(id)
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pic.custom_minimum_size = Vector2(0, pic_h)
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(pic)
	var name: String = _card_title(id) + ("  ×%d" % count if count > 1 else "")
	var title := _label(name, 15 if compact else 18, _title_color(id))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	v.add_child(_rich_line("[center]%s[/center]" % _card_rules(id, compact), 12 if compact else 14))
	return p


func _box_panel(color: Color, width: int) -> PanelContainer:
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(width, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#232b38")
	sb.border_color = color
	sb.set_border_width_all(2)
	sb.border_width_top = 6
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(8)
	p.add_theme_stylebox_override("panel", sb)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	p.add_child(v)
	return p


## Кнопка с BBCode-текстом (иконки ресурсов).
func _rich_button(bb: String, disabled: bool, size: int = 15) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.disabled = disabled
	b.custom_minimum_size = Vector2(0, 26 if size < 14 else 36)
	var r := _rich_line("[center]%s[/center]" % bb, size)
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.offset_top = 4 if size < 14 else 8
	if disabled:
		r.modulate = Color(1, 1, 1, 0.45)
	b.add_child(r)
	return b


# ---------------------------------------------------------------- Колода

var _deck_back := ""

func _show_deck() -> void:
	if busy or overlay_mode == "result":
		return
	if overlay_mode == "deck":
		_close_deck()
		return
	_deck_back = overlay_mode if overlay.visible else ""
	_clear_overlay()
	overlay_mode = "deck"
	var all: Array = run.all_cards()
	var ups := 0
	for id in all:
		if data.is_upgraded(id):
			ups += 1
	var s := "[center][b][font_size=24]Колода: %d %s[/font_size][/b]\n[color=#a9b4c0]В доборе %d, в сбросе %d, в руке %d. Улучшенных: %d.[/color][/center]" % [all.size(), _plural(all.size(), "карта", "карты", "карт"), run.deck.draw_pile.size(), run.deck.discard_pile.size(), run.hand.size(), ups]
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	var cc := CenterContainer.new()
	cc.add_child(grid)
	overlay_body.add_child(cc)
	var counts := _deck_counts()
	for id in counts:
		grid.add_child(_mini_card(id, counts[id], 150, 76, true))
	_overlay_button("Закрыть (D)", _close_deck)
	_show_overlay(s, 960)


func _close_deck() -> void:
	match _deck_back:
		"map": _show_map()
		"market": _show_market()
		"test": _show_test_menu()
		_: _hide_overlay()


# ---------------------------------------------------------------- Оверлей

func _clear_overlay() -> void:
	_clear(overlay_body)
	_clear(overlay_buttons)


func _show_overlay(text: String, width: int = 600) -> void:
	overlay_box.custom_minimum_size = Vector2(width, 0)
	overlay_box.size = Vector2.ZERO
	overlay_text.text = text
	overlay_body.visible = overlay_body.get_child_count() > 0
	overlay.visible = true


func _hide_overlay() -> void:
	overlay.visible = false
	overlay_mode = ""


func _overlay_button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(150, 70)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	overlay_buttons.add_child(b)
	return b


# ---------------------------------------------------------------- Босс-куб

func _update_camera() -> void:
	var look := Vector3(0.3, 0, 0.3)
	var shift := Vector3(0, -0.9, 0)
	camera.size = 7.8
	badge_k = 1.0
	var off := Vector3(7, 8, 7)
	if _is_multi():
		var ext := 0.0
		for i in run.field.cells_n():
			var w: Vector3 = run.field.world(i)
			ext = maxf(ext, maxf(absf(w.x), absf(w.z)) * 2 + 1)
		look = Vector3(0, 0, 0)
		camera.size = 7.8 * maxf(1.0, ext / 4.2)
		badge_k = maxf(1.0, camera.size / 9.0)
	if _is_cube():
		var rb := 0.0
		for i in run.field.cells_n():
			for v in run.field.poly(i):
				rb = maxf(rb, (v as Vector3).length())
		look = _cube_off() + Vector3(0, 0.27, 0)
		shift = Vector3(0, -1.6, 0) * rb / 2.6
		camera.size = rb * STEP * 3.5
		badge_k = maxf(1.0, camera.size / 10.4)
		off = off.rotated(Vector3.UP, cam_yaw)
	camera.position = look + off
	camera.look_at(look, Vector3.UP)
	camera.position += shift


func _top_cells() -> Array:
	var out := []
	var t: int = run.field.top()
	for i in run.field.face_cells(t):
		out.append(i)
	return out


## Направление в мире → номер стрелки (0 вверх/-Z, 1 вниз/+Z, 2 влево/-X, 3 вправо/+X).
static func _dir_index(d: Vector3) -> int:
	if d.z < -0.5:
		return 0
	if d.z > 0.5:
		return 1
	if d.x < -0.5:
		return 2
	return 3


## Грань куба под курсором при выборе поворота: всё, что за краем верхней грани, — та сторона.
func _cube_face_at(screen_pos: Vector2) -> int:
	var from := camera.project_ray_origin(screen_pos)
	var dir := camera.project_ray_normal(screen_pos)
	if absf(dir.y) < 0.0001:
		return -1
	var t := -from.y / dir.y
	var p := from + dir * t
	if _in_top_face(p):
		return -1
	var d := Vector3(p.x, 0, p.z).normalized()
	var best := -1
	var bv := -2.0
	var sides: Dictionary = run.field.side_faces()
	for f in run.roll_options():
		if sides.has(f) and sides[f].dot(d) > bv:
			bv = sides[f].dot(d)
			best = f
	return best


## Точка на плоскости y=0 внутри верхней грани?
func _in_top_face(p: Vector3) -> bool:
	var pts := []
	for v in run.field.face_poly(run.field.top()):
		var w: Vector3 = run.field.orient * v * STEP + _cube_off()
		pts.append(Vector2(w.x, w.z))
	return Geometry2D.is_point_in_polygon(Vector2(p.x, p.z), PackedVector2Array(pts))


## Печать грани текстом: «3/5 [золото]» по каждому ресурсу; снятая — зелёным.
func _seal_text(face: int, size: int = 18, sc: Dictionary = {}) -> String:
	var f = run.field if _is_cube() else null
	return _seal_text_of(f, face, size, sc)


func _seal_text_of(f, face: int, size: int, sc: Dictionary) -> String:
	var seal: Dictionary = f.seals[face]
	if f.broken[face]:
		return "[color=#6fcf97]снята[/color]"
	var have: Dictionary = {}
	if not sc.is_empty():
		have = run.cube_have(sc) if face == f.top() and run.is_cube() else sc["faces"][face]
	var parts := []
	var wild := int(have.get("wild", 0))
	for r in seal:
		if sc.is_empty():
			parts.append("[b]%d[/b]%s" % [int(seal[r]), _img(r, size)])
		else:
			var h := int(have.get(r, 0))
			var col := "#6fcf97" if h >= int(seal[r]) else "#ffffff"
			parts.append("[color=%s]%d[/color]/[b]%d[/b]%s" % [col, h, int(seal[r]), _img(r, size)])
	var t := " ".join(parts)
	if wild > 0:
		t += " +%d%s" % [wild, _img("wild", size)]
	return t


## Печати на кубе: значки над краями верхней грани (куда можно катить) и стрелки при выборе.
func _cube_extras(sc: Dictionary) -> void:
	var f = run.field
	var sides: Dictionary = f.side_faces()
	var opts: Array = run.roll_options() if run.phase == "island" else []
	var top: int = f.top()
	for face in sides:
		var d: Vector3 = sides[face]
		var mid: Vector3 = f.orient * f.shared_edge_mid(top, face) * STEP + _cube_off()
		mid.y = 0
		var holder := Node3D.new()
		holder.position = mid + d * 0.95 + Vector3(0, 0.25, 0)
		board_root.add_child(holder)
		if f.broken[face]:
			holder.add_child(_text_badge("снята", 34, SEAL_DONE_COLOR))
		else:
			var have: Dictionary = sc["faces"][face]
			var lines := []
			for r in f.seals[face]:
				lines.append([r, int(have.get(r, 0)), int(f.seals[face][r])])
			holder.add_child(_seal_badge(lines, 38, face == roll_hover))
		if face in opts:
			var ar := _arrow_node(0, SEAL_COLOR if face == roll_hover else Color("#ffe3a3"), 0.95)
			ar.position = mid - d * 0.65 + Vector3(0, 0.02, 0)
			ar.rotation.y = atan2(-d.x, -d.z)
			ar.scale = Vector3.ONE * 1.6
			board_root.add_child(ar)


## Значок печати: строки «есть/нужно [иконка]».
func _seal_badge(lines: Array, font_size: int, hot: bool) -> Node3D:
	var root := Node3D.new()
	var line_h := font_size * 1.15
	var top := (lines.size() - 1) * line_h / 2.0
	for k in lines.size():
		var res: String = lines[k][0]
		var have: int = lines[k][1]
		var need: int = lines[k][2]
		var y := top - k * line_h
		var lbl := _text_badge("%d/%d" % [mini(have, need), need], font_size, SEAL_DONE_COLOR if have >= need else (SEAL_COLOR if hot else Color("#f4e7d0")))
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		lbl.offset = Vector2(-font_size * 0.05, y)
		root.add_child(lbl)
		var spr := Sprite3D.new()
		spr.texture = _icon(res)
		spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		spr.no_depth_test = true
		spr.render_priority = 6
		spr.pixel_size = 0.006 * badge_k * font_size * 1.1 / 64.0
		var k_px := 64.0 / (font_size * 1.1)
		spr.offset = Vector2(font_size * 0.6 * k_px, y * k_px)
		root.add_child(spr)
	return root


## Блок босса-куба в левой панели: печать верхней грани, сколько снято, схема куба.
func _cube_info(sc: Dictionary) -> void:
	var f = run.field
	var b: Dictionary = run.island["boss"]
	var broken: int = f.face_count() - f.sealed_faces().size()
	var bb := _section(info_box, "Босс: %s · печати %d/%d" % [b["name"], broken, f.face_count()], Color("#eb5757"), 19)
	bb.get_parent().tooltip_text = "Каждый ход катите куб на соседнюю грань и стройте на верхней. В конце хода её печать проверяют: хватает — снята, нет — −1 жизнь за каждую недостающую единицу. Здания на краю грани — соседи зданий соседней грани. Не снятые к последнему ходу печати бьют разом."
	bb.get_parent().mouse_filter = Control.MOUSE_FILTER_PASS
	if run.cube_roll and f.one_way():
		bb.add_child(_rich_line("Барабан поворачивается к следующей грани: назад дороги нет.", 15))
	elif run.cube_roll:
		bb.add_child(_rich_line("[color=#ffb347][b]Куда катить %s?[/b][/color] Кликните по стороне фигуры или по грани на схеме справа." % _shape_word(), 15))
	else:
		var top: int = f.top()
		if f.broken[top]:
			bb.add_child(_rich_line("Верхняя грань: печать уже снята — передышка, готовьте рёбра.", 15))
		else:
			var miss: int = run.cube_shortfall(top, sc)
			bb.add_child(_rich_line("Верхняя грань: %s" % _seal_text(top, 20, sc), 17))
			if miss > 0:
				bb.add_child(_rich_line("[color=#ff8080]Не хватает %d → −%d%s при проверке[/color]" % [miss, miss * int(b.get("life_per_missing", 1)), _heart_img(16)], 14))
			else:
				bb.add_child(_rich_line("[color=#6fcf97]Хватает — печать будет снята[/color]", 14))
	var left: int = run.turns_here() - run.turn
	bb.add_child(_rich_line("[color=#a9b4c0]Ходов после этого: %d. Потом оставшиеся печати бьют разом.[/color]" % left, 13))


## Схема-развёртка куба, повёрнутая как на экране: в центре верх, вокруг 4 стороны,
## низ — за ближней к зрителю стороной. Клетки цветом зданий, на гранях — печати.
## Клик по стороне — катить туда.
func _cube_net(f, interactive: bool, sc: Dictionary = {}) -> Control:
	var view := Control.new()
	view.custom_minimum_size = Vector2(250, 250)
	view.mouse_filter = Control.MOUSE_FILTER_STOP if interactive else Control.MOUSE_FILTER_IGNORE
	var yaw := cam_yaw if _is_cube() else 0.0
	# Экранные оси на земле: вправо и «от зрителя»
	var right := Vector3(1, 0, -1).normalized().rotated(Vector3.UP, yaw)
	var away := Vector3(-1, 0, -1).normalized().rotated(Vector3.UP, yaw)
	var opts: Array = run.roll_options() if interactive else []
	# Развёртка: каждая грань откидывается на плоскость верхней вокруг общего ребра с соседкой,
	# уже лежащей на плоскости (дальние грани — к ближней к зрителю стороне).
	var nf: int = f.face_count()
	var tr := {}
	var top: int = f.top()
	tr[top] = Transform3D.IDENTITY
	var fnb: Array = f.g()["fnb"]
	var wpoly := func(face: int) -> Array:
		var out := []
		for v in f.face_poly(face):
			out.append(f.orient * v)
		return out
	var guard := 0
	while tr.size() < nf and guard < 12:
		guard += 1
		var add := {}
		for face in nf:
			if tr.has(face):
				continue
			var best := -1
			var bv := INF
			for par in fnb[face]:
				if not tr.has(par):
					continue
				var c := Vector3.ZERO
				for v in wpoly.call(par):
					c += tr[par] * v
				var v2 := c.dot(away)
				if v2 < bv:
					bv = v2
					best = par
			if best < 0:
				continue
			var shared := []
			for p in wpoly.call(face):
				for q in wpoly.call(best):
					if (p as Vector3).distance_to(q) < 0.01:
						shared.append(p)
			var a0: Vector3 = shared[0]
			var e: Vector3 = (shared[1] - shared[0]).normalized()
			var ng: Vector3 = f.world_normal(face)
			var np: Vector3 = f.world_normal(best)
			var th := atan2(e.dot(ng.cross(np)), ng.dot(np))
			var hinge := Transform3D(Basis(e, th), Vector3.ZERO)
			hinge = Transform3D(Basis.IDENTITY, a0) * hinge * Transform3D(Basis.IDENTITY, -a0)
			add[face] = tr[best] * hinge
		if add.is_empty():
			break
		for k in add:
			tr[k] = add[k]
	var to2 := func(u: Vector3) -> Vector2:
		return Vector2(u.dot(right), -u.dot(away))
	var cells := {}
	var faces2 := {}
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for face in tr:
		var fp := []
		for v in wpoly.call(face):
			var q: Vector2 = to2.call(tr[face] * v)
			fp.append(q)
			lo = Vector2(minf(lo.x, q.x), minf(lo.y, q.y))
			hi = Vector2(maxf(hi.x, q.x), maxf(hi.y, q.y))
		faces2[face] = fp
		for i in f.face_cells(face):
			var cp := []
			var cc := Vector2.ZERO
			for v in f.poly(i):
				var q: Vector2 = to2.call(tr[face] * (f.orient * v))
				cp.append(q)
				cc += q
			cc /= cp.size()
			var shr := []
			for q in cp:
				shr.append(cc + (q - cc) * 0.86)
			cells[i] = shr
	var scale := minf(244.0 / (hi.x - lo.x), 244.0 / (hi.y - lo.y))
	var origin := Vector2(125, 125) - (lo + hi) / 2.0 * scale
	var font: Font = ThemeDB.fallback_font
	var px := func(q: Vector2) -> Vector2:
		return origin + q * scale
	view.draw.connect(func():
		for i in cells:
			var face: int = f.face_of(i)
			var id: String = f.content[i]
			var col := Color("#5d7a3a")
			if f.broken[face]:
				col = Color("#3d6b45")
			if id == "rock":
				col = Color("#8d8d93")
			elif id == "mountain":
				col = Color("#5e5a57")
			elif id != "" and data.is_building(id):
				col = Color(_res_color(data.color_of(id)))
			if face == roll_hover and not f.broken[face]:
				col = col.lerp(SEAL_COLOR, 0.35)
			var pts := PackedVector2Array()
			for q in cells[i]:
				pts.append(px.call(q))
			view.draw_colored_polygon(pts, col)
		for face in faces2:
			var pts := PackedVector2Array()
			var c := Vector2.ZERO
			for q in faces2[face]:
				pts.append(px.call(q))
				c += px.call(q)
			c /= faces2[face].size()
			pts.append(pts[0])
			var bc := Color("#4a5566")
			var w := 1.5
			if face == f.top():
				bc = Color.WHITE
				w = 3.0
			elif face in opts:
				bc = SEAL_COLOR
				w = 3.0 if face == roll_hover else 2.0
			view.draw_polyline(pts, bc, w)
			var lines := []
			if f.broken[face]:
				lines.append(["", "снята"])
			else:
				var have: Dictionary = {}
				if not sc.is_empty():
					have = run.cube_have(sc) if face == f.top() and run.is_cube() and run.phase == "island" else sc["faces"][face]
				for r in f.seals[face]:
					var t := str(int(f.seals[face][r]))
					if not sc.is_empty():
						t = "%d/%d" % [mini(int(have.get(r, 0)), int(f.seals[face][r])), int(f.seals[face][r])]
					lines.append([r, t])
			var y0 := c.y - (lines.size() - 1) * 9.0
			for k in lines.size():
				var r: String = lines[k][0]
				var t: String = lines[k][1]
				var fs := 15
				var tw := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
				var total := tw + (16.0 if r != "" else 0.0)
				var x := c.x - total / 2.0
				var y := y0 + k * 18.0
				view.draw_rect(Rect2(x - 3, y - 9, total + 6, 18), Color(0, 0, 0, 0.55))
				var tc := Color("#6fcf97") if r == "" else Color.WHITE
				view.draw_string_outline(font, Vector2(x, y + 5), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 3, Color.BLACK)
				view.draw_string(font, Vector2(x, y + 5), t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, tc)
				if r != "":
					view.draw_texture_rect(_icon(r), Rect2(x + tw + 2, y - 7, 14, 14), false)
		)
	if interactive:
		var face_at := func(pos: Vector2) -> int:
			var q: Vector2 = (pos - origin) / scale
			for face in opts:
				if faces2.has(face) and Geometry2D.is_point_in_polygon(q, PackedVector2Array(faces2[face])):
					return face
			return -1
		view.gui_input.connect(func(ev: InputEvent):
			if ev is InputEventMouseMotion:
				var fh: int = face_at.call(ev.position)
				if fh != roll_hover:
					roll_hover = fh
					view.queue_redraw()
					_update_hover()
					_refresh_hint()
			elif ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				var fc: int = face_at.call(ev.position)
				if fc >= 0:
					_on_roll(fc))
	return view


## Камера вокруг куба на 90° (Q — влево, E — вправо).
func _turn_camera(dir: int) -> void:
	if _cam_turning:
		return
	_cam_turning = true
	for c in hover_root.get_children():
		c.queue_free()
	var from := cam_yaw
	var tw := create_tween()
	tw.tween_method(func(a: float):
		cam_yaw = a
		_update_camera(), from, from + dir * PI / 2.0, 0.35).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tw.finished
	cam_yaw = wrapf(cam_yaw, -PI, PI)
	_cam_turning = false
	_full_refresh()


## Куб катится: поворот на 90° вокруг ребра, потом поле перестраивается.
func _on_roll(face: int) -> void:
	if busy or overlay.visible or not _is_cube() or not (face in run.roll_options()):
		return
	busy = true
	selected = -1
	roll_hover = -1
	for c in hover_root.get_children():
		c.queue_free()
	_refresh_ui()
	var axis: Vector3 = run.field.roll_axis(face)
	var ang: float = run.field.roll_angle(face)
	var pivot := _cube_off()
	var tw := create_tween()
	tw.tween_method(func(a: float):
		board_root.transform = Transform3D(Basis(axis, a), Vector3.ZERO).translated_local(-pivot).translated(pivot)
		, 0.0, ang, 0.55).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tw.finished
	board_root.transform = Transform3D.IDENTITY
	run.roll(face)
	busy = false
	_full_refresh()
	if run.field.broken[face]:
		_show_toast("[center][b]Передышка[/b]\n[font_size=16]Печать этой грани уже снята. Можно готовить рёбра для соседних граней.[/font_size][/center]")
	else:
		_show_toast("[center][b]Печать грани: %s[/b]\n[font_size=16]Постройте до %d карт на верхней грани и нажмите «Проверить печать».[/font_size][/center]" % [_seal_text(face, 22), run.plays_left])


## Проверка печати: вспышка верхней грани и надпись. Возвращает длительность.
func _cube_judge_fx(j: Dictionary) -> float:
	if j.get("was_broken", false):
		return 0.0
	var col := SEAL_DONE_COLOR if j["broken"] else DANGER_COLOR
	for i in run.field.face_cells(int(j["face"])):
		_flash_tile(i, col)
	if j["broken"]:
		_show_toast("[center][b][color=#6fcf97]Печать снята![/color][/b][/center]")
	else:
		_show_toast("[center][b][color=#ff8080]Печать устояла: не хватило %d → −%d[/color][/b]%s[/center]" % [j["miss"], j["miss"], _heart_img(22)])
	return 0.6


## F2 (для проверки): новый забег, бот доигрывает до босса-куба, жизни восстановлены.
# ---------------------------------------------------------------- Тест-меню

## Колода как в начале спринта test_stage (0–3); -1 — «своё место» (босс — свой спринт, остров — 1-й)
var test_stage := -1
var _test_back := ""

func _show_test_menu() -> void:
	if busy:
		return
	if overlay_mode != "test":
		_test_back = overlay_mode if overlay.visible else ""
	_clear_overlay()
	overlay_mode = "test"
	var s := "[center][b][font_size=24]Тест-меню[/font_size][/b]\n[color=#a9b4c0]Выберите босса или остров: бот доиграет новый забег до нужного спринта (колода как в игре), и вы сразу окажетесь там. Жизни полные.[/color][/center]"
	# Колода: с какого спринта
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 6)
	overlay_body.add_child(row)
	row.add_child(_label("Колода как перед:", 16, Color("#d7dde4")))
	var opts := [[-1, "своим местом"], [0, "спринтом 1"], [1, "спринтом 2"], [2, "спринтом 3"], [3, "спринтом 4"]]
	for o in opts:
		var tb := Button.new()
		tb.text = o[1]
		tb.toggle_mode = true
		tb.button_pressed = test_stage == int(o[0])
		tb.focus_mode = Control.FOCUS_NONE
		tb.custom_minimum_size = Vector2(130, 36)
		tb.add_theme_font_size_override("font_size", 15)
		var v: int = o[0]
		tb.pressed.connect(func(): test_stage = v; _show_test_menu())
		row.add_child(tb)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 12)
	cols.alignment = BoxContainer.ALIGNMENT_CENTER
	overlay_body.add_child(cols)
	var lists := [["Боссы", Color("#eb5757"), LandTest.BOSSES], ["Острова", Color("#7fa04f"), LandTest.ISLANDS], ["Живая земля", LAND_COLOR, LandTest.LAND], ["Из частей", ECHO_COLOR, LandTest.PARTS]]
	for l in lists:
		var col := VBoxContainer.new()
		col.custom_minimum_size = Vector2(270, 0)
		col.add_theme_constant_override("separation", 6)
		cols.add_child(col)
		var title := _label(l[0], 20, l[1])
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(title)
		for e in l[2]:
			var where := ""
			if e.has("stage"):
				where = "  [color=#a9b4c0]· спринт %d[/color]" % (int(e["stage"]) + 1)
			var b := _rich_button("[b]%s[/b]%s\n[font_size=13][color=#a9b4c0]%s[/color][/font_size]" % [e["name"], where, e["desc"]], false, 15)
			b.custom_minimum_size = Vector2(0, 54)
			var kind: String = e["id"]
			b.pressed.connect(func(): _test_jump(kind))
			col.add_child(b)
	_overlay_button("Закрыть (F1)", _close_test_menu).custom_minimum_size = Vector2(150, 44)
	_overlay_button("Новый забег", _new_run).custom_minimum_size = Vector2(150, 44)
	_show_overlay(s, 1200)


func _close_test_menu() -> void:
	match _test_back:
		"map": _show_map()
		"market": _show_market()
		"": _hide_overlay()
		_:
			if run.phase == "map":
				_show_map()
			elif run.phase == "market":
				_show_market()
			else:
				_hide_overlay()


## Быстрый запуск: F2/F3/F4 и кнопки тест-меню.
func _test_jump(kind: String) -> void:
	if busy:
		return
	busy = true
	_hide_overlay()
	var stage := test_stage
	if stage < 0:
		stage = LandTest.boss_stage(kind)
	_show_toast("[center][b]Бот готовит колоду: спринт %d...[/b][/center]" % (stage + 1))
	await get_tree().process_frame
	await get_tree().process_frame
	LandTest.jump(run, data, kind, stage)
	selected = -1
	busy = false
	cam_yaw = 0.0
	_full_refresh()
	if run.phase == "market":
		_show_market()
	else:
		_announce_field()
