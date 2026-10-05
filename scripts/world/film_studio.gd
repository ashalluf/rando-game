class_name FilmStudio
extends RefCounted
## A Hollywood film studio lot (2026-10-05, "a walled block of huge numbered sound stages"): the
## invented SUNSPIRE PICTURES, in MIDTOWN under the ridge sign, the form of the old lots off
## Melrose and Gower. What is there:
##   - a stucco wall with pilasters round the whole lot, a public pavement outside it;
##   - the main gate on the south street: two pylons and the arch with the studio's name and mark
##     in gilt, a guard booth on the island between the lanes, barrier arms, the iron gates open;
##   - numbered SOUND STAGES (FilmStudioKit.stage()): huge beige stucco sheds with pilasters, a
##     low gable roof of standing seam, ELEPHANT DOORS on the long walls with a red light over
##     each (lit by day on the stages that are shooting), the stage number painted big on the
##     walls and the gables, plant and a zig-zag stair to the roof;
##   - the front lot: the studio's office block facing the gate, rows of office bungalows (HouseKit
##     houses - Spanish revival and craftsman - with lawns), and the studio's WATER TOWER with its
##     mark and name painted round the tank;
##   - the BACKLOT: a "New York street" of false fronts (brownstones with stoops, tenements with
##     fire escapes, shopfronts with awnings and signs) facing each other across a street, their
##     plywood backs braced by raked struts down to sandbags;
##   - basecamp: production trailers, honeywagons and five-ton grip trucks parked along the studio
##     streets, golf carts and equipment at the stage doors, parked cars, crews walking.
##
## How it sits on the map: its Landmarks entry carries an "area" (like MacArthur Park and the
## canals) that CityPlan snaps to whole blocks and closes every road inside; the closed roads are
## the lot's own streets. Its chunks build their part (site_steps()), the far city records its
## massing (capture_steps()). Every roll is a hash of the seed and the place, never a block rng.
## The layout is pure (layout(), cached per plan), so every chunk and every tier agrees.
##
## FILM_STUDIO=0 in the environment: no entry, no site - the blocks are ordinary midtown (the A/B).

const SITE_ID := "film_studio"

static var enabled: bool = OS.get_environment("FILM_STUDIO") != "0"

# --- Where -------------------------------------------------------------------------------------
## The area CityPlan snaps to whole blocks (world metres): three blocks by two in midtown, south
## of the ridge sign and its hills - on the default seed the streets at x 568 / 804 and z -777 /
## -403. Another seed's grid moves the snapped rect with it.
const ANCHOR := Vector2(686.0, -590.0)
const WEST_X := 568.4
const EAST_X := 803.5
const NORTH_Z := -776.8
const SOUTH_Z := -403.4
## The entry's radius (the minimap pin, lots near it). The relief is NOT flattened by it but over
## the area itself (`flat_rect`, MacroMap._relief_at()), out to FLAT_MARGIN: a disc big enough to
## flatten the lot (205 m, + 150 m of fade) reached the front range's foot and the switchback
## drives grown there lost half their length (tests/smoke_test.gd's switchback check).
const RADIUS := 30.0
const FLAT_MARGIN := 70.0

# --- The section (metres) -----------------------------------------------------------------------
## The public pavement round the lot, inside the perimeter kerbs.
const PAVEMENT := 4.5
## The service lane inside the wall.
const LANE := 7.0
## Set back from a closed road (the lot's own street) on an inner side of a sub-block.
const INNER_SET := 2.5
## The gate's opening.
const GATE_W := 13.0
## The ground inside the wall (Industrial's yard ground, a little over the pavement).
const BASE_Y := CityChunk.SIDEWALK_TOP + Industrial.LIFT
## The gap between stages in a row, and their sizes.
const ALLEY := 11.0
const STAGE_W := Vector2(26.0, 46.0)
const STAGE_L := Vector2(42.0, 62.0)
const STAGE_H := Vector2(14.0, 19.0)

# --- Density and draw ---------------------------------------------------------------------------
## Walkers (crew) per metre of studio street.
const CREW_PER_M := 1.0 / 26.0
const VEHICLE_DRAW := 260.0
## The bungalows' styles (HouseKit, BEACH_STYLES' form): Spanish revival and craftsman mostly.
const STYLES := [[HouseKit.Style.SPANISH, 0.48], [HouseKit.Style.CRAFTSMAN, 0.82], [HouseKit.Style.RANCH, 0.92], [HouseKit.Style.STUCCO_BOX, 1.0]]

static var _layouts: Dictionary = {}


## The entry Landmarks.all() lists: id, anchor, a radius (relief flattening) and the area CityPlan
## snaps to the grid. No kept roads: the streets inside are the studio's.
static func entry() -> Dictionary:
	return {"id": SITE_ID, "anchor": ANCHOR, "radius": RADIUS,
		"flat_rect": Rect2(WEST_X - 15.0, NORTH_Z - 15.0, EAST_X - WEST_X + 30.0, SOUTH_Z - NORTH_Z + 30.0), "flat_margin": FLAT_MARGIN,
		"area": {"west_x": WEST_X, "east_x": EAST_X, "north_z": NORTH_Z, "south_z": SOUTH_Z, "keep_z": [], "streets": {}}}


static func h01(parts: Array) -> float:
	return FilmStudioKit.h01(parts)


# =================================================================================================
# Layout (pure)
# =================================================================================================

## {"site", "rect" (kerb to kerb), "wall" (the wall's centre line, a rect), "inner" (inside the
## wall), "gate": {"at": Vector2 (on the wall line), "w"}, "subs": [{"bx", "bz", "content",
## "role" (front / stages / backlot / yard), "long_z"}], "stages": [{"c", "size" (x across, y
## height, z along), "yaw", "number", "doors", "seed", "rolling"}], "offices", "lots", "tower",
## "fronts": [{"at", "yaw", "w", "h", "style", "seed"}], "backlot_street", "streets"
## (the closed roads inside, as rects), "parking": [{"at", "yaw", "kind", "length", "seed"}],
## "carts", "gear", "lamps", "cars"}. {} without the site.
static func layout(plan: CityPlan) -> Dictionary:
	if plan == null or not enabled:
		return {}
	var key := plan.get_instance_id()
	if _layouts.has(key):
		return _layouts[key]
	var lay := _make_layout(plan)
	_layouts[key] = lay
	return lay


