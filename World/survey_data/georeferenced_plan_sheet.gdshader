shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_prepass_alpha;

uniform sampler2D plan_texture : source_color, filter_linear_mipmap_anisotropic, repeat_disable, hint_default_black;
const vec4 sheet_colour = vec4(0.12, 0.18, 0.25, 0.58);
uniform float drawing_opacity : hint_range(0.0, 1.0) = 1.0;
uniform vec4 border_colour : source_color = vec4(0.28, 0.52, 0.62, 0.9);
const float border_width = 0.05;

void fragment() {
	vec4 drawing = texture(plan_texture, UV);
	float ink_alpha = drawing.a * drawing_opacity;
	vec3 colour = mix(sheet_colour.rgb, drawing.rgb, ink_alpha);
	float alpha = sheet_colour.a + ink_alpha * (1.0 - sheet_colour.a);
	float edge_distance = min(min(UV.x, 1.0 - UV.x), min(UV.y, 1.0 - UV.y));
	float border = 1.0 - smoothstep(0.0, border_width, edge_distance);
	ALBEDO = mix(colour, border_colour.rgb, border * border_colour.a);
	ALPHA = max(alpha, border * border_colour.a);
}
