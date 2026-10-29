class_name GreyboxInputController
extends RefCounted
## Translates semantic InputMap actions into authoritative GameSession intents.
##
## Presentation never mutates WorldState directly: movement and object
## interaction are submitted through `GameSession.submit_intent(...)`.
## UI-only actions such as `debug_toggle` are reported back to the stage
## without touching the simulation.

const SUPPORTED_ACTIONS: Array[StringName] = [
	GreyboxGridMetrics.ACTION_MOVE_LEFT,
	GreyboxGridMetrics.ACTION_MOVE_RIGHT,
	GreyboxGridMetrics.ACTION_MOVE_UP,
	GreyboxGridMetrics.ACTION_MOVE_DOWN,
	GreyboxGridMetrics.ACTION_INTERACT,
	GreyboxGridMetrics.ACTION_DEBUG_TOGGLE,
]


static func resolve_action_from_event(event: InputEvent) -> StringName:
	if event == null or not event.is_pressed() or event.is_echo():
		return &""
	for action_name in SUPPORTED_ACTIONS:
		if InputMap.has_action(action_name) and event.is_action_pressed(action_name, false):
			return action_name
	return &""


static func dispatch_event(
	session: GameSession, event: InputEvent, process_immediately_on_host: bool = true
) -> Dictionary:
	var action_name := resolve_action_from_event(event)
	if action_name == &"":
		return {"handled": false, "ok": false, "action": "", "errors": []}
	return dispatch_action(session, action_name, process_immediately_on_host)


static func dispatch_action(
	session: GameSession, action_name: StringName, process_immediately_on_host: bool = true
) -> Dictionary:
	if action_name == GreyboxGridMetrics.ACTION_DEBUG_TOGGLE:
		return {
			"handled": true,
			"ok": true,
			"action": String(action_name),
			"debug_toggle": true,
			"errors": [],
		}
	if GreyboxGridMetrics.is_move_action(action_name):
		var step := GreyboxGridMetrics.direction_for_action(action_name)
		var report := submit_move_step(session, step, process_immediately_on_host)
		report["action"] = String(action_name)
		return report
	if action_name == GreyboxGridMetrics.ACTION_INTERACT:
		var report := submit_interact(session, process_immediately_on_host)
		report["action"] = String(action_name)
		return report
	return {
		"handled": false,
		"ok": false,
		"action": String(action_name),
		"errors": ["unsupported input action '%s'" % String(action_name)],
	}


static func submit_move_step(
	session: GameSession, step: Vector2i, process_immediately_on_host: bool = true
) -> Dictionary:
	var preflight := _preflight_local_body(session)
	if not bool(preflight.get("ok", false)):
		return preflight
	if step == Vector2i.ZERO:
		return _failure("move step must not be zero")

	var world: WorldState = preflight.get("world") as WorldState
	var body_entity_id := int(preflight.get("body_entity_id", -1))
	var current_tile := GreyboxWorld.position_from_component(
		world.get_entity_component(body_entity_id, GreyboxWorld.POSITION_COMPONENT),
		session.greybox_width_tiles,
		session.greybox_height_tiles
	)
	if current_tile.x < 0:
		return _failure("local body has no valid greybox position")
	var target_tile := current_tile + step
	var payload := {
		"entity_id": body_entity_id,
		"to_tile_x": target_tile.x,
		"to_tile_y": target_tile.y,
	}
	return _submit_and_finalize(
		session, SessionProtocol.INTENT_MOVE_BODY, payload, process_immediately_on_host
	)


static func submit_interact(
	session: GameSession, process_immediately_on_host: bool = true, verb: String = "take_one"
) -> Dictionary:
	var preflight := _preflight_local_body(session)
	if not bool(preflight.get("ok", false)):
		return preflight

	var world: WorldState = preflight.get("world") as WorldState
	var object_entity_id := GreyboxWorld.find_supply_object(world)
	if object_entity_id < 1:
		return _failure("greybox supply object does not exist in the world")
	var payload := {"target_entity_id": object_entity_id, "verb": verb}
	return _submit_and_finalize(
		session, SessionProtocol.INTENT_INTERACT_OBJECT, payload, process_immediately_on_host
	)


static func _preflight_local_body(session: GameSession) -> Dictionary:
	if session == null:
		return _failure("game session is null")
	var status: Dictionary = session.session_status()
	if not bool(status.get("running", false)):
		return _failure("game session is not running")
	var world: WorldState = session.world_state()
	if world == null or not world.is_initialized():
		return _failure("session world is not initialized")
	var body_entity_id := int(status.get("local_body_entity_id", -1))
	if body_entity_id < 1 or not world.has_entity(body_entity_id):
		return _failure("local participant has no active body in the world")
	return {"ok": true, "world": world, "body_entity_id": body_entity_id}


static func _submit_and_finalize(
	session: GameSession,
	intent_type: String,
	payload: Dictionary,
	process_immediately_on_host: bool
) -> Dictionary:
	var submit_report: Dictionary = session.submit_intent(intent_type, payload)
	if not bool(submit_report.get("ok", false)):
		var raw_errors: Variant = submit_report.get("errors", ["failed to submit intent"])
		var errors: Array[String] = []
		if typeof(raw_errors) == TYPE_ARRAY:
			var arr: Array = raw_errors
			for item in arr:
				errors.append(String(item))
		return {
			"handled": true,
			"ok": false,
			"intent_type": intent_type,
			"payload": payload,
			"submit_report": submit_report,
			"errors": errors,
		}

	var result := {
		"handled": true,
		"ok": true,
		"intent_type": intent_type,
		"payload": payload,
		"submit_report": submit_report,
		"errors": [],
	}
	var status: Dictionary = session.session_status()
	if process_immediately_on_host and String(status.get("role", "")) == "host":
		var batch_report: Dictionary = session.process_pending_intents()
		result["batch_report"] = batch_report
		var raw_results: Variant = batch_report.get("results", [])
		if typeof(raw_results) == TYPE_ARRAY:
			var results_array: Array = raw_results
			if not results_array.is_empty():
				var last_outcome: Dictionary = results_array[results_array.size() - 1]
				result["intent_outcome"] = last_outcome
				result["applied"] = bool(last_outcome.get("ok", false))
	return result


static func _failure(message: String) -> Dictionary:
	return {"handled": true, "ok": false, "errors": [message]}
