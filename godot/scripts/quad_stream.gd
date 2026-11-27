class_name QuadStream
extends Node3D

## Quadtree of web-mercator ground for 45°N and up.
## Screen-space error picks the split. The arm position is irrelevant here:
## only the camera distance and a per-distance zoom cap decide the leaf.
## Tile bytes are fetched on worker threads (HTTPRequest on the web export,
## which has no threads). The disk cache is user://stream, capped with the
## rest of the tile cache. A floating origin recenters the meshes.

const Tiles = preload("res://scripts/tile_stream.gd")
const _Mvt = preload("res://scripts/mvt.gd")
const _Shader = preload("res://shaders/stream_ground.gdshader")

const GRID := 33
const MIN_Z := 5
const MAX_Z := 14
const OSM_URL := "https://tiles.openfreemap.org/planet/latest/%d/%d/%d.pbf"

var anchor_failed := false
var osm_features := 0
var osm_empty := false
var detail_cap := 13
var origin_merc := Vector2.ZERO

var _tiles: Dictionary = {}
var _gen := 0
var _threads: Array[Thread] = []
var _mutex: Mutex
var _sem: Semaphore
var _jobs: Array = []
var _done: Array = []
var _quit := false
var _use_threads := false
var _http_slots: Array[HTTPRequest] = []
var _inbox: Array = []
var _writes := 0
var _booted := false
var _announced := false
var _osm: Dictionary = {}
var _osm_root: Node3D
var _road_mat: StandardMaterial3D
var _water_mat: StandardMaterial3D
var _town_mat: StandardMaterial3D
var _built_osm_zoom := -1

class StreamTile extends RefCounted:
	var z := 0
	var x := 0
	var y := 0
	var key := ""
	var min_x := 0.0
	var max_x := 0.0
	var min_z := 0.0
	var max_z := 0.0
	var heights := PackedFloat32Array()
	var tex: ImageTexture
	var img_failed := false
	var elev_failed := false
	var elev_pending := false
	var img_pending := false
	var node: MeshInstance3D
	var mat: ShaderMaterial
	var fade := 0.0
	var blend := 0.0
	var mode := ""


func _ready() -> void:
	_boot()


func _exit_tree() -> void:
	_halt()


func start(lat: float, lon: float, cap: int) -> void:
	_boot()
	shutdown()
	detail_cap = clampi(cap, 11, MAX_Z)
	origin_merc = _merc(lat, lon)
	var top := mini(detail_cap, 11)
	for z in range(MIN_Z, top + 1):
		var t: Vector2i = Tiles.tile_of(lat, lon, z)
		_ensure(z, t.x, t.y)
	var oz := mini(12, detail_cap)
	var ot: Vector2i = Tiles.tile_of(lat, lon, oz)
	_ensure_osm(oz, ot.x, ot.y)
	print("stream start ", snappedf(lat, 0.001), " ", snappedf(lon, 0.001), " cap ", detail_cap)


func shutdown() -> void:
	_gen += 1
	_inbox.clear()
	if _mutex != null:
		_mutex.lock()
		_done.clear()
		_jobs.clear()
		_mutex.unlock()
	else:
		_jobs.clear()
	for key in _tiles.keys():
		var tile := _tiles[key] as StreamTile
		if tile.node:
			tile.node.queue_free()
	_tiles.clear()
	for key in _osm.keys():
		var rec: Dictionary = _osm[key]
		var node: Node = rec.get("node")
		if node != null and is_instance_valid(node):
			node.queue_free()
	_osm.clear()
	anchor_failed = false
	osm_features = 0
	osm_empty = false
	_announced = false
	_built_osm_zoom = -1


func tick(focus: Vector3, cam: Vector3, fov: float, view_h: float, cap: int) -> Vector3:
	_boot()
	detail_cap = clampi(cap, 11, MAX_Z)
	_drain(3)
	_pump_http()
	_select(focus, cam, fov, maxf(view_h, 64.0))
	_animate(0.016)
	_build_some(focus, 3)
	_evict(focus)
	_sync_osm(focus)
	if not _announced and has_visual(focus.x, focus.z):
		_announced = true
		print("stream ground z", finest_zoom(focus.x, focus.z))
	if Vector2(focus.x, focus.z).length() > 4500.0:
		return _shift(Vector3(focus.x, 0.0, focus.z))
	return Vector3.ZERO


func height_at(x: float, z: float) -> float:
	var best_z := -1
	var best := -20000.0
	for key in _tiles.keys():
		var tile := _tiles[key] as StreamTile
		if tile.heights.is_empty():
			continue
		if not _inside(tile, x, z):
			continue
		if tile.z >= best_z:
			best_z = tile.z
			best = _bilinear(tile, x, z)
	return best


func finest_zoom(x: float, z: float) -> int:
	var best := -1
	for key in _tiles.keys():
		var tile := _tiles[key] as StreamTile
		if tile.heights.is_empty() or not _inside(tile, x, z):
			continue
		if tile.z > best:
			best = tile.z
	return best


