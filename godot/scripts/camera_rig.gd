class_name ChaseCamera
extends Node3D

var target: Node3D
var yaw_offset := 0.0
var pitch_up := 0.32
var distance := 12.0
var look_ahead := 6.0
var look_height := 1.3
var idle := 0.0
var terrain: TerrainWorld
var camera: Camera3D

func _ready() -> void:
	camera = Camera3D.new()
	camera.fov = 58.0
	camera.near = 0.15
	camera.far = 12000.0
	add_child(camera)


func _process(dt: float) -> void:
	if target == null:
		return
	idle += dt
	if idle > 1.5:
		yaw_offset = lerp_angle(yaw_offset, 0.0, 1.0 - exp(-dt / 0.35))
	var fwd := Vector3.ZERO
	if target.has_method("forward"):
		fwd = target.call("forward")
	else:
		fwd = -target.global_transform.basis.z
	fwd.y = 0.0
	if fwd.length() < 0.001:
		fwd = Vector3(0.0, 0.0, 1.0)
	fwd = fwd.normalized()
	var right := Vector3(fwd.z, 0.0, -fwd.x)
	var orbit := (fwd * cos(yaw_offset) + right * sin(yaw_offset)).normalized()
	var focus := target.global_position + fwd * look_ahead + Vector3.UP * look_height
	var back := -orbit
	var cam_pos := focus + back * distance * cos(pitch_up) + Vector3.UP * distance * sin(pitch_up)
	if terrain != null:
		var ground := terrain.sample(cam_pos.x, cam_pos.z) + 1.4
		if cam_pos.y < ground:
			cam_pos.y = ground
	camera.global_position = cam_pos
	camera.look_at(focus, Vector3.UP)


func orbit(dx: float, dy: float) -> void:
	yaw_offset = wrapf(yaw_offset - dx, -PI, PI)
	pitch_up = clampf(pitch_up - dy, 0.08, 0.85)
	idle = 0.0


func configure(kind: String) -> void:
	match kind:
		"robot":
			distance = 14.0
			look_ahead = 6.0
			look_height = 1.6
			pitch_up = 0.58
			camera.fov = 55.0
		"human":
			distance = 5.4
			look_ahead = 2.2
			look_height = 1.35
			pitch_up = 0.22
			camera.fov = 68.0
		"titan":
			distance = 95.0
			look_ahead = 40.0
			look_height = 28.0
			pitch_up = 0.38
			camera.fov = 55.0
