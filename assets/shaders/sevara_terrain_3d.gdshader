shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// Step 1 CBT Proving Ground Terrain Shader:
// - Per-pixel analytical Signed Distance Field (SDF) road & trail network (zero vertex blur)
// - Twin sunken wheel ruts, grassy/mossy center median, and natural eroded verges
// - Procedural Voronoi embedded cobbles & flat stones with per-stone tint, bevels & crevice AO
// - Rich 3D micro-normal soil, moss cushions & humus under the grass (finite-difference normal mapping)
// - Stratified limestone ledges along stepped hillside terraces

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

// Procedural Voronoi stone/cobble generator:
// Returns vec3(stone_dome_height, stone_id_hash, crevice_border_ao)
vec3 voronoi_stones(vec2 p) {
	vec2 n = floor(p);
	vec2 f = fract(p);
	float md1 = 8.0;
	float md2 = 8.0;
	float best_id = 0.0;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 g = vec2(float(i), float(j));
			vec2 o = hash22(n + g);
			vec2 r = g + (0.18 + 0.64 * o) - f;
			// Slightly anisotropic flat stones
			float d = length(r * vec2(1.0, 1.15));
			if (d < md1) {
				md2 = md1;
				md1 = d;
				best_id = hash12(n + g + vec2(7.1, 3.3));
			} else if (d < md2) {
				md2 = d;
			}
		}
	}
	float edge_dist = md2 - md1;
	// Only a subset of Voronoi cells contain a prominent stone so soil remains visible between them
	float presence = smoothstep(0.32, 0.52, best_id);
	float stone_shape = smoothstep(0.06, 0.22, edge_dist) * (1.0 - smoothstep(0.25, 0.58, md1));
	float dome = pow(clamp(stone_shape, 0.0, 1.0), 0.65) * presence;
	float crevice = smoothstep(0.14, 0.02, edge_dist) * presence;
	return vec3(dome, best_id, crevice);
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
// Returns vec4(road_core_mask, wheel_rut_intensity, median_strip_mask, verge_turf_mask)
vec4 eval_road_network(vec2 xz) {
	float wx = xz.x;
	float wz = xz.y;

	// Organic edge warp for natural hand-trodden trail borders
	float warp_a = (fbm(xz * 0.55) - 0.5) * 0.26 + (value_noise(xz * 2.1) - 0.5) * 0.09;

	// 1. Main valley two-track cart road
	float rz = main_road_z(wx);
	float dz_dx = cos(wx * 0.085 + 0.35) * 0.323 - sin(wx * 0.045 - 0.4) * 0.0855 - 0.06;
	float d_main = abs(wz - rz) / sqrt(1.0 + dz_dx * dz_dx);
	float fade_main = smoothstep(-56.0, -46.0, wx) * (1.0 - smoothstep(46.0, 56.0, wx));

	// 2. NW Overlook terrace trail
	float bx = -3.5 + (wz + 3.6) * 0.55 + sin((wz + 3.6) * 0.16) * 2.2;
	float dx_dz_n = 0.55 + cos((wz + 3.6) * 0.16) * 0.352;
	float d_north = abs(wx - bx) / sqrt(1.0 + dx_dz_n * dx_dz_n);
	float fade_north = smoothstep(rz + 0.8, rz - 0.9, wz) * (1.0 - smoothstep(-32.0, -39.0, wz));

	// 3. SE Meadow basin trail
	float sx = 5.5 + (wz + 1.8) * 0.48 + sin((wz + 1.8) * 0.18) * 1.8;
	float dx_dz_s = 0.48 + cos((wz + 1.8) * 0.18) * 0.324;
	float d_south = abs(wx - sx) / sqrt(1.0 + dx_dz_s * dx_dz_s);
	float fade_south = smoothstep(rz - 0.8, rz + 0.9, wz) * (1.0 - smoothstep(20.0, 27.0, wz));

	// Effective distance to nearest road centerline (normalized so 1.0 = outer edge of roadbed)
	float u_main = (d_main + warp_a) / 1.32;
	float u_north = (d_north + warp_a * 0.85) / 0.96;
	float u_south = (d_south + warp_a * 0.85) / 0.90;

	float m_main = (1.0 - smoothstep(0.68, 1.05, u_main)) * fade_main;
	float m_north = (1.0 - smoothstep(0.66, 1.04, u_north)) * fade_north;
	float m_south = (1.0 - smoothstep(0.66, 1.04, u_south)) * fade_south;
	float road_core = clamp(max(m_main, max(m_north, m_south)), 0.0, 1.0);

	// Distinct twin wheel ruts on the main road & footpaths
	float rut_main = exp(-pow((d_main - 0.52 + warp_a * 0.35) / 0.26, 2.0)) * fade_main;
	float rut_north = exp(-pow((d_north - 0.30 + warp_a * 0.30) / 0.22, 2.0)) * fade_north;
	float rut_south = exp(-pow((d_south - 0.28 + warp_a * 0.30) / 0.21, 2.0)) * fade_south;
	float ruts = clamp(max(rut_main, max(rut_north * 0.85, rut_south * 0.85)), 0.0, 1.0);

	// Center grassy/mossy crown between the two wheel ruts on the main road
	float median_noise = fbm(xz * 0.95 + vec2(2.1, -1.4));
	float median = exp(-pow(d_main / 0.26, 2.0)) * fade_main * smoothstep(0.28, 0.72, median_noise);
	// Suppress median right inside the crossroads intersection so tracks merge cleanly
	median *= (1.0 - max(m_north, m_south) * 0.85);

	// Outer trampled humus/moss verge along the road shoulders
	float v_main = smoothstep(0.55, 0.88, u_main) * (1.0 - smoothstep(0.95, 1.38, u_main)) * fade_main;
	float v_north = smoothstep(0.54, 0.86, u_north) * (1.0 - smoothstep(0.94, 1.35, u_north)) * fade_north;
	float v_south = smoothstep(0.54, 0.86, u_south) * (1.0 - smoothstep(0.94, 1.35, u_south)) * fade_south;
	float verge = clamp(max(v_main, max(v_north, v_south)), 0.0, 1.0);

	return vec4(road_core, ruts, median, verge);
}

