shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// Step 2 3D Procedural Granite, Slate & Mossy Boulder Shader for Sevara Valley:
// - 100% procedural 3D stratified rock fracture, quartz grain & analytical 3D micro-normals.
// - Top moss cushions matched to `meadow_ground_palette` of Step 1 grass & terrain.
// - Wet river sheen & waterline darkening near Nivarel creek (`WATER_SURFACE_Y = 0.42`).

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D moss_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec3 tint : source_color = vec3(0.88, 0.90, 0.92);
uniform vec3 moss_color : source_color = vec3(0.23, 0.37, 0.15);
uniform float moss_amount : hint_range(0.0, 1.0) = 0.65;
uniform float snow_amount : hint_range(0.0, 1.0) = 0.08;
uniform float wetness : hint_range(0.0, 1.0) = 0.24;
uniform float triplanar : hint_range(0.0, 1.0) = 1.0;
uniform float triplanar_scale : hint_range(0.02, 2.0) = 0.34;

varying vec3 v_world;
varying vec3 v_wnormal;
varying vec4 v_custom;

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
		p = rot * p * 2.03;
		a *= 0.5;
	}
	return v;
}

float rock_micro_height(vec3 p) {
	float strata = sin(p.y * 8.5 + fbm(p.xz * 1.4) * 3.4) * 0.5 + 0.5;
	float crag = fbm(p.xz * 3.8 + vec2(p.y * 2.1, -p.y * 1.7));
	float grain = value_noise(p.xz * 16.0 + vec2(p.y * 9.0));
	return strata * 0.038 + crag * 0.028 + grain * 0.008;
}

vec3 meadow_ground_palette(vec2 xz) {
	float macro_a = fbm(xz * 0.045);
	float macro_b = fbm(xz * 0.11 + vec2(5.2, 3.7));
	vec3 deep_sage = vec3(0.16, 0.28, 0.12);
	vec3 lush_meadow = vec3(0.23, 0.37, 0.15);
	vec3 warm_olive = vec3(0.31, 0.43, 0.17);
	vec3 col = mix(deep_sage, lush_meadow, smoothstep(0.22, 0.74, macro_a));
	col = mix(col, warm_olive, smoothstep(0.36, 0.80, macro_b) * 0.70);
	return col;
}

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wnormal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_custom = INSTANCE_CUSTOM;
}

void fragment() {
	// 1. Analytical 3D Rock Fracture & Moss Cushion Micro-Normals
	float eps = 0.025;
	float h0 = rock_micro_height(v_world);
	float hx = rock_micro_height(v_world + vec3(eps, 0.0, 0.0));
	float hz = rock_micro_height(v_world + vec3(0.0, 0.0, eps));
	vec3 d_h = vec3((h0 - hx) / eps, 0.0, (h0 - hz) / eps);
	vec3 world_nrm = normalize(v_wnormal + d_h * 0.95);
	NORMAL = normalize((VIEW_MATRIX * vec4(world_nrm, 0.0)).xyz);

	// 2. Stratified Northern Granite & Warm Limestone Palette
	float strata = sin(v_world.y * 8.5 + fbm(v_world.xz * 1.4) * 3.4) * 0.5 + 0.5;
	float crag = fbm(v_world.xz * 3.6 + vec2(v_world.y * 1.9));
	float lichen = fbm(v_world.xz * 7.2 + vec2(4.1, -2.7));
	float grain = value_noise(v_world.xz * 18.0);

	vec3 slate_deep = vec3(0.24, 0.26, 0.27);
	vec3 granite_mid = vec3(0.36, 0.35, 0.33);
	vec3 limestone_warm = vec3(0.46, 0.42, 0.36);

	vec3 c = mix(slate_deep, granite_mid, smoothstep(0.18, 0.68, strata * 0.60 + crag * 0.40));
	c = mix(c, limestone_warm, smoothstep(0.55, 0.88, crag) * 0.65);
	// Pale gold/sage crustose lichen specks on dry rock faces
	c = mix(c, vec3(0.44, 0.45, 0.32), smoothstep(0.68, 0.90, lichen) * 0.35);
	c *= (0.86 + 0.24 * grain) * tint;
	if (length(v_custom.rgb) > 0.02) {
		c *= v_custom.rgb;
	}

	float up = world_nrm.y;
	c *= 0.80 + 0.28 * smoothstep(-0.20, 0.88, up);

	// 3. Velvety Moss Cushions on Upper Faces (synced with Step 1 meadow palette)
	float inst_moss = v_custom.a > 0.01 ? v_custom.a : moss_amount;
	float moss_mask = smoothstep(0.36, 0.72, up + (crag - 0.5) * 0.42) * inst_moss;
	// Keep submerged base free of bright dry moss
	moss_mask *= smoothstep(0.44, 0.68, v_world.y);
	vec3 ground_moss = meadow_ground_palette(v_world.xz);
	vec3 rich_moss = mix(moss_color, ground_moss, 0.72) * (0.86 + 0.26 * lichen);
	c = mix(c, rich_moss, clamp(moss_mask, 0.0, 0.88));

	// 4. Wet River Sheen near Nivarel Creek Waterline (WATER_SURFACE_Y = 0.42)
	float water_prox = 1.0 - smoothstep(0.38, 0.76, v_world.y);
	float wet = clamp(wetness * 0.45 + water_prox * 0.78, 0.0, 0.90);
	c *= mix(1.0, 0.62, wet);

	ALBEDO = c;
	ROUGHNESS = mix(mix(0.84, 0.92, moss_mask), 0.22, wet);
	SPECULAR = mix(0.18, 0.56, wet);
}
