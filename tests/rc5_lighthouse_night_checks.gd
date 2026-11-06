extends RefCounted
## The lighthouse_night refcam's review (RcLighthouse, docs/HANDOFF.md "The lighthouse from the
## breakwater at night"), for tests/smoke_test.gd. Loaded at run time, not named there, so it
## compiles after the autoloads.
##
## The switch and what it sets; every new uniform's default being the old look; the scattered
## beam's phase function (GDScript copy against the shader's); the beam mesh carrying its axis; the
## kit's own materials wearing the look; the camera row and its lighthouse_t key. Touches no live
## system (materials made here, the kit's cache read only).

var _t: Object


func run(t: Object, _city: Node3D) -> void:
	_t = t
	var was := RcLighthouse.enabled
	_defaults()
	_switch()
	_phase()
	_mesh()
	_kit()
	_camera()
	RcLighthouse.enabled = was


## Every look uniform defaults to 0: a material the review never touches draws as before.
func _defaults() -> void:
	for p in ["res://shaders/lighthouse_beam.gdshader", "res://shaders/lighthouse_lamp.gdshader",
			"res://shaders/breakwater_foam.gdshader", "res://shaders/armour_stone.gdshader"]:
		var src := FileAccess.get_file_as_string(p)
		_t._check(src.contains("uniform float look = 0.0;") and src.contains("look > 0.5"),
			"rc5 lighthouse: %s keeps its old look at look 0" % p.get_file())


func _switch() -> void:
	RcLighthouse.enabled = false
	var off := ShaderMaterial.new()
	off.shader = load("res://shaders/lighthouse_beam.gdshader")
	RcLighthouse.apply(off, "beam")
	_t._check(float(off.get_shader_parameter("look")) == 0.0 and off.get_shader_parameter("waist") == null,
		"rc5 lighthouse: RC5_LIGHTHOUSE=0 puts the old beam back")
	RcLighthouse.enabled = true
	var on := ShaderMaterial.new()
	on.shader = load("res://shaders/lighthouse_beam.gdshader")
	RcLighthouse.apply(on, "beam")
	var spread := float(on.get_shader_parameter("spread"))
	_t._check(float(on.get_shader_parameter("look")) == 1.0 and absf(spread - tan(deg_to_rad(RcLighthouse.BEAM_SPREAD_DEG))) < 1e-6,
		"rc5 lighthouse: the scattered beam's look, spread %.4f" % spread)
	# The Gaussian pencil stays inside the drawn cone (1.15 degrees): ~2.4 sigma at its far end.
	var cone := tan(deg_to_rad(1.15))
	_t._check(cone / spread > 2.0 and RcLighthouse.BEAM_WAIST < 0.45,
		"rc5 lighthouse: the pencil fits the cone (%.1f sigma at the far end)" % (cone / spread))


## The forward scattering: 1 side-on, brighter looking back up the beam, dimmer behind it; the
## shader carries the same expression.
func _phase() -> void:
	var side := RcLighthouse.phase(0.0)
	var fwd := RcLighthouse.phase(0.9)
	var back := RcLighthouse.phase(-0.9)
	_t._check(absf(side - 1.0) < 1e-4 and fwd > 3.0 and back < 0.6,
		"rc5 lighthouse: the beam scatters forward (side %.2f, toward the lens %.2f, away %.2f)" % [side, fwd, back])
	var src := FileAccess.get_file_as_string("res://shaders/lighthouse_beam.gdshader")
	_t._check(src.contains("pow(1.0 + g * g, 1.5) / pow(max(1.0 + g * g - 2.0 * g * cos_t, 1e-4), 1.5)")
		and src.contains("uniform float phase_g = %s;" % str(RcLighthouse.BEAM_G)),
		"rc5 lighthouse: the shader's phase is RcLighthouse.phase()")


## Each beam's cone carries its own axis in UV2 (cos yaw, -sin yaw: the rotor's +X turned).
func _mesh() -> void:
	var m := LighthouseKit.beam_mesh(2, 1700.0) as ArrayMesh
	var arr := m.surface_get_arrays(0)
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var uv2: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV2]
	var ok := uv2.size() == v.size() and v.size() > 0
	for i in range(0, v.size(), 37):
		if not ok:
			break
		var p := v[i]
		if absf(p.x) < 30.0:
			continue
		# Far along a cone the vertex lies along its axis.
		var ax := Vector2(uv2[i].x, uv2[i].y)
		ok = Vector2(p.x, p.z).normalized().dot(ax) > 0.99
	_t._check(ok, "rc5 lighthouse: the beam mesh carries each cone's axis in UV2")


## The kit's own materials wear the look (built at load with the switch on).
func _kit() -> void:
	if not RcLighthouse.enabled or not Lighthouses.enabled():
		return
	var want := 1.0
	var beam := LighthouseKit.light_mat(Lighthouses.LIGHT_ID, "beam") as ShaderMaterial
	var lamp := LighthouseKit.light_mat(Lighthouses.GATE_ID, "lamp") as ShaderMaterial
	var foam := LighthouseKit.mat("foam") as ShaderMaterial
	var stone := LighthouseKit.mat("armour") as ShaderMaterial
	_t._check(float(beam.get_shader_parameter("look")) == want and float(lamp.get_shader_parameter("look")) == want
		and float(foam.get_shader_parameter("look")) == want and float(stone.get_shader_parameter("look")) == want,
		"rc5 lighthouse: the beam, lamp, foam and armour materials wear the review")
	_t._check(absf(float(LighthouseKit.light_mat(Lighthouses.GATE_ID, "beam").get_shader_parameter("beam_length"))
		- float(Lighthouses.LIGHTS[Lighthouses.GATE_ID].length)) < 0.01,
		"rc5 lighthouse: a beam fades over its own light's length")


func _camera() -> void:
	var f := FileAccess.get_file_as_string("res://tools/refcams/cameras_w8.json")
	var data: Variant = JSON.parse_string(f)
	var row: Dictionary = {}
	if data is Dictionary:
		for c: Dictionary in (data as Dictionary).get("cameras", []):
			if String(c.get("name", "")) == "lighthouse_night":
				row = c
	_t._check(not row.is_empty() and float(row.get("hour", 0.0)) == 22.0 and row.has("lighthouse_t"),
		"rc5 lighthouse: the lighthouse_night camera row with its held lens clock")
	if row.is_empty():
		return
	var eye: Array = row.eye
	var d := Lighthouses.nearest(Vector2(float(eye[0]), float(eye[2])))
	_t._check(d.x < Lighthouses.half_width_at(0.0) and float(eye[1]) > Lighthouses.WATER_Y + 1.5,
		"rc5 lighthouse: the eye stands on the breakwater's armour (%.1f m off its crest line)" % d.x)
	var src := FileAccess.get_file_as_string("res://tools/refcams/refcams_shot.gd")
	_t._check(src.contains("_lighthouse_clock(cam)") and src.contains("\"hold_t\""),
		"rc5 lighthouse: refcams_shot holds the lens clock for the row")
