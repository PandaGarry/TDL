shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// Step 2 Soft Painterly River Stone, Velvet Moss & Planed Timber Shader (v7):
// - Eliminates pixelated PNG normal-map finite-difference artifacts, harsh crevices, and square grid noise.
// - Uses quintic C2-continuous gradient noise for soft, rounded, natural river-stone and planed-wood
//   shading that matches Step 1's painterly meadow aesthetic (Tiny Glade / No Rest for the Wicked style).
// - `surface_mode = 0`: Smooth river limestone/slate boulder with silky velvet moss crowns matching Step 1 grass.
// - `surface_mode = 1`: Smooth planed warm oak timber with gentle longitudinal grain & soft edge shading.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D moss_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform int surface_mode : hint_range(0, 1) = 0;
uniform vec3 tint : source_color = vec3(0.96, 0.94, 0.91);
uniform vec3 moss_color : source_color = vec3(0.22, 0.38, 0.14);
uniform float moss_amount : hint_range(0.0, 1.0) = 0.68;
uniform float snow_amount : hint_range(0.0, 1.0) = 0.0;
uniform float wetness : hint_range(0.0, 1.0) = 0.18;
uniform float triplanar : hint_range(0.0, 1.0) = 1.0;
uniform float triplanar_scale : hint_range(0.02, 2.0) = 0.38;

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

// Quintic C2-continuous gradient noise: zero square/grid artifacts, silky smooth transitions
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
		p = rot * p * 1.92 + vec2(1.7, -2.3);
		a *= 0.46;
	}
	return v;
}

float triplanar_soft_fbm(vec3 p, vec3 n, float scale) {
	vec3 w = pow(abs(n), vec3(2.5));
	w /= max(w.x + w.y + w.z, 0.0001);
	float nx = soft_fbm(p.yz * scale + vec2(2.3, -1.7));
	float ny = soft_fbm(p.xz * scale);
	float nz = soft_fbm(p.xy * scale + vec2(-3.1, 4.2));
	return nx * w.x + ny * w.y + nz * w.z;
}

float eval_moss_blanket(vec3 p, vec3 base_n, vec3 dome_dir, float affinity) {
	if (affinity <= 0.18) {
		return 0.0;
	}
	float macro_wave = triplanar_soft_fbm(p, base_n, 0.78);
	float soft_lobe = triplanar_soft_fbm(p + vec3(3.1, 1.7, -2.4), base_n, 1.65);
	float dome_up = mix(dome_dir.y, base_n.y, 0.52);
	float raw_m = dome_up + (soft_lobe - 0.50) * 0.42 + (macro_wave - 0.50) * 0.28;
	float above_water = smoothstep(0.48, 0.66, p.y);
	return smoothstep(0.32, 0.66, raw_m) * affinity * above_water;
}

vec3 meadow_ground_palette(vec2 xz) {
	float macro_a = soft_fbm(xz * 0.045);
	float macro_b = soft_fbm(xz * 0.11 + vec2(5.2, 3.7));
	vec3 deep_sage = vec3(0.17, 0.30, 0.12);
	vec3 lush_meadow = vec3(0.24, 0.39, 0.15);
	vec3 warm_olive = vec3(0.32, 0.45, 0.18);
	vec3 col = mix(deep_sage, lush_meadow, smoothstep(0.22, 0.74, macro_a));
	col = mix(col, warm_olive, smoothstep(0.36, 0.80, macro_b) * 0.70);
	return col;
}

void vertex() {
	v_local = VERTEX;
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 local_dome = normalize(VERTEX + vec3(0.0, 0.22, 0.0));
	if (surface_mode == 0) {
		float top_pillow = smoothstep(0.25, 0.78, local_dome.y) * smoothstep(0.35, 0.85, moss_amount) * smoothstep(0.48, 0.68, wp.y);
		VERTEX += local_dome * (top_pillow * 0.020);
	}
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wnormal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_dome_dir = normalize((MODEL_MATRIX * vec4(local_dome, 0.0)).xyz);
	v_custom = INSTANCE_CUSTOM;
}

