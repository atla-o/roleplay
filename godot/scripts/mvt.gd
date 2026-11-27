class_name Mvt
extends RefCounted

## Minimal Mapbox vector tile reader for OpenFreeMap / OpenMapTiles layers.
## Geometry comes back in world metres using the tile's current bounds.


static func read(buf: PackedByteArray, bounds: Dictionary) -> Dictionary:
	var out := {
		"water": [],
		"roads": [],
		"buildings": [],
		"places": [],
	}
	if buf.is_empty():
		return out
	var layers := _collect(buf, 3)
	for layer_buf in layers:
		var layer: PackedByteArray = layer_buf
		var name := ""
		var extent := 4096
		var keys: PackedStringArray = PackedStringArray()
		var values: Array = []
		var features: Array = []
		var i := 0
		while i < layer.size():
			var key := 0
			var wire := 0
			var step: Array = _key(layer, i)
			if step.is_empty():
				break
			key = int(step[0])
			wire = int(step[1])
			i = int(step[2])
			if wire == 0:
				var vn: Array = _varint(layer, i)
				if vn.is_empty():
					break
				i = int(vn[1])
				if key == 5:
					extent = maxi(int(vn[0]), 1)
			elif wire == 2:
				var ln: Array = _varint(layer, i)
				if ln.is_empty():
					break
				var n := int(ln[0])
				i = int(ln[1])
				if i + n > layer.size():
					break
				var blob := layer.slice(i, i + n)
				i += n
				if key == 1:
					name = blob.get_string_from_utf8()
				elif key == 3:
					keys.append(blob.get_string_from_utf8())
				elif key == 4:
					values.append(_value(blob))
				elif key == 2:
					features.append(blob)
			elif wire == 1:
				i += 8
			elif wire == 5:
				i += 4
			else:
				break
		if not _wanted(name):
			continue
		for feat_buf in features:
			var feat: Dictionary = _feature(feat_buf, keys, values, bounds, float(extent))
			if feat.is_empty():
				continue
			if name == "water":
				(out["water"] as Array).append(feat)
			elif name == "transportation":
				(out["roads"] as Array).append(feat)
			elif name == "building":
				(out["buildings"] as Array).append(feat)
			elif name == "place":
				(out["places"] as Array).append(feat)
	return out


static func _wanted(name: String) -> bool:
	return name == "water" or name == "transportation" or name == "building" or name == "place"


static func _collect(buf: PackedByteArray, field: int) -> Array:
	var found: Array = []
	var i := 0
	while i < buf.size():
		var step: Array = _key(buf, i)
		if step.is_empty():
			break
		var key := int(step[0])
		var wire := int(step[1])
		i = int(step[2])
		if wire == 2:
			var ln: Array = _varint(buf, i)
			if ln.is_empty():
				break
			var n := int(ln[0])
			i = int(ln[1])
			if i + n > buf.size():
				break
			if key == field:
				found.append(buf.slice(i, i + n))
			i += n
		elif wire == 0:
			var vn: Array = _varint(buf, i)
			if vn.is_empty():
				break
			i = int(vn[1])
		elif wire == 1:
			i += 8
		elif wire == 5:
			i += 4
		else:
			break
	return found


static func _feature(buf: PackedByteArray, keys: PackedStringArray, values: Array, bounds: Dictionary, extent: float) -> Dictionary:
	var tags: Array = []
	var geom: Array = []
	var gtype := 0
	var i := 0
	while i < buf.size():
		var step: Array = _key(buf, i)
		if step.is_empty():
			break
		var key := int(step[0])
		var wire := int(step[1])
		i = int(step[2])
		if wire == 0:
			var vn: Array = _varint(buf, i)
			if vn.is_empty():
				break
			i = int(vn[1])
			if key == 3:
				gtype = int(vn[0])
			elif key == 2:
				tags.append(int(vn[0]))
			elif key == 4:
				geom.append(int(vn[0]))
		elif wire == 2:
			var ln: Array = _varint(buf, i)
			if ln.is_empty():
				break
			var n := int(ln[0])
			i = int(ln[1])
			if i + n > buf.size():
				break
			var blob := buf.slice(i, i + n)
			i += n
			if key == 2 or key == 4:
				var j := 0
				while j < blob.size():
					var inner: Array = _varint(blob, j)
					if inner.is_empty():
						break
					j = int(inner[1])
					if key == 2:
						tags.append(int(inner[0]))
					else:
						geom.append(int(inner[0]))
		elif wire == 1:
			i += 8
		elif wire == 5:
			i += 4
		else:
			break
	var props := {}
	var t := 0
	while t + 1 < tags.size():
		var ki := int(tags[t])
		var vi := int(tags[t + 1])
		t += 2
		if ki < 0 or ki >= keys.size() or vi < 0 or vi >= values.size():
			continue
		props[keys[ki]] = values[vi]
	var rings: Array = _rings(geom, bounds, extent)
	if rings.is_empty():
		return {}
	return {"type": gtype, "class": str(props.get("class", "")), "name": str(props.get("name", "")), "rings": rings}


