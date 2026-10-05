class_name Marina
extends RefCounted
## The small-craft marina on the coast between the beach town and the airport (VISUAL_ROADMAP
## #59): the form of Los Angeles' big man-made marina - a basin dredged out of the land behind the
## beach, a main fairway along its seaward side, rows of floating docks on pilings filled with
## hundreds of boats, an entrance channel cut through the sand to the sea between two rubble
## jetties with a light on each end, and a detached rubble breakwater offshore - with waterfront
## towers, restaurants, car parks and a boat yard round it. Every name is invented ("Ballona Bay
## Marina" is not used anywhere: the HUD calls the place Playa, the coast town it stands in).
##
## THIS is the data: a pure plan of world XZ shapes, worked out once per map from the coast
## (MacroMap.coast_x(), beach_width_at()) and the seed's street grid (the site is whole blocks
## between four roads, like a landmark's site), never placed by hand. MarinaBuild builds a chunk's
## share of it; CityPlan asks road_open() / blocks(); MacroMap folds terrace() into the relief and
## paints the water on the horizon bake. Every roll is a hash of seed + place (h01()), never a
## chunk or block rng: nothing else the seed builds moves.
##
## Frame: x east, z south (world). The basin is a quadrilateral - its west side a seawall that
## follows the coast a promenade's width behind the sand, its east, north and south sides straight
## bulkheads - and the entrance channel a band of z [zc - CHANNEL_HALF, zc + CHANNEL_HALF] from the
## basin's west wall out past the waterline. The coast highway crosses the channel on a bridge
## (MarinaBuild; its own strip has a gap there, `pch_gap()`).

## The site, in road terms: the roads nearest these lines bound it (they stay open; everything
## between them is the marina's). Between Venice's boardwalk and the airport fence, behind the sand.
const SITE_WEST_X := -824.0
const SITE_EAST_X := -546.0
const SITE_NORTH_Z := 0.0
const SITE_SOUTH_Z := 404.0

## Land and water levels. The marina's land is a terrace at QUAY_Y of relief (pavement at
## QUAY_Y + CityChunk.SIDEWALK_TOP); the water is the sea's level (the ground follower and the
## GroundBody are at y 0 under it: you wade, as in the sea).
const QUAY_Y := 1.9
const WATER_Y := 0.15
## Over how many metres outside the site the terrace hands back to the rolling relief.
const TERRACE_FADE := 40.0
## The sand's inland edge is the beach's own (CityChunk.SAND_LIP past the beach width).
const SAND_LIP := 22.0
## Width of the promenade between the sand's edge and the basin's west seawall, and of the
## planted bank that climbs from the sand to it.
const WEST_PROM := 13.0
const BANK := 5.0
## Land kept on the basin's east side (towers, car parks), north side (restaurants, car park).
const EAST_LAND := 66.0
const NORTH_LAND := 48.0
## The entrance channel's half width, and where it lies: its centre is this far north of the
## south road's inner edge (room for the boat yard and the bridge's south ramp).
const CHANNEL_HALF := 24.0
const CHANNEL_FROM_SOUTH := 110.0
## The jetties run this far past the waterline; the breakwater stands this far out from it,
## this long (along the coast), centred on the channel.
const JETTY_OUT := 58.0
const BREAKWATER_OFF := 175.0
const BREAKWATER_HALF := 150.0
## Rubble mounds: crest width and height over the water, side slope (run per rise).
const JETTY_CREST := 4.5
const JETTY_TOP := 3.2
const BREAKWATER_CREST := 6.0
const BREAKWATER_TOP := 4.0
const MOUND_SLOPE := 1.6
const MOUND_FOOT := -3.0

## The coast highway's bridge over the channel: the gap in its strip (z either side of zc) and
## the deck's crest (over the water). The ramps run BRIDGE_RAMP at the strip's own grade limit.
const BRIDGE_ABUT := 16.0
const BRIDGE_RAMP := 55.0
const BRIDGE_CREST := 3.9
const BRIDGE_DECK := 1.4

