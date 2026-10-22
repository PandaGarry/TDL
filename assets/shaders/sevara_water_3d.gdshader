shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, diffuse_burley, specular_schlick_ggx;

// Next-gen 2026 stylized mountain river shader (EffectBlocks / Godot-Water-Shader-Prototype inspired):
// - 100% cross-backend (gl_compatibility OpenGL3 + Metal iOS) bathymetry & obstacle foam
// - Wave-refracted riverbed pebbles in crystal amber-emerald shallows
// - Beer-Lambert optical absorption into deep sapphire-teal midstream channel
// - Dual-scrolling Gerstner capillary waves + animated shoreline/weir/bridge-pier foam + sunlit Voronoi caustics

uniform sampler2D riverbed_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 shallow_color : source_color = vec4(0.14, 0.46, 0.42, 0.72);
uniform vec4 mid_color : source_color = vec4(0.05, 0.28, 0.36, 0.88);
uniform vec4 deep_color : source_color = vec4(0.02, 0.13, 0.22, 0.96);
uniform vec4 sky_reflection_tint : source_color = vec4(0.56, 0.74, 0.88, 1.0);
uniform vec4 foam_color : source_color = vec4(0.88, 0.94, 0.98, 1.0);
uniform float flow_speed = 0.56;
uniform float wave_height = 0.030;
uniform float silt_load = 0.16;

varying vec3 v_world_pos;
varying vec3 v_bathymetry;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash(i + vec2(0.0, 0.0)), hash(i + vec2(1.0, 0.0)), u.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x),
		u.y
	);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	mat2 rot = mat2(vec2(0.80, 0.60), vec2(-0.60, 0.80));
	for (int i = 0; i < 4; i++) {
		v += a * noise(p);
		p = rot * p * 2.05;
		a *= 0.5;
	}
	return v;
}

float voronoi_caustics(vec2 p) {
	vec2 n = floor(p);
	vec2 f = fract(p);
	float md = 8.0;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 g = vec2(float(i), float(j));
			vec2 o = vec2(hash(n + g), hash(n + g + vec2(17.3, 41.7)));
			o = 0.5 + 0.42 * sin(TIME * 1.8 + 6.2831 * o);
			vec2 r = g + o - f;
			float d = dot(r, r);
			md = min(md, d);
		}
	}
	return pow(clamp(1.0 - sqrt(md), 0.0, 1.0), 2.6);
}

float river_center_x(float wz) {
	return 1.8 + wz * 0.28 + sin(wz * 0.085 + 0.35) * 4.2 + cos(wz * 0.042) * 2.1;
}

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_bathymetry = COLOR.rgb; // R = shore_prox, G = water_depth, B = rapids_fac
	float depth_atten = clamp(COLOR.g * 1.5, 0.08, 1.0);
	float t = TIME * flow_speed;
	float w1 = sin(v_world_pos.x * 1.45 - t * 3.8 + v_world_pos.z * 0.85);
	float w2 = cos(v_world_pos.x * 2.90 - t * 5.2 - v_world_pos.z * 1.75) * 0.5;
	VERTEX.y += (w1 + w2) * wave_height * depth_atten;
}