static func _make_layout(plan: CityPlan) -> Dictionary:
	var s := plan.site_by_id(SITE_ID)
	if s.is_empty():
		return {}
	var ps := plan.seed
	var rect: Rect2 = s.rect
	var wall := rect.grow(-(PAVEMENT + FilmStudioKit.WALL_T * 0.5))
	var inner := rect.grow(-(PAVEMENT + FilmStudioKit.WALL_T))
	var edge := PAVEMENT + FilmStudioKit.WALL_T + LANE
	var lay := {"site": s, "rect": rect, "wall": wall, "inner": inner, "subs": [], "stages": [], "lots": [],
		"fronts": [], "parking": [], "carts": [], "gear": [], "lamps": [], "cars": [],
		"streets": [], "backlot_walks": [], "offices": {}, "tower": Vector2.INF, "backlot_street": Rect2()}
	# The sub-blocks and what each holds.
	var subs: Array = []
	for bx in range(int(s.ix0), int(s.ix1)):
		for bz in range(int(s.iz0), int(s.iz1)):
			var b: Rect2 = plan.block(bx, bz).rect
			var x0 := b.position.x + (edge if bx == int(s.ix0) else INNER_SET)
			var x1 := b.end.x - (edge if bx == int(s.ix1) - 1 else INNER_SET)
			var z0 := b.position.y + (edge if bz == int(s.iz0) else INNER_SET)
			var z1 := b.end.y - (edge if bz == int(s.iz1) - 1 else INNER_SET)
			if x1 - x0 < 8.0 or z1 - z0 < 8.0:
				continue
			var c := Rect2(x0, z0, x1 - x0, z1 - z0)
			subs.append({"bx": bx, "bz": bz, "content": c, "long_z": c.size.y >= c.size.x, "role": "yard"})
	if subs.is_empty():
		return {}
	# The gate: on the south wall, at the middle of the south-row sub-block nearest the lot's middle.
	var front: Dictionary = {}
	for sub: Dictionary in subs:
		if int(sub.bz) != int(s.iz1) - 1:
			continue
		if front.is_empty() or absf((sub.content as Rect2).get_center().x - rect.get_center().x) < absf((front.content as Rect2).get_center().x - rect.get_center().x):
			front = sub
	if front.is_empty():
		front = subs[0]
	front.role = "front"
	var gate_x := clampf((front.content as Rect2).get_center().x, inner.position.x + GATE_W, inner.end.x - GATE_W)
	lay.gate = {"at": Vector2(gate_x, wall.end.y), "w": GATE_W}
	# The backlot: the sub-block farthest from the gate that is big enough for a street of fronts.
	var best := -1.0
	var backlot: Dictionary = {}
	for sub: Dictionary in subs:
		if sub == front:
			continue
		var c: Rect2 = sub.content
		if minf(c.size.x, c.size.y) < 34.0 or maxf(c.size.x, c.size.y) < 80.0:
			continue
		var d := c.get_center().distance_to(lay.gate.at as Vector2)
		if d > best:
			best = d
			backlot = sub
	if not backlot.is_empty():
		backlot.role = "backlot"
	for sub: Dictionary in subs:
		if sub.role == "yard" and minf((sub.content as Rect2).size.x, (sub.content as Rect2).size.y) >= STAGE_W.x + 4.0:
			sub.role = "stages"
	lay.subs = subs
	# Stages, numbered across the lot from the north-west.
	var order := subs.duplicate()
	order.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.bz) * 1000 + int(a.bx) < int(b.bz) * 1000 + int(b.bx))
	var number := 1 + int(h01([ps, "stage_first"]) * 2.0)
	for sub: Dictionary in order:
		if sub.role != "stages":
			continue
		number = _plan_stages(lay, sub, ps, number)
	_plan_front(plan, lay, front, ps)
	if not backlot.is_empty():
		_plan_backlot(lay, backlot, ps)
	for sub: Dictionary in subs:
		if sub.role == "yard":
			_plan_yard(lay, sub, ps)
	_plan_streets(plan, lay, ps)
	return lay


## Stages in a row along the sub-block's long axis.
static func _plan_stages(lay: Dictionary, sub: Dictionary, ps: int, number: int) -> int:
	var c: Rect2 = sub.content
	var long_z: bool = sub.long_z
	var along := c.size.y if long_z else c.size.x
	var across := c.size.x if long_z else c.size.y
	var key := [ps, "stage", sub.bx, sub.bz]
	var W := clampf(across - 6.0, STAGE_W.x, STAGE_W.y)
	var want_l := lerpf(STAGE_L.x, STAGE_L.y, h01(key + ["l"]))
	var n := maxi(1, int((along - 4.0 + ALLEY) / (want_l + ALLEY)))
	var L := minf(STAGE_L.y + 6.0, (along - 4.0 - ALLEY * float(n - 1)) / float(n))
	if L < 24.0:
		return number
	var total := L * float(n) + ALLEY * float(n - 1)
	var start := (along - total) * 0.5
	for k in n:
		var t := start + L * 0.5 + (L + ALLEY) * float(k)
		var centre := Vector2(c.get_center().x, c.position.y + t) if long_z else Vector2(c.position.x + t, c.get_center().y)
		var sk := key + [k]
		var sd := absi(hash(sk))
		var H := lerpf(STAGE_H.x, STAGE_H.y, h01(sk + ["h"]))
		# Doors: one on each long wall, the two staggered; a second on one side of a long stage.
		var doors: Array = []
		var dw := lerpf(7.5, 10.5, h01(sk + ["dw"]))
		var dh := minf(H - 3.5, lerpf(8.0, 10.5, h01(sk + ["dh"])))
		var off := L * 0.2 * (1.0 if h01(sk + ["dz"]) < 0.5 else -1.0)
		doors.append([1.0, off, dw, dh])
		doors.append([-1.0, -off, dw, dh])
		if L > 50.0:
			doors.append([1.0 if h01(sk + ["d3"]) < 0.5 else -1.0, -off * 2.0 if absf(off * 2.0) < L * 0.5 - dw * 0.6 - 2.0 else 0.0, dw * 0.85, dh * 0.9])
		lay.stages.append({"c": centre, "size": Vector3(W, H, L), "yaw": 0.0 if long_z else PI * 0.5, "number": number,
			"doors": doors, "seed": sd, "rolling": h01(sk + ["rolling"]) < 0.35})
		# Golf carts and gear at the first door, on the street side.
		var dsd := float(doors[0][0])
		var dz := float(doors[0][1])
		var door_pos := _local_to_world(centre, 0.0 if long_z else PI * 0.5, Vector2(dsd * (W * 0.5 + 4.2), dz + dw * 0.5 + 3.5))
		var yaw := (0.0 if long_z else PI * 0.5)
		var ncart := 1 + int(h01(sk + ["carts"]) * 3.0)
		for q in ncart:
			var p := _local_to_world(centre, yaw, Vector2(dsd * (W * 0.5 + 2.2), dz + dw * 0.5 + 2.0 + 1.6 * float(q)))
			lay.carts.append({"at": p, "yaw": yaw + PI * 0.5 * dsd, "seed": absi(hash(sk + ["cart", q]))})
		lay.gear.append({"at": _local_to_world(centre, yaw, Vector2(dsd * (W * 0.5 + 2.4), dz - dw * 0.5 - 3.0)), "yaw": yaw + PI * 0.5 * dsd, "seed": absi(hash(sk + ["gear"]))})
		lay.lamps.append({"at": door_pos, "pool": true})
		number += 1
	return number


## A point in a frame centred on `c` turned by `yaw` (local x across, y = along +z) to world XZ.
static func _local_to_world(c: Vector2, yaw: float, p: Vector2) -> Vector2:
	return c + Vector2(p.x * cos(yaw) + p.y * sin(yaw), -p.x * sin(yaw) + p.y * cos(yaw))


