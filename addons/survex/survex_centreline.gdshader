shader_type spatial;
render_mode unshaded, cull_disabled;

uniform float altitude_origin = 0.0;
uniform float colour_repeat_metres = 250.0;
varying float altitude;
varying float slope_light;

float mid_lump(float value, float offset) {
	float phase = (fract(value + offset) - 0.5) / 0.5;
	return clamp(1.0 - phase * phase, 0.0, 1.0);
}

void vertex() {
	altitude = VERTEX.y + altitude_origin;
	slope_light = COLOR.r;
}

void fragment() {
	float cycle = altitude / max(colour_repeat_metres, 1.0);
	vec3 colour = vec3(mid_lump(cycle, 0.0), mid_lump(cycle, -0.667) * 0.98, mid_lump(cycle, -0.333));
	ALBEDO = mix(colour * 0.38, colour, slope_light);
}
