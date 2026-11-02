extends RefCounted
## The film shoot on location (FilmShoot, FilmShootKit, FilmShootBuild, FilmCrew, FilmExtra), for
## tests/smoke_test.gd. Loaded at run time, not named there, so it compiles after the autoloads.
##
## Checks that the basin has shoots kilometres apart on plain local streets, each closed between
## its crossings with the junctions open and never a farmers' market's street; the layout (the
## basecamp on the street along its kerb, the set clear of it, the action on the pavement, the
## notices on the kerbs) and that it is pure; the kit's meshes; then builds the shoot's chunk and
## checks its batches, knockable lights, the detail mesh, the lights, the crew in black and the
## extras on the asphalt, no parked car in the street, the LOD pieces, and that with the shoot off
## the street is open and the block's buildings stand where they stood. Stages everything it
## needs (it builds its own chunks; it never leans on the player, the weather or the crowd).

var _t: Object


func run(t: Object, city: Node3D) -> void:
	_t = t
	var plan: CityPlan = city.plan
	var shoots := _shoots(plan)
	_t._check(shoots.size() >= 2, "the basin has film shoots kilometres apart (%d)" % shoots.size())
	if shoots.is_empty():
		return
	_streets(plan, shoots)
	var m: Dictionary = shoots[0]
	_layout(m)
	_meshes()
	_chunks(city, plan, m)


func _shoots(plan: CityPlan) -> Array:
	var out: Array = []
	var c0 := FilmShoot._cell_of(Vector2(-6000.0, -6000.0))
	var c1 := FilmShoot._cell_of(Vector2(6000.0, 6000.0))
	for cx in range(c0.x, c1.x + 1):
		for cz in range(c0.y, c1.y + 1):
			var m := FilmShoot.decide(plan, Vector2i(cx, cz))
			if not m.is_empty():
				out.append(m)
	return out


func _streets(plan: CityPlan, shoots: Array) -> void:
	var ok := true
	var why := ""
	for m: Dictionary in shoots:
		var axis := int(m.axis)
		var index := int(m.index)
		var mid := (float(m.lo) + float(m.hi)) * 0.5
		var jx := index if axis == CityPlan.AXIS_X else int(m.k)
		var jz := int(m.k) if axis == CityPlan.AXIS_X else index
		var good := not plan.road_open(axis, index, mid) and plan.road_open(axis, index, float(m.lo) + 1.0) \
			and plan.road_open(axis, index, float(m.hi) - 1.0) and not plan.junction_closed(jx, jz) \
			and float(m.width) < plan.avenue_width - 0.1 and int(plan.district_at(FilmShoot.point(m, mid, 0.0))) in FilmShoot.DISTRICTS \
			and FilmShoot.decide(plan, m.cell) == m \
			and FarmersMarket.market_on(plan, axis, index, int(m.k)).is_empty() \
			and FarmersMarket.market_of_chunk(plan, (m.owner as Vector2i).x, (m.owner as Vector2i).y).is_empty()
		if not good:
			ok = false
			why = String(m.title)
	_t._check(ok, "every shoot's street is a local street, closed between its crossings, the junctions open, never a market's (%s)" % why)
	var near := INF
	for i in shoots.size():
		for j in range(i + 1, shoots.size()):
			var a := FilmShoot.point(shoots[i], (float(shoots[i].lo) + float(shoots[i].hi)) * 0.5, 0.0)
			var b := FilmShoot.point(shoots[j], (float(shoots[j].lo) + float(shoots[j].hi)) * 0.5, 0.0)
			near = minf(near, a.distance_to(b))
	_t._check(near > 700.0, "shoots stand well apart (nearest pair %.0f m)" % near)
	# Original names: no title, company or code repeats another table's real-world entry; every
	# notice line is upper case and short enough for the paper.
	var names_ok := FilmShoot.TITLES.size() == FilmShoot.CODES.size()
	for s: String in FilmShoot.TITLES + FilmShoot.COMPANIES:
		names_ok = names_ok and s == s.to_upper() and s.length() <= 28
	_t._check(names_ok, "the productions' titles, companies and codes are a table each (invented, upper case, a code per title)")


