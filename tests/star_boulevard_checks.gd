extends RefCounted
## The walk of fame (StarBoulevard, StreetCharacter, shaders/walk_of_fame.gdshader), for
## tests/smoke_test.gd. Loaded at run time, not named there, so it compiles after the autoloads.
##
## Checks the plan (a wide midtown boulevard, plain blocks both sides, a short stretch, pure and the
## same twice, on two seeds), the names (invented, unique, as many as the atlas holds), the palace's
## lot (on the walk, fronting it, nobody else's), then builds the palace's block FULL: the band of
## stars on the walk_of_fame shader on the pavement, the palace (BroadwayTheatre) behind its
## forecourt, the souvenir goods and the lamps' medallions, the costumed characters in their
## costumes, the sightseeing buses on their kerb; then LOD (the palace's far boxes, no band); and
## with the walk off the same block (trash cans, the other buildings, the props) is unmoved.

var _t: Node


func run(t: Node, city: Node3D) -> void:
	_t = t
	var plan: CityPlan = city.plan
	_names()
	var p := StarBoulevard.plan_for(plan)
	_t._check(not p.is_empty(), "the walk of fame finds its boulevard in midtown on this seed")
	if p.is_empty():
		return
	_plan(plan, p)
	var pal: Dictionary = p.palace
	_t._check(not pal.is_empty(), "the walk has its movie palace on a lot fronting it")
	if pal.is_empty():
		return
	_full_block(city, plan, pal)
	_goods(city, plan, p)
	_lod_block(city, pal)


func _names() -> void:
	var names: Array = StarNames.NAMES
	var unique := {}
	for n: String in names:
		unique[n] = true
	var img := Image.load_from_file(ProjectSettings.globalize_path("res://assets/textures/star_boulevard/walk_atlas.png"))
	var size_ok := img != null and img.get_width() == 1024 and img.get_height() == 2048
	_t._check(names.size() == 120 and unique.size() == names.size() and size_ok,
		"the walk's names: %d, all different, one atlas cell each (1024 x 2048)" % names.size())
	# Invented only: no real star's name on any star (a list of the most famous, by surname).
	var real := ["MONROE", "CHAPLIN", "HEPBURN", "BOGART", "GARLAND", "PRESLEY", "SINATRA", "DEAN",
		"BRANDO", "STEWART", "GRANT", "TAYLOR", "WAYNE", "DISNEY", "JACKSON", "LENNON", "HANKS",
		"STREEP", "NICHOLSON", "EASTWOOD", "GABLE", "DAVIS", "CROSBY", "HOPE", "BALL", "TEMPLE"]
	var clean := true
	for n: String in names:
		for r: String in real:
			clean = clean and not n.ends_with(" " + r)
	_t._check(clean, "no star carries a real person's name")
	for c: Dictionary in StreetCharacter.COSTUMES:
		clean = clean and c.has("name") and c.has("pieces")
	_t._check(clean and StreetCharacter.COSTUMES.size() >= 5, "%d original costumes, each complete" % StreetCharacter.COSTUMES.size())


func _plan(plan: CityPlan, p: Dictionary) -> void:
	var ok := float(p.width) >= StarBoulevard.MIN_WIDTH
	var n := int(p.k1) - int(p.k0) + 1
	ok = ok and n >= StarBoulevard.MIN_RUN and n <= StarBoulevard.MAX_RUN
	for k in range(int(p.k0), int(p.k1) + 1):
		for bz: int in [int(p.road) - 1, int(p.road)]:
			var b := plan.block(k, bz)
			ok = ok and b.district == CityPlan.District.MIDTOWN and b.kind == CityPlan.BlockKind.BUILDINGS
			ok = ok and StarBoulevard.block_side(plan, k, bz) == (-1 if bz < int(p.road) else 1)
	ok = ok and StarBoulevard.block_side(plan, int(p.k1) + 1, int(p.road)) == 0
	_t._check(ok, "the walk runs %d blocks of %s (%.0f m wide), plain midtown blocks on both sides" % [n, p.name, float(p.width)])
	# Pure: worked out again from nothing it is the same walk; another seed has its own or none.
	StarBoulevard._plans.erase(plan.seed)
	var again := StarBoulevard.plan_for(plan)
	_t._check(int(again.road) == int(p.road) and int(again.k0) == int(p.k0) and int(again.k1) == int(p.k1)
		and int(((again.palace as Dictionary).get("lot", {}) as Dictionary).get("seed", -1)) == int(((p.palace as Dictionary).get("lot", {}) as Dictionary).get("seed", -1)),
		"the walk is pure: worked out again it is the same boulevard, stretch and palace")
	var p2 := CityPlan.new()
	p2.seed = plan.seed + 7919
	p2.macro = plan.macro
	var other := StarBoulevard.plan_for(p2)
	_t._check(other.is_empty() or float(other.width) >= StarBoulevard.MIN_WIDTH,
		"another seed gets its own walk or none (%s)" % ("none" if other.is_empty() else str(other.name)))
	var pal: Dictionary = p.palace
	if not pal.is_empty():
		var bi: Vector2i = pal.block
		var lot: Dictionary = pal.lot
		_t._check(StarBoulevard.lot_fronts(plan, bi.x, bi.y, int(pal.side), lot) and StarBoulevard.claims(plan, bi.x, bi.y, lot)
			and not Broadway.claims(plan, bi.x, bi.y, lot) and not FireStation.claims(plan, bi.x, bi.y, lot)
			and float(pal.depth) >= StarBoulevard.PALACE_MIN.y,
			"the palace's lot fronts the walk, is nobody else's, and is %.0f m deep with the lot behind" % float(pal.depth))
		_t._check(StarBoulevard.blocks_parking(plan, Vector3(StarBoulevard.bus_zone(plan).get_center().x, 0.0, StarBoulevard.bus_zone(plan).get_center().y))
			and not StarBoulevard.blocks_parking(plan, Vector3(StarBoulevard.bus_zone(plan).get_center().x + 60.0, 0.0, StarBoulevard.bus_zone(plan).get_center().y)),
			"the sightseeing buses' kerb is kept clear of parked cars, and only that stretch")