func has_visual(x: float, z: float) -> bool:
	for key in _tiles.keys():
		var tile := _tiles[key] as StreamTile
		if tile.node != null and _inside(tile, x, z):
			return true
	return false


func debug_shift(shift: Vector3) -> void:
	_shift(shift)


func fine_mesh() -> bool:
	for key in _tiles.keys():
		var tile := _tiles[key] as StreamTile
		if tile.node != null and tile.z >= 11:
			return true
	return false


func reveal_now(at: Vector3) -> void:
	var best := -1
	for key in _tiles.keys():
		var tile := _tiles[key] as StreamTile
		if tile.node != null and _inside(tile, at.x, at.z) and tile.z > best:
			best = tile.z
	var shown := 0
	for key in _tiles.keys():
		var tile := _tiles[key] as StreamTile
		if tile.node == null:
			continue
		var show := best >= 0 and tile.z >= best - 1 and _horiz(tile, at) < 6000.0
		tile.node.visible = show
		tile.fade = 1.0 if show else 0.0
		if tile.mat:
			tile.mat.set_shader_parameter("fade", tile.fade)
		if show:
			shown += 1
	print("stream reveal ", shown, " meshes best z", best)


func coarse_mesh() -> bool:
	for key in _tiles.keys():
		var tile := _tiles[key] as StreamTile
		if tile.node != null and tile.z <= 8:
			return true
	return false


func _boot() -> void:
	if _booted:
		return
	_booted = true
	_mutex = Mutex.new()
	_osm_root = Node3D.new()
	_osm_root.name = "Osm"
	add_child(_osm_root)
	_road_mat = StandardMaterial3D.new()
	_road_mat.albedo_color = Color(0.22, 0.22, 0.23)
	_road_mat.roughness = 0.92
	_water_mat = StandardMaterial3D.new()
	_water_mat.albedo_color = Color(0.08, 0.22, 0.28, 0.82)
	_water_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_water_mat.roughness = 0.18
	_town_mat = StandardMaterial3D.new()
	_town_mat.albedo_color = Color(0.55, 0.5, 0.44)
	_town_mat.roughness = 0.84
	if OS.has_feature("web"):
		for _n in 2:
			var http := HTTPRequest.new()
			http.timeout = 25.0
			http.request_completed.connect(_http_done.bind(http))
			add_child(http)
			_http_slots.append(http)
		return
	_use_threads = true
	_sem = Semaphore.new()
	for _n in 2:
		var thread := Thread.new()
		thread.start(_worker)
		_threads.append(thread)


func _halt() -> void:
	if not _use_threads:
		return
	_quit = true
	if _sem != null:
		for _t in _threads:
			_sem.post()
	for thread in _threads:
		if thread.is_started():
			thread.wait_to_finish()
	_threads.clear()
	_use_threads = false


func _worker() -> void:
	while true:
		_sem.wait()
		_mutex.lock()
		if _quit:
			_mutex.unlock()
			return
		if _jobs.is_empty():
			_mutex.unlock()
			continue
		var job: Dictionary = _jobs.pop_front()
		_mutex.unlock()
		var bytes := Tiles._http_get(str(job["url"]))
		_mutex.lock()
		if not _quit:
			var done := job.duplicate()
			done["bytes"] = bytes
			_done.append(done)
		_mutex.unlock()


func _enqueue(job: Dictionary) -> void:
	job["gen"] = _gen
	if _use_threads:
		_mutex.lock()
		_jobs.append(job)
		_mutex.unlock()
		_sem.post()
		return
	_inbox_http(job)


func _inbox_http(job: Dictionary) -> void:
	for http in _http_slots:
		if http.has_meta("job"):
			continue
		http.set_meta("job", job)
		if http.request(str(job["url"])) != OK:
			http.remove_meta("job")
			job["bytes"] = PackedByteArray()
			_inbox.append(job)
		return
	_jobs.append(job)


func _pump_http() -> void:
	if _use_threads:
		return
	var pending: Array = _jobs.duplicate()
	_jobs.clear()
	for job in pending:
		_inbox_http(job)


func _http_done(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray, http: HTTPRequest) -> void:
	if not http.has_meta("job"):
		return
	var job: Dictionary = http.get_meta("job")
	http.remove_meta("job")
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		body = PackedByteArray()
	job["bytes"] = body
	_inbox.append(job)
	_pump_http()


func _drain(budget: int) -> void:
	if _use_threads and _mutex != null:
		_mutex.lock()
		while budget > 0 and not _done.is_empty():
			_inbox.append(_done.pop_front())
			budget -= 1
		_mutex.unlock()
	var left := 3
	while left > 0 and not _inbox.is_empty():
		var job: Dictionary = _inbox.pop_front()
		left -= 1
		_apply(job)


