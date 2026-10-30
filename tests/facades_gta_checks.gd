extends RefCounted
## The facade pass (FacadeVariety, shaders/facade_variety.gdshaderinc, docs/HANDOFF.md "Facades
## that read as built"): checks for tests/smoke_test.gd. Loaded at run time, so it compiles after
## the autoloads. No shader runs under --headless, so the GDScript copies are held to the shader
## source and to known hash values; tools/glshot/far_building_shot.gd (CAM_POS) shows the pixels.

var _t: Node


func run(t: Node, _city: Node3D) -> void:
	_t = t
	_system_matches_the_shader()
	_bevel_is_a_clean_prism()
	_buildings_wear_it()
	_both_shaders_share_it()


## fx_system() and FacadeVariety.system(): the same hash (salt 70), the same thresholds, values
## worked out by hand (tools: a Python copy of wl_hash), and a sane share of each system.
func _system_matches_the_shader() -> void:
	var why := ""
	var known := {101: 0, 138: 1, 175: 0, 212: 1, 249: 0, 286: 0}
	for sd: int in known:
		var got := FacadeVariety.system(sd, Building.WindowStyle.CURTAIN)
		if got != int(known[sd]):
			why += " seed %d: %d, want %d" % [sd, got, known[sd]]
	var counts := [0, 0, 0]
	for sd in 1000:
		counts[FacadeVariety.system(sd, Building.WindowStyle.CURTAIN)] += 1
		if FacadeVariety.system(sd, Building.WindowStyle.PUNCHED) != 0:
			why += " a punched wall has a system"
			break
	if counts[0] < 430 or counts[0] > 570 or counts[1] < 200 or counts[2] < 180:
		why += " shares %s" % [counts]
	var src := FileAccess.get_file_as_string("res://shaders/facade_variety.gdshaderinc")
	for want: String in ["wl_roll(uint(clamp(b_seed, 0.0, 999.0) + 0.5), 70u)", "k < 0.5 ? 0 : (k < 0.76 ? 1 : 2)"]:
		if src.find(want) < 0:
			why += " the include lost '%s'" % want
	_t._check(why == "", "a curtain wall's facade system (flush, fins, slab bands) is rolled the way the shaders roll it%s" % why)


## The pencil-round corners: eight walls, every wall vertical with a unit normal, inside the box,
## the corners cut by the bevel; never on a small part, and on a part with shops inside the first
## bay's frame.
func _bevel_is_a_clean_prism() -> void:
	var why := ""
	var size := Vector3(30.0, 60.0, 24.0)
	var b := 0.22
	var arrays := Building._bevel_arrays(size, b)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var tans: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT]
	if verts.size() != 8 * 6 + 6 * 3 * 2 or norms.size() != verts.size() or tans.size() != verts.size() * 4:
		why += " %d vertices" % verts.size()
	var diag := 0
	for i in verts.size():
		var v := verts[i]
		if absf(v.x) > size.x * 0.5 + 1e-4 or absf(v.y) > size.y * 0.5 + 1e-4 or absf(v.z) > size.z * 0.5 + 1e-4:
			why += " vertex %s outside" % v
			break
		if absf(norms[i].length() - 1.0) > 1e-3:
			why += " normal %s" % norms[i]
			break
		if absf(norms[i].x) > 0.35 and absf(norms[i].z) > 0.35:
			diag += 1
		if absf(v.x) > size.x * 0.5 - b + 1e-3 and absf(v.z) > size.z * 0.5 - b + 1e-3:
			why += " a corner %s was not cut" % v
			break
	# Four diagonal walls of six vertices: the shader's solid corner pier.
	if diag != 24:
		why += " %d diagonal-wall vertices" % diag
	if FacadeVariety.enabled:
		if FacadeVariety.bevel(Vector3(4.0, 20.0, 12.0), 2.5, false) != 0.0:
			why += " a narrow part was bevelled"
		var shop := FacadeVariety.bevel(Vector3(30.0, 20.0, 30.0), 2.4, true)
		if shop > 2.4 * 0.05:
			why += " a shop part's bevel %.3f cuts its glass" % shop
	_t._check(why == "", "bevelled corners are eight clean walls inside the box, never into a shop's glass%s" % why)


## A Building's walls carry the pass and know where the kit's caps stand; its collision is still the box.
func _buildings_wear_it() -> void:
	var why := ""
	var scene: PackedScene = load("res://scenes/props/building.tscn")
	var curtain_seen := false
	for i in 10:
		var bld: Building = scene.instantiate()
		bld.seed = 5300 + i * 61
		bld.lot_size = Vector2(32.0, 30.0)
		bld.min_height = 40.0
		bld.max_height = 90.0
		bld.finish_options.assign([Building.Finish.GLASS if i % 2 == 0 else Building.Finish.PANELS])
		_t.add_child(bld)
		var walls := bld.get_node_or_null("Walls") as MeshInstance3D
		if walls == null or not (walls.material_override is ShaderMaterial):
			why += " seed %d has no walls" % bld.seed
		else:
			var mat := walls.material_override as ShaderMaterial
			if bool(mat.get_shader_parameter("facade_variety")) != FacadeVariety.enabled:
				why += " seed %d facade_variety" % bld.seed
			var caps := float(mat.get_shader_parameter("caps_real_until"))
			var want := bld.kit_mullion_distance if (Building.kit_enabled and ShopfrontKit.enabled and bld.window_style == Building.WindowStyle.CURTAIN) else 0.0
			if not is_equal_approx(caps, want):
				why += " seed %d caps_real_until %.0f, want %.0f" % [bld.seed, caps, want]
			curtain_seen = curtain_seen or bld.window_style == Building.WindowStyle.CURTAIN
		for c in bld.get_children():
			if c is CollisionShape3D and not ((c as CollisionShape3D).shape is BoxShape3D or (c as CollisionShape3D).shape is ConvexPolygonShape3D):
				why += " seed %d collision %s" % [bld.seed, (c as CollisionShape3D).shape]
		bld.free()
	if not curtain_seen:
		why += " no curtain wall among them"
	_t._check(why == "", "buildings wear the facade pass and hand the caps' depth to the kit near the camera%s" % why)


## Both shaders include the pass, the far material switches it with the near one.
func _both_shaders_share_it() -> void:
	var why := ""
	for p: String in ["res://shaders/building.gdshader", "res://shaders/building_lod.gdshader"]:
		var src := FileAccess.get_file_as_string(p)
		if src.find("#include \"res://shaders/facade_variety.gdshaderinc\"") < 0:
			why += " %s lost the include" % p.get_file()
		for f: String in ["fx_pane(", "fx_opposite(", "fx_member(", "fx_roof_drip("]:
			if src.find(f) < 0:
				why += " %s does not call %s" % [p.get_file(), f]
	for far: bool in [false, true]:
		var m := PropFactory.building_lod_material(far)
		if bool(m.get_shader_parameter("facade_variety")) != FacadeVariety.enabled:
			why += " far material %s" % far
	_t._check(why == "", "the near walls and the far boxes draw the same facade pass%s" % why)
