class_name TerrainWorld
extends Node3D

const _Tiles = preload("res://scripts/tile_stream.gd")
const _Quad = preload("res://scripts/quad_stream.gd")
const _Shore = preload("res://scripts/shore.gd")

const CHUNK := 32

var field: Soil.Field
var spec: Dictionary = {}
var mat: ShaderMaterial
var fine_mat: ShaderMaterial
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
var baseline: PackedFloat32Array
var persist := true
var site_id := ""
# World metres = field metres - view_origin, so a far coarse window stays near the camera.
var view_origin := Vector2.ZERO
var imagery_zoom := 8
var stream_radius := 1
var detail_cap := 13
var streaming := false
var quad: QuadStream
const WINDOW := 97
const COL_SPACING := 0.5

func _ready() -> void:
	quad = _Quad.new()
	quad.name = "QuadStream"
	add_child(quad)


func setup(next_spec: Dictionary, albedo: Texture2D, grain: Texture2D) -> void:
	var bytes := FileAccess.get_file_as_bytes("res://data/%s" % next_spec["heights"])
	var heights := _decode_heights(str(next_spec["heights"]), bytes, float(next_spec["hmin"]), float(next_spec["hmax"]))
	setup_heights(next_spec, heights, albedo, grain)


func setup_heights(next_spec: Dictionary, heights: PackedFloat32Array, albedo: Texture2D, grain: Texture2D) -> void:
	streaming = false
	if quad != null:
		quad.shutdown()
	spec = next_spec
	color_tex = albedo
	grain_tex = grain
	_clear()
	var cols: int = spec["cols"]
	var rows: int = spec["rows"]
	field = Soil.Field.new()
	field.cols = cols
	field.rows = rows
	field.spacing = float(spec["spacing"])
	field.heights = heights
	field.disturb = PackedByteArray()
	field.disturb.resize(cols * rows)
	field.changed = PackedInt32Array()
	site_id = str(spec.get("id", "site"))
	baseline = field.heights.duplicate()
	if spec.has("view_origin"):
		view_origin = Vector2(float(spec["view_origin"][0]), float(spec["view_origin"][1]))
	else:
		view_origin = Vector2.ZERO
	if persist:
		_load_edits()
	_build_height_texture()
	_build_disturb_texture()
	mat = ShaderMaterial.new()
	mat.shader = load("res://shaders/ground.gdshader")
	var span := float(spec["cols"] - 1) * field.spacing
	patch = Soil.Patch.new(field)
	fine_img = Image.create(Soil.Patch.N, Soil.Patch.N, false, Image.FORMAT_RGBA8)
	fine_img.fill(Color(0, 0, 0, 1))
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


