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
	var side := maxf(width * 0.5, spacing * 0.6)
	var under := _cells(field, east, north, maxf(spacing * 0.9, 0.4), side, fx, fz)
	var protected := {}
	var moved := 0.0
	for i in under:
		protected[i] = true
		var h: float = field.heights[i]
		if h <= edge_y + 0.015:
			continue
		var dh: float = minf(h - edge_y, 1.4)
		field.heights[i] = h - dh
		field.mark(i)
		moved += dh * area
	if moved <= 0.0:
		return 0.0
	# A heap just ahead of the steel, inside the next bite, so the blade keeps
	# pushing it. The rest spills off both ends as a repose-shaped windrow.
	var rx := fz
	var rz := -fx
	var pile_vol := moved * 0.4
	var side_vol := moved - pile_vol
	var reach := maxf(spacing * 0.8, 0.3)
	var front := _open_cells(field, _cells(field, east + fx * maxf(spacing, 0.7), north + fz * maxf(spacing, 0.7), reach, side * 0.9, fx, fz), protected, edge_y)
	var placed := _add_volume(field, front, pile_vol, area)
	side_vol += pile_vol - placed
	var bands: Array[float] = [0.45, 1.05, 1.75, 2.55]
	var weights: Array[float] = [1.0, 0.62, 0.32, 0.12]
	var weight_sum := 0.0
	for w in weights:
		weight_sum += w
	var berm := PackedInt32Array()
	for side_sign in [-1.0, 1.0]:
		var unplaced := side_vol * 0.5
		for b in bands.size():
			var off: float = side + bands[b]
			var band := _open_cells(field, _cells(field, east + rx * side_sign * off, north + rz * side_sign * off, maxf(spacing * 1.5, 0.9), maxf(spacing * 0.55, 0.42), fx, fz), protected, edge_y)
			var give: float = side_vol * 0.5 * weights[b] / weight_sum
			var got := _add_volume(field, band, give, area)
			unplaced -= got
			berm.append_array(band)
		if unplaced > 0.0001 and berm.size() > 0:
			_add_volume(field, berm, unplaced, area)
	_slump(field, berm, repose_deg, fx, fz, protected, edge_y)
	_even_ridge(field, berm)
	field.cut_m3 += moved
	field.fill_m3 += moved
	return moved


static func _even_ridge(field: Field, cells: PackedInt32Array) -> void:
	var member := {}
	for i in cells:
		member[i] = true
	for _pass in 5:
		for i in cells:
			var c := i % field.cols
			var r := int(i / field.cols)
			var h: float = field.heights[i]
			for step in [Vector2i(1, 0), Vector2i(0, 1)]:
				var nc: int = c + step.x
				var nr: int = r + step.y
				if not field.contains(nc, nr):
					continue
				var j := field.index(nc, nr)
				if not member.has(j):
					continue
				var other: float = field.heights[j]
				var diff := h - other
				if absf(diff) < 0.08:
					continue
				var shift := diff * 0.4
				field.heights[i] = h - shift
				field.heights[j] = other + shift
				h = field.heights[i]
				field.mark(i)
				field.mark(j)


## A pair of shallow grooves under the tracks. The soil they displace is
## piled between them, so the print does not create or lose volume.
static func stamp_tracks(field: Field, east: float, north: float, fx: float, fz: float) -> bool:
	var rx := fz
	var rz := -fx
	var area := field.spacing * field.spacing
	var moved := 0.0
	var grooved := PackedInt32Array()
	for side in [-0.9, 0.9]:
		var cells := _cells(field, east + rx * side, north + rz * side, 0.4, 0.26, fx, fz)
		for i in cells:
			if field.disturb[i] == 180 or field.disturb[i] == 200:
				continue
			field.heights[i] -= 0.04
			field.disturb[i] = 200 if field.disturb[i] == 255 else 180
			field.changed.append(i)
			moved += 0.04 * area
			grooved.append(i)
	if moved <= 0.0:
		return false
	var crown := _cells(field, east, north, 0.4, 0.28, fx, fz)
	if crown.is_empty():
		crown = grooved
	var lift := moved / (float(crown.size()) * area)
	for i in crown:
		if field.disturb[i] == 180 or field.disturb[i] == 200:
			continue
		field.heights[i] += lift
	if crown.size() > 0:
		# Anything the crown could not take (it was all track) goes back evenly.
		var parked := 0.0
		for i in crown:
			if field.disturb[i] == 180 or field.disturb[i] == 200:
				parked += lift * area
		if parked > 0.0 and grooved.size() > 0:
			var back := parked / (float(grooved.size()) * area)
			for i in grooved:
				field.heights[i] += back
	return true


