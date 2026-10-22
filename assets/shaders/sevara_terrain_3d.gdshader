shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// 3D Terrain shader for Sevara Valley (Godot 4.7 GL Compatibility + Forward+).
// Blends riverbed pebbles, spring silt/mud, meadow moss/grass, granite rock
// and high-altitude snow using world position, slope normal and vertex colors:
// COLOR.r = river/channel weight
// COLOR.g = meadow/grass weight
// COLOR.b = rock/cliff weight
// COLOR.a = snow/crest weight

uniform sampler2D tex_pebbles : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_pebbles_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_mud_silt : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_mud_silt_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_meadow : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_meadow_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_rock : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_rock_normal : hint_normal, filter_linear_mipmap, repeat_enable;

uniform float uv_scale : hint_range(0.02, 1.0) = 0.14;
uniform float silt_load : hint_range(0.0, 1.0) = 0.25;
uniform float kevalu_contamination : hint_range(0.0, 1.0) = 0.0;

varying vec3 v_world_pos;
varying vec3 v_world_normal;
varying vec4 v_biome_weights;

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_normal = normalize((MODEL_NORMAL_MATRIX * NORMAL));
	v_biome_weights = COLOR;
}

void fragment() {
	vec2 uv_main = v_world_pos.xz * uv_scale;
	vec2 uv_detail = v_world_pos.xz * (uv_scale * 2.35);

	vec3 col_pebbles = texture(tex_pebbles, uv_detail).rgb * vec3(0.88, 0.90, 0.92);
	vec3 col_mud = texture(tex_mud_silt, uv_main).rgb * vec3(0.95, 0.78, 0.64);
	vec3 col_meadow = texture(tex_meadow, uv_main).rgb * vec3(0.82, 0.94, 0.76);
	vec3 col_rock = texture(tex_rock, uv_main * 0.85).rgb * vec3(0.76, 0.78, 0.82);
	vec3 col_snow = mix(col_meadow, vec3(0.92, 0.95, 0.98), 0.82);

	vec3 n_pebbles = texture(tex_pebbles_normal, uv_detail).rgb;
	vec3 n_mud = texture(tex_mud_silt_normal, uv_main).rgb;
	vec3 n_meadow = texture(tex_meadow_normal, uv_main).rgb;
	vec3 n_rock = texture(tex_rock_normal, uv_main * 0.85).rgb;

	float slope = 1.0 - clamp(v_world_normal.y, 0.0, 1.0);
	float w_river = clamp(v_biome_weights.r, 0.0, 1.0);
	float w_rock = clamp(max(v_biome_weights.b, smoothstep(0.26, 0.55, slope)), 0.0, 1.0);
	float w_snow = clamp(v_biome_weights.a * (1.0 - smoothstep(0.45, 0.75, slope)), 0.0, 1.0);
	float w_meadow = clamp(1.0 - max(w_river, max(w_rock, w_snow)), 0.0, 1.0);

	float mud_mix = clamp((silt_load - 0.18) * 1.45, 0.15, 0.92);
	vec3 river_albedo = mix(col_pebbles, col_mud, mud_mix);
	vec3 river_normal = mix(n_pebbles, n_mud, mud_mix);

	// Subtle cobbled path warmth around the settlement courtyard and bridge approaches
	float path_mask = clamp(v_biome_weights.g, 0.0, 1.0);
	vec3 meadow_or_path = mix(col_meadow, mix(col_pebbles, col_mud, 0.38), path_mask * 0.78);
	vec3 meadow_or_path_n = mix(n_meadow, n_pebbles, path_mask * 0.70);

	vec3 albedo = meadow_or_path * w_meadow
		+ river_albedo * w_river
		+ col_rock * w_rock
		+ col_snow * w_snow;

	vec3 blended_n = normalize(
		meadow_or_path_n * w_meadow
		+ river_normal * w_river
		+ n_rock * (w_rock + w_snow * 0.5)
	);

	// Ash-pale dry mineral crust near Kevar when wild Kevalu spreads
	if (kevalu_contamination > 0.02 && v_world_pos.x > 6.0 && v_world_pos.z < 2.0) {
		float dist_kevar = length(v_world_pos.xz - vec2(18.0, -11.0));
		float k_mask = clamp((1.0 - dist_kevar / 22.0) * kevalu_contamination * 1.4, 0.0, 0.72);
		albedo = mix(albedo, vec3(0.78, 0.77, 0.73), k_mask);
	}

	ALBEDO = albedo;
	NORMAL_MAP = blended_n;
	NORMAL_MAP_DEPTH = 1.15;
	ROUGHNESS = mix(0.86, 0.36, w_river * 0.85);
	SPECULAR = mix(0.22, 0.55, w_river);
}
