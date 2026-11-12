class_name TerrainWorld
extends Node3D

const CHUNK := 32

var field: Soil.Field
var spec: Dictionary = {}
var mat: ShaderMaterial
var height_img: Image
var height_tex: ImageTexture
var disturb_img: Image
var disturb_tex: ImageTexture
var color_tex: Texture2D
var grain_tex: Texture2D
var chunks: Dictionary = {}
var built_lod: Dictionary = {}
var dirty: Dictionary = {}
var focus := Vector3.ZERO
var collision_dirty := true
var window_origin := Vector2i(-99999, -99999)
var ground: StaticBody3D
var shape: HeightMapShape3D
var water: MeshInstance3D
var apron: MeshInstance3D
var patch: Soil.Patch
var ring: Soil.Field
var ring_mask: PackedByteArray
var ring_origin := Vector2.ZERO
var ring_far: MeshInstance3D
var ring_near: MeshInstance3D
var ring_near_at := Vector2(-1.0e9, -1.0e9)
var fine_mesh: MeshInstance3D
var punched: Array = []
var fine_img: Image
var fine_tex: ImageTexture
const WINDOW := 97
const COL_SPACING := 0.5

func setup(next_spec: Dictionary, albedo: Texture2D, grain: Texture2D) -> void:
	spec = next_spec
	color_tex = albedo
	grain_tex = grain
	_clear()
	var cols: int = spec["cols"]
	var rows: int = spec["rows"]
	var bytes := FileAccess.get_file_as_bytes("res://data/%s" % spec["heights"])
	field = Soil.Field.new()
	field.cols = cols
	field.rows = rows
	field.spacing = float(spec["spacing"])
	field.heights = bytes.to_float32_array()
	field.disturb = PackedByteArray()
	field.disturb.resize(cols * rows)
	field.changed = PackedInt32Array()
	_build_height_texture()
	_build_disturb_texture()
	mat = ShaderMaterial.new()
	mat.shader = load("res://shaders/ground.gdshader")
	var span := float(spec["cols"] - 1) * field.spacing
	patch = Soil.Patch.new(field)
	fine_img = Image.create(Soil.Patch.N, Soil.Patch.N, false, Image.FORMAT_L8)
	fine_img.fill(Color(0, 0, 0))
	fine_tex = ImageTexture.create_from_image(fine_img)
	fine_mesh = MeshInstance3D.new()
	fine_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(fine_mesh)
	_bind_ground(span)
	_build_collision()
	_build_apron()
	_build_water()
	_load_ring()
	var spawn := Vector3(float(spec["spawn"][0]), 0.0, float(spec["spawn"][1]))
	ensure_patch(Vector2(spawn.x, spawn.z))
	rebuild_around(spawn)
	_build_ring(spawn)


func sample(x: float, z: float) -> float:
	if patch != null and patch.covers(x, z):
		return patch.sample(x, z)
	var span := _detail_span()
	var in_detail := x >= 0.0 and z >= 0.0 and x <= span and z <= span
	if in_detail:
		var fine := _coarse_sample(x, z)
		var edge := minf(minf(x, z), minf(span - x, span - z))
		if ring != null and edge < 220.0:
			return lerpf(_ring_at(x, z), fine, clampf(edge / 220.0, 0.0, 1.0))
		return fine
	if ring != null:
		return _ring_at(x, z)
	if spec.get("water") != null:
		return float(spec["water"]) - 8.0
	return _coarse_sample(clampf(x, 0.0, span), clampf(z, 0.0, span))


func water_depth(x: float, z: float) -> float:
	if spec.get("water") == null:
		return -1.0
	return float(spec["water"]) + 0.35 - sample(x, z)


func _detail_span() -> float:
	return float(field.cols - 1) * field.spacing


