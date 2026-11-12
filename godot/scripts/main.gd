extends Node

var sites: Array = []
var site_index := 0
var terrain: TerrainWorld
var foliage: Foliage
var vehicle: TrackedVehicle
var human: Walker
var camera: ChaseCamera
var active: Node3D
var kind := "robot"
var ui: Control
var panel: PanelContainer
var capture := false
var shot_dir := ""
var shot_until := ""
var shot_from := ""
var fps_time := 0.0
var sun: DirectionalLight3D
var world: Environment
var bench := false
var bench_elapsed := 0.0
var bench_times := PackedFloat32Array()

func _ready() -> void:
	_read_args()
	_world()
	terrain = TerrainWorld.new()
	add_child(terrain)
	foliage = Foliage.new()
	add_child(foliage)
	vehicle = TrackedVehicle.new()
	vehicle.terrain = terrain
	add_child(vehicle)
	human = Walker.new()
	human.terrain = terrain
	add_child(human)
	camera = ChaseCamera.new()
	camera.terrain = terrain
	add_child(camera)
	_load_sites()
	_ui()
	_activate("robot")
	if shot_dir != "":
		_shots()
	elif bench:
		camera.hold = true
		vehicle.set_physics_process(false)
		human.set_physics_process(false)


func _process(dt: float) -> void:
	if bench and shot_dir == "":
		_bench_frame(dt)
		return
	fps_time += dt
	if fps_time > 2.0:
		fps_time = 0.0
		print("fps ", Engine.get_frames_per_second())
	if active:
		terrain.focus = active.global_position
	if panel and panel.visible:
		return
	var throttle := 0.0
	var steer := 0.0
	var ahead := 0.0
	var side := 0.0
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		throttle += 1.0
		ahead += 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		throttle -= 1.0
		ahead -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		steer += 1.0
		side += 1.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		steer -= 1.0
		side -= 1.0
	var joy_x := Input.get_joy_axis(0, JOY_AXIS_LEFT_X)
	var joy_y := Input.get_joy_axis(0, JOY_AXIS_LEFT_Y)
	if absf(joy_x) > 0.18:
		steer += joy_x
		side += joy_x
	if absf(joy_y) > 0.18:
		throttle -= joy_y
		ahead -= joy_y
	var rt := Input.get_joy_axis(0, JOY_AXIS_TRIGGER_RIGHT)
	var lt := Input.get_joy_axis(0, JOY_AXIS_TRIGGER_LEFT)
	if rt > 0.15:
		throttle += rt
		ahead += rt
	if lt > 0.15:
		throttle -= lt
		ahead -= lt
	var look_x := Input.get_joy_axis(0, JOY_AXIS_RIGHT_X)
	var look_y := Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y)
	if absf(look_x) > 0.15 or absf(look_y) > 0.15:
		camera.orbit(look_x * 0.04, look_y * 0.03)
	var raise := Input.is_key_pressed(KEY_Q) or Input.is_joy_button_pressed(0, JOY_BUTTON_LEFT_SHOULDER)
	var lower := Input.is_key_pressed(KEY_E) or Input.is_joy_button_pressed(0, JOY_BUTTON_RIGHT_SHOULDER)
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			lower = true
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
			raise = true
	if kind == "robot":
		vehicle.throttle = clampf(throttle, -1.0, 1.0)
		vehicle.steer = clampf(steer, -1.0, 1.0)
		var rate := 0.8 * dt
		if raise:
			vehicle.blade_angle = minf(0.45, vehicle.blade_angle + rate)
		if lower:
			vehicle.blade_angle = maxf(-0.65, vehicle.blade_angle - rate)
		if Input.is_key_pressed(KEY_Z):
			vehicle.blade_tilt = maxf(-0.28, vehicle.blade_tilt - rate)
		if Input.is_key_pressed(KEY_C):
			vehicle.blade_tilt = minf(0.28, vehicle.blade_tilt + rate)
	else:
		var walker: Walker = human
		walker.wish = Vector2(clampf(side, -1.0, 1.0), clampf(ahead, -1.0, 1.0))
		walker.running = Input.is_key_pressed(KEY_SHIFT) or rt > 0.4
		walker.jumping = Input.is_key_pressed(KEY_SPACE) or Input.is_joy_button_pressed(0, JOY_BUTTON_A)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or (event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE):
		if panel:
			panel.visible = false
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if panel == null or not panel.visible:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		camera.orbit(event.relative.x * 0.004, event.relative.y * 0.0025)