func _full_block(city: Node3D, plan: CityPlan, pal: Dictionary) -> void:
	var k: Vector2i = pal.block
	var chunk: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
	chunk.build()
	var band: MeshInstance3D = null
	var forecourt: MeshInstance3D = null
	var palace: Node3D = null
	var chars := 0
	var costumed := 0
	for c in chunk.get_children():
		if c is MeshInstance3D and c.name == "WalkOfFame":
			band = c
		elif c is MeshInstance3D and c.name == "PalaceForecourt":
			forecourt = c
		elif c is Node3D and (c as Node).is_in_group("broadway_palace"):
			palace = c
		elif c is StreetCharacter:
			chars += 1
			if (c as Node).find_children("Costume", "MeshInstance3D", true, false).size() > 0 \
					or StreetCharacter.COSTUMES[(c as StreetCharacter).costume].has("metal"):
				costumed += 1
	var shader_ok := band != null and band.material_override is ShaderMaterial \
		and (band.material_override as ShaderMaterial).shader.resource_path.ends_with("walk_of_fame.gdshader")
	var tris := int(band.get_meta("squares", 0)) * 2 if band else 0
	var rect: Rect2 = plan.block(k.x, k.y).rect
	var span := StarBoulevard.band_span(rect)
	var kz := StarBoulevard.kerb_z(rect, int(pal.side))
	var in_band := band != null and absf(float(band.get_meta("band_z", 0.0)) - (kz + float(pal.side) * (StarBoulevard.BAND_FROM + StarBoulevard.BAND * 0.5))) < 0.2
	_t._check(shader_ok and tris >= int(span.y - span.x) and in_band,
		"the band of stars lies on the walk's pavement, %.1f-%.1f m in from the kerb, on the walk_of_fame shader (%d triangles)" % [StarBoulevard.BAND_FROM, StarBoulevard.BAND_FROM + StarBoulevard.BAND, tris])
	_t._check(palace != null and palace.name == "Palace_starlight_palace" and forecourt != null,
		"the movie palace stands behind its forecourt of handprint slabs")
	if palace:
		var front := (pal.lot.center as Vector2).y - float(pal.side) * (pal.lot.size as Vector2).y * 0.5
		_t._check(absf(palace.position.z - (front + float(pal.side) * StarBoulevard.FORECOURT)) < 0.05,
			"the palace's front is set back %.0f m from the pavement" % StarBoulevard.FORECOURT)
	var medals := chunk.get_node_or_null("Batch_sb_medal") as MultiMeshInstance3D
	var lamps: Array = chunk.get_meta("sb_lamps", [])
	_t._check(medals != null and medals.multimesh.instance_count == lamps.size() and lamps.size() > 0,
		"a neon star on each of the walk's lamps (%d)" % lamps.size())
	var want := 0
	for i in StarBoulevard.MAX_CHARACTERS:
		if not StarBoulevard.character_spot(plan, k.x, k.y, rect, int(pal.side), i).is_empty():
			want += 1
	_t._check(chars <= want and costumed == chars and (want == 0 or chars > 0),
		"costumed characters on the stars (%d of %d planned), every one in costume" % [chars, want])
	var buses := 0
	var zone := StarBoulevard.bus_zone(plan)
	for car in chunk.get("_cars"):
		if is_instance_valid(car) and (car as Node).is_in_group("sightseeing_bus"):
			var at := WorldState.to_world((car as Node3D).position)
			if zone.grow(1.0).has_point(Vector2(at.x, at.z)):
				buses += 1
	_t._check(buses == StarBoulevard.BUSES or not PhysicsBudget.can_spawn(),
		"%d sightseeing buses at the kerb in front of the palace" % buses)
	# Off: the same block, every other building and trash can where it was.
	var sig := _signature(chunk, pal)
	_free(chunk)
	StarBoulevard.enabled = false
	StarBoulevard._plans.clear()
	var bare: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
	bare.build()
	StarBoulevard.enabled = true
	StarBoulevard._plans.clear()
	var bare_sig := _signature(bare, pal)
	var none := bare.find_children("WalkOfFame", "MeshInstance3D", false, false).is_empty()
	_t._check(sig == bare_sig and not sig.is_empty() and none,
		"the walk rolls nothing from the block: its trash cans and the buildings off the walk are unmoved (%d)" % sig.size())
	if sig != bare_sig:
		for x in sig:
			if not bare_sig.has(x):
				print("  walk on only:  ", x)
		for x in bare_sig:
			if not sig.has(x):
				print("  walk off only: ", x)
	_free(bare)


