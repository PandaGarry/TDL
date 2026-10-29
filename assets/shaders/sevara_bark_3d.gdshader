shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

// Step 3 Sevara Sculpted Tree Bark Shader (v10):
// - C2-continuous quintic procedural bark grain & vertical ridges (zero orange-brick pixelation)
// - Deep ground-contact Ambient Occlusion & velvety moss skirt at the trunk roots (matches Step 1 & 2)
// - Soft upper-trunk canopy self-shadowing under the leaf crown

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform vec3 tint : source_color = vec3(0.88, 0.82, 0.76);
uniform vec3 moss_color : source_color = vec3(0.16, 0.29, 0.11);
uniform float moss_height : hint_range(0.0, 2.5) = 1.25;
uniform float normal_strength : hint_range(0.0, 2.0) = 0.85;
uniform float object_height : hint_range(0.5, 20.0) = 6.0;
uniform float stiffness : hint_range(0.5, 12.0) = 4.0;
uniform float ao_strength : hint_range(0.0, 1.0) = 0.65;
uniform vec2 wind_direction = vec2(0.92, 0.38);
uniform float wind_strength : hint_range(0.0, 3.0) = 1.0;

varying float v_ao;
varying float v_local_y;
varying float v_height_norm;
varying vec3 v_world_pos;
varying vec3 v_wnormal;

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

float soft_fbm(vec2 p) {
	float v = 0.0;
	float a = 0.52;
	mat2 rot = mat2(vec2(0.80, 0.60), vec2(-0.60, 0.80));
	for (int i = 0; i < 3; i++) {
		v += a * grad_noise(p);
		p = rot * p * 1.95 + vec2(3.7, -2.3);
		a *= 0.48;
	}
	return v;
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
	v_wnormal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	// Smooth quintic vertical bark furrows (no blocky orange texture tiling)
	vec2 bark_uv = vec2((v_world_pos.x + v_world_pos.z) * 3.4, v_local_y * 1.35);
	float eps = 0.04;
	float b0 = soft_fbm(bark_uv);
	float bx = soft_fbm(bark_uv + vec2(eps, 0.0));
	float by = soft_fbm(bark_uv + vec2(0.0, eps));
	vec2 b_grad = vec2(b0 - bx, b0 - by) / eps;

	vec3 base_n = normalize(v_wnormal);
	vec3 bark_world_nrm = normalize(base_n + vec3(b_grad.x * 0.08, b_grad.y * 0.04, b_grad.x * 0.08));
	NORMAL = normalize((VIEW_MATRIX * vec4(bark_world_nrm, 0.0)).xyz);

	float fine_ridge = grad_noise(bark_uv * vec2(2.6, 1.8) + vec2(1.9, -0.7));
	vec3 deep_bark = vec3(0.18, 0.14, 0.11);
	vec3 mid_bark = vec3(0.29, 0.23, 0.18);
	vec3 sunlit_bark = vec3(0.39, 0.32, 0.24);

	vec3 c = mix(deep_bark, mid_bark, smoothstep(0.18, 0.74, b0));
	c = mix(c, sunlit_bark, smoothstep(0.38, 0.84, fine_ridge) * 0.58);
	c *= tint;

	// Velvety mossy root skirt & ground-contact AO at trunk base (matches Step 1 & Step 2 moss)
	float moss_n = soft_fbm(v_world_pos.xz * 2.8 + vec2(v_local_y * 2.1, 1.3));
	float root_moss = 1.0 - smoothstep(0.08, max(moss_height, 0.20), v_local_y + (moss_n - 0.5) * 0.42);
	vec3 deep_moss = vec3(0.10, 0.19, 0.07);
	vec3 lush_moss = moss_color * (0.88 + 0.24 * moss_n);
	vec3 trunk_moss = mix(deep_moss, lush_moss, smoothstep(0.22, 0.78, moss_n));
	c = mix(c, trunk_moss, clamp(root_moss * 0.82, 0.0, 0.85));

	float root_contact_ao = mix(0.48, 1.0, smoothstep(0.0, 0.52, max(v_local_y, 0.0)));
	float canopy_shadow = mix(1.0, 0.54, smoothstep(0.42, 0.82, v_height_norm));

	ALBEDO = c * root_contact_ao * canopy_shadow;
	ROUGHNESS = mix(0.88, 0.94, root_moss);
	SPECULAR = 0.12;
}
