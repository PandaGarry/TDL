shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// Step 2 3D Triplanar Granite, Limestone & Mossy Boulder Shader (v3 — Crisp Angular Facets):
// - Combines screen-space geometric facet normals (`dFdx`/`dFdy`) with 3D triplanar fracture
//   micro-normals so low-poly boulders read as sharp, chiseled mountain rock instead of smooth blobs.
// - Subtle world-space vertex displacement gives every boulder instance a unique silhouette.
// - Patchy moss cushions sit in upper crevices while leaving sunlit granite facets exposed.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D moss_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec3 tint : source_color = vec3(0.92, 0.91, 0.88);
uniform vec3 moss_color : source_color = vec3(0.23, 0.37, 0.15);
uniform float moss_amount : hint_range(0.0, 1.0) = 0.56;
uniform float snow_amount : hint_range(0.0, 1.0) = 0.04;
uniform float wetness : hint_range(0.0, 1.0) = 0.22;
uniform float triplanar : hint_range(0.0, 1.0) = 1.0;
uniform float triplanar_scale : hint_range(0.02, 2.0) = 0.34;

varying vec3 v_world;
varying vec3 v_wnormal;
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

float triplanar_grain(vec3 p, vec3 n, float scale) {
	vec3 w = abs(n);
	w /= max(w.x + w.y + w.z, 0.0001);
	return value_noise(p.yz * scale) * w.x
		+ value_noise(p.xz * scale) * w.y
		+ value_noise(p.xy * scale) * w.z;
}

float rock_micro_height(vec3 p, vec3 n) {
	float crag = triplanar_fbm(p, n, 3.2);
	float detail = triplanar_fbm(p + vec3(3.1, 1.4, -2.2), n, 8.4);
	float strata = sin(p.y * 8.5 + crag * 4.6) * 0.5 + 0.5;
	return crag * 0.036 + detail * 0.018 + strata * 0.020;
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
	vec3 wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	// Subtle world-space crag displacement so each rock instance has angular variety
	float disp = (value_noise(wp.xz * 2.4 + wp.y * 1.7) - 0.5) * 0.12;
	VERTEX += NORMAL * disp;
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wnormal = wn;
	v_custom = INSTANCE_CUSTOM;
}

void fragment() {
	// Combine geometric triangle facet normal with vertex normal for crisp chiseled rock planes
	vec3 dpx = dFdx(v_world);
	vec3 dpy = dFdy(v_world);
	vec3 facet_n = normalize(cross(dpy, dpx));
	if (dot(facet_n, v_wnormal) < 0.0) {
		facet_n = -facet_n;
	}
	vec3 base_n = normalize(mix(v_wnormal, facet_n, 0.66));

	// 1. Full 3D Analytical Rock Fracture & Cleavage Micro-Normals
	float eps = 0.022;
	float h0 = rock_micro_height(v_world, base_n);
	float hx = rock_micro_height(v_world + vec3(eps, 0.0, 0.0), base_n);
	float hy = rock_micro_height(v_world + vec3(0.0, eps, 0.0), base_n);
	float hz = rock_micro_height(v_world + vec3(0.0, 0.0, eps), base_n);
	vec3 grad = vec3(h0 - hx, h0 - hy, h0 - hz) / eps;
	grad -= base_n * dot(grad, base_n);
	vec3 world_nrm = normalize(base_n + grad * 0.92);
	NORMAL = normalize((VIEW_MATRIX * vec4(world_nrm, 0.0)).xyz);

	// 2. Natural Weathered Granite, Warm Limestone & Lichen Palette
	float crag = triplanar_fbm(v_world, base_n, 2.8);
	float detail = triplanar_fbm(v_world + vec3(5.2, -1.8, 3.4), base_n, 7.2);
	float grain = triplanar_grain(v_world, base_n, 20.0);
	float strata = sin(v_world.y * 8.5 + crag * 4.6) * 0.5 + 0.5;
	// Dark crevice veins where `crag` and `detail` dip
	float fissure = smoothstep(0.36, 0.18, crag * 0.65 + detail * 0.35);

	vec3 slate_dark = vec3(0.24, 0.25, 0.24);
	vec3 granite_warm = vec3(0.41, 0.39, 0.35);
	vec3 limestone_sun = vec3(0.52, 0.48, 0.41);

	vec3 c = mix(slate_dark, granite_warm, smoothstep(0.20, 0.68, crag * 0.60 + strata * 0.40));
	c = mix(c, limestone_sun, smoothstep(0.52, 0.84, detail) * 0.64);
	c = mix(c, vec3(0.14, 0.14, 0.13), fissure * 0.55);
	// Pale gold-green crustose lichen flecks on sunlit facets
	c = mix(c, vec3(0.46, 0.48, 0.32), smoothstep(0.68, 0.88, detail * crag * 1.65) * 0.38);
	c *= (0.86 + 0.26 * grain) * tint;
	if (length(v_custom.rgb) > 0.02) {
		c *= v_custom.rgb;
	}

	float up = world_nrm.y;
	c *= 0.80 + 0.28 * smoothstep(-0.25, 0.85, up);

	// 3. Patchy Moss Cushions in Upper Hollows (leaves rocky ridges & edges exposed!)
	float inst_moss = v_custom.a > 0.01 ? v_custom.a : moss_amount;
	float moss_edge_noise = (detail - 0.5) * 0.58 + (crag - 0.5) * 0.32;
	float moss_mask = smoothstep(0.56, 0.82, base_n.y + moss_edge_noise) * inst_moss;
	moss_mask *= smoothstep(0.48, 0.68, v_world.y);
	vec3 ground_moss = meadow_ground_palette(v_world.xz);
	vec3 rich_moss = mix(moss_color, ground_moss, 0.78) * (0.85 + 0.25 * detail);
	c = mix(c, rich_moss, clamp(moss_mask, 0.0, 0.74));

	// 4. Wet River Sheen near Nivarel Creek Waterline (WATER_SURFACE_Y = 0.42)
	float water_prox = 1.0 - smoothstep(0.38, 0.64, v_world.y);
	float wet = clamp(wetness * 0.30 + water_prox * 0.76, 0.0, 0.86);
	c *= mix(1.0, 0.68, wet);

	ALBEDO = c;
	ROUGHNESS = mix(mix(0.84, 0.92, moss_mask), 0.28, wet);
	SPECULAR = mix(0.18, 0.48, wet);
}
