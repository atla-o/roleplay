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
var menu_root: Control
var panel: PanelContainer
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
var edit_timer := 0.0
var north_map: NorthMap
var pin_label: Label
var search_box: LineEdit
var home_button: Button
var places: Array = []
var recent_box: VBoxContainer
var recent: Array = []
var map_test := false
var teleport_test := false
var camera_test := false
var stream_smoke := false
var osm_probe := false
var fly_test := false
var yard_test := false
var yard_drive := 0.0
var camera_time := 0.0
var manipulate_label: Label
var yard: YardMachine
var load_fade: ColorRect
var load_label: Label
var _pin_pending := false
var _pin_since := 0
var _pin_lat := 0.0
var _pin_lon := 0.0
const _Yard = preload("res://scripts/yard.gd")

func _ready() -> void:
	DisplayServer.window_set_title("Roleplay")
	_read_args()
	_world()
	terrain = TerrainWorld.new()
	terrain.persist = not dig_test and not map_test and not teleport_test and not camera_test and shot_dir == "" and not bench
	add_child(terrain)
	foliage = Foliage.new()
	add_child(foliage)
	vehicle = TrackedVehicle.new()
	vehicle.terrain = terrain
	vehicle.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON
	add_child(vehicle)
	yard = _Yard.new()
	yard.terrain = terrain
	yard.foliage = foliage
	foliage.terrain_ref = terrain
	add_child(yard)
	yard.visible = false
	yard.set_physics_process(false)
	human = Walker.new()
	human.terrain = terrain
	human.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON
	add_child(human)
	camera = ChaseCamera.new()
	camera.terrain = terrain
	add_child(camera)
	_load_sites()
	_ui()
	_activate("robot")
	vehicle.set_manipulate(false)
	DisplayServer.window_set_title("Roleplay")
	if map_test:
		_run_map_test()
		return
	if teleport_test:
		terrain.stream_radius = 0
		terrain.imagery_zoom = 6
		_run_teleport_test()
		return
	if camera_test:
		_run_camera_test()
		return
	if fly_test:
		_run_fly_test()
		return
	if yard_test:
		_run_yard_test()
		return
	if osm_probe:
		_run_osm_probe()
		return
	if stream_smoke:
		terrain.stream_radius = 0
		terrain.imagery_zoom = 6
		_run_stream_smoke()
		return
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
	_layout_map_chrome()
	if manipulate_label and manipulate_label.visible:
		manipulate_label.modulate.a = move_toward(manipulate_label.modulate.a, 0.0, dt * 0.45)
		if manipulate_label.modulate.a <= 0.02:
			manipulate_label.visible = false
	if active and terrain:
		var cam_pos := active.global_position
		var fov := 55.0
		var view_h := get_viewport().get_visible_rect().size.y
		if camera and camera.camera:
			cam_pos = camera.camera.global_position
			fov = camera.camera.fov
		var shift := terrain.tick_stream(active.global_position, cam_pos, fov, view_h)
		if shift.length_squared() > 1.0:
			_apply_origin_shift(shift)
		_settle_pin()
	if active:
		terrain.focus = active.global_position
	if terrain and terrain.persist:
		edit_timer += dt
		if edit_timer > 8.0:
			edit_timer = 0.0
			terrain.save_edits()
	if panel and panel.visible:
		vehicle.throttle = 0.0
		vehicle.steer = 0.0
		human.wish = Vector2.ZERO
		human.jumping = false
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
	if yard_test:
		throttle = yard_drive
		steer = 0.0
	if camera_test:
		camera_time += dt
		throttle = 0.9
		steer = sin(camera_time * 1.7)
		if fmod(camera_time, 5.0) < 0.4:
			steer = 1.0 if sin(camera_time * 0.7) > 0.0 else -1.0
	if kind == "yard" and yard != null:
		yard.throttle = clampf(throttle, -1.0, 1.0)
		yard.steer = clampf(steer, -1.0, 1.0)
		if not yard.manipulate:
			yard.blade_angle = 0.35
		var yard_rate := 0.8 * dt
		if yard.manipulate and raise:
			yard.blade_angle = minf(0.4, yard.blade_angle + yard_rate)
		if yard.manipulate and lower:
			yard.blade_angle = maxf(-0.55, yard.blade_angle - yard_rate)
	elif kind != "human":
		vehicle.throttle = clampf(throttle, -1.0, 1.0)
		vehicle.steer = clampf(steer, -1.0, 1.0)
		if not vehicle.manipulate:
			vehicle.blade_angle = 0.4
		var rate := 0.8 * dt
		if vehicle.manipulate and raise:
			vehicle.blade_angle = minf(0.45, vehicle.blade_angle + rate)
		if vehicle.manipulate and lower:
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
	_fade_loading(dt)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		_toggle_menu()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F and (panel == null or not panel.visible):
		if kind == "yard" and yard != null and str(terrain.spec.get("id", "")) == "rene-levasseur":
			yard.set_manipulate(not yard.manipulate)
			_flash_notice("%s %s" % [yard.tool_name(), "down" if yard.manipulate else "up"])
		elif str(terrain.spec.get("id", "")) != "rene-levasseur":
			_flash_notice("Dig not available here yet")
		else:
			vehicle.set_manipulate(not vehicle.manipulate)
			_flash_manipulate()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_R and kind == "yard" and yard != null and (panel == null or not panel.visible):
		yard.cycle_tool()
		_flash_notice(yard.tool_name())
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and event.pressed and (panel == null or not panel.visible):
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			camera.cycle_zoom(-1)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			camera.cycle_zoom(1)
			get_viewport().set_input_as_handled()
	if event is InputEventKey and event.pressed and not event.echo and panel and panel.visible:
		var key := event as InputEventKey
		if key.keycode == KEY_ENTER or key.keycode == KEY_KP_ENTER:
			_teleport_pin()
			get_viewport().set_input_as_handled()
			return
	if panel and panel.visible:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
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
	sky_mat.ground_color = Color(0.14, 0.18, 0.14)
	sky_mat.energy_multiplier = 0.82
	sky_mat.mie_coefficient = 0.045
	sky_mat.turbidity = 7.0
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.84
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_density = 0.00015
	env.fog_aerial_perspective = 0.78
	env.fog_light_color = Color(0.70, 0.76, 0.8)
	env.fog_sun_scatter = 0.05
	# Denser below the bench, so the reservoir carries the mist.
	env.fog_height = 351.5
	env.fog_height_density = 0.045
	if RenderingServer.get_current_rendering_method() == "forward_plus":
		env.ssao_enabled = true
		env.ssao_radius = 1.1
		env.ssao_intensity = 0.7
		env.ssil_enabled = false
		env.sdfgi_enabled = false
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
	fill.light_energy = 0.22
	fill.light_color = Color(0.75, 0.82, 0.92)
	fill.shadow_enabled = false
	add_child(fill)
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 260.0
	sun.directional_shadow_split_1 = 0.05
	sun.directional_shadow_split_2 = 0.14
	sun.directional_shadow_split_3 = 0.34
	sun.shadow_bias = 0.1
	sun.shadow_normal_bias = 1.6
	sun.shadow_blur = 2.2
	sun.light_angular_distance = 0.12
	sun.directional_shadow_blend_splits = true
	add_child(sun)


