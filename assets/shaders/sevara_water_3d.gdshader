shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_disabled, diffuse_burley, specular_schlick_ggx;

// 3D Spatial Water Shader for the Nivarel channel, rapids, and Mulane wetland pools.
// Features directional river current, dual normal ripples, expanding water rings,
// shallow-to-deep turquoise color transition, rock/shore foam, Fresnel sky reflection,
// and dynamic ochre silt turbidity.
// Vertex COLOR channels:
//   R = shore / rock proximity (0 = center of channel, 1 = bank/weir/boulder edge)
//   G = water depth factor (0 = shallow pebbles, 1 = deep pool)
//   B = rapids / weir turbulence factor

uniform vec4 shallow_color : source_color = vec4(0.22, 0.54, 0.52, 0.72);
uniform vec4 deep_color : source_color = vec4(0.07, 0.25, 0.34, 0.90);
uniform vec4 silt_color : source_color = vec4(0.46, 0.35, 0.22, 0.92);
uniform vec4 foam_color : source_color = vec4(0.92, 0.96, 0.98, 0.96);
uniform float silt_load : hint_range(0.0, 1.0) = 0.18;
uniform float flow_speed : hint_range(0.0, 4.0) = 1.15;
uniform float wave_height : hint_range(0.0, 0.25) = 0.032;
uniform vec2 flow_dir = vec2(0.58, 0.81);

varying vec3 v_world_pos;
varying float v_shore;
varying float v_depth;
varying float v_rapids;

float hash1(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float noise2d(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash1(i + vec2(0.0, 0.0)), hash1(i + vec2(1.0, 0.0)), u.x),
		mix(hash1(i + vec2(0.0, 1.0)), hash1(i + vec2(1.0, 1.0)), u.x),
		u.y
	);
}

vec2 ring_wave(vec2 p, vec2 c, float age, float life, float speed) {
	vec2 d = p - c;
	float dist = length(d);
	if (age < 0.0 || age > life) {
		return vec2(0.0);
	}
	float r = 0.10 + age * speed;
	float fade = 1.0 - age / life;
	float w = 0.08 + age * 0.05;
	float a = (dist - r) / w;
	float b = (dist - r * 0.62) / w;
	float ea = exp(-a * a);
	float eb = exp(-b * b);
	return vec2(ea + 0.5 * eb, -2.0 * a * ea - b * eb) * fade;
}

void vertex() {
	v_shore = COLOR.r;
	v_depth = COLOR.g;
	v_rapids = COLOR.b;
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float t = TIME * flow_speed;
	float w1 = sin(world.x * 2.4 + world.z * 1.9 + t * 2.3);
	float w2 = cos(world.x * 3.7 - world.z * 2.8 - t * 1.8);
	VERTEX.y += (w1 * 0.6 + w2 * 0.4) * wave_height * (1.0 - v_shore * 0.55);
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = v_world_pos.xz;
	vec2 fdir = normalize(flow_dir);
	vec2 fperp = vec2(-fdir.y, fdir.x);
	vec2 flow_uv = vec2(dot(p, fdir) * 0.55, dot(p, fperp) * 1.05);
	float t = TIME * flow_speed;

	float n1 = noise2d(flow_uv * 1.8 - vec2(t * 0.95, t * 0.22));
	float n2 = noise2d(flow_uv * 3.6 + vec2(-t * 1.35, t * 0.65));
	float n3 = noise2d(p * 6.2 + vec2(t * 0.45, -t * 0.55));
	float combined = n1 * 0.50 + n2 * 0.35 + n3 * 0.15;

	// Subtle expanding rings on calmer water (rising trout / water striders)
	float rings = 0.0;
	vec2 cell = floor(p / 4.5);
	float hc = hash1(cell);
	float period = 5.5 + hc * 6.0;
	float rt = TIME + hc * 29.0;
	float cyc = floor(rt / period);
	if (hash1(cell + cyc * 1.37) < 0.55) {
		vec2 rc = (cell + 0.25 + 0.5 * vec2(hash1(cell + cyc), hash1(cell - cyc * 0.7))) * 4.5;
		vec2 rv = ring_wave(p, rc, rt - cyc * period, 2.4, 0.52);
		rings += rv.x * (1.0 - v_rapids * 0.7);
	}

	// Water body color: shallow turquoise -> deep blue-teal -> ochre silt plumes
	vec3 water_rgb = mix(shallow_color.rgb, deep_color.rgb, smoothstep(0.08, 0.88, v_depth));
	float silt_plume = smoothstep(0.28, 0.82, combined + silt_load * 0.45) * clamp(silt_load * 1.25, 0.0, 1.0);
	water_rgb = mix(water_rgb, silt_color.rgb, silt_plume * 0.74);

	// White water foam at shorelines, weir logs, millrace, and boulder rapids
	float shore_foam = smoothstep(0.58, 0.94, v_shore + (combined - 0.5) * 0.32);
	float rapid_foam = smoothstep(0.54, 0.84, combined + v_rapids * 0.45) * (0.35 + v_rapids * 0.65);
	float crest_foam = smoothstep(0.74, 0.90, combined) * (1.0 - silt_load * 0.4);
	float foam_mask = clamp(max(max(shore_foam, rapid_foam), crest_foam + rings * 0.45), 0.0, 1.0);

	// Fresnel sky reflection
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.2);
	vec3 sky_refl = vec3(0.68, 0.80, 0.90) * (1.0 - silt_load * 0.35);
	vec3 final_rgb = mix(water_rgb, sky_refl, fresnel * 0.42);
	final_rgb = mix(final_rgb, foam_color.rgb, foam_mask * 0.88);

	// Perturbed normal for sparkling sun highlights
	vec3 wave_n = normalize(vec3((n1 - n2) * 0.42, 0.92, (n2 - n3) * 0.42));
	NORMAL = normalize(mix(NORMAL, wave_n, 0.55));

	ALBEDO = final_rgb;
	ROUGHNESS = mix(0.06, 0.32, silt_load * 0.6 + foam_mask * 0.4);
	METALLIC = 0.08;
	SPECULAR = 0.92;
	ALPHA = clamp(mix(shallow_color.a, deep_color.a, v_depth) + foam_mask * 0.22 + silt_load * 0.14, 0.68, 0.97);
}
