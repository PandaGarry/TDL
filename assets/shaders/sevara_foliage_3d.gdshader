shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, diffuse_burley, specular_schlick_ggx;

// Unified next-gen 2026 Sevara Foliage Shader (NatureBlocks / Stylized-Fluffy-Tree-Shader inspired):
// Supports all 4 botanical rendering modes used by SevaraAssetLibrary3D:
// mode 0 = Tree crowns (spherical crown normal puffing, high-craft leaf/needle detail, SSS backlight, Fresnel rim)
// mode 1 = Grass cards
// mode 2 = Bushes, ferns & wildflowers (with optional instance_tint from INSTANCE_CUSTOM)
// mode 3 = Procedural vertex-colored plants (Proc_Reeds, Proc_Kevar, Proc_Kevalu)

uniform int mode = 0;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec3 crown_center = vec3(0.0, 2.5, 0.0);
uniform vec3 crown_extent = vec3(1.8, 2.0, 1.8);
uniform float object_height = 4.0;
uniform float alpha_cut = 0.34;
uniform float stiffness = 3.5;
uniform float flutter = 0.045;
uniform float translucency = 0.48;
uniform float ground_normal = 0.35;
uniform float texture_color_mix = 0.80;
uniform bool instance_tint = false;

uniform vec4 color_dark : source_color = vec4(0.11, 0.25, 0.12, 1.0);
uniform vec4 color_light : source_color = vec4(0.46, 0.68, 0.26, 1.0);

varying float v_height_t;
varying float v_tree_seed;
varying float v_radial_t;
varying vec4 v_inst_custom;

float hash13(vec3 p3) {
	p3 = fract(p3 * 0.1031);
	p3 += dot(p3, p3.zyx + 31.32);
	return fract((p3.x + p3.y) * p3.z);
}

void vertex() {
	vec3 world_origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	v_tree_seed = hash13(floor(world_origin * 2.0));
	v_inst_custom = INSTANCE_CUSTOM;

	float h_norm = clamp(VERTEX.y / max(object_height, 0.4), 0.0, 1.25);
	v_height_t = clamp(h_norm, 0.0, 1.0);

	// Natural wind sway + leaf flutter
	float wind_amp = (0.28 / max(stiffness, 0.8)) * pow(h_norm, 1.25);
	float phase = TIME * 1.65 + world_origin.x * 0.37 + world_origin.z * 0.43;
	float gust_x = sin(phase + VERTEX.x * 1.4) * cos(phase * 0.75 + VERTEX.z * 1.2);
	float gust_z = cos(phase * 0.85 + VERTEX.y * 1.1);
	float leaf_flutter = sin(TIME * 4.2 + dot(VERTEX, vec3(4.3, 5.1, 3.7))) * flutter * h_norm;

	VERTEX.x += gust_x * wind_amp + leaf_flutter;
	VERTEX.z += gust_z * wind_amp * 0.78 + leaf_flutter;
	VERTEX.y += sin(phase * 1.4 + VERTEX.x * 1.8) * wind_amp * 0.16;

	if (mode == 0) {
		// Tree crown: puff normals outward from crown_center so branches read as a lush volumetric canopy
		vec3 rel = (VERTEX - crown_center) / max(crown_extent, vec3(0.35));
		v_radial_t = clamp(length(rel), 0.0, 1.0);
		vec3 sphere_n = normalize(rel + vec3(0.0, 0.38, 0.0));
		NORMAL = normalize(mix(NORMAL, sphere_n, 0.65));
	} else {
		v_radial_t = v_height_t;
		NORMAL = normalize(mix(NORMAL, vec3(0.0, 1.0, 0.0), ground_normal));
	}
}

void fragment() {
	vec3 safe_n = FRONT_FACING ? NORMAL : -NORMAL;
	NORMAL = safe_n;

	if (mode == 3) {
		// Procedural plants (reeds, kevar, kevalu) use vertex COLOR
		float fresnel = pow(1.0 - clamp(dot(safe_n, VIEW), 0.0, 1.0), 3.0);
		ALBEDO = COLOR.rgb + COLOR.rgb * fresnel * 0.18;
		BACKLIGHT = COLOR.rgb * translucency * 0.55;
		ROUGHNESS = 0.62;
		SPECULAR = 0.24;
	} else {
		vec4 tex_col = texture(albedo_tex, UV);
		ALPHA = tex_col.a;
		ALPHA_SCISSOR_THRESHOLD = clamp(alpha_cut * 0.78, 0.18, 0.46);

		float grad_t = clamp(v_height_t * 0.65 + v_radial_t * 0.35, 0.0, 1.0);
		vec3 palette_col = mix(color_dark.rgb, color_light.rgb, smoothstep(0.08, 0.92, grad_t));
		vec3 warm_shift = mix(vec3(0.93, 0.99, 0.91), vec3(1.07, 1.03, 0.89), v_tree_seed);
		palette_col *= warm_shift;

		if (instance_tint && v_inst_custom.a > 0.01) {
			palette_col = mix(palette_col, v_inst_custom.rgb, 0.65);
		}

		// Preserve high-craft botanical detail (needles, leaf veins, twigs) from the texture
		float tex_luma = dot(tex_col.rgb, vec3(0.299, 0.587, 0.114));
		vec3 shaded_palette = palette_col * clamp(tex_luma * 2.10 + 0.38, 0.45, 1.50);
		vec3 detail_rgb = tex_col.rgb * warm_shift * 1.18;
		if (instance_tint && v_inst_custom.a > 0.01) {
			detail_rgb = mix(detail_rgb, v_inst_custom.rgb * clamp(tex_luma * 1.8 + 0.35, 0.5, 1.4), 0.72);
		}
		vec3 final_col = mix(shaded_palette, detail_rgb, texture_color_mix);

		// Soft inner crown AO and sunlit outer tips
		float crown_ao = mix(0.68, 1.12, smoothstep(0.05, 0.88, grad_t));
		float fresnel = pow(1.0 - clamp(dot(safe_n, VIEW), 0.0, 1.0), 3.0);
		vec3 rim_light = color_light.rgb * fresnel * 0.20 * smoothstep(0.2, 1.0, grad_t);

		ALBEDO = final_col * crown_ao + rim_light;
		BACKLIGHT = mix(final_col, color_light.rgb, 0.5) * translucency * (0.35 + 0.45 * grad_t);
		ROUGHNESS = mix(0.68, 0.48, grad_t);
		SPECULAR = 0.25;
	}
}
