class_name ChaseCamera
extends Node3D

## GTA-style chase arm. The aim point is the body every frame, unsmoothed.
## Only the camera position is critically damped, so the body cannot slip
## off its screen point while the arm catches up.

var target: Node3D
var terrain: TerrainWorld
var camera: Camera3D
var hold := false

var yaw_offset := 0.0
var yaw_vel := 0.0
var pitch_up := 0.42
var idle := 0.0
var distance := 22.0
var fov_base := 52.0
var arm_pos := Vector3.ZERO
var arm_vel := Vector3.ZERO
var _placed := false
var _preset := 1
var _presets: Array[float] = [14.0, 22.0, 36.0]
var _shoulder := 0.0
var _height := 1.35
var anchor_lift := 1.15
var _omega := 14.0

func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON
	camera = Camera3D.new()
	camera.fov = fov_base
	camera.near = 0.2
	camera.far = 14000.0
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(camera)


func _process(dt: float) -> void:
	if target == null or hold or dt <= 0.0:
		return
	dt = minf(dt, 0.05)
	idle += dt
	if idle > 1.5:
		_spring_yaw(0.0, dt)
	var fwd := _flat_forward()
	var right := Vector3(fwd.z, 0.0, -fwd.x)
	var orbit := (fwd * cos(yaw_offset) + right * sin(yaw_offset)).normalized()
	var body := target.global_position
	var aim := body + Vector3.UP * anchor_lift
	var desired := aim - orbit * distance * cos(pitch_up) + Vector3.UP * distance * sin(pitch_up)
	desired += right * _shoulder
	desired = _pull_arm(aim, desired)
	var offset := desired - body
	var limit := distance * 1.15 + 2.0
	if offset.length() > limit:
		desired = body + offset.normalized() * limit
	if not _placed:
		arm_pos = desired
		arm_vel = Vector3.ZERO
		_placed = true
	else:
		arm_pos = _spring_vec(arm_pos, arm_vel, desired, _omega, dt)
	camera.global_position = arm_pos
	# Aim is never smoothed. A fixed pitch puts the body below screen center
	# by a constant angle, so the screen point does not depend on the arm lag.
	camera.look_at(aim, Vector3.UP)
	camera.rotate_object_local(Vector3.RIGHT, deg_to_rad(5.2))
	var speed := 0.0
	if target is RigidBody3D:
		speed = (target as RigidBody3D).linear_velocity.length()
	elif target.get("velocity") != null:
		speed = Vector3(target.velocity).length()
	camera.fov = lerpf(camera.fov, fov_base + clampf(speed / 18.0, 0.0, 1.0) * 6.0, 1.0 - exp(-dt * 6.0))


func orbit(dx: float, dy: float) -> void:
	yaw_offset = wrapf(yaw_offset - dx, -PI, PI)
	yaw_vel = 0.0
	pitch_up = clampf(pitch_up - dy, 0.16, 0.72)
	idle = 0.0


func cycle_zoom(direction: int) -> void:
	_preset = clampi(_preset + direction, 0, _presets.size() - 1)
	distance = _presets[_preset]
	idle = 0.0


func snap() -> void:
	_placed = false
	arm_vel = Vector3.ZERO
	yaw_vel = 0.0


func configure(kind: String) -> void:
	snap()
	match kind:
		"robot":
			_presets = [14.0, 22.0, 36.0]
			_preset = 1
			distance = 22.0
			pitch_up = 0.40
			fov_base = 50.0
			_shoulder = 0.0
			_height = 1.35
			anchor_lift = 1.15
			_omega = 14.0
			camera.near = 0.25
		"human":
			_presets = [3.6, 5.4, 8.0]
			_preset = 1
			distance = 5.4
			pitch_up = 0.22
			fov_base = 58.0
			_shoulder = 0.42
			_height = 1.55
			anchor_lift = 1.45
			_omega = 16.0
			camera.near = 0.08
		"drone":
			_presets = [18.0, 40.0, 90.0]
			_preset = 1
			distance = 40.0
			pitch_up = 0.55
			fov_base = 62.0
			_shoulder = 0.0
			_height = 0.4
			_omega = 8.0
			camera.near = 0.3
	camera.fov = fov_base


func screen_of(world: Vector3) -> Vector2:
	return camera.unproject_position(world)


func _flat_forward() -> Vector3:
	var fwd := Vector3.ZERO
	if target != null and target.has_method("forward"):
		fwd = target.call("forward")
	elif target != null:
		fwd = -target.global_transform.basis.z
	fwd.y = 0.0
	if fwd.length() < 0.001:
		return Vector3(0.0, 0.0, 1.0)
	return fwd.normalized()


func _pull_arm(from: Vector3, to: Vector3) -> Vector3:
	if terrain == null:
		return to
	var delta := to - from
	var length := delta.length()
	if length < 0.4:
		return to
	var dir := delta / length
	var blocked := length
	var steps := 10
	for i in steps:
		var t := float(i + 1) / float(steps)
		var p := from + dir * length * t
		var ground := terrain.sample(p.x, p.z) + 0.85
		if p.y < ground:
			blocked = length * float(i) / float(steps)
			break
	blocked = maxf(blocked, 2.4)
	return from + dir * blocked


func _spring_yaw(goal: float, dt: float) -> void:
	var err := wrapf(yaw_offset - goal, -PI, PI)
	var omega := 8.0
	var decay := exp(-omega * dt)
	var bend := yaw_vel + omega * err
	yaw_offset = goal + (err + bend * dt) * decay
	yaw_vel = (yaw_vel - omega * bend * dt) * decay


func _spring_vec(pos: Vector3, vel: Vector3, goal: Vector3, omega: float, dt: float) -> Vector3:
	var err := pos - goal
	var decay := exp(-omega * dt)
	var bend := vel + err * omega
	arm_vel = (vel - bend * omega * dt) * decay
	return goal + (err + bend * dt) * decay
