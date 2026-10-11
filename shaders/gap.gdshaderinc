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
// the space: reconstruct source-distance falloff, with log-space fallback.
// Bound extrapolation by the stored samples to avoid unstable peaks.
float wall_profile(float e0, float e1, float e2, float y, vec2 gap, float emitter_y) {
	vec3 hs = wall_heights(gap);
	y = clamp(y, gap.x, gap.y);
	float bound = max(e0, max(e1, e2)) * 1.15;
	// A downward emitter gives a vertical receiver E = A*d/(r²+d²)²,
	// d being the vertical separation. Thus sqrt(d/E) is linear in d²
	// for a point emitter and smooth for an area emitter. Reconstruct that
	// quantity instead of log(E), whose slope diverges at the source plane.
	// Shadowed/zero samples retain the conservative legacy interpolation.
	if (min(e0, min(e1, e2)) > 1e-5 && emitter_y > hs.z) {
		vec3 d = vec3(emitter_y) - hs;
		vec3 x = d * d;
		vec3 q = sqrt(d / vec3(e0, e1, e2));
		float dy = max(emitter_y - y, 0.0);
		float at = dy * dy;
		float q0 = (at - x.y) * (at - x.z) / ((x.x - x.y) * (x.x - x.z));
		float q1 = (at - x.x) * (at - x.z) / ((x.y - x.x) * (x.y - x.z));
		float q2 = (at - x.x) * (at - x.y) / ((x.z - x.x) * (x.z - x.y));
		float denominator = dot(q, vec3(q0, q1, q2));
		if (denominator > 1e-4) return min(dy / (denominator * denominator), bound);
	}
	float l0 = log(max(e0, 1e-4)), l1 = log(max(e1, 1e-4)), l2 = log(max(e2, 1e-4));
	float a0 = (y - hs.y) * (y - hs.z) / ((hs.x - hs.y) * (hs.x - hs.z));
	float a1 = (y - hs.x) * (y - hs.z) / ((hs.y - hs.x) * (hs.y - hs.z));
	float a2 = (y - hs.x) * (y - hs.y) / ((hs.z - hs.x) * (hs.z - hs.y));
	return min(exp(a0 * l0 + a1 * l1 + a2 * l2), bound);
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