func _load_sites() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/sites.json"))
	if parsed == null:
		var resource = load("res://data/sites.json")
		parsed = resource.data
	sites = parsed["sites"]
	_open_site(0)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and terrain:
		terrain.save_edits()


func _open_site(index: int, at: Vector2 = Vector2(-1.0e9, -1.0e9)) -> void:
	if terrain and terrain.field != null:
		terrain.save_edits()
	site_index = index
	vehicle.flying = false
	vehicle.gravity_scale = 1.0
	if kind == "drone":
		_activate("robot")
	var spec: Dictionary = sites[index]
	var albedo: Texture2D = load("res://data/%s" % str(spec["color"]))
	print("loading ", spec["name"])
	terrain.setup(spec, albedo, _grain())
	foliage.rebuild(terrain, albedo)
	var yaw_v := float(spec.get("yaw", 0.0))
	var sx := float(spec["spawn"][0])
	var sz := float(spec["spawn"][1])
	if at.x > -1.0e8:
		var landed := _snap_land(at.x, at.y)
		sx = landed.x
		sz = landed.y
	_place(vehicle, sx, sz, yaw_v)
	if not vehicle.manipulate:
		vehicle.blade_angle = 0.4
	vehicle.linear_velocity = Vector3.ZERO
	vehicle.angular_velocity = Vector3.ZERO
	_place(human, sx + 14.0, sz - 10.0, yaw_v)
	if kind == "human":
		_place(human, sx, sz, yaw_v)
		_place(vehicle, sx + 14.0, sz - 10.0, yaw_v)
	terrain.focus = active.global_position if active else vehicle.global_position
	if camera.camera:
		camera.camera.far = 14000.0
	_tune_site()
	print("site ", spec["name"], " cut ", terrain.field.cut_m3, " fill ", terrain.field.fill_m3)


func _tune_site() -> void:
	if world == null:
		return
	_place_sun()
	var forest := bool(terrain.spec.get("forest", false))
	world.ambient_light_energy = 1.15 if forest else 0.62
	world.tonemap_exposure = 0.92 if forest else 0.7
	if world.ssao_enabled:
		world.ssao_intensity = 0.65 if forest else 1.1
	if sun:
		sun.light_energy = 1.15 if forest else 1.05


func _place_sun() -> void:
	if sun == null or terrain == null or terrain.spec.is_empty():
		return
	var lat := float(terrain.spec["lat"]) if terrain.spec.has("lat") else 51.43
	# 16 November, Spencer declination. Noon elevation = 90° − latitude + declination.
	var decl := 23.45 * sin(deg_to_rad(360.0 / 365.0 * (284.0 + 320.0)))
	var elevation := clampf(90.0 - lat + decl, 6.0, 48.0)
	# +Z is north in these tiles, and a DirectionalLight shines along -Z, so yaw 180
	# sends the November sun from the south.
	sun.rotation_degrees = Vector3(-elevation, 180.0, 0.0)
	sun.light_color = Color(1.0, 0.9, 0.76) if elevation < 24.0 else Color(1.0, 0.96, 0.9)
	if terrain.water and terrain.water.material_override is ShaderMaterial:
		var beam := -sun.global_transform.basis.z
		(terrain.water.material_override as ShaderMaterial).set_shader_parameter("sun_dir", beam)


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
	var drone := next == "drone"
	vehicle.flying = drone
	vehicle.gravity_scale = 0.0 if drone else 1.0
	vehicle.set_physics_process(next == "robot" or drone)
	vehicle.visible = next == "robot" or drone
	if yard:
		yard.visible = next == "yard"
		yard.set_physics_process(next == "yard")
		if next != "yard":
			yard.throttle = 0.0
		else:
			var at := vehicle.global_position
			_place(yard, at.x, at.z, 0.0)
			_place(vehicle, at.x + 14.0, at.z - 8.0, 0.0)
	human.set_physics_process(next == "human")
	human.visible = next == "human"
	if next == "human":
		active = human
	elif next == "yard":
		active = yard
	else:
		active = vehicle
	camera.target = active
	camera.configure(next)
	camera.yaw_offset = 0.0


