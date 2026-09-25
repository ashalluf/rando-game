extends RefCounted
## Checks for downtown at 1:1 (DowntownReal), run from tests/smoke_test.gd after the skyline's
## own checks. Loaded at run time so it compiles after the autoloads. Pure maths on the plan,
## the tables and the macro map: nothing here streams the city.
##
## What it pins down: the real streets are roads on every seed, in the real order, at the real
## block spacing; the towers and civic buildings stand at their geocoded positions (to within the
## few metres a block's pavement clamps them by); a few real distances survive the turn onto the
## game's axes; and the frame round the area is the real one - the 110 down the west edge, the
## 101 across the north, the 10 to the south, the hills behind the civic centre, the airport to
## the south-west, the masjid on Exposition to the south.

var _t: Node


func run(t: Node, city: Node3D) -> void:
	_t = t
	var plan: CityPlan = city.get("plan")
	if plan == null or plan.macro == null:
		return
	var macro: MacroMap = plan.macro
	var other := CityPlan.new()
	other.seed = 4242
	other.block_size_range = plan.block_size_range
	other.street_width = plan.street_width
	other.avenue_width = plan.avenue_width
	other.sidewalk_width = plan.sidewalk_width

	# Every real street is a road, at its fitted position and width, named, on two seeds.
	var missing := ""
	for axis in 2:
		for pin: Array in DowntownReal.pins()[axis]:
			for p: CityPlan in [plan, other]:
				var i := p._index_at(axis, float(pin[0]) + 0.01)
				if absf(p.road_pos(axis, i) - float(pin[0])) > 0.01 or absf(p.road_width(axis, i) - float(pin[1])) > 0.01 \
						or p.road_name(axis, i) != str(pin[2]):
					missing += " %s(seed %d)" % [pin[2], p.seed]
	_check(missing == "", "every real downtown street is a road on this seed and another, named%s" % missing)

	# The real order: consecutive roads, west to east and north to south, with no seeded road
	# between two real ones.
	var order := ""
	var avenues := ["GEORGIA ST", "FIGUEROA ST", "FLOWER ST", "HOPE ST", "GRAND AVE", "OLIVE ST", "HILL ST",
		"BROADWAY", "SPRING ST", "MAIN ST", "ALAMEDA ST", "VIGNES ST"]
	var streets := ["CESAR CHAVEZ AVE", "ARCADIA ST", "TEMPLE ST", "1ST ST", "2ND ST", "3RD ST", "4TH ST", "5TH ST",
		"6TH ST", "WILSHIRE BLVD", "7TH ST", "8TH ST", "9TH ST", "OLYMPIC BLVD", "11TH ST", "PICO BLVD", "VENICE BLVD"]
	for pair: Array in [[CityPlan.AXIS_X, avenues], [CityPlan.AXIS_Z, streets]]:
		var axis: int = pair[0]
		var names: Array = pair[1]
		var first := plan._index_at(axis, _pin_pos(axis, names[0]) + 0.01)
		for k in names.size():
			if plan.road_name(axis, first + k) != names[k]:
				order += " %s at %d is %s" % [names[k], first + k, plan.road_name(axis, first + k)]
				break
	_check(order == "", "the real streets run in the real order, one block apart%s" % order)

	# True block spacing (centre line to centre line), from the fit: the avenues 120-130 m apart,
	# the numbered streets 200 m, and a few exact ones.
	var spacing := ""
	for probe: Array in [[CityPlan.AXIS_X, "FIGUEROA ST", "FLOWER ST", 125.9], [CityPlan.AXIS_X, "HILL ST", "BROADWAY", 126.6],
			[CityPlan.AXIS_X, "BROADWAY", "SPRING ST", 122.0], [CityPlan.AXIS_Z, "1ST ST", "2ND ST", 164.0],
			[CityPlan.AXIS_Z, "4TH ST", "5TH ST", 202.5], [CityPlan.AXIS_Z, "5TH ST", "6TH ST", 200.2],
			[CityPlan.AXIS_Z, "7TH ST", "8TH ST", 200.4], [CityPlan.AXIS_Z, "9TH ST", "OLYMPIC BLVD", 198.9]]:
		var d := _pin_pos(probe[0], probe[2]) - _pin_pos(probe[0], probe[1])
		if absf(d - float(probe[3])) > 0.6:
			spacing += " %s-%s %.1f/%.1f" % [probe[1], probe[2], d, probe[3]]
	for i in range(1, 8):
		var d := _pin_pos(CityPlan.AXIS_X, avenues[i + 1]) - _pin_pos(CityPlan.AXIS_X, avenues[i])
		if d < 118.0 or d > 132.0:
			spacing += " %s-%s %.1f" % [avenues[i], avenues[i + 1], d]
	for pair: Array in [["2ND ST", "3RD ST"], ["3RD ST", "4TH ST"], ["6TH ST", "7TH ST"], ["8TH ST", "9TH ST"], ["OLYMPIC BLVD", "11TH ST"]]:
		var d := _pin_pos(CityPlan.AXIS_Z, pair[1]) - _pin_pos(CityPlan.AXIS_Z, pair[0])
		if d < 195.0 or d > 212.0:
			spacing += " %s-%s %.1f" % [pair[0], pair[1], d]
	_check(spacing == "", "downtown's blocks are the real size: avenues ~125 m apart, numbered streets ~200 m%s" % spacing)

	# Each tower stands at its geocoded point, clamped into its block by no more than a few metres.
	var off_real := ""
	var worst := 0.0
	for id: String in LandmarkDowntown.TOWERS:
		var d := LandmarkDowntown.anchor(id).distance_to(LandmarkDowntown.real_xz(id))
		worst = maxf(worst, d)
		if d > 30.0:
			off_real += " %s %.0f m" % [id, d]
	_check(off_real == "", "every downtown tower stands at its real position (worst %.1f m off)%s" % [worst, off_real])
	var civic_off := ""
	for id: String in CivicSites.ORDER:
		var info := CivicSites.site(plan, id)
		var d := (info.centre as Vector2).distance_to(CivicSites.real_xz(id))
		if d > float(CivicSites.SITES[id].get("tolerance", 60.0)):
			civic_off += " %s %.0f m" % [id, d]
	_check(civic_off == "", "every civic building's site is centred on its real position%s" % civic_off)

	# Real distances survive the turn: the game distance between two landmarks is the real one.
	var dist := ""
	var hall := CivicSites.real_xz("ziggurat_hall")
	var arena := CivicSites.real_xz("arena")
	var real_ha := DowntownReal.real_distance("200_n_spring", "1111_s_figueroa")
	if absf(hall.distance_to(arena) - real_ha) > 1.0 or absf(real_ha - 2530.0) > 60.0:
		dist += " hall-arena %.0f/%.0f" % [hall.distance_to(arena), real_ha]
	for pair: Array in [["dt_sail_tower", "dt_crown_cylinder", "900_wilshire", "633_w_5th"],
			["dt_five_drums", "dt_ellipse_crown", "404_s_figueroa", "555_w_5th"]]:
		var g := LandmarkDowntown.anchor(pair[0]).distance_to(LandmarkDowntown.anchor(pair[1]))
		var r := DowntownReal.real_distance(pair[2], pair[3])
		if absf(g - r) > 30.0:
			dist += " %s-%s %.0f/%.0f" % [pair[0], pair[1], g, r]
	var station := CivicSites.real_xz("pueblo_station")
	if absf(hall.distance_to(station) - DowntownReal.real_distance("200_n_spring", "800_n_alameda")) > 1.0:
		dist += " hall-station"
	_check(dist == "", "real distances survive the turn onto the grid (city hall to the arena %.0f m)%s" % [real_ha, dist])

	# The frame: the civic centre north-east of the airport with the hills behind it, the arena
	# south-west of city hall, the 110 down the west edge, the 101 across the north, the 10 below.
	var frame := ""
	var airport := macro.airport_rect
	if not (hall.x > airport.end.x and hall.y < airport.position.y):
		frame += " city hall not north-east of the airport"
	if macro.raw_height_at(hall) > 0.5 or macro.raw_height_at(hall + Vector2(0.0, -1600.0)) < 80.0:
		frame += " no hills north of the civic centre (%.0f m)" % macro.raw_height_at(hall + Vector2(0.0, -1600.0))
	if macro.district_at(hall) != CityPlan.District.DOWNTOWN or macro.district_at(arena) != CityPlan.District.DOWNTOWN:
		frame += " civic centre or arena not downtown"
	if not (arena.x < hall.x and arena.y > hall.y):
		frame += " arena not south-west of city hall"
	var fw: Freeway = macro.freeway
	var fig := _pin_pos(CityPlan.AXIS_X, "FIGUEROA ST")
	var geo := _pin_pos(CityPlan.AXIS_X, "GEORGIA ST")
	for street: String in ["5TH ST", "8TH ST", "OLYMPIC BLVD", "PICO BLVD"]:
		var z := _pin_pos(CityPlan.AXIS_Z, street)
		var hit := false
		for x in range(int(geo) - 320, int(fig), 4):
			if _route_blocks(fw, "110", Vector2(float(x), z)):
				hit = true
				break
		if not hit:
			frame += " no 110 west of Figueroa at %s" % street
	var temple := _pin_pos(CityPlan.AXIS_Z, "TEMPLE ST")
	var chavez := _pin_pos(CityPlan.AXIS_Z, "CESAR CHAVEZ AVE")
	var spring := _pin_pos(CityPlan.AXIS_X, "SPRING ST")
	var north := false
	for z in range(int(chavez), int(temple), 4):
		if _route_blocks(fw, "101", Vector2(spring, float(z))):
			north = true
	if not north:
		frame += " no 101 north of Temple at Spring"
	var venice := _pin_pos(CityPlan.AXIS_Z, "VENICE BLVD")
	var south := false
	for z in range(int(venice), int(venice) + 1200, 4):
		if _route_blocks(fw, "10", Vector2(_pin_pos(CityPlan.AXIS_X, "BROADWAY"), float(z))):
			south = true
	if not south:
		frame += " no 10 south of Venice at Broadway"
	# No freeway deck runs through the core east of Figueroa: the old cross route cut the Financial
	# District. (The core rects start at the 110 - Bunker Hill's west side is the freeway's cut - so
	# the deck along their west edge is the real one.)
	for r: Rect2 in macro.downtown_core:
		var east := Rect2(Vector2(maxf(r.position.x, fig + 20.0), r.position.y), Vector2(r.end.x - maxf(r.position.x, fig + 20.0), r.size.y))
		for i in 12:
			for j in 12:
				var p := east.position + east.size * Vector2((float(i) + 0.5) / 12.0, (float(j) + 0.5) / 12.0)
				if fw.blocks(p, 0.0) and not frame.contains("core"):
					frame += " a deck crosses the core at %s" % p
	_check(frame == "", "downtown sits in its real frame: freeways round it, hills behind, the airport south-west%s" % frame)

	# MacArthur Park's ground: its two sides are real roads, Wilshire runs between them, and it is
	# at its real distance along Wilshire from Figueroa.
	var mac: Dictionary = DowntownReal.MACARTHUR
	var west := DowntownReal.to_game(Vector2(mac.west_u, 0.0)).x
	var east := DowntownReal.to_game(Vector2(mac.east_u, 0.0)).x
	var mac_ok := not DowntownReal.pin_at(CityPlan.AXIS_X, west).is_empty() and not DowntownReal.pin_at(CityPlan.AXIS_X, east).is_empty()
	var along := fig - (west + east) * 0.5
	var real_along := DowntownReal.grid_uv(DowntownReal.real_en(DowntownReal.POINTS.macarthur_park)).x
	mac_ok = mac_ok and absf(along - (DowntownReal.AVENUES[3].u - real_along)) < 40.0
	_check(mac_ok, "MacArthur Park's sides are real roads, %.0f m west of Figueroa along Wilshire" % along)

	# Masjid Omar ibn Al-Khattab (LandmarkMasjidOmar) is where the real one is relative to downtown:
	# grid-south of Pershing Square below Venice, on the real building's line to within 60 m (its
	# real point is past the port, so the distance south is compressed), west of the 110, south of
	# where the 10 leaves it, north of the 105 - the real order.
	var masjid := Vector2.INF
	for lm in Landmarks.all():
		if lm.id == "masjid_omar":
			masjid = lm.anchor
	var mq := ""
	var real_m := DowntownReal.game_xz(LandmarkMasjidOmar.REAL_LATLON)
	if masjid == Vector2.INF:
		mq = " not in the landmark table"
	else:
		if absf(masjid.x - real_m.x) > 60.0:
			mq += " %.0f m off its real line (x %.0f, real %.0f)" % [absf(masjid.x - real_m.x), masjid.x, real_m.x]
		if masjid.y < venice + 200.0:
			mq += " not south of Venice Blvd"
		var at_110 := _route_x_at(fw, "110", masjid.y)
		if not (masjid.x + 60.0 < at_110):
			mq += " not west of the 110 (x %.0f there)" % at_110
		var ten: PackedVector2Array = _route(fw, "10")
		if ten.is_empty() or masjid.y < ten[0].y:
			mq += " not south of the 10"
		var cross := _route_z_at(fw, "105", masjid.x)
		if not (cross > masjid.y + LandmarkMasjidOmar.BLD_OFFSET.z + LandmarkMasjidOmar.SITE_Z1 + 40.0):
			mq += " not north of the 105 (z %.0f there)" % cross
	_check(mq == "", "the masjid stands south of downtown where the real one does: west of the 110, between the 10 and the 105%s" % mq)
	_freeways_clear(plan, city)


