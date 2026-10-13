shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec4 wall_colour : source_color = vec4(0.52, 0.55, 0.58, 0.82);
uniform vec4 window_colour : source_color = vec4(0.10, 0.16, 0.20, 0.82);
uniform vec3 outline_colour : source_color = vec3(0.055, 0.065, 0.075);
uniform float storey_height = 3.2;
uniform float window_width = 4.5;

varying vec3 world_position;
varying vec3 world_normal;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

void fragment() {
	vec3 normal = normalize(world_normal);
	float vertical_face = smoothstep(0.25, 0.75, 1.0 - abs(normal.y));

	// Project a small window grid along the dominant horizontal face axis.
	float horizontal_position = abs(normal.x) > abs(normal.z) ? world_position.z : world_position.x;
	vec2 grid_position = vec2(horizontal_position / window_width, world_position.y / storey_height);
	vec2 cell = fract(grid_position);
	// Screen-space derivatives provide analytic filtering for this procedural
	// pattern—the equivalent of choosing a coarser texture mip at a distance.
	vec2 filter_width = max(fwidth(grid_position) * 1.35, vec2(0.0025));
	float pattern_visibility = 1.0 - smoothstep(0.10, 0.28, max(filter_width.x, filter_width.y));
	float inside_x = smoothstep(0.16 - filter_width.x, 0.16 + filter_width.x, cell.x)
		* (1.0 - smoothstep(0.84 - filter_width.x, 0.84 + filter_width.x, cell.x));
	float inside_y = smoothstep(0.22 - filter_width.y, 0.22 + filter_width.y, cell.y)
		* (1.0 - smoothstep(0.78 - filter_width.y, 0.78 + filter_width.y, cell.y));
	float window_mask = inside_x * inside_y * vertical_face * pattern_visibility;
	vec2 edge_distance = min(cell, 1.0 - cell);
	float mullion_line = (1.0 - smoothstep(0.035 - filter_width.x, 0.035 + filter_width.x, edge_distance.x));
	float storey_line = (1.0 - smoothstep(0.045 - filter_width.y, 0.045 + filter_width.y, edge_distance.y));
	float facade_line = clamp(mullion_line + storey_line, 0.0, 1.0) * vertical_face * pattern_visibility;

	// Large-scale neutral variation stops adjacent city blocks merging into one
	// white mass while keeping this independent of downloaded façade textures.
	float block_tone = 0.5 + 0.5 * sin(world_position.x * 0.018) * sin(world_position.z * 0.021);
	vec3 wall = wall_colour.rgb * mix(0.86, 1.08, block_tone);
	vec3 facade = mix(wall, window_colour.rgb, window_mask * 0.72);
	facade = mix(facade, outline_colour, facade_line * 0.72);
	// Fresnel-style edge darkening gives each mass a legible silhouette in both
	// eyes without a costly screen-space outline pass.
	float silhouette = pow(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), 3.0);
	ALBEDO = mix(facade, outline_colour, silhouette * 0.82);
	ROUGHNESS = mix(0.88, 0.38, window_mask);
	METALLIC = mix(0.0, 0.08, window_mask);
	ALPHA = mix(mix(wall_colour.a, window_colour.a, window_mask), 0.96, max(facade_line, silhouette));
}
