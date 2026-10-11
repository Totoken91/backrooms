shader_type canvas_item;
render_mode blend_disabled;
// Light bake, pass 1: direct light of the panels on a chunk, 0.25 m texels.
// The viewport holds four 160 × 160 tiles side by side:
//   tile 0: floor (up), wall h0 (+X, -X, +Z)
//   tile 1: wall h0 (-Z), wall h1 (+X, -X, +Z)
//   tile 2: wall h1 (-Z), wall h2 (+X, -X, +Z)
//   tile 3: wall h2 (-Z), then the share of the floor light coming from each
//           flicker group 1..3 (a fraction, encoded like the irradiance)
//   tile 4: room space of the column: floor and ceiling heights (16 bits each)
// The floor and wall receivers sit in the column's own space (gap.gdshaderinc).
// "Wall" values are the irradiance on a vertical surface facing that axis, at
// three heights of the column's room space. Panels are Lambertian squares facing down,
// sampled at 8 points; visibility is traced in 3D through the solid spans of
// the level (spans.gdshaderinc). Coordinates are relative to the chunk origin.
// Values are stored as sqrt(E / e_max) for low-end precision.

#include "res://shaders/spans.gdshaderinc"
#include "res://shaders/gap.gdshaderinc"

uniform sampler2D fix_tex : filter_nearest, repeat_disable; // row 0: x, z, radiance, height; row 1: flicker group
uniform int fix_count = 0;
uniform float texel = 0.25;
uniform float tiles = 3.0;
uniform float res = 160.0;
uniform float e_max = 6.0;
uniform float reach = 8.0;
uniform bool calibrate = false;   // development: writes the texel coordinates


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


void fragment() {
	vec2 cell = bake_cell(UV, res, tiles);
	float tile = floor(cell.x / res);
	vec2 local = vec2(mod(cell.x, res), cell.y);
	vec2 p = free_point((local + 0.5) * texel);
	vec4 outv = vec4(0.0);
	// Room space of the column; the wall light is stored at three heights in
	// it: it rises from the floor, peaks and falls under the ceiling.
	vec2 gap = column_gap(p);
	vec3 hs = wall_heights(gap);
	if (occupied(p) < 0.5) {
		float e[13];
		for (int k = 0; k < 13; k++) e[k] = 0.0;
		vec3 eg = vec3(0.0);
		vec3 axes[4] = vec3[4](vec3(1, 0, 0), vec3(-1, 0, 0), vec3(0, 0, 1), vec3(0, 0, -1));
		for (int i = 0; i < fix_count; i++) {
			vec4 f = texelFetch(fix_tex, ivec2(i, 0), 0);
			if (distance(f.xy, p) > reach || f.z <= 0.0) continue;
			int group = int(texelFetch(fix_tex, ivec2(i, 1), 0).r + 0.5);
			// 3 × 3 points over the 0.833 m square diffuser, shifted per texel so the
			// penumbrae through openings are smooth after the denoise pass.
			vec2 jit = (vec2(fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453), fract(sin(dot(p, vec2(39.3468, 11.135))) * 24634.6345)) - 0.5) * vec2(0.278, 0.278);
			for (int s = 0; s < 9; s++) {
				vec2 q = f.xy + vec2(float(s % 3) - 1.0, float(s / 3) - 1.0) * 0.278 + jit;
				vec3 lp = vec3(q.x, f.w - 0.01, q.y);
				// Visibility in 3D per receiver height (a lintel can hide a panel
				// from the floor and not from the top of a wall): floor and h0
				// share one test.
				float vis_low = visible(vec3(p.x, gap.x + 0.02, p.y), lp);
				float vis_mid = visible(vec3(p.x, hs.y, p.y), lp);
				float vis_top = visible(vec3(p.x, hs.z, p.y), lp);
				if (vis_low + vis_mid + vis_top < 0.5) continue;
				// dA = panel area (0.694 m²) / 9; radiance f.z; E += L cos cos dA / d².
				float w = f.z * 0.0772;
				vec3 v = lp - vec3(p.x, gap.x + 0.02, p.y);
				float d2 = dot(v, v);
				vec3 o = v * inversesqrt(d2);
				e[0] += vis_low * w * o.y * o.y / d2;
				if (group > 0) eg[group - 1] += vis_low * w * o.y * o.y / d2;
				for (int h = 0; h < 3; h++) {
					float vis = h == 0 ? vis_low : (h == 1 ? vis_mid : vis_top);
					if (vis < 0.5) continue;
					vec3 vh = lp - vec3(p.x, hs[h], p.y);
					float dh = dot(vh, vh);
					vec3 oh = vh * inversesqrt(dh);
					for (int a = 0; a < 4; a++)
						e[1 + h * 4 + a] += w * max(dot(axes[a], oh), 0.0) * oh.y / dh;
				}
			}
		}
		// A wall height inside solid geometry (under a lintel, a slab) has no
		// surface there: it takes the value of the free height below, or the
		// wall profile through a zero would darken the whole wall.
		for (int h = 1; h < 3; h++) {
			float y = hs[h];
			if (blocked(p, y - 0.01, y + 0.01))
				for (int a = 0; a < 4; a++) e[1 + h * 4 + a] = e[1 + (h - 1) * 4 + a];
		}
		if (tile < 0.5) outv = vec4(e[0], e[1], e[2], e[3]);
		else if (tile < 1.5) outv = vec4(e[4], e[5], e[6], e[7]);
		else if (tile < 2.5) outv = vec4(e[8], e[9], e[10], e[11]);
		else outv = vec4(e[12], eg / max(e[0], 1e-4));
		outv = sqrt(clamp(outv / e_max, 0.0, 1.0));
	}
	// Room space, read without filtering (gap_map); the denoise pass keeps it.
	if (tile > 3.5) outv = vec4(encode_height(gap.x), encode_height(gap.y));
	if (calibrate) outv = vec4(local / res, tile / 4.0, 1.0);
	COLOR = outv;
}
