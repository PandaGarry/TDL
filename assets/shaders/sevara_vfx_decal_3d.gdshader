shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;

// 0 = Soft Contact Shadow Decal (50% AO under barrels, crates, carts, houses)
// 1 = Glowing Ember & Ash Coal Bed (under hearth bonfire & blacksmith forge)
// 2 = Billowing Volumetric Smoke Puff (hearth & chimney smoke particles)
// 3 = Churning White Waterwheel Foam & Spray (mill wheel water splash particles)
// 4 = Atmospheric Sunbeam / God Ray Shaft (diagonal sunlight rays through trees)
uniform int vfx_mode = 0;
uniform vec4 tint_color : source_color = vec4(0.02, 0.03, 0.02, 0.52);
uniform float intensity = 1.0;

varying vec3 v_local;
varying vec3 v_world;
varying vec3 v_normal_view;
varying vec4 v_color;

float hash21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash21(i), hash21(i + vec2(1.0, 0.0)), u.x),
		mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), u.x),
		u.y
	);
}

float fbm2(vec2 p) {
	float v = 0.55 * vnoise(p);
	v += 0.30 * vnoise(p * 2.15 + vec2(3.7, -1.9));
	v += 0.15 * vnoise(p * 4.40 - vec2(1.4, 2.8));
	return v;
}

void vertex() {
	v_local = VERTEX;
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_normal_view = normalize((MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_color = COLOR;
}

void fragment() {
	vec2 uv_c = UV * 2.0 - 1.0;
	float r = length(uv_c);

	if (vfx_mode == 0) {
		// Mode 0: Soft Ground Contact Shadow Decal (50% opacity, smooth radial falloff)
		float falloff = smoothstep(1.0, 0.12, r);
		ALBEDO = tint_color.rgb;
		ALPHA = clamp(tint_color.a * falloff * falloff * intensity, 0.0, 0.72);
	} else if (vfx_mode == 1) {
		// Mode 1: Glowing Coal & Ash Bed under Bonfire / Forge
		float n1 = fbm2(uv_c * 3.8 + vec2(TIME * 0.18, -TIME * 0.12));
		float n2 = fbm2(uv_c * 7.6 - vec2(TIME * 0.25, 1.7));
		float radial_edge = smoothstep(1.0, 0.48, r + (n1 - 0.5) * 0.22);
		float core_heat = smoothstep(0.78, 0.08, r) * smoothstep(0.28, 0.78, n1 * 0.55 + n2 * 0.45);
		float pulse = 0.86 + 0.14 * sin(TIME * 3.4 + n1 * 6.28);

		vec3 charred_ash = vec3(0.05, 0.04, 0.04);
		vec3 warm_cinder = vec3(0.55, 0.14, 0.03);
		vec3 bright_ember = vec3(1.00, 0.48, 0.08) * pulse;
		vec3 col = mix(charred_ash, warm_cinder, smoothstep(0.18, 0.58, core_heat));
		col = mix(col, bright_ember, smoothstep(0.52, 0.88, core_heat));

		ALBEDO = col;
		ALPHA = clamp(radial_edge * 0.94, 0.0, 1.0);
	} else if (vfx_mode == 2) {
		// Mode 2: Billowing Soft Smoke Plume (3D sphere puff or billboard quad)
		float ndotv = abs(dot(normalize(v_normal_view), normalize(VIEW)));
		float sphere_soft = pow(clamp(ndotv, 0.0, 1.0), 1.05);
		float wisp = fbm2(v_world.xz * 2.2 + vec2(v_world.y * 1.6 - TIME * 0.45, TIME * 0.25));
		float alpha_smoke = sphere_soft * smoothstep(0.16, 0.74, wisp) * tint_color.a * v_color.a * intensity;
		vec3 smoke_col = mix(tint_color.rgb * 0.68, tint_color.rgb * 1.08, wisp);
		ALBEDO = smoke_col;
		ALPHA = clamp(alpha_smoke, 0.0, 0.74);
	} else if (vfx_mode == 3) {
		// Mode 3: River Pier Foam Rings & Churning Whitewater Wake (radially feathered)
		float radial_fade = 1.0 - smoothstep(0.28, 0.92, r + (fbm2(v_world.xz * 4.2) - 0.5) * 0.22);
		float foam_n = fbm2(v_world.xz * 5.6 + vec2(TIME * 2.2, -TIME * 1.8));
		float ripple_ring = 0.55 + 0.45 * sin(r * 18.0 - TIME * 4.2 + foam_n * 3.0);
		float spray_mask = radial_fade * smoothstep(0.18, 0.78, foam_n * ripple_ring);
		ALBEDO = mix(vec3(0.72, 0.88, 0.95), vec3(0.96, 0.99, 1.0), foam_n);
		ALPHA = clamp(spray_mask * tint_color.a * v_color.a * intensity, 0.0, 0.76);
	} else {
		// Mode 4: Volumetric Sunbeam / God Ray Shaft through trees
		float beam_u = abs(uv_c.x);
		float beam_v = UV.y;
		float edge_fade = smoothstep(1.0, 0.05, beam_u);
		float v_fade = smoothstep(0.0, 0.28, beam_v) * (1.0 - smoothstep(0.62, 1.0, beam_v));
		float ray_striation = 0.72 + 0.28 * vnoise(vec2(uv_c.x * 6.5 + v_world.z * 0.4, TIME * 0.08));
		float view_fresnel = pow(clamp(abs(dot(normalize(v_normal_view), normalize(VIEW))), 0.0, 1.0), 1.25);
		ALBEDO = tint_color.rgb;
		ALPHA = clamp(edge_fade * v_fade * ray_striation * view_fresnel * tint_color.a * intensity, 0.0, 0.24);
	}
}
