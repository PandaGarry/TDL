shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// Step 2 3D Triplanar Mountain Granite, Velvet Fur-Moss Cushions & River Waterline Shader (v5):
// - Seam-free continuous vertex shaping + raised 3D moss cushion pillowing on mossy boulders.
// - Per-boulder moss affinity (`v_moss_affinity`): ~60% of riverbank boulders wear lush, thick,
//   velvety fur-like moss blankets with micro-tuft normals & backlit velvet sheen, while ~40% stay
//   chiseled bare granite/slate with moss only in deep fracture crevices.
// - Physical Nivarel river interaction at `WATER_SURFACE_Y = 0.42`: dark wet gloss belt & Beer-Lambert depth.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D moss_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec3 tint : source_color = vec3(0.94, 0.92, 0.88);
uniform vec3 moss_color : source_color = vec3(0.20, 0.36, 0.12);
uniform float moss_amount : hint_range(0.0, 1.0) = 0.68;
uniform float snow_amount : hint_range(0.0, 1.0) = 0.04;
uniform float wetness : hint_range(0.0, 1.0) = 0.22;
uniform float triplanar : hint_range(0.0, 1.0) = 1.0;
uniform float triplanar_scale : hint_range(0.02, 2.0) = 0.56;

varying vec3 v_world;
varying vec3 v_wnormal;
varying vec3 v_dome_dir;
varying vec4 v_custom;
varying float v_moss_affinity;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
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
		p = rot * p * 2.03;
		a *= 0.5;
	}
	return v;
}

float triplanar_fbm(vec3 p, vec3 n, float scale) {
	vec3 w = pow(abs(n), vec3(3.0));
	w /= max(w.x + w.y + w.z, 0.0001);
	float nx = fbm(p.yz * scale + vec2(2.3, -1.7));
	float ny = fbm(p.xz * scale);
	float nz = fbm(p.xy * scale + vec2(-3.1, 4.2));
	return nx * w.x + ny * w.y + nz * w.z;
}

vec3 triplanar_rock_tex(vec3 p, vec3 n, float scale) {
	vec3 w = pow(abs(n), vec3(4.0));
	w /= max(w.x + w.y + w.z, 0.0001);
	vec3 tx = texture(albedo_tex, p.yz * scale + vec2(0.19, 0.43)).rgb;
	vec3 ty = texture(albedo_tex, p.xz * scale + vec2(0.07, 0.13)).rgb;
	vec3 tz = texture(albedo_tex, p.xy * scale + vec2(0.61, 0.29)).rgb;
	return tx * w.x + ty * w.y + tz * w.z;
}

float eval_moss_blanket(vec3 p, vec3 base_n, vec3 dome_dir, float affinity) {
	if (affinity <= 0.15) {
		return 0.0;
	}
	float crag = triplanar_fbm(p, base_n, 2.2);
	float tuft_lobes = triplanar_fbm(p + vec3(3.1, 1.7, -2.4), base_n, 4.8);
	float dome_up = mix(dome_dir.y, base_n.y, 0.48);
	float lobe_noise = (tuft_lobes - 0.48) * 0.72 + (crag - 0.48) * 0.48;
	float raw_m = dome_up + lobe_noise;
	float above_water = smoothstep(0.50, 0.66, p.y);
	// Thick scalloped moss cushions on boulder crowns and upper shoulders, leaving lower stone flanks exposed
	return smoothstep(0.46, 0.68, raw_m) * affinity * above_water;
}

