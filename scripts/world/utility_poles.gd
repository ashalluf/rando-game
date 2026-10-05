class_name UtilityPoles
extends RefCounted
## The overhead utilities of a Los Angeles street, as real geometry (2026-10-05, fleet task
## "utility-poles"; docs/HANDOFF.md, the utility poles section).
##
## What: tapered wooden poles (a pole tag, the ground-wire moulding, the brand), a fir crossarm
## on the pole's face with steel braces and three porcelain pin insulators carrying the primaries,
## a spool rack under it for the secondary, two lashed communication bundles lower down on the
## street face with splice cases and storage coils, pole-top transformer cans (bushings, a fuse
## cutout, an arrester and their jumpers) on some, cobra-head street lights on upswept arms on
## some, risers on a few, guy wires with a yellow guard and an anchor rod where a run really
## ends; service drops - twisted triplex on a sagging catenary - to the buildings behind the
## line and to EVERY house in the suburbs and the beach town (a meter on the front wall and a
## mast through the eave with a weatherhead), from the nearest pole in front of it, across the
## street if that is where the line is.
##
## Where: StreetDetail still decides which streets hang a line, which side, the world-space pole
## grid and the junction spans (its pure functions are unchanged); StreetDetail._pole_run() hands
## each run here (street_run()). The span polyline is StreetDetail's: the MIDDLE primary hangs from
## the pin line point at POWER_ARM_HEIGHT + 0.2 over the pavement with POWER_SAG, in
## StreetDetail.CABLE_SEGMENTS pieces - exactly what Birds._wire_spans() / wire_point() land the
## crows on. So the crossarm is bolted to the pole's face and the pole stands POLE_FACE behind the
## old pole point, along the run: its middle pin is where the old pole's axis was.
##
## How it is drawn: the hardware is code-built meshes on ONE shader (shaders/utility_pole.gdshader,
## the surface kind in COLOR.a, paint in COLOR.rgb, UV in metres), batched per chunk through the
## chunk's MultiMeshBatch ("upole" is still the shaft, so StreetWear's flyers and ClimbingPlants'
## trumpet vines find it; "up_head", "up_xfmr", "up_light", ...), each with a light shadow twin
## (PropFactory's shadow proxies). The wires are not instances: every wire of the chunk is ONE
## ribbon mesh (`UtilityWires`) on shaders/utility_wire.gdshader, each vertex on the wire's centre
## line, widened in the vertex shader to face the camera, never thinner than wire_min_px (then
## its coverage goes into alpha), round-shaded across, faded out by wire_fade_end. Committed at the
## chunk's finish (commit(), one hook in CityChunk._finish_build) together with the house drops
## (the houses are noted by one hook in CityChunk._build_house).
##
## Seeding: the old run's hashes (transformer, drop) are kept; everything new is a hash of seed +
## road + pole slot, or seed + house lot. No rng is drawn.
##
## UTILITY_POLES=0 in the environment is the A/B: the old primitive poles and box cables.

# --- Tunables ----------------------------------------------------------------------------------

## Off: the old primitives (the A/B). UTILITY_POLES=0 in the environment.
static var enabled: bool = OS.get_environment("UTILITY_POLES") != "0"

## How far the crossarm's centre stands proud of the pole's axis (the pole's radius at the arm
## plus half the arm). The pole stands this far behind the pin line along the run.
const POLE_FACE := 0.18
## Crossarm: length (an 8 ft arm), section (thick along the run, deep), and the pins' spacing.
const ARM_LENGTH := 2.44
const ARM_THICK := 0.09
const ARM_DEPTH := 0.115
const PIN_SPREAD := 0.72
## Height over the pavement of the secondary's spool and of the two comm bundles' clamps.
const SECONDARY_HEIGHT := 7.25
const COMM_HEIGHTS := [6.35, 5.88]
## How far out on the street face the comm bundles hang.
const COMM_OUT := 0.2
## Mid-span sag (for a POLE_SPACING span; longer spans sag with the square of their length).
const SECONDARY_SAG := 1.35
const COMM_SAGS := [1.7, 1.85]
## Wire radii, metres (bare ACSR primary, triplex secondary, lashed comm bundles, the drop, guy).
const R_PRIMARY := 0.0068
const R_SECONDARY := 0.0135
const R_COMM := [0.024, 0.017]
const R_DROP := 0.0095
const R_GUY := 0.0055
const R_JUMPER := 0.006
## Wire kinds, the shader's `kind` (UV2.y).
enum Wire { PRIMARY, SECONDARY, COMM, DROP, GUY, JUMPER }

## Chance per pole of a cobra-head street light on an arm, by CityPlan.District order
## (DOWNTOWN, MIDTOWN, SUBURBS, INDUSTRIAL, CAMPUS, BEACHTOWN).
const LIGHT_ODDS := [0.1, 0.16, 0.22, 0.3, 0.12, 0.2]
## Chance per pole of a splice case on the upper comm bundle, of a storage coil, of a riser.
const SPLICE_ODDS := 0.3
const COIL_ODDS := 0.12
const RISER_ODDS := 0.12
## Street light arm reach from the pole axis and the pool it throws.
const LIGHT_REACH := 2.35
const LIGHT_HEIGHT := 7.15
const LIGHT_POOL_SIZE := 13.0
## Guy wire: where it leaves the pole and how far out its anchor is; the guard's length.
const GUY_HEIGHT := 7.95
const GUY_LEAD := 4.2
const GUARD_LENGTH := 2.4

## House drops: the farthest a drop reaches, and how far the pole must stand in front of the
## house's front wall (a drop never runs back over a roof).
const HOUSE_DROP_REACH := 40.0
const HOUSE_DROP_FRONT := 1.5
## Mast over the eave (pitched roofs) and over the parapet (flat roofs); the meter's height.
const MAST_OVER_EAVE := 0.95
const MAST_OVER_PARAPET := 0.7
const METER_HEIGHT := 1.55
const DROP_SAG := 0.35
## Draw distances (metres): the fittings and the small stuff on a chunk's batches.
const HEAD_DRAW_DISTANCE := 280.0
const SMALL_DRAW_DISTANCE := 160.0

## Pole tag colours and the transformer can greys are sRGB numbers (vertex colours arrive raw on
## both renderers; the shader decodes them).
const WOOD := Color(0.42, 0.33, 0.25)
const ARM_WOOD := Color(0.55, 0.5, 0.43)
const GALV := Color(0.62, 0.63, 0.62)
const PORCELAIN := Color(0.43, 0.27, 0.16)
const PORCELAIN_GREY := Color(0.72, 0.72, 0.7)
const POLYMER := Color(0.5, 0.52, 0.52)
const CAN := Color(0.66, 0.68, 0.67)
const BLACK := Color(0.07, 0.07, 0.075)
const GUARD := Color(0.92, 0.72, 0.08)
const TAG := Color(0.78, 0.79, 0.8)
const LUMINAIRE := Color(0.6, 0.61, 0.6)
const LENS := Color(0.85, 0.82, 0.7)
const METER_GREY := Color(0.6, 0.62, 0.6)
const GLASS := Color(0.8, 0.85, 0.85)

## Surface kinds, the shader's (COLOR.a * 16).
const K_WOOD := 0
const K_ARM := 1
const K_GALV := 2
const K_PORCELAIN := 3
const K_POLYMER := 4
const K_CAN := 5
const K_BLACK := 6
const K_GUARD := 7
const K_TAG := 8
const K_LENS := 9
const K_GLASS := 10

static var _meshes: Dictionary = {}
static var _material: ShaderMaterial = null
static var _wire_material: ShaderMaterial = null
static var _runs_cache: Dictionary = {}


# =================================================================================================
# The street run (StreetDetail._pole_run hands it here)
# =================================================================================================