## The front lot: the office block facing the gate, rows of bungalows, the water tower at the far end.
static func _plan_front(plan: CityPlan, lay: Dictionary, sub: Dictionary, ps: int) -> void:
	var c: Rect2 = sub.content
	var gz := (lay.gate.at as Vector2).y
	# The office block across the gate end, a forecourt between.
	var ow := minf(c.size.x - 6.0, 52.0)
	var od := 14.0
	var oz := c.end.y - 12.0 - od * 0.5
	lay.offices = {"c": Vector2(c.get_center().x, oz), "size": Vector3(ow, 13.5, od), "storeys": 3}
	# The forecourt between it and the gate: a flagpole lawn, a drive round it.
	var lot_end := oz - od * 0.5 - 6.0
	var lot_start := c.position.y + 18.0
	lay.tower = Vector2(c.get_center().x, c.position.y + 9.0)
	if lot_end - lot_start < 14.0:
		return
	var rows := 2 if c.size.x >= 40.0 else 1
	var path := 4.0
	var depth := (c.size.x - path) / float(rows) if rows == 2 else c.size.x
	var n := maxi(1, roundi((lot_end - lot_start) / 17.0))
	var w := (lot_end - lot_start) / float(n)
	for r in rows:
		var side := 2 if r == 0 else 3
		var x0 := c.position.x if r == 0 else c.end.x - depth
		for k in n:
			var cell := Rect2(x0, lot_start + w * float(k), depth, w)
			var sd := hash([ps, "studio_bungalow", sub.bx, sub.bz, r, k])
			var lot := {"seed": sd, "center": cell.get_center(), "size": cell.size, "cell": cell, "side": side, "yard": cell}
			lay.lots.append(lot)
	lay.front_walk = Rect2(c.get_center().x - path * 0.5, lot_start, path, lot_end - lot_start) if rows == 2 else Rect2()


## The house a bungalow lot gets: HouseKit's plan fronted on the studio street, no garage.
static func house_for(plan: CityPlan, lot: Dictionary) -> Dictionary:
	if lot.has("house"):
		return lot.house
	var front := {"side": int(lot.side), "yard": lot.yard, "walk_front": true, "styles": STYLES}
	var h := HouseKit.plan_fronted(plan, lot, CityPlan.District.SUBURBS, front)
	if not (h.garage as Dictionary).is_empty():
		var gw: Dictionary = h.wings[int(h.garage.wing)]
		if gw.role == "garage" or gw.role == "carport":
			gw.role = "room"
		h.garage = {}
		h.drive = Vector2.ZERO
	lot["house"] = h
	return h


## The backlot: a street of false fronts along the sub-block's long axis.
static func _plan_backlot(lay: Dictionary, sub: Dictionary, ps: int) -> void:
	var c: Rect2 = sub.content
	var long_z: bool = sub.long_z
	var along := c.size.y if long_z else c.size.x
	var street := 11.0
	var walk := 3.2
	var a0 := 6.0
	var a1 := along - 6.0
	var centre := c.get_center()
	# The street: in a frame along the long axis, x across from the centre line.
	var yaw := 0.0 if long_z else PI * 0.5
	lay.backlot = {"c": centre, "yaw": yaw, "along": along, "street": street, "walk": walk, "a0": a0, "a1": a1}
	var sr := Rect2(centre.x - (street * 0.5 + walk), c.position.y + a0, street + walk * 2.0, a1 - a0) if long_z \
		else Rect2(c.position.x + a0, centre.y - (street * 0.5 + walk), a1 - a0, street + walk * 2.0)
	lay.backlot_street = sr
	for sgn: float in [-1.0, 1.0]:
		var lo := sgn * (street * 0.5) if sgn > 0.0 else -(street * 0.5 + walk)
		var wr := Rect2(centre.x + lo, c.position.y + a0, walk, a1 - a0) if long_z else Rect2(c.position.x + a0, centre.y - lo - walk, a1 - a0, walk)
		lay.backlot_walks.append(wr)
		var lt := a0 + 9.0 + (9.0 if sgn > 0.0 else 0.0)
		while lt < a1 - 4.0:
			var lp := _local_to_world(centre, yaw, Vector2(sgn * (street * 0.5 + 0.5), lt - along * 0.5))
			var toward := _local_to_world(Vector2.ZERO, yaw, Vector2(-sgn, 0.0))
			lay.lamps.append({"at": lp, "ny": true, "yaw": atan2(toward.x, toward.y)})
			lt += 18.0
	for sgn: float in [-1.0, 1.0]:
		# Fronts on side sgn face the street (toward -sgn across).
		var t := a0
		var k := 0
		while t < a1 - 6.0:
			var fk := [ps, "front", sub.bx, sub.bz, sgn, k]
			var w := lerpf(6.5, 11.0, h01(fk + ["w"]))
			if t + w > a1:
				w = a1 - t
			if w < 5.0:
				break
			var style := int(h01(fk + ["style"]) * 5.0) % 5
			var fh := lerpf(10.0, 19.0, h01(fk + ["h"]))
			if style == FilmStudioKit.Facade.BROWNSTONE:
				fh = minf(fh, 15.0)
			# The face is at across = sgn * (street/2 + walk); local frame: +x along the row, +z
			# toward the street. Along the long axis this row runs +t on one side, -t on the other.
			var across := sgn * (street * 0.5 + walk + 0.3)
			var t_start := t + w if sgn < 0.0 else t
			var p := Vector2(across, t_start - along * 0.5)
			var at := _local_to_world(centre, yaw, p)
			var fyaw := yaw + (PI * 0.5 if sgn < 0.0 else -PI * 0.5)
			lay.fronts.append({"at": at, "yaw": fyaw, "w": w, "h": fh, "style": style, "seed": absi(hash(fk))})
			t += w
			k += 1
	# Parked cars along the backlot street's kerbs.
	var nc := int((a1 - a0) / 7.0)
	for q in nc:
		if h01([ps, "bl_car", q]) < 0.45:
			continue
		var sgn := -1.0 if q % 2 == 0 else 1.0
		var p := _local_to_world(centre, yaw, Vector2(sgn * (street * 0.5 - 1.3), a0 + 5.0 + 7.0 * float(q) - along * 0.5))
		lay.cars.append({"at": p, "yaw": yaw + (0.0 if sgn > 0.0 else PI), "seed": absi(hash([ps, "bl_car", q]))})


## A yard sub-block (too small for a stage): the mill's sheds and a trailer park.
static func _plan_yard(lay: Dictionary, sub: Dictionary, ps: int) -> void:
	var c: Rect2 = sub.content
	var long_z: bool = sub.long_z
	var along := c.size.y if long_z else c.size.x
	var yaw := 0.0 if long_z else PI * 0.5
	var n := int((along - 4.0) / 14.0)
	for k in n:
		var p := _local_to_world(c.get_center(), yaw, Vector2(0.0, -along * 0.5 + 9.0 + 14.0 * float(k)))
		var kind := "trailer" if h01([ps, "yard", sub.bx, sub.bz, k]) < 0.7 else "truck"
		lay.parking.append({"at": p, "yaw": yaw + PI * 0.5, "kind": kind, "length": 11.0, "seed": absi(hash([ps, "yard", sub.bx, sub.bz, k])), "band": k % 4})


