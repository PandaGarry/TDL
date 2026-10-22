shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform vec3 water_deep_color : source_color = vec3(0.05, 0.20, 0.30);
uniform vec3 water_shallow_color : source_color = vec3(0.10, 0.34, 0.40);
uniform vec3 silt_tint_color : source_color = vec3(0.24, 0.28, 0.19);
uniform vec3 foam_color : source_color = vec3(0.78, 0.86, 0.90);
uniform float silt_load : hint_range(0.0, 1.0) = 0.18;
uniform float flow_speed : hint_range(0.0, 3.0) = 0.72;
uniform float wave_height : hint_range(0.0, 0.15) = 0.025;

varying vec3 v_world_pos;
varying float v_shore_factor;
varying float v_depth_factor;
varying float v_rapids_factor;

float hash21(vec2 p) {
	p = fract(p * vec2(127.1, 311.7));
	p += dot(p, p + 34.23);
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

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 3; i++) {
		v += a * vnoise(p);
		p *= 2.05;
		a *= 0.5;
	}
	return v;
}

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_shore_factor = COLOR.r;
	v_depth_factor = COLOR.g;
	v_rapids_factor = COLOR.b;
	float t = TIME * flow_speed;
	float w1 = sin(v_world_pos.x * 1.8 + v_world_pos.z * 2.2 - t * 2.6);
	float w2 = cos(v_world_pos.x * 2.9 - v_world_pos.z * 1.7 + t * 1.9);
	VERTEX.y += (w1 * 0.6 + w2 * 0.4) * wave_height;
}

void fragment() {
	float t = TIME * flow_speed;
	vec2 flow_uv1 = v_world_pos.xz * 0.42 + vec2(-t * 0.24, -t * 0.58);
	vec2 flow_uv2 = v_world_pos.xz * 0.78 + vec2(t * 0.16, -t * 0.36);

	float n1 = fbm(flow_uv1 * 2.2);
	float n2 = fbm(flow_uv2 * 3.1 + vec2(4.2, 1.7));
	float ripple = (n1 + n2) * 0.5;

	float silt = clamp(silt_load, 0.0, 1.0);
	vec3 deep_col = mix(water_deep_color, silt_tint_color * 0.72, silt * 0.60);
	vec3 shallow_col = mix(water_shallow_color, silt_tint_color, silt * 0.72);
	vec3 base_col = mix(shallow_col, deep_col, clamp(v_depth_factor * 0.85 + 0.15, 0.0, 1.0));

	// Subtle sunlit caustics in shallow water
	float caustic = smoothstep(0.56, 0.78, ripple) * (1.0 - v_depth_factor * 0.7) * (1.0 - silt * 0.65);
	base_col += vec3(0.06, 0.11, 0.12) * caustic;

	// Delicate shoreline lace & rapids whitewater
	float shore_foam = smoothstep(0.76, 0.96, v_shore_factor + (n1 - 0.5) * 0.18);
	float rapids_foam = smoothstep(0.60, 0.84, ripple + v_rapids_factor * 0.25) * v_rapids_factor * 0.65;
	float foam_mask = clamp(max(shore_foam * 0.75, rapids_foam), 0.0, 0.82);

	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.5);
	vec3 sky_refl = vec3(0.32, 0.46, 0.58);
	vec3 final_col = mix(base_col, sky_refl, fresnel * 0.28);
	final_col = mix(final_col, foam_color, foam_mask);

	vec3 wave_n = normalize(vec3((n1 - 0.5) * 0.32, (n2 - 0.5) * 0.32, 1.0));
	NORMAL_MAP = wave_n * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 0.55;

	ALBEDO = final_col;
	ROUGHNESS = mix(0.16, 0.42, max(silt * 0.5, foam_mask));
	SPECULAR = 0.36;
	ALPHA = clamp(mix(0.84, 0.95, max(v_depth_factor, foam_mask)), 0.80, 0.96);
}
