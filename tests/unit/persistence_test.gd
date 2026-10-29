extends Node
## P0-D persistence contracts: WorldState snapshots, checksums, one-step
## migration, atomic document replacement and backup recovery.

const TEST_ROOT_DIR := "user://tests/persistence"
const LEGACY_FIXTURE_PATH := "res://tests/fixtures/saves/world_v0_legacy.json"
const TEST_SEED := 9007199254740993

var _failures: Array[String] = []
var _checks: int = 0


func _ready() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	_test_world_state_contract()
	_test_codec_round_trip_and_rejection()
	_test_legacy_migration()
	_test_save_store_rotation_and_recovery()
	_test_world_codec_store_recovery()

	if _failures.is_empty():
		print("PERSISTENCE_TESTS_OK checks=%d" % _checks)
		get_tree().quit(0)
	else:
		for failure in _failures:
			push_error("PERSISTENCE_TESTS_FAILED: %s" % failure)
		get_tree().quit(1)


func _test_world_state_contract() -> void:
	var invalid_world := WorldState.new()
	var duplicate_packages := _content_packages()
	duplicate_packages.append(duplicate_packages[0].duplicate(true))
	_check(
		not invalid_world.setup_campaign("bad_campaign", TEST_SEED, duplicate_packages),
		"duplicate content packages rejected"
	)
	_check(not invalid_world.is_initialized(), "failed setup leaves world uninitialized")
	_check(
		not invalid_world.setup_campaign("empty_packages", TEST_SEED, []),
		"fresh campaign requires content package pins"
	)
	_check(not invalid_world.is_initialized(), "empty package setup leaves world uninitialized")

	var world := _make_world("spring_valley_contract", 1500)
	_check(world.is_initialized(), "world initializes")
	_check_equal(world.campaign_id(), "spring_valley_contract", "campaign id")
	_check_equal(world.genesis_seed(), TEST_SEED, "genesis seed stays exact i64")
	_check_equal(world.clock().total_minutes(), 1500, "world clock snapshot input")
	_check_equal(world.fact_log().size(), 1, "world fact log populated")
	_check_equal(world.entity_ids(), [1, 2], "runtime entity ids are sequential")
	_check_equal(world.peek_next_entity_id(), 3, "next runtime entity id")

	var packages := world.content_packages()
	_check_equal(packages.size(), 2, "content package count")
	if packages.size() == 2:
		_check_equal(
			String(packages[0].get("package_id", "")), "core", "content packages sorted by id"
		)

	var entity := world.get_entity(1)
	_check_equal(
		String(entity.get("definition_id", "")), "core:species/navelu", "entity definition"
	)
	var copied_components := _as_dictionary(entity.get("components", {}))
	var copied_position := _as_dictionary(copied_components.get("position", {}))
	copied_position["tile_x"] = 999
	var current_position := _as_dictionary(world.get_entity_component(1, "position"))
	_check_equal(
		int(current_position.get("tile_x", -1)), 10, "entity reads return defensive copies"
	)

	_check(
		world.set_entity_component(1, "position", {"tile_x": 11, "tile_y": 12}), "component update"
	)
	_check(
		not world.set_entity_component(1, "Bad Component", {}), "invalid component name rejected"
	)
	_check(not world.set_entity_component(99, "position", {}), "missing entity component rejected")
	_check_equal(world.create_entity("not a stable id", {}), -1, "invalid definition id rejected")
	_check_equal(world.peek_next_entity_id(), 3, "rejected entity does not consume an id")
	_check(world.remove_entity(2), "entity removal")
	_check(not world.has_entity(2), "removed entity no longer exists")

	_check(
		is_equal_approx(world.world_rules().effective_game_minutes_per_real_second(), 2.0),
		"default WorldRules 12-min day yields 2.0 game minutes per real second"
	)
	var rules_patch: Dictionary = (
		world
		. world_rules()
		. apply_patch(
			{
				"lobby_name": "Sevara Test Lobby",
				"day_length_real_minutes": 6.0,
				"time_scale": 2.5,
				"skill_xp_multiplier": 3.0,
			}
		)
	)
	_check(bool(rules_patch.get("ok", false)), "valid WorldRules patch applies")
	_check(
		is_equal_approx(world.world_rules().effective_game_minutes_per_real_second(), 10.0),
		"patched WorldRules 6-min day x2.5 yields 10.0 game minutes per real second"
	)
	var bad_rules_patch: Dictionary = world.world_rules().apply_patch({"max_players": 99})
	_check(not bool(bad_rules_patch.get("ok", true)), "out-of-range max_players rejected")
	_check_equal(
		world.world_rules().lobby_name(),
		"Sevara Test Lobby",
		"rejected WorldRules patch leaves existing rules intact"
	)

	var snapshot := world.snapshot_state()
	_check(JsonValue.is_safe(snapshot), "world snapshot is JSON-safe")
	var parsed_snapshot := _json_round_trip(snapshot)
	var restored := WorldState.new()
	_check(restored.restore_state(parsed_snapshot), "JSON-parsed world snapshot restores")
	_check_equal(
		StateHash.sha256_hex(restored.snapshot_state()),
		StateHash.sha256_hex(world.snapshot_state()),
		"restored world state hash matches"
	)

	var bad_snapshot := _duplicate_dictionary(snapshot)
	bad_snapshot["schema_version"] = 99
	_check(not WorldState.new().restore_state(bad_snapshot), "future world schema rejected")

	bad_snapshot = _duplicate_dictionary(snapshot)
	bad_snapshot["unknown_field"] = true
	_check(not WorldState.new().restore_state(bad_snapshot), "unknown world field rejected")

	bad_snapshot = _duplicate_dictionary(snapshot)
	bad_snapshot["campaign_id"] = true
	_check(not WorldState.new().restore_state(bad_snapshot), "non-string campaign id rejected")

	bad_snapshot = _duplicate_dictionary(snapshot)
	var bad_packages: Array = bad_snapshot.get("content_packages", [])
	if not bad_packages.is_empty():
		var first_package := _duplicate_dictionary(bad_packages[0])
		first_package["version"] = true
		bad_packages[0] = first_package
		bad_snapshot["content_packages"] = bad_packages
	_check(not WorldState.new().restore_state(bad_snapshot), "non-string package version rejected")

	bad_snapshot = _duplicate_dictionary(snapshot)
	var bad_rng := _duplicate_dictionary(bad_snapshot.get("rng", {}))
	bad_rng["root_seed"] = str(TEST_SEED + 1)
	bad_snapshot["rng"] = bad_rng
	_check(not WorldState.new().restore_state(bad_snapshot), "RNG/genesis mismatch rejected")

	bad_snapshot = _duplicate_dictionary(snapshot)
	bad_snapshot["next_entity_id"] = "1"
	_check(not WorldState.new().restore_state(bad_snapshot), "entity id reuse rejected")

	bad_snapshot = _duplicate_dictionary(snapshot)
	var bad_facts := _duplicate_dictionary(bad_snapshot.get("facts", {}))
	var fact_rows: Array = bad_facts.get("facts", [])
	if not fact_rows.is_empty():
		var first_fact := _duplicate_dictionary(fact_rows[0])
		first_fact["game_minute"] = 999999
		fact_rows[0] = first_fact
		bad_facts["facts"] = fact_rows
		bad_snapshot["facts"] = bad_facts
	_check(not WorldState.new().restore_state(bad_snapshot), "future fact rejected by world")

	var preserved := _make_world("preserved_campaign", 10)
	bad_snapshot = _duplicate_dictionary(snapshot)
	bad_snapshot["campaign_id"] = "should_not_commit"
	bad_snapshot["next_entity_id"] = "0"
	_check(not preserved.restore_state(bad_snapshot), "invalid restore returns false")
	_check_equal(
		preserved.campaign_id(), "preserved_campaign", "invalid restore does not partially commit"
	)


