shader_type spatial;
render_mode unshaded, fog_disabled, shadows_disabled, cull_disabled, depth_draw_opaque;

// Distant Mountain Ranges Shader encircling the Sevara Valley (2026 Alpine PBR look).
// Smooth analytical ridge normals, stratified basalt strata, couloir snow packs, and atmospheric haze.

uniform float height = 95.0;
uniform float radius = 260.0;
uniform float seed = 0.17;
uniform vec3 base_color : source_color = vec3(0.28, 0.36, 0.38);
uniform vec3 shadow_color : source_color = vec3(0.18, 0.24, 0.32);
uniform vec3 haze_color : source_color = vec3(0.68, 0.76, 0.84);
uniform vec3 snow_color : source_color = vec3(0.94, 0.96, 0.99);
uniform float haze : hint_range(0.0, 1.0) = 0.46;
uniform float snow : hint_range(0.0, 1.0) = 0.54;
uniform vec3 sun_dir = vec3(-0.42, 0.65, -0.58);
uniform vec3 sun_color : source_color = vec3(1.0, 0.94, 0.84);

varying vec3 v_pos;
varying vec3 v_smooth_normal;
varying float v_t;
varying float v_ridge;

float hash1(float x) {
	return fract(sin(x * 91.3458) * 47453.5453);
}

float noise1d(float x) {
	float i = floor(x);
	float f = fract(x);
	float u = f * f * (3.0 - 2.0 * f);
	return mix(hash1(i), hash1(i + 1.0), u);
}

float hash2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise2d(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash2(i), hash2(i + vec2(1.0, 0.0)), u.x),
		mix(hash2(i + vec2(0.0, 1.0)), hash2(i + vec2(1.0, 1.0)), u.x),
		u.y
	);
}

float ridge_profile(float a) {
	float u = a / 6.2831853;
	float n = noise1d(u * 7.0 + seed * 13.0) * 0.58;
	n += noise1d(u * 19.0 + seed * 31.0) * 0.28;
	n += noise1d(u * 43.0 + seed * 57.0) * 0.14;
	n = smoothstep(0.22, 0.84, n);
	return 0.22 + pow(n, 1.45) * 0.78;
}

void vertex() {
	float a = VERTEX.x;
	float t = VERTEX.y;
	float r = ridge_profile(a);
	float r_next = ridge_profile(a + 0.025);
	float dr_da = (r_next - r) / 0.025;
	float jag = noise1d(a * 11.0 + t * 4.5 + seed * 19.0) - 0.5;
	float h = t * height * r;
	float rad = radius + (t - 0.25) * height * 1.35 * (0.72 + jag * 0.65);
	VERTEX = vec3(cos(a) * rad, h - 12.0 + jag * t * height * 0.08, sin(a) * rad);

	vec3 inward = vec3(-cos(a), 0.52, -sin(a));
	vec3 tangent = vec3(-sin(a), 0.0, cos(a));
	v_smooth_normal = normalize(inward - tangent * (dr_da * 1.15));
	v_t = t;
	v_ridge = r;
	v_pos = VERTEX;
}

void fragment() {
	float strata = noise2d(vec2(v_pos.x * 0.045 + v_pos.z * 0.045, v_pos.y * 0.22));
	float micro = noise2d(vec2(v_pos.x * 0.16 - v_pos.z * 0.14, v_pos.y * 0.55));
	vec3 n = normalize(v_smooth_normal + vec3((strata - 0.5) * 0.35, (micro - 0.5) * 0.25, (micro - 0.5) * 0.35));

	float lit = clamp(dot(n, normalize(sun_dir)) * 0.58 + 0.46, 0.0, 1.0);
	lit = smoothstep(0.18, 0.86, lit);
	vec3 rock_tone = base_color * (0.84 + 0.28 * strata);
	vec3 col = mix(shadow_color, rock_tone * (0.84 + sun_color * 0.30), lit);

	float h01 = v_t * v_ridge;
	float couloir = (strata - 0.45) * 0.22 + (n.y - 0.48) * 0.26;
	float sn = smoothstep(0.96 - snow, 1.08 - snow, h01 + couloir) * step(0.01, snow);
	col = mix(col, snow_color * mix(0.76, 1.04, lit), clamp(sn, 0.0, 0.94));

	float fade = haze + (1.0 - haze) * (1.0 - smoothstep(0.0, 0.58, clamp(v_t, 0.0, 1.0))) * 0.86;
	col = mix(col, haze_color, clamp(fade, 0.0, 1.0));
	ALBEDO = col;
}
