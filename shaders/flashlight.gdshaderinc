// Direct flashlight irradiance, additive in linear space before tone mapping.
// The GPU shadow texture comes from the same SpanMap geometry as baked light.
uniform sampler2D flashlight_shadow : filter_nearest, repeat_disable;
uniform bool flashlight_enabled = false;
uniform vec3 flashlight_origin;
uniform vec3 flashlight_right;
uniform vec3 flashlight_up;
uniform vec3 flashlight_forward;
uniform float flashlight_tan = 0.7;
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
		// PCF taps see different positions on a grazing receiver. Compare
		// each depth to the intersection of THAT ray with the receiver plane,
		// rather than to the central ray distance (which causes dark stripes).
		vec2 tap = (floor((uv+offset)/pixel)+0.5)*pixel;
		vec2 s = tap*2.0-1.0;
		vec3 ray = normalize(flashlight_forward+(flashlight_right*s.x-flashlight_up*s.y)*flashlight_tan);
		float facing = dot(ray,normal);
		float plane_depth = dot(v,normal)/min(facing,-0.00001);
		visible += facing < -0.00001 ? step(plane_depth-bias,flashlight_depth(tap)) : 0.0;
	}
	float cone = 0.82*(1.0-smoothstep(0.12,0.55,radius))+0.18*(1.0-smoothstep(0.1,1.0,radius));
	float cutoff = 1.0 - smoothstep(flashlight_range * 0.75, flashlight_range, d);
	return flashlight_color * (flashlight_energy * cone * cutoff * cosine * visible * 0.25 / (1.0 + d * d));
}

// Four reflected patches selected by real cone hits. Each has an occlusion
// cubemap; no constant ambient term and no illumination through a closed wall.
#include "res://shaders/cube_shadow.gdshaderinc"
uniform sampler2D flashlight_bounce_shadow : filter_nearest, repeat_disable;
uniform vec3 bounce_position[4];
uniform vec3 bounce_normal[4];
uniform vec3 bounce_power[4];
uniform bool flashlight_bounce_enabled = true;
vec3 flashlight_indirect(vec3 position, vec3 normal) {
	if (!flashlight_enabled || !flashlight_bounce_enabled) return vec3(0.0);
	vec3 energy = vec3(0.0);
	for (int i=0;i<4;i++) {
		if (dot(bounce_power[i],vec3(1.0)) <= 0.0) continue;
		vec3 v = position-bounce_position[i];
		float d = length(v);
		if (d >= 6.0 || d < 0.02) continue;
		vec3 ray = v/d;
		float cosine = max(dot(ray,bounce_normal[i]),0.0)*max(dot(-ray,normal),0.0);
		if (cosine <= 0.0) continue;
		vec3 c = cube_uv(ray);
		vec2 cell = clamp(floor((c.xy*0.5+0.5)*24.0),vec2(0.0),vec2(23.0));
		vec2 uv = (vec2(c.z*24.0,float(i)*24.0)+cell+0.5)/vec2(144.0,96.0);
		vec2 encoded = texture(flashlight_bounce_shadow,uv).rg;
		float depth = dot(encoded,vec2(65280.0,255.0))/65535.0*6.0;
		vec3 tap_ray = cube_ray(int(c.z),(cell+0.5)/24.0*2.0-1.0);
		float plane_depth = dot(v,normal)/min(dot(tap_ray,normal),-0.00001);
		float visibility = dot(tap_ray,normal)<-0.00001 ? step(plane_depth-0.08,depth) : 0.0;
		energy += bounce_power[i]*cosine*visibility*(1.0-smoothstep(4.5,6.0,d))/(0.4+d*d);
	}
	return energy;
}
