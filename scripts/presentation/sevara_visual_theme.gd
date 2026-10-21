class_name SevaraVisualTheme
extends RefCounted
## Hybrid PBR + Painterly 2.5D visual theme and CanvasTexture loader for P1.
##
## Loads seamless ground/riverbed/masonry textures with normal maps from
## `res://assets/textures/sevara_p1/`, calculates sun angle and ambient mood
## from `WorldClock`, and renders the orthographic 55-60 degree Sevara valley
## layers and 6.5-7 head character silhouettes without mutating `WorldState`.

const TEXTURE_DIR := "res://assets/textures/sevara_p1"
const CAMERA_ZOOM_PRESETS := [0.65, 1.0, 1.45]

static var _cached_textures: Dictionary = {}


static func load_canvas_texture(base_name: String, include_normals: bool = true) -> Texture2D:
	var cache_key := "%s:%s" % [base_name, "n" if include_normals else "d"]
	if _cached_textures.has(cache_key):
		var cached: Variant = _cached_textures[cache_key]
		if cached is Texture2D:
			return cached as Texture2D

	var diffuse_path := "%s/%s.png" % [TEXTURE_DIR, base_name]
	if not ResourceLoader.exists(diffuse_path):
		return null
	var diffuse := ResourceLoader.load(diffuse_path) as Texture2D
	if diffuse == null:
		return null

	if not include_normals:
		_cached_textures[cache_key] = diffuse
		return diffuse

	var normal_path := "%s/%s_normal.png" % [TEXTURE_DIR, base_name]
	var canvas_tex := CanvasTexture.new()
	canvas_tex.diffuse_texture = diffuse
	if ResourceLoader.exists(normal_path):
		var normal := ResourceLoader.load(normal_path) as Texture2D
		if normal != null:
			canvas_tex.normal_texture = normal
	_cached_textures[cache_key] = canvas_tex
	return canvas_tex


static func lighting_for_hour(hour_of_day: int) -> Dictionary:
	var hour := posmod(hour_of_day, 24)
	if hour >= 5 and hour <= 10:
		return {
			"phase": "morning",
			"ambient": Color(0.95, 0.91, 0.84, 1.0),
			"shadow_offset": Vector2(-0.55, 0.32),
			"shadow_alpha": 0.42,
			"fire_glow": 0.35,
		}
	if hour >= 11 and hour <= 15:
		return {
			"phase": "midday",
			"ambient": Color(1.0, 0.99, 0.96, 1.0),
			"shadow_offset": Vector2(-0.18, 0.22),
			"shadow_alpha": 0.34,
			"fire_glow": 0.18,
		}
	if hour >= 16 and hour <= 20:
		return {
			"phase": "evening",
			"ambient": Color(0.96, 0.78, 0.62, 1.0),
			"shadow_offset": Vector2(0.62, 0.34),
			"shadow_alpha": 0.48,
			"fire_glow": 0.75,
		}
	return {
		"phase": "night",
		"ambient": Color(0.46, 0.56, 0.68, 1.0),
		"shadow_offset": Vector2(0.28, 0.26),
		"shadow_alpha": 0.54,
		"fire_glow": 1.0,
	}


static func npc_visual_palette(npc_id: String) -> Dictionary:
	match npc_id:
		"sarela":
			return {
				"cloak": Color(0.20, 0.34, 0.25, 1.0),
				"tunic": Color(0.72, 0.67, 0.56, 1.0),
				"trim": Color(0.84, 0.68, 0.32, 1.0),
				"prop": "staff",
			}
		"tovan":
			return {
				"cloak": Color(0.27, 0.33, 0.38, 1.0),
				"tunic": Color(0.52, 0.41, 0.30, 1.0),
				"trim": Color(0.64, 0.74, 0.78, 1.0),
				"prop": "hook",
			}
		"mavena":
			return {
				"cloak": Color(0.36, 0.43, 0.24, 1.0),
				"tunic": Color(0.76, 0.72, 0.62, 1.0),
				"trim": Color(0.62, 0.76, 0.38, 1.0),
				"prop": "herbs",
			}
		"selima":
			return {
				"cloak": Color(0.74, 0.70, 0.61, 1.0),
				"tunic": Color(0.48, 0.38, 0.30, 1.0),
				"trim": Color(0.86, 0.56, 0.36, 1.0),
				"prop": "tablet",
			}
		"ruvet":
			return {
				"cloak": Color(0.44, 0.29, 0.21, 1.0),
				"tunic": Color(0.60, 0.52, 0.42, 1.0),
				"trim": Color(0.78, 0.58, 0.34, 1.0),
				"prop": "axe",
			}
		_:
			return {
				"cloak": Color(0.34, 0.38, 0.31, 1.0),
				"tunic": Color(0.66, 0.61, 0.52, 1.0),
				"trim": Color(0.76, 0.70, 0.48, 1.0),
				"prop": "satchel",
			}


