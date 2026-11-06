extends RefCounted
## The police pursuit at night (PursuitLook, the police_pursuit reference camera in
## tools/refcams/cameras_w8.json), for tests/smoke_test.gd. Loaded at run time, not named there, so
## it compiles after the autoloads.
##
## Checks: the LED triple flash (a bank lit about 72 % of the cycle, red in the first half and blue
## in the second, the same expression in both shaders as in GDScript, off by default there); the
## LED light bar (inside the old bar's box, its banks on their sides, one surface); the helicopter's
## searchlight (the pool the beam's width and on the ground, the shaft's fades off by default);
## the hook lines; the camera row and its staging; PURSUIT_LOOK=0 puts the old numbers back.

var _t: Object


func run(t: Object) -> void:
	_t = t
	var was := PursuitLook.enabled
	PursuitLook.enabled = true
	_flashes()
	_bar()
	_searchlight()
	_hooks()
	_camera()
	PursuitLook.enabled = false
	_t._check(is_equal_approx(PursuitLook.pool_dia(100.0, 6.5), 2.0 * 100.0 * tan(deg_to_rad(6.5)) * 1.25 + 2.0)
		and is_equal_approx(PursuitLook.pool_lift(), 0.25),
		"PURSUIT_LOOK=0: the old searchlight pool")
	PursuitLook.enabled = was


func _flashes() -> void:
	var red := 0
	var blue := 0
	var wrong := 0
	for i in 2000:
		var f := (float(i) + 0.5) / 2000.0
		var s := PursuitLook.flash_side(f)
		if s > 0:
			red += 1
			if f >= 0.5:
				wrong += 1
		elif s < 0:
			blue += 1
			if f < 0.5:
				wrong += 1
	var duty := float(red + blue) / 2000.0
	_t._check(duty > 0.65 and duty < 0.8 and absi(red - blue) < 20 and wrong == 0,
		"the LED triple flash lights a bank %.0f %% of the cycle, red first, blue second (the old 36 %%)" % (duty * 100.0))
	var expr := "step(0.0, u) * step(u, 0.42) * step(mod(u, 0.15), 0.12)"
	for path in ["res://shaders/police_lights.gdshader", "res://shaders/police_wash.gdshader"]:
		var src := FileAccess.get_file_as_string(path)
		_t._check(src.contains("uniform float pattern = 0.0;") and src.contains(expr),
			"%s strobes PursuitLook's pattern, off by default" % path.get_file())


func _bar() -> void:
	var m := PursuitLook.light_bar_mesh()
	var vs: PackedVector3Array = PursuitLook.light_bar_arrays()[Mesh.ARRAY_VERTEX]
	var box := AABB(vs[0], Vector3.ZERO)
	for v in vs:
		box = box.expand(v)
	_t._check(m.get_surface_count() == 1, "the LED bar is one surface (one draw a cruiser)")
	_t._check(box.position.x >= -0.63 and box.end.x <= 0.63 and box.position.z >= -0.17 and box.end.z <= 0.17
		and box.position.y >= -0.001 and box.end.y <= 0.16,
		"the LED bar stays inside the old bar's box (%s)" % str(box))
	var arr := PursuitLook.light_bar_arrays()
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var cols: PackedColorArray = arr[Mesh.ARRAY_COLOR]
	var uv2: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV2]
	var bad := 0
	var lens := 0
	for i in verts.size():
		if uv2[i].x < 0.0:
			continue
		lens += 1
		var a := cols[i].a
		if (absf(a - 0.5) < 0.01 and verts[i].x > -0.07) or (a > 0.99 and verts[i].x < 0.07):
			bad += 1
	_t._check(lens > 0 and bad == 0, "the red bank is on the bar's -x, the blue on +x (%d lens vertices)" % lens)
	var wash := FileAccess.get_file_as_string("res://shaders/police_wash.gdshader")
	_t._check(wash.contains("uniform float point_pool = 0.0;"), "the wash's point-source pool is off by default (the A/B)")
	var wm := ShaderMaterial.new()
	PursuitLook.dress_wash(wm, 30.0)
	_t._check(float(wm.get_shader_parameter("point_pool")) == 1.0 and float(wm.get_shader_parameter("pattern")) == 1.0
		and float(wm.get_shader_parameter("glare_size")) < 0.7, "dress_wash(): the pattern, the point pool, the smaller glare")
	var src := FileAccess.get_file_as_string("res://shaders/police_lights.gdshader")
	_t._check(src.contains("uniform float led = 0.0;"), "the bar's LED shading is off by default (the A/B)")


