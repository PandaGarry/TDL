shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

// 3D Tree Bark Shader with normal map, vertex AO, mossy root base, and synchronized trunk wind sway.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform vec3 tint : source_color = vec3(0.95, 0.90, 0.84);
uniform vec3 moss_color : source_color = vec3(0.24, 0.38, 0.16);
uniform float moss_height : hint_range(0.0, 2.5) = 0.85;
uniform float normal_strength : hint_range(0.0, 2.0) = 1.15;
uniform float object_height : hint_range(0.5, 20.0) = 6.0;
uniform float stiffness : hint_range(0.5, 12.0) = 4.0;
uniform float ao_strength : hint_range(0.0, 1.0) = 0.72;
uniform vec2 wind_direction = vec2(0.92, 0.38);
uniform float wind_strength : hint_range(0.0, 3.0) = 1.0;

varying float v_ao;
varying float v_local_y;

vec3 world_to_model_dir(mat4 model, vec3 v) {
	float s2 = max(dot(model[0].xyz, model[0].xyz), 0.0001);
	return (transpose(mat3(model)) * v) / s2;
}

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	float h = clamp(VERTEX.y / max(object_height, 0.5), 0.0, 1.4);
	float weight = h * h;
	vec2 dir = normalize(wind_direction);
	float phase = dot(origin.xz, vec2(0.37, 0.61)) + INSTANCE_CUSTOM.a * 6.283;
	float sway = sin(TIME * 1.25 + phase) * 0.35 + sin(TIME * 0.62 + phase * 1.7) * 0.25;
	float bend = (sway * 0.55 + 0.35) * wind_strength / max(stiffness, 0.4);
	vec3 off = vec3(dir.x, 0.0, dir.y) * bend * weight;
	VERTEX += world_to_model_dir(MODEL_MATRIX, off);
	v_ao = COLOR.r;
	v_local_y = VERTEX.y;
}

void fragment() {
	vec3 c = texture(albedo_tex, UV).rgb * tint;
	float root_moss = 1.0 - smoothstep(0.0, max(moss_height, 0.05), v_local_y);
	c = mix(c, moss_color, clamp(root_moss * 0.55, 0.0, 0.65));
	float ao = mix(1.0, smoothstep(0.0, 1.0, v_ao), ao_strength);
	ALBEDO = c * mix(0.42, 1.0, ao);
	NORMAL_MAP = texture(normal_tex, UV).rgb;
	NORMAL_MAP_DEPTH = normal_strength;
	ROUGHNESS = 0.88;
	SPECULAR = 0.18;
}
