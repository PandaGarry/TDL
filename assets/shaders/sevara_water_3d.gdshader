shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

// 3D Water shader for Nivarel Channel, Mulane Wetland and Kevar Crater Pool.
// Dynamically responds to ecological silt_load, water_clarity and wild Kevalu.

uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform float silt_load : hint_range(0.0, 1.0) = 0.25;
uniform float water_clarity : hint_range(0.0, 1.0) = 0.78;
uniform float flow_speed : hint_range(0.0, 2.0) = 0.35;
uniform float kevalu_tint : hint_range(0.0, 1.0) = 0.0;

varying vec3 v_world_pos;

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float wave = sin(v_world_pos.z * 1.4 - TIME * 2.2) * 0.025
		+ cos(v_world_pos.x * 1.9 + TIME * 1.7) * 0.018;
	VERTEX.y += wave;
}

void fragment() {
	vec2 uv1 = v_world_pos.xz * 0.22 + vec2(0.0, -TIME * flow_speed * 0.25);
	vec2 uv2 = v_world_pos.xz * 0.37 + vec2(TIME * 0.04, -TIME * flow_speed * 0.18);
	vec3 n1 = texture(normal_tex, uv1).rgb;
	vec3 n2 = texture(normal_tex, uv2).rgb;
	vec3 combined_normal = normalize(mix(n1, n2, 0.5));

	vec3 clean_color = vec3(0.11, 0.38, 0.44);
	vec3 silted_color = vec3(0.46, 0.31, 0.19);
	vec3 kevar_color = vec3(0.14, 0.19, 0.24);

	float silt_factor = clamp((silt_load - 0.20) * 1.55 + (1.0 - water_clarity) * 0.4, 0.0, 1.0);
	vec3 water_col = mix(clean_color, silted_color, silt_factor);

	// Check if inside the Kevar crater basin (north-east)
	float dist_kevar = length(v_world_pos.xz - vec2(19.5, -13.5));
	if (dist_kevar < 9.5) {
		float mineral_ring = sin(dist_kevar * 3.2 - TIME * 0.8) * 0.5 + 0.5;
		vec3 oil_tint = mix(kevar_color, vec3(0.28, 0.38, 0.42), mineral_ring * (0.35 + kevalu_tint * 0.45));
		water_col = mix(water_col, oil_tint, smoothstep(9.5, 5.0, dist_kevar));
	}

	// Foam lines near sluice gate (z ~ -1.5) and dam (z ~ -11.0)
	float sluice_foam = exp(-pow((v_world_pos.z + 1.2) * 1.4, 2.0)) * clamp(1.0 - abs(v_world_pos.x) * 0.22, 0.0, 1.0);
	float ripple_crest = smoothstep(0.62, 0.85, combined_normal.r);
	float foam = clamp(sluice_foam * 0.65 + ripple_crest * 0.18, 0.0, 0.85);

	ALBEDO = mix(water_col, vec3(0.88, 0.91, 0.92), foam);
	NORMAL_MAP = combined_normal;
	NORMAL_MAP_DEPTH = 0.85;
	ROUGHNESS = mix(0.12, 0.38, silt_factor);
	METALLIC = 0.08;
	SPECULAR = 0.78;
	ALPHA = clamp(mix(0.76, 0.93, silt_factor) + foam * 0.15, 0.0, 0.96);
}