func _apply(job: Dictionary) -> void:
	if int(job.get("gen", -1)) != _gen:
		return
	var bytes: PackedByteArray = job["bytes"]
	var kind := str(job["kind"])
	var path := str(job["path"])
	if bytes.size() > 32 and not FileAccess.file_exists(path):
		DirAccess.make_dir_recursive_absolute(path.get_base_dir())
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file:
			file.store_buffer(bytes)
			_writes += 1
			if _writes % 24 == 0:
				Tiles._trim_cache()
	if kind == "osm":
		_apply_osm(job, bytes)
		return
	var key := str(job["key"])
	if not _tiles.has(key):
		return
	var tile := _tiles[key] as StreamTile
	if bytes.size() < 32:
		if int(job.get("tries", 0)) < 1:
			job["tries"] = int(job.get("tries", 0)) + 1
			_enqueue(job)
			return
		if kind == "elev":
			tile.elev_failed = true
			tile.elev_pending = false
		else:
			tile.img_failed = true
			tile.img_pending = false
		_consider_failure()
		return
	if kind == "elev":
		tile.elev_pending = false
		var img := Image.new()
		if img.load_png_from_buffer(bytes) != OK:
			tile.elev_failed = true
			_consider_failure()
			return
		tile.heights = _decode_elev(img)
		tile.elev_failed = false
	else:
		tile.img_pending = false
		var photo := Image.new()
		var err := photo.load_jpg_from_buffer(bytes)
		if err != OK:
			err = photo.load_png_from_buffer(bytes)
		if err != OK:
			tile.img_failed = true
		else:
			photo.flip_y()
			tile.tex = ImageTexture.create_from_image(photo)
			tile.img_failed = false
	_consider_failure()


func _consider_failure() -> void:
	if finest_zoom(0.0, 0.0) >= MIN_Z:
		anchor_failed = false
		return
	for key in _tiles.keys():
		var tile := _tiles[key] as StreamTile
		if tile.heights.is_empty() and not tile.elev_failed:
			return
	var any := false
	for key in _tiles.keys():
		var tile := _tiles[key] as StreamTile
		if not tile.heights.is_empty():
			any = true
	anchor_failed = not any


func _ensure(z: int, x: int, y: int) -> void:
	if z < MIN_Z or z > MAX_Z:
		return
	var n := int(pow(2.0, z))
	x = posmod(x, n)
	if y < 0 or y >= n:
		return
	if _north_lat(z, y) < 44.5:
		return
	var key := _key(z, x, y)
	var tile: StreamTile
	if _tiles.has(key):
		tile = _tiles[key]
	else:
		tile = StreamTile.new()
		tile.z = z
		tile.x = x
		tile.y = y
		tile.key = key
		_measure(tile)
		_tiles[key] = tile
	if tile.heights.is_empty() and not tile.elev_failed and not tile.elev_pending:
		tile.elev_pending = true
		_want("elev", z, x, y, Tiles.ELEV % [z, x, y], Tiles._cache("elev", z, x, y), key)
	if tile.tex == null and not tile.img_failed and not tile.img_pending:
		tile.img_pending = true
		_want("img", z, x, y, Tiles.IMG % [z, y, x], Tiles._cache("img", z, x, y), key)


func _want(kind: String, z: int, x: int, y: int, url: String, path: String, key: String) -> void:
	var token := "%s:%s" % [kind, key]
	var job := {
		"kind": kind,
		"z": z,
		"x": x,
		"y": y,
		"url": url,
		"path": path,
		"key": key,
		"token": token,
		"tries": 0,
		"gen": _gen,
	}
	if FileAccess.file_exists(path):
		var cached := FileAccess.get_file_as_bytes(path)
		if cached.size() > 32:
			job["bytes"] = cached
			_inbox.append(job)
			return
	_enqueue(job)


func _busy(token: String) -> bool:
	for job in _inbox:
		if str(job.get("token", "")) == token:
			return true
	for job in _jobs:
		if str(job.get("token", "")) == token:
			return true
	if _mutex != null:
		_mutex.lock()
		var found := false
		for job in _jobs:
			if str(job.get("token", "")) == token:
				found = true
		for job in _done:
			if str(job.get("token", "")) == token:
				found = true
		_mutex.unlock()
		if found:
			return true
	for http in _http_slots:
		if http.has_meta("job"):
			var job: Dictionary = http.get_meta("job")
			if str(job.get("token", "")) == token:
				return true
	return false


