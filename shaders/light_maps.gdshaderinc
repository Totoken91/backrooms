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

// A tap just outside a layer belongs to the adjacent world chunk, not the
// clamped edge of this array layer. Check ownership before reading reused slots.
vec4 chunk_tap(sampler2DArray maps, int stride, int map, vec2 chunk, ivec2 p, ivec2 res, int owner) {
	vec2 delta = floor(vec2(p) / vec2(res));
	vec2 unused_uv;
	int neighbour = light_slot((chunk + delta + 0.5) * CHUNK_SIZE, unused_uv);
	if (neighbour < 0) {
		return texelFetch(maps, ivec3(clamp(p, ivec2(0), res - 1), owner * stride + map), 0);
	}
	ivec2 local = p - ivec2(delta) * res;
	return texelFetch(maps, ivec3(local, neighbour * stride + map), 0);
}

vec4 chunk_sample(sampler2DArray maps, int stride, int map, vec2 xz, vec4 missing) {
	vec2 uv;
	int s = light_slot(xz, uv);
	if (s < 0) return missing;
	ivec2 res = textureSize(maps, 0).xy;
	vec2 pixel = uv * vec2(res) - 0.5;
	// Keep the ordinary single filtered lookup everywhere except the border.
	if (all(greaterThanEqual(pixel, vec2(0.0))) && all(lessThanEqual(pixel, vec2(res - 1)))) {
		return texture(maps, vec3(uv, float(s * stride + map)));
	}
	ivec2 p = ivec2(floor(pixel));
	vec2 f = fract(pixel);
	vec2 chunk = floor(xz / CHUNK_SIZE);
	vec4 a = chunk_tap(maps, stride, map, chunk, p, res, s);
	vec4 b = chunk_tap(maps, stride, map, chunk, p + ivec2(1, 0), res, s);
	vec4 c = chunk_tap(maps, stride, map, chunk, p + ivec2(0, 1), res, s);
	vec4 d = chunk_tap(maps, stride, map, chunk, p + ivec2(1, 1), res, s);
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

vec4 light_map(int map, vec2 xz) {
	return chunk_sample(light_maps, MAPS, map, xz, vec4(0.0));
}

// Transport needs interpolation of energy. The stored values are square
// roots: squaring a hardware-filtered sample loses energy at every contrast
// edge. Decode each tap first, then interpolate the linear irradiance.
vec4 light_energy(int map, vec2 xz) {
	vec2 uv;
	int s = light_slot(xz, uv);
	if (s < 0) return vec4(0.0);
	ivec2 res = textureSize(light_maps, 0).xy;
	vec2 pixel = uv * vec2(res) - 0.5;
	ivec2 p = ivec2(floor(pixel));
	vec2 f = fract(pixel);
	vec4 a, b, c, d;
	if (all(greaterThanEqual(p, ivec2(0))) && all(lessThan(p + 1, res))) {
		int layer = s * MAPS + map;
		a = texelFetch(light_maps, ivec3(p, layer), 0);
		b = texelFetch(light_maps, ivec3(p + ivec2(1, 0), layer), 0);
		c = texelFetch(light_maps, ivec3(p + ivec2(0, 1), layer), 0);
		d = texelFetch(light_maps, ivec3(p + ivec2(1, 1), layer), 0);
	} else {
		vec2 chunk = floor(xz / CHUNK_SIZE);
		a = chunk_tap(light_maps, MAPS, map, chunk, p, res, s);
		b = chunk_tap(light_maps, MAPS, map, chunk, p + ivec2(1, 0), res, s);
		c = chunk_tap(light_maps, MAPS, map, chunk, p + ivec2(0, 1), res, s);
		d = chunk_tap(light_maps, MAPS, map, chunk, p + ivec2(1, 1), res, s);
	}
	return mix(mix(a * a, b * b, f.x), mix(c * c, d * d, f.x), f.y);
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
	return chunk_sample(ao_maps, 1, 0, xz, vec4(1.0)).r;
}
