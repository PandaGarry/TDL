shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, diffuse_burley, specular_schlick_ggx;

// Step 3 Sevara Painterly Fluffy Tree, Willow & Botanical Bush Shader (v10):
// - Eliminates harsh X-plane cross-card artifacts via grazing-angle vertex puffing & edge alpha-scissor softening
// - ACES-calibrated deep forest emerald & warm sunlit olive-sage palette matching Step 1 grass & Step 2 moss
// - Spherical canopy dome normals (never inverted downward on backfaces) + deep inner-crown ambient occlusion

uniform int mode = 0;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec3 crown_center = vec3(0.0, 3.4, 0.0);
uniform vec3 crown_extent = vec3(2.0, 2.2, 2.0);
uniform float object_height = 5.0;
uniform float alpha_cut = 0.32;
uniform float stiffness = 3.5;
uniform float flutter = 0.038;
uniform float translucency = 0.42;
uniform float ground_normal = 0.48;
uniform float texture_color_mix = 0.24;
uniform bool instance_tint = false;

uniform vec4 color_dark : source_color = vec4(0.08, 0.18, 0.07, 1.0);
uniform vec4 color_light : source_color = vec4(0.26, 0.39, 0.14, 1.0);

varying float v_height_t;
varying float v_tree_seed;
varying float v_radial_t;
varying float v_face_align;
varying vec4 v_inst_custom;
varying vec3 v_canopy_nrm_view;
varying vec3 v_world_pos;

float hash13(vec3 p3) {
	p3 = fract(p3 * 0.1031);
	p3 += dot(p3, p3.zyx + 31.32);
	return fract((p3.x + p3.y) * p3.z);
}

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

void vertex() {
	vec3 world_origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	v_tree_seed = hash13(floor(world_origin * 2.0));
	v_inst_custom = INSTANCE_CUSTOM;

	// Measure how edge-on the raw leaf card polygon is relative to the camera view ray
	vec3 raw_world_n = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 raw_view_n = normalize((VIEW_MATRIX * vec4(raw_world_n, 0.0)).xyz);
	v_face_align = abs(raw_view_n.z);

	float h_norm = clamp(VERTEX.y / max(object_height, 0.4), 0.0, 1.25);
	v_height_t = clamp(h_norm, 0.0, 1.0);

	// Synchronized wind sway + gentle leaf cluster flutter
	float wind_amp = (0.24 / max(stiffness, 0.8)) * pow(h_norm, 1.25);
	float phase = TIME * 1.50 + world_origin.x * 0.37 + world_origin.z * 0.43;
	float gust_x = sin(phase + VERTEX.x * 1.2) * cos(phase * 0.75 + VERTEX.z * 1.1);
	float gust_z = cos(phase * 0.85 + VERTEX.y * 1.0);
	float leaf_flutter = sin(TIME * 3.6 + dot(VERTEX, vec3(3.7, 4.3, 3.1))) * flutter * h_norm;

	VERTEX.x += gust_x * wind_amp + leaf_flutter;
	VERTEX.z += gust_z * wind_amp * 0.78 + leaf_flutter;
	VERTEX.y += sin(phase * 1.3 + VERTEX.x * 1.6) * wind_amp * 0.12;

	vec3 local_nrm = NORMAL;
	if (mode == 0) {
		vec3 rel = (VERTEX - crown_center) / max(crown_extent, vec3(0.35));
		v_radial_t = clamp(length(rel), 0.0, 1.0);
		vec3 sphere_n = normalize(rel + vec3(0.0, 0.52, 0.0));
		// Puff edge-on cards slightly along the spherical canopy normal to break up 90-degree X-planes
		float edge_puff = (1.0 - smoothstep(0.10, 0.55, v_face_align)) * (UV.y - 0.5) * 0.28;
		VERTEX += sphere_n * edge_puff;
		local_nrm = normalize(mix(NORMAL, sphere_n, 0.88));
		local_nrm.y = max(local_nrm.y, 0.22);
		local_nrm = normalize(local_nrm);
	} else if (mode == 2) {
		vec3 bush_rel = VERTEX - vec3(0.0, object_height * 0.32, 0.0);
		v_radial_t = clamp(length(bush_rel) / max(object_height * 0.75, 0.25), 0.0, 1.0);
		vec3 dome_n = normalize(bush_rel + vec3(0.0, object_height * 0.62, 0.0));
		local_nrm = normalize(mix(dome_n, vec3(0.0, 1.0, 0.0), ground_normal));
	} else {
		v_radial_t = v_height_t;
		local_nrm = normalize(mix(NORMAL, vec3(0.0, 1.0, 0.0), ground_normal));
	}

	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	NORMAL = local_nrm;
	vec3 world_nrm = normalize((MODEL_MATRIX * vec4(local_nrm, 0.0)).xyz);
	v_canopy_nrm_view = normalize((VIEW_MATRIX * vec4(world_nrm, 0.0)).xyz);
}

