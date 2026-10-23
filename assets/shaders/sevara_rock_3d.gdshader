shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// Step 2 Soft Beveled Painterly Stone, Velvet Moss & Planed Timber Shader (v8):
// - Works with subdivided & bevel-smoothed 3D rock meshes (`_subdivide_and_smooth_rock_mesh`)
//   so boulders keep natural geological silhouettes with soft, rounded edges (zero sharp low-poly
//   triangles and zero rubbery sphere look).
// - Uses quintic C2-continuous gradient noise + softly filtered triplanar stone modulation for
//   modern painterly rock & moss shading that harmonizes 100% with Step 1's meadow & roads.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D moss_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform int surface_mode : hint_range(0, 1) = 0;
uniform vec3 tint : source_color = vec3(0.96, 0.94, 0.90);
uniform vec3 moss_color : source_color = vec3(0.22, 0.38, 0.14);
uniform float moss_amount : hint_range(0.0, 1.0) = 0.68;
uniform float snow_amount : hint_range(0.0, 1.0) = 0.0;
uniform float wetness : hint_range(0.0, 1.0) = 0.18;
uniform float triplanar : hint_range(0.0, 1.0) = 1.0;
uniform float triplanar_scale : hint_range(0.02, 2.0) = 0.34;

varying vec3 v_world;
varying vec3 v_local;
varying vec3 v_wnormal;
varying vec3 v_dome_dir;
varying vec4 v_custom;

vec2 hash22(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.xx + p3.yz) * p3.zy) * 2.0 - 1.0;
}

// Quintic C2-continuous gradient noise: zero square/grid artifacts
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
	float a = 0.54;
	mat2 rot = mat2(vec2(0.80, 0.60), vec2(-0.60, 0.80));
	for (int i = 0; i < 3; i++) {
		v += a * grad_noise(p);
		p = rot * p * 1.95 + vec2(1.7, -2.3);
		a *= 0.46;
	}
	return v;
}

float triplanar_soft_fbm(vec3 p, vec3 n, float scale) {
	vec3 w = pow(abs(n), vec3(2.8));
	w /= max(w.x + w.y + w.z, 0.0001);
	float nx = soft_fbm(p.yz * scale + vec2(2.3, -1.7));
	float ny = soft_fbm(p.xz * scale);
	float nz = soft_fbm(p.xy * scale + vec2(-3.1, 4.2));
	return nx * w.x + ny * w.y + nz * w.z;
}

