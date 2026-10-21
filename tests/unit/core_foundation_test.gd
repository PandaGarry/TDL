extends Node
## Lightweight P0 foundation tests.
##
## GdUnit4 remains the preferred long-term framework, but these contracts
## should not wait for a plugin spike: this scene is a deterministic,
## dependency-free runner for the first Core primitives. CI treats the
## failure marker and non-zero exit as a hard failure.

var _failures: Array[String] = []
var _checks: int = 0


func _ready() -> void:
	call_deferred("_run_tests")


func _run_tests() -> void:
	_test_project_foundation()
	_test_stable_id()
	_test_json_value()
	_test_world_clock()
	_test_rng_streams()
	_test_fact_log()
	_test_state_hash()
	_test_definition_registry()
	_test_sevara_eco_chain()

	if _failures.is_empty():
		print("CORE_FOUNDATION_TESTS_OK checks=%d" % _checks)
		get_tree().quit(0)
	else:
		for failure in _failures:
			push_error("CORE_FOUNDATION_TESTS_FAILED: %s" % failure)
		get_tree().quit(1)


func _test_project_foundation() -> void:
	var expected_layers := {
		PhysicsLayers.TERRAIN: "Terrain",
		PhysicsLayers.BODIES: "Bodies",
		PhysicsLayers.STRUCTURES: "Structures",
		PhysicsLayers.ITEMS: "Items",
		PhysicsLayers.INTERACTABLES: "Interactables",
		PhysicsLayers.HAZARDS: "Hazards",
		PhysicsLayers.SENSORS: "Sensors",
		PhysicsLayers.PROJECTILES: "Projectiles",
	}
	for layer in expected_layers.keys():
		_check_equal(
			PhysicsLayers.layer_name(int(layer)),
			expected_layers[layer],
			"2D physics layer %d name" % int(layer)
		)
	_check_equal(
		PhysicsLayers.bit(PhysicsLayers.BODIES), PhysicsLayers.BODIES_BIT, "Bodies layer bit"
	)
	_check_equal(
		String(ProjectSettings.get_setting("layer_names/3d_physics/layer_1", "")),
		"",
		"legacy 3D layer names removed"
	)

	var required_actions: Array[String] = [
		"move_left",
		"move_right",
		"move_up",
		"move_down",
		"move_run",
		"move_careful",
		"inspect",
		"interact",
		"assist_or_talk",
		"carry_toggle",
		"tool_primary",
		"tool_secondary",
		"throw_or_place",
		"build_or_repair",
		"collect_sample",
		"consume",
		"rest_or_sleep",
		"group_command",
		"debug_toggle",
		"toggle_pause",
	]
	for action_name in required_actions:
		_check(InputMap.has_action(action_name), "InputMap has action '%s'" % action_name)

	for removed_action in ["jump", "dash", "attack_primary"]:
		_check(
			not InputMap.has_action(removed_action), "template action '%s' removed" % removed_action
		)

	_check(_action_has_keycode(&"move_run", KEY_SHIFT), "move_run defaults to Shift")
	_check(_action_has_keycode(&"group_command", KEY_TAB), "group_command defaults to Tab")
	_check(_action_has_keycode(&"debug_toggle", KEY_F3), "debug_toggle defaults to F3")


func _test_stable_id() -> void:
	_check(StableId.is_valid("core:species/navelu"), "canonical stable ID is valid")
	_check(StableId.is_valid("future_mod:material/deep/iron_ingot"), "nested stable ID is valid")
	_check(not StableId.is_valid("Core:Species/Navelu"), "uppercase stable ID rejected")
	_check(not StableId.is_valid("core:navelu"), "stable ID without kind/name rejected")
	_check(not StableId.is_valid("core:species/navelu "), "stable ID with whitespace rejected")
	for invalid_id in [
		"core::species/navelu",
		"core:species//navelu",
		"core:species/",
		"core:/navelu",
		"core:species/navelu/",
	]:
		_check(
			not StableId.is_valid(invalid_id), "empty stable ID segment rejected: %s" % invalid_id
		)
	_check_equal(StableId.namespace_of("core:species/navelu"), "core", "stable ID namespace")
	_check_equal(StableId.kind_of("core:species/navelu"), "species", "stable ID kind")
	_check_equal(StableId.name_of("core:species/navelu"), "navelu", "stable ID name")
	_check_equal(
		StableId.make("core", "material", "torava_wood"),
		"core:material/torava_wood",
		"stable ID factory"
	)
	_check_equal(StableId.make("Core", "material", "wood"), "", "invalid stable ID factory result")


