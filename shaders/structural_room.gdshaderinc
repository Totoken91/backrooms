// Structural slabs stay distinct from lower lintels/duct roofs. Tiny cell-grid
// metadata keeps their material classification valid at variable heights.
uniform sampler2D room_heights : filter_nearest, repeat_disable;
uniform vec2 room_origin;
uniform bool has_room_heights = false;
float structural_ceiling(vec2 p, float fallback) {
	if (!has_room_heights) return fallback;
	ivec2 c = ivec2(floor((p - room_origin) / 2.5));
	ivec2 extent = textureSize(room_heights, 0);
	if (any(lessThan(c, ivec2(0))) || any(greaterThanEqual(c, extent))) return fallback;
	return texelFetch(room_heights, c, 0).g;
}
