class_name YardMachine
extends RigidBody3D

## One-third-scale electric tracked carrier. Blade, grapple, and a saw that
## only takes stems under 3 inches. The dump trailer is part of the body so a
## log that is grappled stays with the machine over rough ground.

const BLADE := 0
const GRAPPLE := 1
const SAW := 2

var terrain: TerrainWorld
var foliage: Foliage
var throttle := 0.0
var steer := 0.0
var blade_angle := 0.35
var manipulate := false
var tool := BLADE
var carried_log: RigidBody3D
var trailer: Node3D
var attach: Node3D
var blade_node: Node3D
var grapple_node: Node3D
var saw_node: Node3D
var saw_disc: Node3D
var model: Node3D
var wheels: Array[Vector3] = []


func _ready() -> void:
	mass = 860.0
	gravity_scale = 1.0
	can_sleep = false
	continuous_cd = false
	linear_damp = 0.2
	angular_damp = 2.2
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0.0, 0.28, -0.05)
	collision_layer = 2
	collision_mask = 0
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.86, 0.62, 1.55)
	shape.shape = box
	shape.position = Vector3(0.0, 0.42, 0.05)
	add_child(shape)
	for side in [-1.0, 1.0]:
		for z in [-0.48, -0.16, 0.16, 0.48]:
			wheels.append(Vector3(side * 0.32, 0.16, z))
	_build()


func forward() -> Vector3:
	var f := global_transform.basis.z
	f.y = 0.0
	if f.length() < 0.001:
		return Vector3(0.0, 0.0, 1.0)
	return f.normalized()


func tool_name() -> String:
	match tool:
		GRAPPLE:
			return "Grapple"
		SAW:
			return "Saw"
		_:
			return "Blade"


func set_manipulate(on: bool) -> void:
	manipulate = on
	blade_angle = -0.42 if on else 0.35
	_pose()


func cycle_tool() -> void:
	tool = (tool + 1) % 3
	_show_tool()
	_pose()


func load_log(log: RigidBody3D) -> bool:
	if log == null or not is_instance_valid(log) or trailer == null:
		return false
	if global_position.distance_to(log.global_position) > 6.0:
		return false
	log.freeze = true
	log.linear_velocity = Vector3.ZERO
	log.angular_velocity = Vector3.ZERO
	log.collision_layer = 0
	log.collision_mask = 0
	log.reparent(trailer)
	log.position = Vector3(0.0, 0.34, -0.05)
	log.rotation = Vector3(0.0, 0.4, PI * 0.5)
	carried_log = log
	return true


func _physics_process(dt: float) -> void:
	if terrain == null or freeze:
		_pose()
		return
	dt = minf(dt, 0.05)
	var space := get_world_3d().direct_space_state
	var xf := global_transform
	var hits := 0
	for wheel in wheels:
		var from: Vector3 = xf * (wheel + Vector3(0.0, 0.22, 0.0))
		var to: Vector3 = from + Vector3.DOWN * 0.7
		var query := PhysicsRayQueryParameters3D.create(from, to, 1)
		query.exclude = [get_rid()]
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			continue
		hits += 1
		var dist: float = from.distance_to(hit.position)
		var compression := 0.28 - dist
		if compression > 0.0:
			var vn := linear_velocity.dot(Vector3.UP)
			apply_force(Vector3.UP * (compression * 22000.0 - vn * 2600.0), hit.position - global_position)
	if hits == 0:
		var ground := terrain.sample(global_position.x, global_position.z)
		if global_position.y < ground - 0.4:
			var t := global_transform
			t.origin.y = ground + 0.25
			global_transform = t
			linear_velocity.y = 0.0
	var fwd := forward()
	var right := global_transform.basis.x
	right.y = 0.0
	if right.length() > 0.001:
		right = right.normalized()
	var speed := linear_velocity.dot(fwd)
	var drive := clampf(throttle, -1.0, 1.0) * 2600.0
	apply_force(fwd * drive * (1.0 - steer * 0.7), xf.basis.x * -0.28)
	apply_force(fwd * drive * (1.0 + steer * 0.7), xf.basis.x * 0.28)
	if absf(speed) < 0.4 and absf(throttle) > 0.5:
		apply_central_force(fwd * throttle * 1600.0)
	var lat := linear_velocity.dot(right)
	apply_central_force(-right * lat * mass * 6.0)
	if absf(throttle) < 0.05:
		apply_central_force(-fwd * speed * mass * 2.4)
	if absf(speed) > 2.8:
		linear_velocity -= fwd * (speed - signf(speed) * 2.8) * 0.4
	if trailer:
		trailer.rotation.y = lerpf(trailer.rotation.y, -steer * 0.18, 1.0 - exp(-dt * 4.0))
	if saw_disc and tool == SAW and manipulate:
		saw_disc.rotate_z(dt * 18.0)
	_pose()
	_work(fwd, right, speed, dt)


