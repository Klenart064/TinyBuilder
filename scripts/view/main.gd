## Главная сцена прототипа: 3D-поле с ортокамерой и интерфейс поверх.
## Вся логика игры — в scripts/core, здесь только отображение и ввод.
extends Node3D

const GameData = preload("res://scripts/core/game_data.gd")
const RunState = preload("res://scripts/core/run_state.gd")
const Board = preload("res://scripts/core/board.gd")
const ComboBook = preload("res://scripts/core/combo_book.gd")

const CELL_STEP := 1.15
const TILE_COLOR := Color("#5d7a3a")
const TILE_FREE_COLOR := Color("#7fa04f")
const TILE_HOVER_COLOR := Color("#a8cf6a")
const TILE_BAD_COLOR := Color("#7a4a3a")
const TILE_COMBO_COLOR := Color("#e8c547")
const COMBO_LINK_COLOR := Color("#ffd866")

var data
var run
var book = ComboBook.new()

var selected := -1
var hover_cell := -1

# 3D
var camera: Camera3D
var tiles: Array = []
var tile_materials: Array = []
var building_nodes: Array = []
var building_ids: Array = []
var yield_labels: Array = []
var ghost: Node3D
var ghost_id := ""
var combo_links: Node3D
var preview_links: Node3D
## Предпросмотр для выбранной карты: клетка -> {"delta": {}, "combo": bool}
var preview_by_cell: Dictionary = {}
## Клетки-партнёры комбо, которые сработают при постановке в клетку под курсором.
var hover_partners: Array = []

# UI
var info_text: RichTextLabel
var rules_text: RichTextLabel
var hint_text: RichTextLabel
var hand_box: HBoxContainer
var undo_btn: Button
var finish_btn: Button
var overlay: Control
var overlay_text: RichTextLabel
var overlay_buttons: HBoxContainer
var toast: Label


func _ready() -> void:
	data = GameData.new()
	if not data.load_all():
		push_error("Ошибка в файлах data/*.json — смотрите вывод выше")
	run = RunState.new()
	book.load_book()
	_build_world()
	_build_ui()
	_new_run()


func _new_run() -> void:
	run.start(data)
	selected = -1
	_hide_overlay()
	_refresh()


# ---------------------------------------------------------------- 3D мир

func _build_world() -> void:
	var env_node := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#27303b")
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
	camera.size = 7.4
	add_child(camera)
	camera.position = Vector3(7, 8, 7)
	camera.look_at(Vector3(1.0, 0, 1.0), Vector3.UP)

	# Подложка под поле
	var base := MeshInstance3D.new()
	var base_mesh := BoxMesh.new()
	base_mesh.size = Vector3(CELL_STEP * 3 + 0.3, 0.3, CELL_STEP * 3 + 0.3)
	base.mesh = base_mesh
	base.position = Vector3(0, -0.3, 0)
	base.material_override = _mat(Color("#3d4a2a"))
	add_child(base)

	for i in Board.CELL_COUNT:
		var tile := MeshInstance3D.new()
		var m := BoxMesh.new()
		m.size = Vector3(1.05, 0.2, 1.05)
		tile.mesh = m
		tile.position = cell_pos(i) + Vector3(0, -0.1, 0)
		var mat := _mat(TILE_COLOR)
		tile.material_override = mat
		add_child(tile)
		tiles.append(tile)
		tile_materials.append(mat)

		var lbl := Label3D.new()
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.no_depth_test = true
		lbl.render_priority = 5
		lbl.font_size = 34
		lbl.outline_size = 14
		lbl.outline_modulate = Color(0, 0, 0, 0.85)
		lbl.pixel_size = 0.006
		lbl.position = cell_pos(i) + Vector3(0, 1.05, 0)
		add_child(lbl)
		yield_labels.append(lbl)

		building_nodes.append(null)
		building_ids.append("")

	combo_links = Node3D.new()
	add_child(combo_links)
	preview_links = Node3D.new()
	add_child(preview_links)


