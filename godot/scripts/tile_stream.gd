class_name TileStream
extends RefCounted

## Web-mercator tiles for the north, in the same z/x/y layout FableFlight uses.
## Elevation is Mapzen Terrarium on the public AWS bucket. Imagery is EOX
## Sentinel-2 cloudless. Both are cached under user://stream with a file cap.

const CACHE_CAP := 240
const ELEV := "https://s3.amazonaws.com/elevation-tiles-prod/terrarium/%d/%d/%d.png"
const IMG := "https://tiles.maps.eox.at/wmts/1.0.0/s2cloudless-2021_3857/default/GoogleMapsCompatible/%d/%d/%d.jpg"


static func tile_of(lat: float, lon: float, zoom: int) -> Vector2i:
	var n := pow(2.0, zoom)
	var x := int(floor((lon + 180.0) / 360.0 * n))
	var lat_r := deg_to_rad(lat)
	var y := int(floor((1.0 - log(tan(lat_r) + 1.0 / cos(lat_r)) / PI) / 2.0 * n))
	var limit := int(n) - 1
	return Vector2i(clampi(x, 0, limit), clampi(y, 0, limit))


static func tile_metres(lat: float, zoom: int) -> float:
	return cos(deg_to_rad(lat)) * TAU * 6378137.0 / pow(2.0, zoom)


static func fraction(lat: float, lon: float, zoom: int) -> Vector2:
	var n := pow(2.0, zoom)
	var fx := (lon + 180.0) / 360.0 * n
	var lat_r := deg_to_rad(lat)
	var fy := (1.0 - log(tan(lat_r) + 1.0 / cos(lat_r)) / PI) / 2.0 * n
	return Vector2(fx - floor(fx), fy - floor(fy))


static func fetch_patch(lat: float, lon: float, zoom: int, radius: int = 1) -> Dictionary:
	var center := tile_of(lat, lon, zoom)
	var n := int(pow(2.0, zoom))
	var side := radius * 2 + 1
	var elevs: Array = []
	var colors: Array = []
	for dy in range(-radius, radius + 1):
		var row_e: Array = []
		var row_c: Array = []
		for dx in range(-radius, radius + 1):
			var tx := posmod(center.x + dx, n)
			var ty := clampi(center.y + dy, 0, n - 1)
			var elev := _image(_cache("elev", zoom, tx, ty), ELEV % [zoom, tx, ty])
			var color := _image(_cache("img", zoom, tx, ty), IMG % [zoom, ty, tx])
			if elev == null or color == null:
				return {}
			row_e.append(elev)
			row_c.append(color)
		elevs.append(row_e)
		colors.append(row_c)
	_trim_cache()
	var stride := 2
	var cell := 256 / stride
	var posts := cell * side
	var heights := PackedFloat32Array()
	heights.resize(posts * posts)
	var paint := Image.create(posts, posts, false, Image.FORMAT_RGB8)
	var lo := 1.0e9
	var hi := -1.0e9
	for ty in side:
		for tx in side:
			var elev: Image = elevs[ty][tx]
			var color: Image = colors[ty][tx]
			for r in cell:
				for c in cell:
					var pr := r * stride
					var pc := c * stride
					var px := elev.get_pixel(pc, pr)
					var h := (px.r * 255.0 * 256.0 + px.g * 255.0 + px.b * 255.0 / 256.0) - 32768.0
					var rr := ty * cell + r
					var cc := tx * cell + c
					# Web-mercator row 0 is north. Store south-first so +Z is north.
					var out_r := posts - 1 - rr
					heights[out_r * posts + cc] = h
					lo = minf(lo, h)
					hi = maxf(hi, h)
					var cx := clampi(int(pc * color.get_width() / 256), 0, color.get_width() - 1)
					var cy := clampi(int(pr * color.get_height() / 256), 0, color.get_height() - 1)
					paint.set_pixel(cc, rr, color.get_pixel(cx, cy))
	return {
		"heights": heights,
		"posts": posts,
		"image": paint,
		"hmin": lo,
		"hmax": hi,
		"tile_m": tile_metres(lat, zoom),
		"center": center,
		"zoom": zoom,
	}


static func _cache(kind: String, zoom: int, x: int, y: int) -> String:
	return "user://stream/%s/%d/%d/%d.bin" % [kind, zoom, x, y]


static func _image(path: String, url: String) -> Image:
	var bytes := PackedByteArray()
	if FileAccess.file_exists(path):
		bytes = FileAccess.get_file_as_bytes(path)
	else:
		bytes = _http_get(url)
		if bytes.is_empty():
			return null
		DirAccess.make_dir_recursive_absolute(path.get_base_dir())
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file:
			file.store_buffer(bytes)
	var img := Image.new()
	var err := img.load_png_from_buffer(bytes) if url.ends_with(".png") else img.load_jpg_from_buffer(bytes)
	if err != OK:
		return null
	return img


static func _http_get(url: String) -> PackedByteArray:
	var secure := url.begins_with("https://")
	var rest := url.trim_prefix("https://").trim_prefix("http://")
	var slash := rest.find("/")
	if slash < 1:
		return PackedByteArray()
	var host := rest.substr(0, slash)
	var path := rest.substr(slash)
	var client := HTTPClient.new()
	var tls: TLSOptions = TLSOptions.client() if secure else null
	if client.connect_to_host(host, 443 if secure else 80, tls) != OK:
		return PackedByteArray()
	var started := Time.get_ticks_msec()
	while client.get_status() == HTTPClient.STATUS_CONNECTING or client.get_status() == HTTPClient.STATUS_RESOLVING:
		client.poll()
		if Time.get_ticks_msec() - started > 20000:
			return PackedByteArray()
		OS.delay_msec(20)
	if client.get_status() != HTTPClient.STATUS_CONNECTED:
		return PackedByteArray()
	if client.request(HTTPClient.METHOD_GET, path, ["User-Agent: roleplay"]) != OK:
		return PackedByteArray()
	while client.get_status() == HTTPClient.STATUS_REQUESTING:
		client.poll()
		if Time.get_ticks_msec() - started > 30000:
			return PackedByteArray()
		OS.delay_msec(20)
	if client.get_status() != HTTPClient.STATUS_BODY and client.get_status() != HTTPClient.STATUS_CONNECTED:
		return PackedByteArray()
	var out := PackedByteArray()
	while client.get_status() == HTTPClient.STATUS_BODY:
		client.poll()
		var chunk := client.read_response_body_chunk()
		if chunk.size() == 0:
			OS.delay_msec(10)
		else:
			out.append_array(chunk)
		if Time.get_ticks_msec() - started > 40000:
			break
	return out


static func _trim_cache() -> void:
	var root := "user://stream"
	if not DirAccess.dir_exists_absolute(root):
		return
	var files: Array[String] = []
	_walk(root, files)
	if files.size() <= CACHE_CAP:
		return
	files.sort_custom(func(a: String, b: String) -> bool:
		return FileAccess.get_modified_time(a) < FileAccess.get_modified_time(b)
	)
	while files.size() > CACHE_CAP:
		DirAccess.remove_absolute(files[0])
		files.remove_at(0)


static func _walk(dir_path: String, files: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if not name.begins_with("."):
			var full := dir_path.path_join(name)
			if dir.current_is_dir():
				_walk(full, files)
			else:
				files.append(full)
		name = dir.get_next()
	dir.list_dir_end()