func _work(fwd: Vector3, right: Vector3, speed: float, dt: float) -> void:
	if not manipulate or terrain == null:
		return
	if tool == SAW and foliage != null:
		var tip := global_position + fwd * 1.15
		foliage.try_saw(tip, 1.45)
		return
	if tool == GRAPPLE and foliage != null:
		for log in foliage.felled_logs:
			if is_instance_valid(log) and not log.freeze and global_position.distance_to(log.global_position) < 2.4:
				load_log(log)
				return
		return
	if tool != BLADE or absf(speed) < 0.2:
		return
	var at := global_position + fwd * 1.05
	var shoulder := global_position + right * 1.15
	var edge := terrain.sample(shoulder.x, shoulder.z) + blade_angle * 0.32
	terrain.cut_blade(at.x, at.z, fwd.x, fwd.z, 1.15, edge, float(terrain.spec.get("repose", 34.0)))
	if dt > 0.0 and absf(speed) > 0.3:
		terrain.stamp_tracks(global_position.x, global_position.z, fwd.x, fwd.z)


func _pose() -> void:
	if attach == null:
		return
	var down := -0.55 if manipulate else 0.15
	attach.rotation.x = lerpf(attach.rotation.x, down + blade_angle * 0.15, 0.4)
	if grapple_node:
		var jaw := 0.15 if manipulate else 0.7
		for child in grapple_node.get_children():
			if child.name == "jaw-l":
				(child as Node3D).rotation.z = jaw
			elif child.name == "jaw-r":
				(child as Node3D).rotation.z = -jaw


func _show_tool() -> void:
	if blade_node:
		blade_node.visible = tool == BLADE
	if grapple_node:
		grapple_node.visible = tool == GRAPPLE
	if saw_node:
		saw_node.visible = tool == SAW


