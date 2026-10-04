class_name Airport
extends RefCounted
## The airport as a major international field (owner, 2026-10-04: "commercial jets taking off and
## landing at LAX ... like a real 2026 game"). Everything here is original - no airline, logo or
## sign of a real airport - but the FORMS are a real big field's: a parallel pair of runways with
## a parallel taxiway between them and the apron, a curving concourse of gates with jet bridges
## docked to parked airliners, a control tower, ground service equipment round every stand, and at
## night the blue and green taxiway lights, the white runway edges, the green and red ends and an
## approach light system with its sequenced flasher running in toward the threshold.
##
## This class is the LAYOUT (one table, all of it derived from MacroMap's airport numbers, so the
## chunks, the landmarks, the lights and the tests read the same places) plus what each airport
## chunk builds over its own rect (ground, paint, fixtures, masts, fences, the ground crews'
## vehicles - Airport.build_chunk(), from CityChunk._build_airport()) and the airfield's lights,
## ONE billboard mesh for the whole field on shaders/aircraft_lights.gdshader (lights_mesh(),
## worn by the always-present "airfield_lights" landmark), so a night flight reads the field
## from across the basin. The buildings are AirportTerminal; the small hardware AirportKit.
##
## Rolls: everything is a hash of the seed and the thing (gate, chunk, light), never a chunk's
## block rng, so nothing else in a chunk moves.
##
## Map frame: +X east, +Z south. The concourse is an arc convex toward the apron (south), the
## runways run east-west, arrivals land westbound on the south runway (27L), departures roll west
## on the north one (27R) - MacroMap.arrival_runway / departure_runway.

# --- Layout ------------------------------------------------------------------------------------

## The concourse is an arc round this centre (north of the field), CONCOURSE_RADIUS to its centre
## line, CONCOURSE_HALF either side of it: the apron face at R + HALF, the landside face at R - HALF.
const ARC_CENTRE := Vector2(-350.0, -330.0)
const CONCOURSE_RADIUS := 1030.0
const CONCOURSE_HALF := 11.0
## Its ends, as an angle either side of due south from the centre (x -575 .. -125).
const CONCOURSE_ARC := 0.2202
## Apron face to the concourse roof edge (two levels: apron and departures).
const CONCOURSE_HEIGHT := 14.0
## Gates along the apron face: how many, the arc length between them, how far off the face the
## parked airliner's nose stops, and the length that airliner is fitted to (Aircraft.AIRLINER).
const GATE_COUNT := 9
const GATE_PITCH := 46.0
const NOSE_GAP := 5.5
const JET_LENGTH := 38.0
## Half the wingspan the gate envelope is painted round (the model's span at JET_LENGTH is 32 m).
const ENVELOPE_HALF := 18.0
## The first gate's number (stands 11 .. 19).
const FIRST_GATE := 11
## The head house (check-in hall) between the drop-off curb and the concourse.
const HEAD_HOUSE := Rect2(-440.0, 636.0, 180.0, 54.0)
## The control tower's foot, the arch landmark's centre (landside east), the multi-storey car park
## (landside west) and the rental-car lot (landside east of the arch).
const TOWER_AT := Vector2(-236.0, 651.0)
const SKYHOOK_AT := Vector2(-160.0, 621.0)
const GARAGE_RECT := Rect2(-632.0, 597.0, 124.0, 46.0)
const RENTAL_RECT := Rect2(-104.0, 597.0, 196.0, 58.0)
## The airside fence's landside runs (z), either side of the terminal.
const FENCE_WEST_Z := 652.0
const FENCE_EAST_Z := 664.0
## Cross taxiways from the parallel taxiway to both runways (x of their centre lines) and width.
const CONNECTOR_XS := [-612.0, -330.0, -40.0]
const CONNECTOR_WIDTH := 23.0
## Runway ends are this far in from the airport rect; the north runway stops short of the hangars.
const RUNWAY_END_INSET := 6.0
const HANGAR_WEST_X := 0.0
## The approach light system off the arrival threshold: stations every APPROACH_STEP metres out to
## APPROACH_LENGTH, a crossbar at APPROACH_BAR, each station a bar of five lamps.
const APPROACH_LENGTH := 450.0
const APPROACH_STEP := 30.0
const APPROACH_BAR := 300.0
## Surface tops (the base apron slab is MacroMap.tarmac_top, 0.1). AirTraffic's runway_top is
## tarmac_top + 0.04, so the runway top sits a centimetre under the wheels.
const GRASS_TOP := 0.112
const TAXI_TOP := 0.118
const CONNECTOR_TOP := 0.122
const RUNWAY_TOP := 0.13
## Apron floodlight masts: height, and the lamps on the head.
const MAST_HEIGHT := 28.0
## Livery count (shaders/airliner_livery.gdshader's table).
const LIVERIES := 6

## Paint colours (instance colours on the "stripe" batch: road_paint.gdshader multiplies them).
const YELLOW := Color(0.98, 0.74, 0.12)
const WHITE := Color(0.96, 0.96, 0.93)
const RED := Color(0.78, 0.12, 0.08)
const RUBBER := Color(0.05, 0.05, 0.05)
## Light colours (aircraft_lights.gdshader: rgb, a = strength).
const L_BLUE := Color(0.18, 0.38, 1.0, 1.0)
const L_GREEN := Color(0.20, 1.0, 0.42, 1.0)
const L_WHITE := Color(1.0, 0.93, 0.78, 1.0)
const L_YELLOW := Color(1.0, 0.72, 0.20, 1.0)
const L_RED := Color(1.0, 0.10, 0.06, 1.0)
const L_FLOOD := Color(1.0, 0.86, 0.62, 1.0)
## aircraft_lights.gdshader kinds.
const K_STEADY := 0
const K_BEACON := 2
const K_FIELD := 4
const K_RABBIT := 5
const K_ROTATE := 6
const K_PAPI := 7

static var _gates: Array[Dictionary] = []
static var _lights: ArrayMesh = null
static var _light_mat: ShaderMaterial = null


## A point on the concourse arc at angle `a` (0 due south of the centre) and radius `r`.
static func arc_point(a: float, r: float) -> Vector2:
	return ARC_CENTRE + Vector2(sin(a), cos(a)) * r


## The arc's outward normal (toward the apron) and its tangent (toward +X) at angle `a`.
static func arc_normal(a: float) -> Vector2:
	return Vector2(sin(a), cos(a))


static func arc_tangent(a: float) -> Vector2:
	return Vector2(cos(a), -sin(a))


static func apron_face() -> float:
	return CONCOURSE_RADIUS + CONCOURSE_HALF


## The angle on the arc of a world x (the concourse's own frame).
static func angle_at_x(x: float, r: float) -> float:
	return asin(clampf((x - ARC_CENTRE.x) / r, -1.0, 1.0))


