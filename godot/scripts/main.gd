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
var hud_chrome: Control
var panel: PanelContainer
var hint: Label
var hud_alpha := 0.0
var hud_goal := 0.0
var hud_pin := 0
var hud_leave_at := -1.0
var capture := false
var dig_test := false
var shot_drive := false
var shot_dir := ""
var shot_until := ""
var shot_from := ""
var shot_only := ""
var fps_time := 0.0
var sun: DirectionalLight3D
var world: Environment
var bench := false
var bench_elapsed := 0.0
var bench_times := PackedFloat32Array()

func _ready() -> void:
	DisplayServer.window_set_title("Roleplay")
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
	vehicle.blade_angle = -0.5
	DisplayServer.window_set_title("Roleplay")
	if shot_dir != "":
		_shots()
	elif dig_test:
		_run_dig_test()
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
	_fade_hud(dt)
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
	if dig_test or shot_drive:
		throttle = 1.0
		steer = 0.0
		lower = true
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


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_H or event.keycode == KEY_TAB:
			_cycle_hud_pin()
			get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
			if panel:
				panel.visible = false
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			get_viewport().set_input_as_handled()
			return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if panel == null or not panel.visible:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			_hide_hud_if_auto()
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
	env.fog_density = 0.00022
	env.fog_aerial_perspective = 0.72
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
		env.volumetric_fog_enabled = false
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
	fill.light_energy = 0.46
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
	var yaw_v := float(spec.get("yaw", 0.0))
	var sx := float(spec["spawn"][0])
	var sz := float(spec["spawn"][1])
	_place(vehicle, sx, sz, yaw_v)
	vehicle.blade_angle = -0.5
	vehicle.linear_velocity = Vector3.ZERO
	vehicle.angular_velocity = Vector3.ZERO
	_place(human, sx + 14.0, sz - 10.0, yaw_v)
	if kind == "human":
		_place(human, sx, sz, yaw_v)
		_place(vehicle, sx + 14.0, sz - 10.0, yaw_v)
	terrain.focus = active.global_position if active else vehicle.global_position
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
	var lift := 0.02 if body is TrackedVehicle else 0.02
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
	ui = Control.new()
	ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ui)
	var hot := Control.new()
	hot.set_anchors_preset(Control.PRESET_TOP_WIDE)
	hot.offset_bottom = 28.0
	hot.mouse_filter = Control.MOUSE_FILTER_STOP
	hot.mouse_entered.connect(_hud_enter)
	hot.mouse_exited.connect(_hud_leave)
	ui.add_child(hot)
	hud_chrome = Control.new()
	hud_chrome.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud_chrome.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_chrome.modulate.a = 0.0
	hud_chrome.visible = false
	ui.add_child(hud_chrome)
	var button := Button.new()
	button.text = "Settings"
	button.focus_mode = Control.FOCUS_NONE
	button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	button.offset_left = -128.0
	button.offset_top = 14.0
	button.offset_right = -16.0
	button.offset_bottom = 48.0
	button.pressed.connect(_toggle_menu)
	button.mouse_entered.connect(_hud_enter)
	button.mouse_exited.connect(_hud_leave)
	hud_chrome.add_child(button)
	panel = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	panel.offset_left = -300.0
	panel.offset_top = 56.0
	panel.offset_right = -16.0
	panel.offset_bottom = 380.0
	panel.visible = false
	panel.mouse_entered.connect(_hud_enter)
	panel.mouse_exited.connect(_hud_leave)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.08, 0.09, 0.94)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	var body_label := Label.new()
	body_label.text = "Body"
	box.add_child(body_label)
	var bodies := HBoxContainer.new()
	box.add_child(bodies)
	for entry in [["Robot", "robot"], ["Human", "human"]]:
		var b := Button.new()
		b.text = entry[0]
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(_activate.bind(entry[1]))
		bodies.add_child(b)
	var place_label := Label.new()
	place_label.text = "Region"
	box.add_child(place_label)
	for i in sites.size():
		var spec: Dictionary = sites[i]
		var region := Button.new()
		region.text = str(spec["name"])
		region.focus_mode = Control.FOCUS_NONE
		var site_i := i
		region.pressed.connect(func() -> void: _go_region(site_i))
		box.add_child(region)
	hud_chrome.add_child(panel)
	if capture:
		return
	hint = Label.new()
	hint.text = "W drive"
	hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hint.offset_left = -160.0
	hint.offset_top = -64.0
	hint.offset_right = 160.0
	hint.offset_bottom = -32.0
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(hint)
	var fade := create_tween()
	fade.tween_interval(2.4)
	fade.tween_property(hint, "modulate:a", 0.0, 1.4)
	fade.tween_callback(hint.queue_free)


