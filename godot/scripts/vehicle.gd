class_name TrackedVehicle
extends RigidBody3D

var terrain: TerrainWorld
var throttle := 0.0
var steer := 0.0
var blade_angle := 0.28
var blade_tilt := 0.0
var tilt_node: Node3D
var travel := 0.0
var track_travel := 0.0
var model: Node3D
var blade_anim: AnimationPlayer
var track_mats: Array[StandardMaterial3D] = []
var track_scroll := 0.0
var dust: GPUParticles3D
var wheels: Array[Vector3] = []

func _ready() -> void:
	mass = 24000.0
	gravity_scale = 1.0
	can_sleep = false
	continuous_cd = false
	linear_damp = 0.08
	angular_damp = 1.4
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0.0, 0.55, -0.1)
	collision_layer = 2
	collision_mask = 0
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.6, 1.5, 4.4)
	shape.shape = box
	shape.position = Vector3(0.0, 1.15, 0.15)
	add_child(shape)
	for side in [-1.0, 1.0]:
		for z in [-1.55, -0.75, 0.05, 0.85, 1.65]:
			wheels.append(Vector3(side * 0.95, 0.45, z))
	_load_model()
	_make_dust()


func forward() -> Vector3:
	var f := global_transform.basis.z
	f.y = 0.0
	if f.length() < 0.001:
		return Vector3(0.0, 0.0, 1.0)
	return f.normalized()


func _physics_process(dt: float) -> void:
	if terrain == null or freeze:
		_pose_blade()
		return
	dt = minf(dt, 0.05)
	var space := get_world_3d().direct_space_state
	var xf := global_transform
	var hits := 0
	for wheel in wheels:
		var from: Vector3 = xf * (wheel + Vector3(0.0, 0.35, 0.0))
		var to: Vector3 = from + Vector3.DOWN * 1.5
		var query := PhysicsRayQueryParameters3D.create(from, to, 1)
		query.exclude = [get_rid()]
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			continue
		hits += 1
		var dist: float = from.distance_to(hit.position)
		var compression := 0.58 - dist
		if compression > 0.0:
			var vn := linear_velocity.dot(Vector3.UP)
			var force := Vector3.UP * (compression * 155000.0 - vn * 14000.0)
			apply_force(force, hit.position - global_position)
	if hits == 0:
		var ground := terrain.sample(global_position.x, global_position.z)
		if global_position.y < ground - 1.2:
			var t := global_transform
			t.origin.y = ground + 0.7
			global_transform = t
			linear_velocity.y = 0.0
	var fwd := forward()
	var right := global_transform.basis.x
	right.y = 0.0
	if right.length() > 0.001:
		right = right.normalized()
	var speed := linear_velocity.dot(fwd)
	var grade := clampf(fwd.y, -0.7, 0.7)
	# basis.z.y is the pitch of the forward vector before we flattened it.
	var pitched := global_transform.basis.z
	grade = pitched.y
	var traction := clampf(1.0 - maxf(grade, 0.0) * 1.35 - maxf(-grade - 0.45, 0.0) * 0.4, 0.18, 1.0)
	var drive := clampf(throttle, -1.0, 1.0) * 82000.0 * traction
	# Differential: steering pushes one track harder than the other.
	var left_bias := 1.0 - steer * 0.85
	var right_bias := 1.0 + steer * 0.85
	apply_force(fwd * drive * left_bias, xf.basis.x * -0.9)
	apply_force(fwd * drive * right_bias, xf.basis.x * 0.9)
	var lat := linear_velocity.dot(right)
	apply_central_force(-right * lat * mass * 5.5)
	if absf(throttle) < 0.05:
		apply_central_force(-fwd * speed * mass * 1.8)
	if absf(speed) > 4.2:
		linear_velocity -= fwd * (speed - signf(speed) * 4.2) * 0.35
	_pose_blade()
	_scroll_tracks(speed, dt)
	if absf(speed) > 0.3:
		track_travel += absf(speed) * dt
		if track_travel > 0.2:
			track_travel = 0.0
			terrain.stamp_tracks(global_position.x, global_position.z, fwd.x, fwd.z)
	if blade_angle < -0.08 and absf(speed) > 0.25:
		travel += absf(speed) * dt
		if travel > 0.22:
			travel = 0.0
			var at := global_position + fwd * 3.15
			var shoulder := global_position + right * 4.8
			var edge := terrain.sample(shoulder.x, shoulder.z) + blade_angle * 0.85
			terrain.cut_blade(at.x, at.z, fwd.x, fwd.z, 3.5, edge, float(terrain.spec["repose"]))
		if dust:
			dust.emitting = true
	elif dust:
		dust.emitting = false
	_hold_shore()


