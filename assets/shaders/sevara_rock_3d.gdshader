shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// 3D Rock, Boulder & Path Stone Shader for Sevara Valley.
// Supports triplanar world mapping, procedural moss cushions on upward faces (v_wnormal.y),
// spring snow dusting on upper crests, and wet river sheen near water.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec3 tint : source_color = vec3(0.92, 0.93, 0.95);
uniform vec3 moss_color : source_color = vec3(0.28, 0.44, 0.18);
uniform float moss_amount : hint_range(0.0, 1.0) = 0.58;
uniform float snow_amount : hint_range(0.0, 1.0) = 0.12;
uniform float wetness : hint_range(0.0, 1.0) = 0.22;
uniform float triplanar : hint_range(0.0, 1.0) = 1.0;
uniform float triplanar_scale : hint_range(0.02, 2.0) = 0.28;

varying vec3 v_world;
varying vec3 v_wnormal;
varying vec4 v_custom;

float hash1(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash1(i + vec2(0.0, 0.0)), hash1(i + vec2(1.0, 0.0)), u.x),
		mix(hash1(i + vec2(0.0, 1.0)), hash1(i + vec2(1.0, 1.0)), u.x),
		u.y
	);
}

vec3 sample_triplanar(vec3 p, vec3 n) {
	vec3 w = pow(abs(n), vec3(4.0));
	w /= max(w.x + w.y + w.z, 0.0001);
	vec3 x = texture(albedo_tex, p.zy * triplanar_scale).rgb;
	vec3 y = texture(albedo_tex, p.xz * triplanar_scale).rgb;
	vec3 z = texture(albedo_tex, p.xy * triplanar_scale).rgb;
	return x * w.x + y * w.y + z * w.z;
}

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wnormal = normalize(mat3(MODEL_MATRIX) * NORMAL);
	v_custom = INSTANCE_CUSTOM;
}

void fragment() {
	vec3 c = triplanar > 0.5 ? sample_triplanar(v_world, v_wnormal) : texture(albedo_tex, UV).rgb;
	c *= tint;
	if (length(v_custom.rgb) > 0.02) {
		c *= v_custom.rgb;
	}

	float up = v_wnormal.y;
	c *= 0.88 + 0.24 * smoothstep(0.15, 0.90, up);

	float n = value_noise(v_world.xz * 0.75 + vec2(v_world.y * 0.45));
	float inst_moss = v_custom.a > 0.01 ? v_custom.a : moss_amount;
	float moss = smoothstep(0.48, 0.82, up + (n - 0.5) * 0.55) * inst_moss;
	c = mix(c, moss_color * (0.82 + 0.35 * n), clamp(moss, 0.0, 0.88));

	if (snow_amount > 0.01 && v_world.y > 0.8) {
		float sn = smoothstep(0.55, 0.86, up + (n - 0.5) * 0.4) * snow_amount * smoothstep(0.8, 2.4, v_world.y);
		c = mix(c, vec3(0.92, 0.95, 0.99), clamp(sn, 0.0, 0.78));
	}

	float wet = clamp(wetness + (1.0 - smoothstep(-0.35, 0.45, v_world.y)) * 0.45, 0.0, 0.85);
	c *= mix(1.0, 0.68, wet);

	ALBEDO = c;
	ROUGHNESS = mix(0.86, 0.30, wet);
	SPECULAR = mix(0.26, 0.56, wet);
}
