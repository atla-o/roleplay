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
const WINDOW := 97

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
	mat.set_shader_parameter("albedo_map", color_tex)
	mat.set_shader_parameter("height_map", height_tex)
	mat.set_shader_parameter("disturb_map", disturb_tex)
	mat.set_shader_parameter("grain_map", grain_tex)
	mat.set_shader_parameter("height_range", Vector2(float(spec["hmin"]), float(spec["hmax"])))
	mat.set_shader_parameter("tile_m", Vector2(span, span))
	mat.set_shader_parameter("spacing", field.spacing)
	_build_collision()
	_build_apron()
	_build_water()
	rebuild_around(Vector3(float(spec["spawn"][0]), 0.0, float(spec["spawn"][1])))


func sample(x: float, z: float) -> float:
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
	var spacing := field.spacing
	var c0 := clampi(int(focus_pos.x / spacing) - WINDOW / 2, 0, field.cols - WINDOW)
	var r0 := clampi(int(focus_pos.z / spacing) - WINDOW / 2, 0, field.rows - WINDOW)
	var origin := Vector2i(c0, r0)
	if origin == window_origin and not collision_dirty:
		return
	window_origin = origin
	collision_dirty = false
	var data := PackedFloat32Array()
	data.resize(WINDOW * WINDOW)
	for j in WINDOW:
		var row := (r0 + j) * field.cols
		for i in WINDOW:
			data[j * WINDOW + i] = field.heights[row + c0 + i]
	shape.map_width = WINDOW
	shape.map_depth = WINDOW
	shape.map_data = data
	var half := float(WINDOW - 1) * spacing * 0.5
	ground.position = Vector3(float(c0) * spacing + half, 0.0, float(r0) * spacing + half)


func _build_water() -> void:
	if spec["water"] == null:
		return
	var span := float(field.cols - 1) * field.spacing
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var y := float(spec["water"]) + 0.55
	# North is +Z. The reservoir continues past the north edge of the measured square.
	var pts := [
		Vector3(0.0, y, -20.0),
		Vector3(span, y, -20.0),
		Vector3(0.0, y, span + 2400.0),
		Vector3(span, y, span + 2400.0),
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
		positions.append(Vector3(float(c) * spacing, field.height_at(c, r) + drop, float(r) * spacing))
		uvs.append(Vector2(float(c) / cols_f, float(r) / rows_f))
		return idx
	for j in range(rs.size() - 1):
		for i in range(cs.size() - 1):
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
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var tool := SurfaceTool.new()
	tool.create_from(mesh, 0)
	tool.generate_normals()
	mesh = tool.commit()
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