func _test_codec_round_trip_and_rejection() -> void:
	var world := _make_world("spring_valley_codec", 4321)
	var encoded := WorldStateCodec.encode(world, "0.1.0-test", 1700000000)
	_check(bool(encoded.get("ok", false)), "world codec encodes")
	var document := _as_dictionary(encoded.get("document", {}))
	_check_equal(String(document.get("format", "")), WorldStateCodec.FORMAT, "codec format")
	_check_equal(int(document.get("schema_version", -1)), 1, "codec schema")
	_check_equal(String(document.get("game_version", "")), "0.1.0-test", "codec game version")
	_check_equal(int(document.get("created_at_unix", -1)), 1700000000, "codec created time")
	_check_equal(String(document.get("payload_sha256", "")).length(), 64, "codec checksum length")

	var expected_rng: Array[int] = [
		world.rng_streams().randi_range(&"ecology", -1000000, 1000000),
		world.rng_streams().randi_range(&"ecology", -1000000, 1000000),
	]

	var decoded := WorldStateCodec.decode(_json_round_trip(document))
	_check(bool(decoded.get("ok", false)), "world codec decodes JSON-parsed document")
	_check_equal(int(decoded.get("source_schema_version", -1)), 1, "decoded source schema")
	_check(not bool(decoded.get("migrated", true)), "v1 document is not marked migrated")
	var decoded_world := decoded.get("world") as WorldState
	_check(decoded_world != null, "decoded world exists")
	if decoded_world != null:
		_check_equal(decoded_world.campaign_id(), "spring_valley_codec", "decoded campaign")
		_check_equal(decoded_world.genesis_seed(), TEST_SEED, "decoded genesis seed")
		_check_equal(decoded_world.clock().total_minutes(), 4321, "decoded clock")
		_check_equal(decoded_world.entity_ids(), [1, 2], "decoded entities")
		var actual_rng: Array[int] = [
			decoded_world.rng_streams().randi_range(&"ecology", -1000000, 1000000),
			decoded_world.rng_streams().randi_range(&"ecology", -1000000, 1000000),
		]
		_check_equal(actual_rng, expected_rng, "decoded RNG continues original stream")

	var tampered := _json_round_trip(document)
	var tampered_payload := _duplicate_dictionary(tampered.get("payload", {}))
	tampered_payload["campaign_id"] = "tampered_campaign"
	tampered["payload"] = tampered_payload
	_check(
		not bool(WorldStateCodec.decode(tampered).get("ok", true)),
		"payload tampering fails checksum"
	)

	var future := _json_round_trip(document)
	future["schema_version"] = 99
	_check(not bool(WorldStateCodec.decode(future).get("ok", true)), "future save schema rejected")

	var wrong_format := _json_round_trip(document)
	wrong_format["format"] = "other.format"
	_check(
		not bool(WorldStateCodec.decode(wrong_format).get("ok", true)), "wrong save format rejected"
	)

	var unknown_field := _json_round_trip(document)
	unknown_field["surprise"] = true
	_check(
		not bool(WorldStateCodec.decode(unknown_field).get("ok", true)),
		"unknown envelope field rejected"
	)

	_check(
		not bool(WorldStateCodec.encode(WorldState.new()).get("ok", true)),
		"uninitialized world cannot encode"
	)


