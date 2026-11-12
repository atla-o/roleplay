class_name Walker
extends CharacterBody3D

var terrain: TerrainWorld
var yaw := 0.0
var dry := Vector3.ZERO
var wish := Vector2.ZERO
var running := false
var jumping := false
var model: Node3D
var anim: AnimationPlayer
var current := ""

func _ready() -> void:
	collision_layer = 2
	collision_mask = 1
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.height = 1.75
	cap.radius = 0.32
	shape.shape = cap
	shape.position = Vector3(0.0, 0.9, 0.0)
	add_child(shape)
	floor_snap_length = 0.3
	floor_max_angle = deg_to_rad(50.0)
	model = (load("res://assets/models/worker.glb") as PackedScene).instantiate()
	add_child(model)
	anim = _find_anim(model)
	_play("Idle")


func forward() -> Vector3:
	return Vector3(sin(yaw), 0.0, cos(yaw))


func _physics_process(dt: float) -> void:
	if terrain == null:
		return
	dt = minf(dt, 0.05)
	var speed := 4.4 if running else 1.55
	var fwd := forward()
	var right := Vector3(fwd.z, 0.0, -fwd.x)
	var dir := fwd * wish.y + right * wish.x
	if dir.length() > 1.0:
		dir = dir.normalized()
	if is_on_floor():
		if jumping:
			velocity.y = 4.4
		else:
			velocity.y = 0.0
	else:
		velocity.y -= 16.0 * dt
	var wish_v := dir * speed
	var blend := 1.0 - exp(-dt / 0.16)
	velocity.x = lerpf(velocity.x, wish_v.x, blend)
	velocity.z = lerpf(velocity.z, wish_v.z, blend)
	if dir.length() > 0.2:
		yaw = lerp_angle(yaw, atan2(dir.x, dir.z), 1.0 - exp(-dt * 8.0))
	var f := forward()
	var n := Vector3.UP
	var r := n.cross(f).normalized()
	global_transform.basis = Basis(r, n, f)
	move_and_slide()
	var ground := terrain.sample(global_position.x, global_position.z)
	if global_position.y < ground:
		global_position.y = ground
		velocity.y = 0.0
	var depth := terrain.water_depth(global_position.x, global_position.z)
	if depth < 0.35:
		dry = global_position
	elif depth < 0.9:
		velocity.x *= 0.55
		velocity.z *= 0.55
	else:
		global_position = dry
		velocity = Vector3.ZERO
	var planar := Vector2(velocity.x, velocity.z).length()
	var clip := "Idle"
	if planar > 2.6:
		clip = "Run"
	elif planar > 0.15:
		clip = "Walk"
	_play(clip)


func _play(clip: String) -> void:
	if anim == null or current == clip:
		return
	if anim.has_animation(clip):
		anim.play(clip)
		current = clip


func _find_anim(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var found := _find_anim(child)
		if found:
			return found
	return null
