class_name CarInteriorKit
extends RefCounted
## The real cabin of an everyday body, built in code at real size in the body MESH's space from
## what CarCabin measured for that body (the cabin box, the belt, the two seat rows, the driver's
## side, the panes) and from the door outlines (CarDoorSplit): the dash with its binnacle, the
## instrument cluster and the centre screen, vents and the cowl under the windscreen, the steering
## column and pedals, two bolstered front seats with headrests on their stalks, the rear bench, the
## centre console with its armrest and gear selector, the carpet and the toe board, the headliner
## with the visors and the mirror, the B-pillar trims, the rear door cards and the sills; per front
## door its card (armrest, grab handle, latch, speaker, window cap) with the seal round it and the
## painted jamb on the body. The steering wheel is its own mesh (CarInterior turns it).
##
## Everything uses its laid-out numbers from the same formulas car_cabin.gdshaderinc traces with,
## so the traced driver's hands land on this wheel (wheel_frame()).
##
## ONE material (shaders/car_interior.gdshader): what a vertex is in COLOR.r (R_* / 16), UV in
## metres (UV2 0..1 across a screen or the cluster). Built once per body type (cached).

const R_SEAT := 0
const R_INSERT := 1
const R_DASH := 2
const R_PLASTIC := 3
const R_CARPET := 4
const R_HEADLINER := 5
const R_SATIN := 6
const R_GLOSS := 7
const R_SCREEN := 8
const R_CLUSTER := 9
const R_RUBBER := 10
const R_WHEEL := 11
const R_METAL := 12
const R_JAMB := 13
const R_SPEAKER := 14

## The wheel's rim radius and section (m), as the trace's (car_cabin.gdshaderinc wr, ring_hit).
const WHEEL_R := 0.185
const WHEEL_TUBE := 0.017

static var _cache: Dictionary = {}
## Builds running on a worker thread, by key: {"task": id, "geos": {...} once done}.
static var _tasks: Dictionary = {}


static func _key(type: int, data: Dictionary, doors: Array) -> Array:
	return [type, doors.size(), data.get("real", false)]


## The finished kit for body `type` (see build()), or {} while its geometry is still being worked
## out on a worker thread (started here the first time it is asked for).
static func request(type: int, data: Dictionary, doors: Array) -> Dictionary:
	var key := _key(type, data, doors)
	if _cache.has(key):
		return _cache[key]
	if not _tasks.has(key):
		var job := {"geos": {}}
		var d := data.duplicate()
		var dd := doors.duplicate()
		job.task = WorkerThreadPool.add_task(func() -> void: job.geos = _geos(d, dd), false, "CarInteriorKit")
		_tasks[key] = job
		return {}
	var job: Dictionary = _tasks[key]
	if not WorkerThreadPool.is_task_completed(job.task):
		return {}
	WorkerThreadPool.wait_for_task_completion(job.task)
	_tasks.erase(key)
	_cache[key] = _finish(job.geos)
	return _cache[key]


## {"cabin": ArrayMesh, "wheel": ArrayMesh, "wheel_xf": Transform3D, "cards": [ArrayMesh per door]}
## for body `type`, at once; `doors` CarDoorSplit's doors (or stand-ins).
static func build(type: int, data: Dictionary, doors: Array) -> Dictionary:
	var key := _key(type, data, doors)
	if _cache.has(key):
		return _cache[key]
	_cache[key] = _finish(_geos(data, doors))
	return _cache[key]


static func _finish(geos: Dictionary) -> Dictionary:
	var cards := []
	for c: Geo in geos.cards:
		cards.append(c.mesh())
	return {"cabin": (geos.cabin as Geo).mesh(), "wheel": (geos.wheel as Geo).mesh(), "wheel_xf": geos.wheel_xf,
		"cards": cards, "layout": geos.layout}


## The kit's geometry as triangle lists: no renderer calls, so a worker thread can run it.
static func _geos(data: Dictionary, doors: Array) -> Dictionary:
	var g := Geo.new()
	var L := layout(data)
	_dash(g, L)
	_seats(g, L)
	_console(g, L)
	_floor_and_roof(g, L, data)
	for d: Dictionary in doors:
		_body_side(g, L, d)
	var cards := []
	for d: Dictionary in doors:
		var c := Geo.new()
		_door_card(c, L, d)
		cards.append(c)
	var w := Geo.new()
	_wheel(w)
	return {"cabin": g, "wheel": w, "wheel_xf": wheel_frame(L), "cards": cards, "layout": L}


