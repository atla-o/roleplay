class_name Foliage
extends Node3D

var pines: Array = []
var birches: Array = []
var grasses: Array = []
var bushes: Array = []
var boulders: Array = []
var spruce_near: ArrayMesh
var spruce_far: ArrayMesh
var fir_near: ArrayMesh
var fir_far: ArrayMesh
var birch_card: ArrayMesh
var shrub_card: ArrayMesh
var spruce_mesh: ArrayMesh
var fir_mesh: ArrayMesh
var spruce_octa: ArrayMesh
var fir_octa: ArrayMesh
var terrain_ref: TerrainWorld
var saplings: Array = []
var felled_logs: Array[RigidBody3D] = []

func _ready() -> void:
	var shader: Shader = load("res://shaders/tree_card.gdshader")
	spruce_near = _card(load("res://assets/textures/spruce_card.png") as Texture2D, shader, 3, 2.92, 16.0, 0.45)
	spruce_far = _card(load("res://assets/textures/spruce_card.png") as Texture2D, shader, 2, 2.92, 16.0, 0.2)
	fir_near = _card(load("res://assets/textures/fir_card.png") as Texture2D, shader, 3, 3.71, 16.0, 0.35)
	fir_far = _card(load("res://assets/textures/fir_card.png") as Texture2D, shader, 2, 3.71, 16.0, 0.15)
	birch_card = _card(load("res://assets/textures/birch_card.png") as Texture2D, shader, 2, 2.15, 14.0, 0.2)
	shrub_card = _card(load("res://assets/textures/shrub_card.png") as Texture2D, shader, 2, 0.9, 0.9, 0.04)
	pines = [spruce_near, fir_near]
	boulders = _meshes("res://assets/models/boulder.glb")
	spruce_mesh = _spruce_mesh()
	fir_mesh = _fir_mesh()
	spruce_octa = _octa_card("res://assets/textures/spruce_octa.png", 7.6, 1.7)
	fir_octa = _octa_card("res://assets/textures/fir_octa.png", 7.6, 2.05)


