// Baked light of the streamed chunks, one layer set per chunk slot (the
// chunk coordinates modulo SLOTS), so finishing a bake uploads only that
// chunk's layers. light_maps holds MAPS layers per slot (LightBaker layout:
// 0-3 direct, 4-6 first gather, 7-9 displayed indirect), ao_maps one.
// slot_chunk tells which chunk a slot currently holds; elsewhere: no light.

uniform sampler2DArray light_maps : filter_linear, repeat_disable;
uniform sampler2DArray ao_maps : filter_linear, repeat_disable;
uniform vec2 slot_chunk[49];

const float CHUNK_SIZE = 40.0;
const float SLOTS = 7.0;
const int MAPS = 10;

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

float ao_map(vec2 xz) {
	vec2 uv;
	int s = light_slot(xz, uv);
	if (s < 0) return 1.0;
	return texture(ao_maps, vec3(uv, float(s))).r;
}
