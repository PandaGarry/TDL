extends Node
## Сохранение в user:// — JSON с версией, атомарной записью и резервной копией.
## Автосейв на рассвете; финал демо стирает чекпоинт.

const SAVE_VERSION := 1
const DEFAULT_SAVE_PATH := "user://saltvigil_save.json"

var save_path := DEFAULT_SAVE_PATH


func _ready() -> void:
	EventBus.night_ended.connect(_on_night_ended)
	EventBus.demo_completed.connect(_on_demo_completed)


func _on_night_ended(_summary: Dictionary) -> void:
	save_game()


func _on_demo_completed(_summary: Dictionary) -> void:
	delete_save()


func has_save() -> bool:
	return FileAccess.file_exists(save_path) or FileAccess.file_exists(_backup_path())


func save_game() -> bool:
	if GameState.is_game_over or GameState.demo_over:
		return false

	var payload := {
		"version": SAVE_VERSION,
		"saved_at": Time.get_datetime_string_from_system(),
		"state": GameState.to_dict()
	}
	var tmp_path := save_path + ".tmp"
	var file := FileAccess.open(tmp_path, FileAccess.WRITE)
	if file == null:
		push_error("SaveSystem: не удалось открыть файл сохранения")
		return false
	file.store_string(JSON.stringify(payload, "\t"))
	file.flush()
	file.close()

	if FileAccess.file_exists(save_path):
		if FileAccess.file_exists(_backup_path()):
			DirAccess.remove_absolute(_global(_backup_path()))
		var backup_error := DirAccess.copy_absolute(_global(save_path), _global(_backup_path()))
		if backup_error != OK:
			push_warning("SaveSystem: не удалось создать резервную копию (%d)" % backup_error)

	var error := DirAccess.rename_absolute(_global(tmp_path), _global(save_path))
	if error == ERR_ALREADY_EXISTS:
		DirAccess.remove_absolute(_global(save_path))
		error = DirAccess.rename_absolute(_global(tmp_path), _global(save_path))
	if error != OK:
		error = DirAccess.copy_absolute(_global(tmp_path), _global(save_path))
		DirAccess.remove_absolute(_global(tmp_path))
	if error != OK:
		push_error("SaveSystem: не удалось записать сохранение (%d)" % error)
		return false
	return true


func load_game() -> bool:
	if _load_from(save_path):
		return true
	if _load_from(_backup_path()):
		push_warning("SaveSystem: основное сохранение повреждено, загружена резервная копия")
		return true
	return false


func delete_save() -> void:
	for path in [save_path, _backup_path(), save_path + ".tmp"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(_global(path))


func _load_from(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	var text := file.get_as_text()
	file.close()

	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		push_error("SaveSystem: повреждённое сохранение " + path)
		return false
	var version := int(parsed.get("version", 0))
	if version <= 0 or version > SAVE_VERSION:
		push_error("SaveSystem: неподдерживаемая версия сохранения")
		return false
	var state: Variant = parsed.get("state", {})
	if not (state is Dictionary):
		return false
	if bool(state.get("is_game_over", false)) or bool(state.get("demo_over", false)):
		return false

	GameState.from_dict(state)
	return true


func _backup_path() -> String:
	return save_path + ".bak"


func _global(path: String) -> String:
	return ProjectSettings.globalize_path(path)
