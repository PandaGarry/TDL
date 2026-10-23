shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// Step 2 3D Triplanar Mountain Granite, Crevice Moss & Stream Waterline Shader (v4):
// - Seam-free continuous vertex shaping (`v_local` radial direction — zero UV/hard-edge seam tearing!).
// - 3-axis triplanar projection of `Rocks_Diffuse.png` (`albedo_tex`) with analytical 3D normal
//   extraction directly from the rock fracture crevices and quartz veins.
// - Organic crevice & dome moss cushions (no flat green polygon caps on low-poly top faces!).
// - Physical stream interaction at `WATER_SURFACE_Y = 0.42`: capillary wet dark band, broken
//   waterline foam collar, and underwater Beer-Lambert optical absorption.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D moss_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec3 tint : source_color = vec3(0.94, 0.92, 0.88);
uniform vec3 moss_color : source_color = vec3(0.22, 0.36, 0.14);
uniform float moss_amount : hint_range(0.0, 1.0) = 0.54;
uniform float snow_amount : hint_range(0.0, 1.0) = 0.04;
uniform float wetness : hint_range(0.0, 1.0) = 0.22;
uniform float triplanar : hint_range(0.0, 1.0) = 1.0;
uniform float triplanar_scale : hint_range(0.02, 2.0) = 0.58;

varying vec3 v_world;
varying vec3 v_wnormal;
varying vec3 v_dome_dir;
varying vec4 v_custom;

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

float rock_micro_height(vec3 p, vec3 n) {
	vec3 tex_c = triplanar_rock_tex(p, n, triplanar_scale);
	float tex_luma = dot(tex_c, vec3(0.333));
	float crag = triplanar_fbm(p, n, 2.5);
	return tex_luma * 0.044 + crag * 0.024;
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
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// Continuous position-based shaping (identical at shared seam vertices -> zero mesh tearing!)
	vec3 local_dome = normalize(VERTEX + vec3(0.0, 0.35, 0.0));
	float disp = (value_noise(wp.xz * 1.9 + wp.y * 1.4) - 0.5) * 0.06;
	VERTEX += local_dome * disp;
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wnormal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_dome_dir = normalize((MODEL_MATRIX * vec4(local_dome, 0.0)).xyz);
	v_custom = INSTANCE_CUSTOM;
}

