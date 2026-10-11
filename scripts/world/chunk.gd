class_name Chunk
extends Node3D
## One 40 m streaming chunk: meshes, collision and panels built from the shared
## LevelWorld boxes, plus its contact-occlusion map; light is baked on the
## GPU by LightBaker and stored in `direct` / `bounce`.

const CELL := LevelWorld.CELL
const CHUNK := LevelWorld.CHUNK
const H := LevelWorld.HEIGHT
const TILE := LevelWorld.TILE
const WALL_UV := 0.6
const FIELD_RES := 32
const AO_RES := 128
## Falloff length of contact occlusion (m).
const AO_RADIUS := 0.22
const LIP := 0.018

var coord: Vector2i
var fixtures: Array = []
var ao: Image
## Baked light (LightBaker tiles): direct, first gather (one bounce), then
## second gather (indirect light including the light bounced off the ceiling).
var direct := []
var bounce1 := []
var bounce := []
## Bake again after a light change: 1 direct, then 2 first and 3 second
## gather; the current light stays shown until each new pass is ready.
var relight := 0
## Invalidates suspended bake results when a panel changes.
var light_revision := 0
var build_ms := 0.0
var max_slice_ms := 0.0
var built := false
var phases := {}
var bake_ms := 0.0

var _world: LevelWorld
var _tools := {}


## Builds the chunk; with a finite slice_ms the work is spread over frames
## (budget checked after each cell) and `built` turns true at the end.
func setup(world: LevelWorld, p_coord: Vector2i, materials: Dictionary, panel_mesh: Mesh, slice_ms := INF) -> void:
	_world = world
	coord = p_coord
	name = "Chunk_%d_%d" % [coord.x, coord.y]
	var started := Time.get_ticks_usec()
	var slice_start := started
	var busy := 0.0
	for key in ["wall", "skirting", "floor", "ceiling"]:
		_tools[key] = [[], [], [], []]
	var body := StaticBody3D.new()
	body.name = "Collision"
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)
	var solids := []
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
						solids.append(b)
				# Only boxes filling the room's height hide the floor and ceiling (a
				# duct roof or a raised floor leaves one of them visible).
				if b.occluder and b.y0 <= 1e-6 and b.y1 >= H - 1e-6:
					covered += maxf(0.0, minf(b.x1, (x + 1) * CELL) - maxf(b.x0, x * CELL)) * maxf(0.0, minf(b.z1, (z + 1) * CELL) - maxf(b.z0, z * CELL))
			for f in _world.cell_fixtures(x, z):
				fixtures.append(f)
			if covered < CELL * CELL - 1e-6:
				_emit_floor_and_ceiling(x, z)
			if Time.get_ticks_usec() - slice_start > slice_ms * 1000.0:
				var elapsed := (Time.get_ticks_usec() - slice_start) / 1000.0
				busy += elapsed
				max_slice_ms = maxf(max_slice_ms, elapsed)
				await get_tree().process_frame
				if not is_inside_tree():
					return
				slice_start = Time.get_ticks_usec()
	phases.geometry = busy + (Time.get_ticks_usec() - slice_start) / 1000.0
	_add_colliders(body, solids)
	phases.collision = busy + (Time.get_ticks_usec() - slice_start) / 1000.0 - phases.geometry
	# Floor collider for the whole chunk: the body stands on it.
	_add_box_shape(body, Vector3(CHUNK * CELL, 1.0, CHUNK * CELL), Vector3((x0 + CHUNK * 0.5) * CELL, -0.5, (z0 + CHUNK * 0.5) * CELL))
	var mesh := ArrayMesh.new()
	for key in ["wall", "skirting", "floor", "ceiling"]:
		var data: Array = _tools[key]
		if data[0].is_empty():
			continue
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array(data[0])
		arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array(data[1])
		arrays[Mesh.ARRAY_TANGENT] = PackedFloat32Array(data[2])
		arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array(data[3])
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(mesh.get_surface_count() - 1, materials[key])
	phases.mesh = busy + (Time.get_ticks_usec() - slice_start) / 1000.0 - phases.geometry - phases.collision
	var instance := MeshInstance3D.new()
	instance.name = "Geometry"
	instance.mesh = mesh
	add_child(instance)
	_tools.clear()
	_build_panels(panel_mesh)
	max_slice_ms = maxf(max_slice_ms, (Time.get_ticks_usec() - slice_start) / 1000.0)
	build_ms = busy + (Time.get_ticks_usec() - slice_start) / 1000.0
	built = true