## Docks. Floating pontoons (deck top DOCK_Y), the headwalk along each seawall BULK_GAP off it,
## main docks every DOCK_PITCH running west from the east headwalk, stopping FAIRWAY short of the
## west seawall (the main fairway), fingers both sides at SLIP_PITCH.
const DOCK_Y := 0.62
const HEAD_W := 2.4
const BULK_GAP := 1.0
const MAIN_W := 2.4
const DOCK_PITCH := 38.0
const FAIRWAY := 44.0
const FINGER_LEN := 9.5
const FINGER_W := 0.9
const SLIP_PITCH := 4.8
## How far the first main dock stands off the north bulkhead and the last off the south one.
const FIRST_DOCK := 21.0
## Boats. Types (BoatMesh builds them).
enum Type { SAIL, MOTOR, FISHER, RUNABOUT }
## Share of slips with a boat in them, and of a boat's type by slip (cumulative odds).
const OCCUPIED := 0.9
const TYPE_ODDS := [0.5, 0.68, 0.86, 1.0]
## Reference lengths of each type's mesh (BoatMesh); a boat is that mesh scaled to its length.
const REF_LEN := [11.0, 17.0, 13.0, 6.5]
## Hull paint palettes (sRGB, plain): most boats are white, some navy, green, cream, red, grey.
const HULL_PAINTS := [
	Color(0.93, 0.93, 0.91), Color(0.93, 0.93, 0.91), Color(0.95, 0.95, 0.93), Color(0.9, 0.91, 0.9),
	Color(0.93, 0.93, 0.91), Color(0.12, 0.16, 0.3), Color(0.08, 0.22, 0.17), Color(0.86, 0.82, 0.7),
	Color(0.55, 0.12, 0.1), Color(0.52, 0.55, 0.58), Color(0.93, 0.93, 0.91), Color(0.2, 0.36, 0.55),
]
## Canvas (sail covers, biminis): navy, royal blue, burgundy, forest, tan, grey.
const CANVAS := [Color(0.1, 0.14, 0.3), Color(0.12, 0.3, 0.55), Color(0.35, 0.09, 0.12), Color(0.1, 0.25, 0.17), Color(0.62, 0.55, 0.42), Color(0.4, 0.42, 0.44)]

## The land's kinds (MarinaBuild draws each on its own material).
enum Ground { PAVERS, ASPHALT, CONCRETE, LAWN, BIKE }

var macro: MacroMap
var seed_value: int = 0
var ok: bool = false
## The site between the four roads' inner edges, and the road indices.
var site := Rect2()
var ix0 := 0
var ix1 := 0
var iz0 := 0
var iz1 := 0
## The chunks (block indices) the marina takes: ix0 <= ix < ix1, iz0 <= iz < iz1.
var zc := 0.0
var z_north := 0.0
var z_south := 0.0
var x_east := 0.0
## The west seawall as a line x = west_a + west_k * z.
var west_a := 0.0
var west_k := 0.0
## Water: the basin quad and the channel band (to the jetty tips), as one polygon.
var water := PackedVector2Array()
var basin := PackedVector2Array()
var channel := Rect2()
## The sand's inland edge, sampled down the site (west boundary of the marina's land).
var sand_edge := PackedVector2Array()
## The marina's land outline (site less the sand), and its partition into ground kinds:
## [{poly, kind}] - land minus water, no overlaps.
var land := PackedVector2Array()
var grounds: Array = []
## Docks: [{a, b, w, kind}] (a -> b along the centre line, w the width); fingers too.
var docks: Array = []
## Pilings [Vector2], gangways [{top, bottom, w}] (top on the quay, bottom on a headwalk).
var piles: Array = []
var gangways: Array = []
## Boats in slips and along the headwalk: [{p, yaw, type, len, scale, paint, canvas, seed, lit,
## anchor}] (yaw: the boat's bow direction as a facing yaw, -Z forward).
var boats: Array = []
## The boat yard: boats on stands [{p, yaw, type, len, ...}], the travel lift well [a, b], and
## the lift's frame centre.
var yard_boats: Array = []
var lift_well := Rect2()
## Buildings: [{rect, kind ("tower" | "restaurant" | "office"), seed}].
var buildings: Array = []
## Car parks [Rect2] and their stall rows [{a, b, depth}], palms [Vector2], lamps [Vector2],
## benches [{p, yaw}].
var car_parks: Array = []
var palms: Array = []
var lamps: Array = []
var benches: Array = []
## The bike path's centre line (along the west promenade) and its ends.
var bike_path := PackedVector2Array()
## The navigation lights: [{p, top, color, kind}] (jetty ends: red to starboard coming in,
## green to port; the breakwater's ends flashing white).
var nav_lights: Array = []
## The channel boats' loop (world XZ polyline, closed) for MarinaTraffic.
var traffic_loop := PackedVector2Array()


## A float 0..1 from a hash of the seed and a key.
func h01(key: Array) -> float:
	return float(absi(hash([seed_value, "marina"] + key)) % 100003) / 100003.0