void fragment() {
	// Keep the smooth outward canopy dome normal on both front and back of leaf cards
	vec3 safe_n = normalize(v_canopy_nrm_view);
	NORMAL = safe_n;

	if (mode == 3) {
		float root_ao = mix(0.58, 1.0, smoothstep(0.0, 0.45, v_height_t));
		float fresnel = pow(1.0 - clamp(dot(safe_n, VIEW), 0.0, 1.0), 3.0);
		ALBEDO = COLOR.rgb * root_ao + COLOR.rgb * fresnel * 0.12;
		BACKLIGHT = COLOR.rgb * translucency * 0.42;
		ROUGHNESS = 0.76;
		SPECULAR = 0.16;
	} else {
		vec4 tex_col = texture(albedo_tex, UV);
		// Soften edge-on cross-cards so thin X-plane silhouettes dissolve into fluffy leaf clusters
		float edge_scissor_boost = (mode == 0 || mode == 2)
			? (1.0 - smoothstep(0.06, 0.34, v_face_align)) * 0.26
			: 0.0;
		ALPHA = tex_col.a;
		ALPHA_SCISSOR_THRESHOLD = clamp(alpha_cut * 0.74 + edge_scissor_boost, 0.20, 0.62);

		// Painterly canopy gradient matched to Step 1 meadow grass & Step 2 velvet moss
		float cluster_n = grad_noise(v_world_pos.xz * 1.35 + vec2(v_world_pos.y * 0.85, v_tree_seed * 7.3));
		float sub_lobe = grad_noise(v_world_pos.xz * 3.10 - vec2(v_world_pos.y * 1.4, 2.1));
		float grad_t = clamp(
			v_height_t * 0.56 + v_radial_t * 0.44 + (cluster_n - 0.5) * 0.22 + (sub_lobe - 0.5) * 0.12,
			0.0,
			1.0
		);

		vec3 mid_olive = mix(color_dark.rgb, color_light.rgb, 0.52);
		vec3 palette_col = mix(color_dark.rgb, mid_olive, smoothstep(0.08, 0.56, grad_t));
		palette_col = mix(palette_col, color_light.rgb, smoothstep(0.46, 0.92, grad_t));
		vec3 warm_shift = mix(vec3(0.94, 0.99, 0.92), vec3(1.05, 1.02, 0.90), v_tree_seed);
		palette_col *= warm_shift;

		if (instance_tint && v_inst_custom.a > 0.01) {
			palette_col = mix(palette_col, v_inst_custom.rgb, 0.65);
		}

		// Subtle leaf cluster modulation from texture luma (kept strictly within ACES range)
		float tex_luma = dot(tex_col.rgb, vec3(0.299, 0.587, 0.114));
		float leaf_relief = mix(0.80, 1.12, smoothstep(0.14, 0.82, tex_luma));
		vec3 final_col = palette_col * leaf_relief;

		// Deep interior branch/root ambient occlusion + soft sunlit outer crown tips
		float inner_ao = mix(0.54, 1.02, smoothstep(0.05, 0.85, grad_t));
		float ground_ao = (mode == 2) ? mix(0.58, 1.0, smoothstep(0.0, 0.45, v_height_t)) : 1.0;
		float fresnel = pow(1.0 - clamp(dot(safe_n, VIEW), 0.0, 1.0), 3.0);
		vec3 rim_light = color_light.rgb * fresnel * 0.12 * smoothstep(0.30, 0.95, grad_t);

		ALBEDO = final_col * inner_ao * ground_ao + rim_light;
		BACKLIGHT = mix(final_col, color_light.rgb, 0.45) * translucency * (0.22 + 0.36 * grad_t);
		ROUGHNESS = mix(0.88, 0.72, grad_t);
		SPECULAR = 0.14;
	}
}
