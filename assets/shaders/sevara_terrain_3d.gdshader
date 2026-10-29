shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// Step 1 + Step 2 CBT Proving Ground Terrain Shader:
// - Single-pass analytical stone height & gradient evaluation (4x faster on mobile TBDR GPUs).
// - Distance-adaptive micro-normal LOD (full 4-octave soil crumb near camera, 2-octave mid-range).
// - Organic two-track roads, turf-lip shadow, and sunlit clover/wildflower glades.
// - Step 2 Nivarel mountain creek riverbed pebbles, wet shore bank, and shallow stone ford.

uniform float silt_stain = 0.16;
uniform int dynamic_pad_count = 0;
uniform vec4 dynamic_pads[10];
uniform int dynamic_fp_count = 0;
uniform vec4 dynamic_fps[10];

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

float fbm2(vec2 p) {
	float v = 0.5 * value_noise(p);
	mat2 rot = mat2(vec2(0.80, 0.60), vec2(-0.60, 0.80));
	p = rot * p * 2.02;
	v += 0.25 * value_noise(p);
	return v * 1.3333;
}

// Single-pass analytical fieldstones: returns vec4(stone_height, dh_dx, dh_dz, stone_id)
vec4 irregular_fieldstones_grad(vec2 p, float density_threshold) {
	vec2 warp = vec2(fbm2(p * 1.8) - 0.5, fbm2(p * 1.8 + vec2(4.3, 8.1)) - 0.5) * 0.48;
	vec2 pw = p + warp;
	vec2 n = floor(pw);
	vec2 f = fract(pw);
	float best_h = 0.0;
	vec2 best_grad = vec2(0.0);
	float best_id = 0.0;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 g = vec2(float(i), float(j));
			vec2 cell = n + g;
			float id = hash12(cell + vec2(7.1, 3.3));
			if (id < density_threshold) {
				continue;
			}
			vec2 o = 0.25 + 0.50 * hash22(cell);
			vec2 d_vec = f - (g + o);
			float ang = id * 6.283;
			float ca = cos(ang);
			float sa = sin(ang);
			vec2 rot_r = vec2(ca * d_vec.x - sa * d_vec.y, sa * d_vec.x + ca * d_vec.y);
			vec2 aspect = vec2(1.0 + fract(id * 5.7) * 0.65, 1.0 + fract(id * 11.3) * 0.45);
			vec2 q = abs(rot_r * aspect);
			float d_oct = max(q.x, q.y) * 0.58 + (q.x + q.y) * 0.42;
			float rad = 0.12 + fract(id * 13.7) * 0.14;
			if (d_oct < rad) {
				float norm_d = clamp(d_oct / rad, 0.0, 1.0);
				float h = smoothstep(1.0, 0.28, norm_d);
				if (h > best_h) {
					best_h = h;
					best_id = id;
					float edge_slope = (1.0 - smoothstep(0.0, 0.35, norm_d)) * 2.2 / max(rad, 0.08);
					best_grad = -d_vec * edge_slope;
				}
			}
		}
	}
	return vec4(best_h, best_grad.x, best_grad.y, best_id);
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

float river_center_x(float wz) {
	float base_cx = 7.8 + wz * 0.22 + sin(wz * 0.088 + 0.35) * 3.6 + cos(wz * 0.044 - 0.2) * 1.8;
	return base_cx + (1.0 - smoothstep(-52.0, -14.0, wz)) * 3.8;
}

float river_half_width(float wz) {
	float base_w = 4.65 + smoothstep(-34.0, 28.0, wz) * 1.10;
	float pool_w = exp(-pow((wz - 12.0) / 8.0, 2.0)) * 1.15;
	float bank_wave = sin(wz * 0.30 + 0.5) * 0.28 + cos(wz * 0.62 - 0.8) * 0.16;
	return base_w + pool_w + bank_wave;
}

// Per-pixel river channel & pebble bank mask: returns vec2(river_bed_mask, wet_shore_mask)
vec2 eval_river_bank(vec2 xz) {
	float wz = xz.y;
	float r_cx = river_center_x(wz);
	float r_hw = river_half_width(wz);
	float warp = (fbm2(xz * 0.75) - 0.5) * 0.22;
	float norm_r = (abs(xz.x - r_cx) + warp) / max(r_hw, 0.5);
	float bed_mask = 1.0 - smoothstep(0.76, 1.12, norm_r);
	float wet_mask = 1.0 - smoothstep(0.72, 1.04, norm_r);
	return vec2(bed_mask, wet_mask);
}

