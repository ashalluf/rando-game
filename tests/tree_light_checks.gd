extends RefCounted
## Trees under light (TreeLight, tree-light-2), for tests/smoke_test.gd. Loaded at run time, not
## named there, so it compiles after the autoloads.
##
## The weighted sway: GDScript's copy holds the include's numbers; a tall tree sways slower than a
## small one; the crown answers a gust late (the load peaks after the gust) and swings back past
## upright as it drops. Every tree shader includes tree_light.gdshaderinc and carries the switch,
## the shadow slack only in an orthographic (directional shadow) pass, the light through the crown
## never in the shadow pass, foliage_tex keeps the rounded normal on both faces. The materials:
## every scanned tree's leaves get a sway height from their mesh, the palms and the LA trees are
## marked, TREE_LIGHT=0 marks a fresh material off. The sun's light for the crowns is the sun's
## colour times its energy and 0 under the horizon. No mesh changes; nothing is left changed.

var _t: Node

const SHADERS := ["res://shaders/foliage_tex.gdshader", "res://shaders/foliage.gdshader", "res://shaders/la_tree.gdshader"]


func run(t: Node, _city: Node3D) -> void:
	_t = t
	if not TreeLight.enabled:
		_t._check(true, "TREE_LIGHT=0: the trees-under-light pass is off (the A/B)")
		return
	_numbers()
	_weight()
	_shaders()
	_materials()
	_sun()
	_switch()


func _numbers() -> void:
	var src := FileAccess.get_file_as_string("res://shaders/tree_light.gdshaderinc")
	var want := [
		"sqrt(%.1f / max(height_m, 1.0)), %.1f, %.1f" % [TreeLight.RATE_REF, TreeLight.RATE_MIN, TreeLight.RATE_MAX],
		"%.2f + height_m * %.2f, %.1f, %.1f" % [TreeLight.LAG_BASE, TreeLight.LAG_PER_M, TreeLight.LAG_MIN, TreeLight.LAG_MAX],
		"g0 + %.1f * (g0 - g1), -0.35, 1.3" % TreeLight.SWING_BACK,
		"t - lag * 2.2",
	]
	var miss := ""
	for w: String in want:
		if not src.contains(w):
			miss += " [" + w + "]"
	_t._check(miss == "", "the weighted sway's numbers match tree_light.gdshaderinc%s" % miss)


func _weight() -> void:
	_t._check(TreeLight.rate(20.0) < TreeLight.rate(10.0) and TreeLight.rate(10.0) < TreeLight.rate(4.0)
		and TreeLight.rate(10.0) == 1.0, "a tall tree sways slower than a small one (20 m %.2f, 10 m %.2f, 4 m %.2f)" % [TreeLight.rate(20.0), TreeLight.rate(10.0), TreeLight.rate(4.0)])
	# The crown's load against the gust over a few minutes at one tree: it lags (the best match
	# is the gust delayed), and it swings back past upright (negative) while gusts drop.
	var p := Vector2(140.0, -60.0)
	var h := 12.0
	var best_shift := 0.0
	var best := INF
	for k in 9:
		var shift := k * 0.25
		var err := 0.0
		for i in 400:
			var tt := 20.0 + i * 0.37
			err += absf(TreeLight.load_of(p, tt, h) - TreesCloseup.gust(p, tt - shift))
		if err < best:
			best = err
			best_shift = shift
	var neg := 0
	var top := 0.0
	for i in 2000:
		var l := TreeLight.load_of(p, i * 0.11, h)
		if l < -0.02:
			neg += 1
		top = maxf(top, l)
	_t._check(best_shift >= TreeLight.lag(h) * 0.5, "a crown answers a gust late (best match %.2f s behind the gust, lag %.2f)" % [best_shift, TreeLight.lag(h)])
	_t._check(neg > 40 and top <= 1.3, "a crown swings back past upright as a gust drops (%d of 2000 samples, top %.2f)" % [neg, top])


