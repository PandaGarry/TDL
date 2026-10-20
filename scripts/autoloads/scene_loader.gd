extends Node
## SceneLoader — смена сцен: мгновенная и асинхронная (с прогрессом).
##
## Асинхронный путь нужен большим уровням: подписавшись на load_progress,
## UI может показывать экран загрузки. Для маленьких сцен достаточно
## change_scene_immediate().

signal load_started(path: String)
signal load_progress(path: String, progress: float)
signal load_finished(path: String)
signal load_failed(path: String)

var _loading_path := ""


func _ready() -> void:
	set_process(false)


func _process(_delta: float) -> void:
	if _loading_path.is_empty():
		set_process(false)
		return

	var progress: Array = []
	var status := ResourceLoader.load_threaded_get_status(_loading_path, progress)
	match status:
		ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			if not progress.is_empty():
				load_progress.emit(_loading_path, float(progress[0]))
		ResourceLoader.THREAD_LOAD_LOADED:
			var packed := ResourceLoader.load_threaded_get(_loading_path) as PackedScene
			var finished_path := _loading_path
			_loading_path = ""
			set_process(false)
			if packed == null:
				_on_load_failed(finished_path)
				return
			get_tree().change_scene_to_packed(packed)
			load_finished.emit(finished_path)
			EventBus.scene_changed.emit(finished_path)
		_:
			var failed_path := _loading_path
			_loading_path = ""
			set_process(false)
			_on_load_failed(failed_path)


## Асинхронная загрузка сцены с сигналами прогресса.
func change_scene_async(path: String) -> void:
	if not ResourceLoader.exists(path):
		_on_load_failed(path)
		return
	var error := ResourceLoader.load_threaded_request(path)
	if error != OK:
		_on_load_failed(path)
		return
	_loading_path = path
	set_process(true)
	load_started.emit(path)
	EventBus.scene_change_requested.emit(path)


## Мгновенная смена сцены (может подфризить на тяжёлых уровнях).
func change_scene_immediate(path: String) -> void:
	EventBus.scene_change_requested.emit(path)
	var error := get_tree().change_scene_to_file(path)
	if error != OK:
		_on_load_failed(path)
		return
	load_finished.emit(path)
	EventBus.scene_changed.emit(path)


func reload_current_scene() -> void:
	get_tree().reload_current_scene()


func is_loading() -> bool:
	return not _loading_path.is_empty()


func _on_load_failed(path: String) -> void:
	push_error("SceneLoader: не удалось загрузить сцену %s" % path)
	load_failed.emit(path)
