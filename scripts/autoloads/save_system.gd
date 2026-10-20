extends Node
## SaveSystem — сохранения в JSON по слотам: user://saves/save_<slot>.json
##
## Формат файла: { "version": int, "timestamp": String, "data": Dictionary }
## Слой игры сам решает, что класть в data (позиция игрока, флаги сюжета,
## инвентарь и т.д.). Здесь — только чтение/запись и версионирование.
##
## Внимание: JSON превращает целочисленные ключи словарей в строки,
## а float может потерять точность. Для сложных данных позже можно
## перейти на var_to_bytes / ResourceSaver — интерфейс при этом не менять.

signal save_completed(slot: int)
signal load_completed(slot: int, data: Dictionary)
signal operation_failed(slot: int, message: String)

const SAVE_DIR := "user://saves"
const CURRENT_VERSION := 1


func save_game(slot: int, data: Dictionary) -> bool:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var payload := {
		"version": CURRENT_VERSION,
		"timestamp": Time.get_datetime_string_from_system(true),
		"data": data,
	}
	var file := FileAccess.open(get_save_path(slot), FileAccess.WRITE)
	if file == null:
		_fail(slot, "не удалось открыть файл для записи")
		return false
	file.store_string(JSON.stringify(payload, "\t"))
	file.close()
	save_completed.emit(slot)
	EventBus.save_completed.emit(slot)
	return true


## Возвращает словарь data из сохранения или {} если сохранения нет/оно битое.
func load_game(slot: int) -> Dictionary:
	var path := get_save_path(slot)
	if not FileAccess.file_exists(path):
		_fail(slot, "сохранение не найдено")
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_fail(slot, "не удалось открыть файл для чтения")
		return {}
	var text := file.get_as_text()
	file.close()

	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		_fail(slot, "файл сохранения повреждён")
		return {}
	var payload: Dictionary = _migrate(parsed)
	var data: Dictionary = payload.get("data", {})
	load_completed.emit(slot, data)
	EventBus.load_completed.emit(slot)
	return data


func has_save(slot: int) -> bool:
	return FileAccess.file_exists(get_save_path(slot))


func delete_save(slot: int) -> void:
	if has_save(slot):
		DirAccess.remove_absolute(get_save_path(slot))


func get_save_path(slot: int) -> String:
	return "%s/save_%d.json" % [SAVE_DIR, slot]


## Миграции старых форматов. Пока версия одна — заглушка с понятным местом,
## куда добавлять цепочку преобразований v1 -> v2 -> ... когда формат вырастет.
func _migrate(payload: Dictionary) -> Dictionary:
	var version := int(payload.get("version", 0))
	if version > CURRENT_VERSION:
		push_warning(
			"SaveSystem: сохранение версии %d новее поддерживаемой %d" % [version, CURRENT_VERSION]
		)
	# match version:
	#   1: payload = _migrate_v1_to_v2(payload)
	return payload


func _fail(slot: int, message: String) -> void:
	push_warning("SaveSystem (слот %d): %s" % [slot, message])
	operation_failed.emit(slot, message)