func _shaders() -> void:
	var bad := ""
	for p: String in SHADERS:
		var src := FileAccess.get_file_as_string(p)
		var sh: Shader = load(p)
		var names := {}
		for u: Dictionary in sh.get_shader_uniform_list():
			names[u.name] = true
		if not src.contains("tree_light.gdshaderinc") or not names.has("tree_light") or not names.has("self_shadow_slack") \
				or not names.has("sway_height") or not src.contains("tl_load(") or not src.contains("PROJECTION_MATRIX[3][3] > 0.5") \
				or not src.contains("!IN_SHADOW_PASS"):
			bad += " " + p.get_file()
	_t._check(bad == "", "every tree shader has the weighted sway, the shadow slack (directional pass only) and the light through the crown%s" % bad)
	var ft := FileAccess.get_file_as_string("res://shaders/foliage_tex.gdshader")
	_t._check(ft.contains("tree_light > 0.5 && closeup > 0.5 && !FRONT_FACING") and ft.contains("tl_path(q,"),
		"the scanned trees keep the rounded crown normal on both faces and trace the path out of the crown")
	_t._check(ProjectSettings.has_setting("shader_globals/tree_sun"), "the tree_sun shader global is declared")


func _materials() -> void:
	var bad := ""
	for i in PropFactory.CITY_TREES.size():
		var m: Mesh = PropFactory.model_tree(i)
		var top := m.get_aabb().end.y
		for s in m.get_surface_count():
			var mat := m.surface_get_material(s)
			if mat is ShaderMaterial and (mat as ShaderMaterial).shader.resource_path.ends_with("foliage_tex.gdshader"):
				var sm := mat as ShaderMaterial
				var sway := float(sm.get_shader_parameter("sway_height"))
				if float(sm.get_shader_parameter("tree_light")) < 0.5 or absf(sway - maxf(top, 1.0)) > 0.01:
					bad += " %s" % PropFactory.CITY_TREES[i]
	_t._check(bad == "", "every street tree's leaves sway by their own height%s" % bad)
	var palm := PropFactory.foliage_material()
	var la := LaTrees.material(LaTrees.Species.FIG)
	_t._check(float(palm.get_shader_parameter("tree_light")) > 0.5 and float(la.get_shader_parameter("tree_light")) > 0.5
		and float(la.get_shader_parameter("sway_height")) > 1.0, "the palms' and the LA trees' materials are lit through and weighted")


func _sun() -> void:
	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.8, 0.6)
	sun.light_energy = 1.3
	sun.rotation_degrees = Vector3(-50.0, 30.0, 0.0)
	var holder := Node3D.new()
	holder.add_child(sun)
	_t.get_tree().root.add_child(holder)
	var up := TreeLight.sun_light(sun)
	var c := sun.light_color.srgb_to_linear()
	var ok_up := up.distance_to(Vector3(c.r, c.g, c.b) * 1.3) < 1e-3
	sun.rotation_degrees = Vector3(10.0, 30.0, 0.0)
	var down := TreeLight.sun_light(sun)
	holder.free()
	_t._check(ok_up and down == Vector3.ZERO and TreeLight.sun_light(null) == Vector3.ZERO,
		"the crowns' sun light is the sun's colour times its energy, nothing once it is down")


func _switch() -> void:
	var was := TreeLight.enabled
	TreeLight.enabled = false
	var off := ShaderMaterial.new()
	off.shader = load("res://shaders/foliage_tex.gdshader")
	TreeLight.mark(off)
	TreeLight.enabled = true
	var on := ShaderMaterial.new()
	on.shader = off.shader
	TreeLight.mark(on)
	TreeLight.enabled = was
	TreeLight._marked.erase(off)
	TreeLight._marked.erase(on)
	_t._check(float(off.get_shader_parameter("tree_light")) == 0.0 and float(on.get_shader_parameter("tree_light")) == 1.0,
		"TREE_LIGHT=0 marks the tree materials off (the A/B)")
	var palm := PropFactory.foliage_material()
	TreeLight.set_all(false)
	var off_ok := float(palm.get_shader_parameter("tree_light")) == 0.0
	TreeLight.set_all(true)
	_t._check(off_ok and float(palm.get_shader_parameter("tree_light")) == 1.0, "TreeLight.set_all() flips every tree material, and back")
