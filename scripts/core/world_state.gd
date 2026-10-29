class_name WorldState
extends RefCounted
## Mutable, serializable truth of one campaign.
##
## WorldState intentionally knows nothing about Godot nodes, scenes,
## rendering, networking or files. GameSession and domain systems mutate
## this model on the authoritative host; presentation hydrates nodes from
## it, while WorldStateCodec/SaveStore own the on-disk representation.
##
## P0-D keeps the model deliberately small: campaign identity, content
## package pins, clock/RNG/facts, a runtime entity allocator and generic,
## explicitly JSON-safe entity component dictionaries. Domain modules will
## add their own validated substates instead of turning this class into a
## dumping ground for every future system.

const SCHEMA_VERSION := 1

var _campaign_id: String = ""
var _genesis_seed: int = 0
var _content_packages: Array[Dictionary] = []
var _world_rules := WorldRules.new()
var _clock := WorldClock.new()
var _rng := RngStreams.new()
var _fact_log := FactLog.new()
var _next_entity_id: int = 1
var _entities: Dictionary = {}


func _init() -> void:
	_rng.setup(0)


## Initializes a fresh campaign. Invalid input leaves the current state
## untouched instead of partially resetting it.
func setup_campaign(campaign_id: String, genesis_seed: int, content_packages: Array) -> bool:
	if not StableId.is_valid_segment(campaign_id):
		push_warning("WorldState.setup_campaign: invalid campaign_id '%s'" % campaign_id)
		return false

	var package_result := _validated_content_packages(content_packages)
	if not bool(package_result["ok"]):
		push_warning("WorldState.setup_campaign: invalid content packages")
		return false
	var validated_packages := _copy_package_array(package_result["value"])
	if validated_packages.is_empty():
		# A fresh campaign must pin the content it was created against.
		# Restored legacy payloads may still have an empty pin list; the
		# session layer decides how to reconcile those in P0-E.
		push_warning("WorldState.setup_campaign: at least one content package is required")
		return false

	_campaign_id = campaign_id
	_genesis_seed = genesis_seed
	_content_packages = validated_packages
	_world_rules.reset_defaults()
	_clock.setup(0)
	_rng.setup(genesis_seed)
	_fact_log.clear()
	_next_entity_id = 1
	_entities.clear()
	return true


func is_initialized() -> bool:
	return not _campaign_id.is_empty()


func campaign_id() -> String:
	return _campaign_id


func genesis_seed() -> int:
	return _genesis_seed


func content_packages() -> Array[Dictionary]:
	return _copy_package_array(_content_packages)


func world_rules() -> WorldRules:
	return _world_rules


func clock() -> WorldClock:
	return _clock


func rng_streams() -> RngStreams:
	return _rng


func fact_log() -> FactLog:
	return _fact_log


func peek_next_entity_id() -> int:
	return _next_entity_id


## Allocates a runtime entity. Definition existence is checked by the
## future GameSession against DefinitionRegistry; WorldState only enforces
## stable IDs and JSON-safe component dictionaries at this boundary.
func create_entity(definition_id: String, components: Dictionary = {}) -> int:
	if not is_initialized():
		push_warning("WorldState.create_entity: campaign is not initialized")
		return -1
	if not StableId.is_valid(definition_id):
		push_warning("WorldState.create_entity: invalid definition_id '%s'" % definition_id)
		return -1
	if _next_entity_id < 1 or _next_entity_id > JsonValue.MAX_SAFE_INTEGER:
		push_warning("WorldState.create_entity: runtime entity ID space exhausted")
		return -1

	var component_result := _validated_components(components)
	if not bool(component_result["ok"]):
		push_warning("WorldState.create_entity: invalid components")
		return -1

	var entity_id := _next_entity_id
	_next_entity_id += 1
	_entities[entity_id] = {
		"definition_id": definition_id,
		"components": component_result["value"],
	}
	return entity_id


func has_entity(entity_id: int) -> bool:
	return _entities.has(entity_id)


func get_entity(entity_id: int) -> Dictionary:
	if not _entities.has(entity_id):
		return {}
	var stored: Dictionary = _entities[entity_id]
	return {
		"id": entity_id,
		"definition_id": String(stored["definition_id"]),
		"components": JsonValue.duplicate_safe(stored["components"]),
	}


func entity_ids() -> Array[int]:
	var result: Array[int] = []
	for raw_id in _entities.keys():
		result.append(int(raw_id))
	result.sort()
	return result


func remove_entity(entity_id: int) -> bool:
	if not _entities.has(entity_id):
		return false
	_entities.erase(entity_id)
	return true


