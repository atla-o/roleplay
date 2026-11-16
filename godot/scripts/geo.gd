class_name Geo
extends RefCounted

## Spherical polar stereographic, tangent at the north pole.
## +X is 90°E. +Y is 180°. Matches tools/bake/north.py.

const R := 6378137.0


static func polar_rho(lat_deg: float) -> float:
	var lat := deg_to_rad(lat_deg)
	return 2.0 * R * tan(PI * 0.25 - lat * 0.5)


static func polar_forward(lat_deg: float, lon_deg: float) -> Vector2:
	var rho := polar_rho(lat_deg)
	var lon := deg_to_rad(lon_deg)
	return Vector2(rho * sin(lon), -rho * cos(lon))


static func polar_inverse(p: Vector2) -> Vector2:
	var rho := p.length()
	var lon := rad_to_deg(atan2(p.x, -p.y))
	var lat := rad_to_deg(PI * 0.5 - 2.0 * atan(rho / (2.0 * R)))
	return Vector2(lat, lon)


## WGS84 UTM. Zone is 1..60. Northern hemisphere.
static func utm_forward(lat_deg: float, lon_deg: float, zone: int) -> Vector2:
	var a := 6378137.0
	var f := 1.0 / 298.257223563
	var b := a * (1.0 - f)
	var e2 := (a * a - b * b) / (a * a)
	var ep2 := e2 / (1.0 - e2)
	var k0 := 0.9996
	var lat := deg_to_rad(lat_deg)
	var lon := deg_to_rad(lon_deg)
	var lon0 := deg_to_rad(float(zone) * 6.0 - 183.0)
	var sin_lat := sin(lat)
	var cos_lat := cos(lat)
	var n := a / sqrt(1.0 - e2 * sin_lat * sin_lat)
	var t := tan(lat) * tan(lat)
	var c := ep2 * cos_lat * cos_lat
	var aa := cos_lat * (lon - lon0)
	var m := a * (
		(1.0 - e2 / 4.0 - 3.0 * e2 * e2 / 64.0 - 5.0 * e2 * e2 * e2 / 256.0) * lat
		- (3.0 * e2 / 8.0 + 3.0 * e2 * e2 / 32.0 + 45.0 * e2 * e2 * e2 / 1024.0) * sin(2.0 * lat)
		+ (15.0 * e2 * e2 / 256.0 + 45.0 * e2 * e2 * e2 / 1024.0) * sin(4.0 * lat)
		- (35.0 * e2 * e2 * e2 / 3072.0) * sin(6.0 * lat)
	)
	var east := k0 * n * (
		aa
		+ (1.0 - t + c) * aa * aa * aa / 6.0
		+ (5.0 - 18.0 * t + t * t + 72.0 * c - 58.0 * ep2) * aa * aa * aa * aa * aa / 120.0
	) + 500000.0
	var north := k0 * (
		m
		+ n * tan(lat) * (
			aa * aa / 2.0
			+ (5.0 - t + 9.0 * c + 4.0 * c * c) * aa * aa * aa * aa / 24.0
			+ (61.0 - 58.0 * t + t * t + 600.0 * c - 330.0 * ep2) * pow(aa, 6.0) / 720.0
		)
	)
	if lat_deg < 0.0:
		north += 10000000.0
	return Vector2(east, north)


## Local metres from a site frame. kind "utm" uses zone, east0, north0.
## kind "local" uses a lat/lon at (cx, cz) and a flat degree scale, which is
## enough inside a 4 km tile.
static func to_local(lat: float, lon: float, frame: Dictionary) -> Vector2:
	var kind := str(frame.get("kind", "local"))
	if kind == "utm":
		var utm := utm_forward(lat, lon, int(frame["zone"]))
		return Vector2(utm.x - float(frame["east0"]), utm.y - float(frame["north0"]))
	var lat0 := float(frame["lat"])
	var lon0 := float(frame["lon"])
	var scale := 111320.0
	var east := (lon - lon0) * scale * cos(deg_to_rad(lat0))
	var north := (lat - lat0) * scale
	return Vector2(float(frame["cx"]) + east, float(frame["cz"]) + north)


static func inside(lat: float, lon: float, bounds: Dictionary) -> bool:
	return lon >= float(bounds["west"]) and lon <= float(bounds["east"]) and lat >= float(bounds["south"]) and lat <= float(bounds["north"])