func cell_pos(i: int) -> Vector3:
	return Vector3((i % Board.SIZE - 1) * CELL_STEP, 0, (i / Board.SIZE - 1) * CELL_STEP)


func _mat(color: Color, alpha: float = 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(color, alpha)
	m.roughness = 0.9
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m


func _add_mesh(parent: Node3D, mesh: Mesh, pos: Vector3, color: Color, alpha: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.material_override = _mat(color, alpha)
	parent.add_child(mi)
	return mi


## Простая «кубиковая» модель здания по полям shape/color/height из cards.json.
func _make_building(id: String, alpha: float = 1.0) -> Node3D:
	var b: Dictionary = data.buildings[id]
	var root := Node3D.new()
	var color := Color(b.get("color", "#cccccc"))
	var h := float(b.get("height", 0.5))
	match b.get("shape", "box"):
		"flat":
			var m := BoxMesh.new()
			m.size = Vector3(0.95, h, 0.95)
			_add_mesh(root, m, Vector3(0, h / 2, 0), color, alpha)
			for k in 3:  # борозды
				var s := BoxMesh.new()
				s.size = Vector3(0.9, 0.03, 0.08)
				_add_mesh(root, s, Vector3(0, h + 0.015, -0.3 + k * 0.3), color.darkened(0.25), alpha)
		"house":
			var m := BoxMesh.new()
			m.size = Vector3(0.7, h, 0.55)
			_add_mesh(root, m, Vector3(0, h / 2, 0), color, alpha)
			var roof := PrismMesh.new()
			roof.size = Vector3(0.8, 0.35, 0.65)
			_add_mesh(root, roof, Vector3(0, h + 0.175, 0), Color("#8a3b2a"), alpha)
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
			_add_mesh(root, top, Vector3(0, h + 0.175, 0), Color("#6b2f2f"), alpha)
		"mill":
			var m := CylinderMesh.new()
			m.top_radius = 0.22
			m.bottom_radius = 0.32
			m.height = h
			_add_mesh(root, m, Vector3(0, h / 2, 0), color, alpha)
			for k in 2:
				var blade := BoxMesh.new()
				blade.size = Vector3(0.9, 0.08, 0.04)
				var bi := _add_mesh(root, blade, Vector3(0, h * 0.8, 0.26), Color("#f0e6d0"), alpha)
				bi.rotation_degrees = Vector3(0, 0, 45 + 90 * k)
		"rock":
			var m := SphereMesh.new()
			m.radius = 0.42
			m.height = 0.6
			_add_mesh(root, m, Vector3(0.05, 0.2, 0), color, alpha)
			var m2 := SphereMesh.new()
			m2.radius = 0.25
			m2.height = 0.4
			_add_mesh(root, m2, Vector3(-0.25, 0.15, 0.25), color.lightened(0.1), alpha)
		_:
			var m := BoxMesh.new()
			m.size = Vector3(0.75, h, 0.75)
			_add_mesh(root, m, Vector3(0, h / 2, 0), color, alpha)
	return root


func _sync_buildings() -> void:
	for i in Board.CELL_COUNT:
		var id: String = run.board.cells[i]
		if building_ids[i] == id:
			continue
		if building_nodes[i] != null:
			building_nodes[i].queue_free()
			building_nodes[i] = null
		building_ids[i] = id
		if id != "":
			var node := _make_building(id)
			node.position = cell_pos(i)
			add_child(node)
			building_nodes[i] = node


func _update_ghost() -> void:
	var want := ""
	if selected >= 0 and selected < run.hand.size() and run.board.is_free(hover_cell):
		want = run.hand[selected]
	if want != ghost_id:
		if ghost != null:
			ghost.queue_free()
			ghost = null
		ghost_id = want
		if want != "":
			ghost = _make_building(want, 0.55)
			add_child(ghost)
	if ghost != null:
		ghost.position = cell_pos(hover_cell)


func _update_tiles() -> void:
	_update_hover_partners()
	for i in Board.CELL_COUNT:
		var c := TILE_COLOR
		if selected >= 0 and run.board.is_free(i):
			c = TILE_FREE_COLOR
			if preview_by_cell.get(i, {}).get("combo", false):
				c = TILE_FREE_COLOR.lerp(TILE_COMBO_COLOR, 0.45)
			if i == hover_cell:
				c = TILE_HOVER_COLOR
		elif selected >= 0 and i == hover_cell:
			c = TILE_BAD_COLOR
		if i in hover_partners:
			c = TILE_COMBO_COLOR
		tile_materials[i].albedo_color = c


## Считает, что даст выбранная карта в каждой свободной клетке.
func _update_preview() -> void:
	preview_by_cell = {}
	if selected < 0 or selected >= run.hand.size():
		return
	var id: String = run.hand[selected]
	var base_sum := 0
	for res in data.buildings[id].get("yield", {}):
		base_sum += int(data.buildings[id]["yield"][res])
	for i in run.board.free_cells():
		var d: Dictionary = run.board.preview_delta(data, i, id)
		var total := 0
		for res in d:
			total += int(d[res])
		preview_by_cell[i] = {"delta": d, "combo": total > base_sum}


## Какие клетки-соседи «включатся», если поставить выбранную карту под курсор.
func _update_hover_partners() -> void:
	hover_partners = []
	for c in preview_links.get_children():
		c.queue_free()
	if selected < 0 or selected >= run.hand.size() or not run.board.is_free(hover_cell):
		return
	var before := _combo_keys(run.production())
	run.board.cells[hover_cell] = run.hand[selected]
	var after: Dictionary = run.production()
	run.board.cells[hover_cell] = ""
	for i in Board.CELL_COUNT:
		for c in after["cells"][i]["combos"]:
			if before.has(_combo_key(i, c)):
				continue
			for p in c["partners"]:
				preview_links.add_child(_link_mesh(i, p, 0.16, 0.2, _glow_mat(COMBO_LINK_COLOR, 0.75)))
			for p in [i] + c["partners"]:
				if p != hover_cell and not (p in hover_partners):
					hover_partners.append(p)


func _combo_key(cell: int, c: Dictionary) -> String:
	return "%d:%s:%s" % [cell, c["id"], str(c["bonus"])]


func _combo_keys(prod: Dictionary) -> Dictionary:
	var keys := {}
	for i in Board.CELL_COUNT:
		for c in prod["cells"][i]["combos"]:
			keys[_combo_key(i, c)] = true
	return keys


func _update_yield_labels() -> void:
	var prod: Dictionary = run.production()
	for i in Board.CELL_COUNT:
		var y: Dictionary = prod["cells"][i]["yield"]
		var lines := []
		var col := Color.WHITE
		for res in data.resources:
			var v := int(y.get(res, 0))
			if v != 0:
				if lines.is_empty():
					col = Color(data.resources[res]["color"])
				lines.append("+%d %s" % [v, data.resources[res]["short"]])
		if preview_by_cell.has(i):
			var d: Dictionary = preview_by_cell[i]["delta"]
			lines = []
			for res in data.resources:
				var v := int(d.get(res, 0))
				if v != 0:
					lines.append("%s%d %s" % ["+" if v > 0 else "", v, data.resources[res]["short"]])
			col = Color(1, 0.9, 0.4, 0.95) if preview_by_cell[i]["combo"] else Color(1, 1, 1, 0.6)
		yield_labels[i].text = "\n".join(lines)
		yield_labels[i].modulate = col
		var h := 1.05
		if preview_by_cell.has(i):
			h = 1.6 if i == hover_cell else 0.45
		yield_labels[i].position = cell_pos(i) + Vector3(0, h, 0)
	_update_combo_links(prod)


## Постоянные золотые дорожки между зданиями, у которых сработало комбо.
func _update_combo_links(prod: Dictionary) -> void:
	for c in combo_links.get_children():
		c.queue_free()
	var done := {}
	for i in Board.CELL_COUNT:
		for c in prod["cells"][i]["combos"]:
			for p in c["partners"]:
				var key := "%d-%d" % [mini(i, p), maxi(i, p)]
				if done.has(key):
					continue
				done[key] = true
				combo_links.add_child(_link_mesh(i, p, 0.1, 0.03, _glow_mat(COMBO_LINK_COLOR, 0.9)))


func _link_mesh(a: int, b: int, width: float, y: float, mat: Material) -> MeshInstance3D:
	var pa := cell_pos(a)
	var pb := cell_pos(b)
	var mi := MeshInstance3D.new()
	var m := BoxMesh.new()
	var horizontal := absf(pa.x - pb.x) > 0.01
	var length := pa.distance_to(pb)
	m.size = Vector3(length if horizontal else width, 0.04, width if horizontal else length)
	mi.mesh = m
	mi.position = (pa + pb) / 2 + Vector3(0, y, 0)
	mi.material_override = mat
	return mi


func _glow_mat(color: Color, alpha: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(color, alpha)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m


# ---------------------------------------------------------------- Эффекты

## После постановки: вылетающие числа, вспышка связей, открытие новых комбо.
func _play_combo_effects(before: Dictionary, placed_cell: int) -> void:
	var after: Dictionary = run.production()
	var before_keys := _combo_keys(before)
	var delay := 0.0
	for i in Board.CELL_COUNT:
		var d := {}
		for res in data.resources:
			var v := int(after["cells"][i]["yield"].get(res, 0)) - int(before["cells"][i]["yield"].get(res, 0))
			if v != 0:
				d[res] = v
		if d.is_empty():
			continue
		var is_combo := false
		for c in after["cells"][i]["combos"]:
			if not before_keys.has(_combo_key(i, c)):
				is_combo = true
				for p in c["partners"]:
					_flash_link(i, p)
					_flash_tile(p)
		if is_combo:
			_flash_tile(i)
		_float_number(i, d, delay, is_combo)
		delay += 0.12
	var ids := []
	for i in Board.CELL_COUNT:
		for c in after["cells"][i]["combos"]:
			ids.append(c["id"])
	var fresh: Array = book.discover(ids)
	if not fresh.is_empty():
		book.save_book()
		var names := []
		for rule in data.combos:
			if data.combo_id(rule) in fresh:
				names.append(rule.get("text", ""))
		_show_toast("Новое комбо в книге!\n" + "\n".join(names))


func _float_number(cell: int, amounts: Dictionary, delay: float, big: bool) -> void:
	var lbl := Label3D.new()
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.no_depth_test = true
	lbl.render_priority = 10
	lbl.font_size = 64 if big else 44
	lbl.outline_size = 18
	lbl.outline_modulate = Color(0, 0, 0, 0.9)
	lbl.pixel_size = 0.006
	var lines := []
	var col := Color.WHITE
	for res in amounts:
		if lines.is_empty():
			col = Color(data.resources[res]["color"])
		lines.append("%s%d %s" % ["+" if amounts[res] > 0 else "", amounts[res], data.resources[res]["short"]])
	lbl.text = "\n".join(lines)
	lbl.modulate = Color(col, 0.0)
	var start := cell_pos(cell) + Vector3(0, 0.9, 0)
	lbl.position = start
	add_child(lbl)
	var t := create_tween()
	t.tween_interval(delay)
	t.tween_property(lbl, "modulate:a", 1.0, 0.08)
	t.parallel().tween_property(lbl, "scale", Vector3.ONE * (1.35 if big else 1.1), 0.12).from(Vector3.ONE * 0.5)
	t.tween_property(lbl, "scale", Vector3.ONE, 0.15)
	t.parallel().tween_property(lbl, "position", start + Vector3(0, 1.2, 0), 1.2).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	t.parallel().tween_property(lbl, "modulate:a", 0.0, 0.5).set_delay(0.8)
	t.tween_callback(lbl.queue_free)


func _flash_link(a: int, b: int) -> void:
	var mat := _glow_mat(Color.WHITE, 1.0)
	var mi := _link_mesh(a, b, 0.22, 0.25, mat)
	add_child(mi)
	var t := create_tween()
	t.tween_property(mat, "albedo_color", Color(COMBO_LINK_COLOR, 0.0), 0.9).set_ease(Tween.EASE_IN)
	t.tween_callback(mi.queue_free)


func _flash_tile(cell: int) -> void:
	var mi := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = Vector3(1.1, 0.02, 1.1)
	mi.mesh = m
	mi.position = cell_pos(cell) + Vector3(0, 0.02, 0)
	var mat := _glow_mat(COMBO_LINK_COLOR, 0.8)
	mi.material_override = mat
	add_child(mi)
	var t := create_tween()
	t.tween_property(mat, "albedo_color:a", 0.0, 0.7)
	t.tween_callback(mi.queue_free)


func _show_toast(text: String) -> void:
	toast.text = text
	toast.visible = true
	toast.modulate.a = 1.0
	var t := create_tween()
	t.tween_interval(2.2)
	t.tween_property(toast, "modulate:a", 0.0, 0.6)
	t.tween_callback(func(): toast.visible = false)


# ---------------------------------------------------------------- Интерфейс

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)

	# Левая панель: поле, задание, угроза, запасы
	var left := _panel(root, 380)
	left.position = Vector2(12, 12)
	info_text = _rich(left)

	# Правая панель: правила комбо
	var right := _panel(root, 320)
	right.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	right.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 12)
	rules_text = _rich(right)
	rules_text.add_theme_font_size_override("normal_font_size", 13)

	# Нижняя часть: подсказка, рука, кнопки
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
	hint_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
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
	spacer.custom_minimum_size = Vector2(30, 0)
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(spacer)

	var buttons := VBoxContainer.new()
	buttons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	buttons.alignment = BoxContainer.ALIGNMENT_END
	row.add_child(buttons)
	undo_btn = Button.new()
	undo_btn.text = "Отменить (Z)"
	undo_btn.custom_minimum_size = Vector2(170, 44)
	undo_btn.pressed.connect(_on_undo)
	buttons.add_child(undo_btn)
	finish_btn = Button.new()
	finish_btn.text = "Завершить поле (Пробел)"
	finish_btn.custom_minimum_size = Vector2(170, 56)
	finish_btn.pressed.connect(_on_finish)
	buttons.add_child(finish_btn)

	# Оверлей итогов
	overlay = ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.55)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(overlay)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	var box := PanelContainer.new()
	box.custom_minimum_size = Vector2(520, 0)
	var box_sb := StyleBoxFlat.new()
	box_sb.bg_color = Color("#1d2430")
	box_sb.border_color = Color("#f2c94c")
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
	v.add_child(overlay_text)
	overlay_buttons = HBoxContainer.new()
	overlay_buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	overlay_buttons.add_theme_constant_override("separation", 10)
	v.add_child(overlay_buttons)
	overlay.visible = false

	toast = Label.new()
	toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 24)
	toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast.add_theme_font_size_override("font_size", 20)
	toast.add_theme_color_override("font_color", Color("#ffd866"))
	toast.add_theme_constant_override("outline_size", 8)
	toast.add_theme_color_override("font_outline_color", Color.BLACK)
	toast.visible = false
	root.add_child(toast)


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


