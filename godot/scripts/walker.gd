class_name Walker
extends CharacterBody3D

var terrain: TerrainWorld
var giant := false
var yaw := 0.0
var wish := Vector2.ZERO
var running := false
var jumping := false
var visual: Node3D

func _ready() -> void:
	collision_layer = 2
	collision_mask = 1
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	var height := 76.0 if giant else 1.6
	var radius := 6.0 if giant else 0.32
	cap.height = height
	cap.radius = radius
	shape.shape = cap
	shape.position = Vector3(0.0, height * 0.5, 0.0)
	add_child(shape)
	_build_visual()
	floor_snap_length = 0.4 if not giant else 2.0
	floor_max_angle = deg_to_rad(50.0)


func forward() -> Vector3:
	return Vector3(sin(yaw), 0.0, cos(yaw))


func _physics_process(dt: float) -> void:
	if terrain == null:
		return
	dt = minf(dt, 0.05)
	var speed := (50.0 if running else 24.0) if giant else (4.6 if running else 1.65)
	var fwd := forward()
	var right := Vector3(fwd.z, 0.0, -fwd.x)
	var dir := (fwd * wish.y + right * wish.x)
	if dir.length() > 1.0:
		dir = dir.normalized()
	var gravity := 12.0 if giant else 14.0
	if is_on_floor():
		if jumping:
			velocity.y = 16.0 if giant else 4.6
		else:
			velocity.y = 0.0
	else:
		velocity.y -= gravity * dt
	var wish_v := dir * speed
	var blend := 1.0 - exp(-dt / (0.55 if giant else 0.16))
	velocity.x = lerp(velocity.x, wish_v.x, blend)
	velocity.z = lerp(velocity.z, wish_v.z, blend)
	if dir.length() > 0.2:
		yaw = lerp_angle(yaw, atan2(dir.x, dir.z), 1.0 - exp(-dt * (2.0 if giant else 8.0)))
	var f := forward()
	var n := Vector3.UP
	var r := n.cross(f).normalized()
	global_transform.basis = Basis(r, n, f)
	move_and_slide()
	var ground := terrain.sample(global_position.x, global_position.z)
	if global_position.y < ground:
		global_position.y = ground
		velocity.y = 0.0


func _build_visual() -> void:
	visual = Node3D.new()
	add_child(visual)
	var scale_n := 48.0 if giant else 1.0
	visual.scale = Vector3.ONE * scale_n
	var cloth := _mat(Color(0.55, 0.32, 0.18))
	var skin := _mat(Color(0.72, 0.52, 0.38))
	var boot := _mat(Color(0.12, 0.1, 0.09))
	_box(visual, Vector3(0.0, 1.05, 0.0), Vector3(0.42, 0.55, 0.24), cloth)
	_box(visual, Vector3(0.0, 1.55, 0.0), Vector3(0.22, 0.22, 0.22), skin)
	_box(visual, Vector3(-0.12, 0.48, 0.0), Vector3(0.14, 0.7, 0.16), cloth)
	_box(visual, Vector3(0.12, 0.48, 0.0), Vector3(0.14, 0.7, 0.16), cloth)
	_box(visual, Vector3(-0.12, 0.08, 0.04), Vector3(0.14, 0.1, 0.28), boot)
	_box(visual, Vector3(0.12, 0.08, 0.04), Vector3(0.14, 0.1, 0.28), boot)
	_box(visual, Vector3(-0.32, 1.05, 0.0), Vector3(0.12, 0.45, 0.12), cloth)
	_box(visual, Vector3(0.32, 1.05, 0.0), Vector3(0.12, 0.45, 0.12), cloth)


func _box(parent: Node3D, center: Vector3, size: Vector3, material: Material) -> void:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.position = center
	node.material_override = material
	parent.add_child(node)


func _mat(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.8
	return mat
