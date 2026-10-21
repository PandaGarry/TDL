shader_type canvas_item;

uniform float wind_strength : hint_range(0.0, 16.0) = 4.0;
uniform float wind_speed : hint_range(0.0, 6.0) = 1.6;

void vertex() {
	float canopy_weight = clamp(1.0 - UV.y, 0.0, 1.0);
	float sway = sin(TIME * wind_speed + VERTEX.x * 0.05 + VERTEX.y * 0.03) * wind_strength;
	VERTEX.x += sway * canopy_weight * canopy_weight;
}