func _rich(parent: PanelContainer) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	r.custom_minimum_size = Vector2(parent.custom_minimum_size.x - 24, 0)
	parent.add_child(r)
	return r


static func _plural(n: int, one: String, few: String, many: String) -> String:
	var m10 := n % 10
	var m100 := n % 100
	if m10 == 1 and m100 != 11:
		return one
	if m10 >= 2 and m10 <= 4 and (m100 < 10 or m100 >= 20):
		return few
	return many


func _res_color(res: String) -> String:
	return data.resources.get(res, {}).get("color", "#ffffff")


## Ресурсы цветным текстом: «[color]12 еды[/color], ...»
func _fmt(amounts: Dictionary, plus: bool = false, show_zero: bool = false) -> String:
	var parts := []
	for res in data.resources:
		if not amounts.has(res) and not show_zero:
			continue
		var v := int(amounts.get(res, 0))
		if v == 0 and not show_zero:
			continue
		parts.append("[color=%s]%s%d %s[/color]" % [_res_color(res), "+" if plus and v > 0 else "", v, data.resources[res]["short"]])
	return ", ".join(parts) if not parts.is_empty() else "ничего"


func _refresh() -> void:
	if selected >= run.hand.size():
		selected = -1
	_sync_buildings()
	_update_preview()
	_update_tiles()
	_update_ghost()
	_update_yield_labels()
	_refresh_info()
	_refresh_hand()
	_refresh_hint()
	undo_btn.disabled = not run.can_undo()


