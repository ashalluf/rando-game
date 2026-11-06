extends RefCounted
## Street trees close up (TreesCloseup, trees-closeup), for tests/smoke_test.gd. Loaded at run
## time, not named there, so it compiles after the autoloads.
##
## The gust field: GDScript's copy holds the include's numbers, stays in 0..1, is not flat, and a
## front travels downwind (a tree downwind sees what the one upwind saw, later). Every tree shader
## includes it and carries the `closeup` switch, the dither is Forward+ only and never in the
## shadow pass. The materials: every scanned street tree's leaf material is marked on with crown
## bounds inside its mesh's bounds, its wood carries the bark settings, the palm material and the
## LA trees' are marked, and with the switch off a fresh material is marked 0. Nothing about a
## mesh changes (bounds, surfaces, the foliage ladder flag), so the ladders' table still holds.
## No state is left behind: the switch is put back.

var _t: Node

const SHADERS := ["res://shaders/foliage_tex.gdshader", "res://shaders/foliage.gdshader", "res://shaders/la_tree.gdshader"]


func run(t: Node, _city: Node3D) -> void:
	_t = t
	if not TreesCloseup.enabled:
		_t._check(true, "TREES_CLOSEUP=0: the street trees close-up pass is off (the A/B)")
		return
	_gust()
	_shaders()
	_materials()
	_switch()


func _gust() -> void:
	var src := FileAccess.get_file_as_string("res://shaders/tree_wind.gdshaderinc")
	var want := {
		"TW_SPEED": TreesCloseup.TW_SPEED, "TW_LEN": TreesCloseup.TW_LEN,
		"TW_LEN2": TreesCloseup.TW_LEN2, "TW_RAGGED": TreesCloseup.TW_RAGGED,
	}
	var miss := ""
	for k: String in want:
		var re := RegEx.create_from_string("const float %s = ([0-9.]+);" % k)
		var m := re.search(src)
		if m == null or absf(m.get_string(1).to_float() - float(want[k])) > 1e-4:
			miss += " " + k
	var dre := RegEx.create_from_string("const vec2 TW_DIR = vec2\\(([0-9.]+), ([0-9.]+)\\);")
	var dm := dre.search(src)
	if dm == null or Vector2(dm.get_string(1).to_float(), dm.get_string(2).to_float()).distance_to(TreesCloseup.TW_DIR) > 1e-4:
		miss += " TW_DIR"
	_t._check(miss == "", "the tree gust field's numbers match tree_wind.gdshaderinc%s" % miss)
	# Range and shape, over a street and a minute.
	var lo := 1.0
	var hi := 0.0
	for i in 400:
		var p := Vector2(fmod(i * 37.3, 900.0) - 450.0, fmod(i * 91.7, 700.0) - 350.0)
		var g := TreesCloseup.gust(p, i * 0.15)
		lo = minf(lo, g)
		hi = maxf(hi, g)
	_t._check(lo >= 0.0 and hi <= 1.0 and hi - lo > 0.6, "the tree gust runs 0..1 with real fronts and lulls (%.2f..%.2f)" % [lo, hi])
	# A front travels: a tree 30 m downwind sees, 30 / TW_SPEED seconds later, nearly what the
	# upwind one saw (the ragged term drifts a little); a tree 30 m ACROSS the wind does not keep
	# step with it in the same way.
	var d := TreesCloseup.wind_dir()
	var moved := 0.0
	var still := 0.0
	for i in 60:
		var p := Vector2(120.0 + i * 3.1, -40.0 + i * 1.7)
		var t0 := 10.0 + i * 0.7
		var a := TreesCloseup.gust(p, t0)
		moved += absf(a - TreesCloseup.gust(p + d * 30.0, t0 + 30.0 / TreesCloseup.TW_SPEED))
		still += absf(a - TreesCloseup.gust(p + d * 30.0, t0))
	moved /= 60.0
	still /= 60.0
	_t._check(moved < 0.06 and moved < still * 0.35,
		"a gust front travels downwind tree to tree (mean mismatch %.3f riding the front, %.3f at one instant)" % [moved, still])
	var lean := Vector2(-0.6, -0.4)
	_t._check(TreesCloseup.wind_dir(lean).is_equal_approx(lean.normalized()), "a steady wind (the Santa Ana's lean) turns the gusts with it")