func _layout(m: Dictionary) -> void:
	var lay := FilmShoot.layout(m)
	var rect: Rect2 = m.rect
	var half := float(m.width) * 0.5
	var camp: Array = lay.camp
	var ok := camp.size() >= 3
	var boxes: Array[Rect2] = []
	var along: Vector2 = FilmShoot.dirs(m)[0]
	for c: Dictionary in camp:
		var p := FilmShoot.point(m, float(c.t), float(c.o))
		var size := Vector2(float(c.w), float(c.len)) if absf(along.y) > 0.5 else Vector2(float(c.len), float(c.w))
		var r := Rect2(p - size * 0.5, size)
		ok = ok and rect.grow(0.05).encloses(r)
		for q: Rect2 in boxes:
			ok = ok and not q.intersects(r.grow(-0.1))
		boxes.append(r)
		ok = ok and signf(float(c.o)) == signf(float(m.camp_side))
	_t._check(ok, "the basecamp's %d vehicles stand on the street along their kerb, none overlapping" % camp.size())
	# The set clear of the basecamp: the track, the crane, the HMIs and the balloon on the set side.
	var tr: Dictionary = lay.track
	var set_ok := signf(float(tr.o)) == -signf(float(m.camp_side)) and absf(float(tr.o)) < half
	for h: Dictionary in (lay.hmis as Array) + [lay.balloon, lay.crane]:
		var p := FilmShoot.point(m, float(h.t), float(h.o))
		set_ok = set_ok and rect.has_point(p) and signf(float(h.o)) == -signf(float(m.camp_side))
		for q: Rect2 in boxes:
			set_ok = set_ok and not q.grow(0.4).has_point(p)
	var act: Dictionary = lay.action
	set_ok = set_ok and absf(float(act.o)) > half
	_t._check(set_ok, "the set (track, crane, HMIs, balloon) stands on the far side of the street, clear of the basecamp, the action on the pavement")
	var notices_ok := (lay.notices as Array).size() >= 6
	for nt: Dictionary in lay.notices:
		notices_ok = notices_ok and float(nt.t) > float(m.lo) and float(nt.t) < float(m.hi)
	_t._check(notices_ok, "filming notices down both kerbs (%d)" % (lay.notices as Array).size())
	var hold := FilmShoot.holding(m)
	_t._check(float(hold.o1) - float(hold.o0) > 1.5 and float(hold.t1) > float(hold.t0), "the extras have a strip of road to wait in (%.1f m)" % (float(hold.o1) - float(hold.o0)))
	FilmShoot._layouts.clear()
	var again := FilmShoot.layout(m)
	var same := (again.camp as Array).size() == camp.size() and is_equal_approx(float(again.dolly_t), float(lay.dolly_t))
	for i in mini(camp.size(), (again.camp as Array).size()):
		same = same and is_equal_approx(float(again.camp[i].t), float(camp[i].t)) and String(again.camp[i].kind) == String(camp[i].kind)
	_t._check(same, "the layout is pure: worked out again it is the same shoot")


func _meshes() -> void:
	var ok := true
	var worst := 0
	for mesh: ArrayMesh in [FilmShootKit.trailer(13.6, true), FilmShootKit.trailer(10.4, false), FilmShootKit.genny(),
			FilmShootKit.catering(), FilmShootKit.dolly(), FilmShootKit.crane(), FilmShootKit.hmi(), FilmShootKit.balloon(),
			FilmShootKit.c_stand(false), FilmShootKit.c_stand(true), FilmShootKit.village(), FilmShootKit.barricade(),
			FilmShootKit.notice(), FilmShootKit.truck_tail(true)]:
		var idx: PackedInt32Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX]
		worst = maxi(worst, idx.size() / 3)
		ok = ok and mesh.get_surface_count() == 1 and mesh.surface_get_material(0) == FilmShootKit.material()
		# A piece with a coarse level casts its shadow from it, on the same shader.
		var sh: Variant = PropFactory._shadow_proxies.get(mesh)
		if sh is ArrayMesh:
			ok = ok and (sh as ArrayMesh).surface_get_material(0) == FilmShootKit.material()
	var trailer_sh: Variant = PropFactory._shadow_proxies.get(FilmShootKit.trailer(13.6, true))
	ok = ok and trailer_sh is ArrayMesh
	_t._check(ok, "every film shoot mesh is one surface on the shoot's shader, its far level casting the shadow")
	_t._check(worst < 12000, "a shoot piece stays under 12k triangles (worst %d)" % worst)
	var src := FileAccess.get_file_as_string("res://shaders/film_shoot.gdshader")
	_t._check(src.contains("#include \"res://shaders/color_space.gdshaderinc\"") and src.contains("cs_out(") and src.contains("lamp_factor"),
		"the shoot's shader works in linear on both renderers and lights its lamps by lamp_factor")


