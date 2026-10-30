class_name ApronKit
extends RefCounted
## The airport's MOVING hardware (AirportGround), built in code at real size on AirportKit's one
## material and with AirportKit's own part builders, so a live truck reads exactly like the
## parked ones in the gate sets: the catering truck in three pieces (cab and chassis, the box
## body, the scissor lift between them, rebuilt as it rises), a follow-me car, the field's crash
## tender (ARFF: a six-wheel airport fire truck with roof and bumper turrets) and the open
## apparatus shed it stands in. Every mesh faces -Z, stands on y 0 and is cached (the scissor
## by its height, in 2 cm steps).

const C_LIME := Color(0.48, 0.62, 0.02)
const C_CHECK := Color(0.02, 0.02, 0.02)

static var _cache: Dictionary = {}


static func _done(key: String, st: SurfaceTool) -> ArrayMesh:
	st.index()
	var mesh := st.commit()
	mesh.surface_set_material(0, AirportKit.material())
	_cache[key] = mesh
	return mesh


## The catering truck without its body: the cab at the back (+Z), the chassis, the wheels and the
## lift's base frame. The body (catering_box()) and the scissor (scissor()) ride on it.
static func catering_base() -> ArrayMesh:
	if _cache.has("catering_base"):
		return _cache["catering_base"]
	var st := AirportKit._begin()
	AirportKit._box(st, Vector3(0.0, 1.35, 3.6), Vector3(2.4, 1.7, 1.9), AirportKit.C_WHITE, AirportKit.PAINT)
	AirportKit._box(st, Vector3(0.0, 1.85, 2.66), Vector3(2.2, 0.75, 0.04), AirportKit.C_DARK, AirportKit.GLASS)
	AirportKit._box(st, Vector3(0.0, 0.75, -0.6), Vector3(2.2, 0.5, 6.8), AirportKit.C_DARK, AirportKit.METAL)
	AirportKit._box(st, Vector3(0.0, 1.06, -0.8), Vector3(2.0, 0.12, 5.8), AirportKit.C_STEEL, AirportKit.METAL)
	AirportKit._cyl(st, Vector3(0.0, 2.2, 4.4), Vector3(0.0, 2.36, 4.4), 0.08, 0.07, 8, AirportKit.C_AMBER, AirportKit.LAMP)
	AirportKit._wheels(st, 1.0, -2.9, 3.4, 0.48, 0.32)
	return _done("catering_base", st)


## The catering box: its origin at the middle of its floor, the front platform and its door at -Z
## (toward the jet's door when the truck has backed in).
static func catering_box() -> ArrayMesh:
	if _cache.has("catering_box"):
		return _cache["catering_box"]
	var st := AirportKit._begin()
	AirportKit._box(st, Vector3(0.0, 1.3, 0.0), Vector3(2.5, 2.6, 6.2), AirportKit.C_WHITE, AirportKit.PAINT, Basis(), true)
	AirportKit._box(st, Vector3(0.0, 0.02, -3.45), Vector3(2.0, 0.08, 0.9), AirportKit.C_STEEL, AirportKit.METAL)
	AirportKit._box(st, Vector3(0.0, 0.65, -3.12), Vector3(1.4, 1.8, 0.05), AirportKit.C_DARK, AirportKit.METAL)
	for s: float in [-1.0, 1.0]:
		AirportKit._box(st, Vector3(s * 0.98, 0.55, -3.86), Vector3(0.04, 1.0, 0.04), AirportKit.C_GALV, AirportKit.METAL)
	AirportKit._box(st, Vector3(0.0, 2.62, 2.9), Vector3(0.5, 0.06, 0.18), AirportKit.C_AMBER, AirportKit.LAMP)
	return _done("catering_box", st)


## The scissor lift between the chassis (y 1.12) and the box's floor `height` metres up: two
## crossed pairs of arms either side, their angle worked out from the height.
static func scissor(height: float) -> ArrayMesh:
	var h := snappedf(clampf(height, 0.25, 4.2), 0.02)
	var key := "scissor_%d" % int(h * 50.0)
	if _cache.has(key):
		return _cache[key]
	var st := AirportKit._begin()
	var arm := 5.6
	var ang := asin(clampf((h - 0.1) / arm, 0.0, 0.95))
	var mid := Vector3(0.0, 1.12 + h * 0.5, -0.8)
	for x: float in [-1.0, 1.0]:
		for sgn: float in [-1.0, 1.0]:
			AirportKit._box(st, mid + Vector3(x, 0.0, 0.0), Vector3(0.12, 0.16, arm), AirportKit.C_STEEL, AirportKit.METAL, Basis(Vector3.RIGHT, sgn * ang))
	AirportKit._box(st, mid, Vector3(2.1, 0.12, 0.12), AirportKit.C_STEEL, AirportKit.METAL)
	return _done(key, st)


