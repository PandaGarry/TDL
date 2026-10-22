shader_type spatial;
render_mode depth_draw_opaque, diffuse_burley, specular_schlick_ggx;

// Tiny Glade / Manor Lords inspired architectural shader:
// Respects the 3D-modeled timber beams, roof tiles, and stone blocks of the mesh
// while adding tactile material micro-grain, curvature bevel highlights,
// warm bounce lighting, and ground-contact ambient occlusion + moss creep.

uniform sampler2D detail_albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D detail_normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D moss_albedo_tex : source_color, filter_linear_mipmap, repeat_enable;

uniform vec4 primary_tint : source_color = vec4(0.62, 0.46, 0.32, 1.0);
uniform vec4 secondary_tint : source_color = vec4(0.45, 0.33, 0.22, 1.0);
uniform float triplanar_scale = 0.42;
uniform float detail_mix = 0.42;
uniform float normal_strength = 0.55;
uniform float base_roughness = 0.78;
uniform float base_metallic = 0.0;
uniform float moss_height = 0.65;
uniform float moss_strength = 0.48;
uniform float bevel_highlight_strength = 0.22;

varying vec3 v_world_pos;
varying vec3 v_world_normal;
varying vec3 v_local_pos;

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

float ground_height_approx(vec2 xz) {
	float river_z = 6.0 * sin(xz.x * 0.035) + 2.5 * cos(xz.x * 0.07);
	float dist_river = abs(xz.y - river_z);
	float bank = smoothstep(3.2, 8.8, dist_river);
	float edge_x = smoothstep(34.0, 74.0, abs(xz.x));
	float edge_z = smoothstep(24.0, 54.0, abs(xz.y));
	float rim = clamp(edge_x * 0.55 + edge_z * 0.75, 0.0, 1.5);
	return -1.45 * (1.0 - bank) + rim * 6.0;
}

vec4 triplanar_sample(sampler2D tex, vec3 wpos, vec3 wnrm, float scale) {
	vec3 blend = abs(wnrm);
	blend = pow(max(blend, vec3(0.0001)), vec3(4.0));
	blend /= (blend.x + blend.y + blend.z);
	vec4 cx = texture(tex, wpos.zy * scale);
	vec4 cy = texture(tex, wpos.xz * scale);
	vec4 cz = texture(tex, wpos.xy * scale);
	return cx * blend.x + cy * blend.y + cz * blend.z;
}

void vertex() {
	v_local_pos = VERTEX;
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 wnrm = normalize(v_world_normal);
	vec3 detail_col = triplanar_sample(detail_albedo_tex, v_world_pos, wnrm, triplanar_scale).rgb;
	vec3 detail_nrm = triplanar_sample(detail_normal_tex, v_world_pos, wnrm, triplanar_scale).rgb;

	// Weathering variation across individual blocks/timbers using world position noise
	float patina = value_noise(v_world_pos.xz * 0.85 + vec2(v_world_pos.y * 1.4));
	vec3 base_tone = mix(secondary_tint.rgb, primary_tint.rgb, smoothstep(0.2, 0.8, patina));

	// Modulate base tone with tactile micro-detail without imposing harsh dark grid lines
	float detail_luma = dot(detail_col, vec3(0.299, 0.587, 0.114));
	vec3 shaded_col = mix(base_tone * clamp(detail_luma * 1.45 + 0.35, 0.55, 1.35), detail_col * (base_tone * 1.55), detail_mix);

	// Curvature / Bevel highlight on 3D stone & timber edges (Tiny Glade look)
	float edge_curv = clamp(length(fwidth(NORMAL)) * 2.4, 0.0, 1.0);
	shaded_col += mix(primary_tint.rgb, vec3(0.95, 0.88, 0.76), 0.5) * edge_curv * bevel_highlight_strength;

	// Ground contact AO and natural moss creep near the foundation
	float terrain_y = ground_height_approx(v_world_pos.xz);
	float h_above_ground = max(0.0, v_world_pos.y - terrain_y);
	float contact_ao = mix(0.58, 1.0, smoothstep(0.0, 0.95, h_above_ground));
	shaded_col *= contact_ao;

	if (moss_strength > 0.01) {
		float moss_mask = (1.0 - smoothstep(0.05, moss_height, h_above_ground)) * smoothstep(-0.2, 0.65, wnrm.y + patina * 0.35);
		vec3 moss_col = triplanar_sample(moss_albedo_tex, v_world_pos, wnrm, 0.38).rgb * vec3(0.78, 0.95, 0.72);
		shaded_col = mix(shaded_col, moss_col, clamp(moss_mask * moss_strength, 0.0, 0.75));
	}

	// Hemispherical top-to-bottom subtle gradient
	float sky_facing = clamp(wnrm.y * 0.5 + 0.5, 0.0, 1.0);
	shaded_col *= mix(0.86, 1.08, sky_facing);

	ALBEDO = shaded_col;
	NORMAL_MAP = detail_nrm;
	NORMAL_MAP_DEPTH = normal_strength;
	ROUGHNESS = clamp(base_roughness - edge_curv * 0.08, 0.18, 0.96);
	METALLIC = base_metallic;
	SPECULAR = mix(0.28, 0.65, base_metallic);
}
