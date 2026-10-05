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
	# The one table: every landmark in it, quarter-turn yaws, a real position for each, and the
	# real layout's arrangement (the arena south-west of the concert hall by about 2 km, the
	# station east of city hall) - so a 1:1 re-layout starts from sane numbers.
	var table := ""
	for id: String in IDS:
		var row: Dictionary = CivicSites.SITES.get(id, {})
		if row.is_empty() or int(row.yaw) % 90 != 0 or (row.footprint as Vector2).x <= 0.0 or not row.has("latlon"):
			table += " " + id
	var arena_real := CivicSites.real_metres("arena")
	var hall_real := CivicSites.real_metres("ziggurat_hall")
	var station_real := CivicSites.real_metres("pueblo_station")
	if not (arena_real.x < hall_real.x and arena_real.y > hall_real.y and station_real.x > hall_real.x and arena_real.distance_to(hall_real) > 1500.0):
		table += " real-layout(arena %s, hall %s, station %s)" % [arena_real, hall_real, station_real]
	t._check(table == "", "the civic table has a turn, a footprint and a real position for every landmark%s" % table)
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
		if holder.find_children("*", "CollisionShape3D", true, false).is_empty():
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
					pq.position = Vector3(p.x, float(CivicSites.site(plan, id).y0) + 1.0, p.y) - off
					pq.collision_mask = 1
					var inside := space.intersect_point(pq, 4)
					for h in inside:
						var ours := false
						for hd in holders:
							if hd.is_ancestor_of(h.collider as Node):
								ours = true
						if ours and not crowd_bad.contains(id):
							crowd_bad += " %s(walks into a wall at %s)" % [id, str(p)]
	t._check(crowd_bad == "", "every civic crowd walks open ground inside its site%s" % crowd_bad)
	for h in holders:
		h.queue_free()
	await t.get_tree().process_frame
	# The table's yaw really turns a landmark: the station a quarter turn, still inside its
	# block, its crowd still inside its site.
	CivicSites.yaw_override["pueblo_station"] = 90
	var turned := Node3D.new()
	turned.position = -off
	city.add_child(turned)
	var tbody := StaticBody3D.new()
	turned.add_child(tbody)
	Landmarks.build(entries.pueblo_station, turned, tbody, plan, true)
	var pivot := turned.get_node_or_null("Civic_pueblo_station") as Node3D
	var tb := Rect2()
	var tfirst := true
	for mi in turned.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh:
			var ab := m.global_transform * m.mesh.get_aabb()
			var r := Rect2(Vector2(ab.position.x, ab.position.z) + Vector2(off.x, off.z), Vector2(ab.size.x, ab.size.z))
			tb = r if tfirst else tb.merge(r)
			tfirst = false
	var sidx := plan.block_index_at(entries.pueblo_station.anchor)
	var srect: Rect2 = plan.block(sidx.x, sidx.y).rect
	var tcrowd: Array = Landmarks.crowds(entries.pueblo_station, plan)
	var tsite := Landmarks.site_rect(plan, entries.pueblo_station.anchor)
	CivicSites.yaw_override.clear()
	t._check(pivot != null and absf(pivot.rotation.y - PI * 0.5) < 0.01 and not tfirst and srect.grow(3.0).encloses(tb)
		and not tcrowd.is_empty() and tsite.grow(0.5).encloses(tcrowd[0][0]),
		"a civic landmark turned a quarter by its table yaw stays in its block (%s in %s)" % [tb, srect])
	turned.queue_free()
	await t.get_tree().process_frame


## [id, world xz, lowest acceptable hit height] for the roofs worth landing on. Points are taken
## in each landmark's own frame and through CivicSites, so a turned landmark is probed right.
func _roofs(plan: CityPlan, _entries: Dictionary) -> Array:
	var out := []
	var a := CivicSites.site(plan, "arena")
	out.append(["arena", CivicSites.to_world(a, LandmarkArenaDistrict._arena_centre(a.local)), float(a.y0) + LandmarkArenaDistrict.DRUM_TOP])
	var hall := CivicSites.site(plan, "ziggurat_hall")
	out.append(["ziggurat_hall", CivicSites.to_world(hall, LandmarkCivicCenter._hall_tower(hall.local)), float(hall.y0) + 110.0])
	var hotel := CivicSites.site(plan, "live_hotel")
	out.append(["live_hotel", CivicSites.to_world(hotel, Vector2(-4.0, -2.0)), float(hotel.y0) + 150.0])
	var st := CivicSites.site(plan, "pueblo_station")
	var sl: Rect2 = st.local
	out.append(["pueblo_station", CivicSites.to_world(st, sl.position + Vector2(LandmarkCivicCenter._station_court(sl) + 15.0, 12.0)), float(st.y0) + 10.0])
	var ch := CivicSites.site(plan, "concert_hall")
	out.append(["concert_hall", CivicSites.to_world(ch, Vector2(4.0, -4.0)), float(ch.y0) + 12.0])
	return out
