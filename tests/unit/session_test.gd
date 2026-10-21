extends Node
## P0-E authoritative session tests.
##
## Covers the session protocol, deterministic scheduler budget/order,
## solo host intent validation, session-owned persistence and package
## pin reconciliation, plus a real ENet localhost host/client pair with
## two participant bodies and one mutable greybox supply object.

const TEST_SAVE_ROOT := "user://tests/session_p0e"
const SOLO_SLOT := "p0e_solo_slot"
const NETWORK_SLOT := "p0e_network_slot"
const BAD_PIN_SLOT := "p0e_bad_pin_slot"
const LEGACY_SLOT := "p0e_legacy_slot"
const LEGACY_FIXTURE_PATH := "res://tests/fixtures/saves/world_v0_legacy.json"

var _failures: Array[String] = []
var _checks: int = 0
var _scheduled_calls: Array[String] = []
var _network_host: GameSession
var _network_client: GameSession


func _ready() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	_test_protocol()
	_test_scheduler_budget()
	_test_solo_session_and_persistence()
	_test_package_pin_rejection()
	_test_legacy_package_reconciliation()
	await _test_enet_host_client()

	if _failures.is_empty():
		print("SESSION_TESTS_OK checks=%d" % _checks)
		get_tree().quit(0)
	else:
		for failure in _failures:
			push_error("SESSION_TESTS_FAILED: %s" % failure)
		get_tree().quit(1)


func _test_protocol() -> void:
	var message := SessionProtocol.make_message(
		SessionProtocol.KIND_SNAPSHOT, 17, {"state_hash": "abc", "count": 3}
	)
	var packet := SessionProtocol.encode_message(message)
	_check(not packet.is_empty(), "session message encodes to a packet")
	var decoded := SessionProtocol.decode_packet(packet)
	_check(bool(decoded.get("ok", false)), "session packet decodes")
	_check_equal(String(decoded.get("kind", "")), SessionProtocol.KIND_SNAPSHOT, "packet kind")
	_check_equal(int(decoded.get("tick", -1)), 17, "packet tick")

	var intent := SessionProtocol.make_intent(
		SessionProtocol.INTENT_MOVE_BODY, 1, {"entity_id": 2, "to_tile_x": 3, "to_tile_y": 4}
	)
	_check(bool(SessionProtocol.validate_intent(intent).get("ok", false)), "valid intent passes")
	intent["unexpected"] = true
	_check(
		not bool(SessionProtocol.validate_intent(intent).get("ok", true)),
		"intent with an unknown field is rejected"
	)
	_check(
		not bool(SessionProtocol.decode_packet("not-json".to_utf8_buffer()).get("ok", true)),
		"non-JSON packet is rejected"
	)


func _test_scheduler_budget() -> void:
	var world := _make_test_world("p0e_scheduler")
	_check(world != null and world.is_initialized(), "scheduler test world is initialized")
	if world == null:
		return
	_scheduled_calls.clear()
	var scheduler := SimulationScheduler.new()
	_check(
		scheduler.register_system("minute_probe", 1, Callable(self, "_record_scheduled_system")),
		"scheduler registers a minute system"
	)
	var report := scheduler.advance(world, 10, 3)
	_check(bool(report.get("ok", false)), "budgeted scheduler advance succeeds")
	_check(bool(report.get("truncated", false)), "scheduler reports call budget truncation")
	_check_equal(int(report.get("system_calls", -1)), 3, "scheduler call budget")
	_check_equal(world.clock().total_minutes(), 3, "scheduler stops at the budgeted event")
	_check_equal(
		_scheduled_calls,
		["minute_probe@1", "minute_probe@2", "minute_probe@3"],
		"scheduler minute call order"
	)


