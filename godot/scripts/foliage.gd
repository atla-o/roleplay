class_name Foliage
extends Node3D

var pines: Array = []
var grasses: Array = []
var bushes: Array = []
var boulders: Array = []

func _ready() -> void:
	for path in ["res://assets/models/pine_a.glb", "res://assets/models/pine_b.glb"]:
		for mesh in _meshes(path):
			pines.append(_trim_trunk(mesh))
	grasses = _meshes("res://assets/models/grass_short.glb") + _meshes("res://assets/models/grass_tall.glb")
	bushes = _meshes("res://assets/models/bush.glb")
	boulders = _meshes("res://assets/models/boulder.glb")


func rebuild(terrain: TerrainWorld, albedo: Texture2D) -> void:
	for child in get_children():
		child.queue_free()
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
			var gap := 6.0 if excess > 0.11 else 10.0
			var n := maxi(int(cell / gap), 1)
			for iy in n:
				for ix in n:
					var jx := _hash(x + ix * 3 + 1, y + iy * 2)
					var jz := _hash(x + ix + 4, y + iy * 5 + 2)
					var birch_stand: bool = jx > 0.78 or (lum > 0.18 and excess < 0.12)
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
					if d2 < 170.0 and near.size() + birch_near.size() < 1200:
						if birch_stand and jx > 0.42:
							birch_near.append(_xf(ex, hh, nz, yaw, sc))
						else:
							near.append(_xf(ex, hh, nz, yaw, sc))
					elif d2 < 1400.0 and far.size() + birch_far.size() < 7000:
						if birch_stand and jx > 0.42:
							birch_far.append(_xf(ex, hh, nz, yaw, sc * 1.2))
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
	var spots: Array[Vector2] = [Vector2(-16.0, 20.0), Vector2(8.0, 14.0), Vector2(-7.0, 28.0)]
	for spot in spots:
		var p: Vector2 = spawn + spot
		var bh := terrain.sample(p.x, p.y)
		if bh > water + 1.5:
			birch_near.append(_xf(p.x, bh - 0.05, p.y, 0.6, 1.2))
	var birch_mesh := _birch_mesh()
	for mesh in pines:
		_spawn(mesh, near, true, 0.0, 230.0)
	_spawn(birch_mesh, birch_near, true, 0.0, 230.0)
	_spawn(_impostor(), far, false, 160.0, 1700.0)
	_spawn(_birch_impostor(), birch_far, false, 160.0, 1700.0)
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


func _spawn(mesh: Mesh, items: Array[Transform3D], shadows: bool, begin: float, end: float) -> void:
	if mesh == null or items.is_empty():
		return
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = mesh
	multi.instance_count = items.size()
	for i in items.size():
		multi.set_instance_transform(i, items[i])
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
	_cone(st, 0.0, 1.6, 0.16, 0.1, Color(0.28, 0.16, 0.08))
	_cone(st, 1.3, 3.4, 1.15, 0.72, Color(0.1, 0.24, 0.1))
	_cone(st, 2.8, 5.1, 0.85, 0.42, Color(0.14, 0.3, 0.12))
	_cone(st, 4.5, 6.8, 0.48, 0.04, Color(0.22, 0.38, 0.16))
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
			# The stylized pines flare into red branch spikes just above the soil.
			if not (mid.y < 1.75 and rad > 0.34):
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