func _coarse_sample(x: float, z: float) -> float:
	var spacing := field.spacing
	var c := clampf(x / spacing, 0.0, float(field.cols - 1))
	var r := clampf(z / spacing, 0.0, float(field.rows - 1))
	var c0 := int(floor(c))
	var r0 := int(floor(r))
	var c1 := mini(c0 + 1, field.cols - 1)
	var r1 := mini(r0 + 1, field.rows - 1)
	var tx := c - float(c0)
	var tz := r - float(r0)
	var h00: float = field.heights[field.index(c0, r0)]
	var h10: float = field.heights[field.index(c1, r0)]
	var h01: float = field.heights[field.index(c0, r1)]
	var h11: float = field.heights[field.index(c1, r1)]
	return lerp(lerp(h00, h10, tx), lerp(h01, h11, tx), tz)


func cut_blade(east: float, north: float, fx: float, fz: float, width: float, edge_y: float, repose: float) -> float:
	ensure_patch(Vector2(east, north))
	var moved: float = Soil.plane_blade(patch.field, east - patch.origin.x, north - patch.origin.y, fx, fz, width, edge_y, repose)
	if moved > 0.0:
		_flush_fine()
	return moved


func ensure_patch(focus: Vector2) -> void:
	if patch == null:
		return
	if patch.recenter(focus):
		fine_img.fill(Color(0, 0, 0))
		fine_tex.update(fine_img)
		_sync_patch_uniforms()
		_rebuild_fine()
		_punch_coarse()
		collision_dirty = true


func _bind_ground(span: float) -> void:
	mat.set_shader_parameter("sentinel", color_tex)
	mat.set_shader_parameter("gravel_alb", load("res://assets/textures/sandy_gravel_02_Diffuse.jpg"))
	mat.set_shader_parameter("gravel_nrm", load("res://assets/textures/sandy_gravel_02_nor_gl.jpg"))
	mat.set_shader_parameter("rock_alb", load("res://assets/textures/rocky_terrain_Diffuse.jpg"))
	mat.set_shader_parameter("rock_nrm", load("res://assets/textures/rocky_terrain_nor_gl.jpg"))
	mat.set_shader_parameter("forest_alb", load("res://assets/textures/forest_floor_Diffuse.jpg"))
	mat.set_shader_parameter("forest_nrm", load("res://assets/textures/forest_floor_nor_gl.jpg"))
	mat.set_shader_parameter("leaves_alb", load("res://assets/textures/forest_leaves_03_Diffuse.jpg"))
	mat.set_shader_parameter("shore_alb", load("res://assets/textures/coast_sand_01_Diffuse.jpg"))
	mat.set_shader_parameter("mud_alb", load("res://assets/textures/brown_mud_Diffuse.jpg"))
	mat.set_shader_parameter("mud_nrm", load("res://assets/textures/brown_mud_nor_gl.jpg"))
	mat.set_shader_parameter("disturb_map", disturb_tex)
	mat.set_shader_parameter("fine_cut", fine_tex)
	mat.set_shader_parameter("height_range", Vector2(float(spec["hmin"]), float(spec["hmax"])))
	mat.set_shader_parameter("tile_m", Vector2(span, span))
	mat.set_shader_parameter("forest", 1.0 if bool(spec.get("forest", false)) else 0.0)
	var water_y := -1000.0
	if spec["water"] != null:
		water_y = float(spec["water"])
	mat.set_shader_parameter("water_y", water_y)
	_sync_patch_uniforms()


func _sync_patch_uniforms() -> void:
	if patch == null or mat == null:
		return
	mat.set_shader_parameter("patch_origin", patch.origin)
	mat.set_shader_parameter("patch_size", patch.size_m())
	mat.set_shader_parameter("patch_live", 1.0 if patch.live else 0.0)


func _flush_fine() -> void:
	var n := Soil.Patch.N
	var cell := Soil.Patch.CELL
	for i in patch.field.changed:
		var c := i % n
		var r := int(i / n)
		var py := n - 1 - r
		fine_img.set_pixel(c, py, Color(1, 1, 1))
		var x := patch.origin.x + float(c) * cell
		var z := patch.origin.y + float(r) * cell
		var cc := clampi(int(x / field.spacing), 0, field.cols - 1)
		var rr := clampi(int(z / field.spacing), 0, field.rows - 1)
		_paint_disturb(cc, rr)
	patch.field.changed = PackedInt32Array()
	fine_tex.update(fine_img)
	disturb_tex.update(disturb_img)
	_rebuild_fine()
	collision_dirty = true


