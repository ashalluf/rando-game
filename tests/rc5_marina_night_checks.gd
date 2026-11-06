extends RefCounted
## The marina at night (MarinaNight, marina_night.gdshaderinc; the marina_night reference camera in
## tools/refcams/cameras_w8.json; docs/HANDOFF.md "The marina at night"), for tests/smoke_test.gd.
## Loaded at run time, not named there.
##
## The lights the water mirrors are where MarinaBuild puts their glows (pedestals, anchor lights,
## nav lights), the pick is nearest first within reach and never past the shader's array, the
## restaurants' fronts face the basin behind the bulkhead, the restaurants' shops are eateries,
## the shader's arrays are MarinaNight's sizes and ml_count 0 keeps the old water, the jib switch
## is on the boat material, and the camera row is there.

var _t: Node


func run(t: Node, city: Node3D) -> void:
	_t = t
	var plan: CityPlan = city.plan
	var mr: Marina = plan.macro.marina if plan.macro else null
	if mr == null or not MarinaNight.enabled or not MarinaGolden.enabled:
		_t._check(true, "marina night: off (no marina, MARINA_NIGHT=0 or MARINA_GOLDEN=0), nothing to check")
		return
	_lights(mr)
	_pick(mr)
	_fronts(mr)
	_names()
	_shader()
	_camera()


func _lights(mr: Marina) -> void:
	var all := MarinaNight.lights_for(mr)
	var anchors := 0
	for bt: Dictionary in mr.boats:
		if bool(bt.anchor):
			anchors += 1
	var nav := 0
	var pedestals := 0
	var in_site := true
	var sane := true
	for l: Array in all:
		var p: Vector3 = l[0]
		var c: Color = l[1]
		if c.r > 6.0 and c.g < 2.0 or c.g > 6.0 and c.r < 2.0:
			nav += 1
		if absf(p.y - (Marina.DOCK_Y + 1.22)) < 1e-3:
			pedestals += 1
		if not mr.site.grow(400.0).has_point(Vector2(p.x, p.z)):
			in_site = false
		if p.y < 0.5 or p.y > 40.0 or float(l[2]) <= 0.0 or c.r + c.g + c.b <= 0.0:
			sane = false
	_t._check(pedestals > 10 and nav >= 2 and all.size() >= anchors + pedestals + 2 and in_site and sane,
		"marina night: %d lights to mirror (%d pedestals, %d anchor lights, %d red / green nav lights), all at the marina, all lit" % [all.size(), pedestals, anchors, nav])
	# Each pedestal is where MarinaBuild lays its lamp box: on a dock's float, beside its line.
	var on_dock := 0
	for l: Array in all:
		var p: Vector3 = l[0]
		if absf(p.y - (Marina.DOCK_Y + 1.22)) > 1e-3:
			continue
		for d: Dictionary in mr.docks:
			var q := Geometry2D.get_closest_point_to_segment(Vector2(p.x, p.z), d.a, d.b)
			if q.distance_to(Vector2(p.x, p.z)) <= float(d.w) * 0.5:
				on_dock += 1
				break
	_t._check(on_dock == pedestals, "marina night: every pedestal light stands on a dock (%d of %d)" % [on_dock, pedestals])


func _pick(mr: Marina) -> void:
	var eye := Vector2(-621.5, 64.5)
	var got := MarinaNight.pick(mr, eye)
	var last := -1.0
	var sorted := true
	for l: Array in got:
		var p: Vector3 = l[0]
		var d := Vector2(p.x, p.z).distance_to(eye)
		if d < last - 1e-4 or d > MarinaNight.REACH:
			sorted = false
		last = d
	_t._check(not got.is_empty() and got.size() <= MarinaNight.MAX_LIGHTS and sorted,
		"marina night: %d lights picked nearest first at the headwalk (at most %d)" % [got.size(), MarinaNight.MAX_LIGHTS])
	_t._check(MarinaNight.pick(mr, Vector2(4000.0, 4000.0)).is_empty(), "marina night: nothing picked far from the marina")
	var mat := ShaderMaterial.new()
	mat.shader = MarinaBuild.water_material().shader
	var n := MarinaNight.push(mat, mr, eye)
	var lp: PackedVector4Array = mat.get_shader_parameter("ml_p")
	var fa: PackedVector4Array = mat.get_shader_parameter("mf_a")
	_t._check(n == got.size() and int(mat.get_shader_parameter("ml_count")) == n and lp.size() == MarinaNight.MAX_LIGHTS
		and fa.size() == MarinaNight.MAX_FRONTS and int(mat.get_shader_parameter("mf_count")) > 0,
		"marina night: the water gets ml_count %d, %d fronts and arrays of the shader's sizes" % [n, int(mat.get_shader_parameter("mf_count"))])


func _fronts(mr: Marina) -> void:
	var fronts := MarinaNight.fronts_for(mr)
	var ok := not fronts.is_empty()
	for f: Array in fronts:
		var a: Vector2 = f[0]
		var b: Vector2 = f[1]
		# The front's line is north of the bulkhead (the water's north edge), facing it.
		if a.y >= float(f[4]) or b.x <= a.x or float(f[3]) <= float(f[2]):
			ok = false
	_t._check(ok, "marina night: %d restaurant fronts, each across the bulkhead from the water and facing it" % fronts.size())


func _names() -> void:
	var pool := MarinaNight.eatery_pool()
	var ok := pool.size() >= 6
	for i in pool:
		var room: int = Building.SHOP_NAME_ROOMS[Building.SHOP_NAMES[i]]
		if room != Building.ShopRoom.CAFE and room != Building.ShopRoom.RESTAURANT:
			ok = false
	_t._check(ok, "marina night: the restaurants' %d shop names are all cafes or restaurants" % pool.size())


func _shader() -> void:
	var inc := FileAccess.get_file_as_string("res://shaders/marina_night.gdshaderinc")
	var water := FileAccess.get_file_as_string("res://shaders/marina_water.gdshader")
	var body := FileAccess.get_file_as_string("res://shaders/boat_body.gdshaderinc")
	var ok := inc.contains("const int ML_MAX = %d;" % MarinaNight.MAX_LIGHTS) \
		and inc.contains("uniform vec4 ml_p[%d];" % MarinaNight.MAX_LIGHTS) \
		and inc.contains("uniform vec4 mf_a[%d];" % MarinaNight.MAX_FRONTS) \
		and water.contains("#include \"res://shaders/marina_night.gdshaderinc\"") \
		and water.contains("bool night_lights = (ml_count > 0 || mf_count > 0) && lamp_factor > 0.01;")
	_t._check(ok, "marina night: the water mirrors the lights, its arrays are MarinaNight's sizes, and no lights keep the old water")
	var m := MarinaBuild.boat_material()
	_t._check(body.contains("uniform float jib_soft = 0.0;") and float(m.get_shader_parameter("jib_soft")) == 1.0,
		"marina night: the boats' material has jib_soft on (0 is the old strip)")


func _camera() -> void:
	var data = JSON.parse_string(FileAccess.get_file_as_string("res://tools/refcams/cameras_w8.json"))
	var found := false
	if data is Dictionary:
		for row: Dictionary in data.get("cameras", []):
			if str(row.get("name", "")) == "marina_night" and float(row.get("hour", 0.0)) == 21.0:
				found = true
	_t._check(found, "marina night: the marina_night camera row is in cameras_w8.json")
