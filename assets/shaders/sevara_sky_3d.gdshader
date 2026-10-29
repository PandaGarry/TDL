shader_type sky;

// Next-gen 2026 procedural mountain valley sky shader (inspired by cloudy-sky-3d & No Rest for the Wicked):
// - Deep cerulean zenith transitioning to warm golden-peach morning horizon haze
// - Multi-layered FBM cumulus & cirrus clouds with silver-gold sun-rim scattering
// - Crisp solar disc with warm Mie atmospheric corona

uniform vec3 sky_top_color : source_color = vec3(0.20, 0.48, 0.80);
uniform vec3 sky_horizon_color : source_color = vec3(0.84, 0.88, 0.90);
uniform vec3 ground_bottom_color : source_color = vec3(0.24, 0.30, 0.28);
uniform vec3 cloud_bright_color : source_color = vec3(1.0, 0.98, 0.94);
uniform vec3 cloud_shadow_color : source_color = vec3(0.62, 0.72, 0.84);
uniform float cloud_coverage = 0.42;
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

	// Base atmospheric gradient tuned for 3/4 valley camera angles (y = 0.0 .. 0.22)
	float zenith_t = smoothstep(0.0, 0.20, clamp(y, 0.0, 1.0));
	vec3 col = mix(sky_horizon_color, sky_top_color, zenith_t);

	// Sun Mie scattering & warm morning glow
	vec3 sun_dir = normalize(LIGHT0_DIRECTION);
	float sun_dot = max(dot(dir, sun_dir), 0.0);
	float mie_glow = pow(sun_dot, 5.0) * 0.34 + pow(sun_dot, 24.0) * 0.40;
	float sun_disc = smoothstep(0.9982, 0.9996, sun_dot) * 2.0;
	vec3 sun_col = vec3(1.0, 0.88, 0.66);
	col += sun_col * (mie_glow + sun_disc);

	// Layered procedural clouds visible right above the mountain ridges (y > 0.015)
	if (y > 0.01) {
		vec2 cloud_uv = dir.xz / (y + 0.26);
		float t = TIME * cloud_speed;
		float n_base = fbm(cloud_uv * 1.35 + vec2(t, t * 0.45));
		float n_detail = fbm(cloud_uv * 3.10 - vec2(t * 0.6, -t * 0.8));
		float cloud_density = smoothstep(1.0 - cloud_coverage, 1.0 - cloud_coverage + 0.32, n_base * 0.72 + n_detail * 0.28);

		// Cloud internal self-shadowing + golden sun-lining
		float light_sample = fbm((cloud_uv + sun_dir.xz * 0.08) * 1.35 + vec2(t, t * 0.45));
		float cloud_lit = smoothstep(0.30, 0.70, n_base - light_sample * 0.35 + 0.38);
		vec3 c_col = mix(cloud_shadow_color, cloud_bright_color, cloud_lit);
		c_col += sun_col * pow(sun_dot, 4.0) * (1.0 - cloud_density * 0.5) * 0.40;

		float horizon_fade = smoothstep(0.012, 0.075, y);
		col = mix(col, c_col, cloud_density * horizon_fade * 0.86);
	} else {
		float ground_t = pow(clamp(-y, 0.0, 1.0), 0.55);
		col = mix(sky_horizon_color, ground_bottom_color, ground_t);
	}

	COLOR = col;
}
