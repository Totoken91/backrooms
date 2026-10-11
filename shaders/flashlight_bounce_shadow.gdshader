shader_type canvas_item;
render_mode blend_disabled;
#include "res://shaders/spans.gdshaderinc"
#include "res://shaders/shadow_trace.gdshaderinc"
#include "res://shaders/cube_shadow.gdshaderinc"
uniform vec3 bounce_position[4];
uniform vec3 bounce_power[4];
void fragment() {
	vec2 tile = UV*vec2(6.0,4.0);
	int face = int(floor(tile.x));
	int probe = int(floor(tile.y));
	vec3 ray = cube_ray(face,fract(tile)*2.0-1.0);
	float depth = 6.0;
	if (dot(bounce_power[probe],vec3(1.0))>0.0) depth = traced_depth(bounce_position[probe],ray,6.0);
	float encoded = floor(clamp(depth/6.0,0.0,1.0)*65535.0);
	COLOR = vec4(floor(encoded/256.0)/255.0,mod(encoded,256.0)/255.0,0.0,1.0);
}