# --- Geometry -------------------------------------------------------------

## Adds a quad with corners in order around its face; triangles are wound so
## that the side facing `normal` is the front face.
## Faces are axis-aligned, so tangents follow from the UV mapping of _uv.
## `shade`: normal stored for lighting when it differs from the face's own
## (winding and UVs follow `normal`).
func _quad(key: String, a: Vector3, b: Vector3, c: Vector3, d: Vector3, normal: Vector3, shade := Vector3.ZERO) -> void:
	var data: Array = _tools[key]
	var verts: Array = data[0]
	var normals: Array = data[1]
	var tangents: Array = data[2]
	var uvs: Array = data[3]
	var flip := (b - a).cross(c - a).dot(normal) > 0.0
	var order := [a, c, b, a, d, c] if flip else [a, b, c, a, c, d]
	var t: Vector3
	var w: float
	if absf(normal.y) > 0.5:
		t = Vector3.RIGHT
		w = -1.0 if normal.y > 0.0 else 1.0
	else:
		t = Vector3(-normal.z, 0.0, normal.x)
		w = 1.0
	for p in order:
		verts.append(p)
		normals.append(normal if shade == Vector3.ZERO else shade)
		tangents.append(t.x)
		tangents.append(t.y)
		tangents.append(t.z)
		tangents.append(w)
		uvs.append(_uv(key, p, normal))


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
			var A := Vector3(a.x, 0.0, a.y)
			var E := Vector3(e.x, 0.0, e.y)
			var up := Vector3.UP
			if b.y0 > 0.0:
				_quad("wall", A + up * b.y0, E + up * b.y0, E + up * b.y1, A + up * b.y1, n)
				continue
			var lip := n * LIP
			_quad("wall", A + up * 0.16, E + up * 0.16, E + up * b.y1, A + up * b.y1, n)
			_quad("skirting", A, E, E + up * 0.16, A + up * 0.16, n)
			_quad("skirting", A + up * 0.008 + lip, E + up * 0.008 + lip, E + up * 0.115 + lip, A + up * 0.115 + lip, n)
			_quad("skirting", A + up * 0.115, E + up * 0.115, E + up * 0.115 + lip, A + up * 0.115 + lip, up)
			# End caps close the skirting at jambs and outside corners. They are lit
			# like their wall: lit along the wall's axis they would show as dashes.
			var along := (E - A).normalized()
			_quad("skirting", A + up * 0.008, A + up * 0.008 + lip, A + up * 0.115 + lip, A + up * 0.115, -along, n)
			_quad("skirting", E + up * 0.008, E + up * 0.008 + lip, E + up * 0.115 + lip, E + up * 0.115, along, n)
	if b.y0 > 0.0:
		_quad("wall", Vector3(b.x0, b.y0, b.z0), Vector3(b.x1, b.y0, b.z0), Vector3(b.x1, b.y0, b.z1), Vector3(b.x0, b.y0, b.z1), Vector3.DOWN)
	if b.y1 < H - 1e-6:
		_quad("wall", Vector3(b.x0, b.y1, b.z0), Vector3(b.x1, b.y1, b.z0), Vector3(b.x1, b.y1, b.z1), Vector3(b.x0, b.y1, b.z1), Vector3.UP)


func _emit_floor_and_ceiling(x: int, z: int) -> void:
	var X := x * CELL
	var Z := z * CELL
	_quad("floor", Vector3(X, 0, Z), Vector3(X + CELL, 0, Z), Vector3(X + CELL, 0, Z + CELL), Vector3(X, 0, Z + CELL), Vector3.UP)
	# Panels replace whole tiles of the ceiling grid (3 × 3 tiles per cell).
	var holes := []
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			for f in _world.cell_fixtures(x + dx, z + dz):
				if f.x1 > X and f.x0 < X + CELL and f.z1 > Z and f.z0 < Z + CELL:
					holes.append(f)
	if holes.is_empty():
		_quad("ceiling", Vector3(X, H, Z), Vector3(X + CELL, H, Z), Vector3(X + CELL, H, Z + CELL), Vector3(X, H, Z + CELL), Vector3.DOWN)
		return
	var n := int(round(CELL / TILE))
	for j in n:
		var run := -1
		for i in n + 1:
			var hole := false
			if i < n:
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