func _refresh_info() -> void:
	var total: Dictionary = run.production()["total"]
	var g: Dictionary = run.goal
	var progress := int(total.get(g["resource"], 0))
	var done := progress >= int(g["target"])
	var t: Dictionary = run.current_threat()
	var s := "[b][font_size=20]Поле %d[/font_size][/b]\n" % run.field_number
	s += "[b]Запасы:[/b] %s\n\n" % _fmt(run.stock, false, true)
	s += "[b]Доход этого поля:[/b] %s\n" % _fmt(total, true)
	s += "[b]Задание:[/b] производство [color=%s]%s[/color] на этом поле ≥ %d  (%d/%d) %s\n" % [
		_res_color(g["resource"]), data.resources[g["resource"]]["short"], g["target"], progress, g["target"],
		"[color=#6fcf97]✔[/color]" if done else ""]
	s += "     награда: %s\n\n" % _fmt(g["reward"], true)
	if not t.is_empty():
		var need: Dictionary = t["need"]
		var parts := []
		for res in need:
			var have := int(run.stock.get(res, 0))
			var ok := have >= int(need[res])
			parts.append("[color=%s]%d/%d %s[/color]%s" % [_res_color(res), have, need[res], data.resources[res]["short"], " ✔" if ok else ""])
		var when := "после этого поля!" if run.fields_until_threat == 1 else "через %d %s" % [run.fields_until_threat, _plural(run.fields_until_threat, "поле", "поля", "полей")]
		s += "[b][color=#eb5757]Угроза %d/%d: %s[/color][/b] — %s\n" % [run.threat_index + 1, data.run["threats"].size(), t["name"], when]
		s += "Нужно в запасах: %s\n" % ", ".join(parts)
	s += "\n[color=#8a96a3]В колоде: %d в доборе, %d в сбросе[/color]" % [run.deck.draw_pile.size(), run.deck.discard_pile.size()]
	info_text.text = s

	var known := 0
	var book_lines := ""
	for rule in data.combos:
		if book.is_known(data.combo_id(rule)):
			known += 1
			book_lines += "[color=#ffd866]★[/color] %s\n" % rule.get("text", "")
		else:
			book_lines += "[color=#6b7683]☆ %s + ???[/color]\n" % data.building_name(rule["building"])
	var r := "[b]Книга комбо[/b] %d/%d\n[color=#8a96a3]соседи — только по сторонам[/color]\n" % [known, data.combos.size()]
	r += book_lines
	r += "\n[b]Базовый доход[/b]\n"
	for id in data.buildings:
		var b: Dictionary = data.buildings[id]
		if b.get("blocked", false):
			continue
		r += "%s: %s\n" % [b["name"], _fmt(b.get("yield", {}), true)]
	r += "\n[color=#8a96a3]ЛКМ по карте/1–5 — выбрать, ЛКМ по клетке — построить, ПКМ/Esc — снять выбор[/color]"
	rules_text.text = r


