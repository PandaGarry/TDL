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
uniform sampler2D tex_flagstone : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_flagstone_normal : hint_normal, filter_linear_mipmap, repeat_enable;

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

vec3 sample_dual_scale(sampler2D samp, vec2 wpos_xz, float scale_a, float blend_noise) {
	mat2 rot = mat2(vec2(0.7986, 0.6018), vec2(-0.6018, 0.7986));
	vec3 ca = texture(samp, wpos_xz * scale_a).rgb;
	vec3 cb = texture(samp, (rot * wpos_xz) * (scale_a * 0.43) + vec2(1.37, 2.91)).rgb;
	return mix(ca, cb, smoothstep(0.28, 0.72, blend_noise));
}

vec3 sample_dual_normal(sampler2D samp, vec2 wpos_xz, float scale_a, float blend_noise) {
	mat2 rot = mat2(vec2(0.7986, 0.6018), vec2(-0.6018, 0.7986));
	vec3 na = texture(samp, wpos_xz * scale_a).rgb * 2.0 - 1.0;
	vec3 nb = texture(samp, (rot * wpos_xz) * (scale_a * 0.43) + vec2(1.37, 2.91)).rgb * 2.0 - 1.0;
	vec3 n = normalize(mix(na, nb, smoothstep(0.28, 0.72, blend_noise)));
	return n * 0.5 + 0.5;
}

vec4 triplanar_color(sampler2D samp, vec3 wpos, vec3 wnorm, float scale) {
	vec3 blend = pow(abs(wnorm), vec3(3.5));
	blend /= max(blend.x + blend.y + blend.z, 0.0001);
	vec4 cx = texture(samp, wpos.zy * scale);
	vec4 cy = texture(samp, wpos.xz * scale);
	vec4 cz = texture(samp, wpos.xy * scale);
	return cx * blend.x + cy * blend.y + cz * blend.z;
}

vec3 triplanar_normal(sampler2D samp, vec3 wpos, vec3 wnorm, float scale) {
	vec3 blend = pow(abs(wnorm), vec3(3.5));
	blend /= max(blend.x + blend.y + blend.z, 0.0001);
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
	vec2 xz = v_world_pos.xz;
	float macro_n = fbm3(xz * 0.042);
	float mid_n = fbm3(xz * 0.16 + vec2(3.7, 9.1));
	float micro_n = vnoise(xz * 1.45);

	float w_mud = clamp(v_weights.r, 0.0, 1.0);
	float w_pebbles = clamp(v_weights.g, 0.0, 1.0);
	float w_stone_v = clamp(v_weights.b, 0.0, 1.0);
	float path_mask = clamp(v_path_height.x, 0.0, 1.0);

	float slope = 1.0 - clamp(v_world_normal.y, 0.0, 1.0);
	float cliff_mask = clamp(smoothstep(0.20, 0.46, slope) + w_stone_v * 0.65, 0.0, 1.0);

	// 1. Photogrammetric northern alpine meadow (anti-tiled dual-scale sampling)
	vec3 meadow_raw = sample_dual_scale(tex_meadow, xz, 0.28, macro_n);
	vec3 meadow_grade = mix(vec3(0.72, 0.74, 0.58), vec3(0.96, 0.88, 0.68), macro_n);
	meadow_grade = mix(meadow_grade, vec3(1.06, 0.88, 0.60), smoothstep(0.52, 0.82, mid_n) * 0.44);
	vec3 c_meadow = meadow_raw * meadow_grade * (0.82 + 0.16 * micro_n);

	// 2. Photogrammetric forest soil, gravel & riverbank mud
	vec3 mud_raw = sample_dual_scale(tex_mud, xz, 0.30, mid_n);
	vec3 mud_tint = mix(vec3(0.76, 0.72, 0.66), vec3(0.86, 0.78, 0.62), clamp(silt_stain, 0.0, 1.0));
	vec3 c_mud = mud_raw * mud_tint;

	// 3. Wet riverbed pebbles & shingle shore
	vec3 peb_raw = sample_dual_scale(tex_pebbles, xz, 0.34, mid_n);
	vec3 c_pebbles = peb_raw * 0.88;

	// 4. Mossy medieval flagstones & cobble path in settlement courtyard
	vec3 flag_raw = sample_dual_scale(tex_flagstone, xz, 0.32, macro_n);
	float flag_height = dot(flag_raw, vec3(0.33, 0.34, 0.33));
	// Blend flagstones with packed dirt path based on distance from settlement hearth (-13, -6)
	float village_core = 1.0 - smoothstep(6.0, 21.0, length(xz - vec2(-13.0, -6.0)));
	vec3 c_path = mix(c_mud * 0.94, flag_raw * 0.96, clamp(village_core * 0.82 + smoothstep(0.42, 0.68, flag_height) * 0.45, 0.0, 1.0));

	// 5. Stratified triplanar northern cliff rock
	vec3 rock_tri = triplanar_color(tex_stone, v_world_pos, v_world_normal, 0.20).rgb;
	vec3 c_cliff = rock_tri * mix(vec3(0.68, 0.72, 0.76), vec3(0.92, 0.90, 0.86), mid_n);

	// Height-modulated organic layer transitions
	float path_blend = clamp(path_mask * (1.0 - w_pebbles * 0.75) * smoothstep(0.15, 0.82, path_mask + (flag_height - 0.45) * 0.35), 0.0, 0.92);
	vec3 albedo = c_meadow;
	albedo = mix(albedo, c_mud, clamp(w_mud * 0.90, 0.0, 1.0));
	albedo = mix(albedo, c_path, path_blend);
	albedo = mix(albedo, c_pebbles, clamp(w_pebbles * 0.92, 0.0, 1.0));
	albedo = mix(albedo, c_cliff, cliff_mask);

	// High mountain spring snow on upper Toramek crags (y > 3.8m)
	float high_snow = smoothstep(3.8, 6.2, v_world_pos.y) * smoothstep(0.35, 0.75, macro_n) * (1.0 - slope * 0.7);
	albedo = mix(albedo, vec3(0.86, 0.90, 0.95), clamp(high_snow, 0.0, 0.78));

	// Dual-scale & triplanar normal maps
	vec3 n_meadow = sample_dual_normal(tex_meadow_normal, xz, 0.28, macro_n);
	vec3 n_mud = sample_dual_normal(tex_mud_normal, xz, 0.30, mid_n);
	vec3 n_flag = sample_dual_normal(tex_flagstone_normal, xz, 0.32, macro_n);
	vec3 n_pebbles = sample_dual_normal(tex_pebbles_normal, xz, 0.34, mid_n);
	vec3 n_stone = triplanar_normal(tex_stone_normal, v_world_pos, v_world_normal, 0.22);

	vec3 n_ground = mix(n_meadow, n_mud, w_mud);
	n_ground = mix(n_ground, mix(n_mud, n_flag, village_core * 0.8 + 0.2), path_blend);
	n_ground = mix(n_ground, n_pebbles, w_pebbles);
	vec3 blended_norm = normalize(mix(n_ground, n_stone, cliff_mask));

	float shore_wet = clamp((w_pebbles * 0.72 + w_mud * 0.75) * (0.55 + wetness_boost * 0.5), 0.0, 0.85);
	albedo = mix(albedo, albedo * 0.66, shore_wet * 0.52);

	ALBEDO = albedo;
	NORMAL_MAP = blended_norm;
	NORMAL_MAP_DEPTH = 1.28;
	ROUGHNESS = clamp(mix(0.86, 0.32, shore_wet), 0.24, 0.94);
	SPECULAR = mix(0.18, 0.42, shore_wet);
}
