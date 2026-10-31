extends RefCounted
## Shop fronts at arm's length (ShopfrontDress, the awnings' cloth in ShopfrontKit, the taped menu
## in building.gdshader; docs/HANDOFF.md "Shop fronts at arm's length"): checks for
## tests/smoke_test.gd. Loaded at run time, so it compiles after the autoloads. No shader runs
## under --headless: the shaders are held to their source, the meshes read back. Every building
## here is made and freed by the file itself.

var _t: Node


func run(t: Node, _city: Node3D) -> void:
	_t = t
	_the_shaders_carry_it()
	_awning_cloth()
	_shops_put_things_out()
	_nothing_else_moves()


func _the_shaders_carry_it() -> void:
	var why := ""
	var props := FileAccess.get_file_as_string("res://shaders/facade_street_props.gdshader")
	for k in range(10, 16):
		if props.find("kind < %d.5" % k) < 0 and k < 15:
			why += " the props shader has no kind %d" % k
	if ShopfrontDress.K_COIR != 10 or ShopfrontDress.K_GLAZE != 15 or FacadeStreet.K_STONE != 9:
		why += " the kinds moved"
	var kit := FileAccess.get_file_as_string("res://shaders/facade_kit.gdshaderinc")
	if kit.find("v_hem = COLOR.a;") < 0 or kit.find("(0.62 - v_hem) / 0.5") < 0:
		why += " facade_kit.gdshaderinc lost the valance"
	if not is_equal_approx(ShopfrontKit.VALANCE_TOP, 0.62) or not is_equal_approx(ShopfrontKit.VALANCE_TOP - ShopfrontKit.VALANCE_BOTTOM, 0.5):
		why += " the valance's alpha range is not the shader's"
	var bld := FileAccess.get_file_as_string("res://shaders/building.gdshader")
	if bld.find("bool menu_bay = (kind == 2u || kind == 3u) && shop_byte(shop, 58u) < 180u") < 0:
		why += " building.gdshader lost the taped menu"
	# Salts 58 and 59 are the menu's alone.
	for f: String in ["res://shaders/building.gdshader", "res://shaders/shop_interior.gdshaderinc", "res://shaders/facade_street.gdshaderinc", "res://shaders/building_lod.gdshader"]:
		var src := FileAccess.get_file_as_string(f)
		var n := src.count(", 58u)") + src.count(", 59u)")
		if f.ends_with("building.gdshader") and n != 3:
			why += " salts 58 / 59 used %d times in %s" % [n, f]
		elif not f.ends_with("building.gdshader") and n != 0:
			why += " salts 58 / 59 used in %s" % f
	_t._check(why == "", "storefront close-up: the shaders draw the mats, plants, menus, signs and valances%s" % why)


## The dome and roller awnings: a valance whose vertex alpha runs top to hem, interior columns
## the slice stretches, and canvas that sags off the straight line between its supports.
func _awning_cloth() -> void:
	var why := ""
	for piece: String in ["awning_dome", "awning_roller"]:
		var m := ShopfrontKit.mesh(piece) as ArrayMesh
		var hem := false
		var sag := false
		var inner := 0
		for si in m.get_surface_count():
			var arr := m.surface_get_arrays(si)
			var cols: PackedColorArray = arr[Mesh.ARRAY_COLOR]
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var uv2: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV2]
			for i in verts.size():
				if cols.size() > i and is_equal_approx(cols[i].a, ShopfrontKit.VALANCE_BOTTOM):
					hem = true
				if uv2.size() > i and int(uv2[i].y - 0.5) == ShopfrontKit.S and absf(verts[i].x) < 0.49 and absf(verts[i].x) > 0.01:
					inner += 1
			if piece == "awning_roller" and si == 0:
				# Mid-depth canvas points under the straight line from cassette to bar.
				for v in verts:
					var t := (v.z - 0.17) / (1.5 - 0.17)
					if t > 0.3 and t < 0.7 and v.y < lerpf(-0.14, -0.59, t) - 0.02:
						sag = true
		if piece == "awning_dome":
			sag = inner > 0
		if not hem or not sag or inner < 20:
			why += " %s: hem %s sag %s inner %d" % [piece, hem, sag, inner]
	_t._check(why == "", "storefront close-up: dome and roller awnings carry a scalloped valance and a sagging cloth%s" % why)


func _make(sd: int, finish: int) -> Building:
	var scene: PackedScene = load("res://scenes/props/building.tscn")
	var bld: Building = scene.instantiate()
	bld.seed = sd
	bld.lot_size = Vector2(26.0, 20.0)
	bld.min_height = 12.0
	bld.max_height = 18.0
	bld.shape_options.assign([Building.Shape.SLAB])
	bld.finish_options.assign([finish])
	bld.window_style_force = Building.WindowStyle.PUNCHED
	bld.allow_storefront = true
	return bld


