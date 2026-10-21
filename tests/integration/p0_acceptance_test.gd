extends Node
## P0-G end-to-end acceptance suite.
##
## Verifies the P0 exit criteria from `core_foundation_blueprint.md` and
## `round12_baseline_lock.md`:
## 1) deterministic fixed-seed replay (identical WorldClock, RNG streams,
##    FactLog and `domain_state_hash()`);
## 2) simulated crash during world save (`world.json` truncated + stale
##    `.tmp` file) with automatic backup recovery;
## 3) malformed JSON resilience for content manifests/definitions and save
##    files without crashing or corrupting a live session;
## 4) real two-process (`OS.create_process`) ENet host/client convergence,
##    90-second emergency disconnect grace window -> shelter transition,
##    and structured `BugBundleExporter` round-trip verification.

const TEST_SAVE_ROOT := "user://tests/p0_acceptance"
const CRASH_SLOT := "p0g_crash_slot"
const ALL_CORRUPT_SLOT := "p0g_all_corrupt_slot"
const WORKER_SLOT := "p0g_worker_slot"
const BUNDLE_SLOT := "p0g_bug_bundle_slot"
const BROKEN_MANIFEST_PATH := "user://tests/p0_acceptance/broken_manifest.json"
const WORKER_SCENE_PATH := "res://tests/integration/enet_client_worker.tscn"
const WORKER_DOCUMENT_NAME := "worker_report"

var _failures: Array[String] = []
var _checks: int = 0
var _host_session: GameSession
var _host_hash_at_remote_4_3: String = ""
var _worker_pid: int = -1


func _ready() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	_test_deterministic_fixed_seed_scenarios()
	_test_crash_during_save_recovery()
	_test_corrupt_json_resilience()
	await _test_two_process_host_client_disconnect_and_bug_bundle()

	if _failures.is_empty():
		print("P0_ACCEPTANCE_TESTS_OK checks=%d" % _checks)
		get_tree().quit(0)
	else:
		for failure in _failures:
			push_error("P0_ACCEPTANCE_TESTS_FAILED: %s" % failure)
		get_tree().quit(1)


func _test_deterministic_fixed_seed_scenarios() -> void:
	var run_a := _run_fixed_seed_scenario("p0g_fixed_seed", 20261021)
	var run_b := _run_fixed_seed_scenario("p0g_fixed_seed", 20261021)
	_check(
		bool(run_a.get("ok", false)) and bool(run_b.get("ok", false)),
		"both fixed-seed scenarios complete cleanly"
	)
	_check_equal(
		String(run_a.get("state_hash", "a")),
		String(run_b.get("state_hash", "b")),
		"fixed-seed replay produces identical domain_state_hash"
	)
	_check_equal(
		int(run_a.get("fact_count", -1)),
		int(run_b.get("fact_count", -2)),
		"fixed-seed replay produces identical FactLog length"
	)
	_check_equal(
		int(run_a.get("weather_sample", -1)),
		int(run_b.get("weather_sample", -2)),
		"fixed-seed replay produces identical named RNG stream draw"
	)


func _run_fixed_seed_scenario(campaign_id: String, seed_value: int) -> Dictionary:
	var session := _make_session("DetSession")
	var start: Dictionary = session.start_new_offline(campaign_id, seed_value, "host", "Host")
	if not bool(start.get("ok", false)):
		_destroy_session(session)
		return {"ok": false}
	session.register_system("hourly_rng_probe", 60, Callable(self, "_hourly_rng_probe"), 10)

	var world := session.world_state()
	var body_id := GreyboxWorld.find_body(world, "host")
	var crate_id := GreyboxWorld.find_supply_object(world)
	session.submit_intent(
		SessionProtocol.INTENT_INTERACT_OBJECT, {"target_entity_id": crate_id, "verb": "take_one"}
	)
	session.submit_intent(
		SessionProtocol.INTENT_MOVE_BODY, {"entity_id": body_id, "to_tile_x": 2, "to_tile_y": 3}
	)
	session.submit_intent(
		SessionProtocol.INTENT_MOVE_BODY, {"entity_id": body_id, "to_tile_x": 3, "to_tile_y": 3}
	)
	var advance: Dictionary = session.advance_simulation_minutes(180)
	var weather_sample := world.rng_streams().stream("weather").next_int_range(1, 1000000)
	var result := {
		"ok": bool(advance.get("ok", false)),
		"state_hash": session.domain_state_hash(),
		"fact_count": world.fact_log().size(),
		"weather_sample": weather_sample,
	}
	_destroy_session(session)
	return result