func _test_json_value() -> void:
	_check(JsonValue.is_safe({"nested": [1, {"ok": true}]}), "nested JSON-safe value accepted")
	_check(
		JsonValue.is_safe({"max": JsonValue.MAX_SAFE_INTEGER}), "max exact JSON integer accepted"
	)
	_check(
		not JsonValue.is_safe({"too_big": JsonValue.MAX_SAFE_INTEGER + 1}),
		"integer beyond exact JSON range rejected"
	)
	var canonical: Dictionary = JsonValue.duplicate_canonical(
		{"whole": 2.0, "fraction": 2.5, "nested": [3.0]}
	)
	_check_equal(typeof(canonical["whole"]), TYPE_INT, "integral JSON float canonicalizes to int")
	_check_equal(typeof(canonical["fraction"]), TYPE_FLOAT, "fractional JSON float stays float")
	_check_equal(
		typeof((canonical["nested"] as Array)[0]),
		TYPE_INT,
		"nested integral JSON float canonicalizes"
	)
	var cyclic: Dictionary = {}
	cyclic["self"] = cyclic
	_check(not JsonValue.is_safe(cyclic), "cyclic JSON value rejected by depth guard")


func _test_world_clock() -> void:
	var clock := WorldClock.new()
	clock.setup()
	_check_equal(clock.year_number(), 1, "clock starts in year 1")
	_check_equal(clock.day_of_season(), 1, "clock starts on season day 1")
	_check_equal(clock.season_index(), 0, "clock starts in first season")

	var first_report := clock.advance_minutes(59)
	_check_equal(int(first_report["hours_crossed"]), 0, "59 minutes crosses no hour")
	var second_report := clock.advance_minutes(1)
	_check_equal(int(second_report["hours_crossed"]), 1, "60th minute crosses one hour")

	clock.setup()
	var season_report := clock.advance_minutes(
		WorldClock.MINUTES_PER_DAY * WorldClock.DAYS_PER_SEASON
	)
	_check_equal(int(season_report["seasons_crossed"]), 1, "30 days cross one season")
	_check_equal(clock.season_index(), 1, "clock enters second season")
	_check_equal(clock.day_of_season(), 1, "new season starts at day 1")

	var snapshot := clock.snapshot_state()
	var restored := WorldClock.new()
	_check(restored.restore_state(snapshot), "clock snapshot restores")
	_check_equal(restored.total_minutes(), clock.total_minutes(), "restored clock total minutes")

	var invalid_clock := WorldClock.new()
	invalid_clock.setup(60)
	_check(
		not invalid_clock.restore_state(
			{"schema_version": WorldClock.SCHEMA_VERSION, "total_minutes": -1}
		),
		"negative clock snapshot rejected"
	)
	_check_equal(invalid_clock.total_minutes(), 60, "failed clock restore preserves state")

	restored.setup(WorldClock.MINUTES_PER_DAY * (WorldClock.DAYS_PER_YEAR - 1))
	restored.advance_minutes(WorldClock.MINUTES_PER_DAY)
	_check_equal(restored.year_number(), 2, "clock crosses into year 2")


