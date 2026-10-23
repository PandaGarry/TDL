shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, diffuse_burley, specular_schlick_ggx;

// Step 2 Nivarel Mountain Creek & Stone Ford Water Shader (v4 — Physical Boulder Wakes & Optics):
// - Crystal olive-emerald & river-teal mountain water over visible 3D cobblestone ford & pebble bed.
// - Physical boulder wake rings & downstream V-shaped current foam around in-stream stepping stones.
// - Reactive to `silt_load` (SevaraEcoChain) and `flow_speed` (SettingsManager.wind_and_water_shaders).

uniform vec4 shallow_color : source_color = vec4(0.17, 0.30, 0.20, 0.24);
uniform vec4 mid_color : source_color = vec4(0.06, 0.23, 0.21, 0.68);
uniform vec4 deep_color : source_color = vec4(0.02, 0.12, 0.15, 0.94);
uniform vec4 sky_reflection_tint : source_color = vec4(0.32, 0.42, 0.38, 1.0);
uniform vec4 foam_color : source_color = vec4(0.78, 0.82, 0.76, 1.0);
uniform float flow_speed = 0.54;
uniform float wave_height = 0.018;
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
	return pow(clamp(1.0 - sqrt(md), 0.0, 1.0), 3.0);
}

vec3 procedural_riverbed(vec2 uv) {
	float n_macro = fbm(uv * 2.4);
	float n_peb1 = noise(uv * 11.0);
	float n_peb2 = noise(uv * 24.0 + vec2(4.7, 9.2));
	vec3 sand_col = vec3(0.28, 0.25, 0.17);
	vec3 olive_pebble = vec3(0.18, 0.23, 0.15);
	vec3 amber_pebble = vec3(0.34, 0.28, 0.18);
	vec3 col = mix(sand_col, olive_pebble, smoothstep(0.28, 0.72, n_macro));
	col = mix(col, amber_pebble, smoothstep(0.52, 0.84, n_peb1) * 0.68);
	col *= (0.85 + 0.30 * n_peb2);
	return col;
}

float river_center_x(float wz) {
	return 7.8 + wz * 0.22 + sin(wz * 0.088 + 0.35) * 3.6 + cos(wz * 0.044 - 0.2) * 1.8;
}

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_bathymetry = COLOR.rgb; // R = shore_prox, G = water_depth, B = rapids_fac
	float depth_atten = clamp(COLOR.g * 1.4, 0.05, 1.0);
	float t = TIME * flow_speed;
	float w1 = sin(v_world_pos.x * 1.65 - t * 3.6 + v_world_pos.z * 0.95);
	float w2 = cos(v_world_pos.x * 3.10 - t * 4.8 - v_world_pos.z * 1.85) * 0.5;
	VERTEX.y += (w1 + w2) * wave_height * depth_atten;
}

