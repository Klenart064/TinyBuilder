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


func load_all(dir: String = "res://data/land") -> bool:
	var cards = _read_json(dir.path_join("cards.json"))
	var run_file = _read_json(dir.path_join("run.json"))
	if cards == null or run_file == null:
		return false
	resources = cards["resources"]
	objects = cards["objects"]
	terrain = cards["terrain"]
	starter_deck = cards["starter_deck"]
	run = run_file
	rules = run_file["rules"]
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
	for key in ["prebuilt_pool", "reward_pool"]:
		for id in run.get(key, []):
			if not is_building(id):
				push_error("%s: '%s' — не карта здания" % [key, id])
				ok = false
	for id in objects:
		var c: String = objects[id].get("color", "")
		if kind(id) == "building" and c != "grey" and not resources.has(c):
			push_error("objects.%s: неизвестный цвет '%s'" % [id, c])
			ok = false
	for t in run.get("terrain_pool", {}):
		if not terrain.has(t):
			push_error("terrain_pool: неизвестная местность '%s'" % t)
			ok = false
	for g in run.get("global_threats", []):
		if not resources.has(g.get("resource", "")):
			push_error("global_threats: неизвестный ресурс '%s'" % g.get("resource", ""))
			ok = false
	return ok


func kind(id: String) -> String:
	if id == "":
		return ""
	return objects.get(id, {}).get("kind", "")


func is_building(id: String) -> bool:
	return kind(id) == "building"


## food / gold / force / grey, "" для не-зданий.
func color_of(id: String) -> String:
	if not is_building(id):
		return ""
	return objects[id].get("color", "")


func obj_name(id: String) -> String:
	return objects.get(id, {}).get("name", id)


func zero_res() -> Dictionary:
	var d := {}
	for r in resources:
		d[r] = 0
	return d


## Цветные карты, кроме id, того же цвета (партнёры для пары).
func pair_partners(id: String) -> Array:
	var out := []
	var c := color_of(id)
	if c == "grey" or c == "":
		return out
	for other in objects:
		if other != id and color_of(other) == c:
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
