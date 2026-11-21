// DEMO: grid floor so you can see the camera and player moving.
shader_type spatial;

uniform vec3 base_color : source_color = vec3(0.17, 0.19, 0.23);
uniform vec3 line_color : source_color = vec3(0.3, 0.34, 0.42);
uniform float cell_size = 2.0;
uniform float line_width = 0.04;

varying vec3 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 cell = abs(fract(world_position.xz / cell_size - 0.5) - 0.5) * cell_size;
	float dist = min(cell.x, cell.y);
	float aa = fwidth(dist);
	float line = 1.0 - smoothstep(line_width - aa, line_width + aa, dist);
	ALBEDO = mix(base_color, line_color, line);
	ROUGHNESS = 0.9;
}