void fragment() {
	float t = TIME * flow_speed;
	float water_depth = clamp(v_bathymetry.g, 0.0, 1.0);
	float rapids_weight = clamp(v_bathymetry.b, 0.0, 1.0);

	// Dual counter-scrolling capillary wave normals
	vec2 flow_uv1 = v_world_pos.xz * vec2(0.62, 0.84) + vec2(-t * 0.42, -t * 1.45);
	vec2 flow_uv2 = v_world_pos.xz * vec2(1.25, 1.62) + vec2(t * 0.32, -t * 2.15);
	vec2 flow_uv3 = v_world_pos.xz * vec2(2.65, 3.10) + vec2(-t * 0.55, -t * 2.95);

	float h1 = fbm(flow_uv1) * 0.55 + fbm(flow_uv2) * 0.30 + noise(flow_uv3) * 0.15;
	float hx = fbm(flow_uv1 + vec2(0.05, 0.0)) * 0.55 + fbm(flow_uv2 + vec2(0.05, 0.0)) * 0.30 + noise(flow_uv3 + vec2(0.05, 0.0)) * 0.15;
	float hz = fbm(flow_uv1 + vec2(0.0, 0.05)) * 0.55 + fbm(flow_uv2 + vec2(0.0, 0.05)) * 0.30 + noise(flow_uv3 + vec2(0.0, 0.05)) * 0.15;

	vec2 wave_grad = vec2(h1 - hx, h1 - hz);
	vec3 wave_nrm = normalize(vec3(wave_grad.x * 4.4, 1.0, wave_grad.y * 4.4));
	NORMAL = normalize(mix(NORMAL, (VIEW_MATRIX * vec4(wave_nrm, 0.0)).xyz, 0.65));

	// Wave-refracted procedural riverbed pebbles & warm golden-green caustics
	vec2 pebble_uv = v_world_pos.xz * 0.45 + wave_grad * 0.42;
	vec3 bed_pebbles = procedural_riverbed(pebble_uv);

	if (water_depth < 0.78 && length(v_world_pos.xz) < 48.0) {
		float caustics = voronoi_caustics(v_world_pos.xz * 1.85 + wave_grad * 1.2 + vec2(-t * 0.35, -t * 1.15));
		bed_pebbles += vec3(0.22, 0.24, 0.14) * caustics * (1.0 - smoothstep(0.15, 0.75, water_depth));
	}

	// Beer-Lambert optical absorption: warm golden-olive shallows -> deep emerald-sapphire thalweg
	vec3 water_tint = mix(shallow_color.rgb, mid_color.rgb, smoothstep(0.10, 0.46, water_depth));
	water_tint = mix(water_tint, deep_color.rgb, smoothstep(0.40, 0.86, water_depth));
	float silt_fac = clamp((silt_load - 0.20) * 1.35, 0.0, 0.65);
	vec3 silt_tint = vec3(0.25, 0.21, 0.13);
	water_tint = mix(water_tint, silt_tint, silt_fac);

	float bed_visibility = exp(-water_depth * (3.2 + silt_fac * 1.6)) * 0.78;
	vec3 water_col = mix(water_tint, bed_pebbles, bed_visibility);

	// Soft canopy/sky tint on grazing angles + subtle under-bridge ambient shadow
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	water_col = mix(water_col, sky_reflection_tint.rgb, fresnel * 0.22);
	float under_bridge = (1.0 - smoothstep(1.2, 2.2, abs(v_world_pos.z - 2.48))) * (1.0 - smoothstep(4.6, 5.8, abs(v_world_pos.x - 12.0)));
	water_col *= mix(1.0, 0.74, under_bridge);

	// 1) Delicate broken shoreline ripples
	float fn1 = fbm(v_world_pos.xz * 2.8 + vec2(-t * 0.45, -t * 1.65));
	float fn2 = fbm(v_world_pos.xz * 4.6 + vec2(t * 0.35, -t * 2.35));
	float shore_zone = (1.0 - smoothstep(0.02, 0.11, water_depth)) * smoothstep(0.008, 0.032, water_depth);
	float shore_lace = smoothstep(0.60, 0.80, fn1 * fn2 * 2.05) * shore_zone * 0.38;

	// 2) Fine longitudinal current wisps past bridge stone piers & rapids
	float d_pier1 = length(vec2((v_world_pos.x - 9.65) * 1.4, (v_world_pos.z - 2.95) * 0.55));
	float d_pier2 = length(vec2((v_world_pos.x - 14.35) * 1.4, (v_world_pos.z - 2.90) * 0.55));
	float d_rapid1 = abs(v_world_pos.z - (-15.0));
	float d_rapid2 = abs(v_world_pos.z - 7.5);
	float pier_wake = max(exp(-pow(d_pier1 / 1.15, 2.0)), exp(-pow(d_pier2 / 1.15, 2.0))) * 0.78;
	float rapid_zone = max(
		pier_wake,
		max(exp(-pow(d_rapid1 / 1.35, 2.0)) * 0.52, exp(-pow(d_rapid2 / 1.25, 2.0)) * 0.48)
	) * smoothstep(0.04, 0.22, water_depth);
	float streak_n = fbm(vec2(v_world_pos.x * 3.1 + sin(v_world_pos.z * 0.6) * 0.8, v_world_pos.z * 0.92 - t * 2.65));
	float rapid_wisps = smoothstep(0.62, 0.84, streak_n * (0.65 + 0.55 * fn2)) * (rapid_zone * 0.56 + rapids_weight * 0.16);

	// 3) Warm sunlit wave crest glints
	float sun_glint = smoothstep(0.79, 0.92, h1) * 0.24 * (1.0 - under_bridge * 0.75);

	float total_foam = clamp(shore_lace + rapid_wisps + sun_glint, 0.0, 0.56);
	ALBEDO = mix(water_col, foam_color.rgb, total_foam);
	ROUGHNESS = mix(0.34, 0.54, total_foam);
	METALLIC = 0.0;
	SPECULAR = 0.26;

	float shore_feather = smoothstep(0.0, 0.08, water_depth);
	float base_alpha = mix(shallow_color.a, deep_color.a, smoothstep(0.06, 0.68, water_depth));
	ALPHA = clamp(base_alpha + silt_fac * 0.12 + total_foam * 0.18, 0.0, 0.95) * shore_feather;
}
