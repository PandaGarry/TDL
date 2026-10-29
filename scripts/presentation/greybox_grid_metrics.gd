class_name GreyboxGridMetrics
extends RefCounted
## Spatial conversion and input-step metrics for the P0-F greybox view.
##
## Baseline spatial constants from `round12_baseline_lock.md`:
## - ecological cell = 32 m;
## - world chunk = 128 m (4x4 ecological cells).
## In the greybox grid one tile represents a 4 m step, so an ecological
## cell is 8x8 tiles and a world chunk is 32x32 tiles.

const DEFAULT_TILE_SIZE_PX := 48.0
const MIN_TILE_SIZE_PX := 16.0
const METERS_PER_TILE := 4.0
const TILES_PER_ECOCELL := 8
const TILES_PER_CHUNK := 32

const ACTION_MOVE_LEFT := &"move_left"
const ACTION_MOVE_RIGHT := &"move_right"
const ACTION_MOVE_UP := &"move_up"
const ACTION_MOVE_DOWN := &"move_down"
const ACTION_INTERACT := &"interact"
const ACTION_DEBUG_TOGGLE := &"debug_toggle"


static func sanitized_tile_size(tile_size_px: float = DEFAULT_TILE_SIZE_PX) -> float:
	if not is_finite(tile_size_px):
		return DEFAULT_TILE_SIZE_PX
	return maxf(tile_size_px, MIN_TILE_SIZE_PX)


static func tile_to_world_origin(
	tile: Vector2i, tile_size_px: float = DEFAULT_TILE_SIZE_PX
) -> Vector2:
	var resolved_size := sanitized_tile_size(tile_size_px)
	return Vector2(float(tile.x) * resolved_size, float(tile.y) * resolved_size)


static func tile_to_world_center(
	tile: Vector2i, tile_size_px: float = DEFAULT_TILE_SIZE_PX
) -> Vector2:
	var resolved_size := sanitized_tile_size(tile_size_px)
	return tile_to_world_origin(tile, resolved_size) + Vector2(resolved_size, resolved_size) * 0.5


static func world_to_tile(
	world_position: Vector2, tile_size_px: float = DEFAULT_TILE_SIZE_PX
) -> Vector2i:
	var resolved_size := sanitized_tile_size(tile_size_px)
	return Vector2i(
		int(floor(world_position.x / resolved_size)), int(floor(world_position.y / resolved_size))
	)


static func ecocell_for_tile(tile: Vector2i) -> Vector2i:
	return Vector2i(
		int(floor(float(tile.x) / float(TILES_PER_ECOCELL))),
		int(floor(float(tile.y) / float(TILES_PER_ECOCELL)))
	)


static func chunk_for_tile(tile: Vector2i) -> Vector2i:
	return Vector2i(
		int(floor(float(tile.x) / float(TILES_PER_CHUNK))),
		int(floor(float(tile.y) / float(TILES_PER_CHUNK)))
	)


static func field_pixel_size(
	width_tiles: int, height_tiles: int, tile_size_px: float = DEFAULT_TILE_SIZE_PX
) -> Vector2:
	var resolved_size := sanitized_tile_size(tile_size_px)
	return Vector2(
		float(maxi(width_tiles, 0)) * resolved_size, float(maxi(height_tiles, 0)) * resolved_size
	)


static func manhattan_distance(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)


static func direction_for_action(action_name: StringName) -> Vector2i:
	match action_name:
		ACTION_MOVE_LEFT:
			return Vector2i(-1, 0)
		ACTION_MOVE_RIGHT:
			return Vector2i(1, 0)
		ACTION_MOVE_UP:
			return Vector2i(0, -1)
		ACTION_MOVE_DOWN:
			return Vector2i(0, 1)
	return Vector2i.ZERO


static func is_move_action(action_name: StringName) -> bool:
	return direction_for_action(action_name) != Vector2i.ZERO
