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
	// and transitions to the exact blade-tip palette in the distance so far hills have zero seam)
	vec3 col = meadow_ground_palette(xz);
	float warm_patch = fbm(xz * 0.08 + vec2(3.1, 1.7));
	vec3 far_tip_col = mix(vec3(0.25, 0.41, 0.16), vec3(0.34, 0.46, 0.18), smoothstep(0.28, 0.76, warm_patch));
	float far_blend = smoothstep(26.0, 44.0, length(xz));
	col = mix(col, far_tip_col, far_blend * 0.92);
	col *= (1.0 + soft_grain * 0.03);

	// 2. Clean, natural earthen footpath with soft olive-turf shoulder and fine soil grain
	float w_path = clamp(v_path_and_wet.x, 0.0, 1.0);
	if (w_path > 0.01) {
		float edge_noise = (fbm(xz * 0.75) - 0.5) * 0.12;
		float wp = w_path + edge_noise;

		// Soft olive-loam shoulder blending grass roots into the compacted trail
		float verge_mask = smoothstep(0.26, 0.48, wp);
		vec3 verge_col = vec3(0.25, 0.30, 0.16);
		col = mix(col, verge_col, verge_mask * 0.75);

		// Compacted warm soil core with fine micro-grain (no blotchy spots)
		float fine_soil = (fbm(xz * 4.5) - 0.5) * 0.05;
		float path_mask = smoothstep(0.42, 0.72, wp);
		float center_crown = smoothstep(0.76, 0.98, w_path);
		vec3 loam_track = vec3(0.41, 0.32, 0.22) * (1.0 + fine_soil);
		vec3 loam_edge = vec3(0.33, 0.27, 0.18);
		vec3 loam_crown = vec3(0.36, 0.31, 0.21) * (1.0 + fine_soil);
		vec3 path_col = mix(loam_edge, loam_track, smoothstep(0.44, 0.78, wp));
		path_col = mix(path_col, loam_crown, center_crown * 0.38);

		col = mix(col, path_col, path_mask);
	}

	// 3. Gently sloped sandy-loam streambed & bank margin (Step 2+)
	float w_pebbles = clamp(v_weights.g, 0.0, 1.0);
	if (w_pebbles > 0.01) {
		float bank_noise = (fbm(xz * 0.35) - 0.5) * 0.16;
		float bank_mask = smoothstep(0.18, 0.68, w_pebbles + bank_noise);
		vec3 bank_col = mix(vec3(0.36, 0.32, 0.25), vec3(0.28, 0.27, 0.24), smoothstep(0.45, 0.90, w_pebbles));
		col = mix(col, bank_col * (1.0 + soft_grain * 0.04), bank_mask);
	}

	// 4. Subtle distant atmospheric perspective on the far valley rim hills
	float rim_haze = smoothstep(52.0, 88.0, length(xz));
	col = mix(col, vec3(0.34, 0.44, 0.36), rim_haze * 0.45);

	ALBEDO = col;
	ROUGHNESS = 0.92;
	SPECULAR = 0.06;
}
