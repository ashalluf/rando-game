class_name StuntRamps
extends RefCounted
## Stunt features for a chaos sandbox (2026-10-30, fleet wave 3 "stunt-ramps"): a playground hidden
## in a real city, every piece where a stunt crew would put it and where it blocks no traffic lane.
##   KICKER   a steel kicker in the roof aisle of a multi-storey car park (CarPark), aimed down the
##            aisle past the last light pole, over the end zone and the parapet into the air.
##   QPIPE    a concrete quarter-pipe with a steel coping at the toe of one bank of the Los Angeles
##            River's channel (LaRiver), across the bed from the foot of an access ramp.
##   LAUNCH / LAND  a ramp pair over a freeway in the INDUSTRIAL district: a tall framed kicker on
##            the right of way one side of the deck, a long landing deck on the other, square across
##            a straight stretch (Footbridges' freeway slots' tests: corridor ground, no gantry, no
##            other deck or off-ramp near).
##   LOOP     a steel loop-the-loop on the same kind of right of way, along the deck.
##   PIER     a kicker at the sea end of RANDO PIER's main deck, launching over the rail.
##   DIRT     a line of dirt tabletops in a bare VACANT lot (VacantLots), down the ruts from its gate.
## WHERE is worked out, never placed: hashes of the seed and the place, asked AFTER every roll the
## city makes (the car park, the river, the freeway, the vacant lot are all already planned), so
## nothing a seed builds elsewhere moves. Every site is a dictionary in TRUE world space:
## {"id", "kind", "p" (Vector3: the foot's centre on the ground, true world), "yaw" (local +Z is the
## way you ride it: basis = Basis(UP, yaw)), plus the kind's numbers}; the chunk whose owned rect
## holds the site's `p` builds it (StuntBuild).
## STUNT_RAMPS=0 in the environment: none of it (the A/B).

enum Kind { KICKER, QPIPE, LAUNCH, LAND, LOOP, PIER, DIRT }

static var enabled: bool = OS.get_environment("STUNT_RAMPS") != "0"

## The car park roofs that get a kicker.
const CAR_PARK_ODDS := 0.75
## The kicker (m): length along the run, height at the lip, width.
const KICKER_LEN := 5.2
const KICKER_H := 1.65
const KICKER_W := 3.0
## Offset of the kicker's centre line from the roof aisle's (the light poles stand on the aisle's).
const KICKER_SIDE := 1.85

## River quarter-pipes: one by this share of the access ramps, across the bed from the ramp's foot.
const QP_ODDS := 0.8
const QP_RADIUS := 4.0
const QP_ANGLE := 78.0
const QP_LEN := 14.0
const QP_DECK := 2.2
## How far from the ramp's foot along the river (m), tried in this order.
const QP_SHIFTS := [36.0, -36.0, 60.0, -60.0, 20.0, -20.0]

## Freeway slots (Footbridges' idea): a slot is SLOT_SEGMENTS deck segments of one route.
const SLOT_SEGMENTS := 10
const PAIR_ODDS := 0.75
const LOOP_ODDS := 0.75
const SLOT_TRIES := 5
## The ramp pair (m): the launch kicker's length and lip height, the landing's, their width, and
## how far each stands off the deck's edge (tried in turn).
const LAUNCH_LEN := 17.0
const LAUNCH_H := 6.2
const LAND_LEN := 24.0
const LAND_H := 5.4
const PAIR_W := 6.0
const PAIR_GAPS := [14.0, 18.0, 11.0, 22.0]
## Ground under a piece within this of level (m).
const MAX_RELIEF := 0.9
## The loop (m): radius, track width, the lateral shift over one turn, the run in and out.
const LOOP_R := 6.4
const LOOP_W := 4.2
const LOOP_SHIFT := 5.4
const LOOP_RUN := 9.0
const LOOP_GAPS := [8.0, 12.0, 16.0]

