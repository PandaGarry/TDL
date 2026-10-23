shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, diffuse_burley, specular_schlick_ggx;

// Step 2 Nivarel Mountain River Water Shader (v9 — Physical Sky/Bank Reflections, Boulder Wakes & Shore Foam):
// - Low-roughness mirror-clear mountain water (Roughness 0.06..0.14, Specular 0.78) with analytic sky, cloud & green-bank reflections
// - Multi-layered scrolling wave normal maps with crisp sunlit specular glints
// - Physical white water foam rings & downstream V-wakes around bridge stone piers and in-stream boulders
// - Beer-Lambert optical depth absorption: golden-pebble shallows -> deep emerald-sapphire channel

uniform vec4 shallow_color : source_color = vec4(0.16, 0.31, 0.22, 0.22);
uniform vec4 mid_color : source_color = vec4(0.05, 0.24, 0.23, 0.72);
uniform vec4 deep_color : source_color = vec4(0.02, 0.13, 0.18, 0.94);
uniform vec4 sky_reflection_tint : source_color = vec4(0.62, 0.78, 0.92, 1.0);
uniform vec4 foam_color : source_color = vec4(0.90, 0.94, 0.92, 1.0);
uniform float flow_speed = 0.58;
uniform float wave_height = 0.022;
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
	vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
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
		p = rot * p * 2.04;
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
			o = 0.5 + 0.42 * sin(TIME * 1.9 + 6.2831 * o);
			vec2 r = g + o - f;
			float d = dot(r, r);
			md = min(md, d);
		}
	}
	return pow(clamp(1.0 - sqrt(md), 0.0, 1.0), 3.0);
}

vec3 procedural_riverbed(vec2 uv) {
	float n_macro = fbm(uv * 2.4);
	float n_peb1 = noise(uv * 10.5);
	float n_peb2 = noise(uv * 22.0 + vec2(4.7, 9.2));
	vec3 sand_col = vec3(0.30, 0.26, 0.18);
	vec3 olive_pebble = vec3(0.19, 0.25, 0.16);
	vec3 amber_pebble = vec3(0.36, 0.29, 0.19);
	vec3 col = mix(sand_col, olive_pebble, smoothstep(0.28, 0.72, n_macro));
	col = mix(col, amber_pebble, smoothstep(0.48, 0.82, n_peb1) * 0.68);
	col *= (0.86 + 0.28 * n_peb2);
	return col;
}

// Compute foam ring + downstream V-wake around an obstacle at `obs_xz` with radius `rad`
float obstacle_foam_wake(vec2 pos_xz, vec2 obs_xz, float rad, float t, float n_turb) {
	vec2 rel = pos_xz - obs_xz;
	// River flows along +Z / slight +X; rotate wake frame slightly along channel
	vec2 flow_rel = vec2(rel.x - rel.y * 0.16, rel.y);
	float d = length(rel);
	// Upstream & side collar ring right around the boulder/pier waterline
	float ring_dist = abs(d - rad * 0.95);
	float collar = exp(-pow(ring_dist / (rad * 0.38), 2.0)) * smoothstep(0.20, 0.72, n_turb);
	// Downstream V-shaped turbulent wake trail
	float down_z = clamp(flow_rel.y, 0.0, rad * 4.2);
	float wake_half_w = rad * 0.55 + down_z * 0.34;
	float cross_d = abs(flow_rel.x);
	float wake_env = (1.0 - smoothstep(wake_half_w * 0.35, wake_half_w, cross_d))
		* (1.0 - smoothstep(0.0, rad * 4.0, down_z))
		* step(0.0, flow_rel.y + rad * 0.25);
	float v_ripples = sin(cross_d * 5.2 - down_z * 2.4 + t * 4.2) * 0.5 + 0.5;
	float tail = wake_env * smoothstep(0.32, 0.78, n_turb * 0.65 + v_ripples * 0.45) * 0.82;
	return clamp(collar + tail, 0.0, 1.0);
}

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_bathymetry = COLOR.rgb; // R = shore_prox, G = water_depth, B = rapids_fac
	float depth_atten = clamp(COLOR.g * 1.45, 0.06, 1.0);
	float t = TIME * flow_speed;
	float w1 = sin(v_world_pos.x * 1.75 - t * 3.8 + v_world_pos.z * 1.05);
	float w2 = cos(v_world_pos.x * 3.25 - t * 5.1 - v_world_pos.z * 1.95) * 0.55;
	float w3 = sin(v_world_pos.x * 5.40 + t * 4.2 + v_world_pos.z * 3.60) * 0.25;
	VERTEX.y += (w1 + w2 + w3) * wave_height * depth_atten;
}

