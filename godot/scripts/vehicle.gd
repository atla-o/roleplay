class_name TrackedVehicle
extends RigidBody3D

var terrain: TerrainWorld
var throttle := 0.0
var steer := 0.0
var blade_angle := 0.28
var blade_tilt := 0.0
var tilt_node: Node3D
var blade_node: Node3D
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
			var edge := terrain.sample(shoulder.x, shoulder.z) + blade_angle * 0.45
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
	# The end of blade-close is the model's rest key, which stands the side
	# wings up as slabs. Stay on the pitched moldboard key.
	if blade_anim.current_animation != "blade-close":
		blade_anim.play("blade-close")
	blade_anim.seek(0.0, true)
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
	blade_node = tilt_node.get_parent() as Node3D if tilt_node else null
	# The charcoal frame shares the pitch pivot and slides out as a grey plate
	# once the blade is in the cut. The yellow moldboard is the blade.
	if blade_node and tilt_node:
		var drop: Array = []
		for child in blade_node.get_children():
			if child != tilt_node:
				drop.append(child)
		for child in drop:
			blade_node.remove_child(child)
			child.free()
		_paint_blade(tilt_node)
	_collect_tracks(model)
	_glass(model)
	_seat_on_ground(model)
	print("tracks ", track_mats.size(), " tilt ", tilt_node != null)


func _build_dozer() -> void:
	var yellow := Color(0.83, 0.52, 0.07)
	var steel := Color(0.62, 0.64, 0.66)
	var dark := Color(0.12, 0.12, 0.13)
	var rubber := Color(0.08, 0.08, 0.09)
	for side in [-1.0, 1.0]:
		_track_side(side, rubber, dark, steel)
	var belly := _box(Vector3(1.55, 0.55, 2.7), yellow)
	belly.position = Vector3(0.0, 0.95, 0.05)
	model.add_child(belly)
	var hood := _box(Vector3(1.35, 0.48, 1.15), yellow)
	hood.position = Vector3(0.0, 1.42, 0.72)
	model.add_child(hood)
	var cab := _box(Vector3(1.28, 1.05, 1.15), yellow)
	cab.position = Vector3(0.0, 1.85, -0.35)
	model.add_child(cab)
	var glass := _box(Vector3(1.12, 0.62, 0.08), Color(0.55, 0.75, 0.82, 0.45))
	glass.position = Vector3(0.0, 1.95, 0.24)
	var gmat := glass.material_override as StandardMaterial3D
	gmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gmat.roughness = 0.05
	gmat.metallic = 0.15
	model.add_child(glass)
	var roof := _box(Vector3(1.4, 0.08, 1.3), Color(0.9, 0.9, 0.88))
	roof.position = Vector3(0.0, 2.42, -0.35)
	model.add_child(roof)
	_add_cylinder(model, 0.06, 0.7, Vector3(0.42, 2.15, 0.55), dark)
	_add_cylinder(model, 0.1, 0.08, Vector3(0.42, 2.52, 0.55), Color(0.2, 0.2, 0.22))
	var pivot := Node3D.new()
	pivot.name = "blade"
	pivot.position = Vector3(0.0, 0.62, 1.28)
	model.add_child(pivot)
	pivot.add_child(_moldboard())
	for side2 in [-1.0, 1.0]:
		_ram(pivot, Vector3(side2 * 0.72, 0.08, -0.85), Vector3(side2 * 1.35, 0.22, 1.35))
		_ram(pivot, Vector3(side2 * 0.42, 0.85, -0.15), Vector3(side2 * 0.95, 0.72, 1.25))
	var ripper := Node3D.new()
	ripper.position = Vector3(0.0, 0.7, -1.85)
	model.add_child(ripper)
	var bar := _box(Vector3(1.5, 0.14, 0.16), dark)
	bar.position = Vector3(0.0, 0.15, 0.0)
	ripper.add_child(bar)
	for x in [-0.5, 0.0, 0.5]:
		var tine := _box(Vector3(0.08, 0.16, 0.7), steel)
		tine.position = Vector3(x, -0.05, -0.28)
		tine.rotation.x = -0.7
		ripper.add_child(tine)


