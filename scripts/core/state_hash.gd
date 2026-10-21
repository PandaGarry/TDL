class_name StateHash
extends RefCounted
## Deterministic canonical encoding and SHA-256 hashing for domain state.
##
## This is a debugging/test seam: two authoritative states with the same
## domain values should produce the same hash even if dictionary insertion
## order differed. It is not a security mechanism and does not replace
## save-file checksums at the persistence boundary.


static func sha256_hex(value: Variant) -> String:
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		push_error("StateHash: failed to start SHA-256 context")
		return ""
	context.update(canonicalize(value).to_utf8_buffer())
	return context.finish().hex_encode()


static func canonicalize(value: Variant) -> String:
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
			return "%0.9f" % number
		TYPE_STRING, TYPE_STRING_NAME:
			return JSON.stringify(String(value))
		TYPE_VECTOR2:
			var vector: Vector2 = value
			return "[%s,%s]" % [canonicalize(vector.x), canonicalize(vector.y)]
		TYPE_ARRAY:
			return _canonicalize_array(value)
		TYPE_PACKED_BYTE_ARRAY:
			return _canonicalize_array(value)
		TYPE_PACKED_INT32_ARRAY:
			return _canonicalize_array(value)
		TYPE_PACKED_INT64_ARRAY:
			return _canonicalize_array(value)
		TYPE_PACKED_FLOAT32_ARRAY:
			return _canonicalize_array(value)
		TYPE_PACKED_FLOAT64_ARRAY:
			return _canonicalize_array(value)
		TYPE_PACKED_STRING_ARRAY:
			return _canonicalize_array(value)
		TYPE_DICTIONARY:
			var dictionary: Dictionary = value
			var keys: Array[String] = []
			for key in dictionary.keys():
				keys.append(String(key))
			keys.sort()
			var parts: Array[String] = []
			for key in keys:
				parts.append("%s:%s" % [JSON.stringify(key), canonicalize(dictionary[key])])
			return "{%s}" % ",".join(parts)
		_:
			return JSON.stringify("<unsupported:%d>" % typeof(value))


static func _canonicalize_array(value: Variant) -> String:
	var parts: Array[String] = []
	for item in value:
		parts.append(canonicalize(item))
	return "[%s]" % ",".join(parts)