## Every gate, west to east: its number, angle, the stand's frame and the parked airliner on it.
## {number, a, n (Vector2, toward the apron), t (Vector2, toward +X), nose (Vector2), centre
## (Vector2), yaw (the jet's yaw: nose toward the building), door (Vector3, the forward left door),
## rotunda (Vector2, the jet bridge's pivot), livery, service (0..3, which trucks attend it)}.
static func gates() -> Array[Dictionary]:
	if not _gates.is_empty():
		return _gates
	var rf := apron_face()
	for i in GATE_COUNT:
		var s := (float(i) - float(GATE_COUNT - 1) * 0.5) * GATE_PITCH
		var a := s / rf
		var n := arc_normal(a)
		var t := arc_tangent(a)
		var nose := arc_point(a, rf + NOSE_GAP)
		var centre := nose + n * (JET_LENGTH * 0.5)
		# The jet's left (port) side, seen from the cockpit with the nose toward the building, is
		# toward -t; the forward door is 5.5 m behind the nose, the fuselage 2 m round.
		var door2 := nose + n * 5.6 - t * 2.15
		var h := hash([i, "gate"])
		_gates.append({
			"number": str(FIRST_GATE + i), "a": a, "n": n, "t": t, "nose": nose, "centre": centre,
			"yaw": a, "door": Vector3(door2.x, 3.9, door2.y),
			"rotunda": arc_point(a, rf + 3.2) - t * 9.0,
			"livery": h % LIVERIES, "service": (h >> 8) % 4, "empty": i == 6,
		})
	return _gates


## Where the parked jets' envelopes are, for anything that must keep out of them (world XZ).
static func near_gate(p: Vector2, margin: float = 0.0) -> bool:
	for g in gates():
		var d: Vector2 = p - (g.centre as Vector2)
		var along := d.dot(g.n)
		var across := d.dot(g.t)
		if absf(along) < JET_LENGTH * 0.5 + 4.0 + margin and absf(across) < ENVELOPE_HALF + margin:
			return true
	return false


## The runways: [z, x0, x1, west designator, east designator] per runway in MacroMap.runway_zs.
static func runways(macro: MacroMap) -> Array:
	var out: Array = []
	var rect := macro.airport_rect
	var names := [["09L", "27R"], ["09R", "27L"]]
	for i in macro.runway_zs.size():
		var z: float = macro.runway_zs[i]
		var x1 := rect.end.x - RUNWAY_END_INSET
		if z - macro.runway_width * 0.5 < 900.0:
			# The north runway ends short of the hangars that stand across its east end.
			x1 = HANGAR_WEST_X - RUNWAY_END_INSET
		var nm: Array = names[mini(i, names.size() - 1)]
		out.append([z, rect.position.x + RUNWAY_END_INSET, x1, nm[0], nm[1]])
	return out


## The parallel taxiway's x range.
static func taxiway_x(macro: MacroMap) -> Vector2:
	return Vector2(macro.airport_rect.position.x + 10.0, HANGAR_WEST_X - 6.0)


## The grass between the taxiway and the north runway, and between the runways, less the cross
## taxiways (world rects).
static func grass_rects(macro: MacroMap) -> Array[Rect2]:
	var out: Array[Rect2] = []
	var rect := macro.airport_rect
	var hw := macro.runway_width * 0.5
	var shoulder := 6.5
	var bands: Array = [
		[macro.taxiway_z + macro.taxiway_width * 0.5 + shoulder, macro.runway_zs[0] - hw - shoulder, HANGAR_WEST_X - 6.0],
	]
	if macro.runway_zs.size() > 1:
		bands.append([macro.runway_zs[0] + hw + shoulder, macro.runway_zs[1] - hw - shoulder, rect.end.x - 4.0])
	for band: Array in bands:
		var x := rect.position.x + 4.0
		var xs: Array = CONNECTOR_XS.duplicate()
		xs.append(float(band[2]) + CONNECTOR_WIDTH * 0.5 + shoulder)
		for cx: float in xs:
			var x_end := cx - CONNECTOR_WIDTH * 0.5 - shoulder
			if x_end - x > 4.0:
				out.append(Rect2(x, band[0], x_end - x, float(band[1]) - float(band[0])))
			x = cx + CONNECTOR_WIDTH * 0.5 + shoulder
	return out


# --- Materials ----------------------------------------------------------------------------------

## Apron concrete: pale poured slabs on 7.5 m joints, worn and stained (road.gdshader).
static func apron_material(seed_value: int) -> ShaderMaterial:
	return PropFactory.road("concrete", 6.0, Color(0.64, 0.64, 0.62), seed_value, 7.5, 0.55)


## Runway and taxiway asphalt: darker, grooved-looking, wear and patches.
static func runway_material(seed_value: int) -> ShaderMaterial:
	return PropFactory.road("asphalt", 9.0, Color(0.52, 0.52, 0.54), seed_value, 0.0, 0.9)


static func taxiway_material(seed_value: int) -> ShaderMaterial:
	return PropFactory.road("asphalt", 8.0, Color(0.6, 0.6, 0.62), seed_value, 0.0, 0.8)


## The infield: dry LA grass, mown in stripes (lawn.gdshader, very dry).
static func grass_material() -> ShaderMaterial:
	return PropFactory.lawn(Color(0.74, 0.70, 0.52), 4821, 0.85, 9.0)


const GRASS_COLOR := Color(0.47, 0.45, 0.30)


# --- What a chunk builds ------------------------------------------------------------------------

## The airport over one chunk's owned rect: ground (also in the far city's capture), then at LOD
## and FULL the masts, fences and big hardware, and at FULL the paint, the light fixtures and the
## ground crews' vehicles round the gates in it.
static func build_chunk(ch: CityChunk) -> void:
	var area := ch.owned_rect()
	var macro: MacroMap = ch.plan.macro
	var seed_value: int = ch.plan.seed
	var full := ch.level == CityChunk.Level.FULL
	var c := area.get_center()
	ch._add_slab(Vector3(c.x, 0.05, c.y), Vector3(area.size.x, 0.1, area.size.y), ch.style.tarmac, full,
		apron_material(hash([seed_value, ch.ix, ch.iz, "lot"])))
	# The parallel taxiway, the cross taxiways, the grass, then the runways on top.
	var tx := taxiway_x(macro)
	_ground(ch, area, Rect2(tx.x, macro.taxiway_z - macro.taxiway_width * 0.5, tx.y - tx.x, macro.taxiway_width), TAXI_TOP,
		ch.style.runway, taxiway_material(hash([seed_value, "taxi"])))
	var south: float = macro.runway_zs[macro.runway_zs.size() - 1] - macro.runway_width * 0.5
	for cx: float in CONNECTOR_XS:
		_ground(ch, area, Rect2(cx - CONNECTOR_WIDTH * 0.5, macro.taxiway_z, CONNECTOR_WIDTH, south - macro.taxiway_z + 2.0), CONNECTOR_TOP,
			ch.style.runway, taxiway_material(hash([seed_value, "taxi"])))
	for g in grass_rects(macro):
		_ground(ch, area, g, GRASS_TOP, GRASS_COLOR, grass_material())
	for rw: Array in runways(macro):
		var z: float = rw[0]
		_ground(ch, area, Rect2(float(rw[1]), z - macro.runway_width * 0.5, float(rw[2]) - float(rw[1]), macro.runway_width), RUNWAY_TOP,
			ch.style.runway, runway_material(hash([seed_value, "runway", z])))
	if ch.capturing:
		return
	_masts(ch, area, macro)
	_fences(ch, area, macro)
	_navaids(ch, area, macro)
	if not full:
		return
	_paint_runways(ch, area, macro)
	_paint_taxiways(ch, area, macro)
	_paint_apron(ch, area, macro)
	_fixtures(ch, area, macro)
	_gate_service(ch, area, seed_value)