## A window of the coarse polar grid, centred on land. Returns the local
## spawn and the lat/lon actually used after a shore snap.
func open_north(meta: Dictionary, lat: float, lon: float, grain: Texture2D) -> Dictionary:
	var posts := int(meta["posts"])
	var half_m := float(meta["half_m"])
	var step := float(meta["step_m"])
	var bytes := FileAccess.get_file_as_bytes("res://data/%s" % str(meta["heights"]))
	var full := _decode_heights(str(meta["heights"]), bytes, float(meta["hmin"]), float(meta["hmax"]))
	var projected := Geo.polar_forward(lat, lon)
	var col := int(round((projected.x + half_m) / step))
	var image_row := int(round((half_m - projected.y) / step))
	var row := posts - 1 - image_row
	col = clampi(col, 0, posts - 1)
	row = clampi(row, 0, posts - 1)
	if full[row * posts + col] < 1.5:
		var found := _nearest_land(full, posts, col, row)
		col = found.x
		row = found.y
	var radius := 8
	var c0 := clampi(col - radius, 0, posts - 2)
	var r0 := clampi(row - radius, 0, posts - 2)
	var c1 := clampi(col + radius, c0 + 1, posts - 1)
	var r1 := clampi(row + radius, r0 + 1, posts - 1)
	var cols := c1 - c0 + 1
	var rows := r1 - r0 + 1
	var window := PackedFloat32Array()
	window.resize(cols * rows)
	var lo := 1.0e9
	var hi := -1.0e9
	for r in rows:
		for c in cols:
			var h: float = full[(r0 + r) * posts + (c0 + c)]
			window[r * cols + c] = h
			lo = minf(lo, h)
			hi = maxf(hi, h)
	var color_tex := load("res://data/%s" % str(meta["color"])) as Texture2D
	var color_img: Image = color_tex.get_image() if color_tex != null else null
	var paint := Image.create(cols, rows, false, Image.FORMAT_RGB8)
	if color_img != null:
		for r in rows:
			# File row 0 is minimum Y. The photo's row 0 is maximum Y.
			var src_row := posts - 1 - (r0 + (rows - 1 - r))
			src_row = clampi(src_row, 0, color_img.get_height() - 1)
			for c in cols:
				var src_col := clampi(c0 + c, 0, color_img.get_width() - 1)
				paint.set_pixel(c, r, color_img.get_pixel(src_col, src_row))
	var albedo := ImageTexture.create_from_image(paint)
	var spec_n := {
		"id": "north-%d-%d" % [c0, r0],
		"name": "North",
		"cols": cols,
		"rows": rows,
		"spacing": step,
		"hmin": lo,
		"hmax": maxf(hi, lo + 1.0),
		"repose": 34.0,
		"water": 0.0,
		"forest": false,
		"lat": lat,
		"spawn": [0.0, 0.0],
		"view_origin": [float(col - c0) * step, float(row - r0) * step],
	}
	setup_heights(spec_n, window, albedo, grain)
	var back_x := -half_m + float(col) * step
	var back_y := -half_m + float(row) * step
	var ll := Geo.polar_inverse(Vector2(back_x, back_y))
	return {"x": 0.0, "z": 0.0, "lat": ll.x, "lon": ll.y}


## Start a streamed window without waiting on the network. The caller keeps
## the loading fade up until stream_ready() or the anchor tile fails.
func open_stream(lat: float, lon: float, _grain: Texture2D) -> Dictionary:
	return begin_stream(lat, lon)


func begin_stream(lat: float, lon: float) -> Dictionary:
	if quad == null:
		quad = _Quad.new()
		quad.name = "QuadStream"
		add_child(quad)
	_clear()
	view_origin = Vector2.ZERO
	streaming = true
	var spec_n := {
		"id": "stream-%.4f-%.4f" % [lat, lon],
		"name": "North",
		"cols": 4,
		"rows": 4,
		"spacing": 32.0,
		"hmin": -400.0,
		"hmax": 2200.0,
		"repose": 34.0,
		"water": null,
		"forest": false,
		"lat": lat,
		"spawn": [0.0, 0.0],
		"view_origin": [0.0, 0.0],
		"diggable": false,
	}
	spec = spec_n
	field = Soil.Field.new()
	field.cols = 4
	field.rows = 4
	field.spacing = 32.0
	field.heights = PackedFloat32Array()
	field.heights.resize(16)
	field.disturb = PackedByteArray()
	field.disturb.resize(16)
	field.changed = PackedInt32Array()
	baseline = field.heights.duplicate()
	quad.start(lat, lon, detail_cap)
	return {"x": 0.0, "z": 0.0, "lat": lat, "lon": lon}


func stream_ready(x: float, z: float) -> bool:
	return streaming and quad != null and quad.has_visual(x, z)


func stream_failed() -> bool:
	return quad != null and quad.anchor_failed


func tick_stream(focus_pos: Vector3, cam_pos: Vector3, fov: float, view_h: float) -> Vector3:
	focus = focus_pos
	if not streaming or quad == null:
		return Vector3.ZERO
	return quad.tick(focus_pos, cam_pos, fov, view_h, detail_cap)


