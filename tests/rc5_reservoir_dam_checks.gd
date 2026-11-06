extends RefCounted
## Lake Shallufer from its trail (Rc5Reservoir, the reservoir_dam reference camera in
## tools/refcams/cameras_w8.json), for tests/smoke_test.gd. Loaded at run time, not named there, so
## it compiles after the autoloads.
##
## Checks: the water's pass is in the shader and off by default (no engine specular on
## Compatibility, the dam and towers mirrored), the material is switched on and told where the
## towers stand; the chain-link weave takes the instance's stretch out (the shared panel material
## only); the overlook stands on the east trail about 160 m off the dam, upstream of it, the fence
## open there and nowhere else; the camera row stands on it looking at the dam; the scree keeps off
## the trail; the trail's pass is in the dam shader; RC5_RESERVOIR=0 puts the old reservoir back.

var _t: Node


func run(t: Node, city: Node3D) -> void:
	_t = t
	var was := Rc5Reservoir.enabled
	Rc5Reservoir.enabled = true
	_shaders()
	var plan: CityPlan = city.plan
	var res: Reservoir = plan.macro.reservoir if plan.macro != null else null
	if res == null:
		_t._check(false, "rc5 reservoir: the plan has a reservoir")
	else:
		_water(res)
		_overlook(res)
		_camera(res)
	Rc5Reservoir.enabled = false
	var wm := ShaderMaterial.new()
	Rc5Reservoir.water(wm, null)
	var fm := ShaderMaterial.new()
	Rc5Reservoir.fence(fm)
	_t._check(float(wm.get_shader_parameter("rc5")) == 0.0 and float(fm.get_shader_parameter("scale_uv")) == 0.0
		and (res == null or Rc5Reservoir.overlook(res).is_empty()),
		"RC5_RESERVOIR=0: the old water, the old weave, no overlook")
	Rc5Reservoir.enabled = was


func _shaders() -> void:
	var w := FileAccess.get_file_as_string("res://shaders/reservoir_water.gdshader")
	_t._check(w.contains("uniform float rc5 = 0.0;"), "the reservoir water's pass is off by default (the A/B)")
	var i := w.find("#else\n\tif (rc5 > 0.5) {\n\t\tSPECULAR = 0.0;")
	_t._check(i > 0, "on Compatibility the engine's own sky reflection is off under the pass (the mirror carries the sky)")
	_t._check(w.contains("SPECULAR = 0.5 * (1.0 - hill_cover);"), "on Forward+ the engine's reflection only where the mirror shows sky")
	_t._check(w.contains("uniform vec4 tower_a") and w.contains("dam_span.x && a0 < dam_span.y"),
		"the dam's face and the intake towers are mirrored")
	var c := FileAccess.get_file_as_string("res://shaders/chain_link.gdshader")
	_t._check(c.contains("uniform float scale_uv = 0.0;") and c.contains("length(MODEL_MATRIX[0].xyz)"),
		"chain-link: the weave by the instance's stretch, off by default")
	var mat := LotFill.chain_link_panel().surface_get_material(0) as ShaderMaterial
	_t._check(mat != null and float(mat.get_shader_parameter("scale_uv")) == 1.0,
		"LotFill's panel material (the one every stretched fence shares) takes the stretch out")
	var d := FileAccess.get_file_as_string("res://shaders/reservoir_dam.gdshader")
	_t._check(d.contains("uniform float trail2 = 0.0;") and float(LandmarkReservoir.dam_material().get_shader_parameter("trail2")) == 1.0,
		"the trail's decomposed granite pass is off by default and on for the dam material")
	var rb := FileAccess.get_file_as_string("res://scripts/world/rock_build.gd")
	_t._check(rb.contains("Rc5Reservoir.scree_ok(ch, q)"), "RockBuild's scree asks the reservoir to keep clear")


