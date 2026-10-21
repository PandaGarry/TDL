class_name GreyboxIntents
extends RefCounted
## Authoritative P0 greybox intent application.
##
## GameSession authenticates the sender, consumes the client sequence
## and decides which body that participant owns. This class then applies
## only the two P0-E domain verbs against WorldState:
## - `move_body`: one bounded, unoccupied tile step;
## - `interact_object`: take one material unit from the adjacent supply
##   object into the actor body's inventory.
##
## Every successful mutation appends its world fact at the current
## WorldClock minute. If fact append fails, component mutations are
## rolled back so state and chronicle cannot silently diverge.


static func apply_intent(
	world: WorldState,
	active_registry: DefinitionRegistry,
	participant_id: String,
	body_entity_id: int,
	intent_type: String,
	payload: Variant,
	width_tiles: int,
	height_tiles: int
) -> Dictionary:
	if typeof(payload) != TYPE_DICTIONARY:
		return _failure("invalid_payload", "intent payload must be a dictionary")
	var typed_payload: Dictionary = payload
	match intent_type:
		SessionProtocol.INTENT_MOVE_BODY:
			return _apply_move_body(
				world, participant_id, body_entity_id, typed_payload, width_tiles, height_tiles
			)
		SessionProtocol.INTENT_INTERACT_OBJECT:
			return _apply_interact_object(
				world,
				active_registry,
				participant_id,
				body_entity_id,
				typed_payload,
				width_tiles,
				height_tiles
			)
	return _failure("unsupported_intent", "intent type is not supported")


static func _apply_move_body(
	world: WorldState,
	participant_id: String,
	body_entity_id: int,
	payload: Dictionary,
	width_tiles: int,
	height_tiles: int
) -> Dictionary:
	var context := _move_context(world, body_entity_id, payload, width_tiles, height_tiles)
	if not bool(context.get("ok", false)):
		return _failure(String(context["reason"]), String(context["error"]))
	var current: Vector2i = context.get("current", Vector2i(-1, -1))
	var target: Vector2i = context.get("target", Vector2i(-1, -1))
	if not world.set_entity_component(
		body_entity_id, GreyboxWorld.POSITION_COMPONENT, {"tile_x": target.x, "tile_y": target.y}
	):
		return _failure("state_update_failed", "failed to move the body")
	var fact := _append_current_fact(
		world,
		"body_moved",
		{
			"participant_id": participant_id,
			"entity_id": body_entity_id,
			"from_tile_x": current.x,
			"from_tile_y": current.y,
			"to_tile_x": target.x,
			"to_tile_y": target.y,
		},
		body_entity_id,
		GreyboxWorld.BODY_DEFINITION_ID
	)
	if fact.is_empty():
		world.set_entity_component(
			body_entity_id,
			GreyboxWorld.POSITION_COMPONENT,
			{"tile_x": current.x, "tile_y": current.y}
		)
		return _failure("fact_append_failed", "failed to record body movement")
	return {"ok": true, "fact": fact, "reason": "", "error": ""}


static func _apply_interact_object(
	world: WorldState,
	active_registry: DefinitionRegistry,
	participant_id: String,
	body_entity_id: int,
	payload: Dictionary,
	width_tiles: int,
	height_tiles: int
) -> Dictionary:
	var context := _interact_context(
		world, active_registry, body_entity_id, payload, width_tiles, height_tiles
	)
	if not bool(context.get("ok", false)):
		return _failure(String(context["reason"]), String(context["error"]))

	var target_entity_id := int(context.get("target_entity_id", -1))
	var item_definition_id := String(context.get("item_definition_id", ""))
	var old_count := int(context.get("old_count", 0))
	var container: Dictionary = context.get("container", {})
	var inventory: Dictionary = context.get("inventory", {})
	var new_inventory: Dictionary = inventory.duplicate(true)
	var new_item_count := (
		int(GreyboxWorld.integral_value(new_inventory.get(item_definition_id, 0)).get("value", 0))
		+ 1
	)
	new_inventory[item_definition_id] = new_item_count
	var new_container := {"definition_id": item_definition_id, "count": old_count - 1}

	if not world.set_entity_component(
		target_entity_id, GreyboxWorld.CONTAINER_COMPONENT, new_container
	):
		return _failure("state_update_failed", "failed to update the supply object")
	if not world.set_entity_component(
		body_entity_id, GreyboxWorld.INVENTORY_COMPONENT, new_inventory
	):
		world.set_entity_component(target_entity_id, GreyboxWorld.CONTAINER_COMPONENT, container)
		return _failure("state_update_failed", "failed to update body inventory")
	var fact := _append_current_fact(
		world,
		"item_taken",
		{
			"participant_id": participant_id,
			"entity_id": body_entity_id,
			"target_entity_id": target_entity_id,
			"item_definition_id": item_definition_id,
			"remaining_count": old_count - 1,
			"inventory_count": new_item_count,
		},
		body_entity_id,
		item_definition_id
	)
	if fact.is_empty():
		world.set_entity_component(target_entity_id, GreyboxWorld.CONTAINER_COMPONENT, container)
		world.set_entity_component(body_entity_id, GreyboxWorld.INVENTORY_COMPONENT, inventory)
		return _failure("fact_append_failed", "failed to record item transfer")
	return {"ok": true, "fact": fact, "reason": "", "error": ""}