func _nearest_land(full: PackedFloat32Array, posts: int, col: int, row: int) -> Vector2i:
	var best := Vector2i(col, row)
	var best_d := 1.0e12
	for r in posts:
		var dz := r - row
		for c in posts:
			if full[r * posts + c] < 1.5:
				continue
			var dx := c - col
			var d := dx * dx + dz * dz
			if d < best_d:
				best_d = d
				best = Vector2i(c, r)
	return best


func sample(x: float, z: float) -> float:
	if streaming and quad != null:
		var streamed := quad.height_at(x, z)
		if streamed > -12000.0:
			return streamed
	if field == null:
		return 0.0
	return _sample_field(x + view_origin.x, z + view_origin.y)


func _sample_field(x: float, z: float) -> float:
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


func stamp_tracks(east: float, north: float, fx: float, fz: float) -> void:
	ensure_patch(Vector2(east, north))
	if patch == null:
		return
	if Soil.stamp_tracks(patch.field, east - patch.origin.x, north - patch.origin.y, fx, fz):
		_flush_fine()


func cut_blade(east: float, north: float, fx: float, fz: float, width: float, edge_y: float, repose: float) -> float:
	ensure_patch(Vector2(east, north))
	if patch == null:
		return 0.0
	var moved: float = Soil.plane_blade(patch.field, east - patch.origin.x, north - patch.origin.y, fx, fz, width, edge_y, repose)
	if moved > 0.0:
		_flush_fine()
	return moved


func ensure_patch(focus: Vector2) -> void:
	if patch == null:
		return
	focus += view_origin
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
	var cover: Texture2D = null
	if str(spec.get("id")) == "rene-levasseur":
		cover = load("res://data/ile_cover.png")
	if cover == null:
		var blank := Image.create(2, 2, false, Image.FORMAT_RGBA8)
		blank.fill(Color(0, 0, 0, 0))
		cover = ImageTexture.create_from_image(blank)
	mat.set_shader_parameter("cover_map", cover)
	_sync_patch_uniforms()
	fine_mat = mat.duplicate() as ShaderMaterial
	fine_mat.set_shader_parameter("is_fine", 1.0)
	fine_mesh.material_override = fine_mat


func _sync_patch_uniforms() -> void:
	if patch == null or mat == null:
		return
	mat.set_shader_parameter("patch_origin", patch.origin)
	mat.set_shader_parameter("patch_size", patch.size_m())
	mat.set_shader_parameter("patch_live", 1.0 if patch.live else 0.0)
	if fine_mat:
		fine_mat.set_shader_parameter("patch_origin", patch.origin)
		fine_mat.set_shader_parameter("patch_size", patch.size_m())
		fine_mat.set_shader_parameter("patch_live", 1.0 if patch.live else 0.0)