func _rebuild_fine() -> void:
	if patch == null or not patch.live:
		return
	var n := Soil.Patch.N
	var cell := Soil.Patch.CELL
	var positions := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var span := float(field.cols - 1) * field.spacing
	positions.resize(n * n)
	normals.resize(n * n)
	uvs.resize(n * n)
	var heights := patch.field.heights
	for r in n:
		for c in n:
			var x := patch.origin.x + float(c) * cell
			var z := patch.origin.y + float(r) * cell
			var idx := r * n + c
			positions[idx] = Vector3(x, heights[idx], z)
			uvs[idx] = Vector2(clampf(x / span, 0.0, 1.0), clampf(z / span, 0.0, 1.0))
			var h: float = heights[idx]
			var hl: float = heights[idx - 1] if c > 0 else h
			var hr: float = heights[idx + 1] if c + 1 < n else h
			var hd: float = heights[idx - n] if r > 0 else h
			var hu: float = heights[idx + n] if r + 1 < n else h
			normals[idx] = Vector3(hl - hr, cell * 2.0, hd - hu).normalized()
	var quads := (n - 1) * (n - 1)
	indices.resize(quads * 6)
	var w := 0
	for r in n - 1:
		for c in n - 1:
			var a := r * n + c
			var b := a + 1
			var d := a + n
			var e := d + 1
			indices[w] = a
			indices[w + 1] = b
			indices[w + 2] = d
			indices[w + 3] = b
			indices[w + 4] = e
			indices[w + 5] = d
			w += 6
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = positions
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, mat)
	fine_mesh.mesh = mesh


func _under_patch(c: int, r: int) -> bool:
	if patch == null or not patch.live:
		return false
	var x := float(c) * field.spacing
	var z := float(r) * field.spacing
	var inset := 2.0
	var lx := x - patch.origin.x
	var lz := z - patch.origin.y
	var size := patch.size_m()
	return lx > inset and lz > inset and lx < size - inset and lz < size - inset


func _punch_coarse() -> void:
	if patch == null or not patch.live:
		return
	var spacing := field.spacing
	var c0 := int(patch.origin.x / spacing / float(CHUNK))
	var r0 := int(patch.origin.y / spacing / float(CHUNK))
	var c1 := int((patch.origin.x + patch.size_m()) / spacing / float(CHUNK))
	var r1 := int((patch.origin.y + patch.size_m()) / spacing / float(CHUNK))
	var next := {}
	for y in range(r0, r1 + 1):
		for x in range(c0, c1 + 1):
			next[Vector2i(x, y)] = true
	for key in punched:
		if not next.has(key) and chunks.has(key):
			_build_chunk(key, _lod_for(_chunk_center(key)))
	for key in next.keys():
		if chunks.has(key):
			_build_chunk(key, _lod_for(_chunk_center(key)))
	punched = next.keys()


func refresh_edits() -> void:
	if field.changed.is_empty():
		return
	var seen := {}
	for i in field.changed:
		var c := i % field.cols
		var r := int(i / field.cols)
		_paint_disturb(c, r)
		_paint_height(c, r)
		var key := Vector2i(int(c / CHUNK), int(r / CHUNK))
		dirty[key] = true
		seen[i] = true
	field.changed = PackedInt32Array()
	disturb_tex.update(disturb_img)
	height_tex.update(height_img)
	collision_dirty = true
	for key in dirty.keys():
		_build_chunk(key, _lod_for(_chunk_center(key)))
	dirty.clear()


func _process(_dt: float) -> void:
	_stream(focus)
	_update_collision(focus)
	if ring != null and ring_near_at.distance_to(Vector2(focus.x, focus.z)) > 700.0:
		_build_ring_near(focus)


