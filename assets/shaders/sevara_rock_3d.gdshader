shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// 3D Photogrammetric Rock, Boulder & Cliff Shader for Sevara Valley (2026 PBR).
// Supports triplanar world mapping for both albedo and normal maps, mossy top cushions,
// spring snow dusting on upper crests, and wet river sheen near water.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D moss_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec3 tint : source_color = vec3(0.86, 0.88, 0.90);
uniform vec3 moss_color : source_color = vec3(0.32, 0.48, 0.22);
uniform float moss_amount : hint_range(0.0, 1.0) = 0.62;
uniform float snow_amount : hint_range(0.0, 1.0) = 0.12;
uniform float wetness : hint_range(0.0, 1.0) = 0.24;
uniform float triplanar : hint_range(0.0, 1.0) = 1.0;
uniform float triplanar_scale : hint_range(0.02, 2.0) = 0.34;

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

vec3 sample_triplanar(sampler2D samp, vec3 p, vec3 n, float scale) {
	vec3 w = pow(abs(n), vec3(4.0));
	w /= max(w.x + w.y + w.z, 0.0001);
	vec3 x = texture(samp, p.zy * scale).rgb;
	vec3 y = texture(samp, p.xz * scale).rgb;
	vec3 z = texture(samp, p.xy * scale).rgb;
	return x * w.x + y * w.y + z * w.z;
}

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wnormal = normalize(mat3(MODEL_MATRIX) * NORMAL);
	v_custom = INSTANCE_CUSTOM;
}

void fragment() {
	vec3 rock_col = sample_triplanar(albedo_tex, v_world, v_wnormal, triplanar_scale);
	vec3 rock_nrm = sample_triplanar(normal_tex, v_world, v_wnormal, triplanar_scale);
	vec3 c = rock_col * tint;
	if (length(v_custom.rgb) > 0.02) {
		c *= v_custom.rgb;
	}

	float up = v_wnormal.y;
	c *= 0.80 + 0.30 * smoothstep(-0.15, 0.90, up);

	float n = value_noise(v_world.xz * 0.85 + vec2(v_world.y * 0.55));
	float inst_moss = v_custom.a > 0.01 ? v_custom.a : moss_amount;
	float rock_luma = dot(rock_col, vec3(0.3, 0.59, 0.11));
	float moss = smoothstep(0.42, 0.78, up + (n - 0.5) * 0.48 - (rock_luma - 0.5) * 0.25) * inst_moss;
	vec3 moss_sample = texture(moss_tex, v_world.xz * 0.42).rgb;
	vec3 rich_moss = mix(moss_color, moss_sample * 1.15, 0.65) * (0.85 + 0.30 * n);
	c = mix(c, rich_moss, clamp(moss, 0.0, 0.90));

	if (snow_amount > 0.01 && v_world.y > 0.8) {
		float sn = smoothstep(0.55, 0.86, up + (n - 0.5) * 0.4) * snow_amount * smoothstep(0.8, 2.4, v_world.y);
		c = mix(c, vec3(0.92, 0.95, 0.99), clamp(sn, 0.0, 0.78));
	}

	float wet = clamp(wetness + (1.0 - smoothstep(-0.35, 0.45, v_world.y)) * 0.52, 0.0, 0.88);
	c *= mix(1.0, 0.64, wet);

	ALBEDO = c;
	NORMAL_MAP = normalize(rock_nrm);
	NORMAL_MAP_DEPTH = mix(1.35, 0.95, moss);
	ROUGHNESS = mix(0.84, 0.26, wet);
	SPECULAR = mix(0.28, 0.58, wet);
}
