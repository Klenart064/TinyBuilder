## Книга комбо: какие комбинации игрок уже находил. Сохраняется между забегами в user://.
extends RefCounted

const SAVE_PATH := "user://combo_book.json"

var discovered: Dictionary = {}


func load_book(path: String = SAVE_PATH) -> void:
	discovered = {}
	if not FileAccess.file_exists(path):
		return
	var f := FileAccess.open(path, FileAccess.READ)
	var parsed = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		discovered = parsed


func save_book(path: String = SAVE_PATH) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(discovered))


func is_known(combo_id: String) -> bool:
	return discovered.has(combo_id)


## Отмечает комбо найденными. Возвращает список только что открытых id.
func discover(ids: Array) -> Array:
	var fresh := []
	for id in ids:
		if not discovered.has(id):
			discovered[id] = true
			fresh.append(id)
	return fresh


func reset() -> void:
	discovered = {}
