class_name TrackedVehicle
extends Node3D

var terrain: TerrainWorld
var yaw := 0.0
var throttle := 0.0
var steer := 0.0
var blade := 0.18
var speed := 0.0
var travel := 0.0
var mass_kg := 26000.0
var engine_n := 90000.0
var visual: Node3D
var blade_pivot: Node3D

func _ready() -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 2
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(3.6, 1.7, 6.2)
	shape.shape = box
	shape.position = Vector3(0.0, 1.15, 0.2)
	body.add_child(shape)
	add_child(body)
	_build_visual()


func forward() -> Vector3:
	return Vector3(sin(yaw), 0.0, cos(yaw))


func _physics_process(dt: float) -> void:
	if terrain == null:
		return
	dt = minf(dt, 0.05)
	var fwd := forward()
	var right := Vector3(fwd.z, 0.0, -fwd.x)
	var origin := global_position
	var wheels := [
		origin + right * 1.35 + fwd * 2.1,
		origin - right * 1.35 + fwd * 2.1,
		origin + right * 1.35 - fwd * 2.1,
		origin - right * 1.35 - fwd * 2.1,
	]
	var heights: Array[float] = []
	var count := 0
	var sum_h := 0.0
	for wheel in wheels:
		var h := terrain.sample(wheel.x, wheel.z)
		heights.append(h)
		sum_h += h
		count += 1
	var ground := sum_h / float(count)
	var front := (heights[0] + heights[1]) * 0.5
	var back := (heights[2] + heights[3]) * 0.5
	var left := (heights[1] + heights[3]) * 0.5
	var right_h := (heights[0] + heights[2]) * 0.5
	var pitch := atan2(back - front, 4.2)
	var roll := atan2(left - right_h, 2.7)
	var slope := sin(pitch)
	var accel := throttle * engine_n / mass_kg
	accel -= slope * 9.8
	accel -= speed * 0.35
	if absf(throttle) < 0.05:
		accel -= speed * 1.6
	speed = clampf(speed + accel * dt, -3.2, 4.2)
	if absf(speed) < 0.05 and absf(throttle) < 0.05:
		speed = 0.0
	yaw += steer * clampf(absf(speed), 0.4, 2.2) * 0.55 * dt
	fwd = forward()
	var step := fwd * speed * dt
	global_position += step
	var ride := ground + 0.42
	global_position.y = lerp(global_position.y, ride, 1.0 - exp(-dt * 8.0))
	var n := Vector3(sin(roll), cos(roll) * cos(pitch), sin(pitch)).normalized()
	var f := (fwd - n * fwd.dot(n)).normalized()
	var r := n.cross(f).normalized()
	f = r.cross(n).normalized()
	global_transform.basis = Basis(r, n, f)
	yaw = atan2(f.x, f.z)
	if blade_pivot:
		blade_pivot.rotation.x = -blade
	if blade < 0.02 and absf(speed) > 0.35:
		travel += absf(speed) * dt
		if travel > 0.55:
			travel = 0.0
			var edge := ground + sin(blade) * 1.25
			var at := global_position + f * 3.15
			Soil.plane_blade(terrain.field, at.x, at.z, f.x, f.z, 3.6, edge, float(terrain.spec["repose"]))
			terrain.refresh_edits()


func _build_visual() -> void:
	visual = Node3D.new()
	add_child(visual)
	var paint := _mat(Color(0.62, 0.28, 0.07), 0.52, 0.08)
	var dark := _mat(Color(0.1, 0.1, 0.11), 0.78, 0.2)
	var metal := _mat(Color(0.62, 0.64, 0.68), 0.32, 0.86)
	var rubber := _mat(Color(0.07, 0.07, 0.08), 0.92, 0.0)
	var glass := StandardMaterial3D.new()
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.albedo_color = Color(0.55, 0.72, 0.82, 0.38)
	glass.roughness = 0.08
	glass.metallic = 0.15
	for side in [-1.0, 1.0]:
		_box(visual, Vector3(side * 1.42, 0.48, 0.05), Vector3(0.62, 0.95, 4.9), rubber)
		_box(visual, Vector3(side * 1.68, 0.55, 0.05), Vector3(0.08, 0.7, 4.5), dark)
		for z in [-1.7, -0.85, 0.0, 0.85, 1.7]:
			_wheel(visual, Vector3(side * 1.42, 0.38, z), 0.32, rubber)
		_wheel(visual, Vector3(side * 1.42, 0.55, 2.25), 0.42, dark)
		_wheel(visual, Vector3(side * 1.42, 0.55, -2.15), 0.4, dark)
	_box(visual, Vector3(0.0, 0.72, -0.15), Vector3(2.15, 0.55, 3.4), paint)
	_box(visual, Vector3(0.0, 1.15, -0.35), Vector3(1.9, 0.42, 2.3), paint)
	_box(visual, Vector3(0.0, 1.72, -1.35), Vector3(1.55, 0.95, 1.35), paint)
	_box(visual, Vector3(0.0, 1.85, -1.35), Vector3(1.25, 0.62, 0.06), glass)
	_box(visual, Vector3(0.35, 2.15, -1.7), Vector3(0.12, 0.55, 0.12), dark)
	var light_mat := _mat(Color(1.0, 0.85, 0.45), 0.4, 0.0)
	light_mat.emission_enabled = true
	light_mat.emission = Color(1.0, 0.8, 0.4)
	light_mat.emission_energy_multiplier = 2.0
	_box(visual, Vector3(-0.7, 1.15, 1.55), Vector3(0.18, 0.12, 0.08), light_mat)
	_box(visual, Vector3(0.7, 1.15, 1.55), Vector3(0.18, 0.12, 0.08), light_mat)
	blade_pivot = Node3D.new()
	blade_pivot.position = Vector3(0.0, 0.95, 2.45)
	visual.add_child(blade_pivot)
	_box(blade_pivot, Vector3(0.0, 0.05, 0.72), Vector3(4.4, 1.45, 0.16), metal)
	_box(blade_pivot, Vector3(0.0, -0.62, 0.78), Vector3(4.4, 0.12, 0.22), dark)
	_box(blade_pivot, Vector3(-1.55, 0.15, 0.15), Vector3(0.12, 0.12, 1.15), dark)
	_box(blade_pivot, Vector3(1.55, 0.15, 0.15), Vector3(0.12, 0.12, 1.15), dark)


func _box(parent: Node3D, center: Vector3, size: Vector3, material: Material) -> void:
	var mesh_node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh_node.mesh = mesh
	mesh_node.position = center
	mesh_node.material_override = material
	parent.add_child(mesh_node)


func _wheel(parent: Node3D, center: Vector3, radius: float, material: Material) -> void:
	var mesh_node := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = 0.5
	mesh.radial_segments = 12
	mesh_node.mesh = mesh
	mesh_node.position = center
	mesh_node.rotation.z = PI * 0.5
	mesh_node.material_override = material
	parent.add_child(mesh_node)


func _mat(color: Color, roughness: float, metallic: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	mat.metallic = metallic
	return mat