func _shaders() -> void:
	var bad := ""
	for p: String in SHADERS:
		var src := FileAccess.get_file_as_string(p)
		var sh: Shader = load(p)
		var names := {}
		for u: Dictionary in sh.get_shader_uniform_list():
			names[u.name] = true
		if not src.contains("tree_wind.gdshaderinc") or not src.contains("tw_gust(") or not names.has("closeup"):
			bad += " " + p.get_file()
	_t._check(bad == "", "every tree shader reads the shared gust field and has the close-up switch%s" % bad)
	var ft := FileAccess.get_file_as_string("res://shaders/foliage_tex.gdshader")
	var at := ft.find("#if CURRENT_RENDERER == RENDERER_FORWARD_PLUS")
	var dith := ft.find("edge_dither * far_px")
	var end := ft.find("#endif", at)
	_t._check(at >= 0 and dith > at and end > dith and ft.contains("!IN_SHADOW_PASS"),
		"the leaf edge dither is Forward+ only (TAA resolves it) and never in the shadow pass")
	var sh2: Shader = load("res://shaders/foliage_tex.gdshader")
	var crown := 0
	for u: Dictionary in sh2.get_shader_uniform_list():
		if u.name in ["crown_center", "crown_radius", "inner_shade", "sun_side", "gust_push"]:
			crown += 1
	_t._check(crown == 5, "the scanned trees' crown light and gust uniforms are on foliage_tex (%d of 5)" % crown)


func _materials() -> void:
	var bad := ""
	var bark := ""
	for i in PropFactory.CITY_TREES.size():
		var m: Mesh = PropFactory.model_tree(i)
		var box := m.get_aabb()
		var leaves := 0
		for s in m.get_surface_count():
			var mat := m.surface_get_material(s)
			if mat is ShaderMaterial and (mat as ShaderMaterial).shader.resource_path.ends_with("foliage_tex.gdshader"):
				leaves += 1
				var sm := mat as ShaderMaterial
				var c: Vector3 = sm.get_shader_parameter("crown_center")
				var r: Vector3 = sm.get_shader_parameter("crown_radius")
				var on := float(sm.get_shader_parameter("closeup")) > 0.5
				if not on or r.x <= 0.0 or r.y <= 0.0 or not box.grow(0.01).has_point(c) or c.y < box.get_center().y:
					bad += " %s" % PropFactory.CITY_TREES[i]
			elif mat is StandardMaterial3D:
				var st := mat as StandardMaterial3D
				if st.roughness_texture != null and not st.ao_enabled:
					bark += " %s/%s" % [PropFactory.CITY_TREES[i], st.resource_name]
		if leaves == 0 or not m.has_meta("foliage_ladder") and PropFactory.foliage_ladders:
			bad += " %s(no leaves or ladder)" % PropFactory.CITY_TREES[i]
	_t._check(bad == "", "every street tree's leaves are marked close up with crown bounds in the crown%s" % bad)
	_t._check(bark == "", "every street tree's bark reads its occlusion map%s" % bark)
	var palm := PropFactory.foliage_material()
	var la := LaTrees.material(LaTrees.Species.FIG)
	_t._check(float(palm.get_shader_parameter("closeup")) > 0.5 and float(la.get_shader_parameter("closeup")) > 0.5,
		"the palms' and the LA trees' materials are marked close up")
	# The meshes are untouched: dress() again changes neither the bounds nor the surfaces.
	var m0: Mesh = PropFactory.model_tree(0)
	var b0 := m0.get_aabb()
	var n0 := m0.get_surface_count()
	TreesCloseup.dress(m0)
	_t._check(m0.get_aabb().is_equal_approx(b0) and m0.get_surface_count() == n0, "dressing a tree leaves its mesh (and the foliage ladders' table) as it was")


func _switch() -> void:
	var was := TreesCloseup.enabled
	TreesCloseup.enabled = false
	var off := ShaderMaterial.new()
	off.shader = load("res://shaders/foliage_tex.gdshader")
	TreesCloseup.mark(off)
	TreesCloseup.enabled = true
	var on := ShaderMaterial.new()
	on.shader = off.shader
	TreesCloseup.mark(on)
	TreesCloseup.enabled = was
	_t._check(float(off.get_shader_parameter("closeup")) == 0.0 and float(on.get_shader_parameter("closeup")) == 1.0,
		"TREES_CLOSEUP=0 marks the tree materials off (the A/B)")
	# set_all(): the whole pass flipped on every material made so far (still_shot.gd TREES_AB), bark
	# included, then put back.
	var palm := PropFactory.foliage_material()
	var bark: StandardMaterial3D = null
	var m0: Mesh = PropFactory.model_tree(0)
	for s in m0.get_surface_count():
		if m0.surface_get_material(s) is StandardMaterial3D:
			bark = m0.surface_get_material(s)
			break
	TreesCloseup.set_all(false)
	var off_ok := float(palm.get_shader_parameter("closeup")) == 0.0 and (bark == null or not bark.has_meta("trees_closeup_was") or bark.ao_enabled == bool((bark.get_meta("trees_closeup_was") as Array)[1]))
	TreesCloseup.set_all(true)
	var on_ok := float(palm.get_shader_parameter("closeup")) == 1.0 and (bark == null or bark.ao_enabled)
	_t._check(off_ok and on_ok, "TreesCloseup.set_all() flips every tree material and the bark, and back")