func set_entity_component(entity_id: int, component_name: String, data: Dictionary) -> bool:
	if not _entities.has(entity_id):
		return false
	var component_result := _validated_components({component_name: data})
	if not bool(component_result["ok"]):
		push_warning("WorldState.set_entity_component: invalid component '%s'" % component_name)
		return false

	var validated: Dictionary = component_result["value"]
	var stored: Dictionary = _entities[entity_id]
	var components: Dictionary = stored["components"]
	components[component_name] = validated[component_name]
	stored["components"] = components
	_entities[entity_id] = stored
	return true


func get_entity_component(entity_id: int, component_name: String) -> Dictionary:
	if not _entities.has(entity_id):
		return {}
	var stored: Dictionary = _entities[entity_id]
	var components: Dictionary = stored["components"]
	if not components.has(component_name):
		return {}
	return JsonValue.duplicate_safe(components[component_name]) as Dictionary


func remove_entity_component(entity_id: int, component_name: String) -> bool:
	if not _entities.has(entity_id):
		return false
	var stored: Dictionary = _entities[entity_id]
	var components: Dictionary = stored["components"]
	if not components.has(component_name):
		return false
	components.erase(component_name)
	stored["components"] = components
	_entities[entity_id] = stored
	return true


## Returns the canonical v1 domain payload used by WorldStateCodec.
## Entity IDs and i64 seeds are strings at this boundary so JSON cannot
## silently round them through a double.
func snapshot_state() -> Dictionary:
	var entities: Dictionary = {}
	for entity_id in entity_ids():
		var stored: Dictionary = _entities[entity_id]
		entities[str(entity_id)] = {
			"definition_id": String(stored["definition_id"]),
			"components": JsonValue.duplicate_safe(stored["components"]),
		}

	return {
		"schema_version": SCHEMA_VERSION,
		"campaign_id": _campaign_id,
		"genesis_seed": str(_genesis_seed),
		"content_packages": JsonValue.duplicate_safe(_content_packages),
		"world_rules": _world_rules.snapshot_state(),
		"clock": _clock.snapshot_state(),
		"rng": _rng.snapshot_state(),
		"facts": _fact_log.snapshot_state(),
		"next_entity_id": str(_next_entity_id),
		"entities": entities,
	}


## Validates a complete v1 payload into temporary objects first. A failed
## restore therefore never replaces a currently valid world by accident.
func restore_state(snapshot: Dictionary) -> bool:
	var parsed := _parse_snapshot(snapshot)
	if not bool(parsed["ok"]):
		return false

	_campaign_id = String(parsed["campaign_id"])
	_genesis_seed = int(parsed["genesis_seed"])
	_content_packages = _copy_package_array(parsed["content_packages"])
	_world_rules = parsed["world_rules"] as WorldRules
	_clock = parsed["clock"] as WorldClock
	_rng = parsed["rng"] as RngStreams
	_fact_log = parsed["fact_log"] as FactLog
	_next_entity_id = int(parsed["next_entity_id"])
	_entities = parsed["entities"]
	return true


static func _parse_snapshot(snapshot: Dictionary) -> Dictionary:
	if not _snapshot_envelope_is_valid(snapshot):
		return {"ok": false}

	var identity := _parse_snapshot_identity(snapshot)
	var restored_rules := _restored_world_rules(
		snapshot.get("world_rules", null), snapshot.has("world_rules")
	)
	var restored_clock := _restored_clock(snapshot.get("clock", null))
	var restored_rng := _restored_rng(
		snapshot.get("rng", null), int(identity.get("genesis_seed", 0))
	)
	var restored_fact_log := _restored_fact_log(snapshot.get("facts", null), restored_clock)
	var entity_result := _validated_entities(snapshot.get("entities", null))
	var parsed_next_id := _parse_i64(snapshot.get("next_entity_id", null))
	var restored_next_entity_id := int(parsed_next_id["value"]) if bool(parsed_next_id["ok"]) else 0
	var highest_entity_id := int(entity_result.get("highest_entity_id", 0))

	var valid := (
		bool(identity["ok"])
		and restored_rules != null
		and restored_clock != null
		and restored_rng != null
		and restored_fact_log != null
		and bool(entity_result["ok"])
		and restored_next_entity_id > highest_entity_id
		and restored_next_entity_id <= JsonValue.MAX_SAFE_INTEGER + 1
	)
	if not valid:
		return {"ok": false}

	return {
		"ok": true,
		"campaign_id": String(identity["campaign_id"]),
		"genesis_seed": int(identity["genesis_seed"]),
		"content_packages": identity["content_packages"],
		"world_rules": restored_rules,
		"clock": restored_clock,
		"rng": restored_rng,
		"fact_log": restored_fact_log,
		"next_entity_id": restored_next_entity_id,
		"entities": entity_result["value"],
	}