func _refresh_hand() -> void:
	for c in hand_box.get_children():
		c.queue_free()
	for i in run.hand.size():
		hand_box.add_child(_card_button(i, run.hand[i]))


func _card_button(i: int, id: String) -> Button:
	var b: Dictionary = data.buildings[id]
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(170, 170)
	btn.focus_mode = Control.FOCUS_NONE
	var res_col := Color(_res_color(b.get("resource", "")))
	for state in ["normal", "hover", "pressed", "focus"]:
		var sb := StyleBoxFlat.new()
		var sel := i == selected
		sb.bg_color = Color("#3a4656") if sel else Color("#1d2430")
		if state == "hover" and not sel:
			sb.bg_color = Color("#2a3442")
		sb.border_color = Color.WHITE if sel else res_col
		sb.set_border_width_all(4 if sel else 2)
		sb.border_width_top = 10
		sb.set_corner_radius_all(8)
		if sel:
			sb.expand_margin_top = 12
		btn.add_theme_stylebox_override(state, sb)
	btn.pressed.connect(_select.bind(i))

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 8)
	margin.add_theme_constant_override("margin_top", 14)
	btn.add_child(margin)
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", 3)
	margin.add_child(v)

	var title := _card_label("[%d] %s" % [i + 1, b["name"]], 15, Color.WHITE)
	v.add_child(title)
	v.add_child(_card_label(data.format_amounts(b.get("yield", {})) if not b.get("yield", {}).is_empty() else "сама ничего", 12, res_col))
	var partners: Array = data.partners_of(id)
	if not partners.is_empty():
		v.add_child(_card_label("Комбо с:", 11, Color("#8a96a3")))
	for p in partners:
		var row := HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_theme_constant_override("separation", 5)
		var chip := ColorRect.new()
		chip.color = Color(data.buildings[p["id"]].get("color", "#ffffff"))
		chip.custom_minimum_size = Vector2(12, 12)
		chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(chip)
		var rule: Dictionary = p["rule"]
		var gain: String = data.format_amounts(rule["bonus"])
		var txt: String
		if p["as_partner"]:
			txt = "%s получит %s" % [data.building_name(p["id"]), gain]
		else:
			var cnt := int(rule.get("min", 1))
			txt = "%s%s: %s%s" % [data.building_name(p["id"]), " ×%d" % cnt if cnt > 1 else "", gain, " за каждого" if rule.get("per", false) else ""]
		var l := _card_label(txt, 11, Color("#ffd866") if not p["as_partner"] else Color("#c9d1d9"))
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		v.add_child(row)
	return btn


