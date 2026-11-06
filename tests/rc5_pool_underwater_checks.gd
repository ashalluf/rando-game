extends RefCounted
## Under the water of a hill home's pool (PoolUnder, the pool_underwater reference camera in
## tools/refcams/cameras_w8.json), for tests/smoke_test.gd. Loaded at run time, not named there, so
## it compiles after the autoloads.
##
## Checks: the camera row is half a metre under estate 392's pool surface, inside the pool, at 14:00
## clear; the shaders' pool passes are off by default (the sea and the lakes keep their look) and the
## include's weir matches PoolUnder's; the tank's faces turn to face in; a registered pool is found
## by a point in its water and not beside it; apply() hands the pool to both materials and puts the
## sea's numbers back outside it; POOL_UNDER=0 keeps the old view; a pool is deep enough to dive in.

var _t: Node


func run(t: Node, city: Node3D) -> void:
	_t = t
	var plan: CityPlan = city.plan
	_shaders()
	_quads()
	_registry()
	if plan.macro != null and plan.macro.hill_roads != null:
		_camera(plan)
	else:
		_t._check(false, "pool underwater: the plan has hill roads")


func _shaders() -> void:
	var inc := FileAccess.get_file_as_string("res://shaders/pool_tank.gdshaderinc")
	_t._check(inc.contains("const float PT_WEIR_DROP = %s;" % str(PoolUnder.WEIR_DROP)),
		"pool_tank.gdshaderinc's weir drop is PoolUnder.WEIR_DROP (%s)" % PoolUnder.WEIR_DROP)
	var u := FileAccess.get_file_as_string("res://shaders/water_underside.gdshader")
	_t._check(u.contains("uniform float pt_on = 0.0;") and u.contains("discard;"),
		"the underside's pool pass is off by default and cut to the pool")
	var w := FileAccess.get_file_as_string("res://shaders/underwater.gdshader")
	_t._check(w.contains("uniform float pt_on = 0.0;") and w.contains("exit_t"),
		"the underwater pass's pool clip is off by default")
	var tank := FileAccess.get_file_as_string("res://shaders/pool_tank.gdshader")
	_t._check(tank.contains("unshaded") and tank.contains("cs_out("),
		"the tank is lit by hand (the pad's box shadows it) and linear on both renderers")
	var s := FileAccess.get_file_as_string("res://scripts/player/swim.gd")
	_t._check(s.contains("PoolUnder.apply(") and s.contains("SwimWater.Kind.POOL, SwimWater.Kind.TANK] else 2.2"),
		"Swim hands the pool to the view and lets him dive in a pool")
	_t._check(SwimWater.POOL_DEPTH > 1.5, "a pool (%.1f m) is deeper than the dive threshold" % SwimWater.POOL_DEPTH)


func _quads() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	PoolUnder._quad(st, Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 0, 1), Vector3(0, 0, 1), Vector3.UP)
	var arr := st.commit_to_arrays()
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var ok := v.size() == 6
	for i in range(0, v.size(), 3):
		# Clockwise seen from the face's side: the cross product points away from it.
		ok = ok and (v[i + 1] - v[i]).cross(v[i + 2] - v[i]).dot(Vector3.UP) < 0.0
	_t._check(ok, "the tank's quads wind to face their normal")


func _registry() -> void:
	var holder := Node.new()
	_t.add_child(holder)
	var pool := {"o": Vector2(1000.0, 2000.0), "fu": Vector2(1, 0), "fv": Vector2(0, 1),
		"rect": Vector4(0.0, 0.0, 5.0, 4.0), "inner": Rect2(0, 0, 5, 3.8), "surface": 50.0, "floor": 48.3,
		"weir": 1.0, "seed": 0.5, "boxes": [[Vector4(-8, 0, 49.9, 1), Vector4(-1, 6, 54, 0)]]}
	var was := PoolUnder.enabled
	PoolUnder.enabled = true
	PoolUnder.register(holder, pool)
	_t._check(not PoolUnder.at(Vector3(1002.0, 49.5, 2002.0)).is_empty(), "a point in the pool's water finds it")
	_t._check(PoolUnder.at(Vector3(1007.0, 49.5, 2002.0)).is_empty() and PoolUnder.at(Vector3(1002.0, 51.5, 2002.0)).is_empty(),
		"a point beside it or over it does not")
	var under := ShaderMaterial.new()
	under.shader = load("res://shaders/water_underside.gdshader")
	var over := ShaderMaterial.new()
	over.shader = load("res://shaders/underwater.gdshader")
	var on := PoolUnder.apply(Vector3(1002.0, 49.5, 2002.0), under, over)
	_t._check(on and float(under.get_shader_parameter("pt_on")) == 1.0 and float(over.get_shader_parameter("pt_on")) == 1.0
		and (under.get_shader_parameter("pt_box0_max") as Vector4).z == 54.0
		and is_equal_approx(float(over.get_shader_parameter("visibility")), PoolUnder.VISIBILITY),
		"apply() hands the pool, its house and pool water to both materials")
	PoolUnder.apply(Vector3(1020.0, 49.5, 2002.0), under, over)
	_t._check(float(under.get_shader_parameter("pt_on")) == 0.0 and is_equal_approx(float(over.get_shader_parameter("visibility")), 9.0),
		"outside a pool the sea's view comes back")
	PoolUnder.enabled = false
	_t._check(not PoolUnder.apply(Vector3(1002.0, 49.5, 2002.0), under, over) and float(over.get_shader_parameter("pt_on")) == 0.0,
		"POOL_UNDER=0: the old view in a pool too")
	PoolUnder.enabled = was
	holder.free()
	_t._check(PoolUnder.at(Vector3(1002.0, 49.5, 2002.0)).is_empty(), "a pool goes with its chunk")


func _row() -> Dictionary:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tools/refcams/cameras_w8.json"))
	if not data is Dictionary:
		return {}
	for c: Dictionary in data.get("cameras", []):
		if c.name == "pool_underwater":
			return c
	return {}


func _camera(plan: CityPlan) -> void:
	var row := _row()
	_t._check(not row.is_empty() and is_equal_approx(float(row.hour), 14.0) and row.weather == "clear" and row.has("swim"),
		"the pool_underwater row is at 14:00 clear with its swim staging")
	if row.is_empty():
		return
	var estates: Array = plan.macro.hill_roads.mansions
	if estates.size() <= 392:
		_t._check(false, "pool underwater: estate 392 exists")
		return
	var h := HillHomeKit.plan_home(plan, estates[392])
	var pl: Dictionary = h.pool
	_t._check(not pl.is_empty() and bool(pl.infinity), "estate 392 has an infinity pool")
	if pl.is_empty():
		return
	var eye: Array = row.eye
	var rel := Vector2(float(eye[0]), float(eye[2])) - (h.o as Vector2)
	var uv := Vector2(rel.dot(h.fu), rel.dot(h.fv))
	var r: Rect2 = pl.r
	_t._check(r.grow(-0.3).has_point(uv), "the eye is inside the pool (%s in %s)" % [uv, r])
	var surface := float(h.top) + 0.1
	var under := surface - float(eye[1])
	_t._check(under > 0.35 and under < 0.7, "the eye is about half a metre under the surface (%.2f m)" % under)