func _clear() -> void:
	for key in chunks.keys():
		var node: Node = chunks[key]
		node.queue_free()
	chunks.clear()
	built_lod.clear()
	dirty.clear()
	if water:
		water.queue_free()
		water = null
	if fine_mesh:
		fine_mesh.queue_free()
		fine_mesh = null
	if ring_far:
		ring_far.queue_free()
		ring_far = null
	if ring_near:
		ring_near.queue_free()
		ring_near = null
	ring = null
	ring_mask = PackedByteArray()
	if apron:
		apron.queue_free()
		apron = null
	if ground:
		ground.queue_free()
		ground = null
	window_origin = Vector2i(-99999, -99999)


func _build_height_texture() -> void:
	var cols := field.cols
	var rows := field.rows
	var span := float(spec["hmax"]) - float(spec["hmin"])
	var raw := PackedByteArray()
	raw.resize(cols * rows * 3)
	for r in rows:
		var src := rows - 1 - r
		for c in cols:
			var h: float = field.heights[src * cols + c]
			var u := int(clampf((h - float(spec["hmin"])) / span, 0.0, 1.0) * 65535.0)
			var i := (r * cols + c) * 3
			raw[i] = (u >> 8) & 255
			raw[i + 1] = u & 255
			raw[i + 2] = 0
	height_img = Image.create_from_data(cols, rows, false, Image.FORMAT_RGB8, raw)
	height_tex = ImageTexture.create_from_image(height_img)


func _build_disturb_texture() -> void:
	disturb_img = Image.create(1024, 1024, false, Image.FORMAT_L8)
	disturb_img.fill(Color(0, 0, 0))
	disturb_tex = ImageTexture.create_from_image(disturb_img)


func _paint_disturb(c: int, r: int) -> void:
	var u := float(c) / float(field.cols - 1)
	var v := float(r) / float(field.rows - 1)
	var x := u * float(disturb_img.get_width())
	var y := (1.0 - v) * float(disturb_img.get_height())
	var px := clampi(int(x), 1, disturb_img.get_width() - 2)
	var py := clampi(int(y), 1, disturb_img.get_height() - 2)
	disturb_img.fill_rect(Rect2i(px - 1, py - 1, 3, 3), Color(1, 1, 1))


func _paint_height(c: int, r: int) -> void:
	var span := float(spec["hmax"]) - float(spec["hmin"])
	var h: float = field.heights[field.index(c, r)]
	var u := int(clampf((h - float(spec["hmin"])) / span, 0.0, 1.0) * 65535.0)
	var img_r := field.rows - 1 - r
	height_img.set_pixel(c, img_r, Color((u >> 8) / 255.0, (u & 255) / 255.0, 0.0))


func _build_collision() -> void:
	ground = StaticBody3D.new()
	ground.collision_layer = 1
	ground.collision_mask = 0
	shape = HeightMapShape3D.new()
	var col := CollisionShape3D.new()
	col.shape = shape
	col.scale = Vector3(field.spacing, 1.0, field.spacing)
	ground.add_child(col)
	add_child(ground)


func _update_collision(focus_pos: Vector3) -> void:
	if shape == null:
		return
	var span := float(WINDOW - 1) * COL_SPACING
	var ox := clampf(focus_pos.x - span * 0.5, 0.0, float(field.cols - 1) * field.spacing - span)
	var oz := clampf(focus_pos.z - span * 0.5, 0.0, float(field.rows - 1) * field.spacing - span)
	ox = snappedf(ox, COL_SPACING)
	oz = snappedf(oz, COL_SPACING)
	var origin := Vector2i(int(ox * 10.0), int(oz * 10.0))
	if origin == window_origin and not collision_dirty:
		return
	window_origin = origin
	collision_dirty = false
	var data := PackedFloat32Array()
	data.resize(WINDOW * WINDOW)
	for j in WINDOW:
		var z := oz + float(j) * COL_SPACING
		for i in WINDOW:
			var x := ox + float(i) * COL_SPACING
			data[j * WINDOW + i] = sample(x, z)
	shape.map_width = WINDOW
	shape.map_depth = WINDOW
	shape.map_data = data
	var col := ground.get_child(0) as CollisionShape3D
	if col:
		col.scale = Vector3(COL_SPACING, 1.0, COL_SPACING)
	ground.position = Vector3(ox + span * 0.5, 0.0, oz + span * 0.5)