void fragment() {
	float t = TIME * flow_speed;
	float water_depth = clamp(v_bathymetry.g, 0.0, 1.0);
	float rapids_weight = clamp(v_bathymetry.b, 0.0, 1.0);

	// 1) Crisp 3-layer scrolling normal map for lively current & capillary ripples
	vec2 flow_uv1 = v_world_pos.xz * vec2(0.72, 0.94) + vec2(-t * 0.38, -t * 1.55);
	vec2 flow_uv2 = v_world_pos.xz * vec2(1.55, 1.92) + vec2(t * 0.34, -t * 2.35);
	vec2 flow_uv3 = v_world_pos.xz * vec2(3.40, 3.95) + vec2(-t * 0.52, -t * 3.20);

	float eps = 0.045;
	float h0 = fbm(flow_uv1) * 0.52 + fbm(flow_uv2) * 0.32 + noise(flow_uv3) * 0.16;
	float hx = fbm(flow_uv1 + vec2(eps, 0.0)) * 0.52 + fbm(flow_uv2 + vec2(eps, 0.0)) * 0.32 + noise(flow_uv3 + vec2(eps, 0.0)) * 0.16;
	float hz = fbm(flow_uv1 + vec2(0.0, eps)) * 0.52 + fbm(flow_uv2 + vec2(0.0, eps)) * 0.32 + noise(flow_uv3 + vec2(0.0, eps)) * 0.16;

	vec2 wave_grad = vec2(h0 - hx, h0 - hz) / eps;
	vec3 wave_nrm_world = normalize(vec3(wave_grad.x * 0.34, 1.0, wave_grad.y * 0.34));
	NORMAL = normalize((VIEW_MATRIX * vec4(wave_nrm_world, 0.0)).xyz);

	// 2) Refracted riverbed pebbles & sunlit Voronoi caustics in clear shallows
	vec2 pebble_uv = v_world_pos.xz * 0.46 + wave_grad * 0.06;
	vec3 bed_pebbles = procedural_riverbed(pebble_uv);

	if (water_depth < 0.82 && length(v_world_pos.xz) < 54.0) {
		float caustics = voronoi_caustics(v_world_pos.xz * 1.95 + wave_grad * 0.18 + vec2(-t * 0.35, -t * 1.15));
		bed_pebbles += vec3(0.26, 0.28, 0.16) * caustics * (1.0 - smoothstep(0.12, 0.78, water_depth));
	}

	// 3) Beer-Lambert depth absorption: golden-emerald shallows -> deep sapphire-teal channel
	vec3 water_tint = mix(shallow_color.rgb, mid_color.rgb, smoothstep(0.08, 0.44, water_depth));
	water_tint = mix(water_tint, deep_color.rgb, smoothstep(0.38, 0.84, water_depth));
	float silt_fac = clamp((silt_load - 0.20) * 1.35, 0.0, 0.65);
	water_tint = mix(water_tint, vec3(0.25, 0.21, 0.13), silt_fac);

	float bed_visibility = exp(-water_depth * (2.9 + silt_fac * 1.5)) * 0.82;
	vec3 water_col = mix(water_tint, bed_pebbles, bed_visibility);

	// 4) Analytic Sky, Cloud, Green-Bank & Sun Specular Reflections (works in both Forward+ and gl_compatibility)
	vec3 view_world = normalize((INV_VIEW_MATRIX * vec4(-VIEW, 0.0)).xyz);
	vec3 refl_world = reflect(-view_world, wave_nrm_world);
	float ndotv = clamp(dot(wave_nrm_world, view_world), 0.0, 1.0);
	float fresnel = 0.06 + 0.66 * pow(1.0 - ndotv, 3.6);

	// Reflected environment dome: green grassy banks at low elevation, azure sky & clouds higher up
	vec3 bank_refl = vec3(0.14, 0.26, 0.11);
	vec3 horizon_refl = vec3(0.66, 0.78, 0.86);
	vec3 zenith_refl = sky_reflection_tint.rgb * vec3(0.58, 0.74, 0.92);
	float cloud_refl = fbm(refl_world.xz * 1.8 + vec2(t * 0.05, -t * 0.03));
	vec3 sky_refl = mix(horizon_refl, zenith_refl, smoothstep(0.05, 0.65, max(refl_world.y, 0.0)));
	sky_refl = mix(sky_refl, vec3(0.88, 0.90, 0.86), smoothstep(0.48, 0.78, cloud_refl) * 0.42);
	vec3 env_refl = mix(bank_refl, sky_refl, smoothstep(0.02, 0.26, refl_world.y));

	// Bridge shadow & underside timber reflection under NivarelBridge3D
	float bridge_z_center = 1.95 + 0.55 * sin(v_world_pos.x * 0.055 + 0.35);
	float under_bridge = (1.0 - smoothstep(1.35, 2.25, abs(v_world_pos.z - bridge_z_center)))
		* (1.0 - smoothstep(5.2, 6.6, abs(v_world_pos.x - 12.0)));
	env_refl = mix(env_refl, vec3(0.16, 0.12, 0.08), under_bridge * 0.75);

	water_col = mix(water_col, env_refl, fresnel * (0.58 + 0.28 * water_depth));
	water_col *= mix(1.0, 0.64, under_bridge);

	// 5) Crisp shoreline foam lace along both grassy riverbanks
	float fn1 = fbm(v_world_pos.xz * 2.6 + vec2(-t * 0.42, -t * 1.55));
	float fn2 = fbm(v_world_pos.xz * 4.8 + vec2(t * 0.34, -t * 2.25));
	float n_turb = fn1 * 0.55 + fn2 * 0.45;
	float shore_band = (1.0 - smoothstep(0.02, 0.18, water_depth)) * smoothstep(0.004, 0.028, water_depth);
	float shore_lace = smoothstep(0.36, 0.64, n_turb + shore_band * 0.22) * shore_band * 0.78;

	// 6) Physical white water foam rings & V-wakes around Bridge Piers & River Boulders
	float wake = 0.0;
	// Bridge stone piers (`pier_xs = [6.35, 9.85, 14.15, 17.65]`)
	wake = max(wake, obstacle_foam_wake(v_world_pos.xz, vec2(6.35, 2.15), 0.95, t, n_turb));
	wake = max(wake, obstacle_foam_wake(v_world_pos.xz, vec2(9.85, 2.22), 1.05, t, n_turb));
	wake = max(wake, obstacle_foam_wake(v_world_pos.xz, vec2(14.15, 2.28), 1.05, t, n_turb));
	wake = max(wake, obstacle_foam_wake(v_world_pos.xz, vec2(17.65, 2.34), 0.95, t, n_turb));
	// In-stream rapids boulders & shoreline boulders touching water
	wake = max(wake, obstacle_foam_wake(v_world_pos.xz, vec2(9.4, -5.8), 1.15, t, n_turb));
	wake = max(wake, obstacle_foam_wake(v_world_pos.xz, vec2(13.8, -12.4), 1.25, t, n_turb));
	wake = max(wake, obstacle_foam_wake(v_world_pos.xz, vec2(7.2, 8.8), 1.10, t, n_turb));
	wake = max(wake, obstacle_foam_wake(v_world_pos.xz, vec2(3.8, 0.6), 1.20, t, n_turb));
	wake = max(wake, obstacle_foam_wake(v_world_pos.xz, vec2(19.4, 3.8), 1.20, t, n_turb));
	wake = max(wake, obstacle_foam_wake(v_world_pos.xz, vec2(4.2, -3.5), 1.15, t, n_turb));
	wake = max(wake, obstacle_foam_wake(v_world_pos.xz, vec2(15.2, -4.8), 1.20, t, n_turb));

	// Longitudinal current streaks along the main thalweg
	float streak_n = fbm(vec2(v_world_pos.x * 2.8 + sin(v_world_pos.z * 0.5) * 0.7, v_world_pos.z * 0.85 - t * 2.45));
	float current_wisps = smoothstep(0.52, 0.76, streak_n * 0.65 + fn2 * 0.45) * (rapids_weight * 0.35 + 0.14) * smoothstep(0.08, 0.35, water_depth);

	// 7) Sunlit wave crest glints & sparkling water highlights
	vec3 sun_dir = normalize(vec3(0.45, 0.68, 0.58));
	vec3 half_vec = normalize(sun_dir + view_world);
	float spec_glint = pow(clamp(dot(wave_nrm_world, half_vec), 0.0, 1.0), 48.0) * (1.0 - under_bridge * 0.85);
	float crest_glint = smoothstep(0.66, 0.84, h0) * 0.28 * (1.0 - under_bridge * 0.75);

	float total_foam = clamp(shore_lace + wake * 0.82 + current_wisps + crest_glint, 0.0, 0.82);
	vec3 final_rgb = mix(water_col, foam_color.rgb, total_foam);
	final_rgb += vec3(0.95, 0.92, 0.80) * spec_glint * 0.52;

	ALBEDO = final_rgb;
	ROUGHNESS = mix(0.07, 0.44, total_foam);
	METALLIC = 0.02;
	SPECULAR = 0.78;

	float shore_feather = smoothstep(0.0, 0.06, water_depth);
	float base_alpha = mix(shallow_color.a, deep_color.a, smoothstep(0.05, 0.62, water_depth));
	ALPHA = clamp(base_alpha + fresnel * 0.24 + silt_fac * 0.12 + total_foam * 0.28, 0.0, 0.96) * shore_feather;
}