func _track_side(side: float, rubber: Color, dark: Color, steel: Color) -> void:
	var x := side * 1.08
	var belt := _box(Vector3(0.46, 0.1, 3.55), rubber)
	belt.position = Vector3(x, 0.16, 0.0)
	model.add_child(belt)
	var frame := _box(Vector3(0.08, 0.16, 3.15), dark)
	frame.position = Vector3(x - side * 0.16, 0.42, 0.0)
	model.add_child(frame)
	for z in [-1.35, -0.8, -0.25, 0.3, 0.85, 1.4]:
		var roller := _cylinder_mesh(0.15, 0.28, steel)
		roller.position = Vector3(x, 0.34, z)
		roller.rotation.z = PI * 0.5
		model.add_child(roller)
		var shoe := _box(Vector3(0.5, 0.05, 0.1), dark)
		shoe.position = Vector3(x, 0.08, z)
		model.add_child(shoe)
	var idler := _cylinder_mesh(0.26, 0.3, dark)
	idler.position = Vector3(x, 0.36, 1.72)
	idler.rotation.z = PI * 0.5
	model.add_child(idler)
	var sprocket := _cylinder_mesh(0.32, 0.28, dark)
	sprocket.position = Vector3(x, 0.4, -1.72)
	sprocket.rotation.z = PI * 0.5
	model.add_child(sprocket)


func _moldboard() -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cols := 16
	var rows := 8
	var width := 3.65
	for r in rows:
		var t0 := float(r) / float(rows)
		var t1 := float(r + 1) / float(rows)
		for c in cols:
			var u0 := float(c) / float(cols)
			var u1 := float(c + 1) / float(cols)
			var quad: Array[Vector3] = [
				_blade_point(u0, t0, width),
				_blade_point(u0, t1, width),
				_blade_point(u1, t0, width),
				_blade_point(u1, t0, width),
				_blade_point(u0, t1, width),
				_blade_point(u1, t1, width),
			]
			for p in quad:
				var steel_c := Color(0.7, 0.72, 0.74) if p.y > 0.12 else Color(0.82, 0.84, 0.8)
				st.set_color(steel_c)
				st.add_vertex(p)
	st.generate_normals()
	var mesh := st.commit()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.metallic = 0.82
	mat.roughness = 0.28
	mi.material_override = mat
	return mi


func _blade_point(u: float, t: float, width: float) -> Vector3:
	var x := lerpf(-width * 0.5, width * 0.5, u)
	var y := t * 1.18
	# Concave moldboard: the top curls back toward the machine (-Z in blade space).
	var z := 1.72 - t * 0.15 - t * t * 0.55
	var end := 1.0 - smoothstep(0.0, 0.14, u) * smoothstep(1.0, 0.86, u)
	z -= end * 0.22
	z += sin(u * PI) * 0.08
	return Vector3(x, y, z)


func _seat_on_ground(root: Node3D) -> void:
	var min_y := 1.0e8
	var found := false
	var stack: Array = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
			var mi := node as MeshInstance3D
			var ab := mi.get_aabb()
			var to_root := root.global_transform.affine_inverse() * mi.global_transform
			for corner in 8:
				var p: Vector3 = to_root * ab.get_endpoint(corner)
				min_y = minf(min_y, p.y)
				found = true
		for child in node.get_children():
			stack.append(child)
	if found:
		root.position.y -= min_y
		print("dozer seated, was ", min_y)


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