func _build_water() -> void:
	if spec["water"] == null:
		return
	var span := float(field.cols - 1) * field.spacing
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var y := float(spec["water"]) + 0.35
	# Wide enough that the horizon is water from the island's high ground.
	var reach := 90000.0
	var pts := [
		Vector3(-reach, y, -reach),
		Vector3(span + reach, y, -reach),
		Vector3(-reach, y, span + reach),
		Vector3(span + reach, y, span + reach),
	]
	for p in pts:
		st.set_uv(Vector2(p.x / span, p.z / span))
		st.add_vertex(p)
	st.add_index(0)
	st.add_index(2)
	st.add_index(1)
	st.add_index(1)
	st.add_index(2)
	st.add_index(3)
	st.generate_normals()
	water = MeshInstance3D.new()
	water.mesh = st.commit()
	var wmat := ShaderMaterial.new()
	wmat.shader = load("res://shaders/water.gdshader")
	wmat.set_shader_parameter("height_map", height_tex)
	wmat.set_shader_parameter("height_range", Vector2(float(spec["hmin"]), float(spec["hmax"])))
	wmat.set_shader_parameter("water_y", y)
	wmat.set_shader_parameter("tile_m", Vector2(span, span))
	wmat.set_shader_parameter("tile_origin", Vector2.ZERO)
	wmat.set_shader_parameter("wave_nrm", load("res://assets/textures/brown_mud_nor_gl.jpg"))
	water.material_override = wmat
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(water)


func _build_apron() -> void:
	var spacing := field.spacing
	var cols := field.cols
	var rows := field.rows
	var span := float(cols - 1) * spacing
	var reach := 480.0
	var step := 24.0
	var outer := float(spec["outer_m"])
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var grid := int(ceil((span + reach * 2.0) / step))
	var origin := -reach
	var ids := {}
	var positions: Array[Vector3] = []
	for gy in range(grid + 1):
		for gx in range(grid + 1):
			var x := origin + float(gx) * step
			var z := origin + float(gy) * step
			var inside := x >= 0.0 and z >= 0.0 and x <= span and z <= span
			if inside and x > step and z > step and x < span - step and z < span - step:
				continue
			var h := outer
			if x >= 0.0 and z >= 0.0 and x <= span and z <= span:
				h = sample(x, z)
			else:
				var ex := clampf(x, 0.0, span)
				var ez := clampf(z, 0.0, span)
				var edge := sample(ex, ez)
				var dist := Vector2(x - ex, z - ez).length()
				h = lerp(edge, outer, clampf(dist / reach, 0.0, 1.0))
			ids[Vector2i(gx, gy)] = positions.size()
			positions.append(Vector3(x, h, z))
	for gy in grid:
		for gx in grid:
			var keys := [Vector2i(gx, gy), Vector2i(gx + 1, gy), Vector2i(gx, gy + 1), Vector2i(gx + 1, gy + 1)]
			if not ids.has(keys[0]) or not ids.has(keys[1]) or not ids.has(keys[2]) or not ids.has(keys[3]):
				continue
			var a: int = ids[keys[0]]
			var b: int = ids[keys[1]]
			var d: int = ids[keys[2]]
			var e: int = ids[keys[3]]
			for idx in [a, d, b, b, d, e]:
				var p: Vector3 = positions[idx]
				st.set_uv(Vector2(clampf(p.x / span, 0.0, 1.0), clampf(p.z / span, 0.0, 1.0)))
				st.add_vertex(p)
	st.generate_normals()
	apron = MeshInstance3D.new()
	apron.mesh = st.commit()
	apron.material_override = mat
	apron.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(apron)