func _ui() -> void:
	ui = Control.new()
	ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ui)
	menu_root = Control.new()
	menu_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu_root.mouse_filter = Control.MOUSE_FILTER_STOP
	menu_root.visible = false
	ui.add_child(menu_root)
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.02, 0.03, 0.04, 0.62)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu_root.add_child(dim)
	panel = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -500.0
	panel.offset_top = -330.0
	panel.offset_right = 500.0
	panel.offset_bottom = 330.0
	panel.visible = false
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.09, 0.1, 0.96)
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_left = 10
	style.corner_radius_bottom_right = 10
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 16
	style.content_margin_bottom = 16
	panel.add_theme_stylebox_override("panel", style)
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 28.0
	panel.offset_top = 22.0
	panel.offset_right = -28.0
	panel.offset_bottom = -22.0
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_child(box)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	box.add_child(top)
	var resume := _menu_button("Resume")
	resume.custom_minimum_size = Vector2(110, 30)
	resume.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	resume.pressed.connect(_close_menu)
	top.add_child(resume)
	var quit := _menu_button("Quit")
	quit.custom_minimum_size = Vector2(90, 30)
	quit.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	quit.pressed.connect(_quit_game)
	top.add_child(quit)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(spacer)
	for entry in [["Robot", "robot"], ["Yard", "yard"], ["Human", "human"], ["Drone", "drone"]]:
		var b := _menu_button(entry[0])
		b.custom_minimum_size = Vector2(72, 30)
		b.size_flags_horizontal = Control.SIZE_SHRINK_END
		b.pressed.connect(_activate.bind(entry[1]))
		top.add_child(b)
	var detail := _menu_button("Detail 13")
	detail.custom_minimum_size = Vector2(96, 30)
	detail.size_flags_horizontal = Control.SIZE_SHRINK_END
	detail.pressed.connect(func() -> void:
		if terrain.detail_cap >= 14:
			terrain.detail_cap = 11
		elif terrain.detail_cap < 13:
			terrain.detail_cap = 13
		else:
			terrain.detail_cap = 14
		detail.text = "Detail %d" % terrain.detail_cap
	)
	top.add_child(detail)
	var map_host := Control.new()
	map_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	map_host.custom_minimum_size = Vector2(640, 420)
	box.add_child(map_host)
	north_map = NorthMap.new()
	north_map.set_anchors_preset(Control.PRESET_FULL_RECT)
	north_map.pinned.connect(_on_pin)
	map_host.add_child(north_map)
	var overlay := Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	map_host.add_child(overlay)
	search_box = LineEdit.new()
	search_box.custom_minimum_size = Vector2(250, 32)
	search_box.placeholder_text = "lat, lon or a place"
	search_box.focus_mode = Control.FOCUS_ALL
	search_box.mouse_filter = Control.MOUSE_FILTER_STOP
	search_box.text_submitted.connect(_search_submitted)
	overlay.add_child(search_box)
	home_button = _menu_button("Home: island")
	home_button.custom_minimum_size = Vector2(132, 30)
	home_button.pressed.connect(func() -> void: _go_region(0))
	overlay.add_child(home_button)
	pin_label = Label.new()
	pin_label.text = "Click the map"
	pin_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(pin_label)
	recent_box = VBoxContainer.new()
	recent_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(recent_box)
	_load_places()
	_load_recent()
	_mark_map()
	manipulate_label = Label.new()
	manipulate_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	manipulate_label.offset_top = 28.0
	manipulate_label.offset_bottom = 64.0
	manipulate_label.offset_left = -120.0
	manipulate_label.offset_right = 120.0
	manipulate_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	manipulate_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	manipulate_label.visible = false
	ui.add_child(manipulate_label)
	load_fade = ColorRect.new()
	load_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	load_fade.color = Color(0.02, 0.03, 0.04, 1.0)
	load_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	load_fade.visible = false
	load_fade.modulate.a = 0.0
	ui.add_child(load_fade)
	load_label = Label.new()
	load_label.text = "Loading the north"
	load_label.set_anchors_preset(Control.PRESET_CENTER)
	load_label.offset_left = -80.0
	load_label.offset_top = -12.0
	load_label.offset_right = 80.0
	load_label.offset_bottom = 12.0
	load_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	load_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	load_label.visible = false
	ui.add_child(load_label)
	menu_root.add_child(panel)


func _layout_map_chrome() -> void:
	if north_map == null or search_box == null or panel == null or not panel.visible:
		return
	if north_map.size.x < 40.0:
		return
	var disk := north_map.disk_rect()
	var local := north_map.position + disk.position
	search_box.position = local + Vector2(14.0, 14.0)
	search_box.size = Vector2(minf(268.0, disk.size.x * 0.42), 32.0)
	if home_button:
		home_button.position = local + Vector2(disk.size.x - 146.0, 14.0)
		home_button.size = Vector2(132.0, 30.0)
	if recent_box:
		recent_box.position = search_box.position + Vector2(0.0, 38.0)
		recent_box.size = Vector2(168.0, 160.0)
	if pin_label:
		pin_label.position = local + Vector2(14.0, disk.size.y - 32.0)
		pin_label.size = Vector2(260.0, 22.0)


func _menu_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 36)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return b


func _snap_land(x: float, z: float) -> Vector2:
	var water := float(terrain.spec["water"]) if terrain.spec.get("water") != null else -9999.0
	if terrain.sample(x, z) > water + 1.5:
		return Vector2(x, z)
	var step := maxf(float(terrain.spec["spacing"]), 20.0)
	for ring_i in range(1, 48):
		var radius := step * float(ring_i)
		for k in 16:
			var ang := float(k) / 16.0 * TAU
			var px := x + cos(ang) * radius
			var pz := z + sin(ang) * radius
			if terrain.sample(px, pz) > water + 1.5:
				return Vector2(px, pz)
	return Vector2(float(terrain.spec["spawn"][0]), float(terrain.spec["spawn"][1]))


func _on_pin(lat: float, lon: float) -> void:
	if pin_label:
		pin_label.text = "%.4f°, %.4f°" % [lat, lon]


func _load_places() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/places.json"))
	if parsed is Array:
		places = parsed


func _coord_token(token: String) -> float:
	var t := token.strip_edges().to_upper()
	var hemi := 0.0
	if t.ends_with("N") or t.ends_with("E") or t.begins_with("N") or t.begins_with("E"):
		hemi = 1.0
	elif t.ends_with("S") or t.ends_with("W") or t.begins_with("S") or t.begins_with("W"):
		hemi = -1.0
	t = t.replace("N", "").replace("S", "").replace("E", "").replace("W", "")
	if not t.is_valid_float():
		return 9999.0
	var value := float(t)
	if hemi < 0.0 and value > 0.0:
		value = -value
	return value


func _parse_latlon(text: String) -> Vector2:
	var parts := text.replace(",", " ").replace(";", " ").split(" ", false)
	if parts.size() != 2:
		return Vector2(999.0, 999.0)
	var lat := _coord_token(parts[0])
	var lon := _coord_token(parts[1])
	if absf(lat) > 90.0 or absf(lon) > 180.0 or lat >= 900.0 or lon >= 900.0:
		return Vector2(999.0, 999.0)
	return Vector2(lat, lon)


