class_name NorthMap
extends Control

signal pinned(lat: float, lon: float)

var tex: Texture2D
var half_m := 1.0
var posts := 1
var step_m := 1.0
var lat_limit := 45.0
var zoom := 1.0
var pan := Vector2.ZERO
var pin := Vector2(999.0, 999.0)
var pin_ok := false
var highlight: PackedVector2Array = PackedVector2Array()
var marks: Array = []
var _drag := false
var _moved := false
var _press := Vector2.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/north.json"))
	if parsed == null:
		return
	var meta: Dictionary = parsed
	half_m = float(meta["half_m"])
	posts = int(meta["posts"])
	step_m = float(meta["step_m"])
	lat_limit = float(meta["lat_limit"])
	tex = load("res://data/%s" % str(meta["color"]))
	queue_redraw()


func set_highlight(points: PackedVector2Array) -> void:
	highlight = points
	queue_redraw()


func set_marks(next: Array) -> void:
	marks = next
	queue_redraw()


func drop_latlon(lat: float, lon: float) -> void:
	if lat < lat_limit:
		return
	pin = Vector2(lat, lon)
	pin_ok = true
	pinned.emit(lat, lon)
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_WHEEL_UP and button.pressed:
			_zoom_at(button.position, 1.15)
			accept_event()
		elif button.button_index == MOUSE_BUTTON_WHEEL_DOWN and button.pressed:
			_zoom_at(button.position, 1.0 / 1.15)
			accept_event()
		elif button.button_index == MOUSE_BUTTON_LEFT:
			if button.pressed:
				_drag = true
				_moved = false
				_press = button.position
			else:
				_drag = false
				if not _moved:
					_pin_at(button.position)
				accept_event()
		elif button.button_index == MOUSE_BUTTON_RIGHT and button.pressed:
			zoom = 1.0
			pan = Vector2.ZERO
			queue_redraw()
			accept_event()
	elif event is InputEventMouseMotion and _drag:
		var motion := event as InputEventMouseMotion
		if _press.distance_to(motion.position) > 4.0:
			_moved = true
		if _moved:
			pan += motion.relative
			queue_redraw()
		accept_event()


func _zoom_at(at: Vector2, factor: float) -> void:
	var before: Variant = _projected(at)
	zoom = clampf(zoom * factor, 0.8, 18.0)
	var origin := _origin()
	var scale := _scale()
	# Keep the geographic point under the cursor.
	if before is Vector2:
		var spot: Vector2 = before
		var col := (spot.x + half_m) / step_m
		var row := (half_m - spot.y) / step_m
		var next := origin + Vector2(col, row) * scale
		pan += at - next
	queue_redraw()


func _pin_at(at: Vector2) -> void:
	var projected: Variant = _projected(at)
	if projected == null:
		return
	var ll := Geo.polar_inverse(projected)
	if ll.x < lat_limit:
		return
	drop_latlon(ll.x, ll.y)


func _projected(at: Vector2) -> Variant:
	if tex == null:
		return null
	var origin := _origin()
	var scale := _scale()
	if scale <= 0.0:
		return null
	var col := (at.x - origin.x) / scale
	var row := (at.y - origin.y) / scale
	if col < 0.0 or row < 0.0 or col > float(posts - 1) or row > float(posts - 1):
		return null
	var x := -half_m + col * step_m
	var y := half_m - row * step_m
	return Vector2(x, y)


func _scale() -> float:
	var fit := minf(size.x, size.y) / float(maxi(posts, 1))
	return fit * zoom * 0.96


func _origin() -> Vector2:
	var draw := float(posts) * _scale()
	return size * 0.5 + pan - Vector2(draw, draw) * 0.5


func _screen(lat: float, lon: float) -> Vector2:
	var p := Geo.polar_forward(lat, lon)
	var col := (p.x + half_m) / step_m
	var row := (half_m - p.y) / step_m
	return _origin() + Vector2(col, row) * _scale()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.04, 0.07, 0.1))
	if tex == null:
		return
	var origin := _origin()
	var draw := float(posts) * _scale()
	draw_texture_rect(tex, Rect2(origin, Vector2(draw, draw)), false)
	if highlight.size() >= 3:
		var poly := PackedVector2Array()
		var mid := Vector2.ZERO
		for ll in highlight:
			poly.append(_screen(ll.x, ll.y))
			mid += ll
		poly.append(poly[0])
		draw_polyline(poly, Color(0.95, 0.78, 0.25), 2.0, true)
		mid /= float(highlight.size())
		var center := _screen(mid.x, mid.y)
		var edge := _screen(mid.x + 0.35, mid.y)
		draw_arc(center, maxf(center.distance_to(edge), 11.0), 0.0, TAU, 40, Color(0.95, 0.78, 0.25), 2.5, true)
	for mark in marks:
		var at := _screen(float(mark["lat"]), float(mark["lon"]))
		draw_circle(at, 4.0, Color(0.75, 0.86, 0.95, 0.9))
	if pin_ok:
		var pin_at := _screen(pin.x, pin.y)
		draw_line(pin_at + Vector2(0, -14), pin_at, Color(0.93, 0.28, 0.22), 2.0)
		draw_circle(pin_at, 5.0, Color(0.93, 0.28, 0.22))
		draw_circle(pin_at, 2.0, Color(1, 0.95, 0.9))