func _flush_fine() -> void:
	var n := Soil.Patch.N
	var cell := Soil.Patch.CELL
	for i in patch.field.changed:
		var c := i % n
		var r := int(i / n)
		var py := n - 1 - r
		var d: int = patch.field.disturb[i]
		var col := fine_img.get_pixel(c, py)
		if d == 180 or d == 200:
			col.g = 1.0
		if d == 255 or d == 200:
			col.r = 1.0
		fine_img.set_pixel(c, py, col)
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
	var moved := patch.field.disturb
	var cover := PackedByteArray()
	cover.resize(n * n)
	for r in n:
		for c in n:
			if moved[r * n + c] == 0:
				continue
			for rr in range(maxi(r - 1, 0), mini(r + 2, n)):
				for cc in range(maxi(c - 1, 0), mini(c + 2, n)):
					cover[rr * n + cc] = 1
	for r in n:
		for c in n:
			var fx := patch.origin.x + float(c) * cell
			var fz := patch.origin.y + float(r) * cell
			var idx := r * n + c
			var lift := 0.03 if cover[idx] != 0 else 0.0
			positions[idx] = Vector3(fx - view_origin.x, heights[idx] + lift, fz - view_origin.y)
			uvs[idx] = Vector2(clampf(fx / span, 0.0, 1.0), clampf(fz / span, 0.0, 1.0))
			var h: float = heights[idx]
			var hl: float = heights[idx - 1] if c > 0 else h
			var hr: float = heights[idx + 1] if c + 1 < n else h
			var hd: float = heights[idx - n] if r > 0 else h
			var hu: float = heights[idx + n] if r + 1 < n else h
			normals[idx] = Vector3(hl - hr, cell * 2.0, hd - hu).normalized()
	for r in n - 1:
		for c in n - 1:
			var a := r * n + c
			var b := a + 1
			var d := a + n
			var e := d + 1
			if cover[a] == 0 and cover[b] == 0 and cover[d] == 0 and cover[e] == 0:
				continue
			indices.append_array(PackedInt32Array([a, b, d, b, e, d]))
	if indices.is_empty():
		fine_mesh.mesh = null
		return
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


func _under_patch(_c: int, _r: int) -> bool:
	# The coarse mesh stays continuous. The ground shader drops fragments that
	# the 0.25 m patch already covers, so the two meshes never share a pixel.
	return false


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
	if streaming:
		return
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


func save_edits() -> void:
	if streaming or not persist or baseline.is_empty() or field == null:
		return
	if patch and patch.live:
		patch.bake()
	var indexes := PackedInt32Array()
	var values := PackedFloat32Array()
	for i in field.heights.size():
		if absf(field.heights[i] - baseline[i]) > 0.004:
			indexes.append(i)
			values.append(field.heights[i])
	DirAccess.make_dir_recursive_absolute("user://world")
	var file := FileAccess.open("user://world/%s.edits" % site_id, FileAccess.WRITE)
	if file == null:
		return
	file.store_32(0x31505752)
	file.store_32(indexes.size())
	for i in indexes.size():
		file.store_32(indexes[i])
		file.store_float(values[i])
	print("saved edits ", site_id, " ", indexes.size())


func _load_edits() -> void:
	var path := "user://world/%s.edits" % site_id
	if not FileAccess.file_exists(path):
		return
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_32() != 0x31505752:
		return
	var count := int(file.get_32())
	var applied := 0
	for _i in count:
		var idx := int(file.get_32())
		var height := file.get_float()
		if idx >= 0 and idx < field.heights.size():
			field.heights[idx] = height
			field.disturb[idx] = 255
			applied += 1
	print("loaded edits ", site_id, " ", applied)


func _decode_heights(name: String, bytes: PackedByteArray, hmin: float, hmax: float) -> PackedFloat32Array:
	if not name.ends_with(".u16"):
		return bytes.to_float32_array()
	var span := maxf(hmax - hmin, 0.001)
	var count := bytes.size() / 2
	var out := PackedFloat32Array()
	out.resize(count)
	for i in count:
		var u := float(bytes.decode_u16(i * 2))
		out[i] = hmin + (u / 65535.0) * span
	return out


func _build_height_texture() -> void:
	var cols := field.cols
	var rows := field.rows
	var span := float(spec["hmax"]) - float(spec["hmin"])
	var raw := PackedByteArray()
	raw.resize(cols * rows * 3)
	for r in rows:
		var src := rows - 1 - r
		for c in cols:
			var h: float = _shore_height(c, src)
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
	if streaming or ground == null or shape == null or field == null:
		return
	focus_pos = Vector3(focus_pos.x + view_origin.x, focus_pos.y, focus_pos.z + view_origin.y)
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
			data[j * WINDOW + i] = _sample_field(x, z)
	shape.map_width = WINDOW
	shape.map_depth = WINDOW
	shape.map_data = data
	var col := ground.get_child(0) as CollisionShape3D
	if col:
		col.scale = Vector3(COL_SPACING, 1.0, COL_SPACING)
	ground.position = Vector3(ox - view_origin.x + span * 0.5, 0.0, oz - view_origin.y + span * 0.5)