vec3 triplanar_soft_tex(vec3 p, vec3 n, float scale) {
	vec3 w = pow(abs(n), vec3(3.2));
	w /= max(w.x + w.y + w.z, 0.0001);
	vec3 tx = texture(albedo_tex, p.yz * scale + vec2(0.19, 0.43)).rgb;
	vec3 ty = texture(albedo_tex, p.xz * scale + vec2(0.07, 0.13)).rgb;
	vec3 tz = texture(albedo_tex, p.xy * scale + vec2(0.61, 0.29)).rgb;
	return tx * w.x + ty * w.y + tz * w.z;
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
		// Smooth Planed Oak Timber Mode (Bridge Planks, Beams & Handrails)
		vec3 nrm = normalize(v_wnormal);
		NORMAL = normalize((VIEW_MATRIX * vec4(nrm, 0.0)).xyz);

		vec2 grain_uv = vec2(v_world.z * 0.95 + v_world.x * 0.25, v_world.x * 3.8 + v_world.y * 4.2);
		float grain_wave = soft_fbm(grain_uv);
		float ring_soft = grad_noise(grain_uv * vec2(0.45, 2.8) + vec2(1.3, 0.7));
		float plank_id = grad_noise(vec2(floor(v_world.x * 2.8) * 1.7, 0.4));

		vec3 warm_oak_light = tint * vec3(0.95, 0.87, 0.75);
		vec3 warm_oak_mid = tint * vec3(0.79, 0.70, 0.58);
		vec3 warm_oak_deep = tint * vec3(0.63, 0.54, 0.43);

		vec3 wood_col = mix(warm_oak_deep, warm_oak_mid, smoothstep(0.18, 0.76, grain_wave));
		wood_col = mix(wood_col, warm_oak_light, smoothstep(0.35, 0.85, ring_soft) * 0.60);
		wood_col *= mix(0.93, 1.06, plank_id);

		float edge_fade = smoothstep(0.95, 1.42, abs(v_local.z));
		wood_col *= mix(1.0, 0.85, edge_fade * 0.60);

		float up = nrm.y;
		wood_col *= 0.80 + 0.25 * smoothstep(-0.4, 0.85, up);

		ALBEDO = wood_col;
		ROUGHNESS = 0.78;
		SPECULAR = 0.14;
		BACKLIGHT = vec3(0.06, 0.04, 0.02);
	} else {
		// Bevel-Smoothed Sculpted Stone & Organic Velvet Moss Mode
		vec3 base_n = normalize(mix(v_wnormal, v_dome_dir, 0.12));
		float inst_moss = v_custom.a > 0.01 ? v_custom.a : moss_amount;
		float moss_mask = eval_moss_blanket(v_world, base_n, v_dome_dir, inst_moss);

		// Soft, natural geological contour normals (quintic noise, zero pixelation)
		float eps = 0.042;
		float h0 = triplanar_soft_fbm(v_world, base_n, 1.65) * 0.024;
		float hx = triplanar_soft_fbm(v_world + vec3(eps, 0.0, 0.0), base_n, 1.65) * 0.024;
		float hy = triplanar_soft_fbm(v_world + vec3(0.0, eps, 0.0), base_n, 1.65) * 0.024;
		float hz = triplanar_soft_fbm(v_world + vec3(0.0, 0.0, eps), base_n, 1.65) * 0.024;
		vec3 grad = vec3(h0 - hx, h0 - hy, h0 - hz) / eps;
		grad -= base_n * dot(grad, base_n);
		vec3 world_nrm = normalize(base_n + grad * 0.68);
		NORMAL = normalize((VIEW_MATRIX * vec4(world_nrm, 0.0)).xyz);

		// Painterly Mountain Limestone & River Granite (with blurred mip-1.5 texture modulation)
		vec3 soft_tex = triplanar_soft_tex(v_world, base_n, triplanar_scale);
		float tex_tone = dot(soft_tex, vec3(0.333));
		float macro_tone = triplanar_soft_fbm(v_world, base_n, 0.85);
		floatstrata = triplanar_soft_fbm(v_world + vec3(3.7, -2.1, 1.4), base_n, 2.1);

		vec3 deep_slate = vec3(0.28, 0.30, 0.31);
		vec3 mid_granite = vec3(0.42, 0.40, 0.37);
		vec3 warm_limestone = vec3(0.53, 0.49, 0.43);

		vec3 c = mix(deep_slate, mid_granite, smoothstep(0.20, 0.72, macro_tone * 0.65 + tex_tone * 0.35));
		c = mix(c, warm_limestone, smoothstep(0.42, 0.82, floatstrata) * 0.62);
		// Soft mineral crevices and warm lichen flecks (smooth, never pixelated)
		float soft_crevice = smoothstep(0.46, 0.22, tex_tone * 0.6 + floatstrata * 0.4);
		c *= mix(1.0, 0.68, soft_crevice * 0.65);
		c *= tint;
		if (length(v_custom.rgb) > 0.02) {
			c *= v_custom.rgb;
		}

		// Soft beveled ridge highlight & ground bounce
		float up = world_nrm.y;
		float bevel_highlight = clamp(1.0 - abs(dot(v_wnormal, v_dome_dir)), 0.0, 1.0);
		c += vec3(0.06, 0.055, 0.045) * smoothstep(0.12, 0.48, bevel_highlight) * smoothstep(-0.1, 0.7, up);
		vec3 ground_bounce = vec3(0.24, 0.30, 0.18);
		c = mix(c * 0.74 + ground_bounce * 0.07, c * 1.06, smoothstep(-0.45, 0.85, up));

		// Multi-layered Painterly Velvet Moss Blanket (matches Step 1 Meadow Grass & 3D Moss Tufts)
		if (moss_mask > 0.01) {
			float cushion_macro = soft_fbm(v_world.xz * 2.6 + vec2(1.7, -1.3));
			float tuft_meso = soft_fbm(v_world.xz * 6.4 - vec2(v_world.y * 2.1, 0.8));

			vec3 ground_moss = meadow_ground_palette(v_world.xz);
			vec3 deep_hollow = vec3(0.11, 0.21, 0.07);
			vec3 lush_mid = mix(vec3(0.20, 0.35, 0.12), ground_moss, 0.65);
			vec3 sunlit_crown = vec3(0.31, 0.46, 0.16);

			vec3 moss_col = mix(deep_hollow, lush_mid, smoothstep(0.22, 0.72, cushion_macro));
			moss_col = mix(moss_col, sunlit_crown, smoothstep(0.38, 0.82, tuft_meso) * 0.68);

			float ndotv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
			float velvet_rim = pow(1.0 - ndotv, 2.5) * smoothstep(-0.1, 0.8, up);
			moss_col += vec3(0.06, 0.10, 0.03) * velvet_rim * 0.58;

			float border_ao = smoothstep(0.05, 0.26, moss_mask) * (1.0 - smoothstep(0.26, 0.62, moss_mask));
			c = mix(c, vec3(0.11, 0.16, 0.07), border_ao * 0.52);
			c = mix(c, moss_col, smoothstep(0.08, 0.66, moss_mask));
		}

		// Smooth Nivarel River Waterline Interaction (`WATER_SURFACE_Y = 0.42`)
		float water_y = 0.42;
		float above_w = v_world.y - water_y;
		float wet_belt = (1.0 - smoothstep(0.0, 0.22, above_w)) * step(-0.08, above_w);
		float submerge_depth = clamp(-above_w / 0.80, 0.0, 1.0);
		float wet_factor = clamp(max(wetness * 0.55, max(wet_belt * 0.78, submerge_depth)), 0.0, 1.0);

		c *= mix(1.0, 0.66, wet_factor);
		vec3 underwater_tint = vec3(0.07, 0.19, 0.18);
		c = mix(c, underwater_tint, submerge_depth * 0.68);

		ALBEDO = c;
		ROUGHNESS = clamp(mix(mix(0.82, 0.94, moss_mask), 0.26, wet_factor), 0.22, 0.96);
		SPECULAR = mix(mix(0.13, 0.05, moss_mask), 0.36, wet_factor);
		BACKLIGHT = vec3(0.15, 0.23, 0.07) * moss_mask * 0.55;
	}
}
