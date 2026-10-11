shader_type spatial;
render_mode unshaded, cull_back;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap;
uniform sampler2D orm_tex : filter_linear_mipmap;
uniform vec3 player_light = vec3(0.2);
varying vec3 world_n;
#include "res://shaders/color_space.gdshaderinc"
void vertex() {world_n = normalize((MODEL_MATRIX * vec4(NORMAL,0.0)).xyz);}
void fragment() {
	vec3 albedo = to_linear(texture(albedo_tex, UV).rgb);
	vec3 orm = texture(orm_tex, UV).rgb;
	vec3 detail = texture(normal_tex, UV).xyz * 2.0 - 1.0;
	vec3 n = normalize(TANGENT * detail.x + BINORMAL * detail.y + NORMAL * detail.z);
	vec3 overhead = normalize((VIEW_MATRIX * vec4(0.0,1.0,0.0,0.0)).xyz + vec3(0.0,0.0,0.45));
	vec3 half_vector = normalize(overhead + normalize(-VERTEX));
	float shape = 0.38 + 0.62 * max(world_n.y, 0.0);
	float highlight = pow(max(dot(n, half_vector), 0.0), mix(32.0,3.0,orm.g));
	// Black anodised paint still has a dielectric coat. The broad reflection
	// follows the sampled room energy; zero Player.light remains truly black.
	vec3 f0 = mix(vec3(0.04), albedo, orm.b) + vec3(0.04);
	vec3 reflected = f0 * (0.2 + 0.8 * highlight) / (0.15 + orm.g * 0.7);
	ALBEDO = compatibility_albedo(player_light * (albedo * shape * orm.r + reflected));
}
