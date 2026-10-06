extends RefCounted
## Kerbs (scripts/world/kerbs.gd: the pavement's cut ring, kerb paint, house numbers, tree wells),
## for tests/smoke_test.gd. Loaded at run time, not named there, so it compiles after the autoloads.
##
## Pure parts first (resolve(), glyph packing, the corner ramps and zones the same twice), then a
## suburban, a beach-town and a downtown block built FULL from the plan: the ring is there with its
## collision, ramps and aprons are cut and lower the kerb, nothing stands in a cut, the marks are
## one shadowless material faded at its range, the suburbs have house numbers; the same block built
## with Kerbs off has the same props and batch counts (hash-seeded: nothing else moves); an LOD
## chunk keeps the plain slab.

var _t: Node


func run(t: Node, city: Node3D) -> void:
	_t = t
	var plan: CityPlan = city.plan
	_pure(plan)
	var picks := _pick_blocks(plan)
	_t._check(picks.size() >= 2, "kerbs: found blocks to build (%d)" % picks.size())
	for k: Vector2i in picks:
		_block(city, plan, k)
	if not picks.is_empty():
		_ab(city, plan, picks[0])
		_lod(city, picks[0])


func _pure(plan: CityPlan) -> void:
	var zones := [[0.25, 6.0, Kerbs.RED, ""], [4.0, 12.0, Kerbs.GREEN, "15 MIN"], [10.0, 20.0, Kerbs.RED, ""], [30.0, 36.0, Kerbs.YELLOW, "LOADING ZONE"]]
	var out := Kerbs.resolve(zones)
	var clash := 0
	for i in out.size():
		for j in range(i + 1, out.size()):
			if float(out[i][0]) < float(out[j][1]) - 0.01 and float(out[j][0]) < float(out[i][1]) - 0.01:
				clash += 1
	_t._check(clash == 0 and out.size() >= 3, "kerbs: resolved zones never overlap (%d zones, %d overlaps)" % [out.size(), clash])
	var bits := Kerbs.glyph_bits("4")
	var rows: Array = LedScreen.GLYPHS["4"]
	var ok := true
	for r in 7:
		var word := int(bits.x) >> (5 * r) if r < 4 else int(bits.y) >> (5 * (r - 4))
		for c in 5:
			ok = ok and ((((word & 31) >> (4 - c)) & 1) == 1) == ((rows[r] as String)[c] == "#")
	_t._check(ok and bits.x < 1048576.0 and bits.y < 32768.0, "kerbs: a glyph packs into UV2 exactly (rows 0-3 in x, 4-6 in y)")
	var b := plan.block(3, 2)
	var r1 := Kerbs.corner_ramps(plan, 3, 2, b.rect)
	var r2 := Kerbs.corner_ramps(plan, 3, 2, b.rect)
	var z1 := Kerbs.edge_zones(plan, 3, 2, b.rect, 1, int(b.district))
	var z2 := Kerbs.edge_zones(plan, 3, 2, b.rect, 1, int(b.district))
	_t._check(str(r1) == str(r2) and str(z1) == str(z2), "kerbs: ramps and zones are pure (the same twice)")
	_t._check(Kerbs.kerb_top([{"e": 0, "uc": 5.0, "a": 0.5, "f": 0.4, "lip": 0.012}], 0, 5.0) < Kerbs.TOP - 0.1 \
		and is_equal_approx(Kerbs.kerb_top([], 0, 5.0), Kerbs.TOP), "kerbs: a cut lowers the kerb to its lip, nothing else does")
	var mat := Kerbs.material()
	_t._check(mat.shader != null and mat.shader.code.contains("km_bit"), "kerbs: the marks material has its shader")


## A suburban, a beach-town and a downtown block of buildings near the map's anchors.
func _pick_blocks(plan: CityPlan) -> Array[Vector2i]:
	var want := {CityPlan.District.SUBURBS: true, CityPlan.District.BEACHTOWN: true, CityPlan.District.DOWNTOWN: true}
	var out: Array[Vector2i] = []
	for a: Vector2 in [Vector2(-540.0, 100.0), Vector2(-600.0, -100.0), Vector2(1640.0, 255.0), Vector2(300.0, -600.0), Vector2(2700.0, 300.0)]:
		var home := plan.block_index_at(a)
		for r in 5:
			for dz in range(-r, r + 1):
				for dx in range(-r, r + 1):
					var k := home + Vector2i(dx, dz)
					var b := plan.block(k.x, k.y)
					if int(b.kind) != CityPlan.BlockKind.BUILDINGS or b.has("site") or plan.river_block(k.x, k.y):
						continue
					if plan.zone_at((b.rect as Rect2).get_center()) != MacroMap.Zone.CITY:
						continue
					if want.has(int(b.district)):
						want.erase(int(b.district))
						out.append(k)
	return out


