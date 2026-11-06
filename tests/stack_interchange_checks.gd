extends RefCounted
## The four-level stack (FreewayStack, StackBuild, StackTraffic) for tests/smoke_test.gd. Loaded at
## run time, so it compiles after the autoloads. Checks: the stack is planned on this seed and on
## another; the 110 is level 1 and the 101 level 4 at the crossing, three separations apart;
## every pair of decks that overlaps in plan is a deck separation apart and no connector is too
## steep (FreewayStack.verify_all()); each connector meets its parent and its target at their
## height, is banked into its left turn and never near the street; no off-ramp in the stack;
## the connectors come out of segments_in() and blocks(); every column stands clear of the decks
## below it and no connector is left without one for long; a chunk on the stack builds the
## connectors into its four freeway meshes with collision, at FULL and at LOD; and a connector
## car drives the deck and is handed to the freeway traffic at the end, and a freeway car at a
## diverge is taken onto the connector.

var _t: Node


func run(t: Node, city: Node3D) -> void:
	_t = t
	var plan: CityPlan = city.plan
	var fw: Freeway = plan.macro.freeway if plan.macro else null
	var st: FreewayStack = fw.stack if fw else null
	_t._check(st != null and st.links.size() == 4, "the four-level stack is planned with four connectors")
	if st == null or st.links.size() != 4:
		return
	_plan(plan, fw, st)
	_other_seed()
	_chunks(city, plan, fw, st)
	await _traffic(city, plan, fw, st)


func _mains(fw: Freeway, st: FreewayStack) -> Dictionary:
	var out := {}
	for ri: int in [st.low, st.high]:
		out[ri] = [fw.routes[ri].points, fw.routes[ri].heights, FreewayStack._runs(fw.routes[ri].points), float(fw.routes[ri].width)]
	return out


func _plan(plan: CityPlan, fw: Freeway, st: FreewayStack) -> void:
	_t._check(fw.routes[st.low].name.contains("110") and fw.routes[st.high].name.contains("101"),
		"the stack is the 110 under the 101")
	_t._check(st.centre.distance_to(DowntownReal.point("four_level_interchange")) < 120.0,
		"the stack stands at the real four-level interchange (%.0f m off)" % st.centre.distance_to(DowntownReal.point("four_level_interchange")))
	var mains := _mains(fw, st)
	var hl: float = FreewayStack.line_nearest(mains[st.low][0], mains[st.low][1], mains[st.low][2], st.centre)[2]
	var hh: float = FreewayStack.line_nearest(mains[st.high][0], mains[st.high][1], mains[st.high][2], st.centre)[2]
	_t._check(hh - hl >= 3.0 * Freeway.DECK_SEPARATION - 0.01, "the 101 crosses %.1f m over the 110 (three deck separations)" % (hh - hl))
	var bad := st.verify_all(mains, st.links)
	_t._check(bad.is_empty(), "every overlapping deck pair is a deck apart, no connector too steep %s" % [bad.slice(0, 3)])
	var ends_ok := true
	var bank_ok := true
	var ground_ok := true
	var levels := {}
	for l in st.links:
		var hs: PackedFloat32Array = l.heights
		var pt: PackedFloat32Array = l.pt
		var h0: float = FreewayStack.line_at(mains[l.from][0], mains[l.from][1], mains[l.from][2], pt[0])[2]
		var h1: float = FreewayStack.line_at(mains[l.to][0], mains[l.to][1], mains[l.to][2], pt[pt.size() - 1])[2]
		if absf(hs[0] - h0) > 0.1 or absf(hs[hs.size() - 1] - h1) > 0.1:
			ends_ok = false
		var bank: PackedFloat32Array = l.bank
		var mid := bank[bank.size() / 2]
		for e in bank:
			if absf(e) > FreewayStack.BANK_MAX + 0.001:
				bank_ok = false
		if mid < 0.02 or absf(bank[0]) > 0.001 or absf(bank[bank.size() - 1]) > 0.001:
			bank_ok = false
		var pts: PackedVector2Array = l.points
		for i in pts.size():
			if hs[i] - plan.height_at(pts[i]) < Freeway.MIN_CLEARANCE + FreewayStack.GIRDER - 0.05:
				ground_ok = false
		levels[int(l.level)] = int(levels.get(int(l.level), 0)) + 1
	_t._check(ends_ok, "every connector meets its parent and its target at their deck height")
	_t._check(bank_ok, "every connector is banked into its left turn, level at its ends, within %.0f %%" % (FreewayStack.BANK_MAX * 100.0))
	_t._check(ground_ok, "no connector comes down near the street")
	_t._check(levels.get(1, 0) == 2 and levels.get(2, 0) == 2, "two connectors on level 2 and two on level 3 (%s)" % [levels])
	var near_ramps := 0
	for r in fw.ramps:
		if (r.pos as Vector2).distance_to(st.centre) < FreewayStack.KEEP - 60.0:
			near_ramps += 1
	_t._check(near_ramps == 0, "no off-ramp peels off inside the stack")
	var segs := fw.segments_in(Rect2(st.centre - Vector2.ONE * 300.0, Vector2.ONE * 600.0))
	var link_segs := 0
	for s in segs:
		if s.has("link"):
			link_segs += 1
	var l0: Dictionary = st.links[0]
	var mid_pt: Vector2 = (l0.points as PackedVector2Array)[(l0.points as PackedVector2Array).size() / 2]
	_t._check(link_segs > 40 and fw.blocks(mid_pt, 0.0), "the connectors come out of segments_in() (%d) and blocks()" % link_segs)
	var cols := st.columns(plan)
	var clear := true
	for c in cols:
		if st.decks_below(c.pos, float(c.top) + 0.4, float(c.r) - 0.2):
			clear = false
	var gaps_ok := true
	for k in st.links.size():
		var ss: Array[float] = []
		for c in cols:
			if int(c.link) == k:
				ss.append(FreewayStack.line_nearest(st.links[k].points, st.links[k].heights, st.links[k].run, c.pos)[0])
		ss.sort()
		ss.push_front(0.0)
		ss.append(float(st.links[k].length))
		for i in ss.size() - 1:
			if ss[i + 1] - ss[i] > FreewayStack.COLUMN_SPACING * 3.0 + 1.0:
				gaps_ok = false
	_t._check(cols.size() > 30 and clear, "every column (%d) stands clear of the decks below it" % cols.size())
	_t._check(gaps_ok, "no connector spans more than three column spacings")


