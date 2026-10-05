class_name Hospital
extends RefCounted
## Hospitals (2026-10-05, "hospitals the ambulances go to"): a modern hospital campus on a whole
## block - a bed tower with horizontal window bands over a podium, a glazed lobby behind the main
## entrance canopy and a drop-off loop on the front street, the EMERGENCY entrance on a side
## street with its big lit red sign and a covered ambulance bay (three bays, an ambulance parked,
## sliding doors), a helipad on the tower roof (a plain H: never the cross, which is a protected
## emblem), a parking structure (ArenaGrounds.garage) and planting. The ambulances bring their
## patients here (Emergency._finish -> EmergencyCar.to_hospital(): the unit drives to the nearest
## hospital's ER entrance, pulls past it, backs into a free bay and parks).
##
## WHERE is worked out, never placed (FireStation's approach): the map is cut into CELL x CELL
## squares; a hash of the seed and the cell says whether it has a hospital and gives CANDIDATES
## points in it; the first whose block is big enough, in a hospital district and clear of every
## other claim (downtown's 1:1 extent, landmarks and their sites, freeways, the light rail, the
## river, the airport's approach, the replica) is the hospital's block. One large MEDICAL CENTRE
## stands in Westlake west of downtown (the block nearest MEDICAL_TARGET that passes the same
## test, any size up from MEDICAL_MIN). Everything is pure geometry - the block's rect, district
## and the global claims - so CityPlan.block() can ask it for the block it is building without
## asking for any other block (no recursion), AFTER every roll and override of its own: the block
## gets `"hospital": true`, its kind is BUILDINGS and CityPlan.lots() is empty, so the far
## city, AirTraffic and every tier see no seeded buildings there. No rng anywhere: hashes of seed
## + cell + block only.
##
## Names are this game's own (BASIN GENERAL, MERIDIAN COMMUNITY, ...), never a real hospital's.

const CELL := 1500.0
const ODDS := 0.85
const CANDIDATES := 24
const DISTRICTS := [CityPlan.District.MIDTOWN, CityPlan.District.SUBURBS, CityPlan.District.BEACHTOWN, CityPlan.District.CAMPUS]
## The smallest block (inside its pavement ring, short x long side, m) a campus fits on.
const MIN_INNER := Vector2(56.0, 70.0)
## The medical centre near downtown: aimed at Westlake (between MacArthur Park and the 110, where
## the big hospitals west of downtown LA stand), the nearest block that passes from SPIRAL points.
const MEDICAL_TARGET := Vector2(1180.0, 420.0)
const MEDICAL_MIN := Vector2(64.0, 76.0)
const MEDICAL_DISTRICTS := [CityPlan.District.MIDTOWN, CityPlan.District.DOWNTOWN, CityPlan.District.SUBURBS]
const MEDICAL_NAME := "BASIN GENERAL MEDICAL CENTER"
const NAMES := ["MERIDIAN COMMUNITY HOSPITAL", "SYCAMORE CREST HOSPITAL", "LANTERN BAY MEDICAL CENTER",
	"CORAL HEIGHTS HOSPITAL", "JUNIPER PARK HOSPITAL", "CANYON VISTA MEDICAL CENTER", "ORCHARD GLEN HOSPITAL",
	"SUNSTONE MEDICAL CENTER", "MARIGOLD VALLEY HOSPITAL", "WILLOW REACH MEDICAL CENTER"]
## How far an ambulance will drive a patient (m); farther, it just leaves.
const TRANSPORT_REACH := 2600.0

## Off (HOSPITALS=0 in the environment): no hospitals, every block what it was (the A/B).
static var enabled: bool = OS.get_environment("HOSPITALS") != "0"
static var _cell_cache: Dictionary = {}
static var _medical_cache: Dictionary = {}
static var _layout_cache: Dictionary = {}


static func _h01(parts: Array) -> float:
	return float(absi(hash(parts)) % 100003) / 100003.0


