extends Node
## GameManager — высокоуровневое состояние игры и пауза.
##
## Не хранит геймплейные данные (здоровье, инвентарь и т.п.) — только
## "в каком режиме сейчас игра". Конкретные системы живут в своих сценах
## и компонентах, менеджер лишь координирует переходы.

signal state_changed(new_state: State)

enum State {
	BOOT, ## Только стартовали, ещё ничего не показано.
	MAIN_MENU, ## Главное меню.
	PLAYING, ## Идёт игровой процесс.
	PAUSED, ## Игровой процесс на паузе (get_tree().paused == true).
}

const MAIN_SCENE_PATH := "res://scenes/main/main.tscn"

var state: State = State.BOOT


func _ready() -> void:
	# Должен продолжать работать, пока дерево на паузе (снятие паузы!).
	process_mode = Node.PROCESS_MODE_ALWAYS


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_pause"):
		toggle_pause()


func set_state(new_state: State) -> void:
	if new_state == state:
		return
	state = new_state
	state_changed.emit(state)


func start_game() -> void:
	get_tree().paused = false
	set_state(State.PLAYING)
	EventBus.game_started.emit()


func set_paused(value: bool) -> void:
	if value and state != State.PLAYING:
		return
	if not value and state != State.PAUSED:
		return
	get_tree().paused = value
	set_state(State.PAUSED if value else State.PLAYING)
	EventBus.game_paused.emit(value)


func toggle_pause() -> void:
	if state == State.PLAYING:
		set_paused(true)
	elif state == State.PAUSED:
		set_paused(false)


func is_playing() -> bool:
	return state == State.PLAYING


func return_to_main_menu() -> void:
	get_tree().paused = false
	set_state(State.MAIN_MENU)
	EventBus.returned_to_main_menu.emit()
	SceneLoader.change_scene_immediate(MAIN_SCENE_PATH)


func quit_game() -> void:
	get_tree().quit()