## Kinds in a StreetDress (vertex alpha x 16), counted by vertex.
func _kinds(bld: Building) -> Dictionary:
	var out := {}
	var mi := bld.get_node_or_null("StreetDress") as MeshInstance3D
	if mi == null:
		return out
	var cols: PackedColorArray = (mi.mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	for c in cols:
		var k := int(floor(c.a * 16.0 + 0.5))
		out[k] = int(out.get(k, 0)) + 1
	return out


## Rows of shops: mats, planters, hanging signs and menu cases appear across a dozen buildings; the
## footprints are recorded and never overlap; everything stays at the ground floor, in the lot.
func _shops_put_things_out() -> void:
	if not ShopfrontDress.enabled or not FacadeStreet.enabled:
		_t._check(true, "storefront close-up: SHOPFRONT_DRESS=0, nothing to check")
		return
	var why := ""
	var seen := {}
	for i in 14:
		var bld := _make(5100 + i * 71, [Building.Finish.FLAT, Building.Finish.BRICK, Building.Finish.PANELS][i % 3])
		_t.add_child(bld)
		var k := _kinds(bld)
		for kind: int in k:
			seen[kind] = int(seen.get(kind, 0)) + int(k[kind])
		var spots: Array = bld.get_meta("sf_dress", [])
		for a in spots.size():
			var pa := Vector2(float(spots[a][0]), float(spots[a][1]))
			if absf(pa.x) > bld.lot_size.x * 0.5 + 1.6 or absf(pa.y) > bld.lot_size.y * 0.5 + 1.6:
				why += " seed %d: a spot at %s is off the lot" % [bld.seed, pa]
			for b in range(a + 1, spots.size()):
				var pb := Vector2(float(spots[b][0]), float(spots[b][1]))
				if pa.distance_to(pb) < (float(spots[a][2]) + float(spots[b][2])) * 0.85:
					why += " seed %d: two things at %s and %s" % [bld.seed, pa, pb]
		var mi := bld.get_node_or_null("StreetDress") as MeshInstance3D
		if mi:
			var verts: PackedVector3Array = (mi.mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
			var cols: PackedColorArray = (mi.mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_COLOR]
			for vi in verts.size():
				if int(floor(cols[vi].a * 16.0 + 0.5)) < ShopfrontDress.K_COIR:
					continue
				var p := verts[vi]
				if p.y < -0.01 or p.y > 4.2 or absf(p.x) > bld.lot_size.x * 0.5 + 1.8 or absf(p.z) > bld.lot_size.y * 0.5 + 1.8:
					why += " seed %d: a dress vertex at %s" % [bld.seed, p]
					break
		bld.free()
	for kind: int in [ShopfrontDress.K_COIR, ShopfrontDress.K_LEAF, ShopfrontDress.K_SOIL, ShopfrontDress.K_SIGN]:
		if int(seen.get(kind, 0)) == 0:
			why += " no kind %d on fourteen rows of shops" % kind
	_t._check(why == "", "storefront close-up: shops put out mats, planters and hanging signs, in their lots, never on top of each other%s" % why)


## The same building with the dress off and on: parts, colours, roof plant, kit pieces and shop
## names do not move; with it off, no dress kind is in the StreetDress.
func _nothing_else_moves() -> void:
	var why := ""
	var was := ShopfrontDress.enabled
	for i in 3:
		var sd := 6300 + i * 97
		var got: Array = []
		for on: bool in [false, true]:
			ShopfrontDress.enabled = on
			var bld := _make(sd, Building.Finish.FLAT if i < 2 else Building.Finish.BRICK)
			_t.add_child(bld)
			var parts: Array = []
			for part: Dictionary in bld.parts:
				parts.append([part.size, part.center])
			var k := _kinds(bld)
			var dressed := false
			for kind: int in k:
				if kind >= ShopfrontDress.K_COIR:
					dressed = true
			got.append([parts, bld.facade_color, bld.roof_props.size(), bld.shop_piece_count, bld.shop_names(2, 3), dressed])
			bld.free()
		ShopfrontDress.enabled = was
		for f in 5:
			if str(got[0][f]) != str(got[1][f]):
				why += " seed %d field %d: %s vs %s" % [sd, f, got[0][f], got[1][f]]
		if got[0][5]:
			why += " seed %d dressed with the dress off" % sd
	ShopfrontDress.enabled = was
	_t._check(why == "", "storefront close-up: the dress moves nothing a building already rolled%s" % why)
