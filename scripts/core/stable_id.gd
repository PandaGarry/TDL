class_name StableId
extends RefCounted
## Stable, fully qualified content identifiers.
##
## Canonical form: `namespace:kind/name`, for example
## `core:species/navelu`. Runtime world state stores these strings instead
## of Godot object references. Segments intentionally use a narrow,
## lowercase ASCII snake_case grammar so identifiers remain stable across
## files, saves, network messages and future data mods.

const MAX_SEGMENT_LENGTH := 64
const MAX_ID_LENGTH := 192


static func is_valid(value: String) -> bool:
	if value.is_empty() or value.length() > MAX_ID_LENGTH or value.strip_edges() != value:
		return false

	var colon_parts := value.split(":")
	if colon_parts.size() != 2:
		return false
	if not is_valid_segment(colon_parts[0]):
		return false

	var path_parts := colon_parts[1].split("/")
	if path_parts.size() < 2:
		return false
	for part in path_parts:
		if not is_valid_segment(part):
			return false
	return true


static func namespace_of(value: String) -> String:
	if not is_valid(value):
		return ""
	return value.split(":")[0]


static func kind_of(value: String) -> String:
	if not is_valid(value):
		return ""
	var path := value.split(":")[1]
	return path.split("/")[0]


static func name_of(value: String) -> String:
	if not is_valid(value):
		return ""
	var path_parts := value.split(":")[1].split("/")
	path_parts.remove_at(0)
	return "/".join(path_parts)


static func make(namespace_name: String, kind: String, name: String) -> String:
	var candidate := "%s:%s/%s" % [namespace_name, kind, name]
	return candidate if is_valid(candidate) else ""


static func is_valid_segment(value: String) -> bool:
	if value.is_empty() or value.length() > MAX_SEGMENT_LENGTH:
		return false

	var first_code := value.unicode_at(0)
	if first_code < 97 or first_code > 122:  # a-z
		return false

	for index in range(value.length()):
		var code := value.unicode_at(index)
		var is_lowercase := code >= 97 and code <= 122
		var is_digit := code >= 48 and code <= 57
		var is_underscore := code == 95
		if not (is_lowercase or is_digit or is_underscore):
			return false
	return true
