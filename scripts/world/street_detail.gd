class_name StreetDetail
extends RefCounted
## The small stuff that makes a street read as a street: gutters and storm drains, stop lines
## and lane arrows, parking stripes, asphalt patches, named street signs, utility poles with
## sagging cables, bus shelters, tree grates, bike racks, news boxes, mailboxes, bollards.
## Everything is seeded from the block or intersection and goes through the chunk's batch, so it
## follows the city relief like every other prop. Static: call with the chunk.

const NEWS_COLORS := [Color(0.85, 0.15, 0.15), Color(0.15, 0.3, 0.7), Color(0.95, 0.75, 0.1), Color(0.2, 0.2, 0.22)]


## Sidewalk-ring details for one block. `edges` are [a, b, inward] like the chunk's props.
static func build_block(chunk: CityChunk, rect: Rect2, edges: Array, params: Dictionary, district: int, rng: RandomNumberGenerator) -> void:
	var batch: MultiMeshBatch = chunk._batch
	var top: float = CityChunk.SIDEWALK_TOP
	var road_top: float = CityChunk.ROAD_TOP
	# Gutters: a dark strip on the asphalt along every curb, and a drain grate near each corner.
	for e in edges:
		var a: Vector2 = e[0]
		var b: Vector2 = e[1]
		var inward: Vector2 = e[2]
		var length := a.distance_to(b)
		var dir := (b - a) / length
		var yaw := atan2(-dir.x, -dir.y)
		var t := 2.0
		while t < length - 2.0:
			var piece := minf(4.0, length - 2.0 - t)
			var p := a + dir * (t + piece * 0.5) - inward * 0.3
			batch.add("gutter", PropFactory.gutter(), Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(1.0, 1.0, piece / 4.0)), Vector3(p.x, road_top + 0.004, p.y)))
			t += piece
		for k in 2:
			var gp := a + dir * (4.0 if k == 0 else length - 4.0) - inward * 0.55
			batch.add("grate", PropFactory.grate(), Transform3D(Basis(Vector3.UP, yaw), Vector3(gp.x, road_top + 0.006, gp.y)))
	# Asphalt patches on this block's two roads.
	var plan: CityPlan = chunk.plan
	var roads := [
		[Vector2(plan.road_pos(CityPlan.AXIS_X, chunk.ix + 1), rect.get_center().y), Vector2(plan.road_width(CityPlan.AXIS_X, chunk.ix + 1), rect.size.y)],
		[Vector2(rect.get_center().x, plan.road_pos(CityPlan.AXIS_Z, chunk.iz + 1)), Vector2(rect.size.x, plan.road_width(CityPlan.AXIS_Z, chunk.iz + 1))],
	]
	for road in roads:
		var c: Vector2 = road[0]
		var s: Vector2 = road[1]
		for i in rng.randi_range(1, 4):
			var w := rng.randf_range(1.5, 4.0)
			var d := rng.randf_range(2.0, 6.0)
			var p := Vector2(rng.randf_range(c.x - s.x * 0.5 + 2.0, c.x + s.x * 0.5 - 2.0), rng.randf_range(c.y - s.y * 0.5 + 3.0, c.y + s.y * 0.5 - 3.0))
			var shade := 0.55 + rng.randf() * 0.7
			batch.add("patch", PropFactory.patch(), Transform3D(Basis(Vector3.UP, rng.randf_range(-0.1, 0.1)).scaled(Vector3(w, 1.0, d)), Vector3(p.x, road_top + 0.003, p.y)), Color(shade, shade, shade))
	# Utility poles and cables along one edge (suburbs and industrial), tree-free side.
	if district == CityPlan.District.SUBURBS or district == CityPlan.District.INDUSTRIAL:
		var e: Array = edges[rng.randi() % 4]
		var a: Vector2 = e[0]
		var b: Vector2 = e[1]
		var inward: Vector2 = e[2]
		var length := a.distance_to(b)
		var dir := (b - a) / length
		var yaw := atan2(-dir.x, -dir.y)
		var spacing := 28.0
		var poles: Array[Vector3] = []
		var t := 6.0
		while t < length - 4.0:
			var p := a + dir * t + inward * 0.7
			var g := chunk._gy(p.x, p.y)
			poles.append(Vector3(p.x, top + g, p.y))
			batch.add("upole", PropFactory.upole(), Transform3D(Basis(Vector3.UP, yaw), Vector3(p.x, top, p.y)))
			batch.add("crossarm", PropFactory.crossarm(), Transform3D(Basis(Vector3.UP, yaw), Vector3(p.x, top + 8.2, p.y)))
			t += spacing
		for i in poles.size() - 1:
			for k in 3:
				var side := (k - 1) * 0.7
				var offset := Vector3(-dir.y, 0.0, dir.x) * side
				_cable(batch, poles[i] + Vector3(0.0, 8.25, 0.0) + offset, poles[i + 1] + Vector3(0.0, 8.25, 0.0) + offset, 0.9)
	# Sidewalk furniture by district.
	var corner_count := 0
	var rack_odds := 0.6 if district == CityPlan.District.DOWNTOWN or district == CityPlan.District.CAMPUS else 0.25
	var news_odds := 0.7 if district == CityPlan.District.DOWNTOWN else 0.3
	var mail_odds := 0.5 if district == CityPlan.District.SUBURBS or district == CityPlan.District.MIDTOWN else 0.15
	for e in edges:
		var a: Vector2 = e[0]
		var b: Vector2 = e[1]
		var inward: Vector2 = e[2]
		var length := a.distance_to(b)
		var dir := (b - a) / length
		var yaw := atan2(-inward.x, -inward.y)
		if rng.randf() < rack_odds:
			var p := a + dir * rng.randf_range(8.0, length - 8.0) + inward * 1.2
			var basis := Basis(Vector3.UP, yaw)
			for k in 3:
				var q := p + dir * (k - 1) * 0.8
				chunk._add_prop("rack", Vector3(q.x, top, q.y), Color(0.3, 0.3, 0.32), [
					["rack", PropFactory.bike_rack(), Transform3D(basis, Vector3(q.x, top, q.y))],
				], [[Vector3(0.9, 0.9, 0.1), Vector3(q.x, top + 0.45, q.y), yaw]])
		if rng.randf() < news_odds:
			var p := a + dir * rng.randf_range(5.0, 12.0) + inward * 1.0
			for k in rng.randi_range(1, 3):
				var q := p + dir * k * 0.55
				var color: Color = NEWS_COLORS[rng.randi() % NEWS_COLORS.size()]
				chunk._add_prop("newsbox", Vector3(q.x, top, q.y), color, [
					["newsbox", PropFactory.news_box(), Transform3D(Basis(Vector3.UP, yaw), Vector3(q.x, top + 0.55, q.y)), color],
				], [[Vector3(0.5, 1.1, 0.5), Vector3(q.x, top + 0.55, q.y), yaw]])
		if rng.randf() < mail_odds:
			var p := a + dir * rng.randf_range(10.0, length - 10.0) + inward * 1.1
			chunk._add_prop("mailbox", Vector3(p.x, top, p.y), Color(0.15, 0.3, 0.25), [
				["mailbox", PropFactory.mailbox(), Transform3D(Basis(Vector3.UP, yaw), Vector3(p.x, top, p.y))],
			], [[Vector3(0.6, 1.3, 0.5), Vector3(p.x, top + 0.65, p.y), yaw]])
		corner_count += 1
	# Bus shelter on an avenue side (one per block at most).
	var wx := plan.road_width(CityPlan.AXIS_X, chunk.ix + 1)
	var wz := plan.road_width(CityPlan.AXIS_Z, chunk.iz + 1)
	var avenue_edges: Array = []
	if wx > plan.street_width + 1.0:
		avenue_edges.append(edges[3])
	if wz > plan.street_width + 1.0:
		avenue_edges.append(edges[1])
	if not avenue_edges.is_empty() and rng.randf() < 0.45:
		var e: Array = avenue_edges[rng.randi() % avenue_edges.size()]
		var a: Vector2 = e[0]
		var b: Vector2 = e[1]
		var inward: Vector2 = e[2]
		var dir := (b - a).normalized()
		var p := a + dir * rng.randf_range(12.0, a.distance_to(b) - 12.0) + inward * 2.0
		_bus_shelter(chunk, p, inward, dir)