func rebuild_around(pos: Vector3) -> void:
	focus = pos
	_stream(pos)
	_update_collision(pos)


func _stream(pos: Vector3) -> void:
	var spacing := field.spacing
	var cc := int(clampf(pos.x / spacing, 0.0, float(field.cols - 1)) / float(CHUNK))
	var cr := int(clampf(pos.z / spacing, 0.0, float(field.rows - 1)) / float(CHUNK))
	var keep := {}
	for y in range(cr - 14, cr + 15):
		for x in range(cc - 14, cc + 15):
			if x < 0 or y < 0:
				continue
			if x * CHUNK >= field.cols or y * CHUNK >= field.rows:
				continue
			var key := Vector2i(x, y)
			if _inside_patch(_chunk_center(key)):
				continue
			keep[key] = true
			var lod := _lod_for(_chunk_center(key))
			if built_lod.get(key, -1) != lod or dirty.has(key):
				_build_chunk(key, lod)
	var drop: Array = []
	for key in chunks.keys():
		if not keep.has(key):
			drop.append(key)
	for key in drop:
		chunks[key].queue_free()
		chunks.erase(key)
		built_lod.erase(key)


func _inside_patch(center: Vector3) -> bool:
	if patch == null or not patch.live:
		return false
	var inset := 6.0
	return center.x > patch.origin.x + inset and center.z > patch.origin.y + inset and center.x < patch.origin.x + patch.size_m() - inset and center.z < patch.origin.y + patch.size_m() - inset


func _lod_for(center: Vector3) -> int:
	var dist := Vector2(center.x - focus.x, center.z - focus.z).length()
	if dist < 240.0:
		return 1
	if dist < 720.0:
		return 2
	if dist < 1600.0:
		return 4
	return 8


func _chunk_center(key: Vector2i) -> Vector3:
	var spacing := field.spacing
	var x := (float(key.x) + 0.5) * float(CHUNK) * spacing
	var z := (float(key.y) + 0.5) * float(CHUNK) * spacing
	return Vector3(x, 0.0, z)


func _build_chunk(key: Vector2i, stride: int) -> void:
	var c0 := key.x * CHUNK
	var r0 := key.y * CHUNK
	var c1 := mini(field.cols - 1, c0 + CHUNK)
	var r1 := mini(field.rows - 1, r0 + CHUNK)
	if c1 <= c0 or r1 <= r0:
		return
	var cs := _steps(c0, c1, stride)
	var rs := _steps(r0, r1, stride)
	var positions := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var lookup := {}
	var cols_f := float(field.cols - 1)
	var rows_f := float(field.rows - 1)
	var spacing := field.spacing
	var add := func(c: int, r: int, drop: float) -> int:
		var id := (r * field.cols + c) * 2 + (1 if drop < 0.0 else 0)
		if lookup.has(id):
			return int(lookup[id])
		var idx := positions.size()
		lookup[id] = idx
		var px := float(c) * spacing
		var pz := float(r) * spacing
		positions.append(Vector3(px, field.height_at(c, r) + drop, pz))
		uvs.append(Vector2(float(c) / cols_f, float(r) / rows_f))
		var step_n := maxi(stride, 1)
		var hl: float = field.height_at(c - step_n, r)
		var hr: float = field.height_at(c + step_n, r)
		var hd: float = field.height_at(c, r - step_n)
		var hu: float = field.height_at(c, r + step_n)
		var nrm := Vector3(hl - hr, float(step_n) * spacing * 2.0, hd - hu).normalized()
		if drop < 0.0:
			nrm = Vector3(0.0, 0.35, 0.0).normalized()
		normals.append(nrm)
		return idx
	for j in range(rs.size() - 1):
		for i in range(cs.size() - 1):
			if _under_patch(cs[i], rs[j]) and _under_patch(cs[i + 1], rs[j]) and _under_patch(cs[i], rs[j + 1]) and _under_patch(cs[i + 1], rs[j + 1]):
				continue
			var a: int = add.call(cs[i], rs[j], 0.0)
			var b: int = add.call(cs[i + 1], rs[j], 0.0)
			var d: int = add.call(cs[i], rs[j + 1], 0.0)
			var e: int = add.call(cs[i + 1], rs[j + 1], 0.0)
			indices.append_array(PackedInt32Array([a, b, d, b, e, d]))
	if _needs_skirt(key, Vector2i(0, -1)):
		_skirt(add, indices, cs, r0, true)
	if _needs_skirt(key, Vector2i(0, 1)):
		_skirt(add, indices, cs, r1, true)
	if _needs_skirt(key, Vector2i(-1, 0)):
		_skirt(add, indices, rs, c0, false)
	if _needs_skirt(key, Vector2i(1, 0)):
		_skirt(add, indices, rs, c1, false)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = positions
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, mat)
	var node: MeshInstance3D = chunks.get(key)
	if node == null:
		node = MeshInstance3D.new()
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		add_child(node)
		chunks[key] = node
	node.mesh = mesh
	built_lod[key] = stride


