shader_type spatial;
// Level 0 surfaces. Godot lights (the nearest panels, with shadows) light the
// material physically; the precomputed irradiance field adds the light of all
// other panels as emission, sampled by world position. UVs are world-space
// metres divided by the finish's tile size, so seams never depend on meshing.
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert, specular_schlick_ggx;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rough_tex : hint_roughness_r, filter_linear_mipmap, repeat_enable;
uniform vec3 tint : source_color = vec3(1.0);
uniform float normal_strength = 0.6;
uniform float roughness_scale = 1.0;
uniform float metallic = 0.0;
// 1 draws the 0.625 m suspended-ceiling grid from the UVs.
uniform bool ceiling_grid = false;
// 1 adds a little damp near the floor (wallpaper).
uniform bool wall_damp = false;

uniform sampler2D field_tex : filter_linear, repeat_disable;
uniform vec4 field_rect = vec4(0.0, 0.0, 200.0, 200.0);
uniform float field_strength = 1.75;
uniform float ceiling_height = 2.8;

varying vec3 world_pos;
varying vec3 world_normal;

float hash(vec2 p) {
	p = mod(p, 289.0);
	vec3 q = fract(vec3(p.xyx) * 0.1031);
	q += dot(q, q.yzx + 33.33);
	return fract((q.x + q.y) * q.z);
}

float noise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	// Far away, fine prints alias whatever the filtering: fade towards the
	// finish's average colour and flatten the relief.
	float dist = length(VERTEX);
	vec3 sampled = texture(albedo_tex, UV).rgb;
	vec3 average = textureLod(albedo_tex, vec2(0.5), 10.0).rgb;
	vec3 color = mix(sampled, average, smoothstep(5.0, 22.0, dist) * 0.85) * tint;
	// Large-scale variation keeps big planes from looking printed.
	color *= 0.95 + 0.08 * noise(world_pos.xz * 0.23 + world_pos.yy * 0.21);
	if (wall_damp) {
		float along = dot(world_pos.xz, vec2(-world_normal.z, world_normal.x));
		float damp = smoothstep(0.64, 0.84, noise(vec2(along * 0.36, world_pos.y * 0.55))) * (1.0 - smoothstep(0.05, 1.15, world_pos.y));
		color = mix(color, color * vec3(0.68, 0.71, 0.52), damp * 0.23);
	}
	if (ceiling_grid) {
		vec2 q = fract(UV);
		float seam = max(1.0 - smoothstep(0.003, 0.012, min(q.x, 1.0 - q.x)), 1.0 - smoothstep(0.003, 0.012, min(q.y, 1.0 - q.y)));
		color *= 0.97 + 0.05 * hash(floor(UV));
		color = mix(color, vec3(0.46, 0.45, 0.36), seam * 0.4);
	}
	ALBEDO = color;
	ROUGHNESS = clamp(texture(rough_tex, UV).r * roughness_scale, 0.05, 1.0);
	METALLIC = metallic;
	NORMAL_MAP = texture(normal_tex, UV).rgb;
	NORMAL_MAP_DEPTH = normal_strength * (1.0 - smoothstep(3.0, 14.0, dist));

	// Irradiance field: R near the floor, G near the ceiling, B contact AO.
	vec2 fuv = (world_pos.xz + world_normal.xz * 0.2 - field_rect.xy) / field_rect.zw;
	vec4 field = texture(field_tex, fuv);
	float h = clamp(world_pos.y / ceiling_height, 0.0, 1.0);
	float irradiance = mix(field.r, field.g, h * h);
	float contact = mix(field.b, 1.0, smoothstep(0.1, 0.85, world_pos.y));
	float vertical = 1.0 - abs(world_normal.y);
	float cove = 1.0 - 0.15 * exp(-(ceiling_height - world_pos.y) * 13.0) * vertical;
	float skirting = 1.0 - 0.18 * exp(-world_pos.y * 12.0) * vertical;
	float facing = world_normal.y < -0.5 ? 0.46 : (world_normal.y > 0.5 ? 0.52 : 0.46);
	EMISSION = color * irradiance * contact * cove * skirting * facing * field_strength;
}
