shader_type canvas_item;
render_mode blend_disabled;
// Light bake, gather pass: indirect light, coloured by the surfaces it comes
// from, on a chunk (0.25 m texels). Run twice: the first gather sees surfaces
// lit by the panels only (one bounce); the second also sees the light of the
// first gather on them, the ceiling above all (two bounces). Three 160 × 160 tiles:
//   tile 0: floor (receiver facing up, at the floor)
//   tile 1: ceiling (facing down, at the ceiling)
//   tile 2: walls (average of the four horizontal orientations, at 1.4 m)
// Rays (16 azimuths × 6 elevations, uniform over the sphere) march the level
// in 3D through its solid spans (spans.gdshaderinc): a ray entering a solid
// sideways hits a wall face, crossing the bottom of a span a ceiling or the
// underside of a lintel, crossing its top the floor or the top of a slab.
// A hit returns albedo × irradiance / π read from the maps of the
// whole streamed region. `boost` stands for the further bounces.

#include "res://shaders/spans.gdshaderinc"
#include "res://shaders/gap.gdshaderinc"

#include "res://shaders/light_maps.gdshaderinc"
// 0 on the first gather; on the second, the factor on the first gather seen
// on hit surfaces standing for all their indirect light (≈ 1 / (1 - albedo)).
uniform float use_bounce = 0.0;
uniform vec2 bake_origin;       // world position of the baked chunk's corner
uniform vec3 wall_albedo = vec3(0.7, 0.6, 0.3);
uniform vec3 floor_albedo = vec3(0.5, 0.45, 0.3);
uniform vec3 ceiling_albedo = vec3(0.75, 0.73, 0.65);
uniform float texel = 0.25;
uniform float tiles = 3.0;
uniform float res = 160.0;
uniform float e_max = 6.0;
uniform float i_max = 2.0;
uniform float boost = 1.0;
uniform float max_distance = 16.0;
// Diagnostic: isolate the wall receiver height without changing map layout.
uniform float wall_receiver_fraction = 0.5;

// Texels whose centre lies in a wall take the light of the nearest free
// point: otherwise bilinear filtering bleeds black into the floor and walls
// at their junction (dark smudges at the foot of brightly lit walls).
vec2 free_point(vec2 p) {
	if (occupied(p) < 0.5) return p;
	for (int k = 1; k <= 3; k++) {
		for (int d = 0; d < 8; d++) {
			float ang = float(d) * PI * 0.25;
			vec2 q = p + vec2(cos(ang), sin(ang)) * float(k) * occ_texel;
			if (occupied(q) < 0.5) return q;
		}
	}
	return p;
}


// Direct map `map` (0-3) at p, relative to the baked chunk.
vec4 dmap(int map, vec2 p) {
	return light_energy(map, bake_origin + p) * e_max;
}

// First-gather map `map` (5-7): irradiance (rgb) at p, relative to the chunk.
vec3 bmap(int map, vec2 p) {
	return light_energy(map, bake_origin + p).rgb * i_max * use_bounce;
}

// Direct irradiance of a wall facing `axis` (0 +X, 1 -X, 2 +Z, 3 -Z) at height y,
// read just in front of it at p.
float wall_direct(vec2 p, int axis, float y) {
	vec4 a = dmap(0, p), b = dmap(1, p), c = dmap(2, p), d = dmap(3, p);
	float h0 = axis == 0 ? a.y : axis == 1 ? a.z : axis == 2 ? a.w : b.x;
	float h1 = axis == 0 ? b.y : axis == 1 ? b.z : axis == 2 ? b.w : c.x;
	float h2 = axis == 0 ? c.y : axis == 1 ? c.z : axis == 2 ? c.w : d.x;
	return wall_profile(h0, h1, h2, y, column_gap(p), ceiling - 0.01);
}

