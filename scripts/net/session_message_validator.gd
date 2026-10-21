class_name SessionMessageValidator
extends RefCounted
## Strict payload validation for session handshake and snapshot messages.
##
## SessionProtocol validates the outer message envelope. This class
## validates the semantic payloads that can create a participant or
## replace a client's mirrored world. Keeping these checks pure and
## separate makes the untrusted-input boundary auditable without making
## GameSession studded with parser code.


static func validated_identity(
	participant_id: String, display_name: String, max_display_name_length: int
) -> Dictionary:
	var normalized_display := display_name.strip_edges()
	if not StableId.is_valid_segment(participant_id):
		return {"ok": false, "errors": ["participant_id must be a valid lowercase segment"]}
	if normalized_display.is_empty() or normalized_display.length() > max_display_name_length:
		return {
			"ok": false,
			"errors": ["display_name must contain 1..%d characters" % max_display_name_length]
		}
	return {
		"ok": true,
		"participant_id": participant_id,
		"display_name": normalized_display,
		"errors": [],
	}


static func validate_hello(
	payload: Dictionary, expected_game_version: String, expected_content_packages: Variant
) -> Dictionary:
	var reason := ""
	var participant_id := ""
	var display_name := ""
	var schema := integral_value(payload.get("world_schema_version", null))
	if not has_only_keys(
		payload,
		[
			"game_version",
			"world_schema_version",
			"content_packages",
			"participant_id",
			"display_name",
		]
	):
		reason = "invalid_hello"
	elif string_value(payload.get("game_version", null)) != expected_game_version:
		reason = "game_version_mismatch"
	elif (
		not bool(schema.get("ok", false))
		or int(schema.get("value", -1)) != WorldState.SCHEMA_VERSION
	):
		reason = "world_schema_mismatch"
	elif not _pins_equal(payload.get("content_packages", null), expected_content_packages):
		reason = "content_package_mismatch"
	else:
		var identity := validated_identity(
			string_value(payload.get("participant_id", null)),
			string_value(payload.get("display_name", null)),
			48
		)
		if bool(identity.get("ok", false)):
			participant_id = String(identity.get("participant_id", ""))
			display_name = String(identity.get("display_name", ""))
		else:
			reason = "invalid_participant"
	return {
		"ok": reason.is_empty(),
		"participant_id": participant_id,
		"display_name": display_name,
		"reason": reason,
	}


static func parse_welcome(payload: Dictionary, local_participant_id: String) -> Dictionary:
	var error := ""
	var body_entity_id := -1
	var next_client_sequence := 1
	var snapshot: Dictionary = {}
	if not has_only_keys(
		payload, ["participant_id", "body_entity_id", "next_client_sequence", "snapshot"]
	):
		error = "welcome payload has invalid fields"
	elif string_value(payload.get("participant_id", null)) != local_participant_id:
		error = "welcome participant does not match the local participant"
	else:
		var body_parse := integral_value(payload.get("body_entity_id", null))
		var sequence_parse := integral_value(payload.get("next_client_sequence", null))
		var snapshot_value: Variant = payload.get("snapshot", null)
		if not bool(body_parse.get("ok", false)) or int(body_parse.get("value", -1)) < 1:
			error = "welcome body_entity_id is invalid"
		elif not bool(sequence_parse.get("ok", false)) or int(sequence_parse.get("value", 0)) < 1:
			error = "welcome next_client_sequence is invalid"
		elif typeof(snapshot_value) != TYPE_DICTIONARY:
			error = "welcome snapshot is missing"
		else:
			body_entity_id = int(body_parse.get("value", -1))
			next_client_sequence = int(sequence_parse.get("value", 1))
			snapshot = snapshot_value
	return {
		"ok": error.is_empty(),
		"body_entity_id": body_entity_id,
		"next_client_sequence": next_client_sequence,
		"snapshot": snapshot,
		"error": error,
	}


