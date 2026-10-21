class_name SaveStore
extends RefCounted
## Generic crash-safe JSON document store for campaign saves.
##
## SaveStore knows nothing about WorldState or individual save schemas.
## Codecs hand it JSON-safe dictionaries and validate document semantics;
## this class owns only slot paths, same-directory temporary writes,
## backup rotation and candidate recovery.
##
## Atomicity contract: a new document is fully written and verified under
## a temporary name before the previous current file is rotated to
## `*.backup1.json` and the temporary file is renamed into place. If the
## process dies in the small rename window, loaders can recover from the
## newest backup instead of seeing a half-written current file.

const DEFAULT_ROOT_DIR := "user://saves/campaigns"
const DEFAULT_BACKUP_COUNT := 5
const MAX_BACKUP_COUNT := 20

var _root_dir: String
var _backup_count: int


func _init(root_dir: String = DEFAULT_ROOT_DIR, backup_count: int = DEFAULT_BACKUP_COUNT) -> void:
	_root_dir = _normalize_root_dir(root_dir)
	_backup_count = clampi(backup_count, 1, MAX_BACKUP_COUNT)


func root_dir() -> String:
	return _root_dir


func backup_count() -> int:
	return _backup_count


func get_slot_directory(slot_id: String) -> String:
	if not _is_valid_name(slot_id):
		return ""
	return _root_dir.path_join(slot_id)


func get_document_path(slot_id: String, document_name: String) -> String:
	var slot_directory := get_slot_directory(slot_id)
	if slot_directory.is_empty() or not _is_valid_name(document_name):
		return ""
	return slot_directory.path_join("%s.json" % document_name)


func get_backup_path(slot_id: String, document_name: String, backup_index: int) -> String:
	var slot_directory := get_slot_directory(slot_id)
	if (
		slot_directory.is_empty()
		or not _is_valid_name(document_name)
		or backup_index < 1
		or backup_index > _backup_count
	):
		return ""
	return slot_directory.path_join("%s.backup%d.json" % [document_name, backup_index])


func get_candidate_paths(slot_id: String, document_name: String) -> Array[String]:
	var result: Array[String] = []
	var current_path := get_document_path(slot_id, document_name)
	if current_path.is_empty():
		return result
	if FileAccess.file_exists(current_path):
		result.append(current_path)
	for backup_index in range(1, _backup_count + 1):
		var backup_path := get_backup_path(slot_id, document_name, backup_index)
		if FileAccess.file_exists(backup_path):
			result.append(backup_path)
	return result


func has_document(slot_id: String, document_name: String) -> bool:
	var current_path := get_document_path(slot_id, document_name)
	return not current_path.is_empty() and FileAccess.file_exists(current_path)


func save_document(slot_id: String, document_name: String, document: Dictionary) -> Dictionary:
	if not JsonValue.is_safe(document):
		return _failure("Document '%s' contains non-JSON-safe values" % document_name)

	var preparation := _prepare_save(slot_id, document_name)
	if not bool(preparation["ok"]):
		return _failure(String(preparation["error"]))
	var slot_directory := String(preparation["slot_directory"])
	var current_path := String(preparation["current_path"])

	_remove_stale_temp_files(slot_directory, document_name)
	var json_bytes := JSON.stringify(document, "\t").to_utf8_buffer()
	var temporary_result := _write_verified_temporary_file(
		slot_directory, document_name, json_bytes
	)
	if not bool(temporary_result["ok"]):
		return _failure(String(temporary_result["error"]))
	var temporary_path := String(temporary_result["path"])

	var replace_error := _replace_current_file(slot_id, document_name, temporary_path, current_path)
	if replace_error != OK:
		_remove_file_if_exists(temporary_path)
		return _failure(
			"Cannot replace current save '%s' (error %d)" % [current_path, replace_error]
		)

	return {
		"ok": true,
		"path": current_path,
		"bytes": json_bytes.size(),
		"errors": [],
	}