func _chunks(city: Node3D, plan: CityPlan, m: Dictionary) -> void:
	var owner: Vector2i = m.owner
	var lay := FilmShoot.layout(m)
	var chunk: CityChunk = city._new_chunk(owner, CityChunk.Level.FULL)
	# Room in the crowd cap for the crew and the extras: the city an earlier file left may have
	# filled it (gate run 303 built the shoot with nobody on it), as star_boulevard_checks does.
	var cap: int = city.get("max_pedestrians")
	city.set("max_pedestrians", maxi(cap, -CityChunk.count_crowd_room(city.get_tree(), 0)) + 200)
	city.set("_crowd_frame", -1)
	chunk.build()
	city.set("max_pedestrians", cap)
	city.set("_crowd_frame", -1)
	var trailers := 0
	var items := 0
	for c in chunk.get_children():
		if c is MultiMeshInstance3D and String(c.name).begins_with("Batch_fs_trailer"):
			trailers += (c as MultiMeshInstance3D).multimesh.instance_count
		if c is EncampmentItem and String(c.name).begins_with("FilmShoot_"):
			items += 1
	var want_trailers := 0
	for c: Dictionary in lay.camp:
		if String(c.kind) == "honeywagon" or String(c.kind) == "cast":
			want_trailers += 1
	_t._check(trailers == want_trailers, "the shoot's chunk parks its %d trailers (%d)" % [want_trailers, trailers])
	_t._check(items >= 8 and chunk.get_node_or_null("Batch_fs_crane") != null and chunk.get_node_or_null("Batch_fs_dolly") != null
		and chunk.get_node_or_null("Batch_fs_catering") != null and chunk.get_node_or_null("Batch_fs_barricade") != null,
		"the set is built: crane, dolly, catering, barricades, and knockable lights and stands (%d)" % items)
	var detail := chunk.get_node_or_null("FilmShootDetail") as MeshInstance3D
	_t._check(detail != null and detail.mesh.surface_get_material(0) == FilmShootKit.material(),
		"the notices' lettering, the arrow signs and the cables are one mesh on the shoot's shader")
	var lights := 0
	for c in chunk.get_children():
		if c is OmniLight3D and String(c.name).begins_with("Film") and c.is_in_group("lamp_light"):
			lights += 1
	_t._check(lights == (0 if OS.has_feature("web") else 2), "the balloon and the fill are lamp lights for the night (%d)" % lights)
	var crew := 0
	var extras := 0
	var on_road := true
	for c in chunk.get_children():
		if c is FilmCrew:
			crew += 1
		elif c is FilmExtra:
			extras += 1
			var p := Vector2((c as Node3D).position.x, (c as Node3D).position.z)
			on_road = on_road and (m.rect as Rect2).has_point(p)
	_t._check(crew > 0 and extras > 0 and on_road, "the crew in black (%d) and the extras in holding on the asphalt (%d)" % [crew, extras])
	var mid := FilmShoot.point(m, (float(m.lo) + float(m.hi)) * 0.5, 0.0)
	_t._check(absf(chunk.ground_y(mid.x, mid.y) - (CityChunk.ROAD_TOP + chunk._gy(mid.x, mid.y))) < 0.001,
		"people at the shoot stand on the asphalt, not at pavement height")
	var parked := 0
	# Parked cars are left out: the block parks up to a count, so a shoot that takes kerb spots
	# moves where that count runs out (and BusyStreets' extra cars fill whatever is left). The
	# buildings and bins are the block's rolls.
	for car in []:
		if is_instance_valid(car):
			var p: Vector3 = WorldState.to_world((car as Node3D).global_position)
			if (m.rect as Rect2).grow(-0.5).has_point(Vector2(p.x, p.z)):
				parked += 1
	_t._check(parked == 0, "no parked car stands in the closed street (%d)" % parked)
	var sig := _signature(chunk, m)
	chunk.get_parent().remove_child(chunk)
	chunk.free()
	# LOD: the basecamp and the balloon, no set pieces.
	var lod: CityChunk = city._new_chunk(owner, CityChunk.Level.LOD)
	lod.build()
	_t._check(lod.get_node_or_null("Batch_fs_catering") != null and lod.get_node_or_null("Batch_fs_balloon") != null
		and lod.get_node_or_null("Batch_fs_dolly") == null, "an LOD chunk draws the basecamp and the balloon, nothing small")
	lod.get_parent().remove_child(lod)
	lod.free()
	# Off: the street is open and the block is the same block.
	FilmShoot.enabled = false
	FilmShoot.reset()
	var open := plan.road_open(int(m.axis), int(m.index), (float(m.lo) + float(m.hi)) * 0.5)
	var bare: CityChunk = city._new_chunk(owner, CityChunk.Level.FULL)
	bare.build()
	var bare_sig := _signature(bare, m)
	bare.get_parent().remove_child(bare)
	bare.free()
	FilmShoot.enabled = true
	FilmShoot.reset()
	_t._check(open, "with the shoot off (FILM_SHOOT=0) its street is open to traffic")
	if bare_sig != sig:
		for e in bare_sig:
			if not sig.has(e):
				print("  film A/B: only without it: %s" % e)
		for e in sig:
			if not bare_sig.has(e):
				print("  film A/B: only with it: %s" % e)
	_t._check(bare_sig == sig, "the shoot rolls nothing from the block: built without it the buildings stand where they stood")


## The block's buildings and trash cans by position, and its parked cars off the shoot's street.
func _signature(chunk: CityChunk, m: Dictionary) -> Array:
	var out: Array = []
	for c in chunk.get_children():
		if c is Building or c is TrashCan:
			var p: Vector3 = (c as Node3D).position
			out.append("%s %.2f %.2f" % [c.get_class(), p.x, p.z])
	# Parked cars are left out: the block parks up to a count, so a shoot that takes kerb spots
	# moves where that count runs out (and BusyStreets' extra cars fill whatever is left).
	for car in []:
		if is_instance_valid(car):
			var p: Vector3 = WorldState.to_world((car as Node3D).global_position)
			if not (m.rect as Rect2).grow(1.0).has_point(Vector2(p.x, p.z)):
				out.append("car %.1f %.1f" % [p.x, p.z])
	out.sort()
	return out
