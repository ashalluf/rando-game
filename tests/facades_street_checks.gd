extends RefCounted
## The street level up close (FacadeStreet, shaders/facade_street.gdshaderinc, docs/HANDOFF.md "The
## street level up close"): checks for tests/smoke_test.gd. Loaded at run time, so it compiles after
## the autoloads. No shader runs under --headless, so the GDScript copies of the integer rolls are
## held to the shader source and to values worked out by hand; the stills show the pixels
## (tools/facades_street/shots.sh). Every building here is made and freed by the file itself.

var _t: Node


func run(t: Node, _city: Node3D) -> void:
	_t = t
	_rolls_match_the_shader()
	_the_shader_wears_it()
	_a_wall_without_shops()
	_a_row_of_shops()
	_nothing_else_moves()


## The door's bay, the lamp's kind and whether it is lit: the shader's integers, bit for bit (values
## from a Python copy of wl_hash), and a sane share of walls with a door.
func _rolls_match_the_shader() -> void:
	var why := ""
	# [shader seed, face, wall length, bays, key, door bay, lamp kind, lit]
	var known := [[7, 1, 18.0, 6, 233544, 3, 1, true], [123, 3, 24.5, 9, 4042850, 6, 2, true],
		[999, 4, 12.4, 5, 32751666, 3, 1, true], [500, 2, 30.0, 12, 16392312, -1, 1, false],
		[42, 1, 9.6, 4, 1380390, 1, 0, true], [311, 2, 15.25, 6, 10199101, 2, 0, true]]
	for k: Array in known:
		var key := FacadeStreet.face_key(k[0], k[1], k[2])
		if key != int(k[4]):
			why += " key %d, want %d" % [key, k[4]]
		if FacadeStreet.door_col(key, k[3]) != int(k[5]):
			why += " door %d, want %d" % [FacadeStreet.door_col(key, k[3]), k[5]]
		if FacadeStreet.lamp_kind(key) != int(k[6]) or FacadeStreet.lamp_lit(key) != bool(k[7]):
			why += " lamp of key %d" % key
	var doors := 0
	var walls := 0
	for sd in 400:
		for f in range(1, 5):
			var cols := 3 + (sd + f) % 9
			var d := FacadeStreet.door_col(FacadeStreet.face_key(sd, f, 6.0 + float(sd % 23) * 1.25), cols)
			walls += 1
			if d >= 0:
				doors += 1
				if d < 1 or d > cols - 2:
					why += " a door in an end bay"
					break
	var share := float(doors) / float(walls)
	if share < 0.55 or share > 0.70:
		why += " door share %.2f" % share
	if FacadeStreet.door_col(FacadeStreet.face_key(7, 1, 18.0), 2) != -1:
		why += " a two-bay wall has a door"
	var size := FacadeStreet.door_size(2.6, 3.4, 0.0)
	if not size.is_equal_approx(Vector2(1.05, 2.22)) or FacadeStreet.door_size(1.5, 3.1, 0.64).y > 2.02 \
			or FacadeStreet.door_sill(Building.Finish.BRICK) != 0.64 or FacadeStreet.door_sill(Building.Finish.GLASS) != 0.0:
		why += " door size %s" % size
	_t._check(why == "", "street level: the door's bay and its lamp are rolled the way the shader rolls them%s" % why)


## building.gdshader includes the pass and calls it where it must; the include's integer rolls are
## the ones FacadeStreet copies; the props shader decodes its vertex colours.
func _the_shader_wears_it() -> void:
	var why := ""
	var src := FileAccess.get_file_as_string("res://shaders/building.gdshader")
	if src.find("#include \"res://shaders/facade_street.gdshaderinc\"") < 0:
		why += " building.gdshader lost the include"
	for f: String in ["fs_door_col(", "fs_door(", "fs_plinth(", "fs_slope(", "fs_patch(", "fs_crack(", "fs_lamp_wash(", "shop_byte(shop_key, 46u) < 96u"]:
		if src.find(f) < 0:
			why += " building.gdshader does not call %s" % f
	var inc := FileAccess.get_file_as_string("res://shaders/facade_street.gdshaderinc")
	for want: String in ["uint sd = uint(clamp(abs(b_seed), 0.0, 999.0) + 0.5);", "uint l = uint(floor(face_len * 4.0 + 0.5)) & 4095u;",
			"return (sd * 8u + f) * 4096u + l;", "if ((wl_hash(key, 90u) >> 24u) >= 160u)", "return 1 + int(wl_hash(key, 91u) % uint(cols - 2.0 + 0.5));",
			"return vec2(clamp(pitch * 0.55, 0.92, 1.05), min(2.22, fl - sill - 0.45));", "return finish == 3 ? 0.0 : 0.64;", "return wl_hash(key, 93u) % 3u;", "return (wl_hash(key, 98u) >> 24u) < 216u;"]:
		if inc.find(want) < 0:
			why += " the include lost '%s'" % want
	if FacadeStreet.SALT_GOOSE != 46 or FacadeStreet.GOOSE_BYTE != 96:
		why += " the gooseneck roll moved"
	var props := FileAccess.get_file_as_string("res://shaders/facade_street_props.gdshader")
	if props.find("cs_srgb_to_linear(COLOR.rgb)") < 0 or props.find("kind = floor(COLOR.a * 16.0 + 0.5);") < 0:
		why += " the props shader's vertex decode"
	_t._check(why == "", "street level: building.gdshader draws the pass with the integer rolls FacadeStreet copies%s" % why)


