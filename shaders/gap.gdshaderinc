// The room space of a column: from its floor to its ceiling (the gap above
// the column's lowest solid span, see SpanMap), and the three heights where
// the bake stores the light on walls, relative to that space: 0.4 m above
// the floor, 0.3 m under the ceiling and midway (less in low spaces).

vec3 wall_heights(vec2 gap) {
	float h = max(gap.y - gap.x, 0.3);
	float lo = gap.x + min(0.4, 0.25 * h);
	float hi = gap.y - min(0.3, 0.2 * h);
	return vec3(lo, (lo + hi) * 0.5, hi);
}

// Wall irradiance at height y from its values at the three wall heights of
// the space: a quadratic in log space (positive, can rise then fall under the
// ceiling), bounded by the samples so the extrapolation stays tame.
float wall_profile(float e0, float e1, float e2, float y, vec2 gap) {
	vec3 hs = wall_heights(gap);
	float l0 = log(max(e0, 1e-4)), l1 = log(max(e1, 1e-4)), l2 = log(max(e2, 1e-4));
	y = clamp(y, gap.x, gap.y);
	float a0 = (y - hs.y) * (y - hs.z) / ((hs.x - hs.y) * (hs.x - hs.z));
	float a1 = (y - hs.x) * (y - hs.z) / ((hs.y - hs.x) * (hs.y - hs.z));
	float a2 = (y - hs.x) * (y - hs.y) / ((hs.z - hs.x) * (hs.z - hs.y));
	return min(exp(a0 * l0 + a1 * l1 + a2 * l2), max(e0, max(e1, e2)) * 1.15);
}

// Heights stored in 16 bits over two 8-bit channels: -16 .. 48 m, ~1 mm.
vec2 encode_height(float h) {
	float v = floor(clamp((h + 16.0) / 64.0, 0.0, 1.0) * 65535.0 + 0.5);
	return vec2(floor(v / 256.0), mod(v, 256.0)) / 255.0;
}

float decode_height(vec2 c) {
	float v = floor(c.x * 255.0 + 0.5) * 256.0 + floor(c.y * 255.0 + 0.5);
	return v / 65535.0 * 64.0 - 16.0;
}