## The studio streets (the closed roads inside the lot and the lane in the wall): basecamp parked
## along one side, lamps on the other.
static func _plan_streets(plan: CityPlan, lay: Dictionary, ps: int) -> void:
	var s: Dictionary = lay.site
	var inner: Rect2 = lay.inner
	var crossings: Array[Rect2] = []
	for ix in range(int(s.ix0) + 1, int(s.ix1)):
		var w := plan.road_width(0, ix)
		var r := Rect2(plan.road_pos(0, ix) - w * 0.5, inner.position.y, w, inner.size.y)
		lay.streets.append({"rect": r, "axis": 0, "index": ix})
	for iz in range(int(s.iz0) + 1, int(s.iz1)):
		var w := plan.road_width(1, iz)
		var r := Rect2(inner.position.x, plan.road_pos(1, iz) - w * 0.5, inner.size.x, w)
		lay.streets.append({"rect": r, "axis": 1, "index": iz})
	for a: Dictionary in lay.streets:
		for b: Dictionary in lay.streets:
			if int(a.axis) == 0 and int(b.axis) == 1:
				crossings.append((a.rect as Rect2).intersection(b.rect as Rect2).grow(4.0))
	var gate: Vector2 = lay.gate.at
	for st: Dictionary in lay.streets:
		var r: Rect2 = st.rect
		var axis: int = st.axis
		var along0: float = r.position.y if axis == 0 else r.position.x
		var along1: float = r.end.y if axis == 0 else r.end.x
		var side := 1.0 if h01([ps, "basecamp_side", axis, st.index]) < 0.5 else -1.0
		var w: float = r.size.x if axis == 0 else r.size.y
		var mid: float = r.get_center().x if axis == 0 else r.get_center().y
		var t := along0 + 4.0
		var k := 0
		while t < along1 - 4.0:
			var vk := [ps, "basecamp", axis, st.index, k]
			var roll := h01(vk)
			var kind := "trailer" if roll < 0.5 else ("honey" if roll < 0.65 else ("truck" if roll < 0.88 else "gap"))
			var length := 12.0 if kind == "trailer" else (14.0 if kind == "honey" else 9.6)
			if kind == "gap":
				length = 8.0
			var ok := true
			var mid_t := t + length * 0.5
			var p := Vector2(mid + side * (w * 0.5 - 2.4), mid_t) if axis == 0 else Vector2(mid_t, mid + side * (w * 0.5 - 2.4))
			var foot := Rect2(p - Vector2(3.0, length * 0.5 + 1.5), Vector2(6.0, length + 3.0)) if axis == 0 else Rect2(p - Vector2(length * 0.5 + 1.5, 3.0), Vector2(length + 3.0, 6.0))
			for cr: Rect2 in crossings:
				if cr.intersects(foot):
					ok = false
			if foot.grow(6.0).has_point(gate):
				ok = false
			if ok and kind != "gap":
				var yaw := (0.0 if axis == 0 else PI * 0.5) + (PI if h01(vk + ["dir"]) < 0.5 else 0.0)
				lay.parking.append({"at": p, "yaw": yaw, "kind": kind, "length": length, "seed": absi(hash(vk)), "band": int(h01(vk + ["band"]) * 4.0)})
			t += length + 1.5 + 2.5 * h01(vk + ["gap"])
			k += 1
		# Lamps on the other side every ~28 m.
		var lt := along0 + 10.0
		while lt < along1 - 6.0:
			var lp := Vector2(mid - side * (w * 0.5 - 0.6), lt) if axis == 0 else Vector2(lt, mid - side * (w * 0.5 - 0.6))
			var clear := true
			for cr: Rect2 in crossings:
				if cr.has_point(lp):
					clear = false
			if clear:
				var toward := Vector2(side, 0.0) if axis == 0 else Vector2(0.0, side)
				lay.lamps.append({"at": lp, "pole": true, "yaw": atan2(toward.x, toward.y)})
			lt += 28.0


## True where the lot (wall, pavement ring, everything inside) covers world XZ `p`.
static func covers(plan: CityPlan, p: Vector2) -> bool:
	var lay := layout(plan)
	return not lay.is_empty() and (lay.rect as Rect2).has_point(p)


# =================================================================================================
# Build
# =================================================================================================

class Acc:
	var st: SurfaceTool
	var ground: SurfaceTool
	var walk: SurfaceTool
	var lawn: SurfaceTool
	var glass: SurfaceTool
	var shapes: int = 0


static func _acc(ch: CityChunk) -> Acc:
	if not ch.has_meta("studio_acc"):
		var a := Acc.new()
		a.st = SurfaceTool.new()
		a.st.begin(Mesh.PRIMITIVE_TRIANGLES)
		a.st.set_smooth_group(-1)
		a.ground = SurfaceTool.new()
		a.ground.begin(Mesh.PRIMITIVE_TRIANGLES)
		a.walk = SurfaceTool.new()
		a.walk.begin(Mesh.PRIMITIVE_TRIANGLES)
		a.lawn = SurfaceTool.new()
		a.lawn.begin(Mesh.PRIMITIVE_TRIANGLES)
		a.glass = SurfaceTool.new()
		a.glass.begin(Mesh.PRIMITIVE_TRIANGLES)
		ch.set_meta("studio_acc", a)
	return ch.get_meta("studio_acc")


static func site_steps(ch: CityChunk) -> Array[Callable]:
	var steps: Array[Callable] = []
	var lay := layout(ch.plan)
	if lay.is_empty():
		return steps
	var area := ch.owned_rect()
	steps.append(_ground.bind(ch, lay, area))
	steps.append(_walls.bind(ch, lay, area))
	if ch.level == CityChunk.Level.FULL:
		# Time-sliced: a stage a step, four fronts a step, eight vehicles a step (a stage is
		# ~20-40 ms of GDScript on a slow box).
		for i in lay.stages.size():
			if area.has_point(lay.stages[i].c):
				steps.append(_stages.bind(ch, lay, area, i, i + 1))
		steps.append(_front.bind(ch, lay, area))
		for i in range(0, lay.fronts.size(), 4):
			steps.append(_backlot.bind(ch, lay, area, i, i + 4))
		for i in range(0, lay.parking.size(), 8):
			steps.append(_vehicles.bind(ch, lay, area, i, i + 8))
		for i in range(0, lay.cars.size(), 2):
			if area.has_point(lay.cars[i].at) or (i + 1 < lay.cars.size() and area.has_point(lay.cars[i + 1].at)):
				steps.append(_park.bind(ch, lay, area, i, i + 2))
	else:
		steps.append(_stages.bind(ch, lay, area))
		steps.append(_front.bind(ch, lay, area))
		steps.append(_backlot.bind(ch, lay, area))
	if ch.level == CityChunk.Level.FULL:
		steps.append(_lights.bind(ch, lay, area))
		steps.append(_crowd.bind(ch, lay, area))
	steps.append(_commit.bind(ch))
	return steps


