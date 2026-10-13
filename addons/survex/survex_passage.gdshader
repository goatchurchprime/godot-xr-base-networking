shader_type spatial;
// The ordinary terrain view must obey the depth buffer, so underground
// passages are hidden by the ground. An explicit X-ray survey mode can use a
// separate material later; making every passage X-ray by default makes it
// impossible to judge the cave's relationship to the surface.
render_mode unshaded, cull_disabled, depth_draw_opaque;

uniform float altitude_origin = 0.0;
uniform float colour_repeat_metres = 250.0;
uniform bool selection_enabled = false;
uniform vec3 selection_position = vec3(0.0);
uniform float selection_radius = 3.0;

varying float altitude;
varying float selected;
varying vec3 world_position;

float mid_lump(float value, float offset) {
	float phase = (fract(value + offset) - 0.5) / 0.5;
	return clamp(1.0 - phase * phase, 0.0, 1.0);
}

void vertex() {
	altitude = VERTEX.y + altitude_origin;
	selected = selection_enabled && distance(VERTEX, selection_position) < selection_radius ? 1.0 : 0.0;
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 face_normal_world = normalize(cross(dFdx(world_position), dFdy(world_position)));
	if (!FRONT_FACING) {
		face_normal_world = -face_normal_world;
	}
	// Godot lighting expects the fragment normal in view space.
	NORMAL = normalize((VIEW_MATRIX * vec4(face_normal_world, 0.0)).xyz);
	float cycle = altitude / max(colour_repeat_metres, 1.0);
	vec3 groundwindow_colour = vec3(
		mid_lump(cycle, 0.0),
		mid_lump(cycle, -0.667) * 0.98,
		mid_lump(cycle, -0.333)
	);
	float face_shade = mix(0.52, 1.0, abs(dot(face_normal_world, normalize(vec3(0.2, 0.97, 0.1)))));
	vec3 colour = groundwindow_colour * face_shade;
	float camera_whiten = clamp(1.0 - distance(world_position, CAMERA_POSITION_WORLD) / 2.5, 0.0, 0.72);
	colour = mix(colour, vec3(1.0), camera_whiten);
	colour = mix(colour, vec3(0.0, 1.0, 1.0), selected * 0.78);
	ALBEDO = colour;
	ROUGHNESS = 0.82;
}
