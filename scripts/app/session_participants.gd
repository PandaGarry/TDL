class_name SessionParticipants
extends RefCounted
## Runtime participant-to-body membership for one GameSession.
##
## Participant identity and body ownership are persisted indirectly in
## WorldState body components. Peer IDs, connection state, the 90-second
## emergency disconnect grace window and the last consumed client
## sequence are runtime-only facts and therefore live here instead of
## being written into the campaign save.

const EMERGENCY_DISCONNECT_GRACE_SECONDS := 90.0

var _records: Dictionary = {}
var _peer_to_participant: Dictionary = {}


func clear() -> void:
	_records.clear()
	_peer_to_participant.clear()


func rebuild_from_world(world: WorldState) -> void:
	var previous: Dictionary = _records.duplicate(true)
	_records.clear()
	_peer_to_participant.clear()
	for body_record in GreyboxWorld.body_records(world):
		var participant_id := String(body_record.get("participant_id", ""))
		var old_record: Dictionary = previous.get(participant_id, {})
		var peer_id := int(old_record.get("peer_id", 0))
		_records[participant_id] = {
			"participant_id": participant_id,
			"peer_id": peer_id,
			"body_entity_id": int(body_record.get("body_entity_id", -1)),
			"display_name": String(body_record.get("display_name", "")),
			"connected": bool(old_record.get("connected", false)),
			"last_client_sequence": int(old_record.get("last_client_sequence", 0)),
			"disconnect_grace_remaining_sec":
			float(old_record.get("disconnect_grace_remaining_sec", 0.0)),
			"sheltered_after_disconnect": bool(old_record.get("sheltered_after_disconnect", false)),
		}
		if peer_id > 0:
			_peer_to_participant[peer_id] = participant_id


func upsert_record(
	participant_id: String, peer_id: int, display_name: String, body_entity_id: int, connected: bool
) -> Dictionary:
	var existing: Dictionary = _records.get(participant_id, {})
	var record := {
		"participant_id": participant_id,
		"peer_id": peer_id,
		"body_entity_id": body_entity_id,
		"display_name": display_name,
		"connected": connected,
		"last_client_sequence": int(existing.get("last_client_sequence", 0)),
		"disconnect_grace_remaining_sec":
		0.0 if connected else float(existing.get("disconnect_grace_remaining_sec", 0.0)),
		"sheltered_after_disconnect":
		false if connected else bool(existing.get("sheltered_after_disconnect", false)),
	}
	_records[participant_id] = record
	if peer_id > 0:
		_peer_to_participant[peer_id] = participant_id
	return record.duplicate(true)


func record(participant_id: String) -> Dictionary:
	var stored: Variant = _records.get(participant_id, {})
	return (stored as Dictionary).duplicate(true) if stored is Dictionary else {}


func participant_id_for_peer(peer_id: int) -> String:
	return String(_peer_to_participant.get(peer_id, ""))


func binding_rejection(peer_id: int, participant_id: String) -> String:
	var peer_participant := participant_id_for_peer(peer_id)
	var existing_record := record(participant_id)
	if not peer_participant.is_empty() and peer_participant != participant_id:
		return "peer_already_bound"
	if (
		not existing_record.is_empty()
		and bool(existing_record.get("connected", false))
		and int(existing_record.get("peer_id", 0)) != peer_id
	):
		return "participant_in_use"
	return ""


func set_last_client_sequence(participant_id: String, client_sequence: int) -> void:
	if not _records.has(participant_id):
		return
	var stored := record(participant_id)
	stored["last_client_sequence"] = client_sequence
	_records[participant_id] = stored


func set_connected(participant_id: String, connected: bool) -> void:
	if not _records.has(participant_id):
		return
	var stored := record(participant_id)
	stored["connected"] = connected
	if connected:
		stored["disconnect_grace_remaining_sec"] = 0.0
		stored["sheltered_after_disconnect"] = false
	_records[participant_id] = stored


func disconnect_peer(
	peer_id: int, grace_seconds: float = EMERGENCY_DISCONNECT_GRACE_SECONDS
) -> Dictionary:
	var participant_id := participant_id_for_peer(peer_id)
	if participant_id.is_empty():
		return {}
	var stored := record(participant_id)
	stored["peer_id"] = 0
	stored["connected"] = false
	stored["disconnect_grace_remaining_sec"] = maxf(grace_seconds, 0.0)
	stored["sheltered_after_disconnect"] = false
	_records[participant_id] = stored
	_peer_to_participant.erase(peer_id)
	return stored.duplicate(true)