func _hourly_rng_probe(world: WorldState, context: Dictionary) -> bool:
	var draw := world.rng_streams().stream("ecology").next_int_range(0, 9999)
	var crate_id := GreyboxWorld.find_supply_object(world)
	if crate_id > 0:
		world.set_entity_component(
			crate_id, "rng_probe", {"minute": int(context.get("scheduled_minute", 0)), "draw": draw}
		)
	return true


func _test_crash_during_save_recovery() -> void:
	_clear_slot(CRASH_SLOT)
	var session := _make_session("CrashSourceSession")
	var start: Dictionary = session.start_new_offline("p0g_crash", 70707, "host", "Host")
	_check(bool(start.get("ok", false)), "crash test source session starts")
	session.advance_simulation_minutes(10)
	var save_v1: Dictionary = session.save_world(CRASH_SLOT)
	_check(bool(save_v1.get("ok", false)), "first valid snapshot saves to CRASH_SLOT")
	var hash_v1 := session.domain_state_hash()

	var body_id := GreyboxWorld.find_body(session.world_state(), "host")
	session.submit_intent(
		SessionProtocol.INTENT_MOVE_BODY, {"entity_id": body_id, "to_tile_x": 2, "to_tile_y": 3}
	)
	session.advance_simulation_minutes(15)
	var save_v2: Dictionary = session.save_world(CRASH_SLOT)
	_check(
		bool(save_v2.get("ok", false)),
		"second snapshot rotates first snapshot into world.backup1.json"
	)
	_destroy_session(session)

	var store := SaveStore.new(TEST_SAVE_ROOT, 5)
	var current_path := store.get_document_path(CRASH_SLOT, WorldStateCodec.WORLD_DOCUMENT_NAME)
	var slot_dir := store.get_slot_directory(CRASH_SLOT)
	_write_raw_text(current_path, '{"format":"tdl.world_save","truncated":')
	_write_raw_text(slot_dir.path_join("world.tmp.interrupted.json"), '{"half_written":true')

	var recovery_session := _make_session("CrashRecoverySession")
	var load_report: Dictionary = recovery_session.load_and_start_offline(
		CRASH_SLOT, "host", "Host"
	)
	_check(bool(load_report.get("ok", false)), "session recovers after simulated save crash")
	_check(bool(load_report.get("recovered", false)), "load report flags backup recovery")
	_check_equal(
		recovery_session.world_state().clock().total_minutes(),
		10,
		"recovered world minute matches backup1 snapshot"
	)
	_check_equal(
		recovery_session.domain_state_hash(),
		hash_v1,
		"recovered world state_hash matches backup1 snapshot"
	)
	_destroy_session(recovery_session)


func _test_corrupt_json_resilience() -> void:
	var live_session := _make_session("LiveResilienceSession")
	var start: Dictionary = live_session.start_new_offline("p0g_live", 30303, "host", "Host")
	_check(bool(start.get("ok", false)), "live session starts before corrupt JSON probes")
	var live_hash := live_session.domain_state_hash()

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TEST_SAVE_ROOT))
	_write_raw_text(BROKEN_MANIFEST_PATH, "{broken_manifest_json: [1, 2")

	var broken_session := _make_session("BrokenManifestSession")
	broken_session.content_manifest_path = BROKEN_MANIFEST_PATH
	var broken_start: Dictionary = broken_session.start_new_offline(
		"p0g_broken", 111, "host", "Host"
	)
	_check(
		not bool(broken_start.get("ok", true)), "corrupt content manifest JSON is rejected cleanly"
	)
	var broken_errors: Variant = broken_start.get("errors", [])
	_check(
		typeof(broken_errors) == TYPE_ARRAY and not (broken_errors as Array).is_empty(),
		"corrupt manifest rejection includes diagnostic error message"
	)
	_destroy_session(broken_session)

	_clear_slot(ALL_CORRUPT_SLOT)
	var store := SaveStore.new(TEST_SAVE_ROOT, 5)
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(store.get_slot_directory(ALL_CORRUPT_SLOT))
	)
	_write_raw_text(
		store.get_document_path(ALL_CORRUPT_SLOT, WorldStateCodec.WORLD_DOCUMENT_NAME),
		"not-a-json-document"
	)
	_write_raw_text(
		store.get_backup_path(ALL_CORRUPT_SLOT, WorldStateCodec.WORLD_DOCUMENT_NAME, 1),
		"{also_broken_backup"
	)

	var corrupt_load_session := _make_session("CorruptSaveSession")
	var corrupt_load: Dictionary = corrupt_load_session.load_and_start_offline(
		ALL_CORRUPT_SLOT, "host", "Host"
	)
	_check(
		not bool(corrupt_load.get("ok", true)),
		"corrupt current + backup save slot is rejected without crashing"
	)
	_destroy_session(corrupt_load_session)

	_check_equal(
		live_session.domain_state_hash(),
		live_hash,
		"unrelated live session state_hash is untouched by corrupt JSON probes"
	)
	_destroy_session(live_session)