static func _snapshot_envelope_is_valid(snapshot: Dictionary) -> bool:
	var base_keys := [
		"schema_version",
		"campaign_id",
		"genesis_seed",
		"content_packages",
		"clock",
		"rng",
		"facts",
		"next_entity_id",
		"entities",
	]
	var full_keys := base_keys.duplicate()
	full_keys.append("world_rules")
	return (
		JsonValue.is_safe(snapshot)
		and _integer_value(snapshot.get("schema_version", -1)) == SCHEMA_VERSION
		and (_has_only_keys(snapshot, full_keys) or _has_only_keys(snapshot, base_keys))
	)


static func _restored_world_rules(raw_snapshot: Variant, has_key: bool) -> WorldRules:
	var restored := WorldRules.new()
	if not has_key:
		return restored
	if typeof(raw_snapshot) != TYPE_DICTIONARY:
		return null
	return restored if restored.restore_state(raw_snapshot) else null


static func _parse_snapshot_identity(snapshot: Dictionary) -> Dictionary:
	var campaign_id := _string_value(snapshot.get("campaign_id", ""))
	var parsed_genesis_seed := _parse_i64(snapshot.get("genesis_seed", null))
	var package_result := _validated_content_packages(snapshot.get("content_packages", null))
	var valid := (
		StableId.is_valid_segment(campaign_id)
		and bool(parsed_genesis_seed["ok"])
		and bool(package_result["ok"])
	)
	return {
		"ok": valid,
		"campaign_id": campaign_id if valid else "",
		"genesis_seed": int(parsed_genesis_seed["value"]) if valid else 0,
		"content_packages": _copy_package_array(package_result["value"]),
	}


static func _restored_clock(raw_snapshot: Variant) -> WorldClock:
	if typeof(raw_snapshot) != TYPE_DICTIONARY:
		return null
	var restored := WorldClock.new()
	return restored if restored.restore_state(raw_snapshot) else null


static func _restored_rng(raw_snapshot: Variant, genesis_seed: int) -> RngStreams:
	if typeof(raw_snapshot) != TYPE_DICTIONARY:
		return null
	var restored := RngStreams.new()
	var valid := restored.restore_state(raw_snapshot) and restored.root_seed() == genesis_seed
	return restored if valid else null


static func _restored_fact_log(raw_snapshot: Variant, clock: WorldClock) -> FactLog:
	if typeof(raw_snapshot) != TYPE_DICTIONARY or clock == null:
		return null
	var restored := FactLog.new()
	if not restored.restore_state(raw_snapshot):
		return null
	for fact in restored.facts():
		if int(fact["game_minute"]) > clock.total_minutes():
			return null
	return restored


static func _validated_content_packages(raw_packages: Variant) -> Dictionary:
	if typeof(raw_packages) != TYPE_ARRAY:
		return {"ok": false, "value": []}

	var by_id: Dictionary = {}
	for raw_package in raw_packages:
		if typeof(raw_package) != TYPE_DICTIONARY or not JsonValue.is_safe(raw_package):
			return {"ok": false, "value": []}
		var package: Dictionary = raw_package
		if not _has_only_keys(package, ["package_id", "version", "manifest_hash"]):
			return {"ok": false, "value": []}

		var package_id := _string_value(package.get("package_id", ""))
		var version := _string_value(package.get("version", "")).strip_edges()
		var manifest_hash := _string_value(package.get("manifest_hash", ""))
		if (
			not StableId.is_valid_segment(package_id)
			or version.is_empty()
			or not _is_sha256_hex(manifest_hash)
			or by_id.has(package_id)
		):
			return {"ok": false, "value": []}

		by_id[package_id] = {
			"package_id": package_id,
			"version": version,
			"manifest_hash": manifest_hash,
		}

	var package_ids: Array[String] = []
	for raw_id in by_id.keys():
		package_ids.append(String(raw_id))
	package_ids.sort()

	var result: Array[Dictionary] = []
	for package_id in package_ids:
		result.append(by_id[package_id])
	return {"ok": true, "value": result}


