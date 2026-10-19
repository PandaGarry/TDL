extends Node
## Загрузчик контента. Всё, что можно добавить без кода, лежит в res://data/*.json.
## Это же — точка входа для модов и Steam Workshop в будущем.

const DATA_DIR := "res://data/"

var config: Dictionary = {}
var items: Dictionary = {}
var item_order: Array = []
var buildings: Dictionary = {}
var building_order: Array = []
var followers: Array = []
var memories: Dictionary = {}
var journal: Array = []
var doctrines: Array = []
var events: Array = []
var loaded := false
var errors: Array = []


func _ready() -> void:
	load_all()


func load_all() -> bool:
	loaded = false
	errors.clear()
	item_order.clear()
	building_order.clear()

	config = _read_json("config.json", {})
	items = _index_by_id("items.json", "id", item_order)
	buildings = _index_by_id("buildings.json", "id", building_order)
	followers = _read_json("followers.json", [])
	memories = _index_by_id("memories.json", "id", [])
	journal = _read_json("journal.json", [])
	doctrines = _read_json("doctrines.json", [])
	events = _read_json("events.json", [])

	if config.is_empty():
		errors.append("config.json не загружен или пуст")
	if followers.is_empty():
		errors.append("followers.json не загружен или пуст")
	if memories.is_empty():
		errors.append("memories.json не загружен или пуст")
	if buildings.is_empty():
		errors.append("buildings.json не загружен или пуст")
	if doctrines.is_empty():
		errors.append("doctrines.json не загружен или пуст")
	if events.is_empty():
		errors.append("events.json не загружен или пуст")

	for message in errors:
		push_error("Database: " + message)

	loaded = errors.is_empty()
	return loaded


func get_config_value(key: String, fallback: Variant = null) -> Variant:
	return config.get(key, fallback)


func get_item(item_id: String) -> Dictionary:
	return items.get(item_id, {})


func get_building(building_id: String) -> Dictionary:
	return buildings.get(building_id, {})


func get_memory(memory_id: String) -> Dictionary:
	return memories.get(memory_id, {})


func get_follower_data(follower_id: String) -> Dictionary:
	for entry in followers:
		if entry.get("id", "") == follower_id:
			return entry
	return {}


func get_journal_entry(entry_id: String) -> Dictionary:
	for entry in journal:
		if entry.get("id", "") == entry_id:
			return entry
	return {}


func get_doctrine(doctrine_id: String) -> Dictionary:
	for entry in doctrines:
		if entry.get("id", "") == doctrine_id:
			return entry
	return {}


func active_doctrines() -> Array:
	var result: Array = []
	for entry in doctrines:
		if str(entry.get("status", "")) == "active":
			result.append(entry)
	return result


func get_event(event_id: String) -> Dictionary:
	for entry in events:
		if entry.get("id", "") == event_id:
			return entry
	return {}


func _read_json(file_name: String, fallback: Variant) -> Variant:
	var path := DATA_DIR + file_name
	if not FileAccess.file_exists(path):
		errors.append("Нет файла " + path)
		return fallback

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		errors.append("Не удалось открыть " + path)
		return fallback

	var text := file.get_as_text()
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null:
		errors.append("Ошибка JSON в " + path)
		return fallback
	return parsed


func _index_by_id(file_name: String, key: String, order: Array) -> Dictionary:
	var result: Dictionary = {}
	var entries: Variant = _read_json(file_name, [])
	if not (entries is Array):
		errors.append(file_name + " должен содержать массив")
		return result
	for entry in entries:
		if not (entry is Dictionary):
			continue
		var entry_id := str(entry.get(key, ""))
		if entry_id.is_empty():
			errors.append(file_name + ": запись без id")
			continue
		result[entry_id] = entry
		if order != null:
			order.append(entry_id)
	return result