func _find_place(text: String) -> Dictionary:
	var query := text.strip_edges().to_lower()
	if query == "":
		return {}
	var best: Dictionary = {}
	var best_rank := 99
	var best_len := 9999
	for item in places:
		var spec: Dictionary = item
		var fields: PackedStringArray = PackedStringArray()
		fields.append(str(spec.get("n", "")))
		fields.append(str(spec.get("a", "")))
		for piece in str(spec.get("alt", "")).split(";", false):
			fields.append(piece)
		for field in fields:
			var name := field.strip_edges().to_lower()
			if name == "":
				continue
			var rank := 99
			if name == query:
				rank = 0
			elif name.begins_with(query):
				rank = 1
			elif name.contains(query):
				rank = 2
			if rank < best_rank or (rank == best_rank and name.length() < best_len):
				best_rank = rank
				best_len = name.length()
				best = spec
	return best


func _go_pin(lat: float, lon: float) -> void:
	if north_map:
		north_map.drop_latlon(lat, lon)
	_teleport_pin()


func _search_submitted(text: String) -> void:
	var coord := _parse_latlon(text)
	if coord.x < 900.0:
		_go_pin(coord.x, coord.y)
		return
	var hit := _find_place(text)
	if hit.is_empty():
		if pin_label:
			pin_label.text = "No northern place"
		return
	_go_pin(float(hit["lat"]), float(hit["lon"]))


func _teleport_pin() -> void:
	if north_map == null or not north_map.pin_ok:
		return
	var lat := north_map.pin.x
	var lon := north_map.pin.y
	_remember_pin(lat, lon)
	for i in sites.size():
		var spec: Dictionary = sites[i]
		if not spec.has("bounds") or not spec.has("frame"):
			continue
		if not Geo.inside(lat, lon, spec["bounds"]):
			continue
		var local := Geo.to_local(lat, lon, spec["frame"])
		_open_site(i, local)
		terrain.ensure_patch(Vector2(active.global_position.x, active.global_position.z))
		terrain.rebuild_around(active.global_position)
		camera.snap()
		camera.hold = false
		_close_menu()
		return
	if lat < 45.0:
		_flash_notice("Coming soon")
		return
	_pin_lat = lat
	_pin_lon = lon
	terrain.begin_stream(lat, lon)
	foliage.clear()
	_activate("drone")
	vehicle.global_position = Vector3(0.0, 36.0, 0.0)
	vehicle.linear_velocity = Vector3.ZERO
	vehicle.angular_velocity = Vector3.ZERO
	if camera.camera:
		camera.camera.far = 80000.0
	terrain.focus = vehicle.global_position
	_pin_pending = true
	_pin_since = Time.get_ticks_msec()
	camera.snap()
	camera.hold = false
	_close_menu()


func _settle_pin() -> void:
	if not _pin_pending:
		return
	var pos := active.global_position if active else Vector3.ZERO
	var elapsed := Time.get_ticks_msec() - _pin_since
	if terrain.stream_ready(pos.x, pos.z):
		_finish_stream_pin()
	elif terrain.stream_failed() or elapsed > 22000:
		_fallback_north()


func _finish_stream_pin() -> void:
	_pin_pending = false
	var x := vehicle.global_position.x
	var z := vehicle.global_position.z
	_place(vehicle, x, z, 0.0)
	var h := terrain.sample(x, z)
	vehicle.global_position.y = h + 16.0
	vehicle.linear_velocity = Vector3.ZERO
	vehicle.angular_velocity = Vector3.ZERO
	_place(human, x + 14.0, z - 10.0, 0.0)
	terrain.focus = vehicle.global_position
	_tune_site()
	camera.snap()
	if pin_label:
		pin_label.text = "Landed %.4f°, %.4f°" % [_pin_lat, _pin_lon]


func _fallback_north() -> void:
	_pin_pending = false
	terrain.streaming = false
	if terrain.quad:
		terrain.quad.shutdown()
	var meta: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/north.json"))
	if meta == null:
		_flash_notice("Coming soon")
		return
	var landed: Dictionary = terrain.open_north(meta, _pin_lat, _pin_lon, _grain())
	if landed.is_empty() or terrain.field == null:
		_flash_notice("Coming soon")
		return
	var landed_h := terrain.sample(float(landed["x"]), float(landed["z"]))
	if is_nan(landed_h) or is_inf(landed_h):
		_flash_notice("Coming soon")
		return
	foliage.rebuild(terrain, terrain.color_tex)
	_activate("drone")
	_place(vehicle, float(landed["x"]), float(landed["z"]), 0.0)
	vehicle.global_position.y = landed_h + 16.0
	if camera.camera:
		camera.camera.far = 280000.0 if float(terrain.spec["spacing"]) > 100.0 else 14000.0
	vehicle.linear_velocity = Vector3.ZERO
	vehicle.angular_velocity = Vector3.ZERO
	_place(human, float(landed["x"]) + 14.0, float(landed["z"]) - 10.0, 0.0)
	terrain.focus = active.global_position
	_tune_site()
	camera.snap()
	camera.hold = false
	if pin_label:
		pin_label.text = "Landed %.4f°, %.4f°" % [float(landed["lat"]), float(landed["lon"])]


func _apply_origin_shift(shift: Vector3) -> void:
	for body in [vehicle, human, yard]:
		if body:
			body.global_position -= shift
	if camera:
		camera.arm_pos -= shift
	for log in foliage.felled_logs:
		if is_instance_valid(log):
			log.global_position -= shift


func _fade_loading(dt: float) -> void:
	if load_fade == null:
		return
	var show := _pin_pending
	var target := 0.86 if show else 0.0
	load_fade.modulate.a = move_toward(load_fade.modulate.a, target, dt * 2.2)
	load_fade.visible = load_fade.modulate.a > 0.03
	if load_label:
		load_label.visible = load_fade.visible


func _remember_pin(lat: float, lon: float) -> void:
	if dig_test or shot_dir != "" or bench:
		return
	recent.push_front({"lat": lat, "lon": lon})
	while recent.size() > 5:
		recent.pop_back()
	DirAccess.make_dir_recursive_absolute("user://world")
	var file := FileAccess.open("user://world/pins.json", FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify({"pins": recent}))
	_show_recent()


