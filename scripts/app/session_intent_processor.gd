class_name SessionIntentProcessor
extends RefCounted
## Host-side processing of one authenticated session intent.
##
## GameSession owns transport and publication. This processor owns the
## order-sensitive authority checks for a queued item: intent schema,
## participant binding, monotonic client sequence, body ownership and
## finally the greybox domain application. It returns an outcome that
## GameSession can publish as local/network events and signals.


static func process_item(
	world: WorldState,
	active_registry: DefinitionRegistry,
	participants: SessionParticipants,
	item: Dictionary,
	width_tiles: int,
	height_tiles: int
) -> Dictionary:
	var peer_id := int(item.get("peer_id", 0))
	var participant_id := String(item.get("participant_id", ""))
	var validation := SessionProtocol.validate_intent(item.get("intent", {}))
	if not bool(validation.get("ok", false)):
		return _rejected(
			peer_id,
			participant_id,
			{},
			"invalid_intent",
			String(validation.get("error", "invalid intent"))
		)

	var intent: Dictionary = validation.get("intent", {})
	var record := participants.record(participant_id)
	if record.is_empty():
		return _rejected(peer_id, participant_id, intent, "participant_not_bound", "")
	var sequence := int(validation.get("client_sequence", 0))
	if sequence <= int(record.get("last_client_sequence", 0)):
		return _rejected(peer_id, participant_id, intent, "duplicate_sequence", "")
	participants.set_last_client_sequence(participant_id, sequence)

	var body_entity_id := GreyboxWorld.find_body(world, participant_id)
	if body_entity_id < 1:
		return _rejected(peer_id, participant_id, intent, "body_not_found", "")
	var apply_report := GreyboxIntents.apply_intent(
		world,
		active_registry,
		participant_id,
		body_entity_id,
		String(validation.get("intent_type", "")),
		validation.get("payload", {}),
		width_tiles,
		height_tiles
	)
	if not bool(apply_report.get("ok", false)):
		return _rejected(
			peer_id,
			participant_id,
			intent,
			String(apply_report.get("reason", "intent_rejected")),
			String(apply_report.get("error", ""))
		)

	return {
		"ok": true,
		"participant_id": participant_id,
		"peer_id": peer_id,
		"intent": intent,
		"intent_type": String(intent.get("intent_type", "")),
		"client_sequence": sequence,
		"fact": apply_report.get("fact", {}),
		"rejection": {},
		"reason": "",
		"error": "",
	}


static func _rejected(
	peer_id: int, participant_id: String, intent: Dictionary, reason: String, error: String
) -> Dictionary:
	var sequence := int(
		SessionMessageValidator.integral_value(intent.get("client_sequence", 0)).get("value", 0)
	)
	var rejection := {
		"participant_id": participant_id,
		"peer_id": peer_id,
		"intent_type": String(intent.get("intent_type", "")),
		"client_sequence": sequence,
		"reason": reason,
		"error": error,
	}
	return {
		"ok": false,
		"participant_id": participant_id,
		"peer_id": peer_id,
		"intent": intent,
		"intent_type": String(intent.get("intent_type", "")),
		"client_sequence": sequence,
		"fact": {},
		"rejection": rejection,
		"reason": reason,
		"error": error,
	}
