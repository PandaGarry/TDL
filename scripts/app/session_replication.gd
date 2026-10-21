class_name SessionReplication
extends RefCounted
## Packet encoding, handshake acceptance, snapshot envelope construction and
## peer broadcast helpers for `GameSession`.
##
## Extracted from `GameSession` so the session composition root stays
## focused on authority transitions, scheduling, `WorldRules` and
## persistence orchestration.

const LOCAL_PEER_ID := 1


static func bind_transport(transport: SessionTransport, target: Object) -> void:
	if transport == null or target == null:
		return
	transport.peer_connected.connect(Callable(target, "_on_transport_peer_connected"))
	transport.peer_disconnected.connect(Callable(target, "_on_transport_peer_disconnected"))
	transport.packet_received.connect(Callable(target, "_on_transport_packet_received"))
	transport.connected_to_server.connect(Callable(target, "_on_transport_connected_to_server"))
	transport.connection_failed.connect(Callable(target, "_on_transport_connection_failed"))
	transport.server_disconnected.connect(Callable(target, "_on_transport_server_disconnected"))


static func unbind_and_close_transport(transport: SessionTransport, target: Object) -> void:
	if transport == null:
		return
	if target != null:
		var pairs := [
			[transport.peer_connected, "_on_transport_peer_connected"],
			[transport.peer_disconnected, "_on_transport_peer_disconnected"],
			[transport.packet_received, "_on_transport_packet_received"],
			[transport.connected_to_server, "_on_transport_connected_to_server"],
			[transport.connection_failed, "_on_transport_connection_failed"],
			[transport.server_disconnected, "_on_transport_server_disconnected"],
		]
		for pair in pairs:
			var sig: Signal = pair[0]
			var callable := Callable(target, String(pair[1]))
			if sig.is_connected(callable):
				sig.disconnect(callable)
	transport.close()


static func accept_hello(
	peer_id: int,
	payload: Dictionary,
	game_version: String,
	world: WorldState,
	registry: DefinitionRegistry,
	participants: SessionParticipants,
	max_players: int,
	width_tiles: int,
	height_tiles: int
) -> Dictionary:
	var validation := SessionMessageValidator.validate_hello(
		payload, game_version, world.content_packages()
	)
	if not bool(validation.get("ok", false)):
		return {
			"ok": false,
			"participant_id": "",
			"reason": String(validation.get("reason", "invalid_hello")),
		}
	var participant_id := String(validation.get("participant_id", ""))
	var display_name := String(validation.get("display_name", ""))
	var binding_rejection := participants.binding_rejection(peer_id, participant_id)
	if not binding_rejection.is_empty():
		return {
			"ok": false,
			"participant_id": participant_id,
			"reason": binding_rejection,
		}
	var spawn_report := GreyboxWorld.spawn_body(
		world, registry, participant_id, display_name, max_players, width_tiles, height_tiles
	)
	if not bool(spawn_report.get("ok", false)):
		return {
			"ok": false,
			"participant_id": participant_id,
			"reason": "session_full",
		}
	var body_entity_id := int(spawn_report.get("body_entity_id", -1))
	var existing_record := participants.record(participant_id)
	var already_connected := (
		bool(existing_record.get("connected", false))
		and int(existing_record.get("peer_id", 0)) == peer_id
	)
	SessionParticipants.set_body_sheltered(world, body_entity_id, false)
	var record := participants.upsert_record(
		participant_id, peer_id, display_name, body_entity_id, true
	)
	return {
		"ok": true,
		"participant_id": participant_id,
		"body_entity_id": body_entity_id,
		"created": bool(spawn_report.get("created", false)),
		"already_connected": already_connected,
		"next_client_sequence": int(record.get("last_client_sequence", 0)) + 1,
	}


static func send_message_to_peer(
	transport: SessionTransport, peer_id: int, tick: int, kind: String, payload: Dictionary
) -> Error:
	if transport == null:
		return ERR_UNCONFIGURED
	var packet := SessionProtocol.encode_message(SessionProtocol.make_message(kind, tick, payload))
	if packet.is_empty():
		return ERR_INVALID_DATA
	return transport.send_packet(peer_id, packet, true)


static func send_message_to_authenticated(
	transport: SessionTransport,
	participants: SessionParticipants,
	tick: int,
	kind: String,
	payload: Dictionary,
	excluded_peer_id: int = 0
) -> void:
	if transport == null or participants == null:
		return
	for peer_id in participants.authenticated_peer_ids():
		if peer_id == LOCAL_PEER_ID or peer_id == excluded_peer_id:
			continue
		send_message_to_peer(transport, peer_id, tick, kind, payload)


static func make_rejection(
	peer_id: int, participant_id: String, intent: Dictionary, reason: String, error: String
) -> Dictionary:
	return {
		"participant_id": participant_id,
		"peer_id": peer_id,
		"intent_type": String(intent.get("intent_type", "")),
		"client_sequence":
		int(
			SessionMessageValidator.integral_value(intent.get("client_sequence", 0)).get("value", 0)
		),
		"reason": reason,
		"error": error,
	}


static func make_snapshot_payload(
	world: WorldState,
	state_hash: String,
	public_participants: Array[Dictionary],
	greybox_object_entity_id: int
) -> Dictionary:
	return {
		"world_snapshot": world.snapshot_state(),
		"state_hash": state_hash,
		"participants": public_participants,
		"greybox_object_entity_id": greybox_object_entity_id,
	}


static func make_hello_payload(
	game_version: String, registry: DefinitionRegistry, participant_id: String, display_name: String
) -> Dictionary:
	return {
		"game_version": game_version,
		"world_schema_version": WorldState.SCHEMA_VERSION,
		"content_packages": [SessionWorldLoader.package_pin_for_registry(registry)],
		"participant_id": participant_id,
		"display_name": display_name,
	}


static func make_welcome_payload(
	participant_id: String,
	body_entity_id: int,
	next_client_sequence: int,
	snapshot_payload: Dictionary
) -> Dictionary:
	return {
		"participant_id": participant_id,
		"body_entity_id": body_entity_id,
		"next_client_sequence": next_client_sequence,
		"snapshot": snapshot_payload,
	}


static func load_metadata(prepared: Dictionary, slot_id: String) -> Dictionary:
	var loaded: Dictionary = prepared.get("loaded", {})
	return {
		"fresh_campaign": false,
		"slot_id": slot_id,
		"loaded_path": String(loaded.get("path", "")),
		"recovered": bool(loaded.get("recovered", false)),
		"migrated": bool(loaded.get("migrated", false)),
		"source_schema_version": int(loaded.get("source_schema_version", -1)),
		"package_pins_reconciled": bool(prepared.get("package_pins_reconciled", false)),
		"warnings": prepared.get("warnings", []),
	}


static func transport_peer_ids(transport: SessionTransport) -> Array[int]:
	var result: Array[int] = []
	if transport == null:
		return result
	for peer_id in transport.get_peers():
		result.append(peer_id)
	return result
