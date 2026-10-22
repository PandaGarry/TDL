shader_type spatial;
render_mode depth_draw_opaque, diffuse_burley, specular_schlick_ggx;

// Stylized naturalistic character & wildlife shader (No Rest for the Wicked / 2026 look):
// - ACES-calibrated albedo so skin, hair, fur, and wool never clip to white in direct sun
// - Procedural hair-cap coverage on the upper scalp of character skin meshes
// - Anatomical top-down lighting gradient, boot/paw ground-contact AO, and warm velvet rim light

uniform vec4 base_color : source_color = vec4(0.46, 0.32, 0.22, 1.0);
uniform vec4 underbelly_color : source_color = vec4(0.32, 0.22, 0.15, 1.0);
uniform vec4 rim_tint : source_color = vec4(0.86, 0.72, 0.52, 1.0);
uniform vec4 scalp_hair_color : source_color = vec4(0.20, 0.13, 0.08, 1.0);
uniform bool is_skin_surface = false;
uniform float base_roughness = 0.68;
uniform float base_metallic = 0.0;
uniform float rim_strength = 0.16;
uniform float micro_grain_strength = 0.07;
uniform float height_span = 1.8;

varying vec3 v_local_pos;
varying vec3 v_world_pos;
varying vec3 v_world_nrm;

float hash13(vec3 p3) {
	p3 = fract(p3 * 0.1031);
	p3 += dot(p3, p3.zyx + 31.32);
	return fract((p3.x + p3.y) * p3.z);
}

void vertex() {
	v_local_pos = VERTEX;
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float h_norm = clamp(v_local_pos.y / max(height_span, 0.25), 0.0, 1.0);
	float top_facing = clamp(v_world_nrm.y * 0.5 + 0.5, 0.0, 1.0);

	vec3 c_base = base_color.rgb;
	vec3 c_under = underbelly_color.rgb;

	// If this is the character Skin primitive, shade the upper crown/scalp & back of head as thick northern hair
	if (is_skin_surface && abs(v_local_pos.x) < 0.36 && v_local_pos.y > 2.12) {
		float crown_mask = smoothstep(2.30, 2.34, v_local_pos.y);
		float back_head_mask = (1.0 - smoothstep(-0.02, 0.08, v_local_pos.z)) * smoothstep(2.12, 2.20, v_local_pos.y);
		float temple_mask = smoothstep(0.14, 0.22, abs(v_local_pos.x)) * smoothstep(2.22, 2.28, v_local_pos.y) * (1.0 - smoothstep(0.06, 0.15, v_local_pos.z));
		float hair_cov = clamp(max(crown_mask, max(back_head_mask, temple_mask)), 0.0, 1.0);
		c_base = mix(c_base, scalp_hair_color.rgb, hair_cov);
		c_under = mix(c_under, scalp_hair_color.rgb * 0.72, hair_cov);
	}

	vec3 tone = mix(c_under, c_base, smoothstep(0.12, 0.72, h_norm * 0.65 + top_facing * 0.35));

	// Subtle organic fur/fabric micro-grain
	float grain = hash13(floor(v_local_pos * 48.0)) * 2.0 - 1.0;
	tone *= (1.0 + grain * micro_grain_strength);

	// Ground-contact AO on hooves, paws, and boots (never exceeding 0.98 so heads don't over-brighten)
	float foot_ao = mix(0.62, 0.96, smoothstep(0.0, 0.32, h_norm));
	tone *= foot_ao;

	// Velvet Fresnel rim light
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.4);
	vec3 rim = rim_tint.rgb * fresnel * rim_strength * smoothstep(0.15, 0.85, top_facing);

	ALBEDO = tone + rim;
	ROUGHNESS = base_roughness;
	METALLIC = base_metallic;
	SPECULAR = mix(0.22, 0.60, base_metallic);
}
