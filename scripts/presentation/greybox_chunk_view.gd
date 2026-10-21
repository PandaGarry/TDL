class_name GreyboxChunkView
extends Node2D
## Presentation container for the active greybox field/chunk.
##
## GreyboxChunkView renders the tile/ecocell/chunk grid and hydrates
## ActorView and SupplyCrateView nodes from the authoritative GameSession.
## All child views are disposable mirrors: dehydrating or freeing them
## never mutates WorldState or changes domain_state_hash().

@export_range(16.0, 128.0, 1.0) var tile_size_px: float = GreyboxGridMetrics.DEFAULT_TILE_SIZE_PX

var _width_tiles: int = 32
var _height_tiles: int = 24
var _local_body_entity_id: int = -1
var _local_tile: Vector2i = Vector2i(-1, -1)
var _hour_of_day: int = 8
var _basin_summary: Dictionary = {}
var _npcs_summary: Array[Dictionary] = []
var _actor_views_by_entity: Dictionary = {}
var _crate_views_by_entity: Dictionary = {}
var _entities_root: Node2D


func _init() -> void:
	_entities_root = Node2D.new()
	_entities_root.name = "HydratedEntities"
	add_child(_entities_root)


func _ready() -> void:
	if not SettingsManager.graphics_settings_changed.is_connected(_on_graphics_settings_changed):
		SettingsManager.graphics_settings_changed.connect(_on_graphics_settings_changed)
	queue_redraw()


func _exit_tree() -> void:
	if SettingsManager.graphics_settings_changed.is_connected(_on_graphics_settings_changed):
		SettingsManager.graphics_settings_changed.disconnect(_on_graphics_settings_changed)


func _on_graphics_settings_changed(_profile: Dictionary) -> void:
	queue_redraw()


func sync_from_session(session: GameSession) -> Dictionary:
	if (
		session == null
		or session.world_state() == null
		or not session.world_state().is_initialized()
	):
		dehydrate_all()
		return presentation_summary()
	var status: Dictionary = session.session_status()
	if not bool(status.get("running", false)):
		dehydrate_all()
		return presentation_summary()

	_width_tiles = maxi(session.greybox_width_tiles, 1)
	_height_tiles = maxi(session.greybox_height_tiles, 1)
	_local_body_entity_id = int(status.get("local_body_entity_id", -1))
	var world: WorldState = session.world_state()
	var active_registry: DefinitionRegistry = session.registry()
	var connected_by_participant := _connected_lookup(status)
	_local_tile = _resolve_entity_tile(world, _local_body_entity_id)
	_hour_of_day = world.clock().hour_of_day()
	_basin_summary = SevaraEcoChain.basin_summary(world)
	_npcs_summary = SevaraP1Npcs.npcs_summary(world)

	var seen_actors: Dictionary = {}
	var seen_crates: Dictionary = {}
	for entity_id in world.entity_ids():
		var entity: Dictionary = world.get_entity(entity_id)
		var definition_id := String(entity.get("definition_id", ""))
		if definition_id == GreyboxWorld.BODY_DEFINITION_ID:
			var actor_model := _build_actor_view_model(
				world, active_registry, entity_id, connected_by_participant
			)
			if not actor_model.is_empty():
				seen_actors[entity_id] = true
				_upsert_actor_view(entity_id, actor_model)
		elif definition_id == GreyboxWorld.OBJECT_DEFINITION_ID:
			var crate_model := _build_crate_view_model(world, active_registry, entity_id)
			if not crate_model.is_empty():
				seen_crates[entity_id] = true
				_upsert_crate_view(entity_id, crate_model)

	_prune_stale_views(_actor_views_by_entity, seen_actors)
	_prune_stale_views(_crate_views_by_entity, seen_crates)
	queue_redraw()
	return presentation_summary()


