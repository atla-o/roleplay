extends SceneTree

func _init() -> void:
	var ok := _run()
	quit(0 if ok else 1)


func _run() -> bool:
	var lib = preload("res://scripts/soil.gd")
	var field = lib.Field.new()
	field.cols = 48
	field.rows = 48
	field.spacing = 2.0
	field.heights = PackedFloat32Array()
	field.heights.resize(48 * 48)
	field.heights.fill(10.0)
	field.disturb = PackedByteArray()
	field.disturb.resize(48 * 48)
	field.changed = PackedInt32Array()
	var before := 0.0
	for h in field.heights:
		before += h
	var moved: float = lib.plane_blade(field, 40.0, 40.0, 0.0, 1.0, 3.6, 9.4, 35.0)
	var after := 0.0
	for h in field.heights:
		after += h
	print("moved ", moved, " sum ", before, " -> ", after, " cut ", field.cut_m3, " fill ", field.fill_m3)
	if moved <= 0.0:
		push_error("blade should cut")
		return false
	if absf(field.cut_m3 - field.fill_m3) > 0.001:
		push_error("cut does not equal fill")
		return false
	if absf(after - before) > 0.05:
		push_error("height sum changed")
		return false
	var idle: float = lib.plane_blade(field, 40.0, 40.0, 0.0, 1.0, 3.6, 100.0, 35.0)
	if idle != 0.0:
		push_error("a blade above the ground moved soil")
		return false
	print("conservation ok")
	return true
