shader_type canvas_item;
render_mode blend_disabled;
// Light bake, pass 1: direct light of the panels on a chunk, 0.25 m texels.
// The viewport holds four 160 × 160 tiles side by side:
//   tile 0: floor (up), wall h0 (+X, -X, +Z)
//   tile 1: wall h0 (-Z), wall h1 (+X, -X, +Z)
//   tile 2: wall h1 (-Z), wall h2 (+X, -X, +Z)
//   tile 3: wall h2 (-Z)
// "Wall" values are the irradiance on a vertical surface facing that axis, at
// WALL_H0 / WALL_H1 / WALL_H2. Panels are Lambertian rectangles facing down, sampled
// at 2 × 2 points; full-height walls occlude (2D march through the occupancy
// map). Coordinates are relative to the chunk origin to keep precision.
// Values are stored as sqrt(E / e_max) for low-end precision.

uniform sampler2D occ_tex : filter_nearest, repeat_disable;
uniform vec2 occ_origin;        // occupancy texel 0, relative to the chunk
uniform float occ_texel = 0.125;
uniform vec2 occ_size;
uniform sampler2D fix_tex : filter_nearest, repeat_disable; // x, z, radiance, 0
uniform int fix_count = 0;
uniform float texel = 0.25;
uniform float tiles = 3.0;
uniform float res = 160.0;
uniform float ceiling = 2.8;
uniform float e_max = 6.0;
uniform float reach = 8.0;
uniform bool calibrate = false;   // development: writes the texel coordinates

// Wall heights: the light on a wall rises from the floor, peaks and falls
// again under the ceiling (recessed panels send little light sideways), so
// three heights are needed (surface.gdshader: wall_profile).
const float WALL_H0 = 0.4;
const float WALL_H1 = 1.6;
const float WALL_H2 = 2.5;

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


float visible(vec2 a, vec2 b) {
	vec2 d = b - a;
	int n = int(ceil(length(d) / occ_texel));
	for (int i = 1; i < 96; i++) {
		if (i >= n) break;
		if (occupied(a + d * (float(i) / float(n))) > 0.5) return 0.0;
	}
	return 1.0;
}

void fragment() {
	vec2 cell = floor(UV * vec2(res * tiles, res));
	float tile = floor(cell.x / res);
	vec2 local = vec2(mod(cell.x, res), cell.y);
	vec2 p = free_point((local + 0.5) * texel);
	vec4 outv = vec4(0.0);
	if (occupied(p) < 0.5) {
		float e[13];
		for (int k = 0; k < 13; k++) e[k] = 0.0;
		vec3 axes[4] = vec3[4](vec3(1, 0, 0), vec3(-1, 0, 0), vec3(0, 0, 1), vec3(0, 0, -1));
		for (int i = 0; i < fix_count; i++) {
			vec4 f = texelFetch(fix_tex, ivec2(i, 0), 0);
			if (distance(f.xy, p) > reach || f.z <= 0.0) continue;
			// 4 × 2 points over the 1.2 × 0.6 m diffuser, shifted per texel so the
			// penumbrae through openings are smooth after the denoise pass.
			vec2 jit = (vec2(fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453), fract(sin(dot(p, vec2(39.3468, 11.135))) * 24634.6345)) - 0.5) * vec2(0.3, 0.3);
			for (int s = 0; s < 8; s++) {
				vec2 q = f.xy + vec2((float(s % 4) - 1.5) * 0.3, s < 4 ? -0.15 : 0.15) + jit;
				if (visible(p, q) < 0.5) continue;
				// dA = panel area / 8; radiance f.z; E += L cos cos dA / d².
				float w = f.z * 0.091875;
				vec3 lp = vec3(q.x, ceiling - 0.01, q.y);
				vec3 v = lp - vec3(p.x, 0.02, p.y);
				float d2 = dot(v, v);
				vec3 o = v * inversesqrt(d2);
				e[0] += w * o.y * o.y / d2;
				for (int h = 0; h < 3; h++) {
					vec3 vh = lp - vec3(p.x, h == 0 ? WALL_H0 : (h == 1 ? WALL_H1 : WALL_H2), p.y);
					float dh = dot(vh, vh);
					vec3 oh = vh * inversesqrt(dh);
					for (int a = 0; a < 4; a++)
						e[1 + h * 4 + a] += w * max(dot(axes[a], oh), 0.0) * oh.y / dh;
				}
			}
		}
		if (tile < 0.5) outv = vec4(e[0], e[1], e[2], e[3]);
		else if (tile < 1.5) outv = vec4(e[4], e[5], e[6], e[7]);
		else if (tile < 2.5) outv = vec4(e[8], e[9], e[10], e[11]);
		else outv = vec4(e[12], 0.0, 0.0, 0.0);
		outv = sqrt(clamp(outv / e_max, 0.0, 1.0));
	}
	if (calibrate) outv = vec4(local / res, tile / 4.0, 1.0);
	COLOR = outv;
}
