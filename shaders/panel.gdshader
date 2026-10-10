shader_type spatial;
// Prismatic fluorescent diffuser. INSTANCE_CUSTOM.r carries the live panel
// power, the same value that drives the panel's Godot light.
render_mode unshaded, cull_disabled;

uniform sampler2D diffuser_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec3 light_color : source_color = vec3(1.0, 0.96, 0.86);
uniform float intensity = 2.6;

varying float power;

void vertex() {
	power = INSTANCE_CUSTOM.r;
}

void fragment() {
	vec3 prism = texture(diffuser_tex, UV * vec2(2.0, 1.0)).rgb;
	// Values above 1 feed the glow pass.
	ALBEDO = light_color * prism * (0.12 + power * intensity);
}
