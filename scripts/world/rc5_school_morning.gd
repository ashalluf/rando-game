class_name RcSchoolMorning
extends RefCounted
## The elementary school's morning drop-off (wave 8 refcam5 `school_morning`, docs/HANDOFF.md "The
## school drop-off at 07:50"). What that view found and fixed, each behind RC5_SCHOOL_MORNING=0 (the
## A/B: exactly main):
##  1. The buses: a school whose loading zone is on its -x / -z kerb never parked them (that kerb
##     belongs to the chunk before the school's: Schools.park_kerb_buses()).
##  2. The drop-off was an empty kerb at 07:50: parents' cars now stand in a drop-off zone beside
##     the buses with their drivers in and hazards on, a crossing guard with a STOP paddle at the
##     kerb, a supervisor at the gate, parents on the pavement (school_front()), in DROP_HOURS.
##  3. The wings' street face was a flat box: sunshades, sills and fins (wing_relief()), a weathered
##     fascia (fascia()).
##  4. The marquee sign stood on the lawn right behind the parked buses (gate + 7 m, in the middle of
##     the bus zone): from the street it was never seen. It stands past the zone's end (sign_s()).

static func _static_init() -> void: LoadPulse.compiled()  # a boot frame: docs/HANDOFF.md "The boot compile"

static var _on: int = -1


## RC5_SCHOOL_MORNING=0 turns every part off.
static func enabled() -> bool:
	if _on < 0:
		_on = 0 if OS.get_environment("RC5_SCHOOL_MORNING") == "0" else 1
	return _on == 1


# --- 2. The drop-off: parents' cars at the kerb, the adults at the gate -------------------------

## When parents drop off and pick up (hours): a little wider than the bus run (Schools.BUS_HOURS).
const DROP_HOURS := [Vector2(7.2, 8.5), Vector2(14.3, 15.5)]
## The drop-off kerb beside the bus zone: how long at most, how far it keeps off the block's ends
## (the corner and its crosswalk), the car pitch, and the share of slots with a car in.
const DROP_LEN := 32.0
const DROP_END_CLEAR := 9.0
const CAR_PITCH := 6.6
const CAR_ODDS := 0.8


static func dropoff_time(hour: float) -> bool:
	for h: Vector2 in DROP_HOURS:
		if hour >= h.x and hour <= h.y:
			return true
	return false


## The school's drop-off kerb (a world rect over the parking lane, like Schools' bus_rect), on the
## side of the bus zone with more room, or an empty Rect2. Pure: the plan only.
static func dropoff_rect(pl: Dictionary) -> Rect2:
	if pl.get("high", false) or not pl.has("bus_rect"):
		return Rect2()
	var fr: Dictionary = pl.fr
	var zr: Rect2 = pl.bus_rect
	var o: Vector2 = fr.o
	var s: Vector2 = fr.s
	var a := (zr.position - o).dot(s)
	var b := (zr.end - o).dot(s)
	var s0 := minf(a, b)
	var s1 := maxf(a, b)
	var room_lo := s0 - 2.0 - DROP_END_CLEAR
	var room_hi := float(fr.A) - DROP_END_CLEAR - (s1 + 2.0)
	var lat := zr.get_center() - (o + s * ((s0 + s1) * 0.5))
	var p0: float
	var p1: float
	if room_hi >= room_lo:
		if room_hi < 12.0:
			return Rect2()
		p0 = s1 + 2.0
		p1 = p0 + minf(DROP_LEN, room_hi)
	else:
		if room_lo < 12.0:
			return Rect2()
		p1 = s0 - 2.0
		p0 = p1 - minf(DROP_LEN, room_lo)
	var q0 := o + s * p0 + lat
	var q1 := o + s * p1 + lat
	var lo := Vector2(minf(q0.x, q1.x), minf(q0.y, q1.y)) - (Vector2(1.8, 0.0) if absf(s.x) < 0.5 else Vector2(0.0, 1.8))
	var hi := Vector2(maxf(q0.x, q1.x), maxf(q0.y, q1.y)) + (Vector2(1.8, 0.0) if absf(s.x) < 0.5 else Vector2(0.0, 1.8))
	return Rect2(lo, hi - lo)


## CityChunk._kerb_taken()'s hook: a kerb spot in a school's drop-off zone while parents are
## dropping off (after every roll: the chunk's stream runs the same).
static func blocks_parking(ch: CityChunk, at: Vector3) -> bool:
	if not enabled() or not Schools.enabled or ch.plan.macro == null:
		return false
	if not dropoff_time(Schools.hour_now(ch)):
		return false
	var p := Vector2(at.x, at.z)
	var c := Schools._cell_of(p)
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			var d := Schools.decide(ch.plan, c + Vector2i(dx, dz))
			if d.is_empty():
				continue
			var pl := Schools.plan_for_school(ch.plan, d)
			if not pl.is_empty() and dropoff_rect(pl).grow(1.0).has_point(p):
				return true
	return false