## A ground slab clipped to the chunk (thin: merged into the chunk's boxes, and recorded by the
## far city's capture with its far colour).
static func _ground(ch: CityChunk, area: Rect2, r: Rect2, top: float, color: Color, mat: Material) -> void:
	var clip := r.intersection(area)
	if clip.size.x <= 0.05 or clip.size.y <= 0.05:
		return
	var cc := clip.get_center()
	var thick := top - 0.1 + 0.004
	ch._add_slab(Vector3(cc.x, top - thick * 0.5, cc.y), Vector3(clip.size.x, thick, clip.size.y), color, false, mat)


## A painted line from `a` to `b` (world XZ) on a surface whose top is `top`, `width` wide, only the
## part inside the chunk: the stripe batch's 0.6 x 3 m box scaled to it.
static func _line(ch: CityChunk, area: Rect2, a: Vector2, b: Vector2, width: float, top: float, col: Color) -> void:
	var d := b - a
	var length := d.length()
	if length < 0.05:
		return
	# Clip to the chunk along the line (the parts are straight, so a parametric clip is exact).
	var t0 := 0.0
	var t1 := 1.0
	for axis in 2:
		var p0: float = a[axis]
		var dd: float = d[axis]
		var lo: float = area.position[axis]
		var hi: float = area.end[axis]
		if absf(dd) < 1e-6:
			if p0 < lo or p0 >= hi:
				return
			continue
		var ta := (lo - p0) / dd
		var tb := (hi - p0) / dd
		t0 = maxf(t0, minf(ta, tb))
		t1 = minf(t1, maxf(ta, tb))
	if t1 - t0 < 1e-4:
		return
	var pa := a + d * t0
	var pb := a + d * t1
	var mid := (pa + pb) * 0.5
	var seg := length * (t1 - t0)
	var yaw := atan2(d.x, d.y)
	ch._batch.add("stripe", PropFactory.stripe(), Transform3D(Basis(Vector3.UP, yaw).scaled_local(Vector3(width / 0.6, 1.0, seg / 3.0)),
		Vector3(mid.x, top + 0.002, mid.y)), col)


## A dashed line: `dash` painted, `gap` bare.
static func _dashes(ch: CityChunk, area: Rect2, a: Vector2, b: Vector2, width: float, top: float, col: Color, dash: float, gap: float) -> void:
	var d := b - a
	var length := d.length()
	if length < 0.05:
		return
	var dir := d / length
	var s := 0.0
	while s < length:
		_line(ch, area, a + dir * s, a + dir * minf(s + dash, length), width, top, col)
		s += dash + gap


## A painted arc round the concourse centre at radius `r`, from angle a0 to a1, in 4 m pieces.
static func _arc_line(ch: CityChunk, area: Rect2, r: float, a0: float, a1: float, width: float, top: float, col: Color, dash: float = 0.0) -> void:
	var n := maxi(1, ceili(absf(a1 - a0) * r / 4.0))
	for i in n:
		if dash > 0.0 and i % 2 == 1:
			continue
		var pa := arc_point(lerpf(a0, a1, float(i) / float(n)), r)
		var pb := arc_point(lerpf(a0, a1, float(i + 1) / float(n)), r)
		if dash > 0.0:
			pb = pa + (pb - pa).normalized() * minf(dash, pa.distance_to(pb))
		_line(ch, area, pa, pb, width, top, col)


## Flat painted text (runway designators, stand numbers): one TextMesh laid face up, reading along
## `right` with its top toward `up` (unit XZ). Only the chunk that owns its centre builds it.
static func _paint_text(ch: CityChunk, area: Rect2, text: String, at: Vector2, right: Vector2, up: Vector2, height: float, top: float, col: Color) -> void:
	if not area.has_point(at):
		return
	var mi := MeshInstance3D.new()
	mi.name = "Paint_" + text
	mi.mesh = PropFactory.text_mesh(text, height)
	mi.material_override = PropFactory.material(col, 0.85)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.transform = Transform3D(Basis(Vector3(right.x, 0.0, right.y), Vector3(up.x, 0.0, up.y), Vector3.UP), Vector3(at.x, top + 0.006, at.y))
	mi.visibility_range_end = 900.0
	ch.add_child(mi)


