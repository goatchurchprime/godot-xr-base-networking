shader_type spatial;
render_mode cull_disabled, shadows_disabled;

uniform float altitude_origin = 0.0;
uniform float colour_repeat_metres = 250.0;
uniform vec3 gray_colour : source_color = vec3(0.035, 0.050, 0.065);
uniform float horizontal_extinction_per_m : hint_range(0.0, 0.01, 0.00001) = 0.00008;
uniform float vertical_extinction_per_m : hint_range(0.0, 0.1, 0.001) = 0.03;
uniform float maximum_layer_haze : hint_range(0.0, 1.0) = 0.60;
uniform sampler2D depthshading : source_color, repeat_enable;

varying float altitude;
varying vec3 world_position;

float layered_haze(vec3 path) {
	float optical_depth = abs(path.y) * vertical_extinction_per_m + length(path.xz) * horizontal_extinction_per_m;
	return clamp(0.2 * (optical_depth - 1.0), 0.0, maximum_layer_haze);
}

void vertex() {
	altitude = VERTEX.y;
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float cycle = altitude / max(colour_repeat_metres, 1.0);
	vec3 colour = texture(depthshading, vec2(cycle, 0.5)).rgb;
	colour = mix(colour, gray_colour, layered_haze(world_position - CAMERA_POSITION_WORLD));
	ALBEDO = colour;
	ROUGHNESS = 1.0;
}

void light() {
	// Horizontal edges have an upward normal and therefore respond most strongly
	// to an overhead light. Back-facing lines remain visible at half strength.
	float d = dot(NORMAL, LIGHT);
	float edge_light = d > 0.0 ? d : -0.5 * d;
	DIFFUSE_LIGHT += ALBEDO * edge_light * LIGHT_COLOR / PI;
}