func _test_solo_session_and_persistence() -> void:
	_delete_slot(SOLO_SLOT)
	var session := _make_session("SoloSession")
	var start_report := session.start_new_offline("p0e_solo", 123456, "host", "Host")
	_check(bool(start_report.get("ok", false)), "solo session starts: %s" % str(start_report))
	if not bool(start_report.get("ok", false)):
		_destroy_session(session)
		return

	var world := session.world_state()
	var body_id := GreyboxWorld.find_body(world, "host")
	var object_id := GreyboxWorld.find_supply_object(world)
	_check(body_id > 0, "solo session creates the host body")
	_check(object_id > 0, "solo session creates the greybox supply object")
	_check_equal(_position_of(world, body_id), Vector2i(2, 2), "host spawn tile")
	_check_equal(_position_of(world, object_id), Vector2i(3, 2), "object spawn tile")

	_scheduled_calls.clear()
	_check(
		session.register_system("hour_probe", 60, Callable(self, "_record_scheduled_system"), 10),
		"session registers hourly system"
	)
	_check(
		session.register_system(
			"half_hour_probe", 30, Callable(self, "_record_scheduled_system"), 20
		),
		"session registers half-hour system"
	)

	var interact_result := _submit_and_process(
		session,
		SessionProtocol.INTENT_INTERACT_OBJECT,
		{"target_entity_id": object_id, "verb": "take_one"}
	)
	_check(bool(interact_result.get("ok", false)), "host can take one item from the supply object")
	_check_equal(_container_count(world, object_id), 2, "supply count after take")
	_check_equal(
		_inventory_count(world, body_id, GreyboxWorld.DEFAULT_CONTAINER_ITEM_DEFINITION_ID),
		1,
		"body inventory after take"
	)

	var teleport_result := _submit_and_process(
		session,
		SessionProtocol.INTENT_MOVE_BODY,
		{"entity_id": body_id, "to_tile_x": 4, "to_tile_y": 2}
	)
	_check(not bool(teleport_result.get("ok", true)), "host teleport intent is rejected")
	_check_equal(
		String(teleport_result.get("reason", "")), "step_too_far", "teleport rejection reason"
	)
	_check_equal(_position_of(world, body_id), Vector2i(2, 2), "rejected move leaves body in place")

	var move_result := _submit_and_process(
		session,
		SessionProtocol.INTENT_MOVE_BODY,
		{"entity_id": body_id, "to_tile_x": 2, "to_tile_y": 3}
	)
	_check(bool(move_result.get("ok", false)), "host can move one authoritative tile step")

	var advance_report := session.advance_simulation_minutes(60)
	_check(bool(advance_report.get("ok", false)), "solo simulation advances one hour")
	_check_equal(
		_scheduled_calls,
		["half_hour_probe@30", "hour_probe@60", "half_hour_probe@60"],
		"session scheduler deterministic order"
	)
	var timed_move := _submit_and_process(
		session,
		SessionProtocol.INTENT_MOVE_BODY,
		{"entity_id": body_id, "to_tile_x": 2, "to_tile_y": 2}
	)
	_check(bool(timed_move.get("ok", false)), "host can move after simulation advance")
	var move_facts := world.fact_log().facts_of_kind("body_moved")
	_check(not move_facts.is_empty(), "body movement facts exist")
	if not move_facts.is_empty():
		_check_equal(
			int(move_facts[move_facts.size() - 1].get("game_minute", -1)),
			60,
			"session appends facts at the current domain minute"
		)

	var entity_count := world.entity_ids().size()
	var save_report := session.save_world(SOLO_SLOT)
	_check(
		bool(save_report.get("ok", false)), "host saves the session world: %s" % str(save_report)
	)
	_destroy_session(session)

	var loaded_session := _make_session("LoadedSoloSession")
	var load_report := loaded_session.load_and_start_offline(SOLO_SLOT, "host", "Host")
	_check(bool(load_report.get("ok", false)), "saved solo session loads: %s" % str(load_report))
	if bool(load_report.get("ok", false)):
		var loaded_world := loaded_session.world_state()
		_check_equal(loaded_world.clock().total_minutes(), 60, "loaded world minute")
		_check_equal(
			loaded_world.entity_ids().size(),
			entity_count,
			"load does not duplicate greybox entities"
		)
		_check_equal(
			_inventory_count(
				loaded_world,
				GreyboxWorld.find_body(loaded_world, "host"),
				GreyboxWorld.DEFAULT_CONTAINER_ITEM_DEFINITION_ID
			),
			1,
			"loaded body inventory"
		)
		_check_equal(
			_container_count(loaded_world, GreyboxWorld.find_supply_object(loaded_world)),
			2,
			"loaded supply count"
		)
	_destroy_session(loaded_session)


