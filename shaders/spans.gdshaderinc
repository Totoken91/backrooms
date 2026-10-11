// The level's solid geometry as vertical spans per 0.125 m column (SpanMap):
// span_a holds spans 0-1, span_b spans 2-3, as (y0, y1, y0, y1), unused spans
// at -100. Coordinates are relative to the chunk origin. Outside the map, the
// default room: floor at 0, ceiling at `ceiling`.

uniform sampler2D span_a : filter_nearest, repeat_disable;
uniform sampler2D span_b : filter_nearest, repeat_disable;
uniform vec2 occ_origin;        // column 0, relative to the chunk
uniform float occ_texel = 0.125;
uniform vec2 occ_size;
uniform float ceiling = 2.8;
// The bake renders in horizontal bands, one per frame (LightBaker._draw):
// the rows band_y0 .. band_y0 + band_rows of the tiles.
uniform float band_y0 = 0.0;
uniform float band_rows = 160.0;

// Texel of the tiles drawn at UV (tiles side by side, res × res each).
vec2 bake_cell(vec2 uv, float res, float tiles) {
	return floor(vec2(uv.x * res * tiles, band_y0 + uv.y * band_rows));
}

bool span_overlap(vec4 s, float lo, float hi) {
	return (lo < s.y && hi > s.x) || (lo < s.w && hi > s.z);
}

// Column index of p, or (-1, -1) outside the map.
ivec2 column(vec2 p) {
	vec2 t = (p - occ_origin) / occ_texel;
	if (t.x < 0.0 || t.y < 0.0 || t.x >= occ_size.x || t.y >= occ_size.y) return ivec2(-1);
	return ivec2(t);
}

// Does the vertical segment [lo, hi] of the column at p meet solid geometry?
bool blocked(vec2 p, float lo, float hi) {
	ivec2 c = column(p);
	if (c.x < 0) return lo < 0.0 || hi > ceiling;
	return span_overlap(texelFetch(span_a, c, 0), lo, hi) || span_overlap(texelFetch(span_b, c, 0), lo, hi);
}

// The spans of the column at p (eight heights: a.xyzw, b.xyzw).
void spans_at(vec2 p, out vec4 a, out vec4 b) {
	ivec2 c = column(p);
	if (c.x < 0) {
		a = vec4(-10.0, 0.0, ceiling, 100.0);
		b = vec4(-100.0);
	} else {
		a = texelFetch(span_a, c, 0);
		b = texelFetch(span_b, c, 0);
	}
}

// Floor-level wall test (1 = solid just above the floor), for the receivers.
float occupied(vec2 p) {
	return blocked(p, 0.04, 0.06) ? 1.0 : 0.0;
}

// Is the straight line a → b free of solid geometry? Marches the columns it
// crosses and tests the height interval it spans in each.
float visible(vec3 a, vec3 b) {
	vec3 d = b - a;
	int n = max(1, int(ceil(length(d.xz) / occ_texel)));
	for (int i = 1; i < 128; i++) {
		if (i > n) break;
		float t0 = float(i - 1) / float(n), t1 = float(i) / float(n);
		vec2 q = a.xz + d.xz * (t0 + t1) * 0.5;
		float y0 = a.y + d.y * t0, y1 = a.y + d.y * t1;
		if (blocked(q, min(y0, y1), max(y0, y1))) return 0.0;
	}
	return 1.0;
}
