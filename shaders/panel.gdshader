shader_type spatial;
// Prismatic fluorescent diffuser. INSTANCE_CUSTOM.r carries the live panel
// power. Radiance in linear units, as in Cycles (emission strength 12), then
// encoded to sRGB: the Compatibility renderer reads ALBEDO as sRGB.
render_mode unshaded, cull_disabled;

uniform sampler2D diffuser_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform vec3 light_color = vec3(1.0, 0.97, 0.9);
uniform float radiance = 12.0;

varying float power;

vec3 to_linear(vec3 c) {
	return mix(pow((c + 0.055) / 1.055, vec3(2.4)), c / 12.92, lessThan(c, vec3(0.04045)));
}

vec3 to_srgb(vec3 c) {
	return mix(1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055, c * 12.92, lessThan(c, vec3(0.0031308)));
}

void vertex() {
	power = INSTANCE_CUSTOM.r;
}

void fragment() {
	vec3 prism = to_linear(texture(diffuser_tex, UV).rgb);
	prism /= max(dot(to_linear(textureLod(diffuser_tex, vec2(0.5), 10.0).rgb), vec3(0.333)), 0.05);
	// Values above 1 feed the glow pass.
	ALBEDO = to_srgb(light_color * prism * (0.01 + power) * radiance);
}
