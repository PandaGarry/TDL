class_name GreyboxWorld
extends RefCounted
## P0 greybox world vocabulary and bootstrap rules.
##
## This class owns the intentionally small component contract shared by
## the authoritative session and the future P0-F presentation:
## player-controlled bodies have `body`, `position` and `inventory`
## components; the one mutable supply object has `position`,
## `container` and `interactable` components.
##
## It is not the final character or object domain model. Keeping these
## greybox rules out of GameSession lets the session stay focused on
## authority, scheduling, persistence and transport while real domain
## modules replace this prototype vocabulary in later slices.

const BODY_DEFINITION_ID := "core:actor/greybox_body"
const OBJECT_DEFINITION_ID := "core:object/greybox_supply_crate"
const DEFAULT_CONTAINER_ITEM_DEFINITION_ID := "core:material/torava_wood"
const DEFAULT_CONTAINER_COUNT := 3
const MAX_MOVE_STEP_TILES := 1

const BODY_COMPONENT := "body"
const POSITION_COMPONENT := "position"
const INVENTORY_COMPONENT := "inventory"
const CONTAINER_COMPONENT := "container"
const INTERACTABLE_COMPONENT := "interactable"


static func required_definition_ids() -> Array[String]:
	return [BODY_DEFINITION_ID, OBJECT_DEFINITION_ID, DEFAULT_CONTAINER_ITEM_DEFINITION_ID]


static func validate_required_definitions(active_registry: DefinitionRegistry) -> Array[String]:
	var errors: Array[String] = []
	for definition_id in required_definition_ids():
		if not active_registry.has_definition(definition_id):
			errors.append("greybox session requires missing definition '%s'" % definition_id)
	return errors


static func validate_world_definitions(
	world: WorldState, active_registry: DefinitionRegistry
) -> Array[String]:
	var errors: Array[String] = []
	for entity_id in world.entity_ids():
		var definition_id := String(world.get_entity(entity_id).get("definition_id", ""))
		if not active_registry.has_definition(definition_id):
			errors.append(
				"entity %d references unknown definition '%s'" % [entity_id, definition_id]
			)
	return errors


static func ensure_supply_object(
	world: WorldState, active_registry: DefinitionRegistry, width_tiles: int, height_tiles: int
) -> Dictionary:
	var existing_id := find_supply_object(world)
	if existing_id > 0:
		return _existing_object_report(
			world, active_registry, existing_id, width_tiles, height_tiles
		)
	var tile := _first_free_tile(world, _object_spawn_tiles(), width_tiles, height_tiles)
	if tile.x < 0 or not active_registry.has_definition(OBJECT_DEFINITION_ID):
		return _failure("greybox supply object cannot be created")
	var entity_id := (
		world
		. create_entity(
			OBJECT_DEFINITION_ID,
			{
				POSITION_COMPONENT: {"tile_x": tile.x, "tile_y": tile.y},
				CONTAINER_COMPONENT:
				{
					"definition_id": DEFAULT_CONTAINER_ITEM_DEFINITION_ID,
					"count": DEFAULT_CONTAINER_COUNT,
				},
				INTERACTABLE_COMPONENT: {"verb": "take_one"},
			}
		)
	)
	if entity_id < 1:
		return _failure("failed to create the greybox supply object")
	var fact := world.fact_log().append_fact(
		"object_spawned",
		world.clock().total_minutes(),
		{"entity_id": entity_id, "tile_x": tile.x, "tile_y": tile.y},
		entity_id,
		OBJECT_DEFINITION_ID
	)
	if fact.is_empty():
		world.remove_entity(entity_id)
		return _failure("failed to record greybox supply object creation")
	return {"ok": true, "entity_id": entity_id, "created": true, "errors": []}


