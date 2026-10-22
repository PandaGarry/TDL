shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, diffuse_burley, specular_schlick_ggx;

// Step 2 Nivarel Mountain Creek & Ford Water Shader (2026 gl_compatibility):
// - Zero external texture dependencies, zero SCREEN_TEXTURE/DEPTH_TEXTURE tile-flush overhead.
// - Wave-refracted procedural river pebbles & golden sand in crystal-clear shallows.
// - Beer-Lambert optical absorption from emerald shallows to deep sapphire-teal channel.
// - Dual counter-scrolling capillary wave normals + lacy shoreline foam + stone-ford rapids wakes.

uniform vec4 shallow_color : source_color = vec4(0.16, 0.44, 0.38, 0.68);
uniform vec4 mid_color : source_color = vec4(0.06, 0.28, 0.34, 0.86);
uniform vec4 deep_color : source_color = vec4(0.03, 0.14, 0.22, 0.94);
uniform vec4 sky_reflection_tint : source_color = vec4(0.58, 0.76, 0.90, 1.0);
uniform vec4 foam_color : source_color = vec4(0.90, 0.95, 0.98, 1.0);
uniform float flow_speed = 0.58;
uniform float wave_height = 0.024;
uniform float silt_load = 0.16;

varying vec3 v_world_pos;
varying vec3 v_bathymetry;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float noise(vec2 p) {
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
		v += a * noise(p);
		p = rot * p * 2.05;
		a *= 0.5;
	}
	return v;
}

float voronoi_caustics(vec2 p) {
	vec2 n = floor(p);
	vec2 f = fract(p);
	float md = 8.0;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 g = vec2(float(i), float(j));
			vec2 o = vec2(hash12(n + g), hash12(n + g + vec2(17.3, 41.7)));
			o = 0.5 + 0.42 * sin(TIME * 1.8 + 6.2831 * o);
			vec2 r = g + o - f;
			float d = dot(r, r);
			md = min(md, d);
		}
	}
	return pow(clamp(1.0 - sqrt(md), 0.0, 1.0), 2.6);
}

vec3 procedural_riverbed(vec2 uv) {
	float n_macro = fbm(uv * 2.2);
	float n_peb1 = noise(uv * 11.5);
	float n_peb2 = noise(uv * 24.0 + vec2(4.7, 9.2));
	vec3 sand_col = vec3(0.30, 0.27, 0.20);
	vec3 slate_pebble = vec3(0.20, 0.25, 0.26);
	vec3 amber_pebble = vec3(0.38, 0.32, 0.22);
	vec3 col = mix(sand_col, slate_pebble, smoothstep(0.28, 0.72, n_macro));
	col = mix(col, amber_pebble, smoothstep(0.55, 0.86, n_peb1) * 0.68);
	col *= (0.84 + 0.32 * n_peb2);
	return col;
}

float river_center_x(float wz) {
	return 7.8 + wz * 0.22 + sin(wz * 0.088 + 0.35) * 3.6 + cos(wz * 0.044 - 0.2) * 1.8;
}

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_bathymetry = COLOR.rgb; // R = shore_prox, G = water_depth, B = rapids_fac
	float depth_atten = clamp(COLOR.g * 1.5, 0.06, 1.0);
	float t = TIME * flow_speed;
	float w1 = sin(v_world_pos.x * 1.45 - t * 3.8 + v_world_pos.z * 0.85);
	float w2 = cos(v_world_pos.x * 2.90 - t * 5.2 - v_world_pos.z * 1.75) * 0.5;
	VERTEX.y += (w1 + w2) * wave_height * depth_atten;
}