## A run's poles, pure: [{"pin": Vector3 (the old pole point, pavement height), "k": slot,
## "gap": the slot before was skipped}], with `along_z`, `line`, `phase`, `street` (unit, toward
## the road), `zl` (the arm face's side, street x up) and `gap_end`.
static func run_of(plan: CityPlan, rect: Rect2, axis: int, index: int, side: int) -> Dictionary:
	var top: float = CityChunk.SIDEWALK_TOP
	var along_z := axis == CityPlan.AXIS_X
	var kerb: float = (rect.position.x if side == 1 else rect.end.x) if along_z else (rect.position.y if side == 1 else rect.end.y)
	var inset := StreetDetail.POLE_INSET if side == 1 else -StreetDetail.POLE_INSET
	var line := kerb + inset
	var u0: float = rect.position.y if along_z else rect.position.x
	var u1: float = rect.end.y if along_z else rect.end.x
	var spacing: float = StreetDetail.POLE_SPACING
	var phase := float(absi(hash([plan.seed, "pole_phase", axis, index])) % 1000) * 0.001 * spacing
	var first := ceili((u0 + StreetDetail.POLE_EDGE_MARGIN - phase) / spacing)
	var last := floori((u1 - StreetDetail.POLE_EDGE_MARGIN - phase) / spacing)
	var arm := Vector3(1.0, 0.0, 0.0) if along_z else Vector3(0.0, 0.0, 1.0)
	var street := -arm * signf(inset)
	var poles: Array = []
	var gap := false
	for k in range(first, last + 1):
		var u := phase + k * spacing
		var p := Vector3(line, top, u) if along_z else Vector3(u, top, line)
		if _blocked(plan, p):
			gap = true
			continue
		poles.append({"pin": p, "k": k, "gap": gap})
		gap = false
	return {"poles": poles, "along_z": along_z, "line": line, "phase": phase, "street": street,
		"zl": street.cross(Vector3.UP), "gap_end": gap, "arm": arm,
		"run_dir": Vector3(0.0, 0.0, 1.0) if along_z else Vector3(1.0, 0.0, 0.0)}


## StreetDetail._pole_blocked() through the plan alone (the freeway corridor).
static func _blocked(plan: CityPlan, p: Vector3) -> bool:
	if plan.macro == null or plan.macro.freeway == null:
		return false
	return plan.macro.freeway.blocks(Vector2(p.x, p.z), StreetDetail.FREEWAY_CLEARANCE)


## Every run block (bx, bz) hangs, pure (StreetDetail._overhead_lines' faces, the same tests).
static func block_runs(plan: CityPlan, bx: int, bz: int) -> Array:
	var key := Vector3i(bx, bz, plan.seed)
	if _runs_cache.has(key):
		return _runs_cache[key]
	if _runs_cache.size() > 4096:
		_runs_cache.clear()
	var out: Array = []
	var rect: Rect2 = plan.block(bx, bz).rect
	var faces := [[CityPlan.AXIS_X, bx, 1], [CityPlan.AXIS_X, bx + 1, 0], [CityPlan.AXIS_Z, bz, 1], [CityPlan.AXIS_Z, bz + 1, 0]]
	for f: Array in faces:
		var axis: int = f[0]
		var index: int = f[1]
		var side: int = f[2]
		if absi(hash([plan.seed, "pole_side", axis, index])) % 2 != side:
			continue
		if not StreetDetail._has_poles(plan, bx, bz, axis, index):
			continue
		var r := run_of(plan, rect, axis, index, side)
		r["axis"] = axis
		r["index"] = index
		out.append(r)
	_runs_cache[key] = out
	return out


## The pole's local frame: x toward the street, y up, z the face the crossarm is bolted to.
## Right-handed (z = x cross y), so no instance is a mirror image.
static func pole_basis(street: Vector3, zl: Vector3) -> Basis:
	return Basis(street, Vector3.UP, zl)


## Where the pole's axis stands for a pin line point.
static func foot_of(pin: Vector3, zl: Vector3) -> Vector3:
	return pin - zl * POLE_FACE


## A point given in the pole's frame (metres over the pavement), in the chunk's world space with
## the relief under the pin line point (as StreetDetail._lift() measures it).
static func at_pole(ch: CityChunk, pin: Vector3, street: Vector3, zl: Vector3, local: Vector3) -> Vector3:
	var foot := foot_of(pin, zl)
	var p := foot + street * local.x + zl * local.z
	return Vector3(p.x, pin.y + local.y + ch._gy(pin.x, pin.z), p.z)


## The run: poles, heads, fittings, collision, spans, junction span, guys, service drops to the
## buildings behind. The same decisions StreetDetail's old run made, from the same hashes.
static func street_run(ch: CityChunk, rect: Rect2, axis: int, index: int, side: int, walls: Array[Rect2]) -> void:
	var plan: CityPlan = ch.plan
	var batch: MultiMeshBatch = ch._batch
	var r := run_of(plan, rect, axis, index, side)
	var poles: Array = r.poles
	if poles.is_empty():
		return
	var street: Vector3 = r.street
	var zl: Vector3 = r.zl
	var along_z: bool = r.along_z
	var run_dir: Vector3 = r.run_dir
	var basis := pole_basis(street, zl)
	var yaw := 0.0 if along_z else PI * 0.5
	var district: int = plan.district_at((rect as Rect2).get_center())
	var drops := not walls.is_empty()
	var into := -street
	var points: Array[Vector3] = []
	var breaks: Array[bool] = []
	for pole: Dictionary in poles:
		var p: Vector3 = pole.pin
		var k: int = pole.k
		points.append(p)
		breaks.append(bool(pole.gap))
		var foot := foot_of(p, zl)
		var tone := _h01([plan.seed, "upole_tone", axis, index, k])
		var custom := Color(_h01([plan.seed, "upole_age", axis, index, k]), tone, 0.0, 0.0)
		batch.add("upole", shaft_mesh(), Transform3D(basis, foot + Vector3(0.0, StreetDetail.POLE_HEIGHT * 0.5, 0.0)), Color.WHITE, custom)
		batch.add("up_head", head_mesh(), Transform3D(basis, foot), Color.WHITE, custom)
		if StreetDetail._hash01([plan.seed, "xfmr", axis, index, k]) < StreetDetail.TRANSFORMER_ODDS:
			batch.add("up_xfmr", transformer_mesh(), Transform3D(basis, foot), Color.WHITE, custom)
		if _h01([plan.seed, "ulight", axis, index, k]) < float(LIGHT_ODDS[district]):
			_street_light(ch, p, street, zl, basis, foot)
		if _h01([plan.seed, "uriser", axis, index, k]) < RISER_ODDS:
			batch.add("up_riser", riser_mesh(), Transform3D(basis, foot), Color.WHITE, custom)
		# A pole you can crash a car into, and the arm (bullets spark off it; the birds' ray
		# down at a span's end finds it).
		ch._add_shape(Vector3(0.34, StreetDetail.POLE_HEIGHT, 0.34), foot + Vector3(0.0, StreetDetail.POLE_HEIGHT * 0.5 + ch._gy(foot.x, foot.z), 0.0), yaw)
		var arm_c := at_pole(ch, p, street, zl, Vector3(0.0, StreetDetail.POWER_ARM_HEIGHT, POLE_FACE))
		ch._add_shape(Vector3(ARM_LENGTH, ARM_DEPTH + 0.1, 0.14), arm_c, yaw)
		# Service drop to the wall behind (the old run's hash and reach): from the spool.
		if drops and StreetDetail._hash01([plan.seed, "drop", axis, index, k]) < StreetDetail.SERVICE_DROP_ODDS:
			var reach := StreetDetail._facade_reach(walls, p, into)
			if reach > 0.0:
				var wall := p + into * (reach + 0.06)
				var top := StreetDetail._lift(ch, wall, StreetDetail.SERVICE_DROP_HEIGHT + 0.55)
				_wall_head(ch, wall, top, street)
				add_wire(batch, secondary_point(ch, p, street, zl), top - Vector3(0.0, 0.18, 0.0), DROP_SAG, Wire.DROP, R_DROP)
	var n := points.size()
	for i in n - 1:
		if breaks[i + 1]:
			continue
		span(ch, points[i], points[i + 1], street, zl, [plan.seed, axis, index, poles[i].k])
	var nbx := ch.ix if along_z else ch.ix + 1
	var nbz := ch.iz + 1 if along_z else ch.iz
	var bridged := false
	if not bool(r.gap_end):
		var ahead := StreetDetail._junction_pole(ch, nbx, nbz, axis, index, along_z, float(r.line), float(r.phase), false)
		if not ahead.is_empty():
			span(ch, points[n - 1], ahead[0], street, zl, [plan.seed, axis, index, poles[n - 1].k])
			bridged = true
	var pbx := ch.ix if along_z else ch.ix - 1
	var pbz := ch.iz - 1 if along_z else ch.iz
	var behind := StreetDetail._junction_pole(ch, pbx, pbz, axis, index, along_z, float(r.line), float(r.phase), true)
	for i in n:
		if breaks[i] or (i == 0 and behind.is_empty()):
			guy(ch, points[i], zl, -run_dir)
		var ends := breaks[i + 1] if i < n - 1 else not bridged
		if ends:
			guy(ch, points[i], zl, run_dir)
	_batch_settings(batch)


