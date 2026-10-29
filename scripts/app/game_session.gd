class_name GameSession
extends Node
## Authoritative composition root for one campaign session.
##
## Owns the runtime relationship between DefinitionRegistry, WorldState,
## SimulationScheduler, SaveStore and SessionTransport. Solo and networked
## play share the same host intent pipeline; clients never mutate their
## mirrored WorldState or write campaign saves.

signal session_started(status: Dictionary)
signal session_stopped
signal session_error(message: String)
signal participant_joined(participant_id: String, body_entity_id: int)
signal participant_disconnected(participant_id: String, body_entity_id: int)
signal intent_applied(intent: Dictionary, fact: Dictionary)
signal intent_rejected(rejection: Dictionary)
signal snapshot_applied(state_hash: String)

enum Role { INACTIVE, HOST, CLIENT }

const LOCAL_PEER_ID := 1
const DEFAULT_PORT := 24731
const DEFAULT_MAX_PLAYERS := 4
const MAX_INTENTS_PER_BATCH := 128
const MAX_PENDING_INTENTS := 256
const MAX_DISPLAY_NAME_LENGTH := 48

@export var content_manifest_path: String = "res://data/core/manifest.json"
@export var save_root_dir: String = "user://saves/campaigns"
@export_range(1, 20, 1) var save_backup_count: int = 5
@export var game_version_override: String = ""
@export_range(1, 4, 1) var max_players: int = DEFAULT_MAX_PLAYERS
@export_range(8, 256, 1) var greybox_width_tiles: int = 32
@export_range(8, 256, 1) var greybox_height_tiles: int = 24
@export var auto_tick_enabled: bool = false
@export var game_minutes_per_real_second: float = 2.0

var _registry := DefinitionRegistry.new()
var _world := WorldState.new()
var _scheduler := SimulationScheduler.new()
var _transport: SessionTransport

var _role: Role = Role.INACTIVE
var _running := false
var _network_host := false
var _client_ready := false
var _local_participant_id := ""
var _local_display_name := ""
var _campaign_slot_id := ""
var _greybox_object_entity_id := -1

var _participants_state := SessionParticipants.new()
var _pending_peers: Dictionary = {}
var _pending_intents: Array[Dictionary] = []
var _next_client_sequence := 1
var _last_snapshot_minute := -1
var _world_dirty := false
var _local_events: Array[Dictionary] = []
var _last_rejection: Dictionary = {}

var _save_in_progress := false
var _intent_processing_in_progress := false
var _simulation_advance_in_progress := false
var _simulation_accumulator_minutes := 0.0


func _process(_delta: float) -> void:
	if _transport != null:
		poll_transport()
	if _is_host_authority() and _running and not _pending_intents.is_empty():
		process_pending_intents()


func _physics_process(delta: float) -> void:
	if not _running or not _is_host_authority() or delta <= 0.0:
		return
	advance_disconnect_grace(delta)
	if not auto_tick_enabled or game_minutes_per_real_second <= 0.0:
		return
	_simulation_accumulator_minutes += delta * game_minutes_per_real_second
	var whole_minutes := int(floor(_simulation_accumulator_minutes))
	if whole_minutes <= 0:
		return
	_simulation_accumulator_minutes -= float(whole_minutes)
	advance_simulation_minutes(whole_minutes)


func _exit_tree() -> void:
	_unbind_and_close_transport()


func start_new_offline(
	campaign_id: String,
	genesis_seed: int,
	participant_id: String = "host",
	display_name: String = "Host"
) -> Dictionary:
	return _start_new_campaign(campaign_id, genesis_seed, false, 0, participant_id, display_name)


func start_new_host(
	campaign_id: String,
	genesis_seed: int,
	port: int = DEFAULT_PORT,
	participant_id: String = "host",
	display_name: String = "Host"
) -> Dictionary:
	return _start_new_campaign(campaign_id, genesis_seed, true, port, participant_id, display_name)


func load_and_start_offline(
	slot_id: String, participant_id: String = "host", display_name: String = "Host"
) -> Dictionary:
	return _load_and_start_campaign(slot_id, false, 0, participant_id, display_name)


func load_and_start_host(
	slot_id: String,
	port: int = DEFAULT_PORT,
	participant_id: String = "host",
	display_name: String = "Host"
) -> Dictionary:
	return _load_and_start_campaign(slot_id, true, port, participant_id, display_name)