void fragment() {
	float t = TIME * flow_speed;
	float water_depth = clamp(v_bathymetry.g, 0.0, 1.0);
	float rapids_weight = clamp(v_bathymetry.b, 0.0, 1.0);

	// Dual counter-scrolling capillary wave normals
	vec2 flow_uv1 = v_world_pos.xz * vec2(0.52, 0.72) + vec2(-t * 0.45, -t * 1.55);
	vec2 flow_uv2 = v_world_pos.xz * vec2(1.05, 1.38) + vec2(t * 0.35, -t * 2.35);
	vec2 flow_uv3 = v_world_pos.xz * vec2(2.35, 2.75) + vec2(-t * 0.65, -t * 3.25);

	float h1 = fbm(flow_uv1) * 0.55 + fbm(flow_uv2) * 0.30 + noise(flow_uv3) * 0.15;
	float hx = fbm(flow_uv1 + vec2(0.06, 0.0)) * 0.55 + fbm(flow_uv2 + vec2(0.06, 0.0)) * 0.30 + noise(flow_uv3 + vec2(0.06, 0.0)) * 0.15;
	float hz = fbm(flow_uv1 + vec2(0.0, 0.06)) * 0.55 + fbm(flow_uv2 + vec2(0.0, 0.06)) * 0.30 + noise(flow_uv3 + vec2(0.0, 0.06)) * 0.15;

	vec2 wave_grad = vec2(h1 - hx, h1 - hz);
	vec3 wave_nrm = normalize(vec3(wave_grad.x * 4.8, 1.0, wave_grad.y * 4.8));
	NORMAL = normalize(mix(NORMAL, (VIEW_MATRIX * vec4(wave_nrm, 0.0)).xyz, 0.78));

	// Wave-refracted procedural riverbed pebbles & golden caustics in crystal shallows
	vec2 pebble_uv = v_world_pos.xz * 0.38 + wave_grad * 0.42;
	vec3 bed_pebbles = procedural_riverbed(pebble_uv);

	if (water_depth < 0.78 && length(v_world_pos.xz) < 48.0) {
		float caustics = voronoi_caustics(v_world_pos.xz * 1.55 + wave_grad * 1.2 + vec2(-t * 0.40, -t * 1.30));
		bed_pebbles += vec3(0.28, 0.42, 0.34) * caustics * (1.0 - smoothstep(0.15, 0.75, water_depth));
	}

	// Beer-Lambert optical absorption from refracted pebbles -> emerald shallows -> deep sapphire channel
	vec3 water_tint = mix(shallow_color.rgb, mid_color.rgb, smoothstep(0.12, 0.52, water_depth));
	water_tint = mix(water_tint, deep_color.rgb, smoothstep(0.45, 0.92, water_depth));
	vec3 silt_tint = vec3(0.26, 0.24, 0.16);
	water_tint = mix(water_tint, silt_tint, clamp(silt_load - 0.18, 0.0, 0.55));

	float bed_visibility = exp(-water_depth * 3.1) * 0.66;
	vec3 water_col = mix(water_tint, bed_pebbles, bed_visibility);

	// Fresnel sky reflection
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.4);
	water_col = mix(water_col, sky_reflection_tint.rgb, fresnel * 0.48);

	// 1) Delicate lacy shoreline foam right at the shallow bank edge
	float foam_noise = fbm(v_world_pos.xz * 2.5 + vec2(-t * 0.55, -t * 1.95));
	float shore_band = (1.0 - smoothstep(0.02, 0.16, water_depth)) * smoothstep(0.005, 0.038, water_depth);
	float shore_lace = smoothstep(0.40, 0.72, shore_band * (0.65 + 0.65 * foam_noise));

	// 2) Foam wakes across the stone ford (z ~ -2.8) and upper/lower boulder rapids (z ~ -15.0, z ~ 6.2)
	float r_cx = river_center_x(v_world_pos.z);
	float d_ford = length(vec2((v_world_pos.x - r_cx) * 0.55, v_world_pos.z - (-2.8)));
	float d_rapid1 = abs(v_world_pos.z - (-15.0));
	float d_rapid2 = abs(v_world_pos.z - 6.2);
	float obstacle_band = max(
		exp(-pow(d_ford / 1.45, 2.0)) * 0.82,
		max(exp(-pow(d_rapid1 / 1.25, 2.0)) * 0.68, exp(-pow(d_rapid2 / 1.15, 2.0)) * 0.62)
	) * smoothstep(0.06, 0.28, water_depth);
	float obstacle_foam = smoothstep(0.36, 0.72, obstacle_band * (0.52 + 0.68 * foam_noise));

	// 3) Current rapid streaks in midstream
	float rapid_noise = fbm(vec2(v_world_pos.x * 2.3 + sin(v_world_pos.z * 0.4) * 1.1, v_world_pos.z * 0.62 - t * 2.75));
	float rapid_foam = smoothstep(0.66 - rapids_weight * 0.09, 0.84, rapid_noise) * smoothstep(0.14, 0.55, water_depth) * (0.32 + rapids_weight * 0.38);

	// 4) Sunlit wave crest glints
	float sun_glint = smoothstep(0.77, 0.90, h1) * 0.36;

	float total_foam = clamp(shore_lace * 0.76 + obstacle_foam * 0.84 + rapid_foam + sun_glint, 0.0, 0.90);
	ALBEDO = mix(water_col, foam_color.rgb, total_foam);
	ROUGHNESS = mix(0.05, 0.36, total_foam);
	METALLIC = 0.04;
	SPECULAR = 0.92;

	float shore_feather = smoothstep(0.0, 0.042, water_depth);
	ALPHA = clamp(mix(shallow_color.a, deep_color.a, smoothstep(0.08, 0.65, water_depth)) + total_foam * 0.24, 0.0, 0.95) * shore_feather;
}