static func _paint_runways(ch: CityChunk, area: Rect2, macro: MacroMap) -> void:
	var hw := macro.runway_width * 0.5
	var top := RUNWAY_TOP
	for rw: Array in runways(macro):
		var z: float = rw[0]
		var x0: float = rw[1]
		var x1: float = rw[2]
		# Edge lines and the centre line.
		for side: float in [-1.0, 1.0]:
			_line(ch, area, Vector2(x0, z + side * (hw - 0.9)), Vector2(x1, z + side * (hw - 0.9)), 0.9, top, WHITE)
		_dashes(ch, area, Vector2(x0 + 72.0, z), Vector2(x1 - 72.0, z), 0.9, top, WHITE, 30.0, 20.0)
		# Each end: threshold bars, the designator, touchdown zone and aiming point markings.
		for end in 2:
			var x_end := x0 if end == 0 else x1
			var inward := 1.0 if end == 0 else -1.0
			for k in 6:
				for side: float in [-1.0, 1.0]:
					var lz := z + side * (2.6 + float(k) * 3.2)
					_line(ch, area, Vector2(x_end + inward * 6.0, lz), Vector2(x_end + inward * 36.0, lz), 1.8, top, WHITE)
			var name: String = rw[3] if end == 0 else rw[4]
			# Read by a pilot landing over this end: the top of the figures points down the runway,
			# and they read toward the pilot's right.
			_paint_text(ch, area, name, Vector2(x_end + inward * 58.0, z), Vector2(0.0, inward), Vector2(inward, 0.0), 15.0, top, WHITE)
			for zone: Array in [[96.0, 3], [226.0, 2], [292.0, 1]]:
				for side: float in [-1.0, 1.0]:
					for k in int(zone[1]):
						var lz := z + side * (6.0 + float(k) * 2.6)
						_line(ch, area, Vector2(x_end + inward * float(zone[0]), lz), Vector2(x_end + inward * (float(zone[0]) + 22.0), lz), 1.8, top, WHITE)
			for side: float in [-1.0, 1.0]:
				_line(ch, area, Vector2(x_end + inward * 140.0, z + side * 9.0), Vector2(x_end + inward * 182.0, z + side * 9.0), 6.0, top, WHITE)
		# Rubber on the touchdown zone of the arrival end (east of the south runway; both ends of
		# the north one get a little from the occasional landing the other way).
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(["rubber", z])
		var arrivals := absf(z - float(macro.runway_zs[macro.arrival_runway])) < 1.0
		var streaks := 70 if arrivals else 18
		for i in streaks:
			var from_end := rng.randf_range(60.0, 420.0) if arrivals else rng.randf_range(80.0, 300.0)
			var x := x1 - from_end if arrivals or rng.randf() < 0.5 else x0 + from_end
			var lz := z + (3.6 if rng.randf() < 0.5 else -3.6) + rng.randf_range(-1.4, 1.4)
			if rng.randf() < 0.18:
				lz = z + rng.randf_range(-0.6, 0.6)
			var length := rng.randf_range(8.0, 34.0)
			_line(ch, area, Vector2(x - length * 0.5, lz), Vector2(x + length * 0.5, lz + rng.randf_range(-0.3, 0.3)), rng.randf_range(0.25, 0.55), top - 0.001, RUBBER)


static func _paint_taxiways(ch: CityChunk, area: Rect2, macro: MacroMap) -> void:
	var tz := macro.taxiway_z
	var tx := taxiway_x(macro)
	var top := TAXI_TOP
	# Centre line, and the edge (two thin lines) on the grass side.
	_line(ch, area, Vector2(tx.x + 4.0, tz), Vector2(tx.y - 4.0, tz), 0.16, top, YELLOW)
	for off: float in [-0.12, 0.22]:
		var ez := tz + macro.taxiway_width * 0.5 - 0.6 + off
		var x := tx.x + 2.0
		for cx: float in CONNECTOR_XS:
			_line(ch, area, Vector2(x, ez), Vector2(cx - CONNECTOR_WIDTH * 0.5 - 2.0, ez), 0.14, top, YELLOW)
			x = cx + CONNECTOR_WIDTH * 0.5 + 2.0
		_line(ch, area, Vector2(x, ez), Vector2(tx.y - 2.0, ez), 0.14, top, YELLOW)
	var hw := macro.runway_width * 0.5
	for cx: float in CONNECTOR_XS:
		# Lead-off curves from the taxiway centre line into the connector, both ways.
		for side: float in [-1.0, 1.0]:
			var r := 22.0
			var c := Vector2(cx + side * r, tz + r)
			var prev := Vector2(cx + side * r, tz)
			for k in range(1, 9):
				var ang := float(k) / 8.0 * PI * 0.5
				var p := c + Vector2(-side * sin(ang), -cos(ang)) * r
				_line(ch, area, prev, p, 0.16, CONNECTOR_TOP, YELLOW)
				prev = p
		# The connector's centre line from the taxiway to the far runway, stopping on each runway
		# (runway paint is white; a taxiway line across a runway is not).
		var z0 := tz + 22.0
		for i in macro.runway_zs.size():
			var rz: float = macro.runway_zs[i]
			_line(ch, area, Vector2(cx, z0), Vector2(cx, rz - hw - 0.5), 0.16, CONNECTOR_TOP, YELLOW)
			# Hold-short: two solid and two dashed lines across the connector, solid side toward
			# the taxiway, 20 m short of the runway edge.
			var hz := rz - hw - 20.0
			for k in 4:
				var lz := hz + float(k) * 0.45
				if k < 2:
					_line(ch, area, Vector2(cx - CONNECTOR_WIDTH * 0.5 + 0.8, lz), Vector2(cx + CONNECTOR_WIDTH * 0.5 - 0.8, lz), 0.22, CONNECTOR_TOP, YELLOW)
				else:
					_dashes(ch, area, Vector2(cx - CONNECTOR_WIDTH * 0.5 + 0.8, lz), Vector2(cx + CONNECTOR_WIDTH * 0.5 - 0.8, lz), 0.22, CONNECTOR_TOP, YELLOW, 0.9, 0.9)
			z0 = rz + hw + 0.5


static func _paint_apron(ch: CityChunk, area: Rect2, macro: MacroMap) -> void:
	var top: float = macro.tarmac_top
	var rf := apron_face()
	var tz := macro.taxiway_z - macro.taxiway_width * 0.5
	for g in gates():
		var a: float = g.a
		var n: Vector2 = g.n
		var t: Vector2 = g.t
		var nose: Vector2 = g.nose
		# Lead-in line from the taxiway edge to the nose stop, and the stop bar across it.
		var out := nose + n * ((tz - 1.0 - nose.y) / maxf(n.y, 0.2))
		_line(ch, area, out, nose - n * 1.5, 0.16, top, YELLOW)
		_line(ch, area, nose - n * 1.5 - t * 2.2, nose - n * 1.5 + t * 2.2, 0.3, top, YELLOW)
		# Stand number, read from the taxiway looking at the building.
		_paint_text(ch, area, g.number, nose + n * 46.0, Vector2(n.y, -n.x), -n, 2.8, top, YELLOW)
		# The equipment restraint envelope: red lines either side of the wings and behind the tail.
		for side: float in [-1.0, 1.0]:
			_line(ch, area, arc_point(a, rf + 0.5) + t * side * ENVELOPE_HALF, arc_point(a, rf + 45.0) + t * side * ENVELOPE_HALF, 0.15, top, RED)
		_line(ch, area, arc_point(a, rf + 45.0) - t * ENVELOPE_HALF, arc_point(a, rf + 45.0) + t * ENVELOPE_HALF, 0.15, top, RED)
		# Hatched no-parking box where the jet bridge swings.
		var rot: Vector2 = g.rotunda
		for k in 5:
			var p := rot + n * (2.0 + float(k) * 1.6) - t * 2.5
			_line(ch, area, p, p + t * 5.0 + n * 1.2, 0.12, top, RED)
	# The service road behind the tails: a white edge line and a dashed centre line.
	var a0 := -CONCOURSE_ARC
	var a1 := CONCOURSE_ARC
	_arc_line(ch, area, rf + 47.0, a0, a1, 0.15, top, WHITE)
	_arc_line(ch, area, rf + 51.5, a0, a1, 0.15, top, WHITE, 3.0)
	# A white line along the apron face: the edge of the vehicle lane under the jet bridges.
	_arc_line(ch, area, rf + 0.6, a0, a1, 0.15, top, WHITE)
	# The remote stands either end: a lead-in line and a stop bar each.
	for spot: Array in macro.apron_spots:
		var p: Vector2 = spot[0]
		if absf(p.y - macro.taxiway_z) < 2.0:
			continue
		var yaw: float = spot[2] if spot.size() > 2 else -PI * 0.5
		var fwd := Vector2(-sin(yaw), -cos(yaw))
		_line(ch, area, p - fwd * 30.0, p + fwd * 18.0, 0.16, top, YELLOW)
		_line(ch, area, p + fwd * 18.0 - Vector2(fwd.y, -fwd.x) * 2.2, p + fwd * 18.0 + Vector2(fwd.y, -fwd.x) * 2.2, 0.3, top, YELLOW)


