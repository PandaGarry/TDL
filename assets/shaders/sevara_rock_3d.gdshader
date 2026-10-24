shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// Step 2 Sevara Sculpted Stone, Velvet Moss & Planed Oak Timber Shader (v9):
// - Mode 0 (Stone & Moss): C2-continuous quintic gradient noise + dual-scale 3D normal map,
//   deep ground-contact Ambient Occlusion & soil-skirt blending at the rock base,
//   velvet moss undercoat for 3D moss fur crowns, and glossy wet waterline belt (`WATER_SURFACE_Y = 0.42`).
// - Mode 1 (Bridge Timber): 3D wood-grain & plank-bevel normal maps, inter-plank AO grooves,
//   wheel-track wear patina along cart ruts, and warm sunlit specular response.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec3 tint : source_color = vec3(0.84, 0.80, 0.74);
uniform float roughness_base : hint_range(0.05, 1.0) = 0.86;
uniform float wetness : hint_range(0.0, 1.0) = 0.08;
uniform float moss_amount : hint_range(0.0, 1.0) = 0.72;
uniform float triplanar_scale : hint_range(0.08, 2.0) = 0.42;
uniform int surface_mode = 0; // 0 = Bevel-Smoothed Stone & Moss, 1 = Planed Oak Bridge Timber

varying vec3 v_world;
varying vec3 v_wnormal;
varying vec3 v_local;
varying vec3 v_dome_dir;
varying vec4 v_custom;

vec2 hash22(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.xx + p3.yz) * p3.zy) * 2.0 - 1.0;
}

float grad_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	float n00 = dot(hash22(i + vec2(0.0, 0.0)), f - vec2(0.0, 0.0));
	float n10 = dot(hash22(i + vec2(1.0, 0.0)), f - vec2(1.0, 0.0));
	float n01 = dot(hash22(i + vec2(0.0, 1.0)), f - vec2(0.0, 1.0));
	float n11 = dot(hash22(i + vec2(1.0, 1.0)), f - vec2(1.0, 1.0));
	return mix(mix(n00, n10, u.x), mix(n01, n11, u.x), u.y) * 0.5 + 0.5;
}

float soft_fbm(vec2 p) {
	float v = 0.0;
	float a = 0.52;
	mat2 rot = mat2(vec2(0.80, 0.60), vec2(-0.60, 0.80));
	for (int i = 0; i < 3; i++) {
		v += a * grad_noise(p);
		p = rot * p * 1.92 + vec2(4.7, -3.1);
		a *= 0.48;
	}
	return v;
}

float triplanar_soft_fbm(vec3 p, vec3 n, float scale) {
	vec3 w = pow(abs(n), vec3(2.2));
	w /= max(w.x + w.y + w.z, 0.0001);
	float xy = soft_fbm(p.xy * scale + vec2(1.7, 3.2));
	float yz = soft_fbm(p.yz * scale + vec2(5.4, -2.1));
	float xz = soft_fbm(p.xz * scale + vec2(-3.8, 2.9));
	return xy * w.z + yz * w.x + xz * w.y;
}

vec3 triplanar_soft_tex(vec3 p, vec3 n, float scale) {
	vec3 w = pow(abs(n), vec3(2.5));
	w /= max(w.x + w.y + w.z, 0.0001);
	vec3 cx = texture(albedo_tex, p.yz * scale).rgb;
	vec3 cy = texture(albedo_tex, p.xz * scale).rgb;
	vec3 cz = texture(albedo_tex, p.xy * scale).rgb;
	return cx * w.x + cy * w.y + cz * w.z;
}

float eval_moss_blanket(vec3 p, vec3 base_n, vec3 dome_dir, float affinity) {
	if (affinity <= 0.18) {
		return 0.0;
	}
	float macro_patch = triplanar_soft_fbm(p, base_n, 1.15);
	float detail_lobe = triplanar_soft_fbm(p + vec3(3.1, 1.7, -2.4), base_n, 2.65);
	float fine_edge = grad_noise(p.xz * 5.4 + vec2(p.y * 2.2, -1.4));
	float up_align = mix(base_n.y, dome_dir.y, 0.35);
	float raw_m = up_align * 0.88 + (macro_patch - 0.48) * 0.52 + (detail_lobe - 0.48) * 0.38 + (fine_edge - 0.50) * 0.18;
	float above_water = smoothstep(0.48, 0.66, p.y);
	return smoothstep(0.38, 0.64, raw_m) * affinity * above_water;
}