func _prepare_save(slot_id: String, document_name: String) -> Dictionary:
	var slot_directory := get_slot_directory(slot_id)
	var current_path := get_document_path(slot_id, document_name)
	if slot_directory.is_empty() or current_path.is_empty():
		return {"ok": false, "error": "Invalid save slot or document name"}

	var make_error := DirAccess.make_dir_recursive_absolute(slot_directory)
	if make_error != OK and make_error != ERR_ALREADY_EXISTS:
		return {
			"ok": false,
			"error": "Cannot create save directory '%s' (error %d)" % [slot_directory, make_error],
		}

	return {
		"ok": true,
		"error": "",
		"slot_directory": slot_directory,
		"current_path": current_path,
	}


func _write_verified_temporary_file(
	slot_directory: String, document_name: String, json_bytes: PackedByteArray
) -> Dictionary:
	var temporary_path := _make_temporary_path(slot_directory, document_name)
	var write_error := _write_bytes_file(temporary_path, json_bytes)
	if write_error != OK:
		_remove_file_if_exists(temporary_path)
		return {
			"ok": false,
			"error": "Cannot write temporary save '%s' (error %d)" % [temporary_path, write_error],
			"path": "",
		}

	var verify_result := _read_bytes_file(temporary_path)
	if not bool(verify_result["ok"]) or verify_result["bytes"] != json_bytes:
		_remove_file_if_exists(temporary_path)
		return {
			"ok": false,
			"error": "Temporary save '%s' failed byte verification" % temporary_path,
			"path": "",
		}

	return {"ok": true, "error": "", "path": temporary_path}


func read_document_at_path(path: String) -> Dictionary:
	var read_result := _read_bytes_file(path)
	if not bool(read_result["ok"]):
		return _failure(String(read_result["error"]))

	var bytes: PackedByteArray = read_result["bytes"]
	var text := bytes.get_string_from_utf8()
	if text.is_empty() and not bytes.is_empty():
		return _failure("%s: file is not valid UTF-8" % path)

	var json := JSON.new()
	var parse_error := json.parse(text)
	if parse_error != OK:
		return _failure("%s:%d: %s" % [path, json.get_error_line(), json.get_error_message()])
	if typeof(json.data) != TYPE_DICTIONARY:
		return _failure("%s: JSON root must be an object" % path)
	if not JsonValue.is_safe(json.data):
		return _failure("%s: JSON document contains unsafe values" % path)

	return {
		"ok": true,
		"path": path,
		"document": JsonValue.duplicate_safe(json.data),
		"errors": [],
	}


## Loads the first parseable candidate in current -> backup1 -> backupN
## order. A codec may pass a `validator(document) -> bool` callable so a
## semantically invalid current file also falls back to backups.
func load_document(
	slot_id: String, document_name: String, validator: Callable = Callable()
) -> Dictionary:
	var candidate_paths := get_candidate_paths(slot_id, document_name)
	if candidate_paths.is_empty():
		return _failure(
			"No save candidates for slot '%s', document '%s'" % [slot_id, document_name]
		)

	var errors: Array[String] = []
	var current_path := get_document_path(slot_id, document_name)
	for candidate_path in candidate_paths:
		var read_result := read_document_at_path(candidate_path)
		if not bool(read_result["ok"]):
			errors.append(String(read_result["errors"][0]))
			continue

		var document: Dictionary = read_result["document"]
		if validator.is_valid():
			var valid_value: Variant = validator.call(document)
			if typeof(valid_value) != TYPE_BOOL or not bool(valid_value):
				errors.append("%s: rejected by document validator" % candidate_path)
				continue

		return {
			"ok": true,
			"path": candidate_path,
			"document": document,
			"recovered": candidate_path != current_path,
			"errors": errors.duplicate(),
		}

	return {"ok": false, "path": "", "document": {}, "recovered": false, "errors": errors}


func delete_slot(slot_id: String) -> bool:
	var slot_directory := get_slot_directory(slot_id)
	if slot_directory.is_empty():
		return false
	if not DirAccess.dir_exists_absolute(slot_directory):
		return true
	return _delete_directory_recursive(slot_directory) == OK