func _world() -> void:
	var env := Environment.new()
	var sky := Sky.new()
	var sky_mat := PhysicalSkyMaterial.new()
	sky_mat.rayleigh_coefficient = 2.4
	sky_mat.mie_coefficient = 0.035
	sky_mat.mie_eccentricity = 0.78
	sky_mat.turbidity = 6.0
	sky_mat.ground_color = Color(0.32, 0.30, 0.26)
	sky_mat.energy_multiplier = 1.05
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.68
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_density = 0.00009
	env.fog_aerial_perspective = 0.55
	env.fog_light_color = Color(0.62, 0.72, 0.84)
	env.fog_sun_scatter = 0.18
	if RenderingServer.get_current_rendering_method() == "forward_plus":
		env.ssao_enabled = true
		env.ssao_radius = 2.2
		env.ssao_intensity = 1.6
		env.ssil_enabled = true
		env.sdfgi_enabled = true
		env.sdfgi_cascades = 4
		env.sdfgi_min_cell_size = 0.4
		env.sdfgi_use_occlusion = true
		env.volumetric_fog_enabled = true
		env.volumetric_fog_density = 0.004
	world = env
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-16.0, 38.0, 0.0)
	sun.light_energy = 1.15
	sun.light_color = Color(1.0, 0.96, 0.88)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-24.0, -150.0, 0.0)
	fill.light_energy = 0.22
	fill.shadow_enabled = false
	add_child(fill)
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 260.0
	sun.directional_shadow_split_1 = 0.08
	sun.directional_shadow_split_2 = 0.22
	sun.directional_shadow_split_3 = 0.5
	sun.shadow_bias = 0.18
	sun.shadow_normal_bias = 2.4
	sun.shadow_blur = 2.2
	sun.light_angular_distance = 0.45
	sun.directional_shadow_blend_splits = true
	add_child(sun)


func _load_sites() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/sites.json"))
	if parsed == null:
		var resource = load("res://data/sites.json")
		parsed = resource.data
	sites = parsed["sites"]
	_open_site(0)


func _open_site(index: int) -> void:
	site_index = index
	var spec: Dictionary = sites[index]
	var albedo: Texture2D = load("res://data/%s" % str(spec["color"]))
	print("loading ", spec["name"])
	terrain.setup(spec, albedo, _grain())
	foliage.rebuild(terrain, albedo)
	_place(vehicle, float(spec["spawn"][0]), float(spec["spawn"][1]), 0.0)
	vehicle.blade_angle = 0.28
	vehicle.linear_velocity = Vector3.ZERO
	vehicle.angular_velocity = Vector3.ZERO
	_place(human, float(spec["spawn"][0]) + 12.0, float(spec["spawn"][1]) - 8.0, 0.0)
	terrain.focus = vehicle.global_position
	_tune_site()
	print("site ", spec["name"], " cut ", terrain.field.cut_m3, " fill ", terrain.field.fill_m3)


func _tune_site() -> void:
	if world == null:
		return
	var forest := bool(terrain.spec.get("forest", false))
	world.ambient_light_energy = 1.15 if forest else 0.62
	world.tonemap_exposure = 0.92 if forest else 0.7
	if world.ssao_enabled:
		world.ssao_intensity = 0.65 if forest else 1.1
	if sun:
		sun.light_energy = 1.35 if forest else 1.1


func _place(body: Node3D, x: float, z: float, yaw_v: float) -> void:
	var y := terrain.sample(x, z)
	var hx := terrain.sample(x + 1.4, z) - terrain.sample(x - 1.4, z)
	var hz := terrain.sample(x, z + 1.4) - terrain.sample(x, z - 1.4)
	var n := Vector3(-hx, 2.8, -hz).normalized()
	var fwd := Vector3(sin(yaw_v), 0.0, cos(yaw_v))
	fwd = (fwd - n * fwd.dot(n)).normalized()
	var r := n.cross(fwd).normalized()
	var lift := 0.55 if body is TrackedVehicle else 0.05
	body.global_transform = Transform3D(Basis(r, n, fwd), Vector3(x, y + lift, z))
	body.set("yaw", yaw_v)
	if body is RigidBody3D:
		body.linear_velocity = Vector3.ZERO
		body.angular_velocity = Vector3.ZERO
		body.freeze = shot_dir != ""