float rock_and_moss_micro_height(vec3 p, vec3 n, float moss_mask) {
	vec3 tex_c = triplanar_rock_tex(p, n, triplanar_scale);
	float tex_luma = dot(tex_c, vec3(0.333));
	float crag = triplanar_fbm(p, n, 2.5);
	float rock_h = tex_luma * 0.046 + crag * 0.025;
	if (moss_mask > 0.02) {
		// Thick 3D fur-like moss cushion height + fine fibrous绒毛 micro-tufts
		float cushion_pillows = fbm(p.xz * 7.5 + vec2(p.y * 3.2, -1.8));
		float fur_fibers = value_noise(p.xz * 34.0 + p.y * 19.0) * 0.65 + value_noise(p.xz * 68.0) * 0.35;
		float moss_h = 0.036 + cushion_pillows * 0.032 + fur_fibers * 0.018;
		return mix(rock_h, moss_h, smoothstep(0.10, 0.65, moss_mask));
	}
	return rock_h;
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

void vertex() {
	// Respect explicit `moss_amount` per boulder / masonry piece so mossy boulders always get
	// lush velvet moss cushions while bare boulders and bridge piers stay clean stone.
	v_moss_affinity = moss_amount;

	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 local_dome = normalize(VERTEX + vec3(0.0, 0.35, 0.0));
	float disp = (value_noise(wp.xz * 1.9 + wp.y * 1.4) - 0.5) * 0.065;
	// Physical 3D pillowing of thick moss caps on upper boulder surfaces
	float top_pillow = smoothstep(0.18, 0.72, local_dome.y) * smoothstep(0.35, 0.85, moss_amount) * smoothstep(0.48, 0.68, wp.y);
	float pillow_disp = top_pillow * (0.032 + 0.026 * value_noise(wp.xz * 4.8));
	VERTEX += local_dome * (disp + pillow_disp);

	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wnormal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_dome_dir = normalize((MODEL_MATRIX * vec4(local_dome, 0.0)).xyz);
	v_custom = INSTANCE_CUSTOM;
}

void fragment() {
	vec3 base_n = normalize(mix(v_wnormal, v_dome_dir, 0.24));
	float inst_moss = v_custom.a > 0.01 ? v_custom.a : moss_amount;
	float moss_mask = eval_moss_blanket(v_world, base_n, v_dome_dir, inst_moss * 1.18);

	// 1. 3D Analytical Rock Fracture & Velvet Fur-Moss Micro-Normals
	float eps = 0.016;
	float h0 = rock_and_moss_micro_height(v_world, base_n, moss_mask);
	float hx = rock_and_moss_micro_height(v_world + vec3(eps, 0.0, 0.0), base_n, moss_mask);
	float hy = rock_and_moss_micro_height(v_world + vec3(0.0, eps, 0.0), base_n, moss_mask);
	float hz = rock_and_moss_micro_height(v_world + vec3(0.0, 0.0, eps), base_n, moss_mask);
	vec3 grad = vec3(h0 - hx, h0 - hy, h0 - hz) / eps;
	grad -= base_n * dot(grad, base_n);
	vec3 world_nrm = normalize(base_n + grad * 1.08);
	NORMAL = normalize((VIEW_MATRIX * vec4(world_nrm, 0.0)).xyz);

	// 2. Triplanar `Rocks_Diffuse.png` blended with Weathered Mountain Granite & Warm Limestone
	vec3 tex_col = triplanar_rock_tex(v_world, base_n, triplanar_scale);
	float tex_luma = dot(tex_col, vec3(0.333));
	float crag = triplanar_fbm(v_world, base_n, 2.2);
	float detail = triplanar_fbm(v_world + vec3(4.7, -1.9, 3.1), base_n, 6.4);
	float crevice = clamp(1.0 - smoothstep(0.16, 0.54, tex_luma), 0.0, 1.0);

	vec3 slate_base = vec3(0.25, 0.26, 0.25);
	vec3 granite_warm = vec3(0.45, 0.42, 0.36);
	vec3 proc_col = mix(slate_base, granite_warm, smoothstep(0.22, 0.76, crag * 0.65 + detail * 0.35));
	vec3 c = mix(proc_col, tex_col * vec3(0.84, 0.81, 0.77), 0.72);
	c *= mix(1.0, 0.48, crevice * 0.78);
	c = mix(c, vec3(0.46, 0.48, 0.32), smoothstep(0.68, 0.88, detail * crag * 1.65) * 0.30);
	c *= tint;
	if (length(v_custom.rgb) > 0.02) {
		c *= v_custom.rgb;
	}

	float up = world_nrm.y;
	c *= 0.75 + 0.31 * smoothstep(-0.35, 0.82, up);

	// 3. Detailed Velvet "Fur-Moss" Blanket (Micro-Fibers, Spore Tips & Rim Velvet Sheen)
	float crevice_moss = crevice * smoothstep(0.20, 0.68, up) * smoothstep(0.46, 0.60, v_world.y) * inst_moss * 0.48;
	float full_moss = clamp(max(moss_mask, crevice_moss), 0.0, 0.88);

	if (full_moss > 0.01) {
		float fiber_fine = value_noise(v_world.xz * 38.0 + v_world.y * 22.0);
		float fiber_micro = value_noise(v_world.xz * 76.0 - v_world.y * 41.0);
		float cushion_lobe = fbm(v_world.xz * 7.2 + vec2(2.4, -1.9));

		vec3 ground_moss = meadow_ground_palette(v_world.xz);
		vec3 deep_velvet = vec3(0.06, 0.12, 0.03);
		vec3 mid_emerald = mix(vec3(0.16, 0.29, 0.09), ground_moss * 0.90, 0.55);
		vec3 sunlit_tips = vec3(0.28, 0.42, 0.13);
		vec3 golden_spore = vec3(0.37, 0.47, 0.16);

		// Pronounced internal cushion shadows and fibrous tuft highlights
		vec3 fur_col = mix(deep_velvet, mid_emerald, smoothstep(0.22, 0.68, cushion_lobe));
		fur_col = mix(fur_col, sunlit_tips, smoothstep(0.42, 0.78, fiber_fine) * 0.82);
		fur_col = mix(fur_col, golden_spore, smoothstep(0.68, 0.92, fiber_micro * fiber_fine * 1.40) * 0.55);
		fur_col *= mix(0.76, 1.14, smoothstep(0.28, 0.74, cushion_lobe * 0.6 + fiber_fine * 0.4));

		// Subtle grazing-angle velvet fur rim sheen (without neon clipping)
		float ndotv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
		float velvet_rim = pow(1.0 - ndotv, 2.7) * smoothstep(0.0, 0.7, up);
		fur_col += vec3(0.08, 0.13, 0.04) * velvet_rim * 0.68;

		// Dark organic shadow border where thick moss cushion meets bare granite
		float moss_border = smoothstep(0.06, 0.24, full_moss) * (1.0 - smoothstep(0.24, 0.52, full_moss));
		c = mix(c, vec3(0.07, 0.11, 0.04), moss_border * 0.64);
		c = mix(c, fur_col, smoothstep(0.08, 0.56, full_moss));
	}

	// 4. Physical Nivarel River Interaction (`WATER_SURFACE_Y = 0.42`)
	float water_y = 0.42;
	float above_w = v_world.y - water_y;
	float wet_belt = (1.0 - smoothstep(0.0, 0.24, above_w)) * step(-0.08, above_w);
	float submerge_depth = clamp(-above_w / 0.75, 0.0, 1.0);
	float wet_factor = clamp(max(wetness, max(wet_belt * 0.86, submerge_depth)), 0.0, 1.0);

	c *= mix(1.0, 0.58, wet_factor);
	vec3 underwater_tint = vec3(0.05, 0.17, 0.15);
	c = mix(c, underwater_tint, submerge_depth * 0.72);

	ALBEDO = c;
	ROUGHNESS = clamp(mix(mix(0.84, 0.95, full_moss), 0.22, wet_factor), 0.18, 0.96);
	SPECULAR = mix(mix(0.14, 0.05, full_moss), 0.42, wet_factor);
	BACKLIGHT = vec3(0.16, 0.24, 0.07) * full_moss * 0.55;
}