float seg_dist(vec2 p, vec2 a, vec2 b) {
	vec2 ab = b - a;
	float t = clamp(dot(p - a, ab) / max(dot(ab, ab), 0.0001), 0.0, 1.0);
	return length(p - (a + ab * t));
}

// Per-pixel road network evaluation with natural fork/junction blending:
// Returns vec4(road_core_mask, wheel_rut_intensity, median_strip_mask, verge_soil_halo)
vec4 eval_road_network(vec2 xz) {
	float wx = xz.x;
	float wz = xz.y;

	float warp_a = (fbm(xz * 0.65) - 0.5) * 0.26 + (value_noise(xz * 2.4) - 0.5) * 0.09;

	// 1. Main valley two-track cart road (stops cleanly at the riverbanks for the timber bridge)
	float rz = main_road_z(wx);
	float dz_dx = cos(wx * 0.085 + 0.35) * 0.323 - sin(wx * 0.045 - 0.4) * 0.0855 - 0.06;
	float signed_main = (wz - rz) / sqrt(1.0 + dz_dx * dz_dx);
	float d_main = abs(signed_main);
	float r_cx = river_center_x(wz);
	float r_hw = river_half_width(wz);
	float bridge_channel_cut = smoothstep(r_hw * 0.74, r_hw * 0.92, abs(wx - r_cx));
	float fade_main = smoothstep(-66.0, -54.0, wx) * (1.0 - smoothstep(54.0, 66.0, wx)) * bridge_channel_cut;

	// 2. NW Overlook terrace trail
	float bx = -3.5 + (wz + 3.6) * 0.55 + sin((wz + 3.6) * 0.16) * 2.2;
	float dx_dz_n = 0.55 + cos((wz + 3.6) * 0.16) * 0.352;
	float d_north = abs(wx - bx) / sqrt(1.0 + dx_dz_n * dx_dz_n);
	float fade_north = smoothstep(rz + 0.35, rz - 0.85, wz) * (1.0 - smoothstep(-44.0, -54.0, wz));

	// 3. SW Meadow & west-bank trail (curves away from the creek along the dry terrace)
	float sx = -3.8 - (wz + 2.2) * 0.36 + sin((wz + 2.2) * 0.15) * 1.2;
	float dx_dz_s = -0.36 + cos((wz + 2.2) * 0.15) * 0.18;
	float d_south = abs(wx - sx) / sqrt(1.0 + dx_dz_s * dx_dz_s);
	float fade_south = smoothstep(rz - 0.35, rz + 0.85, wz) * (1.0 - smoothstep(22.0, 30.0, wz));

	float u_main = (d_main + warp_a) / 1.32;
	float u_north = (d_north + warp_a * 0.85) / 0.96;
	float u_south = (d_south + warp_a * 0.85) / 0.90;

	float m_main = (1.0 - smoothstep(0.64, 1.05, u_main)) * fade_main;
	float m_north = (1.0 - smoothstep(0.62, 1.04, u_north)) * fade_north;
	float m_south = (1.0 - smoothstep(0.62, 1.04, u_south)) * fade_south;
	float pad_any = 0.0;
	if (dynamic_pad_count > 0) {
		for (int i = 0; i < 10; i++) {
			if (i >= dynamic_pad_count) {
				break;
			}
			vec4 pd = dynamic_pads[i];
			float p_val = exp(
				-pow((wx - pd.x) / max(pd.z, 0.5), 2.0) - pow((wz - pd.y) / max(pd.w, 0.5), 2.0)
			);
			pad_any = max(pad_any, p_val);
		}
	} else {
		// Tier 1 Compact West-Bank Tribal Settlement pads (east bank stays untouched wild meadow)
		float pad_elder = exp(-pow((wx - (-13.2)) / 2.9, 2.0) - pow((wz - (-10.2)) / 2.6, 2.0));
		float pad_west = exp(-pow((wx - (-17.8)) / 2.4, 2.0) - pow((wz - (-7.2)) / 2.4, 2.0));
		float pad_well = exp(-pow((wx - (-11.8)) / 1.9, 2.0) - pow((wz - (-6.0)) / 1.9, 2.0));
		float pad_north = exp(-pow((wx - (-7.8)) / 2.5, 2.0) - pow((wz - (-13.4)) / 2.3, 2.0));
		float pad_shed = exp(-pow((wx - (-5.8)) / 2.4, 2.0) - pow((wz - (-8.2)) / 2.2, 2.0));
		float pad_sluice = exp(-pow((wx - (-1.0)) / 2.2, 2.0) - pow((wz - (-11.2)) / 2.2, 2.0));
		float pad_hearth = exp(-pow((wx - (-0.4)) / 2.5, 2.0) - pow((wz - (-5.2)) / 2.5, 2.0));
		pad_any = max(
			max(max(pad_elder, pad_west), max(pad_well, pad_north)),
			max(max(pad_shed, pad_sluice), pad_hearth)
		);
	}

	// Footpaths connecting every tribal hut doorway to the road network
	float d_fp = 99.0;
	if (dynamic_fp_count > 0) {
		for (int i = 0; i < 10; i++) {
			if (i >= dynamic_fp_count) {
				break;
			}
			vec4 fp = dynamic_fps[i];
			d_fp = min(d_fp, seg_dist(xz, fp.xy, fp.zw));
		}
	} else {
		d_fp = seg_dist(xz, vec2(-17.8, -7.2), vec2(-11.8, -6.0));
		d_fp = min(d_fp, seg_dist(xz, vec2(-11.8, -6.0), vec2(-5.8, -5.6)));
		d_fp = min(d_fp, seg_dist(xz, vec2(-11.8, -6.0), vec2(-13.2, -10.2)));
		d_fp = min(d_fp, seg_dist(xz, vec2(-7.8, -13.4), vec2(-5.8, -8.2)));
		d_fp = min(d_fp, seg_dist(xz, vec2(-5.8, -8.2), vec2(-5.8, -5.4)));
		d_fp = min(d_fp, seg_dist(xz, vec2(-5.8, -8.2), vec2(-1.0, -11.2)));
		d_fp = min(d_fp, seg_dist(xz, vec2(-2.6, -3.2), vec2(-0.4, -5.2)));
	}
	float m_fp = 1.0 - smoothstep(0.36, 0.72, d_fp + warp_a * 0.42);
	float rut_fp = exp(-pow((d_fp + warp_a * 0.25) / 0.26, 2.0)) * 0.65;

	float m_pads = max(smoothstep(0.24, 0.68, pad_any - warp_a * 0.22), m_fp * 0.94);
	float road_core = clamp(max(max(m_main, m_pads), max(m_north, m_south)), 0.0, 1.0);

	float h_main = (1.0 - smoothstep(0.75, 1.65, u_main)) * fade_main;
	float h_north = (1.0 - smoothstep(0.72, 1.68, u_north)) * fade_north;
	float h_south = (1.0 - smoothstep(0.72, 1.68, u_south)) * fade_south;
	float h_pads = max(smoothstep(0.08, 0.52, pad_any), 1.0 - smoothstep(0.55, 1.15, d_fp));
	float verge_halo = clamp(max(max(h_main, h_pads), max(h_north, h_south)), 0.0, 1.0);

	float rut_n_track = exp(-pow((signed_main + 0.50 + warp_a * 0.28) / 0.27, 2.0)) * (1.0 - m_north * 0.55);
	float rut_s_track = exp(-pow((signed_main - 0.50 - warp_a * 0.28) / 0.27, 2.0)) * (1.0 - m_south * 0.55);
	float rut_main = max(rut_n_track, rut_s_track) * fade_main;

	float join_fade = smoothstep(0.15, 0.85, d_main);
	float rut_north = exp(-pow((d_north - 0.28 + warp_a * 0.22) / 0.24, 2.0)) * fade_north * mix(0.45, 1.0, join_fade);
	float rut_south = exp(-pow((d_south - 0.26 + warp_a * 0.22) / 0.23, 2.0)) * fade_south * mix(0.45, 1.0, join_fade);
	float junction_bowl = m_main * max(m_north, m_south) * 0.52;
	float ruts = clamp(max(max(rut_main, rut_fp), max(max(rut_north * 0.82, rut_south * 0.82), junction_bowl)), 0.0, 1.0);

	float median_noise = fbm(xz * 0.95 + vec2(2.1, -1.4));
	float median = exp(-pow(signed_main / 0.25, 2.0)) * fade_main * smoothstep(0.24, 0.68, median_noise);
	median *= (1.0 - max(m_north, m_south) * 0.92);

	return vec4(road_core, ruts, median, verge_halo);
}

