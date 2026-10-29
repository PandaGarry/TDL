class_name SupplyCrateView
extends StaticBody2D
## 2D presentation node for `core:object/greybox_supply_crate`.
##
## SupplyCrateView mirrors the authoritative container and interactable
## components from WorldState. It uses PhysicsLayers.STRUCTURES_BIT and
## PhysicsLayers.INTERACTABLES_BIT and never mutates WorldState directly.

const DEFAULT_BOX_SIZE_RATIO := 0.72

var entity_id: int = -1
var definition_id: String = GreyboxWorld.OBJECT_DEFINITION_ID
var visual_profile: String = "core:visual/object_greybox_supply_crate"
var tile_position: Vector2i = Vector2i(-1, -1)
var item_definition_id: String = GreyboxWorld.DEFAULT_CONTAINER_ITEM_DEFINITION_ID
var item_display_name: String = ""
var remaining_count: int = 0
var verb: String = "take_one"
var adjacent_to_local_body: bool = false

var _tile_size_px: float = GreyboxGridMetrics.DEFAULT_TILE_SIZE_PX
var _collision_shape: CollisionShape2D
var _rectangle_shape: RectangleShape2D
var _caption_label: Label


func _init() -> void:
	_configure_physics_nodes()
	_configure_caption_label()


func _ready() -> void:
	_update_geometry()
	_update_caption()
	queue_redraw()


func apply_view_model(model: Dictionary, tile_size_px: float) -> void:
	_tile_size_px = GreyboxGridMetrics.sanitized_tile_size(tile_size_px)
	entity_id = int(GreyboxWorld.integral_value(model.get("entity_id", -1)).get("value", -1))
	definition_id = String(model.get("definition_id", GreyboxWorld.OBJECT_DEFINITION_ID))
	visual_profile = String(model.get("visual_profile", "core:visual/object_greybox_supply_crate"))
	var parsed_x := int(GreyboxWorld.integral_value(model.get("tile_x", 0)).get("value", 0))
	var parsed_y := int(GreyboxWorld.integral_value(model.get("tile_y", 0)).get("value", 0))
	tile_position = Vector2i(parsed_x, parsed_y)
	item_definition_id = String(
		model.get("item_definition_id", GreyboxWorld.DEFAULT_CONTAINER_ITEM_DEFINITION_ID)
	)
	item_display_name = String(model.get("item_display_name", item_definition_id))
	var parsed_count := int(
		GreyboxWorld.integral_value(model.get("remaining_count", 0)).get("value", 0)
	)
	remaining_count = maxi(parsed_count, 0)
	verb = String(model.get("verb", "take_one"))
	adjacent_to_local_body = bool(model.get("adjacent_to_local_body", false))
	name = "SupplyCrateView_%d" % entity_id
	position = GreyboxGridMetrics.tile_to_world_center(tile_position, _tile_size_px)
	_update_geometry()
	_update_caption()
	queue_redraw()


func can_interact_now() -> bool:
	return adjacent_to_local_body and remaining_count > 0 and verb == "take_one"


func caption_text() -> String:
	return _caption_label.text if _caption_label != null else ""


func view_summary() -> Dictionary:
	return {
		"entity_id": entity_id,
		"definition_id": definition_id,
		"visual_profile": visual_profile,
		"tile_x": tile_position.x,
		"tile_y": tile_position.y,
		"world_x": position.x,
		"world_y": position.y,
		"item_definition_id": item_definition_id,
		"item_display_name": item_display_name,
		"remaining_count": remaining_count,
		"verb": verb,
		"adjacent_to_local_body": adjacent_to_local_body,
		"can_interact_now": can_interact_now(),
		"collision_layer": collision_layer,
		"collision_mask": collision_mask,
	}


func _draw() -> void:
	var half_extent := (_tile_size_px * DEFAULT_BOX_SIZE_RATIO) * 0.5
	var rect := Rect2(Vector2(-half_extent, -half_extent), Vector2.ONE * (half_extent * 2.0))
	var shadow_rect := Rect2(rect.position + Vector2(2.0, 4.0), rect.size)
	draw_rect(shadow_rect, Color(0.02, 0.03, 0.04, 0.45), true)

	var fill_color := (
		Color(0.56, 0.39, 0.21, 1.0) if remaining_count > 0 else Color(0.32, 0.28, 0.25, 0.9)
	)
	var border_color := (
		Color(0.96, 0.84, 0.42, 1.0) if can_interact_now() else Color(0.82, 0.67, 0.46, 0.95)
	)
	draw_rect(rect, fill_color, true)
	draw_line(
		Vector2(-half_extent, 0.0), Vector2(half_extent, 0.0), Color(0.28, 0.19, 0.1, 0.85), 2.0
	)
	draw_rect(rect, border_color, false, 2.5 if can_interact_now() else 1.8)


func _configure_physics_nodes() -> void:
	collision_layer = PhysicsLayers.STRUCTURES_BIT | PhysicsLayers.INTERACTABLES_BIT
	collision_mask = 0

	_collision_shape = CollisionShape2D.new()
	_collision_shape.name = "CrateCollisionShape"
	_rectangle_shape = RectangleShape2D.new()
	_collision_shape.shape = _rectangle_shape
	add_child(_collision_shape)


func _configure_caption_label() -> void:
	_caption_label = Label.new()
	_caption_label.name = "CaptionLabel"
	_caption_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption_label.add_theme_font_size_override("font_size", 12)
	_caption_label.add_theme_color_override("font_color", Color(0.95, 0.92, 0.82, 1.0))
	_caption_label.add_theme_color_override("font_outline_color", Color(0.05, 0.06, 0.08, 0.95))
	_caption_label.add_theme_constant_override("outline_size", 3)
	add_child(_caption_label)


func _update_geometry() -> void:
	var box_size := _tile_size_px * DEFAULT_BOX_SIZE_RATIO
	if _rectangle_shape != null:
		_rectangle_shape.size = Vector2(box_size, box_size)
	if _caption_label != null:
		_caption_label.custom_minimum_size = Vector2(160.0, 34.0)
		_caption_label.position = Vector2(-80.0, _tile_size_px * 0.42)


func _update_caption() -> void:
	if _caption_label == null:
		return
	var title := item_display_name if not item_display_name.is_empty() else item_definition_id
	var count_label := (
		"%s: %d" % [title, remaining_count]
		if remaining_count > 0
		else "%s: %s" % [title, UiLocaleCatalog.translate_key("ui.greybox.crate_empty")]
	)
	if can_interact_now():
		_caption_label.text = (
			"%s\n%s" % [count_label, UiLocaleCatalog.translate_key("ui.greybox.interact_prompt")]
		)
	else:
		_caption_label.text = count_label
