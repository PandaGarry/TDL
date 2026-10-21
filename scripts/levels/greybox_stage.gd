class_name GreyboxStage
extends Node2D
## Playable and testable P0-F greybox stage scene.
##
## Connects an authoritative `GameSession` (internal or externally bound)
## to `GreyboxChunkView`, `Camera2D`, semantic input handling and
## `GreyboxDebugOverlay`. Neither this stage nor its child views mutate
## `WorldState` directly.

const DEFAULT_CAMPAIGN_ID := "sevara_greybox"
const DEFAULT_SLOT_ID := "greybox_default"
const DEFAULT_GENESIS_SEED := 4072026

static var next_launch_load_slot_id: String = ""

@export var auto_start_offline: bool = true
@export var auto_enable_p1_slice: bool = false
@export var load_existing_slot_on_start: bool = false
@export var default_campaign_id: String = DEFAULT_CAMPAIGN_ID
@export var default_slot_id: String = DEFAULT_SLOT_ID
@export var save_root_dir: String = "user://saves/campaigns"
@export var default_genesis_seed: int = DEFAULT_GENESIS_SEED
@export var default_participant_id: String = "host"
@export var default_display_name: String = "Host"
@export_range(16.0, 128.0, 1.0) var tile_size_px: float = GreyboxGridMetrics.DEFAULT_TILE_SIZE_PX

var _session: GameSession
var _owns_session: bool = false
var _chunk_view: GreyboxChunkView
var _camera: Camera2D
var _camera_zoom_index: int = 1
var _hud_layer: CanvasLayer
var _debug_overlay: GreyboxDebugOverlay
var _header_title_label: Label
var _controls_hint_label: Label
var _status_banner_label: Label
var _save_button: Button
var _step_time_button: Button
var _menu_button: Button


func _init() -> void:
	_build_stage_nodes()


func _ready() -> void:
	UiLocaleCatalog.ensure_registered()
	_chunk_view.tile_size_px = tile_size_px
	_apply_localized_labels()
	if _session == null and auto_start_offline:
		var slot_to_load := next_launch_load_slot_id.strip_edges()
		next_launch_load_slot_id = ""
		if not slot_to_load.is_empty():
			load_offline_campaign(slot_to_load, default_participant_id, default_display_name)
		elif load_existing_slot_on_start:
			load_offline_campaign(default_slot_id, default_participant_id, default_display_name)
		else:
			start_offline_campaign(
				default_campaign_id,
				default_genesis_seed,
				default_participant_id,
				default_display_name
			)
	else:
		refresh_presentation()


func _exit_tree() -> void:
	_unbind_session_signals(_session)


func _unhandled_input(event: InputEvent) -> void:
	var report := handle_input_event(event, true)
	if bool(report.get("handled", false)) and is_inside_tree() and get_viewport() != null:
		get_viewport().set_input_as_handled()


func bind_session(external_session: GameSession) -> Dictionary:
	if _session != external_session:
		_unbind_session_signals(_session)
		if _owns_session and _session != null and is_instance_valid(_session):
			_session.stop_session()
			_session.free()
		_session = external_session
		_owns_session = false
		_bind_session_signals(_session)
	return refresh_presentation()


func start_offline_campaign(
	campaign_id: String = default_campaign_id,
	genesis_seed: int = default_genesis_seed,
	participant_id: String = default_participant_id,
	display_name: String = default_display_name
) -> Dictionary:
	var active_session := _ensure_owned_session()
	if bool(active_session.session_status().get("running", false)):
		active_session.stop_session()
	var report: Dictionary = active_session.start_new_offline(
		campaign_id, genesis_seed, participant_id, display_name
	)
	if bool(report.get("ok", false)) and auto_enable_p1_slice:
		active_session.enable_sevara_p1_slice()
	refresh_presentation()
	return report


func load_offline_campaign(
	slot_id: String = default_slot_id,
	participant_id: String = default_participant_id,
	display_name: String = default_display_name
) -> Dictionary:
	var active_session := _ensure_owned_session()
	if bool(active_session.session_status().get("running", false)):
		active_session.stop_session()
	var report: Dictionary = active_session.load_and_start_offline(
		slot_id, participant_id, display_name
	)
	refresh_presentation()
	return report


func save_offline_campaign(slot_id: String = default_slot_id) -> Dictionary:
	if _session == null:
		return {"ok": false, "errors": ["no game session is bound to the stage"]}
	var report: Dictionary = _session.save_world(slot_id)
	refresh_presentation()
	return report


func enable_p1_slice() -> Dictionary:
	if _session == null:
		return {"ok": false, "errors": ["no game session is bound to the stage"]}
	var report: Dictionary = _session.enable_sevara_p1_slice()
	refresh_presentation()
	return report


func cycle_texture_quality_preset() -> String:
	var next_preset: String = SettingsManager.cycle_texture_quality()
	refresh_presentation()
	return next_preset