func _select(focus: Vector3, cam: Vector3, fov: float, view_h: float) -> void:
	for key in _tiles.keys():
		(_tiles[key] as StreamTile).mode = ""
	var here := _latlon(focus.x, focus.z)
	if here.x < 44.5:
		return
	var root: Vector2i = Tiles.tile_of(here.x, here.y, MIN_Z)
	_ensure(MIN_Z, root.x, root.y)
	var stack: Array[String] = [_key(MIN_Z, root.x, root.y)]
	var guard := 0
	var pixels := (view_h * 0.5) / maxf(tan(deg_to_rad(fov) * 0.5), 0.15)
	while not stack.is_empty() and guard < 280:
		guard += 1
		var key: String = stack.pop_back()
		if not _tiles.has(key):
			continue
		var tile := _tiles[key] as StreamTile
		if tile.heights.is_empty():
			if tile.elev_failed and tile.z < _cap(_horiz(tile, focus)):
				_request_children(tile)
				for child_key in _child_keys(tile):
					if _tiles.has(child_key) and _inside(_tiles[child_key] as StreamTile, focus.x, focus.z):
						stack.append(child_key)
			continue
		var horiz := _horiz(tile, focus)
		var cap := _cap(horiz)
		var sse := _sse(tile, cam, pixels)
		var split := tile.z < cap and tile.z < MAX_Z and sse > 6.0
		if split:
			_request_children(tile)
			if _children_meshed(tile) and tile.blend >= 0.98:
				tile.mode = "split"
				for child_key in _child_keys(tile):
					stack.append(child_key)
			elif _children_meshed(tile):
				tile.mode = "split"
				for child_key in _child_keys(tile):
					if _tiles.has(child_key):
						(_tiles[child_key] as StreamTile).mode = "in"
			else:
				tile.mode = "leaf"
		else:
			tile.mode = "leaf"


func _animate(dt: float) -> void:
	for key in _tiles.keys():
		var tile := _tiles[key] as StreamTile
		var target := 0.0
		if tile.mode == "leaf":
			target = 1.0
			tile.blend = move_toward(tile.blend, 0.0, dt / 0.4)
		elif tile.mode == "split":
			tile.blend = move_toward(tile.blend, 1.0, dt / 0.35)
			target = 1.0 - tile.blend
		elif tile.mode == "in":
			var parent := _parent(tile)
			var blend := 1.0
			if parent != null:
				blend = parent.blend
			target = blend
		else:
			tile.blend = move_toward(tile.blend, 0.0, dt / 0.4)
		tile.fade = move_toward(tile.fade, target, dt / 0.3)
		if tile.mat:
			tile.mat.set_shader_parameter("fade", clampf(tile.fade, 0.0, 1.0))
		if tile.node:
			tile.node.visible = tile.fade > 0.03


func _request_children(tile: StreamTile) -> void:
	for dy in range(2):
		for dx in range(2):
			_ensure(tile.z + 1, tile.x * 2 + dx, tile.y * 2 + dy)


func _children_meshed(tile: StreamTile) -> bool:
	for child_key in _child_keys(tile):
		if not _tiles.has(child_key):
			return false
		if (_tiles[child_key] as StreamTile).node == null:
			return false
	return true


func _child_keys(tile: StreamTile) -> Array[String]:
	var keys: Array[String] = []
	for dy in range(2):
		for dx in range(2):
			var z := tile.z + 1
			var n := int(pow(2.0, z))
			var x := posmod(tile.x * 2 + dx, n)
			var y := tile.y * 2 + dy
			if y >= 0 and y < n:
				keys.append(_key(z, x, y))
	return keys


func _parent(tile: StreamTile) -> StreamTile:
	if tile.z <= MIN_Z:
		return null
	var key := _key(tile.z - 1, int(tile.x / 2), int(tile.y / 2))
	if not _tiles.has(key):
		return null
	return _tiles[key] as StreamTile


func _build_some(focus: Vector3, budget: int) -> void:
	var pending: Array = []
	for key in _tiles.keys():
		var tile := _tiles[key] as StreamTile
		if tile.node != null or tile.heights.is_empty():
			continue
		if tile.tex == null and not tile.img_failed:
			continue
		pending.append(tile)
	pending.sort_custom(func(a: Variant, b: Variant) -> bool:
		var ta := a as StreamTile
		var tb := b as StreamTile
		if ta.z != tb.z:
			return ta.z < tb.z
		return _horiz(ta, focus) < _horiz(tb, focus)
	)
	var built := 0
	for item in pending:
		if built >= budget:
			break
		_mesh(item as StreamTile)
		built += 1


