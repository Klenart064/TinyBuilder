## Прототип «живая земля»: поле до 4×4, ход игрока (до 2 построек), потом ход земли.
## Логика — в scripts/land, здесь только отображение и ввод.
extends Node3D

const LandData = preload("res://scripts/land/land_data.gd")
const LandRun = preload("res://scripts/land/land_run.gd")
const LandField = preload("res://scripts/land/land_field.gd")
const LandEvents = preload("res://scripts/land/land_events.gd")
const Models = preload("res://scripts/view/models.gd")

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
var overlay: Control
var overlay_text: RichTextLabel
var overlay_buttons: HBoxContainer
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
	_announce_field()


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
	return Vector3((i % LandField.SIZE - 1.5) * STEP, 0, (i / LandField.SIZE - 1.5) * STEP)


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
	for i in LandField.N:
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
		tile.mesh = _box_mesh(Vector3(1.05, 0.3, 1.05))
		tile.position = p + Vector3(0, -0.15, 0)
		var base := _tile_color(i)
		var mat := _mat(base)
		tile.material_override = mat
		board_root.add_child(tile)
		tiles[i] = tile
		tile_mats[i] = mat
		tile_base[i] = base
		# Земляной «бок» под клеткой
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
			node.position = p
			board_root.add_child(node)
			objs[i] = node

	# Связи: пары, дом, конфликты
	for l in sc["links"]:
		match l["type"]:
			"pair":
				board_root.add_child(_link_mesh(l["a"], l["b"], 0.12, 0.03, _glow_mat(PAIR_COLOR, 0.9)))
			"house":
				board_root.add_child(_link_mesh(l["a"], l["b"], 0.07, 0.03, _glow_mat(HOUSE_COLOR, 0.6)))
			"conflict":
				board_root.add_child(_link_mesh(l["a"], l["b"], 0.12, 0.03, _glow_mat(CONFLICT_COLOR, 0.9)))
				var mid: Vector3 = (cell_pos(l["a"]) + cell_pos(l["b"])) / 2 + Vector3(0, 0.6, 0)
				var hb := _heart_badge(-1, 30)
				hb.position = mid
				board_root.add_child(hb)

	# Доход над зданиями
	for i in LandField.N:
		if not f.exists[i] or not data.is_building(f.content[i]):
			continue
		var holder := Node3D.new()
		holder.position = cell_pos(i) + Vector3(0, float(data.objects[f.content[i]].get("height", 0.9)) + 0.3, 0)
		board_root.add_child(holder)
		if i in sc["disabled"]:
			holder.add_child(_text_badge("выкл", 30, Color("#c0c0c0")))
			_dim(objs[i])
		else:
			var y: Dictionary = sc["cells"][i]["yield"]
			if y.is_empty():
				holder.add_child(_text_badge("0", 30, Color("#9aa4ae")))
			else:
				holder.add_child(_make_badge(y, 30, Color.WHITE, 5))


func _terrain_label(i: int) -> void:
	var t: Dictionary = data.terrain[run.field.terrain[i]]
	var node: Node3D
	if t["color"] == "any":
		node = _text_badge("−1", 26, Color("#ffb0a0"))
	else:
		node = _make_badge({t["color"]: int(t["bonus"])}, 26, Color.WHITE, 3)
	node.position = cell_pos(i) + Vector3(-0.28, 0.12, 0.28)
	board_root.add_child(node)

func _dim(node: Node3D) -> void:
	if node == null:
		return
	for c in node.get_children():
		if c is MeshInstance3D and c.material_override is StandardMaterial3D:
			c.material_override.albedo_color = c.material_override.albedo_color.darkened(0.55)


