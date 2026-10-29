class_name DefinitionRegistry
extends RefCounted
## Loader and validator for immutable, versioned content definitions.
##
## The official `core` package and future data mods use the same entry
## point. A package is committed to the registry only if the whole package
## validates; malformed JSON or one broken definition must not leave a
## half-loaded world behind.

const PACKAGE_FORMAT := "tdl.content_package"
const DEFINITIONS_FORMAT := "tdl.definitions"
const SUPPORTED_SCHEMA_VERSION := 1

var _definitions: Dictionary = {}
var _ids_by_kind: Dictionary = {}
var _package_id: String = ""
var _package_version: String = ""
var _manifest_hash: String = ""
var _last_errors: Array[String] = []
var _last_warnings: Array[String] = []


func clear() -> void:
	_definitions.clear()
	_ids_by_kind.clear()
	_package_id = ""
	_package_version = ""
	_manifest_hash = ""


func load_package(manifest_path: String) -> Dictionary:
	var read_errors: Array[String] = []
	var no_warnings: Array[String] = []

	var manifest_result := _read_json_file(manifest_path)
	if not bool(manifest_result.get("ok", false)):
		read_errors.append(String(manifest_result.get("error", "Cannot read manifest")))
		clear()
		return _finish_report(false, read_errors, no_warnings, 0)

	var manifest_value: Variant = manifest_result.get("value", null)
	if typeof(manifest_value) != TYPE_DICTIONARY:
		read_errors.append("%s: manifest root must be an object" % manifest_path)
		clear()
		return _finish_report(false, read_errors, no_warnings, 0)

	var manifest: Dictionary = manifest_value
	var documents: Dictionary = {}
	var definition_files: Variant = manifest.get("definition_files", [])
	if typeof(definition_files) == TYPE_ARRAY:
		var base_directory := manifest_path.get_base_dir()
		for raw_path in definition_files:
			if typeof(raw_path) != TYPE_STRING:
				continue
			var relative_path := String(raw_path)
			if not _is_safe_relative_path(relative_path):
				continue
			var document_result := _read_json_file(base_directory.path_join(relative_path))
			if bool(document_result.get("ok", false)):
				documents[relative_path] = document_result.get("value", null)
			else:
				read_errors.append(String(document_result.get("error", "Cannot read definitions")))

	if not read_errors.is_empty():
		clear()
		return _finish_report(false, read_errors, no_warnings, 0)

	return load_package_documents(manifest, documents)


