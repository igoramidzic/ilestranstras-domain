// Checkered ball, so you can see it roll.
shader_type spatial;

uniform vec3 color_a : source_color = vec3(0.95, 0.36, 0.52);
uniform vec3 color_b : source_color = vec3(1.0, 0.82, 0.36);
uniform float segments = 8.0;

void fragment() {
	float u = step(0.5, fract(UV.x * segments));
	float v = step(0.5, fract(UV.y * segments * 0.5));
	ALBEDO = mix(color_a, color_b, abs(u - v));
	ROUGHNESS = 0.55;
}
