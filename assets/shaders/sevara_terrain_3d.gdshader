shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// Step 1 Look-Dev Foundation: Clean, calm, velvety stylized terrain shader
// (inspired by Bukkbeek NatureBlocks, Tiny Glade, and Breath of the Wild).
// Zero high-frequency noisy photo-textures: smooth macro color harmony that blends
// seamlessly into the 3D grass blades growing from it.

uniform float silt_stain = 0.16;

varying vec3 v_world_pos;
varying vec3 v_world_nrm;
varying vec4 v_weights;
varying vec2 v_path_and_wet;

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

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_weights = COLOR;
	v_path_and_wet = UV2;
}

void fragment() {
	vec2 xz = v_world_pos.xz;
	float soft_grain = fbm(xz * 0.55) * 2.0 - 1.0;

	// 1. Base velvety meadow ground (matches grass blade roots 1:1 up close,
	// and warms toward sunlit blade tips in the distance so far hills blend seamlessly)
	vec3 col = meadow_ground_palette(xz);
	float far_blend = smoothstep(24.0, 44.0, length(xz));
	vec3 far_meadow_col = mix(vec3(0.26, 0.42, 0.17), vec3(0.35, 0.48, 0.19), fbm(xz * 0.07));
	col = mix(col, far_meadow_col, far_blend * 0.65);
	col *= (1.0 + soft_grain * 0.035);

	// 2. Organic earthen footpath with grassy wheel-track median, trampled olive verge & embedded pebbles
	float w_path = clamp(v_path_and_wet.x, 0.0, 1.0);
	if (w_path > 0.01) {
		float edge_noise = (fbm(xz * 0.65) - 0.5) * 0.18 + (value_noise(xz * 1.8) - 0.5) * 0.08;
		float wp = w_path + edge_noise;

		// Trampled dry-olive turf verge right where short grass blades taper out (zero neon green strip!)
		float verge_mask = smoothstep(0.18, 0.38, wp) * (1.0 - smoothstep(0.46, 0.70, wp));
		vec3 verge_col = vec3(0.26, 0.29, 0.16) * (1.0 + soft_grain * 0.05);
		col = mix(col, verge_col, verge_mask * 0.85);

		// Packed warm loam core with subtle twin wheel/foot tracks and center crown
		float path_mask = smoothstep(0.34, 0.66, wp);
		float center_crown = smoothstep(0.72, 0.96, w_path) * (0.4 + 0.6 * fbm(xz * 0.5));
		vec3 loam_track = vec3(0.42, 0.33, 0.23) * (1.0 + soft_grain * 0.06);
		vec3 loam_edge = vec3(0.34, 0.27, 0.19);
		vec3 loam_crown = vec3(0.35, 0.33, 0.20);
		vec3 path_col = mix(loam_edge, loam_track, smoothstep(0.38, 0.74, wp));
		path_col = mix(path_col, loam_crown, center_crown * 0.45);

		// Subtle flat embedded stones along the compacted dirt
		float peb_n = value_noise(xz * 3.6);
		float peb_mask = smoothstep(0.76, 0.86, peb_n) * smoothstep(0.40, 0.65, wp);
		vec3 peb_col = vec3(0.46, 0.43, 0.38);
		path_col = mix(path_col, peb_col, peb_mask * 0.38);

		col = mix(col, path_col, path_mask);
	}

	// 3. Gently sloped sandy-loam streambed & bank margin
	float w_pebbles = clamp(v_weights.g, 0.0, 1.0);
	if (w_pebbles > 0.01) {
		float bank_noise = (fbm(xz * 0.35) - 0.5) * 0.16;
		float bank_mask = smoothstep(0.18, 0.68, w_pebbles + bank_noise);
		vec3 bank_col = mix(vec3(0.36, 0.32, 0.25), vec3(0.28, 0.27, 0.24), smoothstep(0.45, 0.90, w_pebbles));
		col = mix(col, bank_col * (1.0 + soft_grain * 0.04), bank_mask);
	}

	// 4. Steep highland rock outcrops on the distant valley rim
	float slope = 1.0 - clamp(v_world_nrm.y, 0.0, 1.0);
	float w_rock = max(clamp(v_weights.b, 0.0, 1.0), smoothstep(0.18, 0.42, slope));
	if (w_rock > 0.01) {
		float rock_mask = smoothstep(0.15, 0.65, w_rock);
		vec3 rock_col = mix(vec3(0.30, 0.32, 0.33), vec3(0.38, 0.39, 0.38), fbm(xz * 0.22));
		col = mix(col, rock_col, rock_mask);
	}

	ALBEDO = col;
	ROUGHNESS = 0.92;
	SPECULAR = 0.06;
}