## The far city's record (capture mode): the ground slabs, the stages, the offices, the tower, the
## fronts and the bungalows as the LOD chunk builds them.
static func capture_steps(ch: CityChunk) -> Array[Callable]:
	var steps: Array[Callable] = []
	var lay := layout(ch.plan)
	if lay.is_empty():
		return steps
	var area := ch.owned_rect()
	steps.append(_ground.bind(ch, lay, area))
	steps.append(_walls.bind(ch, lay, area))
	steps.append(_stages.bind(ch, lay, area))
	steps.append(_front.bind(ch, lay, area))
	steps.append(_backlot.bind(ch, lay, area))
	return steps


static func _full(ch: CityChunk) -> bool:
	return ch.level == CityChunk.Level.FULL and not ch.capturing


static func _parts(rects: Array, area: Rect2) -> Array[Rect2]:
	var out: Array[Rect2] = []
	for r: Rect2 in rects:
		var p := r.intersection(area)
		if p.size.x > 0.05 and p.size.y > 0.05:
			out.append(p)
	return out


## A flat quad over `r` at height `y` (UV world metres), on the relief.
static func _flat(ch: CityChunk, st: SurfaceTool, r: Rect2, y: float) -> void:
	var a := Vector3(r.position.x, y + ch._gy(r.position.x, r.position.y), r.position.y)
	var b := Vector3(r.end.x, y + ch._gy(r.end.x, r.position.y), r.position.y)
	var c := Vector3(r.end.x, y + ch._gy(r.end.x, r.end.y), r.end.y)
	var d := Vector3(r.position.x, y + ch._gy(r.position.x, r.end.y), r.end.y)
	for v: Vector3 in [a, c, b, a, d, c]:
		st.set_color(Color.WHITE)
		st.set_normal(Vector3.UP)
		st.set_uv(Vector2(v.x, v.z))
		st.add_vertex(v)


## The pavement ring outside the wall, the asphalt and aprons inside it, the bungalows' lawns.
static func _ground(ch: CityChunk, lay: Dictionary, area: Rect2) -> void:
	var rect: Rect2 = lay.rect
	var inner: Rect2 = lay.inner
	var ring := Parks.minus(rect, [inner], 0.05)
	var lawns: Array = []
	for lot: Dictionary in lay.lots:
		lawns.append(lot.cell)
	var inside := Parks.minus(inner, lawns, 0.05)
	if not _full(ch):
		for r: Rect2 in _parts(ring, area):
			ch._add_slab(Vector3(r.get_center().x, CityChunk.SIDEWALK_TOP - 0.1, r.get_center().y), Vector3(r.size.x, 0.2, r.size.y), ch.style.sidewalk, true)
		for r: Rect2 in _parts(inside, area):
			ch._add_slab(Vector3(r.get_center().x, BASE_Y - 0.1, r.get_center().y), Vector3(r.size.x, 0.2, r.size.y), Color(0.36, 0.36, 0.35), true)
		for r: Rect2 in _parts(lawns, area):
			ch._add_slab(Vector3(r.get_center().x, BASE_Y - 0.08, r.get_center().y), Vector3(r.size.x, 0.2, r.size.y), Color(0.34, 0.44, 0.24), true)
		return
	var acc := _acc(ch)
	for r: Rect2 in _parts(ring, area):
		_flat(ch, acc.walk, r, CityChunk.SIDEWALK_TOP)
		ch._add_shape(Vector3(r.size.x, 0.3, r.size.y), Vector3(r.get_center().x, CityChunk.SIDEWALK_TOP - 0.15 + ch._gy(r.get_center().x, r.get_center().y), r.get_center().y))
	# Inside: asphalt, a concrete apron along the foot of every stage, paint for the parking.
	var aprons: Array = []
	for sg: Dictionary in lay.stages:
		var sz: Vector3 = sg.size
		var ext := Vector2(sz.x + 7.0, sz.z + 2.0) if is_zero_approx(float(sg.yaw)) else Vector2(sz.z + 2.0, sz.x + 7.0)
		aprons.append(Rect2((sg.c as Vector2) - ext * 0.5, ext))
	for r: Rect2 in _parts(inside, area):
		for piece: Rect2 in Parks.minus(r, aprons, 0.05):
			Industrial._ground_rect(acc.ground, ch, piece, BASE_Y, Industrial.G_ASPHALT, 0.15, true)
		for ap: Rect2 in aprons:
			var p := ap.intersection(r)
			if p.size.x > 0.05 and p.size.y > 0.05:
				Industrial._ground_rect(acc.ground, ch, p, BASE_Y, Industrial.G_CONCRETE, 0.3, true)
		ch._add_shape(Vector3(r.size.x, 0.3, r.size.y), Vector3(r.get_center().x, BASE_Y - 0.15 + ch._gy(r.get_center().x, r.get_center().y), r.get_center().y))
	# Lane markings: a centre line down each studio street.
	for st: Dictionary in lay.streets:
		var sr: Rect2 = st.rect
		var line := Rect2(sr.get_center().x - 0.06, sr.position.y, 0.12, sr.size.y) if int(st.axis) == 0 else Rect2(sr.position.x, sr.get_center().y - 0.06, sr.size.x, 0.12)
		for p: Rect2 in _parts([line], area):
			Industrial._ground_rect(acc.ground, ch, p, BASE_Y + 0.012, Industrial.G_PAINT, 0.9, false)
	# The backlot's pavements, a kerb up from the street.
	for p: Rect2 in _parts(lay.backlot_walks, area):
		Industrial._ground_rect(acc.ground, ch, p, BASE_Y + 0.15, Industrial.G_CONCRETE, 0.45, true)
		ch._add_shape(Vector3(p.size.x, 0.3, p.size.y), Vector3(p.get_center().x, BASE_Y + 0.0 + ch._gy(p.get_center().x, p.get_center().y), p.get_center().y))
	for r: Rect2 in _parts(lawns, area):
		_flat(ch, acc.lawn, r, BASE_Y + 0.02)
		ch._add_shape(Vector3(r.size.x, 0.3, r.size.y), Vector3(r.get_center().x, BASE_Y - 0.13 + ch._gy(r.get_center().x, r.get_center().y), r.get_center().y))
	if lay.has("front_walk") and (lay.front_walk as Rect2).size.x > 0.0:
		for p: Rect2 in _parts([lay.front_walk], area):
			Industrial._ground_rect(acc.ground, ch, p, BASE_Y + 0.025, Industrial.G_CONCRETE, 0.6, false)
	# A dropped kerb in front of the gate: the drive ramps down across the pavement.
	var g: Vector2 = lay.gate.at
	var ramp := Rect2(g.x - GATE_W * 0.5, rect.end.y - PAVEMENT, GATE_W, PAVEMENT)
	if area.has_point(ramp.get_center()):
		Industrial._ground_rect(acc.ground, ch, ramp, CityChunk.SIDEWALK_TOP + 0.02, Industrial.G_CONCRETE, 0.5, false)


