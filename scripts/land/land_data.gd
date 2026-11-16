## Данные прототипа «живой земли» из data/land/*.json.
## Баланс правится в JSON, код трогать не нужно.
extends RefCounted

var resources: Dictionary = {}
var objects: Dictionary = {}
var terrain: Dictionary = {}
var starter_deck: Dictionary = {}
var run: Dictionary = {}
var rules: Dictionary = {}
var events: Dictionary = {}  # id -> описание события
var colors: Array = []       # цвета-ресурсы без джокера


func load_all(dir: String = "res://data/land") -> bool:
	var cards = _read_json(dir.path_join("cards.json"))
	var run_file = _read_json(dir.path_join("run.json"))
	if cards == null or run_file == null:
		return false
	resources = cards["resources"]
	objects = cards["objects"]
	terrain = cards["terrain"]
	starter_deck = cards["starter_deck"]
	# Улучшенные карты: «field+» = копия «field» с полями из upgrade
	for id in objects.keys():
		var o: Dictionary = objects[id]
		if o.has("upgrade"):
			var up: Dictionary = o.duplicate(true)
			up.erase("upgrade")
			for k in o["upgrade"]:
				up[k] = o["upgrade"][k]
			up["name"] = o["name"] + "+"
			up["upgraded"] = true
			up["base_id"] = id
			objects[id + "+"] = up
	run = run_file
	rules = run_file["rules"]
	colors = []
	for r in resources:
		if not resources[r].get("wild", false):
			colors.append(r)
	events = {}
	for e in run_file["events"]:
		events[e["id"]] = e
	return validate()


func validate() -> bool:
	var ok := true
	for id in starter_deck:
		if not is_building(id):
			push_error("starter_deck: '%s' — не карта здания" % id)
			ok = false
	for key in ["prebuilt_pool", "buy_pool"]:
		for id in run.get(key, []):
			if not is_building(id):
				push_error("%s: '%s' — не карта здания" % [key, id])
				ok = false
	for id in objects:
		var c: String = objects[id].get("color", "")
		if kind(id) == "building" and c != "wild" and c != "city" and not resources.has(c):
			push_error("objects.%s: неизвестный цвет '%s'" % [id, c])
			ok = false
	for t in run.get("terrain_pool", {}):
		if not terrain.has(t):
			push_error("terrain_pool: неизвестная местность '%s'" % t)
			ok = false
	return ok


func kind(id: String) -> String:
	if id == "":
		return ""
	return objects.get(id, {}).get("kind", "")


func is_building(id: String) -> bool:
	return kind(id) == "building"


## Роль здания: base, workshop, housing, city.
func role(id: String) -> String:
	if not is_building(id):
		return ""
	return objects[id].get("role", "")


## Здание добычи или мастерская (у них есть цвет и они ссорятся с другими цветами).
func is_producer(id: String) -> bool:
	var r := role(id)
	return r == "base" or r == "workshop"


## food / gold / force / wild / city, "" для не-зданий.
func color_of(id: String) -> String:
	if not is_building(id):
		return ""
	return objects[id].get("color", "")


## Число из карты (base, self, per_base, wild, per_color, per_housing).
func val(id: String, key: String) -> int:
	return int(objects.get(id, {}).get(key, 0))


## «field+» → «field».
func base_id(id: String) -> String:
	return objects.get(id, {}).get("base_id", id)


func is_upgraded(id: String) -> bool:
	return objects.get(id, {}).get("upgraded", false)


func can_upgrade(id: String) -> bool:
	return objects.has(id + "+")


func obj_name(id: String) -> String:
	return objects.get(id, {}).get("name", id)


func zero_res() -> Dictionary:
	var d := {}
	for r in resources:
		d[r] = 0
	return d


## Партнёры: для мастерской — добыча её цвета, для добычи — мастерская её цвета.
func pair_partners(id: String) -> Array:
	var out := []
	var want := "base" if role(id) == "workshop" else ("workshop" if role(id) == "base" else "")
	if want == "":
		return out
	for other in objects:
		if role(other) == want and color_of(other) == color_of(id) and not is_upgraded(other):
			out.append(other)
	return out


static func _read_json(path: String) -> Variant:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("Не удалось открыть %s" % path)
		return null
	var json := JSON.new()
	var err := json.parse(f.get_as_text())
	if err != OK:
		push_error("%s:%d: %s" % [path, json.get_error_line(), json.get_error_message()])
		return null
	return json.data
