shader_type spatial;
// Level 0 surfaces, lit only by the GPU-baked light of the panels
// (LightBaker): direct irradiance for the floor and for walls at two heights
// and four orientations, plus one coloured bounce, plus fine contact
// occlusion. Outgoing light = albedo × irradiance / π, tonemapped by AgX like
// the Cycles truth renders. UVs are world-space metres / tile size.
render_mode unshaded, cull_back;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
// Linear multiplier on the linear albedo (the Cycles material tints).
uniform vec3 tint = vec3(1.0);
// 1 draws the 2 × 2 ft suspended-ceiling grid from the UVs.
uniform bool ceiling_grid = false;
// 1 adds a little damp near the floor (wallpaper).
uniform bool wall_damp = false;

#include "res://shaders/gap.gdshaderinc"
#include "res://shaders/light_maps.gdshaderinc"
#include "res://shaders/structural_room.gdshaderinc"
uniform vec3 panel_color = vec3(1.0, 0.97, 0.9);
uniform float e_max = 6.0;
uniform float i_max = 2.0;
uniform float light_scale = 1.0;
uniform float ao_strength = 0.7;
// Roughness of the finish, for the faint white Fresnel reflection of a
// dielectric (IOR 1.5) like Cycles' Principled BSDF: wall 0.85, floor 0.95,
// ceiling 0.9.
uniform float roughness = 0.9;
uniform float ceiling_height = 3.2;
// Side of a ceiling tile (a third of a 2.5 m cell).
uniform float tile_size = 0.8333;
// Development: 1 light-map coordinates, 2 raw direct map, 3 direct texture,
// 4 AO, 5 grey 0.18, 6 albedo, 7 contact, 8 direct E / π, 9 indirect E / π
// (8 and 9 with the raw option: linear tonemap, comparable to Cycles passes).
uniform float debug_view = 0.0;
// Power factor of the flicker groups 1..3 (PanelLights), 1 = as baked.
uniform vec3 group_power = vec3(1.0);

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