func _start_new_campaign(
	campaign_id: String,
	genesis_seed: int,
	network_host: bool,
	port: int,
	participant_id: String,
	display_name: String
) -> Dictionary:
	if _running:
		return _failure(["a game session is already running"])
	var prepared := SessionWorldLoader.prepare_new_world(
		content_manifest_path, campaign_id, genesis_seed, greybox_width_tiles, greybox_height_tiles
	)
	if not bool(prepared.get("ok", false)):
		return prepared
	return _start_prepared_host(
		prepared.get("world") as WorldState,
		prepared.get("registry") as DefinitionRegistry,
		participant_id,
		display_name,
		network_host,
		port,
		{"fresh_campaign": true}
	)


func _load_and_start_campaign(
	slot_id: String, network_host: bool, port: int, participant_id: String, display_name: String
) -> Dictionary:
	if _running:
		return _failure(["a game session is already running"])
	var prepared := SessionWorldLoader.prepare_loaded_world(
		content_manifest_path,
		save_root_dir,
		save_backup_count,
		slot_id,
		greybox_width_tiles,
		greybox_height_tiles
	)
	if not bool(prepared.get("ok", false)):
		return prepared
	return _start_prepared_host(
		prepared.get("world") as WorldState,
		prepared.get("registry") as DefinitionRegistry,
		participant_id,
		display_name,
		network_host,
		port,
		SessionReplication.load_metadata(prepared, slot_id)
	)


func start_client(
	address: String, port: int, participant_id: String, display_name: String
) -> Dictionary:
	if _running:
		return _failure(["a game session is already running"])
	var identity := SessionMessageValidator.validated_identity(
		participant_id, display_name, MAX_DISPLAY_NAME_LENGTH
	)
	if not bool(identity.get("ok", false)):
		return identity
	var registry_report := SessionWorldLoader.load_registry(content_manifest_path)
	if not bool(registry_report.get("ok", false)):
		return registry_report

	_reset_session_state()
	_registry = registry_report.get("registry") as DefinitionRegistry
	_role = Role.CLIENT
	_running = true
	_network_host = false
	_client_ready = false
	_local_participant_id = String(identity.get("participant_id", ""))
	_local_display_name = String(identity.get("display_name", ""))
	_transport = EnetSessionTransport.new()
	_bind_transport()
	var error := _transport.join(address, port)
	if error != OK:
		var errors: Array[String] = ["failed to start ENet client: %s" % error_string(error)]
		_reset_session_state()
		return _failure(errors)

	var report := _success({"join_started": true, "connected": false})
	session_started.emit(session_status())
	return report


func stop_session(save_slot_id: String = "") -> Dictionary:
	if not _running:
		return _success({"already_stopped": true})
	var result := _success()
	if not save_slot_id.is_empty():
		if not _is_host_authority():
			return _failure(["only the authoritative host can save before stopping"])
		var save_report := save_world(save_slot_id)
		result["save_report"] = save_report
		if not bool(save_report.get("ok", false)):
			result["ok"] = false
			result["errors"] = save_report.get("errors", ["save before stop failed"])
			return result
	if _network_host and _transport != null:
		_send_message_to_authenticated(SessionProtocol.KIND_SERVER_STOPPING, {})
	_reset_session_state()
	session_stopped.emit()
	return result


func submit_intent(intent_type: String, payload: Dictionary) -> Dictionary:
	if not _running or _local_participant_id.is_empty():
		return _failure(["no local participant is active in this session"])
	var intent := SessionProtocol.make_intent(intent_type, _next_client_sequence, payload)
	var validation := SessionProtocol.validate_intent(intent)
	if not bool(validation.get("ok", false)):
		return _failure([String(validation.get("error", "invalid intent"))])
	if _role == Role.CLIENT:
		return _submit_client_intent(validation)
	if not _is_host_authority():
		return _failure(["session role cannot submit intents"])
	if _pending_intents.size() >= MAX_PENDING_INTENTS:
		return _failure(["host intent queue is full"])
	_queue_intent(LOCAL_PEER_ID, _local_participant_id, validation.get("intent", {}))
	_next_client_sequence += 1
	return _success({"queued": true, "client_sequence": int(validation["client_sequence"])})


func _submit_client_intent(validation: Dictionary) -> Dictionary:
	if not _client_ready or _transport == null:
		return _failure(["client is not connected to an authoritative host"])
	var send_error := _send_message_to_peer(
		LOCAL_PEER_ID, SessionProtocol.KIND_INTENT, validation.get("intent", {})
	)
	if send_error != OK:
		return _failure(["failed to send intent: %s" % error_string(send_error)])
	_next_client_sequence += 1
	return _success({"queued_remote": true, "client_sequence": int(validation["client_sequence"])})


