shader_type spatial;
render_mode depth_draw_opaque, cull_disabled;

#include "res://addons/zylann.hterrain/shaders/include/heightmap.gdshaderinc"

uniform sampler2D u_terrain_heightmap : filter_linear;
uniform mat4 u_terrain_inverse_transform;
uniform vec3 valley_color : source_color = vec3(0.16, 0.20, 0.15);
const vec3 ridge_color = vec3(0.44, 0.43, 0.35);
const vec3 rock_color = vec3(0.24, 0.25, 0.23);
const vec3 under_color = vec3(0.124, 0.25, 0.33);
uniform float slope_colour_strength : hint_range(0.0, 1.0) = 0.72;
uniform float elevation_base_metres = -650.0;
uniform float elevation_range_metres : hint_range(1.0, 3000.0) = 1500.0;
uniform float hillshade_exponent : hint_range(0.25, 8.0) = 1.0;
uniform float direct_light_strength : hint_range(0.0, 4.0) = 1.0;
uniform float terrain_roughness : hint_range(0.0, 1.0) = 0.96;
uniform float terrain_specular : hint_range(0.0, 1.0) = 0.05;

varying float terrain_height;


void vertex() {
	vec2 cell_coords = (u_terrain_inverse_transform * MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
	cell_coords += vec2(0.5);
	UV = cell_coords / vec2(textureSize(u_terrain_heightmap, 0));
	terrain_height = sample_heightmap(u_terrain_heightmap, UV);
	VERTEX.y = terrain_height;
}


void fragment() {
	// Derivatives give every rasterised triangle one stable normal without a
	// second 4097² normal texture. This also makes the 1 m relief readable with
	// the world's single directional light.
	NORMAL = normalize(cross(dFdy(VERTEX), dFdx(VERTEX)));
	vec3 world_up_view = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	float upness = dot(NORMAL, world_up_view);
	float elevation = (terrain_height - elevation_base_metres) / elevation_range_metres;
	elevation = clamp(elevation, 0.0, 1.0);
	vec3 elevcolor = mix(valley_color, ridge_color, elevation);
	ALBEDO = mix((upness > 0.0 ? rock_color : under_color), elevcolor, abs(upness) * slope_colour_strength);
	ROUGHNESS = terrain_roughness;
	SPECULAR = terrain_specular;
}


void light() {
	float incidence = dot(NORMAL, LIGHT);
	if (incidence < 0.0)  incidence = -0.4*incidence;
	float hillshade = pow(incidence, hillshade_exponent) * direct_light_strength;
	DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * hillshade * ATTENUATION;
}