func _hold_shore() -> void:
	if terrain == null or terrain.spec.get("water") == null:
		return
	var depth := terrain.water_depth(global_position.x, global_position.z)
	if depth < 0.2:
		return
	linear_velocity *= 0.8
	if depth < 1.0:
		return
	var best := global_position
	var best_d := depth
	for i in 8:
		var ang := float(i) * TAU / 8.0
		var p := global_position + Vector3(cos(ang), 0.0, sin(ang)) * 2.0
		var d := terrain.water_depth(p.x, p.z)
		if d < best_d:
			best_d = d
			best = p
	var t := global_transform
	t.origin.x = best.x
	t.origin.z = best.z
	t.origin.y = terrain.sample(best.x, best.z) + 0.55
	global_transform = t
	linear_velocity *= 0.15


func _pose_blade() -> void:
	if blade_anim == null or not blade_anim.has_animation("blade-close"):
		return
	var clip := blade_anim.get_animation("blade-close")
	var t := clampf(inverse_lerp(0.45, -0.65, blade_angle), 0.0, 1.0)
	if blade_anim.current_animation != "blade-close":
		blade_anim.play("blade-close")
	blade_anim.seek(t * clip.length, true)
	blade_anim.pause()
	if tilt_node:
		tilt_node.rotation.z = blade_tilt


func _scroll_tracks(speed: float, dt: float) -> void:
	track_scroll = wrapf(track_scroll + speed * dt * 0.18, 0.0, 1.0)
	for mat in track_mats:
		mat.uv1_offset.y = track_scroll


func _load_model() -> void:
	model = (load("res://assets/models/bulldozer.glb") as PackedScene).instantiate()
	add_child(model)
	blade_anim = _find_player(model)
	tilt_node = model.find_child("blade-angle", true, false) as Node3D
	_collect_tracks(model)
	print("tracks ", track_mats.size(), " tilt ", tilt_node != null)


func _find_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var found := _find_player(child)
		if found:
			return found
	return null


func _collect_tracks(node: Node) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		var box := mi.get_aabb()
		var low := box.position.y + box.size.y * 0.5 < 0.85
		var long := box.size.z > box.size.y and box.size.x < 1.4
		if low and long and mi.mesh != null:
			var source := mi.get_active_material(0)
			if source is StandardMaterial3D:
				var mat := (source as StandardMaterial3D).duplicate() as StandardMaterial3D
				mi.set_surface_override_material(0, mat)
				track_mats.append(mat)
	for child in node.get_children():
		_collect_tracks(child)


func _make_dust() -> void:
	dust = GPUParticles3D.new()
	dust.amount = 64
	dust.lifetime = 1.3
	dust.explosiveness = 0.05
	dust.emitting = false
	dust.position = Vector3(0.0, 0.35, 2.6)
	var proc := ParticleProcessMaterial.new()
	proc.direction = Vector3(0.0, 1.0, -0.2)
	proc.spread = 28.0
	proc.initial_velocity_min = 0.6
	proc.initial_velocity_max = 1.8
	proc.gravity = Vector3(0.0, -1.2, 0.0)
	proc.scale_min = 0.6
	proc.scale_max = 1.6
	proc.color = Color(0.72, 0.62, 0.46, 0.55)
	dust.process_material = proc
	var quad := QuadMesh.new()
	quad.size = Vector2(0.7, 0.7)
	dust.draw_pass_1 = quad
	var blade_node := model.find_child("blade", true, false)
	if blade_node:
		blade_node.add_child(dust)
	else:
		add_child(dust)