## The numbers the cabin is laid out by (mesh space): as car_cabin.gdshaderinc's cabin_view().
static func layout(data: Dictionary) -> Dictionary:
	var lo: Vector3 = data.cabin_lo
	var hi: Vector3 = data.cabin_hi
	var seat_z: Vector2 = data.seat_z
	var back := 1.0 if seat_z.y > seat_z.x else -1.0
	var cx := (hi.x + lo.x) * 0.5
	var half_w := (hi.x - lo.x) * 0.5
	var belt: float = data.belt_y
	var front_end := lo.z if back > 0.0 else hi.z
	var dash_rear := front_end + back * 0.42
	var ds: float = data.driver_side
	var sx := cx + ds * (half_w + 0.03) * 0.5
	var zw := lerpf(seat_z.x - back * 0.7, dash_rear + back * 0.22, 0.5)
	zw = dash_rear + back * maxf((zw - dash_rear) * back, 0.12)
	# The screens' tops (the headliner runs between them).
	var screen_top := front_end + back * 0.55
	var rear_top := (hi.z if back > 0.0 else lo.z) - back * 0.3
	# The windscreen's foot: the dash stops short of it and falls to it.
	var cowl_z := front_end - back * 0.1
	var cowl_y := belt - 0.02
	var screen_top_y: float = hi.y
	for p: Array in data.get("panes", []):
		var n: Vector3 = p[2]
		if int(p[3]) == CarCabin.KIND_LAMP or absf(n.z) < 0.45 or absf(n.y) < 0.2:
			continue
		var a: Vector3 = p[0]
		var b: Vector3 = p[1]
		if n.z * back < 0.0:
			screen_top = b.z if back > 0.0 else a.z
			cowl_z = a.z if back > 0.0 else b.z
			cowl_y = a.y
			screen_top_y = b.y
		else:
			rear_top = a.z if back > 0.0 else b.z
	return {
		"lo": lo, "hi": hi, "seat_z": seat_z, "back": back, "cx": cx, "half_w": half_w, "belt": belt,
		"floor": lo.y, "front_end": front_end, "dash_rear": dash_rear, "ds": ds, "sx": sx,
		"wc": Vector3(sx, belt - 0.05, zw), "roof": maxf(hi.y, float(data.get("side_top", hi.y))),
		"screen_top": screen_top, "rear_top": rear_top, "cowl_z": cowl_z, "cowl_y": cowl_y, "screen_top_y": screen_top_y,
		"side_top": float(data.get("side_top", hi.y)), "rear_seats": bool(data.get("rear_seats", true)),
	}


## The wheel's frame: origin the rim's centre, z its axis toward the driver, x across the car.
static func wheel_frame(L: Dictionary) -> Transform3D:
	var back: float = L.back
	var wn := Vector3(0.0, 0.42, back * 0.91).normalized()
	var wu := Vector3.RIGHT
	var wv := wn.cross(wu).normalized()
	wv *= signf(wv.y)
	wu = wv.cross(wn).normalized()
	return Transform3D(Basis(wu, wv, wn), L.wc)


# --- the pieces -------------------------------------------------------------------------------------

