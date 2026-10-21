class_name ActorView
extends CharacterBody2D
## 2D presentation node for one hydrated `core:actor/greybox_body`.
##
## ActorView is strictly a presentation mirror of WorldState. Destroying
## or recreating this node does not alter the campaign state; all movement
## and inventory changes happen through authoritative GameSession intents.

const DEFAULT_BODY_RADIUS_RATIO := 0.34
const DEFAULT_SENSOR_RADIUS_RATIO := 0.95

var entity_id: int = -1
var definition_id: String = GreyboxWorld.BODY_DEFINITION_ID
var visual_profile: String = "core:visual/actor_greybox_body"
var participant_id: String = ""
var display_name: String = ""
var tile_position: Vector2i = Vector2i(-1, -1)
var facing_direction: Vector2 = Vector2.DOWN
var is_local_body: bool = false
var is_participant_connected: bool = true
var inventory: Dictionary = {}
var total_inventory_items: int = 0

var _tile_size_px: float = GreyboxGridMetrics.DEFAULT_TILE_SIZE_PX
var _collision_shape: CollisionShape2D
var _circle_shape: CircleShape2D
var _interaction_sensor: Area2D
var _sensor_collision_shape: CollisionShape2D
var _sensor_circle_shape: CircleShape2D
var _caption_label: Label


func _init() -> void:
	_configure_physics_nodes()
	_configure_caption_label()


func _ready() -> void:
	_update_geometry()
	_update_caption()
	queue_redraw()


func apply_view_model(model: Dictionary, tile_size_px: float) -> void:
	var previous_tile := tile_position
	_tile_size_px = GreyboxGridMetrics.sanitized_tile_size(tile_size_px)
	entity_id = int(model.get("entity_id", -1))
	definition_id = String(model.get("definition_id", GreyboxWorld.BODY_DEFINITION_ID))
	visual_profile = String(model.get("visual_profile", "core:visual/actor_greybox_body"))
	participant_id = String(model.get("participant_id", ""))
	display_name = String(model.get("display_name", participant_id))
	var next_tile := Vector2i(int(model.get("tile_x", 0)), int(model.get("tile_y", 0)))
	if previous_tile.x >= 0 and next_tile != previous_tile:
		var delta := Vector2(next_tile - previous_tile)
		if delta.length_squared() > 0.0:
			facing_direction = delta.normalized()
	tile_position = next_tile
	is_local_body = bool(model.get("is_local_body", false))
	is_participant_connected = bool(model.get("connected", true))
	var raw_inventory: Variant = model.get("inventory", {})
	inventory = (
		(JsonValue.duplicate_safe(raw_inventory) as Dictionary)
		if typeof(raw_inventory) == TYPE_DICTIONARY
		else {}
	)
	total_inventory_items = _sum_inventory(inventory)
	name = "ActorView_%d_%s" % [entity_id, participant_id]
	position = GreyboxGridMetrics.tile_to_world_center(tile_position, _tile_size_px)
	_update_geometry()
	_update_caption()
	queue_redraw()


func interaction_sensor() -> Area2D:
	return _interaction_sensor


func caption_text() -> String:
	return _caption_label.text if _caption_label != null else ""


func view_summary() -> Dictionary:
	return {
		"entity_id": entity_id,
		"definition_id": definition_id,
		"visual_profile": visual_profile,
		"participant_id": participant_id,
		"display_name": display_name,
		"tile_x": tile_position.x,
		"tile_y": tile_position.y,
		"world_x": position.x,
		"world_y": position.y,
		"is_local_body": is_local_body,
		"connected": is_participant_connected,
		"total_inventory_items": total_inventory_items,
		"inventory": JsonValue.duplicate_safe(inventory),
		"collision_layer": collision_layer,
		"collision_mask": collision_mask,
		"sensor_layer": _interaction_sensor.collision_layer if _interaction_sensor != null else 0,
		"sensor_mask": _interaction_sensor.collision_mask if _interaction_sensor != null else 0,
	}


