shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_opaque;

uniform vec3 minor_colour : source_color = vec3(0.2299102, 0.14379409, 0.10977969);
uniform vec3 major_colour : source_color = vec3(0.4822793, 0.32571894, 0.26177442);
uniform vec3 axis_colour : source_color = vec3(0.91997194, 0.3929385, 0.91725844);
uniform float minor_spacing = 10.0;
uniform float major_spacing = 100.0;
uniform float grid_alpha : hint_range(0.0, 1.0) = 0.72;

varying vec3 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float grid_line(vec2 position, float spacing, float width) {
	position.y = position.y * 0.25 + ceil(position.x / spacing) * 0.5 * spacing;
	vec2 cell = abs(fract(position / spacing + 0.5) - 0.5) / max(fwidth(position / spacing), vec2(0.001));
	return 1.0 - clamp(min(cell.x, cell.y) / width * 0.2, 0.0, 1.0);
}

void fragment() {
	float major = grid_line(world_position.xz, major_spacing, 1.0);
	float axis = 1.0 - smoothstep(0.0, 0.35, min(abs(world_position.x), abs(world_position.z)));
	vec3 colour = mix(minor_colour, major_colour, major);
	ALBEDO = colour;
}
