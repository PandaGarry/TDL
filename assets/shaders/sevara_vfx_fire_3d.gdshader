shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;

// EffectBlocks-style 3D animated fire & ember tongue shader
uniform vec4 core_color : source_color = vec4(1.0, 0.94, 0.68, 1.0);
uniform vec4 mid_color : source_color = vec4(1.0, 0.48, 0.08, 1.0);
uniform vec4 tip_color : source_color = vec4(0.75, 0.12, 0.02, 1.0);
uniform float flame_speed = 3.4;
uniform float intensity = 2.4;

varying float v_seed;

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
		p *= 2.05;
		a *= 0.5;
	}
	return v;
}

void vertex() {
	vec3 world_origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	v_seed = hash(world_origin.xz);
	float h = clamp(1.0 - UV.y, 0.0, 1.0);
	float sway = sin(TIME * flame_speed * 1.6 + h * 4.5 + v_seed * 6.28) * 0.08 * h;
	VERTEX.x += sway;
	VERTEX.z += cos(TIME * flame_speed * 1.3 + h * 3.8 + v_seed * 6.28) * 0.08 * h;
}

void fragment() {
	vec2 uv = UV;
	float h = clamp(1.0 - uv.y, 0.0, 1.0);
	float x_dist = abs(uv.x - 0.5) * 2.0;

	vec2 n_uv = vec2(uv.x * 2.6 + v_seed * 3.1, uv.y * 2.4 + TIME * flame_speed);
	float n = fbm(n_uv) * 0.7 + fbm(n_uv * 2.1 - vec2(0.0, TIME * flame_speed * 0.6)) * 0.3;

	// Tapered flame silhouette with licking tongues
	float width = mix(0.75, 0.08, pow(h, 1.15));
	float shape = 1.0 - smoothstep(width * 0.35, width + 0.18, x_dist + (n - 0.48) * 0.55 * (0.25 + h));
	shape *= smoothstep(0.0, 0.14, h) * (1.0 - smoothstep(0.78, 1.0, h));

	float core_mask = smoothstep(0.45, 0.85, shape * (1.0 - h * 0.55));
	vec3 col = mix(tip_color.rgb, mid_color.rgb, smoothstep(0.12, 0.55, shape));
	col = mix(col, core_color.rgb, core_mask);

	ALBEDO = col * intensity;
	ALPHA = clamp(shape * 0.95, 0.0, 1.0);
}