# --- Hardware a chunk builds --------------------------------------------------------------------

## Apron floodlight masts between the gates (behind the wings) and by the remote stands, each
## [position, facing (unit XZ, where its floods point)], with their light on the concrete after
## dark. FULL and LOD (they stand 28 m tall).
static func mast_spots(macro: MacroMap) -> Array:
	var out: Array = []
	var rf := apron_face()
	var gs := gates()
	for i in gs.size() + 1:
		var a: float
		if i == 0:
			a = float(gs[0].a) - GATE_PITCH * 0.5 / rf
		elif i == gs.size():
			a = float(gs[gs.size() - 1].a) + GATE_PITCH * 0.5 / rf
		else:
			a = (float(gs[i - 1].a) + float(gs[i].a)) * 0.5
		out.append([arc_point(a, rf + 36.0), -arc_normal(a)])
	for spot: Array in macro.apron_spots:
		var p: Vector2 = spot[0]
		if absf(p.y - macro.taxiway_z) > 2.0:
			out.append([p + Vector2(0.0, -30.0), Vector2(0.0, 1.0)])
	return out


static func _masts(ch: CityChunk, area: Rect2, macro: MacroMap) -> void:
	var y: float = macro.tarmac_top
	for spot: Array in mast_spots(macro):
		var p: Vector2 = spot[0]
		if not area.has_point(p):
			continue
		var fwd: Vector2 = spot[1]
		ch._batch.add("ap_mast", AirportKit.mast(), Transform3D(Basis(Vector3.UP, atan2(-fwd.x, -fwd.y)), Vector3(p.x, y, p.y)))
		# The pool on the concrete, out in front of the floods.
		var pool_at := p + fwd * 14.0
		ch._batch.add("ap_pool", PropFactory.light_pool(Color(1.0, 0.88, 0.66), 0.9, 1.6),
			Transform3D(Basis(Vector3.RIGHT, -PI * 0.5).scaled(Vector3(80.0, 80.0, 1.0)), Vector3(pool_at.x, y + 0.05, pool_at.y)))
	ch._batch.set_no_shadow("ap_pool")


## The perimeter fence (west, south and east edges) and the airside line either side of the
## terminal; FULL and LOD. Gaps where the hangars and the landside stand on the line.
static func _fences(ch: CityChunk, area: Rect2, macro: MacroMap) -> void:
	var r := macro.airport_rect
	var y: float = macro.tarmac_top
	var runs: Array = [
		[Vector2(r.position.x + 1.5, FENCE_WEST_Z), Vector2(r.position.x + 1.5, r.end.y - 1.5)],
		[Vector2(r.position.x + 1.5, r.end.y - 1.5), Vector2(r.end.x - 1.5, r.end.y - 1.5)],
		[Vector2(r.end.x - 1.5, FENCE_EAST_Z), Vector2(r.end.x - 1.5, r.end.y - 1.5)],
		[Vector2(r.position.x + 1.5, FENCE_WEST_Z), Vector2(HEAD_HOUSE.position.x, FENCE_WEST_Z)],
		[Vector2(HEAD_HOUSE.end.x, FENCE_EAST_Z), Vector2(r.end.x - 1.5, FENCE_EAST_Z)],
	]
	for run: Array in runs:
		var a: Vector2 = run[0]
		var b: Vector2 = run[1]
		var length := a.distance_to(b)
		var dir := (b - a) / length
		var n := maxi(1, ceili(length / AirportKit.FENCE_BAY))
		var bay := length / float(n)
		var yaw := atan2(-dir.y, dir.x)
		for i in n:
			var p := a + dir * ((float(i) + 0.5) * bay)
			if not area.has_point(p):
				continue
			ch._batch.add("ap_fence", AirportKit.fence_panel(), Transform3D(Basis(Vector3.UP, yaw).scaled_local(Vector3(bay, 1.0, 1.0)), Vector3(p.x, y, p.y)))
			var q := a + dir * (float(i) * bay)
			ch._batch.add("ap_fence_post", AirportKit.fence_post(), Transform3D(Basis(Vector3.UP, yaw), Vector3(q.x, y, q.y)))
	ch._batch.set_no_shadow("ap_fence")
	ch._batch.set_shadow_distance("ap_fence_post", 60.0)


## Blast fences behind the runway ends, the localizer array past the arrival runway's far end, the
## glide-slope mast beside its touchdown zone, windsocks, and the PAPI units. FULL and LOD.
static func _navaids(ch: CityChunk, area: Rect2, macro: MacroMap) -> void:
	var y: float = macro.tarmac_top
	var hw := macro.runway_width * 0.5
	var rws := runways(macro)
	var arr: Array = rws[macro.arrival_runway]
	var az: float = arr[0]
	# Blast fence west of both runways (the beach road behind it) and east of the arrival runway.
	for rw: Array in rws:
		var z: float = rw[0]
		_blast_fence(ch, area, Vector2(macro.airport_rect.position.x + 3.0, z), PI * 0.5, 9)
	_blast_fence(ch, area, Vector2(macro.airport_rect.end.x - 3.0, az - 6.0), -PI * 0.5, 6)
	# Localizer: a row of antennas across the arrival runway's centre line past its stop end.
	var lx := float(arr[1]) - 1.5
	for k in 14:
		var p := Vector2(lx + 1.0, az + (float(k) - 6.5) * 2.4)
		if area.has_point(p):
			ch._batch.add("ap_ils", AirportKit.localizer(), Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(p.x, y, p.y)))
	# Glide slope beside the touchdown point (the aim point is AirTraffic.aim_inset in from the end).
	var gs := Vector2(float(arr[2]) - 170.0, az - hw - 46.0)
	if area.has_point(gs):
		ch._batch.add("ap_gs", AirportKit.glide_slope(), Transform3D(Basis(), Vector3(gs.x, y, gs.y)))
	# Windsocks by both runways' touchdown zones, on the grass.
	for p: Vector2 in windsock_spots(macro):
		if area.has_point(p):
			ch._batch.add("ap_sock", AirportKit.windsock(), Transform3D(Basis(Vector3.UP, -0.5), Vector3(p.x, y, p.y)))
	# PAPI boxes, left of each runway's landing end.
	for spot: Array in papi_spots(macro):
		var p: Vector2 = spot[0]
		if area.has_point(p):
			ch._batch.add("ap_papi", AirportKit.papi(), Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(p.x, y, p.y)))


