// Exact texture decoding; Compatibility 4.6 uses approximate conversions in
// scene.glsl / tonemap_inc.glsl. Invert its input polynomial so dark linear
// light is not lost before tonemapping. This is a transfer correction, not GI.
uniform bool raw_output = false;

vec3 to_linear(vec3 c) {
	return mix(pow((c + 0.055) / 1.055, vec3(2.4)), c / 12.92, lessThan(c, vec3(0.04045)));
}

vec3 to_srgb(vec3 c) {
	c = max(c, vec3(0.0));
	return mix(1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055, c * 12.92, lessThan(c, vec3(0.0031308)));
}

vec3 compatibility_albedo(vec3 linear) {
	vec3 target = max(linear, vec3(0.0));
	if (raw_output) {
		// Linear measurement mode: also compensate the engine's output power
		// curve, which omits the sRGB linear toe. Zero must remain exactly zero.
		vec3 encoded = to_srgb(target);
		target = mix(pow((encoded + 0.055) / 1.055, vec3(2.4)), vec3(0.0), lessThanEqual(target, vec3(0.0)));
	}
	vec3 x = to_srgb(target);
	for (int i = 0; i < 6; i++) {
		vec3 f = x * (x * (x * 0.305306011 + 0.682171111) + 0.012522878);
		vec3 df = x * (x * 0.915918033 + 1.364342222) + 0.012522878;
		x = max(x - (f - target) / df, vec3(0.0));
	}
	return x;
}