static func validated_snapshot_world(
	payload: Dictionary, active_registry: DefinitionRegistry, expected_content_packages: Array
) -> Dictionary:
	var error := ""
	var restored := WorldState.new()
	var actual_hash := ""
	if not has_only_keys(
		payload, ["world_snapshot", "state_hash", "participants", "greybox_object_entity_id"]
	):
		error = "snapshot payload has invalid fields"
	else:
		var snapshot_value: Variant = payload.get("world_snapshot", null)
		var participants_value: Variant = payload.get("participants", null)
		var object_id := integral_value(payload.get("greybox_object_entity_id", null))
		if typeof(snapshot_value) != TYPE_DICTIONARY:
			error = "snapshot world payload is missing"
		elif not _participants_payload_is_valid(participants_value):
			error = "snapshot participants payload is invalid"
		elif not bool(object_id.get("ok", false)) or int(object_id.get("value", -1)) < 1:
			error = "snapshot greybox object ID is invalid"
		elif not restored.restore_state(snapshot_value):
			error = "snapshot world payload failed validation"
		else:
			var definition_errors := GreyboxWorld.validate_world_definitions(
				restored, active_registry
			)
			actual_hash = StateHash.sha256_hex(restored.snapshot_state())
			if not _pins_equal(restored.content_packages(), expected_content_packages):
				error = "snapshot content package pins do not match the client registry"
			elif not definition_errors.is_empty():
				error = definition_errors[0]
			elif string_value(payload.get("state_hash", null)) != actual_hash:
				error = "snapshot state hash mismatch"
			elif GreyboxWorld.find_supply_object(restored) != int(object_id.get("value", -1)):
				error = "snapshot greybox object does not match the world"
	return {
		"ok": error.is_empty(),
		"world": restored if error.is_empty() else null,
		"state_hash": actual_hash,
		"error": error,
	}


static func integral_value(value: Variant) -> Dictionary:
	match typeof(value):
		TYPE_INT:
			var int_value := int(value)
			if int_value >= -JsonValue.MAX_SAFE_INTEGER and int_value <= JsonValue.MAX_SAFE_INTEGER:
				return {"ok": true, "value": int_value}
		TYPE_FLOAT:
			var float_value := float(value)
			if (
				is_finite(float_value)
				and float_value == floorf(float_value)
				and absf(float_value) <= float(JsonValue.MAX_SAFE_INTEGER)
			):
				return {"ok": true, "value": int(float_value)}
	return {"ok": false, "value": 0}


static func string_value(value: Variant) -> String:
	return String(value) if typeof(value) == TYPE_STRING else ""


static func has_only_keys(value: Dictionary, required_keys: Array) -> bool:
	if value.size() != required_keys.size():
		return false
	for raw_key in value.keys():
		if typeof(raw_key) != TYPE_STRING or not required_keys.has(String(raw_key)):
			return false
	return true


static func _pins_equal(left: Variant, right: Variant) -> bool:
	return (
		typeof(left) == TYPE_ARRAY
		and typeof(right) == TYPE_ARRAY
		and JsonValue.is_safe(left)
		and JsonValue.is_safe(right)
		and (
			StateHash.sha256_hex(JsonValue.duplicate_canonical(left))
			== StateHash.sha256_hex(JsonValue.duplicate_canonical(right))
		)
	)


static func _participants_payload_is_valid(raw_participants: Variant) -> bool:
	if typeof(raw_participants) != TYPE_ARRAY:
		return false
	for raw_record in raw_participants:
		if typeof(raw_record) != TYPE_DICTIONARY:
			return false
		var record: Dictionary = raw_record
		var body_id := integral_value(record.get("body_entity_id", null))
		if (
			not has_only_keys(
				record, ["participant_id", "display_name", "body_entity_id", "connected", "is_host"]
			)
			or not StableId.is_valid_segment(string_value(record.get("participant_id", null)))
			or string_value(record.get("display_name", null)).strip_edges().is_empty()
			or not bool(body_id.get("ok", false))
			or int(body_id.get("value", -1)) < 1
			or typeof(record.get("connected", null)) != TYPE_BOOL
			or typeof(record.get("is_host", null)) != TYPE_BOOL
		):
			return false
	return true