static func _open_cells(field: Field, cells: PackedInt32Array, protected: Dictionary, edge_y: float) -> PackedInt32Array:
	var open := PackedInt32Array()
	for i in cells:
		if not protected.has(i) and field.heights[i] > edge_y + 0.05:
			open.append(i)
	return open


static func _add_volume(field: Field, cells: PackedInt32Array, volume: float, area: float) -> float:
	if volume <= 0.0 or cells.is_empty():
		return 0.0
	var share := volume / float(cells.size())
	for i in cells:
		field.heights[i] = field.heights[i] + share / area
		field.mark(i)
	return volume


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


static func _slump(field: Field, seeds: PackedInt32Array, repose_deg: float, fx: float, fz: float, protected: Dictionary, edge_y: float) -> void:
	var slope := tan(deg_to_rad(repose_deg))
	var spacing := field.spacing
	var area := spacing * spacing
	var open := seeds.slice(0, mini(900, seeds.size()))
	for _pass in 3:
		var next := PackedInt32Array()
		for i in open:
			var c := i % field.cols
			var r := int(i / field.cols)
			var h: float = field.heights[i]
			var lowest := i
			var low_h := h
			for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var along := float(step.x) * field.spacing * fx + float(step.y) * field.spacing * fz
				if along < -field.spacing * 0.2:
					continue
				var nc: int = c + step.x
				var nr: int = r + step.y
				if not field.contains(nc, nr):
					continue
				var j := field.index(nc, nr)
				if protected.has(j) or field.heights[j] <= edge_y + 0.05:
					continue
				var other: float = field.heights[j]
				if other < low_h:
					low_h = other
					lowest = j
			if lowest == i:
				continue
			var excess := h - low_h - slope * spacing
			if excess <= 0.08:
				continue
			var shift := excess * 0.45
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


