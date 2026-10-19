extends Node
## Сохранение в user:// — JSON с версией. Автосейв на рассвете.

const SAVE_PATH := "user://saltvigil_save.json"
const SAVE_VERSION := 1


func _ready() -> void:
	EventBus.night_ended.connect(_on_night_ended)


func _on_night_ended(_summary: Dictionary) -> void:
	save_game()


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


func save_game() -> bool:
	var payload := {
		"version": SAVE_VERSION,
		"saved_at": Time.get_datetime_string_from_system(),
		"state": GameState.to_dict()
	}
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("SaveSystem: не удалось открыть файл сохранения")
		return false
	file.store_string(JSON.stringify(payload, "\t"))
	file.close()
	return true


func load_game() -> bool:
	if not has_save():
		return false
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return false
	var text := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		push_error("SaveSystem: повреждённое сохранение")
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


func delete_save() -> void:
	if has_save():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