func _draw() -> void:
	var radius := _tile_size_px * DEFAULT_BODY_RADIUS_RATIO
	draw_circle(Vector2(0.0, radius * 0.35), radius * 0.92, Color(0.02, 0.03, 0.04, 0.45))
	var fill_color := _body_fill_color()
	var rim_color := _body_rim_color()
	draw_circle(Vector2.ZERO, radius, fill_color)
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 28, rim_color, 2.5)
	var nose := facing_direction.normalized() * (radius * 0.72)
	draw_line(Vector2.ZERO, nose, rim_color, 2.5)
	draw_circle(nose, maxf(radius * 0.18, 2.5), rim_color)


func _configure_physics_nodes() -> void:
	collision_layer = PhysicsLayers.BODIES_BIT
	collision_mask = (
		PhysicsLayers.TERRAIN_BIT | PhysicsLayers.BODIES_BIT | PhysicsLayers.STRUCTURES_BIT
	)
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING

	_collision_shape = CollisionShape2D.new()
	_collision_shape.name = "BodyCollisionShape"
	_circle_shape = CircleShape2D.new()
	_collision_shape.shape = _circle_shape
	add_child(_collision_shape)

	_interaction_sensor = Area2D.new()
	_interaction_sensor.name = "InteractionSensor"
	_interaction_sensor.collision_layer = PhysicsLayers.SENSORS_BIT
	_interaction_sensor.collision_mask = (PhysicsLayers.INTERACTABLES_BIT | PhysicsLayers.ITEMS_BIT)
	_interaction_sensor.monitoring = false
	_interaction_sensor.monitorable = false
	add_child(_interaction_sensor)

	_sensor_collision_shape = CollisionShape2D.new()
	_sensor_collision_shape.name = "SensorCollisionShape"
	_sensor_circle_shape = CircleShape2D.new()
	_sensor_collision_shape.shape = _sensor_circle_shape
	_interaction_sensor.add_child(_sensor_collision_shape)


func _configure_caption_label() -> void:
	_caption_label = Label.new()
	_caption_label.name = "CaptionLabel"
	_caption_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption_label.add_theme_font_size_override("font_size", 13)
	_caption_label.add_theme_color_override("font_color", Color(0.95, 0.96, 0.92, 1.0))
	_caption_label.add_theme_color_override("font_outline_color", Color(0.05, 0.06, 0.08, 0.95))
	_caption_label.add_theme_constant_override("outline_size", 3)
	add_child(_caption_label)


func _update_geometry() -> void:
	if _circle_shape != null:
		_circle_shape.radius = _tile_size_px * DEFAULT_BODY_RADIUS_RATIO
	if _sensor_circle_shape != null:
		_sensor_circle_shape.radius = _tile_size_px * DEFAULT_SENSOR_RADIUS_RATIO
	if _caption_label != null:
		_caption_label.custom_minimum_size = Vector2(140.0, 20.0)
		_caption_label.position = Vector2(-70.0, -_tile_size_px * 0.82)


func _update_caption() -> void:
	if _caption_label == null:
		return
	var role_badge := "*" if is_local_body else ""
	var offline_badge := "" if is_participant_connected else " [offline]"
	var item_badge := " [%d]" % total_inventory_items if total_inventory_items > 0 else ""
	var label_title := display_name if not display_name.is_empty() else participant_id
	_caption_label.text = "%s%s%s%s" % [role_badge, label_title, item_badge, offline_badge]


func _body_fill_color() -> Color:
	if not is_participant_connected:
		return Color(0.42, 0.46, 0.52, 0.88)
	if is_local_body:
		return Color(0.86, 0.68, 0.25, 1.0)
	return Color(0.25, 0.66, 0.78, 1.0)


func _body_rim_color() -> Color:
	if not is_participant_connected:
		return Color(0.72, 0.75, 0.8, 0.9)
	if is_local_body:
		return Color(0.98, 0.93, 0.72, 1.0)
	return Color(0.78, 0.94, 0.98, 1.0)


static func _sum_inventory(items: Dictionary) -> int:
	var total := 0
	for raw_key in items.keys():
		var parsed := GreyboxWorld.integral_value(items.get(raw_key, 0))
		if bool(parsed.get("ok", false)) and int(parsed.get("value", 0)) > 0:
			total += int(parsed.get("value", 0))
	return total
