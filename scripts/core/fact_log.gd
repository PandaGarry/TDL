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
		"payload": JsonValue.duplicate_safe(payload),
	}
	_next_sequence += 1
	_facts.append(fact)
	return JsonValue.duplicate_safe(fact) as Dictionary


func size() -> int:
	return _facts.size()


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
		highest_sequence = int(fact["sequence"])
		restored.append(fact)

	var stored_next := int(snapshot.get("next_sequence", highest_sequence + 1))
	_facts = restored
	_next_sequence = maxi(stored_next, highest_sequence + 1)
	return true


func _is_valid_restored_fact(fact: Dictionary, highest_sequence: int) -> bool:
	if int(fact.get("sequence", 0)) <= highest_sequence:
		return false
	if not StableId.is_valid_segment(String(fact.get("kind", ""))):
		return false
	return int(fact.get("game_minute", -1)) >= 0


func clear() -> void:
	_facts.clear()
	_next_sequence = 1
