class_name Soil
extends RefCounted

## Cut and fill on a regular height field. Volume that leaves a cell is added
## to other cells, then steep faces slump toward the angle of repose.

class Field extends RefCounted:
	var cols: int
	var rows: int
	var spacing: float
	var heights: PackedFloat32Array
	var disturb: PackedByteArray
	var changed: PackedInt32Array
	var cut_m3: float
	var fill_m3: float

	func index(c: int, r: int) -> int:
		return r * cols + c

	func contains(c: int, r: int) -> bool:
		return c >= 0 and r >= 0 and c < cols and r < rows

	func height_at(c: int, r: int) -> float:
		return heights[index(clampi(c, 0, cols - 1), clampi(r, 0, rows - 1))]

	func mark(i: int) -> void:
		changed.append(i)
		disturb[i] = 255


static func plane_blade(field: Field, east: float, north: float, fx: float, fz: float, width: float, edge_y: float, repose_deg: float) -> float:
	var spacing := field.spacing
	var area := spacing * spacing
	var under := _cells(field, east, north, spacing * 0.85, maxf(width * 0.5, spacing * 0.7), fx, fz)
	var moved := 0.0
	for i in under:
		var h: float = field.heights[i]
		if h <= edge_y + 0.02:
			continue
		var dh: float = minf(h - edge_y, 0.35)
		field.heights[i] = h - dh
		field.mark(i)
		moved += dh * area
	if moved <= 0.0:
		return 0.0
	var ahead := _cells(field, east + fx * spacing * 1.05, north + fz * spacing * 1.05, spacing * 0.22, spacing * 0.7, fx, fz)
	var pile: PackedInt32Array = ahead if ahead.size() > 0 else under
	var lift := moved / (float(pile.size()) * area)
	for i in pile:
		field.heights[i] = field.heights[i] + lift
		field.mark(i)
	_slump(field, pile, repose_deg)
	field.cut_m3 += moved
	field.fill_m3 += moved
	return moved


static func _cells(field: Field, east: float, north: float, along: float, side: float, fx: float, fz: float) -> PackedInt32Array:
	var found := PackedInt32Array()
	var spacing := field.spacing
	var min_c := maxi(0, int(floor((east - side - spacing) / spacing)))
	var max_c := mini(field.cols - 1, int(ceil((east + side + spacing) / spacing)))
	var min_r := maxi(0, int(floor((north - side - spacing) / spacing)))
	var max_r := mini(field.rows - 1, int(ceil((north + side + spacing) / spacing)))
	for r in range(min_r, max_r + 1):
		for c in range(min_c, max_c + 1):
			var dx := (float(c) + 0.5) * spacing - east
			var dn := (float(r) + 0.5) * spacing - north
			var a := dx * fx + dn * fz
			var s := dx * fz - dn * fx
			if a >= -along and a <= along and absf(s) <= side:
				found.append(field.index(c, r))
	return found


static func _slump(field: Field, seeds: PackedInt32Array, repose_deg: float) -> void:
	var slope := tan(deg_to_rad(repose_deg))
	var spacing := field.spacing
	var area := spacing * spacing
	var open := seeds.slice(0, mini(64, seeds.size()))
	for _pass in 4:
		var next := PackedInt32Array()
		for i in open:
			var c := i % field.cols
			var r := int(i / field.cols)
			var h: float = field.heights[i]
			var lowest := i
			var low_h := h
			for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nc: int = c + step.x
				var nr: int = r + step.y
				if not field.contains(nc, nr):
					continue
				var j := field.index(nc, nr)
				var other: float = field.heights[j]
				if other < low_h:
					low_h = other
					lowest = j
			if lowest == i:
				continue
			var excess := h - low_h - slope * spacing
			if excess <= 0.08:
				continue
			var shift := excess * 0.5
			field.heights[i] = h - shift
			field.heights[lowest] = low_h + shift
			field.mark(i)
			field.mark(lowest)
			field.cut_m3 += shift * area
			field.fill_m3 += shift * area
			next.append(lowest)
		open = next
		if open.is_empty():
			break
