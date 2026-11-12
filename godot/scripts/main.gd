extends Node

var sites: Array = []
var site_index := 0
var terrain: TerrainWorld
var foliage: Foliage
var vehicle: TrackedVehicle
var human: Walker
var titan: Walker
var camera: ChaseCamera
var active: Node3D
var kind := "robot"
var ui: Control
var panel: PanelContainer
var capture := false
var shot_dir := ""
var fps_time := 0.0
var sun: DirectionalLight3D

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
	human.giant = false
	add_child(human)
	titan = Walker.new()
	titan.terrain = terrain
	titan.giant = true
	add_child(titan)
	camera = ChaseCamera.new()
	camera.terrain = terrain
	add_child(camera)
	_load_sites()
	_ui()
	_activate("robot")
	if shot_dir != "":
		_shots()


func _process(dt: float) -> void:
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
			vehicle.blade = minf(0.45, vehicle.blade + rate)
		if lower:
			vehicle.blade = maxf(-0.7, vehicle.blade - rate)
	else:
		var walker: Walker = human if kind == "human" else titan
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
	sky_mat.rayleigh_coefficient = 1.6
	sky_mat.mie_coefficient = 0.008
	sky_mat.energy_multiplier = 1.05
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.38
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.85
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_density = 0.00022
	env.fog_aerial_perspective = 0.55
	env.fog_light_color = Color(0.72, 0.78, 0.84)
	if RenderingServer.get_current_rendering_method() == "forward_plus":
		env.ssao_enabled = true
		env.ssao_radius = 2.4
		env.ssao_intensity = 1.3
		env.volumetric_fog_enabled = true
		env.volumetric_fog_density = 0.008
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-28.0, 42.0, 0.0)
	sun.light_energy = 1.05
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-24.0, -150.0, 0.0)
	fill.light_energy = 0.22
	fill.shadow_enabled = false
	add_child(fill)
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 1100.0
	sun.shadow_bias = 0.06
	sun.shadow_normal_bias = 1.1
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
	vehicle.blade = 0.18
	vehicle.speed = 0.0
	_place(human, float(spec["spawn"][0]) + 12.0, float(spec["spawn"][1]) - 8.0, 0.0)
	_place(titan, float(spec["spawn"][0]) - 30.0, float(spec["spawn"][1]) - 20.0, 0.0)
	terrain.focus = vehicle.global_position
	print("site ", spec["name"], " cut ", terrain.field.cut_m3, " fill ", terrain.field.fill_m3)


func _place(body: Node3D, x: float, z: float, yaw_v: float) -> void:
	var y := terrain.sample(x, z)
	body.global_position = Vector3(x, y + 0.35, z)
	body.set("yaw", yaw_v)


func _activate(next: String) -> void:
	kind = next
	vehicle.set_physics_process(next == "robot")
	vehicle.visible = next == "robot"
	human.set_physics_process(next == "human")
	human.visible = next == "human"
	titan.set_physics_process(next == "titan")
	titan.visible = next == "titan"
	match next:
		"robot":
			active = vehicle
		"human":
			active = human
		_:
			active = titan
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
	button.text = "Menu"
	button.position = Vector2(14, 670)
	button.size = Vector2(72, 34)
	button.pressed.connect(_toggle_menu)
	ui.add_child(button)
	panel = PanelContainer.new()
	panel.position = Vector2(14, 470)
	panel.size = Vector2(280, 180)
	panel.visible = false
	var box := VBoxContainer.new()
	panel.add_child(box)
	var bodies := HBoxContainer.new()
	box.add_child(bodies)
	for entry in [["Titan", "titan"], ["Robot", "robot"], ["Human", "human"]]:
		var b := Button.new()
		b.text = entry[0]
		b.pressed.connect(_activate.bind(entry[1]))
		bodies.add_child(b)
	var places := HBoxContainer.new()
	box.add_child(places)
	for i in sites.size():
		var b := Button.new()
		b.text = str(sites[i]["name"])
		var index := i
		b.pressed.connect(func() -> void: _open_site(index))
		places.add_child(b)
	ui.add_child(panel)


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
		if arg == "--capture":
			capture = true
	if OS.get_environment("ROLEPLAY_CAPTURE") == "1":
		capture = true
	if OS.has_feature("web"):
		var query := str(JavaScriptBridge.eval("window.location.search", true))
		if "capture=1" in query:
			capture = true


func _shots() -> void:
	vehicle.set_physics_process(false)
	human.set_physics_process(false)
	titan.set_physics_process(false)
	await get_tree().create_timer(0.2).timeout
	for _i in 6:
		await get_tree().process_frame
	await _shot("basin-robot")
	vehicle.blade = -0.42
	var fwd := vehicle.forward()
	var walked := 0.0
	while walked < 16.0:
		var ground := terrain.sample(vehicle.global_position.x, vehicle.global_position.z)
		var edge := ground - 1.05
		var at := vehicle.global_position + fwd * 3.3
		Soil.plane_blade(terrain.field, at.x, at.z, fwd.x, fwd.z, 3.6, edge, float(terrain.spec["repose"]))
		vehicle.global_position += fwd * 0.8
		walked += 0.8
	terrain.refresh_edits()
	_place(vehicle, vehicle.global_position.x, vehicle.global_position.z, vehicle.yaw)
	terrain.rebuild_around(vehicle.global_position)
	for _i in 4:
		await get_tree().process_frame
	print("cut ", terrain.field.cut_m3, " fill ", terrain.field.fill_m3)
	camera.pitch_up = 0.72
	await _shot("basin-after-cut", 0.7)
	camera.configure("robot")
	_activate("human")
	await _shot("basin-human")
	_activate("titan")
	await _shot("basin-titan")
	_activate("robot")
	_open_site(1)
	for _i in 8:
		await get_tree().process_frame
	await _shot("ile-robot")
	_activate("human")
	await _shot("ile-human")
	_activate("titan")
	await _shot("ile-titan")
	print("shots done")
	get_tree().quit()


func _shot(name: String, yaw_offset: float = 0.0) -> void:
	terrain.focus = active.global_position
	terrain.rebuild_around(active.global_position)
	camera.yaw_offset = yaw_offset
	camera._process(0.016)
	print(name, " body ", active.global_position, " cam ", camera.camera.global_position, " ground ", terrain.sample(active.global_position.x, active.global_position.z))
	for _i in 3:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := shot_dir.path_join(name + ".png")
	image.save_png(path)
	print("wrote ", path, " ", image.get_width(), "x", image.get_height())