## No freeway deck, pillar or off-ramp passes through anything built downtown (owner, 2026-09-25:
## "theres freeways in downtown going straight thru buildings"). Walks every deck segment within
## 800 m of downtown's extent, captures the LOD build of every block the deck or a ramp crosses
## (CityChunk.capturing: the very boxes the far city and the LOD chunk draw - every building
## part, plinth, big-box wall and pad; the FULL chunk builds the same lots) and tests each box
## over 2.5 m tall against the corridors, then the named towers' plans and the civic sites.
func _freeways_clear(plan: CityPlan, city: Node3D) -> void:
	var fw: Freeway = plan.macro.freeway
	var region := DowntownReal.game_extent().grow(800.0)
	var style: Dictionary = city.call("chunk_style")
	var blocks := {}
	var segs := 0
	for route: Dictionary in fw.routes:
		var pts: PackedVector2Array = route.points
		var half: float = float(route.width) * 0.5 + 3.0
		for si in pts.size() - 1:
			var mid := (pts[si] + pts[si + 1]) * 0.5
			if not region.has_point(mid):
				continue
			segs += 1
			var along := (pts[si + 1] - pts[si]).normalized()
			var across := Vector2(-along.y, along.x) * half
			for q: Vector2 in [pts[si], mid, mid + across, mid - across]:
				blocks[plan.block_index_at(q)] = true
	for r: Dictionary in fw.ramps:
		if region.has_point(r.pos):
			for q: Vector2 in Freeway.ramp_path(r):
				blocks[plan.block_index_at(q)] = true
	var hits: Array[String] = []
	var boxes := 0
	for k: Vector2i in blocks:
		var zone := plan.macro.zone_at((plan.block(k.x, k.y).rect as Rect2).get_center())
		if zone != MacroMap.Zone.CITY and zone != MacroMap.Zone.PORT:
			continue
		var cap := CityChunk.new()
		cap.plan = plan
		cap.ix = k.x
		cap.iz = k.y
		cap.level = CityChunk.Level.LOD
		cap.style = style
		cap.capturing = true
		cap.build()
		var xforms: Array = (cap.captured.get("batch", {}) as Dictionary).get("lod_box", {"xforms": []}).xforms.duplicate()
		for box: Array in cap.captured.get("boxes", []):
			xforms.append(box[0])
		cap.free()
		for xf: Transform3D in xforms:
			var bb := xf * AABB(Vector3(-0.5, -0.5, -0.5), Vector3.ONE)
			if bb.size.y < 2.5:
				continue
			boxes += 1
			var foot := Rect2(bb.position.x, bb.position.z, bb.size.x, bb.size.z)
			if fw.blocks_rect(foot, 0.0) and hits.size() < 6:
				hits.append("block %s box at (%.0f, %.0f)" % [k, foot.get_center().x, foot.get_center().y])
	for lm in Landmarks.all():
		var id: String = lm.id
		var foot := Rect2()
		if id.begins_with("dt_"):
			foot = LandmarkDowntown.footprint(lm)
		elif CivicSites.SITES.has(id):
			foot = CivicSites.site(plan, id).world
		elif id == "masjid_omar":
			var m := Vector2(lm.anchor) + Vector2(LandmarkMasjidOmar.BLD_OFFSET.x, LandmarkMasjidOmar.BLD_OFFSET.z)
			foot = Rect2(m.x + LandmarkMasjidOmar.SITE_X0, m.y + LandmarkMasjidOmar.SITE_Z0,
				LandmarkMasjidOmar.SITE_X1 - LandmarkMasjidOmar.SITE_X0, LandmarkMasjidOmar.SITE_Z1 - LandmarkMasjidOmar.SITE_Z0)
		else:
			continue
		if fw.blocks_rect(foot, 0.0):
			hits.append(id)
	# Out in the basin: no deck over the airport (its terminal, its runways - the 405 used to cross
	# all three at nine metres, in the jets' way) or the port.
	for named in [["airport", plan.macro.airport_rect], ["port", plan.macro.port_rect]]:
		if fw.blocks_rect(named[1] as Rect2, 0.0):
			hits.append(str(named[0]))
	_check(segs > 100 and boxes > 500 and hits.is_empty(),
		"no freeway deck, pillar or ramp downtown passes through a building, tower, civic site or the masjid, nor over the airport or the port (%d segments, %d blocks, %d boxes)%s" \
		% [segs, blocks.size(), boxes, (": " + ", ".join(hits)) if not hits.is_empty() else ""])


