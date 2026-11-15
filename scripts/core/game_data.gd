## Загружает данные игры (здания, комбо, параметры забега) из JSON в res://data.
## Чтобы поменять баланс, правьте JSON — код трогать не нужно.
extends RefCounted

var resources: Dictionary = {}
var buildings: Dictionary = {}
var starter_deck: Dictionary = {}
var combos: Array = []
var run: Dictionary = {}


func load_all(dir: String = "res://data") -> bool:
	var cards = _read_json(dir.path_join("cards.json"))
	var combo_file = _read_json(dir.path_join("combos.json"))
	var run_file = _read_json(dir.path_join("run.json"))
	if cards == null or combo_file == null or run_file == null:
		return false
	resources = cards["resources"]
	buildings = cards["buildings"]
	starter_deck = cards["starter_deck"]
	combos = combo_file["combos"]
	run = run_file
	return validate()


## Проверяет, что все ссылки на здания и ресурсы существуют. Ошибки печатаются в консоль.
func validate() -> bool:
	var ok := true
	for id in starter_deck:
		if not buildings.has(id):
			push_error("starter_deck: неизвестное здание '%s'" % id)
			ok = false
	for key in ["prebuilt_pool", "reward_pool"]:
		for id in run.get(key, []):
			if not buildings.has(id):
				push_error("%s: неизвестное здание '%s'" % [key, id])
				ok = false
	for rule in combos:
		if not buildings.has(rule.get("building", "")):
			push_error("combos: неизвестное здание '%s'" % rule.get("building", ""))
			ok = false
		for n in neighbor_list(rule):
			if not buildings.has(n):
				push_error("combos: неизвестный сосед '%s'" % n)
				ok = false
		for res in rule.get("bonus", {}):
			if not resources.has(res):
				push_error("combos: неизвестный ресурс '%s'" % res)
				ok = false
	for id in buildings:
		for res in buildings[id].get("yield", {}):
			if not resources.has(res):
				push_error("buildings.%s: неизвестный ресурс '%s'" % [id, res])
				ok = false
	return ok


static func neighbor_list(rule: Dictionary) -> Array:
	var n = rule.get("neighbor", [])
	if n is String:
		return [n]
	return n


func zero_resources() -> Dictionary:
	var d := {}
	for res in resources:
		d[res] = 0
	return d


func building_name(id: String) -> String:
	return buildings.get(id, {}).get("name", id)


func combos_for(id: String) -> Array:
	var out := []
	for rule in combos:
		if rule.get("building", "") == id:
			out.append(rule)
	return out


## «+3 еды, +2 силы»
func format_amounts(amounts: Dictionary, skip_zero: bool = true) -> String:
	var parts := []
	for res in resources:
		var v := int(amounts.get(res, 0))
		if v == 0 and skip_zero:
			continue
		parts.append("%s%d %s" % ["+" if v >= 0 else "", v, resources[res]["short"]])
	return ", ".join(parts)


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