func _go_region(index: int) -> void:
	_open_site(index)
	terrain.ensure_patch(Vector2(active.global_position.x, active.global_position.z))
	terrain.rebuild_around(active.global_position)
	camera.snap()
	camera.hold = false
	if panel:
		panel.visible = false
	if hud_pin == 0:
		hud_leave_at = Time.get_ticks_msec() / 1000.0 + 1.6


func _toggle_menu() -> void:
	_hud_enter()
	panel.visible = not panel.visible
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _cursor_is_free() -> bool:
	return Input.mouse_mode == Input.MOUSE_MODE_VISIBLE


func _hud_enter() -> void:
	if not _cursor_is_free() or hud_pin == -1:
		return
	hud_goal = 1.0
	hud_leave_at = -1.0


func _hud_leave() -> void:
	if hud_pin != 0:
		return
	hud_leave_at = Time.get_ticks_msec() / 1000.0 + 2.0


func _hide_hud_if_auto() -> void:
	if hud_pin != 0:
		return
	hud_goal = 0.0
	hud_leave_at = -1.0
	if panel:
		panel.visible = false


func _cycle_hud_pin() -> void:
	if hud_pin == 0:
		hud_pin = 1
		hud_goal = 1.0
	elif hud_pin == 1:
		hud_pin = -1
		hud_goal = 0.0
		if panel:
			panel.visible = false
	else:
		hud_pin = 0
		hud_goal = 0.0


func _fade_hud(dt: float) -> void:
	if hud_chrome == null:
		return
	if Input.mouse_mode != Input.MOUSE_MODE_VISIBLE and hud_pin == 0:
		hud_goal = 0.0
		if panel:
			panel.visible = false
	elif hud_pin == 0 and hud_leave_at >= 0.0 and Time.get_ticks_msec() / 1000.0 >= hud_leave_at:
		hud_goal = 0.0
		if panel:
			panel.visible = false
		hud_leave_at = -1.0
	elif hud_pin == 1:
		hud_goal = 1.0
	elif hud_pin == -1:
		hud_goal = 0.0
	hud_alpha = move_toward(hud_alpha, hud_goal, dt * 3.2)
	hud_chrome.modulate.a = hud_alpha
	hud_chrome.visible = hud_alpha > 0.04