## The perimeter wall, cut for the gate, and the gate itself.
static func _walls(ch: CityChunk, lay: Dictionary, area: Rect2) -> void:
	var w: Rect2 = lay.wall
	var g: Vector2 = lay.gate.at
	var hg := float(lay.gate.w) * 0.5 + 2.8
	var runs := [[w.position, Vector2(w.end.x, w.position.y)], [Vector2(w.end.x, w.position.y), w.end],
		[w.position, Vector2(w.position.x, w.end.y)], [Vector2(w.position.x, w.end.y), Vector2(g.x - hg, w.end.y)],
		[Vector2(g.x + hg, w.end.y), w.end]]
	var full := _full(ch)
	var acc: Acc = _acc(ch) if full else null
	for run: Array in runs:
		var a: Vector2 = run[0]
		var b: Vector2 = run[1]
		var horizontal := absf(b.y - a.y) < 0.01
		# Clip the (axis-aligned) run to the chunk: a run on the chunk's edge line belongs to the
		# chunk whose owned rect starts there.
		var p0: Vector2
		var p1: Vector2
		if horizontal:
			if a.y < area.position.y or a.y >= area.end.y:
				continue
			p0 = Vector2(maxf(minf(a.x, b.x), area.position.x), a.y)
			p1 = Vector2(minf(maxf(a.x, b.x), area.end.x), a.y)
		else:
			if a.x < area.position.x or a.x >= area.end.x:
				continue
			p0 = Vector2(a.x, maxf(minf(a.y, b.y), area.position.y))
			p1 = Vector2(a.x, minf(maxf(a.y, b.y), area.end.y))
		var len := (p1.x - p0.x) if horizontal else (p1.y - p0.y)
		if len < 0.05:
			continue
		var y := BASE_Y - 0.1 + minf(ch._gy(p0.x, p0.y), ch._gy(p1.x, p1.y))
		var phase := (p0.x - w.position.x) if horizontal else (p0.y - w.position.y)
		var m := (p0 + p1) * 0.5
		var size := Vector3(len, FilmStudioKit.WALL_H, FilmStudioKit.WALL_T) if horizontal else Vector3(FilmStudioKit.WALL_T, FilmStudioKit.WALL_H, len)
		if full:
			FilmStudioKit.wall(acc.st, p0, p1, y, phase)
			ch._add_shape(size, Vector3(m.x, y + FilmStudioKit.WALL_H * 0.5, m.y))
		else:
			ch._batch.add("lod_box", PropFactory.unit_box(), Transform3D(Basis().scaled(size), Vector3(m.x, BASE_Y - 0.1 + FilmStudioKit.WALL_H * 0.5, m.y)), Color(0.88, 0.83, 0.72), Color(0.0, 0.0, 0.3, 1.0))
	# The gate.
	if area.has_point(g):
		var y := BASE_Y - 0.1 + ch._gy(g.x, g.y)
		if full:
			FilmStudioKit.gate(acc.st, Transform3D(Basis(), Vector3(g.x, y, g.y)), float(lay.gate.w))
			for sx: float in [-1.0, 1.0]:
				ch._add_shape(Vector3(2.8, 10.0, 2.8), Vector3(g.x + sx * (float(lay.gate.w) * 0.5 + 1.4), y + 5.0, g.y))
			ch._add_shape(Vector3(float(lay.gate.w), 2.6, 1.8), Vector3(g.x, y + 8.6, g.y))
			ch._add_shape(Vector3(2.0, 2.9, 2.8), Vector3(g.x, y + 1.6, g.y + 0.6))
		else:
			for sx: float in [-1.0, 1.0]:
				ch._batch.add("lod_box", PropFactory.unit_box(), Transform3D(Basis().scaled(Vector3(2.8, 10.5, 2.8)), Vector3(g.x + sx * (float(lay.gate.w) * 0.5 + 1.4), y + 5.25, g.y)), Color(0.9, 0.85, 0.74), Color(0.0, 0.0, 0.4, 1.0))
			ch._batch.add("lod_box", PropFactory.unit_box(), Transform3D(Basis().scaled(Vector3(float(lay.gate.w), 2.6, 1.8)), Vector3(g.x, y + 8.5, g.y)), Color(0.9, 0.85, 0.74), Color(0.0, 0.0, 0.41, 1.0))


static func _stage_xf(ch: CityChunk, sg: Dictionary) -> Transform3D:
	var c: Vector2 = sg.c
	var sz: Vector3 = sg.size
	var g := INF
	var half := Vector2(sz.x, sz.z) * 0.5
	for k in 4:
		var q := FilmStudio._local_to_world(c, float(sg.yaw), Vector2(half.x * (1.0 if k % 2 == 0 else -1.0), half.y * (1.0 if k < 2 else -1.0)))
		g = minf(g, ch._gy(q.x, q.y))
	return Transform3D(Basis(Vector3.UP, float(sg.yaw)), Vector3(c.x, BASE_Y - 0.05 + g, c.y))


static func _stages(ch: CityChunk, lay: Dictionary, area: Rect2, i0: int = 0, i1: int = 1 << 30) -> void:
	var full := _full(ch)
	var acc: Acc = _acc(ch) if full else null
	for sg: Dictionary in (lay.stages as Array).slice(i0, i1):
		var c: Vector2 = sg.c
		if not area.has_point(c):
			continue
		var xf := _stage_xf(ch, sg)
		var sz: Vector3 = sg.size
		var rise := sz.x * 0.11
		var world_size := Vector3(sz.x, sz.y, sz.z) if is_zero_approx(float(sg.yaw)) else Vector3(sz.z, sz.y, sz.x)
		if full:
			FilmStudioKit.stage(acc.st, xf, sz, int(sg.number), sg.doors, int(sg.seed), bool(sg.rolling))
			ch._add_shape(world_size + Vector3(0.0, rise * 0.5, 0.0), xf.origin + Vector3(0.0, (sz.y + rise * 0.5) * 0.5, 0.0))
			ch._occluder_boxes.append([Transform3D(Basis(), Vector3.ZERO), xf.origin + Vector3(0.0, sz.y * 0.5, 0.0), world_size - Vector3(1.0, 1.0, 1.0)])
		else:
			var paint: Color = FilmStudioKit.STAGE_PAINTS[int(sg.seed) % FilmStudioKit.STAGE_PAINTS.size()]
			ch._batch.add("lod_box", PropFactory.unit_box(), Transform3D(Basis().scaled(world_size), xf.origin + Vector3(0.0, sz.y * 0.5, 0.0)), paint, Color(0.0, 0.0, float(int(sg.seed) % 997) / 997.0, 1.0))
			# The ridge as a lower, narrower box over it.
			var ridge := Vector3(world_size.x * (0.55 if is_zero_approx(float(sg.yaw)) else 1.0), rise, world_size.z * (1.0 if is_zero_approx(float(sg.yaw)) else 0.55))
			ch._batch.add("lod_box", PropFactory.unit_box(), Transform3D(Basis().scaled(ridge), xf.origin + Vector3(0.0, sz.y + rise * 0.5, 0.0)), Color(0.6, 0.62, 0.62), Color(0.0, 0.0, 0.2, 1.0))
			ch._add_lod_shape(world_size, xf.origin + Vector3(0.0, sz.y * 0.5, 0.0))


