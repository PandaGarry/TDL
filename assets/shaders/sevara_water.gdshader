shader_type canvas_item;

uniform float silt_load : hint_range(0.0, 1.0) = 0.25;
uniform float flow_speed : hint_range(0.0, 4.0) = 1.0;
uniform float kevar_sheen : hint_range(0.0, 1.0) = 0.0;
uniform vec4 clear_water_tint : source_color = vec4(0.18, 0.34, 0.39, 0.72);
uniform vec4 silt_water_tint : source_color = vec4(0.42, 0.29, 0.19, 0.88);

void fragment() {
	vec2 flow_uv = UV + vec2(TIME * 0.04 * flow_speed, sin(UV.x * 12.0 + TIME * 1.6) * 0.008);
	vec4 pebble_sample = texture(TEXTURE, fract(flow_uv));
	float ripple = sin(UV.x * 28.0 + TIME * 2.4 * flow_speed) * cos(UV.y * 22.0 - TIME * 1.8);
	float caustic = smoothstep(0.35, 0.92, ripple) * (1.0 - silt_load * 0.75);
	vec3 base_rgb = mix(pebble_sample.rgb, clear_water_tint.rgb, clear_water_tint.a);
	base_rgb = mix(base_rgb, silt_water_tint.rgb, clamp(silt_load * 1.1, 0.0, 0.92));
	base_rgb += vec3(0.18, 0.22, 0.20) * caustic;

	if (kevar_sheen > 0.01) {
		float ring = sin(length(UV - vec2(0.5)) * 42.0 - TIME * 1.9);
		vec3 mineral = vec3(
			0.5 + 0.5 * sin(ring * 3.1 + 0.4),
			0.5 + 0.5 * sin(ring * 3.1 + 2.1),
			0.5 + 0.5 * sin(ring * 3.1 + 4.2)
		);
		base_rgb = mix(base_rgb, mineral * 0.55 + base_rgb * 0.65, kevar_sheen * 0.38);
	}

	COLOR = vec4(base_rgb, 0.94);
}
