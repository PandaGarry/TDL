shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

// 3D Foliage & Plant Shader for Sevara Valley (compatible with GL Compatibility & Forward+).
// Inspired by Bukkbeek NatureBlocks, Fern (foliage_body.gdshaderinc), and ProtonScatter (leaves.gdshader).
// Modes:
//   0 = Tree crown / bush (spherical crown normals, gradient + leaf texture, wind sway & flutter)
//   1 = Grass tuft / reed clump (ground-aligned normals, INSTANCE_CUSTOM tip tint, wind waves)
//   2 = Textured plant / flower / fern (alpha-scissored botanical texture, INSTANCE_CUSTOM blossom tint)
//   3 = Vertex-colored procedural plant (reeds, cattails, Kevar/Kevalu blossoms)

uniform int mode = 0;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform float alpha_cut : hint_range(0.0, 0.95) = 0.42;
uniform vec3 color_dark : source_color = vec3(0.14, 0.34, 0.11);
uniform vec3 color_light : source_color = vec3(0.46, 0.68, 0.24);
uniform vec3 texture_tint : source_color = vec3(1.0, 1.0, 1.0);
uniform float texture_color_mix : hint_range(0.0, 1.0) = 0.38;
uniform float saturation : hint_range(0.2, 1.8) = 1.05;

uniform vec3 crown_center = vec3(0.0, 3.8, 0.0);
uniform vec3 crown_extent = vec3(2.2, 2.2, 2.2);
uniform float sphere_normals : hint_range(0.0, 1.0) = 0.72;
uniform float object_height : hint_range(0.2, 18.0) = 5.5;
uniform float ground_normal : hint_range(0.0, 1.0) = 0.0;

uniform vec2 wind_direction = vec2(0.92, 0.38);
uniform float wind_strength : hint_range(0.0, 3.0) = 1.0;
uniform float stiffness : hint_range(0.5, 12.0) = 3.8;
uniform float flutter : hint_range(0.0, 0.3) = 0.055;
uniform float translucency : hint_range(0.0, 1.0) = 0.55;
uniform float wrap : hint_range(0.0, 1.0) = 0.52;
uniform float snow_cover : hint_range(0.0, 1.0) = 0.08;
uniform bool instance_tint = false;

varying float v_grad;
varying float v_gust;
varying float v_var;
varying vec3 v_world;
varying vec4 v_custom;
varying vec3 v_vcol;

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
	vec2 uv = world_xz * 0.08 - normalize(wind_direction) * time * 0.42;
	float n = value_noise(uv);
	return smoothstep(0.25, 0.85, n);
}

vec3 adjust_saturation(vec3 c, float s) {
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	return mix(vec3(l), c, s);
}

vec3 world_to_model_dir(mat4 model, vec3 v) {
	float s2 = max(dot(model[0].xyz, model[0].xyz), 0.0001);
	return (transpose(mat3(model)) * v) / s2;
}

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float weight = 0.0;
	if (mode == 1) {
		weight = clamp(VERTEX.y / max(object_height, 0.25), 0.0, 1.2);
		weight = weight * weight;
		v_grad = clamp(VERTEX.y / max(object_height, 0.25), 0.0, 1.0);
	} else if (mode == 0) {
		float h = clamp(VERTEX.y / max(object_height, 0.5), 0.0, 1.4);
		weight = h * h;
		vec3 rel = (VERTEX - crown_center) / max(crown_extent, vec3(0.25));
		float outer = clamp(length(rel), 0.0, 1.2);
		v_grad = clamp(0.35 * (rel.y * 0.5 + 0.5) + 0.72 * smoothstep(0.15, 1.05, outer), 0.0, 1.0);
		vec3 sphere_n = normalize(VERTEX - crown_center + vec3(0.0, crown_extent.y * 0.35, 0.0));
		NORMAL = normalize(mix(NORMAL, sphere_n, sphere_normals));
	} else {
		weight = clamp(VERTEX.y / max(object_height, 0.25), 0.0, 1.0);
		v_grad = weight;
	}

	if (ground_normal > 0.0) {
		NORMAL = normalize(mix(NORMAL, vec3(0.0, 1.0, 0.0), ground_normal));
	}

	float gust = wind_gust(origin.xz, TIME);
	vec2 dir = normalize(wind_direction);
	float phase = dot(origin.xz, vec2(0.37, 0.61)) + INSTANCE_CUSTOM.a * 6.283;
	float sway = sin(TIME * 1.25 + phase) * 0.35 + sin(TIME * 0.62 + phase * 1.7) * 0.25;
	float bend = (gust * 1.15 + sway * 0.55 + 0.20) * wind_strength / max(stiffness, 0.4);
	vec3 offset = vec3(dir.x, 0.0, dir.y) * bend * weight;
	float fl = sin(TIME * 5.2 + dot(world, vec3(2.3, 1.7, 2.9))) * cos(TIME * 3.1 + world.y * 2.8);
	offset += vec3(fl * 0.55, fl * 0.30, -fl * 0.45) * flutter * weight * (0.4 + gust) * wind_strength;

	VERTEX += world_to_model_dir(MODEL_MATRIX, offset);
	v_gust = gust;
	v_var = value_noise(world.xz * 0.065);
	v_custom = INSTANCE_CUSTOM;
	v_vcol = COLOR.rgb;
	v_world = world;
}

