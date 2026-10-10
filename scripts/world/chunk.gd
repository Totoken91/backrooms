class_name Chunk
extends Node3D
## One 40 m streaming chunk: meshes, collision and panels built from the shared
## LevelWorld boxes, plus its 32×32 irradiance field (1.25 m texels).

const CELL := LevelWorld.CELL
const CHUNK := LevelWorld.CHUNK
const H := LevelWorld.HEIGHT
const TILE := 0.625
const WALL_UV := 0.6
const FIELD_RES := 32
const LIP := 0.018

var coord: Vector2i
var fixtures: Array = []
var field: Image
var field_ready := false
var build_ms := 0.0
var bake_ms := 0.0

var _world: LevelWorld
var _tools := {}


func setup(world: LevelWorld, p_coord: Vector2i, materials: Dictionary, panel_mesh: Mesh) -> void:
	_world = world
	coord = p_coord
	name = "Chunk_%d_%d" % [coord.x, coord.y]
	var started := Time.get_ticks_usec()
	for key in ["wall", "skirting", "floor", "ceiling"]:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_tools[key] = st
	var body := StaticBody3D.new()
	body.name = "Collision"
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)
	var seen := {}
	var x0 := coord.x * CHUNK
	var z0 := coord.y * CHUNK
	for z in range(z0, z0 + CHUNK):
		for x in range(x0, x0 + CHUNK):
			var boxes: Array = _world.cell_boxes(x, z)
			var covered := 0.0
			for b in boxes:
				if not seen.has(b.id):
					seen[b.id] = true
					_emit_box(b)
					if b.y0 < LevelWorld.BODY_HEIGHT:
						_add_collider(body, b)
				if b.occluder:
					covered += maxf(0.0, minf(b.x1, (x + 1) * CELL) - maxf(b.x0, x * CELL)) * maxf(0.0, minf(b.z1, (z + 1) * CELL) - maxf(b.z0, z * CELL))
			for f in _world.cell_fixtures(x, z):
				fixtures.append(f)
			if covered >= CELL * CELL - 1e-6:
				continue
			_emit_floor_and_ceiling(x, z)
	# Floor collider for the whole chunk: the body stands on it.
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(CHUNK * CELL, 1.0, CHUNK * CELL)
	floor_shape.shape = floor_box
	floor_shape.position = Vector3((x0 + CHUNK * 0.5) * CELL, -0.5, (z0 + CHUNK * 0.5) * CELL)
	body.add_child(floor_shape)
	var mesh := ArrayMesh.new()
	for key in ["wall", "skirting", "floor", "ceiling"]:
		var st: SurfaceTool = _tools[key]
		st.generate_tangents()
		st.commit(mesh)
		mesh.surface_set_material(mesh.get_surface_count() - 1, materials[key])
	var instance := MeshInstance3D.new()
	instance.name = "Geometry"
	instance.mesh = mesh
	add_child(instance)
	_tools.clear()
	_build_panels(panel_mesh)
	build_ms = (Time.get_ticks_usec() - started) / 1000.0


# --- Geometry -------------------------------------------------------------

## Adds a quad with corners in order around its face; triangles are wound so
## that the side facing `normal` is the front face.
func _quad(key: String, a: Vector3, b: Vector3, c: Vector3, d: Vector3, normal: Vector3) -> void:
	var st: SurfaceTool = _tools[key]
	var flip := (b - a).cross(c - a).dot(normal) > 0.0
	var order := [a, c, b, a, d, c] if flip else [a, b, c, a, c, d]
	for p in order:
		st.set_normal(normal)
		st.set_uv(_uv(key, p, normal))
		st.add_vertex(p)


func _uv(key: String, p: Vector3, n: Vector3) -> Vector2:
	if absf(n.y) > 0.5:
		var size := TILE if key == "ceiling" else WALL_UV
		return Vector2(p.x, p.z) / size
	var along := p.x * -n.z + p.z * n.x
	return Vector2(along, -p.y) / WALL_UV


## Face intervals of a box not covered by a touching box at least as tall.
## Every coordinate is a multiple of 0.125 m: comparisons are exact.
func _exposed(b, side: int) -> Array:
	var horizontal := side == 0 or side == 2
	var plane: float = [b.z0, b.x1, b.z1, b.x0][side]
	var t0: float = b.x0 if horizontal else b.z0
	var t1: float = b.x1 if horizontal else b.z1
	var outward := -1e-6 if side == 0 or side == 3 else 1e-6
	var fixed := floori((plane + outward) / CELL)
	var covers := []
	for c in range(floori(t0 / CELL), floori((t1 - 1e-6) / CELL) + 1):
		var others: Array = _world.cell_boxes(c, fixed) if horizontal else _world.cell_boxes(fixed, c)
		for o in others:
			if o == b or o.y0 > b.y0 + 1e-6 or o.y1 < b.y1 - 1e-6:
				continue
			var touching: float = [o.z1, o.x0, o.z0, o.x1][side]
			if absf(touching - plane) > 1e-6:
				continue
			var a: float = maxf(t0, o.x0 if horizontal else o.z0)
			var e: float = minf(t1, o.x1 if horizontal else o.z1)
			if e > a + 1e-6:
				covers.append(Vector2(a, e))
	covers.sort_custom(func(p, q): return p.x < q.x)
	var open := []
	var cursor := t0
	for cv in covers:
		if cv.x > cursor + 1e-6:
			open.append(Vector2(cursor, cv.x))
		cursor = maxf(cursor, cv.y)
	if t1 > cursor + 1e-6:
		open.append(Vector2(cursor, t1))
	return open