func process_pending_intents(max_intents: int = MAX_INTENTS_PER_BATCH) -> Dictionary:
	if not _running or not _is_host_authority():
		return _failure(["only a running host processes intents"])
	if _intent_processing_in_progress:
		return _failure(["intent processing is already in progress"])
	if max_intents < 1:
		return _failure(["max_intents must be positive"])

	_intent_processing_in_progress = true
	var results: Array[Dictionary] = []
	while not _pending_intents.is_empty() and results.size() < max_intents:
		var item: Dictionary = _pending_intents.pop_front()
		results.append(_process_intent_item(item))
	_intent_processing_in_progress = false

	if _world_dirty:
		_broadcast_snapshot(true)
	return _success(
		{"processed": results.size(), "results": results, "remaining": _pending_intents.size()}
	)


func advance_simulation_minutes(
	minutes: int, max_system_calls: int = SimulationScheduler.DEFAULT_MAX_SYSTEM_CALLS
) -> Dictionary:
	if not _running or not _is_host_authority():
		return _failure(["only the authoritative host advances simulation time"])
	if _simulation_advance_in_progress:
		return _failure(["simulation advance is already in progress"])
	if minutes < 0:
		return _failure(["simulation minutes must not be negative"])

	var intent_report := process_pending_intents()
	if not bool(intent_report.get("ok", false)):
		return intent_report
	_simulation_advance_in_progress = true
	var scheduler_report := _scheduler.advance(_world, minutes, max_system_calls)
	_simulation_advance_in_progress = false
	scheduler_report["intent_results"] = intent_report.get("results", [])
	if _current_tick() != _last_snapshot_minute or _world_dirty:
		_broadcast_snapshot(true)
	return scheduler_report


func register_system(
	system_id: String,
	interval_minutes: int,
	callable: Callable,
	order: int = 0,
	phase_minute: int = 0
) -> bool:
	if _role == Role.CLIENT:
		return false
	return _scheduler.register_system(system_id, interval_minutes, callable, order, phase_minute)


func poll_transport() -> void:
	if _transport != null:
		_transport.poll()


func advance_disconnect_grace(seconds: float) -> Array[Dictionary]:
	if not _running or not _is_host_authority():
		return []
	var sheltered := _participants_state.advance_disconnect_grace(_world, seconds)
	if not sheltered.is_empty():
		_world_dirty = true
		_broadcast_snapshot(true)
	return sheltered


func _world_rules_snapshot() -> Dictionary:
	if _world == null or not _world.is_initialized():
		return {}
	return _world.world_rules().snapshot_state()


func enable_sevara_p1_slice() -> Dictionary:
	if not _running or not _is_host_authority():
		return _failure(["only the authoritative host can enable the P1 ecological slice"])
	var eco_report := SevaraEcoChain.ensure_basin_nodes(_world)
	if not bool(eco_report.get("ok", false)):
		return _failure([String(eco_report.get("error", "failed to initialize P1 basin nodes"))])
	var npc_report := SevaraP1Npcs.ensure_slice_npcs(_world)
	if not bool(npc_report.get("ok", false)):
		return _failure([String(npc_report.get("error", "failed to initialize P1 anchor NPCs"))])
	var body_count := BodyVitals.ensure_all_bodies(_world)
	for record in GreyboxWorld.body_records(_world):
		FieldJournalAndChronicle.ensure_journal(_world, int(record.get("body_entity_id", -1)))
	_register_p1_systems()
	_world_dirty = true
	_broadcast_snapshot(true)
	return _success(
		{
			"basin_nodes": eco_report.get("nodes", {}),
			"npcs": npc_report.get("npcs", {}),
			"body_count": body_count,
			"basin_summary": SevaraEcoChain.basin_summary(_world),
		}
	)


func _register_p1_systems() -> void:
	register_system("p1_sevara_ecology_hour", 60, Callable(self, "_step_p1_ecology_hour"), 100)
	register_system("p1_body_vitals_hour", 60, Callable(self, "_step_p1_body_vitals_hour"), 110)
	register_system("p1_anchor_npcs_hour", 60, Callable(self, "_step_p1_npcs_hour"), 120)