func cycle_camera_zoom() -> float:
	var presets: Array = SevaraVisualTheme.CAMERA_ZOOM_PRESETS
	_camera_zoom_index = (_camera_zoom_index + 1) % presets.size()
	var z := float(presets[_camera_zoom_index])
	if _camera != null:
		_camera.zoom = Vector2(z, z)
	return z


func apply_lobby_rules_patch(patch: Dictionary) -> Dictionary:
	if _session == null:
		return {"ok": false, "errors": ["no game session is bound to the stage"]}
	var report: Dictionary = _session.configure_world_rules(patch)
	refresh_presentation()
	return report


func refresh_presentation() -> Dictionary:
	_chunk_view.tile_size_px = tile_size_px
	_chunk_view.sync_from_session(_session)
	_sync_camera_to_focus()
	_debug_overlay.refresh(_session, _chunk_view)
	return stage_status()


func trigger_action(
	action_name: StringName, process_immediately_on_host: bool = true
) -> Dictionary:
	var report := GreyboxInputController.dispatch_action(
		_session, action_name, process_immediately_on_host
	)
	if bool(report.get("debug_toggle", false)):
		report["debug_visible"] = _debug_overlay.toggle_overlay()
	refresh_presentation()
	return report


func handle_input_event(event: InputEvent, process_immediately_on_host: bool = true) -> Dictionary:
	var report := GreyboxInputController.dispatch_event(
		_session, event, process_immediately_on_host
	)
	if bool(report.get("debug_toggle", false)):
		report["debug_visible"] = _debug_overlay.toggle_overlay()
	if bool(report.get("handled", false)):
		refresh_presentation()
	return report


func session() -> GameSession:
	return _session


func chunk_view() -> GreyboxChunkView:
	return _chunk_view


func camera() -> Camera2D:
	return _camera


func debug_overlay() -> GreyboxDebugOverlay:
	return _debug_overlay


func stage_status() -> Dictionary:
	var local_actor := _chunk_view.local_actor_view()
	return {
		"session_bound": _session != null,
		"owns_session": _owns_session,
		"camera_position": {"x": _camera.position.x, "y": _camera.position.y},
		"camera_zoom": _camera.zoom.x if _camera != null else 1.0,
		"local_actor_position":
		(
			{"x": local_actor.position.x, "y": local_actor.position.y}
			if local_actor != null
			else {"x": -1.0, "y": -1.0}
		),
		"debug_visible": _debug_overlay.visible,
		"presentation": _chunk_view.presentation_summary(),
		"debug_snapshot": _debug_overlay.last_snapshot(),
	}


func _build_stage_nodes() -> void:
	name = "GreyboxStage"
	_chunk_view = GreyboxChunkView.new()
	_chunk_view.name = "GreyboxChunkView"
	add_child(_chunk_view)

	_camera = Camera2D.new()
	_camera.name = "StageCamera2D"
	_camera.enabled = true
	_camera.position_smoothing_enabled = false
	add_child(_camera)

	_hud_layer = CanvasLayer.new()
	_hud_layer.name = "HudCanvasLayer"
	add_child(_hud_layer)
	_build_hud_controls()


func _build_hud_controls() -> void:
	var root := MarginContainer.new()
	root.name = "HudMargin"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_theme_constant_override("margin_left", 14)
	root.add_theme_constant_override("margin_top", 12)
	root.add_theme_constant_override("margin_right", 14)
	root.add_theme_constant_override("margin_bottom", 12)
	_hud_layer.add_child(root)

	var vbox := VBoxContainer.new()
	vbox.name = "HudColumn"
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_theme_constant_override("separation", 8)
	root.add_child(vbox)

	var top_bar := HBoxContainer.new()
	top_bar.name = "TopBar"
	top_bar.add_theme_constant_override("separation", 12)
	vbox.add_child(top_bar)

	_header_title_label = Label.new()
	_header_title_label.add_theme_font_size_override("font_size", 16)
	_header_title_label.add_theme_color_override("font_color", Color(0.93, 0.8, 0.42, 1.0))
	top_bar.add_child(_header_title_label)

	_controls_hint_label = Label.new()
	_controls_hint_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_controls_hint_label.add_theme_font_size_override("font_size", 13)
	_controls_hint_label.add_theme_color_override("font_color", Color(0.84, 0.89, 0.86, 1.0))
	top_bar.add_child(_controls_hint_label)

	_step_time_button = Button.new()
	_step_time_button.pressed.connect(_on_step_time_pressed)
	top_bar.add_child(_step_time_button)

	_save_button = Button.new()
	_save_button.pressed.connect(_on_save_pressed)
	top_bar.add_child(_save_button)

	_menu_button = Button.new()
	_menu_button.pressed.connect(_on_menu_pressed)
	top_bar.add_child(_menu_button)

	_status_banner_label = Label.new()
	_status_banner_label.add_theme_font_size_override("font_size", 13)
	_status_banner_label.add_theme_color_override("font_color", Color(0.76, 0.88, 0.78, 1.0))
	vbox.add_child(_status_banner_label)

	_debug_overlay = GreyboxDebugOverlay.new()
	_debug_overlay.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	vbox.add_child(_debug_overlay)


