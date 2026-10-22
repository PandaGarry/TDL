shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// Step 1 CBT Proving Ground Terrain Shader (v3):
// - Per-pixel analytical SDF road network with twin wheel ruts, longitudinal rain/wheel grooves,
//   mossy center median, and natural eroded humus verges.
// - Isolated rounded embedded stones & gravel (zero hexagonal Voronoi cell-border lines!).
// - High-definition 3D micro-normal soil, root thatch, and moss cushions under the grass.
// - Crisp stratified limestone & moss ledges along stepped hillside terraces.

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

vec2 hash22(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.xx + p3.yz) * p3.zy);
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

// Isolated natural rounded pebbles/stones embedded in soil (NO Voronoi polygon cell lines!):
// Returns vec3(stone_dome_height, stone_id_hash, stone_rim_ao)
vec3 embedded_pebbles(vec2 p) {
	vec2 n = floor(p);
	vec2 f = fract(p);
	float warp = (value_noise(p * 2.3) - 0.5) * 0.08;
	float best_dome = 0.0;
	float best_id = 0.0;
	float rim_ao = 0.0;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 g = vec2(float(i), float(j));
			vec2 cell = n + g;
			float id = hash12(cell + vec2(7.1, 3.3));
			// Sparse distribution so compacted earth dominates between stones
			if (id < 0.54) {
				continue;
			}
			vec2 o = 0.22 + 0.56 * hash22(cell);
			vec2 r = g + o - f;
			float ang = id * 6.283;
			float ca = cos(ang);
			float sa = sin(ang);
			vec2 rot_r = vec2(ca * r.x - sa * r.y, sa * r.x + ca * r.y);
			float d = length(rot_r * vec2(1.0, 1.28)) + warp;
			float rad = 0.16 + fract(id * 13.7) * 0.15;
			if (d < rad * 1.28) {
				float norm_d = clamp(d / rad, 0.0, 1.0);
				float dome = (1.0 - norm_d * norm_d);
				dome = pow(dome, 0.75);
				if (dome > best_dome) {
					best_dome = dome;
					best_id = id;
				}
				float collar = smoothstep(rad * 1.26, rad * 0.96, d) * smoothstep(rad * 0.68, rad * 0.96, d);
				rim_ao = max(rim_ao, collar);
			}
		}
	}
	return vec3(best_dome, best_id, rim_ao);
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

float main_road_z(float wx) {
	return -2.2 + sin(wx * 0.085 + 0.35) * 3.8 + cos(wx * 0.045 - 0.4) * 1.9 - wx * 0.06;
}