static func _cell_of(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / CELL), floori(p.y / CELL))


## The rect of block (ix, iz), between its road edges, from the road positions alone (what
## CityPlan.block() computes, without building the block).
static func block_rect(plan: CityPlan, ix: int, iz: int) -> Rect2:
	var x0 := plan.road_pos(CityPlan.AXIS_X, ix) + plan.road_width(CityPlan.AXIS_X, ix) * 0.5
	var x1 := plan.road_pos(CityPlan.AXIS_X, ix + 1) - plan.road_width(CityPlan.AXIS_X, ix + 1) * 0.5
	var z0 := plan.road_pos(CityPlan.AXIS_Z, iz) + plan.road_width(CityPlan.AXIS_Z, iz) * 0.5
	var z1 := plan.road_pos(CityPlan.AXIS_Z, iz + 1) - plan.road_width(CityPlan.AXIS_Z, iz + 1) * 0.5
	return Rect2(x0, z0, x1 - x0, z1 - z0)


## True when block (ix, iz) could take a campus: big enough, a hospital district, plain city
## ground, clear of every other claim. Pure: no CityPlan.block() call.
static func _suitable(plan: CityPlan, ix: int, iz: int, districts: Array, min_inner: Vector2) -> bool:
	var macro: MacroMap = plan.macro
	if macro == null:
		return false
	var rect := block_rect(plan, ix, iz)
	var inner := rect.grow(-plan.sidewalk_width)
	if minf(inner.size.x, inner.size.y) < min_inner.x or maxf(inner.size.x, inner.size.y) < min_inner.y:
		return false
	if maxf(inner.size.x, inner.size.y) > 150.0:
		return false
	if not (int(plan.district_at(rect.get_center())) in districts):
		return false
	for p: Vector2 in [rect.position, rect.end, Vector2(rect.end.x, rect.position.y), Vector2(rect.position.x, rect.end.y), rect.get_center()]:
		if macro.zone_at(p) != MacroMap.Zone.CITY:
			return false
	if DowntownReal.in_extent(rect.get_center()) or Landmarks.claims(rect):
		return false
	if macro.freeway and macro.freeway.blocks_rect(rect, 8.0):
		return false
	var rail := LightRail.of(plan)
	if rail != null and (rail.blocks_rect(rect, 6.0) or not rail.cuts_in(rect).is_empty()):
		return false
	if macro.runway_clear_zone().grow(80.0).intersects(rect):
		return false
	if macro.replica and macro.replica._bounds.intersects(rect.grow(40.0)):
		return false
	if not plan.site_at_block(ix, iz).is_empty() or plan._beside_site(ix, iz) or plan.river_block(ix, iz):
		return false
	for lm in Landmarks.all():
		if lm.get("area") is Dictionary:
			continue
		var r: float = lm.radius
		if Rect2((lm.anchor as Vector2) - Vector2(r, r), Vector2(r, r) * 2.0).grow(20.0).intersects(rect):
			return false
	# Hilly ground: a campus wants a level block (the relief across it under 2.5 m).
	var lo := INF
	var hi := -INF
	for p: Vector2 in [rect.position, rect.end, Vector2(rect.end.x, rect.position.y), Vector2(rect.position.x, rect.end.y), rect.get_center()]:
		var h := macro.relief_at(p)
		lo = minf(lo, h)
		hi = maxf(hi, h)
	return hi - lo < 2.5


