extends RefCounted
## The marketplace lane by Pueblo Station (PuebloLane, PuebloMarket), for tests/smoke_test.gd.
## Loaded at run time, not named there, so it compiles after the autoloads.
##
## The site: on the plan, its block claimed (no lots), the plaza on the real plaza's point and in
## the real place relative to the station, clear of the freeways. The layout, pure: the lane north
## of the plaza, the stalls inside the lane in two rows that never overlap, aisles wide enough to
## walk, the walkers' rings clear of the stalls, the kiosk and the corredor posts; the church, the
## firehouse, the hotel and the car parks inside the site and clear of each other and the plaza.
## The build: near and far, under triangle budgets, collision near, the church a sanctuary (its
## zone holds the church and not the lane, its body in the sanctuary group), the vendors and their
## queue spots.

var _t: Node

## Triangles the near build may hold: the buildings and ground (LandmarkGeo), the market (stalls,
## goods, ironwork, bulbs), the paper and canvas.
const GEO_BUDGET := 90000
const MARKET_BUDGET := 260000
const PAPER_BUDGET := 40000
## And the far copy (all of it LandmarkGeo).
const FAR_BUDGET := 12000


func run(t: Node, city: Node3D) -> void:
	_t = t
	if not PuebloLane.enabled:
		_t._check(true, "the marketplace lane is off (PUEBLO_LANE=0)")
		return
	var plan: CityPlan = city.plan
	var lm := {}
	for e in Landmarks.all():
		if e.id == PuebloLane.ID:
			lm = e
	_t._check(not lm.is_empty() and lm.get("site", "") == "block", "the marketplace lane is a civic block site")
	if lm.is_empty():
		return
	var info := CivicSites.site(plan, PuebloLane.ID)
	var L := PuebloLane.layout(info.local, PuebloLane.kiosk_local(info))
	_site(plan, lm, info, L)
	_layout(L)
	await _build(t, plan, lm, info, L)


func _site(plan: CityPlan, lm: Dictionary, info: Dictionary, L: Dictionary) -> void:
	var idx := plan.block_index_at(lm.anchor)
	_t._check(plan.lots(idx.x, idx.y).is_empty() and Landmarks.claims(plan.block(idx.x, idx.y).rect),
		"the marketplace lane has its block to itself (no lots)")
	var real := DowntownReal.game_xz(PuebloLane.KIOSK_LATLON)
	var plaza := CivicSites.to_world(info, L.p)
	_t._check(plaza.distance_to(real) < 12.0, "the plaza's kiosk stands on the real plaza's point (%.1f m off)" % plaza.distance_to(real))
	# Where the real plaza is from the station: about 245 m grid-west and 26 m grid-south.
	var st := CivicSites.real_xz("pueblo_station")
	var d := plaza - st
	_t._check(d.x < -200.0 and d.x > -300.0 and absf(d.y) < 60.0,
		"the plaza is where the real one is from the station (%.0f m west, %.0f m south)" % [-d.x, d.y])
	var fw: Freeway = plan.macro.freeway if plan.macro else null
	_t._check(fw == null or not fw.blocks_rect(info.world, 0.0), "no freeway deck crosses the marketplace lane's site")
	_t._check(Minimap.LANDMARK_NAMES.has(PuebloLane.ID) and not str(Minimap.LANDMARK_NAMES[PuebloLane.ID]).to_lower().contains("olvera"),
		"the marketplace lane has an invented name on the map")


func _layout(L: Dictionary) -> void:
	var s: Rect2 = L.site
	var lane: Rect2 = L.lane
	var plaza: Rect2 = L.plaza
	var bad := ""
	for key in ["plaza", "lane", "west", "east", "church", "fire", "hotel", "east_lot", "east_lot2", "south_lot", "garden"]:
		var r: Rect2 = L[key]
		if not s.grow(0.01).encloses(r):
			bad += " " + key
	_t._check(bad == "", "everything of the marketplace lane stands inside its site%s" % bad)
	_t._check(lane.end.y <= plaza.position.y + 0.01 and lane.size.y > 90.0 and absf(lane.get_center().x - plaza.get_center().x) < 0.01,
		"the lane runs north from the plaza's middle (%.0f m)" % lane.size.y)
	# Buildings and car parks clear of each other, the plaza and the lane.
	var solids := {"church": L.church, "fire": L.fire, "hotel": L.hotel, "east_lot": L.east_lot, "east_lot2": L.east_lot2, "south_lot": L.south_lot,
		"west": L.west, "east": L.east, "plaza": plaza, "lane": lane}
	var keys := solids.keys()
	var clash := ""
	for i in keys.size():
		for j in range(i + 1, keys.size()):
			var a: Rect2 = solids[keys[i]]
			var b: Rect2 = solids[keys[j]]
			if a.grow(-0.05).intersects(b.grow(-0.05)):
				clash += " %s/%s" % [keys[i], keys[j]]
	_t._check(clash == "", "the marketplace lane's pieces do not overlap%s" % clash)
	# Stalls: inside the lane, never overlapping, an aisle of at least 3 m between the awning and
	# the fronts on both sides.
	var feet: Array[Rect2] = []
	var stall_bad := ""
	for st: Dictionary in L.stalls:
		var xf: Transform3D = st.xf
		var a := xf * Vector3(-PuebloMarket.STALL_W * 0.5, 0, 0)
		var b := xf * Vector3(PuebloMarket.STALL_W * 0.5, 0, -PuebloMarket.STALL_D)
		var r := Rect2(Vector2(minf(a.x, b.x), minf(a.z, b.z)), Vector2(absf(a.x - b.x), absf(a.z - b.z)))
		if not lane.encloses(r):
			stall_bad += " out%d" % int(st.id)
		for o in feet:
			if o.grow(-0.02).intersects(r.grow(-0.02)):
				stall_bad += " overlap%d" % int(st.id)
		feet.append(r)
		var front := xf * Vector3(0, 0, PuebloMarket.AWNING_OUT + 0.15)
		var aisle := PuebloLane.LANE_HALF - absf(front.x - lane.get_center().x)
		if aisle < 3.0:
			stall_bad += " aisle%d(%.1f)" % [int(st.id), aisle]
	_t._check(L.stalls.size() >= 40 and stall_bad == "", "%d stalls down the lane in two rows, clear of each other, aisles >= 3 m%s" % [L.stalls.size(), stall_bad])
	# The walkers' ring in the lane (crowds()) runs between the awnings and the corredor posts.
	var ring_x := PuebloLane.LANE_HALF - 2.0
	var awning := PuebloMarket.STALL_D + 0.05 + PuebloMarket.AWNING_OUT + 0.15
	_t._check(ring_x - awning > 0.6 and PuebloLane.LANE_HALF - 1.5 - ring_x > 0.4,
		"the lane's walkers pass between the awnings and the adobe's posts")
	# The plaza ring clear of the trees and the kiosk's steps.
	var pr := PuebloLane.PLAZA_HALF - 3.0 - 5.0
	_t._check(pr - PuebloLane.TREE_RING > 3.0 and PuebloLane.TREE_RING - 1.8 > PuebloLane.KIOSK_R + 2.2,
		"the plaza's walkers ring the trees, the trees ring the kiosk")
	var segs_ok := true
	var adobes := 0
	for seg: Array in L.segs:
		if float(seg[1]) - float(seg[0]) < 4.0:
			segs_ok = false
		if int(seg[2]) == PuebloLane.Kind.ADOBE:
			adobes += 1
	_t._check(segs_ok and adobes == 1 and L.segs.size() >= 10, "the lane is lined by %d buildings, one of them the adobe" % L.segs.size())