func _test_rng_streams() -> void:
	var first := RngStreams.new()
	first.setup(123456)
	var first_sequence: Array[int] = []
	for index in range(5):
		first_sequence.append(first.randi_range(&"ecology", 1, 1_000_000))

	var second := RngStreams.new()
	second.setup(123456)
	var second_sequence: Array[int] = []
	for index in range(5):
		second_sequence.append(second.randi_range(&"ecology", 1, 1_000_000))
	_check_equal(second_sequence, first_sequence, "same seed and stream reproduce sequence")

	var weather_sequence: Array[int] = []
	var weather := RngStreams.new()
	weather.setup(123456)
	for index in range(5):
		weather_sequence.append(weather.randi_range(&"weather", 1, 1_000_000))
	_check(weather_sequence != first_sequence, "different named streams diverge")

	var source := RngStreams.new()
	source.setup(98765)
	source.randi_range(&"society", 1, 1000)
	source.randi_range(&"society", 1, 1000)
	var snapshot := source.snapshot_state()
	_check_equal(
		int(snapshot.get("schema_version", -1)), RngStreams.SCHEMA_VERSION, "RNG snapshot schema"
	)
	_check_equal(typeof(snapshot["root_seed"]), TYPE_STRING, "RNG root seed is string-encoded")
	var snapshot_streams: Dictionary = snapshot["streams"]
	_check_equal(
		typeof(snapshot_streams["society"]), TYPE_STRING, "RNG stream state is string-encoded"
	)
	var expected_next: Array[int] = []
	for index in range(3):
		expected_next.append(source.randi_range(&"society", 1, 1000))

	var restored := RngStreams.new()
	_check(restored.restore_state(snapshot), "RNG snapshot restores")
	var restored_next: Array[int] = []
	for index in range(3):
		restored_next.append(restored.randi_range(&"society", 1, 1000))
	_check_equal(restored_next, expected_next, "restored RNG stream continues identically")

	var preserved := RngStreams.new()
	preserved.setup(424242)
	preserved.randi_range(&"weather", 1, 1000)
	var preserved_clone := RngStreams.new()
	preserved_clone.setup(424242)
	preserved_clone.randi_range(&"weather", 1, 1000)
	var bad_snapshot: Dictionary = snapshot.duplicate(true)
	var bad_streams: Dictionary = bad_snapshot["streams"]
	bad_streams["society"] = "not_an_integer"
	bad_snapshot["streams"] = bad_streams
	_check(not preserved.restore_state(bad_snapshot), "invalid RNG snapshot rejected")
	_check_equal(
		preserved.randi_range(&"weather", 1, 1000),
		preserved_clone.randi_range(&"weather", 1, 1000),
		"failed RNG restore preserves current streams"
	)


func _test_fact_log() -> void:
	var log := FactLog.new()
	var returned := log.append_fact(
		"object_changed", 120, {"state": "open", "values": [1, 2, 3]}, 42, "core:species/navelu"
	)
	_check_equal(int(returned.get("sequence", 0)), 1, "first fact sequence")
	_check_equal(log.size(), 1, "fact log stores first fact")

	var returned_payload: Dictionary = returned["payload"]
	returned_payload["state"] = "mutated_outside"
	var stored_payload: Dictionary = log.facts()[0]["payload"]
	_check_equal(String(stored_payload["state"]), "open", "returned fact is an immutable copy")

	var rejected := log.append_fact("invalid_payload", 121, {"position": Vector2.ONE})
	_check(rejected.is_empty(), "non-JSON-safe fact payload rejected")
	_check_equal(log.size(), 1, "rejected fact does not change log size")
	var bad_actor := log.append_fact("invalid_actor", 121, {}, -2)
	_check(bad_actor.is_empty(), "fact with actor_id below -1 rejected")
	_check_equal(log.size(), 1, "invalid actor fact does not change log size")

	var snapshot := log.snapshot_state()
	var restored := FactLog.new()
	_check(restored.restore_state(snapshot), "fact log snapshot restores")
	var next_fact := restored.append_fact("world_restored", 122)
	_check_equal(int(next_fact.get("sequence", 0)), 2, "restored fact log continues sequence")
	restored.append_fact("third_fact", 123)
	_check_equal(
		restored.compact_keeping_recent(1), 2, "compact_keeping_recent removes 2 old facts"
	)
	_check_equal(restored.size(), 1, "compacted fact log retains 1 recent fact")
	_check_equal(restored.next_sequence(), 4, "compacted fact log preserves next_sequence")
	var compacted_restored := FactLog.new()
	_check(
		compacted_restored.restore_state(restored.snapshot_state()),
		"compacted fact log snapshot restores cleanly"
	)

	var bad_snapshot: Dictionary = snapshot.duplicate(true)
	var bad_facts: Array = bad_snapshot["facts"]
	var bad_fact: Dictionary = bad_facts[0]
	bad_fact["subject_id"] = "not a stable id"
	bad_facts[0] = bad_fact
	bad_snapshot["facts"] = bad_facts
	_check(
		not FactLog.new().restore_state(bad_snapshot), "fact snapshot with invalid subject rejected"
	)