## Plans the marina for `m` (its coast and the seed's street grid). False (and `ok` false) when
## the grid does not leave room for it on this seed.
func build(m: MacroMap, sd: int) -> bool:
	macro = m
	seed_value = sd
	ok = false
	var plan := CityPlan.new()
	plan.seed = sd
	ix0 = plan._nearest_road(CityPlan.AXIS_X, SITE_WEST_X)
	ix1 = plan._nearest_road(CityPlan.AXIS_X, SITE_EAST_X)
	iz0 = plan._nearest_road(CityPlan.AXIS_Z, SITE_NORTH_Z)
	iz1 = plan._nearest_road(CityPlan.AXIS_Z, SITE_SOUTH_Z)
	if ix1 - ix0 < 2 or iz1 - iz0 < 2:
		return false
	var x0 := plan.road_pos(CityPlan.AXIS_X, ix0) + plan.road_width(CityPlan.AXIS_X, ix0) * 0.5
	var x1 := plan.road_pos(CityPlan.AXIS_X, ix1) - plan.road_width(CityPlan.AXIS_X, ix1) * 0.5
	var z0 := plan.road_pos(CityPlan.AXIS_Z, iz0) + plan.road_width(CityPlan.AXIS_Z, iz0) * 0.5
	var z1 := plan.road_pos(CityPlan.AXIS_Z, iz1) - plan.road_width(CityPlan.AXIS_Z, iz1) * 0.5
	site = Rect2(x0, z0, x1 - x0, z1 - z0)
	zc = z1 - CHANNEL_FROM_SOUTH
	z_north = z0 + NORTH_LAND
	z_south = zc + CHANNEL_HALF
	x_east = x1 - EAST_LAND
	if zc - CHANNEL_HALF - BRIDGE_ABUT - BRIDGE_RAMP < z0 + 8.0 or z_south - z_north < 140.0:
		return false
	# The bridge's ramps (snapped to the highway's points) must land between the site's roads.
	while pch_gap().y > z1 - 1.0:
		zc -= 2.0
		z_south = zc + CHANNEL_HALF
	if pch_gap().x < z0 + 1.0 or z_south - z_north < 140.0:
		return false
	# The sand's inland edge down the site, and the west seawall: a straight line that keeps at
	# least WEST_PROM of promenade behind it everywhere.
	sand_edge = PackedVector2Array()
	var zz := z0 - 8.0
	while zz < z1 + 8.0:
		sand_edge.append(Vector2(sand_x(zz), zz))
		zz += 12.0
	sand_edge.append(Vector2(sand_x(z1 + 8.0), z1 + 8.0))
	west_k = (sand_x(z_south) - sand_x(z_north)) / (z_south - z_north)
	west_a = sand_x(z_north) - west_k * z_north
	var push := 0.0
	for p: Vector2 in sand_edge:
		if p.y >= z_north - 1.0 and p.y <= z_south + 1.0:
			push = maxf(push, p.x - (west_a + west_k * p.y))
	west_a += push + BANK + WEST_PROM
	if x_east - west_x(z_south) < FAIRWAY + 40.0:
		return false
	basin = PackedVector2Array([Vector2(west_x(z_north), z_north), Vector2(x_east, z_north),
		Vector2(x_east, z_south), Vector2(west_x(z_south), z_south)])
	var sea_end := macro.coast_x(zc) - JETTY_OUT
	channel = Rect2(sea_end, zc - CHANNEL_HALF, west_x(zc) + 2.0 - sea_end, CHANNEL_HALF * 2.0)
	var merged := Geometry2D.merge_polygons(basin, _rect_poly(channel))
	water = merged[0] if merged.size() > 0 else basin
	for poly: PackedVector2Array in merged:
		if not Geometry2D.is_polygon_clockwise(poly) and poly.size() > water.size():
			water = poly
	_plan_land()
	_plan_docks()
	_plan_yard()
	_plan_buildings()
	_plan_lights()
	_plan_traffic()
	ok = true
	return true


## The sand's inland edge at z (where the beach rises to the town).
func sand_x(z: float) -> float:
	return macro.coast_x(z) + macro.beach_width_at(z) + SAND_LIP


## The west seawall's x at z.
func west_x(z: float) -> float:
	return west_a + west_k * z


## True when chunk (ix, iz) is one of the marina's blocks (it builds the marina instead of a block).
func owns_block(ix: int, iz: int) -> bool:
	return ok and ix >= ix0 and ix < ix1 and iz >= iz0 and iz < iz1


## Every rect a chunk could own that the marina reaches outside its blocks (the channel, the
## jetties, the bridge and its ramps, the breakwater): MarinaBuild.extras() runs there.
func outer_bounds() -> Rect2:
	var r := channel.grow(14.0)
	r = r.merge(breakwater_rect().grow(20.0))
	var pch := pch_gap()
	r = r.merge(Rect2(macro.coast_x(pch.x) + 20.0, pch.x, 60.0, pch.y - pch.x))
	return r