func _card_label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _refresh_hint() -> void:
	var s := ""
	if selected >= 0 and selected < run.hand.size():
		var id: String = run.hand[selected]
		if run.board.is_free(hover_cell):
			var d: Dictionary = run.board.preview_delta(data, hover_cell, id)
			s = "%s сюда: доход поля %s" % [data.building_name(id), _fmt(d, true)]
		elif hover_cell >= 0:
			s = "[color=#eb5757]Клетка занята[/color]"
		else:
			s = "Выберите клетку для: %s" % data.building_name(id)
	elif hover_cell >= 0 and run.board.cells[hover_cell] != "":
		var notes: Array = run.production()["cells"][hover_cell]["notes"]
		s = data.building_name(run.board.cells[hover_cell])
		if run.board.prebuilt[hover_cell]:
			s += " (было на поле)"
		if not notes.is_empty():
			s += ": " + "; ".join(notes)
	elif run.hand.is_empty():
		s = "Карты кончились — завершите поле"
	else:
		s = "Выберите карту"
	hint_text.text = "[center]%s[/center]" % s


# ---------------------------------------------------------------- Ввод

func _select(i: int) -> void:
	if overlay.visible:
		return
	selected = -1 if selected == i else i
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if overlay.visible:
		return
	if event is InputEventMouseMotion:
		var c := _cell_at(event.position)
		if c != hover_cell:
			hover_cell = c
			_update_tiles()
			_update_ghost()
			_update_yield_labels()
			_refresh_hint()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			var c := _cell_at(event.position)
			var before: Dictionary = run.production()
			if selected >= 0 and run.place(selected, c):
				selected = -1
				_refresh()
				_play_combo_effects(before, c)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			selected = -1
			_refresh()
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1, KEY_2, KEY_3, KEY_4, KEY_5:
				var i: int = event.keycode - KEY_1
				if i < run.hand.size():
					_select(i)
			KEY_ESCAPE:
				selected = -1
				_refresh()
			KEY_Z:
				_on_undo()
			KEY_SPACE, KEY_ENTER:
				_on_finish()