func _test_state_hash() -> void:
	var first := {"b": [3, 2, 1], "a": {"value": 7}}
	var second := {"a": {"value": 7}, "b": [3, 2, 1]}
	var changed := {"a": {"value": 8}, "b": [3, 2, 1]}
	_check_equal(
		StateHash.sha256_hex(first),
		StateHash.sha256_hex(second),
		"dictionary order does not change hash"
	)
	_check(
		StateHash.sha256_hex(first) != StateHash.sha256_hex(changed), "changed state changes hash"
	)
	_check_equal(StateHash.sha256_hex(first).length(), 64, "SHA-256 hex length")
	_check_equal(
		StateHash.sha256_hex(-0.0), StateHash.sha256_hex(0.0), "negative zero hashes as zero"
	)
	_check(
		StateHash.sha256_hex({1: "same"}) != StateHash.sha256_hex({"1": "same"}),
		"integer and string dictionary keys hash distinctly"
	)
	var cyclic_state: Dictionary = {}
	cyclic_state["self"] = cyclic_state
	_check_equal(
		StateHash.sha256_hex(cyclic_state).length(), 64, "cyclic state hash is depth-guarded"
	)


func _test_definition_registry() -> void:
	var registry := DefinitionRegistry.new()
	var report := registry.load_package("res://data/core/manifest.json")
	_check(
		bool(report.get("ok", false)),
		"core definition package loads: %s" % str(report.get("errors", []))
	)
	_check_equal(int(report.get("definition_count", -1)), 20, "core package definition count")
	_check_equal(registry.package_id(), "core", "registry package ID")
	_check_equal(registry.manifest_hash().length(), 64, "registry manifest hash length")
	_check_equal(
		registry.ids_of_kind("species"),
		[
			"core:species/heruna",
			"core:species/karune",
			"core:species/kevalu",
			"core:species/murela",
			"core:species/navelu",
			"core:species/orive",
			"core:species/selave",
			"core:species/talune",
			"core:species/tivane",
			"core:species/torava",
		],
		"registry holds all 10 canonical Sevara species IDs"
	)

	var navelu := registry.get_definition("core:species/navelu")
	var properties: Dictionary = navelu["properties"]
	properties["diet"] = "mutated_outside"
	var navelu_again := registry.get_definition("core:species/navelu")
	var original_properties: Dictionary = navelu_again["properties"]
	_check_equal(
		String(original_properties["diet"]), "herbivore", "registry returns defensive copies"
	)

	var bad_manifest := {
		"format": DefinitionRegistry.PACKAGE_FORMAT,
		"schema_version": 1,
		"package_id": "test",
		"version": "1.0.0",
		"definition_files": ["definitions/bad.json"],
	}
	var bad_document := {
		"format": DefinitionRegistry.DEFINITIONS_FORMAT,
		"schema_version": 1,
		"definitions":
		[
			{
				"id": "test:species/example",
				"kind": "species",
				"name_key": "species.example.name",
				"references": ["test:species/missing"],
			},
			{
				"id": "test:species/example",
				"kind": "species",
				"name_key": "species.example.name",
			},
		],
	}
	var bad_registry := DefinitionRegistry.new()
	var bad_report := bad_registry.load_package_documents(
		bad_manifest, {"definitions/bad.json": bad_document}
	)
	_check(not bool(bad_report.get("ok", true)), "duplicate/unknown-reference package rejected")
	_check_equal(bad_registry.definition_count(), 0, "rejected package leaves registry empty")
	_check(
		not (bad_report.get("errors", []) as Array).is_empty(), "rejected package reports errors"
	)

	var bad_path_manifest: Dictionary = bad_manifest.duplicate(true)
	bad_path_manifest["definition_files"] = ["definitions//bad.json"]
	var bad_path_report := DefinitionRegistry.new().load_package_documents(
		bad_path_manifest, {"definitions//bad.json": bad_document}
	)
	_check(not bool(bad_path_report.get("ok", true)), "double-slash definition path rejected")

	var empty_document := {
		"format": DefinitionRegistry.DEFINITIONS_FORMAT,
		"schema_version": 1,
		"definitions": [],
	}
	var empty_report := DefinitionRegistry.new().load_package_documents(
		bad_manifest, {"definitions/bad.json": empty_document}
	)
	_check(not bool(empty_report.get("ok", true)), "empty definition package rejected")

	var bad_key_document := {
		"format": DefinitionRegistry.DEFINITIONS_FORMAT,
		"schema_version": 1,
		"definitions":
		[
			{
				"id": "test:species/example",
				"kind": "species",
				"name_key": "species..example.name",
			}
		],
	}
	var bad_key_report := DefinitionRegistry.new().load_package_documents(
		bad_manifest, {"definitions/bad.json": bad_key_document}
	)
	_check(not bool(bad_key_report.get("ok", true)), "empty localization key segment rejected")

	var missing_report := DefinitionRegistry.new().load_package("res://data/core/missing.json")
	_check(not bool(missing_report.get("ok", true)), "missing manifest is a report, not a crash")


