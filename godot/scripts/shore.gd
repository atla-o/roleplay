class_name ShoreField
extends RefCounted

## Jump-flood distance from each water texel to the nearest land texel.
## The result is metres in the red channel, divided by `scale`.


static func build(heights: PackedFloat32Array, cols: int, rows: int, water_y: float, world_span: float, n: int, scale: float) -> Image:
	var count := n * n
	var land := PackedByteArray()
	land.resize(count)
	for j in n:
		var field_r := rows - 1 - int(round(float(j) / float(n - 1) * float(rows - 1)))
		field_r = clampi(field_r, 0, rows - 1)
		for i in n:
			var field_c := clampi(int(round(float(i) / float(n - 1) * float(cols - 1))), 0, cols - 1)
			var h: float = heights[field_r * cols + field_c]
			land[j * n + i] = 1 if h > water_y + 0.05 else 0
	var ax := PackedInt32Array()
	var ay := PackedInt32Array()
	ax.resize(count)
	ay.resize(count)
	for i in count:
		if land[i] == 1:
			ax[i] = i % n
			ay[i] = int(i / n)
		else:
			ax[i] = -1
			ay[i] = -1
	var bx := ax.duplicate()
	var by := ay.duplicate()
	var step := n >> 1
	var src_x := ax
	var src_y := ay
	var dst_x := bx
	var dst_y := by
	while step >= 1:
		for y in n:
			var y_base := y * n
			for x in n:
				var best := 100000000.0
				var sx := -1
				var sy := -1
				for oy_i in range(3):
					var oy := -step if oy_i == 0 else (0 if oy_i == 1 else step)
					var yy := y + oy
					if yy < 0 or yy >= n:
						continue
					var row := yy * n
					for ox_i in range(3):
						var ox := -step if ox_i == 0 else (0 if ox_i == 1 else step)
						var xx := x + ox
						if xx < 0 or xx >= n:
							continue
						var seed_x := src_x[row + xx]
						if seed_x < 0:
							continue
						var seed_y := src_y[row + xx]
						var dx := float(seed_x - x)
						var dy := float(seed_y - y)
						var d := dx * dx + dy * dy
						if d < best:
							best = d
							sx = seed_x
							sy = seed_y
				dst_x[y_base + x] = sx
				dst_y[y_base + x] = sy
		var swap_x := src_x
		var swap_y := src_y
		src_x = dst_x
		src_y = dst_y
		dst_x = swap_x
		dst_y = swap_y
		step >>= 1
	var metres := world_span / float(n)
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	for y in n:
		var row := y * n
		for x in n:
			var sx2 := src_x[row + x]
			var dist := 0.0
			if sx2 >= 0:
				var dx2 := float(sx2 - x)
				var dy2 := float(src_y[row + x] - y)
				dist = sqrt(dx2 * dx2 + dy2 * dy2) * metres
			var u := clampf(dist / scale, 0.0, 1.0)
			img.set_pixel(x, y, Color(u, u, u))
	return img
