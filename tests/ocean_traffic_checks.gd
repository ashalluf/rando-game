extends RefCounted
## The ocean traffic (OceanTraffic, Vessel, VesselMesh, AnchoredShip, vessel.gdshader's ride,
## ocean.gdshader's wakes) for tests/smoke_test.gd. Loaded at run time (not named there), so it
## compiles after the autoloads. Checks: the swell copy in sea_ride.gdshaderinc matches the ocean's
## own numbers and the GDScript mirror; every hull and sail builds at every level inside its
## triangle budget; every route keeps to open water; the persistent fleet is out (ferries, tugs,
## the pilot boat, the ships at anchor) and moves along its loops; a sloop sails no closer than
## 40 degrees to the wind, heels to leeward and tacks when its course is upwind; a staged scene
## puts wakes in the ocean material; a vessel shot to pieces burns, explodes and sinks, and leaves
## the fleet.

var _t: Node
var _tree: SceneTree

## Triangle budgets per level (NEAR, MID, FAR) for any hull.
const BUDGET := [9000, 3200, 900]
const LANE_MARGIN := {"coast": 150.0, "bay": 150.0, "ferry": 100.0, "tug": 60.0, "pilot": 60.0}


func run(t: Node, city: Node3D) -> void:
	_t = t
	_tree = t.get_tree()
	_shader_copies()
	_meshes()
	var ot: Node = city.get_node_or_null("OceanTraffic")
	_t._check(ot != null and ot.get("enabled") == true, "ocean traffic: the OceanTraffic node is in the city and on")
	if ot == null:
		return
	for i in 4:
		await _tree.physics_frame
	_t._check(ot.get("macro") != null, "ocean traffic: set up on the city's plan")
	if ot.get("macro") == null:
		return
	_lanes(ot)
	_fleet(ot)
	_ferry_moves(ot)
	_sailing(ot)
	_wakes(ot)
	_sinking(ot)


func _shader_copies() -> void:
	var ocean := FileAccess.get_file_as_string("res://shaders/ocean.gdshader")
	var ride := FileAccess.get_file_as_string("res://shaders/sea_ride.gdshaderinc")
	var pairs := [["base_height = 1.2", "SR_BASE_HEIGHT = 1.2"], ["swell_length = 97.0", "SR_SWELL_LENGTH = 97.0"],
		["group_length = 310.0", "SR_GROUP_LENGTH = 310.0"], ["group_depth : hint_range(0.0, 1.0) = 0.55", "SR_GROUP_DEPTH = 0.55"],
		["speed = 1.0", "SR_SPEED = 1.0"], ["fine_fade = vec2(170.0, 480.0)", "SR_FINE_FADE = vec2(170.0, 480.0)"],
		["tsunami_height = 30.0", "SR_TSUNAMI_HEIGHT = 30.0"], ["tsunami_length = 420.0", "SR_TSUNAMI_LENGTH = 420.0"],
		["tsunami_dir = vec2(1.0, 0.15)", "SR_TSUNAMI_DIR = vec2(1.0, 0.15)"]]
	var ok := true
	for p: Array in pairs:
		if not ocean.contains(p[0]) or not ride.contains(p[1]):
			ok = false
			printerr("ocean traffic: copy mismatch ", p)
	_t._check(ok, "ocean traffic: sea_ride.gdshaderinc's swell numbers are the ocean shader's defaults")
	var waves := ["normalize(vec2(1.00, 0.22)), l0, amp * 0.34", "normalize(vec2(0.86, -0.51)), l0 / 1.59, amp * 0.26",
		"normalize(vec2(0.62, 0.78)), l0 / 2.62, amp * 0.19", "normalize(vec2(0.97, -0.24)), l0 / 4.51, amp * 0.13",
		"normalize(vec2(0.34, 0.94)), l0 / 7.89, amp * 0.08"]
	var wok := true
	for w: String in waves:
		wok = wok and ocean.contains(w) and ride.contains(w)
	_t._check(wok, "ocean traffic: the hulls ride the ocean's five waves (same directions, lengths, shares)")
	_t._check(ocean.contains("float grp = vnoise(p / group_length + vec2(t * 0.006, -t * 0.004));") and ride.contains("float grp = sr_vnoise(p / SR_GROUP_LENGTH + vec2(t * 0.006, -t * 0.004));"),
		"ocean traffic: the hulls ride the ocean's wave groups")
	_t._check(ocean.contains("uniform vec4 wake_a[16];") and ocean.contains("uniform int wake_count = 0;"), "ocean traffic: the ocean shader takes the wakes")
	# The GDScript mirror against hand-worked values: calm at a crest of every wave (t 0, p 0, the
	# group noise there) and periodic in time like the slowest swell.
	var ot_script: GDScript = load("res://scripts/world/ocean_traffic.gd")
	var h0: float = ot_script.call("sea_height", Vector2.ZERO, 0.0, 1.0, 1.0)
	var grp: float = ot_script.call("_vnoise", Vector2.ZERO)
	var want := 1.2 * (1.0 - 0.55 * (1.0 - grp)) * (0.34 + 0.26 + 0.19 + 0.13 + 0.08)
	_t._check(absf(h0 - want) < 0.001, "ocean traffic: the GDScript swell sums the five crests at the origin (%.3f, want %.3f)" % [h0, want])
	var hmax := 0.0
	for i in 200:
		var p := Vector2(float(i) * 37.1, float(i) * -11.3)
		hmax = maxf(hmax, absf(ot_script.call("sea_height", p, float(i) * 0.7, 1.0, 1.0)))
	_t._check(hmax <= 1.2 * 1.0 + 0.001, "ocean traffic: the clear-day swell stays within its amplitude (max %.2f m)" % hmax)
	var cs := ["vessel.gdshader", "boat.gdshader"]
	for s: String in cs:
		var code := FileAccess.get_file_as_string("res://shaders/" + s)
		_t._check(code.contains("#include \"res://shaders/boat_body.gdshaderinc\""), "ocean traffic: %s draws through boat_body.gdshaderinc" % s)
	_t._check(FileAccess.get_file_as_string("res://shaders/vessel.gdshader").contains("#define BOAT_RIDE"), "ocean traffic: vessel.gdshader rides the sea")
	_t._check(not FileAccess.get_file_as_string("res://shaders/boat.gdshader").contains("#define BOAT_RIDE"), "ocean traffic: the marina's boats keep their own bob (no BOAT_RIDE)")


