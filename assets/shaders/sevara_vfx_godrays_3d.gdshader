shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;

// EffectBlocks-style Volumetric Sunbeams / God Rays shader
uniform vec4 ray_color : source_color = vec4(1.0, 0.90, 0.64, 0.13);
uniform float shimmer_speed = 0.45;

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

void fragment() {
	float v_fade = smoothstep(0.0, 0.25, UV.y) * (1.0 - smoothstep(0.55, 1.0, UV.y));
	float h_fade = sin(clamp(UV.x, 0.0, 1.0) * 3.14159265);
	float streak = noise(vec2(UV.x * 6.5 + TIME * shimmer_speed, UV.y * 1.2)) * 0.6
		+ noise(vec2(UV.x * 13.0 - TIME * shimmer_speed * 0.7, UV.y * 2.0)) * 0.4;
	float view_fade = pow(abs(dot(NORMAL, VIEW)), 1.35);
	float alpha = v_fade * h_fade * smoothstep(0.28, 0.82, streak) * view_fade * ray_color.a;
	ALBEDO = ray_color.rgb;
	ALPHA = clamp(alpha, 0.0, 0.35);
}