func _step_p1_ecology_hour(world: WorldState, _context: Dictionary) -> bool:
	return bool(SevaraEcoChain.step_hour(world).get("ok", false))


func _step_p1_body_vitals_hour(world: WorldState, _context: Dictionary) -> bool:
	return bool(BodyVitals.step_hour(world).get("ok", false))


func _step_p1_npcs_hour(world: WorldState, _context: Dictionary) -> bool:
	return bool(SevaraP1Npcs.step_hour(world).get("ok", false))


func configure_world_rules(patch: Dictionary) -> Dictionary:
	if not _running or not _is_host_authority():
		return _failure(["only the authoritative host can update world rules"])
	if _simulation_advance_in_progress or _intent_processing_in_progress or _save_in_progress:
		return _failure(["world rules can only be updated between simulation batches"])
	var apply_report := _world.world_rules().apply_patch(patch)
	if not bool(apply_report.get("ok", false)):
		var rule_errors: Array[String] = []
		for raw_err in apply_report.get("errors", []):
			rule_errors.append(String(raw_err))
		return _failure(rule_errors)
	_sync_runtime_from_world_rules()
	var changed_keys: Array = apply_report.get("changed_keys", [])
	var fact := _append_current_fact(
		"world_rules_updated",
		{"changed_keys": changed_keys, "rules": _world.world_rules().snapshot_state()},
		_body_entity_id_for_participant(_local_participant_id)
	)
	if not fact.is_empty():
		_world_dirty = true
	_record_local_event({"event_type": "world_rules_updated", "changed_keys": changed_keys})
	_broadcast_snapshot(true)
	return _success(
		{
			"rules": _world.world_rules().snapshot_state(),
			"changed_keys": changed_keys,
		}
	)


func save_world(slot_id: String) -> Dictionary:
	if not _running or not _is_host_authority():
		return _failure(["only the authoritative host can save the world"])
	if _save_in_progress:
		return _failure(["a world save is already in progress"])
	if _simulation_advance_in_progress or _intent_processing_in_progress:
		return _failure(["world saves are allowed only between simulation batches"])

	var intent_report := process_pending_intents()
	if not bool(intent_report.get("ok", false)):
		return intent_report
	var validation_errors := SessionWorldLoader.validate_session_world(_world, _registry)
	if not validation_errors.is_empty():
		return _failure(validation_errors)

	_save_in_progress = true
	var store := SaveStore.new(save_root_dir, save_backup_count)
	var report := WorldStateCodec.save_to_store(_world, store, slot_id, _game_version())
	_save_in_progress = false
	if bool(report.get("ok", false)):
		_campaign_slot_id = slot_id
		_record_local_event({"event_type": "world_saved", "slot_id": slot_id})
	return report


func session_status() -> Dictionary:
	var world_initialized := _world != null and _world.is_initialized()
	return {
		"running": _running,
		"role": _role_name(),
		"network_host": _network_host,
		"client_ready": _client_ready,
		"local_participant_id": _local_participant_id,
		"local_body_entity_id": _body_entity_id_for_participant(_local_participant_id),
		"campaign_id": _world.campaign_id() if world_initialized else "",
		"campaign_slot_id": _campaign_slot_id,
		"game_minute": _current_tick(),
		"entity_count": _world.entity_ids().size() if world_initialized else 0,
		"greybox_object_entity_id": _greybox_object_entity_id,
		"world_rules": _world_rules_snapshot(),
		"participants": _public_participants(),
		"disconnect_grace": _participants_state.disconnect_grace_summary(),
		"pending_intents": _pending_intents.size(),
		"transport_peer_id": _transport.get_unique_id() if _transport != null else 0,
		"transport_peers": SessionReplication.transport_peer_ids(_transport),
		"state_hash": domain_state_hash(),
		"last_rejection": JsonValue.duplicate_safe(_last_rejection),
	}


func world_state() -> WorldState:
	return _world


func registry() -> DefinitionRegistry:
	return _registry


func domain_state_hash() -> String:
	if _world == null or not _world.is_initialized():
		return ""
	return StateHash.sha256_hex(_world.snapshot_state())


func take_local_events(clear_after: bool = true) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for event in _local_events:
		result.append(JsonValue.duplicate_safe(event) as Dictionary)
	if clear_after:
		_local_events.clear()
	return result


