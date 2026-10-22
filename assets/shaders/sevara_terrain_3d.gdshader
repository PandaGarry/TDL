shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// 3D Terrain Shader for the expanded Sevara Valley (160 x 120 m).
// Combines Sevara PBR textures, procedural rock strata on steep cliffs (inspired by Fern),
// Voronoi cobblestone/flagstone paths, wet shoreline swash, spring snow patches,
// and drifting cloud shadows.
// Vertex COLOR channels:
//   R = mud / silt weight
//   G = riverbed pebble / shore weight
//   B = cliff stone weight
//   A = spring snow / frost weight
// Vertex UV2 channels:
//   x = path / terrace flagstone weight (0..1)
//   y = height above nearest water (meters)

uniform sampler2D tex_meadow : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_meadow_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_mud : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_mud_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_pebbles : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_pebbles_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_stone : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_stone_normal : hint_normal, filter_linear_mipmap, repeat_enable;

uniform float uv_scale : hint_range(1.0, 64.0) = 24.0;
uniform float silt_stain : hint_range(0.0, 1.0) = 0.15;
uniform float moisture_gloss : hint_range(0.0, 1.0) = 0.55;
uniform float cloud_shadow_strength : hint_range(0.0, 1.0) = 0.32;
uniform vec2 wind_direction = vec2(0.92, 0.38);

varying vec3 v_world_pos;
varying vec3 v_world_normal;
varying vec2 v_path_water;
varying float v_cloud;
varying float v_wet_sheen;

vec2 hash2(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p) * 43758.5453123);
}

float hash1(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash1(i + vec2(0.0, 0.0)), hash1(i + vec2(1.0, 0.0)), u.x),
		mix(hash1(i + vec2(0.0, 1.0)), hash1(i + vec2(1.0, 1.0)), u.x),
		u.y
	);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * value_noise(p);
		p = p * 2.03 + vec2(17.1, 31.7);
		a *= 0.5;
	}
	return v;
}

float voronoi_edge(vec2 x) {
	vec2 n = floor(x);
	vec2 f = fract(x);
	vec2 mg = vec2(0.0);
	vec2 mr = vec2(0.0);
	float md = 8.0;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 g = vec2(float(i), float(j));
			vec2 r = g + hash2(n + g) - f;
			float d = dot(r, r);
			if (d < md) {
				md = d;
				mr = r;
				mg = g;
			}
		}
	}
	md = 8.0;
	for (int j = -2; j <= 2; j++) {
		for (int i = -2; i <= 2; i++) {
			vec2 g = mg + vec2(float(i), float(j));
			vec2 r = g + hash2(n + g) - f;
			if (dot(mr - r, mr - r) > 0.00001) {
				md = min(md, dot(0.5 * (mr + r), normalize(r - mr)));
			}
		}
	}
	return md;
}

float sample_cloud_shadow(vec2 world_xz, float time) {
	vec2 uv = world_xz * 0.018 - normalize(wind_direction) * time * 0.035;
	float n = value_noise(uv) * 0.7 + value_noise(uv * 2.3 + vec2(4.1, 2.7)) * 0.3;
	return smoothstep(0.52, 0.68, n) * cloud_shadow_strength;
}

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_path_water = UV2;
	v_cloud = sample_cloud_shadow(v_world_pos.xz, TIME);
}