// Micro-heightfield used for analytical per-pixel 3D normal mapping (soil clods, cobbles, ruts, rock ledges)
float eval_micro_height(vec2 xz, vec4 road_info, float slope) {
	float road_core = road_info.x;
	float ruts = road_info.y;
	float median = road_info.z;

	// 1. Soil clods, roots & mossy cushions under grass and on open slopes
	float moss_pillow = fbm(xz * 1.65);
	float soil_clods = fbm(xz * 5.2 + vec2(3.7, 1.9));
	float fine_grit = value_noise(xz * 16.0);
	float turf_h = moss_pillow * 0.032 + soil_clods * 0.016 + fine_grit * 0.005;

	// 2. Road profile: sunken ruts, raised center crown, and embedded 3D Voronoi cobbles
	vec3 cobble_a = voronoi_stones(xz * 2.8);
	vec3 cobble_b = voronoi_stones(xz * 6.4 + vec2(11.3, 4.7));
	float stone_density = clamp(ruts * 0.85 + road_core * 0.45 - median * 0.65, 0.0, 1.0);
	float stone_h = (cobble_a.x * 0.036 + cobble_b.x * 0.016) * stone_density;
	float rut_depression = -ruts * 0.038 + median * 0.022;
	float road_h = rut_depression + stone_h + soil_clods * 0.010 + fine_grit * 0.004;

	// 3. Stratified limestone ledges on steeper hillside terrace breaks
	float ledge_mask = smoothstep(0.15, 0.34, slope) * (1.0 - road_core);
	float strata_bands = sin(xz.x * 1.4 + xz.y * 1.8 + fbm(xz * 0.9) * 3.5);
	float rock_h = (smoothstep(-0.3, 0.5, strata_bands) * 0.055 + cobble_a.x * 0.028) * ledge_mask;

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
	float verge = road_info.w;

	// --- 1. Analytical 3D Micro-Normal Mapping (finite difference over micro-heightfield) ---
	float eps = 0.024;
	float h0 = eval_micro_height(xz, road_info, slope);
	float hx = eval_micro_height(xz + vec2(eps, 0.0), road_info, slope);
	float hz = eval_micro_height(xz + vec2(0.0, eps), road_info, slope);
	vec3 d_h = vec3((h0 - hx) / eps, 0.0, (h0 - hz) / eps);
	float dist_atten = 1.0 - smoothstep(22.0, 58.0, length(xz));
	vec3 world_nrm = normalize(v_world_nrm + d_h * (1.15 * dist_atten + 0.25));
	NORMAL = normalize((VIEW_MATRIX * vec4(world_nrm, 0.0)).xyz);

	// --- 2. Rich Multi-Layered Ground & Under-Grass Soil/Moss Palette ---
	vec3 base_meadow = meadow_ground_palette(xz);
	float moss_n = fbm(xz * 1.65);
	float humus_n = fbm(xz * 4.8 + vec2(6.1, -2.3));
	float grit_n = value_noise(xz * 15.0);

	// Dark rich forest humus in micro-hollows + velvety moss cushions + warm dry root-litter specks
	vec3 humus_dark = vec3(0.13, 0.16, 0.09);
	vec3 moss_cushion = vec3(0.24, 0.38, 0.15);
	vec3 dry_thatch = vec3(0.32, 0.31, 0.18);
	vec3 detailed_turf = mix(humus_dark, base_meadow, smoothstep(0.18, 0.62, moss_n));
	detailed_turf = mix(detailed_turf, moss_cushion, smoothstep(0.55, 0.86, moss_n) * 0.65);
	detailed_turf = mix(detailed_turf, dry_thatch, smoothstep(0.68, 0.90, humus_n) * 0.35);
	detailed_turf *= (0.93 + 0.14 * grit_n);

	// Blend toward sunlit grass-tip tone in the far distance so distant hills match 3D grass seamlessly
	float warm_patch = fbm(xz * 0.08 + vec2(3.1, 1.7));
	vec3 far_tip_col = mix(vec3(0.24, 0.39, 0.15), vec3(0.33, 0.45, 0.18), smoothstep(0.28, 0.76, warm_patch));
	float far_blend = smoothstep(34.0, 54.0, length(xz));
	vec3 col = mix(detailed_turf, far_tip_col * (0.95 + 0.10 * moss_n), far_blend * 0.78);
	float rough = 0.91;

	// --- 3. Stratified Limestone & Mossy Rock Ledges on Hillside Terrace Slopes ---
	float ledge_mask = smoothstep(0.14, 0.32, slope) * (1.0 - road_core);
	if (ledge_mask > 0.01) {
		vec3 rock_v = voronoi_stones(xz * 1.9);
		float strata = sin(v_world_pos.y * 8.5 + fbm(xz * 0.8) * 2.8) * 0.5 + 0.5;
		vec3 limestone_light = vec3(0.42, 0.41, 0.38);
		vec3 slate_shadow = vec3(0.26, 0.28, 0.29);
		vec3 rock_col = mix(slate_shadow, limestone_light, smoothstep(0.25, 0.78, strata * 0.65 + rock_v.x * 0.35));
		// Crevice AO between rock blocks
		rock_col *= (1.0 - rock_v.z * 0.42);
		// Moss creeping over the upper shelves of the rock ledges
		float ledge_moss = smoothstep(0.48, 0.78, moss_n) * (1.0 - smoothstep(0.24, 0.42, slope));
		rock_col = mix(rock_col, moss_cushion, ledge_moss * 0.65);
		col = mix(col, rock_col, ledge_mask * 0.90);
		rough = mix(rough, 0.78, ledge_mask);
	}

	// --- 4. Detailed Two-Track Earthen & Cobble Road Network ---
	if (road_core > 0.01 || verge > 0.01) {
		// 4a. Trampled humus, dry clover-earth & pebble shoulder along the road verge
		vec3 verge_loam = mix(vec3(0.22, 0.24, 0.14), vec3(0.29, 0.26, 0.17), humus_n);
		verge_loam *= (0.90 + 0.18 * grit_n);
		col = mix(col, verge_loam, verge * 0.82);

		// 4b. Compacted roadbed loam + darker damp wheel ruts + mossy/grassy center median
		vec3 dry_loam = vec3(0.42, 0.34, 0.24) * (0.92 + 0.16 * humus_n);
		vec3 damp_rut_soil = vec3(0.28, 0.22, 0.15) * (0.90 + 0.18 * grit_n);
		vec3 road_soil = mix(dry_loam, damp_rut_soil, smoothstep(0.15, 0.78, ruts));

		// Center median strip between the two wheel ruts (overgrown with low moss & turf)
		vec3 median_turf = mix(vec3(0.23, 0.33, 0.15), vec3(0.31, 0.36, 0.18), moss_n);
		road_soil = mix(road_soil, median_turf, clamp(median * 0.88, 0.0, 1.0));

		// 4c. Embedded 3D Voronoi Cobbles & Gravel along wheel ruts and crossroads
		vec3 cob1 = voronoi_stones(xz * 2.8);
		vec3 cob2 = voronoi_stones(xz * 6.4 + vec2(11.3, 4.7));
		float stone_zone = clamp(ruts * 0.92 + road_core * 0.48 - median * 0.70, 0.0, 1.0);
		float big_stone_mask = smoothstep(0.12, 0.45, cob1.x) * stone_zone;
		float small_pebble_mask = smoothstep(0.18, 0.55, cob2.x) * stone_zone * (1.0 - big_stone_mask);

		// Per-stone mineral color variation (warm sandstone, cool slate, pale limestone)
		vec3 stone_warm = vec3(0.48, 0.42, 0.34);
		vec3 stone_cool = vec3(0.36, 0.39, 0.41);
		vec3 stone_pale = vec3(0.53, 0.50, 0.45);
		vec3 s_col1 = mix(stone_warm, stone_cool, smoothstep(0.3, 0.7, cob1.y));
		s_col1 = mix(s_col1, stone_pale, smoothstep(0.75, 0.95, cob1.y));
		s_col1 *= (0.90 + 0.18 * grit_n);

		vec3 s_col2 = mix(stone_cool, stone_warm, fract(cob2.y * 7.3)) * (0.88 + 0.20 * grit_n);

		// Dark soil crevice AO around embedded stones
		float crevice_ao = 1.0 - clamp((cob1.z * 0.52 + cob2.z * 0.28) * stone_zone, 0.0, 0.55);
		road_soil *= crevice_ao;
		road_soil = mix(road_soil, s_col1, big_stone_mask * 0.88);
		road_soil = mix(road_soil, s_col2, small_pebble_mask * 0.72);

		col = mix(col, road_soil, road_core);
		float road_rough = mix(0.92, 0.74, ruts * 0.65 + big_stone_mask * 0.55);
		rough = mix(rough, road_rough, road_core);
	}

	// --- 5. Distant Valley Rim Atmospheric Perspective ---
	float rim_haze = smoothstep(56.0, 92.0, length(xz));
	col = mix(col, vec3(0.32, 0.42, 0.35), rim_haze * 0.42);

	ALBEDO = col;
	ROUGHNESS = rough;
	SPECULAR = 0.08;
}
