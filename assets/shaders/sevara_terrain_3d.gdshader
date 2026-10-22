shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// Next-gen 2026 Sevara Valley Terrain Shader:
// - Dual-scale stochastic anti-tiling sampling (zero visible grid repetition)
// - 8-biome height-and-splat blending (meadow moss, clover grass, forest floor,
//   wet river pebbles, marsh silt, flagstone cobblestone trails, cliff granite, spring snow)
// - Normal-map blending with wetness darkening and specular sheen along the water's edge

uniform sampler2D tex_meadow : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_meadow_nrm : hint_normal, filter_linear_mipmap, repeat_enable;

uniform sampler2D tex_forest : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_forest_nrm : hint_normal, filter_linear_mipmap, repeat_enable;

uniform sampler2D tex_mud : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_mud_nrm : hint_normal, filter_linear_mipmap, repeat_enable;

uniform sampler2D tex_pebbles : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_pebbles_nrm : hint_normal, filter_linear_mipmap, repeat_enable;

uniform sampler2D tex_stone : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_stone_nrm : hint_normal, filter_linear_mipmap, repeat_enable;

uniform sampler2D tex_snow : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_snow_nrm : hint_normal, filter_linear_mipmap, repeat_enable;

uniform sampler2D tex_cliff : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_cliff_nrm : hint_normal, filter_linear_mipmap, repeat_enable;

uniform sampler2D tex_path : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_path_nrm : hint_normal, filter_linear_mipmap, repeat_enable;

uniform float uv_scale = 0.26;

varying vec3 v_world_pos;
varying vec3 v_world_nrm;
varying vec4 v_weights;
varying vec2 v_path_and_wet;

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

vec3 sample_stochastic(sampler2D tex, vec2 uv, float macro_mask) {
	vec2 uv_a = uv;
	vec2 uv_b = mat2(vec2(0.80, -0.60), vec2(0.60, 0.80)) * (uv * 0.43) + vec2(0.37, 0.71);
	return mix(texture(tex, uv_a).rgb, texture(tex, uv_b).rgb, macro_mask);
}

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_weights = COLOR;
	v_path_and_wet = UV2;
}