func _water(res: Reservoir) -> void:
	var m := ShaderMaterial.new()
	Rc5Reservoir.water(m, res)
	var ta: Vector4 = m.get_shader_parameter("tower_a")
	var tb: Vector4 = m.get_shader_parameter("tower_b")
	var mid := res.arc_point((res.dam_a0 + res.dam_a1) * 0.5, Reservoir.DAM_RADIUS)
	var ok := float(m.get_shader_parameter("rc5")) == 1.0 and ta.z > 3.0 and tb.z > 2.0
	for tw: Vector4 in [ta, tb]:
		var p := Vector2(tw.x, tw.y)
		# Upstream of the dam's face (outside its arc), within 40 m of it, the house over the crest.
		var r := p.distance_to(res.dam_centre)
		ok = ok and r > Reservoir.DAM_RADIUS and r < Reservoir.DAM_RADIUS + 40.0 and p.distance_to(mid) < 200.0
		ok = ok and tw.w > res.crest - res.level
	_t._check(ok, "the water knows where the towers stand (%s, %s)" % [ta, tb])


func _overlook(res: Reservoir) -> void:
	var o := Rc5Reservoir.overlook(res)
	_t._check(not o.is_empty(), "the trail has an overlook")
	if o.is_empty():
		return
	var mid := res.arc_point((res.dam_a0 + res.dam_a1) * 0.5, Reservoir.DAM_RADIUS)
	var at: Vector2 = o.at
	var d := at - mid
	_t._check(absf(d.length() - Rc5Reservoir.OVERLOOK_DIST) < 25.0 and d.x > 0.0 and d.y < 0.0,
		"the overlook stands about %d m off the dam, east and upstream of it (%.0f m)" % [int(Rc5Reservoir.OVERLOOK_DIST), d.length()])
	var centre: Vector2 = o.centre
	var out: Vector2 = o.out
	_t._check(res.macro.height_at(centre + out * 6.0) < res.macro.height_at(centre - out * 6.0),
		"the balcony faces the lake (downhill)")
	_t._check(Rc5Reservoir.fence_open(res, centre) and not Rc5Reservoir.fence_open(res, centre + (o.dir as Vector2) * 20.0),
		"the fence is open at the overlook and nowhere else")
	_t._check(res.keep_clear(at, res.macro.height_at(at)), "the overlook's trail point keeps scree and planting off")


func _camera(res: Reservoir) -> void:
	var f := FileAccess.open("res://tools/refcams/cameras_w8.json", FileAccess.READ)
	_t._check(f != null, "tools/refcams/cameras_w8.json exists")
	if f == null:
		return
	var data: Variant = JSON.parse_string(f.get_as_text())
	var row: Dictionary = {}
	if data is Dictionary:
		for c: Dictionary in (data as Dictionary).get("cameras", []):
			if str(c.get("name", "")) == "reservoir_dam":
				row = c
	_t._check(not row.is_empty(), "the reservoir_dam camera row is in cameras_w8.json")
	if row.is_empty():
		return
	var eye: Array = row.eye
	var p := Vector2(float(eye[0]), float(eye[2]))
	var o := Rc5Reservoir.overlook(res)
	var mid := res.arc_point((res.dam_a0 + res.dam_a1) * 0.5, Reservoir.DAM_RADIUS)
	var d := mid - p
	var want := rad_to_deg(atan2(-d.x, -d.y))
	var turn := absf(wrapf(float(eye[3]) - want, -180.0, 180.0))
	_t._check(not o.is_empty() and p.distance_to(o.centre) < Rc5Reservoir.OVERLOOK_R and float(row.hour) == 10.5 and turn < 20.0,
		"the camera stands on the overlook at 10:30 looking at the dam (%.1f degrees off)" % turn)
	var deck := res.level + Reservoir.TRAIL_RISE + 0.07
	_t._check(not bool(row.get("agl", true)) and float(eye[1]) > deck + 1.4 and float(eye[1]) < deck + 1.9,
		"the eye is a standing person's on the balcony's deck")
