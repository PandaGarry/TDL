shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D tex_meadow : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_meadow_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_mud : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_mud_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_pebbles : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_pebbles_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_stone : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_stone_normal : hint_normal, filter_linear_mipmap, repeat_enable;

uniform float uv_scale : hint_range(1.0, 48.0) = 16.0;
uniform float silt_stain : hint_range(0.0, 1.0) = 0.18;
uniform float wetness_boost : hint_range(0.0, 1.0) = 0.24;

varying vec3 v_world_pos;
varying vec3 v_world_normal;
varying vec4 v_weights;
varying vec2 v_path_height;

float hash21(vec2 p) {
	p = fract(p * vec2(127.1, 311.7));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash21(i), hash21(i + vec2(1.0, 0.0)), u.x),
		mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), u.x),
		u.y
	);
}

float fbm3(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	mat2 rot = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));
	for (int i = 0; i < 3; i++) {
		v += a * vnoise(p);
		p = rot * p * 2.04;
		a *= 0.5;
	}
	return v;
}

vec4 triplanar_color(sampler2D samp, vec3 wpos, vec3 wnorm, float scale) {
	vec3 blend = abs(wnorm);
	blend = max(blend - 0.2, 0.0001);
	blend /= (blend.x + blend.y + blend.z);
	vec4 cx = texture(samp, wpos.zy * scale);
	vec4 cy = texture(samp, wpos.xz * scale);
	vec4 cz = texture(samp, wpos.xy * scale);
	return cx * blend.x + cy * blend.y + cz * blend.z;
}

vec3 triplanar_normal(sampler2D samp, vec3 wpos, vec3 wnorm, float scale) {
	vec3 blend = abs(wnorm);
	blend = max(blend - 0.2, 0.0001);
	blend /= (blend.x + blend.y + blend.z);
	vec3 nx = texture(samp, wpos.zy * scale).rgb;
	vec3 ny = texture(samp, wpos.xz * scale).rgb;
	vec3 nz = texture(samp, wpos.xy * scale).rgb;
	return normalize(nx * blend.x + ny * blend.y + nz * blend.z);
}

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_weights = COLOR;
	v_path_height = UV2;
}

void fragment() {
	vec2 tiled_uv = v_world_pos.xz * 0.22;
	float macro_n = fbm3(v_world_pos.xz * 0.038);
	float mid_n = fbm3(v_world_pos.xz * 0.14 + vec2(3.7, 9.1));
	float micro_n = vnoise(v_world_pos.xz * 1.15);

	float w_mud = clamp(v_weights.r, 0.0, 1.0);
	float w_pebbles = clamp(v_weights.g, 0.0, 1.0);
	float w_stone_v = clamp(v_weights.b, 0.0, 1.0);
	float path_mask = clamp(v_path_height.x, 0.0, 1.0);

	float slope = 1.0 - clamp(v_world_normal.y, 0.0, 1.0);
	float cliff_mask = clamp(smoothstep(0.24, 0.50, slope) + w_stone_v * 0.55, 0.0, 1.0);

	// 1. Rich emerald & olive-gold valley meadow
	vec3 meadow_tex = texture(tex_meadow, tiled_uv).rgb;
	float tex_luma = clamp(dot(meadow_tex, vec3(0.3, 0.59, 0.11)), 0.25, 0.72);
	vec3 meadow_lush = mix(vec3(0.16, 0.33, 0.12), vec3(0.30, 0.48, 0.18), macro_n);
	meadow_lush = mix(meadow_lush, vec3(0.38, 0.48, 0.20), smoothstep(0.55, 0.82, mid_n) * 0.42);
	vec3 c_meadow = meadow_lush * (0.76 + tex_luma * 0.48) * (0.92 + 0.16 * micro_n);

	// 2. Riverbank mud, wetland humus & silt
	vec3 mud_tex = texture(tex_mud, tiled_uv * 1.15).rgb;
	vec3 mud_col = mix(vec3(0.24, 0.19, 0.14), vec3(0.34, 0.29, 0.21), clamp(silt_stain, 0.0, 1.0));
	vec3 c_mud = mix(mud_col, mud_tex * 0.75, 0.42) * (0.88 + 0.24 * mid_n);

	// 3. Riverbed pebbles & cobble shore
	vec3 peb_tex = texture(tex_pebbles, tiled_uv * 1.4).rgb;
	vec3 c_pebbles = mix(peb_tex * 0.85, vec3(0.38, 0.40, 0.42), 0.35);

	// 4. Triplanar cliff granite & mountain ridges
	vec3 rock_tri = triplanar_color(tex_stone, v_world_pos, v_world_normal, 0.18).rgb;
	vec3 granite = mix(vec3(0.34, 0.36, 0.39), vec3(0.48, 0.49, 0.50), mid_n);
	vec3 c_cliff = mix(granite, rock_tri * 0.88, 0.48);

	// 5. Settlement courtyard & worn dirt-cobble footpath
	vec3 c_path = mix(vec3(0.42, 0.36, 0.28), c_pebbles * 1.06, smoothstep(0.35, 0.72, micro_n));

	// Combine layers organically
	vec3 albedo = c_meadow;
	albedo = mix(albedo, c_mud, clamp(w_mud * 0.88, 0.0, 1.0));
	albedo = mix(albedo, c_pebbles, clamp(w_pebbles * 0.90, 0.0, 1.0));
	albedo = mix(albedo, c_path, clamp(path_mask * (1.0 - w_pebbles * 0.8), 0.0, 0.82));
	albedo = mix(albedo, c_cliff, cliff_mask);

	// High mountain spring snow only on high Toramek crags (y > 3.8m)
	float high_snow = smoothstep(3.8, 6.2, v_world_pos.y) * smoothstep(0.35, 0.75, macro_n) * (1.0 - slope * 0.7);
	albedo = mix(albedo, vec3(0.84, 0.89, 0.93), clamp(high_snow, 0.0, 0.78));

	// Blend normal maps
	vec3 n_meadow = texture(tex_meadow_normal, tiled_uv).rgb;
	vec3 n_mud = texture(tex_mud_normal, tiled_uv * 1.15).rgb;
	vec3 n_pebbles = texture(tex_pebbles_normal, tiled_uv * 1.4).rgb;
	vec3 n_stone = triplanar_normal(tex_stone_normal, v_world_pos, v_world_normal, 0.24);
	vec3 blended_norm = normalize(
		mix(mix(mix(n_meadow, n_mud, w_mud), n_pebbles, max(w_pebbles, path_mask * 0.6)), n_stone, cliff_mask)
	);

	float shore_wet = clamp((w_pebbles * 0.65 + w_mud * 0.75) * (0.55 + wetness_boost * 0.5), 0.0, 0.82);
	albedo = mix(albedo, albedo * 0.72, shore_wet * 0.45);

	ALBEDO = albedo;
	NORMAL_MAP = blended_norm;
	NORMAL_MAP_DEPTH = 0.78;
	ROUGHNESS = clamp(mix(0.88, 0.40, shore_wet), 0.28, 0.95);
	SPECULAR = mix(0.14, 0.36, shore_wet);
}
