shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// Step 1 CBT Proving Ground Terrain Shader (v4):
// - Organic junction blending (side trails merge naturally into the near rut without dark "railroad"
//   stripes cutting across the fork).
// - Multi-octave 3D micro-normal soil clods, fine grit, dry crust fissures, and root litter.
// - Irregular, faceted weathered fieldstones partially buried under soil dust (zero cartoon circles
//   or dark outline rings!).
// - Wide humus-and-moss verge transition under roadside grass so grass tufts grow out of rich earth.

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

// Irregular, faceted & partially soil-buried fieldstones + coarse gravel
// (NO circular outlines, NO Voronoi cell borders):
// Returns vec2(buried_stone_height, stone_id_hash)
vec2 irregular_fieldstones(vec2 p) {
	vec2 p_warped = p + vec2(fbm(p * 1.9) - 0.5, fbm(p * 1.9 + vec2(4.3, 8.1)) - 0.5) * 0.52;
	vec2 n = floor(p_warped);
	vec2 f = fract(p_warped);
	float best_h = 0.0;
	float best_id = 0.0;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 g = vec2(float(i), float(j));
			vec2 cell = n + g;
			float id = hash12(cell + vec2(7.1, 3.3));
			// Sparse distribution so compacted earth & fine grit dominate
			if (id < 0.68) {
				continue;
			}
			vec2 o = 0.25 + 0.50 * hash22(cell);
			vec2 r = g + o - f;
			float ang = id * 6.283;
			float ca = cos(ang);
			float sa = sin(ang);
			vec2 rot_r = vec2(ca * r.x - sa * r.y, sa * r.x + ca * r.y);
			// Angular faceted distance metric instead of round circles
			vec2 aspect = vec2(1.0 + fract(id * 5.7) * 0.65, 1.0 + fract(id * 11.3) * 0.45);
			vec2 q = abs(rot_r * aspect);
			float d_oct = max(q.x, q.y) * 0.58 + (q.x + q.y) * 0.42;
			float rad = 0.11 + fract(id * 13.7) * 0.13;
			if (d_oct < rad) {
				float norm_d = clamp(d_oct / rad, 0.0, 1.0);
				// Flat-topped weathered stone gently sloping into the surrounding soil
				float h = smoothstep(1.0, 0.28, norm_d);
				if (h > best_h) {
					best_h = h;
					best_id = id;
				}
			}
		}
	}
	return vec2(best_h, best_id);
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

