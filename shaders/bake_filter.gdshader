shader_type canvas_item;
render_mode blend_disabled;
// Light bake, denoise pass: Gaussian blur of a baked chunk (three 160 × 160
// tiles) that does not cross walls: a neighbour counts only if neither it nor
// the midpoint towards it lies in a wall. Removes the ray-pattern noise of the
// jittered direct and gather passes, like a lightmapper's denoiser.

uniform sampler2D src : filter_nearest, repeat_disable;
#include "res://shaders/spans.gdshaderinc"
uniform float texel = 0.25;
uniform float tiles = 3.0;
uniform float res = 160.0;
uniform int radius = 2;
uniform float sigma = 1.2;

void fragment() {
	vec2 cell = bake_cell(UV, res, tiles);
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
			vec4 encoded = texelFetch(src, ivec2(n + vec2(tile * res, 0.0)), 0);
			// Maps store sqrt(irradiance / range). Average energy, not its
			// encoding: averaging square roots darkens noisy/occluded texels.
			sum += encoded * encoded * w;
			wsum += w;
		}
	}
	// Tile 4 holds encoded heights: no blur.
	COLOR = (wsum > 0.0 && tile < 3.5) ? sqrt(sum / wsum) : centre;
}