func rebuild(terrain: TerrainWorld, albedo: Texture2D) -> void:
	terrain_ref = terrain
	saplings.clear()
	for child in get_children():
		child.queue_free()
	if str(terrain.spec.get("id")) == "rene-levasseur" and spruce_near != null:
		var cover_tex := load("res://data/ile_cover.png") as Texture2D
		if cover_tex != null and cover_tex.get_image() != null:
			_place_boreal(terrain, cover_tex.get_image())
			return
	var img := albedo.get_image()
	if img == null:
		return
	var span := float(terrain.field.cols - 1) * terrain.field.spacing
	var water := float(terrain.spec["water"]) if terrain.spec["water"] != null else -9999.0
	var forest := bool(terrain.spec.get("forest", false))
	var spawn := Vector2(float(terrain.spec["spawn"][0]), float(terrain.spec["spawn"][1]))
	var near: Array[Transform3D] = []
	var far: Array[Transform3D] = []
	var grass: Array[Transform3D] = []
	var shrub: Array[Transform3D] = []
	var rocks: Array[Transform3D] = []
	var logs: Array[Transform3D] = []
	var birch_near: Array[Transform3D] = []
	var birch_far: Array[Transform3D] = []
	var step := 10
	for y in range(0, img.get_height(), step):
		for x in range(0, img.get_width(), step):
			var px := img.get_pixel(x, y)
			var east := float(x) / float(img.get_width() - 1) * span
			var north := (1.0 - float(y) / float(img.get_height() - 1)) * span
			var h := terrain.sample(east, north)
			if h < water + 1.2:
				continue
			var roll := _hash(x, y)
			var green := px.g > px.r + 0.025 and px.g > 0.08
			var dist := Vector2(east, north).distance_to(spawn)
			var slope := _slope(terrain, east, north)
			if dist > 12.0 and roll > 0.35 and rocks.size() < 900 and (slope > 0.08 or not forest):
				var rs := 0.8 + _hash(x + 4, y) * (3.2 if slope > 0.3 else 1.6)
				rocks.append(_xf(east, h - 0.2, north, roll * TAU, rs))
			if not forest:
				continue
			var excess := px.g - maxf(px.r, px.b)
			var lum := (px.r + px.g + px.b) / 3.0
			# Sentinel-2: dark green is closed canopy, pale or brown pixels are clearings.
			var clearing := excess < 0.028 or lum < 0.07 or lum > 0.7 or not green
			if clearing:
				if _hash(x + 8, y + 8) > 0.62 and grass.size() < 700:
					grass.append(_xf(east, h, north, roll * TAU, 0.9))
				continue
			var cell := span / float(img.get_width()) * float(step)
			var gap := 5.0 if excess > 0.1 else 8.0
			var n := maxi(int(cell / gap), 1)
			for iy in n:
				for ix in n:
					var jx := _hash(x + ix * 3 + 1, y + iy * 2)
					var jz := _hash(x + ix + 4, y + iy * 5 + 2)
					var birch_stand: bool = jx > 0.9
					var ex := east + (float(ix) + jx) * (cell / float(n))
					var nz := north + (float(iy) + jz) * (cell / float(n))
					var hh := terrain.sample(ex, nz)
					if hh < water + 1.5:
						continue
					var d2 := Vector2(ex, nz).distance_to(spawn)
					if d2 < 14.0:
						continue
					var sc := 0.7 + jz * 0.9
					var yaw := (jx + jz) * TAU
					hh -= 0.22
					if d2 < 220.0 and near.size() + birch_near.size() < 2000:
						if birch_stand and birch_near.size() < 36 and d2 > 46.0:
							birch_near.append(_xf(ex, hh, nz, yaw, sc * 1.35))
						else:
							near.append(_xf(ex, hh, nz, yaw, sc))
					elif d2 < 1400.0 and far.size() + birch_far.size() < 7000:
						if birch_stand and jx > 0.42:
							birch_far.append(_xf(ex, hh, nz, yaw, sc * 2.6))
						else:
							far.append(_xf(ex, hh, nz, yaw, sc * 1.2))
			if dist < 120.0 and slope < 0.4:
				if roll > 0.22 and grass.size() < 2200:
					grass.append(_xf(east + roll, h, north, roll * TAU, 0.45 + roll * 0.35))
				if _hash(x + 3, y + 7) > 0.4 and shrub.size() < 1800:
					shrub.append(_xf(east, h, north, roll * 3.0, 0.55 + roll * 0.5))
				if _hash(x + 5, y + 2) > 0.72 and logs.size() < 520:
					logs.append(_log_xf(east, h + 0.12, north, roll * TAU))
			elif _hash(x + 1, y + 9) > 0.62 and shrub.size() < 900:
				shrub.append(_xf(east, h, north, roll * 3.0, 0.7 + roll * 0.6))
	var litter: Array[Vector2] = [Vector2(-4.0, 6.0), Vector2(-10.0, 9.0), Vector2(2.0, 8.0), Vector2(-7.0, 14.0)]
	for spot2 in litter:
		var q: Vector2 = spawn + spot2
		var qh := terrain.sample(q.x, q.y)
		shrub.append(_xf(q.x, qh, q.y, 1.2, 0.85))
		logs.append(_log_xf(q.x + 1.4, qh + 0.1, q.y + 0.6, 0.7))
	var spruce: Array[Transform3D] = []
	var fir: Array[Transform3D] = []
	for i in near.size():
		if i % 5 == 0:
			fir.append(near[i])
		else:
			spruce.append(near[i])
	_spawn(pines[0], spruce, true, 0.0, 240.0)
	_spawn(pines[1], fir, true, 0.0, 240.0)
	_spawn_variants(birches, birch_near, true, 0.0, 230.0)
	_spawn(_impostor(), far, false, 160.0, 1700.0)
	_spawn_variants(birches, birch_far, false, 160.0, 1700.0)
	for mesh in grasses:
		_spawn(mesh, grass, false, 0.0, 90.0)
	for mesh in bushes:
		_spawn(mesh, shrub, false, 0.0, 160.0)
	for mesh in boulders:
		_spawn(mesh, rocks, true, 0.0, 500.0)
	_spawn(_log_mesh(), logs, true, 0.0, 180.0)
	var trunks: Array[Transform3D] = []
	for xf in near:
		if Vector2(xf.origin.x, xf.origin.z).distance_to(spawn) < 36.0 and trunks.size() < 70:
			trunks.append(xf)
	_collide(trunks, 0.42, 5.5)
	_collide(rocks, 0.55, 1.1)


func _raster_at(img: Image, east: float, north: float, span: float) -> Color:
	if img == null:
		return Color(0.2, 0.32, 0.14)
	var x := clampi(int(east / span * float(img.get_width() - 1)), 0, img.get_width() - 1)
	var y := clampi(int((1.0 - north / span) * float(img.get_height() - 1)), 0, img.get_height() - 1)
	return img.get_pixel(x, y)