## Rect round the breakwater's mound (the crest line runs along z at breakwater_x()).
func breakwater_rect() -> Rect2:
	var bx := breakwater_x()
	var half := BREAKWATER_CREST * 0.5 + (BREAKWATER_TOP - MOUND_FOOT) * MOUND_SLOPE
	return Rect2(bx - half, zc - BREAKWATER_HALF - half, half * 2.0, BREAKWATER_HALF * 2.0 + half * 2.0)


func breakwater_x() -> float:
	return macro.coast_x(zc) - BREAKWATER_OFF


## The z span [z0, z1] of the coast highway's gap (the bridge and its ramps replace its strip).
func pch_gap() -> Vector2:
	var half := CHANNEL_HALF + BRIDGE_ABUT + BRIDGE_RAMP
	# Snapped outward to the highway's own points (HillRoads._add_coast_highway(): every
	# COAST_STEP from its start), so its strip ends exactly where the bridge's ramps begin.
	var z0 := macro.shelf_full_z - 420.0
	var st := HillRoads.COAST_STEP
	return Vector2(z0 + st * floorf((zc - half - z0) / st), z0 + st * ceilf((zc + half - z0) / st))


## The coast highway's centre at z (HillRoads lays it COAST_INSET in from the waterline).
func pch_x(z: float) -> float:
	return macro.coast_x(z) + HillRoads.COAST_INSET


## The bridge deck's top at z (inside pch_gap()), from `end_y` (the strip's own height at the
## gap's ends) up to the crest over the channel.
func bridge_y(z: float, end_y: float) -> float:
	var d := absf(z - zc)
	var flat := CHANNEL_HALF + BRIDGE_ABUT
	if d <= flat:
		return WATER_Y + BRIDGE_CREST + BRIDGE_DECK
	var gap := pch_gap()
	var ramp := (zc - gap.x) if z < zc else (gap.y - zc)
	var t := clampf((d - flat) / maxf(ramp - flat, 1.0), 0.0, 1.0)
	return lerpf(WATER_Y + BRIDGE_CREST + BRIDGE_DECK, end_y, t * t * (3.0 - 2.0 * t))


## True when world XZ `p` is open water of the marina (basin or channel, to the jetty tips).
func in_water(p: Vector2) -> bool:
	if not ok:
		return false
	if channel.has_point(p):
		return true
	return Geometry2D.is_point_in_polygon(p, basin)


## True where world XZ `p` is the marina's (its site, the channel, the bridge): no city is built there.
func blocks(p: Vector2) -> bool:
	return ok and (site.has_point(p) or channel.grow(6.0).has_point(p))


## CityPlan.road_open()'s question: false for any road the marina closes - every road inside the
## site, and any road whose strip crosses the channel (west of the site: the beach ends of the
## streets, the grid road on the sand).
func road_open(plan: CityPlan, axis: int, index: int, along: float) -> bool:
	if not ok:
		return true
	var c := plan.road_pos(axis, index)
	var half := plan.road_width(axis, index) * 0.5
	var p := Vector2(c, along) if axis == CityPlan.AXIS_X else Vector2(along, c)
	if site.grow(-0.5).has_point(p):
		return false
	var strip := Rect2(c - half, along - 0.5, half * 2.0, 1.0) if axis == CityPlan.AXIS_X else Rect2(along - 0.5, c - half, 1.0, half * 2.0)
	if strip.intersects(channel.grow(6.0)):
		return false
	# The streets' beach ends between the site's north road and its south one, west of it: the
	# bridge's ramps stand on the sand there.
	if axis == CityPlan.AXIS_Z and index > iz0 and index < iz1 and along < site.position.x:
		var gap := pch_gap()
		if c > gap.x - 12.0 and c < gap.y + 12.0:
			return false
	return true


## The relief inside the marina: the site flat at QUAY_Y, handed back to `h` over TERRACE_FADE
## outside it. Never on the sand (west of its inland edge): the beach keeps its own heights, and
## the coast highway on it its own.
func terrace(p: Vector2, h: float) -> float:
	if not ok:
		return h
	var r := site
	var dx := maxf(maxf(r.position.x - p.x, p.x - r.end.x), 0.0)
	var dz := maxf(maxf(r.position.y - p.y, p.y - r.end.y), 0.0)
	var d := sqrt(dx * dx + dz * dz)
	if d >= TERRACE_FADE:
		return h
	if p.x < sand_x(p.y) - 0.5:
		return h
	var w := 1.0 - d / TERRACE_FADE
	w = w * w * (3.0 - 2.0 * w)
	return lerpf(h, QUAY_Y, w)


