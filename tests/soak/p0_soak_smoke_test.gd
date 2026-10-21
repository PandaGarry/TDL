extends Node
## P0-G headless soak-smoke suite.
##
## Runs 3 distinct seeds across a full in-game season (30 days = 43,200
## minutes each) with hourly (60m), daily (1440m) and 10-day (14400m)
## scheduled systems, deterministic RNG stream draws, repeated body
## movement intents and periodic world saves. Verifies zero errors,
## stable entity counts, bounded execution time and bit-identical
## replay of a full season.

const TEST_SAVE_ROOT := "user://tests/p0_soak"
const SEASON_MINUTES := WorldClock.MINUTES_PER_SEASON
const STEP_MINUTES := 360

var _failures: Array[String] = []
var _checks: int = 0
var _hourly_calls: int = 0
var _daily_calls: int = 0
var _decade_calls: int = 0


func _ready() -> void:
	call_deferred("_run_soak")


func _run_soak() -> void:
	var seeds: Array[int] = [10101, 20202, 30303]
	var hashes_by_seed: Dictionary = {}

	for seed_value in seeds:
		var report := _run_single_season_soak(seed_value, "soak_seed_%d" % seed_value)
		_check(
			bool(report.get("ok", false)),
			"full-season soak completes cleanly for seed %d" % seed_value
		)
		_check_equal(
			int(report.get("total_minutes", -1)),
			SEASON_MINUTES,
			"seed %d reaches 43,200 minutes (1 full season)" % seed_value
		)
		_check_equal(
			int(report.get("season_index", -1)),
			2,
			"seed %d advances calendar into season 2" % seed_value
		)
		_check_equal(
			int(report.get("entity_count", -1)),
			2,
			"seed %d keeps stable entity count without leaks" % seed_value
		)
		_check_equal(
			int(report.get("hourly_calls", -1)),
			720,
			"seed %d executes 720 hourly system ticks" % seed_value
		)
		_check_equal(
			int(report.get("daily_calls", -1)),
			30,
			"seed %d executes 30 daily system ticks" % seed_value
		)
		_check_equal(
			int(report.get("decade_calls", -1)),
			3,
			"seed %d executes 3 ten-day system ticks" % seed_value
		)
		_check(
			int(report.get("elapsed_msec", 999999)) < 15000,
			"seed %d full-season soak finishes within 15s budget" % seed_value
		)
		hashes_by_seed[seed_value] = String(report.get("state_hash", ""))

	var replay_10101 := _run_single_season_soak(10101, "soak_replay_10101")
	_check_equal(
		String(replay_10101.get("state_hash", "replay")),
		String(hashes_by_seed.get(10101, "first")),
		"full-season soak replay for seed 10101 produces identical domain_state_hash"
	)
	_check(
		String(hashes_by_seed.get(10101, "")) != String(hashes_by_seed.get(20202, "")),
		"distinct genesis seeds produce distinct full-season state hashes"
	)

	if _failures.is_empty():
		print("P0_SOAK_SMOKE_OK checks=%d" % _checks)
		get_tree().quit(0)
	else:
		for failure in _failures:
			push_error("P0_SOAK_SMOKE_FAILED: %s" % failure)
		get_tree().quit(1)