func _build_water() -> void:
	if spec["water"] == null:
		return
	var span := float(field.cols - 1) * field.spacing
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var y := float(spec["water"]) + 0.28
	if str(spec.get("id")) == "rene-levasseur":
		# Long reservoir swells need more than four corners. 32 m over the tile.
		var step := 32.0
		var n := int(span / step)
		var count := (n + 1) * (n + 1)
		var positions := PackedVector3Array()
		var uvs := PackedVector2Array()
		positions.resize(count)
		uvs.resize(count)
		for j in n + 1:
			for i in n + 1:
				var idx := j * (n + 1) + i
				var x := float(i) * step
				var z := float(j) * step
				positions[idx] = Vector3(x, y, z)
				uvs[idx] = Vector2(x / span, z / span)
		var indices := PackedInt32Array()
		indices.resize(n * n * 6)
		var t := 0
		for j in n:
			for i in n:
				var a := j * (n + 1) + i
				var b := a + 1
				var c := a + (n + 1)
				var d := c + 1
				indices[t] = a
				indices[t + 1] = c
				indices[t + 2] = b
				indices[t + 3] = b
				indices[t + 4] = c
				indices[t + 5] = d
				t += 6
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = positions
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		arrays[Mesh.ARRAY_INDEX] = indices
		var grid := ArrayMesh.new()
		grid.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		st.create_from(grid, 0)
	else:
		# Wide enough that the horizon is water from the high ground.
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
	wmat.set_shader_parameter("use_ssr", 1.0 if RenderingServer.get_current_rendering_method() == "forward_plus" else 0.0)
	wmat.set_shader_parameter("sun_dir", Vector3(0.55, 0.38, 0.74))
	_attach_shore(wmat)
	water.material_override = wmat
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(water)


func _attach_shore(wmat: ShaderMaterial) -> void:
	if str(spec.get("id", "")) != "rene-levasseur":
		wmat.set_shader_parameter("has_shore", 0.0)
		return
	var started := Time.get_ticks_msec()
	var span := float(field.cols - 1) * field.spacing
	var shore_img: Image = _Shore.build(field.heights, field.cols, field.rows, float(spec["water"]), span, 128, 96.0)
	var shore_tex := ImageTexture.create_from_image(shore_img)
	wmat.set_shader_parameter("shore_field", shore_tex)
	wmat.set_shader_parameter("shore_scale", 96.0)
	wmat.set_shader_parameter("has_shore", 1.0)
	print("shore field ", Time.get_ticks_msec() - started, " ms")


func _build_apron() -> void:
	# The island already continues as a ring. A second sheet there fights it.
	if spec.has("ring"):
		return
	var span := float(field.cols - 1) * field.spacing
	# A coarse northern window is tens of kilometres across. An 8 m apron there never finishes.
	if span > 12000.0:
		return
	var reach := 640.0
	var step := 8.0
	var water_y := -1000.0
	if spec.get("water") != null:
		water_y = float(spec["water"])
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
			var h := 0.0
			if inside:
				h = sample(x, z)
			else:
				var ex := clampf(x, 0.0, span)
				var ez := clampf(z, 0.0, span)
				var edge := sample(ex, ez)
				var dist := Vector2(x - ex, z - ez).length()
				var t := clampf(dist / reach, 0.0, 1.0)
				t = t * t
				# Fall away from the edge. Never climb above it into the sky.
				h = edge - 22.0 * t
				if water_y > -100.0:
					h = minf(h, lerpf(edge, water_y - 8.0, t))
				h = minf(h, edge)
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
	if streaming:
		return
	_stream(pos)
	_update_collision(pos)