static func _batch_settings(batch: MultiMeshBatch) -> void:
	batch.set_draw_distance("up_head", HEAD_DRAW_DISTANCE)
	batch.set_draw_distance("up_xfmr", HEAD_DRAW_DISTANCE)
	batch.set_draw_distance("up_light", HEAD_DRAW_DISTANCE)
	for key in ["up_riser", "up_splice", "up_coil", "up_guard", "up_anchor", "up_meter", "up_mast", "up_whead"]:
		batch.set_draw_distance(key, SMALL_DRAW_DISTANCE)
	for key in ["up_guard", "up_anchor", "up_meter", "up_whead", "up_splice", "up_coil"]:
		batch.set_no_shadow(key)


## The spool rack's point on a pole (where the secondary and every drop hang).
static func secondary_point(ch: CityChunk, pin: Vector3, street: Vector3, zl: Vector3) -> Vector3:
	return at_pole(ch, pin, street, zl, Vector3(0.0, SECONDARY_HEIGHT, POLE_FACE + 0.06))


## One pole-to-pole span: the three primaries on the pins (the middle one is Birds' polyline),
## the secondary off the spool, the two comm bundles on the street face. `key` seeds the span's
## splice case and coil.
static func span(ch: CityChunk, a: Vector3, b: Vector3, street: Vector3, zl: Vector3, key: Array) -> void:
	var batch: MultiMeshBatch = ch._batch
	var length := Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))
	var k2 := pow(length / StreetDetail.POLE_SPACING, 2.0)
	var pin_y: float = StreetDetail.POWER_ARM_HEIGHT + 0.2
	for i in 3:
		var o := street * float(i - 1) * PIN_SPREAD
		add_wire(batch, StreetDetail._lift(ch, a + o, pin_y), StreetDetail._lift(ch, b + o, pin_y), StreetDetail.POWER_SAG * k2, Wire.PRIMARY, R_PRIMARY)
	add_wire(batch, secondary_point(ch, a, street, zl), secondary_point(ch, b, street, zl), SECONDARY_SAG * k2, Wire.SECONDARY, R_SECONDARY)
	for c in 2:
		var la := at_pole(ch, a, street, zl, Vector3(COMM_OUT, COMM_HEIGHTS[c], 0.0))
		var lb := at_pole(ch, b, street, zl, Vector3(COMM_OUT, COMM_HEIGHTS[c], 0.0))
		var sag: float = float(COMM_SAGS[c]) * k2
		add_wire(batch, la, lb, sag, Wire.COMM, float(R_COMM[c]))
		if c == 0 and _h01(key + ["usplice"]) < SPLICE_ODDS:
			var t := clampf(2.6 / maxf(length, 1.0), 0.05, 0.4)
			var at := catenary_point(la, lb, sag, t)
			var dir := (catenary_point(la, lb, sag, t + 0.01) - at).normalized()
			_put_along(batch, "up_splice", splice_mesh(), at - Vector3(0.0, 0.09, 0.0), dir)
		if c == 1 and _h01(key + ["ucoil"]) < COIL_ODDS:
			var t := clampf(4.5 / maxf(length, 1.0), 0.05, 0.4)
			var at := catenary_point(la, lb, sag, t)
			var dir := (catenary_point(la, lb, sag, t + 0.01) - at).normalized()
			_put_along(batch, "up_coil", coil_mesh(), at, dir)


## A guy from the arm's level down to an anchor GUY_LEAD out along `dir`, with its guard.
static func guy(ch: CityChunk, pin: Vector3, zl: Vector3, dir: Vector3) -> void:
	var batch: MultiMeshBatch = ch._batch
	var foot := foot_of(pin, zl)
	var top := Vector3(foot.x, foot.y + GUY_HEIGHT + ch._gy(foot.x, foot.z), foot.z) + dir * 0.13
	var ground := foot + dir * GUY_LEAD
	var anchor := Vector3(ground.x, ground.y + ch._gy(ground.x, ground.z) + 0.05, ground.z)
	add_wire(batch, top, anchor, 0.0, Wire.GUY, R_GUY)
	var d := (top - anchor).normalized()
	_put_along(batch, "up_guard", guard_mesh(), anchor + d * (GUARD_LENGTH * 0.5 + 0.12), d)
	_put_along(batch, "up_anchor", anchor_mesh(), anchor, d)


## A cobra head on an upswept arm over the street, its lens glowing and its pool on the road.
static func _street_light(ch: CityChunk, pin: Vector3, street: Vector3, zl: Vector3, basis: Basis, foot: Vector3) -> void:
	var batch: MultiMeshBatch = ch._batch
	batch.add("up_light", light_mesh(), Transform3D(basis, foot))
	var head := foot + street * (LIGHT_REACH + 0.33)
	var lens := Transform3D(Basis(Vector3.RIGHT, PI * 0.5).scaled(Vector3(0.62, 1.0, 0.3)) if absf(street.x) > 0.5 else Basis(Vector3.RIGHT, PI * 0.5).scaled(Vector3(0.3, 1.0, 0.62)), head + Vector3(0.0, LIGHT_HEIGHT - 0.035, 0.0))
	batch.add("up_lens", PropFactory.lamp_face(Color(1.0, 0.86, 0.62), 2.2), lens)
	var pool_at := foot + street * (LIGHT_REACH + 0.5)
	var pool := Transform3D(Basis(Vector3.RIGHT, -PI * 0.5).scaled(Vector3(LIGHT_POOL_SIZE, 1.0, LIGHT_POOL_SIZE)), pool_at + Vector3(0.0, 0.09, 0.0))
	batch.add("lamp_pool", PropFactory.light_pool(), pool, NightCity.pool_color(Vector2(pool_at.x, pool_at.z)))
	batch.set_no_shadow("lamp_pool")
	batch.set_no_shadow("up_lens")


## A wall head for a drop on a Building: a short conduit with a weatherhead.
static func _wall_head(ch: CityChunk, wall: Vector3, top: Vector3, street: Vector3) -> void:
	var batch: MultiMeshBatch = ch._batch
	var base := top - Vector3(0.0, 1.3, 0.0)
	var face := Basis(Vector3.UP.cross(street), Vector3.UP, street)
	var g := ch._gy(wall.x, wall.z)
	batch.add("up_mast", mast_mesh(), Transform3D(face.scaled_local(Vector3(1.0, 1.3, 1.0)), Vector3(base.x, base.y - g, base.z) + street * 0.05))
	batch.add("up_whead", weatherhead_mesh(), Transform3D(face, Vector3(top.x, top.y - g, top.z) + street * 0.05))


static func _put_along(batch: MultiMeshBatch, key: String, mesh: Mesh, at: Vector3, dir: Vector3) -> void:
	# Meshes run along +Z; `at` is a true world point (relief included), the batch adds it again.
	var up := Vector3.UP if absf(dir.y) < 0.95 else Vector3.RIGHT
	var x := up.cross(dir).normalized()
	var y := dir.cross(x).normalized()
	var g: float = batch.ground.call(at.x, at.z) if batch.ground.is_valid() else 0.0
	batch.add(key, mesh, Transform3D(Basis(x, y, dir), Vector3(at.x, at.y - g, at.z)))


# =================================================================================================
# House drops (every house in the suburbs and the beach town)
# =================================================================================================

## CityChunk._build_house(): remembers the house for the drops at the finish.
static func note_house(ch: CityChunk, house: Dictionary) -> void:
	if not enabled or ch.capturing or ch.level != CityChunk.Level.FULL:
		return
	if not ch.has_meta("up_houses"):
		ch.set_meta("up_houses", [])
	(ch.get_meta("up_houses") as Array).append(house)