## The medical centre's block (Vector2i), or Vector2i.MAX when none fits.
static func medical_block(plan: CityPlan) -> Vector2i:
	if _medical_cache.has(plan.seed):
		return _medical_cache[plan.seed]
	var out := Vector2i.MAX
	_medical_cache[plan.seed] = out
	if not enabled or plan.macro == null:
		return out
	var c := plan.block_index_at(MEDICAL_TARGET)
	var best_d := INF
	for dx in range(-4, 5):
		for dz in range(-4, 5):
			var bi := c + Vector2i(dx, dz)
			if not _suitable(plan, bi.x, bi.y, MEDICAL_DISTRICTS, MEDICAL_MIN):
				continue
			var d := block_rect(plan, bi.x, bi.y).get_center().distance_to(MEDICAL_TARGET)
			if d < best_d:
				best_d = d
				out = bi
	_medical_cache[plan.seed] = out
	return out


## The hospital block of map cell `cell` (Vector2i.MAX for none). The cell holding the medical
## centre has no other.
static func cell_block(plan: CityPlan, cell: Vector2i) -> Vector2i:
	var key := Vector3i(plan.seed, cell.x, cell.y)
	if _cell_cache.has(key):
		return _cell_cache[key]
	var out := Vector2i.MAX
	_cell_cache[key] = out
	if not enabled or plan.macro == null:
		return out
	var med := medical_block(plan)
	if med != Vector2i.MAX and _cell_of(block_rect(plan, med.x, med.y).get_center()) == cell:
		return out
	if _h01([plan.seed, cell.x, cell.y, "hospital"]) > ODDS:
		return out
	for k in CANDIDATES:
		var target := Vector2((float(cell.x) + lerpf(0.15, 0.85, _h01([plan.seed, cell.x, cell.y, k, "hx"]))) * CELL,
				(float(cell.y) + lerpf(0.15, 0.85, _h01([plan.seed, cell.x, cell.y, k, "hz"]))) * CELL)
		if plan.macro.zone_at(target) != MacroMap.Zone.CITY:
			continue
		var bi := plan.block_index_at(target)
		if _cell_of(block_rect(plan, bi.x, bi.y).get_center()) != cell:
			continue
		if _suitable(plan, bi.x, bi.y, DISTRICTS, MIN_INNER):
			out = bi
			break
	_cell_cache[key] = out
	return out


## True when block (ix, iz) is a hospital's (CityPlan.block() asks, after its own rolls).
static func claims_block(plan: CityPlan, ix: int, iz: int) -> bool:
	if not enabled or plan.macro == null:
		return false
	var bi := Vector2i(ix, iz)
	if medical_block(plan) == bi:
		return true
	return cell_block(plan, _cell_of(block_rect(plan, ix, iz).get_center())) == bi


static func is_hospital(block: Dictionary) -> bool:
	return block.get("hospital", false)


## Every hospital block within `reach` of `p` (true world XZ).
static func blocks_near(plan: CityPlan, p: Vector2, reach: float) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var c := _cell_of(p)
	var n := ceili(reach / CELL)
	for dx in range(-n, n + 1):
		for dz in range(-n, n + 1):
			var bi := cell_block(plan, c + Vector2i(dx, dz))
			if bi != Vector2i.MAX:
				out.append(bi)
	var med := medical_block(plan)
	if med != Vector2i.MAX and not out.has(med):
		out.append(med)
	var kept: Array[Vector2i] = []
	for bi in out:
		if block_rect(plan, bi.x, bi.y).get_center().distance_to(p) <= reach:
			kept.append(bi)
	return kept


# --- Layout --------------------------------------------------------------------------------------