func _card(tex: Texture2D, shader: Shader, crosses: int, half_w: float, height: float, sway: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in crosses:
		var ang := PI * float(k) / float(crosses)
		var dir := Vector3(cos(ang), 0.0, sin(ang))
		var a := -dir * half_w
		var b := dir * half_w
		var top_a := a + Vector3(0.0, height, 0.0)
		var top_b := b + Vector3(0.0, height, 0.0)
		var verts: Array[Vector3] = [a, top_a, b, b, top_a, top_b]
		# Godot's texture V is down the image, and the cards are painted tip-up.
		var uvs: Array[Vector2] = [Vector2(0, 1), Vector2(0, 0), Vector2(1, 1), Vector2(1, 1), Vector2(0, 0), Vector2(1, 0)]
		for i in verts.size():
			st.set_color(Color(1, 1, 1))
			st.set_uv(uvs[i])
			st.add_vertex(verts[i])
	st.generate_normals()
	var mesh := st.commit()
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("crown", tex)
	mat.set_shader_parameter("sway", sway)
	mesh.surface_set_material(0, mat)
	return mesh


func _place_boreal(terrain: TerrainWorld, cover: Image) -> void:
	var span := float(terrain.field.cols - 1) * terrain.field.spacing
	var water := float(terrain.spec["water"]) if terrain.spec.get("water") != null else -9999.0
	var spawn := Vector2(float(terrain.spec["spawn"][0]), float(terrain.spec["spawn"][1]))
	var near_s: Array[Transform3D] = []
	var near_f: Array[Transform3D] = []
	var mid_s: Array[Transform3D] = []
	var mid_f: Array[Transform3D] = []
	var far_s: Array[Transform3D] = []
	var far_f: Array[Transform3D] = []
	var near_s_c: Array[Color] = []
	var near_f_c: Array[Color] = []
	var mid_s_c: Array[Color] = []
	var mid_f_c: Array[Color] = []
	var far_s_c: Array[Color] = []
	var far_f_c: Array[Color] = []
	var photo: Image = terrain.color_tex.get_image() if terrain.color_tex != null else null
	var ndvi_tex := load("res://data/ile_ndvi.png") as Texture2D
	var ndvi: Image = ndvi_tex.get_image() if ndvi_tex != null else null
	var birch_near: Array[Transform3D] = []
	var shrubs: Array[Transform3D] = []
	var rocks: Array[Transform3D] = []
	var width := cover.get_width()
	var height := cover.get_height()
	var step := 1
	for y in range(0, height, step):
		for x in range(0, width, step):
			var px := cover.get_pixel(x, y)
			var east := float(x) / float(width - 1) * span
			var north := (1.0 - float(y) / float(height - 1)) * span
			east += (_hash(x, y) - 0.5) * span / float(width) * float(step)
			north += (_hash(x + 3, y + 1) - 0.5) * span / float(height) * float(step)
			var dist := Vector2(east, north).distance_to(spawn)
			if dist < 22.0:
				continue
			var tree := px.r
			var shore := px.a
			if shore > 0.5 and dist < 160.0 and rocks.size() < 70 and _hash(x + 2, y) > 0.78:
				var rh := terrain.sample(east, north)
				if rh > water + 0.4:
					rocks.append(_xf(east, rh - 0.15, north, _hash(x, y + 4) * TAU, 0.45 + _hash(x + 6, y) * 1.1))
			if dist < 160.0 and shrubs.size() < 140 and shore < 0.28 and px.b > 0.15 and _hash(x, y + 9) > 0.55:
				var sh := terrain.sample(east, north)
				if sh > water + 1.2:
					shrubs.append(_xf(east, sh, north, _hash(x + 1, y) * TAU, 0.7 + _hash(x, y + 5) * 0.8))
			if tree < 0.42 or shore > 0.55:
				continue
			if dist < 85.0 and near_s.size() + near_f.size() + birch_near.size() >= 340:
				continue
			if dist >= 85.0 and dist < 260.0 and mid_s.size() + mid_f.size() >= 1100:
				continue
			if dist >= 260.0 and far_s.size() + far_f.size() >= 2800:
				continue
			var hh := terrain.sample(east, north)
			if hh < water + 1.5:
				continue
			var pix := _raster_at(photo, east, north, span)
			var veg := _raster_at(ndvi, east, north, span).r if ndvi != null else 1.0
			var green := pix.g - maxf(pix.r, pix.b)
			# Imagery tree mask plus the land-cover weight. Bare shore and rock stay open.
			if (photo != null and green < 0.01 and veg < 0.62) or shore > 0.62:
				continue
			var tall := 0.62 + _hash(x + 5, y + 2) * 0.63
			if px.g > 0.4 or veg < 0.7:
				tall *= 0.78
			var yaw := _hash(x + 8, y) * TAU
			var crown_m := _crown_metres(photo, east, north, span)
			var xz := clampf(crown_m / 1.35, 0.55, 1.75)
			var xf := _xf_crown(east, hh - 0.25, north, yaw, xz, tall * 1.75)
			var lum := (pix.r + pix.g + pix.b) / 3.0
			var gain := clampf(0.62 / maxf(lum, 0.05), 0.5, 1.8)
			var tint := Color(clampf(pix.r * gain, 0.0, 1.0), clampf(pix.g * gain, 0.0, 1.0), clampf(pix.b * gain, 0.0, 1.0))
			var fir := xz > 1.12
			if dist < 85.0:
				if fir:
					near_f.append(xf)
					near_f_c.append(tint)
				else:
					near_s.append(xf)
					near_s_c.append(tint)
			elif dist < 260.0:
				if fir:
					mid_f.append(xf)
					mid_f_c.append(tint)
				else:
					mid_s.append(xf)
					mid_s_c.append(tint)
			else:
				if fir:
					far_f.append(xf)
					far_f_c.append(tint)
				else:
					far_s.append(xf)
					far_s_c.append(tint)
	var far_spruce: Array[Transform3D] = []
	var far_fir: Array[Transform3D] = []
	var far_spruce_c: Array[Color] = []
	var far_fir_c: Array[Color] = []
	far_spruce.append_array(mid_s)
	far_spruce.append_array(far_s)
	far_fir.append_array(mid_f)
	far_fir.append_array(far_f)
	far_spruce_c.append_array(mid_s_c)
	far_spruce_c.append_array(far_s_c)
	far_fir_c.append_array(mid_f_c)
	far_fir_c.append_array(far_f_c)
	_spawn(spruce_mesh, near_s, true, 0.0, 130.0, near_s_c)
	_spawn(fir_mesh, near_f, true, 0.0, 130.0, near_f_c)
	_spawn(birch_card, birch_near, true, 0.0, 140.0)
	_spawn(spruce_octa, far_spruce, false, 80.0, 1600.0, far_spruce_c)
	_spawn(fir_octa, far_fir, false, 80.0, 1600.0, far_fir_c)
	_spawn(shrub_card, shrubs, false, 0.0, 95.0)
	for mesh in boulders:
		_spawn(mesh, rocks, true, 0.0, 180.0)
	var trunks: Array[Transform3D] = []
	for item in near_s:
		if trunks.size() < 36 and Vector2(item.origin.x, item.origin.z).distance_to(spawn) < 40.0:
			trunks.append(item)
	_collide(trunks, 0.35, 8.0)
	_plant_yard_saplings(terrain, spawn, water)
	print("boreal near ", near_s.size() + near_f.size(), " mid ", mid_s.size() + mid_f.size(), " far ", far_s.size() + far_f.size(), " shrubs ", shrubs.size(), " saplings ", saplings.size())


func _collide(items: Array[Transform3D], radius: float, height: float) -> void:
	for xf in items:
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		var shape := CollisionShape3D.new()
		var cap := CapsuleShape3D.new()
		cap.radius = radius
		cap.height = height
		shape.shape = cap
		shape.position = Vector3(0.0, height * 0.45, 0.0)
		body.add_child(shape)
		body.position = xf.origin
		add_child(body)


func _log_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sides := 6
	var length := 3.2
	var radius := 0.16
	for i in sides:
		var a0 := TAU * float(i) / float(sides)
		var a1 := TAU * float(i + 1) / float(sides)
		var x0 := Vector3(-length * 0.5, cos(a0) * radius, sin(a0) * radius)
		var x1 := Vector3(length * 0.5, cos(a0) * radius, sin(a0) * radius)
		var y0 := Vector3(-length * 0.5, cos(a1) * radius, sin(a1) * radius)
		var y1 := Vector3(length * 0.5, cos(a1) * radius, sin(a1) * radius)
		for p in [x0, x1, y0, y0, x1, y1]:
			st.set_color(Color(0.32, 0.2, 0.1))
			st.add_vertex(p)
	st.generate_normals()
	var mesh := st.commit()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.34, 0.22, 0.12)
	mat.roughness = 0.92
	mesh.surface_set_material(0, mat)
	return mesh