// Per-pixel road network evaluation:
// Returns vec4(road_core_mask, wheel_rut_intensity, median_strip_mask, longitudinal_groove)
vec4 eval_road_network(vec2 xz) {
	float wx = xz.x;
	float wz = xz.y;

	float warp_a = (fbm(xz * 0.55) - 0.5) * 0.24 + (value_noise(xz * 2.1) - 0.5) * 0.08;

	// 1. Main valley two-track cart road
	float rz = main_road_z(wx);
	float dz_dx = cos(wx * 0.085 + 0.35) * 0.323 - sin(wx * 0.045 - 0.4) * 0.0855 - 0.06;
	float d_main = abs(wz - rz) / sqrt(1.0 + dz_dx * dz_dx);
	float fade_main = smoothstep(-64.0, -52.0, wx) * (1.0 - smoothstep(52.0, 64.0, wx));

	// 2. NW Overlook terrace trail
	float bx = -3.5 + (wz + 3.6) * 0.55 + sin((wz + 3.6) * 0.16) * 2.2;
	float dx_dz_n = 0.55 + cos((wz + 3.6) * 0.16) * 0.352;
	float d_north = abs(wx - bx) / sqrt(1.0 + dx_dz_n * dx_dz_n);
	float fade_north = smoothstep(rz + 0.8, rz - 0.9, wz) * (1.0 - smoothstep(-42.0, -52.0, wz));

	// 3. SE Meadow basin trail
	float sx = 5.5 + (wz + 1.8) * 0.48 + sin((wz + 1.8) * 0.18) * 1.8;
	float dx_dz_s = 0.48 + cos((wz + 1.8) * 0.18) * 0.324;
	float d_south = abs(wx - sx) / sqrt(1.0 + dx_dz_s * dx_dz_s);
	float fade_south = smoothstep(rz - 0.8, rz + 0.9, wz) * (1.0 - smoothstep(20.0, 28.0, wz));

	float u_main = (d_main + warp_a) / 1.32;
	float u_north = (d_north + warp_a * 0.85) / 0.96;
	float u_south = (d_south + warp_a * 0.85) / 0.90;

	float m_main = (1.0 - smoothstep(0.68, 1.05, u_main)) * fade_main;
	float m_north = (1.0 - smoothstep(0.66, 1.04, u_north)) * fade_north;
	float m_south = (1.0 - smoothstep(0.66, 1.04, u_south)) * fade_south;
	float road_core = clamp(max(m_main, max(m_north, m_south)), 0.0, 1.0);

	// Distinct twin wheel ruts on the main road & footpaths
	float rut_main = exp(-pow((d_main - 0.52 + warp_a * 0.30) / 0.25, 2.0)) * fade_main;
	float rut_north = exp(-pow((d_north - 0.30 + warp_a * 0.25) / 0.21, 2.0)) * fade_north;
	float rut_south = exp(-pow((d_south - 0.28 + warp_a * 0.25) / 0.20, 2.0)) * fade_south;
	float ruts = clamp(max(rut_main, max(rut_north * 0.85, rut_south * 0.85)), 0.0, 1.0);

	// Center grassy/mossy crown between the two wheel ruts on the main road
	float median_noise = fbm(xz * 0.95 + vec2(2.1, -1.4));
	float median = exp(-pow(d_main / 0.25, 2.0)) * fade_main * smoothstep(0.26, 0.70, median_noise);
	median *= (1.0 - max(m_north, m_south) * 0.85);

	// Longitudinal wheel/rain groove pattern running along the trail direction
	float groove_main = sin(d_main * 22.0 + fbm(vec2(wx * 0.45, wz * 1.8)) * 3.2) * 0.5 + 0.5;
	float groove_branch = sin(min(d_north, d_south) * 24.0 + fbm(vec2(wx * 1.6, wz * 0.45)) * 3.2) * 0.5 + 0.5;
	float groove = mix(groove_branch, groove_main, step(max(m_north, m_south), m_main));

	return vec4(road_core, ruts, median, groove);
}

// Micro-heightfield used for analytical per-pixel 3D normal mapping
float eval_micro_height(vec2 xz, vec4 road_info, float slope) {
	float road_core = road_info.x;
	float ruts = road_info.y;
	float median = road_info.z;
	float groove = road_info.w;

	// 1. Rich forest-meadow soil clods, root network & mossy cushions under grass
	float moss_pillow = fbm(xz * 1.85);
	float soil_clods = fbm(xz * 5.6 + vec2(3.7, 1.9));
	float fine_grit = value_noise(xz * 18.0);
	float turf_h = moss_pillow * 0.036 + soil_clods * 0.018 + fine_grit * 0.006;

	// 2. Road profile: sunken ruts with longitudinal wheel grooves + sparse embedded rounded stones
	vec3 peb_a = embedded_pebbles(xz * 2.6);
	vec3 peb_b = embedded_pebbles(xz * 5.8 + vec2(11.3, 4.7));
	float stone_zone = clamp(ruts * 0.78 + road_core * 0.32 - median * 0.75, 0.0, 1.0);
	float stone_h = (peb_a.x * 0.024 + peb_b.x * 0.012) * stone_zone;
	float rut_depression = -ruts * 0.042 + (groove - 0.5) * ruts * 0.014 + median * 0.024;
	float road_h = rut_depression + stone_h + soil_clods * 0.012 + fine_grit * 0.005;

	// 3. Stratified limestone ledges on hillside terrace breaks
	float ledge_mask = smoothstep(0.11, 0.26, slope) * (1.0 - road_core);
	float strata_bands = sin(xz.x * 1.2 + xz.y * 1.6 + fbm(xz * 0.85) * 3.8);
	float rock_h = (smoothstep(-0.35, 0.45, strata_bands) * 0.065 + soil_clods * 0.022) * ledge_mask;

	return mix(turf_h, road_h, road_core) + rock_h;
}

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_weights = COLOR;
	v_path_and_wet = UV2;
}