## The front lot: the office block, the bungalows, the water tower.
static func _front(ch: CityChunk, lay: Dictionary, area: Rect2) -> void:
	var full := _full(ch)
	var acc: Acc = _acc(ch) if full else null
	var of: Dictionary = lay.offices
	if not of.is_empty() and area.has_point(of.c as Vector2):
		var c: Vector2 = of.c
		var sz: Vector3 = of.size
		var y := BASE_Y - 0.05 + ch._gy(c.x, c.y)
		if full:
			FilmStudioKit.offices(acc.st, acc.glass, Transform3D(Basis(), Vector3(c.x, y, c.y)), sz, int(of.storeys))
			ch._add_shape(sz, Vector3(c.x, y + sz.y * 0.5, c.y))
			ch._occluder_boxes.append([Transform3D(Basis(), Vector3.ZERO), Vector3(c.x, y + sz.y * 0.5, c.y), sz - Vector3(1.0, 1.0, 1.0)])
		else:
			ch._batch.add("lod_box", PropFactory.unit_box(), Transform3D(Basis().scaled(sz), Vector3(c.x, y + sz.y * 0.5, c.y)), Color(0.92, 0.88, 0.8), Color(0.25, 0.4, float(absi(hash([ch.plan.seed, "studio_offices"])) % 997) / 997.0, 0.0))
			ch._add_lod_shape(sz, Vector3(c.x, y + sz.y * 0.5, c.y))
	var t: Vector2 = lay.tower
	if t != Vector2.INF and area.has_point(t):
		var y := BASE_Y - 0.05 + ch._gy(t.x, t.y)
		if full:
			FilmStudioKit.water_tower(acc.st, Transform3D(Basis(Vector3.UP, float(lay.get("tower_yaw", 0.0))), Vector3(t.x, y, t.y)))
			ch._add_shape(Vector3(1.2, 24.0, 1.2), Vector3(t.x, y + 12.0, t.y))
			ch._add_shape(Vector3(10.8, 8.4, 10.8), Vector3(t.x, y + 24.0 + 5.6, t.y))
		else:
			ch._batch.add("lod_box", PropFactory.unit_box(), Transform3D(Basis().scaled(Vector3(10.4, 8.0, 10.4)), Vector3(t.x, y + 24.0 + 5.0, t.y)), Color(0.86, 0.85, 0.82), Color(0.0, 0.0, 0.5, 1.0))
			ch._batch.add("lod_box", PropFactory.unit_box(), Transform3D(Basis().scaled(Vector3(9.0, 24.0, 9.0)), Vector3(t.x, y + 12.0, t.y)), Color(0.5, 0.5, 0.48), Color(0.0, 0.0, 0.51, 1.0))
	if not HouseKit.enabled:
		return
	for lot: Dictionary in lay.lots:
		if area.has_point(lot.center):
			HouseKit.build(ch, house_for(ch.plan, lot))


## The backlot's New York street.
static func _backlot(ch: CityChunk, lay: Dictionary, area: Rect2, i0: int = 0, i1: int = 1 << 30) -> void:
	if lay.fronts.is_empty():
		return
	var full := _full(ch)
	var acc: Acc = _acc(ch) if full else null
	for f: Dictionary in (lay.fronts as Array).slice(i0, i1):
		var at: Vector2 = f.at
		var w: float = f.w
		var yaw: float = f.yaw
		var mid := at + Vector2(cos(yaw), -sin(yaw)) * w * 0.5
		if not area.has_point(mid):
			continue
		var y := BASE_Y - 0.05 + ch._gy(mid.x, mid.y)
		var xf := Transform3D(Basis(Vector3.UP, yaw), Vector3(at.x, y, at.y))
		var h: float = f.h
		if full:
			FilmStudioKit.facade(acc.st, xf, w, h, int(f.style), int(f.seed))
			var c3 := xf * Vector3(w * 0.5, h * 0.5, 0.15)
			ch._add_shape(Vector3(w, h, 0.4), c3, yaw)
		else:
			var c3 := xf * Vector3(w * 0.5, h * 0.5, 0.15)
			var col := Color(0.62, 0.42, 0.34) if int(f.style) != FilmStudioKit.Facade.LIMESTONE else Color(0.8, 0.76, 0.66)
			ch._batch.add("lod_box", PropFactory.unit_box(), Transform3D(Basis(Vector3.UP, yaw).scaled_local(Vector3(w, h, 0.5)), c3), col, Color(0.25, 0.3, float(int(f.seed) % 997) / 997.0, 0.0))


## The backlot street's parked cars (FULL): real Vehicle bodies - the street is seen from the
## pavement, where the cheap static cars read as grey boxes - parked and asleep like the city's
## (CityChunk._park_car(): under the city root, hidden with the chunk until it is shown, freed
## when it retires). Their rolls are a private rng of the seed and the spot.
static func _park(ch: CityChunk, lay: Dictionary, area: Rect2, i0: int, i1: int) -> void:
	for car: Dictionary in (lay.cars as Array).slice(i0, i1):
		var p: Vector2 = car.at
		if not area.has_point(p) or not PhysicsBudget.can_spawn():
			continue
		var rng := RandomNumberGenerator.new()
		rng.seed = hash([ch.plan.seed, "studio_car", int(car.seed)])
		var v := Vehicle.random_car(rng)
		var holder: Node = ch.get_parent() if ch.get_parent() else ch
		var spot := Vector3(p.x, BASE_Y + 0.3 + ch._gy(p.x, p.y), p.y)
		v.position = WorldState.to_local(spot) if holder != ch else spot
		v.rotation.y = float(car.yaw)
		holder.add_child(v)
		v.visible = ch.visible
		ch._cars.append(v)


## Basecamp, golf carts, gear.
static func _vehicles(ch: CityChunk, lay: Dictionary, area: Rect2, i0: int = 0, i1: int = 1 << 30) -> void:
	var acc := _acc(ch)
	for pk: Dictionary in (lay.parking as Array).slice(i0, i1):
		var p: Vector2 = pk.at
		if not area.has_point(p):
			continue
		var y := BASE_Y + ch._gy(p.x, p.y)
		var xf := Transform3D(Basis(Vector3.UP, float(pk.yaw)), Vector3(p.x, y, p.y))
		match String(pk.kind):
			"trailer":
				FilmStudioKit.trailer(acc.st, xf, float(pk.length) - 1.6, false, int(pk.band))
			"honey":
				FilmStudioKit.trailer(acc.st, xf, float(pk.length) - 1.6, true, int(pk.band))
			_:
				FilmStudioKit.truck(acc.st, xf, int(pk.band))
		var l: float = float(pk.length)
		ch._add_shape(Vector3(2.6, 3.9, l), Vector3(p.x, y + 1.95, p.y), float(pk.yaw))
	if i0 != 0:
		return
	for cart: Dictionary in lay.carts:
		var p: Vector2 = cart.at
		if not area.has_point(p):
			continue
		var paints := [Color(0.92, 0.92, 0.9), Color(0.9, 0.86, 0.74), Color(0.2, 0.34, 0.24), Color(0.12, 0.12, 0.13)]
		var paint: Color = paints[int(cart.seed) % paints.size()]
		var y := BASE_Y + ch._gy(p.x, p.y)
		FilmStudioKit.golf_cart(acc.st, Transform3D(Basis(Vector3.UP, float(cart.yaw)), Vector3(p.x, y, p.y)), paint, int(cart.seed) % 3 == 0)
		ch._add_shape(Vector3(1.2, 1.9, 2.4), Vector3(p.x, y + 0.95, p.y), float(cart.yaw))
	for gear: Dictionary in lay.gear:
		var p: Vector2 = gear.at
		if not area.has_point(p):
			continue
		FilmStudioKit.gear(acc.st, Transform3D(Basis(Vector3.UP, float(gear.yaw)), Vector3(p.x, BASE_Y + ch._gy(p.x, p.y), p.y)), int(gear.seed))