func dehydrate_all() -> void:
	for raw_id in _actor_views_by_entity.keys():
		var node: Variant = _actor_views_by_entity[raw_id]
		if is_instance_valid(node):
			(node as Node).free()
	for raw_id in _crate_views_by_entity.keys():
		var node: Variant = _crate_views_by_entity[raw_id]
		if is_instance_valid(node):
			(node as Node).free()
	_actor_views_by_entity.clear()
	_crate_views_by_entity.clear()
	_local_body_entity_id = -1
	_local_tile = Vector2i(-1, -1)
	_hour_of_day = 8
	_basin_summary = {}
	_npcs_summary = []
	queue_redraw()


func actor_view_for_entity(entity_id: int) -> ActorView:
	var candidate: Variant = _actor_views_by_entity.get(entity_id, null)
	if is_instance_valid(candidate) and not (candidate as Node).is_queued_for_deletion():
		return candidate as ActorView
	return null


func local_actor_view() -> ActorView:
	return actor_view_for_entity(_local_body_entity_id)


func supply_crate_view() -> SupplyCrateView:
	var ids: Array = _crate_views_by_entity.keys()
	ids.sort()
	for raw_id in ids:
		var candidate: Variant = _crate_views_by_entity[raw_id]
		if is_instance_valid(candidate) and not (candidate as Node).is_queued_for_deletion():
			return candidate as SupplyCrateView
	return null


func hydrated_entity_ids() -> Array[int]:
	var ids: Array[int] = []
	for raw_id in _actor_views_by_entity.keys():
		var candidate: Variant = _actor_views_by_entity[raw_id]
		if is_instance_valid(candidate) and not (candidate as Node).is_queued_for_deletion():
			ids.append(int(raw_id))
	for raw_id in _crate_views_by_entity.keys():
		var candidate: Variant = _crate_views_by_entity[raw_id]
		if is_instance_valid(candidate) and not (candidate as Node).is_queued_for_deletion():
			ids.append(int(raw_id))
	ids.sort()
	return ids


func field_center_world() -> Vector2:
	return GreyboxGridMetrics.field_pixel_size(_width_tiles, _height_tiles, tile_size_px) * 0.5


func presentation_summary() -> Dictionary:
	var actors: Array[Dictionary] = []
	var actor_ids: Array = _actor_views_by_entity.keys()
	actor_ids.sort()
	for raw_id in actor_ids:
		var view := actor_view_for_entity(int(raw_id))
		if view != null:
			actors.append(view.view_summary())

	var crate := supply_crate_view()
	var light := SevaraVisualTheme.lighting_for_hour(_hour_of_day)
	return {
		"width_tiles": _width_tiles,
		"height_tiles": _height_tiles,
		"tile_size_px": GreyboxGridMetrics.sanitized_tile_size(tile_size_px),
		"local_body_entity_id": _local_body_entity_id,
		"local_tile_x": _local_tile.x,
		"local_tile_y": _local_tile.y,
		"hydrated_entity_ids": hydrated_entity_ids(),
		"actor_count": actors.size(),
		"actors": actors,
		"supply_crate": crate.view_summary() if crate != null else {},
		"p1_basin_nodes_count": int(_basin_summary.get("node_count", 0)),
		"p1_npcs_count": _npcs_summary.size(),
		"ambient_phase": String(light.get("phase", "morning")),
		"graphics_profile": SettingsManager.graphics_profile(),
	}


func _draw() -> void:
	var resolved_tile := GreyboxGridMetrics.sanitized_tile_size(tile_size_px)
	var field_size := GreyboxGridMetrics.field_pixel_size(
		_width_tiles, _height_tiles, resolved_tile
	)
	var field_rect := Rect2(Vector2.ZERO, field_size)
	SevaraVisualTheme.draw_chunk_landscape(
		self,
		_width_tiles,
		_height_tiles,
		resolved_tile,
		_basin_summary,
		_hour_of_day,
		SettingsManager.graphics_profile()
	)
	_draw_p1_npcs(resolved_tile)

	if _local_tile.x >= 0:
		var local_origin := GreyboxGridMetrics.tile_to_world_origin(_local_tile, resolved_tile)
		draw_rect(
			Rect2(local_origin, Vector2.ONE * resolved_tile), Color(0.86, 0.68, 0.25, 0.18), true
		)

	var crate := supply_crate_view()
	if crate != null and crate.tile_position.x >= 0:
		var crate_origin := GreyboxGridMetrics.tile_to_world_origin(
			crate.tile_position, resolved_tile
		)
		var highlight := (
			Color(0.95, 0.82, 0.35, 0.24)
			if crate.can_interact_now()
			else Color(0.55, 0.42, 0.24, 0.14)
		)
		draw_rect(Rect2(crate_origin, Vector2.ONE * resolved_tile), highlight, true)

	if SettingsManager.texture_quality == SettingsManager.TEXTURE_QUALITY_GREYBOX:
		_draw_grid_lines(resolved_tile, field_size)
	draw_rect(field_rect, Color(0.46, 0.56, 0.48, 0.9), false, 2.5)