void fragment() {
	if (surface_mode == 1) {
		// Smooth Planed Oak Timber Mode (Bridge Planks, Beams & Handrails):
		// Soft longitudinal wood grain without pixelated bark textures or harsh black grooves.
		vec3 nrm = normalize(v_wnormal);
		NORMAL = normalize((VIEW_MATRIX * vec4(nrm, 0.0)).xyz);

		vec2 grain_uv = vec2(v_world.z * 0.85 + v_world.x * 0.35, v_world.x * 3.6 + v_world.y * 4.2);
		float grain_wave = soft_fbm(grain_uv);
		float ring_soft = grad_noise(grain_uv * vec2(0.55, 2.4) + vec2(1.3, 0.7));

		vec3 warm_oak_light = tint * vec3(1.05, 1.01, 0.95);
		vec3 warm_oak_mid = tint * vec3(0.92, 0.88, 0.82);
		vec3 warm_oak_deep = tint * vec3(0.78, 0.73, 0.66);

		vec3 wood_col = mix(warm_oak_deep, warm_oak_mid, smoothstep(0.20, 0.75, grain_wave));
		wood_col = mix(wood_col, warm_oak_light, smoothstep(0.40, 0.85, ring_soft) * 0.55);

		// Soft hemispheric sunlight & ground bounce
		float up = nrm.y;
		wood_col *= 0.82 + 0.24 * smoothstep(-0.4, 0.85, up);

		ALBEDO = wood_col;
		ROUGHNESS = 0.76;
		SPECULAR = 0.14;
		BACKLIGHT = vec3(0.06, 0.04, 0.02);
	} else {
		// Smooth Painterly River Stone & Velvet Moss Mode
		vec3 base_n = normalize(mix(v_wnormal, v_dome_dir, 0.28));
		float inst_moss = v_custom.a > 0.01 ? v_custom.a : moss_amount;
		float moss_mask = eval_moss_blanket(v_world, base_n, v_dome_dir, inst_moss);

		// Gentle, wide-radius normal Perturbation for soft rounded stone feel (zero pixelation)
		float eps = 0.08;
		float h0 = triplanar_soft_fbm(v_world, base_n, 1.05) * 0.014;
		float hx = triplanar_soft_fbm(v_world + vec3(eps, 0.0, 0.0), base_n, 1.05) * 0.014;
		float hy = triplanar_soft_fbm(v_world + vec3(0.0, eps, 0.0), base_n, 1.05) * 0.014;
		float hz = triplanar_soft_fbm(v_world + vec3(0.0, 0.0, eps), base_n, 1.05) * 0.014;
		vec3 grad = vec3(h0 - hx, h0 - hy, h0 - hz) / eps;
		grad -= base_n * dot(grad, base_n);
		vec3 world_nrm = normalize(base_n + grad * 0.35);
		NORMAL = normalize((VIEW_MATRIX * vec4(world_nrm, 0.0)).xyz);

		// Painterly Warm River Limestone & Soft Blue-Grey Slate Palette (Tiny Glade style)
		float macro_tone = triplanar_soft_fbm(v_world, base_n, 0.68);
		float meso_tone = triplanar_soft_fbm(v_world + vec3(4.1, -2.3, 1.9), base_n, 1.45);
		float subtle_vein = triplanar_soft_fbm(v_world + vec3(-1.8, 3.4, 2.7), base_n, 2.3);

		vec3 cool_river_slate = vec3(0.38, 0.40, 0.41);
		vec3 warm_limestone = vec3(0.51, 0.48, 0.43);
		vec3 sunlit_sandstone = vec3(0.58, 0.55, 0.49);

		vec3 c = mix(cool_river_slate, warm_limestone, smoothstep(0.22, 0.78, macro_tone));
		c = mix(c, sunlit_sandstone, smoothstep(0.38, 0.84, meso_tone) * 0.58);
		c *= mix(0.91, 1.05, smoothstep(0.22, 0.78, subtle_vein));
		c *= tint;
		if (length(v_custom.rgb) > 0.02) {
			c *= v_custom.rgb;
		}

		// Soft hemispheric ambient sky/ground gradient
		float up = world_nrm.y;
		vec3 ground_bounce = vec3(0.28, 0.35, 0.22);
		c = mix(c * 0.78 + ground_bounce * 0.08, c * 1.05, smoothstep(-0.45, 0.85, up));

		// Silky Velvet Moss Crown (Seamless with Step 1 Meadow Grass Palette)
		if (moss_mask > 0.01) {
			float soft_tuft = soft_fbm(v_world.xz * 1.8 + vec2(1.7, -1.3));
			float velvet_wave = grad_noise(v_world.xz * 3.8 + v_world.y * 1.8);

			vec3 ground_moss = meadow_ground_palette(v_world.xz);
			vec3 deep_moss = mix(vec3(0.16, 0.28, 0.11), ground_moss * 0.86, 0.65);
			vec3 mid_moss = mix(vec3(0.23, 0.38, 0.14), ground_moss, 0.72);
			vec3 warm_moss_tips = vec3(0.32, 0.47, 0.18);

			vec3 moss_col = mix(deep_moss, mid_moss, smoothstep(0.20, 0.78, soft_tuft));
			moss_col = mix(moss_col, warm_moss_tips, smoothstep(0.32, 0.82, velvet_wave) * 0.52);

			// Soft grazing-angle velvet sheen
			float ndotv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
			float velvet_rim = pow(1.0 - ndotv, 2.4) * smoothstep(-0.1, 0.8, up);
			moss_col += vec3(0.07, 0.11, 0.03) * velvet_rim * 0.62;

			// Gentle organic transition border where moss hugs warm stone
			float edge_darken = smoothstep(0.04, 0.24, moss_mask) * (1.0 - smoothstep(0.24, 0.62, moss_mask));
			c = mix(c, c * vec3(0.80, 0.84, 0.74), edge_darken * 0.45);
			c = mix(c, moss_col, smoothstep(0.05, 0.72, moss_mask));
		}

		// Smooth Nivarel River Waterline Interaction (`WATER_SURFACE_Y = 0.42`)
		float water_y = 0.42;
		float above_w = v_world.y - water_y;
		float wet_belt = (1.0 - smoothstep(0.0, 0.22, above_w)) * step(-0.08, above_w);
		float submerge_depth = clamp(-above_w / 0.80, 0.0, 1.0);
		float wet_factor = clamp(max(wetness * 0.60, max(wet_belt * 0.75, submerge_depth)), 0.0, 1.0);

		c *= mix(1.0, 0.70, wet_factor);
		vec3 underwater_tint = vec3(0.08, 0.21, 0.19);
		c = mix(c, underwater_tint, submerge_depth * 0.65);

		ALBEDO = c;
		ROUGHNESS = clamp(mix(mix(0.80, 0.94, moss_mask), 0.28, wet_factor), 0.24, 0.96);
		SPECULAR = mix(mix(0.12, 0.05, moss_mask), 0.34, wet_factor);
		BACKLIGHT = vec3(0.15, 0.23, 0.07) * moss_mask * 0.55;
	}
}
