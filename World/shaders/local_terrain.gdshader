shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// These are deliberately mid-value albedos rather than baked illumination.
// Godot's sun supplies the directional relief and the environment supplies a
// modest sky fill, so north-facing slopes stay legible without looking flat.
uniform vec3 valley_colour : source_color = vec3(0.30, 0.46, 0.20);
uniform vec3 alpine_colour : source_color = vec3(0.57, 0.58, 0.46);
uniform vec3 rock_colour : source_color = vec3(0.48, 0.46, 0.41);

varying vec3 world_position;
varying vec3 world_normal;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

void fragment() {
	vec3 normal = normalize(world_normal);
	float elevation = smoothstep(-500.0, 650.0, world_position.y);
	float steepness = smoothstep(0.25, 0.82, 1.0 - abs(normal.y));
	vec3 vegetation = mix(valley_colour, alpine_colour, elevation);
	ALBEDO = mix(vegetation, rock_colour, steepness * 0.72);
	ROUGHNESS = 0.94;
	METALLIC = 0.0;
}
