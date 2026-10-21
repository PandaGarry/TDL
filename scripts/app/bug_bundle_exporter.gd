class_name BugBundleExporter
extends RefCounted
## Structured diagnostic session log and bug-bundle exporter for P0-G.
##
## Captures the authoritative session status, world snapshot, recent
## world facts, local session event log and optional GreyboxStage
## presentation/overlay state into a versioned, checksummed JSON bundle
## written atomically through `SaveStore`.

const FORMAT := "tdl.bug_bundle"
const SCHEMA_VERSION := 1
const DOCUMENT_NAME := "bug_bundle"
const DEFAULT_FACT_LIMIT := 32


static func build_bundle(
	session: GameSession, stage: GreyboxStage = null, note: String = "", created_at_unix: int = -1
) -> Dictionary:
	var resolved_created_at := (
		created_at_unix if created_at_unix >= 0 else int(Time.get_unix_time_from_system())
	)
	var session_status: Dictionary = session.session_status() if session != null else {}
	var world: WorldState = session.world_state() if session != null else null
	var world_ready := world != null and world.is_initialized()
	var world_snapshot: Dictionary = world.snapshot_state() if world_ready else {}
	var recent_facts: Array[Dictionary] = []
	if world_ready:
		recent_facts = world.fact_log().last_facts(DEFAULT_FACT_LIMIT)
	var session_events: Array[Dictionary] = []
	if session != null:
		session_events = session.take_local_events()
	var stage_status: Dictionary = stage.stage_status() if stage != null else {}

	var raw_payload := {
		"note": note.strip_edges(),
		"state_hash": session.domain_state_hash() if session != null else "",
		"session_status": session_status,
		"world_snapshot": world_snapshot,
		"recent_facts": recent_facts,
		"session_events": session_events,
		"stage_status": stage_status,
	}
	var canonical_payload: Dictionary = JsonValue.duplicate_canonical(raw_payload) as Dictionary
	var payload_sha256 := StateHash.sha256_hex(canonical_payload)
	return {
		"format": FORMAT,
		"schema_version": SCHEMA_VERSION,
		"created_at_unix": resolved_created_at,
		"payload_sha256": payload_sha256,
		"payload": canonical_payload,
	}


static func validate_bundle(bundle: Variant) -> Dictionary:
	if typeof(bundle) != TYPE_DICTIONARY or not JsonValue.is_safe(bundle):
		return {"ok": false, "error": "bug bundle must be a JSON-safe dictionary"}
	var doc: Dictionary = bundle
	if String(doc.get("format", "")) != FORMAT:
		return {"ok": false, "error": "bug bundle format must be '%s'" % FORMAT}
	var parsed_schema := GreyboxWorld.integral_value(doc.get("schema_version", -1))
	if (
		not bool(parsed_schema.get("ok", false))
		or int(parsed_schema.get("value", -1)) != SCHEMA_VERSION
	):
		return {"ok": false, "error": "unsupported bug bundle schema_version"}
	var parsed_created := GreyboxWorld.integral_value(doc.get("created_at_unix", -1))
	if not bool(parsed_created.get("ok", false)) or int(parsed_created.get("value", -1)) < 0:
		return {"ok": false, "error": "bug bundle created_at_unix must be non-negative"}
	var raw_payload: Variant = doc.get("payload", null)
	if typeof(raw_payload) != TYPE_DICTIONARY:
		return {"ok": false, "error": "bug bundle payload must be a dictionary"}
	var canonical_payload: Dictionary = JsonValue.duplicate_canonical(raw_payload) as Dictionary
	var expected_hash := StateHash.sha256_hex(canonical_payload)
	var stored_hash := String(doc.get("payload_sha256", ""))
	if stored_hash.is_empty() or stored_hash != expected_hash:
		return {"ok": false, "error": "bug bundle payload_sha256 mismatch"}
	return {
		"ok": true,
		"payload_sha256": expected_hash,
		"payload": canonical_payload,
		"error": "",
	}


static func export_to_store(
	store: SaveStore,
	slot_id: String,
	session: GameSession,
	stage: GreyboxStage = null,
	note: String = ""
) -> Dictionary:
	if store == null:
		return {"ok": false, "errors": ["SaveStore is null"]}
	var bundle := build_bundle(session, stage, note)
	var save_report: Dictionary = store.save_document(slot_id, DOCUMENT_NAME, bundle)
	if not bool(save_report.get("ok", false)):
		return {
			"ok": false,
			"errors": [String(save_report.get("error", "failed to save bug bundle"))],
		}
	return {
		"ok": true,
		"path": String(save_report.get("path", "")),
		"payload_sha256": String(bundle.get("payload_sha256", "")),
		"bundle": bundle,
		"errors": [],
	}


static func load_from_store(store: SaveStore, slot_id: String) -> Dictionary:
	if store == null:
		return {"ok": false, "errors": ["SaveStore is null"]}
	var load_report: Dictionary = store.load_document(
		slot_id, DOCUMENT_NAME, Callable(BugBundleExporter, "_is_valid_bundle_document")
	)
	if not bool(load_report.get("ok", false)):
		return {
			"ok": false,
			"errors": [String(load_report.get("error", "failed to load bug bundle"))],
		}
	var doc: Dictionary = load_report.get("document", {})
	var validation := validate_bundle(doc)
	return {
		"ok": bool(validation.get("ok", false)),
		"path": String(load_report.get("path", "")),
		"recovered": bool(load_report.get("recovered", false)),
		"payload_sha256": String(validation.get("payload_sha256", "")),
		"payload": validation.get("payload", {}),
		"bundle": doc,
		"errors":
		[] if bool(validation.get("ok", false)) else [String(validation.get("error", "invalid"))],
	}


static func _is_valid_bundle_document(doc: Dictionary) -> bool:
	return bool(validate_bundle(doc).get("ok", false))
