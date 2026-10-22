shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;

// EffectBlocks-style drifting morning river mist, chimney smoke & water ripples shader
// mode 0 = soft drifting river mist / smoke puff
// mode 1 = expanding concentric water ripple ring
uniform int vfx_mode = 0;
uniform vec4 tint_color : source_color = vec4(0.86, 0.92, 0.96, 0.24);
uniform float drift_speed = 0.28;

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
	for (int i = 0; i < 4; i++) {
		v += a * noise(p);
		p *= 2.02;
		a *= 0.5;
	}
	return v;
}

void fragment() {
	vec2 centered = UV * 2.0 - 1.0;
	float r = length(centered);

	if (vfx_mode == 1) {
		// Concentric animated water ripple rings around rocks/pilings
		float phase = fract(TIME * drift_speed + hash(floor(VERTEX.xz)));
		float ring1 = exp(-pow((r - phase * 0.88) * 14.0, 2.0)) * (1.0 - phase);
		float phase2 = fract(phase + 0.5);
		float ring2 = exp(-pow((r - phase2 * 0.88) * 14.0, 2.0)) * (1.0 - phase2);
		float radial_mask = 1.0 - smoothstep(0.75, 1.0, r);
		ALBEDO = tint_color.rgb;
		ALPHA = clamp((ring1 + ring2) * radial_mask * tint_color.a * 2.2, 0.0, 0.75);
	} else if (vfx_mode == 2) {
		// Soft ground contact shadow decal (ambient occlusion disc under trees, houses, rocks)
		float shadow_falloff = pow(clamp(1.0 - r, 0.0, 1.0), 1.85);
		ALBEDO = tint_color.rgb;
		ALPHA = clamp(shadow_falloff * tint_color.a, 0.0, 0.65);
	} else {
		// Soft drifting morning river mist & hearth smoke
		float radial_fade = pow(clamp(1.0 - r, 0.0, 1.0), 1.6);
		vec2 flow = UV * 2.4 + vec2(TIME * drift_speed, -TIME * drift_speed * 0.45);
		float wisp = fbm(flow) * 0.65 + fbm(flow * 1.9 - vec2(TIME * drift_speed * 0.5)) * 0.35;
		float alpha = radial_fade * smoothstep(0.26, 0.78, wisp) * tint_color.a;
		ALBEDO = tint_color.rgb;
		ALPHA = clamp(alpha, 0.0, 0.45);
	}
}
