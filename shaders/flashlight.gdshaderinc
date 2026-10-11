// Direct flashlight irradiance, additive in linear space before tone mapping.
// The GPU shadow texture comes from the same SpanMap geometry as baked light.
uniform sampler2D flashlight_shadow : filter_nearest, repeat_disable;
uniform bool flashlight_enabled = false;
uniform vec3 flashlight_origin;
uniform vec3 flashlight_right;
uniform vec3 flashlight_up;
uniform vec3 flashlight_forward;
uniform float flashlight_tan = 0.4877;
uniform float flashlight_range = 18.0;
uniform vec3 flashlight_color = vec3(1.0, 0.94, 0.82);
uniform float flashlight_energy = 24.0;
float flashlight_depth(vec2 uv) {
	vec2 c = texture(flashlight_shadow, uv).rg;
	return dot(c, vec2(65280.0, 255.0)) / 65535.0 * flashlight_range;
}
vec3 flashlight_irradiance(vec3 position, vec3 normal) {
	if (!flashlight_enabled) return vec3(0.0);
	vec3 v = position - flashlight_origin;
	float d = length(v);
	float forward = dot(v, flashlight_forward);
	if (forward <= 0.0 || d >= flashlight_range) return vec3(0.0);
	vec2 screen = vec2(dot(v, flashlight_right), -dot(v, flashlight_up)) / (forward * flashlight_tan);
	float radius = length(screen);
	if (radius >= 1.0) return vec3(0.0);
	float cosine = max(dot(normal, -v / max(d, 0.001)), 0.0);
	if (cosine <= 0.0) return vec3(0.0);
	vec2 uv = screen * 0.5 + 0.5;
	vec2 pixel = vec2(1.0) / vec2(textureSize(flashlight_shadow, 0));
	float visible = 0.0;
	float bias = 0.15 + d * 0.004;
	for (int i = 0; i < 4; i++) {
		vec2 offset = vec2(float(i % 2) - 0.5, float(i / 2) - 0.5) * pixel;
		visible += step(d - bias, flashlight_depth(uv + offset));
	}
	float cone = 1.0 - smoothstep(0.3, 1.0, radius);
	float cutoff = 1.0 - smoothstep(flashlight_range * 0.75, flashlight_range, d);
	return flashlight_color * (flashlight_energy * cone * cutoff * cosine * visible * 0.25 / (1.0 + d * d));
}
