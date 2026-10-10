shader_type canvas_item;
render_mode blend_disabled;
// Light bake, denoise pass: Gaussian blur of a baked chunk (three 160 × 160
// tiles) that does not cross walls: a neighbour counts only if neither it nor
// the midpoint towards it lies in a wall. Removes the ray-pattern noise of the
// jittered direct and gather passes, like a lightmapper's denoiser.

uniform sampler2D src : filter_nearest, repeat_disable;
uniform sampler2D occ_tex : filter_nearest, repeat_disable;
uniform vec2 occ_origin;
uniform float occ_texel = 0.125;
uniform vec2 occ_size;
uniform float texel = 0.25;
uniform float tiles = 3.0;
uniform float res = 160.0;
uniform int radius = 2;
uniform float sigma = 1.2;

float occupied(vec2 p) {
	vec2 t = (p - occ_origin) / occ_texel;
	if (t.x < 0.0 || t.y < 0.0 || t.x >= occ_size.x || t.y >= occ_size.y) return 0.0;
	return texelFetch(occ_tex, ivec2(t), 0).r;
}

void fragment() {
	vec2 cell = floor(UV * vec2(res * tiles, res));
	float tile = floor(cell.x / res);
	vec2 local = vec2(mod(cell.x, res), cell.y);
	vec2 p = (local + 0.5) * texel;
	vec4 centre = texelFetch(src, ivec2(cell), 0);
	vec4 sum = vec4(0.0);
	float wsum = 0.0;
	bool inside = occupied(p) > 0.5;
	for (int dy = -radius; dy <= radius; dy++) {
		for (int dx = -radius; dx <= radius; dx++) {
			vec2 n = local + vec2(float(dx), float(dy));
			if (n.x < 0.0 || n.y < 0.0 || n.x >= res || n.y >= res) continue;
			vec2 q = (n + 0.5) * texel;
			if (!inside && (occupied(q) > 0.5 || occupied((p + q) * 0.5) > 0.5)) continue;
			float w = exp(-float(dx * dx + dy * dy) / (2.0 * sigma * sigma));
			sum += texelFetch(src, ivec2(n + vec2(tile * res, 0.0)), 0) * w;
			wsum += w;
		}
	}
	COLOR = wsum > 0.0 ? sum / wsum : centre;
}
