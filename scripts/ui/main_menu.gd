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
	add_child(bg_world)
	bg_world.ensure_built()
	bg_world.set_camera_lookpoint("valley_panorama")
	_title_label.add_theme_color_override("font_shadow_color", Color(0.04, 0.05, 0.03, 0.85))
	_title_label.add_theme_constant_override("shadow_offset_x", 2)
	_title_label.add_theme_constant_override("shadow_offset_y", 3)
	_subtitle_label.add_theme_color_override("font_shadow_color", Color(0.04, 0.05, 0.03, 0.88))
	_subtitle_label.add_theme_constant_override("shadow_offset_x", 1)
	_subtitle_label.add_theme_constant_override("shadow_offset_y", 2)
	var menu_btns: Array[Button] = [
		_new_game_button, _continue_button, _settings_button, _quit_button
	]
	for idx in range(menu_btns.size()):
		_style_menu_button(menu_btns[idx], idx == 0)


static func _style_menu_button(btn: Button, is_primary: bool) -> void:
	if btn == null:
		return
	var n_box := StyleBoxFlat.new()
	n_box.bg_color = (
		Color(0.11, 0.16, 0.12, 0.88) if is_primary else Color(0.08, 0.11, 0.09, 0.82)
	)
	n_box.border_color = (
		Color(0.82, 0.69, 0.42, 0.92) if is_primary else Color(0.58, 0.50, 0.34, 0.74)
	)
	n_box.set_border_width_all(1)
	n_box.border_width_bottom = 2
	n_box.set_corner_radius_all(8)
	n_box.shadow_color = Color(0.0, 0.0, 0.0, 0.42)
	n_box.shadow_size = 7
	n_box.shadow_offset = Vector2(0.0, 3.0)
	n_box.content_margin_left = 18.0
	n_box.content_margin_right = 18.0
	n_box.content_margin_top = 9.0
	n_box.content_margin_bottom = 9.0
	var h_box := n_box.duplicate() as StyleBoxFlat
	h_box.bg_color = Color(0.17, 0.24, 0.17, 0.94)
	h_box.border_color = Color(0.95, 0.82, 0.50, 0.98)
	var d_box := n_box.duplicate() as StyleBoxFlat
	d_box.bg_color = Color(0.07, 0.09, 0.08, 0.52)
	d_box.border_color = Color(0.42, 0.38, 0.30, 0.42)
	btn.add_theme_stylebox_override("normal", n_box)
	btn.add_theme_stylebox_override("hover", h_box)
	btn.add_theme_stylebox_override("focus", h_box)
	btn.add_theme_stylebox_override("pressed", h_box)
	btn.add_theme_stylebox_override("disabled", d_box)
	btn.add_theme_color_override("font_color", Color(0.96, 0.92, 0.82, 1.0))
	btn.add_theme_color_override("font_hover_color", Color(1.0, 0.98, 0.90, 1.0))
	btn.add_theme_color_override("font_disabled_color", Color(0.68, 0.70, 0.66, 0.58))


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