func _draw_p1_npcs(resolved_tile: float) -> void:
	for npc in _npcs_summary:
		var npc_id := String(npc.get("npc_id", ""))
		var tx := clampi(int(npc.get("tile_x", 12)), 0, _width_tiles - 1)
		var ty := clampi(int(npc.get("tile_y", 10)), 0, _height_tiles - 1)
		var center := GreyboxGridMetrics.tile_to_world_center(Vector2i(tx, ty), resolved_tile)
		draw_set_transform(center, 0.0, Vector2.ONE)
		SevaraVisualTheme.draw_humanoid_6_5_heads(
			self,
			resolved_tile,
			SevaraVisualTheme.npc_visual_palette(npc_id),
			Vector2.DOWN,
			false,
			{},
			_hour_of_day
		)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_grid_lines(resolved_tile: float, field_size: Vector2) -> void:
	for x in range(1, _width_tiles):
		var px := float(x) * resolved_tile
		var is_ecocell := (x % GreyboxGridMetrics.TILES_PER_ECOCELL) == 0
		var color := Color(0.32, 0.42, 0.35, 0.65) if is_ecocell else Color(0.18, 0.23, 0.2, 0.45)
		draw_line(Vector2(px, 0.0), Vector2(px, field_size.y), color, 1.8 if is_ecocell else 1.0)
	for y in range(1, _height_tiles):
		var py := float(y) * resolved_tile
		var is_ecocell := (y % GreyboxGridMetrics.TILES_PER_ECOCELL) == 0
		var color := Color(0.32, 0.42, 0.35, 0.65) if is_ecocell else Color(0.18, 0.23, 0.2, 0.45)
		draw_line(Vector2(0.0, py), Vector2(field_size.x, py), color, 1.8 if is_ecocell else 1.0)


func _build_actor_view_model(
	world: WorldState,
	active_registry: DefinitionRegistry,
	entity_id: int,
	connected_by_participant: Dictionary
) -> Dictionary:
	var tile := _resolve_entity_tile(world, entity_id)
	if tile.x < 0:
		return {}
	var body: Dictionary = world.get_entity_component(entity_id, GreyboxWorld.BODY_COMPONENT)
	var inventory: Dictionary = world.get_entity_component(
		entity_id, GreyboxWorld.INVENTORY_COMPONENT
	)
	var vitals: Dictionary = world.get_entity_component(entity_id, BodyVitals.VITALS_COMPONENT)
	var participant_id := String(body.get("participant_id", ""))
	var display_name := String(body.get("display_name", participant_id))
	var definition: Dictionary = (
		active_registry.get_definition(GreyboxWorld.BODY_DEFINITION_ID)
		if active_registry != null
		else {}
	)
	return {
		"entity_id": entity_id,
		"definition_id": GreyboxWorld.BODY_DEFINITION_ID,
		"visual_profile":
		String(definition.get("visual_profile", "core:visual/actor_greybox_body")),
		"participant_id": participant_id,
		"display_name": display_name,
		"tile_x": tile.x,
		"tile_y": tile.y,
		"is_local_body": entity_id == _local_body_entity_id,
		"connected": bool(connected_by_participant.get(participant_id, true)),
		"inventory": inventory,
		"vitals": vitals,
		"hour_of_day": _hour_of_day,
	}