## A follow-me car: a compact yellow utility pickup with a chequered band, a lit roof sign and
## amber beacons.
static func follow_me() -> ArrayMesh:
	if _cache.has("follow_me"):
		return _cache["follow_me"]
	var st := AirportKit._begin()
	var y := AirportKit.C_YELLOW
	AirportKit._box(st, Vector3(0.0, 0.72, 0.0), Vector3(1.86, 0.62, 4.9), y, AirportKit.PAINT)
	AirportKit._box(st, Vector3(0.0, 1.3, -0.25), Vector3(1.72, 0.62, 2.2), y, AirportKit.PAINT)
	AirportKit._box(st, Vector3(0.0, 1.32, -1.38), Vector3(1.6, 0.52, 0.06), AirportKit.C_DARK, AirportKit.GLASS, Basis(Vector3.RIGHT, -0.5))
	for s: float in [-1.0, 1.0]:
		AirportKit._box(st, Vector3(s * 0.865, 1.33, -0.25), Vector3(0.02, 0.44, 1.9), AirportKit.C_DARK, AirportKit.GLASS)
		# The chequered band down each side: alternating black squares on the yellow.
		for k in 8:
			if k % 2 == 0:
				AirportKit._box(st, Vector3(s * 0.935, 0.78, -2.1 + float(k) * 0.6), Vector3(0.02, 0.28, 0.6), C_CHECK, AirportKit.PAINT)
	AirportKit._box(st, Vector3(0.0, 0.48, -2.47), Vector3(1.8, 0.2, 0.08), AirportKit.C_DARK, AirportKit.RUBBER)
	for s: float in [-1.0, 1.0]:
		AirportKit._box(st, Vector3(s * 0.66, 0.82, -2.46), Vector3(0.32, 0.12, 0.04), Color(1.0, 0.95, 0.85), AirportKit.LAMP)
	# The roof sign: a lit board on a frame, and the beacons either end of it.
	AirportKit._box(st, Vector3(0.0, 1.66, -0.3), Vector3(1.5, 0.08, 0.5), AirportKit.C_GALV, AirportKit.METAL)
	AirportKit._box(st, Vector3(0.0, 1.9, -0.3), Vector3(1.3, 0.38, 0.1), Color(1.0, 0.9, 0.6), AirportKit.LAMP)
	for s: float in [-1.0, 1.0]:
		AirportKit._cyl(st, Vector3(s * 0.72, 1.7, -0.3), Vector3(s * 0.72, 1.86, -0.3), 0.08, 0.07, 8, AirportKit.C_AMBER, AirportKit.LAMP)
	AirportKit._wheels(st, 0.8, -1.55, 1.5, 0.36, 0.26)
	return _done("follow_me", st)