static func draw_chunk_landscape(
	canvas: CanvasItem,
	width_tiles: int,
	height_tiles: int,
	tile_size_px: float,
	basin_summary: Dictionary,
	hour_of_day: int,
	graphics_profile: Dictionary
) -> void:
	var quality := String(graphics_profile.get("texture_quality", "high"))
	var field_size := Vector2(float(width_tiles), float(height_tiles)) * tile_size_px
	var field_rect := Rect2(Vector2.ZERO, field_size)
	if quality == "greybox":
		canvas.draw_rect(field_rect, Color(0.11, 0.14, 0.12, 1.0), true)
		return

	var include_normals := quality == "medium" or quality == "high"
	var light := lighting_for_hour(hour_of_day)
	var ambient: Color = light.get("ambient", Color.WHITE)
	var chunk_clean_tex := load_canvas_texture("chunk_nivara_clean", include_normals)
	var chunk_silted_tex := load_canvas_texture("chunk_nivara_silted_dusk", false)
	var avg_silt := float(basin_summary.get("average_silt_load", 0.28))
	var kevalu_wild := bool(basin_summary.get("any_kevalu_wild", false))
	var phase := String(light.get("phase", "morning"))

	if chunk_clean_tex != null:
		canvas.draw_texture_rect(field_rect, chunk_clean_tex, false, ambient)
		if chunk_silted_tex != null:
			var silt_blend := clampf((avg_silt - 0.24) / 0.42, 0.0, 1.0)
			if kevalu_wild:
				silt_blend = maxf(silt_blend, 0.65)
			if phase == "evening" or phase == "night":
				silt_blend = maxf(silt_blend, 0.55)
			if silt_blend > 0.02:
				canvas.draw_texture_rect(
					field_rect, chunk_silted_tex, false, Color(1.0, 1.0, 1.0, silt_blend)
				)
		return

	var meadow_tex := load_canvas_texture("tex_meadow_moss_and_snow", include_normals)
	var mud_tex := load_canvas_texture("tex_spring_mud_and_silt", include_normals)
	var pebble_tex := load_canvas_texture("tex_riverbed_pebbles", include_normals)
	var stone_tex := load_canvas_texture("tex_stone_and_timber", include_normals)

	if meadow_tex != null:
		canvas.draw_texture_rect(field_rect, meadow_tex, true, ambient)
	else:
		canvas.draw_rect(field_rect, Color(0.22, 0.28, 0.19, 1.0) * ambient, true)

	var courtyard_rect := Rect2(
		Vector2(10.0, 8.0) * tile_size_px, Vector2(12.0, 9.0) * tile_size_px
	)
	if mud_tex != null:
		canvas.draw_texture_rect(courtyard_rect, mud_tex, true, ambient)

	var channel_rect := Rect2(
		Vector2(13.0, 0.0) * tile_size_px, Vector2(4.5, float(height_tiles)) * tile_size_px
	)
	if stone_tex != null:
		canvas.draw_texture_rect(channel_rect.grow(tile_size_px * 0.45), stone_tex, true, ambient)
	if pebble_tex != null:
		canvas.draw_texture_rect(channel_rect, pebble_tex, true, ambient)

	var water_color := Color(0.18, 0.36, 0.42, 0.62).lerp(
		Color(0.46, 0.31, 0.20, 0.84), clampf(avg_silt * 1.15, 0.0, 1.0)
	)
	canvas.draw_rect(channel_rect, water_color * ambient, true)

	var sluice_rect := Rect2(Vector2(12.8, 10.6) * tile_size_px, Vector2(4.9, 1.1) * tile_size_px)
	canvas.draw_rect(sluice_rect, Color(0.32, 0.23, 0.16, 0.96) * ambient, true)
	canvas.draw_rect(sluice_rect, Color(0.58, 0.45, 0.31, 0.95) * ambient, false, 2.0)

	var kevar_center := Vector2(25.5, 5.5) * tile_size_px
	canvas.draw_circle(kevar_center, tile_size_px * 2.2, Color(0.18, 0.20, 0.23, 0.92) * ambient)
	canvas.draw_circle(kevar_center, tile_size_px * 1.5, Color(0.16, 0.28, 0.33, 0.88) * ambient)
	if bool(basin_summary.get("any_kevalu_wild", false)):
		canvas.draw_arc(
			kevar_center, tile_size_px * 1.85, 0.0, TAU, 32, Color(0.78, 0.77, 0.72, 0.85), 2.5
		)


