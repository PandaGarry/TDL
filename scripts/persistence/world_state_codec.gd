class_name WorldStateCodec
extends RefCounted
## Versioned on-disk codec for WorldState.
##
## WorldState owns the canonical v1 domain payload. This codec owns the
## file envelope around it: format, schema, game version, creation time
## and a payload SHA-256. Legacy documents are migrated one schema step
## at a time into a v1 payload and only then handed to WorldState.

const FORMAT := "tdl.world_save"
const CURRENT_SCHEMA_VERSION := 1
const LEGACY_SCHEMA_VERSION := 0
const WORLD_DOCUMENT_NAME := "world"
const DEFAULT_GAME_VERSION := "dev"


static func encode(
	world: WorldState, game_version: String = "", created_at_unix: int = -1
) -> Dictionary:
	if world == null:
		return _encode_failure("Cannot encode a null WorldState")
	if not world.is_initialized():
		return _encode_failure("Cannot encode an uninitialized WorldState")

	var payload := world.snapshot_state()
	var validation_world := WorldState.new()
	if not validation_world.restore_state(payload):
		return _encode_failure("WorldState payload failed its own validation")

	var resolved_game_version := game_version.strip_edges()
	if resolved_game_version.is_empty():
		resolved_game_version = (
			String(ProjectSettings.get_setting("application/config/version", DEFAULT_GAME_VERSION))
			. strip_edges()
		)
	if resolved_game_version.is_empty():
		resolved_game_version = DEFAULT_GAME_VERSION

	var resolved_created_at := created_at_unix
	if resolved_created_at < 0:
		resolved_created_at = int(Time.get_unix_time_from_system())

	var document := {
		"format": FORMAT,
		"schema_version": CURRENT_SCHEMA_VERSION,
		"game_version": resolved_game_version,
		"created_at_unix": resolved_created_at,
		"payload_sha256": _payload_hash(payload),
		"payload": payload,
	}
	if not JsonValue.is_safe(document):
		return _encode_failure("Encoded world document is not JSON-safe")

	return {"ok": true, "document": document, "errors": []}


static func decode(document: Dictionary) -> Dictionary:
	if not JsonValue.is_safe(document):
		return _decode_failure("World document contains non-JSON-safe values")

	var schema_version := _integer_value(document.get("schema_version", -1))
	if schema_version == LEGACY_SCHEMA_VERSION:
		var migration := _migrate_v0_to_v1(document)
		if not bool(migration["ok"]):
			return _decode_failure(String(migration["error"]), LEGACY_SCHEMA_VERSION, false)
		return _world_from_payload(migration["payload"], LEGACY_SCHEMA_VERSION, true)

	if schema_version > CURRENT_SCHEMA_VERSION:
		return _decode_failure(
			(
				"World save schema %d is newer than supported %d"
				% [schema_version, CURRENT_SCHEMA_VERSION]
			),
			schema_version
		)
	if schema_version != CURRENT_SCHEMA_VERSION:
		return _decode_failure("Unsupported world save schema %d" % schema_version, schema_version)
	if String(document.get("format", "")) != FORMAT:
		return _decode_failure("World document format must be '%s'" % FORMAT, schema_version)
	if not _has_only_keys(
		document,
		[
			"format",
			"schema_version",
			"game_version",
			"created_at_unix",
			"payload_sha256",
			"payload",
		]
	):
		return _decode_failure(
			"World document envelope has missing or unknown fields", schema_version
		)

	var game_version: Variant = document["game_version"]
	if typeof(game_version) != TYPE_STRING or String(game_version).strip_edges().is_empty():
		return _decode_failure(
			"World document game_version must be a non-empty string", schema_version
		)
	if _integer_value(document.get("created_at_unix", -1)) < 0:
		return _decode_failure("World document created_at_unix must be >= 0", schema_version)

	var payload_value: Variant = document["payload"]
	if typeof(payload_value) != TYPE_DICTIONARY:
		return _decode_failure("World document payload must be an object", schema_version)
	var payload: Dictionary = payload_value

	var expected_hash := String(document.get("payload_sha256", ""))
	if not _is_sha256_hex(expected_hash):
		return _decode_failure("World document payload_sha256 is malformed", schema_version)
	if _payload_hash(payload) != expected_hash:
		return _decode_failure("World document payload checksum mismatch", schema_version)

	return _world_from_payload(payload, CURRENT_SCHEMA_VERSION, false)