## The pole that feeds a house, pure: [pin, street, zl] of the nearest pole within
## HOUSE_DROP_REACH that stands at least HOUSE_DROP_FRONT in front of the attachment (`at`, on the
## front wall, `out` the wall's outward normal), on the house's block or one round it; or [].
static func feeder(plan: CityPlan, bx: int, bz: int, at: Vector2, out: Vector2) -> Array:
	var best: Array = []
	var best_d := HOUSE_DROP_REACH
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			for r: Dictionary in block_runs(plan, bx + dx, bz + dz):
				for pole: Dictionary in r.poles:
					var p: Vector3 = pole.pin
					var d := Vector2(p.x, p.z) - at
					var fwd := d.dot(out)
					if fwd < HOUSE_DROP_FRONT:
						continue
					# Not a drop that runs along the house front for most of its length.
					if absf(d.dot(Vector2(-out.y, out.x))) > fwd * 2.2 + 4.0:
						continue
					var dist := d.length()
					if dist < best_d:
						best_d = dist
						best = [p, r.street, r.zl]
	return best


## The drop, the meter and the mast of every house the chunk noted.
static func _house_drops(ch: CityChunk) -> void:
	if not ch.has_meta("up_houses"):
		return
	var houses: Array = ch.get_meta("up_houses")
	ch.remove_meta("up_houses")
	var batch: MultiMeshBatch = ch._batch
	var plan: CityPlan = ch.plan
	for h: Dictionary in houses:
		var att := house_attachment(ch, h)
		if att.is_empty():
			continue
		var at: Vector2 = att.at
		var out: Vector2 = att.out
		var src := feeder(plan, ch.ix, ch.iz, at, out)
		if src.is_empty():
			continue
		var pin: Vector3 = src[0]
		# Slide the attachment along the wall toward the pole, inside the wing's span.
		var t := Vector2(-out.y, out.x)
		var slide := clampf((Vector2(pin.x, pin.z) - at).dot(t), att.lo, att.hi)
		at += t * slide
		var g := ch._gy(at.x, at.y)
		var floor_y: float = att.floor
		var face := Basis(Vector3(out.y, 0.0, -out.x), Vector3.UP, Vector3(out.x, 0.0, out.y))
		var wall := Vector3(at.x, 0.0, at.y) + Vector3(out.x, 0.0, out.y) * 0.07
		var custom := Color(_h01([plan.seed, h.seed, "meter"]), 0.0, 0.0, 0.0)
		batch.add("up_meter", meter_mesh(), Transform3D(face, Vector3(wall.x, floor_y + METER_HEIGHT - g, wall.z)), Color.WHITE, custom)
		var mast_base := floor_y + METER_HEIGHT + 0.3
		var mast_top: float = att.top
		batch.add("up_mast", mast_mesh(), Transform3D(face.scaled_local(Vector3(1.0, mast_top - mast_base, 1.0)), Vector3(wall.x, mast_base - g, wall.z)))
		# The weatherhead's mouth turns toward the pole.
		var to_pole := Vector3(pin.x - wall.x, 0.0, pin.z - wall.z).normalized()
		var hb := Basis(Vector3.UP.cross(to_pole).normalized(), Vector3.UP, to_pole)
		batch.add("up_whead", weatherhead_mesh(), Transform3D(hb, Vector3(wall.x, mast_top - g, wall.z)))
		var end := Vector3(wall.x, mast_top - 0.22, wall.z) + to_pole * 0.05
		add_wire(batch, secondary_point(ch, pin, src[1], src[2]), end, DROP_SAG + 0.012 * Vector2(pin.x, pin.z).distance_to(at), Wire.DROP, R_DROP)
	_batch_settings(batch)


## Where a house takes its service: the main wing's front wall. {"at" (the wall's mid point, world
## xz), "out", "lo"/"hi" (how far the point may slide along the wall), "floor" (world y of the
## floor), "top" (world y of the mast's top)}, or {} for a house with no wing.
static func house_attachment(ch: CityChunk, h: Dictionary) -> Dictionary:
	var wings: Array = h.wings
	if wings.is_empty():
		return {}
	var w: Dictionary = wings[0]
	for x: Dictionary in wings:
		if str(x.role) == "main":
			w = x
			break
	var f: Dictionary = h.f
	var r: Rect2 = w.r
	var o: Vector2 = f.o
	var fu: Vector2 = f.u
	var fv: Vector2 = f.v
	var mid := o + fu * (r.position.x + r.size.x * 0.5) + fv * r.position.y
	# The floor as HouseBuild.setup() works it out.
	var gmax := -INF
	for gr: Rect2 in HouseKit.ground_parts(h):
		for c: Vector2 in [gr.position, Vector2(gr.end.x, gr.position.y), gr.end, Vector2(gr.position.x, gr.end.y)]:
			gmax = maxf(gmax, ch._gy(c.x, c.y))
	var floor_y := gmax + CityChunk.SIDEWALK_TOP + YardFill.LIFT + HouseKit.FLOOR_LIFT
	var wall_top := floor_y + float(w.storeys) * HouseKit.STOREY
	var roof: String = w.roof
	var flat := roof == "flat" or roof == "deck" or roof == "butterfly"
	var top := wall_top + (HouseKit.PARAPET + MAST_OVER_PARAPET if flat else MAST_OVER_EAVE)
	var half := maxf(r.size.x * 0.5 - 0.7, 0.0)
	return {"at": mid, "out": -fv, "lo": -half, "hi": half, "floor": floor_y, "top": top}


# =================================================================================================
# Wires: one ribbon mesh a chunk
# =================================================================================================

## A sagging wire from a to b (true world points, relief included) in StreetDetail.CABLE_SEGMENTS
## pieces on the parabola StreetDetail._catenary() always drew.
static func add_wire(batch: MultiMeshBatch, a: Vector3, b: Vector3, sag: float, kind: int, radius: float) -> void:
	var n: int = StreetDetail.CABLE_SEGMENTS if sag > 0.0 else 1
	var pts := PackedVector3Array()
	pts.resize(n + 1)
	for i in n + 1:
		pts[i] = catenary_point(a, b, sag, float(i) / float(n))
	if not batch.has_meta("up_wires"):
		batch.set_meta("up_wires", [])
	(batch.get_meta("up_wires") as Array).append([pts, radius, kind])


static func catenary_point(a: Vector3, b: Vector3, sag: float, s: float) -> Vector3:
	return a.lerp(b, s) - Vector3(0.0, sag * 4.0 * s * (1.0 - s), 0.0)


## CityChunk._finish_build(), before the batch is built: the house drops, then every wire of the
## chunk as one ribbon mesh.
static func commit(ch: CityChunk) -> void:
	if not enabled:
		return
	_house_drops(ch)
	var batch: MultiMeshBatch = ch._batch
	if not batch.has_meta("up_wires"):
		return
	var wires: Array = batch.get_meta("up_wires")
	batch.remove_meta("up_wires")
	var mesh := ribbon_mesh(wires)
	if mesh == null:
		return
	var mi := MeshInstance3D.new()
	mi.name = "UtilityWires"
	mi.mesh = mesh
	mi.material_override = wire_material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	ch.add_child(mi)


## The ribbons: every vertex on its wire's centre line (the shader widens it to face the camera),
## NORMAL the wire's direction, UV (side -1 / +1, metres along), UV2 (radius, kind).
static func ribbon_mesh(wires: Array) -> ArrayMesh:
	var v := PackedVector3Array()
	var nrm := PackedVector3Array()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var idx := PackedInt32Array()
	for w: Array in wires:
		var pts: PackedVector3Array = w[0]
		var radius: float = w[1]
		var kind: int = w[2]
		var n := pts.size()
		if n < 2:
			continue
		var along := 0.0
		var base := v.size()
		for i in n:
			var t: Vector3
			if i == 0:
				t = pts[1] - pts[0]
			elif i == n - 1:
				t = pts[n - 1] - pts[n - 2]
			else:
				t = pts[i + 1] - pts[i - 1]
			t = t.normalized()
			if i > 0:
				along += pts[i].distance_to(pts[i - 1])
			for s in [-1.0, 1.0]:
				v.append(pts[i])
				nrm.append(t)
				uv.append(Vector2(s, along))
				uv2.append(Vector2(radius, float(kind)))
		for i in n - 1:
			var a := base + i * 2
			idx.append_array([a, a + 2, a + 1, a + 1, a + 2, a + 3])
	if idx.is_empty():
		return null
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = v
	arrays[Mesh.ARRAY_NORMAL] = nrm
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_TEX_UV2] = uv2
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	# The vertices sit on the centre line: the drawn wire is up to a few pixels wider.
	var aabb := mesh.get_aabb()
	mesh.custom_aabb = aabb.grow(0.5)
	return mesh