func _run_single_season_soak(seed_value: int, slot_id: String) -> Dictionary:
	_hourly_calls = 0
	_daily_calls = 0
	_decade_calls = 0

	var started_msec := Time.get_ticks_msec()
	var session := GameSession.new()
	session.name = "SoakSession_%d" % seed_value
	session.save_root_dir = TEST_SAVE_ROOT
	session.save_backup_count = 2
	add_child(session)

	var start: Dictionary = session.start_new_offline(slot_id, seed_value, "host", "Host")
	if not bool(start.get("ok", false)):
		session.free()
		return {"ok": false}

	session.register_system("soak_hourly", 60, Callable(self, "_on_hourly_tick"), 10)
	session.register_system("soak_daily", 1440, Callable(self, "_on_daily_tick"), 20)
	session.register_system("soak_decade", 14400, Callable(self, "_on_decade_tick"), 30)

	var world := session.world_state()
	var body_id := GreyboxWorld.find_body(world, "host")
	var patrol: Array[Vector2i] = [
		Vector2i(2, 3),
		Vector2i(3, 3),
		Vector2i(2, 3),
		Vector2i(2, 2),
	]
	var steps := int(SEASON_MINUTES / STEP_MINUTES)
	var ok := true

	for step_index in range(steps):
		var target_tile: Vector2i = patrol[step_index % patrol.size()]
		var move_intent: Dictionary = (
			session
			. submit_intent(
				SessionProtocol.INTENT_MOVE_BODY,
				{
					"entity_id": body_id,
					"to_tile_x": target_tile.x,
					"to_tile_y": target_tile.y,
				}
			)
		)
		if not bool(move_intent.get("ok", false)):
			ok = false
			break
		var advance: Dictionary = session.advance_simulation_minutes(STEP_MINUTES)
		if not bool(advance.get("ok", false)):
			ok = false
			break
		if world.clock().total_minutes() % 14400 == 0:
			var save_report: Dictionary = session.save_world(slot_id)
			if not bool(save_report.get("ok", false)):
				ok = false
				break

	var elapsed_msec := Time.get_ticks_msec() - started_msec
	var result := {
		"ok": ok,
		"total_minutes": world.clock().total_minutes(),
		"season_index": world.clock().season_index(),
		"entity_count": world.entity_ids().size(),
		"hourly_calls": _hourly_calls,
		"daily_calls": _daily_calls,
		"decade_calls": _decade_calls,
		"elapsed_msec": elapsed_msec,
		"state_hash": session.domain_state_hash(),
	}
	session.stop_session()
	session.free()
	return result


func _on_hourly_tick(world: WorldState, context: Dictionary) -> bool:
	_hourly_calls += 1
	var draw := world.rng_streams().stream("weather").next_int_range(0, 1000)
	var crate_id := GreyboxWorld.find_supply_object(world)
	if crate_id > 0:
		var telemetry: Dictionary = world.get_entity_component(crate_id, "soak_telemetry")
		telemetry["hourly_minute"] = int(context.get("scheduled_minute", 0))
		telemetry["weather_draw"] = draw
		world.set_entity_component(crate_id, "soak_telemetry", telemetry)
	return true


func _on_daily_tick(world: WorldState, context: Dictionary) -> bool:
	_daily_calls += 1
	var draw := world.rng_streams().stream("ecology").next_int_range(0, 10000)
	var crate_id := GreyboxWorld.find_supply_object(world)
	if crate_id > 0:
		var telemetry: Dictionary = world.get_entity_component(crate_id, "soak_telemetry")
		telemetry["daily_minute"] = int(context.get("scheduled_minute", 0))
		telemetry["ecology_draw"] = draw
		world.set_entity_component(crate_id, "soak_telemetry", telemetry)
	return true


func _on_decade_tick(world: WorldState, context: Dictionary) -> bool:
	_decade_calls += 1
	var draw := world.rng_streams().stream("social").next_int_range(0, 100000)
	var crate_id := GreyboxWorld.find_supply_object(world)
	if crate_id > 0:
		var telemetry: Dictionary = world.get_entity_component(crate_id, "soak_telemetry")
		telemetry["decade_minute"] = int(context.get("scheduled_minute", 0))
		telemetry["social_draw"] = draw
		world.set_entity_component(crate_id, "soak_telemetry", telemetry)
	return true


func _check(condition: bool, label: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(label)


func _check_equal(actual: Variant, expected: Variant, label: String) -> void:
	_checks += 1
	if actual != expected:
		_failures.append("%s: expected %s, got %s" % [label, str(expected), str(actual)])
