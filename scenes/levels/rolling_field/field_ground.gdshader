// Lawn. The grass texture (from tools/blender/build_item_models.py) is sampled
// twice, at different scales and angles, and tinted by big soft patches of
// lush and dry grass, so the repetition doesn't show from up close or from
// far away.
shader_type spatial;

uniform sampler2D grass_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_roughness : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
// Meters per repeat of the fine layer.
uniform float tile_size = 2.5;
uniform vec3 lush_tint : source_color = vec3(0.9, 1.0, 0.85);
uniform vec3 dry_tint : source_color = vec3(1.15, 1.0, 0.62);
uniform float normal_strength = 1.0;

varying vec3 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void fragment() {
	vec2 p = world_position.xz;
	vec2 uv_fine = p / tile_size;
	mat2 turn = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));
	vec2 uv_coarse = turn * p / (tile_size * 4.37);

	vec3 fine = texture(grass_albedo, uv_fine).rgb;
	vec3 coarse = texture(grass_albedo, uv_coarse).rgb;
	vec3 albedo = mix(fine, coarse, 0.4);

	float patches = value_noise(p * 0.035) * 0.65 + value_noise(p * 0.11) * 0.35;
	albedo *= mix(lush_tint, dry_tint, smoothstep(0.45, 0.85, patches));
	albedo *= 0.85 + 0.3 * value_noise(p * 0.6);

	ALBEDO = albedo;
	NORMAL_MAP = normalize(mix(texture(grass_normal, uv_fine).rgb, texture(grass_normal, uv_coarse).rgb, 0.4));
	NORMAL_MAP_DEPTH = normal_strength;
	ROUGHNESS = mix(texture(grass_roughness, uv_fine).r, 1.0, 0.2);
	SPECULAR = 0.3;
}