func _test_package_pin_rejection() -> void:
	_delete_slot(BAD_PIN_SLOT)
	var registry := DefinitionRegistry.new()
	var registry_report := registry.load_package("res://data/core/manifest.json")
	_check(bool(registry_report.get("ok", false)), "bad-pin fixture registry loads")
	var world := WorldState.new()
	var pins: Array = [
		{"package_id": "core", "version": "9.9.9", "manifest_sha256": "a".repeat(64)}
	]
	_check(world.setup_campaign("p0e_bad_pin", 7, pins), "bad-pin fixture world initializes")
	world.create_entity("core:species/navelu", {})
	var store := SaveStore.new(TEST_SAVE_ROOT, 2)
	var saved := WorldStateCodec.save_to_store(world, store, BAD_PIN_SLOT, "test")
	_check(bool(saved.get("ok", false)), "bad-pin fixture world saves")

	var session := _make_session("BadPinSession")
	var report := session.load_and_start_offline(BAD_PIN_SLOT, "host", "Host")
	_check(not bool(report.get("ok", true)), "session rejects a world with mismatched package pins")
	_check(
		not bool(session.session_status().get("running", true)),
		"rejected package pins do not start a session"
	)
	_destroy_session(session)


func _test_legacy_package_reconciliation() -> void:
	_delete_slot(LEGACY_SLOT)
	var document_text := FileAccess.get_file_as_string(LEGACY_FIXTURE_PATH)
	var parser := JSON.new()
	_check(parser.parse(document_text) == OK, "legacy fixture JSON parses")
	if parser.data is Dictionary:
		var decoded := WorldStateCodec.decode(parser.data)
		_check(bool(decoded.get("ok", false)), "legacy fixture decodes and migrates")
		var legacy_world := decoded.get("world") as WorldState
		if legacy_world != null:
			_check(legacy_world.content_packages().is_empty(), "legacy world starts without pins")
			var store := SaveStore.new(TEST_SAVE_ROOT, 2)
			var saved := WorldStateCodec.save_to_store(legacy_world, store, LEGACY_SLOT, "test")
			_check(bool(saved.get("ok", false)), "legacy migrated world can be stored")
	else:
		_check(false, "legacy fixture root is a dictionary")
		return

	var session := _make_session("LegacySession")
	var report := session.load_and_start_offline(LEGACY_SLOT, "host", "Host")
	_check(bool(report.get("ok", false)), "legacy session loads: %s" % str(report))
	_check(
		bool(report.get("package_pins_reconciled", false)),
		"legacy load explicitly reports package pin reconciliation"
	)
	if bool(report.get("ok", false)):
		var pins := session.world_state().content_packages()
		_check_equal(pins.size(), 1, "reconciled world has one active package pin")
		if pins.size() == 1:
			_check_equal(
				String(pins[0].get("manifest_sha256", "")),
				session.registry().manifest_hash(),
				"reconciled pin matches the active registry"
			)
		_check(
			GreyboxWorld.find_body(session.world_state(), "host") > 0,
			"legacy session gains a participant body"
		)
		_check(
			GreyboxWorld.find_supply_object(session.world_state()) > 0,
			"legacy session gains the greybox supply object"
		)
	_destroy_session(session)


