extends RefCounted
## Climbing plants and garden accents (ClimbingPlants), for tests/smoke_test.gd. Loaded at run
## time, not named there, so it compiles after the autoloads.
##
## Builds beach-town FULL chunks straight from the plan (city._new_chunk + build()) and checks:
## the atlas is the grid the script reads; the per-district tables cover every district; a beach
## block grows bougainvillea and more on its walls, drawn as tiles of one shader with a
## shadows-only twin and no shadow from the leaves themselves, each with a draw distance; the
## card and accent caps hold; no card on a house face sits in a window, a door or inside the wing
## next to it; the same block builds the same plants; built with the plants off the block is the
## same block (hash-seeded, nothing else moved); a LOD chunk grows nothing; downtown is far
## sparser than the beach town. Counts come from the chunk's "climbers" meta (mesh data reads
## back empty under --headless).

var _t: Node


func run(t: Node, city: Node3D) -> void:
	_t = t
	var plan: CityPlan = city.plan
	var tex: Texture2D = load("res://assets/textures/climbers/climbers_albedo.png")
	_t._check(tex != null and tex.get_width() == ClimbingPlants.ATLAS_COLS * int(ClimbingPlants.CELL_PX) \
		and tex.get_height() == ClimbingPlants.ATLAS_ROWS * int(ClimbingPlants.CELL_PX),
		"the climbers atlas is the %d x %d grid of %d px cells ClimbingPlants reads" % [ClimbingPlants.ATLAS_COLS, ClimbingPlants.ATLAS_ROWS, int(ClimbingPlants.CELL_PX)])
	_t._check(ClimbingPlants.DISTRICT_SHARE.size() == CityPlan.District.size() and ClimbingPlants.WALL_ODDS.size() == ClimbingPlants.WALL_SPECIES.size(),
		"the climbers' per-district and per-wall tables cover every district and wall kind")
	var keys := _blocks(plan, CityPlan.District.BEACHTOWN, 6)
	_t._check(keys.size() >= 2, "the beach town has blocks of houses to plant (%d)" % keys.size())
	var grown := 0
	var species := {}
	var tiles_ok := true
	var caps_ok := true
	var in_holes := 0
	var faces := 0
	var same := true
	var off_same := true
	var built := 0
	ClimbingPlants.debug = true
	for k in keys:
		if built >= 2:
			break
		var chunk: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
		chunk.build()
		var m: Dictionary = chunk.get_meta("climbers", {})
		if int(m.get("cards", 0)) == 0:
			chunk.get_parent().remove_child(chunk)
			chunk.free()
			continue
		built += 1
		grown += int(m.cards)
		for s: String in (m.counts as Dictionary):
			if int(m.counts[s]) > 0:
				species[s] = true
		caps_ok = caps_ok and int(m.cards) <= ClimbingPlants.MAX_CARDS and int(m.accent_tris) <= ClimbingPlants.MAX_ACCENT_TRIS + 400
		for n in chunk.get_tree().get_nodes_in_group("climbers"):
			if not chunk.is_ancestor_of(n):
				continue
			var mi := n as MeshInstance3D
			var shadow_twin := String(mi.name).begins_with("ClimbersShadow")
			var leaves := String(mi.name).begins_with("Climbers_")
			tiles_ok = tiles_ok and mi.mesh.get_surface_count() == 1 and mi.mesh.surface_get_material(0) == ClimbingPlants.material() \
				and mi.visibility_range_end > 0.0 \
				and (not shadow_twin or mi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY) \
				and (not leaves or mi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
		# No card centre in an opening of the house face it grew on.
		for f: Dictionary in (m.faces as Array):
			faces += 1
			var o: Vector3 = f.o
			var tt: Vector3 = f.t
			var nn: Vector3 = f.n
			for c: Vector3 in (m.centres as Array):
				var d := c - o
				var off := d.dot(nn)
				if off < -0.02 or off > 0.7:
					continue
				var u := d.dot(tt)
				for hl: Array in (f.holes as Array):
					if u > float(hl[0]) + 0.25 and u < float(hl[1]) - 0.25 and d.y > float(hl[2]) + 0.25 and d.y < float(hl[3]) - 0.25:
						in_holes += 1
						break
		var sig := _signature(chunk)
		var counts: Dictionary = (m.counts as Dictionary).duplicate()
		var cards := int(m.cards)
		chunk.get_parent().remove_child(chunk)
		chunk.free()
		# The same block again: the same plants.
		var again: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
		again.build()
		var m2: Dictionary = again.get_meta("climbers", {})
		same = same and int(m2.get("cards", -1)) == cards and m2.counts == counts
		again.get_parent().remove_child(again)
		again.free()
		# Off: the same block, no plants.
		ClimbingPlants.enabled = false
		var bare: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
		bare.build()
		ClimbingPlants.enabled = true
		off_same = off_same and _signature(bare) == sig and bare.get_tree().get_nodes_in_group("climbers").filter(func(n: Node) -> bool: return bare.is_ancestor_of(n)).is_empty()
		bare.get_parent().remove_child(bare)
		bare.free()
	ClimbingPlants.debug = false
	_t._check(grown > 200, "beach-town blocks grow climbers on their walls (%d cards on %d blocks)" % [grown, built])
	_t._check(species.has("bougainvillea") and species.size() >= 4, "bougainvillea and at least three more species grow there (%s)" % [species.keys()])
	_t._check(tiles_ok, "climbers are tiles of one mesh on the climbers shader, ranged, the leaves shadowless and their twin shadows-only")
	_t._check(caps_ok, "the per-chunk card and accent caps hold")
	_t._check(faces > 0 and in_holes == 0, "no card grows in a house window, door or the wing beside it (%d faces, %d cards in openings)" % [faces, in_holes])
	_t._check(same, "the same block grows the same plants")
	_t._check(off_same, "the plants roll nothing from the block: built without them it is the same block")
	# A LOD chunk grows nothing.
	if not keys.is_empty():
		var lod: CityChunk = city._new_chunk(keys[0], CityChunk.Level.LOD)
		lod.build()
		_t._check(not lod.has_meta("climbers") and lod.get_tree().get_nodes_in_group("climbers").filter(func(n: Node) -> bool: return lod.is_ancestor_of(n)).is_empty(),
			"a LOD chunk grows no climbers")
		lod.get_parent().remove_child(lod)
		lod.free()
	_t._check(float(ClimbingPlants.DISTRICT_SHARE[CityPlan.District.DOWNTOWN]) < 0.2 * float(ClimbingPlants.DISTRICT_SHARE[CityPlan.District.BEACHTOWN]),
		"downtown is far sparser in climbers than the beach town")


## Beach-town (or `district`) blocks of lots, ordinary sizes first.
func _blocks(plan: CityPlan, district: int, want: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var c0 := plan.block_index_at(Vector2(0.0, 2500.0))
	for r in range(0, 30):
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dz)) != r or out.size() >= want:
					continue
				var k := c0 + Vector2i(dx * 2, dz * 2)
				var b := plan.block(k.x, k.y)
				var rect: Rect2 = b.rect
				if int(b.district) == district and int(b.kind) == CityPlan.BlockKind.BUILDINGS and not b.has("site") \
						and rect.size.x < 160.0 and rect.size.y < 160.0 \
						and plan.zone_at(rect.get_center()) == MacroMap.Zone.CITY and not plan.lots(k.x, k.y).is_empty():
					out.append(k)
	return out


## Everything the block built but the plants: child names and the batches' instance counts.
func _signature(chunk: CityChunk) -> Array:
	var out: Array = []
	for c in chunk.get_children():
		var nm := String(c.name)
		if nm.begins_with("Climber"):
			continue
		var count := 0
		if c is MultiMeshInstance3D and (c as MultiMeshInstance3D).multimesh:
			count = (c as MultiMeshInstance3D).multimesh.instance_count
		out.append("%s:%d" % [nm, count])
	out.sort()
	return out
