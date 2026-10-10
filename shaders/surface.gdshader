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
// Fine contact occlusion over the same area as the field (0.3125 m texels).
uniform sampler2D ao_tex : filter_linear, repeat_disable;
uniform float ao_strength = 0.7;
uniform float field_strength = 1.75;
uniform float ceiling_height = 2.8;
// Level 0 light itself is yellow: every surface is bathed in it.
uniform vec3 light_tint : source_color = vec3(1.0, 0.87, 0.5);
uniform float wall_level = 0.22;
uniform float floor_level = 0.31;
uniform float ceiling_level = 0.11;
// Even bounce light that fills every face, shadowed sides included.
uniform float ambient_level = 0.3;

// Panels around the player, one texel per 2.5 m cell: RG = panel centre
// within the cell, B = live power, A = 1 if the cell has a panel. Every panel
// lights its surroundings the same way at any distance from the player.
uniform sampler2D fixture_tex : filter_nearest, repeat_disable;
uniform vec2 fixture_origin = vec2(0.0);
uniform float fixture_cells = 80.0;
uniform float direct_strength = 0.7;

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
		// 2 × 4 ft tiles (0.625 × 1.25 m) with thin, light T-bar seams.
		vec2 tile = UV * vec2(1.0, 0.5);
		vec2 q = fract(tile);
		vec2 width = fwidth(tile) * 1.2;
		float seam = max(1.0 - smoothstep(0.0, width.x + 0.004, min(q.x, 1.0 - q.x)), 1.0 - smoothstep(0.0, width.y + 0.002, min(q.y, 1.0 - q.y)));
		color *= 0.975 + 0.035 * hash(floor(tile));
		color = mix(color, color * 0.86, seam * 0.6);
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
	float vertical = 1.0 - abs(world_normal.y);
	// Contact occlusion: full on the floor, fading up the wall from its foot
	// and down from the ceiling, so corners and junctions darken softly.
	float occlusion = texture(ao_tex, (world_pos.xz + world_normal.xz * 0.03 - field_rect.xy) / field_rect.zw).r;
	float near_floor = 1.0 - smoothstep(0.0, 0.35, world_pos.y);
	float near_ceiling = 1.0 - smoothstep(0.0, 0.4, ceiling_height - world_pos.y);
	float junction = world_normal.y > 0.5 ? 1.0 : (world_normal.y < -0.5 ? 0.6 : max(near_floor * 0.7, near_ceiling * 0.4));
	float contact = mix(1.0, occlusion, junction * ao_strength);
	float cove = 1.0;
	float skirting = 1.0;
	// Office light reads even: walls as bright as the floor, ceiling a bit less.
	float facing = world_normal.y < -0.5 ? ceiling_level : (world_normal.y > 0.5 ? floor_level : wall_level);
	EMISSION = color * light_tint * (irradiance * facing * field_strength + ambient_level) * contact * cove * skirting;

	// Direct light of the panels in the 3 × 3 cells around the fragment: a
	// downward cone gives the pool on the carpet and the arcs on the walls.
	// The reach (2.5 m horizontally) never exceeds the window, so no panel
	// enters or leaves abruptly. field.a is the baked share of nearby panels
	// this point sees, which keeps the light from crossing walls.
	vec2 cell = floor(world_pos.xz / 2.5);
	float direct = 0.0;
	for (int dz = -1; dz <= 1; dz++) {
		for (int dx = -1; dx <= 1; dx++) {
			vec2 c = cell + vec2(float(dx), float(dz));
			vec2 t = (c - fixture_origin + 0.5) / fixture_cells;
			if (t.x < 0.0 || t.y < 0.0 || t.x > 1.0 || t.y > 1.0) continue;
			vec4 f = texture(fixture_tex, t);
			if (f.a < 0.5) continue;
			vec3 centre = vec3((c.x + f.r) * 2.5, ceiling_height - 0.01, (c.y + f.g) * 2.5);
			// Fades out 2.1 m from the panel centre: its samples (±0.4 m) stay
			// inside the 2.5 m guaranteed by the window.
			float reach = 1.0 - smoothstep(1.3, 2.1, length(centre.xz - world_pos.xz));
			for (int s = 0; s < 2; s++) {
				vec3 to_light = centre + vec3(float(s) * 0.8 - 0.4, 0.0, 0.0) - world_pos;
				float d = length(to_light);
				vec3 l = to_light / d;
				float cone = smoothstep(0.05, 0.7, l.y);
				float ndl = max(dot(world_normal, l), 0.0);
				direct += f.b * cone * ndl * reach / (1.0 + d * d * 0.35);
			}
		}
	}
	// Walls only: fluorescent troffers light carpets evenly, round pools on the
	// floor read as theatre spotlights.
	EMISSION += color * light_tint * direct * field.a * contact * direct_strength * vertical;
}