## Shape owners instead of nodes; contiguous full-height boxes on the same
## rows merge, so a maze row of solid cells becomes one shape.
func _add_colliders(body: StaticBody3D, boxes: Array) -> void:
	boxes.sort_custom(func(p, q): return p.z0 < q.z0 or (p.z0 == q.z0 and (p.z1 < q.z1 or (p.z1 == q.z1 and p.x0 < q.x0))))
	var run = null
	for b in boxes:
		var full: bool = b.y0 <= 0.0 and b.y1 >= H
		if run != null and full and run[4] and run[1] == b.z0 and run[3] == b.z1 and absf(run[2] - b.x0) < 1e-6:
			run[2] = b.x1
			continue
		if run != null:
			_flush(body, run)
		run = [b.x0, b.z0, b.x1, b.z1, full, b.y0, minf(b.y1, H)]
	if run != null:
		_flush(body, run)


func _flush(body: StaticBody3D, r: Array) -> void:
	_add_box_shape(body, Vector3(r[2] - r[0], r[6] - r[5], r[3] - r[1]), Vector3((r[0] + r[2]) * 0.5, (r[5] + r[6]) * 0.5, (r[1] + r[3]) * 0.5))


func _add_box_shape(body: StaticBody3D, size: Vector3, center: Vector3) -> void:
	var box := BoxShape3D.new()
	box.size = size
	var owner := body.create_shape_owner(body)
	body.shape_owner_add_shape(owner, box)
	body.shape_owner_set_transform(owner, Transform3D(Basis(), center))


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
		mm.set_instance_custom_data(i, Color(0.0 if _world.panels_off.has(f.id) else PanelLights.power(0.0, f.seed, true), 0, 0, 0))
	var node := MultiMeshInstance3D.new()
	node.name = "Panels"
	node.multimesh = mm
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)


func set_panel_power(index: int, power: float) -> void:
	var node := get_node_or_null("Panels") as MultiMeshInstance3D
	if node:
		node.multimesh.set_instance_custom_data(index, Color(power, 0, 0, 0))


# --- Contact occlusion ----------------------------------------------------

## Fine contact occlusion, 0.3125 m texels: exact distance to the full-height
## wall boxes (only those: the junctions of floor and walls), summed so inner
## corners darken more than straight walls.
func bake_ao(slice_ms: float) -> void:
	var slice_start := Time.get_ticks_usec()
	ao = Image.create(AO_RES, AO_RES, false, Image.FORMAT_L8)
	var texel := CELL * CHUNK / AO_RES
	var bx := coord.x * CHUNK * CELL
	var bz := coord.y * CHUNK * CELL
	for iz in AO_RES:
		var wz := bz + (iz + 0.5) * texel
		for ix in AO_RES:
			var wx := bx + (ix + 0.5) * texel
			var occ := 0.0
			var cx0 := floori((wx - 1.0) / CELL)
			var cz0 := floori((wz - 1.0) / CELL)
			for cz in range(cz0, floori((wz + 1.0) / CELL) + 1):
				for cx in range(cx0, floori((wx + 1.0) / CELL) + 1):
					for b in _world.cell_boxes(cx, cz):
						if not b.occluder or b.y0 > 1e-6 or b.y1 < H - 1e-6:
							continue
						var dx: float = wx - clampf(wx, b.x0, b.x1)
						var dz: float = wz - clampf(wz, b.z0, b.z1)
						occ += exp(-sqrt(dx * dx + dz * dz) / AO_RADIUS)
			ao.set_pixel(ix, iz, Color.from_hsv(0, 0, clampf(1.0 - occ * 0.3, 0.0, 1.0)))
		if Time.get_ticks_usec() - slice_start > slice_ms * 1000.0:
			bake_ms += (Time.get_ticks_usec() - slice_start) / 1000.0
			await get_tree().process_frame
			if not is_inside_tree():
				return
			slice_start = Time.get_ticks_usec()
	bake_ms += (Time.get_ticks_usec() - slice_start) / 1000.0