static func save_to_store(
	world: WorldState,
	store: SaveStore,
	slot_id: String,
	game_version: String = "",
	created_at_unix: int = -1
) -> Dictionary:
	if store == null:
		return {"ok": false, "path": "", "bytes": 0, "errors": ["SaveStore is null"]}

	var encoded := encode(world, game_version, created_at_unix)
	if not bool(encoded["ok"]):
		return {"ok": false, "path": "", "bytes": 0, "errors": encoded["errors"]}

	var saved := store.save_document(slot_id, WORLD_DOCUMENT_NAME, encoded["document"])
	if not bool(saved["ok"]):
		return {
			"ok": false,
			"path": "",
			"bytes": 0,
			"errors": saved.get("errors", ["SaveStore failed"]),
		}
	return {
		"ok": true,
		"path": String(saved["path"]),
		"bytes": int(saved["bytes"]),
		"errors": [],
	}


## Tries current and backup candidates in order. Decode runs for every
## candidate, so a parseable but checksum-invalid current file falls back
## to a valid backup just like truncated JSON does.
static func load_from_store(store: SaveStore, slot_id: String) -> Dictionary:
	if store == null:
		return _load_failure("SaveStore is null")

	var candidate_paths := store.get_candidate_paths(slot_id, WORLD_DOCUMENT_NAME)
	if candidate_paths.is_empty():
		return _load_failure("No world save candidates in slot '%s'" % slot_id)

	var errors: Array[String] = []
	var current_path := store.get_document_path(slot_id, WORLD_DOCUMENT_NAME)
	for candidate_path in candidate_paths:
		var read_result := store.read_document_at_path(candidate_path)
		if not bool(read_result["ok"]):
			errors.append(String(read_result["errors"][0]))
			continue

		var decoded := decode(read_result["document"])
		if bool(decoded["ok"]):
			return {
				"ok": true,
				"world": decoded["world"],
				"path": candidate_path,
				"recovered": candidate_path != current_path,
				"source_schema_version": int(decoded["source_schema_version"]),
				"migrated": bool(decoded["migrated"]),
				"errors": errors.duplicate(),
			}
		for raw_error in decoded["errors"]:
			errors.append("%s: %s" % [candidate_path, String(raw_error)])

	return {
		"ok": false,
		"world": null,
		"path": "",
		"recovered": false,
		"source_schema_version": -1,
		"migrated": false,
		"errors": errors,
	}


static func _world_from_payload(
	payload: Dictionary, source_schema_version: int, migrated: bool
) -> Dictionary:
	var world := WorldState.new()
	if not world.restore_state(payload):
		return _decode_failure(
			"World payload failed WorldState validation", source_schema_version, migrated
		)
	return {
		"ok": true,
		"world": world,
		"errors": [],
		"source_schema_version": source_schema_version,
		"migrated": migrated,
	}