## Validates already parsed JSON documents. Keeping this seam separate from
## FileAccess lets tests exercise malformed packages without fixture files
## for every error branch.
func load_package_documents(manifest: Dictionary, documents_by_path: Dictionary) -> Dictionary:
	clear()
	var errors: Array[String] = []
	var warnings: Array[String] = []

	if not JsonValue.is_safe(manifest):
		errors.append("manifest contains non-JSON-safe values")
	if not JsonValue.is_safe(documents_by_path):
		errors.append("definition documents contain non-JSON-safe values")

	if String(manifest.get("format", "")) != PACKAGE_FORMAT:
		errors.append("manifest.format must be '%s'" % PACKAGE_FORMAT)
	if _integer_value(manifest.get("schema_version", -1)) != SUPPORTED_SCHEMA_VERSION:
		errors.append("manifest.schema_version must be %d" % SUPPORTED_SCHEMA_VERSION)

	var package_id := String(manifest.get("package_id", ""))
	if not StableId.is_valid_segment(package_id):
		errors.append("manifest.package_id must be a valid lowercase segment")

	var package_version := String(manifest.get("version", ""))
	if package_version.strip_edges().is_empty():
		errors.append("manifest.version must not be empty")

	var relative_paths: Array[String] = []
	var raw_definition_files: Variant = manifest.get("definition_files", null)
	if typeof(raw_definition_files) != TYPE_ARRAY or raw_definition_files.is_empty():
		errors.append("manifest.definition_files must be a non-empty array")
	else:
		for raw_path in raw_definition_files:
			if typeof(raw_path) != TYPE_STRING:
				errors.append("manifest.definition_files entries must be strings")
				continue
			var relative_path := String(raw_path)
			if not _is_safe_relative_path(relative_path):
				errors.append("Unsafe or non-JSON definition path: '%s'" % relative_path)
			elif relative_paths.has(relative_path):
				errors.append("Duplicate definition file in manifest: '%s'" % relative_path)
			else:
				relative_paths.append(relative_path)

	var temp_definitions: Dictionary = {}
	var temp_ids_by_kind: Dictionary = {}

	for relative_path in relative_paths:
		if not documents_by_path.has(relative_path):
			errors.append("%s: document was not supplied" % relative_path)
			continue

		var document_value: Variant = documents_by_path[relative_path]
		if typeof(document_value) != TYPE_DICTIONARY:
			errors.append("%s: root must be an object" % relative_path)
			continue
		var document: Dictionary = document_value

		if String(document.get("format", "")) != DEFINITIONS_FORMAT:
			errors.append("%s: format must be '%s'" % [relative_path, DEFINITIONS_FORMAT])
		if _integer_value(document.get("schema_version", -1)) != SUPPORTED_SCHEMA_VERSION:
			errors.append(
				"%s: schema_version must be %d" % [relative_path, SUPPORTED_SCHEMA_VERSION]
			)

		var raw_definitions: Variant = document.get("definitions", null)
		if typeof(raw_definitions) != TYPE_ARRAY:
			errors.append("%s: definitions must be an array" % relative_path)
			continue

		for index in range(raw_definitions.size()):
			var location := "%s definitions[%d]" % [relative_path, index]
			var raw_definition: Variant = raw_definitions[index]
			if typeof(raw_definition) != TYPE_DICTIONARY:
				errors.append("%s: definition must be an object" % location)
				continue
			if not JsonValue.is_safe(raw_definition):
				errors.append("%s: definition contains non-JSON-safe values" % location)
				continue

			var definition: Dictionary = JsonValue.duplicate_safe(raw_definition) as Dictionary
			var definition_id := String(definition.get("id", ""))
			var kind := String(definition.get("kind", ""))
			var name_key := String(definition.get("name_key", ""))

			if not StableId.is_valid(definition_id):
				errors.append("%s: invalid id '%s'" % [location, definition_id])
				continue
			if StableId.namespace_of(definition_id) != package_id:
				errors.append(
					"%s: id namespace must match package_id '%s'" % [location, package_id]
				)
			if not StableId.is_valid_segment(kind):
				errors.append("%s: invalid kind '%s'" % [location, kind])
			elif StableId.kind_of(definition_id) != kind:
				errors.append("%s: kind '%s' does not match id path" % [location, kind])
			if not _is_valid_localization_key(name_key):
				errors.append("%s: invalid name_key '%s'" % [location, name_key])

			_validate_optional_definition_fields(definition, location, errors)

			if temp_definitions.has(definition_id):
				errors.append("%s: duplicate id '%s'" % [location, definition_id])
				continue

			temp_definitions[definition_id] = definition
			var ids_for_kind: Array = temp_ids_by_kind.get(kind, [])
			ids_for_kind.append(definition_id)
			temp_ids_by_kind[kind] = ids_for_kind

	_validate_references(temp_definitions, errors)
	if temp_definitions.is_empty():
		errors.append("package must define at least one definition")

	if not errors.is_empty():
		return _finish_report(false, errors, warnings, 0)

	for kind in temp_ids_by_kind.keys():
		var sorted_ids: Array = temp_ids_by_kind[kind]
		sorted_ids.sort()
		temp_ids_by_kind[kind] = sorted_ids

	var sorted_definition_ids: Array[String] = []
	for definition_id in temp_definitions.keys():
		sorted_definition_ids.append(String(definition_id))
	sorted_definition_ids.sort()

	var sorted_definitions: Array = []
	for definition_id in sorted_definition_ids:
		sorted_definitions.append(temp_definitions[definition_id])

	_definitions = temp_definitions
	_ids_by_kind = temp_ids_by_kind
	_package_id = package_id
	_package_version = package_version
	_manifest_hash = (
		StateHash
		. sha256_hex(
			{
				"manifest": JsonValue.duplicate_safe(manifest),
				"definitions": sorted_definitions,
			}
		)
	)

	return _finish_report(true, errors, warnings, _definitions.size())


func has_definition(definition_id: String) -> bool:
	return _definitions.has(definition_id)


func get_definition(definition_id: String) -> Dictionary:
	if not _definitions.has(definition_id):
		return {}
	return JsonValue.duplicate_safe(_definitions[definition_id]) as Dictionary


func definition_count() -> int:
	return _definitions.size()


func definition_ids() -> Array[String]:
	var result: Array[String] = []
	for definition_id in _definitions.keys():
		result.append(String(definition_id))
	result.sort()
	return result