void fragment() {
	vec4 tex = texture(albedo_tex, UV);
	if (mode != 3 && alpha_cut > 0.001 && tex.a < alpha_cut) {
		discard;
	}

	vec3 col;
	if (mode == 3) {
		col = v_vcol * (0.84 + 0.28 * v_grad);
	} else if (mode == 1) {
		vec3 tip = length(v_custom.rgb) > 0.02 ? v_custom.rgb : color_light;
		vec3 root = mix(color_dark, tip * 0.55, 0.35);
		col = mix(root, tip, smoothstep(0.0, 0.92, v_grad));
		col = mix(col, col * tex.rgb * 1.25, texture_color_mix);
		col = mix(col, col * 1.26 + vec3(0.03, 0.04, 0.0), v_gust * v_grad * v_grad * 0.55);
	} else {
		vec3 grad = mix(color_dark * (mode == 0 ? 0.80 : 1.0), color_light, smoothstep(0.0, 1.0, v_grad));
		col = mix(grad, tex.rgb * texture_tint, texture_color_mix);
		if (instance_tint && length(v_custom.rgb) > 0.02) {
			float lum = dot(tex.rgb, vec3(0.3, 0.59, 0.11));
			vec3 tinted = v_custom.rgb * (0.58 + lum * 0.88);
			float centre = smoothstep(0.10, 0.35, tex.r - tex.b);
			col = mix(tinted, col, centre * 0.6);
		}
		if (abs(v_custom.a) > 0.001) {
			col *= 0.90 + 0.20 * fract(v_custom.a * 17.31);
		}
	}

	col *= 0.90 + 0.20 * v_var;

	if (snow_cover > 0.005 && mode == 0) {
		float wup = (INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).y;
		float frost = smoothstep(0.30, 0.78, wup) * clamp(snow_cover * 1.25, 0.0, 1.0) * smoothstep(0.45, 0.95, v_grad);
		col = mix(col, vec3(0.91, 0.95, 0.99), frost * 0.72);
	}

	ALBEDO = adjust_saturation(col, saturation);
	ROUGHNESS = 0.88;
	SPECULAR = 0.15;
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float diff = clamp((ndl + wrap) / (1.0 + wrap), 0.0, 1.0);
	diff = smoothstep(0.0, 1.0, diff);
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * diff / PI;

	float back = pow(clamp(dot(VIEW, -LIGHT), 0.0, 1.0), 3.0);
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * back * min(translucency, 0.85) * 0.45 / PI;

	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0) * smoothstep(-0.2, 0.6, ndl);
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * rim * 0.28 / PI;
	DIFFUSE_LIGHT += vec3(0.05, 0.08, 0.14) * (1.0 - clamp(diff * ATTENUATION, 0.0, 1.0)) * 0.26;
}
