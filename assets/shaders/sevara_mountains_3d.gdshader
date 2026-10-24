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

float ridged2d(vec2 p) {
	float n = noise2d(p) * 2.0 - 1.0;
	float r = 1.0 - abs(n);
	return r * r;
}

float ridge_profile(float a) {
	vec2 dir = vec2(cos(a), sin(a));
	float n = ridged2d(dir * 2.4 + vec2(seed * 13.0, seed * 7.0)) * 0.56;
	n += ridged2d(dir * 5.8 + vec2(seed * 31.0, seed * 19.0)) * 0.29;
	n += ridged2d(dir * 12.5 + vec2(seed * 57.0, seed * 41.0)) * 0.15;
	float valley_pass = 0.65 + 0.35 * sin(a * 2.0 + seed * 9.0);
	float prof = 0.16 + pow(clamp(n * valley_pass, 0.0, 1.0), 1.25) * 0.84;
	// Carve a dramatic V-shaped mountain canyon pass where the Nivarel river enters from the north
	vec2 river_entry_dir = normalize(vec2(0.08, -0.996));
	float river_align = max(dot(dir, river_entry_dir), 0.0);
	float inner_ring = 1.0 - smoothstep(65.0, 105.0, radius);
	float gorge_notch = pow(river_align, 64.0) * inner_ring;
	float gorge_shoulders = pow(river_align, 14.0) * (1.0 - pow(river_align, 48.0)) * inner_ring;
	return max(prof * (1.0 - gorge_notch * 0.82) + gorge_shoulders * 0.32, 0.04);
}

void vertex() {
	float a = VERTEX.x;
	float t = VERTEX.y;
	vec2 dir = vec2(cos(a), sin(a));
	float r = ridge_profile(a);
	float r_next = ridge_profile(a + 0.02);
	float dr_da = (r_next - r) / 0.02;
	float jag = ridged2d(dir * 4.5 + vec2(t * 3.8 + seed * 19.0, seed * 11.0)) - 0.45;
	float h = t * height * r;
	float rad = radius + (1.0 - t) * height * 0.85 + jag * height * 0.18;
	VERTEX = vec3(cos(a) * rad, h - 2.5 + jag * t * height * 0.06, sin(a) * rad);

	vec3 inward = vec3(-cos(a), 0.42, -sin(a));
	vec3 tangent = vec3(-sin(a), 0.0, cos(a));
	v_smooth_normal = normalize(inward - tangent * (dr_da * 1.45));
	v_t = t;
	v_ridge = r;
	v_pos = VERTEX;
}

void fragment() {
	float strata = noise2d(vec2(v_pos.x * 0.05 + v_pos.z * 0.05, v_pos.y * 0.28));
	float gully = ridged2d(vec2(v_pos.x * 0.09 - v_pos.z * 0.08, v_pos.y * 0.14));
	vec3 n = normalize(v_smooth_normal + vec3((gully - 0.5) * 0.42, (strata - 0.5) * 0.22, (gully - 0.5) * 0.42));

	float lit = clamp(dot(n, normalize(sun_dir)) * 0.62 + 0.42, 0.0, 1.0);
	lit = smoothstep(0.16, 0.84, lit);
	vec3 rock_tone = base_color * (0.86 + 0.24 * strata);
	vec3 col = mix(shadow_color, rock_tone * (0.86 + sun_color * 0.28), lit);

	float h01 = v_t * v_ridge;
	float couloir = (1.0 - gully) * 0.34 + (strata - 0.5) * 0.14;
	float sn = smoothstep(0.86 - snow * 0.65, 1.02 - snow * 0.55, h01 + couloir) * smoothstep(0.28, 0.65, v_t);
	vec3 snow_lit = mix(vec3(0.68, 0.77, 0.88), snow_color, lit);
	col = mix(col, snow_lit, clamp(sn, 0.0, 0.92));

	float base_mist = smoothstep(0.55, 0.0, v_t);
	float total_haze = clamp(haze + base_mist * 0.58, 0.0, 0.94);
	ALBEDO = mix(col, haze_color, total_haze);
}