func _paint_blade(node: Node) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		# The moldboard mesh also carries small grey plates on its back.
		# Keep the broad faces and drop those short ribs.
		var src := mi.mesh
		if src != null:
			var out := ArrayMesh.new()
			for s in src.get_surface_count():
				var arrays: Array = src.surface_get_arrays(s)
				var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
				var kept := PackedInt32Array()
				var i := 0
				while i + 2 < indices.size():
					var a: Vector3 = verts[indices[i]]
					var b: Vector3 = verts[indices[i + 1]]
					var c: Vector3 = verts[indices[i + 2]]
					var span := maxf(a.distance_to(b), maxf(b.distance_to(c), c.distance_to(a)))
					if span > 0.45:
						kept.append(indices[i])
						kept.append(indices[i + 1])
						kept.append(indices[i + 2])
					i += 3
				arrays[Mesh.ARRAY_INDEX] = kept
				out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
				var mat := src.surface_get_material(s)
				if mat is StandardMaterial3D:
					var painted := (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
					painted.albedo_color = Color(0.93, 0.76, 0.1)
					painted.roughness = 0.55
					out.surface_set_material(out.get_surface_count() - 1, painted)
			mi.mesh = out
	for child in node.get_children():
		_paint_blade(child)


func _glass(node: Node) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		var mat := mi.get_active_material(0)
		if mat is StandardMaterial3D:
			var c := (mat as StandardMaterial3D).albedo_color
			if c.b > c.r + 0.05 and c.g > 0.65 and c.r > 0.5:
				var glass := (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
				glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				glass.albedo_color = Color(0.55, 0.72, 0.78, 0.38)
				glass.roughness = 0.04
				glass.metallic = 0.05
				mi.set_surface_override_material(0, glass)
	for child in node.get_children():
		_glass(child)


func _dress() -> void:
	# Stack on the hood, rams out to the blade, cleats on the tracks, tines at the rear.
	_add_cylinder(model, 0.055, 0.62, Vector3(0.38, 2.42, -0.62), Color(0.12, 0.12, 0.13))
	_add_cylinder(model, 0.09, 0.08, Vector3(0.38, 2.72, -0.62), Color(0.2, 0.2, 0.22))
	if blade_node:
		_ram(blade_node, Vector3(0.55, 0.35, 0.15), Vector3(0.72, 0.02, 2.05))
		_ram(blade_node, Vector3(-0.55, 0.35, 0.15), Vector3(-0.72, 0.02, 2.05))
	for z in [-1.45, -0.95, -0.45, 0.05, 0.55, 1.05, 1.5]:
		for side in [-1.05, 1.05]:
			var cleat := _box(Vector3(0.08, 0.06, 0.16), Color(0.16, 0.16, 0.17))
			cleat.position = Vector3(side, 0.22, z)
			model.add_child(cleat)
	for x in [-0.55, 0.0, 0.55]:
		var tine := _box(Vector3(0.08, 0.28, 0.55), Color(0.1, 0.1, 0.11))
		tine.position = Vector3(x, 0.42, -2.15)
		tine.rotation.x = -0.5
		model.add_child(tine)


func _ram(parent: Node3D, a: Vector3, b: Vector3) -> void:
	var length := a.distance_to(b)
	var mi := _cylinder_mesh(0.04, length, Color(0.72, 0.74, 0.76))
	var dir := (b - a).normalized()
	var x_axis := dir.cross(Vector3.FORWARD)
	if x_axis.length() < 0.001:
		x_axis = dir.cross(Vector3.RIGHT)
	x_axis = x_axis.normalized()
	var z_axis := x_axis.cross(dir).normalized()
	mi.transform = Transform3D(Basis(x_axis, dir, z_axis), (a + b) * 0.5)
	parent.add_child(mi)


func _add_cylinder(parent: Node3D, radius: float, height: float, at: Vector3, color: Color) -> void:
	var mi := _cylinder_mesh(radius, height, color)
	mi.position = at
	parent.add_child(mi)


func _cylinder_mesh(radius: float, height: float, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 8
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = 0.65
	mat.roughness = 0.38
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	return mi


func _box(size: Vector3, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = 0.45
	mat.roughness = 0.5
	mi.material_override = mat
	return mi


func _make_dust() -> void:
	dust = GPUParticles3D.new()
	dust.amount = 64
	dust.lifetime = 1.3
	dust.explosiveness = 0.05
	dust.emitting = false
	dust.position = Vector3(0.0, 0.35, 2.6)
	var proc := ParticleProcessMaterial.new()
	proc.direction = Vector3(0.0, 0.6, -0.2)
	proc.spread = 28.0
	proc.initial_velocity_min = 0.4
	proc.initial_velocity_max = 1.1
	proc.gravity = Vector3(0.0, -1.2, 0.0)
	proc.scale_min = 0.15
	proc.scale_max = 0.4
	proc.color = Color(0.62, 0.48, 0.32, 0.35)
	dust.process_material = proc
	var quad := QuadMesh.new()
	quad.size = Vector2(0.18, 0.18)
	var puff := StandardMaterial3D.new()
	puff.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	puff.albedo_color = Color(0.62, 0.48, 0.32, 0.4)
	puff.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	puff.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	quad.material = puff
	dust.draw_pass_1 = quad
	var blade_node := model.find_child("blade", true, false)
	if blade_node:
		blade_node.add_child(dust)
	else:
		add_child(dust)