static func _rect_poly(r: Rect2) -> PackedVector2Array:
	return PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])


# --- Land -----------------------------------------------------------------------------------------

func _plan_land() -> void:
	# The land: the site east of the sand's edge (plus the promenade strip the edge leaves in the
	# site's north-west corner), less the water.
	land = PackedVector2Array()
	for p: Vector2 in sand_edge:
		if p.y >= site.position.y - 0.01 and p.y <= site.end.y + 0.01:
			land.append(Vector2(maxf(p.x + BANK, site.position.x), p.y))
	land.insert(0, Vector2(maxf(sand_x(site.position.y) + BANK, site.position.x), site.position.y))
	land.append(Vector2(maxf(sand_x(site.end.y) + BANK, site.position.x), site.end.y))
	land.append(site.end)
	land.append(Vector2(site.end.x, site.position.y))
	var pieces := Geometry2D.clip_polygons(land, water)
	# The promenade: within PROM of the water (pavers), the rest by zone.
	var prom := Geometry2D.offset_polygon(water, 9.0, Geometry2D.JOIN_MITER)
	var zones: Array = [
		# The boat yard south of the basin and the channel.
		[Rect2(site.position.x, z_south, site.size.x, site.end.y - z_south), Ground.CONCRETE],
		# The towers' side: their plazas.
		[Rect2(x_east, z_north, site.end.x - x_east, z_south - z_north), Ground.PAVERS],
		# The north side: restaurants' terraces and the car park.
		[Rect2(site.position.x, site.position.y, site.size.x, z_north - site.position.y), Ground.PAVERS],
		# The west strip: lawn and the bike path.
		[Rect2(site.position.x - 40.0, z_north, west_x(z_north) - site.position.x + 60.0, z_south - z_north), Ground.LAWN],
	]
	grounds = []
	for piece: PackedVector2Array in pieces:
		if Geometry2D.is_polygon_clockwise(piece):
			continue
		var rest: Array = [piece]
		# Promenade first.
		var next: Array = []
		for r: PackedVector2Array in rest:
			for pr: PackedVector2Array in prom:
				for q: PackedVector2Array in Geometry2D.intersect_polygons(r, pr):
					grounds.append({"poly": q, "kind": Ground.PAVERS})
			var left: Array = [r]
			for pr: PackedVector2Array in prom:
				var l2: Array = []
				for l: PackedVector2Array in left:
					for q: PackedVector2Array in Geometry2D.clip_polygons(l, pr):
						if not Geometry2D.is_polygon_clockwise(q):
							l2.append(q)
				left = l2
			next.append_array(left)
		rest = next
		for zone: Array in zones:
			var zp := _rect_poly(zone[0])
			var left: Array = []
			for r: PackedVector2Array in rest:
				for q: PackedVector2Array in Geometry2D.intersect_polygons(r, zp):
					grounds.append({"poly": q, "kind": zone[1]})
				for q: PackedVector2Array in Geometry2D.clip_polygons(r, zp):
					if not Geometry2D.is_polygon_clockwise(q):
						left.append(q)
			rest = left
		for r: PackedVector2Array in rest:
			grounds.append({"poly": r, "kind": Ground.PAVERS})
	# The bike path down the west promenade, a metre in from the sand's edge bank, from the
	# site's north road to the channel's north bank, and from its south bank to the south road
	# (the bridge's ramps carry the highway over; the path ducks under at the bank).
	bike_path = PackedVector2Array()
	for p: Vector2 in sand_edge:
		if p.y >= site.position.y and p.y <= site.end.y:
			bike_path.append(Vector2(p.x + BANK + 3.0, p.y))
	# Palms along the west promenade and the east quay, lamps along every quay, benches facing
	# the water.
	palms = []
	lamps = []
	benches = []
	var z := z_north + 6.0
	var i := 0
	while z < z_south - 4.0:
		if absf(z - zc) > CHANNEL_HALF + 6.0:
			var wx := (sand_x(z) + BANK + west_x(z)) * 0.5 + 2.0
			if i % 2 == 0:
				palms.append(Vector2(wx + 2.5, z))
			if i % 3 == 1:
				lamps.append(Vector2(west_x(z) - 2.0, z))
			if i % 3 == 2:
				benches.append({"p": Vector2(west_x(z) - 3.2, z), "yaw": -PI * 0.5})
		var ex := x_east + 4.0
		if i % 2 == 0:
			palms.append(Vector2(ex + 5.5, z))
		if i % 3 == 0:
			lamps.append(Vector2(ex - 2.2, z))
		if i % 3 == 2:
			benches.append({"p": Vector2(ex - 1.0, z), "yaw": PI * 0.5})
		z += 9.0
		i += 1
	var x := west_x(z_north) + 8.0
	i = 0
	while x < x_east - 4.0:
		if i % 3 == 0:
			lamps.append(Vector2(x, z_north - 2.2))
		if i % 2 == 1:
			palms.append(Vector2(x, z_north - 7.0))
		x += 10.0
		i += 1