func _show_hud() -> void:
	hud_pin = 1
	hud_goal = 1.0
	hud_alpha = 1.0
	if hud_chrome:
		hud_chrome.modulate.a = 1.0
		hud_chrome.visible = true
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
		if arg.begins_with("--only="):
			shot_only = arg.trim_prefix("--only=")
		if arg == "--capture":
			capture = true
		if arg == "--bench":
			bench = true
		if arg == "--dig-test":
			dig_test = true
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
	_activate("robot")
	vehicle.blade_angle = -0.5
	if _take("n1") or _take("hidden"):
		camera.hold = false
		camera.snap()
		await _shot("n1")
		if _take("hidden"):
			await _shot("hidden")
	if _take("hover"):
		_show_hud()
		panel.visible = false
		await get_tree().process_frame
		await _shot("hover")
	if _take("settings"):
		_show_hud()
		panel.visible = true
		await get_tree().process_frame
		await _shot("settings")
		panel.visible = false
	if hud_chrome:
		hud_pin = -1
		hud_goal = 0.0
		hud_alpha = 0.0
		hud_chrome.modulate.a = 0.0
		hud_chrome.visible = false
		if panel:
			panel.visible = false
	if _take("dig-before") or _take("dig-after"):
		camera.hold = false
		camera.snap()
		var fwd := vehicle.forward()
		await _frame_dozer(fwd)
		await _shot("dig-before")
		vehicle.freeze = false
		vehicle.set_physics_process(true)
		shot_drive = true
		vehicle.blade_angle = -0.55
		var walked := 0.0
		while walked < 4.0:
			await get_tree().physics_frame
			walked += get_physics_process_delta_time()
		shot_drive = false
		vehicle.throttle = 0.0
		vehicle.set_physics_process(false)
		fwd = vehicle.forward()
		await _frame_trench(fwd, 0.0)
		await _shot("dig-after")
	for i in range(1, sites.size()):
		var key := "n%d" % (i + 1)
		if not _take(key):
			continue
		_open_site(i)
		_activate("robot")
		camera.hold = false
		camera.snap()
		for _i in 3:
			await get_tree().process_frame
		await _shot(key)
	print("shots done")
	get_tree().quit()


func _run_dig_test() -> void:
	vehicle.freeze = false
	vehicle.blade_angle = -0.55
	vehicle.throttle = 1.0
	vehicle.steer = 0.0
	await get_tree().physics_frame
	var origin_before := terrain.patch.origin
	var before := _coarse_sum()
	var probe := vehicle.global_position
	var fwd0 := vehicle.forward()
	var probes: Array[float] = []
	for i in 16:
		var p := probe + fwd0 * (1.5 + float(i) * 0.7)
		probes.append(terrain.sample(p.x, p.z))
	var elapsed := 0.0
	while elapsed < 5.0:
		await get_tree().physics_frame
		elapsed += get_physics_process_delta_time()
	terrain.patch.bake()
	var after := _coarse_sum()
	var changed := 0
	for i in 16:
		var p := probe + fwd0 * (1.5 + float(i) * 0.7)
		if absf(terrain.sample(p.x, p.z) - probes[i]) > 0.02:
			changed += 1
	var cut: float = terrain.patch.field.cut_m3
	var fill: float = terrain.patch.field.fill_m3
	var conserved := absf(after - before) < 8.0 and absf(cut - fill) < 0.05
	var dug := changed >= 3 and cut > 0.05
	print("dig-test seconds %.2f changed %d coarse %.4f -> %.4f cut %.3f fill %.3f origin %s -> %s" % [elapsed, changed, before, after, cut, fill, origin_before, terrain.patch.origin])
	if dug and conserved:
		print("dig-test ok")
		get_tree().quit(0)
	else:
		print("dig-test FAIL")
		get_tree().quit(1)


func _coarse_sum() -> float:
	var total := 0.0
	for h in terrain.field.heights:
		total += h
	return total


func _basin_machine(dig: bool) -> void:
	await _shot("basin-robot")
	sun.rotation_degrees = Vector3(-20.0, 70.0, 0.0)
	sun.light_energy = 1.25
	_place(vehicle, 1240.0, 1840.0, 0.0)
	terrain.ensure_patch(Vector2(1240.0, 1840.0))
	terrain.rebuild_around(vehicle.global_position)
	camera.configure("robot")
	await _frame_dozer(vehicle.forward())
	await _shot("basin-dozer")
	if not dig:
		return
	await _frame_trench(vehicle.forward(), 0.0)
	await _shot("basin-before-cut")
	vehicle.blade_angle = -0.62
	vehicle._pose_blade()
	var fwd := vehicle.forward()
	var right := Vector3(fwd.z, 0.0, -fwd.x)
	var walked := 0.0
	var mid_done := false
	var walk_to := 14.0
	if shot_only != "" and not _take("basin-after-cut"):
		walk_to = 8.0
	while walked < walk_to:
		var shoulder := vehicle.global_position + right * 5.2
		var edge := terrain.sample(shoulder.x, shoulder.z) - 0.28
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
				vehicle.dust.emitting = false
			await _frame_trench(fwd, 0.0)
			await _shot("basin-mid-push")
			fwd = vehicle.forward()
			right = Vector3(fwd.z, 0.0, -fwd.x)
	terrain.refresh_edits()
	_place(vehicle, vehicle.global_position.x, vehicle.global_position.z, 0.0)
	vehicle.blade_angle = 0.35
	vehicle._pose_blade()
	terrain.rebuild_around(vehicle.global_position)
	_log_trench(fwd)
	await _frame_trench(fwd, -4.0)
	await _shot("basin-after-cut")
	camera.hold = false
	camera.configure("robot")
	sun.rotation_degrees = Vector3(-16.0, 38.0, 0.0)
	sun.light_energy = 1.15
	_activate("human")
	await _shot("basin-human")
	_activate("robot")


