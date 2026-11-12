class_name Foliage
extends Node3D

var tree_mesh: ArrayMesh
var shrub_mesh: ArrayMesh
var mat: ShaderMaterial

func _ready() -> void:
	mat = ShaderMaterial.new()
	mat.shader = load("res://shaders/foliage.gdshader")
	tree_mesh = _conifer()
	shrub_mesh = _shrub()


func rebuild(terrain: TerrainWorld, albedo: Texture2D) -> void:
	for child in get_children():
		child.queue_free()
	if not bool(terrain.spec.get("forest", false)):
		return
	var img := albedo.get_image()
	if img == null:
		return
	var span := float(terrain.field.cols - 1) * terrain.field.spacing
	var water := float(terrain.spec["water"]) if terrain.spec["water"] != null else -9999.0
	var trees: Array[Transform3D] = []
	var shrubs: Array[Transform3D] = []
	var spawn := Vector2(float(terrain.spec["spawn"][0]), float(terrain.spec["spawn"][1]))
	var step := 6
	for y in range(0, img.get_height(), step):
		for x in range(0, img.get_width(), step):
			var px := img.get_pixel(x, y)
			if px.g < px.r + 0.03 or px.g < 0.1:
				continue
			var roll := _hash(x, y)
			if roll < 0.28:
				continue
			var east := float(x) / float(img.get_width() - 1) * span
			var north := (1.0 - float(y) / float(img.get_height() - 1)) * span
			east += (_hash(x + 3, y) - 0.5) * 18.0
			north += (_hash(x, y + 5) - 0.5) * 18.0
			var h := terrain.sample(east, north)
			if h < water + 2.0:
				continue
			if Vector2(east, north).distance_to(spawn) < 28.0:
				continue
			var s := 0.75 + _hash(x + 9, y + 2) * 0.7
			var xf := Transform3D(Basis.IDENTITY.scaled(Vector3(s, s, s)).rotated(Vector3.UP, roll * TAU), Vector3(east, h, north))
			if px.g > px.r + 0.08 and trees.size() < 4200:
				trees.append(xf)
			elif shrubs.size() < 1800:
				shrubs.append(xf.scaled(Vector3(1.4, 0.7, 1.4)))
	_spawn(tree_mesh, trees, OS.has_feature("web") == false)
	_spawn(shrub_mesh, shrubs, false)


func _spawn(mesh: ArrayMesh, items: Array[Transform3D], shadows: bool) -> void:
	if items.is_empty():
		return
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = mesh
	multi.instance_count = items.size()
	for i in items.size():
		multi.set_instance_transform(i, items[i])
	var node := MultiMeshInstance3D.new()
	node.multimesh = multi
	node.material_override = mat
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)


func _conifer() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_frustum(st, 0.0, 3.2, 0.22, 0.14, Color(0.32, 0.18, 0.1), 7)
	_cards(st, 2.2, 2.6, 2.4, Color(0.12, 0.32, 0.13))
	_cards(st, 4.2, 2.4, 1.9, Color(0.16, 0.4, 0.16))
	_cards(st, 6.2, 2.2, 1.3, Color(0.28, 0.5, 0.2))
	_cards(st, 8.0, 1.6, 0.7, Color(0.45, 0.62, 0.28))
	st.generate_normals()
	return st.commit()


func _shrub() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_frustum(st, 0.0, 0.7, 0.7, 0.45, Color(0.24, 0.38, 0.16), 7)
	_frustum(st, 0.45, 1.15, 0.4, 0.08, Color(0.36, 0.5, 0.2), 6)
	st.generate_normals()
	return st.commit()


func _cards(st: SurfaceTool, y: float, height: float, width: float, color: Color) -> void:
	var hw := width * 0.5
	var y0 := y
	var y1 := y + height
	for angle in [0.0, PI * 0.5, PI * 0.25]:
		var c := cos(angle)
		var s := sin(angle)
		var a := Vector3(-hw * c, y0, -hw * s)
		var b := Vector3(hw * c, y0, hw * s)
		var d := Vector3(-hw * c, y1, -hw * s)
		var e := Vector3(hw * c, y1, hw * s)
		for p in [a, d, b, b, d, e]:
			st.set_color(color)
			st.add_vertex(p)


func _frustum(st: SurfaceTool, y0: float, y1: float, r0: float, r1: float, color: Color, sides: int) -> void:
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