static func _dash(g: Geo, L: Dictionary) -> void:
	var back: float = L.back
	var lo: Vector3 = L.lo
	var hi: Vector3 = L.hi
	var belt: float = L.belt
	var cx: float = L.cx
	var w: float = (hi.x - lo.x) * 0.5 + 0.02
	var fe: float = L.front_end
	var dr: float = L.dash_rear
	# The main body of the dash, from just behind the windscreen's foot to its face.
	var cz: float = L.cowl_z + back * 0.07
	if (dr - cz) * back < 0.2:
		cz = dr - back * 0.2
	var cy: float = minf(float(L.cowl_y) - 0.03, belt + 0.02)
	var zc := (cz + dr) * 0.5
	var dz := absf(dr - cz) * 0.5
	g.rbox(_at(cx, (belt - 0.31 + cy - 0.02) * 0.5, zc), Vector3(w, (cy - 0.02 - (belt - 0.31)) * 0.5, dz), 0.05, 3, R_DASH)
	# The top: a padded slab from over the face down to the windscreen's foot.
	var top_a := Vector3(cx, belt + 0.04, dr - back * 0.05)
	var top_c := Vector3(cx, cy, cz)
	var run := top_c - top_a
	var tilt := Basis(Vector3.RIGHT, atan2(run.y, absf(run.z)) * back)
	g.rbox(Transform3D(tilt, (top_a + top_c) * 0.5), Vector3(w - 0.01, 0.03, run.length() * 0.5 + 0.03), 0.025, 3, R_DASH)
	# The lower face (the knee bolsters), set back from the upper.
	g.rbox(_at(cx, belt - 0.33, dr - back * 0.08), Vector3(w - 0.04, 0.09, 0.08), 0.04, 2, R_PLASTIC)
	# The binnacle over the cluster and the cluster face inside it.
	var sx: float = L.sx
	g.rbox(_at(sx, belt + 0.07, dr - back * 0.04), Vector3(0.19, 0.045, 0.09), 0.04, 3, R_DASH)
	g.panel(Vector3(sx, belt - 0.01, dr - back * 0.085), Vector3(0.155, 0.0, 0.0), Vector3(0.0, 0.055, -back * 0.012), Vector3(0, 0, back), R_CLUSTER)
	# The centre screen, standing proud of the dash on a thin bezel.
	g.rbox(_at(cx, belt - 0.09, dr + back * 0.005), Vector3(0.135, 0.085, 0.012), 0.008, 2, R_GLOSS)
	g.panel(Vector3(cx, belt - 0.09, dr + back * 0.0185), Vector3(0.122, 0.0, 0.0), Vector3(0.0, 0.074, 0.0), Vector3(0, 0, back), R_SCREEN)
	# The centre stack under it: controls on a satin strip.
	g.rbox(_at(cx, belt - 0.22, dr - back * 0.01), Vector3(0.12, 0.035, 0.02), 0.01, 2, R_GLOSS)
	for k in 3:
		g.cyl(Vector3(cx + (k - 1) * 0.07, belt - 0.22, dr + back * 0.008), Vector3(0, 0, back), 0.016, 0.014, 12, R_SATIN)
	# Vents: two at the outer ends of the face, two either side of the screen.
	for x: float in [lo.x + 0.13, hi.x - 0.13, cx - 0.17, cx + 0.17]:
		g.rbox(_at(x, belt - 0.02, dr + back * 0.004), Vector3(0.05, 0.028, 0.012), 0.008, 2, R_GLOSS)
		for k in 3:
			g.rbox(_at(x, belt - 0.035 + k * 0.015, dr + back * 0.012), Vector3(0.042, 0.002, 0.004), 0.001, 1, R_SATIN)
	# A satin strip across the face.
	g.rbox(_at(cx, belt - 0.06, dr + back * 0.002), Vector3(w - 0.05, 0.006, 0.006), 0.004, 1, R_SATIN)
	# The steering column's shroud and the stalks.
	var wf := wheel_frame(L)
	var wn := wf.basis.z
	g.cyl(wf.origin - wn * 0.05, -wn, 0.045, 0.30, 14, R_PLASTIC)
	for s: float in [-1.0, 1.0]:
		var a := wf.origin - wn * 0.09 + wf.basis.x * (0.05 * s)
		g.cyl(a, wf.basis.x * s + wf.basis.y * 0.15, 0.007, 0.12, 8, R_PLASTIC)
	# The pedals under the driver's side of the dash.
	var fy: float = L.floor
	for k in 2:
		var px: float = sx + (-0.07 if k == 0 else 0.09) * (1.0 if L.ds < 0.0 else -1.0)
		var pz: float = dr + back * 0.12
		g.rbox(Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-62.0) * back), Vector3(px, fy + 0.11, pz)), Vector3(0.04 if k == 0 else 0.025, 0.05, 0.007), 0.005, 1, R_RUBBER)


static func _seats(g: Geo, L: Dictionary) -> void:
	var back: float = L.back
	var belt: float = L.belt
	var fy: float = L.floor
	var cx: float = L.cx
	var hw: float = L.half_w
	var sz: Vector2 = L.seat_z
	for s: float in [-1.0, 1.0]:
		var xa: float = cx + s * 0.1
		var xb: float = cx + s * (hw - 0.07)
		var mid := (xa + xb) * 0.5
		var w := minf(absf(xb - xa), 0.56) * 0.5
		_seat(g, mid, w, sz.x, back, belt, fy)
	if L.rear_seats:
		var lo: Vector3 = L.lo
		var hi: Vector3 = L.hi
		var bw := (hi.x - lo.x) * 0.5 - 0.06
		var top := belt - 0.44
		var z := sz.y
		# Cushion, with three puffy places.
		g.rbox(_at(cx, top - 0.06, z - back * 0.25), Vector3(bw, 0.07, 0.25), 0.06, 3, R_SEAT, 0.02)
		g.rbox(_at(cx, (fy + top - 0.1) * 0.5, z - back * 0.2), Vector3(bw - 0.02, (top - 0.1 - fy) * 0.5, 0.2), 0.03, 1, R_PLASTIC)
		var bb := Basis(Vector3.RIGHT, deg_to_rad(-16.0) * back)
		g.rbox(Transform3D(bb, Vector3(cx, (top + belt + 0.08) * 0.5, z + back * 0.06)), Vector3(bw, (belt + 0.08 - top) * 0.5, 0.08), 0.06, 3, R_SEAT, 0.015)
		for k: float in [-1.0, 0.0, 1.0]:
			var hx: float = cx + k * bw * 0.66
			g.rbox(_at(hx, belt + 0.17, z + back * 0.15), Vector3(0.12, 0.08, 0.05), 0.04, 2, R_SEAT)
			for q: float in [-1.0, 1.0]:
				g.cyl(Vector3(hx + q * 0.06, belt + 0.06, z + back * 0.14), Vector3.UP, 0.007, 0.06, 6, R_METAL)
	else:
		# No back seats: a trimmed bulkhead behind the front ones.
		var lo2: Vector3 = L.lo
		var hi2: Vector3 = L.hi
		g.rbox(_at(cx, (fy + belt) * 0.5 + 0.1, sz.x + back * 0.32), Vector3((hi2.x - lo2.x) * 0.5, (belt - fy) * 0.5 + 0.12, 0.03), 0.02, 1, R_PLASTIC)