func _steps(a: int, b: int, stride: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	var v := a
	while v < b:
		out.append(v)
		v += stride
	if out.is_empty() or out[out.size() - 1] != b:
		out.append(b)
	return out


func _needs_skirt(key: Vector2i, dir: Vector2i) -> bool:
	var nkey := key + dir
	var max_x := int((field.cols - 1) / CHUNK)
	var max_y := int((field.rows - 1) / CHUNK)
	if nkey.x < 0 or nkey.y < 0 or nkey.x > max_x or nkey.y > max_y:
		return true
	return _lod_for(_chunk_center(nkey)) > _lod_for(_chunk_center(key))


func _skirt(add: Callable, indices: PackedInt32Array, line: PackedInt32Array, fixed: int, horizontal: bool) -> void:
	for i in range(line.size() - 1):
		var p0: int = line[i]
		var p1: int = line[i + 1]
		var c0 := p0 if horizontal else fixed
		var r0 := fixed if horizontal else p0
		var c1 := p1 if horizontal else fixed
		var r1 := fixed if horizontal else p1
		var a: int = add.call(c0, r0, 0.0)
		var b: int = add.call(c1, r1, 0.0)
		var d: int = add.call(c0, r0, -10.0)
		var e: int = add.call(c1, r1, -10.0)
		indices.append_array(PackedInt32Array([a, b, d, b, e, d]))


func _load_ring() -> void:
	if not spec.has("ring"):
		return
	var info: Dictionary = spec["ring"]
	ring = Soil.Field.new()
	ring.cols = int(info["cols"])
	ring.rows = int(info["rows"])
	ring.spacing = float(info["spacing"])
	ring.heights = FileAccess.get_file_as_bytes("res://data/%s" % str(info["heights"])).to_float32_array()
	ring.disturb = PackedByteArray()
	ring.changed = PackedInt32Array()
	ring_mask = FileAccess.get_file_as_bytes("res://data/%s" % str(info["mask"]))
	ring_origin = Vector2(float(info["origin"][0]), float(info["origin"][1]))
	print("ring ", ring.cols, "x", ring.rows, " from ", ring_origin)


func _ring_at(x: float, z: float) -> float:
	var water := float(spec["water"]) if spec.get("water") != null else 0.0
	var cf := (x - ring_origin.x) / ring.spacing - 0.5
	var rf := (z - ring_origin.y) / ring.spacing - 0.5
	if cf < 0.0 or rf < 0.0 or cf > float(ring.cols - 1) or rf > float(ring.rows - 1):
		return water - 12.0
	var c0 := int(floor(cf))
	var r0 := int(floor(rf))
	var c1 := mini(c0 + 1, ring.cols - 1)
	var r1 := mini(r0 + 1, ring.rows - 1)
	if ring_mask[r0 * ring.cols + c0] == 0 and ring_mask[r1 * ring.cols + c1] == 0:
		return water - 12.0
	var tx := cf - float(c0)
	var tz := rf - float(r0)
	var h00: float = ring.heights[r0 * ring.cols + c0]
	var h10: float = ring.heights[r0 * ring.cols + c1]
	var h01: float = ring.heights[r1 * ring.cols + c0]
	var h11: float = ring.heights[r1 * ring.cols + c1]
	return lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), tz)