## A 0.25 m patch that follows the machine. It bakes its volume back into the
## 2 m grid when it recenters, so soil is not created or lost.
class Patch extends RefCounted:
	const N := 256
	const CELL := 0.25
	var origin := Vector2.ZERO
	var field: Field
	var coarse: Field
	var live := false

	func _init(coarse_field: Field) -> void:
		coarse = coarse_field
		field = Field.new()
		field.cols = N
		field.rows = N
		field.spacing = CELL
		field.heights = PackedFloat32Array()
		field.heights.resize(N * N)
		field.disturb = PackedByteArray()
		field.disturb.resize(N * N)
		field.changed = PackedInt32Array()

	func size_m() -> float:
		return float(N - 1) * CELL

	func covers(x: float, z: float) -> bool:
		if not live:
			return false
		var lx := x - origin.x
		var lz := z - origin.y
		var size := size_m()
		return lx >= 0.0 and lz >= 0.0 and lx <= size and lz <= size

	func sample(x: float, z: float) -> float:
		var c := clampf((x - origin.x) / CELL, 0.0, float(N - 1))
		var r := clampf((z - origin.y) / CELL, 0.0, float(N - 1))
		var c0 := int(floor(c))
		var r0 := int(floor(r))
		var c1 := mini(c0 + 1, N - 1)
		var r1 := mini(r0 + 1, N - 1)
		var tx := c - float(c0)
		var tz := r - float(r0)
		var h00: float = field.heights[r0 * N + c0]
		var h10: float = field.heights[r0 * N + c1]
		var h01: float = field.heights[r1 * N + c0]
		var h11: float = field.heights[r1 * N + c1]
		return lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), tz)

	func recenter(focus: Vector2, force: bool = false) -> bool:
		var size := size_m()
		var center := origin + Vector2(size, size) * 0.5
		if live and not force and focus.distance_to(center) < 22.0:
			return false
		var old_origin := origin
		var old_heights := field.heights.duplicate()
		var old_disturb := field.disturb.duplicate()
		var had := live
		if live:
			bake()
		origin = Vector2(snappedf(focus.x - size * 0.5, CELL), snappedf(focus.y - size * 0.5, CELL))
		_fill()
		if had:
			_copy_overlap(old_origin, old_heights, old_disturb)
		live = true
		return true

	func bake() -> void:
		if not live:
			return
		var acc_sum := {}
		var acc_n := {}
		for r in N:
			var z := origin.y + (float(r) + 0.5) * CELL
			var rr := clampi(int(floor(z / coarse.spacing)), 0, coarse.rows - 1)
			for c in N:
				var x := origin.x + (float(c) + 0.5) * CELL
				var cc := clampi(int(floor(x / coarse.spacing)), 0, coarse.cols - 1)
				var key := rr * coarse.cols + cc
				acc_sum[key] = float(acc_sum.get(key, 0.0)) + field.heights[r * N + c]
				acc_n[key] = int(acc_n.get(key, 0)) + 1
		for key in acc_n.keys():
			var n: int = acc_n[key]
			if n <= 0:
				continue
			coarse.heights[int(key)] = float(acc_sum[key]) / float(n)
			coarse.changed.append(int(key))

	func _copy_overlap(old_origin: Vector2, old_heights: PackedFloat32Array, old_disturb: PackedByteArray) -> void:
		for r in N:
			var z := origin.y + float(r) * CELL
			var orow := (z - old_origin.y) / CELL
			if orow < 0.0 or orow > float(N - 1):
				continue
			var r0 := int(floor(orow))
			var r1 := mini(r0 + 1, N - 1)
			var tr := orow - float(r0)
			for c in N:
				var x := origin.x + float(c) * CELL
				var ocol := (x - old_origin.x) / CELL
				if ocol < 0.0 or ocol > float(N - 1):
					continue
				var c0 := int(floor(ocol))
				var c1 := mini(c0 + 1, N - 1)
				var tc := ocol - float(c0)
				var h00: float = old_heights[r0 * N + c0]
				var h10: float = old_heights[r0 * N + c1]
				var h01: float = old_heights[r1 * N + c0]
				var h11: float = old_heights[r1 * N + c1]
				field.heights[r * N + c] = lerpf(lerpf(h00, h10, tc), lerpf(h01, h11, tc), tr)
				field.disturb[r * N + c] = old_disturb[r0 * N + c0]

	func _fill() -> void:
		var spacing := coarse.spacing
		for r in N:
			var z := origin.y + float(r) * CELL
			for c in N:
				var x := origin.x + float(c) * CELL
				field.heights[r * N + c] = _coarse_at(x, z, spacing)
		field.disturb.fill(0)
		field.changed = PackedInt32Array()

	func _coarse_at(x: float, z: float, spacing: float) -> float:
		var c := clampf(x / spacing, 0.0, float(coarse.cols - 1))
		var r := clampf(z / spacing, 0.0, float(coarse.rows - 1))
		var c0 := int(floor(c))
		var r0 := int(floor(r))
		var c1 := mini(c0 + 1, coarse.cols - 1)
		var r1 := mini(r0 + 1, coarse.rows - 1)
		var tx := c - float(c0)
		var tz := r - float(r0)
		var h00: float = coarse.heights[r0 * coarse.cols + c0]
		var h10: float = coarse.heights[r0 * coarse.cols + c1]
		var h01: float = coarse.heights[r1 * coarse.cols + c0]
		var h11: float = coarse.heights[r1 * coarse.cols + c1]
		return lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), tz)