func _stream(pos: Vector3) -> void:
	pos = Vector3(pos.x + view_origin.x, pos.y, pos.z + view_origin.y)
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
			if _meets_water(key):
				lod = mini(lod, 1)
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


func _meets_water(key: Vector2i) -> bool:
	if spec.get("water") == null:
		return false
	var wy := float(spec["water"])
	var c0 := key.x * CHUNK
	var r0 := key.y * CHUNK
	var lo := 1.0e9
	var hi := -1.0e9
	for r in [r0, mini(field.rows - 1, r0 + CHUNK / 2), mini(field.rows - 1, r0 + CHUNK)]:
		for c in [c0, mini(field.cols - 1, c0 + CHUNK / 2), mini(field.cols - 1, c0 + CHUNK)]:
			var h: float = field.height_at(c, r)
			lo = minf(lo, h)
			hi = maxf(hi, h)
	return lo < wy + 3.0 and hi > wy - 8.0


func _lod_for(center: Vector3) -> int:
	var dist := Vector2(center.x - focus.x, center.z - focus.z).length()
	if dist < 560.0:
		return 1
	if dist < 1200.0:
		return 2
	if dist < 2200.0:
		return 4
	return 8


func _chunk_center(key: Vector2i) -> Vector3:
	var spacing := field.spacing
	var x := (float(key.x) + 0.5) * float(CHUNK) * spacing - view_origin.x
	var z := (float(key.y) + 0.5) * float(CHUNK) * spacing - view_origin.y
	return Vector3(x, 0.0, z)


func _build_chunk(key: Vector2i, stride: int) -> void:
	var c0 := key.x * CHUNK
	var r0 := key.y * CHUNK
	var c1 := mini(field.cols - 1, c0 + CHUNK)
	var r1 := mini(field.rows - 1, r0 + CHUNK)
	if c1 <= c0 or r1 <= r0:
		return
	# Overlap the next chunk by one step so a LOD crack cannot open onto the sky.
	var c1_mesh := mini(field.cols - 1, c1 + stride * 2)
	var r1_mesh := mini(field.rows - 1, r1 + stride * 2)
	var cs := _steps(c0, c1_mesh, stride)
	var rs := _steps(r0, r1_mesh, stride)
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
		var px := float(c) * spacing - view_origin.x
		var pz := float(r) * spacing - view_origin.y
		positions.append(Vector3(px, _shore_height(c, r) + drop, pz))
		uvs.append(Vector2(float(c) / cols_f, float(r) / rows_f))
		var step_n := 6
		var hl: float = field.height_at(c - step_n, r)
		var hr: float = field.height_at(c + step_n, r)
		var hd: float = field.height_at(c, r - step_n)
		var hu: float = field.height_at(c, r + step_n)
		var nrm := Vector3(hl - hr, float(step_n) * spacing * 2.0, hd - hu).normalized()
		if drop < 0.0:
			nrm = Vector3(0.0, -1.0, 0.0)
		normals.append(nrm)
		return idx
	for j in range(rs.size() - 1):
		for i in range(cs.size() - 1):
			if _under_patch(cs[i], rs[j]) and _under_patch(cs[i + 1], rs[j]) and _under_patch(cs[i], rs[j + 1]) and _under_patch(cs[i + 1], rs[j + 1]):
				continue
			_quad(add, indices, cs[i], rs[j], cs[i + 1], rs[j + 1])
	# No vertical skirt. A wall at the map edge reads as a sheet in the sky.
	# The apron outside the tile falls away and the fog takes the horizon.
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


