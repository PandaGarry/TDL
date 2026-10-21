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
	_test_world_clock()
	_test_rng_streams()
	_test_fact_log()
	_test_state_hash()
	_test_definition_registry()

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


func _test_stable_id() -> void:
	_check(StableId.is_valid("core:species/navelu"), "canonical stable ID is valid")
	_check(StableId.is_valid("future_mod:material/deep/iron_ingot"), "nested stable ID is valid")
	_check(not StableId.is_valid("Core:Species/Navelu"), "uppercase stable ID rejected")
	_check(not StableId.is_valid("core:navelu"), "stable ID without kind/name rejected")
	_check(not StableId.is_valid("core:species/navelu "), "stable ID with whitespace rejected")
	_check_equal(StableId.namespace_of("core:species/navelu"), "core", "stable ID namespace")
	_check_equal(StableId.kind_of("core:species/navelu"), "species", "stable ID kind")
	_check_equal(StableId.name_of("core:species/navelu"), "navelu", "stable ID name")
	_check_equal(
		StableId.make("core", "material", "torava_wood"),
		"core:material/torava_wood",
		"stable ID factory"
	)
	_check_equal(StableId.make("Core", "material", "wood"), "", "invalid stable ID factory result")


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
	var expected_next: Array[int] = []
	for index in range(3):
		expected_next.append(source.randi_range(&"society", 1, 1000))

	var restored := RngStreams.new()
	_check(restored.restore_state(snapshot), "RNG snapshot restores")
	var restored_next: Array[int] = []
	for index in range(3):
		restored_next.append(restored.randi_range(&"society", 1, 1000))
	_check_equal(restored_next, expected_next, "restored RNG stream continues identically")


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

	var snapshot := log.snapshot_state()
	var restored := FactLog.new()
	_check(restored.restore_state(snapshot), "fact log snapshot restores")
	var next_fact := restored.append_fact("world_restored", 122)
	_check_equal(int(next_fact.get("sequence", 0)), 2, "restored fact log continues sequence")


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


func _test_definition_registry() -> void:
	var registry := DefinitionRegistry.new()
	var report := registry.load_package("res://data/core/manifest.json")
	_check(
		bool(report.get("ok", false)),
		"core definition package loads: %s" % str(report.get("errors", []))
	)
	_check_equal(int(report.get("definition_count", -1)), 5, "core package definition count")
	_check_equal(registry.package_id(), "core", "registry package ID")
	_check_equal(registry.manifest_hash().length(), 64, "registry manifest hash length")
	_check_equal(
		registry.ids_of_kind("species"),
		["core:species/murela", "core:species/navelu", "core:species/selave"],
		"registry species IDs"
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

	var missing_report := DefinitionRegistry.new().load_package("res://data/core/missing.json")
	_check(not bool(missing_report.get("ok", true)), "missing manifest is a report, not a crash")


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)


func _check_equal(actual: Variant, expected: Variant, message: String) -> void:
	_checks += 1
	if actual != expected:
		_failures.append("%s: expected %s, got %s" % [message, str(expected), str(actual)])
