class_name LevelWorld
extends RefCounted
## Level 0 world description. Geometry is axis-aligned boxes in metres, shared
## by meshing, collision and lighting. The 2.5 m cell is only a spatial index
## and the unit of the classic baseline maze.
##
## Generator "level0-godot.1": the classic maze everywhere, except a reserved
## 17.5 m site at the origin holding the C01 composition (spawn). Site exits
## always face odd maze cells, which the maze spanning tree reaches.

const CELL := 2.5
const CHUNK := 16
const HEIGHT := 2.8
const VERSION := "level0-godot.1"
const BODY_HEIGHT := 1.9
const SITE := Rect2i(2, 2, 7, 7)
const DIRS := [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
const EPS := 1e-6


class Box:
	extends RefCounted
	var id: String
	var kind: String
	var x0: float
	var z0: float
	var x1: float
	var z1: float
	var y0: float = 0.0
	var y1: float = HEIGHT
	var occluder := true

	func _init(p_id: String, p_kind: String, a: float, b: float, c: float, d: float) -> void:
		id = p_id
		kind = p_kind
		x0 = a
		z0 = b
		x1 = c
		z1 = d


class Fixture:
	extends RefCounted
	var id: String
	var x: float
	var z: float
	var x0: float
	var z0: float
	var x1: float
	var z1: float
	var y: float = HEIGHT
	var seed: int


var seed: int
var version_hash := Hashing.text(VERSION)
var spawn: Dictionary
var views := {}
var composition_report := {}
var site_grid: PackedByteArray

var _chunks := {}
var _maze_boxes := {}
var _maze_fixtures := {}
var _site_index := {}
var _site_fixture_index := {}
var _site_boxes: Array[Box] = []
var _site_fixtures: Array[Fixture] = []


func _init(p_seed: int) -> void:
	seed = Hashing.u32(p_seed)
	_build_site()


static func fresh_seed(previous := -1) -> int:
	var crypto := Crypto.new()
	var bytes := crypto.generate_random_bytes(4)
	var value := bytes.decode_u32(0)
	if value == previous:
		value = Hashing.u32(value + 0x9e3779b9)
	return value


func hash_cell(x: int, z: int, salt: int = 0) -> int:
	return Hashing.cell(seed, x, z, salt)


func channel(domain: String, ids: Array = []) -> int:
	return Hashing.channel(seed, version_hash, domain, ids)


# --- Classic maze -----------------------------------------------------------

func _in_site(cx: int, cz: int, x: int, z: int) -> bool:
	return cx == 0 and cz == 0 and SITE.has_point(Vector2i(x, z))


var _rng := 1


func _random() -> float:
	_rng = Hashing.u32(_rng ^ (_rng << 13))
	_rng ^= _rng >> 17
	_rng = Hashing.u32(_rng ^ (_rng << 5))
	return float(_rng) / 4294967296.0


## Cells of a chunk: 0 open maze, 1 solid maze, 2 reserved site.
func chunk_at(cx: int, cz: int) -> PackedByteArray:
	var key := Vector2i(cx, cz)
	if _chunks.has(key):
		return _chunks[key]
	_rng = hash_cell(cx, cz, 3107)
	if _rng == 0:
		_rng = 1
	var cells: Array[int] = []
	cells.resize(CHUNK * CHUNK)
	cells.fill(1)
	var stack: Array[Vector2i] = [Vector2i(1, 1)]
	cells[CHUNK + 1] = 0
	# A connected one-cell circulation spine; it goes around the reserved site.
	while not stack.is_empty():
		var p: Vector2i = stack[-1]
		var choices: Array[int] = []
		for d in 4:
			var n: Vector2i = p + DIRS[d] * 2
			if n.x > 0 and n.y > 0 and n.x < CHUNK and n.y < CHUNK and cells[n.y * CHUNK + n.x] == 1 and not _in_site(cx, cz, n.x, n.y):
				choices.append(d)
		if choices.is_empty():
			stack.pop_back()
			continue
		var d: int = choices[int(_random() * choices.size())]
		var mid: Vector2i = p + DIRS[d]
		var n2: Vector2i = p + DIRS[d] * 2
		cells[mid.y * CHUNK + mid.x] = 0
		cells[n2.y * CHUNK + n2.x] = 0
		stack.append(n2)
	# Edge contract: hashed left/top openings meet the neighbours' odd cells.
	cells[(1 + 2 * (hash_cell(cx, cz, 101) % 8)) * CHUNK] = 0
	cells[1 + 2 * (hash_cell(cx, cz, 202) % 8)] = 0
	var rooms: Array[Rect2i] = []
	if cx == 0 and cz == 0:
		rooms.append(SITE)
	var reserved := rooms.size()
	for attempt in 80:
		if rooms.size() - reserved >= 3:
			break
		var w := 3 + int(_random() * 4)
		var h := 3 + int(_random() * 4)
		var x := 1 + int(_random() * (CHUNK - w - 1))
		var z := 1 + int(_random() * (CHUNK - h - 1))
		var candidate := Rect2i(x, z, w, h)
		var clash := false
		for r in rooms:
			if candidate.grow(1).intersects(r):
				clash = true
				break
		if clash:
			continue
		rooms.append(candidate)
		for dz in h:
			for dx in w:
				cells[(z + dz) * CHUNK + x + dx] = 0
	for z in CHUNK:
		for x in CHUNK:
			if _in_site(cx, cz, x, z):
				cells[z * CHUNK + x] = 2
	_clean(cells)
	var packed := PackedByteArray(cells)
	_chunks[key] = packed
	return packed


static func _interior(x: int, z: int) -> bool:
	return x > 0 and z > 0 and x < CHUNK - 1 and z < CHUNK - 1


static func _solid(cells: Array[int], n: int) -> int:
	return 1 if cells[n] != 0 else 0


static func _solid_neighbours(cells: Array[int], n: int) -> int:
	var s := 0
	for d in DIRS:
		s += _solid(cells, (n / CHUNK + d.y) * CHUNK + n % CHUNK + d.x)
	return s


static func _remove_fragments(cells: Array[int]) -> void:
	var seen := PackedByteArray()
	seen.resize(CHUNK * CHUNK)
	for k in CHUNK * CHUNK:
		if cells[k] == 0 or seen[k]:
			continue
		var component: Array[int] = [k]
		seen[k] = 1
		var anchored := false
		var i := 0
		while i < component.size():
			var n: int = component[i]
			i += 1
			var x := n % CHUNK
			var z := n / CHUNK
			if not _interior(x, z) or cells[n] == 2:
				anchored = true
			for d in DIRS:
				var nx: int = x + d.x
				var nz: int = z + d.y
				if nx < 0 or nz < 0 or nx >= CHUNK or nz >= CHUNK:
					continue
				var j := nz * CHUNK + nx
				if cells[j] != 0 and not seen[j]:
					seen[j] = 1
					component.append(j)
		if not anchored and component.size() < 3:
			for n in component:
				cells[n] = 0


## Removes tiny wall islands and diagonal-only contacts; never touches the
## chunk boundary contract or the reserved site.
static func _clean(cells: Array[int]) -> void:
	_remove_fragments(cells)
	var cleaned := true
	var pass_count := 0
	while cleaned and pass_count < CHUNK * CHUNK:
		pass_count += 1
		cleaned = false
		for z in CHUNK - 1:
			for x in CHUNK - 1:
				var a := z * CHUNK + x
				var b := a + 1
				var c := a + CHUNK
				var dd := c + 1
				if _solid(cells, a) == _solid(cells, dd) and _solid(cells, b) == _solid(cells, c) and _solid(cells, a) != _solid(cells, b):
					var best := -1
					for n in ([a, dd] if _solid(cells, a) else [b, c]):
						if not _interior(n % CHUNK, n / CHUNK) or cells[n] == 2:
							continue
						if best < 0 or _solid_neighbours(cells, n) < _solid_neighbours(cells, best) or (_solid_neighbours(cells, n) == _solid_neighbours(cells, best) and n < best):
							best = n
					if best < 0:
						continue
					cells[best] = 0
					cleaned = true
		if cleaned:
			_remove_fragments(cells)


func cell_kind(x: int, z: int) -> int:
	var cx := floori(float(x) / CHUNK)
	var cz := floori(float(z) / CHUNK)
	return chunk_at(cx, cz)[(z - cz * CHUNK) * CHUNK + x - cx * CHUNK]


func is_open(x: int, z: int) -> bool:
	return cell_kind(x, z) == 0


func prune(cx: int, cz: int, keep := 4) -> void:
	for key in _chunks.keys():
		if absi(key.x - cx) > keep or absi(key.y - cz) > keep:
			_chunks.erase(key)
	for cache in [_maze_boxes, _maze_fixtures]:
		for key in cache.keys():
			if absi(floori(float(key.x) / CHUNK) - cx) > keep or absi(floori(float(key.y) / CHUNK) - cz) > keep:
				cache.erase(key)


# --- C01 site -----------------------------------------------------------------

func _build_site() -> void:
	var w := int(SITE.size.x * CELL / Compositions.Q)
	var d := int(SITE.size.y * CELL / Compositions.Q)
	var pick := func(domain: String, n: int) -> int: return channel("C01." + domain) % n
	var c := Compositions.c01(pick, w, d)
	var resolved := Compositions.resolve(c, w, d)
	site_grid = resolved.grid
	var ox := SITE.position.x * CELL
	var oz := SITE.position.y * CELL
	var Q := Compositions.Q
	var i := 0
	for r in resolved.boxes:
		var b := Box.new("s%d" % i, "wall", ox + r[0] * Q, oz + r[1] * Q, ox + r[2] * Q, oz + r[3] * Q)
		_site_boxes.append(b)
		i += 1
	i = 0
	for l in c.lintels:
		var r: Array = l.rect
		var b := Box.new("l%d" % i, "lintel", ox + r[0] * Q, oz + r[1] * Q, ox + r[2] * Q, oz + r[3] * Q)
		b.y0 = l.y0
		b.y1 = l.y1
		b.occluder = false
		_site_boxes.append(b)
		i += 1
	for f in resolved.fixtures:
		var r: Array = f.rect
		var fx := Fixture.new()
		fx.id = "c%d" % f.key
		fx.x0 = ox + r[0] * Q
		fx.z0 = oz + r[1] * Q
		fx.x1 = ox + r[2] * Q
		fx.z1 = oz + r[3] * Q
		fx.x = (fx.x0 + fx.x1) * 0.5
		fx.z = (fx.z0 + fx.z1) * 0.5
		fx.seed = channel("C01.fixtures", [f.key])
		_site_fixtures.append(fx)
	for b in _site_boxes:
		for z in range(floori(b.z0 / CELL), floori((b.z1 - EPS) / CELL) + 1):
			for x in range(floori(b.x0 / CELL), floori((b.x1 - EPS) / CELL) + 1):
				var k := Vector2i(x, z)
				if not _site_index.has(k):
					_site_index[k] = []
				_site_index[k].append(b)
	for f in _site_fixtures:
		var k := Vector2i(floori(f.x / CELL), floori(f.z / CELL))
		if not _site_fixture_index.has(k):
			_site_fixture_index[k] = []
		_site_fixture_index[k].append(f)
	for key in c.views:
		var v: Dictionary = c.views[key]
		views[key] = {"position": Vector3(ox + v.x * Q, 0.0, oz + v.z * Q), "yaw": v.yaw, "label": v.label}
	spawn = views[c.spawn]
	var exits := []
	for f in c.free:
		if f.has("exit"):
			var r: Array = f.rect
			exits.append({"name": f.name, "side": f.exit, "x0": ox + r[0] * Q, "z0": oz + r[1] * Q, "x1": ox + r[2] * Q, "z1": oz + r[3] * Q})
	composition_report = {"id": c.id, "name": c.name, "variant": c.variant, "exits": exits,
		"site": Rect2(ox, oz, SITE.size.x * CELL, SITE.size.y * CELL), "boxes": _site_boxes.size(), "fixtures": _site_fixtures.size()}


# --- Queries ------------------------------------------------------------------

## Boxes overlapping index cell (x, z). Maze cells are one 2.5 m box each.
func cell_boxes(x: int, z: int) -> Array:
	var kind := cell_kind(x, z)
	if kind == 2:
		return _site_index.get(Vector2i(x, z), [])
	if kind != 1:
		return []
	var k := Vector2i(x, z)
	if not _maze_boxes.has(k):
		_maze_boxes[k] = [Box.new("m%d,%d" % [x, z], "wall", x * CELL, z * CELL, (x + 1) * CELL, (z + 1) * CELL)]
	return _maze_boxes[k]


## Classic panels sit on odd/odd open cells; site panels come from C01.
func cell_fixtures(x: int, z: int) -> Array:
	var kind := cell_kind(x, z)
	if kind == 2:
		return _site_fixture_index.get(Vector2i(x, z), [])
	if kind != 0 or posmod(x, 2) != 1 or posmod(z, 2) != 1 or hash_cell(x, z, 303) % 7 == 0:
		return []
	var k := Vector2i(x, z)
	if _maze_fixtures.has(k):
		return _maze_fixtures[k]
	var f := Fixture.new()
	f.id = "f%d,%d" % [x, z]
	f.x0 = x * CELL + 0.625
	f.z0 = z * CELL + 1.25
	f.x1 = x * CELL + 1.875
	f.z1 = z * CELL + 1.875
	f.x = (f.x0 + f.x1) * 0.5
	f.z = (f.z0 + f.z1) * 0.5
	f.seed = hash_cell(x, z, 1407)
	_maze_fixtures[k] = [f]
	return _maze_fixtures[k]


func point_blocked(x: float, z: float) -> bool:
	for b in cell_boxes(floori(x / CELL), floori(z / CELL)):
		if b.occluder and x > b.x0 and x < b.x1 and z > b.z0 and z < b.z1:
			return true
	return false


func circle_blocked(x: float, z: float, r: float, height := BODY_HEIGHT) -> bool:
	for cz in range(floori((z - r) / CELL), floori((z + r) / CELL) + 1):
		for cx in range(floori((x - r) / CELL), floori((x + r) / CELL) + 1):
			for b in cell_boxes(cx, cz):
				if b.y0 >= height:
					continue
				var dx: float = x - clampf(x, b.x0, b.x1)
				var dz: float = z - clampf(z, b.z0, b.z1)
				if dx * dx + dz * dz < r * r - 1e-10:
					return true
	return false


static func _slab(ax: float, az: float, dx: float, dz: float, b: Box) -> float:
	var t0 := 0.0
	var t1 := 1.0
	if absf(dx) < 1e-9:
		if ax < b.x0 or ax > b.x1:
			return INF
	else:
		var p := (b.x0 - ax) / dx
		var r := (b.x1 - ax) / dx
		t0 = maxf(t0, minf(p, r))
		t1 = minf(t1, maxf(p, r))
		if t0 > t1:
			return INF
	if absf(dz) < 1e-9:
		if az < b.z0 or az > b.z1:
			return INF
	else:
		var p := (b.z0 - az) / dz
		var r := (b.z1 - az) / dz
		t0 = maxf(t0, minf(p, r))
		t1 = minf(t1, maxf(p, r))
		if t0 > t1:
			return INF
	return t0


## First full-height occluder along a→b as a fraction of the segment (2D).
func raycast(ax: float, az: float, bx: float, bz: float) -> float:
	var dx := bx - ax
	var dz := bz - az
	var best := INF
	var x := floori(ax / CELL)
	var z := floori(az / CELL)
	var ex := floori(bx / CELL)
	var ez := floori(bz / CELL)
	var sx := 1 if dx > 0 else -1
	var sz := 1 if dz > 0 else -1
	var tdx := INF if absf(dx) < 1e-9 else absf(CELL / dx)
	var tdz := INF if absf(dz) < 1e-9 else absf(CELL / dz)
	var tx := INF if absf(dx) < 1e-9 else ((x + 1) * CELL - ax if dx > 0 else ax - x * CELL) / absf(dx)
	var tz := INF if absf(dz) < 1e-9 else ((z + 1) * CELL - az if dz > 0 else az - z * CELL) / absf(dz)
	for n in 256:
		for b in cell_boxes(x, z):
			if b.occluder:
				best = minf(best, _slab(ax, az, dx, dz, b))
		if best <= minf(minf(tx, tz), 1.0):
			return best
		if x == ex and z == ez:
			break
		if absf(tx - tz) < 1e-12:
			for b in cell_boxes(x + sx, z) + cell_boxes(x, z + sz):
				if b.occluder:
					best = minf(best, _slab(ax, az, dx, dz, b))
			x += sx
			z += sz
			tx += tdx
			tz += tdz
		elif tx < tz:
			x += sx
			tx += tdx
		else:
			z += sz
			tz += tdz
	return best


func segment_blocked(ax: float, az: float, bx: float, bz: float) -> bool:
	return raycast(ax, az, bx, bz) < 1.0