func _test_enet_host_client() -> void:
	_delete_slot(NETWORK_SLOT)
	var selected_port := 0
	for candidate_port in [24731, 24732, 24733, 24734, 24735]:
		_network_host = _make_session("NetworkHost")
		var host_report := _network_host.start_new_host(
			"p0e_network", 987654, candidate_port, "host", "Host"
		)
		if bool(host_report.get("ok", false)):
			selected_port = candidate_port
			break
		_destroy_session(_network_host)
		_network_host = null
	_check(selected_port > 0, "ENet host starts on a localhost port")
	if selected_port <= 0:
		return

	_network_client = _make_session("NetworkClient")
	var client_report := _network_client.start_client(
		"127.0.0.1", selected_port, "guest_1", "Guest"
	)
	_check(bool(client_report.get("ok", false)), "ENet client join starts: %s" % str(client_report))
	var ready: bool = await _wait_until(Callable(self, "_network_client_ready"), 10000)
	_check(ready, "ENet client receives welcome and authoritative snapshot")
	if not ready:
		_destroy_session(_network_client)
		_destroy_session(_network_host)
		_network_client = null
		_network_host = null
		return

	var host_world := _network_host.world_state()
	var client_world := _network_client.world_state()
	var host_body_id := GreyboxWorld.find_body(host_world, "host")
	var guest_body_id := GreyboxWorld.find_body(host_world, "guest_1")
	var object_id := GreyboxWorld.find_supply_object(host_world)
	_check(host_body_id > 0 and guest_body_id > 0, "host world contains two participant bodies")
	_check_equal(
		_network_client.domain_state_hash(),
		_network_host.domain_state_hash(),
		"host and client world hashes match after join"
	)

	var interact_submit := _network_client.submit_intent(
		SessionProtocol.INTENT_INTERACT_OBJECT, {"target_entity_id": object_id, "verb": "take_one"}
	)
	_check(bool(interact_submit.get("ok", false)), "client submits an interact intent")
	_check(
		await _wait_until(Callable(self, "_network_guest_took_item"), 10000),
		"host validates and replicates the guest item transfer"
	)

	var spoof_submit := _network_client.submit_intent(
		SessionProtocol.INTENT_MOVE_BODY,
		{"entity_id": host_body_id, "to_tile_x": 2, "to_tile_y": 3}
	)
	_check(
		bool(spoof_submit.get("ok", false)), "client can submit a spoofed move for host validation"
	)
	_check(
		await _wait_until(Callable(self, "_network_client_rejected_entity_mismatch"), 10000),
		"host rejects a move for another participant's body"
	)
	_check_equal(
		_position_of(host_world, host_body_id),
		Vector2i(2, 2),
		"spoofed move does not move the host body"
	)

	var move_submit := _network_client.submit_intent(
		SessionProtocol.INTENT_MOVE_BODY,
		{"entity_id": guest_body_id, "to_tile_x": 4, "to_tile_y": 3}
	)
	_check(bool(move_submit.get("ok", false)), "client submits its own move intent")
	_check(
		await _wait_until(Callable(self, "_network_guest_position_is").bind(4, 3), 10000),
		"host validates and replicates the guest move"
	)

	var client_save := _network_client.save_world(NETWORK_SLOT)
	_check(not bool(client_save.get("ok", true)), "client cannot write the campaign world save")

	var advance_report := _network_host.advance_simulation_minutes(5)
	_check(bool(advance_report.get("ok", false)), "network host advances authoritative time")
	_check(
		await _wait_until(Callable(self, "_network_client_minute_is_five"), 10000),
		"client receives the advanced authoritative clock and matching hash"
	)
	_check_equal(client_world.clock().total_minutes(), 5, "client mirrored minute")

	_network_client.stop_session()
	_check(
		await _wait_until(Callable(self, "_network_guest_disconnected"), 10000),
		"host observes guest disconnect and keeps the body in the world"
	)
	_check(host_world.has_entity(guest_body_id), "disconnected guest body remains persistent")

	var host_save := _network_host.save_world(NETWORK_SLOT)
	_check(bool(host_save.get("ok", false)), "network host saves the authoritative world")
	_destroy_session(_network_client)
	_destroy_session(_network_host)
	_network_client = null
	_network_host = null


func _record_scheduled_system(_world: WorldState, context: Dictionary) -> bool:
	_scheduled_calls.append(
		"%s@%d" % [String(context.get("system_id", "")), int(context.get("scheduled_minute", -1))]
	)
	return true


func _make_session(session_name: String) -> GameSession:
	var session := GameSession.new()
	session.name = session_name
	session.save_root_dir = TEST_SAVE_ROOT
	session.save_backup_count = 2
	add_child(session)
	return session


func _destroy_session(session: GameSession) -> void:
	if not is_instance_valid(session):
		return
	if bool(session.session_status().get("running", false)):
		session.stop_session()
	if session.get_parent() == self:
		remove_child(session)
	session.free()


func _make_test_world(campaign_id: String) -> WorldState:
	var registry := DefinitionRegistry.new()
	var report := registry.load_package("res://data/core/manifest.json")
	if not bool(report.get("ok", false)):
		return null
	var world := WorldState.new()
	var pins: Array = [SessionWorldLoader.package_pin_for_registry(registry)]
	if not world.setup_campaign(campaign_id, 42, pins):
		return null
	return world