static func windsock_spots(macro: MacroMap) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var hw := macro.runway_width * 0.5
	for rw: Array in runways(macro):
		out.append(Vector2(float(rw[2]) - 300.0, float(rw[0]) - hw - 16.0))
	return out


## Four PAPI units a runway, on the left of a pilot landing west (the south side), beside the aim
## point: [position, transition angle].
static func papi_spots(macro: MacroMap) -> Array:
	var out: Array = []
	var hw := macro.runway_width * 0.5
	var arr: Array = runways(macro)[macro.arrival_runway]
	for k in 4:
		out.append([Vector2(float(arr[2]) - 175.0, float(arr[0]) + hw + 12.0 + float(k) * 9.0), 2.5 + float(k) * 0.33])
	return out


static func _blast_fence(ch: CityChunk, area: Rect2, at: Vector2, yaw: float, panels: int) -> void:
	var dir := Vector2(cos(yaw), -sin(yaw))
	for k in panels:
		var p := at + dir * ((float(k) - float(panels - 1) * 0.5) * AirportKit.BLAST_PANEL)
		if area.has_point(p):
			ch._batch.add("ap_blast", AirportKit.blast_fence(), Transform3D(Basis(Vector3.UP, yaw), Vector3(p.x, 0.1, p.y)))


## The fixtures under the field's lights: runway edge housings, blue taxiway edge domes, inset
## centre-line lights (FULL only; the light itself is in lights_mesh()).
static func _fixtures(ch: CityChunk, area: Rect2, macro: MacroMap) -> void:
	for spec: Array in _field_light_specs(macro):
		var p: Vector3 = spec[0]
		if not area.has_point(Vector2(p.x, p.z)):
			continue
		match int(spec[5]):
			1:
				ch._batch.add("ap_edge", AirportKit.edge_light(), Transform3D(Basis(), Vector3(p.x, 0.1, p.z)), Color.WHITE, Color(0.9, 0.88, 0.8, 1.0))
			2:
				ch._batch.add("ap_edge", AirportKit.edge_light(), Transform3D(Basis(), Vector3(p.x, 0.1, p.z)), Color.WHITE, Color(0.05, 0.12, 0.6, 1.0))
			3:
				ch._batch.add("ap_inset", AirportKit.inset_light(), Transform3D(Basis(), Vector3(p.x, p.y - 0.02, p.z)))
	ch._batch.set_no_shadow("ap_inset")
	ch._batch.set_shadow_distance("ap_edge", 30.0)


## The ground crews' equipment round each gate whose stand lies in the chunk: a pushback tug at
## the nose, a belt loader at the forward hold, a baggage tug with its train of carts, a catering
## truck lifted to the rear door, a fuel truck under the wing, a power unit and cones. Which of the
## trucks attend a gate is its `service` roll; the positions are the stand's own frame.
static func _gate_service(ch: CityChunk, area: Rect2, seed_value: int) -> void:
	var y := 0.1
	for g in gates():
		var centre: Vector2 = g.centre
		if not area.has_point(centre):
			continue
		var rng := RandomNumberGenerator.new()
		rng.seed = hash([seed_value, "gate", g.number])
		var n: Vector2 = g.n
		var t: Vector2 = g.t
		var nose: Vector2 = g.nose
		# Stand frame: `along` metres from the nose toward the tail, `side` to the jet's right (+t).
		var at := func(along: float, side: float) -> Vector3:
			var p := nose + n * along + t * side
			return Vector3(p.x, y, p.y)
		var face := func(dir_n: float, dir_t: float) -> Basis:
			var d := n * dir_n + t * dir_t
			return Basis(Vector3.UP, atan2(-d.x, -d.y))
		var service: int = g.service
		if bool(g.empty):
			# An empty stand waiting for its next arrival: the bridge parked back, the tug waiting.
			ch._batch.add("ap_tug", AirportKit.vehicle("pushback"), Transform3D(face.call(1.0, 0.0), at.call(-1.0, 6.0)), Color.WHITE, AirportKit.livery_white())
			continue
		ch._batch.add("ap_tug", AirportKit.vehicle("pushback"), Transform3D(face.call(1.0, 0.0), at.call(2.2, rng.randf_range(-0.3, 0.3))), Color.WHITE, AirportKit.livery_white())
		ch._batch.add("ap_gpu", AirportKit.vehicle("gpu"), Transform3D(face.call(0.0, 1.0), at.call(3.0, 4.2)))
		ch._batch.add("ap_belt", AirportKit.vehicle("belt_loader"), Transform3D(face.call(0.3, -1.0), at.call(9.0, 5.4)), Color.WHITE, AirportKit.livery_yellow())
		# The baggage train: a tug and three to four carts in a line along the side of the jet.
		var carts := 3 + rng.randi() % 2
		ch._batch.add("ap_bagtug", AirportKit.vehicle("baggage_tug"), Transform3D(face.call(-1.0, 0.0), at.call(10.5, 8.6)), Color.WHITE, AirportKit.livery_yellow())
		for k in carts:
			ch._batch.add("ap_cart", AirportKit.vehicle("cart"), Transform3D(face.call(-1.0, 0.0), at.call(14.4 + float(k) * 3.9, 8.6 + rng.randf_range(-0.15, 0.15))),
				Color.WHITE, AirportKit.cart_tint(rng.randi()))
		if service & 1:
			ch._batch.add("ap_catering", AirportKit.vehicle("catering"), Transform3D(face.call(0.0, -1.0), at.call(JET_LENGTH - 9.0, 4.6)), Color.WHITE, AirportKit.livery_white())
		if service & 2:
			ch._batch.add("ap_fuel", AirportKit.vehicle("fuel_truck"), Transform3D(face.call(1.0, 0.0), at.call(17.0, 12.8)), Color.WHITE, AirportKit.livery_white())
		# Cones off both wingtips, the nose and the engines.
		for spot: Vector2 in [Vector2(24.0, 17.2), Vector2(24.0, -17.2), Vector2(-1.4, 1.6), Vector2(12.5, 5.6), Vector2(12.5, -5.6), Vector2(39.0, 0.0)]:
			ch._batch.add("ap_cone", AirportKit.cone(), Transform3D(Basis(Vector3.UP, rng.randf() * TAU), at.call(spot.x, spot.y)))
	ch._batch.set_shadow_distance("ap_cone", 30.0)
	_crew(ch, area, seed_value)