func _test_two_process_host_client_disconnect_and_bug_bundle() -> void:
	_clear_slot(WORKER_SLOT)
	_clear_slot(BUNDLE_SLOT)
	_host_hash_at_remote_4_3 = ""
	_worker_pid = -1

	_host_session = _make_session("TwoProcessHostSession")
	var host_stage := _instantiate_stage()
	if host_stage != null:
		host_stage.bind_session(_host_session)

	var port := _start_host_on_available_port(_host_session)
	_check(port > 0, "two-process ENet host starts on port %d" % port)
	if port <= 0:
		_cleanup_two_process(host_stage)
		return

	var args := PackedStringArray(
		[
			"--headless",
			"--path",
			ProjectSettings.globalize_path("res://"),
			"--scene",
			WORKER_SCENE_PATH,
			"--quit-after",
			"1500",
			"--",
			"--port=%d" % port,
			"--save-root=%s" % TEST_SAVE_ROOT,
			"--slot=%s" % WORKER_SLOT,
		]
	)
	_worker_pid = OS.create_process(OS.get_executable_path(), args)
	_check(_worker_pid > 0, "spawned child Godot client process pid=%d" % _worker_pid)
	if _worker_pid <= 0:
		_cleanup_two_process(host_stage)
		return

	var completed: bool = await _wait_until(
		Callable(self, "_did_worker_complete_and_disconnect"), 12000
	)
	_check(completed, "child client process completed actions, wrote report and disconnected")

	var store := SaveStore.new(TEST_SAVE_ROOT, 2)
	var report_load: Dictionary = store.load_document(
		WORKER_SLOT, WORKER_DOCUMENT_NAME, Callable(self, "_accept_any_dict")
	)
	_check(bool(report_load.get("ok", false)), "worker report document loads from SaveStore")
	var worker_doc: Dictionary = report_load.get("document", {})
	_check(
		bool(worker_doc.get("ok", false)),
		"worker reported success (err=%s)" % String(worker_doc.get("error", ""))
	)
	_check(
		int(worker_doc.get("worker_pid", 0)) != OS.get_process_id(),
		"worker ran in a distinct OS process"
	)
	_check_equal(
		String(worker_doc.get("state_hash", "worker")),
		_host_hash_at_remote_4_3,
		"host and child-process client state_hash match at tile (4,3)"
	)
	_check_equal(int(worker_doc.get("local_tile_x", -1)), 4, "worker local actor tile_x")
	_check_equal(int(worker_doc.get("local_tile_y", -1)), 3, "worker local actor tile_y")
	_check_equal(int(worker_doc.get("crate_remaining", -1)), 2, "worker supply crate remaining")

	var status_after_disc: Dictionary = _host_session.session_status()
	var grace_map: Dictionary = status_after_disc.get("disconnect_grace", {})
	var remote_grace: Dictionary = grace_map.get("remote_peer", {})
	_check(
		float(remote_grace.get("remaining_sec", 0.0)) > 0.0,
		"disconnected remote_peer enters 90s emergency grace window"
	)
	_check(
		not bool(remote_grace.get("sheltered", true)),
		"remote_peer is not yet sheltered before 90s expire"
	)

	var half_step: Array[Dictionary] = _host_session.advance_disconnect_grace(40.0)
	_check(half_step.is_empty(), "40s grace step does not shelter remote_peer yet")
	var full_step: Array[Dictionary] = _host_session.advance_disconnect_grace(60.0)
	_check_equal(full_step.size(), 1, "remaining 60s grace step shelters remote_peer")
	var sheltered_facts: Array[Dictionary] = _host_session.world_state().fact_log().facts_of_kind(
		"participant_sheltered"
	)
	_check_equal(sheltered_facts.size(), 1, "FactLog records participant_sheltered after 90s grace")

	if host_stage != null:
		host_stage.refresh_presentation()
	var export_report: Dictionary = BugBundleExporter.export_to_store(
		store, BUNDLE_SLOT, _host_session, host_stage, "P0-G acceptance diagnostic bundle"
	)
	_check(bool(export_report.get("ok", false)), "BugBundleExporter writes bundle to SaveStore")
	var bundle_load: Dictionary = BugBundleExporter.load_from_store(store, BUNDLE_SLOT)
	_check(bool(bundle_load.get("ok", false)), "BugBundleExporter reloads and validates bundle")
	var bundle_payload: Dictionary = bundle_load.get("payload", {})
	_check_equal(
		String(bundle_payload.get("state_hash", "")),
		_host_session.domain_state_hash(),
		"loaded bug bundle state_hash matches host session"
	)

	_cleanup_two_process(host_stage)


