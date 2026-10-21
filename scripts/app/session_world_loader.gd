class_name SessionWorldLoader
extends RefCounted
## Registry/world preparation for GameSession.
##
## This loader is the boundary where a generic WorldState becomes a
## runnable P0 session world. It loads the active DefinitionRegistry,
## pins fresh campaigns to that exact package, reconciles only the
## explicitly supported legacy case of missing pins, verifies that
## every persisted entity definition still exists, and ensures the
## greybox supply object before GameSession commits any runtime state.


static func load_registry(manifest_path: String) -> Dictionary:
	var loaded_registry := DefinitionRegistry.new()
	var report := loaded_registry.load_package(manifest_path)
	if not bool(report.get("ok", false)):
		return _failure(_string_array(report.get("errors", ["content package failed to load"])))
	var definition_errors := GreyboxWorld.validate_required_definitions(loaded_registry)
	if not definition_errors.is_empty():
		return _failure(definition_errors)
	return {
		"ok": true,
		"registry": loaded_registry,
		"package_pin": package_pin_for_registry(loaded_registry),
		"errors": [],
		"warnings": report.get("warnings", []),
	}


static func prepare_new_world(
	manifest_path: String,
	campaign_id: String,
	genesis_seed: int,
	width_tiles: int,
	height_tiles: int
) -> Dictionary:
	var registry_report := load_registry(manifest_path)
	if not bool(registry_report.get("ok", false)):
		return registry_report
	var active_registry := registry_report.get("registry") as DefinitionRegistry
	var world := WorldState.new()
	var packages: Array = [registry_report.get("package_pin", {})]
	if not world.setup_campaign(campaign_id, genesis_seed, packages):
		return _failure(["failed to initialize a new campaign world"])
	if (
		world
		. fact_log()
		. append_fact(
			"campaign_created", 0, {"campaign_id": campaign_id, "genesis_seed": str(genesis_seed)}
		)
		. is_empty()
	):
		return _failure(["failed to record campaign creation"])
	var object_report := GreyboxWorld.ensure_supply_object(
		world, active_registry, width_tiles, height_tiles
	)
	if not bool(object_report.get("ok", false)):
		return object_report
	return {"ok": true, "world": world, "registry": active_registry, "errors": []}


static func prepare_loaded_world(
	manifest_path: String,
	save_root_dir: String,
	save_backup_count: int,
	slot_id: String,
	width_tiles: int,
	height_tiles: int
) -> Dictionary:
	var registry_report := load_registry(manifest_path)
	if not bool(registry_report.get("ok", false)):
		return registry_report
	var active_registry := registry_report.get("registry") as DefinitionRegistry
	var store := SaveStore.new(save_root_dir, save_backup_count)
	var loaded := WorldStateCodec.load_from_store(store, slot_id)
	var loaded_world := loaded.get("world") as WorldState
	if not bool(loaded.get("ok", false)) or loaded_world == null:
		return _failure(_string_array(loaded.get("errors", ["world load failed"])))
	var reconciled := _reconcile_loaded_world(loaded_world, registry_report.get("package_pin", {}))
	if not bool(reconciled.get("ok", false)):
		return reconciled
	var world := reconciled.get("world") as WorldState
	var validation_errors := GreyboxWorld.validate_world_definitions(world, active_registry)
	if not validation_errors.is_empty():
		return _failure(validation_errors)
	var object_report := GreyboxWorld.ensure_supply_object(
		world, active_registry, width_tiles, height_tiles
	)
	if not bool(object_report.get("ok", false)):
		return object_report
	return {
		"ok": true,
		"world": world,
		"registry": active_registry,
		"loaded": loaded,
		"package_pins_reconciled": bool(reconciled.get("reconciled", false)),
		"warnings": reconciled.get("warnings", []),
		"errors": [],
	}


static func validate_session_world(
	world: WorldState, active_registry: DefinitionRegistry
) -> Array[String]:
	var errors := GreyboxWorld.validate_world_definitions(world, active_registry)
	var expected_pins: Array = [package_pin_for_registry(active_registry)]
	if not pins_equal(world.content_packages(), expected_pins):
		errors.append("world content package pins do not match the active registry")
	if GreyboxWorld.find_supply_object(world) < 1:
		errors.append("session world has no greybox supply object")
	return errors


static func package_pin_for_registry(active_registry: DefinitionRegistry) -> Dictionary:
	return {
		"package_id": active_registry.package_id(),
		"version": active_registry.package_version(),
		"manifest_hash": active_registry.manifest_hash(),
	}


static func pins_equal(left: Variant, right: Variant) -> bool:
	return (
		typeof(left) == TYPE_ARRAY
		and typeof(right) == TYPE_ARRAY
		and JsonValue.is_safe(left)
		and JsonValue.is_safe(right)
		and (
			StateHash.sha256_hex(JsonValue.duplicate_canonical(left))
			== StateHash.sha256_hex(JsonValue.duplicate_canonical(right))
		)
	)


static func _reconcile_loaded_world(
	loaded_world: WorldState, package_pin: Dictionary
) -> Dictionary:
	var expected_pins: Array = [package_pin]
	var actual_pins := loaded_world.content_packages()
	if pins_equal(actual_pins, expected_pins):
		return {"ok": true, "world": loaded_world, "reconciled": false, "warnings": []}
	if not actual_pins.is_empty():
		return _failure(
			[
				(
					"loaded world content package pins do not match the active "
					+ "single-package registry"
				)
			]
		)
	var snapshot := loaded_world.snapshot_state()
	snapshot["content_packages"] = expected_pins
	var reconciled_world := WorldState.new()
	if not reconciled_world.restore_state(snapshot):
		return _failure(["failed to adopt current package pins for a legacy world"])
	return {
		"ok": true,
		"world": reconciled_world,
		"reconciled": true,
		"warnings":
		["legacy world had no package pins; current registry pins were adopted explicitly"],
	}


static func _string_array(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if typeof(value) == TYPE_ARRAY:
		for raw_item in value:
			result.append(String(raw_item))
	return result


static func _failure(errors: Array[String]) -> Dictionary:
	return {"ok": false, "errors": errors.duplicate()}
