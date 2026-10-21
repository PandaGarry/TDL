class_name WorldRules
extends RefCounted
## Authoritative campaign and cooperative lobby rules owned by the host.
##
## Lives inside `WorldState`, is serialized into campaign saves, participates
## in `domain_state_hash()` and is replicated to all connected clients.
## Domain systems in P1-P3 (ecology, settlements, skills/combat) read their
## pacing and balance multipliers from this contract instead of hardcoding
## magic constants. Client-local presentation preferences (texture quality,
## foliage density, audio, locale) live in `SettingsManager`, never here.

const SCHEMA_VERSION := 1

const DEFAULT_LOBBY_NAME := "Sevara Campaign"
const MAX_LOBBY_NAME_LENGTH := 48
const MIN_MAX_PLAYERS := 1
const MAX_MAX_PLAYERS := 4
const DEFAULT_MAX_PLAYERS := 4

const DEFAULT_ABSENT_SETTLEMENT_PROTECTION := true
const DEFAULT_ALLOW_PLAYER_CONFLICT := true

const MIN_DISCONNECT_GRACE_SECONDS := 5.0
const MAX_DISCONNECT_GRACE_SECONDS := 600.0
const DEFAULT_DISCONNECT_GRACE_SECONDS := 90.0

const MIN_DAY_LENGTH_REAL_MINUTES := 1.0
const MAX_DAY_LENGTH_REAL_MINUTES := 120.0
const DEFAULT_DAY_LENGTH_REAL_MINUTES := 12.0

const MIN_TIME_SCALE := 0.1
const MAX_TIME_SCALE := 60.0
const DEFAULT_TIME_SCALE := 1.0

const MIN_SKILL_XP_MULTIPLIER := 0.1
const MAX_SKILL_XP_MULTIPLIER := 20.0
const DEFAULT_SKILL_XP_MULTIPLIER := 1.0

const MIN_RESOURCE_YIELD_MULTIPLIER := 0.1
const MAX_RESOURCE_YIELD_MULTIPLIER := 10.0
const DEFAULT_RESOURCE_YIELD_MULTIPLIER := 1.0

const MIN_ECOLOGY_RECOVERY_MULTIPLIER := 0.1
const MAX_ECOLOGY_RECOVERY_MULTIPLIER := 10.0
const DEFAULT_ECOLOGY_RECOVERY_MULTIPLIER := 1.0

const MIN_SURVIVAL_PRESSURE_MULTIPLIER := 0.1
const MAX_SURVIVAL_PRESSURE_MULTIPLIER := 5.0
const DEFAULT_SURVIVAL_PRESSURE_MULTIPLIER := 1.0

var _lobby_name: String = DEFAULT_LOBBY_NAME
var _max_players: int = DEFAULT_MAX_PLAYERS
var _absent_settlement_protection: bool = DEFAULT_ABSENT_SETTLEMENT_PROTECTION
var _disconnect_grace_seconds: float = DEFAULT_DISCONNECT_GRACE_SECONDS
var _allow_player_conflict: bool = DEFAULT_ALLOW_PLAYER_CONFLICT
var _day_length_real_minutes: float = DEFAULT_DAY_LENGTH_REAL_MINUTES
var _time_scale: float = DEFAULT_TIME_SCALE
var _skill_xp_multiplier: float = DEFAULT_SKILL_XP_MULTIPLIER
var _resource_yield_multiplier: float = DEFAULT_RESOURCE_YIELD_MULTIPLIER
var _ecology_recovery_multiplier: float = DEFAULT_ECOLOGY_RECOVERY_MULTIPLIER
var _survival_pressure_multiplier: float = DEFAULT_SURVIVAL_PRESSURE_MULTIPLIER


func reset_defaults() -> void:
	_lobby_name = DEFAULT_LOBBY_NAME
	_max_players = DEFAULT_MAX_PLAYERS
	_absent_settlement_protection = DEFAULT_ABSENT_SETTLEMENT_PROTECTION
	_disconnect_grace_seconds = DEFAULT_DISCONNECT_GRACE_SECONDS
	_allow_player_conflict = DEFAULT_ALLOW_PLAYER_CONFLICT
	_day_length_real_minutes = DEFAULT_DAY_LENGTH_REAL_MINUTES
	_time_scale = DEFAULT_TIME_SCALE
	_skill_xp_multiplier = DEFAULT_SKILL_XP_MULTIPLIER
	_resource_yield_multiplier = DEFAULT_RESOURCE_YIELD_MULTIPLIER
	_ecology_recovery_multiplier = DEFAULT_ECOLOGY_RECOVERY_MULTIPLIER
	_survival_pressure_multiplier = DEFAULT_SURVIVAL_PRESSURE_MULTIPLIER


func lobby_name() -> String:
	return _lobby_name


func max_players() -> int:
	return _max_players