void fragment() {
	vec2 cell = bake_cell(UV, res, tiles);
	float tile = floor(cell.x / res);
	vec2 local = vec2(mod(cell.x, res), cell.y);
	vec2 p = free_point((local + 0.5) * texel);
	vec3 total = vec3(0.0);
	// Three tiles only (the viewport has five, for the direct pass).
	if (tile < 2.5 && occupied(p) < 0.5) {
		// Receivers in the column's room space: its floor, its ceiling (the
		// underside of a lintel or duct roof above it), walls midway.
		vec2 gap = column_gap(p);
		float y0 = tile < 0.5 ? gap.x + 0.03 : (tile < 1.5 ? gap.y - 0.03 : mix(gap.x, gap.y, wall_receiver_fraction));
		// Walls: the light a wall receives comes from the half-space in front of
		// it. Next to a wall (within 0.5 m) face away from it; elsewhere average
		// the four orientations.
		vec2 wall_normal = vec2(0.0);
		if (tile > 1.5) {
			for (int k = 1; k <= 4; k++) {
				float r = float(k) * occ_texel;
				if (occupied(p + vec2(r, 0)) > 0.5) wall_normal.x -= 1.0;
				if (occupied(p - vec2(r, 0)) > 0.5) wall_normal.x += 1.0;
				if (occupied(p + vec2(0, r)) > 0.5) wall_normal.y -= 1.0;
				if (occupied(p - vec2(0, r)) > 0.5) wall_normal.y += 1.0;
			}
			if (length(wall_normal) > 0.0) wall_normal = normalize(wall_normal);
		}
		// Rays: 16 azimuths × 6 elevations, the pattern rotated and jittered per
		// texel (a fixed pattern draws streaks); the denoise pass smooths it.
		float rot = fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
		float lift = fract(sin(dot(p, vec2(39.3468, 11.135))) * 24634.6345);
		const int AZ = 16;
		const int EL = 6;
		float weight = 4.0 * PI / float(AZ * EL);
		float cosine_weight = 0.0;
		for (int e = 0; e < EL; e++) {
			float cz = 1.0 - 2.0 * (float(e) + lift) / float(EL);   // stratified, uniform in cos
			float sz = sqrt(1.0 - cz * cz);
			for (int a = 0; a < AZ; a++) {
				float phi = (float(a) + rot + 0.5 * float(e % 2)) * 2.0 * PI / float(AZ);
				vec3 dir = vec3(cos(phi) * sz, cz, sin(phi) * sz);
				float facing;
				if (tile < 0.5) facing = dir.y;
				else if (tile < 1.5) facing = -dir.y;
				else if (length(wall_normal) > 0.0) facing = dot(dir.xz, wall_normal);
				else facing = (abs(dir.x) + abs(dir.z)) * 0.25;   // mean over 4 walls
				if (facing <= 0.0) continue;
				cosine_weight += facing * weight;
				// One column per step; in each, the height interval the ray covers
				// is tested against the column's spans.
				float dt = occ_texel / max(sz, 1e-3);
				float t_max = max_distance / max(sz, 0.05);
				vec3 radiance = vec3(0.0);
				float t_prev = 0.0;
				for (int i = 1; i < 160; i++) {
					float t = min(float(i) * dt, t_max);
					vec2 qm = p + dir.xz * (t_prev + t) * 0.5;
					float ya = y0 + dir.y * t_prev, yb = y0 + dir.y * t;
					vec4 sa, sb;
					spans_at(qm, sa, sb);
					vec4 lo = vec4(sa.x, sa.z, sb.x, sb.z), hi = vec4(sa.y, sa.w, sb.y, sb.w);
					bool side = false;
					for (int k = 0; k < 4; k++) side = side || (ya > lo[k] && ya < hi[k]);
					if (side) {
						// A step can cross both grid axes. Preferring X on a tie
						// mislabels continuous Z walls and reads their unlit X field.
						// Find the exposed face from the adjacent solid columns;
						// at a genuine corner use the last crossed cell boundary.
						vec2 wall_at = floor((qm - occ_origin) / occ_texel);
						vec2 centre = occ_origin + (wall_at + 0.5) * occ_texel;
						vec2 step_sign = sign(dir.xz);
						bool open_x = !blocked(centre - vec2(step_sign.x * occ_texel, 0), ya - 0.001, ya + 0.001);
						bool open_z = !blocked(centre - vec2(0, step_sign.y * occ_texel), ya - 0.001, ya + 0.001);
						vec2 entry = centre - step_sign * occ_texel * 0.5;
						float tx = abs(dir.x) > 1e-5 ? (entry.x - p.x) / dir.x : -1e5;
						float tz = abs(dir.z) > 1e-5 ? (entry.y - p.y) / dir.z : -1e5;
						bool x_face = open_x != open_z ? open_x : tx >= tz;
						int axis = x_face ? (dir.x > 0.0 ? 1 : 0) : (dir.z > 0.0 ? 3 : 2);
						// Read the wall's light 0.2 m in front of it: closer, bilinear
						// filtering mixes in the wall's own (black) texels.
						vec2 face = axis == 0 ? vec2(1, 0) : axis == 1 ? vec2(-1, 0) : axis == 2 ? vec2(0, 1) : vec2(0, -1);
						float hit_t = max(x_face ? tx : tz, 0.0);
						vec2 front = p + dir.xz * hit_t + face * 0.2;
						radiance = wall_albedo * (wall_direct(front, axis, y0 + dir.y * hit_t) + bmap(7, front)) / PI;
						break;
					}
					// Horizontal faces crossed within the step: the first one met.
					float face_y = 1e5;
					if (dir.y > 0.0) {
						for (int k = 0; k < 4; k++) if (lo[k] > ya && lo[k] <= yb) face_y = min(face_y, lo[k]);
					} else {
						face_y = -1e5;
						for (int k = 0; k < 4; k++) if (hi[k] < ya && hi[k] >= yb) face_y = max(face_y, hi[k]);
					}
					if (abs(face_y) < 1e4) {
						vec2 q = p + dir.xz * ((face_y - y0) / dir.y);
						if (dir.y < 0.0) {
							// Floor, or the top of a slab (seen with the floor's light).
							vec3 alb = face_y < column_gap(q).x + 0.1 ? floor_albedo : wall_albedo;
							radiance = alb * (dmap(0, q).x + bmap(5, q)) / PI;
						} else {
							// Ceiling (no direct light: the panels face down), or the
							// underside of a lintel, lit from below like the ceiling.
							vec3 alb = face_y > ceiling - 0.1 ? ceiling_albedo : wall_albedo;
							radiance = alb * bmap(6, q) / PI;
						}
						break;
					}
					if (t >= t_max) break;
					t_prev = t;
				}
				total += radiance * facing * weight;
			}
		}
		// The exact cosine integral is PI for every unit receiver normal (and
		// for an average of normals). Finite jittered sphere quadrature varies
		// by up to 1/3 for floor/ceiling. Normalize the quadrature, including
		// rays that miss or hit black surfaces, to preserve constant radiance.
		// This is not a visibility-dependent gain: darkness remains darkness.
		total *= boost * PI / max(cosine_weight, 1e-5);
	}
	COLOR = vec4(sqrt(clamp(total / i_max, 0.0, 1.0)), 1.0);
}