static func _seat(g: Geo, x: float, w: float, z: float, back: float, belt: float, fy: float) -> void:
	var top := belt - 0.42
	# The base and its rails, the cushion with side bolsters and an insert down its middle.
	g.rbox(_at(x, (fy + top - 0.1) * 0.5, z - back * 0.24), Vector3(w * 0.7, maxf((top - 0.1 - fy) * 0.5, 0.02), 0.2), 0.02, 1, R_PLASTIC)
	for q: float in [-1.0, 1.0]:
		g.rbox(_at(x + q * w * 0.62, fy + 0.02, z - back * 0.24), Vector3(0.015, 0.015, 0.3), 0.006, 1, R_METAL)
	var cb := Basis(Vector3.RIGHT, deg_to_rad(5.0) * back)
	g.rbox(Transform3D(cb, Vector3(x, top - 0.065, z - back * 0.25)), Vector3(w, 0.06, 0.25), 0.05, 3, R_SEAT)
	g.rbox(Transform3D(cb, Vector3(x, top - 0.005, z - back * 0.26)), Vector3(w * 0.58, 0.012, 0.21), 0.02, 3, R_INSERT, 0.012)
	for q: float in [-1.0, 1.0]:
		g.rbox(Transform3D(cb, Vector3(x + q * w * 0.82, top + 0.005, z - back * 0.25)), Vector3(w * 0.18, 0.035, 0.23), 0.03, 2, R_SEAT)
	# The backrest, raked, its bolsters wrapping forward, the insert in the middle.
	var bb := Basis(Vector3.RIGHT, deg_to_rad(-17.0) * back)
	var h := (belt + 0.13 - top) * 0.5
	var c := Vector3(x, top + h, z + back * 0.07)
	g.rbox(Transform3D(bb, c), Vector3(w, h, 0.065), 0.05, 3, R_SEAT)
	g.rbox(Transform3D(bb, c + bb * Vector3(0.0, -0.02, -back * 0.06)), Vector3(w * 0.58, h * 0.82, 0.012), 0.02, 3, R_INSERT, 0.01)
	for q: float in [-1.0, 1.0]:
		g.rbox(Transform3D(bb, c + bb * Vector3(q * w * 0.84, -h * 0.15, -back * 0.04)), Vector3(w * 0.17, h * 0.72, 0.05), 0.035, 2, R_SEAT)
	# The headrest on two stalks.
	var top_c := c + bb * Vector3(0.0, h, 0.0)
	var hr := top_c + Vector3(0.0, 0.12, back * 0.02)
	g.rbox(Transform3D(bb, hr), Vector3(0.13, 0.08, 0.05), 0.04, 3, R_SEAT)
	for q: float in [-1.0, 1.0]:
		g.cyl(top_c + Vector3(q * 0.06, -0.01, 0.0), Vector3.UP, 0.0065, 0.06, 6, R_METAL)


static func _console(g: Geo, L: Dictionary) -> void:
	var back: float = L.back
	var belt: float = L.belt
	var fy: float = L.floor
	var cx: float = L.cx
	var dr: float = L.dash_rear
	var sz: Vector2 = L.seat_z
	var z0 := dr - back * 0.05
	var z1 := sz.x + back * 0.03
	var zc := (z0 + z1) * 0.5
	var hz := absf(z1 - z0) * 0.5
	g.rbox(_at(cx, (fy + belt - 0.36) * 0.5, zc), Vector3(0.1, (belt - 0.36 - fy) * 0.5, hz), 0.03, 2, R_PLASTIC)
	# A gloss tray at the front with the selector, and the armrest at the back.
	g.rbox(_at(cx, belt - 0.355, zc - back * hz * 0.35), Vector3(0.085, 0.006, hz * 0.45), 0.004, 1, R_GLOSS)
	var zg := sz.x - back * 0.42
	g.cyl(Vector3(cx, belt - 0.36, zg), Vector3(0.0, 1.0, -back * 0.12), 0.012, 0.1, 8, R_SATIN)
	g.rbox(_at(cx, belt - 0.245, zg - back * 0.012), Vector3(0.026, 0.03, 0.04), 0.022, 2, R_SEAT)
	g.rbox(_at(cx, belt - 0.3, sz.x - back * 0.17), Vector3(0.095, 0.035, 0.17), 0.03, 2, R_SEAT)