func _emit_box(b) -> void:
	for side in 4:
		var n: Vector3 = [Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(-1, 0, 0)][side]
		for span in _exposed(b, side):
			var a: Vector2
			var e: Vector2
			match side:
				0: a = Vector2(span.x, b.z0); e = Vector2(span.y, b.z0)
				1: a = Vector2(b.x1, span.x); e = Vector2(b.x1, span.y)
				2: a = Vector2(span.y, b.z1); e = Vector2(span.x, b.z1)
				_: a = Vector2(b.x0, span.y); e = Vector2(b.x0, span.x)
			var P := func(p: Vector2, y: float, o: float = 0.0) -> Vector3: return Vector3(p.x + n.x * o, y, p.y + n.z * o)
			if b.y0 > 0.0:
				_quad("wall", P.call(a, b.y0), P.call(e, b.y0), P.call(e, b.y1), P.call(a, b.y1), n)
				continue
			_quad("wall", P.call(a, 0.16), P.call(e, 0.16), P.call(e, b.y1), P.call(a, b.y1), n)
			_quad("skirting", P.call(a, 0.0), P.call(e, 0.0), P.call(e, 0.16), P.call(a, 0.16), n)
			_quad("skirting", P.call(a, 0.008, LIP), P.call(e, 0.008, LIP), P.call(e, 0.115, LIP), P.call(a, 0.115, LIP), n)
			_quad("skirting", P.call(a, 0.115), P.call(e, 0.115), P.call(e, 0.115, LIP), P.call(a, 0.115, LIP), Vector3.UP)
			# End caps close the skirting at jambs and outside corners.
			var along := Vector3(e.x - a.x, 0, e.y - a.y).normalized()
			_quad("skirting", P.call(a, 0.008), P.call(a, 0.008, LIP), P.call(a, 0.115, LIP), P.call(a, 0.115), -along)
			_quad("skirting", P.call(e, 0.008), P.call(e, 0.008, LIP), P.call(e, 0.115, LIP), P.call(e, 0.115), along)
	if b.y0 > 0.0:
		_quad("wall", Vector3(b.x0, b.y0, b.z0), Vector3(b.x1, b.y0, b.z0), Vector3(b.x1, b.y0, b.z1), Vector3(b.x0, b.y0, b.z1), Vector3.DOWN)
	if b.y1 < H - 1e-6:
		_quad("wall", Vector3(b.x0, b.y1, b.z0), Vector3(b.x1, b.y1, b.z0), Vector3(b.x1, b.y1, b.z1), Vector3(b.x0, b.y1, b.z1), Vector3.UP)


func _emit_floor_and_ceiling(x: int, z: int) -> void:
	var X := x * CELL
	var Z := z * CELL
	_quad("floor", Vector3(X, 0, Z), Vector3(X + CELL, 0, Z), Vector3(X + CELL, 0, Z + CELL), Vector3(X, 0, Z + CELL), Vector3.UP)
	# Panels replace whole tiles of the world 0.625 m ceiling grid.
	var holes := []
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			for f in _world.cell_fixtures(x + dx, z + dz):
				if f.x1 > X and f.x0 < X + CELL and f.z1 > Z and f.z0 < Z + CELL:
					holes.append(f)
	if holes.is_empty():
		_quad("ceiling", Vector3(X, H, Z), Vector3(X + CELL, H, Z), Vector3(X + CELL, H, Z + CELL), Vector3(X, H, Z + CELL), Vector3.DOWN)
		return
	for j in 4:
		var run := -1
		for i in 5:
			var hole := false
			if i < 4:
				var cx := X + (i + 0.5) * TILE
				var cz := Z + (j + 0.5) * TILE
				for f in holes:
					if cx > f.x0 and cx < f.x1 and cz > f.z0 and cz < f.z1:
						hole = true
						break
				if not hole:
					if run < 0:
						run = i
					continue
			if run >= 0:
				var a := X + run * TILE
				var e := X + i * TILE
				var c := Z + j * TILE
				_quad("ceiling", Vector3(a, H, c), Vector3(e, H, c), Vector3(e, H, c + TILE), Vector3(a, H, c + TILE), Vector3.DOWN)
				run = -1


