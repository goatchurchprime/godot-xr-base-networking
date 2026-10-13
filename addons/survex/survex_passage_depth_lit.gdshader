shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, diffuse_burley, specular_schlick_ggx, shadows_disabled;

uniform float altitude_origin = 0.0;
uniform float colour_repeat_metres = 250.0;
uniform bool selection_enabled = true;
uniform vec3 selection_position = vec3(0.0);
uniform float selection_radius = 5.0;
uniform vec3 selection_colour : source_color = vec3(0.0, 1.0, 1.0);
uniform float ambient_floor : hint_range(0.0, 1.0) = 0.18;
uniform vec3 gray_colour : source_color = vec3(0.035, 0.050, 0.065);
uniform float horizontal_extinction_per_m : hint_range(0.0, 0.01, 0.00001) = 0.00008;
uniform float vertical_extinction_per_m : hint_range(0.0, 0.1, 0.001) = 0.03;
const float maximum_layer_haze = 0.89;
uniform sampler2D depthshading : source_color, repeat_enable;

varying float altitude;
varying float selected;
varying vec3 world_position;

float layered_haze(vec3 path) {
	float optical_depth = abs(path.y) * vertical_extinction_per_m + length(path.xz) * horizontal_extinction_per_m;
	return clamp(1.22 * (optical_depth - 1.0), 0.0, maximum_layer_haze);
}

void vertex() {
	altitude = VERTEX.y + altitude_origin;
	selected = selection_enabled && distance(VERTEX, selection_position) < selection_radius ? 1.0 : 0.0;
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float cycle = altitude / max(colour_repeat_metres, 1.0);
	vec3 altitude_colour = texture(depthshading, vec2(cycle, 0.5)).rgb;
	vec3 colour = mix(altitude_colour * ambient_floor, altitude_colour, 0.72);
	colour = mix(colour, selection_colour, selected * 0.78);
	colour = mix(colour, gray_colour, layered_haze(world_position - CAMERA_POSITION_WORLD));
	ALBEDO = colour;
	ROUGHNESS = 0.88;
	METALLIC = 0.0;
}

void light() {
	// Preserve the deliberately boxy, two-sided facet response. Deliberately do
	// not multiply by ATTENUATION: it includes shadow-map visibility, and cave
	// passages should not darken one another merely because they overlap in plan.
	float d = dot(NORMAL, LIGHT);
	if (d > 0.0) {
		DIFFUSE_LIGHT += d * LIGHT_COLOR / PI;
	} else {
		DIFFUSE_LIGHT += -0.5 * d * LIGHT_COLOR / PI;
	}
}
