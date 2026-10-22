shader_type sky;

// Next-gen 2026 procedural mountain valley sky shader (inspired by cloudy-sky-3d & No Rest for the Wicked):
// - Deep cerulean zenith transitioning to warm golden-peach morning horizon haze
// - Multi-layered FBM cumulus & cirrus clouds with silver-gold sun-rim scattering
// - Crisp solar disc with warm Mie atmospheric corona

uniform vec3 sky_top_color : source_color = vec3(0.22, 0.44, 0.68);
uniform vec3 sky_horizon_color : source_color = vec3(0.84, 0.86, 0.82);
uniform vec3 ground_bottom_color : source_color = vec3(0.24, 0.30, 0.28);
uniform vec3 cloud_bright_color : source_color = vec3(0.99, 0.96, 0.90);
uniform vec3 cloud_shadow_color : source_color = vec3(0.56, 0.64, 0.74);
uniform float cloud_coverage = 0.48;
uniform float cloud_speed = 0.012;

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
	for (int i = 0; i < 5; i++) {
		v += a * noise(p);
		p = rot * p * 2.03;
		a *= 0.5;
	}
	return v;
}

void sky() {
	vec3 dir = normalize(EYEDIR);
	float y = dir.y;

	// Base atmospheric gradient
	float zenith_t = pow(clamp(y, 0.0, 1.0), 0.58);
	vec3 col = mix(sky_horizon_color, sky_top_color, zenith_t);

	// Sun Mie scattering & warm morning glow
	vec3 sun_dir = normalize(LIGHT0_DIRECTION);
	float sun_dot = max(dot(dir, sun_dir), 0.0);
	float mie_glow = pow(sun_dot, 6.0) * 0.38 + pow(sun_dot, 32.0) * 0.45;
	float sun_disc = smoothstep(0.9982, 0.9996, sun_dot) * 2.2;
	vec3 sun_col = vec3(1.0, 0.88, 0.66);
	col += sun_col * (mie_glow + sun_disc);

	// Layered procedural clouds above the horizon
	if (y > 0.01) {
		vec2 cloud_uv = dir.xz / (y + 0.16);
		float t = TIME * cloud_speed;
		float n_base = fbm(cloud_uv * 1.15 + vec2(t, t * 0.45));
		float n_detail = fbm(cloud_uv * 2.85 - vec2(t * 0.6, -t * 0.8));
		float cloud_density = smoothstep(1.0 - cloud_coverage, 1.0 - cloud_coverage + 0.34, n_base * 0.72 + n_detail * 0.28);

		// Cloud internal self-shadowing + golden sun-lining
		float light_sample = fbm((cloud_uv + sun_dir.xz * 0.08) * 1.15 + vec2(t, t * 0.45));
		float cloud_lit = smoothstep(0.32, 0.72, n_base - light_sample * 0.35 + 0.38);
		vec3 c_col = mix(cloud_shadow_color, cloud_bright_color, cloud_lit);
		c_col += sun_col * pow(sun_dot, 4.0) * (1.0 - cloud_density * 0.5) * 0.45;

		float horizon_fade = smoothstep(0.01, 0.18, y);
		col = mix(col, c_col, cloud_density * horizon_fade * 0.88);
	} else {
		float ground_t = pow(clamp(-y, 0.0, 1.0), 0.55);
		col = mix(sky_horizon_color, ground_bottom_color, ground_t);
	}

	COLOR = col;
}
