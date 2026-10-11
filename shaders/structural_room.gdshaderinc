// Structural slabs stay distinct from lower lintels/duct roofs. Tiny cell-grid
// metadata keeps their material classification valid at variable heights.
uniform sampler2D room_heights : filter_nearest, repeat_disable;
uniform vec2 room_origin;
uniform bool has_room_heights = false;
// Surface rendering uses bounded per-chunk metadata; bake passes retain
// their local SpanMap metadata. Separate ownership avoids reading an old slot.
uniform bool streamed_room_heights = false;
uniform sampler2DArray chunk_room_heights : filter_nearest, repeat_disable;
uniform vec2 room_slot_chunk[49];
float structural_ceiling(vec2 p, float fallback) {
	if (streamed_room_heights) {
		vec2 chunk = floor(p / 40.0);
		vec2 ring = mod(chunk, 7.0);
		int slot = int(ring.x + ring.y * 7.0);
		if (distance(room_slot_chunk[slot], chunk) > 0.5) return fallback;
		ivec2 cell = ivec2(floor((p - chunk * 40.0) / 2.5));
		return texelFetch(chunk_room_heights, ivec3(cell, slot), 0).g;
	}
	if (!has_room_heights) return fallback;
	ivec2 c = ivec2(floor((p - room_origin) / 2.5));
	ivec2 extent = textureSize(room_heights, 0);
	if (any(lessThan(c, ivec2(0))) || any(greaterThanEqual(c, extent))) return fallback;
	return texelFetch(room_heights, c, 0).g;
}
