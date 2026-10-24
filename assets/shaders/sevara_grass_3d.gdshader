shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

// Step 1 CBT Proving Ground 3D Grass & Roadside Turf Shader (v5):
// - Root color matches the rich moss/humus/verge ground palette underneath
// - Smooth hill-aligned normal (never inverted downward on backfaces)
// - Interactive player/NPC grass parting around `player_pos`
// - Clustered sunlit wildflower & clover glades + warm subsurface tip translucency

uniform vec3 root_color : source_color = vec3(0.16, 0.28, 0.12);
uniform vec3 tip_color : source_color = vec3(0.25, 0.40, 0.15);
uniform vec3 tip_color_warm : source_color = vec3(0.35, 0.46, 0.18);
uniform float blade_height : hint_range(0.12, 1.5) = 0.34;
uniform float surface_fur_mode : hint_range(0.0, 1.0) = 0.0;
uniform vec2 wind_direction = vec2(0.88, 0.47);
uniform float wind_strength : hint_range(0.0, 3.0) = 0.72;
uniform vec3 player_pos = vec3(0.0, -100.0, 0.0);

varying float v_t;
varying vec3 v_root_col;
varying vec3 v_tip_col;
varying float v_gust;
varying vec3 v_up_normal_view;
varying float v_blossom_id;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash12(i + vec2(0.0, 0.0)), hash12(i + vec2(1.0, 0.0)), u.x),
		mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), u.x),
		u.y
	);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	mat2 rot = mat2(vec2(0.80, 0.60), vec2(-0.60, 0.80));
	for (int i = 0; i < 4; i++) {
		v += a * value_noise(p);
		p = rot * p * 2.02;
		a *= 0.5;
	}
	return v;
}

vec3 meadow_ground_palette(vec2 xz) {
	float macro_a = fbm(xz * 0.045);
	float macro_b = fbm(xz * 0.11 + vec2(5.2, 3.7));
	vec3 deep_sage = vec3(0.16, 0.28, 0.12);
	vec3 lush_meadow = vec3(0.23, 0.37, 0.15);
	vec3 warm_olive = vec3(0.31, 0.43, 0.17);
	vec3 col = mix(deep_sage, lush_meadow, smoothstep(0.22, 0.74, macro_a));
	col = mix(col, warm_olive, smoothstep(0.36, 0.80, macro_b) * 0.70);

	float moss_n = fbm(xz * 1.65);
	vec3 humus_dark = vec3(0.13, 0.16, 0.09);
	vec3 moss_cushion = vec3(0.24, 0.38, 0.15);
	col = mix(humus_dark, col, smoothstep(0.18, 0.62, moss_n));
	col = mix(col, moss_cushion, smoothstep(0.55, 0.86, moss_n) * 0.65);
	return col;
}

float wind_gust(vec2 world_xz, float time) {
	vec2 uv = world_xz * 0.075 - normalize(wind_direction) * time * 0.42;
	return smoothstep(0.20, 0.85, fbm(uv));
}