func _start_prepared_host(
	prepared_world: WorldState,
	prepared_registry: DefinitionRegistry,
	participant_id: String,
	display_name: String,
	network_host: bool,
	port: int,
	metadata: Dictionary
) -> Dictionary:
	if _running:
		return _failure(["a game session is already running"])
	var identity := SessionMessageValidator.validated_identity(
		participant_id, display_name, MAX_DISPLAY_NAME_LENGTH
	)
	if not bool(identity.get("ok", false)):
		return identity
	if prepared_world == null or prepared_registry == null:
		return _failure(["prepared session world or registry is missing"])
	var spawn_report := GreyboxWorld.spawn_body(
		prepared_world,
		prepared_registry,
		String(identity.get("participant_id", "")),
		String(identity.get("display_name", "")),
		_effective_max_players(),
		greybox_width_tiles,
		greybox_height_tiles
	)
	if not bool(spawn_report.get("ok", false)):
		return spawn_report

	_reset_session_state()
	_registry = prepared_registry
	_world = prepared_world
	_role = Role.HOST
	_running = true
	_network_host = network_host
	_local_participant_id = String(identity.get("participant_id", ""))
	_local_display_name = String(identity.get("display_name", ""))
	_campaign_slot_id = String(metadata.get("slot_id", ""))
	_greybox_object_entity_id = GreyboxWorld.find_supply_object(_world)
	_participants_state.rebuild_from_world(_world)
	_participants_state.upsert_record(
		_local_participant_id,
		LOCAL_PEER_ID,
		_local_display_name,
		int(spawn_report.get("body_entity_id", -1)),
		true
	)
	if not SevaraEcoChain.find_basin_nodes(_world).is_empty():
		BodyVitals.ensure_all_bodies(_world)
		for record in GreyboxWorld.body_records(_world):
			FieldJournalAndChronicle.ensure_journal(_world, int(record.get("body_entity_id", -1)))
		_register_p1_systems()
	_scheduler.reset_for_minute(_current_tick())
	_last_snapshot_minute = _current_tick()
	_sync_runtime_from_world_rules()

	if network_host:
		_transport = EnetSessionTransport.new()
		_bind_transport()
		var remote_peer_capacity := maxi(_effective_max_players() - 1, 1)
		var error := _transport.host(port, remote_peer_capacity)
		if error != OK:
			var errors: Array[String] = ["failed to start ENet host: %s" % error_string(error)]
			_reset_session_state()
			return _failure(errors)

	var report := _success(metadata)
	report["body_entity_id"] = int(spawn_report.get("body_entity_id", -1))
	report["greybox_object_entity_id"] = _greybox_object_entity_id
	session_started.emit(session_status())
	participant_joined.emit(_local_participant_id, int(spawn_report.get("body_entity_id", -1)))
	return report


func _sync_runtime_from_world_rules() -> void:
	if _world == null or not _world.is_initialized():
		return
	var rules := _world.world_rules()
	max_players = rules.max_players()
	game_minutes_per_real_second = rules.effective_game_minutes_per_real_second()


func _body_entity_id_for_participant(participant_id: String) -> int:
	if participant_id.is_empty() or _world == null or not _world.is_initialized():
		return -1
	return GreyboxWorld.find_body(_world, participant_id)


func _public_participants() -> Array[Dictionary]:
	var host_participant_id := _local_participant_id if _is_host_authority() else ""
	return _participants_state.public_records(_world, host_participant_id)


func _queue_intent(peer_id: int, participant_id: String, intent: Dictionary) -> void:
	(
		_pending_intents
		. append(
			{
				"peer_id": peer_id,
				"participant_id": participant_id,
				"intent": JsonValue.duplicate_safe(intent),
			}
		)
	)


func _process_intent_item(item: Dictionary) -> Dictionary:
	var outcome := SessionIntentProcessor.process_item(
		_world, _registry, _participants_state, item, greybox_width_tiles, greybox_height_tiles
	)
	var intent: Dictionary = outcome.get("intent", {})
	if bool(outcome.get("ok", false)):
		var fact: Dictionary = outcome.get("fact", {})
		_world_dirty = true
		var event := {
			"event_type": "intent_applied",
			"participant_id": String(outcome.get("participant_id", "")),
			"intent": intent,
			"fact": fact,
		}
		_record_local_event(event)
		_send_message_to_authenticated(SessionProtocol.KIND_EVENT, event)
		intent_applied.emit(intent.duplicate(true), fact.duplicate(true))
	else:
		var rejection: Dictionary = outcome.get("rejection", {})
		_last_rejection = rejection.duplicate(true)
		_record_local_event({"event_type": "intent_rejected", "rejection": rejection})
		var peer_id := int(outcome.get("peer_id", 0))
		if _network_host and peer_id != LOCAL_PEER_ID and peer_id > 0:
			_send_message_to_peer(peer_id, SessionProtocol.KIND_REJECT, rejection)
		intent_rejected.emit(rejection.duplicate(true))
	return {
		"ok": bool(outcome.get("ok", false)),
		"participant_id": String(outcome.get("participant_id", "")),
		"peer_id": int(outcome.get("peer_id", 0)),
		"intent_type": String(outcome.get("intent_type", "")),
		"client_sequence": int(outcome.get("client_sequence", 0)),
		"fact": outcome.get("fact", {}),
		"reason": String(outcome.get("reason", "")),
		"error": String(outcome.get("error", "")),
	}