## The named route's points, or [].
func _route(fw: Freeway, number: String) -> PackedVector2Array:
	for route: Dictionary in fw.routes:
		if str(route.name).begins_with(number + " "):
			return route.points
	return PackedVector2Array()


## World x where the named route crosses z (the first crossing), or INF.
func _route_x_at(fw: Freeway, number: String, z: float) -> float:
	var pts := _route(fw, number)
	for i in pts.size() - 1:
		if (pts[i].y - z) * (pts[i + 1].y - z) <= 0.0 and pts[i].y != pts[i + 1].y:
			return lerpf(pts[i].x, pts[i + 1].x, (z - pts[i].y) / (pts[i + 1].y - pts[i].y))
	return INF


## World z where the named route crosses x (the southernmost crossing), or -INF.
func _route_z_at(fw: Freeway, number: String, x: float) -> float:
	var pts := _route(fw, number)
	var best := -INF
	for i in pts.size() - 1:
		if (pts[i].x - x) * (pts[i + 1].x - x) <= 0.0 and pts[i].x != pts[i + 1].x:
			best = maxf(best, lerpf(pts[i].y, pts[i + 1].y, (x - pts[i].x) / (pts[i + 1].x - pts[i].x)))
	return best


func _pin_pos(axis: int, road_name: String) -> float:
	for pin: Array in DowntownReal.pins()[axis]:
		if str(pin[2]) == road_name:
			return float(pin[0])
	return NAN


## True when the named freeway (its name starts with `number`) blocks `pos`.
func _route_blocks(fw: Freeway, number: String, pos: Vector2) -> bool:
	for route: Dictionary in fw.routes:
		if not str(route.name).begins_with(number + " "):
			continue
		var pts: PackedVector2Array = route.points
		for i in pts.size() - 1:
			var a := pts[i]
			var ab := pts[i + 1] - a
			var f := clampf((pos - a).dot(ab) / maxf(ab.length_squared(), 0.001), 0.0, 1.0)
			if pos.distance_to(a + ab * f) < float(route.width) * 0.5:
				return true
	return false


func _check(ok: bool, label: String) -> void:
	_t._check(ok, label)