func advance_disconnect_grace(world: WorldState, seconds: float) -> Array[Dictionary]:
	var sheltered_list: Array[Dictionary] = []
	if seconds <= 0.0 or not is_finite(seconds):
		return sheltered_list
	var ids: Array = _records.keys()
	ids.sort()
	for raw_id in ids:
		var participant_id := String(raw_id)
		var stored := record(participant_id)
		if bool(stored.get("connected", false)):
			continue
		var remaining := float(stored.get("disconnect_grace_remaining_sec", 0.0))
		var already_sheltered := bool(stored.get("sheltered_after_disconnect", false))
		if remaining <= 0.0 or already_sheltered:
			continue
		var next_remaining := maxf(0.0, remaining - seconds)
		stored["disconnect_grace_remaining_sec"] = next_remaining
		if next_remaining == 0.0:
			stored["sheltered_after_disconnect"] = true
			var body_entity_id := int(stored.get("body_entity_id", -1))
			if world != null and world.is_initialized():
				var configured_grace := int(round(world.world_rules().disconnect_grace_seconds()))
				set_body_sheltered(world, body_entity_id, true)
				(
					world
					. fact_log()
					. append_fact(
						"participant_sheltered",
						world.clock().total_minutes(),
						{
							"participant_id": participant_id,
							"entity_id": body_entity_id,
							"grace_seconds": configured_grace,
						},
						body_entity_id,
						GreyboxWorld.BODY_DEFINITION_ID
					)
				)
			sheltered_list.append(stored.duplicate(true))
		_records[participant_id] = stored
	return sheltered_list


static func set_body_sheltered(world: WorldState, body_entity_id: int, sheltered: bool) -> void:
	if world == null or not world.is_initialized() or body_entity_id < 1:
		return
	var body_comp := world.get_entity_component(body_entity_id, GreyboxWorld.BODY_COMPONENT)
	if body_comp.is_empty():
		return
	if sheltered:
		body_comp["sheltered"] = true
	else:
		body_comp.erase("sheltered")
	world.set_entity_component(body_entity_id, GreyboxWorld.BODY_COMPONENT, body_comp)


func disconnect_grace_summary() -> Dictionary:
	var summary: Dictionary = {}
	var ids: Array = _records.keys()
	ids.sort()
	for raw_id in ids:
		var participant_id := String(raw_id)
		var stored := record(participant_id)
		if bool(stored.get("connected", false)):
			continue
		summary[participant_id] = {
			"remaining_sec": float(stored.get("disconnect_grace_remaining_sec", 0.0)),
			"sheltered": bool(stored.get("sheltered_after_disconnect", false)),
			"body_entity_id": int(stored.get("body_entity_id", -1)),
		}
	return summary


func authenticated_peer_ids() -> Array[int]:
	var result: Array[int] = []
	for raw_peer_id in _peer_to_participant.keys():
		result.append(int(raw_peer_id))
	result.sort()
	return result


func public_records(world: WorldState, host_participant_id: String = "") -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for body_record in GreyboxWorld.body_records(world):
		var participant_id := String(body_record.get("participant_id", ""))
		var runtime_record := record(participant_id)
		var is_host := participant_id == host_participant_id
		if host_participant_id.is_empty():
			is_host = int(runtime_record.get("peer_id", 0)) == 1
		(
			result
			. append(
				{
					"participant_id": participant_id,
					"display_name": String(body_record.get("display_name", "")),
					"body_entity_id": int(body_record.get("body_entity_id", -1)),
					"connected": bool(runtime_record.get("connected", false)),
					"is_host": is_host,
				}
			)
		)
	result.sort_custom(_compare_records)
	return result


func overlay_public_records(
	raw_records: Variant, local_participant_id: String, local_peer_id: int
) -> void:
	if typeof(raw_records) != TYPE_ARRAY:
		return
	for raw_record in raw_records:
		if typeof(raw_record) != TYPE_DICTIONARY:
			continue
		var public_record: Dictionary = raw_record
		var participant_id := GreyboxWorld.string_value(public_record.get("participant_id", null))
		if not _records.has(participant_id):
			continue
		var stored := record(participant_id)
		stored["connected"] = bool(public_record.get("connected", false))
		stored["body_entity_id"] = int(
			GreyboxWorld.integral_value(public_record.get("body_entity_id", null)).get("value", -1)
		)
		if participant_id == local_participant_id:
			stored["peer_id"] = local_peer_id
		elif bool(public_record.get("is_host", false)):
			stored["peer_id"] = 1
		else:
			stored["peer_id"] = 0
		_records[participant_id] = stored
		var peer_id := int(stored.get("peer_id", 0))
		if peer_id > 0:
			_peer_to_participant[peer_id] = participant_id


static func _compare_records(left: Dictionary, right: Dictionary) -> bool:
	return String(left.get("participant_id", "")) < String(right.get("participant_id", ""))
