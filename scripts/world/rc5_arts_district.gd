class_name RcArtsDistrict
## The arts_district reference camera's pass (wave 8, refcam5; docs/HANDOFF.md "The Arts District
## at 10:00"): what gave the Arts District's brick warehouses away from the pavement, fixed in
## Industrial's own shader and builder.
##   - The brick was a flat photo: its normal map was bound to the material and never read. The
##     courses now stand in relief, with lime bloom low on the wall.
##   - The steel factory windows were painted flat on the face - a pixel grid of dark squares with
##     white "missing" panes. The sash now sits ~22 cm back in a real reveal seen along the view
##     ray (brick returns, the sill a pale ledge, the head's shadow on the glass), a heavier
##     perimeter frame, drawn panes each at its own tilt mirroring the street, a few painted out
##     grey-green, open or milky.
##   - Murals on brick were painted as if on concrete (chips showed grey cement, hard vector-black
##     outlines): the courses show through the paint, chips go back to the brick, softer ink.
##   - Downspouts on brick were bright galvanised sticks: on the old brick they are cast iron painted
##     dark (SPOUT_PAINT), the same kind as the door frames.
##   - Grade doors in brick were flush slabs: a dark steel frame (jambs and a deep header) stands
##     proud round each, so the door reads set into the wall.
##   - The cars in the warehouses' employee stalls were ArenaGrounds' 260-triangle box cars: at
##     20 m from the pavement they read as grey bricks. Within RcAutoRow.REAL_NEAR of their cell
##     they are now the real road bodies' far twins (CarParkBuild.real_body(), RcAutoRow's types),
##     the box past it and as the shadow.
## RC5_ARTS=0 in the environment is the A/B (the `rc5_arts` uniform 0, the mural flag and the
## frames left out).

static func _static_init() -> void: LoadPulse.compiled()  # a boot frame: docs/HANDOFF.md "The boot compile"

static var enabled: bool = OS.get_environment("RC5_ARTS") != "0"

## The steel frame round a grade door in a brick wall: jamb width, how far it stands proud, the
## header's height.
const JAMB := 0.22
const PROUD := 0.2
const HEADER := 0.42
const FRAME_PAINT := Color(0.14, 0.145, 0.15)


static func apply(mat: ShaderMaterial) -> void:
	mat.set_shader_parameter("rc5_arts", 1.0 if enabled else 0.0)


## COLOR.b of a mural box: 1 when it is painted over brick (the shader shows the courses through
## the paint), else the old 0.5.
static func mural_flag(brick: bool) -> float:
	return 1.0 if enabled and brick else 0.5


## The frame round a grade door at u on a brick front (Industrial's warehouse frame `cx`, the
## front's face at `front_v`, the door `size` (width, height)).
static func door_frame(cx: Dictionary, u: float, front_v: float, size: Vector2) -> void:
	if not enabled:
		return
	var v := front_v - PROUD * 0.5
	for sx: float in [-1.0, 1.0]:
		Industrial._fb(cx, u + sx * (size.x * 0.5 + JAMB * 0.5), v, (size.y + HEADER) * 0.5, Vector3(JAMB, size.y + HEADER, PROUD), IndustrialKit.K_STEEL, FRAME_PAINT)
	Industrial._fb(cx, u, v, size.y + HEADER * 0.5, Vector3(size.x, HEADER, PROUD), IndustrialKit.K_STEEL, FRAME_PAINT)


## A brick warehouse's downspouts: dark painted iron (the steel kind takes the paint), else the old
## galvanised pipe.
const SPOUT_PAINT := Color(0.17, 0.18, 0.17)


static func spout_kind(brick: bool) -> int:
	return IndustrialKit.K_STEEL if enabled and brick else IndustrialKit.K_GALV


static func spout_paint(brick: bool) -> Color:
	return SPOUT_PAINT if enabled and brick else Color(0.62, 0.63, 0.62)


## The yard cars' cells (metres): coarser than the dealers' (a yard's stalls are fewer and spread
## along a whole lot), three nodes a body kind a cell.
const CAR_CELL := 48.0


## Industrial._stalls() hands each yard car here before its batch add: true when it is taken (a
## FULL chunk), the car drawn per cell at the chunk's finish (commit()).
static func yard_car(ch: CityChunk, v: int, xf: Transform3D, paint: Color) -> bool:
	if not enabled or ch.level != CityChunk.Level.FULL or ch.capturing:
		return false
	if not CarParkBuild.real_body(Vehicle.BodyType.SEDAN).has("mesh"):
		return false
	if not ch.has_meta("rc5_arts_cars"):
		ch.set_meta("rc5_arts_cars", [])
	var lifted := xf
	lifted.origin.y += ch._gy(xf.origin.x, xf.origin.z)
	(ch.get_meta("rc5_arts_cars") as Array).append([v, lifted, paint])
	return true


## At the chunk's finish: the taken yard cars per CELL, the real body within REAL_NEAR (no shadow
## of its own), the box past it and the box as the shadow throughout.
static func commit(ch: CityChunk) -> void:
	if not ch.has_meta("rc5_arts_cars"):
		return
	var cars: Array = ch.get_meta("rc5_arts_cars")
	ch.remove_meta("rc5_arts_cars")
	var seed_v := ch.plan.seed
	var cells: Dictionary = {}
	for c: Array in cars:
		var xf: Transform3D = c[1]
		var p := xf.origin
		var ck := Vector2i(floori(p.x / CAR_CELL), floori(p.z / CAR_CELL))
		if not cells.has(ck):
			cells[ck] = {"box": AABB(p, Vector3.ZERO), "far": {}, "near": {}}
		var cell: Dictionary = cells[ck]
		cell.box = (cell.box as AABB).expand(p)
		var v: int = c[0]
		if not (cell.far as Dictionary).has(v):
			cell.far[v] = []
		cell.far[v].append([xf, c[2]])
		var t := RcAutoRow.body_type(seed_v, v, p)
		var body := CarParkBuild.real_body(t)
		if not body.has("mesh"):
			continue
		if not (cell.near as Dictionary).has(t):
			cell.near[t] = []
		cell.near[t].append([xf, c[2]])
	for ck: Vector2i in cells:
		var cell: Dictionary = cells[ck]
		var bounds: AABB = (cell.box as AABB).grow(3.0)
		bounds.size.y += 1.5
		for v: int in cell.far:
			var mmi := CarParkBuild._car_mmi(ArenaGrounds.car_mesh(v), cell.far[v], Vector3.ZERO, false)
			mmi.name = "YardBoxCars%d_%d_%d" % [v, ck.x, ck.y]
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			RcAutoRow._seat(ch, mmi, bounds, RcAutoRow.REAL_NEAR, 0.0)
			var twin := CarParkBuild._car_mmi(ArenaGrounds.car_mesh(v), cell.far[v], Vector3.ZERO, false)
			twin.name = "YardCarShadows%d_%d_%d" % [v, ck.x, ck.y]
			twin.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
			RcAutoRow._seat(ch, twin, bounds, 0.0, 0.0)
		for t: int in cell.near:
			var body := CarParkBuild.real_body(t)
			var mmi := CarParkBuild._car_mmi(body.mesh, cell.near[t], body.offset, true)
			mmi.name = "YardRealCars%d_%d_%d" % [t, ck.x, ck.y]
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			RcAutoRow._seat(ch, mmi, bounds, 0.0, RcAutoRow.REAL_NEAR)