func _append_current_fact(
	kind: String, payload: Dictionary, actor_id: int = -1, subject_id: String = ""
) -> Dictionary:
	if _world == null or not _world.is_initialized():
		return {}
	return _world.fact_log().append_fact(
		kind, _world.clock().total_minutes(), payload, actor_id, subject_id
	)


func _bind_transport() -> void:
	SessionReplication.bind_transport(_transport, self)


func _unbind_and_close_transport() -> void:
	SessionReplication.unbind_and_close_transport(_transport, self)
	_transport = null


func _on_transport_peer_connected(peer_id: int) -> void:
	if _running and _network_host and peer_id > LOCAL_PEER_ID:
		_pending_peers[peer_id] = true


func _on_transport_peer_disconnected(peer_id: int) -> void:
	_pending_peers.erase(peer_id)
	if not _running or not _network_host:
		return
	var grace_sec := (
		_world.world_rules().disconnect_grace_seconds()
		if _world != null and _world.is_initialized()
		else SessionParticipants.EMERGENCY_DISCONNECT_GRACE_SECONDS
	)
	var record := _participants_state.disconnect_peer(peer_id, grace_sec)
	if record.is_empty():
		return
	var participant_id := String(record.get("participant_id", ""))
	var body_entity_id := int(record.get("body_entity_id", -1))
	var fact := _append_current_fact(
		"participant_disconnected",
		{"participant_id": participant_id, "entity_id": body_entity_id},
		body_entity_id,
		GreyboxWorld.BODY_DEFINITION_ID
	)
	if not fact.is_empty():
		_world_dirty = true
	_broadcast_snapshot(true)
	participant_disconnected.emit(participant_id, body_entity_id)


func _on_transport_connected_to_server() -> void:
	if _role == Role.CLIENT and _running:
		_send_hello()


func _on_transport_connection_failed() -> void:
	_client_ready = false
	_emit_session_error("failed to connect to the session host")


func _on_transport_server_disconnected() -> void:
	_client_ready = false
	_participants_state.set_connected(_local_participant_id, false)
	_emit_session_error("session host disconnected")


func _on_transport_packet_received(peer_id: int, packet: PackedByteArray) -> void:
	if not _running:
		return
	var decoded := SessionProtocol.decode_packet(packet)
	if not bool(decoded.get("ok", false)):
		_emit_session_error(String(decoded.get("error", "invalid session packet")))
		return
	var kind := String(decoded.get("kind", ""))
	var payload: Dictionary = decoded.get("payload", {})
	if _role == Role.HOST:
		_handle_host_packet(peer_id, kind, payload)
	elif _role == Role.CLIENT:
		_handle_client_packet(peer_id, kind, payload)


func _handle_host_packet(peer_id: int, kind: String, payload: Dictionary) -> void:
	match kind:
		SessionProtocol.KIND_HELLO:
			_handle_hello(peer_id, payload)
		SessionProtocol.KIND_INTENT:
			_handle_host_intent(peer_id, payload)
		SessionProtocol.KIND_PING:
			_send_message_to_peer(peer_id, SessionProtocol.KIND_PONG, {})
		_:
			_send_rejection_message(peer_id, "", {}, "unexpected_message", kind)


func _handle_host_intent(peer_id: int, payload: Dictionary) -> void:
	var participant_id := _participants_state.participant_id_for_peer(peer_id)
	if participant_id.is_empty():
		_send_rejection_message(peer_id, "", {}, "unauthenticated_peer", "")
		return
	var validation := SessionProtocol.validate_intent(payload)
	if not bool(validation.get("ok", false)):
		_send_rejection_message(
			peer_id,
			participant_id,
			{},
			"invalid_intent",
			String(validation.get("error", "invalid intent"))
		)
		return
	if _pending_intents.size() >= MAX_PENDING_INTENTS:
		_send_rejection_message(
			peer_id, participant_id, validation.get("intent", {}), "intent_queue_full", ""
		)
		return
	_queue_intent(peer_id, participant_id, validation.get("intent", {}))