## The school's front at drop-off, from the chunk that owns that kerb (Schools.park_buses()): the
## parents' cars in the drop-off zone (drivers in, hazards on), and on the pavement a crossing
## guard at the kerb by the gate, a supervisor at the gate and a few parents. FULL chunks only,
## hashes of the school's cell only.
static func school_front(ch: CityChunk, pl: Dictionary) -> void:
	if not enabled() or pl.get("high", false) or ch.capturing or ch.level != CityChunk.Level.FULL:
		return
	if not dropoff_time(Schools.hour_now(ch)):
		return
	_cars(ch, pl)
	_people(ch, pl)


static func _cars(ch: CityChunk, pl: Dictionary) -> void:
	var r := dropoff_rect(pl)
	if r.size == Vector2.ZERO:
		return
	var road: Array = pl.front_road
	var rp := ch.plan.road_pos(int(road[0]), int(road[1]))
	var along_x := r.size.x > r.size.y
	var len := maxf(r.size.x, r.size.y)
	var n := int(len / CAR_PITCH)
	var own := ch.plan.owned_rect(ch.ix, ch.iz)
	var holder: Node = ch.get_parent() if ch.get_parent() else ch
	for i in n:
		var t := (float(i) + 0.5) * CAR_PITCH - float(n) * CAR_PITCH * 0.5
		var c := r.get_center()
		var p := c + (Vector2(t, 0.0) if along_x else Vector2(0.0, t))
		var key := [ch.plan.seed, pl.cell, "dropoff", i]
		if Schools._h01(key) > CAR_ODDS or not own.has_point(p) or not PhysicsBudget.can_spawn():
			continue
		# Right-hand traffic: the car on the +side of the road faces the way that lane runs.
		var dir := Vector2.ZERO
		if along_x:
			dir = Vector2(1.0, 0.0) if p.y > rp else Vector2(-1.0, 0.0)
		else:
			dir = Vector2(0.0, -1.0) if p.x > rp else Vector2(0.0, 1.0)
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(key)
		var car := Vehicle.random_car(rng)
		car.set_meta("school_dropoff", true)
		var at := Vector3(p.x, 0.7 + ch._gy(p.x, p.y), p.y)
		# A car pulled in short of the kerb, a little skewed: dropping off, not parked.
		at += Vector3(dir.y, 0.0, -dir.x) * (rng.randf_range(-0.25, 0.15) * (1.0 if along_x else -1.0))
		car.position = WorldState.to_local(at) if holder != ch else at
		car.rotation.y = atan2(-dir.x, -dir.y) + rng.randf_range(-0.05, 0.05)
		holder.add_child(car)
		car.visible = ch.visible
		car.seat_waiting_driver(hash(key) + 1)
		# Hazards on (Vehicle._tick_lights: an npc driver not `waiting`).
		car.waiting = false
		ch._cars.append(car)


static func _people(ch: CityChunk, pl: Dictionary) -> void:
	var fr: Dictionary = pl.fr
	var gate_s := -1.0
	for f: Dictionary in pl.fac:
		if f.t == "lawn":
			gate_s = float(f.gate_s)
	if gate_s < 0.0:
		return
	var zr: Rect2 = pl.bus_rect
	var kerb_d := (zr.get_center() - (fr.o as Vector2)).dot(fr.d) + 1.3 + 0.6
	var street_yaw := atan2((fr.d as Vector2).x, (fr.d as Vector2).y)
	var drop := dropoff_rect(pl)
	var drop_s := gate_s + 18.0
	if drop.size != Vector2.ZERO:
		drop_s = (drop.get_center() - (fr.o as Vector2)).dot(fr.s)
	var side := signf(drop_s - gate_s) if drop_s != gate_s else 1.0
	# [s, d, yaw, kind]: kind 0 the guard, 1 the supervisor, 2 a parent.
	var spots: Array = [
		[gate_s + side * 3.0, kerb_d, street_yaw, 0],
		[gate_s - side * 1.6, -0.9, street_yaw, 1],
	]
	var parents := 2 + int(Schools._h01([ch.plan.seed, pl.cell, "parents"]) * 3.0)
	for i in parents:
		var h := Schools._h01([ch.plan.seed, pl.cell, "parent", i])
		var s := lerpf(gate_s + side * 2.0, drop_s + side * 6.0, h)
		var d := lerpf(-2.8, -0.8, Schools._h01([ch.plan.seed, pl.cell, "parent_d", i]))
		var yaw := street_yaw + PI + (Schools._h01([ch.plan.seed, pl.cell, "parent_y", i]) - 0.5) * 2.4
		spots.append([s, d, yaw, 2])
	var own := ch.plan.owned_rect(ch.ix, ch.iz)
	var block := Schools._block_rect(ch.plan, Vector2i(ch.ix, ch.iz))
	for i in spots.size():
		var sp: Array = spots[i]
		var at := Schools._lp(fr, float(sp[0]), float(sp[1]))
		if not own.has_point(at) or not ch._take_crowd_room():
			continue
		var ped := SchoolStaff.new()
		ped.hivis = int(sp[3]) < 2
		ped.paddle = int(sp[3]) == 0
		ped.setup_vendor(block, hash([ch.plan.seed, pl.cell, "front", i]), at, float(sp[2]), false, 0.0)
		ped.set_meta("no_trim", true)
		ped.position = Vector3(at.x, ch.ground_y(at.x, at.y) + 0.05, at.y)
		ch.add_child(ped)