static func _validated_components(raw_components: Variant) -> Dictionary:
	if typeof(raw_components) != TYPE_DICTIONARY or not JsonValue.is_safe(raw_components):
		return {"ok": false, "value": {}}

	var source: Dictionary = raw_components
	var result: Dictionary = {}
	for raw_name in source.keys():
		var component_name := String(raw_name)
		if not StableId.is_valid_segment(component_name):
			return {"ok": false, "value": {}}
		if typeof(source[raw_name]) != TYPE_DICTIONARY:
			return {"ok": false, "value": {}}
		result[component_name] = JsonValue.duplicate_canonical(source[raw_name])
	return {"ok": true, "value": result}


static func _validated_entities(raw_entities: Variant) -> Dictionary:
	if typeof(raw_entities) != TYPE_DICTIONARY:
		return {"ok": false, "value": {}, "highest_entity_id": 0}

	var source: Dictionary = raw_entities
	var result: Dictionary = {}
	var highest_entity_id := 0

	for raw_key in source.keys():
		if typeof(raw_key) != TYPE_STRING and typeof(raw_key) != TYPE_STRING_NAME:
			return {"ok": false, "value": {}, "highest_entity_id": 0}
		var key := String(raw_key)
		var parsed_id := _parse_i64(key)
		if not bool(parsed_id["ok"]):
			return {"ok": false, "value": {}, "highest_entity_id": 0}
		var entity_id := int(parsed_id["value"])
		if (
			str(entity_id) != key
			or entity_id < 1
			or entity_id > JsonValue.MAX_SAFE_INTEGER
			or result.has(entity_id)
		):
			return {"ok": false, "value": {}, "highest_entity_id": 0}

		var raw_entity: Variant = source[raw_key]
		if typeof(raw_entity) != TYPE_DICTIONARY or not JsonValue.is_safe(raw_entity):
			return {"ok": false, "value": {}, "highest_entity_id": 0}
		var entity: Dictionary = raw_entity
		if not _has_only_keys(entity, ["definition_id", "components"]):
			return {"ok": false, "value": {}, "highest_entity_id": 0}

		var definition_id := _string_value(entity.get("definition_id", ""))
		if not StableId.is_valid(definition_id):
			return {"ok": false, "value": {}, "highest_entity_id": 0}
		var component_result := _validated_components(entity.get("components", null))
		if not bool(component_result["ok"]):
			return {"ok": false, "value": {}, "highest_entity_id": 0}

		result[entity_id] = {
			"definition_id": definition_id,
			"components": component_result["value"],
		}
		highest_entity_id = maxi(highest_entity_id, entity_id)

	return {"ok": true, "value": result, "highest_entity_id": highest_entity_id}


static func _copy_package_array(raw_packages: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if typeof(raw_packages) != TYPE_ARRAY:
		return result
	for raw_package in raw_packages:
		if typeof(raw_package) == TYPE_DICTIONARY:
			result.append(JsonValue.duplicate_safe(raw_package) as Dictionary)
	return result


static func _string_value(value: Variant) -> String:
	# Schema strings must not be silently coerced from bool/number values:
	# `String(true)` would otherwise become the valid segment "true".
	if typeof(value) == TYPE_STRING or typeof(value) == TYPE_STRING_NAME:
		return String(value)
	return ""


static func _has_only_keys(dictionary: Dictionary, expected_keys: Array) -> bool:
	if dictionary.size() != expected_keys.size():
		return false
	for expected_key in expected_keys:
		if not dictionary.has(String(expected_key)):
			return false
	return true


static func _parse_i64(value: Variant) -> Dictionary:
	if typeof(value) == TYPE_INT:
		return {"ok": true, "value": int(value)}
	if (
		typeof(value) == TYPE_FLOAT
		and is_finite(float(value))
		and floor(float(value)) == float(value)
		and absf(float(value)) <= float(JsonValue.MAX_SAFE_INTEGER)
	):
		return {"ok": true, "value": int(value)}
	if typeof(value) == TYPE_STRING or typeof(value) == TYPE_STRING_NAME:
		var text := String(value)
		if text.is_valid_int():
			var parsed := text.to_int()
			if str(parsed) == text:
				return {"ok": true, "value": parsed}
	return {"ok": false, "value": 0}


static func _integer_value(value: Variant) -> int:
	var parsed := _parse_i64(value)
	return int(parsed["value"]) if bool(parsed["ok"]) else -1


static func _is_sha256_hex(value: String) -> bool:
	if value.length() != 64:
		return false
	for index in range(value.length()):
		var code := value.unicode_at(index)
		var is_digit := code >= 48 and code <= 57
		var is_lower_hex := code >= 97 and code <= 102
		if not (is_digit or is_lower_hex):
			return false
	return true