## Round the bank where it meets the water so a 2 m grid does not stair-step
## the shoreline. Inland heights stay as surveyed.
func _shore_height(c: int, r: int) -> float:
	var h: float = field.height_at(c, r)
	if spec.get("water") == null:
		return h
	var wy := float(spec["water"])
	var gap := absf(h - wy)
	if gap > 5.0:
		return h
	var acc := 0.0
	var n := 0
	for dz in range(-4, 5):
		for dx in range(-4, 5):
			acc += field.height_at(c + dx * 2, r + dz * 2)
			n += 1
	var blend := (1.0 - gap / 5.0) * 0.9
	return lerpf(h, acc / float(n), blend)


func _steps(a: int, b: int, stride: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	var v := a
	while v < b:
		out.append(v)
		v += stride
	if out.is_empty() or out[out.size() - 1] != b:
		out.append(b)
	return out


func _map_edge(key: Vector2i, dir: Vector2i) -> bool:
	var nkey := key + dir
	var max_x := int((field.cols - 1) / CHUNK)
	var max_y := int((field.rows - 1) / CHUNK)
	return nkey.x < 0 or nkey.y < 0 or nkey.x > max_x or nkey.y > max_y


func _neighbor_step(key: Vector2i, dir: Vector2i, stride: int) -> int:
	if _map_edge(key, dir):
		return stride
	return maxi(stride, _lod_for(_chunk_center(key + dir)))


func _quad(add: Callable, indices: PackedInt32Array, c0: int, r0: int, c1: int, r1: int) -> void:
	var a: int = add.call(c0, r0, 0.0)
	var b: int = add.call(c1, r0, 0.0)
	var d: int = add.call(c0, r1, 0.0)
	var e: int = add.call(c1, r1, 0.0)
	indices.append_array(PackedInt32Array([a, b, d, b, e, d]))


func _zip_rows(add: Callable, indices: PackedInt32Array, low_c: PackedInt32Array, low_r: int, high_c: PackedInt32Array, high_r: int) -> void:
	var i := 0
	var j := 0
	var na := low_c.size()
	var nb := high_c.size()
	if na < 2 or nb < 2:
		return
	while i < na - 1 or j < nb - 1:
		var take_low := i < na - 1 and (j >= nb - 1 or low_c[i + 1] <= high_c[j + 1])
		if take_low:
			_quad_corner(add, indices, low_c[i], low_r, low_c[i + 1], low_r, high_c[j], high_r)
			i += 1
		else:
			_quad_corner(add, indices, low_c[i], low_r, high_c[j + 1], high_r, high_c[j], high_r)
			j += 1


func _zip_cols(add: Callable, indices: PackedInt32Array, left_c: int, left_r: PackedInt32Array, right_c: int, right_r: PackedInt32Array) -> void:
	var i := 0
	var j := 0
	var na := left_r.size()
	var nb := right_r.size()
	if na < 2 or nb < 2:
		return
	while i < na - 1 or j < nb - 1:
		var take_left := i < na - 1 and (j >= nb - 1 or left_r[i + 1] <= right_r[j + 1])
		if take_left:
			_quad_corner(add, indices, left_c, left_r[i], right_c, right_r[j], left_c, left_r[i + 1])
			i += 1
		else:
			_quad_corner(add, indices, right_c, right_r[j], right_c, right_r[j + 1], left_c, left_r[i])
			j += 1


func _quad_corner(add: Callable, indices: PackedInt32Array, c0: int, r0: int, c1: int, r1: int, c2: int, r2: int) -> void:
	var a: int = add.call(c0, r0, 0.0)
	var b: int = add.call(c1, r1, 0.0)
	var d: int = add.call(c2, r2, 0.0)
	indices.append_array(PackedInt32Array([a, b, d]))


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
	var ring_bytes := FileAccess.get_file_as_bytes("res://data/%s" % str(info["heights"]))
	ring.heights = _decode_heights(str(info["heights"]), ring_bytes, float(info.get("hmin", 0.0)), float(info.get("hmax", 1.0)))
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
	var far_stride := 16 if OS.has_feature("web") else 8
	_build_ring_mesh(far_stride, 0.0, 1.0e9, "far")
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