## RANDO PIER's kicker, in PierPark's frame (x out to sea negative, z south).
const PIER_ID := "pier"
const PIER_AT := Vector2(-263.0, -6.0)
const PIER_LEN := 6.0
const PIER_H := 1.95
const PIER_W := 3.4

## Dirt lines in vacant lots: the share of eligible lots, the line's numbers (m).
const DIRT_ODDS := 0.7
const DIRT_W := 4.6
const DIRT_MIN_D := 24.0

static var _cache: Dictionary = {}


static func h01(parts: Array) -> float:
	return float(absi(hash(parts)) % 100003) / 100003.0


static func _plan_cache(plan: CityPlan) -> Dictionary:
	var k := plan.get_instance_id()
	if not _cache.has(k):
		if _cache.size() > 8:
			_cache.clear()
		_cache[k] = {}
	return _cache[k]


## Every site whose foot `p` lies in chunk (ix, iz)'s owned rect (the vacant lots' are not here:
## those come with their lot, see vacant_site()).
static func owned_by(plan: CityPlan, ix: int, iz: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not enabled or plan == null or plan.macro == null:
		return out
	var r := plan.owned_rect(ix, iz)
	var cp := car_park_site(plan, ix, iz)
	if not cp.is_empty():
		out.append(cp)
	for list: Array in [river_sites(plan), freeway_sites(plan), pier_sites(plan)]:
		for s: Dictionary in list:
			var p: Vector3 = s.p
			if r.has_point(Vector2(p.x, p.z)):
				out.append(s)
	return out


## Every site but the vacant lots' (probes and the checks).
static func all_sites(plan: CityPlan) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not enabled or plan == null or plan.macro == null:
		return out
	for list: Array in [river_sites(plan), freeway_sites(plan), pier_sites(plan)]:
		for s: Dictionary in list:
			out.append(s)
	return out


## The rects every site of this kind list keeps clear (the right of way's planting under them).
static func clear_rects(sites: Array) -> Array[Rect2]:
	var out: Array[Rect2] = []
	for s: Dictionary in sites:
		if s.has("clear"):
			out.append(s.clear)
	return out


# --- The car park's roof -------------------------------------------------------------------------

## The kicker on the roof of the car park built on block (bx, bz), or {}.
static func car_park_site(plan: CityPlan, bx: int, bz: int) -> Dictionary:
	var cs := CarPark.on_block(plan, bx, bz)
	if cs.is_empty():
		return {}
	if h01([plan.seed, "stunt_cp", int(cs.seed)]) >= CAR_PARK_ODDS:
		return {}
	var lay: Dictionary = cs.layout
	var m0: float = lay.m0
	var m1: float = lay.m1
	# The last of the roof's light poles in the aisle (CarParkBuild._roof()): the kicker stands
	# between it and the end zone, so it must fit there.
	var n := maxi(1, int((m1 - m0) / CarParkBuild.ROOF_POLE_SPACING))
	var last_pole := m0 + (float(n) - 0.5) * (m1 - m0) / float(n)
	var foot_u := m1 - KICKER_LEN - 0.4
	if foot_u < last_pole + 0.8 or foot_u < float(lay.r1) + 8.0:
		return {}
	# The two lanes of the aisle: the one on the street side or the far one, by hash.
	var side := -1.0 if h01([plan.seed, "stunt_cp_side", int(cs.seed)]) < 0.5 else 1.0
	var vc := CarPark.WALL + CarPark.STALL_D + CarPark.AISLE * 0.5 + side * KICKER_SIDE
	var xf := CarParkBuild.frame_xform(plan, cs)
	var y := CarPark.FLOOR * float(lay.decks)
	var foot := xf * Vector3(foot_u, y, vc)
	var fwd := xf.basis.x
	return {"id": "stunt_cp_%d" % (int(cs.seed) % 100000), "kind": Kind.KICKER, "p": foot,
		"yaw": atan2(fwd.x, fwd.z), "len": KICKER_LEN, "h": KICKER_H, "w": KICKER_W, "paint": _paint(plan, "cp", int(cs.seed)),
		"run_from": xf * Vector3(float(lay.r1) + 2.0, y, vc), "deck": true}


# --- The river -----------------------------------------------------------------------------------

static func river_sites(plan: CityPlan) -> Array:
	var pc := _plan_cache(plan)
	if pc.has("river"):
		return pc.river
	var out: Array = []
	pc.river = out
	var rv: LaRiver = plan.macro.river
	if rv == null or rv.pts.size() < 2:
		return out
	var fw: Freeway = plan.macro.freeway
	var bridges := rv.bridges(plan)
	var ramps := rv.ramps(plan)
	for rp: Dictionary in ramps:
		var k := int(rp.k)
		if h01([plan.seed, "stunt_qp", k]) >= QP_ODDS:
			continue
		var foot_s: float = rp.s1
		var side := -float(rp.side)
		for shift: float in QP_SHIFTS:
			var s := foot_s + shift
			var lo := s - QP_LEN * 0.5 - 6.0
			var hi := s + QP_LEN * 0.5 + 6.0
			if lo < 140.0 or hi > rv.length - LaRiver.MOUTH_RUN - 40.0:
				continue
			var ok := true
			for br: Dictionary in bridges:
				if absf(float(br.s) - s) < 45.0:
					ok = false
			for other: Dictionary in ramps:
				# Off every ramp's bank (its own included: the QP is on the other bank).
				if float(other.side) == side and maxf(float(other.s0), float(other.s1)) > lo - 8.0 and minf(float(other.s0), float(other.s1)) < hi + 8.0:
					ok = false
			for bar: Dictionary in rv.bars_in(lo, hi):
				if float(bar.side) == side:
					ok = false
			for kk in range(floori(lo / LaRiver.OUTFALL_PITCH) - 1, ceili(hi / LaRiver.OUTFALL_PITCH) + 1):
				var os := (float(kk) + 0.5) * LaRiver.OUTFALL_PITCH
				if os > lo - 2.0 and os < hi + 2.0 and LaRiver.outfall_at(kk, 0 if side > 0.0 else 1):
					ok = false
			if not ok:
				continue
			var bh := rv.bed_half(s)
			var foot2 := rv.point(s, side * (bh - QP_RADIUS * sin(deg_to_rad(QP_ANGLE)) - 0.05))
			if fw != null and fw.blocks(foot2, 12.0):
				continue
			var d: Vector2 = rv.at(s)[1]
			var across := Vector2(-d.y, d.x) * side
			var y := rv.toe_at(s)
			# The bed falls BED_FALL toward the low flow; the foot sits on its lowest corner.
			var bed := rv.surface(s, side * (bh - QP_RADIUS - 0.2))
			out.append({"id": "stunt_qp_%d" % k, "kind": Kind.QPIPE, "p": Vector3(foot2.x, minf(y, bed), foot2.y),
				"yaw": atan2(across.x, across.y), "len": QP_LEN, "r": QP_RADIUS, "angle": QP_ANGLE, "deck": QP_DECK,
				"toe": y, "s": s, "side": side, "bank_slope": LaRiver.SLOPE})
			break
	return out


# --- The freeway's right of way ------------------------------------------------------------------

static func freeway_sites(plan: CityPlan) -> Array:
	var pc := _plan_cache(plan)
	if pc.has("freeway"):
		return pc.freeway
	var out: Array = []
	pc.freeway = out
	var fw: Freeway = plan.macro.freeway
	if fw == null:
		return out
	for ri in fw.routes.size():
		var count: int = (fw.routes[ri].points as PackedVector2Array).size() - 1
		for slot in range(0, count / SLOT_SEGMENTS + 1):
			for what: int in [Kind.LAUNCH, Kind.LOOP]:
				var odds := PAIR_ODDS if what == Kind.LAUNCH else LOOP_ODDS
				if h01([plan.seed, "stunt_fw", ri, slot, what]) >= odds:
					continue
				var order: Array = []
				for j in SLOT_SEGMENTS:
					var i := slot * SLOT_SEGMENTS + j
					if i >= 2 and i < count - 2:
						order.append([h01([plan.seed, "stunt_fw_try", ri, i, what]), i])
				order.sort()
				for t in mini(order.size(), SLOT_TRIES):
					var got := _pair(plan, ri, int(order[t][1])) if what == Kind.LAUNCH else _loop(plan, ri, int(order[t][1]))
					if got.is_empty():
						continue
					# Never two features over each other (a loop and a pair in neighbouring slots).
					var clash := false
					for o: Dictionary in out:
						if (o.clear as Rect2).grow(6.0).intersects(got[0].clear):
							clash = true
					if clash:
						continue
					out.append_array(got)
					break
	return out


## The segment `i` of route `ri` if it can carry a stunt: a straight stretch, no gantry, not the
## stack, in the INDUSTRIAL district. [c, dir (across, unit), along (unit), half width, deck y].
static func _segment(plan: CityPlan, ri: int, i: int) -> Array:
	var fw: Freeway = plan.macro.freeway
	var route: Dictionary = fw.routes[ri]
	var pts: PackedVector2Array = route.points
	var hs: PackedFloat32Array = route.heights
	var gantry_every := int(round(Freeway.GANTRY_SPACING / Freeway.STEP))
	for d in range(-1, 3):
		if posmod(i + d, gantry_every) == 0:
			return []
	var a := pts[i]
	var b := pts[i + 1]
	var along := (b - a).normalized()
	for j: int in [i - 1, i + 1]:
		var d2 := (pts[j + 1] - pts[j]).normalized()
		if along.dot(d2) < 0.998:
			return []
	var stack: FreewayStack = fw.stack
	if stack != null:
		for j in range(i - 2, i + 3):
			if stack.covered.has(Vector2i(ri, j)) or stack.open_edges.has(Vector2i(ri, j)):
				return []
	var c := (a + b) * 0.5
	if plan.zone_at(c) != MacroMap.Zone.CITY or plan.district_at(c) != CityPlan.District.INDUSTRIAL:
		return []
	return [c, Vector2(-along.y, along.x), along, float(route.width) * 0.5, maxf(hs[i], hs[i + 1])]


## The ground of a piece: a rect turned to (dir, along) round `c` of half sizes (hd across, ha
## along) is on the right of way (Footbridges' stair-tower test), level, clear of every other deck,
## off-ramp, footbridge, the light rail and the freight line. The ground height, or NAN.
static func _ground(plan: CityPlan, c: Vector2, dir: Vector2, along: Vector2, hd: float, ha: float, own_route: int) -> float:
	var r := Footbridges._turned_rect(c, dir, along, hd, ha)
	if plan.district_at(c) != CityPlan.District.INDUSTRIAL:
		return NAN
	if not Footbridges._tower_ground_ok(plan, r, c, CityChunk.SIDEWALK_TOP + plan.macro.relief_at(c)):
		return NAN
	var lo := INF
	var hi := -INF
	for k in 9:
		var q := c + dir * hd * float(k % 3 - 1) + along * ha * float(k / 3 - 1)
		var g := plan.macro.relief_at(q)
		lo = minf(lo, g)
		hi = maxf(hi, g)
	if hi - lo > MAX_RELIEF:
		return NAN
	var fw: Freeway = plan.macro.freeway
	# Never under any deck, its own route's bends included.
	if fw.blocks_rect(r, 1.0):
		return NAN
	for s: Dictionary in fw.segments_in(r.grow(30.0)):
		if int(s.route) == own_route:
			continue
		if Freeway.segment_rect_distance(s.a, s.b, r) < float(s.width) * 0.5 + 6.0:
			return NAN
	for rp: Dictionary in fw.ramps_in(r.grow(Freeway.RAMP_RUN + Freeway.RAMP_BOW + 6.0)):
		var path := Freeway.ramp_path(rp)
		for q in path.size() - 1:
			if Freeway.segment_rect_distance(path[q], path[q + 1], r) < Freeway.RAMP_WIDTH * 0.5 + 6.0:
				return NAN
	if not Footbridges.near(plan, r, 6.0).is_empty():
		return NAN
	var rail := LightRail.of(plan)
	if rail != null and rail.blocks_rect(r, 3.0):
		return NAN
	if FreightRail.of(plan) != null and not FreightRail.of(plan).cut_rects().is_empty():
		for fr: Rect2 in FreightRail.of(plan).cut_rects():
			if fr.grow(4.0).intersects(r):
				return NAN
	return CityChunk.SIDEWALK_TOP + hi


## The launch ramp and the landing ramp square across segment i, or [].
static func _pair(plan: CityPlan, ri: int, i: int) -> Array:
	var seg := _segment(plan, ri, i)
	if seg.is_empty():
		return []
	var c: Vector2 = seg[0]
	var dir: Vector2 = seg[1]
	var along: Vector2 = seg[2]
	var half: float = seg[3]
	var sgn := 1.0 if h01([plan.seed, "stunt_pair_sgn", ri, i]) < 0.5 else -1.0
	for gap: float in PAIR_GAPS:
		# The launch on side -sgn rides toward +sgn (its lip `gap` off the deck's edge), the landing
		# on side +sgn rides away from the deck (its top `gap` off the other edge).
		var lc := c - dir * sgn * (half + gap + LAUNCH_LEN * 0.5)
		var gl := _ground(plan, lc, dir, along, LAUNCH_LEN * 0.5 + 1.0, PAIR_W * 0.5 + 1.5, ri)
		if is_nan(gl):
			continue
		var dc := c + dir * sgn * (half + gap + LAND_LEN * 0.5)
		var gd := _ground(plan, dc, dir, along, LAND_LEN * 0.5 + 1.0, PAIR_W * 0.5 + 1.5, ri)
		if is_nan(gd):
			continue
		var ride := dir * sgn
		var yaw := atan2(ride.x, ride.y)
		var lf := lc - ride * LAUNCH_LEN * 0.5
		var df := dc - ride * LAND_LEN * 0.5
		var id := "stunt_pair_%d_%d" % [ri, i]
		var paint := _paint(plan, "pair", ri * 1000 + i)
		var lr := Footbridges._turned_rect(lc, dir, along, LAUNCH_LEN * 0.5 + 2.5, PAIR_W * 0.5 + 2.5)
		var dr := Footbridges._turned_rect(dc, dir, along, LAND_LEN * 0.5 + 2.5, PAIR_W * 0.5 + 2.5)
		return [
			{"id": id + "_a", "kind": Kind.LAUNCH, "p": Vector3(lf.x, gl, lf.y), "yaw": yaw, "len": LAUNCH_LEN,
				"h": LAUNCH_H, "w": PAIR_W, "paint": paint, "clear": lr, "deck_y": seg[4], "route": ri, "index": i,
				"run_from": Vector3(lf.x - ride.x * 30.0, gl, lf.y - ride.y * 30.0)},
			{"id": id + "_b", "kind": Kind.LAND, "p": Vector3(df.x, gd, df.y), "yaw": yaw, "len": LAND_LEN,
				"h": LAND_H, "w": PAIR_W, "paint": paint, "clear": dr, "route": ri, "index": i},
		]
	return []


## A loop beside segment i, riding along the route, or [].
static func _loop(plan: CityPlan, ri: int, i: int) -> Array:
	var seg := _segment(plan, ri, i)
	if seg.is_empty():
		return []
	var c: Vector2 = seg[0]
	var dir: Vector2 = seg[1]
	var along: Vector2 = seg[2]
	var half: float = seg[3]
	var sgn := 1.0 if h01([plan.seed, "stunt_loop_sgn", ri, i]) < 0.5 else -1.0
	var fwd := along * (1.0 if h01([plan.seed, "stunt_loop_dir", ri, i]) < 0.5 else -1.0)
	var lateral := (LOOP_SHIFT + LOOP_W) * 0.5 + 1.5
	var ha := LOOP_R + LOOP_RUN + 1.0
	for gap: float in LOOP_GAPS:
		var lc := c + dir * sgn * (half + gap + lateral)
		var g := _ground(plan, lc, dir, along, lateral, ha, ri)
		if is_nan(g):
			continue
		# The loop's frame: +Z forward (fwd), +X the way the track shifts over the turn; the entry
		# lane is at x = 0, the exit at x = LOOP_SHIFT. The shift is toward the deck or away by hash.
		var right := Vector2(-fwd.y, fwd.x)
		var shift_dir := 1.0 if h01([plan.seed, "stunt_loop_side", ri, i]) < 0.5 else -1.0
		var x0 := lc - right * shift_dir * LOOP_SHIFT * 0.5
		# Godot: Basis(UP, yaw) turns +Z to (sin yaw, cos yaw) and +X to (cos yaw, -sin yaw); the
		# loop's shift is signed in that +X (StuntKit builds a loop shifting to -X as its mirror).
		var yaw := atan2(fwd.x, fwd.y)
		var plus_x := Vector2(cos(yaw), -sin(yaw))
		var shift := LOOP_SHIFT * signf(plus_x.dot(right * shift_dir))
		return [{"id": "stunt_loop_%d_%d" % [ri, i], "kind": Kind.LOOP, "p": Vector3(x0.x, g, x0.y), "yaw": yaw,
			"r": LOOP_R, "w": LOOP_W, "shift": shift, "run": LOOP_RUN,
			"paint": _paint(plan, "loop", ri * 1000 + i),
			"clear": Footbridges._turned_rect(lc, dir, along, lateral + 2.0, ha + 2.0), "route": ri, "index": i,
			"run_from": Vector3(x0.x - fwd.x * (LOOP_RUN + 25.0), g, x0.y - fwd.y * (LOOP_RUN + 25.0))}]
	return []


# --- The pier ------------------------------------------------------------------------------------

static func pier_sites(plan: CityPlan) -> Array:
	var pc := _plan_cache(plan)
	if pc.has("pier"):
		return pc.pier
	var out: Array = []
	pc.pier = out
	for lm: Dictionary in Landmarks.all():
		if String(lm.id) != PIER_ID:
			continue
		var a: Vector2 = lm.anchor
		var foot := a + PIER_AT
		# The run is out to sea, -X in the park's frame: yaw of -X is -PI / 2.
		out.append({"id": "stunt_pier", "kind": Kind.PIER, "p": Vector3(foot.x, PierPark.DECK_TOP, foot.y), "yaw": -PI * 0.5,
			"len": PIER_LEN, "h": PIER_H, "w": PIER_W, "paint": Color(0.86, 0.16, 0.10), "deck": true,
			"run_from": Vector3(foot.x + 60.0, PierPark.DECK_TOP, foot.y)})
	return out


# --- Vacant lots ---------------------------------------------------------------------------------

## A line of dirt jumps in this VACANT lot (VacantLots.plan_lot()'s plan `vp`), or {}: down the
## ruts from the gate, where the lot keeps its drive clear, and on only where nothing the lot
## dumped there (rubble, junk, a tree, the broken slab) stands in the line. Pure.
static func vacant_site(plan: CityPlan, lot: Dictionary, vp: Dictionary) -> Dictionary:
	if not enabled or vp.is_empty() or int(vp.kind) != VacantLots.VACANT:
		return {}
	if h01([plan.seed, int(lot.seed), "stunt_dirt"]) >= DIRT_ODDS:
		return {}
	var f: Dictionary = vp.frame
	var D: float = f.depth
	var L: float = f.len
	if D < DIRT_MIN_D or L < DIRT_W + 6.0:
		return {}
	if (vp.slab as Rect2).size != Vector2.ZERO:
		return {}
	var gate_u: float = vp.gate_u
	var u := clampf(gate_u, DIRT_W * 0.5 + 1.5, L - DIRT_W * 0.5 - 1.5)
	var v0 := 4.5
	var v1 := D - 1.8
	var lane := Industrial.fr(f, u - DIRT_W * 0.5 - 1.0, v0, u + DIRT_W * 0.5 + 1.0, v1)
	for it: Dictionary in vp.items:
		if not it.has("p"):
			continue
		var t := String(it.t)
		if t == "trespass" or t == "lease":
			continue
		var p: Vector2 = it.p
		var r := float(it.get("r", 1.4)) + 0.6
		if lane.intersects(Rect2(p - Vector2(r, r), Vector2(r, r) * 2.0)):
			return {}
	# Two or three tabletops, as many as fit: [start v, takeoff run, table, landing run, height].
	var jumps: Array = []
	var v := v0 + 1.0
	var k := 0
	while true:
		var h := lerpf(1.0, 1.7, h01([plan.seed, int(lot.seed), "stunt_dirt_h", k]))
		var take := h / tan(deg_to_rad(lerpf(26.0, 33.0, h01([plan.seed, int(lot.seed), "stunt_dirt_a", k]))))
		var table := lerpf(1.6, 3.2, h01([plan.seed, int(lot.seed), "stunt_dirt_t", k]))
		var land := h / tan(deg_to_rad(lerpf(14.0, 19.0, h01([plan.seed, int(lot.seed), "stunt_dirt_l", k]))))
		if v + take + table + land > v1 or k >= 3:
			break
		jumps.append([v, take, table, land, h])
		v += take + table + land + lerpf(3.5, 6.0, h01([plan.seed, int(lot.seed), "stunt_dirt_g", k]))
		k += 1
	if jumps.is_empty():
		return {}
	var foot := Industrial.fp(f, u, 0.0)
	var n: Vector2 = f.n
	var g := CityChunk.SIDEWALK_TOP + plan.macro.relief_at(Industrial.fp(f, u, D * 0.5))
	return {"id": "stunt_dirt_%d" % (int(lot.seed) % 1000000), "kind": Kind.DIRT, "p": Vector3(foot.x, g, foot.y),
		"yaw": atan2(n.x, n.y), "w": DIRT_W, "jumps": jumps, "lot": int(lot.seed), "depth": D}


# --- Paint ---------------------------------------------------------------------------------------

## Stunt-crew paint (sRGB): orange, yellow, red, blue, black, white.
const PAINTS: Array[Color] = [Color(0.92, 0.42, 0.06), Color(0.95, 0.74, 0.08), Color(0.78, 0.10, 0.08),
	Color(0.08, 0.28, 0.62), Color(0.10, 0.10, 0.11), Color(0.88, 0.88, 0.86)]


static func _paint(plan: CityPlan, what: String, k: int) -> Color:
	return PAINTS[absi(hash([plan.seed, "stunt_paint", what, k])) % PAINTS.size()]


## The lips of a site in its own frame: [[centre (local), forward (local), width, lip height]], what
## StuntDirector watches for a launch.
static func lips(s: Dictionary) -> Array:
	match int(s.kind):
		Kind.KICKER, Kind.PIER, Kind.LAUNCH:
			return [[Vector3(0.0, float(s.h), float(s.len)), Vector3(0.0, 0.0, 1.0), float(s.w), float(s.h)]]
		Kind.QPIPE:
			var a := deg_to_rad(float(s.angle))
			var r: float = s.r
			return [[Vector3(0.0, r * (1.0 - cos(a)), r * sin(a)), Vector3(0.0, sin(a), cos(a)), float(s.len), r * (1.0 - cos(a))]]
		Kind.DIRT:
			var out: Array = []
			for j: Array in s.jumps:
				out.append([Vector3(0.0, float(j[4]), float(j[0]) + float(j[1])), Vector3(0.0, 0.0, 1.0), float(s.w), float(j[4])])
			return out
	return []
