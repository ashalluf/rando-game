extends RefCounted
## The LA River at night (RiverNight; the river_night reference camera in
## tools/refcams/cameras_w7.json; docs/HANDOFF.md "The LA River at night"), for tests/smoke_test.gd.
## Loaded at run time, not named there, so it compiles after the autoloads.
##
## A FULL build of the 6th St chunk notes the ribbon bridge and hands its frame to both river
## materials; the record is the builder's (span ends, deck, the rib's crown); the fixtures under the
## deck are where the shader lights them from; every new shader branch is behind the river_night
## global and lamp_factor (day is untouched); the camera row stands on the bed facing the bridge.

var _t: Node


func run(t: Node, city: Node3D) -> void:
	_t = t
	var plan: CityPlan = city.plan
	var rv: LaRiver = plan.macro.river if plan.macro else null
	_shaders()
	if rv == null or not RiverNight.enabled():
		_t._check(true, "river night: off (no river or RIVER_NIGHT=0), nothing more to check")
		return
	_bridge(city, plan, rv)
	_camera(plan, rv)


func _shaders() -> void:
	var inc := FileAccess.get_file_as_string("res://shaders/river_night.gdshaderinc")
	var water := FileAccess.get_file_as_string("res://shaders/river_water.gdshader")
	var concrete := FileAccess.get_file_as_string("res://shaders/river_concrete.gdshader")
	var gate := "river_night > 0.5 && lamp_factor > 0.01"
	_t._check(water.contains(gate) and concrete.count(gate) >= 3 and water.contains("river_night.gdshaderinc") \
			and concrete.contains("river_night.gdshaderinc") and not inc.contains("texture("),
		"river night: every new branch of the river's shaders is behind river_night and lamp_factor, and samples no texture")
	var ok := absf(_const(inc, "RN_FIX_IN") - RiverNight.FIX_IN) < 1e-4 and absf(_const(inc, "RN_FIX_DROP") - RiverNight.FIX_DROP) < 1e-4 \
		and absf(_const(inc, "RN_FIX_PITCH") - RiverNight.PITCH) < 1e-4 and inc.contains("uniform vec4 rn_a[%d]" % RiverNight.MAX)
	_t._check(ok, "river night: the shader's fixture numbers and array size are RiverNight's")
	_t._check(inc.contains("rn_d[i].z * pow(max(1.0 - e * e, 0.0), 0.7)") and inc.contains("rn_b[i].x + 0.4 + h * rn_d[i].w"),
		"river night: the shader's rib is RiverBridges' ribbon rib (rise, lean)")


func _const(src: String, name: String) -> float:
	var re := RegEx.create_from_string("const float " + name + " = ([0-9.]+);")
	var m := re.search(src)
	return m.get_string(1).to_float() if m else -1.0


func _bridge(city: Node3D, plan: CityPlan, rv: LaRiver) -> void:
	var br6 := {}
	for br: Dictionary in rv.bridges(plan):
		if br.name == "6TH ST":
			br6 = br
	if br6.is_empty():
		_t._check(true, "river night: no 6th St bridge on this seed")
		return
	var chunk: CityChunk = city._new_chunk(br6.owner, CityChunk.Level.FULL)
	chunk.build()
	var key := "%d:%d" % [int(br6.axis), int(br6.index)]
	var rec: Dictionary = RiverNight._bridges.get(key, {})
	var noted := not rec.is_empty() and RiverNight._order.has(key)
	_t._check(noted and float(rec.get("kind", -1.0)) == RiverNight.K_RIBBON,
		"river night: building the 6th St chunk notes its ribbon bridge (%s)" % key)
	if noted:
		var st: Array = rec.stops
		var sorted := float(st[0]) < float(st[1]) and float(st[1]) < float(st[2]) and float(st[2]) < float(st[3])
		var mid := (float(st[0]) + float(st[1])) * 0.5
		var crown := RiverNight.rib_at(rec, mid, 1.0)
		var bed := rv.toe_at(float(br6.s))
		_t._check(sorted and absf(crown.y - (float(rec.deck) + 0.2 + RiverBridges.RIBBON_RISE)) < 0.05 and float(rec.deck) > bed + 4.0
			and RiverNight.rib_at(rec, float(st[3]) + 1.0, 1.0) == Vector2.INF,
			"river night: the record's spans run in order, the rib's crown is the rise over the deck (%.1f), the deck over the bed (%.1f > %.1f)" % [crown.y, rec.deck, bed])
		var m := RiverBuild.concrete_material()
		var w := RiverBuild.water_material()
		var n := int(m.get_shader_parameter("rn_count"))
		var arr: PackedVector4Array = w.get_shader_parameter("rn_a")
		var found := false
		for v in arr:
			if absf(v.x - (rec.o as Vector2).x) < 0.01 and absf(v.y - (rec.o as Vector2).y) < 0.01:
				found = true
		_t._check(n >= 1 and n <= RiverNight.MAX and int(w.get_shader_parameter("rn_count")) == n and arr.size() == RiverNight.MAX and found,
			"river night: both river materials carry the bridge (%d of %d slots)" % [n, RiverNight.MAX])
		var ts := RiverNight.fixture_ts({"tb": rec.tb})
		var tb: Vector2 = rec.tb
		_t._check(ts.size() >= 4 and ts[0] < tb.x and ts[-1] > tb.y - RiverNight.PITCH and ts[-1] <= tb.y + 2.0,
			"river night: %d fixtures hang under the deck over the bed (%.0f .. %.0f)" % [ts.size(), tb.x, tb.y])
	var lamps := chunk.get_node_or_null("RiverLamps")
	_t._check(lamps != null, "river night: the chunk carries the lamp mesh (fixture lenses, LED strips)")
	chunk.get_parent().remove_child(chunk)
	chunk.free()
	# Packing: the arrays always hold MAX entries, zero past the count.
	var a := RiverNight.arrays([])
	_t._check(int(a.rn_count) == 0 and (a.rn_a as PackedVector4Array).size() == RiverNight.MAX and (a.rn_e as PackedVector4Array)[0] == Vector4.ZERO,
		"river night: an empty table packs MAX zero entries")


func _camera(plan: CityPlan, rv: LaRiver) -> void:
	var cams: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tools/refcams/cameras_w7.json"))
	var row := {}
	for c: Dictionary in cams.get("cameras", []):
		if c.get("name", "") == "river_night":
			row = c
	if row.is_empty():
		_t._check(false, "river night: the river_night camera row is in cameras_w7.json")
		return
	var eye: Array = row.eye
	var p := Vector2(float(eye[0]), float(eye[2]))
	var nr := rv.nearest(p, 100.0)
	var over := float(eye[1]) - rv.surface(nr.x, nr.y)
	var yaw := deg_to_rad(float(eye[3]))
	var fwd := Vector2(-sin(yaw), -cos(yaw))
	var ahead := -1.0
	for br: Dictionary in rv.bridges(plan):
		if br.name == "6TH ST":
			ahead = ((br.p as Vector2) - p).dot(fwd)
	_t._check(nr.w > 0.5 and absf(nr.y) < rv.bed_half(nr.x) and over > 0.8 and over < 2.5 and ahead > 20.0 and ahead < 120.0
		and float(row.hour) > 21.0 and not bool(row.get("agl", true)),
		"river night: the camera stands on the bed %.1f m up, the 6th St bridge %.0f m ahead, after dark" % [over, ahead])
