shader_type canvas_item;
render_mode blend_disabled;
// Light bake, gather pass: indirect light, coloured by the surfaces it comes
// from, on a chunk (0.25 m texels). Run twice: the first gather sees surfaces
// lit by the panels only (one bounce); the second also sees the light of the
// first gather on them, the ceiling above all (two bounces). Three 160 × 160 tiles:
//   tile 0: floor (receiver facing up, at the floor)
//   tile 1: ceiling (facing down, at the ceiling)
//   tile 2: walls (average of the four horizontal orientations, at 1.4 m)
// Rays (12 azimuths × 6 elevations, uniform over the sphere) march the 2.5D
// scene: full-height walls from the occupancy map, the floor and ceiling as
// planes. A hit returns albedo × irradiance / π read from the maps of the
// whole streamed region. `boost` stands for the further bounces.

uniform sampler2D occ_tex : filter_nearest, repeat_disable;
uniform vec2 occ_origin;
uniform float occ_texel = 0.125;
uniform vec2 occ_size;
uniform sampler2D direct0 : filter_linear, repeat_disable;
uniform sampler2D direct1 : filter_linear, repeat_disable;
uniform sampler2D direct2 : filter_linear, repeat_disable;
uniform sampler2D bounce0 : filter_linear, repeat_disable;
uniform sampler2D bounce1 : filter_linear, repeat_disable;
uniform sampler2D bounce2 : filter_linear, repeat_disable;
// 0 on the first gather; on the second, the factor on the first gather seen
// on hit surfaces standing for all their indirect light (≈ 1 / (1 - albedo)).
uniform float use_bounce = 0.0;
uniform vec4 region;            // direct maps: origin (relative to chunk), size (m)
uniform vec3 wall_albedo = vec3(0.7, 0.6, 0.3);
uniform vec3 floor_albedo = vec3(0.5, 0.45, 0.3);
uniform vec3 ceiling_albedo = vec3(0.75, 0.73, 0.65);
uniform float texel = 0.25;
uniform float tiles = 3.0;
uniform float res = 160.0;
uniform float ceiling = 2.8;
uniform float e_max = 6.0;
uniform float i_max = 2.0;
uniform float boost = 1.0;
uniform float max_distance = 16.0;

float occupied(vec2 p) {
	vec2 t = (p - occ_origin) / occ_texel;
	if (t.x < 0.0 || t.y < 0.0 || t.x >= occ_size.x || t.y >= occ_size.y) return 0.0;
	return texelFetch(occ_tex, ivec2(t), 0).r;
}

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


vec4 dmap(sampler2D m, vec2 p) {
	vec4 v = texture(m, (p - region.xy) / region.zw);
	return v * v * e_max;
}

// First-gather irradiance (rgb) at p.
vec3 bmap(sampler2D m, vec2 p) {
	vec3 v = texture(m, (p - region.xy) / region.zw).rgb;
	return v * v * i_max * use_bounce;
}

// Direct irradiance of a wall facing `axis` (0 +X, 1 -X, 2 +Z, 3 -Z) at height y,
// read just in front of it at p.
float wall_direct(vec2 p, int axis, float y) {
	vec4 a = dmap(direct0, p), b = dmap(direct1, p), c = dmap(direct2, p);
	float low = axis == 0 ? a.y : axis == 1 ? a.z : axis == 2 ? a.w : b.x;
	float high = axis == 0 ? b.y : axis == 1 ? b.z : axis == 2 ? b.w : c.x;
	low = max(low, 1e-4);
	high = max(high, 1e-4);
	return low * pow(high / low, clamp((y - 0.6) / 1.5, -0.4, 1.4));   // geometric, as in surface.gdshader
}

void fragment() {
	vec2 cell = floor(UV * vec2(res * tiles, res));
	float tile = floor(cell.x / res);
	vec2 local = vec2(mod(cell.x, res), cell.y);
	vec2 p = free_point((local + 0.5) * texel);
	vec3 total = vec3(0.0);
	if (occupied(p) < 0.5) {
		float y0 = tile < 0.5 ? 0.03 : (tile < 1.5 ? ceiling - 0.03 : 1.4);
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
		const int AZ = 12;
		const int EL = 6;
		float weight = 4.0 * PI / float(AZ * EL);
		for (int e = 0; e < EL; e++) {
			float cz = 1.0 - 2.0 * (float(e) + 0.5) / float(EL);   // uniform in cos
			float sz = sqrt(1.0 - cz * cz);
			for (int a = 0; a < AZ; a++) {
				float phi = (float(a) + 0.5 * float(e % 2)) * 2.0 * PI / float(AZ);
				vec3 dir = vec3(cos(phi) * sz, cz, sin(phi) * sz);
				float facing;
				if (tile < 0.5) facing = dir.y;
				else if (tile < 1.5) facing = -dir.y;
				else if (length(wall_normal) > 0.0) facing = dot(dir.xz, wall_normal);
				else facing = (abs(dir.x) + abs(dir.z)) * 0.25;   // mean over 4 walls
				if (facing <= 0.0) continue;
				// Distance to the floor or ceiling plane along the ray.
				float t_plane = dir.y > 0.001 ? (ceiling - y0) / dir.y : (dir.y < -0.001 ? -y0 / dir.y : 1e5);
				float t_end = min(t_plane, max_distance / max(sz, 0.05));
				float h_end = t_end * sz;
				int steps = int(ceil(h_end / occ_texel));
				vec3 radiance = vec3(0.0);
				bool hit_wall = false;
				vec2 prev = p;
				for (int i = 1; i < 128; i++) {
					if (i > steps) break;
					float t = min(float(i) * occ_texel / max(sz, 1e-4), t_end);
					vec2 q = p + dir.xz * t;
					if (occupied(q) > 0.5) {
						float y = y0 + dir.y * t;
						// Facing axis: the one whose cell boundary the ray crossed.
						vec2 dc = floor((q - occ_origin) / occ_texel) - floor((prev - occ_origin) / occ_texel);
						int axis = abs(dc.x) >= abs(dc.y) ? (dir.x > 0.0 ? 1 : 0) : (dir.z > 0.0 ? 3 : 2);
						// Read the wall's light 0.2 m in front of it: closer, bilinear
						// filtering mixes in the wall's own (black) texels.
						vec2 face = axis == 0 ? vec2(1, 0) : axis == 1 ? vec2(-1, 0) : axis == 2 ? vec2(0, 1) : vec2(0, -1);
						vec2 wall_at = floor((q - occ_origin) / occ_texel);
						vec2 front = occ_origin + (wall_at + 0.5) * occ_texel;
						front = mix(front, prev, abs(face.yx)) + face * (0.0625 + 0.2);
						radiance = wall_albedo * (wall_direct(front, axis, clamp(y, 0.0, ceiling)) + bmap(bounce2, front)) / PI;
						hit_wall = true;
						break;
					}
					prev = q;
				}
				if (!hit_wall && t_plane < 1e4 && t_plane <= t_end + 1e-3) {
					vec2 q = p + dir.xz * t_plane;
					// The ceiling gets no direct light (the panels face down).
					if (dir.y < 0.0) radiance = floor_albedo * (dmap(direct0, q).x + bmap(bounce0, q)) / PI;
					else radiance = ceiling_albedo * bmap(bounce1, q) / PI;
				}
				total += radiance * facing * weight;
			}
		}
		total *= boost;
	}
	COLOR = vec4(sqrt(clamp(total / i_max, 0.0, 1.0)), 1.0);
}