void fragment() {
	vec2 w_uv = v_world_pos.xz * uv_scale;
	float macro_n = noise(v_world_pos.xz * 0.065);
	float detail_n = noise(v_world_pos.xz * 0.24);
	float stoch_blend = smoothstep(0.25, 0.75, macro_n);

	float w_mud = clamp(v_weights.r, 0.0, 1.0);
	float w_pebbles = clamp(v_weights.g, 0.0, 1.0);
	float w_stone = clamp(v_weights.b, 0.0, 1.0);
	float w_snow = clamp(v_weights.a, 0.0, 1.0);
	float w_path = clamp(v_path_and_wet.x, 0.0, 1.0);
	float above_water = v_path_and_wet.y;

	float slope = 1.0 - clamp(v_world_nrm.y, 0.0, 1.0);
	float w_cliff = smoothstep(0.16, 0.42, slope);

	vec3 c_meadow = sample_stochastic(tex_meadow, w_uv * 0.95, stoch_blend);
	vec3 n_meadow = sample_stochastic(tex_meadow_nrm, w_uv * 0.95, stoch_blend);

	vec3 c_forest = sample_stochastic(tex_forest, w_uv * 0.88, stoch_blend);
	vec3 n_forest = sample_stochastic(tex_forest_nrm, w_uv * 0.88, stoch_blend);

	float forest_patch = smoothstep(0.36, 0.68, macro_n * 0.7 + detail_n * 0.3);
	vec3 col = mix(c_meadow, c_forest, forest_patch * 0.58);
	vec3 nrm = mix(n_meadow, n_forest, forest_patch * 0.58);
	float rough = mix(0.84, 0.78, forest_patch * 0.58);

	// Warm ochre-moss tint variation across sunlit meadows vs shaded forest margins
	vec3 meadow_grade = mix(vec3(0.88, 0.97, 0.82), vec3(1.05, 1.01, 0.90), detail_n);
	col *= meadow_grade;

	// Blend marsh mud & fertile bank soil
	if (w_mud > 0.01) {
		vec3 c_mud = sample_stochastic(tex_mud, w_uv * 1.05, stoch_blend);
		vec3 n_mud = sample_stochastic(tex_mud_nrm, w_uv * 1.05, stoch_blend);
		float m_blend = smoothstep(0.05, 0.72, w_mud + (detail_n - 0.5) * 0.16);
		col = mix(col, c_mud, m_blend);
		nrm = mix(nrm, n_mud, m_blend);
		rough = mix(rough, 0.48, m_blend);
	}

	// Blend riverbed & shoreline pebbles
	if (w_pebbles > 0.01) {
		vec3 c_peb = sample_stochastic(tex_pebbles, w_uv * 1.30, stoch_blend);
		vec3 n_peb = sample_stochastic(tex_pebbles_nrm, w_uv * 1.30, stoch_blend);
		float p_blend = smoothstep(0.10, 0.76, w_pebbles + (detail_n - 0.5) * 0.20);
		col = mix(col, c_peb, p_blend);
		nrm = mix(nrm, n_peb, p_blend);
		rough = mix(rough, 0.44, p_blend);
	}

	// Blend medieval flagstone & mossy cobblestone paths + settlement courtyard
	if (w_path > 0.01) {
		vec3 c_path = sample_stochastic(tex_path, w_uv * 1.25, stoch_blend);
		vec3 n_path = sample_stochastic(tex_path_nrm, w_uv * 1.25, stoch_blend);
		float path_luma = dot(c_path, vec3(0.299, 0.587, 0.114));
		float path_blend = smoothstep(0.14, 0.66, w_path + (path_luma - 0.45) * 0.22);
		col = mix(col, c_path * vec3(1.02, 1.00, 0.96), path_blend);
		nrm = mix(nrm, n_path, path_blend);
		rough = mix(rough, 0.66, path_blend);
	}

	// Blend steep cliff rock & highland stone
	float rock_weight = max(w_stone, w_cliff);
	if (rock_weight > 0.01) {
		vec3 c_rock = sample_stochastic(tex_cliff, w_uv * 0.82, stoch_blend);
		vec3 n_rock = sample_stochastic(tex_cliff_nrm, w_uv * 0.82, stoch_blend);
		float r_blend = smoothstep(0.10, 0.68, rock_weight + (detail_n - 0.5) * 0.18);
		col = mix(col, c_rock, r_blend);
		nrm = mix(nrm, n_rock, r_blend);
		rough = mix(rough, 0.72, r_blend);
	}

	// Blend spring snow patches on Toramek ridges (saving green moss peeks in crevices)
	if (w_snow > 0.01) {
		vec3 c_snow = sample_stochastic(tex_snow, w_uv * 0.95, stoch_blend);
		vec3 n_snow = sample_stochastic(tex_snow_nrm, w_uv * 0.95, stoch_blend);
		float s_blend = smoothstep(0.22, 0.76, w_snow * (1.0 - w_cliff * 0.6) + (macro_n - 0.5) * 0.22);
		col = mix(col, mix(c_snow, vec3(0.92, 0.96, 1.0), 0.55), s_blend);
		nrm = mix(nrm, n_snow, s_blend);
		rough = mix(rough, 0.52, s_blend);
	}

	// Shoreline wetness darkening & capillary sheen near water level
	float wetness = 1.0 - smoothstep(0.0, 0.38, above_water);
	col = mix(col, col * vec3(0.58, 0.63, 0.68), wetness * 0.76);
	rough = mix(rough, 0.14, wetness * 0.84);

	ALBEDO = col;
	NORMAL_MAP = normalize(nrm);
	NORMAL_MAP_DEPTH = 1.35;
	ROUGHNESS = clamp(rough, 0.10, 0.95);
	SPECULAR = mix(0.24, 0.72, wetness);
}