func _build(t: Node, plan: CityPlan, lm: Dictionary, info: Dictionary, L: Dictionary) -> void:
	var tree := t.get_tree()
	for detailed in [true, false]:
		var root := Node3D.new()
		tree.root.add_child(root)
		var body := StaticBody3D.new()
		root.add_child(body)
		var zones0 := tree.get_nodes_in_group(Sanctuary.ZONE_GROUP).size()
		Landmarks.build(lm, root, body if detailed else null, plan, detailed)
		await tree.process_frame
		var pivot := root.get_node_or_null("Civic_" + PuebloLane.ID) as Node3D
		_t._check(pivot != null, "the marketplace lane builds (%s)" % ("near" if detailed else "far"))
		if pivot == null:
			root.queue_free()
			return
		var tris: Dictionary = pivot.get_meta("pueblo_tris", {})
		var zones := tree.get_nodes_in_group(Sanctuary.ZONE_GROUP).size() - zones0
		if detailed:
			_t._check(int(tris.get("geo", 0)) > 5000 and int(tris.geo) < GEO_BUDGET and int(tris.market) > 20000 and int(tris.market) < MARKET_BUDGET
				and int(tris.paper) > 3000 and int(tris.paper) < PAPER_BUDGET,
				"the near marketplace lane is detailed and under budget (%s)" % [tris])
			var shapes := 0
			var civic := pivot.get_node_or_null("CivicBody")
			for c in (civic.get_children() if civic else []):
				if c is CollisionShape3D:
					shapes += 1
			_t._check(shapes > 100, "the marketplace lane has collision (%d shapes)" % shapes)
			var church := pivot.get_node_or_null("ChurchBody") as StaticBody3D
			_t._check(church != null and church.is_in_group(Sanctuary.BODY_GROUP) and church.get_child_count() > 4, "the church's body is a sanctuary's")
			var cr: Rect2 = L.church
			var inside := CivicSites.to_world(info, cr.get_center())
			var lane: Rect2 = L.lane
			var outside := CivicSites.to_world(info, lane.get_center())
			var y: float = info.y0
			_t._check(zones == 1 and Sanctuary.contains(tree, Vector3(inside.x, y + 3.0, inside.y)) and Sanctuary.contains(tree, Vector3(inside.x, y + 15.0, inside.y))
				and not Sanctuary.contains(tree, Vector3(outside.x, y + 1.5, outside.y)),
				"the church is a sanctuary: its zone holds the nave and the bell gable, not the lane")
			_t._check(int(pivot.get_meta("pergola_cards", 0)) > 2000 and pivot.get_node_or_null("PergolaVinesShadow") != null,
				"the pergola is grown over with vines and throws their shade (%d cards)" % int(pivot.get_meta("pergola_cards", 0)))
		else:
			_t._check(int(tris.get("geo", 0)) > 500 and int(tris.geo) < FAR_BUDGET and int(tris.market) < 4000 and int(tris.paper) == 0,
				"the far marketplace lane is cheap (%s)" % [tris])
			_t._check(zones == 1, "the far copy keeps the church's sanctuary zone")
		root.queue_free()
		await tree.process_frame
	# The vendors and their queues (built into a stand-in chunk: the steps are counted, not run).
	var stand := CityChunk.new()
	stand.plan = plan
	var idx := plan.block_index_at(lm.anchor)
	stand.ix = idx.x
	stand.iz = idx.y
	var steps := PuebloLane.people_steps(lm, stand)
	var queue: Array = stand.get_meta("vendor_queue", [])
	_t._check(steps.size() >= 12 and queue.size() == L.stalls.size() * 2, "%d stall vendors and %d queue spots" % [steps.size(), queue.size()])
	stand.free()