static func wire_material() -> ShaderMaterial:
	if _wire_material == null:
		_wire_material = ShaderMaterial.new()
		_wire_material.shader = load("res://shaders/utility_wire.gdshader")
	return _wire_material


static func material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = load("res://shaders/utility_pole.gdshader")
	return _material


# =================================================================================================
# The hardware, built in code (pole frame: x toward the street, y up from the pavement, z the
# crossarm's face; meshes that run along a wire run along +Z)
# =================================================================================================

## Mesh builder: one surface, flat or smooth normals, UV in metres, kind in COLOR.a.
class Geo extends RefCounted:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var uv := PackedVector2Array()
	var c := PackedColorArray()
	var idx := PackedInt32Array()

	func vert(p: Vector3, nn: Vector3, t: Vector2, col: Color, kind: int) -> int:
		v.append(p)
		n.append(nn)
		uv.append(t)
		c.append(Color(col.r, col.g, col.b, (float(kind) + 0.5) / 16.0))
		return v.size() - 1

	## A triangle wound to face its vertices' normals (front faces clockwise, as Godot draws).
	func tri(a: int, b: int, cc: int) -> void:
		var want := n[a] + n[b] + n[cc]
		var flat := (v[cc] - v[a]).cross(v[b] - v[a])
		if flat.dot(want) < 0.0:
			idx.append_array([a, cc, b])
		else:
			idx.append_array([a, b, cc])

	## A flat quad facing `nn`.
	func quad(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, nn: Vector3, col: Color, kind: int, u: Vector2 = Vector2.ONE) -> void:
		var a := vert(p0, nn, Vector2(0.0, 0.0), col, kind)
		var b := vert(p1, nn, Vector2(u.x, 0.0), col, kind)
		var cc := vert(p2, nn, Vector2(u.x, u.y), col, kind)
		var d := vert(p3, nn, Vector2(0.0, u.y), col, kind)
		tri(a, b, cc)
		tri(a, cc, d)

	## An oriented box: centre, half extents along the basis' columns.
	func box(center: Vector3, half: Vector3, basis: Basis, col: Color, kind: int) -> void:
		var ax := [basis.x.normalized(), basis.y.normalized(), basis.z.normalized()]
		var hs := [half.x, half.y, half.z]
		for f in 3:
			for s in [-1.0, 1.0]:
				var nn: Vector3 = ax[f] * s
				var e1: Vector3 = ax[(f + 1) % 3] * hs[(f + 1) % 3]
				var e2: Vector3 = ax[(f + 2) % 3] * hs[(f + 2) % 3]
				var fc: Vector3 = center + nn * hs[f]
				quad(fc - e1 - e2, fc + e1 - e2, fc + e1 + e2, fc - e1 + e2, nn, col, kind,
					Vector2(2.0 * hs[(f + 1) % 3], 2.0 * hs[(f + 2) % 3]))

	## A surface of revolution about the segment a -> b: `profile` is [Vector2(radius, t 0..1)],
	## smooth round, flat along the profile's steps. UV: (metres round, metres along).
	func lathe(a: Vector3, b: Vector3, profile: Array, sides: int, col: Color, kind: int, cap0: bool = false, cap1: bool = false) -> void:
		var axis := b - a
		var length := axis.length()
		var d := axis / length
		var ref := Vector3.UP if absf(d.y) < 0.9 else Vector3.RIGHT
		var e1 := ref.cross(d).normalized()
		var e2 := d.cross(e1).normalized()
		var rows: Array = []
		for k in profile.size():
			var pr: Vector2 = profile[k]
			# The profile's slope gives the normal's lean along the axis.
			var prev: Vector2 = profile[maxi(k - 1, 0)]
			var next: Vector2 = profile[mini(k + 1, profile.size() - 1)]
			var dr := next.x - prev.x
			var dt := (next.y - prev.y) * length
			var lean := -dr / maxf(sqrt(dr * dr + dt * dt), 1e-5)
			var row: Array = []
			for s in sides + 1:
				var ang := TAU * float(s) / float(sides)
				var radial := e1 * cos(ang) + e2 * sin(ang)
				var nn := (radial * sqrt(maxf(1.0 - lean * lean, 0.0)) + d * lean).normalized()
				row.append(vert(a + d * pr.y * length + radial * pr.x, nn, Vector2(ang * pr.x, pr.y * length), col, kind))
			rows.append(row)
		for k in profile.size() - 1:
			var r0: Array = rows[k]
			var r1: Array = rows[k + 1]
			for s in sides:
				tri(r0[s], r0[s + 1], r1[s + 1])
				tri(r0[s], r1[s + 1], r1[s])
		if cap0:
			_cap(a, -d, e1, e2, (profile[0] as Vector2).x, sides, col, kind)
		if cap1:
			_cap(b, d, e1, e2, (profile[profile.size() - 1] as Vector2).x, sides, col, kind)

	func _cap(at: Vector3, nn: Vector3, e1: Vector3, e2: Vector3, r: float, sides: int, col: Color, kind: int) -> void:
		if r <= 0.0005:
			return
		var centre := vert(at, nn, Vector2.ZERO, col, kind)
		var ring: Array = []
		for s in sides + 1:
			var ang := TAU * float(s) / float(sides)
			var p := at + (e1 * cos(ang) + e2 * sin(ang)) * r
			ring.append(vert(p, nn, Vector2(cos(ang), sin(ang)) * r, col, kind))
		for s in sides:
			tri(centre, ring[s], ring[s + 1])

	## A round tube from a to b.
	func tube(a: Vector3, b: Vector3, r: float, sides: int, col: Color, kind: int, caps: bool = false) -> void:
		lathe(a, b, [Vector2(r, 0.0), Vector2(r, 1.0)], sides, col, kind, caps, caps)

	## A bent tube through `path` (one tube per piece, the joints overlap).
	func pipe(path: Array, r: float, sides: int, col: Color, kind: int) -> void:
		for i in path.size() - 1:
			tube(path[i], path[i + 1], r, sides, col, kind, i == 0 or i == path.size() - 2)

	func commit(lods: bool = true) -> Mesh:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = v
		arrays[Mesh.ARRAY_NORMAL] = n
		arrays[Mesh.ARRAY_TEX_UV] = uv
		arrays[Mesh.ARRAY_COLOR] = c
		arrays[Mesh.ARRAY_INDEX] = idx
		if not lods:
			var am := ArrayMesh.new()
			am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			am.surface_set_material(0, UtilityPoles.material())
			return am
		var im := ImporterMesh.new()
		im.add_surface(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, UtilityPoles.material())
		im.generate_lods(25.0, 60.0, [])
		return im.get_mesh()

	func triangles() -> int:
		return idx.size() / 3


static func _cached(key: String, build: Callable, shadow: Callable = Callable()) -> Mesh:
	if _meshes.has(key):
		return _meshes[key]
	var mesh: Mesh = build.call()
	_meshes[key] = mesh
	if shadow.is_valid():
		var sm: Mesh = shadow.call()
		PropFactory._shadow_proxies[mesh] = sm
	return mesh