# --- 3. The wings' street face: relief, not a flat box -------------------------------------------

## The 1960s classroom wing's street face had its ribbon windows painted flush on a flat wall under
## a saturated band: a box. Now each ribbon gets a precast concrete sunshade (an eyebrow, `SHADE`
## deep) over it and a sill under it, and a slim fin stands between the bays - the shadow lines a
## real one has under a low morning sun - and the fascia band is the weathered paint of a school
## colour (`fascia()`), not the colour itself. Bays exactly as SchoolKit.wall() lays them for
## W_CLASS (pitch 9, the ribbon 0.5..8.5 by 1.0..3.0 of each 4 m storey).
const SHADE := 0.8
const FIN := Vector2(0.22, 0.42)


static func wing_relief(st: SurfaceTool, xf: Transform3D, len: float, depth: float, storeys: int, kind: int, paint: Color) -> void:
	if not enabled():
		return
	var pitch: float = SchoolKit.PITCH[SchoolKit.W_CLASS]
	var bays := int(floor((len - 0.6) / pitch))
	if bays <= 0:
		return
	var margin := (len - float(bays) * pitch) * 0.5
	var z := -depth * 0.5
	var concrete := SchoolKit.CONCRETE
	for f in storeys:
		var y0 := float(f) * Schools.STOREY
		for k in bays:
			var x0 := -len * 0.5 + margin + float(k) * pitch
			var cx := x0 + pitch * 0.5
			# The eyebrow over the ribbon (its soffit shades the head of the glass), the sill.
			SchoolKit.box(st, xf * Transform3D(Basis(), Vector3(cx, y0 + 3.22, z - SHADE * 0.5)), Vector3(8.7, 0.2, SHADE), SchoolKit.K_CONCRETE, concrete, 0.0, 4)
			SchoolKit.box(st, xf * Transform3D(Basis(), Vector3(cx, y0 + 0.93, z - 0.07)), Vector3(8.3, 0.1, 0.14), SchoolKit.K_CONCRETE, concrete, 0.0, 36)
		# Fins on the bay lines, foot to the parapet, in the wall's own finish.
		for k in bays + 1:
			var x := -len * 0.5 + margin + float(k) * pitch
			SchoolKit.box(st, xf * Transform3D(Basis(), Vector3(x, y0 + Schools.STOREY * 0.5 + 0.2, z - FIN.y * 0.5)), Vector3(FIN.x, Schools.STOREY, FIN.y), kind, paint, 0.0, 36)


## The brick wings' fascia band: the school colour as weathered paint (a third toward a warm grey,
## a little darker), never the saturated swatch.
static func fascia(trim: Color) -> Color:
	if not enabled():
		return trim
	var grey := Color(0.42, 0.41, 0.39)
	return trim.lerp(grey, 0.35).darkened(0.08)


# --- 4. The marquee sign, out from behind the buses ----------------------------------------------

## Where along the front (frame s) the marquee stands: just past the bus zone's end on the drop-off
## side (where nothing taller than a car stands at the kerb), or `old` (Schools' gate + 7 m) when
## that does not fit on the lawn or the switch is off.
static func sign_s(pl: Dictionary, old: float) -> float:
	if not enabled() or pl.get("high", false) or not pl.has("bus_rect"):
		return old
	var fr: Dictionary = pl.fr
	var zr: Rect2 = pl.bus_rect
	var a := (zr.position - (fr.o as Vector2)).dot(fr.s)
	var b := (zr.end - (fr.o as Vector2)).dot(fr.s)
	var drop := dropoff_rect(pl)
	var s := maxf(a, b) + 2.5
	if drop.size != Vector2.ZERO and (drop.get_center() - (fr.o as Vector2)).dot(fr.s) < minf(a, b):
		s = minf(a, b) - 2.5
	if s < 3.0 or s > float(fr.A) - 3.0:
		return old
	return s