func _add_collider(body: StaticBody3D, b) -> void:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	var top: float = minf(b.y1, H)
	box.size = Vector3(b.x1 - b.x0, top - b.y0, b.z1 - b.z0)
	shape.shape = box
	shape.position = Vector3((b.x0 + b.x1) * 0.5, (b.y0 + top) * 0.5, (b.z0 + b.z1) * 0.5)
	body.add_child(shape)


func _build_panels(panel_mesh: Mesh) -> void:
	if fixtures.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = panel_mesh
	mm.instance_count = fixtures.size()
	for i in fixtures.size():
		var f = fixtures[i]
		mm.set_instance_transform(i, Transform3D(Basis(), Vector3(f.x, H - 0.006, f.z)))
		mm.set_instance_custom_data(i, Color(0.9, 0, 0, 0))
	var node := MultiMeshInstance3D.new()
	node.name = "Panels"
	node.multimesh = mm
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)


func set_panel_power(index: int, power: float) -> void:
	var node := get_node_or_null("Panels") as MultiMeshInstance3D
	if node:
		node.multimesh.set_instance_custom_data(index, Color(power, 0, 0, 0))


# --- Irradiance field -------------------------------------------------------

## Bakes the chunk's field against the physics colliders of the loaded
## neighbourhood (rays at 1.4 m: lintels are not occluders). Yields to keep
## each frame's share under `slice_ms`.
func bake_field(space: PhysicsDirectSpaceState3D, nearby: Array, slice_ms: float) -> void:
	var started := Time.get_ticks_usec()
	var slice_start := started
	field = Image.create(FIELD_RES, FIELD_RES, false, Image.FORMAT_RGBA8)
	var query := PhysicsRayQueryParameters3D.new()
	query.collision_mask = 1
	var texel := CELL * CHUNK / FIELD_RES
	var bx := coord.x * CHUNK * CELL
	var bz := coord.y * CHUNK * CELL
	for iz in FIELD_RES:
		for ix in FIELD_RES:
			var wx := bx + (ix + 0.5) * texel
			var wz := bz + (iz + 0.5) * texel
			var ao := 1.0
			var sum := 0.0
			if _world.point_blocked(wx, wz):
				var p := _free_point(wx, wz)
				if p == Vector2.INF:
					field.set_pixel(ix, iz, Color(0.08, 0.1, 0.53, 1))
					continue
				wx = p.x
				wz = p.y
			# Contact occlusion from nearby wall boxes (analytic, no rays).
			for cz in range(floori(wz / CELL) - 1, floori(wz / CELL) + 2):
				for cx in range(floori(wx / CELL) - 1, floori(wx / CELL) + 2):
					for b in _world.cell_boxes(cx, cz):
						if not b.occluder:
							continue
						var dx: float = wx - clampf(wx, b.x0, b.x1)
						var dz: float = wz - clampf(wz, b.z0, b.z1)
						ao -= 0.16 * exp(-sqrt(dx * dx + dz * dz) * 3.5)
			var from := Vector3(wx, 1.4, wz)
			for f in nearby:
				var d2: float = ((wx - f.x) * (wx - f.x) + (wz - f.z) * (wz - f.z)) / (CELL * CELL)
				if d2 > 7.0:
					continue
				query.from = from
				query.to = Vector3(f.x, 1.4, f.z)
				if not space.intersect_ray(query).is_empty():
					continue
				sum += (0.76 + float(f.seed % 101) / 101.0 * 0.24) * 0.8 * exp(-d2 * 0.75)
			var radiance := 1.0 - exp(-sum * 1.3)
			var bounce := 0.11
			field.set_pixel(ix, iz, Color(bounce + radiance * 0.6, minf(1.0, bounce * 1.25 + radiance * 0.72), maxf(0.53, ao), 1))
			if Time.get_ticks_usec() - slice_start > slice_ms * 1000.0:
				bake_ms += (Time.get_ticks_usec() - slice_start) / 1000.0
				await get_tree().process_frame
				if not is_inside_tree():
					return
				slice_start = Time.get_ticks_usec()
	bake_ms += (Time.get_ticks_usec() - slice_start) / 1000.0
	field_ready = true


func _free_point(x: float, z: float) -> Vector2:
	var best := Vector2.INF
	var distance := 1.7
	for b in _world.cell_boxes(floori(x / CELL), floori(z / CELL)):
		if not b.occluder or x <= b.x0 or x >= b.x1 or z <= b.z0 or z >= b.z1:
			continue
		for p in [Vector2(b.x0 - 0.02, z), Vector2(b.x1 + 0.02, z), Vector2(x, b.z0 - 0.02), Vector2(x, b.z1 + 0.02)]:
			var d := Vector2(x, z).distance_to(p)
			if d < distance and not _world.point_blocked(p.x, p.y):
				distance = d
				best = p
	return best