// Per-pixel road network evaluation with natural fork/junction blending:
// Returns vec4(road_core_mask, wheel_rut_intensity, median_strip_mask, verge_soil_halo)
vec4 eval_road_network(vec2 xz) {
	float wx = xz.x;
	float wz = xz.y;

	float warp_a = (fbm(xz * 0.65) - 0.5) * 0.26 + (value_noise(xz * 2.4) - 0.5) * 0.09;

	// 1. Main valley two-track cart road
	float rz = main_road_z(wx);
	float dz_dx = cos(wx * 0.085 + 0.35) * 0.323 - sin(wx * 0.045 - 0.4) * 0.0855 - 0.06;
	float signed_main = (wz - rz) / sqrt(1.0 + dz_dx * dz_dx);
	float d_main = abs(signed_main);
	float fade_main = smoothstep(-66.0, -54.0, wx) * (1.0 - smoothstep(54.0, 66.0, wx));

	// 2. NW Overlook terrace trail (approaches main road from the NORTH side: signed_main < 0)
	float bx = -3.5 + (wz + 3.6) * 0.55 + sin((wz + 3.6) * 0.16) * 2.2;
	float dx_dz_n = 0.55 + cos((wz + 3.6) * 0.16) * 0.352;
	float d_north = abs(wx - bx) / sqrt(1.0 + dx_dz_n * dx_dz_n);
	float fade_north = smoothstep(rz + 0.35, rz - 0.85, wz) * (1.0 - smoothstep(-44.0, -54.0, wz));

	// 3. SE Meadow basin trail (approaches main road from the SOUTH side: signed_main > 0)
	float sx = 5.5 + (wz + 1.8) * 0.48 + sin((wz + 1.8) * 0.18) * 1.8;
	float dx_dz_s = 0.48 + cos((wz + 1.8) * 0.18) * 0.324;
	float d_south = abs(wx - sx) / sqrt(1.0 + dx_dz_s * dx_dz_s);
	float fade_south = smoothstep(rz - 0.35, rz + 0.85, wz) * (1.0 - smoothstep(20.0, 28.0, wz));

	float u_main = (d_main + warp_a) / 1.32;
	float u_north = (d_north + warp_a * 0.85) / 0.96;
	float u_south = (d_south + warp_a * 0.85) / 0.90;

	float m_main = (1.0 - smoothstep(0.64, 1.05, u_main)) * fade_main;
	float m_north = (1.0 - smoothstep(0.62, 1.04, u_north)) * fade_north;
	float m_south = (1.0 - smoothstep(0.62, 1.04, u_south)) * fade_south;
	float road_core = clamp(max(m_main, max(m_north, m_south)), 0.0, 1.0);

	// Wide organic humus halo extending under the roadside grass (eliminates neon-green islands)
	float h_main = (1.0 - smoothstep(0.75, 1.65, u_main)) * fade_main;
	float h_north = (1.0 - smoothstep(0.72, 1.68, u_north)) * fade_north;
	float h_south = (1.0 - smoothstep(0.72, 1.68, u_south)) * fade_south;
	float verge_halo = clamp(max(h_main, max(h_north, h_south)), 0.0, 1.0);

	// Natural wheel-rut blending at road forks (prevents straight dark stripes across intersections):
	// North rut (-0.50) softens where the north branch joins; South rut (+0.50) softens where south branch joins.
	float rut_n_track = exp(-pow((signed_main + 0.50 + warp_a * 0.28) / 0.27, 2.0)) * (1.0 - m_north * 0.55);
	float rut_s_track = exp(-pow((signed_main - 0.50 - warp_a * 0.28) / 0.27, 2.0)) * (1.0 - m_south * 0.55);
	float rut_main = max(rut_n_track, rut_s_track) * fade_main;

	// Branch ruts fade smoothly as they merge into the main roadbed
	float join_fade_n = smoothstep(0.15, 0.85, d_main);
	float join_fade_s = smoothstep(0.15, 0.85, d_main);
	float rut_north = exp(-pow((d_north - 0.28 + warp_a * 0.22) / 0.24, 2.0)) * fade_north * mix(0.45, 1.0, join_fade_n);
	float rut_south = exp(-pow((d_south - 0.26 + warp_a * 0.22) / 0.23, 2.0)) * fade_south * mix(0.45, 1.0, join_fade_s);
	float junction_bowl = m_main * max(m_north, m_south) * 0.52;
	float ruts = clamp(max(rut_main, max(max(rut_north * 0.82, rut_south * 0.82), junction_bowl)), 0.0, 1.0);

	// Center grassy/mossy crown between the two wheel ruts on the main road
	float median_noise = fbm(xz * 0.95 + vec2(2.1, -1.4));
	float median = exp(-pow(signed_main / 0.25, 2.0)) * fade_main * smoothstep(0.24, 0.68, median_noise);
	median *= (1.0 - max(m_north, m_south) * 0.92);

	return vec4(road_core, ruts, median, verge_halo);
}