## Intersection details: stop lines, lane arrows, street name signs, bollards downtown.
static func build_intersection(chunk: CityChunk, pos: Vector2, size: Vector2, kind: int, rng: RandomNumberGenerator) -> void:
	var batch: MultiMeshBatch = chunk._batch
	var plan: CityPlan = chunk.plan
	var road_top: float = CityChunk.ROAD_TOP
	var top: float = CityChunk.SIDEWALK_TOP
	# Four approaches: right-hand traffic, so the stop line spans the half of the road that
	# carries traffic toward the intersection.
	var approaches := [
		[Vector2(0.0, 1.0), size.y, size.x],   # from +Z (south), road along Z, width size.x
		[Vector2(0.0, -1.0), size.y, size.x],
		[Vector2(1.0, 0.0), size.x, size.y],
		[Vector2(-1.0, 0.0), size.x, size.y],
	]
	for ap in approaches:
		var d: Vector2 = ap[0]                 # direction from the center to the approach
		var along_w: float = ap[1]             # width of the crossing road (how far the approach starts)
		var road_w: float = ap[2]              # width of the approach road
		var half_w := road_w * 0.5
		var perp := Vector2(-d.y, d.x)
		# Right-hand traffic: cars arriving along -d keep to their right, which is -perp here
		# (matches TrafficManager._lane_offset for every approach).
		var inbound_side := -1.0
		var lane_c: Vector2 = pos + d * (along_w * 0.5 + 3.3) + perp * inbound_side * half_w * 0.5
		var yaw := atan2(-d.x, -d.y)
		if kind != CityPlan.Intersection.PLAIN:
			batch.add("stop_line", PropFactory.stop_line(), Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(half_w - 1.0, 1.0, 1.0)), Vector3(lane_c.x, road_top + 0.016, lane_c.y)))
		# Lane arrows on avenues (two lanes: straight in the outer, left turn in the inner).
		if road_w > plan.street_width + 1.0:
			var lanes := 2
			var lane_w := half_w / lanes
			for l in lanes:
				var lc: Vector2 = pos + d * (along_w * 0.5 + 9.0) + perp * inbound_side * (lane_w * (l + 0.5))
				var mesh := PropFactory.arrow_left() if l == lanes - 1 else PropFactory.arrow_straight()
				var flip := Basis(Vector3.UP, yaw + PI)
				# The left-turn arrow bends to mesh -X; mirror it when that lands on the driver's right.
				var turned_left := flip * Vector3(-1.0, 0.0, 0.0)
				var want_left := Vector3.UP.cross(Vector3(-d.x, 0.0, -d.y))
				if l == lanes - 1 and turned_left.dot(want_left) < 0.0:
					flip = flip.scaled(Vector3(-1.0, 1.0, 1.0))
				batch.add("arrow_left" if l == lanes - 1 else "arrow_straight", mesh, Transform3D(flip, Vector3(lc.x, road_top + 0.016, lc.y)))
	# Street name sign on the +X +Z corner.
	var corner := pos + Vector2(size.x * 0.5 + 1.4, size.y * 0.5 + 1.4)
	var at := Vector3(corner.x, top, corner.y)
	var name_x := plan.road_name(CityPlan.AXIS_X, chunk.ix + 1)
	var name_z := plan.road_name(CityPlan.AXIS_Z, chunk.iz + 1)
	var instances := [
		["sign_post", PropFactory.sign_post(), Transform3D(Basis(), at + Vector3(0.0, 1.4, 0.0))],
		["sign_plate", PropFactory.sign_plate(), Transform3D(Basis(Vector3.UP, PI * 0.5), at + Vector3(0.0, 2.6, 0.0)), Color(0.1, 0.4, 0.2)],
		["sign_plate", PropFactory.sign_plate(), Transform3D(Basis(), at + Vector3(0.0, 2.32, 0.0)), Color(0.1, 0.4, 0.2)],
		["text_" + name_x, PropFactory.text_mesh(name_x), Transform3D(Basis(Vector3.UP, PI * 0.5), at + Vector3(0.03, 2.6, 0.0)), Color.WHITE],
		["text_" + name_x, PropFactory.text_mesh(name_x), Transform3D(Basis(Vector3.UP, -PI * 0.5), at + Vector3(-0.03, 2.6, 0.0)), Color.WHITE],
		["text_" + name_z, PropFactory.text_mesh(name_z), Transform3D(Basis(), at + Vector3(0.0, 2.32, 0.03)), Color.WHITE],
		["text_" + name_z, PropFactory.text_mesh(name_z), Transform3D(Basis(Vector3.UP, PI), at + Vector3(0.0, 2.32, -0.03)), Color.WHITE],
	]
	chunk._add_prop("street_sign", at, Color(0.3, 0.3, 0.32), instances, [[Vector3(0.2, 2.8, 0.2), at + Vector3(0.0, 1.4, 0.0), 0.0]])
	# Bollards on downtown corners.
	if chunk.plan.district_at(pos) == CityPlan.District.DOWNTOWN and rng.randf() < 0.6:
		for c: Vector2 in [Vector2(1, 1), Vector2(-1, 1), Vector2(-1, -1), Vector2(1, -1)]:
			var cc := pos + Vector2(c.x * (size.x * 0.5 + 0.6), c.y * (size.y * 0.5 + 0.6))
			for k in 3:
				var q := cc + Vector2(c.x * k * 1.1, 0.0) if k < 2 else cc + Vector2(0.0, c.y * 1.1)
				chunk._add_prop("bollard", Vector3(q.x, top, q.y), Color(0.25, 0.25, 0.27), [
					["bollard", PropFactory.bollard(), Transform3D(Basis(), Vector3(q.x, top + 0.45, q.y))],
				], [[Vector3(0.3, 0.9, 0.3), Vector3(q.x, top + 0.45, q.y), 0.0]])