func _test_legacy_migration() -> void:
	var parser_store := SaveStore.new(TEST_ROOT_DIR)
	var fixture := parser_store.read_document_at_path(LEGACY_FIXTURE_PATH)
	_check(bool(fixture.get("ok", false)), "legacy fixture parses")
	var legacy_document := _as_dictionary(fixture.get("document", {}))

	var decoded := WorldStateCodec.decode(legacy_document)
	_check(bool(decoded.get("ok", false)), "legacy v0 document migrates")
	_check_equal(int(decoded.get("source_schema_version", -1)), 0, "legacy source schema")
	_check(bool(decoded.get("migrated", false)), "legacy migration is reported")
	var migrated_world := decoded.get("world") as WorldState
	_check(migrated_world != null, "migrated world exists")
	if migrated_world != null:
		_check_equal(migrated_world.campaign_id(), "spring_valley_legacy", "migrated campaign id")
		_check_equal(migrated_world.genesis_seed(), 9876543210123, "migrated genesis seed")
		_check_equal(migrated_world.clock().total_minutes(), 3000, "migrated clock")
		_check_equal(migrated_world.entity_ids(), [2, 7], "migrated entity ids sorted")
		_check_equal(migrated_world.peek_next_entity_id(), 8, "migrated next entity id")
		_check_equal(
			migrated_world.create_entity("core:species/selave", {}),
			8,
			"migrated world allocates after highest legacy id"
		)

	var duplicate_legacy := _duplicate_dictionary(legacy_document)
	var entities: Array = duplicate_legacy.get("entities", [])
	if entities.size() == 2:
		var second := _duplicate_dictionary(entities[1])
		second["id"] = 7
		entities[1] = second
		duplicate_legacy["entities"] = entities
	_check(
		not bool(WorldStateCodec.decode(duplicate_legacy).get("ok", true)),
		"duplicate legacy entity id rejected"
	)

	var bad_legacy_campaign := _duplicate_dictionary(legacy_document)
	bad_legacy_campaign["campaign_id"] = true
	_check(
		not bool(WorldStateCodec.decode(bad_legacy_campaign).get("ok", true)),
		"non-string legacy campaign id rejected"
	)


