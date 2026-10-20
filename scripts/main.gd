extends Node
## Main — точка входа (run/main_scene в project.godot).
##
## Пока концепция игры не выбрана, Main просто показывает главное меню.
## Позже сюда ляжет логика загрузки: сплэш -> меню или сразу в сейв.

const MAIN_MENU_PATH := "res://scenes/ui/main_menu/main_menu.tscn"


func _ready() -> void:
	var menu_scene := load(MAIN_MENU_PATH) as PackedScene
	if menu_scene == null:
		push_error("Main: не удалось загрузить главное меню %s" % MAIN_MENU_PATH)
		return
	add_child(menu_scene.instantiate())
	GameManager.set_state(GameManager.State.MAIN_MENU)
