shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform sampler2D riverbed_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D riverbed_normal : hint_normal, filter_linear_mipmap, repeat_enable;

uniform vec3 water_deep_color : source_color = vec3(0.04, 0.17, 0.24);
uniform vec3 water_shallow_color : source_color = vec3(0.09, 0.30, 0.33);
uniform vec3 silt_tint_color : source_color = vec3(0.25, 0.28, 0.19);
uniform vec3 foam_color : source_color = vec3(0.84, 0.90, 0.94);
uniform float silt_load : hint_range(0.0, 1.0) = 0.18;
uniform float flow_speed : hint_range(0.0, 3.0) = 0.72;
uniform float wave_height : hint_range(0.0, 0.15) = 0.022;

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
	vec2 flow_uv1 = v_world_pos.xz * 0.38 + vec2(-t * 0.22, -t * 0.54);
	vec2 flow_uv2 = v_world_pos.xz * 0.72 + vec2(t * 0.15, -t * 0.34);

	float n1 = fbm(flow_uv1 * 2.2);
	float n2 = fbm(flow_uv2 * 3.1 + vec2(4.2, 1.7));
	float ripple = (n1 + n2) * 0.5;

	vec3 nrm_sample1 = texture(riverbed_normal, flow_uv1 * 0.85).rgb * 2.0 - 1.0;
	vec3 nrm_sample2 = texture(riverbed_normal, flow_uv2 * 1.15).rgb * 2.0 - 1.0;
	vec2 wave_offset = (nrm_sample1.xy + nrm_sample2.xy) * 0.035 + vec2(n1 - 0.5, n2 - 0.5) * 0.045;

	// Refracted riverbed pebbles visible through clear mountain water
	vec2 bed_uv = v_world_pos.xz * 0.36 + wave_offset;
	vec3 bed_pebbles = texture(riverbed_tex, bed_uv).rgb * 0.78;

	float silt = clamp(silt_load, 0.0, 1.0);
	float depth = clamp(v_depth_factor, 0.0, 1.0);
	vec3 deep_col = mix(water_deep_color, silt_tint_color * 0.68, silt * 0.62);
	vec3 shallow_col = mix(water_shallow_color, silt_tint_color, silt * 0.74);

	// Blend refracted pebbles in shallow water and over rapids into deep emerald-sapphire pool
	float bed_visibility = (1.0 - smoothstep(0.05, 0.78, depth)) * (1.0 - silt * 0.65);
	vec3 water_body = mix(shallow_col, deep_col, smoothstep(0.08, 0.88, depth));
	vec3 base_col = mix(water_body, bed_pebbles * vec3(0.68, 0.88, 0.92), clamp(bed_visibility * 0.68, 0.0, 0.75));

	// Sunlit caustics dancing over shallow pebbles
	float caustic = smoothstep(0.54, 0.76, ripple) * (1.0 - depth * 0.68) * (1.0 - silt * 0.65);
	base_col += vec3(0.09, 0.15, 0.16) * caustic;

	// Delicate shoreline lace & rapids whitewater
	float shore_foam = smoothstep(0.80, 0.97, v_shore_factor + (n1 - 0.5) * 0.22);
	float rapids_foam = smoothstep(0.58, 0.82, ripple + v_rapids_factor * 0.28) * v_rapids_factor * 0.72;
	float foam_mask = clamp(max(shore_foam * 0.68, rapids_foam), 0.0, 0.84);

	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.2);
	vec3 sky_refl = vec3(0.38, 0.52, 0.64);
	vec3 final_col = mix(base_col, sky_refl, fresnel * 0.36);
	final_col = mix(final_col, foam_color, foam_mask);

	vec3 wave_n = normalize(vec3(wave_offset.x * 5.5, wave_offset.y * 5.5, 1.0));
	NORMAL_MAP = wave_n * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 0.85;

	ALBEDO = final_col;
	ROUGHNESS = mix(0.09, 0.38, max(silt * 0.45, foam_mask));
	SPECULAR = 0.48;
	ALPHA = clamp(mix(0.76, 0.95, max(depth * 0.85 + 0.15, foam_mask)), 0.72, 0.96);
}