func _log_xf(x: float, y: float, z: float, yaw: float) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw), Vector3(x, y, z))


func _xf(x: float, y: float, z: float, yaw: float, scale: float) -> Transform3D:
	var basis := Basis(Vector3.UP, yaw).scaled(Vector3(scale, scale, scale))
	return Transform3D(basis, Vector3(x, y, z))


func _slope(terrain: TerrainWorld, x: float, z: float) -> float:
	var h := terrain.sample(x, z)
	var hx := terrain.sample(x + 4.0, z) - h
	var hz := terrain.sample(x, z + 4.0) - h
	return clampf(Vector2(hx, hz).length() / 4.0, 0.0, 1.0)


func _baked_tree(path: String) -> ArrayMesh:
	var packed := load(path) as PackedScene
	if packed == null:
		return null
	var root := packed.instantiate()
	var mi := _first_mesh(root)
	if mi == null or mi.mesh == null:
		root.free()
		return null
	var src := mi.mesh
	var xf := mi.transform
	var birch := path.contains("birch")
	var out := ArrayMesh.new()
	var leaf_n := 0
	for s in src.get_surface_count():
		var arrays: Array = src.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		for i in verts.size():
			verts[i] = xf * verts[i]
		if not norms.is_empty():
			var basis := xf.basis
			for i in norms.size():
				norms[i] = (basis * norms[i]).normalized()
			arrays[Mesh.ARRAY_NORMAL] = norms
		var mat := src.surface_get_material(s)
		var leaf := false
		if birch and mat is StandardMaterial3D:
			var tint := (mat as StandardMaterial3D).albedo_color
			var pale := tint.r > 0.35 and tint.g > 0.35
			var black := tint.r < 0.1 and tint.g < 0.1
			leaf = not pale and not black
			if leaf:
				leaf_n += 1
				# The second shell sits just outside the first so the crown
				# reads as leaves instead of one z-fighting blob.
				if leaf_n > 1:
					var spread := 1.12
					for i in verts.size():
						verts[i].x *= spread
						verts[i].z *= spread
						verts[i].y *= 1.04
		arrays[Mesh.ARRAY_VERTEX] = verts
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		if mat is BaseMaterial3D:
			mat = mat.duplicate()
			(mat as BaseMaterial3D).cull_mode = BaseMaterial3D.CULL_DISABLED
			if leaf and mat is StandardMaterial3D:
				(mat as StandardMaterial3D).albedo_color = Color(0.64, 0.74, 0.36)
				(mat as StandardMaterial3D).roughness = 0.7
		out.surface_set_material(out.get_surface_count() - 1, mat)
	root.free()
	return out


