extends RefCounted
## The street's second clutter pass (StreetClutter2: bags, cardboard, carts, cones, a hand truck,
## steam, weeds, butts and gum, puddles, flyers, blowing pages, droppings), for
## tests/smoke_test.gd. Loaded at run time, not named there, so it compiles after the autoloads.
##
## Builds FULL downtown and midtown chunks straight from the plan (city._new_chunk + build()) at a
## forced hour and weekday (a collection night, then a working morning), and checks: the shader's
## surface codes are StreetClutter2's; every kind is laid somewhere; each kind is ONE batch a chunk
## on its shader, the flat ones and the steam shadowless, every one drawn to a distance; the
## pavement kinds stand on the block's pavement and the road kinds lie in its road; the plan is
## the same twice (hash-seeded); steam only where its district has any; the block built with it
## off is the same block and has no batch of it. Placements are read from the chunk's
## "street_clutter_2" meta (instance transforms read back as identity under --headless).

var _t: Object

const PAVEMENT := ["sc2_bags_0", "sc2_bags_1", "sc2_card", "sc2_cart", "sc2_dolly", "sc2_weeds", "sc2_drop"]
const ROAD := ["sc2_puddle", "sc2_paper", "sc2_cone"]


func run(t: Object, city: Node3D) -> void:
	_t = t
	var plan: CityPlan = city.plan
	_shader_codes()
	_tables_and_meshes()
	var hour0 := StreetClutter2.force_hour
	var day0 := StreetClutter2.force_day
	var was := StreetClutter2.enabled
	StreetClutter2.enabled = true
	_built(city, plan)
	StreetClutter2.force_hour = hour0
	StreetClutter2.force_day = day0
	StreetClutter2.enabled = was


func _shader_codes() -> void:
	var src := FileAccess.get_file_as_string("res://shaders/street_clutter_2.gdshader")
	var consts: Dictionary = (load("res://scripts/world/street_clutter_2.gd") as GDScript).get_script_constant_map()
	var bad: Array = []
	for name: String in consts:
		if not name.begins_with("C_"):
			continue
		if src.find("const int %s = %d;" % [name, int(consts[name])]) < 0:
			bad.append(name)
	_t._check(bad.is_empty(), "the street clutter 2 shader's surface codes match StreetClutter2's (%s)" % [bad])
	_t._check(src.find("road_wetness < puddle_from") >= 0, "a puddle is collapsed in the vertex stage on a dry street")
	var steam := FileAccess.get_file_as_string("res://shaders/street_steam.gdshader")
	_t._check(steam.find("depth_draw_never") >= 0 and steam.find("shadows_disabled") >= 0, "the steam is a transparent plume that writes no depth and casts nothing")


func _tables_and_meshes() -> void:
	var short: Array = []
	for name: String in ["COLLECTION_ODDS", "RESTAURANT_BAG_ODDS", "CARDBOARD_ODDS", "STEAM_ODDS", "CART_ODDS", "WEEDS_PER_M",
			"BUTTS_PER_SHOP_M", "PUDDLES_PER_M", "PAPER_ODDS", "DROPPINGS_PER_M"]:
		var table: Array = (load("res://scripts/world/street_clutter_2.gd") as GDScript).get_script_constant_map()[name]
		if table.size() != CityPlan.District.size():
			short.append(name)
	_t._check(short.is_empty(), "every street clutter 2 table covers every district (%s)" % [short])
	# Real-size meshes in a budget: one surface on the right material, triangles in range.
	var bad: Array = []
	for key: String in StreetClutter2.KEYS:
		var mesh := StreetClutter2.mesh_for(key)
		var tris: int = mesh.surface_get_array_len(0) / 3 if mesh.get_surface_count() == 1 else -1
		if tris < 2 or tris > 2600:
			bad.append("%s %d" % [key, tris])
	_t._check(bad.is_empty(), "street clutter 2 meshes are one surface, 2-2,600 triangles (%s)" % [bad])
	var c := StreetClutter2.cone().get_aabb()
	var cart := StreetClutter2.cart().get_aabb()
	_t._check(absf(c.end.y - 0.71) < 0.02 and absf(cart.end.y - 1.06) < 0.06 and absf(cart.size.z - 1.0) < 0.15,
		"a cone stands 71 cm and a cart's handle about a metre up (%.2f, %.2f, %.2f long)" % [c.end.y, cart.end.y, cart.size.z])


func _blocks(plan: CityPlan, at: Vector2, district: int, want: int) -> Array[Vector2i]:
	var centre := plan.block_index_at(at)
	var keys: Array[Vector2i] = []
	for r in 4:
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dz)) != r:
					continue
				var k := centre + Vector2i(dx, dz)
				var b := plan.block(k.x, k.y)
				if int(b.district) != district or int(b.kind) != CityPlan.BlockKind.BUILDINGS or b.has("site") or b.has("grounds") or b.has("hospital"):
					continue
				if plan.zone_at((b.rect as Rect2).get_center()) != MacroMap.Zone.CITY or plan.river_block(k.x, k.y) or plan.marina_block(k.x, k.y):
					continue
				keys.append(k)
				if keys.size() >= want:
					return keys
	return keys