func _searchlight() -> void:
	var w := 2.0 * 90.0 * tan(deg_to_rad(6.5))
	_t._check(PursuitLook.pool_dia(90.0, 6.5) < w * 1.2, "the searchlight's pool is the beam's width (%.1f m)" % PursuitLook.pool_dia(90.0, 6.5))
	_t._check(PursuitLook.pool_lift() < 0.1, "the pool lies on the ground, not over the tyres")
	_t._check(PursuitLook.POOL_STRENGTH < 1.0 and PursuitLook.CORE_STRENGTH < 1.0,
		"the pool is faint: the spot does the lighting")
	var src := FileAccess.get_file_as_string("res://shaders/searchlight_beam.gdshader")
	_t._check(src.contains("uniform float foot_fade = 0.0;") and src.contains("uniform float near_to = 0.0;"),
		"the shaft's foot and near fades are off by default (the A/B)")
	var pool := MeshInstance3D.new()
	var core := MeshInstance3D.new()
	core.name = "PoolCore"
	pool.add_child(core)
	var mat := ShaderMaterial.new()
	PursuitLook.dress_searchlight(pool, mat)
	_t._check(float(mat.get_shader_parameter("foot_fade")) > 0.0 and float(mat.get_shader_parameter("near_to")) > 0.0
		and pool.mesh != null and core.scale.x < 0.5, "dress_searchlight() fades the shaft and softens the pool")
	pool.free()


func _hooks() -> void:
	var heli := FileAccess.get_file_as_string("res://scripts/vehicles/helicopter.gd")
	_t._check(heli.contains("PursuitLook.dress_searchlight(") and heli.contains("PursuitLook.pool_dia(")
		and heli.contains("PursuitLook.pool_lift()"), "the helicopter's searchlight takes PursuitLook's pool and shaft")
	var car := FileAccess.get_file_as_string("res://scripts/npc/police_car.gd")
	_t._check(car.contains("PursuitLook.dress_bar(") and car.contains("return PursuitLook.flash_side(f)"),
		"PoliceCar's bar and flash_side() follow PursuitLook")
	var look := FileAccess.get_file_as_string("res://scripts/npc/police_night_look.gd")
	_t._check(look.contains("PursuitLook.dress_wash(mat, pool_size)"), "the washes strobe the bar's pattern")


func _camera() -> void:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tools/refcams/cameras_w8.json"))
	var row: Dictionary = {}
	if data is Dictionary:
		for c in (data as Dictionary).get("cameras", []):
			if String(c.get("name", "")) == "police_pursuit":
				row = c
	var drive: Dictionary = row.get("drive", {})
	var pursuit: Dictionary = drive.get("pursuit", {})
	_t._check(not row.is_empty() and float(row.get("hour", 0.0)) == 22.0 and String(row.get("weather", "")) == "clear",
		"the police_pursuit camera row: 22:00 clear")
	_t._check(int(pursuit.get("stars", 0)) == 3 and (pursuit.get("cruisers", []) as Array).size() == 2 and pursuit.has("heli"),
		"its pursuit staging: three stars, two cruisers, the helicopter")
	_t._check(ResourceLoader.exists("res://tools/refcams/pursuit_stage.gd")
		and FileAccess.get_file_as_string("res://tools/refcams/chase_stage.gd").contains("pursuit_stage.gd"),
		"the drive staging loads the pursuit staging")