void fragment() {
	float t = TIME * flow_speed;
	float water_depth = clamp(v_bathymetry.g, 0.0, 1.0);
	float rapids_weight = clamp(v_bathymetry.b, 0.0, 1.0);

	// Dual counter-scrolling capillary wave normals
	vec2 flow_uv1 = v_world_pos.xz * vec2(0.48, 0.68) + vec2(-t * 0.55, -t * 1.45);
	vec2 flow_uv2 = v_world_pos.xz * vec2(0.96, 1.28) + vec2(t * 0.35, -t * 2.25);
	vec2 flow_uv3 = v_world_pos.xz * vec2(2.15, 2.55) + vec2(-t * 0.65, -t * 3.15);

	float h1 = fbm(flow_uv1) * 0.55 + fbm(flow_uv2) * 0.30 + noise(flow_uv3) * 0.15;
	float hx = fbm(flow_uv1 + vec2(0.07, 0.0)) * 0.55 + fbm(flow_uv2 + vec2(0.07, 0.0)) * 0.30 + noise(flow_uv3 + vec2(0.07, 0.0)) * 0.15;
	float hz = fbm(flow_uv1 + vec2(0.0, 0.07)) * 0.55 + fbm(flow_uv2 + vec2(0.0, 0.07)) * 0.30 + noise(flow_uv3 + vec2(0.0, 0.07)) * 0.15;

	vec2 wave_grad = vec2(h1 - hx, h1 - hz);
	vec3 wave_nrm = normalize(vec3(wave_grad.x * 4.6, 1.0, wave_grad.y * 4.6));
	NORMAL = normalize(mix(NORMAL, (VIEW_MATRIX * vec4(wave_nrm, 0.0)).xyz, 0.75));

	// Wave-refracted riverbed pebbles visible in crystal-clear shallows
	vec2 pebble_uv = v_world_pos.xz * 0.34 + wave_grad * 0.38;
	vec3 bed_pebbles = texture(riverbed_tex, pebble_uv).rgb * vec3(0.72, 0.78, 0.74);

	// Sunlit Voronoi caustics dancing on the shallow pebbles
	float caustics = voronoi_caustics(v_world_pos.xz * 1.45 + wave_grad * 1.2 + vec2(-t * 0.45, -t * 1.25));
	bed_pebbles += vec3(0.32, 0.48, 0.40) * caustics * (1.0 - smoothstep(0.15, 0.72, water_depth));

	// Beer-Lambert optical absorption from refracted pebbles -> emerald shallows -> deep sapphire channel
	vec3 water_tint = mix(shallow_color.rgb, mid_color.rgb, smoothstep(0.12, 0.52, water_depth));
	water_tint = mix(water_tint, deep_color.rgb, smoothstep(0.45, 0.92, water_depth));
	// Ecological silt response (when Toramek slope erodes)
	vec3 silt_tint = vec3(0.26, 0.24, 0.16);
	water_tint = mix(water_tint, silt_tint, clamp(silt_load - 0.18, 0.0, 0.55));

	float bed_visibility = exp(-water_depth * 3.4) * 0.62;
	vec3 water_col = mix(water_tint, bed_pebbles, bed_visibility);

	// Fresnel sky reflection
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.4);
	water_col = mix(water_col, sky_reflection_tint.rgb, fresnel * 0.46);

	// 1) Delicate lacy shoreline foam right at the shallow bank edge (water_depth < 0.16)
	float foam_noise = fbm(v_world_pos.xz * 2.4 + vec2(-t * 0.65, -t * 1.85));
	float shore_band = (1.0 - smoothstep(0.02, 0.15, water_depth)) * smoothstep(0.005, 0.035, water_depth);
	float shore_lace = smoothstep(0.42, 0.72, shore_band * (0.65 + 0.65 * foam_noise));

	// 2) Foam wakes around bridge pilings (z ~ -4.6) and wooden weirs (z ~ -10.2 and z ~ 5.8)
	float r_cx = river_center_x(v_world_pos.z);
	float d_weir1 = abs(v_world_pos.z - (-10.2));
	float d_weir2 = abs(v_world_pos.z - 5.8);
	float d_bridge = length(vec2((v_world_pos.x - r_cx) * 0.65, v_world_pos.z - (-4.6)));
	float obstacle_band = max(
		exp(-pow(d_weir1 / 0.55, 2.0)),
		max(exp(-pow(d_weir2 / 0.55, 2.0)), exp(-pow(d_bridge / 0.95, 2.0)) * 0.65)
	) * smoothstep(0.10, 0.35, water_depth);
	float obstacle_foam = smoothstep(0.36, 0.74, obstacle_band * (0.55 + 0.65 * foam_noise));

	// 3) Current rapid streaks in midstream rapids
	float rapid_noise = fbm(vec2(v_world_pos.x * 2.2 + sin(v_world_pos.z * 0.4) * 1.1, v_world_pos.z * 0.58 - t * 2.65));
	float rapid_foam = smoothstep(0.68 - rapids_weight * 0.08, 0.85, rapid_noise) * smoothstep(0.18, 0.55, water_depth) * (0.35 + rapids_weight * 0.35);

	// 4) Sunlit wave crest glints
	float sun_glint = smoothstep(0.78, 0.91, h1) * 0.35;

	float total_foam = clamp(shore_lace * 0.78 + obstacle_foam * 0.85 + rapid_foam + sun_glint, 0.0, 0.92);
	ALBEDO = mix(water_col, foam_color.rgb, total_foam);
	ROUGHNESS = mix(0.06, 0.38, total_foam);
	METALLIC = 0.04;
	SPECULAR = 0.92;

	float shore_feather = smoothstep(0.0, 0.045, water_depth);
	ALPHA = clamp(mix(shallow_color.a, deep_color.a, smoothstep(0.08, 0.65, water_depth)) + total_foam * 0.22, 0.0, 0.96) * shore_feather;
}
