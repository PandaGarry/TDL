extends Control
## Главное меню — вход в P0-F greybox-прототип и настройки оболочки.
##
## Все тексты проходят через ключи локализации `UiLocaleCatalog` (`tr(...)`).
## "Новая кампания" запускает `scenes/levels/greybox_stage.tscn` через
## `SceneLoader` и `GameManager`, а "Продолжить" проверяет наличие
## валидного мирового слота в `SaveStore`.

const GREYBOX_STAGE_SCENE_PATH := "res://scenes/levels/greybox_stage.tscn"
const CAMPAIGN_SAVE_ROOT := "user://saves/campaigns"

@onready var _title_label: Label = %TitleLabel
@onready var _subtitle_label: Label = %SubtitleLabel
@onready var _new_game_button: Button = %NewGameButton
@onready var _continue_button: Button = %ContinueButton
@onready var _settings_button: Button = %SettingsButton
@onready var _quit_button: Button = %QuitButton
@onready var _status_label: Label = %StatusLabel


func _ready() -> void:
	UiLocaleCatalog.ensure_registered()
	_install_backdrop_texture()
	_apply_localized_texts()
	_new_game_button.pressed.connect(_on_new_game_pressed)
	_continue_button.pressed.connect(_on_continue_pressed)
	_settings_button.pressed.connect(_on_settings_pressed)
	_quit_button.pressed.connect(_on_quit_pressed)
	SettingsManager.settings_changed.connect(_apply_localized_texts)

	_continue_button.disabled = not _has_campaign_save()
	_new_game_button.grab_focus()


func _install_backdrop_texture() -> void:
	var bg_world := SevaraWorld3D.new()
	bg_world.name = "MainMenuWorld3D"
	bg_world.set_camera_preset(2, Vector2i(11, 11))
	add_child(bg_world)


func _exit_tree() -> void:
	if SettingsManager.settings_changed.is_connected(_apply_localized_texts):
		SettingsManager.settings_changed.disconnect(_apply_localized_texts)


func _apply_localized_texts() -> void:
	_title_label.text = tr("ui.main_menu.title")
	_subtitle_label.text = tr("ui.main_menu.subtitle")
	_new_game_button.text = tr("ui.main_menu.new_game")
	_continue_button.text = tr("ui.main_menu.continue")
	_settings_button.text = tr("ui.main_menu.settings")
	_quit_button.text = tr("ui.main_menu.quit")


func _has_campaign_save() -> bool:
	var store := SaveStore.new(CAMPAIGN_SAVE_ROOT, 5)
	var has_world_candidates := not (
		store
		. get_candidate_paths(GreyboxStage.DEFAULT_SLOT_ID, WorldStateCodec.WORLD_DOCUMENT_NAME)
		. is_empty()
	)
	return has_world_candidates or SaveSystem.has_save(0)


func _on_new_game_pressed() -> void:
	GreyboxStage.next_launch_load_slot_id = ""
	GameManager.start_game()
	SceneLoader.change_scene_immediate(GREYBOX_STAGE_SCENE_PATH)


func _on_continue_pressed() -> void:
	var store := SaveStore.new(CAMPAIGN_SAVE_ROOT, 5)
	var has_world_candidates := not (
		store
		. get_candidate_paths(GreyboxStage.DEFAULT_SLOT_ID, WorldStateCodec.WORLD_DOCUMENT_NAME)
		. is_empty()
	)
	if has_world_candidates:
		GreyboxStage.next_launch_load_slot_id = GreyboxStage.DEFAULT_SLOT_ID
		GameManager.start_game()
		SceneLoader.change_scene_immediate(GREYBOX_STAGE_SCENE_PATH)
		return
	var legacy_data: Dictionary = SaveSystem.load_game(0)
	if legacy_data.is_empty():
		_status_label.text = tr("ui.main_menu.status_no_save")
	else:
		GreyboxStage.next_launch_load_slot_id = ""
		GameManager.start_game()
		SceneLoader.change_scene_immediate(GREYBOX_STAGE_SCENE_PATH)


func _on_settings_pressed() -> void:
	_status_label.text = tr("ui.main_menu.status_settings_info")


func _on_quit_pressed() -> void:
	GameManager.quit_game()