func _first_mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		return node
	for child in node.get_children():
		var found := _first_mesh(child)
		if found:
			return found
	return null


func _spawn_variants(meshes: Array, items: Array[Transform3D], shadows: bool, begin: float, end: float) -> void:
	if meshes.is_empty() or items.is_empty():
		return
	var buckets: Array = []
	for _m in meshes:
		buckets.append([] as Array[Transform3D])
	for i in items.size():
		(buckets[i % meshes.size()] as Array[Transform3D]).append(items[i])
	for i in meshes.size():
		_spawn(meshes[i], buckets[i], shadows, begin, end)


func _meshes(path: String) -> Array:
	var packed := load(path) as PackedScene
	if packed == null:
		return []
	var root := packed.instantiate()
	var found: Array = []
	_collect(root, found)
	root.free()
	return found


func _collect(node: Node, found: Array) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			found.append(mi.mesh)
	for child in node.get_children():
		_collect(child, found)


func _spawn(mesh: Mesh, items: Array[Transform3D], shadows: bool, begin: float, end: float, tints: Array[Color] = []) -> void:
	if mesh == null or items.is_empty():
		return
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.use_colors = tints.size() == items.size()
	multi.mesh = mesh
	multi.instance_count = items.size()
	for i in items.size():
		multi.set_instance_transform(i, items[i])
		if multi.use_colors:
			multi.set_instance_color(i, tints[i])
	var node := MultiMeshInstance3D.new()
	node.multimesh = multi
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if end > 0.0:
		node.visibility_range_begin = begin
		node.visibility_range_end = end
		node.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	add_child(node)