func _did_worker_complete_and_disconnect() -> bool:
	if _host_session == null:
		return false
	var world := _host_session.world_state()
	var remote_id := GreyboxWorld.find_body(world, "remote_peer")
	if remote_id > 0 and _host_hash_at_remote_4_3.is_empty():
		var tile := GreyboxWorld.position_from_component(
			world.get_entity_component(remote_id, GreyboxWorld.POSITION_COMPONENT),
			_host_session.greybox_width_tiles,
			_host_session.greybox_height_tiles
		)
		if tile == Vector2i(4, 3):
			_host_hash_at_remote_4_3 = _host_session.domain_state_hash()

	var store := SaveStore.new(TEST_SAVE_ROOT, 2)
	if not store.has_document(WORKER_SLOT, WORKER_DOCUMENT_NAME):
		return false
	var grace: Dictionary = _host_session.session_status().get("disconnect_grace", {})
	return grace.has("remote_peer")


func _wait_until(predicate: Callable, timeout_msec: int) -> bool:
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < timeout_msec:
		if _host_session != null:
			_host_session.poll_transport()
			_host_session.process_pending_intents()
		if bool(predicate.call()):
			return true
		OS.delay_msec(4)
		await get_tree().process_frame
	return bool(predicate.call())


func _start_host_on_available_port(session: GameSession) -> int:
	for offset in range(25):
		var candidate_port := 25310 + offset
		var report: Dictionary = session.start_new_host(
			"p0g_two_proc", 888999, candidate_port, "host", "Host"
		)
		if bool(report.get("ok", false)):
			return candidate_port
	return -1


func _make_session(session_name: String) -> GameSession:
	var session := GameSession.new()
	session.name = session_name
	session.save_root_dir = TEST_SAVE_ROOT
	session.save_backup_count = 3
	add_child(session)
	return session


func _instantiate_stage() -> GreyboxStage:
	var packed := load("res://scenes/levels/greybox_stage.tscn") as PackedScene
	if packed == null:
		return null
	var stage := packed.instantiate() as GreyboxStage
	if stage == null:
		return null
	stage.auto_start_offline = false
	stage.save_root_dir = TEST_SAVE_ROOT
	add_child(stage)
	return stage


func _destroy_session(session: GameSession) -> void:
	if session != null and is_instance_valid(session):
		session.stop_session()
		session.free()


func _cleanup_two_process(host_stage: GreyboxStage) -> void:
	if host_stage != null and is_instance_valid(host_stage):
		host_stage.bind_session(null)
		host_stage.free()
	_destroy_session(_host_session)
	_host_session = null
	if _worker_pid > 0 and OS.is_process_running(_worker_pid):
		OS.kill(_worker_pid)
	_worker_pid = -1


func _accept_any_dict(doc: Dictionary) -> bool:
	return not doc.is_empty()


func _write_raw_text(path: String, content: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(content)
		file.close()


func _clear_slot(slot_id: String) -> void:
	var store := SaveStore.new(TEST_SAVE_ROOT, 5)
	var slot_dir := store.get_slot_directory(slot_id)
	var dir := DirAccess.open(slot_dir)
	if dir == null:
		return
	var files: Array[String] = []
	dir.list_dir_begin()
	var entry := dir.get_next()
	while not entry.is_empty():
		if not dir.current_is_dir():
			files.append(slot_dir.path_join(entry))
		entry = dir.get_next()
	dir.list_dir_end()
	for file_path in files:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(file_path))


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(label)


func _check_equal(actual: Variant, expected: Variant, label: String) -> void:
	_checks += 1
	if actual != expected:
		_failures.append("%s: expected %s, got %s" % [label, str(expected), str(actual)])
