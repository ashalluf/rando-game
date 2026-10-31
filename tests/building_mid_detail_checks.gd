extends RefCounted
## The facade from 20-80 m (FacadeMid, shaders/facade_mid.gdshader, docs/HANDOFF.md "Buildings at
## mid distance"): checks for tests/smoke_test.gd. Loaded at run time, so it compiles after the
## autoloads. No shader runs under --headless, so these are about what is built: the dressing is one
## mesh inside its lot, balconies get furnished, residential walls get their hardware, and turning
## it on moves nothing a building already rolled. Every building here is made and freed by the file.

var _t: Node


func run(t: Node, _city: Node3D) -> void:
	_t = t
	_the_shader()
	_apartments_get_dressed()
	_glass_towers_stay_plain()
	_nothing_else_moves()


func _the_shader() -> void:
	var why := ""
	var src := FileAccess.get_file_as_string("res://shaders/facade_mid.gdshader")
	if src.find("cs_srgb_to_linear(COLOR.rgb)") < 0 or src.find("kind = floor(COLOR.a * 16.0 + 0.5);") < 0:
		why += " the vertex decode"
	if src.find("#include \"res://shaders/color_space.gdshaderinc\"") < 0 or src.find("ALBEDO = cs_out(c);") < 0:
		why += " the colour space"
	if src.find("uniform sampler2D") >= 0 or src.find("instance uniform") >= 0:
		why += " a sampler or an instance uniform"
	if FacadeMid.K_SOIL >= 16:
		why += " more kinds than the alpha holds"
	_t._check(why == "", "mid detail: facade_mid.gdshader decodes its vertex colours in linear on both renderers%s" % why)


func _make(sd: int, finish: int, style: int, shops: bool) -> Building:
	var scene: PackedScene = load("res://scenes/props/building.tscn")
	var bld: Building = scene.instantiate()
	bld.seed = sd
	bld.lot_size = Vector2(24.0, 20.0)
	bld.min_height = 12.0
	bld.max_height = 20.0
	bld.shape_options.assign([Building.Shape.SLAB])
	bld.finish_options.assign([finish])
	bld.window_style_force = style
	bld.allow_storefront = shops
	return bld


## What a building's MidDress holds: "" or why it is wrong, and its triangle count in `out[0]`.
func _dress(bld: Building, out: Array) -> String:
	out[0] = 0
	var why := ""
	for node_name: String in ["MidDress", "MidDressNear"]:
		var got := [0]
		why += _dress_one(bld, bld.get_node_or_null(node_name) as MeshInstance3D, got)
		out[0] = int(out[0]) + int(got[0])
	return why


func _dress_one(bld: Building, mi: MeshInstance3D, out: Array) -> String:
	if mi == null:
		return ""
	var arrays := (mi.mesh as ArrayMesh).surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	out[0] = idx.size() / 3
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	for p in verts:
		if not (is_finite(p.x) and is_finite(p.y) and is_finite(p.z)):
			return " a vertex is not finite"
		lo = lo.min(p)
		hi = hi.max(p)
	var half := Vector3(bld.lot_size.x * 0.5 + 2.2, 0.0, bld.lot_size.y * 0.5 + 2.2)
	if lo.x < -half.x or lo.z < -half.z or hi.x > half.x or hi.z > half.z or lo.y < -0.05 or hi.y > bld.height + 2.0:
		return " MidDress spans %s .. %s" % [lo, hi]
	if idx.size() / 3 > 30000:
		return " MidDress is %d triangles" % (idx.size() / 3)
	if mi.material_override != FacadeMid.material() or mi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF \
			or mi.visibility_range_end <= 0.0 or mi.visibility_range_end > 200.0:
		return " MidDress material / shadow / range"
	return ""


## Punched-window rendered and brick blocks: most of them get a MidDress, all of it in the lot, and
## somewhere among them balcony life and wall hardware.
func _apartments_get_dressed() -> void:
	if not FacadeMid.enabled:
		_t._check(true, "mid detail: FACADE_MID=0, nothing to check")
		return
	var why := ""
	var dressed := 0
	var tris := 0
	var most := 0
	for i in 12:
		var bld := _make(5300 + i * 41, [Building.Finish.FLAT, Building.Finish.BRICK][i % 2], Building.WindowStyle.PUNCHED, i % 3 == 0)
		_t.add_child(bld)
		var out := [0]
		why += _dress(bld, out)
		if int(out[0]) > 0:
			dressed += 1
		tris += int(out[0])
		most = maxi(most, int(out[0]))
		bld.free()
	if dressed < 8:
		why += " only %d of 12 apartment blocks dressed" % dressed
	_t._check(why == "", "mid detail: apartment blocks are dressed, inside their lots (%d of 12, %d triangles, most %d)%s" % [dressed, tris, most, why])


## A curtain-wall tower carries no balcony life, no sleeve ACs and no painted name: at most the
## flashing on a roof edge with no parapet.
func _glass_towers_stay_plain() -> void:
	if not FacadeMid.enabled:
		return
	var why := ""
	for i in 4:
		var bld := _make(6100 + i * 13, Building.Finish.GLASS, Building.WindowStyle.CURTAIN, false)
		_t.add_child(bld)
		var out := [0]
		why += _dress(bld, out)
		if int(out[0]) > 400:
			why += " seed %d: %d triangles on a glass tower" % [bld.seed, out[0]]
		bld.free()
	_t._check(why == "", "mid detail: a curtain-wall tower stays plain%s" % why)


## The same building with the pass off and on: parts, colours, roof plant, shop names and its other
## nodes' counts are the same (the pass rolls only hashes); only MidDress (and our fire escapes in
## the kit batch) is new.
func _nothing_else_moves() -> void:
	var why := ""
	var was := FacadeMid.enabled
	for i in 6:
		var sd := 7300 + i * 77
		var got: Array = []
		for on: bool in [false, true]:
			FacadeMid.enabled = on
			var bld := _make(sd, Building.Finish.FLAT if i < 3 else Building.Finish.BRICK, Building.WindowStyle.PUNCHED, i % 2 == 0)
			_t.add_child(bld)
			var parts: Array = []
			for part: Dictionary in bld.parts:
				parts.append([part.size, part.center])
			var details := ""
			for name: String in ["Details", "Frames", "Balconies", "Bays", "StreetDress"]:
				var node := bld.get_node_or_null(name)
				if node is MultiMeshInstance3D:
					details += "%s:%d " % [name, (node as MultiMeshInstance3D).multimesh.instance_count]
				elif node is MeshInstance3D:
					details += "%s:%d " % [name, (node as MeshInstance3D).mesh.get_faces().size()]
			got.append([parts, bld.facade_color, bld.roof_props.size(), bld.shop_piece_count, details,
				bld.shop_names(2, 3), bld.get_node_or_null("MidDress") != null or bld.get_node_or_null("MidDressNear") != null])
			bld.free()
		FacadeMid.enabled = was
		for k in 6:
			if str(got[0][k]) != str(got[1][k]):
				why += " seed %d field %d: %s vs %s" % [sd, k, got[0][k], got[1][k]]
		if got[0][6]:
			why += " seed %d dressed with the pass off" % sd
	FacadeMid.enabled = was
	_t._check(why == "", "mid detail: turning the pass on moves nothing a building already rolled%s" % why)