func _other_seed() -> void:
	var macro := MacroMap.new()
	macro.seed = 4242
	macro.setup()
	var fw: Freeway = macro.freeway
	var ok: bool = fw.stack != null and fw.stack.links.size() == 4 and fw.stack.verify_all(_mains(fw, fw.stack), fw.stack.links).is_empty()
	_t._check(ok, "the stack plans soundly on another seed")


func _chunks(city: Node3D, plan: CityPlan, fw: Freeway, st: FreewayStack) -> void:
	var c := st.centre
	for level in [CityChunk.Level.FULL, CityChunk.Level.LOD]:
		var key := plan.block_index_at(c)
		var chunk: CityChunk = city._new_chunk(key, level)
		chunk.build()
		var ok := chunk.has_node("FreewayDeck") and chunk.has_node("FreewayStructure") and chunk.has_node("FreewayBody")
		var kit := FreewayKit.new(chunk)
		var body := StaticBody3D.new()
		var built := StackBuild.build(chunk, kit, body)
		var arr := kit.body.commit_to_arrays()
		var kinds := {}
		if arr.size() > 0 and arr[Mesh.ARRAY_COLOR] != null:
			for col: Color in arr[Mesh.ARRAY_COLOR]:
				var kd := int(round(col.a * FreewayKit.KIND_SCALE))
				kinds[kd] = int(kinds.get(kd, 0)) + 1
		_t._check(ok and built > 0 and body.get_child_count() > 0 and kinds.get(FreewayKit.S_PILLAR, 0) > 0 and kinds.get(FreewayKit.S_BARRIER, 0) > 0,
			"a %s chunk at the stack builds the connectors into its freeway meshes with collision (%d pieces)" % ["FULL" if level == CityChunk.Level.FULL else "LOD", built])
		body.free()
		chunk.free()


func _traffic(city: Node3D, plan: CityPlan, fw: Freeway, st: FreewayStack) -> void:
	var stt = city.get_node_or_null("StackTraffic")
	var tm = city.get_node_or_null("Traffic")
	_t._check(stt != null and tm != null, "the stack has its own traffic beside the freeway's")
	if stt == null or tm == null:
		return
	var l: Dictionary = st.links[0]
	stt._built_frame = -1
	stt._spawn(st, 0, 20.0, 0, NAN)
	var car = null
	for c in stt.cars:
		if int(c.traffic.link) == 0 and absf(float(c.traffic.s) - 20.0) < 0.5:
			car = c
	_t._check(car != null, "a connector car can be put on a connector")
	if car == null:
		return
	var on_deck := true
	var steps := 0
	while is_instance_valid(car) and car.get_parent() == stt and steps < 4000:
		stt._drive(st, 0.1)
		steps += 1
		if car.get_parent() == stt and steps % 25 == 0:
			var p := WorldState.to_world(car.global_position)
			var s: float = car.traffic.s
			var deck: Vector3 = StackTraffic.frame_at(l, s)[0]
			if absf(p.y - car.road_lift() - deck.y) > 1.5 or Vector2(p.x, p.z).distance_to(Vector2(deck.x, deck.z)) > 12.0:
				on_deck = false
	_t._check(on_deck, "a connector car rides on its deck")
	_t._check(is_instance_valid(car) and car.get_parent() == tm and tm.freeway_cars.has(car) and int(car.traffic.fw) == int(l.to)
		and int(car.traffic.dir) == int(l.to_sign), "at the end it is handed to the freeway traffic on the target, in its direction")
	# A freeway car nearing a diverge is taken onto the connector.
	var t0: float = (l.pt as PackedFloat32Array)[0]
	var sg: int = l.from_sign
	var main = tm.place_freeway_car(int(l.from), t0 - 6.0 * sg, sg)
	stt.take_share = 1.0
	for c in stt.cars.duplicate():
		if int(c.traffic.link) == 0:
			stt.cars.erase(c)
			stt._retire(c)
	var took: bool = stt._take_from_main(st, tm, 0)
	_t._check(took and main.get_parent() == stt and not tm.freeway_cars.has(main), "a freeway car at the diverge turns onto the connector")
	stt.take_share = 0.45
	await _t.get_tree().process_frame