void fragment() {
	vec2 wp = v_world_pos.xz;
	vec2 tiled_uv = wp * 0.14;
	float macro_n = fbm(wp * 0.055);
	float mid_n = value_noise(wp * 0.22 + vec2(3.7, 9.1));
	float fine_n = value_noise(wp * 1.15);

	float w_mud = clamp(COLOR.r + silt_stain * 0.24 * COLOR.g, 0.0, 1.0);
	float w_pebbles = clamp(COLOR.g, 0.0, 1.0);
	float steep_slope = 1.0 - smoothstep(0.52, 0.80, v_world_normal.y);
	float w_stone = clamp(max(COLOR.b, steep_slope), 0.0, 1.0);
	float w_snow = clamp(COLOR.a, 0.0, 1.0);
	float w_meadow = clamp(1.0 - max(max(w_mud, w_pebbles), w_stone * 0.85), 0.0, 1.0);

	float sum_w = max(w_meadow + w_mud + w_pebbles + w_stone, 0.001);
	w_meadow /= sum_w;
	w_mud /= sum_w;
	w_pebbles /= sum_w;
	w_stone /= sum_w;

	// Rich meadow color variation across the valley (lush emerald, warm clover, dark moss)
	vec3 meadow_tex = texture(tex_meadow, tiled_uv).rgb;
	vec3 meadow_lush = mix(vec3(0.18, 0.34, 0.14), vec3(0.32, 0.48, 0.20), macro_n);
	meadow_lush = mix(meadow_lush, vec3(0.42, 0.50, 0.22), smoothstep(0.55, 0.82, mid_n) * 0.45);
	vec3 col_meadow = mix(meadow_tex, meadow_lush, 0.52) * (0.90 + 0.20 * fine_n);

	vec3 col_mud = mix(texture(tex_mud, tiled_uv).rgb, vec3(0.34, 0.25, 0.17), 0.35) * (0.88 + 0.22 * mid_n);
	vec3 col_pebbles = mix(texture(tex_pebbles, tiled_uv * 1.25).rgb, vec3(0.42, 0.40, 0.36), 0.25);
	vec3 col_stone = texture(tex_stone, tiled_uv * 0.9).rgb;

	vec3 n_meadow = texture(tex_meadow_normal, tiled_uv).rgb;
	vec3 n_mud = texture(tex_mud_normal, tiled_uv).rgb;
	vec3 n_pebbles = texture(tex_pebbles_normal, tiled_uv * 1.25).rgb;
	vec3 n_stone = texture(tex_stone_normal, tiled_uv * 0.9).rgb;

	vec3 albedo = col_meadow * w_meadow + col_mud * w_mud + col_pebbles * w_pebbles + col_stone * w_stone;
	vec3 norm_map = normalize(n_meadow * w_meadow + n_mud * w_mud + n_pebbles * w_pebbles + n_stone * w_stone);

	// Procedural rock strata & moss ledges on steep Toramek cliffs
	if (steep_slope > 0.02) {
		float v = v_world_pos.y;
		float warp = value_noise(vec2(wp.x * 0.12 + wp.y * 0.08, v * 0.25));
		float layer_coord = (v + warp * 1.4) * 1.65;
		float fl = floor(layer_coord);
		float fr = fract(layer_coord);
		float lh = fract(sin(fl * 78.233) * 43758.5453);
		float ledge_prof = smoothstep(0.0, 0.22, fr) * (0.68 + 0.32 * fr);
		float crack_val = abs(value_noise(vec2(wp.x * 0.45 + lh * 2.0, v * 0.55)) - 0.5);
		float crack = 1.0 - smoothstep(0.0, 0.04, crack_val);

		vec3 cliff_col = mix(col_stone, vec3(0.38, 0.40, 0.43), 0.45) * (0.84 + lh * 0.22);
		cliff_col *= mix(0.58, 1.04, ledge_prof);
		cliff_col *= 1.0 - crack * 0.42;

		// Moss cushions on cliff ledges
		float ledge_top = smoothstep(0.76, 0.96, fr) * smoothstep(0.35, 0.72, macro_n);
		vec3 cliff_moss = vec3(0.24, 0.38, 0.16) * (0.85 + 0.3 * fine_n);
		cliff_col = mix(cliff_col, cliff_moss, clamp(ledge_top * 0.78, 0.0, 0.75));
		albedo = mix(albedo, cliff_col, steep_slope);
	}

	// Cobblestone / flagstone settlement paths and courtyard terrace
	float path_w = clamp(v_path_water.x + (mid_n - 0.5) * 0.18, 0.0, 1.0) * (1.0 - steep_slope);
	float path_mask = smoothstep(0.25, 0.68, path_w);
	if (path_mask > 0.01) {
		float edge_d = voronoi_edge(wp * 0.85 + vec2(mid_n, fine_n) * 0.25);
		float mortar = 1.0 - smoothstep(0.02, 0.07, edge_d);
		vec3 path_col = mix(col_stone * vec3(1.05, 0.98, 0.90), vec3(0.46, 0.41, 0.35), 0.45);
		path_col = mix(path_col, vec3(0.24, 0.22, 0.18), mortar * 0.55);
		albedo = mix(albedo, path_col, path_mask * 0.82);
	}

	// Wet shoreline darkening & subtle foam band along Nivarel and Mulane
	float above_water = v_path_water.y;
	float wet_band = 1.0 - smoothstep(0.0, 0.85, above_water);
	if (wet_band > 0.01) {
		albedo = mix(albedo, albedo * vec3(0.56, 0.58, 0.62), wet_band * 0.72);
	}

	// Spring snow patches on upper slopes and shaded hollows
	float snow_drift = smoothstep(0.42, 0.78, macro_n * 0.6 + fine_n * 0.4);
	float snow_mask = clamp(w_snow * (0.55 + 0.65 * snow_drift) * smoothstep(0.55, 0.88, v_world_normal.y), 0.0, 0.88);
	vec3 snow_col = mix(vec3(0.80, 0.86, 0.94), vec3(0.95, 0.97, 0.99), snow_drift);
	albedo = mix(albedo, snow_col, snow_mask);

	// Ochre silt deposit tint when soil erosion increases
	vec3 silt_tint = vec3(0.48, 0.35, 0.21);
	albedo = mix(albedo, silt_tint, w_mud * silt_stain * 0.42);

	float wetness = clamp(max(w_mud * 0.65 + w_pebbles * 0.45, wet_band * 0.85) * moisture_gloss, 0.0, 1.0);
	v_wet_sheen = wetness;

	ALBEDO = albedo;
	NORMAL_MAP = norm_map;
	NORMAL_MAP_DEPTH = mix(0.95, 1.35, w_stone + w_pebbles * 0.5);
	ROUGHNESS = clamp(mix(0.88, 0.26, wetness), 0.18, 0.96);
	SPECULAR = mix(0.18, 0.52, wetness);
}

void light() {
	float sun_vis = 1.0 - v_cloud;
	float ndl = clamp(dot(NORMAL, LIGHT), 0.0, 1.0);
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * ndl * sun_vis / PI;
	if (v_wet_sheen > 0.02) {
		vec3 hv = normalize(LIGHT + VIEW);
		float sp = pow(clamp(dot(NORMAL, hv), 0.0, 1.0), mix(24.0, 180.0, v_wet_sheen)) * v_wet_sheen * 0.45;
		SPECULAR_LIGHT += LIGHT_COLOR * ATTENUATION * sp * sun_vis;
	}
}