func _birch_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_marked_trunk(st, 5.4, 0.13, 0.055)
	_sphere(st, Vector3(0.0, 4.6, 0.0), 1.35, Color(0.62, 0.78, 0.38))
	_sphere(st, Vector3(0.35, 5.5, 0.15), 0.85, Color(0.72, 0.84, 0.46))
	_sphere(st, Vector3(-0.28, 5.15, -0.2), 0.7, Color(0.66, 0.8, 0.4))
	st.generate_normals()
	var mesh := st.commit()
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/foliage.gdshader")
	mesh.surface_set_material(0, mat)
	return mesh


func _birch_impostor() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_marked_trunk(st, 4.6, 0.14, 0.06)
	_sphere(st, Vector3(0.0, 4.4, 0.0), 1.5, Color(0.64, 0.78, 0.4))
	st.generate_normals()
	var mesh := st.commit()
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/foliage.gdshader")
	mesh.surface_set_material(0, mat)
	return mesh


func _impostor() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_cone(st, 0.0, 1.4, 0.11, 0.06, Color(0.22, 0.14, 0.08))
	_cone(st, 1.0, 3.1, 0.9, 0.5, Color(0.045, 0.12, 0.055))
	_cone(st, 2.4, 4.8, 0.66, 0.28, Color(0.06, 0.15, 0.065))
	_cone(st, 4.0, 6.6, 0.34, 0.02, Color(0.08, 0.18, 0.08))
	st.generate_normals()
	var mesh := st.commit()
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/foliage.gdshader")
	mesh.surface_set_material(0, mat)
	return mesh


func _trim_trunk(mesh: Mesh) -> Mesh:
	var src := mesh as ArrayMesh
	if src == null:
		return mesh
	var out := ArrayMesh.new()
	for s in src.get_surface_count():
		var arrays: Array = src.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		if idx.is_empty():
			out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			out.surface_set_material(out.get_surface_count() - 1, src.surface_get_material(s))
			continue
		var kept := PackedInt32Array()
		var i := 0
		while i + 2 < idx.size():
			var mid := (verts[idx[i]] + verts[idx[i + 1]] + verts[idx[i + 2]]) / 3.0
			var rad := Vector2(mid.x, mid.z).length()
			# Bark only. The lowest wide triangles are the red branch spikes.
			var spike := s == 0 and mid.y < 2.9 and rad > 0.28
			if not spike:
				kept.append(idx[i])
				kept.append(idx[i + 1])
				kept.append(idx[i + 2])
			i += 3
		arrays[Mesh.ARRAY_INDEX] = kept
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		out.surface_set_material(out.get_surface_count() - 1, src.surface_get_material(s))
	return out


func _marked_trunk(st: SurfaceTool, height: float, r0: float, r1: float) -> void:
	var rings := 16
	var sides := 8
	for ring in rings:
		var t := float(ring) / float(rings - 1)
		var y := t * height
		var rad := lerpf(r0, r1, t)
		var band := ring % 4 == 2
		for i in sides:
			var a0 := TAU * float(i) / float(sides)
			var a1 := TAU * float(i + 1) / float(sides)
			var mark := band or (i == 2 and ring % 3 == 0)
			var color := Color(0.18, 0.2, 0.18) if mark else Color(0.93, 0.94, 0.91)
			var y1 := (float(ring + 1) / float(rings - 1)) * height
			if ring == rings - 1:
				break
			var rad1 := lerpf(r0, r1, float(ring + 1) / float(rings - 1))
			var b0 := Vector3(cos(a0) * rad, y, sin(a0) * rad)
			var b1 := Vector3(cos(a1) * rad, y, sin(a1) * rad)
			var t0 := Vector3(cos(a0) * rad1, y1, sin(a0) * rad1)
			var t1 := Vector3(cos(a1) * rad1, y1, sin(a1) * rad1)
			for p in [b0, t0, b1, b1, t0, t1]:
				st.set_color(color)
				st.add_vertex(p)


func _sphere(st: SurfaceTool, center: Vector3, radius: float, color: Color) -> void:
	var lat := 6
	var lon := 8
	for j in lat:
		var v0 := PI * float(j) / float(lat)
		var v1 := PI * float(j + 1) / float(lat)
		for i in lon:
			var u0 := TAU * float(i) / float(lon)
			var u1 := TAU * float(i + 1) / float(lon)
			var p00 := center + Vector3(sin(v0) * cos(u0), cos(v0), sin(v0) * sin(u0)) * radius
			var p10 := center + Vector3(sin(v0) * cos(u1), cos(v0), sin(v0) * sin(u1)) * radius
			var p01 := center + Vector3(sin(v1) * cos(u0), cos(v1), sin(v1) * sin(u0)) * radius
			var p11 := center + Vector3(sin(v1) * cos(u1), cos(v1), sin(v1) * sin(u1)) * radius
			for p in [p00, p01, p10, p10, p01, p11]:
				st.set_color(color)
				st.add_vertex(p)


