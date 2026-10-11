shader_type canvas_item;
render_mode blend_disabled;
#include "res://shaders/spans.gdshaderinc"
uniform vec3 beam_origin;
uniform vec3 beam_right;
uniform vec3 beam_up;
uniform vec3 beam_forward;
uniform float beam_tan = 0.4877;
uniform float beam_range = 18.0;
void fragment() {
	vec2 screen = UV * 2.0 - 1.0;
	vec3 ray = normalize(beam_forward + (beam_right * screen.x - beam_up * screen.y) * beam_tan);
	vec2 cell = floor((beam_origin.xz - occ_origin) / occ_texel);
	vec2 step_dir = sign(ray.xz);
	vec2 safe_ray = mix(ray.xz, vec2(0.000001), lessThan(abs(ray.xz), vec2(0.000001)));
	vec2 boundary = occ_origin + (cell + max(step_dir, vec2(0.0))) * occ_texel;
	vec2 next_t = (boundary - beam_origin.xz) / safe_ray;
	vec2 stride = abs(vec2(occ_texel) / safe_ray);
	next_t = mix(next_t, vec2(1e20), lessThan(abs(ray.xz), vec2(0.000001)));
	float t = 0.0;
	float hit = beam_range;
	for (int i = 0; i < 256; i++) {
		float end = min(min(next_t.x, next_t.y), beam_range);
		vec3 p = beam_origin + ray * ((t + end) * 0.5);
		vec4 spans0, spans1;
		spans_at(p.xz, spans0, spans1);
		for (int k = 0; k < 4; k++) {
			vec2 slab = k == 0 ? spans0.xy : k == 1 ? spans0.zw : k == 2 ? spans1.xy : spans1.zw;
			if (slab.x < -50.0 && slab.y < -50.0) continue;
			if (abs(ray.y) < 0.000001) {
				if (beam_origin.y > slab.x && beam_origin.y < slab.y) hit = min(hit, t);
			} else {
				vec2 ys = (slab - beam_origin.y) / ray.y;
				float enter = max(t, min(ys.x, ys.y));
				float leave = min(end, max(ys.x, ys.y));
				if (enter <= leave && leave >= 0.0) hit = min(hit, max(enter, 0.0));
			}
		}
		if (hit < beam_range) break;
		if (end >= beam_range) break;
		t = end;
		bool cross_x = next_t.x <= next_t.y;
		if (cross_x) next_t.x += stride.x;
		else next_t.y += stride.y;
	}
	// 16-bit distance in RG; nearest sampling, PCF happens on receivers.
	float encoded = floor(clamp(hit / beam_range, 0.0, 1.0) * 65535.0);
	COLOR = vec4(floor(encoded / 256.0) / 255.0, mod(encoded, 256.0) / 255.0, 0.0, 1.0);
}
