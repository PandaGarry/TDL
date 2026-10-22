shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, diffuse_burley, specular_schlick_ggx;

// Step 2 Nivarel Mountain Creek & Ford Water Shader (v2 — Natural Emerald/Teal Stream):
// - Transparent shallow water (alpha 0.28..0.82) letting the real 3D pebble riverbed shine through.
// - Natural alpine olive-emerald & deep river-teal palette (zero neon pool-blue!).
// - Delicate, broken current foam wisps in rapids & around ford stones (no solid white shore line!).

uniform vec4 shallow_color : source_color = vec4(0.14, 0.26, 0.19, 0.30);
uniform vec4 mid_color : source_color = vec4(0.07, 0.21, 0.19, 0.66);
uniform vec4 deep_color : source_color = vec4(0.04, 0.13, 0.14, 0.84);
uniform vec4 sky_reflection_tint : source_color = vec4(0.36, 0.46, 0.48, 1.0);
uniform vec4 foam_color : source_color = vec4(0.76, 0.82, 0.80, 1.0);
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
	float n_peb1 = noise(uv * 12.0);
	float n_peb2 = noise(uv * 26.0 + vec2(4.7, 9.2));
	vec3 sand_col = vec3(0.24, 0.22, 0.16);
	vec3 slate_pebble = vec3(0.16, 0.20, 0.19);
	vec3 amber_pebble = vec3(0.30, 0.25, 0.17);
	vec3 col = mix(sand_col, slate_pebble, smoothstep(0.28, 0.72, n_macro));
	col = mix(col, amber_pebble, smoothstep(0.55, 0.86, n_peb1) * 0.65);
	col *= (0.84 + 0.30 * n_peb2);
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
	vec3 wave_nrm = normalize(vec3(wave_grad.x * 5.2, 1.0, wave_grad.y * 5.2));
	NORMAL = normalize(mix(NORMAL, (VIEW_MATRIX * vec4(wave_nrm, 0.0)).xyz, 0.80));

	// Wave-refracted procedural riverbed pebbles & subtle warm caustics in shallows
	vec2 pebble_uv = v_world_pos.xz * 0.42 + wave_grad * 0.38;
	vec3 bed_pebbles = procedural_riverbed(pebble_uv);

	if (water_depth < 0.72 && length(v_world_pos.xz) < 46.0) {
		float caustics = voronoi_caustics(v_world_pos.xz * 1.75 + wave_grad * 1.1 + vec2(-t * 0.35, -t * 1.15));
		bed_pebbles += vec3(0.18, 0.24, 0.16) * caustics * (1.0 - smoothstep(0.12, 0.68, water_depth));
	}

	// Beer-Lambert optical absorption from refracted pebbles -> olive-emerald shallows -> deep river teal
	vec3 water_tint = mix(shallow_color.rgb, mid_color.rgb, smoothstep(0.14, 0.55, water_depth));
	water_tint = mix(water_tint, deep_color.rgb, smoothstep(0.48, 0.92, water_depth));
	vec3 silt_tint = vec3(0.24, 0.21, 0.14);
	water_tint = mix(water_tint, silt_tint, clamp(silt_load - 0.18, 0.0, 0.55));

	float bed_visibility = exp(-water_depth * 2.6) * 0.72;
	vec3 water_col = mix(water_tint, bed_pebbles, bed_visibility);

	// Subtle Fresnel sky reflection (prevents electric-blue saturation)
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.8);
	water_col = mix(water_col, sky_reflection_tint.rgb, fresnel * 0.28);

	// 1) Delicate broken shoreline ripples (only where two noise octaves intersect — never a solid white line!)
	float fn1 = fbm(v_world_pos.xz * 2.8 + vec2(-t * 0.45, -t * 1.65));
	float fn2 = fbm(v_world_pos.xz * 4.6 + vec2(t * 0.35, -t * 2.35));
	float shore_zone = (1.0 - smoothstep(0.03, 0.14, water_depth)) * smoothstep(0.01, 0.04, water_depth);
	float shore_lace = smoothstep(0.56, 0.78, fn1 * fn2 * 2.1) * shore_zone * 0.45;

	// 2) Fine current wisps across the stone ford (z ~ -2.8) and boulder rapids (z ~ -15.0, z ~ 6.2)
	float r_cx = river_center_x(v_world_pos.z);
	float d_ford = length(vec2((v_world_pos.x - r_cx) * 0.65, v_world_pos.z - (-2.8)));
	float d_rapid1 = abs(v_world_pos.z - (-15.0));
	float d_rapid2 = abs(v_world_pos.z - 6.2);
	float rapid_zone = max(
		exp(-pow(d_ford / 1.35, 2.0)) * 0.75,
		max(exp(-pow(d_rapid1 / 1.20, 2.0)) * 0.60, exp(-pow(d_rapid2 / 1.10, 2.0)) * 0.55)
	) * smoothstep(0.05, 0.24, water_depth);
	float streak_n = fbm(vec2(v_world_pos.x * 2.8 + sin(v_world_pos.z * 0.5) * 0.9, v_world_pos.z * 0.85 - t * 2.65));
	float rapid_wisps = smoothstep(0.62, 0.84, streak_n * (0.65 + 0.55 * fn2)) * (rapid_zone * 0.65 + rapids_weight * 0.25);

	// 3) Sunlit wave crest glints
	float sun_glint = smoothstep(0.80, 0.92, h1) * 0.28;

	float total_foam = clamp(shore_lace + rapid_wisps + sun_glint, 0.0, 0.68);
	ALBEDO = mix(water_col, foam_color.rgb, total_foam);
	ROUGHNESS = mix(0.06, 0.34, total_foam);
	METALLIC = 0.03;
	SPECULAR = 0.88;

	// Smooth transparent feathering at the water's edge so wet pebbles blend seamlessly
	float shore_feather = smoothstep(0.0, 0.09, water_depth);
	float base_alpha = mix(shallow_color.a, deep_color.a, smoothstep(0.06, 0.72, water_depth));
	ALPHA = clamp(base_alpha + total_foam * 0.18, 0.0, 0.88) * shore_feather;
}
