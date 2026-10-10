class_name Hashing
## Specified 32-bit integer hashes. GDScript ints are 64-bit: every result is
## masked back to an unsigned 32-bit value so the world is reproducible.

const MASK := 0xFFFFFFFF


static func u32(x: int) -> int:
	return x & MASK


## Low 32 bits of a product, like JavaScript's Math.imul (64-bit wraparound
## keeps the low word exact).
static func imul(a: int, b: int) -> int:
	return (a * b) & MASK


static func mix(h: int) -> int:
	h = u32(h)
	h ^= h >> 16
	h = imul(h, 0x7feb352d)
	h ^= h >> 15
	h = imul(h, 0x846ca68b)
	h ^= h >> 16
	return h


static func text(s: String) -> int:
	var h := 0x811c9dc5
	for c in s.to_utf8_buffer():
		h ^= c
		h = imul(h, 0x01000193)
	return h


## One independent domain per decision: (seed, version, domain, ids...).
static func channel(seed: int, version_hash: int, domain: String, ids: Array = []) -> int:
	var h := mix(u32(seed) ^ 0x9e3779b9)
	h = mix(h ^ version_hash)
	h = mix(h ^ text(domain))
	for id in ids:
		h = mix(h ^ u32(int(id)))
	return h


## Cell hash of the classic maze, valid for negative coordinates.
static func cell(seed: int, x: int, z: int, salt: int = 0) -> int:
	var h := imul(x, 374761393) ^ imul(z, 668265263) ^ u32(seed) ^ u32(salt)
	h = imul(h ^ (h >> 13), 1274126177)
	return u32(h ^ (h >> 16))