## Ground crew: a few people in hi-vis walking round each attended stand (ApronCrew, an ordinary
## pedestrian on a small ring by the jet, counted in the crowd cap).
static func _crew(ch: CityChunk, area: Rect2, seed_value: int) -> void:
	for g in gates():
		var centre: Vector2 = g.centre
		if not area.has_point(centre) or bool(g.empty):
			continue
		var n: Vector2 = g.n
		var t: Vector2 = g.t
		var nose: Vector2 = g.nose
		# A ring round the forward hold and the baggage train, on the jet's right side.
		var c := nose + n * 12.0 + t * 6.0
		var ring := Rect2(c - Vector2(4.5, 4.5), Vector2(9.0, 9.0))
		var rng := RandomNumberGenerator.new()
		rng.seed = hash([seed_value, "crew", g.number])
		for k in 2 + rng.randi() % 2:
			ch._spawn_apron_crew(ring, rng)


# --- The field's lights -------------------------------------------------------------------------

## Every field light: [position (world), colour, size m, kind, facing (Vector3.ZERO all round),
## fixture (0 none, 1 elevated runway edge, 2 elevated taxiway edge, 3 inset), phase 0..1].
static func _field_light_specs(macro: MacroMap) -> Array:
	var out: Array = []
	var hw := macro.runway_width * 0.5
	var edge_y := RUNWAY_TOP + 0.38
	var arr_z: float = macro.runway_zs[macro.arrival_runway]
	for rw: Array in runways(macro):
		var z: float = rw[0]
		var x0: float = rw[1]
		var x1: float = rw[2]
		var length := x1 - x0
		var arrival := absf(z - arr_z) < 1.0
		# Edge lights every 50 m (yellow over the last 200 m of a landing toward the west end).
		var n := maxi(2, roundi(length / 50.0))
		for i in n + 1:
			var x := lerpf(x0, x1, float(i) / float(n))
			var col := L_YELLOW if arrival and x - x0 < 200.0 else L_WHITE
			for side: float in [-1.0, 1.0]:
				out.append([Vector3(x, edge_y, z + side * (hw + 1.5)), col, 1.0, K_FIELD, Vector3.ZERO, 1, 0.0])
		# Centre line every 25 m: white, then red and white alternating, then red at the end.
		var m := maxi(2, roundi(length / 25.0))
		for i in range(1, m):
			var x := lerpf(x0, x1, float(i) / float(m))
			var to_end := x - x0
			var col := L_WHITE
			if to_end < 100.0:
				col = L_RED
			elif to_end < 250.0 and i % 2 == 0:
				col = L_RED
			out.append([Vector3(x, RUNWAY_TOP + 0.05, z + 0.4), col, 0.65, K_FIELD, Vector3.ZERO, 3, 0.0])
		# Each end: a bar of green threshold lights facing out (toward landing traffic), and the
		# red end lights facing in, at the same posts.
		for end in 2:
			var xe := x0 if end == 0 else x1
			var out_dir := Vector3(-1.0, 0.0, 0.0) if end == 0 else Vector3(1.0, 0.0, 0.0)
			var k := -hw - 1.0
			while k <= hw + 1.0:
				out.append([Vector3(xe, edge_y, z + k), L_GREEN, 1.1, K_FIELD, out_dir, 1, 0.0])
				out.append([Vector3(xe, edge_y, z + k), L_RED, 1.0, K_FIELD, -out_dir, 0, 0.0])
				k += 3.0
		if arrival:
			# Touchdown zone bars: rows of white lights either side of the centre line.
			var d := 30.0
			while d < 300.0:
				for side: float in [-1.0, 1.0]:
					for j in 3:
						out.append([Vector3(x1 - d, RUNWAY_TOP + 0.05, z + side * (6.0 + float(j) * 1.5)), L_WHITE, 0.55, K_FIELD, Vector3(1.0, 0.0, 0.0), 3, 0.0])
				d += 30.0
	# The approach light system east of the arrival threshold, out over the long-term car park:
	# a five-lamp bar every 30 m on posts rising with the distance, the crossbar, red side rows in
	# the first 60 m, and the sequenced flasher at every station from the crossbar out.
	var arr: Array = runways(macro)[macro.arrival_runway]
	var xt: float = arr[2]
	# All round, not aimed: a real approach light is seen well off its axis, and aimed down the
	# approach these vanished from anywhere beside it.
	var face := Vector3.ZERO
	var stations := int(APPROACH_LENGTH / APPROACH_STEP)
	for s in range(1, stations + 1):
		var d := float(s) * APPROACH_STEP
		var py := macro.height_at(Vector2(xt + d, arr_z)) + 1.2 + d * 0.004
		for j in 5:
			out.append([Vector3(xt + d, py, arr_z + (float(j) - 2.0) * 1.0), L_WHITE, 1.0, K_FIELD, face, 0, 0.0])
		if absf(d - APPROACH_BAR) < 1.0:
			for j in 8:
				for side: float in [-1.0, 1.0]:
					out.append([Vector3(xt + d, py, arr_z + side * (4.0 + float(j) * 1.5)), L_WHITE, 1.0, K_FIELD, face, 0, 0.0])
		if d <= 60.0:
			for side: float in [-1.0, 1.0]:
				for j in 3:
					out.append([Vector3(xt + d, py, arr_z + side * (10.0 + float(j) * 1.5)), L_RED, 0.9, K_FIELD, face, 0, 0.0])
		if d >= APPROACH_BAR - 1.0:
			# Phase runs 1 at the farthest station to 0 at the crossbar: the flash comes in.
			var ph := (d - APPROACH_BAR) / maxf(APPROACH_LENGTH - APPROACH_BAR, 1.0)
			out.append([Vector3(xt + d, py + 0.5, arr_z), Color(1.0, 1.0, 1.0, 1.0), 2.4, K_RABBIT, face, 0, 1.0 - ph])
	# PAPI.
	for spot: Array in papi_spots(macro):
		var p: Vector2 = spot[0]
		out.append([Vector3(p.x, 0.75, p.y), Color(1.0, 1.0, 1.0, 1.0), 1.3, K_PAPI, Vector3(1.0, 0.0, 0.0), 0, (float(spot[1]) - 2.0) / 2.0])
	# Taxiways: blue edge lights every 30 m along both edges of the parallel taxiway (a gap where a
	# connector or the apron meets it) and along the connectors, green centre lights every 15 m.
	var tz := macro.taxiway_z
	var tw := macro.taxiway_width * 0.5
	var tx := taxiway_x(macro)
	var x := tx.x + 3.0
	while x < tx.y:
		var on_connector := false
		for cx: float in CONNECTOR_XS:
			on_connector = on_connector or absf(x - cx) < CONNECTOR_WIDTH * 0.5 + 4.0
		if not on_connector:
			out.append([Vector3(x, TAXI_TOP + 0.35, tz + tw + 1.2), L_BLUE, 0.8, K_FIELD, Vector3.ZERO, 2, 0.0])
		out.append([Vector3(x, TAXI_TOP + 0.35, tz - tw - 1.2), L_BLUE, 0.8, K_FIELD, Vector3.ZERO, 2, 0.0])
		x += 30.0
	x = tx.x + 10.0
	while x < tx.y - 4.0:
		out.append([Vector3(x, TAXI_TOP + 0.04, tz), L_GREEN, 0.55, K_FIELD, Vector3.ZERO, 3, 0.0])
		x += 15.0
	var south: float = macro.runway_zs[macro.runway_zs.size() - 1] - hw
	for cx: float in CONNECTOR_XS:
		var z := tz + tw + 8.0
		while z < south - 4.0:
			var on_runway := false
			for rz: float in macro.runway_zs:
				on_runway = on_runway or absf(z - rz) < hw + 3.0
			if not on_runway:
				for side: float in [-1.0, 1.0]:
					out.append([Vector3(cx + side * (CONNECTOR_WIDTH * 0.5 + 1.2), TAXI_TOP + 0.35, z), L_BLUE, 0.8, K_FIELD, Vector3.ZERO, 2, 0.0])
				out.append([Vector3(cx, CONNECTOR_TOP + 0.04, z), L_GREEN, 0.55, K_FIELD, Vector3.ZERO, 3, 0.0])
			z += 15.0
		# Stop bars: a row of red lights across each hold-short line.
		for rz: float in macro.runway_zs:
			var hz := rz - hw - 19.4
			var k := -CONNECTOR_WIDTH * 0.5 + 1.5
			while k < CONNECTOR_WIDTH * 0.5 - 1.0:
				out.append([Vector3(cx + k, CONNECTOR_TOP + 0.05, hz), L_RED, 0.6, K_FIELD, Vector3(0.0, 0.0, -1.0), 3, 0.0])
				k += 3.0
	# The apron's edge along the taxiway: blue lights on the gate side too, between stands.
	return out