func _build() -> void:
	model = Node3D.new()
	model.name = "yard"
	add_child(model)
	var orange := Color(0.86, 0.28, 0.08)
	var black := Color(0.08, 0.08, 0.09)
	var steel := Color(0.62, 0.64, 0.66)
	var glass := Color(0.45, 0.62, 0.66, 0.55)
	for side in [-1.0, 1.0]:
		_track(side, black, steel)
	_box(model, Vector3(0.62, 0.22, 0.92), Vector3(0.0, 0.36, 0.02), orange)
	_box(model, Vector3(0.5, 0.16, 0.42), Vector3(0.0, 0.5, 0.28), orange.darkened(0.08))
	_box(model, Vector3(0.48, 0.32, 0.4), Vector3(0.0, 0.66, -0.12), orange)
	var window := _box(model, Vector3(0.4, 0.16, 0.04), Vector3(0.0, 0.7, 0.08), glass)
	var gmat := window.material_override as StandardMaterial3D
	gmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gmat.roughness = 0.08
	_box(model, Vector3(0.08, 0.06, 0.08), Vector3(0.18, 0.78, -0.28), Color(0.95, 0.85, 0.2))
	attach = Node3D.new()
	attach.name = "attach"
	attach.position = Vector3(0.0, 0.34, 0.72)
	model.add_child(attach)
	blade_node = Node3D.new()
	blade_node.name = "blade"
	attach.add_child(blade_node)
	_box(blade_node, Vector3(1.05, 0.28, 0.06), Vector3(0.0, 0.08, 0.16), steel)
	_box(blade_node, Vector3(1.08, 0.05, 0.08), Vector3(0.0, -0.08, 0.2), Color(0.78, 0.8, 0.82))
	grapple_node = Node3D.new()
	grapple_node.name = "grapple"
	attach.add_child(grapple_node)
	_box(grapple_node, Vector3(0.12, 0.08, 0.28), Vector3(0.0, 0.16, 0.12), steel)
	var left := _box(grapple_node, Vector3(0.05, 0.22, 0.05), Vector3(-0.1, 0.02, 0.22), steel)
	left.name = "jaw-l"
	var right := _box(grapple_node, Vector3(0.05, 0.22, 0.05), Vector3(0.1, 0.02, 0.22), steel)
	right.name = "jaw-r"
	saw_node = Node3D.new()
	saw_node.name = "saw"
	attach.add_child(saw_node)
	_box(saw_node, Vector3(0.08, 0.08, 0.42), Vector3(0.16, 0.12, 0.18), Color(0.7, 0.42, 0.16))
	saw_disc = _cylinder(saw_node, 0.16, 0.02, Vector3(0.34, 0.1, 0.34), Color(0.75, 0.76, 0.78))
	saw_disc.rotation.y = PI * 0.5
	trailer = Node3D.new()
	trailer.name = "trailer"
	trailer.position = Vector3(0.0, 0.16, -1.42)
	model.add_child(trailer)
	_box(trailer, Vector3(0.08, 0.06, 0.55), Vector3(0.0, 0.08, 0.42), steel)
	_box(trailer, Vector3(0.72, 0.1, 1.15), Vector3(0.0, 0.16, -0.15), Color(0.45, 0.47, 0.5))
	_box(trailer, Vector3(0.04, 0.18, 1.15), Vector3(-0.34, 0.28, -0.15), Color(0.4, 0.42, 0.44))
	_box(trailer, Vector3(0.04, 0.18, 1.15), Vector3(0.34, 0.28, -0.15), Color(0.4, 0.42, 0.44))
	_box(trailer, Vector3(0.72, 0.16, 0.04), Vector3(0.0, 0.26, -0.7), Color(0.4, 0.42, 0.44))
	_cylinder(trailer, 0.14, 0.08, Vector3(-0.32, 0.02, 0.15), black)
	_cylinder(trailer, 0.14, 0.08, Vector3(0.32, 0.02, 0.15), black)
	_cylinder(trailer, 0.14, 0.08, Vector3(-0.32, 0.02, -0.4), black)
	_cylinder(trailer, 0.14, 0.08, Vector3(0.32, 0.02, -0.4), black)
	_show_tool()
	_pose()


func _track(side: float, rubber: Color, steel: Color) -> void:
	var x := side * 0.34
	_box(model, Vector3(0.16, 0.08, 1.28), Vector3(x, 0.1, 0.0), rubber)
	_box(model, Vector3(0.04, 0.1, 1.05), Vector3(x - side * 0.06, 0.2, 0.0), Color(0.16, 0.16, 0.17))
	for z in [-0.48, -0.16, 0.16, 0.48]:
		var roller := _cylinder(model, 0.07, 0.12, Vector3(x, 0.16, z), steel)
		roller.rotation.z = PI * 0.5
		_box(model, Vector3(0.18, 0.03, 0.06), Vector3(x, 0.05, z), rubber)


func _box(parent: Node3D, size: Vector3, at: Vector3, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.position = at
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = 0.35
	mat.roughness = 0.55
	mi.material_override = mat
	parent.add_child(mi)
	return mi


func _cylinder(parent: Node3D, radius: float, height: float, at: Vector3, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 8
	mi.mesh = mesh
	mi.position = at
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = 0.45
	mat.roughness = 0.45
	mi.material_override = mat
	parent.add_child(mi)
	return mi
