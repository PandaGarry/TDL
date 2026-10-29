class_name GreyboxDebugOverlay
extends PanelContainer
## Diagnostic overlay for the P0-F greybox presentation.
##
## Surfaces authoritative time/minute, session role and peers, active
## tile/ecocell/chunk coordinates, hydrated bodies, supply crate state,
## recent FactLog entries, last intent rejection and domain_state_hash().

const DEFAULT_MAX_RECENT_FACTS := 6

@export_range(1, 20, 1) var max_recent_facts: int = DEFAULT_MAX_RECENT_FACTS

var _last_snapshot: Dictionary = {}
var _report_label: Label


func _init() -> void:
	_configure_panel()


func _ready() -> void:
	if _report_label != null and _report_label.text.is_empty():
		_report_label.text = format_report(build_snapshot(null, null, max_recent_facts))


func refresh(session: GameSession, chunk_view: GreyboxChunkView) -> Dictionary:
	_last_snapshot = build_snapshot(session, chunk_view, max_recent_facts)
	if _report_label != null:
		_report_label.text = format_report(_last_snapshot)
	return last_snapshot()


func toggle_overlay() -> bool:
	visible = not visible
	return visible


func last_snapshot() -> Dictionary:
	return JsonValue.duplicate_safe(_last_snapshot) as Dictionary


func report_text() -> String:
	return _report_label.text if _report_label != null else ""


static func build_snapshot(
	session: GameSession,
	chunk_view: GreyboxChunkView,
	recent_fact_limit: int = DEFAULT_MAX_RECENT_FACTS
) -> Dictionary:
	var status: Dictionary = session.session_status() if session != null else {}
	var world: WorldState = session.world_state() if session != null else null
	var world_ready := world != null and world.is_initialized()
	var presentation: Dictionary = chunk_view.presentation_summary() if chunk_view != null else {}
	var local_tile := Vector2i(
		int(presentation.get("local_tile_x", -1)), int(presentation.get("local_tile_y", -1))
	)
	var local_ecocell := (
		GreyboxGridMetrics.ecocell_for_tile(local_tile) if local_tile.x >= 0 else Vector2i(-1, -1)
	)
	var local_chunk := (
		GreyboxGridMetrics.chunk_for_tile(local_tile) if local_tile.x >= 0 else Vector2i(-1, -1)
	)
	var recent_facts: Array[Dictionary] = []
	if world_ready:
		recent_facts = world.fact_log().last_facts(maxi(recent_fact_limit, 1))

	return {
		"running": bool(status.get("running", false)),
		"role": String(status.get("role", "inactive")),
		"network_host": bool(status.get("network_host", false)),
		"client_ready": bool(status.get("client_ready", false)),
		"campaign_id": String(status.get("campaign_id", "")),
		"campaign_slot_id": String(status.get("campaign_slot_id", "")),
		"game_minute": int(status.get("game_minute", 0)),
		"formatted_time": _format_clock(world.clock()) if world_ready else "uninitialized",
		"local_participant_id": String(status.get("local_participant_id", "")),
		"local_body_entity_id": int(status.get("local_body_entity_id", -1)),
		"local_tile": {"x": local_tile.x, "y": local_tile.y},
		"local_ecocell": {"x": local_ecocell.x, "y": local_ecocell.y},
		"local_chunk": {"x": local_chunk.x, "y": local_chunk.y},
		"world_rules": JsonValue.duplicate_safe(status.get("world_rules", {})),
		"graphics_profile": SettingsManager.graphics_profile(),
		"p1_basin": SevaraEcoChain.basin_summary(world) if world_ready else {},
		"p1_npcs_count": SevaraP1Npcs.find_npcs(world).size() if world_ready else 0,
		"p1_chronicle_count":
		FieldJournalAndChronicle.build_settlement_chronicle(world).size() if world_ready else 0,
		"transport_peer_id": int(status.get("transport_peer_id", 0)),
		"transport_peers": JsonValue.duplicate_safe(status.get("transport_peers", [])),
		"participants": JsonValue.duplicate_safe(status.get("participants", [])),
		"entity_count": int(status.get("entity_count", 0)),
		"hydrated_entity_ids":
		JsonValue.duplicate_safe(presentation.get("hydrated_entity_ids", [])),
		"actors": JsonValue.duplicate_safe(presentation.get("actors", [])),
		"supply_crate": JsonValue.duplicate_safe(presentation.get("supply_crate", {})),
		"fact_count": world.fact_log().size() if world_ready else 0,
		"recent_facts": JsonValue.duplicate_safe(recent_facts),
		"last_rejection": JsonValue.duplicate_safe(status.get("last_rejection", {})),
		"state_hash": String(status.get("state_hash", "")),
	}