static func _floor_and_roof(g: Geo, L: Dictionary, data: Dictionary) -> void:
	var back: float = L.back
	var lo: Vector3 = L.lo
	var hi: Vector3 = L.hi
	var fy: float = L.floor
	var belt: float = L.belt
	var cx: float = L.cx
	var fe: float = L.front_end
	var rear := (hi.z if back > 0.0 else lo.z) + back * 0.25
	var foot := fe + back * 0.15
	var x0 := lo.x - 0.05
	var x1 := hi.x + 0.05
	# The carpet, and the toe board up to the dash's foot.
	g.quad(Vector3(x0, fy, foot), Vector3(x1, fy, foot), Vector3(x1, fy, rear), Vector3(x0, fy, rear), Vector3.UP, R_CARPET)
	g.quad(Vector3(x0, belt - 0.32, fe - back * 0.05), Vector3(x1, belt - 0.32, fe - back * 0.05), Vector3(x1, fy, foot), Vector3(x0, fy, foot), Vector3(0, 0.6, back * 0.8).normalized(), R_CARPET)
	# The tunnel's hump under the console.
	g.rbox(_at(cx, fy + 0.06, (foot + float(L.seat_z.x)) * 0.5), Vector3(0.14, 0.07, absf(float(L.seat_z.x) - foot) * 0.5), 0.05, 2, R_CARPET)
	# The headliner between the screens' tops, just over the side glass, and the visors.
	var roof: float = minf(float(L.side_top), float(L.screen_top_y)) - 0.004
	x0 = cx - (hi.x - lo.x) * 0.5 * 0.92
	x1 = cx + (hi.x - lo.x) * 0.5 * 0.92
	var st: float = L.screen_top
	var rt: float = L.rear_top
	g.quad(Vector3(x0 + 0.03, roof, st), Vector3(x1 - 0.03, roof, st), Vector3(x1 - 0.03, roof, rt), Vector3(x0 + 0.03, roof, rt), Vector3.DOWN, R_HEADLINER)
	for s: float in [-1.0, 1.0]:
		g.rbox(_at(cx + s * (hi.x - lo.x) * 0.26, roof - 0.03, st + back * 0.17), Vector3(0.16, 0.01, 0.08), 0.008, 2, R_HEADLINER)
	var my := minf(roof, float(L.screen_top_y)) - 0.1
	g.rbox(_at(cx, my, st + back * 0.14), Vector3(0.12, 0.03, 0.01), 0.01, 2, R_GLOSS)
	g.cyl(Vector3(cx, my + 0.02, st + back * 0.14), Vector3(0, 1, -back * 0.6), 0.008, 0.07, 6, R_PLASTIC)
	# A rear wall behind the bench (the boot's bulkhead), up to the rear glass.
	if L.rear_seats:
		var z: float = float(L.seat_z.y) + back * 0.2
		g.quad(Vector3(x0, fy, z), Vector3(x1, fy, z), Vector3(x1, belt + 0.02, z), Vector3(x0, belt + 0.02, z), Vector3(0, 0, -back), R_PLASTIC)
		g.quad(Vector3(x0, belt + 0.02, z), Vector3(x1, belt + 0.02, z), Vector3(x1, belt + 0.02, rear), Vector3(x0, belt + 0.02, rear), Vector3.UP, R_CARPET)


## The body's side behind a front door: the B-pillar trim, the rear door card or quarter trim, the
## sill under the door, and the painted jamb round the opening.
static func _body_side(g: Geo, L: Dictionary, d: Dictionary) -> void:
	var s: float = d.side
	var back: float = L.back
	var x: float = s * (float(d.skin_x) - 0.075)
	var zb := -float(d.rear)
	var hi: Vector3 = L.hi
	var lo: Vector3 = L.lo
	var rear_end := (hi.z if back > 0.0 else lo.z)
	var fy: float = L.floor
	var belt: float = d.belt
	# B-pillar trim up the glass, leaning in with the glasshouse.
	var gh := float(d.top) - belt
	var lean := Basis(Vector3(0, 0, 1), deg_to_rad(11.0) * s)
	g.rbox(Transform3D(lean, Vector3(x - s * (0.015 + gh * 0.1), belt + gh * 0.45, zb + back * 0.04)), Vector3(0.02, gh * 0.47, 0.045), 0.015, 2, R_PLASTIC)
	# The quarter: a card from the floor to the belt, with an armrest and a cap.
	var z0 := zb + back * 0.02
	var mid := (z0 + rear_end) * 0.5
	var hz := absf(rear_end - z0) * 0.5
	g.quad(Vector3(x, fy, z0), Vector3(x, fy, rear_end), Vector3(x, belt, rear_end), Vector3(x, belt, z0), Vector3(-s, 0, 0), R_PLASTIC)
	g.rbox(_at(x - s * 0.02, belt - 0.2, mid), Vector3(0.03, 0.025, hz * 0.6), 0.02, 2, R_SEAT)
	g.rbox(_at(x - s * 0.005, belt - 0.01, mid), Vector3(0.025, 0.015, hz), 0.012, 1, R_DASH)
	# The sill under the door opening.
	var sill: float = d.sill
	var zf := -float(d.front)
	g.rbox(_at(x + s * 0.02, (fy + sill) * 0.5 + 0.03, (zf + zb) * 0.5), Vector3(0.06, (sill - fy) * 0.5 + 0.04, absf(zb - zf) * 0.5), 0.02, 1, R_PLASTIC)
	g.rbox(_at(x + s * 0.03, sill + 0.065, (zf + zb) * 0.5), Vector3(0.05, 0.004, absf(zb - zf) * 0.5 - 0.02), 0.003, 1, R_SATIN)
	# The jamb: a painted band from the skin in to the trim, round the door's lower outline.
	var outline: PackedVector2Array = _clip_below(d.lower, belt)
	var grown := Geometry2D.offset_polygon(outline, 0.006)
	if not grown.is_empty():
		g.band(grown[0], s * (float(d.skin_x) - 0.004), x, s, true, R_JAMB, belt - 0.01)