func _take(name: String) -> bool:
	if shot_only == "":
		return true
	return ("," + shot_only + ",").contains("," + name + ",")


func _frame_forest() -> void:
	# Low, looking across the moss at a birch a few metres ahead of the spawn.
	var birch := Vector3(2192.0, 0.0, 1612.0)
	birch.y = terrain.sample(birch.x, birch.z)
	var at := Vector3(2204.0, 0.0, 1596.0)
	at.y = terrain.sample(at.x, at.z) + 1.25
	_place(vehicle, 2238.0, 1572.0, 0.4)
	camera.hold = true
	camera.camera.global_position = at
	camera.camera.look_at(birch + Vector3(0.0, 1.5, 0.0), Vector3.UP)


func _frame_lake() -> void:
	var x := 3854.0
	var z := 3806.0
	_place(vehicle, x, z, atan2(58.0, 58.0))
	terrain.rebuild_around(vehicle.global_position)
	camera.hold = true
	camera.camera.global_position = Vector3(x - 18.0, terrain.sample(x, z) + 7.0, z - 10.0)
	camera.camera.look_at(Vector3(3912.0, 74.0, 3864.0), Vector3.UP)


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
	# Stand just uphill of the waterline and look along it, so the wet bank
	# and the shallows fill the frame instead of a distant horizon.
	var cam_at := Vector3(2002.0, 0.0, 2318.0)
	cam_at.y = terrain.sample(cam_at.x, cam_at.z) + 1.35
	var gaze := Vector3(1990.0, float(water) + 0.05, 2334.0)
	_place(human, 2024.0, 2296.0, yaw)
	camera.hold = true
	camera.camera.global_position = cam_at
	camera.camera.look_at(gaze, Vector3.UP)
	print("shore ", human.global_position, " look ", look, " water ", water, " low ", low)


func _frame_dozer(fwd: Vector3) -> void:
	var side := Vector3(fwd.z, 0.0, -fwd.x)
	camera.hold = true
	camera.camera.global_position = vehicle.global_position + fwd * 6.5 + side * 4.8 + Vector3.UP * 2.0
	camera.camera.look_at(vehicle.global_position + Vector3.UP * 1.15, Vector3.UP)
	for _i in 2:
		await get_tree().process_frame


func _frame_trench(fwd: Vector3, along: float) -> void:
	# Camera sits in front of the blade and off to one side, so the yellow
	# blade is the near end and the trench runs away behind the tracks.
	var side := Vector3(fwd.z, 0.0, -fwd.x)
	var focus := vehicle.global_position + fwd * 1.8
	var trail := clampf(-along, 0.0, 8.0)
	camera.hold = true
	camera.camera.global_position = focus + fwd * 4.2 + side * 6.2 + Vector3.UP * 3.0
	camera.camera.look_at(vehicle.global_position + fwd * 0.4 + Vector3.UP * 0.8, Vector3.UP)
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
	if not _take(name):
		if shot_until != "" and name == shot_until:
			print("shots done")
			get_tree().quit()
		return
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