static func format_report(snapshot: Dictionary) -> String:
	var lines: Array[String] = []
	lines.append("[TDL P0-F Debug Overlay]")
	(
		lines
		. append(
			(
				"Session: role=%s running=%s net_host=%s client_ready=%s campaign=%s"
				% [
					String(snapshot.get("role", "inactive")),
					str(bool(snapshot.get("running", false))),
					str(bool(snapshot.get("network_host", false))),
					str(bool(snapshot.get("client_ready", false))),
					String(snapshot.get("campaign_id", "-")),
				]
			)
		)
	)
	(
		lines
		. append(
			(
				"Clock: %s | minute=%d"
				% [
					String(snapshot.get("formatted_time", "uninitialized")),
					int(snapshot.get("game_minute", 0)),
				]
			)
		)
	)
	var tile: Dictionary = snapshot.get("local_tile", {})
	var ecocell: Dictionary = snapshot.get("local_ecocell", {})
	var chunk: Dictionary = snapshot.get("local_chunk", {})
	(
		lines
		. append(
			(
				"Local: participant=%s body=%d tile=(%d,%d) ecocell=(%d,%d) chunk=(%d,%d)"
				% [
					String(snapshot.get("local_participant_id", "-")),
					int(snapshot.get("local_body_entity_id", -1)),
					int(tile.get("x", -1)),
					int(tile.get("y", -1)),
					int(ecocell.get("x", -1)),
					int(ecocell.get("y", -1)),
					int(chunk.get("x", -1)),
					int(chunk.get("y", -1)),
				]
			)
		)
	)
	var rules: Dictionary = snapshot.get("world_rules", {})
	if not rules.is_empty():
		(
			lines
			. append(
				(
					"Rules: lobby='%s' day=%.1fm scale=x%.1f xp=x%.1f max_players=%d"
					% [
						String(rules.get("lobby_name", "")),
						float(rules.get("day_length_real_minutes", 12.0)),
						float(rules.get("time_scale", 1.0)),
						float(rules.get("skill_xp_multiplier", 1.0)),
						int(rules.get("max_players", 4)),
					]
				)
			)
		)
	var p1_basin: Dictionary = snapshot.get("p1_basin", {})
	if not p1_basin.is_empty():
		var ch: Dictionary = p1_basin.get(SevaraEcoChain.NODE_NIVAREL_CHANNEL, {})
		var wt: Dictionary = p1_basin.get(SevaraEcoChain.NODE_MULANE_WETLAND, {})
		(
			lines
			. append(
				(
					"P1 Sevara: dams=%.2f selave=%.2f murela_juv=%.2f kevalu_wild=%.2f npcs=%d chronicle=%d"
					% [
						float(ch.get("navelu_dams_integrity", 0.0)),
						float(ch.get("selave_coverage", 0.0)),
						float(wt.get("murela_juveniles", 0.0)),
						float(ch.get("kevalu_wild_biomass", 0.0)),
						int(snapshot.get("p1_npcs_count", 0)),
						int(snapshot.get("p1_chronicle_count", 0)),
					]
				)
			)
		)
	(
		lines
		. append(
			(
				"Peers: local_peer=%d remote_peers=%s participants=%s"
				% [
					int(snapshot.get("transport_peer_id", 0)),
					str(snapshot.get("transport_peers", [])),
					_format_participants(snapshot.get("participants", [])),
				]
			)
		)
	)
	lines.append("Bodies: %s" % _format_actors(snapshot.get("actors", [])))
	lines.append("Crate: %s" % _format_crate(snapshot.get("supply_crate", {})))
	(
		lines
		. append(
			(
				"Facts (%d total): %s"
				% [
					int(snapshot.get("fact_count", 0)),
					_format_facts(snapshot.get("recent_facts", [])),
				]
			)
		)
	)
	var rejection: Dictionary = snapshot.get("last_rejection", {})
	if not rejection.is_empty():
		(
			lines
			. append(
				(
					"Last Rejection: reason=%s intent=%s seq=%d"
					% [
						String(rejection.get("reason", "")),
						String(rejection.get("intent_type", "")),
						int(rejection.get("client_sequence", 0)),
					]
				)
			)
		)
	var state_hash := String(snapshot.get("state_hash", ""))
	var short_hash := state_hash.substr(0, 16) if state_hash.length() >= 16 else state_hash
	lines.append("State Hash: %s (%s)" % [short_hash, state_hash])
	return "\n".join(lines)


