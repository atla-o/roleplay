class_name Foliage
extends Node3D

var pines: Array = []
var grasses: Array = []
var bushes: Array = []
var boulders: Array = []

func _ready() -> void:
	pines = _meshes("res://assets/models/pine_a.glb") + _meshes("res://assets/models/pine_b.glb")
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
	var step := 6
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
			if dist < 10.0:
				continue
			var slope := _slope(terrain, east, north)
			if roll > 0.35 and rocks.size() < 900 and (slope > 0.08 or not forest):
				var rs := 0.8 + _hash(x + 4, y) * (3.2 if slope > 0.3 else 1.6)
				rocks.append(_xf(east, h - 0.2, north, roll * TAU, rs))
			if not forest or not green:
				continue
			if roll > 0.12 and near.size() < 720 and dist < 640.0:
				var s := 0.75 + _hash(x + 2, y + 1) * 0.7
				near.append(_xf(east + (_hash(x, y + 3) - 0.5) * 6.0, h, north, roll * TAU, s))
			elif far.size() < 1400:
				var s2 := 0.9 + _hash(x + 6, y) * 0.8
				far.append(_xf(east, h, north, roll * TAU, s2))
			if _hash(x + 8, y + 8) > 0.38 and grass.size() < 1400:
				grass.append(_xf(east, h, north, roll * TAU, 0.8 + roll * 0.7))
			if _hash(x + 1, y + 9) > 0.42 and shrub.size() < 1100:
				shrub.append(_xf(east, h, north, roll * 3.0, 0.7 + roll * 0.6))
			if _hash(x + 5, y + 2) > 0.86 and logs.size() < 220:
				logs.append(_log_xf(east, h + 0.18, north, roll * TAU))
	for mesh in pines:
		_spawn(mesh, near, true, 0.0, 260.0)
	_spawn(_impostor(), far, false, 180.0, 1400.0)
	for mesh in grasses:
		_spawn(mesh, grass, false, 0.0, 90.0)
	for mesh in bushes:
		_spawn(mesh, shrub, false, 0.0, 160.0)
	for mesh in boulders:
		_spawn(mesh, rocks, true, 0.0, 500.0)
	_spawn(_log_mesh(), logs, true, 0.0, 180.0)
	_collide(near, 0.42, 5.5)
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