func _make(sd: int, shops: bool, finish: int) -> Building:
	var scene: PackedScene = load("res://scenes/props/building.tscn")
	var bld: Building = scene.instantiate()
	bld.seed = sd
	bld.lot_size = Vector2(22.0, 18.0)
	bld.min_height = 9.0 if not shops else 12.0
	bld.max_height = 14.0 if not shops else 18.0
	bld.shape_options.assign([Building.Shape.SLAB])
	bld.finish_options.assign([finish])
	bld.window_style_force = Building.WindowStyle.PUNCHED
	bld.allow_storefront = shops
	return bld


## Every vertex of a StreetDress: inside the building's lot (plus a hand off the wall), above its foot.
func _dress_bounds(bld: Building) -> String:
	var mi := bld.get_node_or_null("StreetDress") as MeshInstance3D
	if mi == null:
		return " no StreetDress"
	var verts: PackedVector3Array = (mi.mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	for p in verts:
		lo = lo.min(p)
		hi = hi.max(p)
	var half := Vector3(bld.lot_size.x * 0.5 + 1.0, 0.0, bld.lot_size.y * 0.5 + 1.0)
	if lo.x < -half.x or lo.z < -half.z or hi.x > half.x or hi.z > half.z or lo.y < -0.01 or hi.y > bld.height + 1.0:
		return " StreetDress spans %s .. %s" % [lo, hi]
	if verts.size() / 4 * 2 > 9000:
		return " StreetDress is %d triangles" % (verts.size() / 2)
	if mi.material_override != FacadeStreet.material() or mi.visibility_range_end <= 0.0:
		return " StreetDress material / range"
	return ""


## A low building with no shops: its material carries the pass, a door stands where the roll says,
## the window frames leave that bay, and its hardware is one mesh inside the lot.
func _a_wall_without_shops() -> void:
	if not FacadeStreet.enabled:
		_t._check(true, "street level: FACADES_STREET=0, no hardware to check")
		return
	var why := ""
	var doors := 0
	for i in 6:
		var bld := _make(8800 + i * 37, false, [Building.Finish.FLAT, Building.Finish.BRICK, Building.Finish.PANELS][i % 3])
		_t.add_child(bld)
		var walls := bld.get_node_or_null("Walls") as MeshInstance3D
		var mat := walls.material_override as ShaderMaterial if walls else null
		if mat == null or not bool(mat.get_shader_parameter("facade_street")) or not is_equal_approx(float(mat.get_shader_parameter("street_ground_y")), bld.position.y):
			why += " seed %d's walls" % bld.seed
		for part: Dictionary in bld.parts:
			var size: Vector3 = part.size
			var bottom: float = (part.center as Vector3).y - size.y * 0.5
			for fi in 4:
				var size_u: float = size.z if fi < 2 else size.x
				var pitch: float = part.pitch_z if fi < 2 else part.pitch_x
				var cols := roundi(size_u / pitch)
				var d := FacadeStreet.door_for(bld, fi + 1, size_u, cols, bottom, 0.0, pitch, part.floor_h)
				if d >= 0:
					doors += 1
		why += _dress_bounds(bld)
		bld.free()
	if doors == 0:
		why += " no doors on six walls-without-shops buildings"
	_t._check(why == "", "street level: a ground floor without shops gets its door, lamp and step, and its hardware stays in its lot%s" % why)


## A row of shops: goosenecks over the boards the roll picks, a StreetDress inside the lot; no door
## is drawn in a storefront.
func _a_row_of_shops() -> void:
	if not FacadeStreet.enabled:
		return
	var why := ""
	var goose := 0
	for i in 6:
		var bld := _make(9100 + i * 53, true, [Building.Finish.FLAT, Building.Finish.BRICK][i % 2])
		_t.add_child(bld)
		for part: Dictionary in bld.parts:
			if not bool(part.storefront):
				continue
			var size: Vector3 = part.size
			var pitch: float = part.pitch_x
			if FacadeStreet.door_for(bld, 3, size.x, roundi(size.x / pitch), 0.0, 4.5, pitch, part.floor_h) != -1:
				why += " a storefront has a door"
			for run in 4:
				if Building.shop_byte(bld.shop_key(3, run), FacadeStreet.SALT_GOOSE) < FacadeStreet.GOOSE_BYTE:
					goose += 1
		why += _dress_bounds(bld)
		bld.free()
	if goose == 0:
		why += " no gooseneck rolled on six rows of shops"
	_t._check(why == "", "street level: shops get their goosenecks, meters and housings, inside the lot%s" % why)


## The same building with the pass off and on: its parts, colours, roof plant, shop names and kit
## pieces are the same (the pass rolls only hashes), the walls the only material that changes.
func _nothing_else_moves() -> void:
	var why := ""
	var was := FacadeStreet.enabled
	for i in 4:
		var sd := 7700 + i * 91
		var shops := i % 2 == 0
		var got: Array = []
		for on: bool in [false, true]:
			FacadeStreet.enabled = on
			var bld := _make(sd, shops, Building.Finish.FLAT if i < 2 else Building.Finish.BRICK)
			_t.add_child(bld)
			var parts: Array = []
			for part: Dictionary in bld.parts:
				parts.append([part.size, part.center])
			got.append([parts, bld.facade_color, bld.roof_props.size(), bld.shop_piece_count, bld.cap_piece_count,
				bld.get_node_or_null("StreetDress") != null, bld.shop_names(2, 3)])
			bld.free()
		FacadeStreet.enabled = was
		for k in 5:
			if str(got[0][k]) != str(got[1][k]):
				why += " seed %d field %d: %s vs %s" % [sd, k, got[0][k], got[1][k]]
		if str(got[0][6]) != str(got[1][6]):
			why += " seed %d's shop names moved" % sd
		if got[0][5]:
			why += " seed %d dressed with the pass off" % sd
	FacadeStreet.enabled = was
	_t._check(why == "", "street level: turning the pass on moves nothing a building already rolled%s" % why)
