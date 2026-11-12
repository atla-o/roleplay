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
		var dh: float = minf(h - edge_y, 0.5)
		field.heights[i] = h - dh
		field.mark(i)
		moved += dh * area
	if moved <= 0.0:
		return 0.0
	# A narrow band just ahead of the blade, as wide as the blade, so the spoil
	# stands up as a windrow instead of being smeared across the cut.
	# Drop the spoil far enough ahead that a 35° face does not run back and fill the trench.
	var ahead_dist := maxf(spacing * 1.8, 2.1)
	var pile_side := minf(maxf(width * 0.34, spacing), width * 0.5)
	var ahead := _cells(field, east + fx * ahead_dist, north + fz * ahead_dist, maxf(spacing * 0.8, 0.28), pile_side, fx, fz)
	var pile: PackedInt32Array = ahead if ahead.size() > 0 else under
	var lift := moved / (float(pile.size()) * area)
	for i in pile:
		field.heights[i] = field.heights[i] + lift
		field.mark(i)
	_slump(field, pile, repose_deg, fx, fz)
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


static func _slump(field: Field, seeds: PackedInt32Array, repose_deg: float, fx: float, fz: float) -> void:
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
				if along < -field.spacing * 0.25:
					continue
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
		if live and not force and focus.distance_to(center) < 14.0:
			return false
		if live:
			bake()
		origin = Vector2(snappedf(focus.x - size * 0.5, CELL), snappedf(focus.y - size * 0.5, CELL))
		_fill()
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
