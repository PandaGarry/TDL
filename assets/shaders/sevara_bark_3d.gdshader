shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

// Step 3 Sevara Sculpted Tree Bark Shader (v9):
// - Warm weathered mountain pine, oak & willow bark with 3D normal map relief
// - Deep ground-contact Ambient Occlusion & velvety moss skirt at the trunk roots (matches Step 1 & 2)
// - Soft upper-trunk canopy self-shadowing under the leaf crown

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform vec3 tint : source_color = vec3(0.86, 0.78, 0.68);
uniform vec3 moss_color : source_color = vec3(0.18, 0.32, 0.12);
uniform float moss_height : hint_range(0.0, 2.5) = 1.05;
uniform float normal_strength : hint_range(0.0, 2.0) = 1.15;
uniform float object_height : hint_range(0.5, 20.0) = 6.0;
uniform float stiffness : hint_range(0.5, 12.0) = 4.0;
uniform float ao_strength : hint_range(0.0, 1.0) = 0.68;
uniform vec2 wind_direction = vec2(0.92, 0.38);
uniform float wind_strength : hint_range(0.0, 3.0) = 1.0;

varying float v_ao;
varying float v_local_y;
varying float v_height_norm;
varying vec3 v_world_pos;

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

vec3 world_to_model_dir(mat4 model, vec3 v) {
	float s2 = max(dot(model[0].xyz, model[0].xyz), 0.0001);
	return (transpose(mat3(model)) * v) / s2;
}

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	float h = clamp(VERTEX.y / max(object_height, 0.5), 0.0, 1.4);
	v_height_norm = clamp(h, 0.0, 1.0);
	float weight = h * h;
	vec2 dir = normalize(wind_direction);
	float phase = dot(origin.xz, vec2(0.37, 0.61)) + INSTANCE_CUSTOM.a * 6.283;
	float sway = sin(TIME * 1.25 + phase) * 0.35 + sin(TIME * 0.62 + phase * 1.7) * 0.25;
	float bend = (sway * 0.55 + 0.35) * wind_strength / max(stiffness, 0.4);
	vec3 off = vec3(dir.x, 0.0, dir.y) * bend * weight;
	VERTEX += world_to_model_dir(MODEL_MATRIX, off);
	v_ao = COLOR.r;
	v_local_y = VERTEX.y;
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 tex_c = texture(albedo_tex, UV).rgb;
	// Warm painterly bark tone (prevents washed-out grey trunks)
	vec3 warm_bark = mix(vec3(0.32, 0.24, 0.17), vec3(0.54, 0.43, 0.32), smoothstep(0.15, 0.82, dot(tex_c, vec3(0.333))));
	vec3 c = mix(warm_bark, tex_c * tint, 0.62);

	// Organic mossy root skirt & ground-contact AO at trunk base
	float moss_n = value_noise(v_world_pos.xz * 3.2 + vec2(v_local_y * 2.4, 1.3));
	float root_moss = (1.0 - smoothstep(0.05, max(moss_height, 0.15), v_local_y + (moss_n - 0.5) * 0.35));
	c = mix(c, moss_color * (0.85 + 0.30 * moss_n), clamp(root_moss * 0.72, 0.0, 0.78));

	float root_contact_ao = mix(0.54, 1.0, smoothstep(0.0, 0.45, max(v_local_y, 0.0)));
	float canopy_shadow = mix(1.0, 0.62, smoothstep(0.48, 0.88, v_height_norm));
	float vtx_ao = mix(1.0, smoothstep(0.0, 1.0, v_ao), ao_strength * 0.65);

	ALBEDO = c * root_contact_ao * canopy_shadow * mix(0.56, 1.0, vtx_ao);
	NORMAL_MAP = texture(normal_tex, UV).rgb;
	NORMAL_MAP_DEPTH = normal_strength;
	ROUGHNESS = mix(0.88, 0.94, root_moss);
	SPECULAR = 0.14;
}
