class_name ChaseCamera
extends Node3D

var target: Node3D
var yaw_offset := 0.0
var pitch_up := 0.38
var distance := 11.0
var look_ahead := 5.0
var look_height := 1.6
var idle := 0.0
var terrain: TerrainWorld
var camera: Camera3D
var _placed := false
var hold := false

func _ready() -> void:
	camera = Camera3D.new()
	camera.fov = 55.0
	camera.near = 0.2
	camera.far = 14000.0
	add_child(camera)


func _process(dt: float) -> void:
	if target == null or hold:
		return
	idle += dt
	if idle > 1.4:
		yaw_offset = lerp_angle(yaw_offset, 0.0, 1.0 - exp(-dt / 0.4))
	var fwd := Vector3.ZERO
	if target.has_method("forward"):
		fwd = target.call("forward")
	else:
		fwd = target.global_transform.basis.z
	fwd.y = 0.0
	if fwd.length() < 0.001:
		fwd = Vector3(0.0, 0.0, 1.0)
	fwd = fwd.normalized()
	var right := Vector3(fwd.z, 0.0, -fwd.x)
	var orbit := (fwd * cos(yaw_offset) + right * sin(yaw_offset)).normalized()
	var focus := target.global_position + fwd * look_ahead + Vector3.UP * look_height
	var cam_pos := focus - orbit * distance * cos(pitch_up) + Vector3.UP * distance * sin(pitch_up)
	if terrain != null:
		var ground := terrain.sample(cam_pos.x, cam_pos.z) + (2.2 if distance > 40.0 else 0.8)
		if cam_pos.y < ground:
			cam_pos.y = ground
	if not _placed:
		camera.global_position = cam_pos
		_placed = true
	else:
		var lag := 1.0 - exp(-dt * (3.2 if distance > 40.0 else 5.5))
		camera.global_position = camera.global_position.lerp(cam_pos, lag)
	camera.look_at(focus, Vector3.UP)


func orbit(dx: float, dy: float) -> void:
	yaw_offset = wrapf(yaw_offset - dx, -PI, PI)
	pitch_up = clampf(pitch_up - dy, 0.12, 0.9)
	idle = 0.0


func snap() -> void:
	_placed = false


func configure(kind: String) -> void:
	_placed = false
	match kind:
		"robot":
			distance = 11.5
			look_ahead = 4.8
			look_height = 1.5
			pitch_up = 0.42
			camera.fov = 52.0
			camera.near = 0.25
		"human":
			distance = 5.2
			look_ahead = 1.6
			look_height = 1.45
			pitch_up = 0.18
			camera.fov = 62.0
			camera.near = 0.08