func ids_of_kind(kind: String) -> Array[String]:
	var result: Array[String] = []
	var stored: Variant = _ids_by_kind.get(kind, [])
	if typeof(stored) == TYPE_ARRAY:
		for definition_id in stored:
			result.append(String(definition_id))
	result.sort()
	return result


func package_id() -> String:
	return _package_id


func package_version() -> String:
	return _package_version


func manifest_hash() -> String:
	return _manifest_hash


func last_errors() -> Array[String]:
	return _last_errors.duplicate()


func last_warnings() -> Array[String]:
	return _last_warnings.duplicate()


func _validate_optional_definition_fields(
	definition: Dictionary, location: String, errors: Array[String]
) -> void:
	var raw_tags: Variant = definition.get("tags", [])
	if typeof(raw_tags) != TYPE_ARRAY:
		errors.append("%s: tags must be an array" % location)
	else:
		for raw_tag in raw_tags:
			if typeof(raw_tag) != TYPE_STRING or not StableId.is_valid_segment(String(raw_tag)):
				errors.append("%s: invalid tag '%s'" % [location, str(raw_tag)])

	var raw_properties: Variant = definition.get("properties", {})
	if typeof(raw_properties) != TYPE_DICTIONARY:
		errors.append("%s: properties must be an object" % location)

	var visual_profile := String(definition.get("visual_profile", ""))
	if not visual_profile.is_empty() and not StableId.is_valid(visual_profile):
		errors.append("%s: invalid visual_profile '%s'" % [location, visual_profile])

	var raw_references: Variant = definition.get("references", [])
	if typeof(raw_references) != TYPE_ARRAY:
		errors.append("%s: references must be an array" % location)
	else:
		for raw_reference in raw_references:
			if typeof(raw_reference) != TYPE_STRING or not StableId.is_valid(String(raw_reference)):
				errors.append("%s: invalid reference '%s'" % [location, str(raw_reference)])


func _validate_references(definitions: Dictionary, errors: Array[String]) -> void:
	var definition_ids: Array = definitions.keys()
	definition_ids.sort()
	for raw_id in definition_ids:
		var definition_id := String(raw_id)
		var definition: Dictionary = definitions[definition_id]
		var raw_references: Variant = definition.get("references", [])
		if typeof(raw_references) != TYPE_ARRAY:
			continue
		for raw_reference in raw_references:
			var reference_id := String(raw_reference)
			if StableId.is_valid(reference_id) and not definitions.has(reference_id):
				errors.append(
					"%s references unknown definition '%s'" % [definition_id, reference_id]
				)


func _read_json_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "error": "%s: file not found" % path}

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {
			"ok": false,
			"error": "%s: cannot open file (error %d)" % [path, FileAccess.get_open_error()],
		}

	var text := file.get_as_text()
	file.close()

	var json := JSON.new()
	var parse_error := json.parse(text)
	if parse_error != OK:
		return {
			"ok": false,
			"error": "%s:%d: %s" % [path, json.get_error_line(), json.get_error_message()],
		}
	return {"ok": true, "value": json.data}


func _finish_report(
	ok: bool, errors: Array[String], warnings: Array[String], count: int
) -> Dictionary:
	_last_errors = errors.duplicate()
	_last_warnings = warnings.duplicate()
	return {
		"ok": ok,
		"errors": _last_errors.duplicate(),
		"warnings": _last_warnings.duplicate(),
		"definition_count": count,
		"package_id": _package_id,
		"package_version": _package_version,
		"manifest_hash": _manifest_hash,
	}


static func _integer_value(value: Variant) -> int:
	if typeof(value) == TYPE_INT:
		return int(value)
	if (
		typeof(value) == TYPE_FLOAT
		and is_finite(float(value))
		and floor(float(value)) == float(value)
	):
		return int(value)
	return -1


static func _is_safe_relative_path(path: String) -> bool:
	if path.is_empty() or not path.ends_with(".json"):
		return false
	if path.begins_with("/") or path.contains(":") or path.contains("\\"):
		return false
	for segment in path.split("/"):
		if segment.is_empty() or segment == "." or segment == "..":
			return false
	return true


static func _is_valid_localization_key(value: String) -> bool:
	if value.is_empty() or value.strip_edges() != value:
		return false
	for segment in value.split("."):
		if not StableId.is_valid_segment(segment):
			return false
	return true