func _submit_and_process(
	session: GameSession, intent_type: String, payload: Dictionary
) -> Dictionary:
	var submit_report := session.submit_intent(intent_type, payload)
	_check(
		bool(submit_report.get("ok", false)),
		"session accepts %s for authoritative processing" % intent_type
	)
	var process_report := session.process_pending_intents()
	var results: Array = process_report.get("results", [])
	if results.is_empty():
		_check(false, "session processes %s" % intent_type)
		return {}
	return results[0]


func _wait_until(predicate: Callable, timeout_msec: int) -> bool:
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < timeout_msec:
		if bool(predicate.call()):
			return true
		_pump_network_sessions()
		await get_tree().process_frame
	return bool(predicate.call())


func _pump_network_sessions() -> void:
	if is_instance_valid(_network_host):
		_network_host.poll_transport()
		if bool(_network_host.session_status().get("running", false)):
			_network_host.process_pending_intents()
	if is_instance_valid(_network_client):
		_network_client.poll_transport()


func _network_client_ready() -> bool:
	if not is_instance_valid(_network_host) or not is_instance_valid(_network_client):
		return false
	var status := _network_client.session_status()
	var participants: Array = status.get("participants", [])
	return (
		bool(status.get("client_ready", false))
		and participants.size() == 2
		and _network_client.domain_state_hash() == _network_host.domain_state_hash()
	)


func _network_guest_took_item() -> bool:
	if not is_instance_valid(_network_host) or not is_instance_valid(_network_client):
		return false
	var host_world := _network_host.world_state()
	var client_world := _network_client.world_state()
	var object_id := GreyboxWorld.find_supply_object(host_world)
	var guest_id := GreyboxWorld.find_body(host_world, "guest_1")
	return (
		_container_count(host_world, object_id) == 2
		and _container_count(client_world, object_id) == 2
		and (
			_inventory_count(
				client_world, guest_id, GreyboxWorld.DEFAULT_CONTAINER_ITEM_DEFINITION_ID
			)
			== 1
		)
	)


func _network_client_rejected_entity_mismatch() -> bool:
	if not is_instance_valid(_network_client):
		return false
	var rejection: Dictionary = _network_client.session_status().get("last_rejection", {})
	return String(rejection.get("reason", "")) == "entity_mismatch"


func _network_guest_position_is(tile_x: int, tile_y: int) -> bool:
	if not is_instance_valid(_network_host) or not is_instance_valid(_network_client):
		return false
	var expected := Vector2i(tile_x, tile_y)
	var host_world := _network_host.world_state()
	var client_world := _network_client.world_state()
	var guest_id := GreyboxWorld.find_body(host_world, "guest_1")
	return (
		_position_of(host_world, guest_id) == expected
		and _position_of(client_world, guest_id) == expected
	)


func _network_client_minute_is_five() -> bool:
	if not is_instance_valid(_network_host) or not is_instance_valid(_network_client):
		return false
	return (
		_network_client.world_state().clock().total_minutes() == 5
		and _network_client.domain_state_hash() == _network_host.domain_state_hash()
	)


func _network_guest_disconnected() -> bool:
	if not is_instance_valid(_network_host):
		return false
	for raw_participant in _network_host.session_status().get("participants", []):
		var participant: Dictionary = raw_participant
		if String(participant.get("participant_id", "")) == "guest_1":
			return not bool(participant.get("connected", true))
	return false


func _position_of(world: WorldState, entity_id: int) -> Vector2i:
	return GreyboxWorld.position_from_component(
		world.get_entity_component(entity_id, GreyboxWorld.POSITION_COMPONENT), 32, 24
	)


func _container_count(world: WorldState, entity_id: int) -> int:
	var container := world.get_entity_component(entity_id, GreyboxWorld.CONTAINER_COMPONENT)
	return int(GreyboxWorld.integral_value(container.get("count", null)).get("value", -1))


func _inventory_count(world: WorldState, entity_id: int, definition_id: String) -> int:
	var inventory := world.get_entity_component(entity_id, GreyboxWorld.INVENTORY_COMPONENT)
	return int(GreyboxWorld.integral_value(inventory.get(definition_id, 0)).get("value", -1))


func _delete_slot(slot_id: String) -> void:
	SaveStore.new(TEST_SAVE_ROOT, 2).delete_slot(slot_id)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)


func _check_equal(actual: Variant, expected: Variant, message: String) -> void:
	_checks += 1
	if actual != expected:
		_failures.append("%s: expected %s, got %s" % [message, str(expected), str(actual)])