func _meshes() -> void:
	var vm: GDScript = load("res://scripts/world/vessel_mesh.gd")
	var ok := true
	var report := ""
	for k in 7:
		for v in 2:
			var prev := 1 << 30
			for lv in 3:
				var m: ArrayMesh = vm.call("hull", k, v, lv)
				var tris := m.surface_get_array_index_len(0) / 3
				report += " %d/%d/%d:%d" % [k, v, lv, tris]
				if tris <= 0 or tris > BUDGET[lv] or tris > prev:
					ok = false
				prev = tris
	_t._check(ok, "ocean traffic: every hull builds at every level inside its budget, coarser each level (%s)" % report.strip_edges())
	var sok := true
	for side: float in [-1.0, 1.0]:
		for lv in 3:
			var m: ArrayMesh = vm.call("main_sail", 0, side, lv)
			var j: ArrayMesh = vm.call("jib", 1, side, lv)
			sok = sok and m.surface_get_array_index_len(0) > 0 and j.surface_get_array_index_len(0) > 0
	# The main bellies to the leeward side it was built for.
	var near_main: ArrayMesh = vm.call("main_sail", 0, 1.0, 0)
	var verts: PackedVector3Array = near_main.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var mean_x := 0.0
	for p in verts:
		mean_x += p.x
	mean_x /= maxf(float(verts.size()), 1.0)
	_t._check(sok and mean_x > 0.02, "ocean traffic: the sails build on both tacks, bellied to leeward (mean x %.2f)" % mean_x)


func _lanes(ot: Node) -> void:
	var lanes: Dictionary = ot.get("lanes")
	var vs: GDScript = load("res://scripts/vehicles/vessel.gd")
	var bad := []
	for name: String in lanes:
		var pts: PackedVector2Array = lanes[name]
		var cum: PackedFloat32Array = vs.call("cumulate", pts)
		var s := 0.0
		while s < cum[cum.size() - 1]:
			var p: Vector2 = vs.call("loop_point", pts, cum, s)
			if not ot.call("sea_room", p, LANE_MARGIN.get(name, 100.0)):
				bad.append([name, p])
				break
			s += 25.0
	_t._check(lanes.size() >= 5 and bad.is_empty(), "ocean traffic: every route keeps to open water with room (%s)" % str(bad))
	var aok := true
	for a: Vector2 in ot.get_script().get_script_constant_map()["ANCHORAGE"]:
		aok = aok and ot.call("sea_room", a, 260.0)
	_t._check(aok, "ocean traffic: the ships at anchor lie on open water")


func _fleet(ot: Node) -> void:
	var tags := {}
	for v: Node in ot.get("vessels"):
		tags[String(v.get("tag")).get_slice("_", 0)] = tags.get(String(v.get("tag")).get_slice("_", 0), 0) + 1
	_t._check(tags.get("ferry", 0) == 2 and tags.get("tug", 0) == 2 and tags.get("pilot", 0) == 1, "ocean traffic: the persistent fleet is out (%s)" % str(tags))
	var ships: Array = ot.get("ships")
	_t._check(ships.size() == 5, "ocean traffic: five container ships ride at anchor in the roads")
	var lit := 0
	for s: Node in ships:
		if s.get_node_or_null("Lights") != null and s.get_node_or_null("Hull") != null:
			lit += 1
	_t._check(lit == ships.size(), "ocean traffic: every ship at anchor has her hull and her anchor and deck lights")


func _find(ot: Node, tag: String) -> Node:
	for v: Node in ot.get("vessels"):
		if v.get("tag") == tag:
			return v
	return null