func _mesh(tile: StreamTile) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var span_x := tile.max_x - tile.min_x
	var span_z := tile.max_z - tile.min_z
	var drop := maxf(span_x * 0.012, 24.0)
	for j in GRID - 1:
		for i in GRID - 1:
			var a := _local(tile, i, j)
			var b := _local(tile, i + 1, j)
			var c := _local(tile, i, j + 1)
			var d := _local(tile, i + 1, j + 1)
			_tri(st, a, c, b, Vector2(float(i) / 32.0, float(j) / 32.0), Vector2(float(i) / 32.0, float(j + 1) / 32.0), Vector2(float(i + 1) / 32.0, float(j) / 32.0))
			_tri(st, b, c, d, Vector2(float(i + 1) / 32.0, float(j) / 32.0), Vector2(float(i) / 32.0, float(j + 1) / 32.0), Vector2(float(i + 1) / 32.0, float(j + 1) / 32.0))
	for i in GRID - 1:
		var a0 := _local(tile, i, 0)
		var b0 := _local(tile, i + 1, 0)
		_skirt(st, a0, b0, drop, float(i) / 32.0, 0.0)
		var a1 := _local(tile, i, GRID - 1)
		var b1 := _local(tile, i + 1, GRID - 1)
		_skirt(st, b1, a1, drop, float(i) / 32.0, 1.0)
	for j in GRID - 1:
		var a2 := _local(tile, 0, j)
		var b2 := _local(tile, 0, j + 1)
		_skirt(st, b2, a2, drop, 0.0, float(j) / 32.0)
		var a3 := _local(tile, GRID - 1, j)
		var b3 := _local(tile, GRID - 1, j + 1)
		_skirt(st, a3, b3, drop, 1.0, float(j) / 32.0)
	st.generate_normals()
	var mesh := st.commit()
	var mat: ShaderMaterial = null
	# The dither shader is for Forward+. The compatibility renderer (web, and
	# this VM's screenshots) draws a plain albedo so the tile cannot vanish.
	if RenderingServer.get_current_rendering_method() == "forward_plus":
		mat = ShaderMaterial.new()
		mat.shader = _Shader
		mat.set_shader_parameter("fade", 1.0)
		if tile.tex:
			mat.set_shader_parameter("imagery", tile.tex)
			mat.set_shader_parameter("has_photo", 1.0)
		else:
			mat.set_shader_parameter("has_photo", 0.0)
		mesh.surface_set_material(0, mat)
	else:
		var plain := StandardMaterial3D.new()
		plain.albedo_color = Color(0.42, 0.4, 0.34)
		plain.albedo_texture = tile.tex
		plain.roughness = 0.92
		plain.cull_mode = BaseMaterial3D.CULL_DISABLED
		mesh.surface_set_material(0, plain)
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position = Vector3(tile.min_x, 0.0, tile.min_z)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if tile.z >= 12 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	tile.node = node
	tile.mat = mat
	tile.fade = 0.0
	print("stream mesh z", tile.z, " span ", snappedf(tile.max_x - tile.min_x, 1.0), " at ", snappedf(tile.min_x, 1.0), ",", snappedf(tile.min_z, 1.0))


func _local(tile: StreamTile, i: int, j: int) -> Vector3:
	var u := float(i) / 32.0
	var v := float(j) / 32.0
	var h: float = tile.heights[j * GRID + i]
	return Vector3(u * (tile.max_x - tile.min_x), h, v * (tile.max_z - tile.min_z))


func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, uva: Vector2, uvb: Vector2, uvc: Vector2) -> void:
	st.set_uv(uva)
	st.add_vertex(a)
	st.set_uv(uvb)
	st.add_vertex(b)
	st.set_uv(uvc)
	st.add_vertex(c)


func _skirt(st: SurfaceTool, a: Vector3, b: Vector3, drop: float, u: float, v: float) -> void:
	var a2 := Vector3(a.x, a.y - drop, a.z)
	var b2 := Vector3(b.x, b.y - drop, b.z)
	var uv := Vector2(u, v)
	for p in [a, a2, b, b, a2, b2]:
		st.set_uv(uv)
		st.add_vertex(p)


func _evict(focus: Vector3) -> void:
	if _tiles.size() <= 72:
		return
	var ranked: Array = []
	for key in _tiles.keys():
		var tile := _tiles[key] as StreamTile
		if tile.mode != "" or tile.fade > 0.05:
			continue
		if tile.z <= 7 or tile.elev_pending or tile.img_pending:
			continue
		ranked.append(tile)
	ranked.sort_custom(func(a: Variant, b: Variant) -> bool:
		return _horiz(a as StreamTile, focus) > _horiz(b as StreamTile, focus)
	)
	var removed := 0
	for item in ranked:
		if _tiles.size() <= 56 or removed >= 8:
			break
		var tile := item as StreamTile
		if tile.node:
			tile.node.queue_free()
		_tiles.erase(tile.key)
		removed += 1


func _shift(shift: Vector3) -> Vector3:
	origin_merc += Vector2(shift.x, shift.z)
	for key in _tiles.keys():
		var tile := _tiles[key] as StreamTile
		tile.min_x -= shift.x
		tile.max_x -= shift.x
		tile.min_z -= shift.z
		tile.max_z -= shift.z
		if tile.node:
			tile.node.position -= shift
	for key in _osm.keys():
		var rec: Dictionary = _osm[key]
		var node: Node3D = rec.get("node")
		if node != null and is_instance_valid(node):
			node.position -= shift
	return shift