func _activate(next: String) -> void:
	kind = next
	vehicle.set_physics_process(next == "robot")
	vehicle.visible = next == "robot"
	human.set_physics_process(next == "human")
	human.visible = next == "human"
	match next:
		"robot":
			active = vehicle
		_:
			active = human
	camera.target = active
	camera.configure(next)
	camera.yaw_offset = 0.0


func _ui() -> void:
	if capture:
		return
	ui = Control.new()
	ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ui)
	var button := Button.new()
	button.text = "Settings"
	button.position = Vector2(14, 674)
	button.size = Vector2(92, 32)
	button.pressed.connect(_toggle_menu)
	ui.add_child(button)
	panel = PanelContainer.new()
	panel.position = Vector2(14, 360)
	panel.custom_minimum_size = Vector2(260, 0)
	panel.visible = false
	var box := VBoxContainer.new()
	panel.add_child(box)
	var body_label := Label.new()
	body_label.text = "Body"
	box.add_child(body_label)
	var bodies := HBoxContainer.new()
	box.add_child(bodies)
	for entry in [["Robot", "robot"], ["Human", "human"]]:
		var b := Button.new()
		b.text = entry[0]
		b.pressed.connect(_activate.bind(entry[1]))
		bodies.add_child(b)
	var place_label := Label.new()
	place_label.text = "Place"
	box.add_child(place_label)
	for i in sites.size():
		var spec: Dictionary = sites[i]
		var spawns: Array = spec.get("spawns", [])
		for j in spawns.size():
			var spawn: Dictionary = spawns[j]
			var b := Button.new()
			b.text = "%s · %s" % [spec["name"], spawn["name"]]
			var site_i := i
			var spawn_i := j
			b.pressed.connect(func() -> void: _go_spawn(site_i, spawn_i))
			box.add_child(b)
	ui.add_child(panel)


func _go_spawn(site_i: int, spawn_i: int) -> void:
	if site_i != site_index:
		_open_site(site_i)
	var spawn: Dictionary = sites[site_i]["spawns"][spawn_i]
	var yaw_v := float(spawn.get("yaw", 0.0))
	var at: Array = spawn["at"]
	_place(active, float(at[0]), float(at[1]), yaw_v)
	var other: Node3D = human if active == vehicle else vehicle
	_place(other, float(at[0]) + 10.0, float(at[1]) - 8.0, yaw_v)
	terrain.focus = active.global_position
	terrain.ensure_patch(Vector2(active.global_position.x, active.global_position.z))
	camera.snap()
	camera.hold = false
	if panel:
		panel.visible = false


func _toggle_menu() -> void:
	panel.visible = not panel.visible
	if panel.visible:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _grain() -> Texture2D:
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	for y in n:
		for x in n:
			var h := _hash(x, y)
			var hx := _hash(x + 1, y) - _hash(x - 1, y)
			var hy := _hash(x, y + 1) - _hash(x, y - 1)
			var nx := -hx * 0.8
			var ny := -hy * 0.8
			var nz := 1.0
			var ln := sqrt(nx * nx + ny * ny + nz * nz)
			img.set_pixel(x, y, Color(nx / ln * 0.5 + 0.5, ny / ln * 0.5 + 0.5, nz / ln * 0.5 + 0.5))
	return ImageTexture.create_from_image(img)


func _hash(x: int, y: int) -> float:
	var n := x * 374761393 + y * 668265263
	n = (n ^ (n >> 13)) * 1274126177
	return float(n & 0x7fffffff) / 2147483647.0


func _read_args() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="):
			shot_dir = arg.trim_prefix("--shots=")
			capture = true
		if arg.begins_with("--until="):
			shot_until = arg.trim_prefix("--until=")
		if arg.begins_with("--from="):
			shot_from = arg.trim_prefix("--from=")
		if arg == "--capture":
			capture = true
		if arg == "--bench":
			bench = true
	if OS.get_environment("ROLEPLAY_CAPTURE") == "1":
		capture = true
	if OS.has_feature("web"):
		var query := str(JavaScriptBridge.eval("window.location.search", true))
		if "capture=1" in query:
			capture = true
		if "bench=1" in query:
			bench = true


