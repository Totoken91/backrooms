shader_type canvas_item;
render_mode blend_disabled;
#include "res://shaders/spans.gdshaderinc"
#include "res://shaders/shadow_trace.gdshaderinc"
uniform vec3 beam_origin;
uniform vec3 beam_right;
uniform vec3 beam_up;
uniform vec3 beam_forward;
uniform float beam_tan = 0.7;
uniform float beam_range = 18.0;
void fragment() {
	vec2 screen = UV * 2.0 - 1.0;
	vec3 ray = normalize(beam_forward + (beam_right * screen.x - beam_up * screen.y) * beam_tan);
	float hit = traced_depth(beam_origin,ray,beam_range);
	// 16-bit distance in RG; nearest sampling, PCF happens on receivers.
	float encoded = floor(clamp(hit / beam_range, 0.0, 1.0) * 65535.0);
	COLOR = vec4(floor(encoded / 256.0) / 255.0, mod(encoded, 256.0) / 255.0, 0.0, 1.0);
}