func _replace_current_file(
	slot_id: String, document_name: String, temporary_path: String, current_path: String
) -> Error:
	var moved_current_to_backup := false

	if FileAccess.file_exists(current_path):
		var oldest_backup := get_backup_path(slot_id, document_name, _backup_count)
		var remove_error := _remove_file_if_exists(oldest_backup)
		if remove_error != OK:
			return remove_error

		for backup_index in range(_backup_count - 1, 0, -1):
			var source := get_backup_path(slot_id, document_name, backup_index)
			var destination := get_backup_path(slot_id, document_name, backup_index + 1)
			if FileAccess.file_exists(source):
				var rename_error := _rename_file(source, destination)
				if rename_error != OK:
					return rename_error

		var first_backup := get_backup_path(slot_id, document_name, 1)
		var current_rename_error := _rename_file(current_path, first_backup)
		if current_rename_error != OK:
			return current_rename_error
		moved_current_to_backup = true

	var temporary_rename_error := _rename_file(temporary_path, current_path)
	if temporary_rename_error != OK:
		if moved_current_to_backup and not FileAccess.file_exists(current_path):
			_rename_file(get_backup_path(slot_id, document_name, 1), current_path)
		return temporary_rename_error
	return OK


func _make_temporary_path(slot_directory: String, document_name: String) -> String:
	var base := "%s.tmp-%d-%d" % [document_name, OS.get_process_id(), Time.get_ticks_usec()]
	var candidate := slot_directory.path_join("%s.json" % base)
	var suffix := 1
	while FileAccess.file_exists(candidate):
		candidate = slot_directory.path_join("%s-%d.json" % [base, suffix])
		suffix += 1
	return candidate


func _remove_stale_temp_files(slot_directory: String, document_name: String) -> void:
	var directory := DirAccess.open(slot_directory)
	if directory == null:
		return

	var prefix := "%s.tmp-" % document_name
	var stale_entries: Array[String] = []
	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		if (
			not directory.current_is_dir()
			and entry.begins_with(prefix)
			and entry.ends_with(".json")
		):
			stale_entries.append(entry)
		entry = directory.get_next()
	directory.list_dir_end()

	# Collect first; deleting while iterating a directory is not portable.
	for stale_entry in stale_entries:
		_remove_file_if_exists(slot_directory.path_join(stale_entry))


func _delete_directory_recursive(path: String) -> Error:
	var directory := DirAccess.open(path)
	if directory == null:
		return ERR_CANT_OPEN

	var children: Array[Dictionary] = []
	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		if entry != "." and entry != "..":
			children.append({"path": path.path_join(entry), "is_dir": directory.current_is_dir()})
		entry = directory.get_next()
	directory.list_dir_end()

	# Collect first; deleting while iterating a directory is not portable.
	for child in children:
		var child_path := String(child["path"])
		var child_error: Error
		if bool(child["is_dir"]):
			child_error = _delete_directory_recursive(child_path)
		else:
			child_error = DirAccess.remove_absolute(child_path)
		if child_error != OK:
			return child_error
	return DirAccess.remove_absolute(path)


static func _write_bytes_file(path: String, bytes: PackedByteArray) -> Error:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	if not bytes.is_empty() and not file.store_buffer(bytes):
		file.close()
		return ERR_FILE_CANT_WRITE
	file.flush()
	file.close()
	return OK


static func _read_bytes_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "error": "%s: file not found" % path, "bytes": PackedByteArray()}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {
			"ok": false,
			"error": "%s: cannot open file (error %d)" % [path, FileAccess.get_open_error()],
			"bytes": PackedByteArray(),
		}
	var bytes := file.get_buffer(file.get_length())
	file.close()
	return {"ok": true, "error": "", "bytes": bytes}


static func _rename_file(from_path: String, to_path: String) -> Error:
	var remove_error := _remove_file_if_exists(to_path)
	if remove_error != OK:
		return remove_error
	return DirAccess.rename_absolute(from_path, to_path)


static func _remove_file_if_exists(path: String) -> Error:
	if path.is_empty() or not FileAccess.file_exists(path):
		return OK
	return DirAccess.remove_absolute(path)


static func _failure(message: String) -> Dictionary:
	return {"ok": false, "path": "", "document": {}, "errors": [message]}


static func _is_valid_name(value: String) -> bool:
	return StableId.is_valid_segment(value)


static func _normalize_root_dir(value: String) -> String:
	var result := value.strip_edges()
	if result.is_empty():
		return DEFAULT_ROOT_DIR
	while result.length() > 1 and result.ends_with("/") and not result.ends_with("://"):
		result = result.substr(0, result.length() - 1)
	return result