void vertex() {
	float t = clamp(UV.y, 0.0, 1.0);
	vec4 rnd = COLOR;
	vec3 world_v = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;

	// Natural meadow clumping + extended distance taper across the 136x88m CBT proving ground
	float clump = fbm(world_v.xz * 0.20);
	float glade_n = fbm(world_v.xz * 0.14 + vec2(4.2, -1.8));
	float inst_h = clamp(INSTANCE_CUSTOM.a, 0.14, 1.45);
	float verge_tint = clamp(INSTANCE_CUSTOM.r, 0.0, 1.0);
	float dist_origin = length(world_v.xz);
	float dist_taper = 1.0 - smoothstep(66.0, 86.0, dist_origin);
	float near_wind_boost = mix(1.22, 0.72, smoothstep(8.0, 48.0, dist_origin));
	float h_scale = (0.72 + rnd.g * 0.46) * (0.74 + clump * 0.56) * inst_h * dist_taper;
	float gust = wind_gust(world_v.xz, TIME);
	float wave = sin(TIME * 1.65 - dot(world_v.xz, wind_direction) * 0.42 + rnd.a * 6.28) * 0.5 + 0.5;
	float flutter = sin(TIME * 3.8 + world_v.x * 2.3 - world_v.z * 1.9 + rnd.g * 6.28) * 0.08 * near_wind_boost;
	float bend = ((gust * 0.65 + wave * 0.35 + 0.08) * near_wind_boost + flutter) * wind_strength;

	float curve = t * t;
	vec2 wdir = normalize(wind_direction);
	vec2 rest_bend = vec2(cos(rnd.b * 6.283), sin(rnd.b * 6.283)) * 0.12;
	vec2 total_xz = (wdir * bend * 0.34 + rest_bend) * curve * blade_height * h_scale;

	// Interactive grass parting around player / traveller (`player_pos`)
	vec2 to_blade = world_v.xz - player_pos.xz;
	float p_dist = length(to_blade);
	if (p_dist < 1.15 && p_dist > 0.001) {
		float push = (1.0 - smoothstep(0.15, 1.15, p_dist)) * curve;
		total_xz += (to_blade / p_dist) * (push * 0.28);
		h_scale *= (1.0 - push * 0.24);
	}

	if (surface_fur_mode > 0.5) {
		VERTEX.x += total_xz.x * 0.28;
		VERTEX.z += total_xz.y * 0.28;
	} else {
		VERTEX.y *= blade_height * h_scale;
		VERTEX.x += total_xz.x;
		VERTEX.z += total_xz.y;
	}

	// Tilt normal slightly with wind bend so rolling wind waves catch golden sunlight across the meadow
	vec3 terrain_up_local = normalize(vec3(total_xz.x * 0.42, 1.0, total_xz.y * 0.42));
	NORMAL = terrain_up_local;
	vec3 world_up = normalize((MODEL_MATRIX * vec4(terrain_up_local, 0.0)).xyz);
	v_up_normal_view = normalize((VIEW_MATRIX * vec4(world_up, 0.0)).xyz);

	// Exact root match with the underlying terrain (including earthy verge tint near road edges)
	vec3 ground_col = meadow_ground_palette(world_v.xz);
	vec3 verge_root = vec3(0.20, 0.24, 0.12);
	v_root_col = mix(ground_col, verge_root, verge_tint * 0.65);

	float warm_patch = fbm(world_v.xz * 0.085 + vec2(3.1, 1.7));
	float cool_patch = fbm(world_v.xz * 0.16 + vec2(-2.4, 4.3));
	vec3 base_tip = mix(tip_color, tip_color_warm, smoothstep(0.24, 0.76, warm_patch));
	base_tip = mix(base_tip, vec3(0.19, 0.35, 0.14), smoothstep(0.54, 0.84, cool_patch) * 0.36);
	base_tip = mix(base_tip, vec3(0.44, 0.50, 0.20), smoothstep(0.54, 0.84, clump) * 0.46);
	base_tip = mix(base_tip, vec3(0.32, 0.39, 0.17), verge_tint * 0.45);
	v_tip_col = base_tip * (0.88 + (rnd.r - 0.5) * 0.24);
	v_t = t;
	v_gust = gust;

	// Clustered wildflower & clover glades on sunlit meadow rises
	float blossom_thresh = mix(0.978, 0.905, smoothstep(0.50, 0.78, glade_n));
	v_blossom_id = (rnd.r > blossom_thresh && clump > 0.36 && inst_h > 0.48 && verge_tint < 0.2)
		? fract(rnd.b * 17.3 + glade_n * 0.35)
		: -1.0;
}

void fragment() {
	// Never flip the normal downward on backfaces: keep the smooth hill normal!
	NORMAL = normalize(v_up_normal_view);

	float t = v_t;
	vec3 col = mix(v_root_col, v_tip_col, smoothstep(0.06, 0.94, t));
	// Deep root contact ambient occlusion connecting grass tufts to the dark humus soil (no floating look)
	float root_ao = mix(0.46, 1.0, smoothstep(0.0, 0.48, t));
	col *= root_ao;
	// Warm golden subsurface translucency on sunlit wind-wave crests
	col += vec3(0.062, 0.074, 0.020) * (v_gust * 0.85 + 0.15) * (t * t);

	// Delicate wildflower & clover specks at the top 22% of blossom stems
	if (v_blossom_id >= 0.0 && t > 0.78) {
		float petal_t = smoothstep(0.78, 0.91, t);
		vec3 petal_col = vec3(0.95, 0.93, 0.82); // Meadowsweet cream
		if (v_blossom_id > 0.74) {
			petal_col = vec3(0.94, 0.78, 0.26); // Golden buttercup
		} else if (v_blossom_id > 0.48) {
			petal_col = vec3(0.66, 0.78, 0.95); // Sky speedwell
		} else if (v_blossom_id > 0.26) {
			petal_col = vec3(0.88, 0.68, 0.78); // Rose clover
		}
		col = mix(col, petal_col, petal_t * 0.90);
	}

	ALBEDO = col;
	ROUGHNESS = 0.92;
	SPECULAR = 0.06;
}