## Triangles of each hardware mesh (the checks hold them to a budget).
static func triangle_counts() -> Dictionary:
	var meshes := {"shaft": shaft_mesh(), "head": head_mesh(), "xfmr": transformer_mesh(), "light": light_mesh(),
		"riser": riser_mesh(), "splice": splice_mesh(), "coil": coil_mesh(), "guard": guard_mesh(),
		"anchor": anchor_mesh(), "meter": meter_mesh(), "mast": mast_mesh(), "whead": weatherhead_mesh()}
	var out := {}
	for key: String in meshes:
		var m: Mesh = meshes[key]
		var count := 0
		for s in m.get_surface_count():
			var a := m.surface_get_arrays(s)
			count += (a[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
		out[key] = count
	return out


## The shaft: a 9 m Douglas-fir pole tapering from 0.165 m at the pavement to 0.125 m, a little
## bowed, its top chamfered, the pole tag at eye height and the ground wire's moulding down the
## field side. Centred on its height (StreetWear, ClimbingPlants read it as before).
static func shaft_mesh() -> Mesh:
	return _cached("shaft", _build_shaft, _build_shaft_shadow)


static func _build_shaft() -> Mesh:
	var g := Geo.new()
	var hh: float = StreetDetail.POLE_HEIGHT * 0.5
	var prof: Array = []
	var rings := 10
	for i in rings + 1:
		var t := float(i) / float(rings)
		prof.append(Vector2(lerpf(0.165, 0.127, t), t * 0.985))
	prof.append(Vector2(0.105, 1.0))
	var a := Vector3(0.0, -hh, 0.0)
	var b := Vector3(0.0, hh, 0.0)
	g.lathe(a, b, prof, 14, WOOD, K_WOOD, false, true)
	# Pole tag (aluminium, numbered) on the street face at 1.7 m.
	g.box(Vector3(0.161, 1.7 - hh, 0.0), Vector3(0.004, 0.045, 0.05), Basis(), TAG, K_TAG)
	# The ground wire's moulding, a half-round strip down the field side to the top.
	var ga := Vector3(-0.16, -hh, 0.0)
	var gb := Vector3(-0.128, hh - 0.6, 0.0)
	g.tube(ga, gb, 0.012, 5, GALV, K_GALV)
	return g.commit()


static func _build_shaft_shadow() -> Mesh:
	var g := Geo.new()
	var hh: float = StreetDetail.POLE_HEIGHT * 0.5
	g.lathe(Vector3(0.0, -hh, 0.0), Vector3(0.0, hh, 0.0), [Vector2(0.16, 0.0), Vector2(0.125, 1.0)], 6, WOOD, K_WOOD, false, true)
	return g.commit(false)


## The head: the crossarm on the pole's +z face with its braces, the three pins and porcelain
## insulators, the through-bolt, the secondary's spool rack under the middle pin and the comm
## bundles' strand clamps on the street face. Origin at the pole's foot.
static func head_mesh() -> Mesh:
	return _cached("head", _build_head, _build_head_shadow)


static func _pin_insulator(g: Geo, base: Vector3, col: Color) -> void:
	# Steel pin, then a pin insulator: a wide drip skirt, a waist, the top skirt, the groove the
	# conductor is tied in and the crown. The groove's top is 0.1425 m over the arm's top, so the
	# conductor lies at POWER_ARM_HEIGHT + 0.2 over the pavement.
	g.tube(base, base + Vector3(0.0, 0.04, 0.0), 0.012, 6, GALV, K_GALV)
	var p := [Vector2(0.026, 0.0), Vector2(0.062, 0.12), Vector2(0.064, 0.2), Vector2(0.034, 0.3),
		Vector2(0.052, 0.48), Vector2(0.054, 0.56), Vector2(0.03, 0.64), Vector2(0.026, 0.8),
		Vector2(0.033, 0.88), Vector2(0.026, 0.97), Vector2(0.0, 1.0)]
	g.lathe(base + Vector3(0.0, 0.01, 0.0), base + Vector3(0.0, 0.1525, 0.0), p, 10, col, K_PORCELAIN, true, false)


static func _build_head() -> Mesh:
	var g := Geo.new()
	var arm_y: float = StreetDetail.POWER_ARM_HEIGHT
	var z := POLE_FACE
	# The arm: an octagonal section (chamfered edges), end grain capped.
	var hx := ARM_LENGTH * 0.5
	var ht := ARM_THICK * 0.5
	var hd := ARM_DEPTH * 0.5
	var ch := 0.014
	var sect := [Vector2(ht - ch, hd), Vector2(ht, hd - ch), Vector2(ht, -hd + ch), Vector2(ht - ch, -hd),
		Vector2(-ht + ch, -hd), Vector2(-ht, -hd + ch), Vector2(-ht, hd - ch), Vector2(-ht + ch, hd)]
	for i in 8:
		var s0: Vector2 = sect[i]
		var s1: Vector2 = sect[(i + 1) % 8]
		var mid := (s0 + s1) * 0.5
		var nn := Vector3(0.0, mid.y, mid.x).normalized()
		g.quad(Vector3(-hx, arm_y + s0.y, z + s0.x), Vector3(hx, arm_y + s0.y, z + s0.x), Vector3(hx, arm_y + s1.y, z + s1.x), Vector3(-hx, arm_y + s1.y, z + s1.x), nn, ARM_WOOD, K_ARM, Vector2(ARM_LENGTH, s0.distance_to(s1)))
	for e in [-1.0, 1.0]:
		var c0 := g.vert(Vector3(hx * e, arm_y, z), Vector3(e, 0.0, 0.0), Vector2.ZERO, ARM_WOOD, K_ARM)
		for i in 8:
			var s0: Vector2 = sect[i]
			var s1: Vector2 = sect[(i + 1) % 8]
			var a := g.vert(Vector3(hx * e, arm_y + s0.y, z + s0.x), Vector3(e, 0.0, 0.0), Vector2(s0.x, s0.y), ARM_WOOD, K_ARM)
			var b := g.vert(Vector3(hx * e, arm_y + s1.y, z + s1.x), Vector3(e, 0.0, 0.0), Vector2(s1.x, s1.y), ARM_WOOD, K_ARM)
			g.tri(c0, a, b)
	# Braces: flat galvanised straps from under the arm down to the pole's face.
	for s in [-1.0, 1.0]:
		var top := Vector3(s * 0.62, arm_y - hd - 0.004, z - 0.01)
		var bot := Vector3(s * 0.04, arm_y - 0.62, 0.142)
		var dir := (bot - top).normalized()
		var side := dir.cross(Vector3(0.0, 0.0, 1.0)).normalized()
		g.box((top + bot) * 0.5, Vector3(0.022, top.distance_to(bot) * 0.5, 0.004), Basis(side, dir, Vector3(0.0, 0.0, 1.0)), GALV, K_GALV)
		g.box(bot, Vector3(0.018, 0.018, 0.012), Basis(), GALV, K_GALV)
	# Through-bolt, washer.
	g.tube(Vector3(0.0, arm_y, -0.16), Vector3(0.0, arm_y, z + ht + 0.03), 0.009, 6, GALV, K_GALV, true)
	g.box(Vector3(0.0, arm_y, z + ht + 0.004), Vector3(0.03, 0.03, 0.004), Basis(), GALV, K_GALV)
	# Pins and insulators: porcelain brown on the outer two, grey on the middle on some poles is
	# not worth a variant: all brown, the commonest LA glaze.
	for i in 3:
		_pin_insulator(g, Vector3(float(i - 1) * PIN_SPREAD, arm_y + hd, z), PORCELAIN)
	# Secondary rack: a strap on the pole's face and one spool insulator.
	var sy := SECONDARY_HEIGHT
	g.box(Vector3(0.0, sy, 0.142), Vector3(0.025, 0.2, 0.005), Basis(), GALV, K_GALV)
	g.box(Vector3(0.0, sy + 0.07, z + 0.02), Vector3(0.025, 0.004, 0.07), Basis(), GALV, K_GALV)
	g.box(Vector3(0.0, sy - 0.07, z + 0.02), Vector3(0.025, 0.004, 0.07), Basis(), GALV, K_GALV)
	g.lathe(Vector3(0.0, sy - 0.066, z + 0.06), Vector3(0.0, sy + 0.066, z + 0.06),
		[Vector2(0.04, 0.0), Vector2(0.045, 0.15), Vector2(0.03, 0.5), Vector2(0.045, 0.85), Vector2(0.04, 1.0)], 8, PORCELAIN_GREY, K_PORCELAIN)
	# Comm bundles' clamps and bolts on the street face.
	for hgt: float in COMM_HEIGHTS:
		g.tube(Vector3(-0.17, hgt, 0.0), Vector3(COMM_OUT + 0.02, hgt, 0.0), 0.008, 6, GALV, K_GALV, true)
		g.box(Vector3(COMM_OUT - 0.02, hgt, 0.0), Vector3(0.035, 0.03, 0.03), Basis(), GALV, K_GALV)
	return g.commit()


static func _build_head_shadow() -> Mesh:
	var g := Geo.new()
	g.box(Vector3(0.0, StreetDetail.POWER_ARM_HEIGHT, POLE_FACE), Vector3(ARM_LENGTH * 0.5, ARM_DEPTH * 0.5, ARM_THICK * 0.5), Basis(), ARM_WOOD, K_ARM)
	return g.commit(false)


## A pole-top transformer on the field side: the can on two hanger brackets, its lid, the HV
## bushing on top with its jumper up to a fuse cutout on a bracket at the arm's end and from that
## to the near primary, an arrester, three LV bushings and their leads to the spool rack.
static func transformer_mesh() -> Mesh:
	return _cached("xfmr", _build_xfmr, _build_xfmr_shadow)


static func _build_xfmr() -> Mesh:
	var g := Geo.new()
	var cx := -0.5
	var y0 := 6.35
	var y1 := 7.25
	var c := Vector3(cx, 0.0, 0.0)
	# The can: a rim at the bottom, the body, the lid's rim and its shallow dome.
	g.lathe(c + Vector3(0.0, y0, 0.0), c + Vector3(0.0, y1 + 0.1, 0.0),
		[Vector2(0.22, 0.0), Vector2(0.27, 0.03), Vector2(0.275, 0.06), Vector2(0.275, 0.86), Vector2(0.29, 0.875),
		Vector2(0.29, 0.9), Vector2(0.255, 0.93), Vector2(0.17, 0.98), Vector2(0.0, 1.0)], 14, CAN, K_CAN, true, false)
	# Hanger brackets to the pole's field face.
	for hy in [y1 - 0.1, y0 + 0.2]:
		g.box(Vector3(-0.2, hy, 0.0), Vector3(0.07, 0.03, 0.09), Basis(), GALV, K_GALV)
		g.box(Vector3(-0.155, hy, 0.0), Vector3(0.006, 0.08, 0.1), Basis(), GALV, K_GALV)
	# Lifting lugs.
	for s in [-1.0, 1.0]:
		g.box(c + Vector3(0.0, y1 + 0.02, s * 0.28), Vector3(0.025, 0.03, 0.012), Basis(), CAN, K_CAN)
	# HV bushing on the lid.
	var hv := c + Vector3(0.0, y1 + 0.1, 0.0)
	g.lathe(hv, hv + Vector3(0.0, 0.2, 0.0), [Vector2(0.035, 0.0), Vector2(0.05, 0.15), Vector2(0.03, 0.3), Vector2(0.045, 0.45),
		Vector2(0.026, 0.6), Vector2(0.04, 0.75), Vector2(0.02, 0.9), Vector2(0.012, 1.0)], 8, PORCELAIN, K_PORCELAIN)
	# LV bushings on the can's street-ward side, low.
	for i in 3:
		var bz := (float(i) - 1.0) * 0.12
		var b0 := c + Vector3(0.27, y1 - 0.2, bz)
		g.tube(b0, b0 + Vector3(0.07, 0.0, 0.0), 0.022, 6, BLACK, K_BLACK, true)
	# The fuse cutout: a bracket under the arm's field end, the porcelain body tilted, the fuse
	# tube in front of it; the arrester beside it.
	var arm_y: float = StreetDetail.POWER_ARM_HEIGHT
	var cut := Vector3(-1.02, arm_y - 0.32, POLE_FACE + 0.08)
	g.box(Vector3(-1.02, arm_y - 0.12, POLE_FACE), Vector3(0.02, 0.07, 0.02), Basis(), GALV, K_GALV)
	var tilt := Basis(Vector3(0.0, 0.0, 1.0), 0.3)
	g.lathe(cut - tilt.y * 0.16, cut + tilt.y * 0.16, [Vector2(0.025, 0.0), Vector2(0.04, 0.2), Vector2(0.027, 0.35), Vector2(0.04, 0.5),
		Vector2(0.027, 0.65), Vector2(0.04, 0.8), Vector2(0.025, 1.0)], 7, PORCELAIN_GREY, K_PORCELAIN)
	g.tube(cut + Vector3(0.03, -0.14, 0.05), cut + Vector3(-0.03, 0.15, 0.05), 0.016, 6, BLACK, K_BLACK, true)
	var arr := Vector3(-0.85, arm_y - 0.3, POLE_FACE + 0.06)
	g.lathe(arr - Vector3(0.0, 0.12, 0.0), arr + Vector3(0.0, 0.12, 0.0), [Vector2(0.03, 0.0), Vector2(0.045, 0.2), Vector2(0.03, 0.35),
		Vector2(0.045, 0.55), Vector2(0.03, 0.7), Vector2(0.045, 0.9), Vector2(0.03, 1.0)], 7, POLYMER, K_POLYMER, true, true)
	# Jumpers: primary pin -> cutout top, cutout bottom -> HV bushing, arrester -> cutout.
	var pin_top := Vector3(-PIN_SPREAD, arm_y + 0.2, POLE_FACE)
	var cut_top := cut + tilt.y * 0.17 + Vector3(0.0, 0.0, 0.05)
	var cut_bot := cut - tilt.y * 0.17 + Vector3(0.0, 0.0, 0.05)
	g.pipe([pin_top, pin_top.lerp(cut_top, 0.5) + Vector3(-0.05, 0.05, 0.0), cut_top], R_JUMPER, 4, BLACK, K_BLACK)
	g.pipe([cut_bot, cut_bot.lerp(hv + Vector3(0.0, 0.21, 0.0), 0.5) + Vector3(-0.08, -0.1, 0.0), hv + Vector3(0.0, 0.21, 0.0)], R_JUMPER, 4, BLACK, K_BLACK)
	g.pipe([arr + Vector3(0.0, 0.13, 0.0), cut_top.lerp(arr, 0.5) + Vector3(0.0, 0.1, 0.0), cut_top], R_JUMPER, 4, BLACK, K_BLACK)
	# LV leads to the spool.
	var spool := Vector3(0.0, SECONDARY_HEIGHT, POLE_FACE + 0.06)
	for i in 3:
		var bz := (float(i) - 1.0) * 0.12
		var b1 := c + Vector3(0.34, y1 - 0.2, bz)
		g.pipe([b1, b1 + Vector3(0.05, 0.08, 0.0), spool.lerp(b1, 0.4) + Vector3(0.0, 0.18, 0.0), spool + Vector3(0.0, 0.0, 0.03)], 0.009, 4, BLACK, K_BLACK)
	return g.commit()


static func _build_xfmr_shadow() -> Mesh:
	var g := Geo.new()
	g.lathe(Vector3(-0.5, 6.35, 0.0), Vector3(-0.5, 7.35, 0.0), [Vector2(0.27, 0.0), Vector2(0.27, 1.0)], 8, CAN, K_CAN, true, true)
	return g.commit(false)


## A cobra-head street light: the clamp on the street face, the upswept tubular arm, the
## luminaire (a tapered shell, the lens under it, the photocell on its back).
static func light_mesh() -> Mesh:
	return _cached("light", _build_light, _build_light_shadow)


static func _build_light() -> Mesh:
	var g := Geo.new()
	var y := LIGHT_HEIGHT
	var r := LIGHT_REACH
	g.box(Vector3(0.17, y - 0.38, 0.0), Vector3(0.02, 0.18, 0.07), Basis(), GALV, K_GALV)
	var path: Array = [Vector3(0.18, y - 0.45, 0.0), Vector3(0.45, y - 0.32, 0.0), Vector3(0.95, y - 0.14, 0.0),
		Vector3(1.55, y - 0.04, 0.0), Vector3(r, y, 0.0)]
	g.pipe(path, 0.03, 8, GALV, K_GALV)
	# A brace under the arm.
	g.pipe([Vector3(0.18, y - 0.9, 0.0), Vector3(0.9, y - 0.18, 0.0)], 0.012, 5, GALV, K_GALV)
	# The luminaire: elliptical sections along x, deepest a third of the way in.
	var sec := [[0.0, 0.05, 0.045], [0.06, 0.11, 0.075], [0.22, 0.165, 0.095], [0.45, 0.18, 0.09], [0.62, 0.15, 0.07], [0.72, 0.09, 0.045], [0.76, 0.0, 0.0]]
	var sides := 12
	var x0 := r - 0.05
	var rows: Array = []
	for k in sec.size():
		var s: Array = sec[k]
		var row: Array = []
		for i in sides + 1:
			var a := TAU * float(i) / float(sides)
			var wz := float(s[1]) * cos(a)
			var hy := float(s[2]) * sin(a)
			# The underside is flatter: the lens.
			if hy < 0.0:
				hy *= 0.45
			var p := Vector3(x0 + float(s[0]), y + 0.02 + hy, wz)
			var nn := Vector3(0.0, sin(a) / maxf(float(s[2]), 0.01), cos(a) / maxf(float(s[1]), 0.01)).normalized()
			var lens := sin(a) < -0.35 and k > 0 and k < sec.size() - 1
			row.append(g.vert(p, nn, Vector2(a * 0.1, float(s[0])), LENS if lens else LUMINAIRE, K_LENS if lens else K_CAN))
		rows.append(row)
	for k in sec.size() - 1:
		for i in sides:
			g.tri(rows[k][i], rows[k][i + 1], rows[k + 1][i + 1])
			g.tri(rows[k][i], rows[k + 1][i + 1], rows[k + 1][i])
	# Photocell.
	g.lathe(Vector3(x0 + 0.36, y + 0.1, 0.0), Vector3(x0 + 0.36, y + 0.16, 0.0), [Vector2(0.035, 0.0), Vector2(0.035, 0.7), Vector2(0.02, 1.0)], 8, BLACK, K_BLACK, false, true)
	return g.commit()


static func _build_light_shadow() -> Mesh:
	var g := Geo.new()
	g.tube(Vector3(0.18, LIGHT_HEIGHT - 0.4, 0.0), Vector3(LIGHT_REACH + 0.6, LIGHT_HEIGHT, 0.0), 0.08, 4, LUMINAIRE, K_CAN)
	return g.commit(false)


## A riser: a U-guard up the field side from the pavement, a conduit on to the secondary with a
## weatherhead, two stand-off brackets.
static func riser_mesh() -> Mesh:
	return _cached("riser", _build_riser)


static func _build_riser() -> Mesh:
	var g := Geo.new()
	var x := -0.2
	var zz := 0.09
	g.box(Vector3(x - 0.02, 1.5, zz), Vector3(0.035, 1.5, 0.05), Basis(), GALV, K_GALV)
	g.tube(Vector3(x - 0.02, 3.0, zz), Vector3(x - 0.02, SECONDARY_HEIGHT - 0.3, zz), 0.035, 8, GALV, K_GALV)
	for hy in [1.0, 2.2, 4.0, 5.6]:
		g.box(Vector3(x + 0.02, hy, zz), Vector3(0.03, 0.02, 0.06), Basis(), GALV, K_GALV)
	g.pipe([Vector3(x - 0.02, SECONDARY_HEIGHT - 0.3, zz), Vector3(x - 0.02, SECONDARY_HEIGHT - 0.12, zz), Vector3(x + 0.04, SECONDARY_HEIGHT - 0.05, zz + 0.05)], 0.04, 8, BLACK, K_BLACK)
	return g.commit()


## A splice case on a comm bundle: a black cylinder with tapered end caps and two strand hangers.
## Runs along +Z, centred.
static func splice_mesh() -> Mesh:
	return _cached("splice", _build_splice)


static func _build_splice() -> Mesh:
	var g := Geo.new()
	var l := 0.56
	g.lathe(Vector3(0.0, 0.0, -l * 0.5), Vector3(0.0, 0.0, l * 0.5),
		[Vector2(0.02, 0.0), Vector2(0.05, 0.06), Vector2(0.075, 0.12), Vector2(0.078, 0.2), Vector2(0.078, 0.8),
		Vector2(0.075, 0.88), Vector2(0.05, 0.94), Vector2(0.02, 1.0)], 10, BLACK, K_BLACK, true, true)
	for s in [-1.0, 1.0]:
		g.box(Vector3(0.0, 0.085, s * 0.18), Vector3(0.012, 0.03, 0.015), Basis(), GALV, K_GALV)
	return g.commit()


## A storage coil (a "snowshoe" of spare fibre) hung under the strand: a flat loop, along +Z.
static func coil_mesh() -> Mesh:
	return _cached("coil", _build_coil)


static func _build_coil() -> Mesh:
	var g := Geo.new()
	var pts: Array = []
	for i in 17:
		var a := TAU * float(i) / 16.0
		pts.append(Vector3(0.0, -0.32 - 0.3 * cos(a), 0.5 * sin(a)))
	g.pipe(pts, 0.022, 5, BLACK, K_BLACK)
	g.box(Vector3(0.0, -0.05, 0.0), Vector3(0.01, 0.05, 0.5), Basis(), BLACK, K_BLACK)
	return g.commit()


## A guy guard (the yellow sleeve over the guy's low end), along +Z, centred.
static func guard_mesh() -> Mesh:
	return _cached("guard", _build_guard)


static func _build_guard() -> Mesh:
	var g := Geo.new()
	g.lathe(Vector3(0.0, 0.0, -GUARD_LENGTH * 0.5), Vector3(0.0, 0.0, GUARD_LENGTH * 0.5),
		[Vector2(0.03, 0.0), Vector2(0.034, 0.02), Vector2(0.034, 0.98), Vector2(0.026, 1.0)], 8, GUARD, K_GUARD, true, true)
	return g.commit()


## The anchor rod coming out of the pavement with its eye, along +Z from the ground.
static func anchor_mesh() -> Mesh:
	return _cached("anchor", _build_anchor)


static func _build_anchor() -> Mesh:
	var g := Geo.new()
	g.tube(Vector3(0.0, 0.0, -0.3), Vector3(0.0, 0.0, 0.18), 0.012, 6, GALV, K_GALV)
	var pts: Array = []
	for i in 9:
		var a := TAU * float(i) / 8.0
		pts.append(Vector3(0.045 * sin(a), 0.0, 0.2 + 0.045 * cos(a)))
	g.pipe(pts, 0.01, 4, GALV, K_GALV)
	return g.commit()


## The house's meter: a grey can with its glass dome on a back plate. Faces +Z (out of the wall),
## origin at the dome's centre height on the wall.
static func meter_mesh() -> Mesh:
	return _cached("meter", _build_meter)


static func _build_meter() -> Mesh:
	var g := Geo.new()
	g.box(Vector3(0.0, -0.05, 0.06), Vector3(0.15, 0.27, 0.06), Basis(), METER_GREY, K_CAN)
	g.lathe(Vector3(0.0, 0.03, 0.12), Vector3(0.0, 0.03, 0.2), [Vector2(0.09, 0.0), Vector2(0.09, 0.6), Vector2(0.07, 0.9), Vector2(0.0, 1.0)], 10, GLASS, K_GLASS)
	g.lathe(Vector3(0.0, 0.03, 0.115), Vector3(0.0, 0.03, 0.13), [Vector2(0.1, 0.0), Vector2(0.1, 1.0)], 10, METER_GREY, K_CAN)
	# The conduit up to the mast and down into the wall.
	g.tube(Vector3(0.0, 0.22, 0.06), Vector3(0.0, 0.32, 0.06), 0.03, 8, GALV, K_GALV)
	return g.commit()


## A unit conduit (1 m up +Y), scaled per instance, on a stand-off at the bottom.
static func mast_mesh() -> Mesh:
	return _cached("mast", _build_mast)


static func _build_mast() -> Mesh:
	var g := Geo.new()
	g.tube(Vector3(0.0, 0.0, 0.06), Vector3(0.0, 1.0, 0.06), 0.03, 8, GALV, K_GALV)
	return g.commit()


## The weatherhead at a mast's top: a bent cap, its mouth toward +Z, and the insulator knob the
## drop is tied to under it. Origin at the mast's top.
static func weatherhead_mesh() -> Mesh:
	return _cached("whead", _build_whead)


static func _build_whead() -> Mesh:
	var g := Geo.new()
	g.pipe([Vector3(0.0, -0.02, 0.06), Vector3(0.0, 0.06, 0.06), Vector3(0.0, 0.11, 0.1), Vector3(0.0, 0.11, 0.15)], 0.042, 8, BLACK, K_BLACK)
	g.box(Vector3(0.0, -0.2, 0.1), Vector3(0.012, 0.015, 0.04), Basis(), GALV, K_GALV)
	g.lathe(Vector3(0.0, -0.23, 0.12), Vector3(0.0, -0.17, 0.12), [Vector2(0.02, 0.0), Vector2(0.03, 0.3), Vector2(0.02, 0.6), Vector2(0.025, 1.0)], 6, PORCELAIN_GREY, K_PORCELAIN)
	return g.commit()


## Builds every mesh now (the loading screen), and hands back the hardware's material for the
## loading screen to draw through a MultiMesh (the only way the chunks draw it).
static func warm() -> Array:
	if not enabled:
		return []
	shaft_mesh()
	head_mesh()
	transformer_mesh()
	light_mesh()
	riser_mesh()
	splice_mesh()
	coil_mesh()
	guard_mesh()
	anchor_mesh()
	meter_mesh()
	mast_mesh()
	weatherhead_mesh()
	return [material()]


static func _h01(parts: Array) -> float:
	return float(absi(hash(parts)) % 100000) / 100000.0
