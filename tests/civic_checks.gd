extends RefCounted
## Checks for the downtown civic landmarks (the arena district and the civic centre), run from
## tests/smoke_test.gd near the end of the city test. Loaded at run time so it compiles after the
## autoloads and can name the landmark classes freely. Kept fast: nothing here streams the city.
## Every landmark is built detailed into a holder at its true position with a body of its own,
## and checked by maths and by rays against that body, then freed.

const IDS := ["arena", "live_plaza", "live_hotel", "convention_center", "ziggurat_hall", "civic_park", "concert_hall", "lattice_museum", "pueblo_station"]

var _t: Node


func run(t: Node, city: Node3D) -> void:
	_t = t
	var plan: CityPlan = city.get("plan")
	if plan == null or plan.macro == null:
		return
	var ws := t.get_tree().root.get_node("/root/WorldState")
	var off: Vector3 = ws.get("world_offset")
	var entries := {}
	for lm in Landmarks.all():
		if IDS.has(lm.id):
			entries[lm.id] = lm
	t._check(entries.size() == IDS.size(), "every civic landmark is listed (%d of %d)" % [entries.size(), IDS.size()])
	var claims := ""
	var freeway := ""
	var far := ""
	for id: String in entries:
		var lm: Dictionary = entries[id]
		var idx := plan.block_index_at(lm.anchor)
		var b := plan.block(idx.x, idx.y)
		if lm.get("site", "") != "block" or not plan.lots(idx.x, idx.y).is_empty() or b.kind != CityPlan.BlockKind.BUILDINGS:
			claims += " " + id
		# No freeway deck crosses a site: city hall used to stand under the 110.
		var site := Landmarks.site_rect(plan, lm.anchor)
		for i in 7:
			for j in 7:
				var p := site.position + site.size * Vector2((float(i) + 0.5) / 7.0, (float(j) + 0.5) / 7.0)
				if plan.macro.freeway.blocks(p, 0.0) and not freeway.contains(id):
					freeway += " " + id
		if not city.has_node("FarLandmark_" + id):
			far += " " + id
	t._check(claims == "", "each civic landmark has its block to itself: no lots, no park or plaza roll%s" % claims)
	t._check(freeway == "", "no freeway deck crosses a civic landmark's site%s" % freeway)
	t._check(far == "", "every civic landmark has a far version%s" % far)

	# Build each one detailed at its true place, with a body of its own, and look at what it made.
	var outside := ""
	var solid := ""
	var crowd_bad := ""
	var holders: Array[Node3D] = []
	for id: String in entries:
		var lm: Dictionary = entries[id]
		var holder := Node3D.new()
		holder.name = "CivicCheck_" + id
		holder.position = -off
		city.add_child(holder)
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		holder.add_child(body)
		Landmarks.build(lm, holder, body, plan, true)
		holders.append(holder)
		# Everything it drew stays inside its block, off the roads - a couple of metres of
		# overhang allowed (the arena's drum, the concert hall's sails).
		var idx := plan.block_index_at(lm.anchor)
		var block_rect: Rect2 = plan.block(idx.x, idx.y).rect
		var bounds := Rect2()
		var first := true
		for mi in holder.find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			if m.mesh == null:
				continue
			var ab := m.global_transform * m.mesh.get_aabb()
			var r := Rect2(Vector2(ab.position.x, ab.position.z) + Vector2(off.x, off.z), Vector2(ab.size.x, ab.size.z))
			bounds = r if first else bounds.merge(r)
			first = false
		if first or not block_rect.grow(3.0).encloses(bounds):
			outside += " %s%s" % [id, "" if first else str(bounds)]
		if body.get_child_count() == 0:
			solid += " " + id
	t._check(outside == "", "every civic landmark stays inside its own block, off the roads%s" % outside)
	t._check(solid == "", "every civic landmark has collision%s" % solid)
	for i in 3:
		await t.get_tree().physics_frame
	var space := city.get_world_3d().direct_space_state
	# Rays from the sky onto the roofs you can land on.
	var land := ""
	for probe: Array in _roofs(plan, entries):
		var id: String = probe[0]
		var at: Vector2 = probe[1]
		var above: float = probe[2]
		var q := PhysicsRayQueryParameters3D.create(Vector3(at.x, 400.0, at.y) - off, Vector3(at.x, -5.0, at.y) - off, 1)
		var hit := space.intersect_ray(q)
		var y: float = (hit.position.y + off.y) if not hit.is_empty() else -1.0
		if hit.is_empty() or y < above:
			land += " %s(%.1f m, wanted over %.1f)" % [id, y, above]
	t._check(land == "", "the roofs of the arena, city hall, the hotel and the station are solid%s" % land)
	# The crowds a landmark spawns wander rects that are inside its site and clear of its walls.
	for id: String in entries:
		var lm: Dictionary = entries[id]
		var site := Landmarks.site_rect(plan, lm.anchor)
		for crowd: Array in Landmarks.crowds(lm, plan):
			var rect: Rect2 = crowd[0]
			if not site.grow(0.5).encloses(rect):
				crowd_bad += " %s(outside)" % id
				continue
			for i in 4:
				for j in 4:
					var p := rect.position + rect.size * Vector2((float(i) + 0.5) / 4.0, (float(j) + 0.5) / 4.0)
					var pq := PhysicsPointQueryParameters3D.new()
					pq.position = Vector3(p.x, LandmarkArenaDistrict.ground(plan, site) + 1.0, p.y) - off
					pq.collision_mask = 1
					var inside := space.intersect_point(pq, 4)
					for h in inside:
						if (h.collider as Node).get_parent() in holders and not crowd_bad.contains(id):
							crowd_bad += " %s(walks into a wall at %s)" % [id, str(p)]
	t._check(crowd_bad == "", "every civic crowd walks open ground inside its site%s" % crowd_bad)
	for h in holders:
		h.queue_free()
	await t.get_tree().process_frame


## [id, world xz, lowest acceptable hit height] for the roofs worth landing on.
func _roofs(plan: CityPlan, entries: Dictionary) -> Array:
	var out := []
	var s := Landmarks.site_rect(plan, entries.arena.anchor)
	var y0 := LandmarkArenaDistrict.ground(plan, s)
	out.append(["arena", LandmarkArenaDistrict._arena_centre(s), y0 + LandmarkArenaDistrict.DRUM_TOP])
	var hall := Landmarks.site_rect(plan, entries.ziggurat_hall.anchor)
	out.append(["ziggurat_hall", hall.get_center() + Vector2(0.0, 6.0), y0 + 110.0])
	var hotel := Landmarks.site_rect(plan, entries.live_hotel.anchor)
	out.append(["live_hotel", hotel.get_center() + Vector2(-4.0, -2.0), y0 + 150.0])
	var station := Landmarks.site_rect(plan, entries.pueblo_station.anchor)
	out.append(["pueblo_station", station.position + Vector2(LandmarkCivicCenter._station_court(station) + 15.0, 12.0), y0 + 10.0])
	var concert := Landmarks.site_rect(plan, entries.concert_hall.anchor)
	out.append(["concert_hall", concert.get_center() + Vector2(4.0, -4.0), y0 + 12.0])
	return out
