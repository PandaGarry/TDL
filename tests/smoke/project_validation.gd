extends Node
## Project validation scene for CI and local headless checks.
##
## Why this exists: launching individual files with
## `godot --check-only --script ...` compiles them outside the normal
## project run, so identifiers of autoload singletons (EventBus,
## SaveSystem, etc.) are unresolved and good scripts look broken.
## This scene is launched as a normal project scene instead: autoloads
## are active, then every GDScript under res://scripts is loaded through
## ResourceLoader, which forces compilation in the real project context.
##
## Run with:
##   godot --headless --path . --scene res://tests/smoke/project_validation.tscn

const SCRIPT_ROOT := "res://scripts"

var _failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run_validation")


func _run_validation() -> void:
	var paths: Array[String] = []
	_collect_scripts(SCRIPT_ROOT, paths)
	paths.sort()

	if paths.is_empty():
		_failures.append("No GDScript files found under %s" % SCRIPT_ROOT)

	for path in paths:
		var resource: Resource = ResourceLoader.load(path)
		if resource == null:
			_failures.append("%s: ResourceLoader returned null" % path)
			continue

		var script := resource as GDScript
		if script == null:
			_failures.append("%s: loaded resource is not GDScript" % path)
			continue

		if not script.can_instantiate() and not script.is_abstract():
			_failures.append("%s: script cannot instantiate (likely compile error)" % path)

	if _failures.is_empty():
		print("PROJECT_VALIDATION_OK scripts=%d" % paths.size())
		get_tree().quit(0)
	else:
		for failure in _failures:
			push_error("PROJECT_VALIDATION_FAILED: %s" % failure)
		get_tree().quit(1)


func _collect_scripts(path: String, result: Array[String]) -> void:
	var directory := DirAccess.open(path)
	if directory == null:
		_failures.append("%s: cannot open directory" % path)
		return

	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		var child_path := path.path_join(entry)
		if directory.current_is_dir():
			_collect_scripts(child_path, result)
		elif entry.ends_with(".gd"):
			result.append(child_path)
		entry = directory.get_next()
	directory.list_dir_end()