func _load_recent() -> void:
	if not FileAccess.file_exists("user://world/pins.json"):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("user://world/pins.json"))
	if parsed is Dictionary:
		recent = parsed.get("pins", [])
	_show_recent()


func _show_recent() -> void:
	if recent_box == null:
		return
	for child in recent_box.get_children():
		child.queue_free()
	for pin in recent:
		var lat := float(pin["lat"])
		var lon := float(pin["lon"])
		var b := _menu_button("%.2f, %.2f" % [lat, lon])
		b.custom_minimum_size = Vector2(0, 26)
		b.pressed.connect(_go_pin.bind(lat, lon))
		recent_box.add_child(b)


func _mark_map() -> void:
	if north_map == null or sites.is_empty():
		return
	var island: Dictionary = sites[0]
	if island.has("bounds"):
		var b: Dictionary = island["bounds"]
		var poly := PackedVector2Array()
		for i in 24:
			var t := float(i) / 24.0
			var lat: float
			var lon: float
			if t < 0.25:
				var u := t / 0.25
				lat = float(b["south"])
				lon = lerpf(float(b["west"]), float(b["east"]), u)
			elif t < 0.5:
				var u2 := (t - 0.25) / 0.25
				lon = float(b["east"])
				lat = lerpf(float(b["south"]), float(b["north"]), u2)
			elif t < 0.75:
				var u3 := (t - 0.5) / 0.25
				lat = float(b["north"])
				lon = lerpf(float(b["east"]), float(b["west"]), u3)
			else:
				var u4 := (t - 0.75) / 0.25
				lon = float(b["west"])
				lat = lerpf(float(b["north"]), float(b["south"]), u4)
			poly.append(Vector2(lat, lon))
		north_map.set_highlight(poly)
	north_map.set_marks([])


func _shot_altitude(lat: float, lon: float, near_name: String, far_name: String) -> void:
	terrain.detail_cap = 13
	north_map.drop_latlon(lat, lon)
	_teleport_pin()
	var wait := Time.get_ticks_msec()
	while _pin_pending and Time.get_ticks_msec() - wait < 30000:
		await get_tree().process_frame
	var refine := Time.get_ticks_msec()
	while terrain.quad and terrain.streaming and terrain.quad.finest_zoom(vehicle.global_position.x, vehicle.global_position.z) < 11 and Time.get_ticks_msec() - refine < 25000:
		await get_tree().process_frame
	var mesh_wait := Time.get_ticks_msec()
	while terrain.quad and not terrain.quad.fine_mesh() and Time.get_ticks_msec() - mesh_wait < 20000:
		await get_tree().process_frame
	if terrain.quad:
		terrain.quad.reveal_now(vehicle.global_position)
	camera.hold = true
	vehicle.visible = false
	vehicle.freeze = true
	var ground := terrain.sample(vehicle.global_position.x, vehicle.global_position.z)
	var eye_y := maxf(vehicle.global_position.y, ground) + 55.0
	camera.camera.fov = 58.0
	camera.camera.global_position = vehicle.global_position + Vector3(-80.0, 0.0, -90.0)
	camera.camera.global_position.y = eye_y
	camera.camera.look_at(vehicle.global_position + Vector3(60.0, ground - vehicle.global_position.y + 6.0, 40.0), Vector3.UP)
	await _shot(near_name)
	camera.camera.global_position = Vector3(-900.0, ground + 2600.0, -1100.0)
	camera.camera.look_at(Vector3(180.0, ground + 4.0, 160.0), Vector3.UP)
	await _shot(far_name)


func _frame_spot(at: Vector3, look: Vector3, eye: float) -> void:
	vehicle.visible = false
	var ground_y := terrain.sample(at.x, at.z)
	vehicle.global_position = Vector3(at.x, ground_y + 0.6, at.z)
	camera.hold = true
	camera.camera.global_position = Vector3(at.x, ground_y + eye, at.z)
	var look_y := terrain.sample(look.x, look.z)
	camera.camera.look_at(Vector3(look.x, look_y + 1.6, look.z), Vector3.UP)
	terrain.focus = camera.camera.global_position
	terrain.rebuild_around(camera.camera.global_position)


func _frame_reservoir() -> void:
	var origin := vehicle.global_position
	# The reservoir is west of this bench. Look that way, from just above the moss.
	var aim := Vector3(-0.92, 0.0, 0.28)
	vehicle.visible = false
	camera.hold = true
	var eye := terrain.sample(origin.x, origin.z) + 3.4
	camera.camera.global_position = Vector3(origin.x, eye, origin.z) - aim * 4.0
	camera.camera.look_at(origin + aim * 90.0 + Vector3(0.0, 1.2, 0.0), Vector3.UP)


func _frame_spawn_shot() -> void:
	var fwd := vehicle.forward()
	camera.hold = true
	var pitch := camera.pitch_up
	var focus := vehicle.global_position + fwd * 7.5 + Vector3.UP * camera.anchor_lift
	camera.camera.global_position = focus - fwd * camera.distance * cos(pitch) + Vector3.UP * camera.distance * sin(pitch)
	camera.camera.look_at(focus, Vector3.UP)


func _run_map_test() -> void:
	var back := Geo.polar_inverse(Geo.polar_forward(78.05, 13.64))
	print("roundtrip ", back)
	var svalbard := _find_place("svalbard")
	var yamal := _find_place("yamal")
	var quebec := _find_place("northern quebec")
	var island := _find_place("rene")
	var places_ok := absf(float(svalbard.get("lat", 0.0)) - 78.05) < 0.2 and absf(float(yamal.get("lat", 0.0)) - 70.49) < 0.2 and absf(float(quebec.get("lat", 0.0)) - 58.1) < 0.2 and absf(float(island.get("lon", 0.0)) + 69.08) < 0.2
	print("places ", "ok" if places_ok else "FAIL", " ", svalbard.get("n"), " ", yamal.get("n"), " ", quebec.get("n"), " ", island.get("n"))
	north_map.drop_latlon(51.45, -69.09)
	_teleport_pin()
	var island_id := str(terrain.spec.get("id"))
	var island_h := terrain.sample(active.global_position.x, active.global_position.z)
	print("island-pin ", island_id, " ", active.global_position, " h ", island_h)
	north_map.drop_latlon(78.04862, 13.6441)
	_teleport_pin()
	var europe_id := str(terrain.spec.get("id"))
	var europe_h := terrain.sample(active.global_position.x, active.global_position.z)
	print("svalbard-pin ", europe_id, " ", active.global_position, " h ", europe_h)
	north_map.drop_latlon(62.0, -70.0)
	_teleport_pin()
	var far_id := str(terrain.spec.get("id"))
	var far_h := terrain.sample(active.global_position.x, active.global_position.z)
	print("lowres-pin ", far_id, " ", active.global_position, " h ", far_h)
	var ok := places_ok and island_id == "rene-levasseur" and europe_id == "northern-2" and far_id.begins_with("north-") and island_h > 300.0 and far_h > 1.5 and absf(active.global_position.x) < 5000.0
	print("map-test ", "ok" if ok else "FAIL")
	get_tree().quit(0 if ok else 1)