## The crash tender: a six-wheel airport fire truck, 11 m long, a low forward cab with a big
## windscreen, a tall body with lockers, a roof turret on its boom and a bumper turret.
static func arff() -> ArrayMesh:
	if _cache.has("arff"):
		return _cache["arff"]
	var st := AirportKit._begin()
	var c := C_LIME
	AirportKit._box(st, Vector3(0.0, 0.95, 0.4), Vector3(2.9, 0.6, 10.6), AirportKit.C_DARK, AirportKit.METAL)
	# Cab at the front, its windscreen raked.
	AirportKit._box(st, Vector3(0.0, 2.15, -3.9), Vector3(2.95, 1.9, 2.6), c, AirportKit.PAINT)
	AirportKit._box(st, Vector3(0.0, 2.55, -5.18), Vector3(2.7, 1.0, 0.06), AirportKit.C_DARK, AirportKit.GLASS, Basis(Vector3.RIGHT, -0.18))
	for s: float in [-1.0, 1.0]:
		AirportKit._box(st, Vector3(s * 1.485, 2.5, -3.9), Vector3(0.02, 0.8, 1.9), AirportKit.C_DARK, AirportKit.GLASS)
	# The body: lockers either side, a white band, the tank behind.
	AirportKit._box(st, Vector3(0.0, 2.2, 1.6), Vector3(2.95, 2.4, 7.4), c, AirportKit.PAINT)
	for s: float in [-1.0, 1.0]:
		AirportKit._box(st, Vector3(s * 1.485, 2.55, 1.6), Vector3(0.02, 0.22, 7.2), AirportKit.C_WHITE, AirportKit.PAINT)
		for k in 4:
			AirportKit._box(st, Vector3(s * 1.49, 1.75, -1.2 + float(k) * 1.75), Vector3(0.02, 0.9, 1.5), AirportKit.C_GALV, AirportKit.METAL)
	# Roof turret on its boom, the bumper turret, beacons and a light bar.
	AirportKit._box(st, Vector3(0.0, 3.5, -2.2), Vector3(0.8, 0.3, 0.8), AirportKit.C_STEEL, AirportKit.METAL)
	AirportKit._cyl(st, Vector3(0.0, 3.65, -2.2), Vector3(0.0, 3.85, -4.2), 0.14, 0.09, 8, AirportKit.C_GALV, AirportKit.METAL)
	AirportKit._cyl(st, Vector3(0.0, 0.9, -5.3), Vector3(0.0, 1.05, -6.0), 0.1, 0.06, 8, AirportKit.C_GALV, AirportKit.METAL)
	AirportKit._box(st, Vector3(0.0, 3.16, -4.4), Vector3(1.8, 0.14, 0.3), AirportKit.C_RED, AirportKit.LAMP)
	for s: float in [-1.0, 1.0]:
		AirportKit._cyl(st, Vector3(s * 1.2, 3.4, 4.9), Vector3(s * 1.2, 3.6, 4.9), 0.1, 0.09, 8, AirportKit.C_RED, AirportKit.LAMP)
		AirportKit._box(st, Vector3(s * 1.05, 1.15, -5.22), Vector3(0.4, 0.16, 0.05), Color(1.0, 0.95, 0.85), AirportKit.LAMP)
	for z: float in [-3.4, 1.9, 4.0]:
		for s: float in [-1.0, 1.0]:
			AirportKit._wheel(st, Vector3(s * 1.25, 0.66, z), 0.66, 0.5)
	return _done("arff", st)


## The crash tender's apparatus shed: an open front of two bays, back and side walls, a roof on a
## row of columns, a red header with the bay numbers lit after dark. Open to -Z.
static func arff_station() -> ArrayMesh:
	if _cache.has("arff_station"):
		return _cache["arff_station"]
	var st := AirportKit._begin()
	var wall := Color(0.46, 0.45, 0.42)
	var w := 16.0
	var dep := 15.0
	var h := 6.4
	AirportKit._box(st, Vector3(0.0, h * 0.5, dep * 0.5), Vector3(w, h, 0.4), wall, AirportKit.METAL)
	for s: float in [-1.0, 1.0]:
		AirportKit._box(st, Vector3(s * w * 0.5, h * 0.5, 0.0), Vector3(0.4, h, dep), wall, AirportKit.METAL)
	AirportKit._box(st, Vector3(0.0, h + 0.2, 0.0), Vector3(w + 0.8, 0.4, dep + 0.8), AirportKit.C_GALV, AirportKit.METAL, Basis(), true)
	AirportKit._box(st, Vector3(0.0, h - 0.5, -dep * 0.5), Vector3(w + 0.4, 1.0, 0.4), AirportKit.C_RED, AirportKit.PAINT)
	AirportKit._box(st, Vector3(0.0, h * 0.5, -dep * 0.5), Vector3(0.6, h, 0.6), wall, AirportKit.METAL)
	AirportKit._box(st, Vector3(0.0, 0.03, 0.0), Vector3(w, 0.06, dep), Color(0.30, 0.30, 0.29), AirportKit.METAL)
	# Lamps under the header, lit at night (the shader lights LAMP kinds by lamp_factor).
	for x: float in [-4.0, 4.0]:
		AirportKit._box(st, Vector3(x, h - 1.05, -dep * 0.5 + 0.3), Vector3(1.4, 0.08, 0.4), Color(1.0, 0.92, 0.78), AirportKit.LAMP)
	return _done("arff_station", st)