func _spruce_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_whorl(st, 0.0, 1.5, 0.12, 0.05, Color(0.24, 0.15, 0.08), 7)
	for i in 8:
		var t := float(i) / 7.0
		var y0 := 0.7 + t * 6.2
		var rad := lerpf(1.15, 0.08, t)
		var green := Color(0.07, 0.2, 0.09).lerp(Color(0.14, 0.28, 0.12), t)
		_whorl(st, y0, y0 + lerpf(1.35, 0.7, t), rad, rad * 0.12, green, 8)
	st.generate_normals()
	var mesh := st.commit()
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/crown.gdshader")
	mesh.surface_set_material(0, mat)
	return mesh


func _fir_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_whorl(st, 0.0, 1.3, 0.16, 0.07, Color(0.28, 0.17, 0.09), 7)
	for i in 6:
		var t := float(i) / 5.0
		var y0 := 0.6 + t * 5.4
		var rad := lerpf(1.55, 0.16, t)
		var green := Color(0.06, 0.16, 0.07).lerp(Color(0.12, 0.24, 0.1), t)
		_whorl(st, y0, y0 + lerpf(1.7, 0.9, t), rad, rad * 0.2, green, 8)
	st.generate_normals()
	var mesh := st.commit()
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/crown.gdshader")
	mesh.surface_set_material(0, mat)
	return mesh


func _whorl(st: SurfaceTool, y0: float, y1: float, r0: float, r1: float, color: Color, sides: int) -> void:
	for i in sides:
		var a0 := TAU * float(i) / float(sides)
		var a1 := TAU * float(i + 1) / float(sides)
		var b0 := Vector3(cos(a0) * r0, y0, sin(a0) * r0)
		var b1 := Vector3(cos(a1) * r0, y0, sin(a1) * r0)
		var t0 := Vector3(cos(a0) * r1, y1, sin(a0) * r1)
		var t1 := Vector3(cos(a1) * r1, y1, sin(a1) * r1)
		for p in [b0, t0, b1, b1, t0, t1]:
			st.set_color(color)
			st.set_uv(Vector2(0.5, clampf(p.y / 8.0, 0.0, 1.0)))
			st.add_vertex(p)


func _cone(st: SurfaceTool, y0: float, y1: float, r0: float, r1: float, color: Color) -> void:
	var sides := 6
	for i in sides:
		var a0 := TAU * float(i) / float(sides)
		var a1 := TAU * float(i + 1) / float(sides)
		var b0 := Vector3(cos(a0) * r0, y0, sin(a0) * r0)
		var b1 := Vector3(cos(a1) * r0, y0, sin(a1) * r0)
		var t0 := Vector3(cos(a0) * r1, y1, sin(a0) * r1)
		var t1 := Vector3(cos(a1) * r1, y1, sin(a1) * r1)
		for p in [b0, t0, b1, b1, t0, t1]:
			st.set_color(color)
			st.add_vertex(p)


func _hash(x: int, y: int) -> float:
	var n := x * 374761393 + y * 668265263
	n = (n ^ (n >> 13)) * 1274126177
	return float(n & 0x7fffffff) / 2147483647.0


func clear() -> void:
	saplings.clear()
	for child in get_children():
		child.queue_free()


func _process(_dt: float) -> void:
	if terrain_ref == null:
		return
	for log in felled_logs:
		if not is_instance_valid(log) or log.freeze:
			continue
		var ground := terrain_ref.sample(log.global_position.x, log.global_position.z)
		if log.global_position.y < ground + 0.08:
			var at := log.global_position
			at.y = ground + 0.16
			log.global_position = at
			var vel := log.linear_velocity
			vel.y = maxf(vel.y, 0.0)
			log.linear_velocity = vel