static func _move_context(
	world: WorldState, body_entity_id: int, payload: Dictionary, width_tiles: int, height_tiles: int
) -> Dictionary:
	var reason := ""
	var error := ""
	var current := Vector2i(-1, -1)
	var target := Vector2i(-1, -1)
	if not GreyboxWorld.has_only_keys(payload, ["entity_id", "to_tile_x", "to_tile_y"]):
		reason = "invalid_payload"
		error = "move payload has invalid fields"
	else:
		var requested_entity := GreyboxWorld.integral_value(payload.get("entity_id", null))
		var target_x := GreyboxWorld.integral_value(payload.get("to_tile_x", null))
		var target_y := GreyboxWorld.integral_value(payload.get("to_tile_y", null))
		if (
			not bool(requested_entity.get("ok", false))
			or not bool(target_x.get("ok", false))
			or not bool(target_y.get("ok", false))
		):
			reason = "invalid_payload"
			error = "move fields must be integers"
		elif int(requested_entity.get("value", -1)) != body_entity_id:
			reason = "entity_mismatch"
			error = "participant cannot move another participant's body"
		else:
			current = GreyboxWorld.position_from_component(
				world.get_entity_component(body_entity_id, GreyboxWorld.POSITION_COMPONENT),
				width_tiles,
				height_tiles
			)
			target = Vector2i(int(target_x["value"]), int(target_y["value"]))
			var distance := absi(target.x - current.x) + absi(target.y - current.y)
			if current.x < 0:
				reason = "invalid_body_state"
				error = "body has no valid position"
			elif not GreyboxWorld.tile_is_in_bounds(target, width_tiles, height_tiles):
				reason = "target_out_of_bounds"
				error = "target tile is outside the greybox"
			elif distance == 0:
				reason = "invalid_payload"
				error = "move target equals the current tile"
			elif distance > GreyboxWorld.MAX_MOVE_STEP_TILES:
				reason = "step_too_far"
				error = "move exceeds the authoritative step limit"
			elif GreyboxWorld.tile_is_occupied(
				world, target, width_tiles, height_tiles, body_entity_id
			):
				reason = "tile_occupied"
				error = "target tile is occupied"
	return {
		"ok": reason.is_empty(),
		"current": current,
		"target": target,
		"reason": reason,
		"error": error,
	}


static func _interact_context(
	world: WorldState,
	active_registry: DefinitionRegistry,
	body_entity_id: int,
	payload: Dictionary,
	width_tiles: int,
	height_tiles: int
) -> Dictionary:
	var reason := ""
	var error := ""
	var target_entity_id := -1
	var container: Dictionary = {}
	var inventory: Dictionary = {}
	var item_definition_id := ""
	var old_count := 0

	if not GreyboxWorld.has_only_keys(payload, ["target_entity_id", "verb"]):
		reason = "invalid_payload"
		error = "interact payload has invalid fields"
	else:
		var target_parse := GreyboxWorld.integral_value(payload.get("target_entity_id", null))
		if not bool(target_parse.get("ok", false)):
			reason = "invalid_payload"
			error = "target_entity_id must be an integer"
		elif GreyboxWorld.string_value(payload.get("verb", null)) != "take_one":
			reason = "unsupported_verb"
			error = "only take_one is supported in P0-E"
		else:
			target_entity_id = int(target_parse.get("value", -1))
			if not world.has_entity(target_entity_id):
				reason = "target_not_found"
				error = "interaction target does not exist"
			elif (
				String(world.get_entity(target_entity_id).get("definition_id", ""))
				!= GreyboxWorld.OBJECT_DEFINITION_ID
			):
				reason = "invalid_target"
				error = "target is not the greybox supply object"
			else:
				var body_position := GreyboxWorld.position_from_component(
					world.get_entity_component(body_entity_id, GreyboxWorld.POSITION_COMPONENT),
					width_tiles,
					height_tiles
				)
				var target_position := GreyboxWorld.position_from_component(
					world.get_entity_component(target_entity_id, GreyboxWorld.POSITION_COMPONENT),
					width_tiles,
					height_tiles
				)
				container = world.get_entity_component(
					target_entity_id, GreyboxWorld.CONTAINER_COMPONENT
				)
				inventory = world.get_entity_component(
					body_entity_id, GreyboxWorld.INVENTORY_COMPONENT
				)
				item_definition_id = String(container.get("definition_id", ""))
				old_count = int(
					GreyboxWorld.integral_value(container.get("count", null)).get("value", 0)
				)
				var distance := (
					absi(target_position.x - body_position.x)
					+ absi(target_position.y - body_position.y)
				)
				if body_position.x < 0 or target_position.x < 0:
					reason = "invalid_object_state"
					error = "actor or target has no valid position"
				elif distance > 1:
					reason = "not_adjacent"
					error = "body must be adjacent to the supply object"
				elif not GreyboxWorld.container_component_is_valid(container, active_registry):
					reason = "invalid_object_state"
					error = "supply container is invalid"
				elif old_count <= 0:
					reason = "container_empty"
					error = "supply object is empty"
				elif not GreyboxWorld.inventory_component_is_valid(inventory):
					reason = "invalid_body_state"
					error = "body inventory is invalid"

	return {
		"ok": reason.is_empty(),
		"target_entity_id": target_entity_id,
		"container": container,
		"inventory": inventory,
		"item_definition_id": item_definition_id,
		"old_count": old_count,
		"reason": reason,
		"error": error,
	}


static func _append_current_fact(
	world: WorldState, kind: String, payload: Dictionary, actor_id: int, subject_id: String
) -> Dictionary:
	return world.fact_log().append_fact(
		kind, world.clock().total_minutes(), payload, actor_id, subject_id
	)


static func _failure(reason: String, error: String) -> Dictionary:
	return {"ok": false, "fact": {}, "reason": reason, "error": error}