## The campus of block (ix, iz), all in a frame on the block's inner rect: `o`, `a` (u, along the
## front street), `n` (v, back from it), `W` x `D` (the inner rect's size in u and v), the front
## road and the ER road ([axis, index]), the ER side's sign (`er_right`: the ER street is at
## u = W), and the pieces as frame rects (Rect2 in u, v): `podium`, `tower`, `court` (the
## ambulance court), `canopy` (the bays' roof), `bays` (Array of [u, v] bay centres, the
## ambulance's rear toward the building), `loop` (the drop-off drive), `garage`, `lot` (a surface
## car park, or an empty Rect2), heights (`podium_h`, `tower_h`, `storeys`), the name and
## `medical`. Cached.
static func layout(plan: CityPlan, ix: int, iz: int) -> Dictionary:
	var key := Vector3i(plan.seed, ix, iz)
	if _layout_cache.has(key):
		return _layout_cache[key]
	var rect := block_rect(plan, ix, iz)
	var inner := rect.grow(-plan.sidewalk_width)
	var roads := [[CityPlan.AXIS_Z, iz], [CityPlan.AXIS_Z, iz + 1], [CityPlan.AXIS_X, ix], [CityPlan.AXIS_X, ix + 1]]
	var widths: Array[float] = []
	for r: Array in roads:
		widths.append(plan.road_width(int(r[0]), int(r[1])) + _h01([plan.seed, ix, iz, int(r[0]), int(r[1]), "hw"]) * 0.5)
	# The front is the widest road whose side is long enough to be the frontage; the ER street the
	# wider of the two beside it.
	var front := 0
	var best := -1.0
	for s in 4:
		var f := Industrial.frame(inner, s)
		if float(f.len) < 56.0 or float(f.depth) < 66.0:
			continue
		if widths[s] > best:
			best = widths[s]
			front = s
	var f0 := Industrial.frame(inner, front)
	var a: Vector2 = f0.a
	var side_right := _side_facing(a)
	var side_left := _side_facing(-a)
	var er_right := widths[side_right] >= widths[side_left]
	var o: Vector2 = f0.o
	if not er_right:
		o = o + a * float(f0.len)
		a = -a
	var lay := {"o": o, "a": a, "n": f0.n, "W": float(f0.len), "D": float(f0.depth), "front_side": front,
		"er_side": side_right if er_right else side_left, "front_road": roads[front], "er_road": roads[side_right if er_right else side_left],
		"er_right": er_right, "inner": inner, "block": Vector2i(ix, iz)}
	var medical := medical_block(plan) == Vector2i(ix, iz)
	lay.medical = medical
	var W: float = lay.W
	var D: float = lay.D
	var front_v := 19.0
	var court_w := 25.0
	# The garage behind the podium where the block is deep enough, else a surface lot.
	var gd := clampf(D - front_v - 4.0 - 34.0, 0.0, 36.0)
	var garage := gd >= 22.0
	var pd := minf(D - front_v - (gd + 5.0 if garage else 5.0), 52.0)
	var podium := Rect2(6.0, front_v, W - court_w - 6.0, pd)
	lay.podium = podium
	lay.podium_h = 13.2
	# The bed tower: a slab along the street over the podium's front half, its storeys by a hash
	# (the medical centre taller).
	var storeys := 6 + absi(hash("%d:%d:%d:storeys" % [plan.seed, ix, iz])) % 6
	if medical:
		storeys = 14 + int(_h01([plan.seed, ix, iz, "storeys"]) * 3.0)
	lay.storeys = storeys
	var tw := minf(podium.size.x - 6.0, 58.0 if medical else 48.0)
	var td := minf(19.0 if not medical else 22.0, podium.size.y - 6.0)
	var tu := podium.position.x + (podium.size.x - tw) * (0.35 + 0.3 * _h01([plan.seed, ix, iz, "tu"]))
	lay.tower = Rect2(tu, podium.position.y + 3.0, tw, td)
	lay.tower_h = float(storeys) * 3.9
	# The ambulance court on the ER street, its three bays under a canopy against the podium's
	# ER-side wall; the ambulances back in, their rear to the doors.
	var court_v0 := podium.position.y + 4.0
	var court := Rect2(W - court_w, court_v0, court_w, minf(31.0, pd - 2.0))
	lay.court = court
	var canopy := Rect2(W - court_w, court_v0 + 2.0, 11.5, 15.6)
	lay.canopy = canopy
	var bays: Array = []
	for k in 3:
		bays.append(Vector2(W - court_w + 4.4, canopy.position.y + 2.6 + float(k) * 5.2))
	lay.bays = bays
	lay.er_door = Vector2(W - court_w, canopy.position.y + canopy.size.y * 0.5)
	# The court's mouth on the ER street (frame u = W), the middle of the drive across the pavement.
	lay.court_mouth = Vector2(W, court.position.y + court.size.y * 0.5)
	lay.loop = Rect2(podium.position.x + podium.size.x * 0.5 - 21.0, 1.5, 42.0, front_v - 1.5)
	if garage:
		lay.garage = Rect2(2.0, D - gd, minf(W - court_w - 4.0, 72.0), gd - 1.0)
	else:
		lay.garage = Rect2()
	var lot_v0 := court.end.y + 3.0
	lay.lot = Rect2(W - court_w + 1.0, lot_v0, court_w - 2.0, D - lot_v0 - 1.0) if D - lot_v0 > 18.0 else Rect2()
	# Neighbouring cells take neighbouring names (no two hospitals near each other share one).
	var cell := _cell_of(block_rect(plan, ix, iz).get_center())
	lay.name = MEDICAL_NAME if medical else NAMES[posmod(cell.x * 3 + cell.y * 7 + absi(plan.seed) % 5, NAMES.size())]
	lay.seed = absi(hash([plan.seed, ix, iz, "hospital"]))
	# The campus's one floor level: the pavement at the block's highest corner (HospitalBuild
	# stands everything on it; an ambulance backing in drives on it).
	var hi := -INF
	for p: Vector2 in [inner.position, inner.end, Vector2(inner.end.x, inner.position.y), Vector2(inner.position.x, inner.end.y), inner.get_center()]:
		hi = maxf(hi, plan.macro.relief_at(p) if plan.macro else 0.0)
	lay.floor_gy = hi
	_layout_cache[key] = lay
	return lay