func _built(city: Node3D, plan: CityPlan) -> void:
	var downtown := _blocks(plan, Vector2(2800.0, 100.0), CityPlan.District.DOWNTOWN, 3)
	var midtown := _blocks(plan, Vector2(950.0, 650.0), CityPlan.District.MIDTOWN, 3)
	_t._check(downtown.size() >= 2 and midtown.size() >= 2, "downtown and midtown have blocks of buildings to clutter (%d, %d)" % [downtown.size(), midtown.size()])
	var seen := {}
	var batch_ok := true
	var shadow_ok := true
	var draw_ok := true
	var place_bad: Array = []
	var steam_bad := 0
	var same_plan := true
	var same_block := true
	var off_clean := true
	var count := 0
	var runs := [[21.5, 2], [10.0, 3]]
	var first := true
	for run: Array in runs:
		StreetClutter2.force_hour = float(run[0])
		StreetClutter2.force_day = int(run[1])
		for k in downtown + midtown:
			var chunk: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
			chunk.build()
			var block := plan.block(k.x, k.y)
			var rect: Rect2 = block.rect
			var out: Dictionary = chunk.get_meta("street_clutter_2", {})
			for key: String in out:
				var items: Array = out[key]
				count += items.size()
				if not items.is_empty():
					seen[key] = true
				for it: Array in items:
					var o: Vector3 = (it[0] as Transform3D).origin
					var p := Vector2(o.x, o.z)
					if key in PAVEMENT and not rect.grow(0.05).has_point(p):
						place_bad.append("%s %.1f,%.1f" % [key, p.x, p.y])
					if key in ROAD and rect.grow(-0.1).has_point(p):
						place_bad.append("%s %.1f,%.1f" % [key, p.x, p.y])
					if key == "sc2_steam" and float(StreetClutter2.STEAM_ODDS[int(block.district)]) <= 0.0:
						steam_bad += 1
				var node := chunk.get_node_or_null("Batch_" + key) as MultiMeshInstance3D
				if node == null:
					batch_ok = false
					continue
				var mesh: Mesh = node.multimesh.mesh
				var mat := mesh.surface_get_material(0) as ShaderMaterial
				var want_shader := "street_steam.gdshader" if key == "sc2_steam" else "street_clutter_2.gdshader"
				batch_ok = batch_ok and mesh.get_surface_count() == 1 and mat != null and mat.shader.resource_path.ends_with(want_shader) \
					and node.multimesh.instance_count == items.size()
				if key == "sc2_steam" or key == "sc2_poster" or key in StreetClutter2.FLAT_KEYS:
					shadow_ok = shadow_ok and node.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF and chunk.get_node_or_null("BatchShadow_" + key) == null
				draw_ok = draw_ok and node.visibility_range_end > 0.0
			# Hash-seeded: the same block built again gets the same pieces (first two blocks).
			if first and k == downtown[0] or first and not midtown.is_empty() and k == midtown[0]:
				var twin: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
				twin.build()
				same_plan = same_plan and _sig(twin.get_meta("street_clutter_2", {})) == _sig(out)
				twin.get_parent().remove_child(twin)
				twin.free()
			var sig := _signature(chunk)
			chunk.get_parent().remove_child(chunk)
			chunk.free()
			if first:
				StreetClutter2.enabled = false
				var bare: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
				bare.build()
				StreetClutter2.enabled = true
				same_block = same_block and _signature(bare) == sig
				for key: String in StreetClutter2.KEYS:
					off_clean = off_clean and bare.get_node_or_null("Batch_" + key) == null
				off_clean = off_clean and not bare.has_meta("street_clutter_2")
				bare.get_parent().remove_child(bare)
				bare.free()
		first = false
	var core := ["sc2_bags_0", "sc2_bags_1", "sc2_card", "sc2_steam", "sc2_weeds", "sc2_butts", "sc2_puddle", "sc2_paper", "sc2_drop"]
	var missing := core.filter(func(kd: String) -> bool: return not seen.has(kd))
	_t._check(missing.is_empty(), "downtown and midtown get bags, cardboard, steam, weeds, butts, puddles, pages and droppings (missing %s; %d pieces; seen %s)" % [missing, count, seen.keys()])
	_t._check(batch_ok, "each kind of street clutter 2 is one batch a chunk on its shader, one instance a piece")
	_t._check(shadow_ok, "the flat clutter, the flyers and the steam cast no shadow")
	_t._check(draw_ok, "every street clutter 2 batch stops drawing at a distance")
	_t._check(place_bad.is_empty(), "pavement clutter stands on the pavement and road clutter lies in the road (%s)" % [place_bad.slice(0, 6)])
	_t._check(steam_bad == 0, "steam rises only in districts that have it (%d)" % steam_bad)
	_t._check(same_plan, "street clutter 2 is hash-seeded: the same block built twice gets the same pieces")
	_t._check(same_block, "street clutter 2 rolls nothing from the block: built without it, the block is the same")
	_t._check(off_clean, "off (STREET_CLUTTER_2=0), no street clutter 2 batch is built")


func _sig(out: Dictionary) -> Array:
	var s: Array = []
	for key: String in out:
		for it: Array in out[key]:
			var o: Vector3 = (it[0] as Transform3D).origin
			s.append("%s %.2f %.2f %.2f" % [key, o.x, o.z, (it[1] as Color).r])
	s.sort()
	return s


## Buildings, props and trash cans of a chunk, by position.
func _signature(chunk: CityChunk) -> Array:
	var out: Array = []
	for c in chunk.get_children():
		if c is Building or c is TrashCan:
			var p: Vector3 = (c as Node3D).position
			out.append("%s %.2f %.2f" % [c.get_class(), p.x, p.z])
	for r in chunk.prop_records:
		out.append("%s %s %.2f %.2f" % [r.kind, r.id, (r.position as Vector3).x, (r.position as Vector3).z])
	out.sort()
	return out