func absent_settlement_protection() -> bool:
	return _absent_settlement_protection


func disconnect_grace_seconds() -> float:
	return _disconnect_grace_seconds


func allow_player_conflict() -> bool:
	return _allow_player_conflict


func day_length_real_minutes() -> float:
	return _day_length_real_minutes


func time_scale() -> float:
	return _time_scale


func skill_xp_multiplier() -> float:
	return _skill_xp_multiplier


func resource_yield_multiplier() -> float:
	return _resource_yield_multiplier


func ecology_recovery_multiplier() -> float:
	return _ecology_recovery_multiplier


func survival_pressure_multiplier() -> float:
	return _survival_pressure_multiplier


func effective_game_minutes_per_real_second() -> float:
	var real_seconds_per_day := _day_length_real_minutes * 60.0
	if real_seconds_per_day <= 0.0:
		return 2.0
	return (float(WorldClock.MINUTES_PER_DAY) / real_seconds_per_day) * _time_scale


func apply_patch(patch: Dictionary) -> Dictionary:
	if patch.is_empty():
		return {"ok": false, "errors": ["world rules patch must not be empty"], "changed_keys": []}
	if not JsonValue.is_safe(patch):
		return {"ok": false, "errors": ["world rules patch is not JSON-safe"], "changed_keys": []}

	var candidate := snapshot_state()
	var errors: Array[String] = []
	var changed_keys: Array[String] = []
	var allowed_keys := _patchable_keys()

	for raw_key in patch.keys():
		if typeof(raw_key) != TYPE_STRING:
			errors.append("world rules key must be a string")
			continue
		var key := String(raw_key)
		if not allowed_keys.has(key):
			errors.append("unknown world rule '%s'" % key)
			continue
		candidate[key] = patch[key]
		changed_keys.append(key)

	if not errors.is_empty():
		return {"ok": false, "errors": errors, "changed_keys": []}

	var validated := _validate_snapshot(candidate)
	if not bool(validated.get("ok", false)):
		return {
			"ok": false,
			"errors": [String(validated.get("error", "invalid world rules patch"))],
			"changed_keys": [],
		}

	changed_keys.sort()
	_commit_validated(validated.get("values", {}))
	return {
		"ok": true,
		"errors": [],
		"changed_keys": changed_keys,
		"rules": snapshot_state(),
	}


func snapshot_state() -> Dictionary:
	return (
		(
			JsonValue
			. duplicate_canonical(
				{
					"schema_version": SCHEMA_VERSION,
					"lobby_name": _lobby_name,
					"max_players": _max_players,
					"absent_settlement_protection": _absent_settlement_protection,
					"disconnect_grace_seconds": _disconnect_grace_seconds,
					"allow_player_conflict": _allow_player_conflict,
					"day_length_real_minutes": _day_length_real_minutes,
					"time_scale": _time_scale,
					"skill_xp_multiplier": _skill_xp_multiplier,
					"resource_yield_multiplier": _resource_yield_multiplier,
					"ecology_recovery_multiplier": _ecology_recovery_multiplier,
					"survival_pressure_multiplier": _survival_pressure_multiplier,
				}
			)
		)
		as Dictionary
	)


func restore_state(snapshot: Dictionary) -> bool:
	var validated := _validate_snapshot(snapshot)
	if not bool(validated.get("ok", false)):
		return false
	_commit_validated(validated.get("values", {}))
	return true


func _commit_validated(values: Dictionary) -> void:
	_lobby_name = String(values["lobby_name"])
	_max_players = int(values["max_players"])
	_absent_settlement_protection = bool(values["absent_settlement_protection"])
	_disconnect_grace_seconds = float(values["disconnect_grace_seconds"])
	_allow_player_conflict = bool(values["allow_player_conflict"])
	_day_length_real_minutes = float(values["day_length_real_minutes"])
	_time_scale = float(values["time_scale"])
	_skill_xp_multiplier = float(values["skill_xp_multiplier"])
	_resource_yield_multiplier = float(values["resource_yield_multiplier"])
	_ecology_recovery_multiplier = float(values["ecology_recovery_multiplier"])
	_survival_pressure_multiplier = float(values["survival_pressure_multiplier"])


