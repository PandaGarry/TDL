class_name FactLog
extends RefCounted
## Append-only journal of authoritative world facts.
##
## A fact records that something happened; it does not imply that every
## NPC observed or believes it. Observations, rumours and beliefs are a
## separate future knowledge layer.

const SCHEMA_VERSION := 1

var _facts: Array[Dictionary] = []
var _next_sequence: int = 1


func append_fact(
	kind: String,
	game_minute: int,
	payload: Dictionary = {},
	actor_id: int = -1,
	subject_id: String = ""
) -> Dictionary:
	if not StableId.is_valid_segment(kind):
		push_warning("FactLog.append_fact: invalid fact kind '%s'" % kind)
		return {}
	if game_minute < 0:
		push_warning("FactLog.append_fact: negative game_minute %d" % game_minute)
		return {}
	if actor_id < -1:
		push_warning("FactLog.append_fact: invalid actor_id %d" % actor_id)
		return {}
	if not JsonValue.is_safe(payload):
		push_warning("FactLog.append_fact: payload for '%s' is not JSON-safe" % kind)
		return {}
	if not subject_id.is_empty() and not StableId.is_valid(subject_id):
		push_warning("FactLog.append_fact: invalid subject_id '%s'" % subject_id)
		return {}

	var fact: Dictionary = {
		"sequence": _next_sequence,
		"kind": kind,
		"game_minute": game_minute,
		"actor_id": actor_id,
		"subject_id": subject_id,
		"payload": JsonValue.duplicate_canonical(payload),
	}
	_next_sequence += 1
	_facts.append(fact)
	return JsonValue.duplicate_safe(fact) as Dictionary


func size() -> int:
	return _facts.size()


func next_sequence() -> int:
	return _next_sequence


func compact_keeping_recent(keep_count: int) -> int:
	var bounded_keep := maxi(keep_count, 0)
	var remove_count := _facts.size() - bounded_keep
	if remove_count <= 0:
		return 0
	_facts = _facts.slice(remove_count, _facts.size())
	return remove_count


func facts() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for fact in _facts:
		result.append(JsonValue.duplicate_safe(fact) as Dictionary)
	return result


func last_facts(count: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if count <= 0:
		return result
	var first_index := maxi(0, _facts.size() - count)
	for index in range(first_index, _facts.size()):
		result.append(JsonValue.duplicate_safe(_facts[index]) as Dictionary)
	return result


func facts_of_kind(kind: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for fact in _facts:
		if String(fact.get("kind", "")) == kind:
			result.append(JsonValue.duplicate_safe(fact) as Dictionary)
	return result


func snapshot_state() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"next_sequence": _next_sequence,
		"facts": JsonValue.duplicate_safe(_facts),
	}


func restore_state(snapshot: Dictionary) -> bool:
	if int(snapshot.get("schema_version", 0)) != SCHEMA_VERSION:
		return false
	var raw_facts: Variant = snapshot.get("facts", null)
	if typeof(raw_facts) != TYPE_ARRAY:
		return false

	var restored: Array[Dictionary] = []
	var highest_sequence := 0
	for raw_fact in raw_facts:
		if typeof(raw_fact) != TYPE_DICTIONARY or not JsonValue.is_safe(raw_fact):
			return false
		var fact: Dictionary = JsonValue.duplicate_safe(raw_fact) as Dictionary
		if not _is_valid_restored_fact(fact, highest_sequence):
			return false
		_normalize_restored_fact(fact)
		highest_sequence = int(fact["sequence"])
		restored.append(fact)

	var parsed_next := _integral_value(snapshot.get("next_sequence", highest_sequence + 1))
	if not bool(parsed_next["ok"]):
		return false
	var stored_next := int(parsed_next["value"])
	_facts = restored
	_next_sequence = maxi(stored_next, highest_sequence + 1)
	return true


func _is_valid_restored_fact(fact: Dictionary, highest_sequence: int) -> bool:
	return (
		_has_required_fact_fields(fact)
		and _restored_fact_numbers_are_valid(fact, highest_sequence)
		and _restored_fact_strings_are_valid(fact)
		and typeof(fact["payload"]) == TYPE_DICTIONARY
	)


func _has_required_fact_fields(fact: Dictionary) -> bool:
	for required_field in [
		"sequence",
		"kind",
		"game_minute",
		"actor_id",
		"subject_id",
		"payload",
	]:
		if not fact.has(required_field):
			return false
	return true


func _restored_fact_numbers_are_valid(fact: Dictionary, highest_sequence: int) -> bool:
	var sequence := _integral_value(fact.get("sequence", 0))
	var game_minute := _integral_value(fact.get("game_minute", -1))
	var actor_id := _integral_value(fact.get("actor_id", -2))
	return (
		bool(sequence["ok"])
		and int(sequence["value"]) > highest_sequence
		and bool(game_minute["ok"])
		and int(game_minute["value"]) >= 0
		and bool(actor_id["ok"])
		and int(actor_id["value"]) >= -1
	)


func _restored_fact_strings_are_valid(fact: Dictionary) -> bool:
	var kind: Variant = fact.get("kind", null)
	var subject: Variant = fact.get("subject_id", null)
	var kind_is_string := typeof(kind) == TYPE_STRING or typeof(kind) == TYPE_STRING_NAME
	var subject_is_string := typeof(subject) == TYPE_STRING or typeof(subject) == TYPE_STRING_NAME
	if not kind_is_string or not subject_is_string:
		return false
	var subject_id := String(subject)
	return (
		StableId.is_valid_segment(String(kind))
		and (subject_id.is_empty() or StableId.is_valid(subject_id))
	)


func _normalize_restored_fact(fact: Dictionary) -> void:
	fact["sequence"] = int(_integral_value(fact["sequence"])["value"])
	fact["kind"] = String(fact["kind"])
	fact["game_minute"] = int(_integral_value(fact["game_minute"])["value"])
	fact["actor_id"] = int(_integral_value(fact["actor_id"])["value"])
	fact["subject_id"] = String(fact["subject_id"])
	fact["payload"] = JsonValue.duplicate_canonical(fact["payload"])


static func _integral_value(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_INT:
		return {"ok": true, "value": int(value)}
	if (
		typeof(value) == TYPE_FLOAT
		and is_finite(float(value))
		and floor(float(value)) == float(value)
	):
		return {"ok": true, "value": int(value)}
	return {"ok": false, "value": 0}


func clear() -> void:
	_facts.clear()
	_next_sequence = 1