func _cell_at(screen_pos: Vector2) -> int:
	var from := camera.project_ray_origin(screen_pos)
	var dir := camera.project_ray_normal(screen_pos)
	if absf(dir.y) < 0.0001:
		return -1
	var t := -from.y / dir.y
	if t < 0:
		return -1
	var p := from + dir * t
	var col := roundi(p.x / CELL_STEP) + 1
	var row := roundi(p.z / CELL_STEP) + 1
	if col < 0 or col >= Board.SIZE or row < 0 or row >= Board.SIZE:
		return -1
	var i := row * Board.SIZE + col
	var center := cell_pos(i)
	if absf(p.x - center.x) > 0.55 or absf(p.z - center.z) > 0.55:
		return -1
	return i


func _on_undo() -> void:
	if run.undo():
		_refresh()


func _on_finish() -> void:
	if overlay.visible or run.game_over:
		return
	selected = -1
	var rep: Dictionary = run.finish_field()
	var s := "[center][b][font_size=22]Поле %d завершено[/font_size][/b][/center]\n\n" % run.field_number
	s += "Доход: %s\n" % _fmt(rep["income"], true)
	var g: Dictionary = rep["goal"]
	if rep["goal_done"]:
		s += "[color=#6fcf97]Задание выполнено![/color] Награда: %s\n" % _fmt(g["reward"], true)
	else:
		s += "[color=#8a96a3]Задание не выполнено (%s ≥ %d)[/color]\n" % [data.resources[g["resource"]]["short"], g["target"]]
	if g.has("best"):
		var got := int(rep["income"].get(g["resource"], 0))
		if got >= int(g["best"]):
			s += "[color=#ffd866]Идеальная раскладка! %d %s — максимум для этой руки[/color]\n" % [got, data.resources[g["resource"]]["short"]]
		else:
			s += "[color=#8a96a3]Максимум с этой рукой: %d %s[/color]\n" % [g["best"], data.resources[g["resource"]]["short"]]
	if rep.has("threat"):
		var t: Dictionary = rep["threat"]
		if rep["threat_passed"]:
			s += "\n[color=#6fcf97][b]Угроза «%s» отбита![/b][/color] Потрачено: %s\n" % [t["name"], _fmt(t["need"])]
		else:
			s += "\n[color=#eb5757][b]Угроза «%s» не отбита.[/b][/color]\nНужно было: %s\n" % [t["name"], _fmt(t["need"])]
	s += "\nЗапасы: %s" % _fmt(run.stock, false, true)

	_clear_overlay_buttons()
	if run.victory:
		s += "\n\n[center][b][font_size=24][color=#f2c94c]Победа! Все угрозы отбиты.[/color][/font_size][/b][/center]"
		_overlay_button("Новый забег", _new_run)
	elif run.game_over:
		s += "\n\n[center][b][font_size=24][color=#eb5757]Забег окончен[/color][/font_size][/b]\nПолей пройдено: %d[/center]" % run.field_number
		_overlay_button("Новый забег", _new_run)
	elif not run.reward_options.is_empty():
		s += "\n\n[b]Выберите карту в колоду:[/b]"
		for i in run.reward_options.size():
			var id: String = run.reward_options[i]
			_overlay_button(data.building_name(id), _on_reward.bind(i))
	else:
		_overlay_button("Следующее поле", _on_next_field)
	_refresh()
	_show_overlay(s)


func _on_reward(i: int) -> void:
	run.choose_reward(i)
	_on_next_field()


func _on_next_field() -> void:
	run.next_field()
	_hide_overlay()
	_refresh()


func _show_overlay(text: String) -> void:
	overlay_text.text = text
	overlay.visible = true


func _hide_overlay() -> void:
	overlay.visible = false


func _clear_overlay_buttons() -> void:
	for c in overlay_buttons.get_children():
		c.queue_free()


func _overlay_button(text: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(150, 44)
	b.pressed.connect(cb)
	overlay_buttons.add_child(b)