func _test_save_store_rotation_and_recovery() -> void:
	_check_equal(
		SaveStore.new("user://").root_dir(),
		SaveStore.DEFAULT_ROOT_DIR,
		"bare user root is not a save store root"
	)
	_check_equal(
		SaveStore.new("user://tests/../escape").root_dir(),
		SaveStore.DEFAULT_ROOT_DIR,
		"traversal save root rejected"
	)

	var store := SaveStore.new(TEST_ROOT_DIR, 2)
	var slot_id := "generic_store"
	store.delete_slot(slot_id)

	_check_equal(store.get_document_path("../escape", "world"), "", "path escape rejected")
	_check(
		not bool(store.save_document("../escape", "world", {}).get("ok", true)),
		"invalid slot cannot save"
	)

	var stale_temp_path := _create_stale_temp_file(store, slot_id)
	_check(FileAccess.file_exists(stale_temp_path), "stale temp fixture exists")
	for value in [1, 2, 3, 4]:
		var saved := store.save_document(slot_id, "sample", {"value": value})
		_check(bool(saved.get("ok", false)), "generic document %d saves" % value)
	_check(not FileAccess.file_exists(stale_temp_path), "stale temp cleaned on next save")

	var candidates := store.get_candidate_paths(slot_id, "sample")
	_check_equal(candidates.size(), 3, "current plus two rotated backups retained")
	var current := store.load_document(slot_id, "sample")
	_check(bool(current.get("ok", false)), "current generic document loads")
	_check_equal(
		int(_as_dictionary(current.get("document", {})).get("value", -1)),
		4,
		"newest generic document is current"
	)

	var recovered := store.load_document(
		slot_id, "sample", Callable(self, "_generic_document_is_usable")
	)
	_check(bool(recovered.get("ok", false)), "validator fallback loads a backup")
	_check(bool(recovered.get("recovered", false)), "validator fallback reports recovery")
	_check_equal(
		int(_as_dictionary(recovered.get("document", {})).get("value", -1)),
		3,
		"validator fallback returns previous document"
	)

	_check(store.delete_slot(slot_id), "generic test slot deletes")
	_check(not store.has_document(slot_id, "sample"), "deleted generic document is gone")
	var missing_document := store.load_document(slot_id, "sample")
	_check(not bool(missing_document.get("ok", true)), "missing generic document fails cleanly")
	_check(
		not bool(missing_document.get("recovered", true)),
		"missing generic document reports recovered=false"
	)


func _test_world_codec_store_recovery() -> void:
	var store := SaveStore.new(TEST_ROOT_DIR, 3)
	var slot_id := "world_recovery"
	store.delete_slot(slot_id)

	var missing := WorldStateCodec.load_from_store(store, slot_id)
	_check(not bool(missing.get("ok", true)), "missing world slot is a report, not a crash")

	var first_world := _make_world("recovery_campaign", 200)
	var first_save := WorldStateCodec.save_to_store(first_world, store, slot_id, "test", 10)
	_check(bool(first_save.get("ok", false)), "first world save succeeds")

	var second_world := _make_world("recovery_campaign", 300)
	var second_save := WorldStateCodec.save_to_store(second_world, store, slot_id, "test", 20)
	_check(bool(second_save.get("ok", false)), "second world save succeeds")
	_check(store.has_document(slot_id, "world"), "world current document exists")
	_check(
		FileAccess.file_exists(store.get_backup_path(slot_id, "world", 1)),
		"first world rotated to backup1"
	)

	var latest := WorldStateCodec.load_from_store(store, slot_id)
	_check(bool(latest.get("ok", false)), "latest world loads from store")
	_check(not bool(latest.get("recovered", true)), "latest world does not need recovery")
	var latest_world := latest.get("world") as WorldState
	if latest_world != null:
		_check_equal(latest_world.clock().total_minutes(), 300, "latest world minute")

	var current_path := store.get_document_path(slot_id, "world")
	_check(_write_text_file(current_path, "{ this is not json"), "corrupt current fixture")
	var after_truncation := WorldStateCodec.load_from_store(store, slot_id)
	_check(bool(after_truncation.get("ok", false)), "corrupt JSON falls back to backup")
	_check(bool(after_truncation.get("recovered", false)), "corrupt JSON reports recovery")
	var backup_world := after_truncation.get("world") as WorldState
	if backup_world != null:
		_check_equal(backup_world.clock().total_minutes(), 200, "backup world minute")

	# Simulate the crash window after current rotated to backup1 but
	# before the verified temp file was renamed into place.
	_check(DirAccess.remove_absolute(current_path) == OK, "missing current fixture")
	var after_missing_current := WorldStateCodec.load_from_store(store, slot_id)
	_check(bool(after_missing_current.get("ok", false)), "missing current falls back to backup")
	_check(bool(after_missing_current.get("recovered", false)), "missing current reports recovery")
	var missing_current_world := after_missing_current.get("world") as WorldState
	if missing_current_world != null:
		_check_equal(missing_current_world.clock().total_minutes(), 200, "missing-current backup")

	var checksum_slot := "world_checksum_recovery"
	store.delete_slot(checksum_slot)
	WorldStateCodec.save_to_store(_make_world("checksum_campaign", 400), store, checksum_slot)
	WorldStateCodec.save_to_store(_make_world("checksum_campaign", 500), store, checksum_slot)
	var checksum_path := store.get_document_path(checksum_slot, "world")
	var current_document := _as_dictionary(
		store.read_document_at_path(checksum_path).get("document", {})
	)
	var payload := _duplicate_dictionary(current_document.get("payload", {}))
	payload["campaign_id"] = "checksum_tamper"
	current_document["payload"] = payload
	_check(
		_write_text_file(checksum_path, JSON.stringify(current_document)), "checksum tamper fixture"
	)
	var after_checksum := WorldStateCodec.load_from_store(store, checksum_slot)
	_check(bool(after_checksum.get("ok", false)), "checksum failure falls back to backup")
	_check(bool(after_checksum.get("recovered", false)), "checksum recovery reported")
	var checksum_world := after_checksum.get("world") as WorldState
	if checksum_world != null:
		_check_equal(checksum_world.clock().total_minutes(), 400, "checksum backup minute")

	_check(store.delete_slot(slot_id), "recovery slot deletes")
	_check(store.delete_slot(checksum_slot), "checksum slot deletes")