## Lamps along the studio streets and pools at the stage doors; a light at the gate.
static func _lights(ch: CityChunk, lay: Dictionary, area: Rect2) -> void:
	var acc := _acc(ch)
	var n_omni := 0
	for lp: Dictionary in lay.lamps:
		var p: Vector2 = lp.at
		if not area.has_point(p):
			continue
		var y := BASE_Y + ch._gy(p.x, p.y)
		if lp.get("ny", false):
			var nxf := Transform3D(Basis(Vector3.UP, float(lp.yaw)), Vector3(p.x, y + 0.15, p.y))
			FilmStudioKit.ny_lamp(acc.st, nxf)
			var at := nxf * Vector3(0.0, 0.0, 1.25)
			ch._batch.add("studio_pool", PropFactory.light_pool(Color(1.0, 0.82, 0.55), 0.9, 2.0), Transform3D(Basis().scaled(Vector3(8.0, 1.0, 8.0)), Vector3(at.x, BASE_Y + 0.03, at.z)))
		elif lp.get("pole", false):
			var yaw: float = lp.yaw
			var xf := Transform3D(Basis(Vector3.UP, yaw), Vector3(p.x, y, p.y))
			FilmStudioKit.cyl(acc.st, xf, 0.12, 7.5, FilmStudioKit.K_STEEL, Color(0.28, 0.3, 0.3), 8, false)
			FilmStudioKit.beam(acc.st, xf * Vector3(0.0, 7.4, 0.0), xf * Vector3(0.0, 7.6, 1.6), 0.08, 0.08, FilmStudioKit.K_STEEL, Color(0.28, 0.3, 0.3))
			FilmStudioKit.box(acc.st, xf * Transform3D(Basis(), Vector3(0.0, 7.55, 1.8)), Vector3(0.38, 0.16, 0.7), FilmStudioKit.K_LAMP, Color(1.0, 0.86, 0.62))
			var at := xf * Vector3(0.0, 0.0, 1.8)
			ch._batch.add("studio_pool", PropFactory.light_pool(Color(1.0, 0.84, 0.6), 0.8, 2.0), Transform3D(Basis().scaled(Vector3(9.0, 1.0, 9.0)), Vector3(at.x, BASE_Y + 0.03, at.z)))
		else:
			ch._batch.add("studio_pool", PropFactory.light_pool(Color(1.0, 0.84, 0.6), 0.8, 2.0), Transform3D(Basis().scaled(Vector3(8.0, 1.0, 8.0)), Vector3(p.x, BASE_Y + 0.03, p.y)))
	var g: Vector2 = lay.gate.at
	if area.has_point(g):
		ch._batch.add("studio_pool", PropFactory.light_pool(Color(1.0, 0.86, 0.62), 1.0, 2.0), Transform3D(Basis().scaled(Vector3(16.0, 1.0, 16.0)), Vector3(g.x, BASE_Y + 0.03, g.y + 2.0)))
		if not OS.has_feature("web") and n_omni < 2:
			var l := OmniLight3D.new()
			l.position = Vector3(g.x, BASE_Y + 6.0 + ch._gy(g.x, g.y), g.y + 3.0)
			l.light_color = Color(1.0, 0.84, 0.62)
			l.omni_range = 22.0
			l.light_energy = 0.0
			l.shadow_enabled = false
			l.distance_fade_enabled = true
			l.distance_fade_begin = 120.0
			l.distance_fade_length = 40.0
			# Hidden as DayNight hides a dark lamp, so its lamp tick shows it after dark.
			l.visible = false
			l.set_meta("dark_hidden", true)
			l.add_to_group("lamp_light")
			ch.add_child(l)
			n_omni += 1
	ch._batch.set_no_shadow("studio_pool")


## Crew: walkers on the studio streets and the lane.
static func _crowd(ch: CityChunk, lay: Dictionary, area: Rect2) -> void:
	var rects: Array = []
	for st: Dictionary in lay.streets:
		rects.append(st.rect)
	var inner: Rect2 = lay.inner
	rects.append(Rect2(inner.position.x, inner.end.y - LANE, inner.size.x, LANE))
	rects.append(Rect2(inner.position.x, inner.position.y, inner.size.x, LANE))
	if (lay.backlot_street as Rect2).size.x > 0.0:
		rects.append(lay.backlot_street)
	for r: Rect2 in _parts(rects, area):
		var length := maxf(r.size.x, r.size.y)
		if length < 20.0:
			continue
		var rng := RandomNumberGenerator.new()
		rng.seed = hash([ch.plan.seed, "studio_crew", int(r.position.x), int(r.position.y)])
		var n := int(length * CREW_PER_M + rng.randf())
		for step: Callable in ch._crowd_steps(r, minf(r.size.x, r.size.y) * 0.5, n, rng):
			step.call()


static var _walk_mat: Material
static var _lawn_mat: Material


## Everything accumulated: the studio mesh, the yard ground, the pavement, the lawns.
static func _commit(ch: CityChunk) -> void:
	if not ch.has_meta("studio_acc"):
		return
	var acc: Acc = ch.get_meta("studio_acc")
	ch.remove_meta("studio_acc")
	if _walk_mat == null:
		_walk_mat = PropFactory.road("sidewalk", 3.0, Color(1.45, 1.43, 1.38), 7713, 1.5, 0.35)
		_lawn_mat = PropFactory.lawn(Color(0.86, 0.98, 0.72), 5521, 0.25, 3.0)
	var parts := [["StudioLot", acc.st, FilmStudioKit.material(), true], ["StudioGround", acc.ground, Industrial.ground_material(), false],
		["StudioPavement", acc.walk, _walk_mat, false], ["StudioLawn", acc.lawn, _lawn_mat, false],
		["StudioGlass", acc.glass, FilmStudioKit.glass_material(), true]]
	for p: Array in parts:
		var st: SurfaceTool = p[1]
		var mesh := st.commit()
		if mesh.get_surface_count() == 0:
			continue
		var mi := MeshInstance3D.new()
		mi.name = p[0]
		mi.mesh = mesh
		mi.material_override = p[2]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if p[3] else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ch.add_child(mi)