#include "res://shaders/color_space.gdshaderinc"
#include "res://shaders/flashlight.gdshaderinc"

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	// Far away, fine prints alias whatever the filtering: fade towards the
	// finish's average colour and flatten the relief.
	float dist = length(VERTEX);
	vec3 sampled = to_linear(texture(albedo_tex, UV).rgb);
	vec3 average = to_linear(textureLod(albedo_tex, vec2(0.5), 10.0).rgb);
	vec3 color = mix(sampled, average, smoothstep(5.0, 22.0, dist) * 0.85) * tint;
	// Large-scale variation keeps big planes from looking printed.
	color *= 0.95 + 0.08 * noise(world_pos.xz * 0.23 + world_pos.yy * 0.21);
	if (wall_damp) {
		float along = dot(world_pos.xz, vec2(-world_normal.z, world_normal.x));
		float damp = smoothstep(0.64, 0.84, noise(vec2(along * 0.36, world_pos.y * 0.55))) * (1.0 - smoothstep(0.05, 1.15, world_pos.y));
		color = mix(color, color * vec3(0.68, 0.71, 0.52), damp * 0.23);
	}
	if (ceiling_grid) {
		// Square tiles, three per 2.5 m cell (the middle one holds the panel),
		// with thin T-bar seams.
		vec2 tile = world_pos.xz / tile_size;
		vec2 q = fract(tile);
		vec2 width = fwidth(tile) * 1.2;
		float seam = max(1.0 - smoothstep(0.0, width.x + 0.004, min(q.x, 1.0 - q.x)), 1.0 - smoothstep(0.0, width.y + 0.002, min(q.y, 1.0 - q.y)));
		color *= 0.975 + 0.035 * hash(floor(tile));
		color = mix(color, color * 0.86, seam * 0.6);
	}
	vec2 at = world_pos.xz + world_normal.xz * 0.13;
	vec4 d0 = light_map(0, at), d1 = light_map(1, at), d2 = light_map(2, at), d3 = light_map(3, at);
	// Room space of this column (floor and ceiling heights).
	vec2 gap = gap_map(at, ceiling_height);
	d0 = d0 * d0 * e_max; d1 = d1 * d1 * e_max; d2 = d2 * d2 * e_max; d3 = d3 * d3 * e_max;
	vec3 direct;
	vec3 bounce;
	if (world_normal.y > 0.5) {
		direct = vec3(d0.x);
		vec3 b = light_map(8, at).rgb;
		bounce = b * b * i_max;
	} else if (world_normal.y < -0.5) {
		direct = vec3(0.0);
		vec3 b = light_map(9, at).rgb;
		bounce = b * b * i_max;
	} else {
		// Walls: irradiance for the facing axis at three heights.
		int axis = world_normal.x > 0.5 ? 0 : world_normal.x < -0.5 ? 1 : world_normal.z > 0.5 ? 2 : 3;
		float h0 = axis == 0 ? d0.y : axis == 1 ? d0.z : axis == 2 ? d0.w : d1.x;
		float h1 = axis == 0 ? d1.y : axis == 1 ? d1.z : axis == 2 ? d1.w : d2.x;
		float h2 = axis == 0 ? d2.y : axis == 1 ? d2.z : axis == 2 ? d2.w : d3.x;
		direct = vec3(wall_profile(h0, h1, h2, world_pos.y, gap, structural_ceiling(at, ceiling_height) - 0.01));
		vec3 b = light_map(10, at).rgb;
		bounce = b * b * i_max;
	}
	// Development (debug_view 10): the first gather alone (one bounce).
	vec3 fb = light_map(world_normal.y > 0.5 ? 5 : (world_normal.y < -0.5 ? 6 : 7), at).rgb;
	vec3 first_bounce = fb * fb * i_max;
	// Flicker: each group's share of the direct light here (baked) follows the
	// group's power; the indirect light follows a share smoothed over ~1.5 m.
	vec3 dim = vec3(1.0) - group_power;
	if (dim.x + dim.y + dim.z > 0.001) {
		direct *= max(1.0 - dot(d3.yzw, dim), 0.0);
		vec3 share = d3.yzw;
		for (int k = 0; k < 4; k++) {
			vec4 n = light_map(3, at + vec2(k < 2 ? (k == 0 ? 1.5 : -1.5) : 0.0, k >= 2 ? (k == 2 ? 1.5 : -1.5) : 0.0));
			share += n.yzw * n.yzw * e_max;
		}
		bounce *= max(1.0 - 0.8 * dot(share / 5.0, dim), 0.0);
	}
	// Contact occlusion: full on the floor, fading up the wall from its foot
	// and down from the ceiling, so corners and junctions darken softly.
	float occlusion = ao_map(world_pos.xz + world_normal.xz * 0.03);
	float near_floor = 1.0 - smoothstep(0.0, 0.35, world_pos.y - gap.x);
	float near_ceiling = 1.0 - smoothstep(0.0, 0.4, gap.y - world_pos.y);
	// Light at the ceiling: a lit wall brightens the ceiling beside it, so the
	// wall-ceiling junction only darkens slightly.
	float junction = world_normal.y > 0.5 ? 1.0 : (world_normal.y < -0.5 ? 0.15 : max(near_floor * 0.7, near_ceiling * 0.1));
	float contact = mix(1.0, occlusion, junction * ao_strength);
	// Rough Schlick Fresnel (F0 0.04), energy conserving like the Principled
	// BSDF: the reflected part is white and takes from the diffuse part. The
	// reflected light is taken as the incident irradiance (rough surfaces).
	float cos_v = clamp(dot(normalize(CAMERA_POSITION_WORLD - world_pos), world_normal), 0.0, 1.0);
	float fresnel = 0.04 + (max(1.0 - roughness, 0.04) - 0.04) * pow(1.0 - cos_v, 5.0);
	vec3 irradiance = direct * panel_color + bounce + flashlight_irradiance(world_pos, world_normal);
	ALBEDO = compatibility_albedo((color * (1.0 - fresnel) + fresnel) * irradiance * contact * light_scale / PI);
	if (debug_view > 0.5) ALBEDO = debug_view < 1.5 ? vec3(fract(at / 40.0), 0.0) : debug_view < 2.5 ? d0.rgb / e_max : debug_view < 3.5 ? light_map(0, at).rgb : debug_view < 4.5 ? vec3(ao_map(at)) : debug_view < 5.5 ? compatibility_albedo(vec3(0.18)) : debug_view < 6.5 ? compatibility_albedo(color) : debug_view < 7.5 ? vec3(contact) : debug_view < 8.5 ? compatibility_albedo(direct * panel_color / PI) : debug_view < 9.5 ? compatibility_albedo(bounce / PI) : compatibility_albedo(first_bounce / PI);
}
