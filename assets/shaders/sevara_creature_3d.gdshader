shader_type spatial;
render_mode depth_draw_opaque, diffuse_burley, specular_schlick_ggx;

// Stylized naturalistic character & wildlife shader (No Rest for the Wicked / 2026 look):
// - Preserves clean facial features, hair, fur, and garment colors
// - Adds anatomical top-down lighting gradient & paw/boot ground contact AO
// - Adds warm velvet rim scattering on fur and wool edges

uniform vec4 base_color : source_color = vec4(0.58, 0.42, 0.28, 1.0);
uniform vec4 underbelly_color : source_color = vec4(0.42, 0.30, 0.20, 1.0);
uniform vec4 rim_tint : source_color = vec4(0.92, 0.78, 0.58, 1.0);
uniform float base_roughness = 0.68;
uniform float base_metallic = 0.0;
uniform float rim_strength = 0.28;
uniform float micro_grain_strength = 0.08;
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

	// Anatomical fur/garment shading from grounded feet/paws to sunlit shoulders
	vec3 tone = mix(underbelly_color.rgb, base_color.rgb, smoothstep(0.12, 0.68, h_norm * 0.65 + top_facing * 0.35));

	// Subtle organic fur/fabric micro-grain
	float grain = hash13(floor(v_local_pos * 48.0)) * 2.0 - 1.0;
	tone *= (1.0 + grain * micro_grain_strength);

	// Ground-contact AO on hooves, paws, and boots
	float foot_ao = mix(0.62, 1.04, smoothstep(0.0, 0.28, h_norm));
	tone *= foot_ao;

	// Velvet Fresnel rim light (catching morning sun on fur & wool cloaks)
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.2);
	vec3 rim = rim_tint.rgb * fresnel * rim_strength * smoothstep(0.15, 0.85, top_facing);

	ALBEDO = tone + rim;
	ROUGHNESS = base_roughness;
	METALLIC = base_metallic;
	SPECULAR = mix(0.26, 0.65, base_metallic);
}