func _go_region(index: int) -> void:
	_open_site(index)
	terrain.ensure_patch(Vector2(active.global_position.x, active.global_position.z))
	terrain.rebuild_around(active.global_position)
	camera.snap()
	camera.hold = false
	_close_menu()


func _toggle_menu() -> void:
	if panel != null and panel.visible:
		_close_menu()
	else:
		_open_menu()


func _open_menu() -> void:
	if menu_root:
		menu_root.visible = true
	if panel:
		panel.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	vehicle.throttle = 0.0
	vehicle.steer = 0.0
	human.wish = Vector2.ZERO
	human.jumping = false


func _close_menu() -> void:
	if menu_root:
		menu_root.visible = false
	if panel:
		panel.visible = false
	if capture or dig_test or shot_dir != "":
		return
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _quit_game() -> void:
	get_tree().quit()


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
		if arg == "--map-test":
			map_test = true
		if arg == "--teleport-test":
			teleport_test = true
		if arg == "--camera-test":
			camera_test = true
		if arg == "--stream-smoke":
			stream_smoke = true
		if arg == "--osm-probe":
			osm_probe = true
		if arg == "--fly-test":
			fly_test = true
		if arg == "--yard-test":
			yard_test = true
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
	vehicle.set_manipulate(false)
	if _take("dozer-close"):
		vehicle.blade_angle = -0.12
		vehicle._pose_blade()
		var fwd0 := vehicle.forward()
		var side0 := Vector3(fwd0.z, 0.0, -fwd0.x)
		camera.hold = true
		camera.camera.global_position = vehicle.global_position + fwd0 * 5.2 + side0 * 4.6 + Vector3.UP * 2.8
		camera.camera.look_at(vehicle.global_position + fwd0 * 1.5 + Vector3.UP * 0.85, Vector3.UP)
		await get_tree().process_frame
		await _shot("dozer-close")
	if _take("map-island") or _take("map-svalbard"):
		_open_menu()
		for _frame in 4:
			await get_tree().process_frame
		if north_map and north_map.size.x < 20.0:
			north_map.size = Vector2(640, 540)
		if _take("map-island"):
			north_map.drop_latlon(51.4427, -69.0854)
			await get_tree().process_frame
			await _shot("map-island")
			_teleport_pin()
			_frame_spawn_shot()
			for _frame2 in 3:
				await get_tree().process_frame
			await _shot("spawn-island")
			if _take("island-shore"):
				_frame_reservoir()
				for _shore in 3:
					await get_tree().process_frame
				await _shot("island-shore")
			_open_menu()
	if _take("yard-close"):
		_activate("yard")
		var sx := float(terrain.spec["spawn"][0])
		var sz := float(terrain.spec["spawn"][1])
		_place(yard, sx, sz, 0.4)
		yard.tool = 0
		yard.set_manipulate(true)
		camera.hold = true
		var yfwd := yard.forward()
		var yside := Vector3(yfwd.z, 0.0, -yfwd.x)
		camera.camera.global_position = yard.global_position + yfwd * 6.2 + yside * 4.6 + Vector3.UP * 2.6
		camera.camera.look_at(yard.global_position + yfwd * 0.2 + Vector3.UP * 0.55, Vector3.UP)
		await _shot("yard-close")
	if _take("cmp-shore") or _take("cmp-forest") or _take("cmp-rock"):
		_close_menu()
		if _take("cmp-shore"):
			_frame_spot(Vector3(2240.0, 0.0, 3160.0), Vector3(2050.0, 0.0, 3000.0), 4.2)
			await _shot("cmp-shore")
		if _take("cmp-forest"):
			_frame_spot(Vector3(2268.0, 0.0, 2980.0), Vector3(2480.0, 0.0, 3140.0), 6.5)
			await _shot("cmp-forest")
		if _take("cmp-rock"):
			_frame_spot(Vector3(2540.0, 0.0, 920.0), Vector3(2465.0, 0.0, 790.0), 14.0)
			await _shot("cmp-rock")
			for _frame3 in 2:
				await get_tree().process_frame
		if _take("map-svalbard"):
			north_map.drop_latlon(78.04862, 13.6441)
			await get_tree().process_frame
			await _shot("map-svalbard")
			_teleport_pin()
			_frame_spawn_shot()
			for _frame4 in 3:
				await get_tree().process_frame
			await _shot("spawn-svalbard")
	if _take("n1") or _take("hidden"):
		camera.hold = false
		camera.snap()
		await _shot("n1")
		if _take("hidden"):
			await _shot("hidden")
	if _take("hover"):
		_close_menu()
		await get_tree().process_frame
		await _shot("hover")
	if _take("settings"):
		_open_menu()
		await get_tree().process_frame
		await _shot("settings")
		_close_menu()
	if _take("dig-before") or _take("dig-after"):
		camera.hold = false
		camera.snap()
		var fwd := vehicle.forward()
		await _frame_dozer(fwd)
		await _shot("dig-before")
		vehicle.freeze = false
		vehicle.set_physics_process(true)
		shot_drive = true
		vehicle.set_manipulate(true)
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
	if _take("drone-svalbard-500") or _take("drone-yamal-500") or _take("drone-baffin-500"):
		terrain.imagery_zoom = 10
		terrain.stream_radius = 1
		if _take("drone-svalbard-500"):
			await _shot_altitude(78.2, 16.0, "drone-svalbard-500", "drone-svalbard-3km")
		if _take("drone-yamal-500"):
			await _shot_altitude(70.8, 68.5, "drone-yamal-500", "drone-yamal-3km")
		if _take("drone-baffin-500"):
			await _shot_altitude(70.0, -70.0, "drone-baffin-500", "drone-baffin-3km")
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