# --- Docks and boats ----------------------------------------------------------------------------

func _plan_docks() -> void:
	docks = []
	piles = []
	gangways = []
	boats = []
	# The east headwalk along the east bulkhead, the full length of the basin.
	var hx := x_east - BULK_GAP - HEAD_W * 0.5
	docks.append({"a": Vector2(hx, z_north + 4.0), "b": Vector2(hx, z_south - 4.0), "w": HEAD_W, "kind": "head"})
	# The west headwalk along the west seawall, north of the channel: side-tied big yachts on it.
	var wz0 := z_north + 4.0
	var wz1 := zc - CHANNEL_HALF - 6.0
	var wa := Vector2(west_x(wz0) + BULK_GAP + HEAD_W * 0.5, wz0)
	var wb := Vector2(west_x(wz1) + BULK_GAP + HEAD_W * 0.5, wz1)
	docks.append({"a": wa, "b": wb, "w": HEAD_W, "kind": "head"})
	# Gangways down to the west headwalk, and its pilings.
	var wdir := (wb - wa).normalized()
	var wn := Vector2(wdir.y, -wdir.x) # toward the land (west)
	if wn.x > 0.0:
		wn = -wn
	for t: float in [0.22, 0.72]:
		var p := wa.lerp(wb, t)
		gangways.append({"top": p + wn * (BULK_GAP + HEAD_W * 0.5 + 8.0), "bottom": p + wn * (HEAD_W * 0.5 - 0.2) - wdir * 0.0, "w": 1.5, "along": wdir})
	var wl := wa.distance_to(wb)
	var s := 4.0
	while s < wl - 2.0:
		piles.append(wa + wdir * s + wn * -(HEAD_W * 0.5 + 0.35))
		s += 12.0
	# Side-tied yachts along the west headwalk's water side, bow north.
	s = 3.0
	var k := 0
	while s < wl - 8.0:
		var t := Type.MOTOR if h01(["wtype", k]) < 0.7 else Type.SAIL
		var length := lerpf(15.0, 23.0, h01(["wlen", k])) if t == Type.MOTOR else lerpf(12.0, 15.5, h01(["wlen", k]))
		if s + length > wl - 2.0:
			break
		if h01(["wocc", k]) < 0.86:
			var beam := _beam(t, length)
			var c := wa + wdir * (s + length * 0.5) - wn * (HEAD_W * 0.5 + 0.5 + beam * 0.5)
			boats.append(_boat(t, length, c, wdir, k + 5000))
		s += length + 3.5
		k += 1
	# Main docks west from the east headwalk, every DOCK_PITCH, fingers both sides.
	var z := z_north + FIRST_DOCK
	var di := 0
	while z <= z_south - FIRST_DOCK + 0.01:
		var x_end := west_x(z) + FAIRWAY
		# South of the channel's north bank the fairway turns out into the channel: keep the
		# docks clear of it.
		if z > zc - CHANNEL_HALF - FINGER_LEN - 4.0:
			x_end = maxf(x_end, west_x(z) + FAIRWAY + 18.0)
		var x_root := hx - HEAD_W * 0.5
		if x_root - x_end < 30.0:
			z += DOCK_PITCH
			continue
		docks.append({"a": Vector2(x_root, z), "b": Vector2(x_end, z), "w": MAIN_W, "kind": "main"})
		# A gangway down to the east headwalk by every other main dock's root.
		if di % 2 == 0:
			gangways.append({"top": Vector2(x_east + 8.0, z + 6.0), "bottom": Vector2(hx + HEAD_W * 0.5 - 0.2, z + 6.0), "w": 1.5, "along": Vector2(0.0, 1.0)})
		# Slips: first one a slip off the headwalk.
		var x := x_root - 3.0 - SLIP_PITCH
		var slip := 0
		while x > x_end + SLIP_PITCH * 0.5:
			for side: float in [-1.0, 1.0]:
				var fz := z + side * MAIN_W * 0.5
				# The finger (from the main dock's edge out FINGER_LEN), with a pile at its tip.
				docks.append({"a": Vector2(x, fz), "b": Vector2(x, fz + side * FINGER_LEN), "w": FINGER_W, "kind": "finger"})
				if slip % 2 == 0:
					piles.append(Vector2(x, fz + side * (FINGER_LEN + 0.45)))
				# The boat in the slip west of this finger (between it and the next one).
				var key := [di, slip, side]
				if h01(["occ"] + key) < OCCUPIED:
					var t := _type_roll(h01(["type"] + key), z, x)
					var length := _len_roll(t, h01(["len"] + key))
					var beam := _beam(t, length)
					if beam > SLIP_PITCH - FINGER_W - 0.35:
						length *= (SLIP_PITCH - FINGER_W - 0.35) / beam
						beam = SLIP_PITCH - FINGER_W - 0.35
					var bow_in := h01(["bow"] + key) < 0.8
					var dir := Vector2(0.0, side if bow_in else -side)
					var c := Vector2(x - SLIP_PITCH * 0.5, fz + side * (0.55 + length * 0.5))
					boats.append(_boat(t, length, c, dir, hash(key)))
			x -= SLIP_PITCH
			slip += 1
		# Guide piles along the main dock.
		var px := x_root - 6.0
		while px > x_end + 4.0:
			piles.append(Vector2(px, z - MAIN_W * 0.5 - 0.35))
			px -= 24.0
		di += 1
		z += DOCK_PITCH
	# Pile caps along the east headwalk.
	var pz := z_north + 8.0
	while pz < z_south - 6.0:
		piles.append(Vector2(hx + HEAD_W * 0.5 + 0.35, pz))
		pz += 14.0