float eval_soil_micro_height(vec2 xz, vec4 road_info, float slope, bool near_lod) {
	float road_core = road_info.x;
	float ruts = road_info.y;
	float median = road_info.z;

	float moss_h = fbm2(xz * 1.9);
	float clod_h = fbm2(xz * 6.8 + vec2(3.7, 1.9));
	float fine_h = 0.0;
	if (near_lod) {
		fine_h = fbm2(xz * 21.0 + vec2(-4.2, 7.5)) * 0.011 + value_noise(xz * 48.0) * 0.005;
	}
	float turf_h = moss_h * 0.032 + clod_h * 0.022 + fine_h;
	float wagon_chatter = (sin(xz.x * 3.4 + xz.y * 2.1) * 0.016 + cos(xz.x * 6.8 - xz.y * 4.5) * 0.010) * ruts;
	float rut_depression = -ruts * 0.042 + median * 0.024 + wagon_chatter;
	float road_h = rut_depression + clod_h * 0.022 + fine_h;

	float ledge_mask = smoothstep(0.11, 0.25, slope) * (1.0 - road_core);
	float rock_h = 0.0;
	if (ledge_mask > 0.01) {
		float strata_bands = sin(xz.x * 1.2 + xz.y * 1.6 + moss_h * 3.8);
		rock_h = (smoothstep(-0.35, 0.45, strata_bands) * 0.065 + clod_h * 0.024) * ledge_mask;
	}
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
	float dist_origin = length(xz);
	float slope = 1.0 - clamp(v_world_nrm.y, 0.0, 1.0);
	vec4 road_info = eval_road_network(xz);
	float road_core = road_info.x;
	float ruts = road_info.y;
	float median = road_info.z;
	float verge_halo = road_info.w;
	vec2 river_info = eval_river_bank(xz);
	float river_bed = river_info.x;
	float wet_shore = river_info.y;

	// Single-pass analytical stone evaluation (on roadbeds and river pebble banks within 44m)
	vec4 st1 = vec4(0.0);
	vec4 st2 = vec4(0.0);
	float stone_zone = clamp(max(ruts * 0.75 + road_core * 0.32 - median * 0.82, river_bed * 0.92), 0.0, 1.0);
	if ((road_core > 0.01 || river_bed > 0.01) && dist_origin < 44.0 && stone_zone > 0.02) {
		float thresh = mix(0.68, 0.42, river_bed);
		st1 = irregular_fieldstones_grad(xz * 2.5, thresh);
		if (dist_origin < 28.0) {
			st2 = irregular_fieldstones_grad(xz * 5.6 + vec2(9.4, 3.8), thresh);
		}
	}

	// --- 1. Distance-Adaptive Analytical 3D Micro-Normal Mapping ---
	vec3 world_nrm = v_world_nrm;
	if (dist_origin < 68.0) {
		bool near_lod = (dist_origin < 30.0);
		float eps = 0.018;
		float h0 = eval_soil_micro_height(xz, road_info, slope, near_lod);
		float hx = eval_soil_micro_height(xz + vec2(eps, 0.0), road_info, slope, near_lod);
		float hz = eval_soil_micro_height(xz + vec2(0.0, eps), road_info, slope, near_lod);
		vec3 d_h = vec3((h0 - hx) / eps, 0.0, (h0 - hz) / eps);
		d_h.xz += (st1.yz * 0.068 + st2.yz * 0.038) * stone_zone;
		float dist_atten = 1.0 - smoothstep(26.0, 68.0, dist_origin);
		world_nrm = normalize(v_world_nrm + d_h * (1.35 * dist_atten + 0.28));
	}
	NORMAL = normalize((VIEW_MATRIX * vec4(world_nrm, 0.0)).xyz);

	// --- 2. Rich Multi-Layered Under-Grass Soil, Humus, Sunlit Clover Glades & Moss Cushions ---
	vec3 base_meadow = meadow_ground_palette(xz);
	float moss_n = fbm(xz * 1.9);
	float clod_n = fbm(xz * 6.8 + vec2(6.1, -2.3));
	float crumb_n = (dist_origin < 46.0) ? fbm2(xz * 21.0 + vec2(-3.4, 5.1)) : 0.5;
	float grit_n = (dist_origin < 34.0) ? value_noise(xz * 48.0) : 0.5;

	vec3 humus_dark = vec3(0.13, 0.15, 0.09);
	vec3 moss_cushion = vec3(0.22, 0.36, 0.14);
	vec3 dry_thatch = vec3(0.28, 0.25, 0.15);
	vec3 detailed_turf = mix(humus_dark, base_meadow, smoothstep(0.20, 0.64, moss_n));
	detailed_turf = mix(detailed_turf, moss_cushion, smoothstep(0.54, 0.85, moss_n) * 0.65);
	detailed_turf = mix(detailed_turf, dry_thatch, smoothstep(0.58, 0.86, clod_n) * 0.45);

	float glade_n = fbm2(xz * 0.14 + vec2(4.2, -1.8));
	detailed_turf = mix(detailed_turf, vec3(0.28, 0.41, 0.16), smoothstep(0.52, 0.82, glade_n) * 0.38);
	detailed_turf *= (0.86 + 0.16 * crumb_n + 0.12 * grit_n);

	vec3 roadside_under_soil = mix(vec3(0.18, 0.22, 0.11), vec3(0.25, 0.24, 0.14), clod_n) * (0.88 + 0.22 * crumb_n);
	detailed_turf = mix(detailed_turf, roadside_under_soil, verge_halo * 0.78);

	float warm_patch = fbm2(xz * 0.08 + vec2(3.1, 1.7));
	vec3 far_tip_col = mix(vec3(0.23, 0.37, 0.15), vec3(0.31, 0.43, 0.17), smoothstep(0.28, 0.76, warm_patch));
	float far_blend = smoothstep(54.0, 82.0, dist_origin);
	vec3 col = mix(detailed_turf, far_tip_col * (0.94 + 0.12 * moss_n), far_blend * 0.68);
	float rough = 0.92;

	// --- 3. Stratified Limestone & Mossy Rock Ledges on Steep Cliff Slopes ---
	float ledge_mask = smoothstep(0.34, 0.52, slope) * (1.0 - road_core * 0.85) * (1.0 - river_bed);
	if (ledge_mask > 0.01) {
		float strata = sin(v_world_pos.y * 9.5 + fbm2(xz * 0.85) * 3.2) * 0.5 + 0.5;
		float fracture = fbm2(xz * 3.4);
		vec3 limestone_warm = vec3(0.43, 0.40, 0.35);
		vec3 slate_dark = vec3(0.24, 0.26, 0.26);
		vec3 rock_col = mix(slate_dark, limestone_warm, smoothstep(0.22, 0.78, strata * 0.68 + fracture * 0.32));
		rock_col *= (0.86 + 0.16 * crumb_n + 0.12 * grit_n);
		float ledge_moss = smoothstep(0.42, 0.74, moss_n) * (1.0 - smoothstep(0.22, 0.38, slope));
		rock_col = mix(rock_col, moss_cushion, ledge_moss * 0.65);
		col = mix(col, rock_col, ledge_mask * 0.90);
		rough = mix(rough, 0.78, ledge_mask);
	}

	// --- 4. Organic Two-Track Earthen Road with Turf-Lip Shadow, Mossy Median & Buried Fieldstones ---
	if (road_core > 0.01) {
		vec3 dry_loam = vec3(0.35, 0.28, 0.19);
		vec3 coarse_sand = vec3(0.41, 0.33, 0.23);
		vec3 dark_humus_edge = vec3(0.21, 0.20, 0.12);
		vec3 damp_rut = vec3(0.24, 0.19, 0.13);

		vec3 road_soil = mix(dry_loam, coarse_sand, smoothstep(0.30, 0.75, clod_n) * 0.75);
		road_soil = mix(road_soil, dark_humus_edge, (1.0 - smoothstep(0.12, 0.62, road_core)) * 0.72);
		road_soil = mix(road_soil, damp_rut, smoothstep(0.18, 0.82, ruts) * (0.72 + 0.28 * crumb_n));

		float turf_lip_ao = 1.0 - smoothstep(0.14, 0.38, road_core) * (1.0 - smoothstep(0.38, 0.64, road_core)) * 0.22;
		float fine_gravel = (dist_origin < 32.0) ? (value_noise(xz * 86.0) * 0.6 + value_noise(xz * 154.0) * 0.4 - 0.5) * 0.14 : 0.0;
		float grain_mod = (0.82 + 0.22 * crumb_n + 0.14 * (grit_n - 0.35) + fine_gravel) * turf_lip_ao;
		road_soil *= grain_mod;

		vec3 median_turf = mix(vec3(0.20, 0.31, 0.13), vec3(0.27, 0.34, 0.15), moss_n) * grain_mod;
		road_soil = mix(road_soil, median_turf, clamp(median * 0.88 * (1.0 - river_bed), 0.0, 1.0));

		float dust_cover = smoothstep(0.32, 0.78, clod_n);
		float m_st1 = smoothstep(0.18, 0.65, st1.x) * (1.0 - dust_cover * 0.55) * stone_zone;
		float m_st2 = smoothstep(0.22, 0.68, st2.x) * (1.0 - dust_cover * 0.45) * stone_zone * (1.0 - m_st1);

		vec3 stone_slate = vec3(0.33, 0.30, 0.26) * grain_mod;
		vec3 stone_sand = vec3(0.40, 0.34, 0.26) * grain_mod;
		vec3 scol1 = mix(stone_slate, stone_sand, fract(st1.w * 9.1));
		vec3 scol2 = mix(stone_slate, stone_sand, fract(st2.w * 7.3));

		road_soil = mix(road_soil, scol1, m_st1 * 0.68);
		road_soil = mix(road_soil, scol2, m_st2 * 0.55);

		// Organic ragged turf-tuft road edges so grass and dirt interlace naturally
		float ragged_edge = (clod_n - 0.5) * 0.26 + (crumb_n - 0.5) * 0.14 + (grit_n - 0.5) * 0.08;
		float smooth_edge = smoothstep(0.08, 0.52, road_core + ragged_edge);
		col = mix(col, road_soil, smooth_edge);
		float road_rough = mix(0.93, 0.78, ruts * 0.45 + m_st1 * 0.38);
		rough = mix(rough, road_rough, smooth_edge);
	}

	// --- 5. Step 2 Deep Nivarel River Pebble Shelf, Thalweg Bed & Wet Mossy Shore Bank ---
	if (river_bed > 0.01) {
		float grain = 0.84 + 0.20 * crumb_n + 0.12 * (grit_n - 0.35);
		float submerge = clamp((0.48 - v_world_pos.y) * 2.4, 0.0, 1.0);
		float deep_thalweg = clamp((0.10 - v_world_pos.y) * 0.78, 0.0, 1.0);

		vec3 river_sand = mix(vec3(0.30, 0.27, 0.18), vec3(0.20, 0.23, 0.16), clod_n) * grain;
		vec3 bank_moss = mix(vec3(0.17, 0.29, 0.13), vec3(0.23, 0.35, 0.15), moss_n) * grain;
		vec3 deep_silt = mix(vec3(0.10, 0.14, 0.12), vec3(0.07, 0.11, 0.10), clod_n) * grain;
		vec3 bed_col = mix(bank_moss, river_sand, clamp(submerge * 0.92, 0.0, 1.0));

		float stone_vis = clamp(submerge * 1.15 + 0.22, 0.0, 1.0) * (1.0 - deep_thalweg * 0.55);
		float m_p1 = smoothstep(0.10, 0.52, st1.x) * stone_vis;
		float m_p2 = smoothstep(0.14, 0.56, st2.x) * (1.0 - m_p1) * stone_vis;
		vec3 peb_warm = vec3(0.44, 0.38, 0.28) * grain;
		vec3 peb_slate = vec3(0.26, 0.30, 0.26) * grain;
		vec3 peb_jade = vec3(0.22, 0.32, 0.23) * grain;
		vec3 pcol1 = mix(peb_slate, peb_warm, fract(st1.w * 11.3));
		pcol1 = mix(pcol1, peb_jade, smoothstep(0.65, 0.92, fract(st1.w * 5.7)));
		vec3 pcol2 = mix(peb_slate, peb_warm, fract(st2.w * 8.9));

		bed_col = mix(bed_col, pcol1, m_p1 * 0.84);
		bed_col = mix(bed_col, pcol2, m_p2 * 0.68);
		bed_col = mix(bed_col, deep_silt, deep_thalweg * 0.78);
		float wet_dark = clamp(wet_shore * 0.52 + submerge * 0.44, 0.0, 0.84);
		bed_col *= mix(1.0, 0.72, wet_dark);

		col = mix(col, bed_col, smoothstep(0.06, 0.58, river_bed));
		rough = mix(rough, mix(0.80, 0.26, wet_dark), smoothstep(0.06, 0.58, river_bed));
	}

	// --- 6. Dynamic Building Contact Ambient Occlusion, Hearth Ground Glow & Charred Ash Pit ---
	float bld_ao = 0.0;
	int n_pads = clamp(dynamic_pad_count, 0, 10);
	for (int i = 0; i < 10; i++) {
		if (i >= n_pads) {
			break;
		}
		vec4 pad = dynamic_pads[i];
		vec2 rxz = max(pad.zw * 0.78, vec2(0.85));
		vec2 d = (xz - pad.xy) / rxz;
		bld_ao = max(bld_ao, exp(-dot(d, d)));
	}
	col *= mix(1.0, 0.36, clamp(bld_ao, 0.0, 0.94));

	// Communal Hearth charred ash pit & warm firelight reflection on the ground
	float d_hearth = length(xz - vec2(-0.4, -5.2));
	float ash_ring = 1.0 - smoothstep(0.45, 1.35, d_hearth + (clod_n - 0.5) * 0.24);
	float ember_core = 1.0 - smoothstep(0.0, 0.68, d_hearth + (crumb_n - 0.5) * 0.16);
	vec3 soot_soil = mix(vec3(0.06, 0.05, 0.04), vec3(0.16, 0.14, 0.12), crumb_n);
	col = mix(col, soot_soil, ash_ring * 0.92);
	col += vec3(0.42, 0.14, 0.02) * ember_core * (0.75 + 0.25 * sin(TIME * 4.2));

	float fire_bounce = (
		exp(-pow(d_hearth / 3.4, 2.0)) * 0.18
		+ exp(-pow(length(xz - vec2(-5.8, -8.2)) / 2.6, 2.0)) * 0.14
		+ exp(-pow(length(xz - vec2(-11.4, -9.2)) / 2.2, 2.0)) * 0.10
		+ exp(-pow(length(xz - vec2(-16.2, -6.5)) / 2.0, 2.0)) * 0.09
		+ exp(-pow(length(xz - vec2(-7.8, -11.6)) / 2.0, 2.0)) * 0.09
	) * (0.90 + 0.10 * sin(TIME * 3.6 + xz.x));
	col += vec3(0.55, 0.28, 0.07) * fire_bounce * (1.0 - river_bed);

	float sun_beam = smoothstep(0.56, 0.86, sin(xz.x * 0.22 - xz.y * 0.16 + 0.8) * 0.5 + 0.5)
		* smoothstep(0.38, 0.78, moss_n);
	col += vec3(0.035, 0.032, 0.014) * sun_beam * (1.0 - river_bed * 0.6);

	float low_mist = (1.0 - smoothstep(0.35, 1.35, v_world_pos.y))
		* smoothstep(14.0, 56.0, dist_origin) * 0.22;
	col = mix(col, vec3(0.44, 0.54, 0.52), low_mist);

	float rim_haze = smoothstep(82.0, 118.0, dist_origin);
	col = mix(col, vec3(0.32, 0.42, 0.35), rim_haze * 0.42);

	ALBEDO = col;
	ROUGHNESS = rough;
	SPECULAR = 0.08;
}