func _run_teleport_test() -> void:
	var points: Array[Vector2] = [
		Vector2(78.04862, 13.6441),
		Vector2(70.49304, 67.91264),
		Vector2(58.1, -68.4),
		Vector2(53.3, -70.2),
		Vector2(64.15, -21.9),
		Vector2(69.65, 18.96),
		Vector2(71.29, -156.79),
		Vector2(60.72, -135.05),
		Vector2(68.97, 33.09),
		Vector2(51.05, -114.08),
		Vector2(46.8, -71.2),
		Vector2(74.0, -90.0),
		Vector2(80.0, 20.0),
	]
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for _i in 10:
		points.append(Vector2(rng.randf_range(46.0, 78.0), rng.randf_range(-170.0, 170.0)))
	var failed := 0
	var checked_zoom := false
	for p in points:
		north_map.drop_latlon(p.x, p.y)
		_teleport_pin()
		var wait := Time.get_ticks_msec()
		while _pin_pending and Time.get_ticks_msec() - wait < 22000:
			await get_tree().process_frame
		var h := terrain.sample(active.global_position.x, active.global_position.z)
		var finite := not is_nan(h) and not is_inf(h)
		var near := absf(active.global_position.x) < 8000.0 and absf(active.global_position.z) < 8000.0
		var sane := h > -11000.0 and h < 9000.0
		var grounded := absf(active.global_position.y - h) < 30.0
		var id := str(terrain.spec.get("id", ""))
		if not finite or not near or not sane or not grounded or terrain.field == null:
			failed += 1
			print("teleport FAIL ", p, " h ", h, " at ", active.global_position, " id ", id)
		else:
			print("teleport ok ", p, " h ", snapped(h, 0.1), " ", id, " z ", terrain.quad.finest_zoom(active.global_position.x, active.global_position.z) if terrain.quad else -1)
		if not checked_zoom and id.begins_with("stream") and terrain.quad:
			var zoom_wait := Time.get_ticks_msec()
			while terrain.quad.finest_zoom(active.global_position.x, active.global_position.z) < 11 and Time.get_ticks_msec() - zoom_wait < 40000:
				await get_tree().process_frame
			var zoom := terrain.quad.finest_zoom(active.global_position.x, active.global_position.z)
			if zoom < 11:
				failed += 1
				print("teleport FAIL zoom ", zoom)
			else:
				print("teleport zoom ", zoom)
			var h0 := terrain.sample(active.global_position.x, active.global_position.z)
			var shift := Vector3(5200.0, 0.0, -1800.0)
			terrain.quad.debug_shift(shift)
			active.global_position -= shift
			var h1 := terrain.sample(active.global_position.x, active.global_position.z)
			if absf(h0 - h1) > 4.0:
				failed += 1
				print("origin FAIL ", h0, " ", h1)
			else:
				print("origin ok ", snappedf(h0, 0.1))
			terrain.quad.debug_shift(-shift)
			active.global_position += shift
			checked_zoom = true
		if absf(p.x - 69.65) < 0.05 and terrain.streaming and terrain.quad:
			var osm_wait := Time.get_ticks_msec()
			while terrain.quad.osm_features < 1 and not terrain.quad.osm_empty and Time.get_ticks_msec() - osm_wait < 20000:
				await get_tree().process_frame
			if terrain.quad.osm_features < 1 and not terrain.quad.osm_empty:
				failed += 1
				print("osm FAIL")
			else:
				print("osm ", terrain.quad.osm_features, " empty ", terrain.quad.osm_empty)
	print("teleport-test ", points.size(), " failed ", failed)
	get_tree().quit(0 if failed == 0 else 1)


func _flash_notice(text: String) -> void:
	if manipulate_label == null:
		return
	manipulate_label.text = text
	manipulate_label.modulate.a = 1.0
	manipulate_label.visible = true


func _flash_manipulate() -> void:
	_flash_notice("Blade down" if vehicle.manipulate else "Blade up")


func _run_fly_test() -> void:
	terrain.stream_radius = 0
	terrain.imagery_zoom = 7
	Engine.time_scale = 6.0
	var points: Array[Vector2] = [
		Vector2(78.2, 16.0),
		Vector2(70.8, 68.5),
		Vector2(70.0, -70.0),
		Vector2(64.2, -153.0),
		Vector2(60.0, -100.0),
		Vector2(66.0, 30.0),
		Vector2(55.0, 10.0),
		Vector2(50.0, -80.0),
		Vector2(72.0, 100.0),
		Vector2(68.0, -140.0),
	]
	var failed := 0
	for p in points:
		north_map.drop_latlon(p.x, p.y)
		_teleport_pin()
		var wait := Time.get_ticks_msec()
		while _pin_pending and Time.get_ticks_msec() - wait < 22000:
			await get_tree().process_frame
		if _pin_pending:
			failed += 1
			print("fly FAIL still loading ", p)
			continue
		var elapsed := 0.0
		while elapsed < 30.0:
			await get_tree().physics_frame
			elapsed += get_physics_process_delta_time()
			vehicle.throttle = 0.65
			vehicle.steer = sin(elapsed * 0.35)
		var h := terrain.sample(vehicle.global_position.x, vehicle.global_position.z)
		var id := str(terrain.spec.get("id"))
		if is_nan(h) or is_inf(h) or not id.begins_with("stream-"):
			failed += 1
			print("fly FAIL ", p, " ", id, " h ", h)
		else:
			print("fly ok ", p, " ", id, " h ", snappedf(h, 0.1))
	Engine.time_scale = 1.0
	print("fly-test ", points.size(), " failed ", failed)
	get_tree().quit(0 if failed == 0 else 1)