func _type_roll(r: float, _z: float, _x: float) -> int:
	for t in TYPE_ODDS.size():
		if r < float(TYPE_ODDS[t]):
			return t
	return Type.SAIL


func _len_roll(t: int, r: float) -> float:
	match t:
		Type.SAIL:
			return lerpf(8.5, 13.5, r)
		Type.MOTOR:
			return lerpf(11.0, 15.0, r)
		Type.FISHER:
			return lerpf(10.0, 14.0, r)
	return lerpf(5.5, 7.5, r)


## A boat's beam for its type and length (real proportions).
static func _beam(t: int, length: float) -> float:
	match t:
		Type.SAIL:
			return length * 0.33
		Type.MOTOR:
			return length * 0.29
		Type.FISHER:
			return length * 0.32
	return length * 0.36


func _boat(t: int, length: float, c: Vector2, bow: Vector2, key: int) -> Dictionary:
	var paint: Color = HULL_PAINTS[int(h01(["paint", key]) * HULL_PAINTS.size()) % HULL_PAINTS.size()]
	var canvas: Color = CANVAS[int(h01(["canvas", key]) * CANVAS.size()) % CANVAS.size()]
	var variant := 1 if h01(["var", key]) < 0.45 else 0
	return {"p": c, "yaw": atan2(-bow.x, -bow.y), "type": t, "len": length, "scale": length / float(REF_LEN[t]),
		"paint": paint, "canvas": canvas, "seed": key, "variant": variant,
		"lit": h01(["lit", key]) < 0.2, "anchor": t == Type.SAIL and h01(["anchor", key]) < 0.14,
		"phase": h01(["phase", key])}


# --- The boat yard ------------------------------------------------------------------------------

func _plan_yard() -> void:
	yard_boats = []
	# The travel lift's well: two piers out from the south bulkhead into the fairway, west of the docks.
	var wx := west_x(z_south) + 26.0
	lift_well = Rect2(wx - 3.6, z_south - 17.0, 7.2, 17.0)
	# Boats on stands in rows across the yard, east of the well, in from the bulkhead.
	var x := wx + 16.0
	var k := 0
	var depth := site.end.y - z_south
	var rows := clampi(int((depth - 30.0) / 15.0) + 1, 1, 5)
	while x < site.end.x - 8.0:
		for row in rows:
			var z := z_south + 12.0 + row * 15.0
			if z > z_south + depth - 24.0:
				continue
			# The shed's corner by the south road.
			if x > site.end.x - 40.0 and z > site.end.y - 30.0:
				continue
			if h01(["yocc", k, row]) < 0.82:
				var t := Type.SAIL if h01(["ytype", k, row]) < 0.55 else (Type.FISHER if h01(["ytype2", k, row]) < 0.5 else Type.MOTOR)
				var length := _len_roll(t, h01(["ylen", k, row]))
				yard_boats.append(_boat(t, length, Vector2(x, z), Vector2(1.0 if row % 2 == 0 else -1.0, 0.0).rotated(PI * 0.5), 9000 + k * 8 + row))
		x += 9.5
		k += 1


# --- Buildings ----------------------------------------------------------------------------------