func _handle_client_packet(peer_id: int, kind: String, payload: Dictionary) -> void:
	if peer_id != LOCAL_PEER_ID:
		_emit_session_error("ignored a session packet from a non-host peer")
		return
	match kind:
		SessionProtocol.KIND_WELCOME:
			_handle_welcome(payload)
		SessionProtocol.KIND_SNAPSHOT:
			_apply_snapshot_payload(payload)
		SessionProtocol.KIND_EVENT:
			_record_local_event(payload)
		SessionProtocol.KIND_REJECT:
			_last_rejection = payload.duplicate(true)
			_record_local_event({"event_type": "intent_rejected", "rejection": payload})
			intent_rejected.emit(payload.duplicate(true))
		SessionProtocol.KIND_PONG:
			_record_local_event({"event_type": "pong"})
		SessionProtocol.KIND_SERVER_STOPPING:
			_client_ready = false
			_emit_session_error("session host is stopping")
		_:
			_emit_session_error("unexpected session message kind '%s'" % kind)


func _send_hello() -> void:
	var payload := SessionReplication.make_hello_payload(
		_game_version(), _registry, _local_participant_id, _local_display_name
	)
	var error := _send_message_to_peer(LOCAL_PEER_ID, SessionProtocol.KIND_HELLO, payload)
	if error != OK:
		_emit_session_error("failed to send session hello: %s" % error_string(error))


func _handle_hello(peer_id: int, payload: Dictionary) -> void:
	if not _network_host or peer_id <= LOCAL_PEER_ID:
		return
	var accepted := SessionReplication.accept_hello(
		peer_id,
		payload,
		_game_version(),
		_world,
		_registry,
		_participants_state,
		_effective_max_players(),
		greybox_width_tiles,
		greybox_height_tiles
	)
	if not bool(accepted.get("ok", false)):
		_send_rejection_message(
			peer_id,
			String(accepted.get("participant_id", "")),
			{},
			String(accepted.get("reason", "invalid_hello")),
			""
		)
		return
	var participant_id := String(accepted.get("participant_id", ""))
	var body_entity_id := int(accepted.get("body_entity_id", -1))
	_pending_peers.erase(peer_id)
	if bool(accepted.get("created", false)):
		_world_dirty = true
	var welcome := SessionReplication.make_welcome_payload(
		participant_id,
		body_entity_id,
		int(accepted.get("next_client_sequence", 1)),
		_make_snapshot_payload()
	)
	_send_message_to_peer(peer_id, SessionProtocol.KIND_WELCOME, welcome)
	if not bool(accepted.get("already_connected", false)):
		_send_message_to_authenticated(
			SessionProtocol.KIND_EVENT,
			{
				"event_type": "participant_joined",
				"participant_id": participant_id,
				"body_entity_id": body_entity_id,
			},
			peer_id
		)
		_broadcast_snapshot(true, peer_id)
		participant_joined.emit(participant_id, body_entity_id)


func _handle_welcome(payload: Dictionary) -> void:
	var parsed := SessionMessageValidator.parse_welcome(payload, _local_participant_id)
	if not bool(parsed.get("ok", false)):
		_emit_session_error(String(parsed.get("error", "invalid welcome payload")))
		return
	_next_client_sequence = int(parsed.get("next_client_sequence", 1))
	_apply_snapshot_payload(parsed.get("snapshot", {}), int(parsed.get("body_entity_id", -1)))


func _make_snapshot_payload() -> Dictionary:
	return SessionReplication.make_snapshot_payload(
		_world, domain_state_hash(), _public_participants(), _greybox_object_entity_id
	)