void fragment() {
	vec2 xz = v_world_pos.xz;
	float slope = 1.0 - clamp(v_world_nrm.y, 0.0, 1.0);
	vec4 road_info = eval_road_network(xz);
	float road_core = road_info.x;
	float ruts = road_info.y;
	float median = road_info.z;
	float groove = road_info.w;

	// --- 1. Analytical 3D Micro-Normal Mapping ---
	float eps = 0.022;
	float h0 = eval_micro_height(xz, road_info, slope);
	float hx = eval_micro_height(xz + vec2(eps, 0.0), road_info, slope);
	float hz = eval_micro_height(xz + vec2(0.0, eps), road_info, slope);
	vec3 d_h = vec3((h0 - hx) / eps, 0.0, (h0 - hz) / eps);
	float dist_atten = 1.0 - smoothstep(26.0, 68.0, length(xz));
	vec3 world_nrm = normalize(v_world_nrm + d_h * (1.25 * dist_atten + 0.30));
	NORMAL = normalize((VIEW_MATRIX * vec4(world_nrm, 0.0)).xyz);

	// --- 2. Rich Multi-Layered Under-Grass Soil, Humus, Root Litter & Moss Cushions ---
	vec3 base_meadow = meadow_ground_palette(xz);
	float moss_n = fbm(xz * 1.85);
	float humus_n = fbm(xz * 5.2 + vec2(6.1, -2.3));
	float grit_n = value_noise(xz * 16.0);

	vec3 humus_dark = vec3(0.13, 0.15, 0.09);
	vec3 moss_cushion = vec3(0.23, 0.37, 0.14);
	vec3 dry_thatch = vec3(0.30, 0.27, 0.16);
	vec3 detailed_turf = mix(humus_dark, base_meadow, smoothstep(0.20, 0.64, moss_n));
	detailed_turf = mix(detailed_turf, moss_cushion, smoothstep(0.54, 0.85, moss_n) * 0.68);
	detailed_turf = mix(detailed_turf, dry_thatch, smoothstep(0.64, 0.88, humus_n) * 0.42);
	detailed_turf *= (0.90 + 0.20 * grit_n);

	float warm_patch = fbm(xz * 0.08 + vec2(3.1, 1.7));
	vec3 far_tip_col = mix(vec3(0.24, 0.39, 0.15), vec3(0.33, 0.45, 0.18), smoothstep(0.28, 0.76, warm_patch));
	float far_blend = smoothstep(42.0, 66.0, length(xz));
	vec3 col = mix(detailed_turf, far_tip_col * (0.94 + 0.12 * moss_n), far_blend * 0.72);
	float rough = 0.91;

	// --- 3. Stratified Limestone & Mossy Rock Ledges on Hillside Terrace Slopes ---
	float ledge_mask = smoothstep(0.11, 0.25, slope) * (1.0 - road_core);
	if (ledge_mask > 0.01) {
		float strata = sin(v_world_pos.y * 9.5 + fbm(xz * 0.85) * 3.2) * 0.5 + 0.5;
		float fracture = fbm(xz * 3.4);
		vec3 limestone_warm = vec3(0.44, 0.41, 0.36);
		vec3 slate_dark = vec3(0.25, 0.27, 0.27);
		vec3 rock_col = mix(slate_dark, limestone_warm, smoothstep(0.22, 0.78, strata * 0.68 + fracture * 0.32));
		rock_col *= (0.88 + 0.22 * grit_n);
		float ledge_moss = smoothstep(0.45, 0.76, moss_n) * (1.0 - smoothstep(0.22, 0.38, slope));
		rock_col = mix(rock_col, moss_cushion, ledge_moss * 0.62);
		col = mix(col, rock_col, ledge_mask * 0.92);
		rough = mix(rough, 0.76, ledge_mask);
	}

	// --- 4. Natural Two-Track Earthen Road with Wheel Grooves, Mossy Median & Earthy Pebbles ---
	if (road_core > 0.01) {
		// 4a. Earthy humus & trampled dry grass verge along road shoulders
		float shoulder = smoothstep(0.05, 0.45, road_core) * (1.0 - smoothstep(0.45, 0.82, road_core));
		vec3 verge_loam = mix(vec3(0.20, 0.23, 0.13), vec3(0.28, 0.24, 0.15), humus_n);
		verge_loam *= (0.88 + 0.22 * grit_n);

		// 4b. Warm compacted loam + darker damp wheel ruts with longitudinal groove shading
		vec3 dry_loam = vec3(0.39, 0.31, 0.21) * (0.91 + 0.18 * humus_n);
		vec3 sandy_shoulder = vec3(0.44, 0.36, 0.25) * (0.92 + 0.16 * grit_n);
		vec3 damp_rut = vec3(0.26, 0.20, 0.14) * (0.88 + 0.16 * groove + 0.10 * grit_n);

		vec3 road_soil = mix(sandy_shoulder, dry_loam, smoothstep(0.25, 0.65, road_core));
		road_soil = mix(road_soil, damp_rut, smoothstep(0.15, 0.80, ruts));
		road_soil = mix(road_soil, verge_loam, shoulder * 0.65);

		// 4c. Overgrown mossy/grassy center median strip between the two wheel ruts
		vec3 median_turf = mix(vec3(0.21, 0.32, 0.14), vec3(0.28, 0.35, 0.16), moss_n) * (0.90 + 0.18 * grit_n);
		road_soil = mix(road_soil, median_turf, clamp(median * 0.90, 0.0, 1.0));

		// 4d. Sparse, natural earthy-ochre & weathered-slate pebbles embedded in the soil
		vec3 peb1 = embedded_pebbles(xz * 2.6);
		vec3 peb2 = embedded_pebbles(xz * 5.8 + vec2(11.3, 4.7));
		float stone_zone = clamp(ruts * 0.82 + road_core * 0.35 - median * 0.80, 0.0, 1.0);
		float m_peb1 = smoothstep(0.10, 0.45, peb1.x) * stone_zone;
		float m_peb2 = smoothstep(0.15, 0.50, peb2.x) * stone_zone * (1.0 - m_peb1);

		vec3 peb_sandstone = vec3(0.43, 0.36, 0.27);
		vec3 peb_weathered = vec3(0.34, 0.31, 0.26);
		vec3 peb_ochre = vec3(0.46, 0.39, 0.29);
		vec3 pcol1 = mix(peb_weathered, peb_sandstone, fract(peb1.y * 9.1));
		pcol1 = mix(pcol1, peb_ochre, smoothstep(0.75, 0.95, peb1.y)) * (0.90 + 0.18 * grit_n);
		vec3 pcol2 = mix(peb_weathered, peb_ochre, fract(peb2.y * 7.3)) * (0.88 + 0.20 * grit_n);

		// Subtle soil collar AO around individual stones only (no cell borders!)
		float collar_ao = 1.0 - clamp((peb1.z * 0.32 + peb2.z * 0.20) * stone_zone, 0.0, 0.38);
		road_soil *= collar_ao;
		road_soil = mix(road_soil, pcol1, m_peb1 * 0.78);
		road_soil = mix(road_soil, pcol2, m_peb2 * 0.65);

		float smooth_edge = smoothstep(0.05, 0.52, road_core);
		col = mix(col, road_soil, smooth_edge);
		float road_rough = mix(0.92, 0.76, ruts * 0.55 + m_peb1 * 0.45);
		rough = mix(rough, road_rough, smooth_edge);
	}

	// --- 5. Distant Valley Rim Atmospheric Perspective ---
	float rim_haze = smoothstep(62.0, 96.0, length(xz));
	col = mix(col, vec3(0.32, 0.42, 0.35), rim_haze * 0.42);

	ALBEDO = col;
	ROUGHNESS = rough;
	SPECULAR = 0.08;
}