## Every light the airfield shows at night, in ONE billboard mesh (see the class header). Built once.
static func lights_mesh(macro: MacroMap) -> ArrayMesh:
	if _lights != null:
		return _lights
	var specs := _field_light_specs(macro)
	var y: float = macro.tarmac_top
	# The apron floodlight masts' lamps, and a red obstruction light on top of each.
	for spot: Array in mast_spots(macro):
		var p: Vector2 = spot[0]
		var fwd := Vector3((spot[1] as Vector2).x, 0.0, (spot[1] as Vector2).y)
		var side := Vector3(fwd.z, 0.0, -fwd.x)
		for k in 4:
			var at := Vector3(p.x, y + MAST_HEIGHT - 0.4, p.y) + side * ((float(k) - 1.5) * 1.15) + fwd * 0.9
			specs.append([at, L_FLOOD, 2.6, K_STEADY, (fwd - Vector3.UP * 0.8).normalized(), 0, 0.0])
		specs.append([Vector3(p.x, y + MAST_HEIGHT + 1.3, p.y), L_RED, 1.0, K_BEACON, Vector3.ZERO, 0, fposmod(p.x * 0.013, 1.0)])
	# The control tower's rotating beacon (white and green, half a turn apart) and red lights.
	var top := Vector3(TOWER_AT.x, y + AirportTerminal.TOWER_TOP + 2.2, TOWER_AT.y)
	specs.append([top, Color(1.0, 0.97, 0.9, 1.0), 4.0, K_ROTATE, Vector3.ZERO, 0, 0.0])
	specs.append([top + Vector3(0.0, 0.3, 0.0), Color(0.2, 1.0, 0.4, 1.0), 4.0, K_ROTATE, Vector3.ZERO, 0, 0.5])
	# Red obstruction lights on the hangars' roofs and the concourse ends.
	for k in 3:
		specs.append([Vector3(30.0, y + 23.0, 770.0 + float(k) * 60.0), L_RED, 1.2, K_STEADY, Vector3.ZERO, 0, 0.0])
	for a: float in [-CONCOURSE_ARC, CONCOURSE_ARC]:
		var p := arc_point(a, CONCOURSE_RADIUS)
		specs.append([Vector3(p.x, y + CONCOURSE_HEIGHT + 1.0, p.y), L_RED, 1.0, K_STEADY, Vector3.ZERO, 0, 0.0])
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var corners := [Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(1.0, 1.0), Vector2(0.0, 1.0)]
	for spec: Array in specs:
		var code := float(spec[3]) * 10.0 + clampf(float(spec[6]), 0.0, 1.0) * 9.0
		if (spec[4] as Vector3) != Vector3.ZERO:
			code += 100.0
		for k: int in [0, 1, 2, 0, 2, 3]:
			st.set_color(spec[1])
			st.set_uv(corners[k])
			st.set_uv2(Vector2(spec[2], code))
			st.set_normal(spec[4])
			st.add_vertex(spec[0])
	_lights = st.commit()
	_lights.surface_set_material(0, light_material())
	return _lights


static func light_count(macro: MacroMap) -> int:
	return lights_mesh(macro).surface_get_array_len(0) / 6


static func light_material() -> ShaderMaterial:
	if _light_mat != null:
		return _light_mat
	_light_mat = ShaderMaterial.new()
	_light_mat.shader = load("res://shaders/aircraft_lights.gdshader")
	# Field lights never shrink under about the aircraft's minimum angle, so a runway reads as a
	# line of points from across the basin (at 0.0042 they were single dim pixels at 1 km).
	_light_mat.set_shader_parameter("min_angle", 0.0065)
	_light_mat.set_shader_parameter("hdr", 3.5)
	_light_mat.set_shader_parameter("day_level", 0.0)
	_light_mat.set_shader_parameter("field_day", 0.0)
	return _light_mat


## The field's lights as a node (the "airfield_lights" landmark builds it near and far alike).
static func build_lights(parent: Node3D, macro: MacroMap) -> void:
	var mi := MeshInstance3D.new()
	mi.name = "AirfieldLights"
	mi.mesh = lights_mesh(macro)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	# Every corner of a light sits on its centre, and the shader draws them past the far plane.
	mi.extra_cull_margin = 16000.0
	# Not an obstacle for the air traffic's clearance field (AirTraffic._measure_landmarks()).
	mi.set_meta("air_ignore", true)
	parent.add_child(mi)