func _sync_osm(focus: Vector3) -> void:
	var here := _latlon(focus.x, focus.z)
	if here.x < 44.5:
		return
	var oz := mini(12, detail_cap)
	var center: Vector2i = Tiles.tile_of(here.x, here.y, oz)
	_ensure_osm(oz, center.x, center.y)
	for dir in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		_ensure_osm(oz, center.x + dir.x, center.y + dir.y)
	var zoom_here := finest_zoom(focus.x, focus.z)
	if zoom_here < 9:
		return
	for key in _osm.keys():
		var rec: Dictionary = _osm[key]
		if not bool(rec.get("ready", false)) or bool(rec.get("empty", false)):
			continue
		if int(rec.get("built_zoom", -1)) == zoom_here:
			continue
		var bytes: PackedByteArray = rec.get("bytes", PackedByteArray())
		if bytes.size() < 32:
			continue
		_build_osm(key, zoom_here)
		return


func _ensure_osm(z: int, x: int, y: int) -> void:
	if z < 0:
		return
	var n := int(pow(2.0, z))
	x = posmod(x, n)
	if y < 0 or y >= n:
		return
	if _north_lat(z, y) < 44.5:
		return
	var key := "osm%d/%d/%d" % [z, x, y]
	if _osm.has(key):
		return
	_osm[key] = {
		"z": z,
		"x": x,
		"y": y,
		"ready": false,
		"built": false,
		"built_zoom": -1,
		"bytes": PackedByteArray(),
		"node": null,
	}
	_want("osm", z, x, y, OSM_URL % [z, x, y], Tiles._cache("osm", z, x, y), key)


func _apply_osm(job: Dictionary, bytes: PackedByteArray) -> void:
	var key := str(job["key"])
	if not _osm.has(key):
		return
	var rec: Dictionary = _osm[key]
	if bytes.size() < 32:
		if int(job.get("tries", 0)) < 1:
			job["tries"] = 1
			_enqueue(job)
			return
		rec["ready"] = true
		rec["empty"] = true
		_osm[key] = rec
		if osm_features == 0:
			osm_empty = true
		return
	rec["bytes"] = bytes
	rec["ready"] = true
	rec["empty"] = false
	_osm[key] = rec
	osm_empty = false


func _build_osm(key: String, zoom_here: int) -> void:
	if not _osm.has(key):
		return
	var rec: Dictionary = _osm[key]
	var bytes: PackedByteArray = rec["bytes"]
	if bytes.size() < 32:
		rec["built"] = true
		rec["built_zoom"] = zoom_here
		_osm[key] = rec
		return
	var z := int(rec["z"])
	var x := int(rec["x"])
	var y := int(rec["y"])
	var bounds := _tile_bounds(z, x, y)
	var parsed: Dictionary = _Mvt.read(bytes, bounds)
	var host := Node3D.new()
	host.name = key
	host.position = Vector3(float(bounds["min_x"]), 0.0, float(bounds["min_z"]))
	var roads := 0
	var waters := 0
	var places := 0
	var buildings := 0
	for item in parsed["roads"]:
		if roads >= 160:
			break
		var feat: Dictionary = item
		var road_class := str(feat.get("class", ""))
		if road_class == "ferry" or road_class == "aerialway":
			continue
		for ring in feat["rings"]:
			if _road(host, ring, _road_width(road_class), bounds):
				roads += 1
	for item in parsed["water"]:
		if waters >= 16:
			break
		var feat_w: Dictionary = item
		for ring in feat_w["rings"]:
			if _water(host, ring, str(feat_w.get("class", "")), bounds):
				waters += 1
	for item in parsed["buildings"]:
		if buildings >= 40:
			break
		var feat_b: Dictionary = item
		for ring in feat_b["rings"]:
			if _block(host, ring, bounds, 0.0):
				buildings += 1
				break
	for item in parsed["places"]:
		if places >= 24:
			break
		var feat_p: Dictionary = item
		if _place(host, feat_p, bounds):
			places += 1
	var previous: Node = rec.get("node")
	if previous != null and is_instance_valid(previous):
		previous.queue_free()
	_osm_root.add_child(host)
	rec["node"] = host
	rec["built"] = true
	rec["built_zoom"] = zoom_here
	_osm[key] = rec
	_built_osm_zoom = zoom_here
	osm_features = maxi(osm_features, roads + places + waters + buildings)
	print("osm ", key, " roads ", roads, " water ", waters, " buildings ", buildings, " places ", places)


func _road(host: Node3D, ring: PackedVector2Array, width: float, bounds: Dictionary) -> bool:
	if ring.size() < 2 or width <= 0.0:
		return false
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ox := float(bounds["min_x"])
	var oz := float(bounds["min_z"])
	var wrote := false
	var limit := mini(ring.size() - 1, 240)
	for i in limit:
		var a := ring[i]
		var b := ring[i + 1]
		var delta := b - a
		var length := delta.length()
		if length < 0.8:
			continue
		var dir := delta / length
		var side := Vector2(-dir.y, dir.x) * width * 0.5
		var ha := height_at(a.x, a.y)
		var hb := height_at(b.x, b.y)
		if ha < -12000.0 or hb < -12000.0:
			continue
		var lift := 0.22
		var p0 := Vector3(a.x + side.x - ox, ha + lift, a.y + side.y - oz)
		var p1 := Vector3(a.x - side.x - ox, ha + lift, a.y - side.y - oz)
		var p2 := Vector3(b.x + side.x - ox, hb + lift, b.y + side.y - oz)
		var p3 := Vector3(b.x - side.x - ox, hb + lift, b.y - side.y - oz)
		for p in [p0, p2, p1, p1, p2, p3]:
			st.add_vertex(p)
		wrote = true
	if not wrote:
		return false
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _road_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	host.add_child(mi)
	return true