static func spawn_body(
	world: WorldState,
	active_registry: DefinitionRegistry,
	participant_id: String,
	display_name: String,
	max_players: int,
	width_tiles: int,
	height_tiles: int
) -> Dictionary:
	var existing_id := find_body(world, participant_id)
	if existing_id > 0:
		return {"ok": true, "body_entity_id": existing_id, "created": false, "errors": []}
	var preflight_error := _body_spawn_preflight_error(world, active_registry, max_players)
	if not preflight_error.is_empty():
		return _failure(preflight_error)
	var tile := _first_free_tile(world, _body_spawn_tiles(), width_tiles, height_tiles)
	if tile.x < 0:
		return _failure("no free greybox tile for a new body")
	var entity_id := (
		world
		. create_entity(
			BODY_DEFINITION_ID,
			{
				BODY_COMPONENT:
				{
					"participant_id": participant_id,
					"display_name": display_name,
					"is_player_body": true,
				},
				POSITION_COMPONENT: {"tile_x": tile.x, "tile_y": tile.y},
				INVENTORY_COMPONENT: {},
			}
		)
	)
	if entity_id < 1:
		return _failure("failed to create a greybox body")
	var fact := (
		world
		. fact_log()
		. append_fact(
			"body_spawned",
			world.clock().total_minutes(),
			{
				"entity_id": entity_id,
				"participant_id": participant_id,
				"tile_x": tile.x,
				"tile_y": tile.y,
			},
			entity_id,
			BODY_DEFINITION_ID
		)
	)
	if fact.is_empty():
		world.remove_entity(entity_id)
		return _failure("failed to record greybox body creation")
	return {"ok": true, "body_entity_id": entity_id, "created": true, "errors": []}


static func find_supply_object(world: WorldState) -> int:
	if world == null or not world.is_initialized():
		return -1
	for entity_id in world.entity_ids():
		if String(world.get_entity(entity_id).get("definition_id", "")) == OBJECT_DEFINITION_ID:
			return entity_id
	return -1


static func find_body(world: WorldState, participant_id: String) -> int:
	for record in body_records(world):
		if String(record.get("participant_id", "")) == participant_id:
			return int(record.get("body_entity_id", -1))
	return -1


static func body_records(world: WorldState) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if world == null or not world.is_initialized():
		return result
	for entity_id in world.entity_ids():
		if String(world.get_entity(entity_id).get("definition_id", "")) != BODY_DEFINITION_ID:
			continue
		var body := world.get_entity_component(entity_id, BODY_COMPONENT)
		var participant_id := _string_value(body.get("participant_id", null))
		var display_name := _string_value(body.get("display_name", null))
		if not StableId.is_valid_segment(participant_id) or display_name.strip_edges().is_empty():
			continue
		(
			result
			. append(
				{
					"participant_id": participant_id,
					"display_name": display_name,
					"body_entity_id": entity_id,
				}
			)
		)
	return result


static func tile_is_occupied(
	world: WorldState,
	tile: Vector2i,
	width_tiles: int,
	height_tiles: int,
	ignored_entity_id: int = -1
) -> bool:
	for entity_id in world.entity_ids():
		if entity_id == ignored_entity_id or not entity_is_solid(world, entity_id):
			continue
		var position := position_from_component(
			world.get_entity_component(entity_id, POSITION_COMPONENT), width_tiles, height_tiles
		)
		if position == tile:
			return true
	return false


static func entity_is_solid(world: WorldState, entity_id: int) -> bool:
	var definition_id := String(world.get_entity(entity_id).get("definition_id", ""))
	if definition_id == BODY_DEFINITION_ID or definition_id == OBJECT_DEFINITION_ID:
		return true
	return (
		not world.get_entity_component(entity_id, BODY_COMPONENT).is_empty()
		or not world.get_entity_component(entity_id, CONTAINER_COMPONENT).is_empty()
	)


static func position_component_is_valid(
	component: Dictionary, width_tiles: int, height_tiles: int
) -> bool:
	return position_from_component(component, width_tiles, height_tiles).x >= 0


static func position_from_component(
	component: Dictionary, width_tiles: int, height_tiles: int
) -> Vector2i:
	if not _has_only_keys(component, ["tile_x", "tile_y"]):
		return Vector2i(-1, -1)
	var parsed_x := _integral_value(component.get("tile_x", null))
	var parsed_y := _integral_value(component.get("tile_y", null))
	if not bool(parsed_x.get("ok", false)) or not bool(parsed_y.get("ok", false)):
		return Vector2i(-1, -1)
	var tile := Vector2i(int(parsed_x["value"]), int(parsed_y["value"]))
	return tile if tile_is_in_bounds(tile, width_tiles, height_tiles) else Vector2i(-1, -1)


