shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

// Step 1 Look-Dev Foundation: Velvety Stylized 3D Meadow Grass Shader
// (inspired by Bukkbeek NatureBlocks, Tiny Glade, and Breath of the Wild).
// Key principles:
// 1. Root color matches the exact procedural ground color at (world_pos.xz) -> zero seam at the base.
// 2. Blade normal is locked to the smooth hill normal (never flipped downward on backfaces!).
// 3. Soft, calm wind waves roll across the tips without noisy per-pixel speckles.

uniform vec3 root_color : source_color = vec3(0.17, 0.30, 0.13);
uniform vec3 tip_color : source_color = vec3(0.25, 0.41, 0.16);
uniform vec3 tip_color_warm : source_color = vec3(0.34, 0.46, 0.18);
uniform float blade_height : hint_range(0.15, 1.5) = 0.34;
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
	vec3 deep_sage = vec3(0.17, 0.30, 0.13);
	vec3 lush_meadow = vec3(0.24, 0.39, 0.16);
	vec3 warm_olive = vec3(0.33, 0.45, 0.18);
	vec3 col = mix(deep_sage, lush_meadow, smoothstep(0.22, 0.74, macro_a));
	col = mix(col, warm_olive, smoothstep(0.36, 0.80, macro_b) * 0.72);
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

	// Natural meadow clumping + smooth distance taper so far hills have no abrupt grass cutoff
	float clump = fbm(world_v.xz * 0.20);
	float inst_h = clamp(INSTANCE_CUSTOM.a, 0.16, 1.35);
	float dist_taper = 1.0 - smoothstep(32.0, 45.0, length(world_v.xz));
	float h_scale = (0.72 + rnd.g * 0.46) * (0.74 + clump * 0.56) * inst_h * dist_taper;
	float gust = wind_gust(world_v.xz, TIME);
	float wave = sin(TIME * 1.5 - dot(world_v.xz, wind_direction) * 0.38 + rnd.a * 6.28) * 0.5 + 0.5;
	float bend = (gust * 0.65 + wave * 0.35 + 0.08) * wind_strength;

	float curve = t * t;
	vec2 wdir = normalize(wind_direction);
	vec2 rest_bend = vec2(cos(rnd.b * 6.283), sin(rnd.b * 6.283)) * 0.12;
	vec2 total_xz = (wdir * bend * 0.34 + rest_bend) * curve * blade_height * h_scale;

	VERTEX.y *= blade_height * h_scale;
	VERTEX.x += total_xz.x;
	VERTEX.z += total_xz.y;

	// Lock normal to smooth terrain-up vector so front and back of blades shade identically
	vec3 terrain_up_local = vec3(0.0, 1.0, 0.0);
	NORMAL = terrain_up_local;
	vec3 world_up = normalize((MODEL_MATRIX * vec4(terrain_up_local, 0.0)).xyz);
	v_up_normal_view = normalize((VIEW_MATRIX * vec4(world_up, 0.0)).xyz);

	// Exact root match with the underlying terrain at world_v.xz
	vec3 ground_col = meadow_ground_palette(world_v.xz);
	v_root_col = ground_col;

	float warm_patch = fbm(world_v.xz * 0.08 + vec2(3.1, 1.7));
	vec3 base_tip = mix(tip_color, tip_color_warm, smoothstep(0.28, 0.76, warm_patch));
	// Taller seed-head clumps catch slightly warmer golden-oat sunlight
	base_tip = mix(base_tip, vec3(0.44, 0.51, 0.21), smoothstep(0.58, 0.85, clump) * 0.45);
	v_tip_col = base_tip * (0.93 + (rnd.r - 0.5) * 0.14);
	v_t = t;
	v_gust = gust;
	// ~3.5% of tall blades in lush clumps carry a delicate wildflower blossom at the very tip
	v_blossom_id = (rnd.r > 0.965 && clump > 0.45 && inst_h > 0.65) ? fract(rnd.b * 17.3) : -1.0;
}

void fragment() {
	// Never flip the normal downward on backfaces: keep the smooth hill normal!
	NORMAL = normalize(v_up_normal_view);

	float t = v_t;
	vec3 col = mix(v_root_col, v_tip_col, smoothstep(0.08, 0.95, t));
	// Subtle sunlit sheen along rolling wind gusts
	col += vec3(0.035, 0.048, 0.012) * v_gust * (t * t);

	// Delicate wildflower specks at the top 18% of rare blossom stems
	if (v_blossom_id >= 0.0 && t > 0.80) {
		float petal_t = smoothstep(0.80, 0.92, t);
		vec3 petal_col = vec3(0.92, 0.90, 0.78); // Warm cream clover
		if (v_blossom_id > 0.66) {
			petal_col = vec3(0.90, 0.76, 0.28); // Golden buttercup
		} else if (v_blossom_id > 0.38) {
			petal_col = vec3(0.64, 0.76, 0.92); // Alpine speedwell blue
		}
		col = mix(col, petal_col, petal_t * 0.88);
	}

	ALBEDO = col;
	ROUGHNESS = 0.92;
	SPECULAR = 0.06;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float diff = smoothstep(-0.22, 0.88, ndl) * 0.82 + 0.18;
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * diff / PI;
	float back = pow(clamp(dot(VIEW, -LIGHT), 0.0, 1.0), 3.2);
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * back * v_t * 0.26 / PI;
	DIFFUSE_LIGHT += vec3(0.05, 0.08, 0.14) * (1.0 - clamp(ndl * ATTENUATION, 0.0, 1.0)) * 0.28;
}