func _water(host: Node3D, ring: PackedVector2Array, kind: String, bounds: Dictionary) -> bool:
	if ring.size() < 3 or ring.size() > 700:
		return false
	var idx := Geometry2D.triangulate_polygon(ring)
	if idx.size() < 3:
		return false
	var surface := _water_surface(ring, kind)
	var ox := float(bounds["min_x"])
	var oz := float(bounds["min_z"])
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var wrote := false
	var t := 0
	while t + 2 < idx.size():
		var a := ring[idx[t]]
		var b := ring[idx[t + 1]]
		var c := ring[idx[t + 2]]
		t += 3
		var mid := (a + b + c) / 3.0
		var mid_h := height_at(mid.x, mid.y)
		if mid_h < -12000.0 or mid_h > surface + 2.4:
			continue
		for p in [a, b, c]:
			st.add_vertex(Vector3(p.x - ox, surface, p.y - oz))
		wrote = true
	if not wrote:
		return false
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _water_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	host.add_child(mi)
	return true


func _block(host: Node3D, ring: PackedVector2Array, bounds: Dictionary, floors: float) -> bool:
	if ring.size() < 3:
		return false
	var min_x := ring[0].x
	var max_x := ring[0].x
	var min_z := ring[0].y
	var max_z := ring[0].y
	for p in ring:
		min_x = minf(min_x, p.x)
		max_x = maxf(max_x, p.x)
		min_z = minf(min_z, p.y)
		max_z = maxf(max_z, p.y)
	var w := max_x - min_x
	var d := max_z - min_z
	if w < 2.0 or d < 2.0 or w > 400.0 or d > 400.0:
		return false
	var cx := (min_x + max_x) * 0.5
	var cz := (min_z + max_z) * 0.5
	var ground := height_at(cx, cz)
	if ground < -12000.0:
		return false
	var height := floors
	if height < 3.0:
		height = clampf(sqrt(w * d) * 0.35, 3.2, 16.0)
	var box := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(w, height, d)
	box.mesh = mesh
	box.material_override = _town_mat
	box.position = Vector3(cx - float(bounds["min_x"]), ground + height * 0.5, cz - float(bounds["min_z"]))
	box.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	host.add_child(box)
	return true


func _place(host: Node3D, feat: Dictionary, bounds: Dictionary) -> bool:
	var kind := str(feat.get("class", ""))
	var floors := 0.0
	var count := 1
	if kind == "city":
		floors = 22.0
		count = 5
	elif kind == "town":
		floors = 12.0
		count = 4
	elif kind == "suburb":
		floors = 8.0
		count = 3
	elif kind == "village":
		floors = 6.0
		count = 2
	elif kind == "hamlet":
		floors = 4.0
		count = 1
	else:
		return false
	var rings: Array = feat["rings"]
	if rings.is_empty():
		return false
	var ring: PackedVector2Array = rings[0]
	if ring.is_empty():
		return false
	var at := ring[0]
	var placed := false
	count = mini(count, 4)
	for i in count:
		var jitter := Vector2(cos(float(i) * 2.3), sin(float(i) * 1.7)) * (6.0 + float(i) * 4.0)
		var footprint := PackedVector2Array([
			at + jitter + Vector2(-4.0, -4.0),
			at + jitter + Vector2(4.0, -4.0),
			at + jitter + Vector2(4.0, 4.0),
			at + jitter + Vector2(-4.0, 4.0),
		])
		var h := floors * (1.0 - float(i) * 0.12)
		if _block(host, footprint, bounds, h):
			placed = true
	return placed


func _water_surface(ring: PackedVector2Array, kind: String) -> float:
	if kind == "ocean" or kind == "sea":
		return 0.2
	var samples: Array[float] = []
	var step := maxi(int(ring.size() / 12), 1)
	var i := 0
	while i < ring.size():
		var h := height_at(ring[i].x, ring[i].y)
		if h > -12000.0:
			samples.append(h)
		i += step
	if samples.is_empty():
		return 0.2
	samples.sort()
	return samples[int(float(samples.size()) * 0.25)] + 0.15


func _road_width(kind: String) -> float:
	match kind:
		"motorway":
			return 9.0
		"trunk":
			return 7.5
		"primary":
			return 6.2
		"secondary":
			return 5.2
		"tertiary":
			return 4.2
		"minor", "unclassified":
			return 3.2
		"service", "track":
			return 2.4
		_:
			return 3.0


