extends Control
## Главное меню — временная заглушка пре-продакшена.
##
## Кнопки уже честно подключены к системам (выход работает, "Продолжить"
## проверяет реальное сохранение), но первого уровня пока нет: направление
## H1 выбрано и сведено в GDD v1.0 Core Baseline, однако игровой прототип
## ещё не реализован.
## См. docs/design/gdd.md и docs/production/round12_baseline_lock.md.

@onready var _new_game_button: Button = %NewGameButton
@onready var _continue_button: Button = %ContinueButton
@onready var _settings_button: Button = %SettingsButton
@onready var _quit_button: Button = %QuitButton
@onready var _status_label: Label = %StatusLabel


func _ready() -> void:
	_new_game_button.pressed.connect(_on_new_game_pressed)
	_continue_button.pressed.connect(_on_continue_pressed)
	_settings_button.pressed.connect(_on_settings_pressed)
	_quit_button.pressed.connect(_on_quit_pressed)

	_continue_button.disabled = not SaveSystem.has_save(0)
	_new_game_button.grab_focus()


func _on_new_game_pressed() -> void:
	# TODO: после утверждения первого прототипа —
	# SceneLoader.change_scene_async(первый уровень) и GameManager.start_game().
	_status_label.text = (
		"Игрового прототипа пока нет. GDD v1.0 Core Baseline принят.\n"
		+ "См. docs/design/gdd.md"
	)


func _on_continue_pressed() -> void:
	var data := SaveSystem.load_game(0)
	if data.is_empty():
		_status_label.text = "Сохранение не найдено или повреждено."
	else:
		_status_label.text = "Сохранение загружено. Игрового уровня в каркасе пока нет."


func _on_settings_pressed() -> void:
	# TODO: экран настроек поверх меню; логика уже есть в SettingsManager.
	_status_label.text = (
		"Экран настроек появится вместе с первым прототипом.\n"
		+ "Настройки уже хранятся: SettingsManager."
	)


func _on_quit_pressed() -> void:
	GameManager.quit_game()