func _link_mesh(a: int, b: int, width: float, y: float, mat: Material) -> MeshInstance3D:
	var pa := cell_pos(a)
	var pb := cell_pos(b)
	var mi := MeshInstance3D.new()
	var horizontal := absf(pa.x - pb.x) > 0.01
	var length := pa.distance_to(pb)
	mi.mesh = _box_mesh(Vector3(length if horizontal else width, 0.04, width if horizontal else length))
	mi.position = (pa + pb) / 2 + Vector3(0, y, 0)
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
	for i in LandField.N:
		if tile_mats.size() <= i or tile_mats[i] == null:
			continue
		var c: Color = tile_base[i]
		if card != "" and f.is_free(i):
			c = c.lerp(TILE_FREE_COLOR, 0.5)
			if LandEvents.endangers(run.intent, i):
				c = c.lerp(TILE_DANGER_COLOR, 0.5)
			if i == hover:
				c = TILE_HOVER_COLOR
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
	var dd := int(after["discontent"]) - int(before["discontent"])
	if dd > 0:
		var hb := _heart_badge(-dd, 36)
		hb.position = cell_pos(hover) + Vector3(0, 2.25, 0)
		hover_root.add_child(hb)
	for l in after["links"]:
		if l["a"] != hover and l["b"] != hover:
			continue
		var col := PAIR_COLOR if l["type"] == "pair" else (HOUSE_COLOR if l["type"] == "house" else CONFLICT_COLOR)
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
	lbl.pixel_size = 0.006
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
	spr.pixel_size = 0.006 * size * 1.0 / 64.0
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
		lbl.pixel_size = 0.006
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
		spr.pixel_size = 0.006 * font_size * 1.1 / 64.0
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
	_show_toast("[center][b]Поле %d: %s[/b]\n[font_size=16]%s[/font_size][/center]" % [run.field_index, ev.get("name", ""), ev.get("desc", "")])


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

	overlay = ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.6)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(overlay)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	var box := PanelContainer.new()
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
		margin.add_theme_constant_override("margin_" + side, 20)
	box.add_child(margin)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 16)
	margin.add_child(v)
	overlay_text = RichTextLabel.new()
	overlay_text.bbcode_enabled = true
	overlay_text.fit_content = true
	overlay_text.scroll_active = false
	overlay_text.add_theme_font_size_override("normal_font_size", 16)
	overlay_text.add_theme_font_size_override("bold_font_size", 16)
	v.add_child(overlay_text)
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
	_refresh_side()
	_refresh_hand()
	_refresh_hint()
	undo_btn.disabled = not run.can_undo() or busy
	var last: bool = run.turn >= int(data.run["turns_per_field"])
	end_btn.text = "%s\n(Пробел)" % ("Ход земли и итог" if last else "Ход земли")
	end_btn.disabled = busy or run.game_over


func _refresh_info() -> void:
	_clear(info_box)
	var sc: Dictionary = run.score()

	var head := HBoxContainer.new()
	head.add_child(_label("Поле %d/%d" % [run.field_index, int(data.run["fields_to_win"])], 24, Color.WHITE))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	head.add_child(_label("Ход %d/%d" % [run.turn, int(data.run["turns_per_field"])], 24, LAND_COLOR))
	info_box.add_child(head)

	# Жизни: полупрозрачные сердца — столько снимет текущее недовольство
	var hearts := HBoxContainer.new()
	hearts.add_theme_constant_override("separation", 0)
	var heart: Texture2D = _icon_tex("res://assets/icons/heart.svg")
	var danger := int(sc["discontent"])
	for k in int(data.run["lives"]):
		var tr := _icon_rect(heart, 26)
		if k >= run.lives:
			tr.modulate = Color(0.3, 0.3, 0.3, 0.5)
		elif k >= run.lives - danger:
			tr.modulate = Color(1, 1, 1, 0.35)
		hearts.add_child(tr)
	info_box.add_child(hearts)
	if danger > 0:
		info_box.add_child(_rich_line("[color=#ff8080]Разные цвета рядом: −%d%s в конце поля[/color]" % [danger, _heart_img(16)], 15))

	# Земля: название и что она сделает сейчас (полное описание — в подсказке)
	var ev: Dictionary = run.event_info()
	var lb := _section(info_box, ev.get("name", ""), LAND_COLOR, 19)
	lb.get_parent().tooltip_text = ev.get("desc", "")
	lb.get_parent().mouse_filter = Control.MOUSE_FILTER_PASS
	lb.add_child(_rich_line(LandEvents.describe(run.intent), 15))

	# Задание поля
	var prog: Dictionary = run.task_progress(sc)
	var all_ok := true
	for r in prog:
		if prog[r]["have"] < prog[r]["need"]:
			all_ok = false
	var tb := _section(info_box, "Задание", Color("#6fcf97") if all_ok else Color("#f2c94c"), 19)
	for r in prog:
		tb.add_child(_progress_row(r, prog[r]["have"], prog[r]["need"]))

	# Глобальная угроза
	var g: Dictionary = run.global_threat()
	var left: int = run.global_end_field() - run.field_index
	var when := "это поле!" if left == 0 else "ещё %d %s" % [left + 1, _plural(left + 1, "поле", "поля", "полей")]
	var gb := _section(info_box, "%s · %s" % [g["name"], when], Color("#eb5757"), 19)
	gb.get_parent().tooltip_text = "Весь доход этого ресурса за поля %d–%d. Не хватит — минус %d жизни." % [run.global_start, run.global_end_field(), int(g.get("penalty", 3))]
	gb.get_parent().mouse_filter = Control.MOUSE_FILTER_PASS
	var cur := int(run.global_progress) + int(sc["total"].get(g["resource"], 0))
	gb.add_child(_progress_row(g["resource"], cur, int(g["need"])))