func _shots() -> void:
	vehicle.set_physics_process(false)
	human.set_physics_process(false)
	await get_tree().create_timer(0.2).timeout
	for _i in 4:
		await get_tree().process_frame
	for _warm in 8:
		await get_tree().process_frame
	print("play fps ", Engine.get_frames_per_second())
	if shot_from != "ile":
		await _shot("basin-robot")
		sun.rotation_degrees = Vector3(-20.0, 70.0, 0.0)
		sun.light_energy = 1.25
		_place(vehicle, 1240.0, 1840.0, 0.0)
		terrain.ensure_patch(Vector2(1240.0, 1840.0))
		terrain.rebuild_around(vehicle.global_position)
		camera.configure("robot")
		await _frame_trench(vehicle.forward(), 0.0)
		await _shot("basin-before-cut")
		vehicle.blade_angle = -0.62
		vehicle._pose_blade()
		var fwd := vehicle.forward()
		var right := Vector3(fwd.z, 0.0, -fwd.x)
		var walked := 0.0
		var mid_done := false
		while walked < 14.0:
			var shoulder := vehicle.global_position + right * 5.2
			var edge := terrain.sample(shoulder.x, shoulder.z) - 0.85
			var at := vehicle.global_position + fwd * 3.15
			terrain.cut_blade(at.x, at.z, fwd.x, fwd.z, 3.6, edge, float(terrain.spec["repose"]))
			terrain.stamp_tracks(vehicle.global_position.x, vehicle.global_position.z, fwd.x, fwd.z)
			vehicle.global_position += fwd * 0.35
			walked += 0.35
			if not mid_done and walked >= 6.0:
				mid_done = true
				terrain.refresh_edits()
				_place(vehicle, vehicle.global_position.x, vehicle.global_position.z, 0.0)
				vehicle.blade_angle = -0.62
				vehicle._pose_blade()
				if vehicle.dust:
					vehicle.dust.emitting = true
				await _frame_trench(fwd, -2.5)
				await _shot("basin-mid-push")
				vehicle.dust.emitting = false
				fwd = vehicle.forward()
				right = Vector3(fwd.z, 0.0, -fwd.x)
		terrain.refresh_edits()
		_place(vehicle, vehicle.global_position.x, vehicle.global_position.z, 0.0)
		vehicle.blade_angle = 0.35
		vehicle._pose_blade()
		terrain.rebuild_around(vehicle.global_position)
		_log_trench(fwd)
		await _frame_trench(fwd, -6.0)
		await _shot("basin-after-cut")
		camera.hold = false
		camera.configure("robot")
		sun.rotation_degrees = Vector3(-16.0, 38.0, 0.0)
		sun.light_energy = 1.15
		_activate("human")
		await _shot("basin-human")
		_activate("robot")
	_open_site(1)
	for _i in 6:
		await get_tree().process_frame
	await _shot("ile-robot")
	_activate("human")
	await _shot("ile-human")
	_go_spawn(1, 2)
	_activate("human")
	camera.configure("human")
	camera.distance = 8.0
	camera.pitch_up = 0.22
	await _shot("ile-heights")
	_stand_on_shore()
	await _shot("ile-shore")
	print("shots done")
	get_tree().quit()


func _stand_on_shore() -> void:
	if terrain.spec.get("water") == null:
		return
	var water := float(terrain.spec["water"])
	var origin := human.global_position
	for spot in terrain.spec.get("spawns", []):
		if str(spot["name"]) == "Shore":
			origin = Vector3(float(spot["at"][0]), 0.0, float(spot["at"][1]))
			break
	var look := origin
	var low := terrain.sample(origin.x, origin.z)
	var reaches: Array[float] = [40.0, 90.0, 160.0]
	for reach in reaches:
		for i in 16:
			var ang := TAU * float(i) / 16.0
			var p := Vector2(origin.x, origin.z) + Vector2(cos(ang), sin(ang)) * reach
			var h := terrain.sample(p.x, p.y)
			if h < low:
				low = h
				look = Vector3(p.x, h, p.y)
	var yaw := atan2(look.x - origin.x, look.z - origin.z)
	_place(human, origin.x, origin.z, yaw)
	terrain.rebuild_around(human.global_position)
	var aim := (look - human.global_position)
	aim.y = 0.0
	if aim.length() < 0.1:
		aim = Vector3(0.0, 0.0, 1.0)
	aim = aim.normalized()
	camera.hold = true
	camera.camera.global_position = human.global_position - aim * 8.0 + Vector3.UP * 3.8
	camera.camera.look_at(human.global_position + aim * 18.0 + Vector3.UP * 0.4, Vector3.UP)
	print("shore ", human.global_position, " look ", look, " water ", water, " low ", low)