## The souvenir goods and flags along the walk's blocks (the palace's frontage keeps clear of
## them, so a block or two of the others): planned by hash, built on the pavement's band edge.
func _goods(city: Node3D, plan: CityPlan, p: Dictionary) -> void:
	var goods := 0
	var flags := 0
	var built := 0
	for k in range(int(p.k0), int(p.k1) + 1):
		if goods > 0 and flags > 0 or built >= 3:
			break
		var bk := Vector2i(k, int(p.road) - 1)
		if bk == (p.palace as Dictionary).get("block", Vector2i(-99999, 0)):
			continue
		var chunk: CityChunk = city._new_chunk(bk, CityChunk.Level.FULL)
		chunk.build()
		built += 1
		for c in chunk.get_children():
			if c is MultiMeshInstance3D and String(c.name).begins_with("Batch_sb_"):
				var n := (c as MultiMeshInstance3D).multimesh.instance_count
				if String(c.name).begins_with("Batch_sb_flag"):
					flags += n
				elif String(c.name) != "Batch_sb_medal" and String(c.name) != "Batch_sb_pool":
					goods += n
		_free(chunk)
	_t._check(goods > 0 and flags > 0, "souvenir goods (%d) and feather flags (%d) out on the walk's pavements" % [goods, flags])


func _lod_block(city: Node3D, pal: Dictionary) -> void:
	var k: Vector2i = pal.block
	var chunk: CityChunk = city._new_chunk(k, CityChunk.Level.LOD)
	chunk.build()
	var band := chunk.find_children("WalkOfFame", "MeshInstance3D", false, false)
	var boxes := chunk.get_node_or_null("Batch_lod_box") as MultiMeshInstance3D
	_t._check(band.is_empty() and boxes != null and boxes.multimesh.instance_count > 2,
		"LOD: the palace's far boxes, no band of stars")
	_free(chunk)


func _signature(chunk: CityChunk, pal: Dictionary) -> Array:
	var plan := chunk.plan
	var side := StarBoulevard.block_side(plan, chunk.ix, chunk.iz)
	var own: Array[Rect2] = []
	for lot: Dictionary in plan.lots(chunk.ix, chunk.iz):
		if StarBoulevard.lot_fronts(plan, chunk.ix, chunk.iz, side, lot) or int(lot.seed) == int(((pal.get("behind", {})) as Dictionary).get("seed", -1)):
			var c: Vector2 = lot.center
			var sz: Vector2 = lot.size
			own.append(Rect2(c - sz * 0.5, sz).grow(1.0))
	var out: Array = []
	for c in chunk.get_children():
		if c is Building or c is TrashCan:
			var p: Vector3 = (c as Node3D).position
			var mine := false
			for r: Rect2 in own:
				mine = mine or r.has_point(Vector2(p.x, p.z))
			if c is Building and mine:
				continue
			out.append("%s %.2f %.2f" % ["B" if c is Building else "T", p.x, p.z])
	out.sort()
	return out


func _free(chunk: CityChunk) -> void:
	for car in chunk.get("_cars"):
		if is_instance_valid(car):
			(car as Node).get_parent().remove_child(car)
			(car as Node).free()
	chunk.get_parent().remove_child(chunk)
	chunk.free()
