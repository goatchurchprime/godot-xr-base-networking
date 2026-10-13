shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;

uniform float point_size : hint_range(1.0, 16.0, 0.25) = 2.0;
uniform bool adaptive_point_size = true;
uniform float point_size_factor = 200.0;
uniform float maximum_point_size = 64.0;
uniform float node_spacing = 1.0;
uniform vec3 node_center = vec3(0.0);
uniform int visible_child_mask = 0;
uniform bool circular_points = false;
uniform bool near_fragmentation = true;
uniform float near_fragment_distance = 0.8;
uniform bool distance_shading = true;
uniform vec3 distance_close_color : source_color = vec3(1.0, 0.0, 0.0);
uniform vec3 distance_far_color : source_color = vec3(0.0, 0.0, 1.0);
uniform float distance_color_mix : hint_range(0.0, 1.0, 0.01) = 0.5;
uniform float distance_far = 30.0;
uniform float distance_taper = 20.0;

varying flat float handoff_hidden;
varying flat float near_fragment_fraction;
varying flat vec3 shaded_color;

void vertex() {
	vec3 world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float camera_distance = max(length(CAMERA_POSITION_WORLD - world_position), 0.001);
	float model_scale = length(MODEL_MATRIX[0].xyz);
	float adaptive_size = point_size_factor * node_spacing * model_scale / camera_distance;
	POINT_SIZE = adaptive_point_size ? clamp(adaptive_size, point_size, maximum_point_size) : point_size;
	near_fragment_fraction = near_fragmentation
		? clamp(1.0 - camera_distance / max(near_fragment_distance * model_scale, 0.001), 0.0, 1.0)
		: 0.0;
	// TunnelVR's depth cue: retain the scan RGB while progressively tinting
	// nearby points toward close_color and distant points toward far_color.
	// The reciprocal curve changes rapidly nearby and gently in the distance.
	float shading_far = max(distance_far * model_scale, 0.001);
	float shading_taper = max(distance_taper * model_scale, 0.001);
	float distance_mix = clamp(
		camera_distance * (shading_taper + shading_far)
			/ (shading_far * (camera_distance + shading_taper)),
		0.0,
		1.0
	);
	vec3 depth_color = mix(distance_close_color, distance_far_color, distance_mix);
	shaded_color = distance_shading
		? mix(depth_color, COLOR.rgb, clamp(distance_color_mix, 0.0, 1.0))
		: COLOR.rgb;

	// A visible child owns its octant. Its mesh contains both its new samples
	// and copies of the parent samples from that octant, all at one point size.
	int child_bit = (VERTEX.x >= node_center.x ? 16 : 1)
		* (VERTEX.y >= node_center.y ? 4 : 1)
		* (VERTEX.z >= node_center.z ? 2 : 1);
	handoff_hidden = ((visible_child_mask / child_bit) % 2) != 0 ? 1.0 : 0.0;
	if (handoff_hidden > 0.5) {
		POINT_SIZE = 0.0;
	}
}

void fragment() {
	if (handoff_hidden > 0.5) {
		discard;
	}
	if (circular_points) {
		vec2 point_delta = POINT_COORD - vec2(0.5);
		if (dot(point_delta, point_delta) > 0.25) {
			discard;
		}
	}
	// TunnelVR's close-range treatment: progressively cut a cross through a
	// large splat so it breaks into fragments rather than filling the camera.
	vec2 centred_coord = abs(POINT_COORD * 2.0 - vec2(1.0));
	if (centred_coord.x < near_fragment_fraction || centred_coord.y < near_fragment_fraction) {
		discard;
	}
	ALBEDO = shaded_color;
	ALPHA = COLOR.a;
}