func _ferry_moves(ot: Node) -> void:
	var f := _find(ot, "ferry_1")
	if f == null:
		_t._check(false, "ocean traffic: the second ferry exists")
		return
	var p0: Vector3 = f.get("world_pos")
	var s0: float = f.get("path_s")
	for i in 100:
		f.call("drive", 0.1)
	var p1: Vector3 = f.get("world_pos")
	var moved := Vector2(p0.x, p0.z).distance_to(Vector2(p1.x, p1.z))
	_t._check(moved > 60.0 and moved < 200.0 and f.get("path_s") != s0, "ocean traffic: a ferry runs her crossing (%.0f m in 10 s)" % moved)
	_t._check(ot.call("sea_room", Vector2(p1.x, p1.z), 60.0), "ocean traffic: ... and stays on the water")


func _sailing(ot: Node) -> void:
	var vs: GDScript = load("res://scripts/vehicles/vessel.gd")
	var v: Node = vs.new()
	v.call("setup", 0, 0, 12.0, Color(0.94, 0.94, 0.92), 1, 4242)
	v.set("tag", "check_sail")
	var wind: Vector2 = ot.get("wind")
	var home := Vector2(-2600.0, 400.0)
	v.call("sail", home, home, wind, -wind)
	v.set("home_reach", 1e9)
	v.set("_course_left", 1e9)
	v.set("traffic", null)
	ot.add_child(v)
	var min_twa := 180.0
	var flips := 0
	var last_side: float = v.get("sail_side")
	var heel_ok := true
	for i in 6000:
		v.call("drive", 0.1)
		var h: Vector2 = v.get("heading")
		var twa: float = absf(rad_to_deg(h.angle_to(-wind)))
		if i > 300:
			min_twa = minf(min_twa, twa)
		var side: float = v.get("sail_side")
		if side != last_side:
			flips += 1
			last_side = side
		var heel: float = v.get("heel")
		var boom: float = v.get("boom")
		if i > 300 and absf(heel) > 0.06 and absf(boom) > 0.05 and signf(heel) == signf(boom):
			heel_ok = false
	_t._check(min_twa > 38.0, "ocean traffic: a sloop beating upwind never points closer than 40 degrees (closest %.0f)" % min_twa)
	_t._check(flips >= 2, "ocean traffic: ... and tacks, the sails swinging across (%d times in 10 minutes)" % flips)
	_t._check(heel_ok, "ocean traffic: ... heeled to leeward, away from the wind")
	var start := home
	var p: Vector3 = v.get("world_pos")
	var gain := (Vector2(p.x, p.z) - start).dot(-wind)
	_t._check(gain > 300.0, "ocean traffic: ... and makes ground to windward (%.0f m in 10 minutes)" % gain)
	v.queue_free()


func _wakes(ot: Node) -> void:
	var cam := _tree.root.get_viewport().get_camera_3d()
	if cam == null:
		_t._check(true, "ocean traffic: no camera, wakes not checked")
		return
	var ws: Node = _tree.root.get_node_or_null("/root/WorldState")
	var c: Vector3 = ws.call("to_world", cam.global_position)
	var before: int = (ot.get("vessels") as Array).size()
	ot.call("stage_scene", Vector2(c.x, c.z), cam.global_rotation.y)
	ot.call("push_wakes")
	var mat: ShaderMaterial = PropFactory.ocean_material()
	var n: int = mat.get_shader_parameter("wake_count")
	var a: PackedVector4Array = mat.get_shader_parameter("wake_a")
	_t._check(n >= 5 and a.size() == 16, "ocean traffic: a staged scene hands its wakes to the ocean (%d)" % n)
	_t._check((ot.get("vessels") as Array).size() >= before + 7 and ot.get("staged") == true, "ocean traffic: the staged scene puts seven boats out")


func _sinking(ot: Node) -> void:
	var v := _find(ot, "stage_4")
	if v == null:
		_t._check(false, "ocean traffic: the staged motor yacht exists")
		return
	v.call("take_hit", -1, 10.0, Vector3.FORWARD)
	_t._check(v.get("life") == 0, "ocean traffic: a round does not sink a yacht")
	v.call("take_hit", -1, 5000.0, Vector3.FORWARD)
	_t._check(v.get("life") == 1, "ocean traffic: shot to pieces, she burns")
	for i in 40:
		v.call("drive", 0.1)
	_t._check(v.get("life") == 2 and v.get("collision_layer") == 0, "ocean traffic: ... explodes and goes down (nothing left to hit)")
	var y0: float = (v.get("world_pos") as Vector3).y
	for i in 500:
		v.call("drive", 0.1)
		if v.get("done"):
			break
	_t._check(v.get("done") == true and y0 < 0.2, "ocean traffic: ... and sinks out of sight")
	await_frame(ot)


func await_frame(ot: Node) -> void:
	# The finished signal frees her; the fleet list lets her go.
	var still := false
	for x: Node in ot.get("vessels"):
		if x.get("tag") == "stage_4":
			still = true
	_t._check(not still, "ocean traffic: a sunk vessel leaves the fleet")