func _test_sevara_eco_chain() -> void:
	var registry := DefinitionRegistry.new()
	var load_report := registry.load_package("res://data/core/manifest.json")
	_check(bool(load_report.get("ok", false)), "core package loads for P1-A ecology test")
	var pin := {
		"package_id": "core",
		"version": "0.1.0",
		"manifest_hash": registry.manifest_hash(),
	}

	var restored_world := WorldState.new()
	_check(restored_world.setup_campaign("p1a_restored", 2026, [pin]), "restored_world setup")
	_check(bool(SevaraEcoChain.ensure_basin_nodes(restored_world).get("ok", false)), "init nodes")
	var restore_dam := SevaraEcoChain.apply_intervention(
		restored_world, SevaraEcoChain.INTERVENTION_RESTORE_NAVELU_DAM
	)
	_check(bool(restore_dam.get("ok", false)), "restore_navelu_dam intervention succeeds")
	var quarantine := SevaraEcoChain.apply_intervention(
		restored_world, SevaraEcoChain.INTERVENTION_PLANT_KEVALU_QUARANTINE
	)
	_check(bool(quarantine.get("ok", false)), "plant_kevalu_quarantine intervention succeeds")

	var degraded_world := WorldState.new()
	_check(degraded_world.setup_campaign("p1a_degraded", 2026, [pin]), "degraded_world setup")
	_check(bool(SevaraEcoChain.ensure_basin_nodes(degraded_world).get("ok", false)), "init nodes")
	_check(
		bool(
			(
				SevaraEcoChain
				. apply_intervention(degraded_world, SevaraEcoChain.INTERVENTION_CLEAR_NAVELU_DAM)
				. get("ok", false)
			)
		),
		"clear_navelu_dam intervention succeeds"
	)
	_check(
		bool(
			(
				SevaraEcoChain
				. apply_intervention(
					degraded_world, SevaraEcoChain.INTERVENTION_RELEASE_KEVALU_WILD
				)
				. get("ok", false)
			)
		),
		"release_kevalu_wild intervention succeeds"
	)

	for _hour in range(12):
		restored_world.clock().advance_minutes(60)
		SevaraEcoChain.step_hour(restored_world)
		degraded_world.clock().advance_minutes(60)
		SevaraEcoChain.step_hour(degraded_world)

	var good_summary := SevaraEcoChain.basin_summary(restored_world)
	var bad_summary := SevaraEcoChain.basin_summary(degraded_world)
	var good_channel: Dictionary = good_summary[SevaraEcoChain.NODE_NIVAREL_CHANNEL]
	var bad_channel: Dictionary = bad_summary[SevaraEcoChain.NODE_NIVAREL_CHANNEL]
	var good_wetland: Dictionary = good_summary[SevaraEcoChain.NODE_MULANE_WETLAND]
	var bad_wetland: Dictionary = bad_summary[SevaraEcoChain.NODE_MULANE_WETLAND]

	_check(
		(
			float(good_wetland.get("murela_juveniles", 0.0))
			> float(bad_wetland.get("murela_juveniles", 1.0))
		),
		"restored Navelu dams + Selave yield healthier Murela juveniles than cleared dams"
	)
	_check(
		float(good_channel.get("tivane_sync", 0.0)) > float(bad_channel.get("tivane_sync", 1.0)),
		"uncontained wild Kevalu degrades Tivane pollinator sync compared to quarantine"
	)
	_check(
		(
			float(good_channel.get("kevalu_quarantine_knowledge", 0.0)) > 0.0
			and is_equal_approx(float(good_channel.get("kevalu_wild_biomass", 1.0)), 0.0)
		),
		"quarantined Kevalu builds botanical knowledge without wild channel contamination"
	)
	_check_equal(
		degraded_world.fact_log().facts_of_kind("eco_kevalu_spread").size(),
		1,
		"uncontained Kevalu logs eco_kevalu_spread causal fact"
	)


func _action_has_keycode(action_name: StringName, expected_keycode: Key) -> bool:
	for event in InputMap.action_get_events(action_name):
		var key_event := event as InputEventKey
		if key_event != null and key_event.keycode == expected_keycode:
			return true
	return false


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)


func _check_equal(actual: Variant, expected: Variant, message: String) -> void:
	_checks += 1
	if actual != expected:
		_failures.append("%s: expected %s, got %s" % [message, str(expected), str(actual)])