func _refresh_side() -> void:
	_clear(side_box)
	var nf: Dictionary = run.next_field
	var sb := _section(side_box, "Дальше", Color("#8ab4f8"), 19)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	sb.add_child(row)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 2)
	grid.add_theme_constant_override("v_separation", 2)
	row.add_child(grid)
	var f = nf["field"]
	for i in LandField.N:
		var cell := PanelContainer.new()
		cell.custom_minimum_size = Vector2(20, 20)
		var st := StyleBoxFlat.new()
		st.set_corner_radius_all(3)
		st.bg_color = Color("#5d7a3a") if f.exists[i] else Color("#2a313b")
		cell.add_theme_stylebox_override("panel", st)
		if f.exists[i] and f.content[i] != "":
			var q := _label("?", 12, Color.WHITE)
			q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			cell.add_child(q)
		grid.add_child(cell)
	var nev: Dictionary = data.events.get(nf["event"], {})
	var res_icons := ""
	for r in nf["task"]:
		res_icons += _img(r, 26) + " "
	var info := _rich_line("[color=#c58cff]%s[/color]\n%s" % [nev.get("name", ""), res_icons], 15)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)

	var help_btn := Button.new()
	help_btn.text = "Скрыть правила (H)" if show_rules else "Правила (H)"
	help_btn.focus_mode = Control.FOCUS_NONE
	help_btn.custom_minimum_size = Vector2(0, 36)
	help_btn.pressed.connect(_toggle_rules)
	side_box.add_child(help_btn)
	if not show_rules:
		return
	var rb := _section(side_box, "Правила", Color("#8a96a3"), 16)
	var food := _img("food", 16)
	var gold := _img("gold", 16)
	var force := _img("force", 16)
	var t := ""
	t += "Здание: [b]+1[/b] своего цвета.\n"
	t += "[color=#ffd866]+2[/color] за сторону с другим зданием своего цвета:\n  Поле+Мельница %s\n  Шахта+Кузница %s\n  Казарма+Башня %s\n" % [food, gold, force]
	t += "Дом: +1 каждому соседу, не ссорится.\n"
	t += "[color=#ff8080]Разные цвета рядом: −1%s[/color] в конце поля.\n" % _heart_img(14)
	t += "Не хватило задания: −1%s за штуку.\n" % _heart_img(14)
	t += "Озеро: +1%s соседям.\n" % food
	t += "Логово выключает здание по стрелке, %s рядом сносит его.\n" % force
	t += "Излишки идут на следующее поле.\n"
	t += "[color=#8a96a3]1–4 карта, ПКМ снять, Z отмена[/color]"
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
	var title := _label(data.obj_name(id), 20, Color.WHITE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	var t := ""
	if col == "grey":
		t = "[b]+1[/b]%s%s%s [color=#a9b4c0]соседям[/color]" % [_img("food", 20), _img("gold", 20), _img("force", 20)]
	else:
		var partners := []
		for p in data.pair_partners(id):
			partners.append(data.objects[p].get("with", data.obj_name(p)))
		t = "[b]+1[/b]%s  [color=#ffd866][b]+2[/b][/color]%s [b]%s[/b]" % [_img(col, 22), _img(col, 20), ", ".join(partners)]
	var stats := _rich_line("[center]%s[/center]" % t, 15)
	v.add_child(stats)
	return btn

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
	if busy:
		s = "[color=#c58cff]Ходит земля…[/color]"
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


func _unhandled_input(event: InputEvent) -> void:
	if overlay.visible or busy:
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
			KEY_SPACE, KEY_ENTER:
				_on_end_turn()


func _try_place(cell: int) -> void:
	if selected < 0 or not run.can_place(selected, cell):
		return
	var before: Dictionary = run.score()
	var r: Dictionary = run.place(selected, cell)
	if not r["ok"]:
		return
	selected = -1
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


func _cell_at(screen_pos: Vector2) -> int:
	var from := camera.project_ray_origin(screen_pos)
	var dir := camera.project_ray_normal(screen_pos)
	if absf(dir.y) < 0.0001:
		return -1
	var t := -from.y / dir.y
	if t < 0:
		return -1
	var p := from + dir * t
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
	if busy or overlay.visible or run.game_over:
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
	var dur := _animate_land(r.get("land", {}))
	if dur > 0.0:
		await get_tree().create_timer(dur + 0.15).timeout
	busy = false
	_full_refresh()
	if r.get("field_done", false):
		_show_field_result(r["result"])


func _show_field_result(res: Dictionary) -> void:
	var s := "[center][b][font_size=24]Поле %d завершено[/font_size][/b][/center]\n\n" % run.field_index
	s += "Доход поля: %s\n" % _fmt(res["prod"], true)
	var task_line := []
	for r in res["task"]:
		var have := int(res["prod"].get(r, 0)) + int(res["carry_in"].get(r, 0))
		task_line.append("%d/%d%s" % [mini(have, int(res["task"][r])), int(res["task"][r]), _img(r)])
	s += "Задание: %s" % "  ".join(task_line)
	if res["missing"] > 0:
		s += "  [color=#eb5757]не хватило %d → −%d%s[/color]\n" % [res["missing"], res["missing"], _heart_img()]
	else:
		s += "  [color=#6fcf97]выполнено[/color]\n"
	if res["discontent"] > 0:
		s += "[color=#eb5757]Недовольство: −%d%s[/color]\n" % [res["discontent"], _heart_img()]
	else:
		s += "[color=#6fcf97]Без недовольства[/color]\n"
	var co: Dictionary = res["carry_out"]
	var any_carry := false
	for r in co:
		if int(co[r]) > 0:
			any_carry = true
	if any_carry:
		s += "Излишки на следующее поле: %s\n" % _fmt(co)
	if res.get("global_checked", false):
		var g: Dictionary = res["global"]
		if res["global_passed"]:
			s += "\n[color=#6fcf97][b]Угроза «%s» отбита![/b][/color] (%d/%d%s)\n" % [g["name"], res["global_progress"], g["need"], _img(g["resource"])]
		else:
			s += "\n[color=#eb5757][b]Угроза «%s» не отбита[/b][/color] (%d/%d%s): −%d%s\n" % [g["name"], res["global_progress"], g["need"], _img(g["resource"]), int(g.get("penalty", 3)), _heart_img()]
	s += "\nЖизни: %d → [b]%d[/b]%s" % [res["lives_before"], res["lives_after"], _heart_img()]

	_clear(overlay_buttons)
	if run.victory:
		s += "\n\n[center][b][font_size=26][color=#f2c94c]Победа! Земля покорена.[/color][/font_size][/b][/center]"
		_overlay_button("Новый забег", _new_run)
	elif run.game_over:
		s += "\n\n[center][b][font_size=26][color=#eb5757]Забег окончен[/color][/font_size][/b]\nПолей пройдено: %d[/center]" % run.field_index
		_overlay_button("Новый забег", _new_run)
	else:
		s += "\n\n[center][b]Выберите карту в колоду или отдохните:[/b][/center]"
		for i in run.reward_options.size():
			_reward_button(run.reward_options[i], _on_reward.bind(i))
		_overlay_button("Отдых: +%d жизнь" % int(data.run.get("rest_heal", 1)), _on_reward.bind(-1))
	_show_overlay(s)


func _reward_button(id: String, cb: Callable) -> void:
	var col: String = data.color_of(id)
	var b := Button.new()
	b.custom_minimum_size = Vector2(130, 70)
	b.focus_mode = Control.FOCUS_NONE
	b.text = data.obj_name(id)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#232b38")
	sb.border_color = Color(_res_color(col))
	sb.set_border_width_all(2)
	sb.border_width_top = 8
	sb.set_corner_radius_all(6)
	b.add_theme_stylebox_override("normal", sb)
	var sh := sb.duplicate()
	sh.bg_color = Color("#34404f")
	b.add_theme_stylebox_override("hover", sh)
	b.pressed.connect(cb)
	overlay_buttons.add_child(b)


func _on_reward(i: int) -> void:
	run.choose_reward(i)
	_hide_overlay()
	_full_refresh()
	_announce_field()


func _show_overlay(text: String) -> void:
	overlay_text.text = text
	overlay.visible = true


func _hide_overlay() -> void:
	overlay.visible = false


func _overlay_button(text: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(150, 70)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	overlay_buttons.add_child(b)