## The block side whose road a frame direction `d` points at (0 -z, 1 +z, 2 -x, 3 +x).
static func _side_facing(d: Vector2) -> int:
	if absf(d.x) > absf(d.y):
		return 3 if d.x > 0.0 else 2
	return 1 if d.y > 0.0 else 0


## A frame point (u, v) in true world XZ.
static func fp(lay: Dictionary, u: float, v: float) -> Vector2:
	return (lay.o as Vector2) + (lay.a as Vector2) * u + (lay.n as Vector2) * v


## A frame rect as a world rect.
static func fr(lay: Dictionary, r: Rect2) -> Rect2:
	var p := fp(lay, r.position.x, r.position.y)
	var q := fp(lay, r.end.x, r.end.y)
	return Rect2(Vector2(minf(p.x, q.x), minf(p.y, q.y)), Vector2(absf(q.x - p.x), absf(q.y - p.y)))


## Where the drives cross the pavement (true world XZ points on the kerb line, and the road each
## meets): the drop-off loop's entry and exit and the ambulance court's mouth.
static func kerb_cuts(plan: CityPlan, lay: Dictionary) -> Array:
	var sw := plan.sidewalk_width
	var loop: Rect2 = lay.loop
	var out := []
	for u: float in [loop.position.x + 3.5, loop.end.x - 3.5]:
		out.append({"at": fp(lay, u, -sw), "road": lay.front_road, "width": 7.0})
	var m: Vector2 = lay.court_mouth
	out.append({"at": fp(lay, m.x + sw, m.y), "road": lay.er_road, "width": 9.0})
	return out


## True when `p` (true world XZ) is on a kerb a hospital's drive crosses, which no parked car may
## block (CityChunk._park_car asks, after its rolls).
static func keeps_clear(plan: CityPlan, p: Vector2) -> bool:
	if not enabled:
		return false
	var bi := plan.block_index_at(p)
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			var b := bi + Vector2i(dx, dz)
			if not claims_block(plan, b.x, b.y):
				continue
			for cut: Dictionary in kerb_cuts(plan, layout(plan, b.x, b.y)):
				if (cut.at as Vector2).distance_to(p) < float(cut.width) * 0.5 + 6.0:
					return true
	return false