void fragment() {
	vec3 base_n = normalize(mix(v_wnormal, v_dome_dir, 0.24));

	// 1. 3D Analytical Rock Fracture & Texture Crevice Micro-Normals
	float eps = 0.020;
	float h0 = rock_micro_height(v_world, base_n);
	float hx = rock_micro_height(v_world + vec3(eps, 0.0, 0.0), base_n);
	float hy = rock_micro_height(v_world + vec3(0.0, eps, 0.0), base_n);
	float hz = rock_micro_height(v_world + vec3(0.0, 0.0, eps), base_n);
	vec3 grad = vec3(h0 - hx, h0 - hy, h0 - hz) / eps;
	grad -= base_n * dot(grad, base_n);
	vec3 world_nrm = normalize(base_n + grad * 0.95);
	NORMAL = normalize((VIEW_MATRIX * vec4(world_nrm, 0.0)).xyz);

	// 2. Triplanar `Rocks_Diffuse.png` blended with Weathered Mountain Granite & Warm Limestone
	vec3 tex_col = triplanar_rock_tex(v_world, base_n, triplanar_scale);
	float tex_luma = dot(tex_col, vec3(0.333));
	float crag = triplanar_fbm(v_world, base_n, 2.2);
	float detail = triplanar_fbm(v_world + vec3(4.7, -1.9, 3.1), base_n, 6.4);
	float crevice = clamp(1.0 - smoothstep(0.16, 0.54, tex_luma), 0.0, 1.0);

	vec3 slate_base = vec3(0.26, 0.27, 0.26);
	vec3 granite_warm = vec3(0.44, 0.41, 0.36);
	vec3 proc_col = mix(slate_base, granite_warm, smoothstep(0.22, 0.76, crag * 0.65 + detail * 0.35));
	// Blend real rock photography (`Rocks_Diffuse.png`) with procedural macro-variation
	vec3 c = mix(proc_col, tex_col * vec3(0.82, 0.80, 0.76), 0.68);
	// Deepen fracture crevices for strong chiseled relief
	c *= mix(1.0, 0.52, crevice * 0.72);
	// Subtle warm lichen flecks on sunlit faces
	c = mix(c, vec3(0.45, 0.47, 0.31), smoothstep(0.68, 0.88, detail * crag * 1.65) * 0.32);
	c *= tint;
	if (length(v_custom.rgb) > 0.02) {
		c *= v_custom.rgb;
	}

	// Ground contact ambient occlusion at the base of the boulder
	float up = world_nrm.y;
	c *= 0.76 + 0.30 * smoothstep(-0.35, 0.82, up);

	// 3. Organic Crevice & Dome Moss Cushions (uses smooth `v_dome_dir.y` + crevice depth so
	//    it NEVER paints a flat green polygon cap on low-poly top triangles!)
	float inst_moss = v_custom.a > 0.01 ? v_custom.a : moss_amount;
	float dome_up = mix(v_dome_dir.y, world_nrm.y, 0.38);
	float moss_noise = (detail - 0.48) * 0.62 + (crag - 0.50) * 0.38 + crevice * 0.28;
	float moss_mask = smoothstep(0.48, 0.78, dome_up + moss_noise) * inst_moss;
	// Keep moss above the stream waterline (`WATER_SURFACE_Y = 0.42`)
	moss_mask *= smoothstep(0.46, 0.62, v_world.y);

	vec3 ground_moss = meadow_ground_palette(v_world.xz);
	vec3 rich_moss = mix(moss_color, ground_moss, 0.78) * (0.82 + 0.28 * detail);
	// Dark olive moss rim where moss meets bare stone
	float moss_rim = smoothstep(0.12, 0.38, moss_mask) * (1.0 - smoothstep(0.38, 0.70, moss_mask));
	c = mix(c, vec3(0.12, 0.19, 0.08), moss_rim * 0.42);
	c = mix(c, rich_moss, clamp(moss_mask, 0.0, 0.72));

	// 4. Physical Nivarel Creek Interaction (`WATER_SURFACE_Y = 0.42`):
	//    - Capillary wet belt just above water (y = 0.42..0.56)
	//    - Delicate waterline foam ring at y ~ 0.425
	//    - Underwater optical Beer-Lambert absorption below y = 0.42
	float water_y = 0.42;
	float above_w = v_world.y - water_y;
	float wet_belt = 1.0 - smoothstep(-0.04, 0.15, above_w);
	float wet = clamp(wetness * 0.26 + wet_belt * 0.80, 0.0, 0.88);
	c *= mix(1.0, 0.64, wet);

	// Broken foam collar right where the water surface meets the boulder
	float wl_band = exp(-pow((above_w - 0.008) / 0.022, 2.0));
	float wl_foam = wl_band * smoothstep(0.42, 0.72, detail * 0.7 + crag * 0.5) * 0.48;
	c = mix(c, vec3(0.74, 0.80, 0.75), wl_foam);

	// Underwater absorption so submerged boulder bases blend smoothly into the creek depth
	float submerge_depth = clamp(-above_w * 3.2, 0.0, 1.0);
	if (submerge_depth > 0.005) {
		vec3 creek_deep_tint = vec3(0.07, 0.20, 0.16);
		c = mix(c, creek_deep_tint, submerge_depth * 0.68);
	}

	ALBEDO = c;
	ROUGHNESS = mix(mix(0.84, 0.92, moss_mask), 0.22, wet);
	SPECULAR = mix(0.18, 0.54, wet);
}