## Minimal pre-P0-D shape kept only as a migration fixture:
## `{campaign_id, genesis_seed, total_minutes, entities: [...]}`.
## v1 adds package pins, named RNG streams, facts and the entity map.
static func _migrate_v0_to_v1(document: Dictionary) -> Dictionary:
	var format_value := String(document.get("format", FORMAT))
	if format_value != FORMAT:
		return {"ok": false, "error": "Legacy world document has wrong format"}

	var campaign_id := String(document.get("campaign_id", ""))
	if not StableId.is_valid_segment(campaign_id):
		return {"ok": false, "error": "Legacy world document has invalid campaign_id"}

	var parsed_genesis_seed := _parse_i64(document.get("genesis_seed", null))
	if not bool(parsed_genesis_seed["ok"]):
		return {"ok": false, "error": "Legacy world document has invalid genesis_seed"}
	var genesis_seed := int(parsed_genesis_seed["value"])

	var total_minutes := _integer_value(document.get("total_minutes", -1))
	if total_minutes < 0:
		return {"ok": false, "error": "Legacy world document has invalid total_minutes"}

	var raw_entities: Variant = document.get("entities", null)
	if typeof(raw_entities) != TYPE_ARRAY:
		return {"ok": false, "error": "Legacy world document entities must be an array"}

	var entities: Dictionary = {}
	var highest_entity_id := 0
	for raw_entity in raw_entities:
		if typeof(raw_entity) != TYPE_DICTIONARY:
			return {"ok": false, "error": "Legacy world entity must be an object"}
		var entity: Dictionary = raw_entity
		if not _has_only_keys(entity, ["id", "definition_id", "components"]):
			return {"ok": false, "error": "Legacy world entity has missing or unknown fields"}
		var parsed_entity_id := _parse_i64(entity.get("id", null))
		if not bool(parsed_entity_id["ok"]):
			return {"ok": false, "error": "Legacy world entity has invalid id"}
		var entity_id := int(parsed_entity_id["value"])
		var entity_key := str(entity_id)
		if entity_id < 1 or entities.has(entity_key):
			return {"ok": false, "error": "Legacy world entity id is invalid or duplicated"}
		entities[entity_key] = {
			"definition_id": String(entity.get("definition_id", "")),
			"components": JsonValue.duplicate_safe(entity.get("components", {})),
		}
		highest_entity_id = maxi(highest_entity_id, entity_id)

	var payload := {
		"schema_version": CURRENT_SCHEMA_VERSION,
		"campaign_id": campaign_id,
		"genesis_seed": str(genesis_seed),
		"content_packages": [],
		"clock":
		{
			"schema_version": WorldClock.SCHEMA_VERSION,
			"total_minutes": total_minutes,
		},
		"rng":
		{
			"schema_version": RngStreams.SCHEMA_VERSION,
			"root_seed": str(genesis_seed),
			"streams": {},
		},
		"facts":
		{
			"schema_version": FactLog.SCHEMA_VERSION,
			"next_sequence": 1,
			"facts": [],
		},
		"next_entity_id": str(highest_entity_id + 1),
		"entities": entities,
	}
	return {"ok": true, "error": "", "payload": payload}


static func _payload_hash(payload: Dictionary) -> String:
	# JSON parses every number back as a double. Normalize integral values
	# through float first so the checksum is identical before writing and
	# after reading, without weakening StateHash for in-memory state.
	return StateHash.sha256_hex(_json_normalized(payload))


static func _json_normalized(value: Variant) -> Variant:
	match typeof(value):
		TYPE_INT:
			return float(value)
		TYPE_FLOAT:
			var number := float(value)
			return 0.0 if number == 0.0 else number
		TYPE_STRING_NAME:
			return String(value)
		TYPE_ARRAY:
			var result: Array = []
			for item in value:
				result.append(_json_normalized(item))
			return result
		TYPE_DICTIONARY:
			var result: Dictionary = {}
			var dictionary: Dictionary = value
			for key in dictionary.keys():
				result[String(key)] = _json_normalized(dictionary[key])
			return result
		_:
			return value


static func _encode_failure(message: String) -> Dictionary:
	return {"ok": false, "document": {}, "errors": [message]}


static func _decode_failure(
	message: String, source_schema_version: int = -1, migrated: bool = false
) -> Dictionary:
	return {
		"ok": false,
		"world": null,
		"errors": [message],
		"source_schema_version": source_schema_version,
		"migrated": migrated,
	}


static func _load_failure(message: String) -> Dictionary:
	return {
		"ok": false,
		"world": null,
		"path": "",
		"recovered": false,
		"source_schema_version": -1,
		"migrated": false,
		"errors": [message],
	}


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