func _tile_bounds(z: int, x: int, y: int) -> Dictionary:
	var n := pow(2.0, z)
	var lon0 := float(x) / n * 360.0 - 180.0
	var lon1 := float(x + 1) / n * 360.0 - 180.0
	var lat_n := _lat_of(float(y) / n)
	var lat_s := _lat_of(float(y + 1) / n)
	var sw := _merc(lat_s, lon0) - origin_merc
	var ne := _merc(lat_n, lon1) - origin_merc
	return {"min_x": sw.x, "max_x": ne.x, "min_z": sw.y, "max_z": ne.y}


func _measure(tile: StreamTile) -> void:
	var bounds := _tile_bounds(tile.z, tile.x, tile.y)
	tile.min_x = float(bounds["min_x"])
	tile.max_x = float(bounds["max_x"])
	tile.min_z = float(bounds["min_z"])
	tile.max_z = float(bounds["max_z"])


func _decode_elev(img: Image) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(GRID * GRID)
	var w := img.get_width()
	var h := img.get_height()
	if w < 2 or h < 2:
		return PackedFloat32Array()
	for j in GRID:
		var v := float(j) / 32.0
		var row := clampi(int(round((1.0 - v) * float(h - 1))), 0, h - 1)
		for i in GRID:
			var u := float(i) / 32.0
			var col := clampi(int(round(u * float(w - 1))), 0, w - 1)
			var px := img.get_pixel(col, row)
			out[j * GRID + i] = (px.r * 255.0 * 256.0 + px.g * 255.0 + px.b * 255.0 / 256.0) - 32768.0
	return out


func _bilinear(tile: StreamTile, x: float, z: float) -> float:
	var u := clampf((x - tile.min_x) / maxf(tile.max_x - tile.min_x, 0.001) * 32.0, 0.0, 32.0)
	var v := clampf((z - tile.min_z) / maxf(tile.max_z - tile.min_z, 0.001) * 32.0, 0.0, 32.0)
	var c0 := int(floor(u))
	var r0 := int(floor(v))
	var c1 := mini(c0 + 1, 32)
	var r1 := mini(r0 + 1, 32)
	var tx := u - float(c0)
	var tz := v - float(r0)
	var h00: float = tile.heights[r0 * GRID + c0]
	var h10: float = tile.heights[r0 * GRID + c1]
	var h01: float = tile.heights[r1 * GRID + c0]
	var h11: float = tile.heights[r1 * GRID + c1]
	return lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), tz)


func _inside(tile: StreamTile, x: float, z: float) -> bool:
	return x >= tile.min_x and x <= tile.max_x and z >= tile.min_z and z <= tile.max_z


func _horiz(tile: StreamTile, focus: Vector3) -> float:
	var x := clampf(focus.x, tile.min_x, tile.max_x)
	var z := clampf(focus.z, tile.min_z, tile.max_z)
	return Vector2(focus.x - x, focus.z - z).length()


func _sse(tile: StreamTile, cam: Vector3, pixels: float) -> float:
	var x := clampf(cam.x, tile.min_x, tile.max_x)
	var z := clampf(cam.z, tile.min_z, tile.max_z)
	var dist := Vector2(cam.x - x, cam.z - z).length()
	dist = maxf(dist, absf(cam.y) * 0.35)
	dist = maxf(dist, 50.0)
	var err := maxf(tile.max_x - tile.min_x, 1.0) / 32.0
	return err / dist * pixels


func _cap(horiz: float) -> int:
	var want := 5
	if horiz < 50000.0:
		want = 6
	if horiz < 20000.0:
		want = 8
	if horiz < 12000.0:
		want = 11
	if horiz < 4500.0:
		want = 12
	if horiz < 1800.0:
		want = 13
	if horiz < 600.0:
		want = 14
	return clampi(mini(want, detail_cap), MIN_Z, MAX_Z)


func _latlon(x: float, z: float) -> Vector2:
	var merc := origin_merc + Vector2(x, z)
	var lon := rad_to_deg(merc.x / 6378137.0)
	var lat := rad_to_deg(2.0 * atan(exp(merc.y / 6378137.0)) - PI * 0.5)
	return Vector2(lat, lon)


func _merc(lat: float, lon: float) -> Vector2:
	var clamped := clampf(lat, -85.0, 85.0)
	var s := sin(deg_to_rad(clamped))
	var y := 0.5 * 6378137.0 * log((1.0 + s) / maxf(1.0 - s, 0.0000001))
	return Vector2(deg_to_rad(lon) * 6378137.0, y)


func _lat_of(y_norm: float) -> float:
	return rad_to_deg(atan(sinh(PI * (1.0 - 2.0 * y_norm))))


func _north_lat(z: int, y: int) -> float:
	return _lat_of(float(y) / pow(2.0, z))


func _key(z: int, x: int, y: int) -> String:
	return "%d/%d/%d" % [z, x, y]
