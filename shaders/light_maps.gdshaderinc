// Baked light of the streamed chunks, one layer set per chunk slot (the
// chunk coordinates modulo SLOTS), so finishing a bake uploads only that
// chunk's layers. light_maps holds MAPS layers per slot (LightBaker layout:
// 0-3 direct, 4 room space (floor and ceiling heights), 5-7 first gather,
// 8-10 displayed indirect), ao_maps one.
// slot_chunk tells which chunk a slot currently holds; elsewhere: no light.

uniform sampler2DArray light_maps : filter_linear, repeat_disable;
uniform sampler2DArray ao_maps : filter_linear, repeat_disable;
uniform vec2 slot_chunk[49];

const float CHUNK_SIZE = 40.0;
const float SLOTS = 7.0;
const int MAPS = 11;

// Slot of the chunk containing xz (world metres), or -1 if not loaded; uv
// inside the chunk.
int light_slot(vec2 xz, out vec2 uv) {
	vec2 c = floor(xz / CHUNK_SIZE);
	vec2 s = mod(c, SLOTS);
	int slot = int(s.x + s.y * SLOTS);
	uv = (xz - c * CHUNK_SIZE) / CHUNK_SIZE;
	if (distance(slot_chunk[slot], c) > 0.5) return -1;
	return slot;
}

vec4 light_map(int map, vec2 xz) {
	vec2 uv;
	int s = light_slot(xz, uv);
	if (s < 0) return vec4(0.0);
	return texture(light_maps, vec3(uv, float(s * MAPS + map)));
}

// Room space (floor, ceiling heights) of the column at xz; the default room
// where no chunk is loaded.
vec2 gap_map(vec2 xz, float default_ceiling) {
	vec2 uv;
	int s = light_slot(xz, uv);
	if (s < 0) return vec2(0.0, default_ceiling);
	// Read at the texel centre: the (linear) filter then returns the texel
	// itself, as the encoded heights need. (One texture cannot be bound with
	// two filters in the Compatibility renderer: the filter is texture state.)
	vec2 res = vec2(textureSize(light_maps, 0).xy);
	vec2 centre = (floor(uv * res) + 0.5) / res;
	vec4 c = texture(light_maps, vec3(centre, float(s * MAPS + 4)));
	return vec2(decode_height(c.xy), decode_height(c.zw));
}

float ao_map(vec2 xz) {
	vec2 uv;
	int s = light_slot(xz, uv);
	if (s < 0) return 1.0;
	return texture(ao_maps, vec3(uv, float(s))).r;
}
