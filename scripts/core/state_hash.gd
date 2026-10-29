class_name StateHash
extends RefCounted
## Deterministic canonical encoding and SHA-256 hashing for domain state.
##
## This is a debugging/test seam: two authoritative states with the same
## domain values should produce the same hash even if dictionary insertion
## order differed. It is not a security mechanism and does not replace
## save-file checksums at the persistence boundary.

const MAX_DEPTH := 32


static func sha256_hex(value: Variant) -> String:
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		push_error("StateHash: failed to start SHA-256 context")
		return ""
	context.update(canonicalize(value).to_utf8_buffer())
	return context.finish().hex_encode()


static func canonicalize(value: Variant, depth: int = 0) -> String:
	if depth > MAX_DEPTH:
		return JSON.stringify("<max_depth>")
	match typeof(value):
		TYPE_NIL:
			return "null"
		TYPE_BOOL:
			return "true" if bool(value) else "false"
		TYPE_INT:
			return str(int(value))
		TYPE_FLOAT:
			var number := float(value)
			if is_nan(number):
				return "nan"
			if is_inf(number):
				return "inf" if number > 0.0 else "-inf"
			if number == 0.0:
				number = 0.0
			return "f64:%s" % var_to_bytes(number).hex_encode()
		TYPE_STRING, TYPE_STRING_NAME:
			return JSON.stringify(String(value))
		TYPE_VECTOR2:
			var vector: Vector2 = value
			return (
				"[%s,%s]" % [canonicalize(vector.x, depth + 1), canonicalize(vector.y, depth + 1)]
			)
		TYPE_ARRAY:
			return _canonicalize_array(value, depth + 1)
		TYPE_PACKED_BYTE_ARRAY:
			return _canonicalize_array(value, depth + 1)
		TYPE_PACKED_INT32_ARRAY:
			return _canonicalize_array(value, depth + 1)
		TYPE_PACKED_INT64_ARRAY:
			return _canonicalize_array(value, depth + 1)
		TYPE_PACKED_FLOAT32_ARRAY:
			return _canonicalize_array(value, depth + 1)
		TYPE_PACKED_FLOAT64_ARRAY:
			return _canonicalize_array(value, depth + 1)
		TYPE_PACKED_STRING_ARRAY:
			return _canonicalize_array(value, depth + 1)
		TYPE_DICTIONARY:
			var dictionary: Dictionary = value
			var encoded_keys: Array[String] = []
			var values_by_encoded_key: Dictionary = {}
			for key in dictionary.keys():
				var encoded_key := canonicalize(key, depth + 1)
				encoded_keys.append(encoded_key)
				values_by_encoded_key[encoded_key] = dictionary[key]
			encoded_keys.sort()
			var parts: Array[String] = []
			for encoded_key in encoded_keys:
				parts.append(
					(
						"%s:%s"
						% [encoded_key, canonicalize(values_by_encoded_key[encoded_key], depth + 1)]
					)
				)
			return "{%s}" % ",".join(parts)
		_:
			return JSON.stringify("<unsupported:%d>" % typeof(value))


static func _canonicalize_array(value: Variant, depth: int) -> String:
	var parts: Array[String] = []
	for item in value:
		parts.append(canonicalize(item, depth))
	return "[%s]" % ",".join(parts)
