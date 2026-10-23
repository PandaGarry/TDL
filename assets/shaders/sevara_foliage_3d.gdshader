shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, diffuse_burley, specular_schlick_ggx;

// Step 3 Sevara Painterly Fluffy Tree, Willow & Botanical Bush Shader (v9):
// - Mode 0: Tree & Willow Crowns — spherical canopy normal puffing (never inverted downward on backfaces),
//   deep inner-crown ambient occlusion, warm sunlit outer foliage clusters, and golden subsurface backlight.
// - Mode 1: Tall Grass Cards.
// - Mode 2: Bushes, Ferns, Clover & Wildflower Clusters.
// - Mode 3: Procedural Botanical Stems (Reeds, Kevar, Kevalu).

uniform int mode = 0;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec3 crown_center = vec3(0.0, 3.2, 0.0);
uniform vec3 crown_extent = vec3(2.0, 2.2, 2.0);
uniform float object_height = 5.0;
uniform float alpha_cut = 0.32;
uniform float stiffness = 3.5;
uniform float flutter = 0.042;
uniform float translucency = 0.52;
uniform float ground_normal = 0.45;
uniform float texture_color_mix = 0.38;
uniform bool instance_tint = false;

uniform vec4 color_dark : source_color = vec4(0.10, 0.22, 0.09, 1.0);
uniform vec4 color_light : source_color = vec4(0.32, 0.46, 0.17, 1.0);

varying float v_height_t;
varying float v_tree_seed;
varying float v_radial_t;
varying vec4 v_inst_custom;
varying vec3 v_canopy_nrm_view;
varying vec3 v_world_pos;

float hash13(vec3 p3) {
	p3 = fract(p3 * 0.1031);
	p3 += dot(p3, p3.zyx + 31.32);
	return fract((p3.x + p3.y) * p3.z);
}

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

void vertex() {
	vec3 world_origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	v_tree_seed = hash13(floor(world_origin * 2.0));
	v_inst_custom = INSTANCE_CUSTOM;

	float h_norm = clamp(VERTEX.y / max(object_height, 0.4), 0.0, 1.25);
	v_height_t = clamp(h_norm, 0.0, 1.0);

	// Synchronized wind sway + gentle leaf cluster flutter
	float wind_amp = (0.26 / max(stiffness, 0.8)) * pow(h_norm, 1.25);
	float phase = TIME * 1.55 + world_origin.x * 0.37 + world_origin.z * 0.43;
	float gust_x = sin(phase + VERTEX.x * 1.2) * cos(phase * 0.75 + VERTEX.z * 1.1);
	float gust_z = cos(phase * 0.85 + VERTEX.y * 1.0);
	float leaf_flutter = sin(TIME * 3.8 + dot(VERTEX, vec3(3.7, 4.3, 3.1))) * flutter * h_norm;

	VERTEX.x += gust_x * wind_amp + leaf_flutter;
	VERTEX.z += gust_z * wind_amp * 0.78 + leaf_flutter;
	VERTEX.y += sin(phase * 1.3 + VERTEX.x * 1.6) * wind_amp * 0.14;

	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;

	vec3 local_nrm = NORMAL;
	if (mode == 0) {
		// Fluffy spherical canopy normal outward from crown center + upward sky bias
		vec3 rel = (VERTEX - crown_center) / max(crown_extent, vec3(0.35));
		v_radial_t = clamp(length(rel), 0.0, 1.0);
		vec3 sphere_n = normalize(rel + vec3(0.0, 0.48, 0.0));
		local_nrm = normalize(mix(NORMAL, sphere_n, 0.82));
		// Ensure normal never points downward into the ground
		local_nrm.y = max(local_nrm.y, 0.18);
		local_nrm = normalize(local_nrm);
	} else if (mode == 2) {
		// Fluffy bush / fern / flower dome normal
		vec3 bush_rel = VERTEX - vec3(0.0, object_height * 0.35, 0.0);
		v_radial_t = clamp(length(bush_rel) / max(object_height * 0.75, 0.25), 0.0, 1.0);
		vec3 dome_n = normalize(bush_rel + vec3(0.0, object_height * 0.55, 0.0));
		local_nrm = normalize(mix(dome_n, vec3(0.0, 1.0, 0.0), ground_normal));
	} else {
		v_radial_t = v_height_t;
		local_nrm = normalize(mix(NORMAL, vec3(0.0, 1.0, 0.0), ground_normal));
	}

	NORMAL = local_nrm;
	vec3 world_nrm = normalize((MODEL_MATRIX * vec4(local_nrm, 0.0)).xyz);
	v_canopy_nrm_view = normalize((VIEW_MATRIX * vec4(world_nrm, 0.0)).xyz);
}

