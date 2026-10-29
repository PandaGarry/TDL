extends Node
## Child-process ENet client worker for the P0-G two-process acceptance test.
##
## Launched via `OS.create_process(...)` by `tests/integration/p0_acceptance_test.gd`.
## Connects to the authoritative host over localhost ENet, hydrates a full
## `GreyboxStage`, submits `interact` (`take_one`) and `move_down` (`(4,2) -> (4,3)`),
## waits for replicated snapshots, writes its diagnostic report to `SaveStore`
## and disconnects cleanly.

const WORKER_DOCUMENT_NAME := "worker_report"

var _port: int = 0
var _save_root: String = "user://tests/p0_acceptance"
var _slot_id: String = "worker_slot"
var _session: GameSession
var _stage: GreyboxStage


func _ready() -> void:
	call_deferred("_run_worker")


func _run_worker() -> void:
	_parse_cmdline()
	if _port <= 0:
		_write_report_and_quit(false, "invalid or missing --port argument")
		return

	_session = GameSession.new()
	_session.name = "WorkerClientSession"
	_session.save_root_dir = _save_root
	add_child(_session)

	var packed := load("res://scenes/levels/greybox_stage.tscn") as PackedScene
	if packed != null:
		_stage = packed.instantiate() as GreyboxStage
		if _stage != null:
			_stage.auto_start_offline = false
			_stage.save_root_dir = _save_root
			add_child(_stage)
			_stage.bind_session(_session)

	var start_report: Dictionary = _session.start_client(
		"127.0.0.1", _port, "remote_peer", "RemotePeer"
	)
	if not bool(start_report.get("ok", false)):
		_write_report_and_quit(false, "start_client failed: %s" % str(start_report))
		return

	var connected: bool = await _wait_until(Callable(self, "_is_client_ready"), 6000)
	if not connected:
		_write_report_and_quit(false, "timed out waiting for welcome snapshot")
		return

	var action_error: String = await _execute_worker_actions()
	if not action_error.is_empty():
		_write_report_and_quit(false, action_error)
		return

	if _stage != null:
		_stage.refresh_presentation()
	_write_report_and_quit(true, "")


func _execute_worker_actions() -> String:
	var interact_report: Dictionary = (
		_stage.trigger_action(GreyboxGridMetrics.ACTION_INTERACT)
		if _stage != null
		else GreyboxInputController.dispatch_action(_session, GreyboxGridMetrics.ACTION_INTERACT)
	)
	if not bool(interact_report.get("ok", false)):
		return "failed to submit interact intent"

	var took_item: bool = await _wait_until(Callable(self, "_did_take_item"), 6000)
	if not took_item:
		return "timed out waiting for replicated item transfer"

	var move_report: Dictionary = (
		_stage.trigger_action(GreyboxGridMetrics.ACTION_MOVE_DOWN)
		if _stage != null
		else GreyboxInputController.dispatch_action(_session, GreyboxGridMetrics.ACTION_MOVE_DOWN)
	)
	if not bool(move_report.get("ok", false)):
		return "failed to submit move_down intent"

	var moved: bool = await _wait_until(Callable(self, "_did_reach_tile_4_3"), 6000)
	if not moved:
		return "timed out waiting for replicated move to (4,3)"
	return ""


func _parse_cmdline() -> void:
	var all_args := OS.get_cmdline_args()
	for arg in OS.get_cmdline_user_args():
		all_args.append(arg)
	for raw_arg in all_args:
		var arg := String(raw_arg)
		if arg.begins_with("--port="):
			_port = int(arg.trim_prefix("--port="))
		elif arg.begins_with("--save-root="):
			_save_root = arg.trim_prefix("--save-root=")
		elif arg.begins_with("--slot="):
			_slot_id = arg.trim_prefix("--slot=")


func _is_client_ready() -> bool:
	if _session == null:
		return false
	var status: Dictionary = _session.session_status()
	return bool(status.get("client_ready", false)) and not _session.domain_state_hash().is_empty()


func _did_take_item() -> bool:
	if not _is_client_ready():
		return false
	var world: WorldState = _session.world_state()
	var crate_id := GreyboxWorld.find_supply_object(world)
	if crate_id < 1:
		return false
	var container: Dictionary = world.get_entity_component(
		crate_id, GreyboxWorld.CONTAINER_COMPONENT
	)
	var count := int(GreyboxWorld.integral_value(container.get("count", -1)).get("value", -1))
	return count == 2


func _did_reach_tile_4_3() -> bool:
	if not _did_take_item():
		return false
	var world: WorldState = _session.world_state()
	var body_id := GreyboxWorld.find_body(world, "remote_peer")
	if body_id < 1:
		return false
	var tile := GreyboxWorld.position_from_component(
		world.get_entity_component(body_id, GreyboxWorld.POSITION_COMPONENT),
		_session.greybox_width_tiles,
		_session.greybox_height_tiles
	)
	return tile == Vector2i(4, 3)


func _wait_until(predicate: Callable, timeout_msec: int) -> bool:
	var started := Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < timeout_msec:
		if _session != null:
			_session.poll_transport()
		if bool(predicate.call()):
			return true
		OS.delay_msec(2)
		await get_tree().process_frame
	return bool(predicate.call())


func _write_report_and_quit(ok: bool, error_message: String) -> void:
	var store := SaveStore.new(_save_root, 2)
	var local_actor := _stage.chunk_view().local_actor_view() if _stage != null else null
	var crate_view := _stage.chunk_view().supply_crate_view() if _stage != null else null
	var report := {
		"ok": ok,
		"error": error_message,
		"worker_pid": OS.get_process_id(),
		"state_hash": _session.domain_state_hash() if _session != null else "",
		"hydrated_count": _stage.chunk_view().hydrated_entity_ids().size() if _stage != null else 0,
		"local_tile_x": local_actor.tile_position.x if local_actor != null else -1,
		"local_tile_y": local_actor.tile_position.y if local_actor != null else -1,
		"crate_remaining": crate_view.remaining_count if crate_view != null else -1,
	}
	store.save_document(_slot_id, WORKER_DOCUMENT_NAME, report)
	OS.delay_msec(15)
	if _stage != null and is_instance_valid(_stage):
		_stage.bind_session(null)
		_stage.free()
		_stage = null
	if _session != null and is_instance_valid(_session):
		_session.stop_session()
		_session.free()
		_session = null
	get_tree().quit(0 if ok else 1)