func _make_world(campaign_id: String, total_minutes: int) -> WorldState:
	var world := WorldState.new()
	_check(
		world.setup_campaign(campaign_id, TEST_SEED, _content_packages()),
		"test world '%s' setup" % campaign_id
	)
	world.clock().advance_minutes(total_minutes)
	world.rng_streams().randi_range(&"ecology", 0, 1000000)
	var fact := world.fact_log().append_fact(
		"world_created", total_minutes, {"campaign_id": campaign_id, "minute_marker": total_minutes}
	)
	_check(not fact.is_empty(), "test world fact appended")

	var first_id := (
		world
		. create_entity(
			"core:species/navelu",
			{
				"position": {"tile_x": 10, "tile_y": 20},
				"vitality": {"health": 0.9},
			}
		)
	)
	var second_id := world.create_entity("core:material/torava_wood", {"stack": {"count": 5}})
	_check_equal(first_id, 1, "first test entity id")
	_check_equal(second_id, 2, "second test entity id")
	return world


func _content_packages() -> Array[Dictionary]:
	# The official package pin must come from the real registry accessors;
	# the second synthetic package only proves canonical sorting.
	var registry := DefinitionRegistry.new()
	var report := registry.load_package("res://data/core/manifest.json")
	_check(bool(report.get("ok", false)), "core package loads for world pin")
	var packages: Array[Dictionary] = [
		{
			"package_id": "zeta_pack",
			"version": "2.0.0",
			"manifest_hash": "b".repeat(64),
		},
		{
			"package_id": registry.package_id(),
			"version": registry.package_version(),
			"manifest_hash": registry.manifest_hash(),
		},
	]
	return packages


func _generic_document_is_usable(document: Dictionary) -> bool:
	return int(document.get("value", 99)) < 4


func _create_stale_temp_file(store: SaveStore, slot_id: String) -> String:
	var slot_directory := store.get_slot_directory(slot_id)
	DirAccess.make_dir_recursive_absolute(slot_directory)
	var stale_path := slot_directory.path_join("sample.tmp-stale.json")
	_write_text_file(stale_path, "{}")
	return stale_path


func _json_round_trip(document: Dictionary) -> Dictionary:
	var json := JSON.new()
	var parse_error := json.parse(JSON.stringify(document))
	if parse_error != OK or typeof(json.data) != TYPE_DICTIONARY:
		_failures.append("JSON round-trip failed in persistence test")
		return {}
	return json.data


func _write_text_file(path: String, text: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_buffer(text.to_utf8_buffer())
	file.close()
	return true


func _duplicate_dictionary(value: Variant) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return {}
	var dictionary: Dictionary = value
	return dictionary.duplicate(true)


func _as_dictionary(value: Variant) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return {}
	var dictionary: Dictionary = value
	return dictionary


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)


func _check_equal(actual: Variant, expected: Variant, message: String) -> void:
	_checks += 1
	if actual != expected:
		_failures.append("%s: expected %s, got %s" % [message, str(expected), str(actual)])