void fragment() {
	// Keep the smooth outward canopy dome normal on both front and back of leaf cards!
	vec3 safe_n = normalize(v_canopy_nrm_view);
	NORMAL = safe_n;

	if (mode == 3) {
		// Procedural plants (reeds, kevar, kevalu) use vertex COLOR
		float root_ao = mix(0.62, 1.0, smoothstep(0.0, 0.45, v_height_t));
		float fresnel = pow(1.0 - clamp(dot(safe_n, VIEW), 0.0, 1.0), 3.0);
		ALBEDO = COLOR.rgb * root_ao + COLOR.rgb * fresnel * 0.14;
		BACKLIGHT = COLOR.rgb * translucency * 0.48;
		ROUGHNESS = 0.72;
		SPECULAR = 0.18;
	} else {
		vec4 tex_col = texture(albedo_tex, UV);
		ALPHA = tex_col.a;
		ALPHA_SCISSOR_THRESHOLD = clamp(alpha_cut * 0.75, 0.18, 0.42);

		// Multi-layered canopy gradient harmonized with Step 1 & Step 2 meadow/moss palette
		float cluster_n = value_noise(v_world_pos.xz * 1.45 + vec2(v_world_pos.y * 0.9, v_tree_seed * 7.3));
		float grad_t = clamp(v_height_t * 0.58 + v_radial_t * 0.42 + (cluster_n - 0.5) * 0.18, 0.0, 1.0);

		vec3 palette_col = mix(color_dark.rgb, color_light.rgb, smoothstep(0.10, 0.90, grad_t));
		vec3 warm_shift = mix(vec3(0.94, 0.98, 0.92), vec3(1.06, 1.02, 0.90), v_tree_seed);
		palette_col *= warm_shift;

		if (instance_tint && v_inst_custom.a > 0.01) {
			palette_col = mix(palette_col, v_inst_custom.rgb, 0.68);
		}

		// Soft botanical leaf/needle relief from texture luma (without harsh raw-texture clipping)
		float tex_luma = dot(tex_col.rgb, vec3(0.299, 0.587, 0.114));
		float leaf_relief = mix(0.76, 1.18, smoothstep(0.12, 0.82, tex_luma));
		vec3 shaded_palette = palette_col * leaf_relief;

		// For flower petals (mode 2 with instance_tint or high red/blue chroma), preserve blossom colors
		float tex_chroma = length(tex_col.rgb - vec3(tex_luma));
		float is_flower_petal = (mode == 2) ? smoothstep(0.24, 0.48, tex_luma) * step(0.15, tex_col.r - tex_col.g * 0.65) : 0.0;
		vec3 detail_rgb = tex_col.rgb * warm_shift * 0.88;
		vec3 final_col = mix(shaded_palette, detail_rgb, clamp(texture_color_mix * 0.38 + is_flower_petal * 0.75 + tex_chroma * 0.15, 0.0, 0.85));

		// Deep interior branch/root ambient occlusion + warm sunlit outer crown tips
		float inner_ao = mix(0.58, 1.06, smoothstep(0.04, 0.86, grad_t));
		float ground_ao = (mode == 2) ? mix(0.64, 1.0, smoothstep(0.0, 0.42, v_height_t)) : 1.0;
		float fresnel = pow(1.0 - clamp(dot(safe_n, VIEW), 0.0, 1.0), 2.8);
		vec3 rim_light = color_light.rgb * fresnel * 0.16 * smoothstep(0.25, 0.95, grad_t);

		ALBEDO = final_col * inner_ao * ground_ao + rim_light;
		BACKLIGHT = mix(final_col, color_light.rgb, 0.55) * translucency * (0.28 + 0.44 * grad_t);
		ROUGHNESS = mix(0.84, 0.64, grad_t);
		SPECULAR = 0.16;
	}
}
