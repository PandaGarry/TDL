shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

// 3D Dense Meadow Grass Carpet Shader for MultiMeshInstance3D in Sevara Valley.
// Combines curved 3D blade patches with terrain-normal alignment (Bukkbeek NatureBlocks look),
// rolling wind gusts, player trample push-aside, root-to-tip color gradient,
// and wildflower heads on select blades.

uniform vec3 root_color : source_color = vec3(0.12, 0.26, 0.09);
uniform vec3 tip_color : source_color = vec3(0.38, 0.62, 0.20);
uniform vec3 tip_color_warm : source_color = vec3(0.64, 0.68, 0.24);
uniform float blade_height : hint_range(0.15, 1.5) = 0.52;
uniform vec2 wind_direction = vec2(0.92, 0.38);
uniform float wind_strength : hint_range(0.0, 3.0) = 1.0;
uniform vec3 player_pos = vec3(0.0, -100.0, 0.0);

varying float v_t;
varying vec3 v_tip;
varying float v_gust;
varying float v_flower;
varying vec3 v_flower_col;

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

float wind_gust(vec2 world_xz, float time) {
	vec2 uv = world_xz * 0.09 - normalize(wind_direction) * time * 0.48;
	return smoothstep(0.22, 0.84, value_noise(uv));
}

void vertex() {
	float t = clamp(UV.y, 0.0, 1.0);
	vec4 rnd = COLOR;
	vec3 inst_origin = MODEL_MATRIX[3].xyz;
	vec3 world_v = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;

	float clump = value_noise(world_v.xz * 0.22);
	float h_scale = (0.65 + rnd.g * 0.65) * (0.75 + clump * 0.5) * max(INSTANCE_CUSTOM.a, 0.55);
	float gust = wind_gust(world_v.xz, TIME);
	float wave = sin(TIME * 1.8 - dot(world_v.xz, wind_direction) * 0.45 + rnd.a * 6.28) * 0.5 + 0.5;
	float flutter = sin(TIME * 5.6 + rnd.r * 14.0) * 0.05;
	float bend = (gust * 0.72 + wave * 0.28 + 0.08) * wind_strength;

	// Player pushes grass blades gently aside when walking through the meadow
	vec3 to_blade = world_v - player_pos;
	float pd = length(to_blade.xz);
	float push = (1.0 - smoothstep(0.35, 1.45, pd)) * step(abs(to_blade.y), 2.2);
	vec2 push_xz = normalize(to_blade.xz + vec2(0.0001)) * push * 0.65;

	float curve = t * t;
	vec2 wdir = normalize(wind_direction);
	vec2 rest_bend = vec2(cos(rnd.b * 6.283), sin(rnd.b * 6.283)) * 0.16;
	vec2 total_xz = (wdir * bend * 0.42 + vec2(flutter, flutter * 0.7) + rest_bend + push_xz) * curve * blade_height * h_scale;

	VERTEX.y *= blade_height * h_scale * (1.0 - push * 0.45);
	VERTEX.x += total_xz.x;
	VERTEX.z += total_xz.y;

	// Blend blade normal with sky/terrain up vector for velvety NatureBlocks shading
	NORMAL = normalize(mix(NORMAL, vec3(0.0, 1.0, 0.0), 0.72));

	float region = value_noise(world_v.xz * 0.08 + vec2(4.2, 1.9));
	vec3 base_tip = mix(tip_color, tip_color_warm, smoothstep(0.42, 0.76, region + (rnd.r - 0.5) * 0.25));
	if (length(INSTANCE_CUSTOM.rgb) > 0.05) {
		base_tip = mix(base_tip, INSTANCE_CUSTOM.rgb, 0.55);
	}
	v_tip = base_tip * (0.86 + rnd.r * 0.28);
	v_t = t;
	v_gust = gust;

	v_flower = step(0.955, fract(rnd.r * 7.31 + rnd.a * 3.17));
	float fc = fract(rnd.a * 5.13);
	v_flower_col = fc < 0.42
		? vec3(0.98, 0.96, 0.88)
		: (fc < 0.72 ? vec3(0.96, 0.82, 0.24) : (fc < 0.88 ? vec3(0.88, 0.54, 0.72) : vec3(0.48, 0.68, 0.95)));
}

void fragment() {
	float t = v_t;
	vec3 root = mix(root_color, v_tip * 0.52, 0.24);
	vec3 col = mix(root, v_tip, smoothstep(0.0, 0.88, t));
	col = mix(col, col * 1.28 + vec3(0.04, 0.05, 0.0), v_gust * t * t * 0.55);
	col *= mix(0.58, 1.0, smoothstep(0.0, 0.35, t));
	col = mix(col, v_flower_col, v_flower * smoothstep(0.80, 0.92, t));

	ALBEDO = col;
	ROUGHNESS = 0.92;
	SPECULAR = 0.15;
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float diff = smoothstep(-0.22, 0.88, ndl) * 0.82 + 0.18;
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * diff / PI;
	float back = pow(clamp(dot(VIEW, -LIGHT), 0.0, 1.0), 3.5);
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * back * v_t * 0.38 / PI;
	DIFFUSE_LIGHT += vec3(0.05, 0.08, 0.14) * (1.0 - clamp(ndl * ATTENUATION, 0.0, 1.0)) * 0.28;
}
