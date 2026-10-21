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
	var diffuse := _load_texture_2d(diffuse_path)
	if diffuse == null:
		return null

	if not include_normals:
		_cached_textures[cache_key] = diffuse
		return diffuse

	var normal_path := "%s/%s_normal.png" % [TEXTURE_DIR, base_name]
	var canvas_tex := CanvasTexture.new()
	canvas_tex.diffuse_texture = diffuse
	var normal := _load_texture_2d(normal_path)
	if normal != null:
		canvas_tex.normal_texture = normal
	_cached_textures[cache_key] = canvas_tex
	return canvas_tex


static func _load_texture_2d(res_path: String) -> Texture2D:
	var abs_path := ProjectSettings.globalize_path(res_path)
	if FileAccess.file_exists(abs_path):
		var img := Image.load_from_file(abs_path)
		if img != null and not img.is_empty():
			return ImageTexture.create_from_image(img)
	if ResourceLoader.exists(res_path):
		var res: Resource = ResourceLoader.load(res_path)
		if res is Texture2D:
			return res as Texture2D
	return null


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


static func npc_display_tag(npc_id: String) -> String:
	match npc_id:
		"sarela":
			return "Сарела · Вождь"
		"tovan":
			return "Тован · Шлюз"
		"ilune":
			return "Илуне · Мулане"
		"mavena":
			return "Мавена · Травница"
		"evaren":
			return "Эварен · Хераво"
		"selima":
			return "Селима · Хроника"
		"tobren":
			return "Тобрен · Кевар"
		"ruvet":
			return "Рувет · Лесоруб"
		_:
			return npc_id


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
	var ambient := _color_or(light.get("ambient"), Color.WHITE)
	var meadow_tex := load_canvas_texture("tex_meadow_moss_and_snow", include_normals)
	var outer_rect := field_rect.grow(tile_size_px * 18.0)
	if meadow_tex != null:
		canvas.draw_texture_rect(meadow_tex, outer_rect, true, ambient.darkened(0.18))
	else:
		canvas.draw_rect(outer_rect, Color(0.16, 0.21, 0.15, 1.0) * ambient, true)

	var chunk_clean_tex := load_canvas_texture("chunk_nivara_clean", include_normals)
	var chunk_silted_tex := load_canvas_texture("chunk_nivara_silted_dusk", false)
	var wetland: Variant = basin_summary.get("mulane_wetland", {})
	var channel: Variant = basin_summary.get("nivarel_channel", {})
	var avg_silt := (
		float((wetland as Dictionary).get("silt_load", 0.28))
		if typeof(wetland) == TYPE_DICTIONARY
		else 0.28
	)
	var kevalu_wild := (
		float((channel as Dictionary).get("kevalu_wild_biomass", 0.0)) > 0.05
		if typeof(channel) == TYPE_DICTIONARY
		else false
	)
	var phase := String(light.get("phase", "morning"))

	if chunk_clean_tex != null:
		canvas.draw_texture_rect(chunk_clean_tex, field_rect, false, ambient)
		if chunk_silted_tex != null:
			var silt_blend := clampf((avg_silt - 0.24) / 0.42, 0.0, 1.0)
			if kevalu_wild:
				silt_blend = maxf(silt_blend, 0.65)
			if phase == "evening" or phase == "night":
				silt_blend = maxf(silt_blend, 0.55)
			if silt_blend > 0.02:
				canvas.draw_texture_rect(
					chunk_silted_tex, field_rect, false, Color(1.0, 1.0, 1.0, silt_blend)
				)
		return

	if meadow_tex != null:
		canvas.draw_texture_rect(meadow_tex, field_rect, true, ambient)
	else:
		canvas.draw_rect(field_rect, Color(0.22, 0.28, 0.19, 1.0) * ambient, true)


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
	var shadow_offset := _vec2_or(light.get("shadow_offset"), Vector2(-0.4, 0.28))
	var shadow_alpha := float(light.get("shadow_alpha", 0.4))
	var h := tile_size_px * 0.92
	var head_r := h / 6.8 * 0.52

	canvas.draw_circle(
		shadow_offset * (tile_size_px * 0.42) + Vector2(0.0, tile_size_px * 0.18),
		tile_size_px * 0.28,
		Color(0.02, 0.03, 0.04, shadow_alpha)
	)

	var cloak_color := _color_or(palette.get("cloak"), Color(0.34, 0.40, 0.28, 1.0))
	var tunic_color := _color_or(palette.get("tunic"), Color(0.68, 0.62, 0.52, 1.0))
	var trim_color := _color_or(palette.get("trim"), Color(0.86, 0.68, 0.28, 1.0))
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


static func _color_or(raw: Variant, fallback: Color) -> Color:
	if typeof(raw) == TYPE_COLOR:
		return raw as Color
	return fallback


static func _vec2_or(raw: Variant, fallback: Vector2) -> Vector2:
	if typeof(raw) == TYPE_VECTOR2:
		return raw as Vector2
	return fallback