static func container_component_is_valid(
	component: Dictionary, active_registry: DefinitionRegistry
) -> bool:
	if not _has_only_keys(component, ["definition_id", "count"]):
		return false
	var definition_id := _string_value(component.get("definition_id", null))
	var count := _integral_value(component.get("count", null))
	return (
		active_registry.has_definition(definition_id)
		and StableId.kind_of(definition_id) == "material"
		and bool(count.get("ok", false))
		and int(count.get("value", -1)) >= 0
	)


static func inventory_component_is_valid(component: Dictionary) -> bool:
	for raw_key in component.keys():
		if typeof(raw_key) != TYPE_STRING or not StableId.is_valid(String(raw_key)):
			return false
		var count := _integral_value(component.get(raw_key, null))
		if not bool(count.get("ok", false)) or int(count.get("value", -1)) < 0:
			return false
	return true


static func tile_is_in_bounds(tile: Vector2i, width_tiles: int, height_tiles: int) -> bool:
	return tile.x >= 0 and tile.y >= 0 and tile.x < width_tiles and tile.y < height_tiles


static func integral_value(value: Variant) -> Dictionary:
	match typeof(value):
		TYPE_INT:
			var int_value := int(value)
			if int_value >= -JsonValue.MAX_SAFE_INTEGER and int_value <= JsonValue.MAX_SAFE_INTEGER:
				return {"ok": true, "value": int_value}
		TYPE_FLOAT:
			var float_value := float(value)
			if (
				is_finite(float_value)
				and float_value == floorf(float_value)
				and absf(float_value) <= float(JsonValue.MAX_SAFE_INTEGER)
			):
				return {"ok": true, "value": int(float_value)}
	return {"ok": false, "value": 0}


static func string_value(value: Variant) -> String:
	return String(value) if typeof(value) == TYPE_STRING else ""


static func has_only_keys(value: Dictionary, required_keys: Array) -> bool:
	if value.size() != required_keys.size():
		return false
	for raw_key in value.keys():
		if typeof(raw_key) != TYPE_STRING or not required_keys.has(String(raw_key)):
			return false
	return true


static func _existing_object_report(
	world: WorldState,
	active_registry: DefinitionRegistry,
	entity_id: int,
	width_tiles: int,
	height_tiles: int
) -> Dictionary:
	if (
		not position_component_is_valid(
			world.get_entity_component(entity_id, POSITION_COMPONENT), width_tiles, height_tiles
		)
		or not container_component_is_valid(
			world.get_entity_component(entity_id, CONTAINER_COMPONENT), active_registry
		)
	):
		return _failure("existing greybox supply object has invalid components")
	return {"ok": true, "entity_id": entity_id, "created": false, "errors": []}


static func _body_spawn_preflight_error(
	world: WorldState, active_registry: DefinitionRegistry, max_players: int
) -> String:
	if not active_registry.has_definition(BODY_DEFINITION_ID):
		return "greybox body definition is not loaded"
	if body_records(world).size() >= maxi(max_players, 1):
		return "session body capacity has been reached"
	return ""


static func _first_free_tile(
	world: WorldState, candidates: Array[Vector2i], width_tiles: int, height_tiles: int
) -> Vector2i:
	for tile in candidates:
		if (
			tile_is_in_bounds(tile, width_tiles, height_tiles)
			and not tile_is_occupied(world, tile, width_tiles, height_tiles)
		):
			return tile
	return Vector2i(-1, -1)


static func _body_spawn_tiles() -> Array[Vector2i]:
	return [
		Vector2i(2, 2),
		Vector2i(4, 2),
		Vector2i(2, 4),
		Vector2i(4, 4),
		Vector2i(6, 2),
		Vector2i(6, 4),
		Vector2i(8, 2),
		Vector2i(8, 4),
	]


static func _object_spawn_tiles() -> Array[Vector2i]:
	return [
		Vector2i(3, 2),
		Vector2i(3, 3),
		Vector2i(5, 3),
		Vector2i(3, 5),
		Vector2i(5, 5),
		Vector2i(7, 3),
	]


static func _failure(message: String) -> Dictionary:
	return {"ok": false, "errors": [message]}


static func _integral_value(value: Variant) -> Dictionary:
	return integral_value(value)


static func _string_value(value: Variant) -> String:
	return string_value(value)


static func _has_only_keys(value: Dictionary, required_keys: Array) -> bool:
	return has_only_keys(value, required_keys)