static func _door_card(g: Geo, L: Dictionary, d: Dictionary) -> void:
	var s: float = d.side
	var back: float = L.back
	var x: float = s * (float(d.skin_x) - 0.075)
	var belt: float = d.belt
	var sill: float = d.sill
	var zf := -float(d.front)
	var zb := -float(d.rear)
	var outline := _clip_below(d.lower, belt)
	var shrunk := Geometry2D.offset_polygon(outline, -0.012)
	var card: PackedVector2Array = shrunk[0] if not shrunk.is_empty() else outline
	# The card itself, flat across the door's outline.
	g.poly_x(card, x, -s, R_PLASTIC)
	# The seal round it, back to the skin.
	g.band(card, x, s * (float(d.skin_x) - 0.012), s, false, R_RUBBER, belt - 0.02)
	var mid := (zf + zb) * 0.5
	var hz := absf(zb - zf) * 0.5
	# The upper panel in the seat's trim, the armrest with the pull, the latch, the speaker.
	g.rbox(_at(x - s * 0.012, belt - 0.12, mid + back * 0.03), Vector3(0.012, 0.08, hz * 0.85), 0.012, 2, R_SEAT)
	g.rbox(_at(x - s * 0.035, belt - 0.22, mid + back * 0.06), Vector3(0.035, 0.02, hz * 0.55), 0.018, 2, R_SEAT)
	g.rbox(_at(x - s * 0.02, belt - 0.2, mid - back * 0.12), Vector3(0.025, 0.045, 0.06), 0.012, 2, R_PLASTIC)
	g.rbox(_at(x - s * 0.015, belt - 0.07, zf + back * 0.16), Vector3(0.015, 0.02, 0.07), 0.01, 2, R_SATIN)
	g.disc_x(Vector3(x - s * 0.006, sill + 0.16, zf + back * 0.2), 0.075, -s, 20, R_SPEAKER)
	# The pocket along the bottom.
	g.rbox(_at(x - s * 0.04, sill + 0.09, mid + back * 0.05), Vector3(0.03, 0.04, hz * 0.6), 0.015, 2, R_PLASTIC)
	# The window cap along the top.
	g.rbox(_at(x + s * 0.01, belt - 0.005, mid), Vector3(0.035, 0.012, hz), 0.01, 1, R_DASH)


static func _wheel(g: Geo) -> void:
	# Built round its own frame: the rim in the xy plane, its axis +z toward the driver.
	g.torus(Transform3D.IDENTITY, WHEEL_R, WHEEL_TUBE, 40, 10, R_WHEEL)
	# The hub with its pad, and three spokes (across and down).
	g.rbox(Transform3D(Basis.IDENTITY, Vector3(0.0, -0.01, -0.025)), Vector3(0.075, 0.06, 0.03), 0.028, 3, R_PLASTIC)
	g.rbox(Transform3D(Basis.IDENTITY, Vector3(0.0, -0.005, 0.005)), Vector3(0.06, 0.045, 0.006), 0.012, 2, R_GLOSS)
	for a: float in [0.0, PI, -PI * 0.5]:
		var dir := Vector3(cos(a), sin(a), 0.0)
		var c := dir * (WHEEL_R * 0.62)
		var b := Basis(dir, Vector3(0, 0, 1).cross(dir), Vector3(0, 0, 1))
		g.rbox(Transform3D(b, c + Vector3(0, 0, -0.02)), Vector3(WHEEL_R * 0.34, 0.022, 0.012), 0.01, 2, R_SATIN if a != -PI * 0.5 else R_PLASTIC)


# --- helpers ----------------------------------------------------------------------------------------

static func _at(x: float, y: float, z: float) -> Transform3D:
	return Transform3D(Basis.IDENTITY, Vector3(x, y, z))


## `outline` (along, height) cut off above `h`, as a polygon.
static func _clip_below(outline: PackedVector2Array, h: float) -> PackedVector2Array:
	var big := PackedVector2Array([Vector2(-50, -1), Vector2(50, -1), Vector2(50, h), Vector2(-50, h)])
	var parts := Geometry2D.intersect_polygons(outline, big)
	if parts.is_empty():
		return outline
	var best: PackedVector2Array = parts[0]
	for p: PackedVector2Array in parts:
		if p.size() > best.size():
			best = p
	return best


