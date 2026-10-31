class_name HallDress
## The golden-aerial review (GoldenAerial): the convention centre's two exhibition halls were plain
## white boxes - two of the biggest shapes in the downtown aerial, a white roof with nothing on it
## over a blank white wall, read as untextured blocks from 140 m. This dresses a hall the way the
## real ones are built: a weathered membrane roof in strips (lighter than the panels it is not:
## a roof is a grey film), rows of packaged rooftop units between the skylight monitors, steel
## pilasters down the long walls and a grey plinth at the foot. Geometry only, cosmetic (no
## collision), no rng (the pieces are on fixed pitches); GOLDEN_AERIAL=0 builds none of it.

## A roof strip's width (the membrane's sheets) and the units' pitch along a row.
const STRIP := 6.0
const UNIT_PITCH := 17.0
const PILASTER_PITCH := 9.0


## Dress `hall` (a rect in the builder's frame, walls from y0 to y0 + h). `monitors` are the roof
## monitors' z centres (4 m deep, the hall's width less `inset`), `key` a prefix for materials.
static func dress(g: LandmarkGeo, hall: Rect2, y0: float, h: float, monitors: Array, key: String, detailed: bool) -> void:
	if not GoldenAerial.enabled:
		return
	var roof_key := key + "_roof"
	var unit_key := key + "_unit"
	var trim_key := key + "_trim"
	g.use(roof_key, LandmarkMats.plain(roof_key, Color(0.47, 0.47, 0.455), 0.88, 0.0))
	g.use(unit_key, LandmarkMats.plain(unit_key, Color(0.52, 0.53, 0.52), 0.55, 0.35))
	g.use(trim_key, LandmarkMats.plain(trim_key, Color(0.42, 0.43, 0.43), 0.75, 0.1))
	var top := y0 + h + 0.035
	# The membrane, in sheets across the roof, each a shade off its neighbour (dirt, age, patches).
	var n := maxi(1, int(hall.size.x / STRIP))
	var w := hall.size.x / float(n)
	for i in n:
		var x0 := hall.position.x + w * float(i)
		var shade := 0.93 + 0.07 * _h(i, 3)
		var poly := PackedVector2Array([Vector2(x0, hall.position.y), Vector2(x0, hall.end.y),
			Vector2(x0 + w, hall.end.y), Vector2(x0 + w, hall.position.y)])
		g.cap(roof_key, LandmarkGeo.ccw(poly), top, Color(shade, shade, shade * 0.98))
	# Rooftop units in rows between the monitors (and between the outer ones and the parapet).
	var zs: Array = [hall.position.y + 2.0]
	for z: float in monitors:
		zs.append(z)
	zs.append(hall.end.y - 2.0)
	zs.sort()
	var k := 0
	for j in range(zs.size() - 1):
		var gap: float = zs[j + 1] - zs[j]
		if gap < 14.0:
			continue
		var zc: float = (zs[j] + zs[j + 1]) * 0.5
		var units := int((hall.size.x - 16.0) / UNIT_PITCH)
		for i in units:
			k += 1
			if _h(k, 7) < 0.22:
				continue
			var x := hall.position.x + 8.0 + UNIT_PITCH * (float(i) + 0.5)
			var big := _h(k, 11) < 0.35
			var size := Vector3(4.2, 1.7, 2.3) if big else Vector3(2.6, 1.3, 1.8)
			var c := Vector3(x + (_h(k, 13) - 0.5) * 3.0, top + size.y * 0.5, zc + (_h(k, 17) - 0.5) * 2.0)
			g.box(unit_key, c, size, Color.WHITE, Basis(), 0.06 if detailed else 0.0)
			# Its fan housing on top and a duct run down to the roof.
			g.box(trim_key, c + Vector3(size.x * 0.22, size.y * 0.5 + 0.12, 0.0), Vector3(1.0, 0.25, 1.0), Color.WHITE)
			if detailed:
				g.box(unit_key, c + Vector3(0.0, -size.y * 0.5 + 0.35, size.z * 0.5 + 1.4), Vector3(0.7, 0.7, 2.8), Color(0.9, 0.9, 0.9))
	# Pilasters and the plinth on the long walls (the -z face is the hall's front, glazed along its
	# clerestory: a plinth only).
	for z_face: float in [hall.position.y, hall.end.y]:
		var out := -1.0 if z_face == hall.position.y else 1.0
		var p := int(hall.size.x / PILASTER_PITCH)
		for i in range(1, p if out > 0.0 else 1):
			var x := hall.position.x + hall.size.x * float(i) / float(p)
			g.box(key, Vector3(x, y0 + h * 0.5, z_face + out * 0.2), Vector3(0.7, h, 0.4), Color(0.9, 0.9, 0.89))
		g.box(trim_key, Vector3(hall.get_center().x, y0 + 0.65, z_face + out * 0.12), Vector3(hall.size.x, 1.3, 0.24), Color.WHITE)
	for x_face: float in [hall.position.x, hall.end.x]:
		var out := -1.0 if x_face == hall.position.x else 1.0
		g.box(trim_key, Vector3(x_face + out * 0.12, y0 + 0.65, hall.get_center().y), Vector3(0.24, 1.3, hall.size.y), Color.WHITE)
		var q := int(hall.size.y / PILASTER_PITCH)
		for i in range(1, q):
			var z := hall.position.y + hall.size.y * float(i) / float(q)
			g.box(key, Vector3(x_face + out * 0.2, y0 + h * 0.5, z), Vector3(0.4, h, 0.7), Color(0.9, 0.9, 0.89))


static func _h(i: int, salt: int) -> float:
	return float(hash([i, salt, "hall_dress"]) % 10007) / 10007.0