// Multi-octave 3D micro-heightfield for crisp soil clods, coarse sand, root fibers & embedded stones
float eval_micro_height(vec2 xz, vec4 road_info, float slope) {
	float road_core = road_info.x;
	float ruts = road_info.y;
	float median = road_info.z;

	// 1. Multi-scale forest/meadow soil clods, root network & fine earth crumb
	float moss_h = fbm(xz * 1.9);
	float clod_h = fbm(xz * 6.8 + vec2(3.7, 1.9));
	float crumb_h = fbm(xz * 21.0 + vec2(-4.2, 7.5));
	float grit_h = value_noise(xz * 48.0);
	float turf_h = moss_h * 0.032 + clod_h * 0.022 + crumb_h * 0.011 + grit_h * 0.005;

	// 2. Road profile: gentle sunken wheel tracks + rough soil crumb + partially buried angular stones
	vec2 st1 = irregular_fieldstones(xz * 2.4);
	vec2 st2 = irregular_fieldstones(xz * 5.6 + vec2(9.4, 3.8));
	float dust_bury = smoothstep(0.25, 0.78, clod_h);
	float stone_zone = clamp(ruts * 0.72 + road_core * 0.35 - median * 0.80, 0.0, 1.0);
	float stone_h = (st1.x * (1.0 - dust_bury * 0.45) * 0.018 + st2.x * 0.009) * stone_zone;
	float rut_depression = -ruts * 0.034 + median * 0.022;
	float road_h = rut_depression + stone_h + clod_h * 0.018 + crumb_h * 0.012 + grit_h * 0.006;

	// 3. Stratified limestone ledges on hillside terrace breaks
	float ledge_mask = smoothstep(0.11, 0.25, slope) * (1.0 - road_core);
	float strata_bands = sin(xz.x * 1.2 + xz.y * 1.6 + fbm(xz * 0.85) * 3.8);
	float rock_h = (smoothstep(-0.35, 0.45, strata_bands) * 0.065 + clod_h * 0.024) * ledge_mask;

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
	float verge_halo = road_info.w;

	// --- 1. Analytical 3D Micro-Normal Mapping ---
	float eps = 0.018;
	float h0 = eval_micro_height(xz, road_info, slope);
	float hx = eval_micro_height(xz + vec2(eps, 0.0), road_info, slope);
	float hz = eval_micro_height(xz + vec2(0.0, eps), road_info, slope);
	vec3 d_h = vec3((h0 - hx) / eps, 0.0, (h0 - hz) / eps);
	float dist_atten = 1.0 - smoothstep(28.0, 74.0, length(xz));
	vec3 world_nrm = normalize(v_world_nrm + d_h * (1.35 * dist_atten + 0.32));
	NORMAL = normalize((VIEW_MATRIX * vec4(world_nrm, 0.0)).xyz);

	// --- 2. Rich Multi-Layered Under-Grass Soil, Humus, Root Litter & Moss Cushions ---
	vec3 base_meadow = meadow_ground_palette(xz);
	float moss_n = fbm(xz * 1.9);
	float clod_n = fbm(xz * 6.8 + vec2(6.1, -2.3));
	float crumb_n = fbm(xz * 21.0 + vec2(-3.4, 5.1));
	float grit_n = value_noise(xz * 48.0);

	vec3 humus_dark = vec3(0.13, 0.15, 0.09);
	vec3 moss_cushion = vec3(0.22, 0.36, 0.14);
	vec3 dry_thatch = vec3(0.28, 0.25, 0.15);
	vec3 detailed_turf = mix(humus_dark, base_meadow, smoothstep(0.20, 0.64, moss_n));
	detailed_turf = mix(detailed_turf, moss_cushion, smoothstep(0.54, 0.85, moss_n) * 0.65);
	detailed_turf = mix(detailed_turf, dry_thatch, smoothstep(0.58, 0.86, clod_n) * 0.45);
	detailed_turf *= (0.86 + 0.16 * crumb_n + 0.12 * grit_n);

	// Earthy humus/moss transition under roadside grass tufts so verge grass sits on natural forest soil
	vec3 roadside_under_soil = mix(vec3(0.18, 0.22, 0.11), vec3(0.25, 0.24, 0.14), clod_n) * (0.88 + 0.22 * crumb_n);
	detailed_turf = mix(detailed_turf, roadside_under_soil, verge_halo * 0.78);

	float warm_patch = fbm(xz * 0.08 + vec2(3.1, 1.7));
	vec3 far_tip_col = mix(vec3(0.23, 0.37, 0.15), vec3(0.31, 0.43, 0.17), smoothstep(0.28, 0.76, warm_patch));
	float far_blend = smoothstep(54.0, 82.0, length(xz));
	vec3 col = mix(detailed_turf, far_tip_col * (0.94 + 0.12 * moss_n), far_blend * 0.68);
	float rough = 0.92;

	// --- 3. Stratified Limestone & Mossy Rock Ledges on Hillside Terrace Slopes ---
	float ledge_mask = smoothstep(0.11, 0.25, slope) * (1.0 - road_core * 0.85);
	if (ledge_mask > 0.01) {
		float strata = sin(v_world_pos.y * 9.5 + fbm(xz * 0.85) * 3.2) * 0.5 + 0.5;
		float fracture = fbm(xz * 3.4);
		vec3 limestone_warm = vec3(0.43, 0.40, 0.35);
		vec3 slate_dark = vec3(0.24, 0.26, 0.26);
		vec3 rock_col = mix(slate_dark, limestone_warm, smoothstep(0.22, 0.78, strata * 0.68 + fracture * 0.32));
		rock_col *= (0.86 + 0.16 * crumb_n + 0.12 * grit_n);
		float ledge_moss = smoothstep(0.42, 0.74, moss_n) * (1.0 - smoothstep(0.22, 0.38, slope));
		rock_col = mix(rock_col, moss_cushion, ledge_moss * 0.65);
		col = mix(col, rock_col, ledge_mask * 0.90);
		rough = mix(rough, 0.78, ledge_mask);
	}

	// --- 4. Organic Two-Track Earthen Road with Rich Soil Crumb, Mossy Median & Buried Fieldstones ---
	if (road_core > 0.01) {
		// 4a. Multi-toned compacted loam, coarse sandy grit & damp wheel tracks
		vec3 dry_loam = vec3(0.35, 0.28, 0.19);
		vec3 coarse_sand = vec3(0.41, 0.33, 0.23);
		vec3 dark_humus_edge = vec3(0.22, 0.21, 0.13);
		vec3 damp_rut = vec3(0.24, 0.19, 0.13);

		vec3 road_soil = mix(dry_loam, coarse_sand, smoothstep(0.30, 0.75, clod_n) * 0.75);
		road_soil = mix(road_soil, dark_humus_edge, (1.0 - smoothstep(0.12, 0.62, road_core)) * 0.72);
		road_soil = mix(road_soil, damp_rut, smoothstep(0.18, 0.82, ruts) * (0.72 + 0.28 * crumb_n));

		// High-frequency soil crumb & pebble-sand grain (eliminates smooth plastic look!)
		float grain_mod = 0.82 + 0.22 * crumb_n + 0.14 * (grit_n - 0.35);
		road_soil *= grain_mod;

		// 4b. Overgrown mossy/grassy center median strip between the two wheel ruts
		vec3 median_turf = mix(vec3(0.20, 0.31, 0.13), vec3(0.27, 0.34, 0.15), moss_n) * grain_mod;
		road_soil = mix(road_soil, median_turf, clamp(median * 0.88, 0.0, 1.0));

		// 4c. Sparse, irregular weathered stones partially buried in soil dust (zero dark rings!)
		vec2 st1 = irregular_fieldstones(xz * 2.4);
		vec2 st2 = irregular_fieldstones(xz * 5.6 + vec2(9.4, 3.8));
		float dust_cover = smoothstep(0.32, 0.78, clod_n);
		float stone_zone = clamp(ruts * 0.75 + road_core * 0.32 - median * 0.82, 0.0, 1.0);
		float m_st1 = smoothstep(0.18, 0.65, st1.x) * (1.0 - dust_cover * 0.55) * stone_zone;
		float m_st2 = smoothstep(0.22, 0.68, st2.x) * (1.0 - dust_cover * 0.45) * stone_zone * (1.0 - m_st1);

		vec3 stone_slate = vec3(0.33, 0.30, 0.26) * grain_mod;
		vec3 stone_sand = vec3(0.40, 0.34, 0.26) * grain_mod;
		vec3 scol1 = mix(stone_slate, stone_sand, fract(st1.y * 9.1));
		vec3 scol2 = mix(stone_slate, stone_sand, fract(st2.y * 7.3));

		road_soil = mix(road_soil, scol1, m_st1 * 0.68);
		road_soil = mix(road_soil, scol2, m_st2 * 0.55);

		// Organic frayed road edge modulated by soil clods & moss
		float edge_noise = (clod_n - 0.5) * 0.18 + (crumb_n - 0.5) * 0.08;
		float smooth_edge = smoothstep(0.06, 0.54, road_core + edge_noise);
		col = mix(col, road_soil, smooth_edge);
		float road_rough = mix(0.93, 0.80, ruts * 0.45 + m_st1 * 0.35);
		rough = mix(rough, road_rough, smooth_edge);
	}

	// --- 5. Distant Valley Rim Atmospheric Perspective ---
	float rim_haze = smoothstep(66.0, 98.0, length(xz));
	col = mix(col, vec3(0.32, 0.42, 0.35), rim_haze * 0.42);

	ALBEDO = col;
	ROUGHNESS = rough;
	SPECULAR = 0.07;
}
