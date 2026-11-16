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
var recent_box: VBoxContainer
var recent: Array = []
var map_test := false

func _ready() -> void:
	DisplayServer.window_set_title("Roleplay")
	_read_args()
	_world()
	terrain = TerrainWorld.new()
	terrain.persist = not dig_test and shot_dir == "" and not bench
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
	if map_test:
		_run_map_test()
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
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		_toggle_menu()
		get_viewport().set_input_as_handled()
		return
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


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and terrain:
		terrain.save_edits()


func _open_site(index: int, at: Vector2 = Vector2(-1.0e9, -1.0e9)) -> void:
	if terrain and terrain.field != null:
		terrain.save_edits()
	site_index = index
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
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	var title := Label.new()
	title.text = "Settings"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var body_label := Label.new()
	body_label.text = "Body"
	box.add_child(body_label)
	var bodies := HBoxContainer.new()
	bodies.add_theme_constant_override("separation", 8)
	box.add_child(bodies)
	for entry in [["Robot", "robot"], ["Human", "human"]]:
		var b := _menu_button(entry[0])
		b.pressed.connect(_activate.bind(entry[1]))
		bodies.add_child(b)
	var columns := HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 12)
	box.add_child(columns)
	var side := VBoxContainer.new()
	side.custom_minimum_size = Vector2(220, 0)
	side.add_theme_constant_override("separation", 6)
	columns.add_child(side)
	var home := _menu_button("Home: island")
	home.pressed.connect(func() -> void: _go_region(0))
	side.add_child(home)
	for i in range(1, sites.size()):
		var spec: Dictionary = sites[i]
		var region := _menu_button(str(spec["name"]))
		var site_i := i
		region.pressed.connect(func() -> void: _go_region(site_i))
		side.add_child(region)
	pin_label = Label.new()
	pin_label.text = "Drop a pin on the map"
	pin_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	side.add_child(pin_label)
	search_box = LineEdit.new()
	search_box.placeholder_text = "lat, lon"
	search_box.focus_mode = Control.FOCUS_ALL
	search_box.text_submitted.connect(_search_submitted)
	side.add_child(search_box)
	var teleport := _menu_button("Teleport")
	teleport.pressed.connect(_teleport_pin)
	side.add_child(teleport)
	recent_box = VBoxContainer.new()
	side.add_child(recent_box)
	var resume := _menu_button("Resume")
	resume.pressed.connect(_close_menu)
	side.add_child(resume)
	var quit := _menu_button("Quit")
	quit.pressed.connect(_quit_game)
	side.add_child(quit)
	var map_col := VBoxContainer.new()
	map_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_child(map_col)
	var tab := Label.new()
	tab.text = "Map"
	map_col.add_child(tab)
	north_map = NorthMap.new()
	north_map.custom_minimum_size = Vector2(520, 520)
	north_map.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	north_map.size_flags_vertical = Control.SIZE_EXPAND_FILL
	north_map.pinned.connect(_on_pin)
	map_col.add_child(north_map)
	_load_recent()
	_mark_map()
	menu_root.add_child(panel)


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


func _search_submitted(text: String) -> void:
	var parts := text.replace(",", " ").split(" ", false)
	if parts.size() < 2:
		return
	if not parts[0].is_valid_float() or not parts[1].is_valid_float():
		return
	if north_map:
		north_map.drop_latlon(float(parts[0]), float(parts[1]))


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
	var meta: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/north.json"))
	if meta == null:
		return
	var landed: Dictionary = terrain.open_north(meta, lat, lon, _grain())
	foliage.rebuild(terrain, terrain.color_tex)
	var yaw_v := 0.0
	_place(vehicle, float(landed["x"]), float(landed["z"]), yaw_v)
	vehicle.blade_angle = -0.5
	vehicle.linear_velocity = Vector3.ZERO
	vehicle.angular_velocity = Vector3.ZERO
	_place(human, float(landed["x"]) + 14.0, float(landed["z"]) - 10.0, yaw_v)
	if kind == "human":
		_place(human, float(landed["x"]), float(landed["z"]), yaw_v)
	terrain.focus = active.global_position
	_tune_site()
	camera.snap()
	camera.hold = false
	if pin_label:
		pin_label.text = "Landed %.4f°, %.4f°" % [float(landed["lat"]), float(landed["lon"])]
	_close_menu()


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
		b.custom_minimum_size = Vector2(0, 28)
		b.pressed.connect(north_map.drop_latlon.bind(lat, lon))
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
	var marks: Array = []
	for i in range(1, sites.size()):
		var spec: Dictionary = sites[i]
		marks.append({"lat": float(spec["lat"]), "lon": float(spec["lon"]), "name": spec["name"]})
	north_map.set_marks(marks)


func _frame_spawn_shot() -> void:
	var fwd := vehicle.forward()
	camera.hold = true
	camera.camera.global_position = vehicle.global_position - fwd * 16.0 + Vector3.UP * 8.0
	camera.camera.look_at(vehicle.global_position + fwd * 8.0 + Vector3.UP * 1.2, Vector3.UP)


func _run_map_test() -> void:
	var back := Geo.polar_inverse(Geo.polar_forward(78.05, 13.64))
	print("roundtrip ", back)
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
	var ok := island_id == "rene-levasseur" and europe_id == "northern-2" and far_id.begins_with("north-") and island_h > 300.0 and far_h > 1.5
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
	vehicle._pose_blade()
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
			_open_menu()
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
