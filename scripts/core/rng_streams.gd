class_name RngStreams
extends RefCounted
## Named, reproducible random-number streams for domain simulation.
##
## Ecology, weather, society and genesis must not share one global random
## sequence: adding a draw in one system would silently change every other
## system. Each named stream is derived independently from the campaign's
## root seed, and its `RandomNumberGenerator.state` is snapshot-friendly.

const DEFAULT_STREAM := &"default"
const SCHEMA_VERSION := 1

var _root_seed: int = 0
var _streams: Dictionary = {}


func setup(root_seed: int) -> void:
	_root_seed = root_seed
	_streams.clear()


func root_seed() -> int:
	return _root_seed


func get_stream(stream_name: StringName = DEFAULT_STREAM) -> RandomNumberGenerator:
	var key := String(stream_name)
	if not StableId.is_valid_segment(key):
		push_warning("RngStreams: invalid stream name '%s', using default" % key)
		key = String(DEFAULT_STREAM)

	if _streams.has(key):
		return _streams[key] as RandomNumberGenerator

	var rng := RandomNumberGenerator.new()
	rng.seed = _derive_seed(key)
	_streams[key] = rng
	return rng


func randf_range(stream_name: StringName, from_value: float, to_value: float) -> float:
	return get_stream(stream_name).randf_range(from_value, to_value)


func randi_range(stream_name: StringName, from_value: int, to_value: int) -> int:
	return get_stream(stream_name).randi_range(from_value, to_value)


func chance(stream_name: StringName, probability: float) -> bool:
	return get_stream(stream_name).randf() < clampf(probability, 0.0, 1.0)


func snapshot_state() -> Dictionary:
	var stream_states: Dictionary = {}
	var names: Array = _streams.keys()
	names.sort()
	for stream_name in names:
		var rng := _streams[stream_name] as RandomNumberGenerator
		# RandomNumberGenerator.state is a full i64. Store it as text so a
		# JSON round-trip cannot silently round it through a double.
		stream_states[String(stream_name)] = str(rng.state)
	return {
		"schema_version": SCHEMA_VERSION,
		"root_seed": str(_root_seed),
		"streams": stream_states,
	}


func restore_state(snapshot: Dictionary) -> bool:
	var parsed_snapshot := _parse_snapshot(snapshot)
	if not bool(parsed_snapshot.get("ok", false)):
		return false

	# Commit only after the whole snapshot validated; a bad stream must
	# not leave the running campaign with a half-restored RNG state.
	setup(int(parsed_snapshot["root_seed"]))
	var parsed_states: Dictionary = parsed_snapshot["streams"]
	for stream_name in parsed_states.keys():
		get_stream(StringName(stream_name)).state = int(parsed_states[stream_name])
	return true


func _parse_snapshot(snapshot: Dictionary) -> Dictionary:
	var stream_states: Variant = snapshot.get("streams", null)
	if (
		_integer_value(snapshot.get("schema_version", -1)) != SCHEMA_VERSION
		or not snapshot.has("root_seed")
		or typeof(stream_states) != TYPE_DICTIONARY
	):
		return {"ok": false}

	var parsed_root_seed := _parse_i64(snapshot["root_seed"])
	if not bool(parsed_root_seed["ok"]):
		return {"ok": false}

	var parsed_states: Dictionary = {}
	for stream_name in stream_states.keys():
		var name_string := String(stream_name)
		var parsed_state := _parse_i64(stream_states[stream_name])
		if not StableId.is_valid_segment(name_string) or not bool(parsed_state["ok"]):
			return {"ok": false}
		parsed_states[name_string] = int(parsed_state["value"])

	return {
		"ok": true,
		"root_seed": int(parsed_root_seed["value"]),
		"streams": parsed_states,
	}


func _derive_seed(stream_name: String) -> int:
	# The stream is derived only from root_seed + stream name, never from
	# how many other streams happened to be created first. SHA-256 keeps
	# this derivation independent of Godot's internal String.hash choice.
	var digest := ("tdl-rng-v1|%d|%s" % [_root_seed, stream_name]).sha256_text()
	var seed := 0
	for index in range(15):
		seed = seed * 16 + _hex_digit_value(digest.unicode_at(index))
	return seed if seed != 0 else 1


static func _parse_i64(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_INT:
		return {"ok": true, "value": int(value)}
	if typeof(value) == TYPE_STRING or typeof(value) == TYPE_STRING_NAME:
		var text := String(value)
		if text.is_valid_int():
			var parsed := text.to_int()
			if str(parsed) == text:
				return {"ok": true, "value": parsed}
	return {"ok": false, "value": 0}


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


static func _hex_digit_value(code: int) -> int:
	if code >= 48 and code <= 57:
		return code - 48
	if code >= 97 and code <= 102:
		return code - 87
	if code >= 65 and code <= 70:
		return code - 55
	return 0
