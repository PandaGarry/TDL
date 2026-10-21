extends Node
## SettingsManager — client-local user settings (audio, display, locale, graphics).
##
## Stores client preferences in `user://settings.cfg` and applies them on
## startup and on every change. Client graphics/texture presets, foliage
## density, shader toggles, audio volumes and UI language never mutate
## `WorldState` or `domain_state_hash()`; campaign and cooperative lobby
## rules live in `WorldRules` inside `WorldState`.

signal settings_changed
signal graphics_settings_changed(profile: Dictionary)

const SETTINGS_PATH := "user://settings.cfg"
const DEFAULT_LANGUAGE := "ru"

const TEXTURE_QUALITY_GREYBOX := "greybox"
const TEXTURE_QUALITY_LOW := "low"
const TEXTURE_QUALITY_MEDIUM := "medium"
const TEXTURE_QUALITY_HIGH := "high"

const MIN_FOLIAGE_DENSITY := 0.0
const MAX_FOLIAGE_DENSITY := 1.0
const DEFAULT_FOLIAGE_DENSITY := 1.0

const MIN_UI_SCALE := 0.75
const MAX_UI_SCALE := 1.5
const DEFAULT_UI_SCALE := 1.0

var master_volume: float = 1.0
var music_volume: float = 1.0
var sfx_volume: float = 1.0
var ambience_volume: float = 1.0
var fullscreen: bool = false
var vsync_enabled: bool = true
var language: String = DEFAULT_LANGUAGE
var texture_quality: String = TEXTURE_QUALITY_HIGH
var foliage_density: float = DEFAULT_FOLIAGE_DENSITY
var wind_and_water_shaders: bool = true
var ui_scale: float = DEFAULT_UI_SCALE


func _ready() -> void:
	UiLocaleCatalog.ensure_registered()
	load_settings()
	apply_all()


static func is_valid_texture_quality(preset: String) -> bool:
	return (
		preset
		in [
			TEXTURE_QUALITY_GREYBOX,
			TEXTURE_QUALITY_LOW,
			TEXTURE_QUALITY_MEDIUM,
			TEXTURE_QUALITY_HIGH,
		]
	)


func load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return
	master_volume = clampf(
		float(config.get_value("audio", "master_volume", master_volume)), 0.0, 1.0
	)
	music_volume = clampf(float(config.get_value("audio", "music_volume", music_volume)), 0.0, 1.0)
	sfx_volume = clampf(float(config.get_value("audio", "sfx_volume", sfx_volume)), 0.0, 1.0)
	ambience_volume = clampf(
		float(config.get_value("audio", "ambience_volume", ambience_volume)), 0.0, 1.0
	)
	fullscreen = bool(config.get_value("display", "fullscreen", fullscreen))
	vsync_enabled = bool(config.get_value("display", "vsync_enabled", vsync_enabled))
	language = String(config.get_value("locale", "language", language))

	var loaded_quality := String(config.get_value("graphics", "texture_quality", texture_quality))
	if is_valid_texture_quality(loaded_quality):
		texture_quality = loaded_quality
	foliage_density = clampf(
		float(config.get_value("graphics", "foliage_density", foliage_density)),
		MIN_FOLIAGE_DENSITY,
		MAX_FOLIAGE_DENSITY
	)
	wind_and_water_shaders = bool(
		config.get_value("graphics", "wind_and_water_shaders", wind_and_water_shaders)
	)
	ui_scale = clampf(
		float(config.get_value("ui", "ui_scale", ui_scale)), MIN_UI_SCALE, MAX_UI_SCALE
	)


func save_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("audio", "master_volume", master_volume)
	config.set_value("audio", "music_volume", music_volume)
	config.set_value("audio", "sfx_volume", sfx_volume)
	config.set_value("audio", "ambience_volume", ambience_volume)
	config.set_value("display", "fullscreen", fullscreen)
	config.set_value("display", "vsync_enabled", vsync_enabled)
	config.set_value("locale", "language", language)
	config.set_value("graphics", "texture_quality", texture_quality)
	config.set_value("graphics", "foliage_density", foliage_density)
	config.set_value("graphics", "wind_and_water_shaders", wind_and_water_shaders)
	config.set_value("ui", "ui_scale", ui_scale)
	if config.save(SETTINGS_PATH) != OK:
		push_warning("SettingsManager: не удалось сохранить настройки в %s" % SETTINGS_PATH)


func apply_all() -> void:
	UiLocaleCatalog.ensure_registered()
	_apply_volume(AudioManager.BUS_MASTER, master_volume)
	_apply_volume(AudioManager.BUS_MUSIC, music_volume)
	_apply_volume(AudioManager.BUS_SFX, sfx_volume)
	_apply_volume(AudioManager.BUS_AMBIENCE, ambience_volume)
	_apply_display_settings()
	TranslationServer.set_locale(language)
	settings_changed.emit()
	graphics_settings_changed.emit(graphics_profile())
	EventBus.settings_changed.emit()


func graphics_profile() -> Dictionary:
	return {
		"texture_quality": texture_quality,
		"foliage_density": foliage_density,
		"wind_and_water_shaders": wind_and_water_shaders,
		"fullscreen": fullscreen,
		"vsync_enabled": vsync_enabled,
		"ui_scale": ui_scale,
	}


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


func set_ambience_volume(value: float) -> void:
	ambience_volume = clampf(value, 0.0, 1.0)
	_apply_volume(AudioManager.BUS_AMBIENCE, ambience_volume)
	_on_changed()


func set_fullscreen(value: bool) -> void:
	fullscreen = value
	_apply_display_settings()
	_on_changed(true)


func set_vsync_enabled(value: bool) -> void:
	vsync_enabled = value
	_apply_display_settings()
	_on_changed(true)


func set_language(code: String) -> void:
	language = code if not code.strip_edges().is_empty() else DEFAULT_LANGUAGE
	UiLocaleCatalog.ensure_registered()
	TranslationServer.set_locale(language)
	_on_changed()


func set_texture_quality(preset: String) -> bool:
	var cleaned := preset.strip_edges().to_lower()
	if not is_valid_texture_quality(cleaned):
		return false
	texture_quality = cleaned
	_on_changed(true)
	return true


func set_foliage_density(value: float) -> void:
	if not is_finite(value):
		return
	foliage_density = clampf(value, MIN_FOLIAGE_DENSITY, MAX_FOLIAGE_DENSITY)
	_on_changed(true)


func set_wind_and_water_shaders(enabled: bool) -> void:
	wind_and_water_shaders = enabled
	_on_changed(true)


func set_ui_scale(value: float) -> void:
	if not is_finite(value):
		return
	ui_scale = clampf(value, MIN_UI_SCALE, MAX_UI_SCALE)
	_on_changed(true)


func _apply_volume(bus_name: String, volume_linear: float) -> void:
	var index := AudioServer.get_bus_index(bus_name)
	if index == -1:
		return
	AudioServer.set_bus_mute(index, volume_linear <= 0.001)
	AudioServer.set_bus_volume_db(index, linear_to_db(maxf(volume_linear, 0.001)))


func _apply_display_settings() -> void:
	if fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	var vsync_mode := DisplayServer.VSYNC_ENABLED if vsync_enabled else DisplayServer.VSYNC_DISABLED
	DisplayServer.window_set_vsync_mode(vsync_mode)


func _on_changed(emit_graphics: bool = false) -> void:
	save_settings()
	settings_changed.emit()
	if emit_graphics:
		graphics_settings_changed.emit(graphics_profile())
	EventBus.settings_changed.emit()