func _crown_metres(photo: Image, east: float, north: float, span: float) -> float:
	if photo == null:
		return 1.3
	var cx := int(east / span * float(photo.get_width() - 1))
	var cy := int((1.0 - north / span) * float(photo.get_height() - 1))
	var max_r := 0.0
	var metres_per := span / float(photo.get_width())
	for dy in range(-4, 5):
		for dx in range(-4, 5):
			var px := clampi(cx + dx, 0, photo.get_width() - 1)
			var py := clampi(cy + dy, 0, photo.get_height() - 1)
			var sample := photo.get_pixel(px, py)
			if sample.g > sample.r + 0.012 and sample.g > 0.08:
				max_r = maxf(max_r, Vector2(float(dx), float(dy)).length())
	return clampf(max_r * metres_per, 0.8, 2.6)


func _xf_crown(x: float, y: float, z: float, yaw: float, crown: float, height: float) -> Transform3D:
	var basis := Basis(Vector3.UP, yaw).scaled(Vector3(crown, height, crown))
	return Transform3D(basis, Vector3(x, y, z))


func _octa_card(path: String, height: float, half_w: float) -> ArrayMesh:
	var tex := load(path) as Texture2D
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var verts: Array[Vector3] = [
		Vector3(-half_w, 0.0, 0.0),
		Vector3(-half_w, height, 0.0),
		Vector3(half_w, 0.0, 0.0),
		Vector3(half_w, 0.0, 0.0),
		Vector3(-half_w, height, 0.0),
		Vector3(half_w, height, 0.0),
	]
	var uvs: Array[Vector2] = [
		Vector2(0, 0), Vector2(0, 1), Vector2(1, 0),
		Vector2(1, 0), Vector2(0, 1), Vector2(1, 1),
	]
	for i in verts.size():
		st.set_color(Color(1, 1, 1))
		st.set_uv(uvs[i])
		st.add_vertex(verts[i])
	st.generate_normals()
	var mesh := st.commit()
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/impostor.gdshader")
	mat.set_shader_parameter("atlas", tex)
	mesh.surface_set_material(0, mat)
	return mesh


func _plant_yard_saplings(terrain: TerrainWorld, spawn: Vector2, water: float) -> void:
	var spots: Array[Vector2] = [Vector2(6.0, 3.5), Vector2(8.0, -2.0), Vector2(-5.0, 6.0), Vector2(4.0, 8.0)]
	var diameters: Array[float] = [0.05, 0.062, 0.055, 0.09]
	for i in spots.size():
		var at: Vector2 = spawn + spots[i]
		var h := terrain.sample(at.x, at.y)
		if h < water + 1.2:
			continue
		plant_sapling(at.x, h, at.y, diameters[i])


func plant_sapling(x: float, y: float, z: float, diameter: float) -> Dictionary:
	var mi := MeshInstance3D.new()
	mi.mesh = spruce_mesh if spruce_mesh != null else spruce_near
	mi.scale = Vector3(0.22, 0.32, 0.22)
	mi.position = Vector3(x, y, z)
	add_child(mi)
	var rec := {"x": x, "y": y, "z": z, "diameter": diameter, "alive": true, "node": mi}
	saplings.append(rec)
	return rec


func try_saw(at: Vector3, reach: float) -> void:
	for rec in saplings:
		if not bool(rec.get("alive", false)):
			continue
		if float(rec.get("diameter", 1.0)) >= 0.0762:
			continue
		var flat := Vector2(at.x, at.z).distance_to(Vector2(float(rec["x"]), float(rec["z"])))
		if flat > reach:
			continue
		fell(rec)
		return


func fell(rec: Dictionary) -> RigidBody3D:
	rec["alive"] = false
	var node: Node = rec.get("node")
	if node != null and is_instance_valid(node):
		node.queue_free()
		rec["node"] = null
	var body := RigidBody3D.new()
	body.mass = 28.0
	body.collision_layer = 4
	body.collision_mask = 1
	body.linear_damp = 0.4
	body.angular_damp = 1.2
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = maxf(float(rec["diameter"]) * 0.5, 0.025)
	cyl.height = 2.4
	shape.shape = cyl
	shape.rotation.z = PI * 0.5
	body.add_child(shape)
	var mi := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = cyl.radius
	mesh.bottom_radius = cyl.radius
	mesh.height = 2.4
	mi.mesh = mesh
	mi.rotation.z = PI * 0.5
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.42, 0.27, 0.14)
	mat.roughness = 0.9
	mi.material_override = mat
	body.add_child(mi)
	body.position = Vector3(float(rec["x"]), float(rec["y"]) + 0.22, float(rec["z"]))
	var parent := get_parent()
	if parent:
		parent.add_child(body)
	else:
		add_child(body)
	felled_logs.append(body)
	return body
