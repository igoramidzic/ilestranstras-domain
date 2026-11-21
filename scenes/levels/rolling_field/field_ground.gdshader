// Grassy ground with a fine 1 m grid and a coarse 10 m grid. Each grid fades
// out when its lines get too thin on screen, so it stays readable (and free of
// shimmer) from right next to the ball all the way to fully zoomed out.
shader_type spatial;

uniform vec3 base_color : source_color = vec3(0.36, 0.55, 0.3);
uniform vec3 line_color : source_color = vec3(0.46, 0.66, 0.38);
uniform float line_width = 0.03;

varying vec3 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float grid(vec2 p, float cell) {
	vec2 uv = p / cell;
	vec2 width = fwidth(uv);
	vec2 dist = abs(fract(uv - 0.5) - 0.5);
	vec2 lines = 1.0 - smoothstep(vec2(line_width) - width, vec2(line_width) + width, dist);
	float fade = 1.0 - smoothstep(0.08, 0.25, max(width.x, width.y));
	return max(lines.x, lines.y) * fade;
}

void fragment() {
	float line = max(grid(world_position.xz, 1.0) * 0.5, grid(world_position.xz, 10.0));
	ALBEDO = mix(base_color, line_color, line);
	ROUGHNESS = 0.95;
}