func _plan_buildings() -> void:
	buildings = []
	car_parks = []
	# Waterfront apartment towers on the east land: three, between car parks.
	var east_w := site.end.x - x_east
	var tw := minf(32.0, east_w - 22.0)
	var span := z_south - z_north
	var n := 3
	for k in n:
		var cz := z_north + span * (float(k) + 0.5) / n
		var r := Rect2(site.end.x - 6.0 - tw, cz - 17.0, tw, 34.0)
		buildings.append({"rect": r, "kind": "tower", "seed": absi(hash([seed_value, "marina_tower", k]))})
		if k < n - 1:
			var cz2 := z_north + span * (float(k) + 1.5) / n
			car_parks.append(Rect2(x_east + 12.0, cz + 21.0, site.end.x - 4.0 - x_east - 12.0, cz2 - cz - 42.0))
	# Restaurants along the north quay, on the water, and the car park behind them on the road.
	var nx0 := west_x(z_north) + 14.0
	var nx1 := x_east - 6.0
	var count := clampi(int((nx1 - nx0) / 44.0), 1, 4)
	for k in count:
		var cx := lerpf(nx0, nx1, (float(k) + 0.5) / count)
		var r := Rect2(cx - 10.0, z_north - 9.0 - 13.0, 20.0, 13.0)
		buildings.append({"rect": r, "kind": "restaurant", "seed": absi(hash([seed_value, "marina_rest", k]))})
	car_parks.append(Rect2(nx0 - 4.0, site.position.y + 3.0, nx1 - nx0 + 8.0, z_north - 9.0 - 13.0 - 4.0 - site.position.y - 3.0))
	# The boat yard's car park along the south road, west of the shed.
	car_parks.append(Rect2(west_x(z_south) + 50.0, site.end.y - 19.0, site.end.x - 44.0 - west_x(z_south) - 50.0, 17.8))
	# The boat yard's office and shed by the south road.
	buildings.append({"rect": Rect2(site.end.x - 34.0, site.end.y - 16.0, 28.0, 12.0), "kind": "shed", "seed": absi(hash([seed_value, "marina_shed"]))})
	# Car park lamps along each car park's long sides.
	for cp: Rect2 in car_parks:
		if cp.size.x < 8.0 or cp.size.y < 8.0:
			continue
		var x := cp.position.x + 6.0
		while x < cp.end.x - 3.0:
			lamps.append(Vector2(x, cp.get_center().y))
			x += 26.0


# --- Lights and traffic ---------------------------------------------------------------------------

func _plan_lights() -> void:
	nav_lights = []
	var tip := macro.coast_x(zc) - JETTY_OUT + 3.0
	# Coming in from the sea heading east, starboard (south) is red, port (north) green.
	nav_lights.append({"p": Vector2(tip, zc + CHANNEL_HALF + JETTY_CREST * 0.5 + 1.0), "color": Color(1.0, 0.12, 0.08), "tower": true, "phase": 0.0})
	nav_lights.append({"p": Vector2(tip, zc - CHANNEL_HALF - JETTY_CREST * 0.5 - 1.0), "color": Color(0.1, 1.0, 0.35), "tower": false, "phase": 0.5})
	var bx := breakwater_x()
	for e: float in [-1.0, 1.0]:
		nav_lights.append({"p": Vector2(bx, zc + e * (BREAKWATER_HALF - 4.0)), "color": Color(1.0, 0.96, 0.85), "tower": false, "phase": 0.25 + e * 0.1})


func _plan_traffic() -> void:
	# Out of the fairway's north end, down it, west along the channel past the jetties, a wide
	# turn in the lee of the breakwater, back in along the channel's other side and up the fairway.
	traffic_loop = PackedVector2Array()
	var fx := west_x(z_north + 40.0) + 14.0
	traffic_loop.append(Vector2(fx, z_north + 40.0))
	traffic_loop.append(Vector2(west_x(zc - 30.0) + 14.0, zc - 30.0))
	traffic_loop.append(Vector2(west_x(zc) - 10.0, zc - 7.0))
	traffic_loop.append(Vector2(channel.position.x + 6.0, zc - 7.0))
	traffic_loop.append(Vector2(macro.coast_x(zc) - 105.0, zc - 26.0))
	traffic_loop.append(Vector2(macro.coast_x(zc) - 128.0, zc))
	traffic_loop.append(Vector2(macro.coast_x(zc) - 105.0, zc + 26.0))
	traffic_loop.append(Vector2(channel.position.x + 6.0, zc + 7.0))
	traffic_loop.append(Vector2(west_x(zc) - 10.0, zc + 7.0))
	traffic_loop.append(Vector2(west_x(zc - 30.0) + 26.0, zc - 26.0))
	traffic_loop.append(Vector2(west_x(z_north + 40.0) + 26.0, z_north + 34.0))