## Two cable pieces from a to b with `sag` meters of droop in the middle.
static func _cable(batch: MultiMeshBatch, a: Vector3, b: Vector3, sag: float) -> void:
	var mid := (a + b) * 0.5 - Vector3(0.0, sag, 0.0)
	for seg in [[a, mid], [mid, b]]:
		var p0: Vector3 = seg[0]
		var p1: Vector3 = seg[1]
		var length := p0.distance_to(p1)
		var basis := Basis.looking_at(p1 - p0, Vector3.UP).scaled(Vector3(1.0, 1.0, length))
		var center := (p0 + p1) * 0.5
		# The batch adds the relief; cables hang from poles that already include it, so remove it.
		batch.add("cable", PropFactory.cable(), Transform3D(basis, Vector3(center.x, center.y - (batch.ground.call(center.x, center.z) if batch.ground.is_valid() else 0.0), center.z)))


static func _bus_shelter(chunk: CityChunk, p: Vector2, inward: Vector2, dir: Vector2) -> void:
	var top: float = CityChunk.SIDEWALK_TOP
	var yaw := atan2(-inward.x, -inward.y)      # faces the road
	var basis := Basis(Vector3.UP, yaw + PI)
	var at := Vector3(p.x, top, p.y)
	var back := Vector3(inward.x, 0.0, inward.y) * 0.9
	var along := Vector3(dir.x, 0.0, dir.y)
	var instances := [
		["shelter_post", PropFactory.shelter_post(), Transform3D(basis, at + back + along * 1.8 + Vector3(0.0, 1.25, 0.0))],
		["shelter_post", PropFactory.shelter_post(), Transform3D(basis, at + back - along * 1.8 + Vector3(0.0, 1.25, 0.0))],
		["shelter_roof", PropFactory.shelter_roof(), Transform3D(basis, at + back * 0.4 + Vector3(0.0, 2.55, 0.0))],
		["shelter_glass", PropFactory.shelter_glass(), Transform3D(basis, at + back + Vector3(0.0, 1.3, 0.0))],
		["bench", PropFactory.model_bench(), Transform3D(Basis(Vector3.UP, yaw), at + back * 0.55)],
		["sign_post", PropFactory.sign_post(), Transform3D(Basis(), at + along * 2.6 + Vector3(0.0, 1.4, 0.0))],
		["bus_sign", PropFactory.bus_sign(), Transform3D(basis, at + along * 2.6 + Vector3(0.0, 2.7, 0.0))],
	]
	chunk._add_prop("bus_stop", at, Color(0.3, 0.3, 0.32), instances, [[Vector3(4.2, 2.6, 1.0), at + back + Vector3(0.0, 1.3, 0.0), yaw]])
