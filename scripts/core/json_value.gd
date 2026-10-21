class_name JsonValue
extends RefCounted
## Helpers for values that cross JSON, save, network or mod-data boundaries.
##
## Core state deliberately accepts only JSON-safe primitives, arrays and
## string-keyed dictionaries at these boundaries. Godot-specific values such
## as Vector2 or object references must be encoded by their owning codec
## before they reach this layer.


static func is_safe(value: Variant) -> bool:
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_STRING, TYPE_STRING_NAME:
			return true
		TYPE_FLOAT:
			return is_finite(float(value))
		TYPE_ARRAY:
			for item in value:
				if not is_safe(item):
					return false
			return true
		TYPE_DICTIONARY:
			for key in value.keys():
				if typeof(key) != TYPE_STRING and typeof(key) != TYPE_STRING_NAME:
					return false
				if not is_safe(value[key]):
					return false
			return true
		_:
			return false


static func duplicate_safe(value: Variant) -> Variant:
	match typeof(value):
		TYPE_ARRAY:
			var result: Array = []
			for item in value:
				result.append(duplicate_safe(item))
			return result
		TYPE_DICTIONARY:
			var result: Dictionary = {}
			for key in value.keys():
				result[String(key)] = duplicate_safe(value[key])
			return result
		TYPE_STRING_NAME:
			return String(value)
		_:
			return value