func _build_crate_view_model(
	world: WorldState, active_registry: DefinitionRegistry, entity_id: int
) -> Dictionary:
	var tile := _resolve_entity_tile(world, entity_id)
	if tile.x < 0:
		return {}
	var container: Dictionary = world.get_entity_component(
		entity_id, GreyboxWorld.CONTAINER_COMPONENT
	)
	var interactable: Dictionary = world.get_entity_component(
		entity_id, GreyboxWorld.INTERACTABLE_COMPONENT
	)
	var item_definition_id := String(
		container.get("definition_id", GreyboxWorld.DEFAULT_CONTAINER_ITEM_DEFINITION_ID)
	)
	var remaining_count := int(
		GreyboxWorld.integral_value(container.get("count", 0)).get("value", 0)
	)
	var crate_def: Dictionary = (
		active_registry.get_definition(GreyboxWorld.OBJECT_DEFINITION_ID)
		if active_registry != null
		else {}
	)
	var item_def: Dictionary = (
		active_registry.get_definition(item_definition_id) if active_registry != null else {}
	)
	var item_name_key := String(item_def.get("name_key", ""))
	var item_display_name := (
		UiLocaleCatalog.translate_key(item_name_key)
		if not item_name_key.is_empty()
		else item_definition_id
	)
	var adjacent := (
		_local_tile.x >= 0 and GreyboxGridMetrics.manhattan_distance(_local_tile, tile) == 1
	)
	return {
		"entity_id": entity_id,
		"definition_id": GreyboxWorld.OBJECT_DEFINITION_ID,
		"visual_profile":
		String(crate_def.get("visual_profile", "core:visual/object_greybox_supply_crate")),
		"tile_x": tile.x,
		"tile_y": tile.y,
		"item_definition_id": item_definition_id,
		"item_display_name": item_display_name,
		"remaining_count": remaining_count,
		"verb": String(interactable.get("verb", "take_one")),
		"adjacent_to_local_body": adjacent,
	}


func _upsert_actor_view(entity_id: int, model: Dictionary) -> void:
	var view := actor_view_for_entity(entity_id)
	if view == null:
		view = ActorView.new()
		_entities_root.add_child(view)
		_actor_views_by_entity[entity_id] = view
	view.apply_view_model(model, tile_size_px)


func _upsert_crate_view(entity_id: int, model: Dictionary) -> void:
	var candidate: Variant = _crate_views_by_entity.get(entity_id, null)
	var view: SupplyCrateView = null
	if is_instance_valid(candidate) and not (candidate as Node).is_queued_for_deletion():
		view = candidate as SupplyCrateView
	if view == null:
		view = SupplyCrateView.new()
		_entities_root.add_child(view)
		_crate_views_by_entity[entity_id] = view
	view.apply_view_model(model, tile_size_px)


func _resolve_entity_tile(world: WorldState, entity_id: int) -> Vector2i:
	if world == null or not world.has_entity(entity_id):
		return Vector2i(-1, -1)
	return GreyboxWorld.position_from_component(
		world.get_entity_component(entity_id, GreyboxWorld.POSITION_COMPONENT),
		_width_tiles,
		_height_tiles
	)


static func _connected_lookup(status: Dictionary) -> Dictionary:
	var lookup: Dictionary = {}
	var raw_participants: Variant = status.get("participants", [])
	if typeof(raw_participants) != TYPE_ARRAY:
		return lookup
	var participants: Array = raw_participants
	for raw_entry in participants:
		if typeof(raw_entry) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = raw_entry
		var participant_id := String(entry.get("participant_id", ""))
		if not participant_id.is_empty():
			lookup[participant_id] = bool(entry.get("connected", false))
	return lookup


static func _prune_stale_views(views_by_entity: Dictionary, active_ids: Dictionary) -> void:
	var existing_ids: Array = views_by_entity.keys()
	for raw_id in existing_ids:
		var entity_id := int(raw_id)
		if active_ids.has(entity_id):
			continue
		var candidate: Variant = views_by_entity.get(entity_id, null)
		if is_instance_valid(candidate):
			(candidate as Node).free()
		views_by_entity.erase(entity_id)