static func _validate_snapshot(snapshot: Dictionary) -> Dictionary:
	if not JsonValue.is_safe(snapshot):
		return {"ok": false, "error": "world_rules snapshot is not JSON-safe"}
	var required_keys := _snapshot_keys()
	if not GreyboxWorld.has_only_keys(snapshot, required_keys):
		return {"ok": false, "error": "world_rules snapshot has missing or unknown keys"}

	var schema := GreyboxWorld.integral_value(snapshot.get("schema_version", -1))
	if not bool(schema.get("ok", false)) or int(schema.get("value", -1)) != SCHEMA_VERSION:
		return {"ok": false, "error": "unsupported world_rules schema_version"}

	var raw_lobby := snapshot.get("lobby_name", null)
	if typeof(raw_lobby) != TYPE_STRING:
		return {"ok": false, "error": "lobby_name must be a string"}
	var lobby := String(raw_lobby).strip_edges()
	if lobby.is_empty() or lobby.length() > MAX_LOBBY_NAME_LENGTH:
		return {"ok": false, "error": "lobby_name length must be 1..%d" % MAX_LOBBY_NAME_LENGTH}

	var parsed_max_players := GreyboxWorld.integral_value(snapshot.get("max_players", -1))
	var max_p := int(parsed_max_players.get("value", -1))
	if (
		not bool(parsed_max_players.get("ok", false))
		or max_p < MIN_MAX_PLAYERS
		or max_p > MAX_MAX_PLAYERS
	):
		return {
			"ok": false,
			"error": "max_players must be in %d..%d" % [MIN_MAX_PLAYERS, MAX_MAX_PLAYERS],
		}

	if typeof(snapshot.get("absent_settlement_protection", null)) != TYPE_BOOL:
		return {"ok": false, "error": "absent_settlement_protection must be a bool"}
	if typeof(snapshot.get("allow_player_conflict", null)) != TYPE_BOOL:
		return {"ok": false, "error": "allow_player_conflict must be a bool"}

	var float_specs := [
		["disconnect_grace_seconds", MIN_DISCONNECT_GRACE_SECONDS, MAX_DISCONNECT_GRACE_SECONDS],
		["day_length_real_minutes", MIN_DAY_LENGTH_REAL_MINUTES, MAX_DAY_LENGTH_REAL_MINUTES],
		["time_scale", MIN_TIME_SCALE, MAX_TIME_SCALE],
		["skill_xp_multiplier", MIN_SKILL_XP_MULTIPLIER, MAX_SKILL_XP_MULTIPLIER],
		["resource_yield_multiplier", MIN_RESOURCE_YIELD_MULTIPLIER, MAX_RESOURCE_YIELD_MULTIPLIER],
		[
			"ecology_recovery_multiplier",
			MIN_ECOLOGY_RECOVERY_MULTIPLIER,
			MAX_ECOLOGY_RECOVERY_MULTIPLIER
		],
		[
			"survival_pressure_multiplier",
			MIN_SURVIVAL_PRESSURE_MULTIPLIER,
			MAX_SURVIVAL_PRESSURE_MULTIPLIER
		],
	]
	var parsed_floats: Dictionary = {}
	for spec in float_specs:
		var field_name := String(spec[0])
		var min_val := float(spec[1])
		var max_val := float(spec[2])
		var number_check := _finite_number_in_range(
			snapshot.get(field_name, null), min_val, max_val
		)
		if not bool(number_check.get("ok", false)):
			return {
				"ok": false,
				"error": "%s must be in [%s, %s]" % [field_name, str(min_val), str(max_val)],
			}
		parsed_floats[field_name] = float(number_check.get("value", 0.0))

	return {
		"ok": true,
		"values":
		{
			"lobby_name": lobby,
			"max_players": max_p,
			"absent_settlement_protection": bool(snapshot["absent_settlement_protection"]),
			"allow_player_conflict": bool(snapshot["allow_player_conflict"]),
			"disconnect_grace_seconds": float(parsed_floats["disconnect_grace_seconds"]),
			"day_length_real_minutes": float(parsed_floats["day_length_real_minutes"]),
			"time_scale": float(parsed_floats["time_scale"]),
			"skill_xp_multiplier": float(parsed_floats["skill_xp_multiplier"]),
			"resource_yield_multiplier": float(parsed_floats["resource_yield_multiplier"]),
			"ecology_recovery_multiplier": float(parsed_floats["ecology_recovery_multiplier"]),
			"survival_pressure_multiplier": float(parsed_floats["survival_pressure_multiplier"]),
		},
	}


static func _finite_number_in_range(value: Variant, min_val: float, max_val: float) -> Dictionary:
	var t := typeof(value)
	if t != TYPE_INT and t != TYPE_FLOAT:
		return {"ok": false, "value": 0.0}
	var number := float(value)
	if not is_finite(number) or number < min_val or number > max_val:
		return {"ok": false, "value": 0.0}
	return {"ok": true, "value": number}


static func _patchable_keys() -> Array[String]:
	return [
		"lobby_name",
		"max_players",
		"absent_settlement_protection",
		"disconnect_grace_seconds",
		"allow_player_conflict",
		"day_length_real_minutes",
		"time_scale",
		"skill_xp_multiplier",
		"resource_yield_multiplier",
		"ecology_recovery_multiplier",
		"survival_pressure_multiplier",
	]


static func _snapshot_keys() -> Array[String]:
	var keys := _patchable_keys()
	keys.append("schema_version")
	return keys
