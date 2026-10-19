extends Node
## Точка входа: переключает меню и игровой экран.

const MainMenuScript = preload("res://src/ui/main_menu.gd")
const GameScreenScript = preload("res://src/game/game_screen.gd")

var _screen: Node


func _ready() -> void:
	var window := get_window()
	window.title = "Saltvigil"
	window.min_size = Vector2i(1280, 720)
	_show_menu()


func _show_menu() -> void:
	_clear_screen()
	var menu := MainMenuScript.new()
	add_child(menu)
	menu.new_game_requested.connect(_on_new_game)
	menu.continue_requested.connect(_on_continue)
	menu.quit_requested.connect(_on_quit)
	_screen = menu


func _on_new_game() -> void:
	GameState.new_game()
	GameState.start()
	_show_game()


func _on_continue() -> void:
	if SaveSystem.load_game():
		GameState.start()
		_show_game()


func _show_game() -> void:
	_clear_screen()
	var game := GameScreenScript.new()
	add_child(game)
	game.exit_requested.connect(_show_menu)
	game.restart_requested.connect(_on_restart)
	_screen = game


func _on_restart() -> void:
	GameState.new_game()
	GameState.start()
	_show_game()


func _on_quit() -> void:
	get_tree().quit()


func _clear_screen() -> void:
	if _screen != null and is_instance_valid(_screen):
		remove_child(_screen)
		_screen.queue_free()
	_screen = null