func _apply_snapshot_payload(payload: Dictionary, expected_body_id: int = -1) -> bool:
	var validation := SessionMessageValidator.validated_snapshot_world(
		payload, _registry, [SessionWorldLoader.package_pin_for_registry(_registry)]
	)
	if not bool(validation.get("ok", false)) or not _world.restore_state(payload["world_snapshot"]):
		_emit_session_error(String(validation.get("error", "invalid snapshot")))
		return false
	_sync_runtime_from_world_rules()
	_greybox_object_entity_id = GreyboxWorld.find_supply_object(_world)
	_participants_state.rebuild_from_world(_world)
	_participants_state.overlay_public_records(
		payload.get("participants", []),
		_local_participant_id,
		_transport.get_unique_id() if _transport != null else 0
	)
	_scheduler.reset_for_minute(_current_tick())
	_last_snapshot_minute = _current_tick()
	_world_dirty = false
	if expected_body_id > 0:
		_client_ready = _body_entity_id_for_participant(_local_participant_id) == expected_body_id
		if not _client_ready:
			_emit_session_error("welcome body does not match the snapshot body")
			return false
	snapshot_applied.emit(String(validation.get("state_hash", "")))
	return true


func _broadcast_snapshot(force: bool = false, excluded_peer_id: int = 0) -> void:
	if not _network_host or not _is_host_authority() or not _world.is_initialized():
		return
	if not force and not _world_dirty and _last_snapshot_minute == _current_tick():
		return
	_send_message_to_authenticated(
		SessionProtocol.KIND_SNAPSHOT, _make_snapshot_payload(), excluded_peer_id
	)
	_world_dirty = false
	_last_snapshot_minute = _current_tick()


func _send_message_to_authenticated(
	kind: String, payload: Dictionary, excluded_peer_id: int = 0
) -> void:
	if not _network_host:
		return
	SessionReplication.send_message_to_authenticated(
		_transport, _participants_state, _current_tick(), kind, payload, excluded_peer_id
	)


func _send_message_to_peer(peer_id: int, kind: String, payload: Dictionary) -> Error:
	return SessionReplication.send_message_to_peer(
		_transport, peer_id, _current_tick(), kind, payload
	)


func _send_rejection_message(
	peer_id: int, participant_id: String, intent: Dictionary, reason: String, error: String
) -> void:
	var rejection := SessionReplication.make_rejection(
		peer_id, participant_id, intent, reason, error
	)
	_last_rejection = rejection.duplicate(true)
	_send_message_to_peer(peer_id, SessionProtocol.KIND_REJECT, rejection)
	intent_rejected.emit(rejection.duplicate(true))


func _reset_session_state() -> void:
	_unbind_and_close_transport()
	_registry = DefinitionRegistry.new()
	_world = WorldState.new()
	_scheduler = SimulationScheduler.new()
	_role = Role.INACTIVE
	_running = false
	_network_host = false
	_client_ready = false
	_local_participant_id = ""
	_local_display_name = ""
	_campaign_slot_id = ""
	_greybox_object_entity_id = -1
	_participants_state.clear()
	_pending_peers.clear()
	_pending_intents.clear()
	_next_client_sequence = 1
	_last_snapshot_minute = -1
	_world_dirty = false
	_local_events.clear()
	_last_rejection = {}
	_save_in_progress = false
	_intent_processing_in_progress = false
	_simulation_advance_in_progress = false
	_simulation_accumulator_minutes = 0.0


func _record_local_event(event: Dictionary) -> void:
	if JsonValue.is_safe(event):
		_local_events.append(JsonValue.duplicate_safe(event) as Dictionary)


func _emit_session_error(message: String) -> void:
	_record_local_event({"event_type": "session_error", "message": message})
	session_error.emit(message)


func _effective_max_players() -> int:
	return clampi(max_players, 1, DEFAULT_MAX_PLAYERS)


func _is_host_authority() -> bool:
	return _role == Role.HOST


func _current_tick() -> int:
	if _world == null or not _world.is_initialized():
		return 0
	return _world.clock().total_minutes()


func _role_name() -> String:
	match _role:
		Role.HOST:
			return "host"
		Role.CLIENT:
			return "client"
		_:
			return "inactive"


func _game_version() -> String:
	var resolved := game_version_override.strip_edges()
	if resolved.is_empty():
		resolved = (
			String(
				ProjectSettings.get_setting(
					"application/config/version", WorldStateCodec.DEFAULT_GAME_VERSION
				)
			)
			. strip_edges()
		)
	return resolved if not resolved.is_empty() else WorldStateCodec.DEFAULT_GAME_VERSION


func _success(extra: Dictionary = {}) -> Dictionary:
	var result := {"ok": true, "errors": []}
	for key in extra.keys():
		result[key] = extra[key]
	return result


func _failure(errors: Array[String]) -> Dictionary:
	return {"ok": false, "errors": errors.duplicate()}