func _configure_panel() -> void:
	name = "GreyboxDebugOverlay"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.09, 0.08, 0.86)
	style.border_color = Color(0.62, 0.54, 0.36, 0.80)
	style.set_border_width_all(1)
	style.border_width_bottom = 2
	style.set_corner_radius_all(8)
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.40)
	style.shadow_size = 7
	style.shadow_offset = Vector2(0.0, 3.0)
	style.content_margin_left = 12.0
	style.content_margin_top = 9.0
	style.content_margin_right = 12.0
	style.content_margin_bottom = 9.0
	add_theme_stylebox_override("panel", style)

	_report_label = Label.new()
	_report_label.name = "ReportLabel"
	_report_label.add_theme_font_size_override("font_size", 13)
	_report_label.add_theme_color_override("font_color", Color(0.90, 0.95, 0.88, 1.0))
	_report_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.70))
	_report_label.add_theme_constant_override("shadow_offset_x", 1)
	_report_label.add_theme_constant_override("shadow_offset_y", 1)
	add_child(_report_label)


static func _format_clock(clock: WorldClock) -> String:
	if clock == null:
		return "uninitialized"
	return (
		"Y%d S%d D%d %02d:%02d"
		% [
			clock.year_number(),
			clock.season_index() + 1,
			clock.day_of_season(),
			clock.hour_of_day(),
			clock.minute_of_hour(),
		]
	)


static func _format_participants(raw_participants: Variant) -> String:
	if typeof(raw_participants) != TYPE_ARRAY:
		return "[]"
	var entries: Array = raw_participants
	var parts: Array[String] = []
	for raw_item in entries:
		if typeof(raw_item) != TYPE_DICTIONARY:
			continue
		var item: Dictionary = raw_item
		(
			parts
			. append(
				(
					"%s#%d(%s)"
					% [
						String(item.get("participant_id", "?")),
						int(item.get("body_entity_id", -1)),
						"on" if bool(item.get("connected", false)) else "off",
					]
				)
			)
		)
	return "[" + ", ".join(parts) + "]"


static func _format_actors(raw_actors: Variant) -> String:
	if typeof(raw_actors) != TYPE_ARRAY:
		return "none"
	var actors: Array = raw_actors
	if actors.is_empty():
		return "none"
	var parts: Array[String] = []
	for raw_actor in actors:
		if typeof(raw_actor) != TYPE_DICTIONARY:
			continue
		var actor: Dictionary = raw_actor
		(
			parts
			. append(
				(
					"%s(id=%d tile=%d,%d items=%d)"
					% [
						String(actor.get("participant_id", "?")),
						int(actor.get("entity_id", -1)),
						int(actor.get("tile_x", -1)),
						int(actor.get("tile_y", -1)),
						int(actor.get("total_inventory_items", 0)),
					]
				)
			)
		)
	return "; ".join(parts)


static func _format_crate(crate: Dictionary) -> String:
	if crate.is_empty():
		return "none"
	return (
		"id=%d tile=(%d,%d) %s=%d adj=%s"
		% [
			int(crate.get("entity_id", -1)),
			int(crate.get("tile_x", -1)),
			int(crate.get("tile_y", -1)),
			String(crate.get("item_definition_id", "")),
			int(crate.get("remaining_count", 0)),
			str(bool(crate.get("adjacent_to_local_body", false))),
		]
	)


static func _format_facts(raw_facts: Variant) -> String:
	if typeof(raw_facts) != TYPE_ARRAY:
		return "none"
	var facts: Array = raw_facts
	if facts.is_empty():
		return "none"
	var parts: Array[String] = []
	for raw_fact in facts:
		if typeof(raw_fact) != TYPE_DICTIONARY:
			continue
		var fact: Dictionary = raw_fact
		(
			parts
			. append(
				(
					"#%d@m%d:%s"
					% [
						int(fact.get("sequence", 0)),
						int(fact.get("game_minute", 0)),
						String(fact.get("kind", "?")),
					]
				)
			)
		)
	return ", ".join(parts)