func _block(city: Node3D, plan: CityPlan, k: Vector2i) -> void:
	var b := plan.block(k.x, k.y)
	var chunk: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
	chunk.build()
	var name := "kerbs %s block %s" % [CityPlan.District.keys()[int(b.district)], k]
	var st: Dictionary = chunk.get_meta("kerbs", {})
	var built: Dictionary = st.get("built", {})
	_t._check(not built.is_empty(), "%s: the ring was built" % name)
	if built.is_empty():
		_drop(chunk)
		return
	var ring := chunk.get_node_or_null("KerbRing") as MeshInstance3D
	_t._check(ring != null and ring.material_override == st.mat, "%s: the ring wears the pavement's own material" % name)
	# Collision: the ring's trimesh on the chunk's StreetProps, covering the block's edge.
	var faces := 0
	for c in chunk._statics.get_children():
		if c is CollisionShape3D and (c as CollisionShape3D).shape is ConcavePolygonShape3D:
			var n: int = ((c as CollisionShape3D).shape as ConcavePolygonShape3D).get_faces().size() / 3
			if n == int(built.faces):
				faces = n
	_t._check(faces == int(built.faces) and faces > 200, "%s: the ring collides (%d triangles)" % [name, faces])
	_t._check(int(built.ramps) >= 2, "%s: corner ramps are cut (%d)" % [name, built.ramps])
	# Nothing upright stands in a cut.
	var inside := 0
	for n: Dictionary in built.notches:
		var poly: PackedVector2Array = n.poly
		for rec: Dictionary in chunk.prop_records:
			var p: Vector3 = rec.position
			if Geometry2D.is_point_in_polygon(Vector2(p.x, p.z), poly):
				inside += 1
	_t._check(inside == 0, "%s: no prop stands in a ramp or an apron (%d)" % [name, inside])
	# The marks: one material, no shadow, faded at its range.
	var marks_ok := true
	var tiles := 0
	for c in chunk.get_children():
		if c is MeshInstance3D and (c as Node).name.begins_with("KerbMarks"):
			tiles += 1
			var mi := c as MeshInstance3D
			marks_ok = marks_ok and mi.material_override == Kerbs.material() and mi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF \
				and mi.visibility_range_end > 100.0
	_t._check(tiles > 0 and marks_ok, "%s: kerb marks are %d shadowless tile(s) on one material" % [name, tiles])
	_t._check((built.zones as Array).size() >= 2, "%s: the kerb is painted (%d zones)" % [name, (built.zones as Array).size()])
	if int(b.district) == CityPlan.District.SUBURBS or int(b.district) == CityPlan.District.BEACHTOWN:
		_t._check((built.numbers as Array).size() >= 1, "%s: house numbers on the kerb (%d)" % [name, (built.numbers as Array).size()])
	# The tree grates wear the kerb shader's grate.
	if chunk._batch.data().has("tree_grate"):
		_t._check(chunk._batch.data()["tree_grate"].mesh == Kerbs.grate_mesh(), "%s: street trees stand in cast-iron grates" % name)
	_drop(chunk)


## The same block with the kerbs off: the same props in the same places, the same batches.
func _ab(city: Node3D, plan: CityPlan, k: Vector2i) -> void:
	var on: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
	on.build()
	Kerbs.enabled = false
	var off: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
	off.build()
	Kerbs.enabled = true
	var same := on.prop_records.size() == off.prop_records.size()
	if same:
		for i in on.prop_records.size():
			var a: Dictionary = on.prop_records[i]
			var b: Dictionary = off.prop_records[i]
			# The street's signs ("ssign_", StreetSigns) step out of the kerb cuts, so they follow them.
			same = same and a.id == b.id and ((a.position as Vector3).is_equal_approx(b.position) or String(a.id).begins_with("ssign_"))
	var counts := true
	var don := on._batch.data()
	var doff := off._batch.data()
	for key: String in doff:
		if key == "kerb_paint":
			continue
		counts = counts and don.has(key) and (don[key].xforms as Array).size() == (doff[key].xforms as Array).size()
	_t._check(same and counts, "kerbs: the block built with the kerbs off has the same props and batches (hash-seeded)")
	_t._check(not off.has_meta("kerbs") and off.get_node_or_null("KerbRing") == null, "kerbs: KERBS=0 builds the plain slab")
	_drop(on)
	_drop(off)


func _lod(city: Node3D, k: Vector2i) -> void:
	var lod: CityChunk = city._new_chunk(k, CityChunk.Level.LOD)
	lod.build()
	_t._check(not lod.has_meta("kerbs") and lod.get_node_or_null("KerbRing") == null, "kerbs: an LOD chunk keeps the plain slab")
	_drop(lod)


func _drop(chunk: CityChunk) -> void:
	chunk.get_parent().remove_child(chunk)
	chunk.free()