static func _rings(geom: Array, bounds: Dictionary, extent: float) -> Array:
	var rings: Array = []
	var cur := PackedVector2Array()
	var cx := 0
	var cy := 0
	var i := 0
	while i < geom.size():
		var cmdi := int(geom[i])
		i += 1
		var cmd := cmdi & 7
		var count := cmdi >> 3
		if count < 0 or count > 200000:
			break
		if cmd == 1:
			if cur.size() >= 2:
				rings.append(cur)
			cur = PackedVector2Array()
			for _k in count:
				if i + 1 >= geom.size():
					return rings
				cx += _zz(int(geom[i]))
				i += 1
				cy += _zz(int(geom[i]))
				i += 1
				cur.append(_xy(cx, cy, bounds, extent))
		elif cmd == 2:
			for _k in count:
				if i + 1 >= geom.size():
					return rings
				cx += _zz(int(geom[i]))
				i += 1
				cy += _zz(int(geom[i]))
				i += 1
				cur.append(_xy(cx, cy, bounds, extent))
		elif cmd == 7:
			if cur.size() >= 3:
				rings.append(cur)
			cur = PackedVector2Array()
		else:
			break
	if cur.size() >= 1:
		rings.append(cur)
	return rings


static func _xy(px: int, py: int, bounds: Dictionary, extent: float) -> Vector2:
	var u := clampf(float(px) / extent, 0.0, 1.0)
	var v := clampf(float(py) / extent, 0.0, 1.0)
	var x := lerpf(float(bounds["min_x"]), float(bounds["max_x"]), u)
	# Tile y grows south. World +Z is north.
	var z := lerpf(float(bounds["max_z"]), float(bounds["min_z"]), v)
	return Vector2(x, z)


static func _zz(n: int) -> int:
	var v := n >> 1
	if (n & 1) != 0:
		return -v - 1
	return v


static func _value(buf: PackedByteArray) -> Variant:
	var i := 0
	while i < buf.size():
		var step: Array = _key(buf, i)
		if step.is_empty():
			break
		var key := int(step[0])
		var wire := int(step[1])
		i = int(step[2])
		if wire == 2:
			var ln: Array = _varint(buf, i)
			if ln.is_empty():
				break
			var n := int(ln[0])
			i = int(ln[1])
			if i + n > buf.size():
				break
			var blob := buf.slice(i, i + n)
			i += n
			if key == 1:
				return blob.get_string_from_utf8()
		elif wire == 0:
			var vn: Array = _varint(buf, i)
			if vn.is_empty():
				break
			i = int(vn[1])
			if key == 7:
				return int(vn[0]) != 0
			return int(vn[0])
		elif wire == 5:
			if i + 4 > buf.size():
				break
			var f := buf.decode_float(i)
			i += 4
			return f
		elif wire == 1:
			if i + 8 > buf.size():
				break
			var d := buf.decode_double(i)
			i += 8
			return d
		else:
			break
	return ""


static func _key(buf: PackedByteArray, i: int) -> Array:
	var vn: Array = _varint(buf, i)
	if vn.is_empty():
		return []
	var k := int(vn[0])
	return [k >> 3, k & 7, int(vn[1])]


static func _varint(buf: PackedByteArray, i: int) -> Array:
	var shift := 0
	var result := 0
	while i < buf.size() and shift < 63:
		var b := int(buf[i])
		i += 1
		result |= (b & 0x7f) << shift
		if (b & 0x80) == 0:
			return [result, i]
		shift += 7
	return []
