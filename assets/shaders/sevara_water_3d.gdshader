shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_back, diffuse_burley, specular_schlick_ggx;

// Next-gen 2026 stylized mountain river shader (EffectBlocks / Godot-Water-Shader-Prototype inspired):
// - Combines exact vertex bathymetry (COLOR.rgb) with real-time scene depth_texture intersection
//   around submerged rocks, bridge piers, and beaver dam logs
// - Beer-Lambert optical absorption from crystal amber-emerald shallows to deep sapphire-teal channel
// - Dual-scrolling Gerstner capillary waves + animated shore & rapid foam + sunlit Voronoi caustics

uniform sampler2D depth_texture : hint_depth_texture, filter_linear_mipmap;
uniform vec4 shallow_color : source_color = vec4(0.18, 0.56, 0.48, 0.68);
uniform vec4 mid_color : source_color = vec4(0.06, 0.35, 0.43, 0.86);
uniform vec4 deep_color : source_color = vec4(0.02, 0.16, 0.27, 0.95);
uniform vec4 sky_reflection_tint : source_color = vec4(0.70, 0.85, 0.96, 1.0);
uniform vec4 foam_color : source_color = vec4(0.95, 0.98, 1.0, 1.0);
uniform float flow_speed = 0.58;
uniform float wave_height = 0.032;

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
	return pow(clamp(1.0 - sqrt(md), 0.0, 1.0), 2.4);
}

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_bathymetry = COLOR.rgb; // R = shore_prox, G = water_depth, B = rapids_fac
	float depth_atten = clamp(COLOR.g * 1.6, 0.1, 1.0);
	float t = TIME * flow_speed;
	float w1 = sin(v_world_pos.x * 1.45 - t * 3.8 + v_world_pos.z * 0.85);
	float w2 = cos(v_world_pos.x * 2.90 - t * 5.2 - v_world_pos.z * 1.75) * 0.5;
	VERTEX.y += (w1 + w2) * wave_height * depth_atten;
}

void fragment() {
	float t = TIME * flow_speed;
	float vertex_depth = clamp(v_bathymetry.g, 0.0, 1.0);
	float rapids_weight = clamp(v_bathymetry.b, 0.0, 1.0);

	// Sample scene depth buffer to detect submerged 3D rocks, bridge pilings, and shallow banks
	float raw_depth = texture(depth_texture, SCREEN_UV).r;
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, raw_depth);
	vec4 view_pos = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	view_pos.xyz /= max(view_pos.w, 0.00001);
	float scene_linear_depth = -view_pos.z;
	float surface_linear_depth = -VERTEX.z;
	float geo_depth_diff = max(0.0, scene_linear_depth - surface_linear_depth);

	float water_depth = vertex_depth;
	if (raw_depth < 0.9995) {
		water_depth = min(vertex_depth, clamp(geo_depth_diff * 0.95, 0.0, 1.2));
	}

	// Dual counter-scrolling capillary wave normals (flowing NW -> SE along +Z/+X)
	vec2 flow_uv1 = v_world_pos.xz * vec2(0.48, 0.68) + vec2(-t * 0.55, -t * 1.45);
	vec2 flow_uv2 = v_world_pos.xz * vec2(0.96, 1.28) + vec2(t * 0.35, -t * 2.25);
	vec2 flow_uv3 = v_world_pos.xz * vec2(2.15, 2.55) + vec2(-t * 0.65, -t * 3.15);

	float h1 = fbm(flow_uv1) * 0.55 + fbm(flow_uv2) * 0.30 + noise(flow_uv3) * 0.15;
	float hx = fbm(flow_uv1 + vec2(0.07, 0.0)) * 0.55 + fbm(flow_uv2 + vec2(0.07, 0.0)) * 0.30 + noise(flow_uv3 + vec2(0.07, 0.0)) * 0.15;
	float hz = fbm(flow_uv1 + vec2(0.0, 0.07)) * 0.55 + fbm(flow_uv2 + vec2(0.0, 0.07)) * 0.30 + noise(flow_uv3 + vec2(0.0, 0.07)) * 0.15;

	vec3 wave_nrm = normalize(vec3((h1 - hx) * 4.6, 1.0, (h1 - hz) * 4.6));
	NORMAL = normalize(mix(NORMAL, (VIEW_MATRIX * vec4(wave_nrm, 0.0)).xyz, 0.74));

	// Beer-Lambert depth color absorption
	vec3 water_col = mix(shallow_color.rgb, mid_color.rgb, smoothstep(0.06, 0.44, water_depth));
	water_col = mix(water_col, deep_color.rgb, smoothstep(0.38, 0.92, water_depth));

	// Sunlit Voronoi caustics dancing on shallow pebbles
	float caustics = voronoi_caustics(v_world_pos.xz * 1.55 + vec2(-t * 0.45, -t * 1.25));
	float shallow_mask = (1.0 - smoothstep(0.15, 0.78, water_depth)) * smoothstep(0.02, 0.14, water_depth);
	water_col += vec3(0.38, 0.56, 0.46) * caustics * shallow_mask * 0.70;

	// Fresnel sky reflection
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.2);
	water_col = mix(water_col, sky_reflection_tint.rgb, fresnel * 0.54);

	// 1) Animated shoreline & submerged-object intersection foam rings
	float foam_noise = fbm(v_world_pos.xz * 2.1 + vec2(-t * 0.65, -t * 1.85));
	float edge_foam_band = 1.0 - smoothstep(0.015, 0.24 + foam_noise * 0.14, water_depth);
	float ripple_ring = sin(water_depth * 28.0 - TIME * 4.0 + foam_noise * 4.2) * 0.5 + 0.5;
	float intersection_foam = smoothstep(0.34, 0.66, edge_foam_band * (0.65 + 0.35 * ripple_ring));

	// 2) Current rapid streaks in the midstream & gorge rapids
	float rapid_noise = fbm(vec2(v_world_pos.x * 2.1 + sin(v_world_pos.z * 0.4) * 1.1, v_world_pos.z * 0.55 - t * 2.65));
	float rapid_foam = smoothstep(0.62 - rapids_weight * 0.12, 0.80, rapid_noise) * smoothstep(0.12, 0.45, water_depth) * (0.45 + rapids_weight * 0.40);

	// 3) Sparkling sun glints on wave crests
	float sun_glint = smoothstep(0.75, 0.89, h1) * 0.48;

	float total_foam = clamp(intersection_foam + rapid_foam + sun_glint, 0.0, 1.0);
	ALBEDO = mix(water_col, foam_color.rgb, total_foam);
	ROUGHNESS = mix(0.05, 0.40, total_foam);
	METALLIC = 0.04;
	SPECULAR = 0.94;

	// Smooth feathering at the outer dry edge of the river bank
	float shore_feather = smoothstep(0.0, 0.045, vertex_depth);
	ALPHA = clamp(mix(shallow_color.a, deep_color.a, smoothstep(0.08, 0.68, water_depth)) + total_foam * 0.28, 0.0, 0.97) * shore_feather;
}
