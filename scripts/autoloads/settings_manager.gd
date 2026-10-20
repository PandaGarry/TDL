extends Node
## SettingsManager — пользовательские настройки.
##
## Хранит настройки в user://settings.cfg, применяет их при запуске
## и при каждом изменении. Экран настроек (когда появится) должен
## работать только через этот API, а не дёргать AudioServer/DisplayServer
## напрямую.

signal settings_changed

const SETTINGS_PATH := "user://settings.cfg"
const DEFAULT_LANGUAGE := "ru"

var master_volume: float = 1.0
var music_volume: float = 1.0
var sfx_volume: float = 1.0
var fullscreen: bool = false
var language: String = DEFAULT_LANGUAGE


func _ready() -> void:
	load_settings()
	apply_all()


func load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return # Первый запуск — остаются значения по умолчанию.
	master_volume = float(config.get_value("audio", "master_volume", master_volume))
	music_volume = float(config.get_value("audio", "music_volume", music_volume))
	sfx_volume = float(config.get_value("audio", "sfx_volume", sfx_volume))
	fullscreen = bool(config.get_value("display", "fullscreen", fullscreen))
	language = String(config.get_value("locale", "language", language))


func save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("audio", "master_volume", master_volume)
	config.set_value("audio", "music_volume", music_volume)
	config.set_value("audio", "sfx_volume", sfx_volume)
	config.set_value("display", "fullscreen", fullscreen)
	config.set_value("locale", "language", language)
	if config.save(SETTINGS_PATH) != OK:
		push_warning("SettingsManager: не удалось сохранить настройки в %s" % SETTINGS_PATH)


func apply_all() -> void:
	_apply_volume(AudioManager.BUS_MASTER, master_volume)
	_apply_volume(AudioManager.BUS_MUSIC, music_volume)
	_apply_volume(AudioManager.BUS_SFX, sfx_volume)
	_apply_fullscreen()
	TranslationServer.set_locale(language)
	settings_changed.emit()
	EventBus.settings_changed.emit()


## volume_linear: 0.0 (тишина) .. 1.0 (полная громкость).
func set_master_volume(value: float) -> void:
	master_volume = clampf(value, 0.0, 1.0)
	_apply_volume(AudioManager.BUS_MASTER, master_volume)
	_on_changed()


func set_music_volume(value: float) -> void:
	music_volume = clampf(value, 0.0, 1.0)
	_apply_volume(AudioManager.BUS_MUSIC, music_volume)
	_on_changed()


func set_sfx_volume(value: float) -> void:
	sfx_volume = clampf(value, 0.0, 1.0)
	_apply_volume(AudioManager.BUS_SFX, sfx_volume)
	_on_changed()


func set_fullscreen(value: bool) -> void:
	fullscreen = value
	_apply_fullscreen()
	_on_changed()


func set_language(code: String) -> void:
	language = code
	TranslationServer.set_locale(language)
	_on_changed()


func _apply_volume(bus_name: String, volume_linear: float) -> void:
	var index := AudioServer.get_bus_index(bus_name)
	if index == -1:
		return
	AudioServer.set_bus_mute(index, volume_linear <= 0.001)
	AudioServer.set_bus_volume_db(index, linear_to_db(maxf(volume_linear, 0.001)))


func _apply_fullscreen() -> void:
	if fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)


func _on_changed() -> void:
	save_settings()
	settings_changed.emit()
	EventBus.settings_changed.emit()