## The nearest hospital to `p` (true world XZ) within `reach`: its layout, or {}.
static func nearest(plan: CityPlan, p: Vector2, reach: float = TRANSPORT_REACH) -> Dictionary:
	if plan == null or not enabled:
		return {}
	var best := {}
	var best_d := reach
	for bi in blocks_near(plan, p, reach):
		var lay := layout(plan, bi.x, bi.y)
		var d := fp(lay, (lay.court_mouth as Vector2).x, (lay.court_mouth as Vector2).y).distance_to(p)
		if d < best_d:
			best_d = d
			best = lay
	return best


## Where an ambulance stops on the ER street before backing in: the kerb point at the court's
## mouth (true world XZ) - its goal for StreetRoute.kerb_stop.
static func er_goal(lay: Dictionary) -> Vector2:
	var m: Vector2 = lay.court_mouth
	return fp(lay, m.x - 2.0, m.y)


## Bays taken by ambulances that backed in (block -> bay index -> unit), so the next takes another.
static var _bays_taken: Dictionary = {}


## A free bay of `lay` for `car` (its index 1..2; bay 0 holds the parked ambulance), or -1.
static func take_bay(lay: Dictionary, car: Object) -> int:
	var key: Vector2i = lay.block
	var taken: Dictionary = _bays_taken.get(key, {})
	for k in [1, 2]:
		var who: Variant = taken.get(k)
		if who == null or not is_instance_valid(who) or who == car:
			taken[k] = car
			_bays_taken[key] = taken
			return k
	return -1


static func free_bay(lay: Dictionary, car: Object) -> void:
	var taken: Dictionary = _bays_taken.get(lay.block, {})
	for k in taken.keys():
		if taken[k] == car:
			taken.erase(k)


## The path an ambulance backs into bay `k` along: [[true world XZ, yaw]...] from `start` (its
## stop on the ER street, heading `dir2`), first pulling forward past the mouth, then reversing in
## a curve into the bay, nose to the street. Sampled every metre or so.
static func back_in_path(lay: Dictionary, k: int, start: Vector2, dir2: Vector2) -> Array:
	var out: Array = []
	var bay: Vector2 = (lay.bays as Array)[k]
	var bay_w := fp(lay, bay.x, bay.y)
	var out_dir := (lay.a as Vector2)
	# Forward to a point past the mouth on the lane the car is in.
	var mouth := fp(lay, (lay.court_mouth as Vector2).x, (lay.court_mouth as Vector2).y)
	var lane_off := (start - mouth).dot(out_dir)
	var lane_pt := mouth + out_dir * lane_off
	var past := lane_pt + dir2 * 11.0
	var yaw0 := atan2(-dir2.x, -dir2.y)
	var fwd_len := maxf(start.distance_to(past), 0.1)
	var n_fwd := maxi(2, int(fwd_len / 1.0))
	for i in n_fwd + 1:
		out.append([start.lerp(past, float(i) / float(n_fwd)), yaw0, false])
	# Then back: a Bezier from `past` (moving -dir2) into the bay (moving -out_dir, inward).
	var c1 := past - dir2 * 8.0
	var c2 := bay_w + out_dir * 9.0
	var steps := 26
	var prev := past
	for i in range(1, steps + 1):
		var t := float(i) / float(steps)
		var mt := 1.0 - t
		var p := past * mt * mt * mt + c1 * 3.0 * mt * mt * t + c2 * 3.0 * mt * t * t + bay_w * t * t * t
		var motion := (p - prev).normalized()
		# Reversing: the car faces against its motion.
		var yaw := atan2(motion.x, motion.y)
		out.append([p, yaw, true])
		prev = p
	return out