func _apply_localized_labels() -> void:
	if _header_title_label != null:
		_header_title_label.text = tr("ui.greybox.header_title")
	if _controls_hint_label != null:
		_controls_hint_label.text = tr("ui.greybox.controls_hint")
	if _save_button != null:
		_save_button.text = tr("ui.greybox.save_button")
	if _step_time_button != null:
		_step_time_button.text = tr("ui.greybox.step_time_button")
	if _menu_button != null:
		_menu_button.text = tr("ui.greybox.menu_button")


func _ensure_owned_session() -> GameSession:
	if _session != null and _owns_session and is_instance_valid(_session):
		_session.save_root_dir = save_root_dir
		return _session
	_unbind_session_signals(_session)
	var created := GameSession.new()
	created.name = "OwnedGameSession"
	created.save_root_dir = save_root_dir
	add_child(created)
	_session = created
	_owns_session = true
	_bind_session_signals(_session)
	return _session


func _bind_session_signals(target: GameSession) -> void:
	if target == null:
		return
	if not target.session_started.is_connected(_on_session_started):
		target.session_started.connect(_on_session_started)
	if not target.session_stopped.is_connected(_on_session_stopped):
		target.session_stopped.connect(_on_session_stopped)
	if not target.participant_joined.is_connected(_on_participant_changed):
		target.participant_joined.connect(_on_participant_changed)
	if not target.participant_disconnected.is_connected(_on_participant_changed):
		target.participant_disconnected.connect(_on_participant_changed)
	if not target.intent_applied.is_connected(_on_intent_applied):
		target.intent_applied.connect(_on_intent_applied)
	if not target.intent_rejected.is_connected(_on_intent_rejected):
		target.intent_rejected.connect(_on_intent_rejected)
	if not target.snapshot_applied.is_connected(_on_snapshot_applied):
		target.snapshot_applied.connect(_on_snapshot_applied)


func _unbind_session_signals(target: GameSession) -> void:
	if target == null or not is_instance_valid(target):
		return
	if target.session_started.is_connected(_on_session_started):
		target.session_started.disconnect(_on_session_started)
	if target.session_stopped.is_connected(_on_session_stopped):
		target.session_stopped.disconnect(_on_session_stopped)
	if target.participant_joined.is_connected(_on_participant_changed):
		target.participant_joined.disconnect(_on_participant_changed)
	if target.participant_disconnected.is_connected(_on_participant_changed):
		target.participant_disconnected.disconnect(_on_participant_changed)
	if target.intent_applied.is_connected(_on_intent_applied):
		target.intent_applied.disconnect(_on_intent_applied)
	if target.intent_rejected.is_connected(_on_intent_rejected):
		target.intent_rejected.disconnect(_on_intent_rejected)
	if target.snapshot_applied.is_connected(_on_snapshot_applied):
		target.snapshot_applied.disconnect(_on_snapshot_applied)


func _sync_camera_to_focus() -> void:
	if _camera == null:
		return
	var local_actor := _chunk_view.local_actor_view()
	if local_actor != null:
		_camera.position = local_actor.position
	else:
		_camera.position = _chunk_view.field_center_world()
	_camera.reset_smoothing()


func _on_session_started(_status: Dictionary) -> void:
	refresh_presentation()


func _on_session_stopped() -> void:
	refresh_presentation()


func _on_participant_changed(_participant_id: String, _body_entity_id: int) -> void:
	refresh_presentation()


func _on_intent_applied(_intent: Dictionary, _fact: Dictionary) -> void:
	refresh_presentation()


func _on_intent_rejected(rejection: Dictionary) -> void:
	if _status_banner_label != null:
		_status_banner_label.text = (
			"Rejected: %s (%s)"
			% [String(rejection.get("reason", "")), String(rejection.get("error", ""))]
		)
	refresh_presentation()


func _on_snapshot_applied(_state_hash: String) -> void:
	refresh_presentation()


func _on_step_time_pressed() -> void:
	if _session == null:
		return
	var report: Dictionary = _session.advance_simulation_minutes(1)
	if _status_banner_label != null:
		_status_banner_label.text = (
			"Time +1m -> m=%d" % int(report.get("end_minute", 0))
			if bool(report.get("ok", false))
			else "Step failed"
		)
	refresh_presentation()


func _on_save_pressed() -> void:
	var report := save_offline_campaign(default_slot_id)
	if _status_banner_label != null:
		_status_banner_label.text = (
			"Saved slot '%s'" % default_slot_id
			if bool(report.get("ok", false))
			else "Save failed: %s" % str(report.get("errors", []))
		)


func _on_menu_pressed() -> void:
	if _session != null and _owns_session and is_instance_valid(_session):
		_session.stop_session()
	GameManager.return_to_main_menu()
