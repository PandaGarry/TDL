class_name RngStreams
extends RefCounted
## Named, reproducible random-number streams for domain simulation.
##
## Ecology, weather, society and genesis must not share one global random
## sequence: adding a draw in one system would silently change every other
## system. Each named stream is derived independently from the campaign's
## root seed, and its `RandomNumberGenerator.state` is snapshot-friendly.

const DEFAULT_STREAM := &"default"

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
		stream_states[String(stream_name)] = rng.state
	return {
		"root_seed": _root_seed,
		"streams": stream_states,
	}


func restore_state(snapshot: Dictionary) -> bool:
	if not snapshot.has("root_seed") or not snapshot.has("streams"):
		return false
	var stream_states: Variant = snapshot["streams"]
	if typeof(stream_states) != TYPE_DICTIONARY:
		return false

	setup(int(snapshot["root_seed"]))
	for stream_name in stream_states.keys():
		var name_string := String(stream_name)
		if not StableId.is_valid_segment(name_string):
			return false
		get_stream(StringName(name_string)).state = int(stream_states[stream_name])
	return true


func _derive_seed(stream_name: String) -> int:
	# The stream is derived only from root_seed + stream name, never from
	# how many other streams happened to be created first.
	var mixed: int = _root_seed * 1103515245 + int(stream_name.hash())
	mixed ^= mixed >> 16
	mixed *= 2246822519
	mixed ^= mixed >> 13
	return mixed