static func draw_humanoid_6_5_heads(
	canvas: CanvasItem,
	tile_size_px: float,
	palette: Dictionary,
	facing: Vector2,
	is_local: bool,
	vitals: Dictionary,
	hour_of_day: int
) -> void:
	var light := lighting_for_hour(hour_of_day)
	var shadow_offset: Vector2 = light.get("shadow_offset", Vector2(-0.4, 0.28))
	var shadow_alpha := float(light.get("shadow_alpha", 0.4))
	var h := tile_size_px * 0.92
	var head_r := h / 6.8 * 0.52

	canvas.draw_circle(
		shadow_offset * (tile_size_px * 0.42) + Vector2(0.0, tile_size_px * 0.18),
		tile_size_px * 0.28,
		Color(0.02, 0.03, 0.04, shadow_alpha)
	)

	var cloak_color: Color = palette.get("cloak", Color(0.34, 0.40, 0.28, 1.0))
	var tunic_color: Color = palette.get("tunic", Color(0.68, 0.62, 0.52, 1.0))
	var trim_color: Color = palette.get("trim", Color(0.86, 0.68, 0.28, 1.0))
	var wetness := float(vitals.get("wetness", 0.0))
	if wetness > 20.0:
		cloak_color = cloak_color.darkened(clampf(wetness / 180.0, 0.0, 0.38))

	canvas.draw_rect(
		Rect2(Vector2(-head_r * 1.1, h * 0.08), Vector2(head_r * 0.85, h * 0.26)),
		Color(0.24, 0.17, 0.12, 1.0),
		true
	)
	canvas.draw_rect(
		Rect2(Vector2(head_r * 0.25, h * 0.08), Vector2(head_r * 0.85, h * 0.26)),
		Color(0.24, 0.17, 0.12, 1.0),
		true
	)

	var cloak_pts := PackedVector2Array(
		[
			Vector2(-head_r * 1.9, -h * 0.34),
			Vector2(head_r * 1.9, -h * 0.34),
			Vector2(head_r * 2.3, h * 0.14),
			Vector2(-head_r * 2.3, h * 0.14),
		]
	)
	canvas.draw_colored_polygon(cloak_pts, cloak_color)
	canvas.draw_rect(
		Rect2(Vector2(-head_r * 1.25, -h * 0.30), Vector2(head_r * 2.5, h * 0.36)),
		tunic_color,
		true
	)
	canvas.draw_line(
		Vector2(-head_r * 1.3, -h * 0.10), Vector2(head_r * 1.3, -h * 0.10), trim_color, 2.0
	)

	var head_center := Vector2(0.0, -h * 0.44)
	canvas.draw_circle(head_center, head_r * 1.15, cloak_color.darkened(0.15))
	canvas.draw_circle(
		head_center + facing.normalized() * (head_r * 0.22),
		head_r * 0.88,
		Color(0.82, 0.69, 0.58, 1.0)
	)

	if is_local:
		canvas.draw_arc(Vector2(0.0, h * 0.18), tile_size_px * 0.34, 0.0, TAU, 28, trim_color, 2.0)
	if float(vitals.get("body_warmth", 75.0)) < 45.0:
		canvas.draw_circle(
			head_center + facing.normalized() * (head_r * 1.4),
			head_r * 0.55,
			Color(0.88, 0.93, 0.96, 0.45)
		)