func _build_ring(focus_pos: Vector3) -> void:
	if ring == null:
		return
	focus = focus_pos
	_build_ring_mesh(8, 0.0, 1.0e9, "far")
	_build_ring_near(focus_pos)


func _build_ring_near(focus_pos: Vector3) -> void:
	ring_near_at = Vector2(focus_pos.x, focus_pos.z)
	focus = focus_pos
	_build_ring_mesh(1, 0.0, 5200.0, "near")


func _build_ring_mesh(stride: int, min_dist: float, max_dist: float, which: String) -> void:
	var positions := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var span := _detail_span()
	var spacing := ring.spacing
	var cols := ring.cols
	var rows := ring.rows
	var lookup := {}
	var add := func(c: int, r: int) -> int:
		var key := r * cols + c
		if lookup.has(key):
			return int(lookup[key])
		var idx := positions.size()
		lookup[key] = idx
		var x := ring_origin.x + (float(c) + 0.5) * spacing
		var z := ring_origin.y + (float(r) + 0.5) * spacing
		var h: float = ring.heights[key]
		if c < 0 or r < 0 or c >= cols or r >= rows or ring_mask[key] == 0:
			h = float(spec["water"]) - 2.0
		positions.append(Vector3(x, h, z))
		uvs.append(Vector2(x / span, z / span))
		return idx
	var r_start := 0
	var r_end := rows - 1
	var c_start := 0
	var c_end := cols - 1
	if max_dist < 1.0e8:
		var cf := (focus.x - ring_origin.x) / spacing
		var rf := (focus.z - ring_origin.y) / spacing
		var rad := int(max_dist / spacing) + stride * 2
		c_start = clampi(int(cf) - rad, 0, cols - 2)
		c_end = clampi(int(cf) + rad, 1, cols - 1)
		r_start = clampi(int(rf) - rad, 0, rows - 2)
		r_end = clampi(int(rf) + rad, 1, rows - 1)
	var r := r_start
	while r < r_end:
		var r2 := mini(r + stride, rows - 1)
		var c := c_start
		while c < c_end:
			var c2 := mini(c + stride, cols - 1)
			var covered := ring_mask[r * cols + c] > 0 or ring_mask[r * cols + c2] > 0 or ring_mask[r2 * cols + c] > 0 or ring_mask[r2 * cols + c2] > 0
			if covered:
				var mx := ring_origin.x + (float(c + c2) * 0.5 + 0.5) * spacing
				var mz := ring_origin.y + (float(r + r2) * 0.5 + 0.5) * spacing
				var dist := Vector2(mx - focus.x, mz - focus.z).length()
				var inside := mx > 80.0 and mz > 80.0 and mx < span - 80.0 and mz < span - 80.0
				if dist >= min_dist and dist <= max_dist and not inside:
					var ia: int = add.call(c, r)
					var ib: int = add.call(c2, r)
					var id: int = add.call(c, r2)
					var ie: int = add.call(c2, r2)
					indices.append_array(PackedInt32Array([ia, ib, id, ib, ie, id]))
			c += stride
		r += stride
	if indices.is_empty():
		return
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = positions
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var tool := SurfaceTool.new()
	tool.create_from(mesh, 0)
	tool.generate_normals()
	mesh = tool.commit()
	mesh.surface_set_material(0, mat)
	var node: MeshInstance3D
	if which == "far":
		if ring_far == null:
			ring_far = MeshInstance3D.new()
			ring_far.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(ring_far)
		node = ring_far
	else:
		if ring_near == null:
			ring_near = MeshInstance3D.new()
			ring_near.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			add_child(ring_near)
		node = ring_near
	node.mesh = mesh
	print("ring ", which, " tris ", indices.size() / 3)
