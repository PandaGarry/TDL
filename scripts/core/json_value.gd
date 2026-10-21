class_name JsonValue
extends RefCounted
## Helpers for values that cross JSON, save, network or mod-data boundaries.
##
## Core state deliberately accepts only JSON-safe primitives, arrays and
## string-keyed dictionaries at these boundaries. Godot-specific values such
## as Vector2 or object references must be encoded by their owning codec
## before they reach this layer.

const MAX_DEPTH := 32
const MAX_SAFE_INTEGER := 9007199254740991


static func is_safe(value: Variant, depth: int = 0) -> bool:
	if depth > MAX_DEPTH:
		return false
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_STRING, TYPE_STRING_NAME:
			return true
		TYPE_INT:
			# JSON parsers commonly round-trip numbers through IEEE-754
			# doubles. Larger integers must be encoded as strings by the
			# owning codec instead of pretending they are exact here.
			return int(value) >= -MAX_SAFE_INTEGER and int(value) <= MAX_SAFE_INTEGER
		TYPE_FLOAT:
			return is_finite(float(value))
		TYPE_ARRAY:
			for item in value:
				if not is_safe(item, depth + 1):
					return false
			return true
		TYPE_DICTIONARY:
			for key in value.keys():
				if typeof(key) != TYPE_STRING and typeof(key) != TYPE_STRING_NAME:
					return false
				if not is_safe(value[key], depth + 1):
					return false
			return true
		_:
			return false


## Deep-copies a JSON-safe value into the canonical in-memory shape used
## by domain state. JSON has one number type, so an integral finite double
## inside the exact-integer range becomes an `int`; fractional values stay
## `float`. This keeps StateHash stable across a save/load round-trip.
static func duplicate_canonical(value: Variant, depth: int = 0) -> Variant:
	if depth > MAX_DEPTH:
		return null
	match typeof(value):
		TYPE_FLOAT:
			var number := float(value)
			if (
				is_finite(number)
				and floor(number) == number
				and absf(number) <= float(MAX_SAFE_INTEGER)
			):
				return int(number)
			return 0.0 if number == 0.0 else number
		TYPE_ARRAY:
			var result: Array = []
			for item in value:
				result.append(duplicate_canonical(item, depth + 1))
			return result
		TYPE_DICTIONARY:
			var result: Dictionary = {}
			for key in value.keys():
				result[String(key)] = duplicate_canonical(value[key], depth + 1)
			return result
		TYPE_STRING_NAME:
			return String(value)
		_:
			return value


static func duplicate_safe(value: Variant, depth: int = 0) -> Variant:
	if depth > MAX_DEPTH:
		return null
	match typeof(value):
		TYPE_ARRAY:
			var result: Array = []
			for item in value:
				result.append(duplicate_safe(item, depth + 1))
			return result
		TYPE_DICTIONARY:
			var result: Dictionary = {}
			for key in value.keys():
				result[String(key)] = duplicate_safe(value[key], depth + 1)
			return result
		TYPE_STRING_NAME:
			return String(value)
		_:
			return value