func _run_camera_test() -> void:
	vehicle.freeze = false
	vehicle.set_manipulate(false)
	camera.hold = false
	camera.snap()
	var vp := get_viewport().get_visible_rect().size
	if vp.x < 16.0:
		vp = Vector2(1280.0, 720.0)
	var worst := 0.0
	var lock := Vector2.ZERO
	var locked := false
	var elapsed := 0.0
	var samples := 0
	while elapsed < 30.0:
		await get_tree().physics_frame
		await get_tree().process_frame
		elapsed += get_physics_process_delta_time()
		var body := vehicle.global_position + Vector3.UP * camera.anchor_lift
		var screen := camera.screen_of(body)
		if not locked and elapsed > 0.8:
			lock = screen
			locked = true
			var nx := screen.x / vp.x
			var ny := screen.y / vp.y
			print("camera lock ", snappedf(nx, 0.001), " ", snappedf(ny, 0.001), " px ", screen)
			if ny < 0.53 or absf(nx - 0.5) > 0.06:
				print("camera-test FAIL lock is not below center")
				get_tree().quit(1)
				return
		if locked:
			var err := screen.distance_to(lock)
			worst = maxf(worst, err)
			samples += 1
			if err > 16.0:
				print("camera-test FAIL drift ", snappedf(err, 0.1), " px at ", snappedf(elapsed, 0.01))
				get_tree().quit(1)
				return
	print("camera-test ok samples ", samples, " worst_px ", snappedf(worst, 0.01))
	get_tree().quit(0)


func _run_osm_probe() -> void:
	north_map.drop_latlon(69.65, 18.96)
	_teleport_pin()
	var wait := Time.get_ticks_msec()
	while Time.get_ticks_msec() - wait < 20000:
		await get_tree().process_frame
	var features := 0
	var empty := true
	if terrain.quad != null:
		features = terrain.quad.osm_features
		empty = terrain.quad.osm_empty
	print("osm-probe features ", features, " empty ", empty)
	get_tree().quit(0)


func _run_stream_smoke() -> void:
	north_map.drop_latlon(78.2, 16.0)
	_teleport_pin()
	var wait := Time.get_ticks_msec()
	while _pin_pending and Time.get_ticks_msec() - wait < 25000:
		await get_tree().process_frame
	var sh := terrain.sample(active.global_position.x, active.global_position.z)
	print("stream ", terrain.spec.get("id"), " h ", sh, " flying ", vehicle.flying)
	get_tree().quit(0 if str(terrain.spec.get("id")).begins_with("stream-") and not is_nan(sh) else 1)


func _run_yard_test() -> void:
	_activate("yard")
	var sx := float(terrain.spec["spawn"][0])
	var sz := float(terrain.spec["spawn"][1])
	_place(yard, sx, sz, 0.0)
	yard.freeze = false
	var fwd := yard.forward()
	var tree_at := yard.global_position + fwd * 3.4
	var th := terrain.sample(tree_at.x, tree_at.z)
	var rec: Dictionary = foliage.plant_sapling(tree_at.x, th, tree_at.z, 0.055)
	yard.tool = 2
	yard.set_manipulate(true)
	yard_drive = 1.0
	var elapsed := 0.0
	while elapsed < 8.0 and bool(rec.get("alive", false)):
		await get_tree().physics_frame
		elapsed += get_physics_process_delta_time()
	var felled: bool = not bool(rec.get("alive", true)) and not foliage.felled_logs.is_empty()
	print("yard fell ", felled, " pos ", yard.global_position, " tree ", tree_at, " logs ", foliage.felled_logs.size())
	if not felled:
		print("yard-test FAIL fell")
		get_tree().quit(1)
		return
	var log: RigidBody3D = foliage.felled_logs[foliage.felled_logs.size() - 1]
	yard.tool = 0
	yard.set_manipulate(true)
	var probe := yard.global_position + yard.forward() * 2.0
	var before := terrain.sample(probe.x, probe.z)
	var pushed := 0.0
	while pushed < 6.0:
		await get_tree().physics_frame
		pushed += get_physics_process_delta_time()
	var after := terrain.sample(probe.x, probe.z)
	var cut := 0.0
	if terrain.patch != null and terrain.patch.field != null:
		cut = terrain.patch.field.cut_m3
	var dug := absf(after - before) > 0.015 or cut > 0.02
	print("yard push before ", snappedf(before, 0.01), " after ", snappedf(after, 0.01), " cut ", snappedf(cut, 0.001))
	if not dug:
		print("yard-test FAIL push")
		get_tree().quit(1)
		return
	yard.tool = 1
	yard.set_manipulate(true)
	var back := 0.0
	while is_instance_valid(log) and yard.global_position.distance_to(log.global_position) > 3.2 and back < 10.0:
		var to_log := log.global_position - yard.global_position
		yard_drive = 1.0 if to_log.dot(yard.forward()) >= 0.0 else -1.0
		await get_tree().physics_frame
		back += get_physics_process_delta_time()
	var loaded := yard.load_log(log)
	print("yard load ", loaded, " dist ", yard.global_position.distance_to(log.global_position) if is_instance_valid(log) else -1)
	if not loaded:
		print("yard-test FAIL load")
		get_tree().quit(1)
		return
	var start: Vector3 = log.global_position
	yard.tool = 0
	yard.set_manipulate(false)
	yard_drive = 1.0
	var travelled := 0.0
	var guard := 0.0
	var prev := yard.global_position
	while travelled < 50.0 and guard < 40.0:
		await get_tree().physics_frame
		var step := Vector2(yard.global_position.x - prev.x, yard.global_position.z - prev.z).length()
		prev = yard.global_position
		travelled += step
		guard += get_physics_process_delta_time()
	var carried := log.global_position.distance_to(start)
	var parent_ok: bool = log.get_parent() == yard.trailer or yard.trailer.is_ancestor_of(log)
	print("yard haul travelled ", snappedf(travelled, 0.1), " log ", snappedf(carried, 0.1), " parent ", parent_ok)
	var ok := travelled >= 50.0 and carried >= 45.0 and parent_ok
	print("yard-test ", "ok" if ok else "FAIL")
	get_tree().quit(0 if ok else 1)


func _run_dig_test() -> void:
	vehicle.freeze = false
	vehicle.set_manipulate(true)
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