func _frame_trench(fwd: Vector3, back: float) -> void:
	var side := Vector3(fwd.z, 0.0, -fwd.x)
	var trench := vehicle.global_position + fwd * back
	camera.hold = true
	camera.camera.global_position = trench - fwd * 3.2 + side * 8.0 + Vector3.UP * 3.6
	camera.camera.look_at(trench + Vector3.UP * 0.15, Vector3.UP)
	for _i in 2:
		await get_tree().process_frame


func _log_trench(fwd: Vector3) -> void:
	var side := Vector3(fwd.z, 0.0, -fwd.x)
	var origin := vehicle.global_position - fwd * 8.0
	var line := "trench"
	for i in 9:
		var p := origin + fwd * float(i) * 1.5
		var center := terrain.sample(p.x, p.z)
		var edge := terrain.sample(p.x + side.x * 4.0, p.z + side.z * 4.0)
		line += " %.2f/%.2f" % [center, edge]
	print(line, " cut ", terrain.patch.field.cut_m3, " fill ", terrain.patch.field.fill_m3)


func _bench_frame(dt: float) -> void:
	bench_elapsed += dt
	if bench_elapsed < 1.2:
		return
	bench_times.append(dt)
	var span := bench_elapsed - 1.2
	var duration := 14.0
	var pts: Array[Vector2] = [Vector2(1700, 1700), Vector2(2300, 2100), Vector2(2720, 2700), Vector2(3200, 3000), Vector2(2400, 3300), Vector2(1600, 2500)]
	var u := clampf(span / duration, 0.0, 0.999)
	var scaled := u * float(pts.size())
	var i := mini(int(scaled), pts.size() - 2)
	var f := scaled - float(i)
	var a: Vector2 = pts[i].lerp(pts[i + 1], f)
	var b: Vector2 = pts[i + 1]
	var heading := b - a
	if heading.length() < 0.5:
		heading = Vector2(0.0, 1.0)
	heading = heading.normalized()
	var gaze := a + heading * 50.0
	var y := terrain.sample(a.x, a.y) + 8.0
	var look := Vector3(gaze.x, terrain.sample(gaze.x, gaze.y) + 1.5, gaze.y)
	camera.hold = true
	camera.camera.global_position = Vector3(a.x, y, a.y)
	camera.camera.look_at(look, Vector3.UP)
	terrain.focus = camera.camera.global_position
	if span < duration:
		return
	bench_times.sort()
	var n := bench_times.size()
	var sum := 0.0
	for t in bench_times:
		sum += t
	var mean := sum / float(maxi(n, 1))
	var low_i := mini(n - 1, int(float(n) * 0.99))
	var low_dt: float = bench_times[low_i]
	print("bench frames ", n, " avg_fps ", 1.0 / mean, " low1_fps ", 1.0 / maxf(low_dt, 0.0001), " mean_ms ", mean * 1000.0)
	get_tree().quit()


func _shot(name: String, yaw_offset: float = 0.0) -> void:
	terrain.focus = active.global_position
	terrain.rebuild_around(active.global_position)
	camera.yaw_offset = yaw_offset
	camera.idle = -30.0
	camera._process(0.016)
	print(name, " body ", active.global_position, " cam ", camera.camera.global_position, " ground ", terrain.sample(active.global_position.x, active.global_position.z))
	for _i in 3:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := shot_dir.path_join(name + ".png")
	image.save_png(path)
	print("wrote ", path, " ", image.get_width(), "x", image.get_height())
	if shot_until != "" and name == shot_until:
		print("shots done")
		get_tree().quit()