## A triangle list in one material, with what each vertex is in COLOR.r.
class Geo:
	extends RefCounted
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var col := PackedColorArray()

	func mesh() -> ArrayMesh:
		var m := ArrayMesh.new()
		if v.is_empty():
			return m
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = v
		arr[Mesh.ARRAY_NORMAL] = n
		arr[Mesh.ARRAY_TEX_UV] = uv
		arr[Mesh.ARRAY_TEX_UV2] = uv2
		arr[Mesh.ARRAY_COLOR] = col
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		return m

	func _role(r: int) -> Color:
		return Color((float(r) + 0.5) / 16.0, 0.0, 0.0, 1.0)

	## One triangle, turned so its front (clockwise, Godot's) faces the normals given.
	func tri(a: Vector3, b: Vector3, c: Vector3, na: Vector3, nb: Vector3, nc: Vector3, ua: Vector2, ub: Vector2, uc: Vector2, role: int, u2: Array = []) -> void:
		var face := (b - a).cross(c - a)
		var swap := face.dot(na + nb + nc) > 0.0
		var cr := _role(role)
		var pts := [a, c, b] if swap else [a, b, c]
		var ns := [na, nc, nb] if swap else [na, nb, nc]
		var us := [ua, uc, ub] if swap else [ua, ub, uc]
		var u2s: Array = u2 if not u2.is_empty() else [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]
		if swap and not u2.is_empty():
			u2s = [u2[0], u2[2], u2[1]]
		for i in 3:
			v.append(pts[i])
			n.append(ns[i])
			uv.append(us[i])
			uv2.append(u2s[i])
			col.append(cr)

	func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, nrm: Vector3, role: int) -> void:
		var e1 := (b - a)
		var e2 := (d - a)
		var ua := Vector2(0, 0)
		var ub := Vector2(e1.length(), 0)
		var ud := Vector2(0, e2.length())
		var uc := Vector2(e1.length(), e2.length())
		tri(a, b, c, nrm, nrm, nrm, ua, ub, uc, role)
		tri(a, c, d, nrm, nrm, nrm, ua, uc, ud, role)

	## A flat rectangle centred at `c`, half extents along `ax` and `ay`, facing `nrm`, with UV2
	## running 0..1 across it (the cluster and the screen draw on that).
	func panel(c: Vector3, ax: Vector3, ay: Vector3, nrm: Vector3, role: int) -> void:
		var a := c - ax - ay
		var b := c + ax - ay
		var cc := c + ax + ay
		var d := c - ax + ay
		var w := ax.length() * 2.0
		var h := ay.length() * 2.0
		tri(a, b, cc, nrm, nrm, nrm, Vector2(0, 0), Vector2(w, 0), Vector2(w, h), role, [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0)])
		tri(a, cc, d, nrm, nrm, nrm, Vector2(0, 0), Vector2(w, h), Vector2(0, h), role, [Vector2(0, 1), Vector2(1, 0), Vector2(0, 0)])

	## A box with rounded edges and corners (radius `r`, `seg` steps a face side), placed by `xf`;
	## `puff` bulges its +y face in the middle (a cushion).
	func rbox(xf: Transform3D, half: Vector3, r: float, seg: int, role: int, puff: float = 0.0) -> void:
		r = minf(r, minf(half.x, minf(half.y, half.z)) * 0.98)
		var inner := (half - Vector3.ONE * r).max(Vector3.ZERO)
		var steps := maxi(seg, 1) + 2
		for f in 6:
			var axis := f / 2
			var sgn := 1.0 if f % 2 == 0 else -1.0
			var grid := []
			for i in steps + 1:
				var row := []
				for j in steps + 1:
					var a := -1.0 + 2.0 * float(i) / steps
					var b := -1.0 + 2.0 * float(j) / steps
					var p := Vector3.ZERO
					p[axis] = sgn
					p[(axis + 1) % 3] = a
					p[(axis + 2) % 3] = b
					var q := p * half
					var c := q.clamp(-inner, inner)
					var dd := q - c
					var nr := dd.normalized() if dd.length() > 1e-6 else p
					var pos := c + nr * r
					if puff != 0.0 and axis == 1 and sgn > 0.0:
						pos.y += puff * (1.0 - a * a) * (1.0 - b * b)
					var uvp := Vector2(pos[(axis + 1) % 3], pos[(axis + 2) % 3])
					row.append([xf * pos, (xf.basis * nr).normalized(), uvp])
				grid.append(row)
			for i in steps:
				for j in steps:
					var p00: Array = grid[i][j]
					var p10: Array = grid[i + 1][j]
					var p11: Array = grid[i + 1][j + 1]
					var p01: Array = grid[i][j + 1]
					tri(p00[0], p10[0], p11[0], p00[1], p10[1], p11[1], p00[2], p10[2], p11[2], role)
					tri(p00[0], p11[0], p01[0], p00[1], p11[1], p01[1], p00[2], p11[2], p01[2], role)

	## A capped cylinder from `a` along `dir` for `length`.
	func cyl(a: Vector3, dir: Vector3, rad: float, length: float, seg: int, role: int) -> void:
		var ax := dir.normalized()
		var u := ax.cross(Vector3.UP if absf(ax.y) < 0.9 else Vector3.RIGHT).normalized()
		var w := ax.cross(u).normalized()
		var b := a + ax * length
		for k in seg:
			var t0 := TAU * float(k) / seg
			var t1 := TAU * float(k + 1) / seg
			var n0 := u * cos(t0) + w * sin(t0)
			var n1 := u * cos(t1) + w * sin(t1)
			var ua := Vector2(t0 * rad, 0)
			var ub := Vector2(t1 * rad, 0)
			var uc := Vector2(t1 * rad, length)
			var ud := Vector2(t0 * rad, length)
			tri(a + n0 * rad, a + n1 * rad, b + n1 * rad, n0, n1, n1, ua, ub, uc, role)
			tri(a + n0 * rad, b + n1 * rad, b + n0 * rad, n0, n1, n0, ua, uc, ud, role)
			tri(b, b + n0 * rad, b + n1 * rad, ax, ax, ax, Vector2.ZERO, ua, ub, role)
			tri(a, a + n1 * rad, a + n0 * rad, -ax, -ax, -ax, Vector2.ZERO, ub, ua, role)

	func torus(xf: Transform3D, R: float, r: float, su: int, sv: int, role: int) -> void:
		for i in su:
			for j in sv:
				var pts := []
				for q in [[i, j], [i + 1, j], [i + 1, j + 1], [i, j + 1]]:
					var a := TAU * float(q[0]) / su
					var b := TAU * float(q[1]) / sv
					var ring := Vector3(cos(a), sin(a), 0.0)
					var nr := (ring * cos(b) + Vector3(0, 0, 1) * sin(b)).normalized()
					var p := ring * R + nr * r
					pts.append([xf * p, (xf.basis * nr).normalized(), Vector2(a * R, b * r)])
				tri(pts[0][0], pts[1][0], pts[2][0], pts[0][1], pts[1][1], pts[2][1], pts[0][2], pts[1][2], pts[2][2], role)
				tri(pts[0][0], pts[2][0], pts[3][0], pts[0][1], pts[2][1], pts[3][1], pts[0][2], pts[2][2], pts[3][2], role)

	## A flat polygon (along, height) at x, facing `nx` (+1 / -1 along x).
	func poly_x(outline: PackedVector2Array, x: float, nx: float, role: int) -> void:
		var idx := Geometry2D.triangulate_polygon(outline)
		var nrm := Vector3(nx, 0, 0)
		for t in idx.size() / 3:
			var p: Array = []
			for k in 3:
				var q := outline[idx[t * 3 + k]]
				p.append(Vector3(x, q.y, -q.x))
			tri(p[0], p[1], p[2], nrm, nrm, nrm, Vector2(-p[0].z, p[0].y), Vector2(-p[1].z, p[1].y), Vector2(-p[2].z, p[2].y), role)

	## A band round `outline` (along, height) from x0 to x1: facing in toward the outline's middle
	## when `inward`, out of it otherwise.
	func band(outline: PackedVector2Array, x0: float, x1: float, _side: float, inward: bool, role: int, skip_top: float = -INF) -> void:
		var m := Vector2.ZERO
		for q in outline:
			m += q
		m /= maxf(outline.size(), 1)
		for i in outline.size():
			var a := outline[i]
			var b := outline[(i + 1) % outline.size()]
			var e := (b - a)
			if e.length() < 1e-4 or (skip_top > -INF and a.y > skip_top and b.y > skip_top):
				continue
			var nn := Vector2(-e.y, e.x).normalized()
			if (nn.dot(m - (a + b) * 0.5) > 0.0) != inward:
				nn = -nn
			var nrm := Vector3(0.0, nn.y, -nn.x)
			var p0 := Vector3(x0, a.y, -a.x)
			var p1 := Vector3(x0, b.y, -b.x)
			var p2 := Vector3(x1, b.y, -b.x)
			var p3 := Vector3(x1, a.y, -a.x)
			var l := e.length()
			tri(p0, p1, p2, nrm, nrm, nrm, Vector2(0, 0), Vector2(l, 0), Vector2(l, 0.07), role)
			tri(p0, p2, p3, nrm, nrm, nrm, Vector2(0, 0), Vector2(l, 0.07), Vector2(0, 0.07), role)

	## A disc in the yz plane at `c`, facing `nx` along x (a speaker grille), UV2 0..1 across it.
	func disc_x(c: Vector3, rad: float, nx: float, seg: int, role: int) -> void:
		var nrm := Vector3(nx, 0, 0)
		for k in seg:
			var t0 := TAU * float(k) / seg
			var t1 := TAU * float(k + 1) / seg
			var a := c + Vector3(0, sin(t0), cos(t0)) * rad
			var b := c + Vector3(0, sin(t1), cos(t1)) * rad
			tri(c, a, b, nrm, nrm, nrm, Vector2.ZERO, Vector2(cos(t0), sin(t0)) * rad, Vector2(cos(t1), sin(t1)) * rad, role,
					[Vector2(0.5, 0.5), Vector2(0.5 + 0.5 * cos(t0), 0.5 + 0.5 * sin(t0)), Vector2(0.5 + 0.5 * cos(t1), 0.5 + 0.5 * sin(t1))])