vec3 meadow_ground_palette(vec2 xz) {
	float macro_a = soft_fbm(xz * 0.045);
	float macro_b = soft_fbm(xz * 0.11 + vec2(5.2, 3.7));
	vec3 deep_sage = vec3(0.16, 0.29, 0.11);
	vec3 lush_meadow = vec3(0.23, 0.38, 0.15);
	vec3 warm_olive = vec3(0.31, 0.44, 0.17);
	vec3 col = mix(deep_sage, lush_meadow, smoothstep(0.22, 0.74, macro_a));
	col = mix(col, warm_olive, smoothstep(0.36, 0.80, macro_b) * 0.70);
	return col;
}

void vertex() {
	v_local = VERTEX;
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 local_dome = normalize(VERTEX + vec3(0.0, 0.25, 0.0));
	if (surface_mode == 0) {
		float top_pillow = smoothstep(0.28, 0.78, local_dome.y) * smoothstep(0.35, 0.85, moss_amount) * smoothstep(0.48, 0.68, wp.y);
		VERTEX += local_dome * (top_pillow * 0.018);
	}
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wnormal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_dome_dir = normalize((MODEL_MATRIX * vec4(local_dome, 0.0)).xyz);
	v_custom = INSTANCE_CUSTOM;
}

void fragment() {
	if (surface_mode == 1) {
		// Smooth Planed Oak Timber Mode with 3D Wood-Grain & Bevel Normal Map, Inter-Plank AO & Wheel Wear
		vec3 base_n = normalize(v_wnormal);
		vec2 grain_uv = vec2(v_world.z * 1.15 + v_world.x * 0.28, v_world.x * 4.2 + v_world.y * 4.5);
		float eps = 0.035;
		float g0 = soft_fbm(grain_uv);
		float gx = soft_fbm(grain_uv + vec2(eps, 0.0));
		float gy = soft_fbm(grain_uv + vec2(0.0, eps));
		vec2 grain_grad = vec2(g0 - gx, g0 - gy) / eps;

		// Rounded plank bevel normal across local X width of each plank (`[-0.17, +0.17]`)
		float is_top_deck = smoothstep(0.4, 0.9, abs(base_n.y)) * step(0.8, abs(v_local.z) + 0.85);
		float plank_bevel_x = clamp(v_local.x / 0.165, -1.0, 1.0) * smoothstep(0.07, 0.165, abs(v_local.x));
		vec3 wood_world_nrm = normalize(
			base_n + vec3(plank_bevel_x * 0.42 * is_top_deck + grain_grad.y * 0.045, 0.0, grain_grad.x * 0.055)
		);
		NORMAL = normalize((VIEW_MATRIX * vec4(wood_world_nrm, 0.0)).xyz);

		float ring_soft = grad_noise(grain_uv * vec2(0.48, 3.1) + vec2(1.3, 0.7));
		float plank_id = grad_noise(vec2(floor(v_world.x * 2.85) * 1.7, 0.4));

		vec3 warm_oak_light = tint * vec3(0.96, 0.87, 0.74);
		vec3 warm_oak_mid = tint * vec3(0.78, 0.68, 0.55);
		vec3 warm_oak_deep = tint * vec3(0.58, 0.48, 0.37);

		vec3 wood_col = mix(warm_oak_deep, warm_oak_mid, smoothstep(0.16, 0.78, g0));
		wood_col = mix(wood_col, warm_oak_light, smoothstep(0.34, 0.84, ring_soft) * 0.58);
		wood_col *= mix(0.91, 1.07, plank_id);

		// Deep inter-plank groove shadow (Contact AO between planks) + curb & post contact shadow
		float plank_groove_ao = smoothstep(0.095, 0.155, abs(v_local.x)) * is_top_deck;
		float curb_contact_ao = smoothstep(1.02, 1.42, abs(v_local.z));
		float total_wood_ao = clamp(plank_groove_ao * 0.56 + curb_contact_ao * 0.44, 0.0, 0.74);
		wood_col *= (1.0 - total_wood_ao);

		// Hand-forged dark iron nail heads fastening each oak plank to the two carrier beams (`|v_local.z| ~ 1.24`)
		vec2 nail_uv = vec2(abs(v_local.x) - 0.072, abs(v_local.z) - 1.24);
		float nail_dist = length(nail_uv * vec2(1.0, 1.25));
		float nail_head = (1.0 - smoothstep(0.014, 0.024, nail_dist)) * is_top_deck;
		float nail_stain = (1.0 - smoothstep(0.022, 0.052, nail_dist)) * is_top_deck;
		wood_col *= (1.0 - nail_stain * 0.36);
		wood_col = mix(wood_col, vec3(0.10, 0.11, 0.13), nail_head);

		// Cart wheel-rut & footstep wear patina along the two traffic tracks (`abs(v_local.z) ~ 0.54`)
		float wheel_rut = exp(-pow((abs(v_local.z) - 0.54) / 0.32, 2.0)) * is_top_deck;
		float soil_speck = soft_fbm(v_world.xz * 2.4 + vec2(3.1, -1.8));
		vec3 rut_patina = vec3(0.28, 0.22, 0.15);
		wood_col = mix(wood_col, rut_patina, wheel_rut * smoothstep(0.28, 0.76, soil_speck) * 0.34);

		// Wet dark grime & mossy dampness on lower bridge beams/posts near water & bank abutments
		float waterline_grime = 1.0 - smoothstep(0.45, 0.96, v_world.y);
		wood_col = mix(wood_col, vec3(0.14, 0.16, 0.09), waterline_grime * 0.58);
		float bank_end = smoothstep(5.1, 6.35, abs(v_world.x - 12.0)) * smoothstep(0.75, 1.38, abs(v_local.z));
		wood_col = mix(wood_col, vec3(0.18, 0.30, 0.11), bank_end * 0.45);

		float up = wood_world_nrm.y;
		wood_col *= 0.78 + 0.26 * smoothstep(-0.4, 0.85, up);

		ALBEDO = wood_col;
		float base_w_rough = mix(0.66, 0.42, wheel_rut * 0.65 + (1.0 - plank_groove_ao) * 0.25 + waterline_grime * 0.45);
		ROUGHNESS = mix(base_w_rough, 0.26, nail_head);
		METALLIC = nail_head * 0.82;
		SPECULAR = mix(0.36, 0.68, nail_head);
		BACKLIGHT = vec3(0.06, 0.04, 0.02);
	} else {
		// Bevel-Smoothed Sculpted Stone & Organic Velvet Moss Mode
		vec3 base_n = normalize(mix(v_wnormal, v_dome_dir, 0.12));
		float inst_moss = v_custom.a > 0.01 ? v_custom.a : moss_amount;
		float moss_mask = eval_moss_blanket(v_world, base_n, v_dome_dir, inst_moss);

		// Dual-scale 3D rock normal map (geological strata + fine mineral relief)
		float eps = 0.038;
		float n_freq = mix(1.75, 3.6, moss_mask);
		float n_amp = mix(0.048, 0.056, moss_mask);
		float h0 = triplanar_soft_fbm(v_world, base_n, n_freq) * n_amp
			+ triplanar_soft_fbm(v_world + vec3(2.3, -1.7, 4.1), base_n, n_freq * 2.35) * (n_amp * 0.38);
		float hx = triplanar_soft_fbm(v_world + vec3(eps, 0.0, 0.0), base_n, n_freq) * n_amp
			+ triplanar_soft_fbm(v_world + vec3(2.3 + eps, -1.7, 4.1), base_n, n_freq * 2.35) * (n_amp * 0.38);
		float hy = triplanar_soft_fbm(v_world + vec3(0.0, eps, 0.0), base_n, n_freq) * n_amp
			+ triplanar_soft_fbm(v_world + vec3(2.3, -1.7 + eps, 4.1), base_n, n_freq * 2.35) * (n_amp * 0.38);
		float hz = triplanar_soft_fbm(v_world + vec3(0.0, 0.0, eps), base_n, n_freq) * n_amp
			+ triplanar_soft_fbm(v_world + vec3(2.3, -1.7, 4.1 + eps), base_n, n_freq * 2.35) * (n_amp * 0.38);
		vec3 grad = vec3(h0 - hx, h0 - hy, h0 - hz) / eps;
		grad -= base_n * dot(grad, base_n);
		vec3 world_nrm = normalize(base_n + grad * 0.85);
		NORMAL = normalize((VIEW_MATRIX * vec4(world_nrm, 0.0)).xyz);

		// Painterly Mountain Limestone & River Granite
		vec3 soft_tex = triplanar_soft_tex(v_world, base_n, triplanar_scale);
		float tex_tone = dot(soft_tex, vec3(0.333));
		float macro_tone = triplanar_soft_fbm(v_world, base_n, 0.88);
		float strata = triplanar_soft_fbm(v_world + vec3(3.7, -2.1, 1.4), base_n, 2.2);

		vec3 deep_slate = vec3(0.25, 0.27, 0.29);
		vec3 mid_granite = vec3(0.41, 0.39, 0.36);
		vec3 warm_limestone = vec3(0.54, 0.50, 0.43);

		vec3 c = mix(deep_slate, mid_granite, smoothstep(0.18, 0.72, macro_tone * 0.62 + tex_tone * 0.38));
		c = mix(c, warm_limestone, smoothstep(0.40, 0.82, strata) * 0.64);
		float soft_crevice = smoothstep(0.48, 0.20, tex_tone * 0.55 + strata * 0.45);
		c *= mix(1.0, 0.62, soft_crevice * 0.72);
		c *= tint;
		if (length(v_custom.rgb) > 0.02) {
			c *= v_custom.rgb;
		}

		// Soft beveled ridge highlight & ground bounce
		float up = world_nrm.y;
		float bevel_highlight = clamp(1.0 - abs(dot(v_wnormal, v_dome_dir)), 0.0, 1.0);
		c += vec3(0.07, 0.065, 0.052) * smoothstep(0.10, 0.46, bevel_highlight) * smoothstep(-0.05, 0.75, up);
		vec3 ground_bounce = vec3(0.22, 0.29, 0.16);
		c = mix(c * 0.70 + ground_bounce * 0.06, c * 1.06, smoothstep(-0.45, 0.85, up));

		// Sunlit Mountain Lichen Rosettes on dry upper stone faces (links bare stone to meadow ecology)
		float lichen_n = triplanar_soft_fbm(v_world + vec3(6.4, 1.2, -3.7), base_n, 3.8);
		float lichen_mask = smoothstep(0.62, 0.84, lichen_n) * smoothstep(0.15, 0.75, up)
			* (1.0 - moss_mask) * smoothstep(0.55, 0.82, v_world.y);
		c = mix(c, vec3(0.38, 0.44, 0.24), lichen_mask * 0.52);

		// Deep Ground-Contact Ambient Occlusion & Base Soil/Moss Blending (prevents "floating sticker" look)
		float base_skirt = (1.0 - smoothstep(0.05, 0.92, v_local.y)) * (1.0 - smoothstep(-0.35, 0.35, v_dome_dir.y));
		float ground_contact_ao = clamp(base_skirt * 0.68 + smoothstep(0.25, -0.45, v_dome_dir.y) * 0.32, 0.0, 0.72);
		vec3 root_humus = vec3(0.11, 0.16, 0.08);
		c = mix(c, root_humus, base_skirt * 0.55);
		c *= (1.0 - ground_contact_ao * 0.48);

		// Deep Velvet Moss Undercoat Blanket (matches Step 1 soil/moss under 3D grass blades)
		if (moss_mask > 0.01) {
			float cushion_macro = soft_fbm(v_world.xz * 2.8 + vec2(1.7, -1.3));
			float tuft_meso = soft_fbm(v_world.xz * 6.8 - vec2(v_world.y * 2.1, 0.8));

			vec3 ground_moss = meadow_ground_palette(v_world.xz);
			vec3 deep_hollow = vec3(0.09, 0.17, 0.06);
			vec3 lush_mid = mix(vec3(0.16, 0.28, 0.10), ground_moss * 0.82, 0.55);
			vec3 sunlit_crown = vec3(0.24, 0.37, 0.14);

			vec3 moss_col = mix(deep_hollow, lush_mid, smoothstep(0.20, 0.72, cushion_macro));
			moss_col = mix(moss_col, sunlit_crown, smoothstep(0.40, 0.84, tuft_meso) * 0.65);

			float ndotv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
			float velvet_rim = pow(1.0 - ndotv, 2.5) * smoothstep(-0.1, 0.8, up);
			moss_col += vec3(0.05, 0.08, 0.02) * velvet_rim * 0.50;

			float border_ao = smoothstep(0.05, 0.28, moss_mask) * (1.0 - smoothstep(0.28, 0.66, moss_mask));
			c = mix(c, vec3(0.09, 0.13, 0.05), border_ao * 0.62);
			c = mix(c, moss_col, smoothstep(0.10, 0.70, moss_mask));
		}

		// Smooth Nivarel River Waterline Interaction (`WATER_SURFACE_Y = 0.42`)
		float water_y = 0.42;
		float above_w = v_world.y - water_y;
		float wet_belt = (1.0 - smoothstep(0.0, 0.26, above_w)) * step(-0.08, above_w);
		float submerge_depth = clamp(-above_w / 0.80, 0.0, 1.0);
		float wet_factor = clamp(max(wetness * 0.55, max(wet_belt * 0.82, submerge_depth)), 0.0, 1.0);

		c *= mix(1.0, 0.62, wet_factor);
		vec3 underwater_tint = vec3(0.06, 0.18, 0.17);
		c = mix(c, underwater_tint, submerge_depth * 0.68);

		ALBEDO = c;
		float dry_rough = clamp(roughness_base + (soft_crevice - 0.5) * 0.10, 0.78, 0.94);
		ROUGHNESS = clamp(mix(mix(dry_rough, 0.95, moss_mask), 0.20, wet_factor), 0.18, 0.96);
		SPECULAR = mix(mix(0.18, 0.05, moss_mask), 0.48, wet_factor);
		BACKLIGHT = vec3(0.15, 0.23, 0.07) * moss_mask * 0.55;
	}
}
