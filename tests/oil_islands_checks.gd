extends RefCounted
## Checks for the decorated oil islands in the bay (OilIslands, OilIslandBuild; docs/HANDOFF.md,
## "The oil islands"), run from tests/smoke_test.gd: where they stand (at sea, off the Long
## Beach sand, clear of the port, the berth and each other), the plan (pad, berm, wall, towers
## inside the wall, the falls on the shore side), the shader's copies and codes, and the near and
## far builds (collision only near, the far copy's planting shadowless, no boulders far).
## Loaded at run time so it can name the classes freely.

var _t: Node


func run(t: Node, city: Node3D) -> void:
	_t = t
	var plan: CityPlan = city.get("plan")
	if plan == null or plan.macro == null:
		return
	var macro: MacroMap = plan.macro
	var ids := []
	for lm in Landmarks.all():
		if OilIslands.is_island(lm.id):
			ids.append(lm)
	if not OilIslands.enabled:
		_t._check(ids.is_empty(), "OIL_ISLANDS=0 lists no oil island")
		return
	_t._check(ids.size() == OilIslands.ISLANDS.size(), "every oil island is a landmark (%d of %d)" % [ids.size(), OilIslands.ISLANDS.size()])
	var wet := ""
	var shore := ""
	var port := ""
	for i in OilIslands.ISLANDS.size():
		var a: Vector2 = OilIslands.ISLANDS[i].anchor
		for k in 48:
			var p := OilIslands.to_world(i, OilIslands.ring_local(i, TAU * float(k) / 48.0, 26.0))
			if macro.zone_at(p) != MacroMap.Zone.OCEAN:
				wet += " %d@%s" % [i, p]
				break
			for r: Rect2 in [macro.port_rect, macro.harbor_rect]:
				if r.grow(40.0).has_point(p):
					port += " %d" % i
		var off := a.y - macro.bay_z
		if off < 400.0 or off > 1200.0 or a.x <= macro.port_rect.end.x or a.x >= macro.bay_east_x:
			shore += " %d (%.0f m)" % [i, off]
		for j in range(i + 1, OilIslands.ISLANDS.size()):
			var b: Vector2 = OilIslands.ISLANDS[j].anchor
			var ri: float = (OilIslands.ISLANDS[i].half as Vector2).x + 22.0
			var rj: float = (OilIslands.ISLANDS[j].half as Vector2).x + 22.0
			_t._check(a.distance_to(b) > ri + rj + 30.0, "oil islands %d and %d stand apart (%.0f m)" % [i, j, a.distance_to(b)])
	_t._check(wet == "", "every oil island's revetment stands in open water (not:%s)" % wet)
	_t._check(shore == "", "the oil islands lie 400-1200 m off the Long Beach sand, east of the port (not:%s)" % shore)
	_t._check(port == "", "no oil island reaches the port or its berth (%s)" % port)
	# The plan.
	var plan_bad := ""
	for i in OilIslands.ISLANDS.size():
		var c := OilIslands.to_world(i, Vector2.ZERO)
		if absf(OilIslands.surface_at(c) - OilIslands.PAD_Y) > 0.01:
			plan_bad += " pad%d" % i
		if not is_nan(OilIslands.surface_at(OilIslands.to_world(i, OilIslands.ring_local(i, 1.0, 40.0)))):
			plan_bad += " sea%d" % i
		var berm := OilIslands.surface_at(OilIslands.to_world(i, OilIslands.ring_local(i, 2.0, -9.0)))
		if berm <= OilIslands.PAD_Y + 0.5:
			plan_bad += " berm%d" % i
		var wl := OilIslands.surface_at(OilIslands.to_world(i, OilIslands.ring_local(i, 2.0, float(OilIslands.RINGS[2][0]))))
		# surface_at() measures along the ray from the centre, the rings along the edge's normal.
		if absf(wl) > 0.8:
			plan_bad += " waterline%d" % i
		for tw: Dictionary in OilIslands.towers(i):
			var tc := OilIslands.to_world(i, tw.at)
			if OilIslands.edge_distance(i, tc) > -(OilIslands.WALL_IN + OilIslands.TOWER_HALF + 8.0):
				plan_bad += " tower%d" % i
		var f := OilIslands.edge_local(i, OilIslands.falls_angle(i))
		if OilIslands.to_world(i, f).y > OilIslands.ISLANDS[i].anchor.y:
			plan_bad += " falls%d" % i
		if str(OilIslands.towers(i)) != str(OilIslands.towers(i)):
			plan_bad += " roll%d" % i
	_t._check(plan_bad == "", "oil islands: pad, berm, waterline, towers inside the wall, falls facing the shore (bad:%s)" % plan_bad)
	# The vertex code survives 8-bit storage for every kind and wash.
	var code_bad := 0
	for kind in 16:
		for wash in 8:
			var a8 := roundf(OilIslandBuild.code(kind, wash) * 255.0) / 255.0
			var c := int(floor(a8 * 128.0))
			if c % 16 != kind or c / 16 != wash:
				code_bad += 1
	_t._check(code_bad == 0, "oil island vertex codes decode exactly from 8 bits (%d wrong)" % code_bad)
	# The shader's copy of the night washes.
	var src := FileAccess.get_file_as_string("res://shaders/oil_island.gdshader")
	var m := RegEx.create_from_string("vec3\\(([0-9.]+), ([0-9.]+), ([0-9.]+)\\)")
	var start := src.find("WASHES[8]")
	var found := m.search_all(src.substr(start, src.find(");", start) - start))
	var wash_ok := found.size() == OilIslands.WASHES.size()
	for k in mini(found.size(), OilIslands.WASHES.size()):
		var w: Color = OilIslands.WASHES[k]
		var v := Vector3(float(found[k].get_string(1)), float(found[k].get_string(2)), float(found[k].get_string(3)))
		wash_ok = wash_ok and v.distance_to(Vector3(w.r, w.g, w.b)) < 1e-4
	_t._check(wash_ok, "oil_island.gdshader's WASHES match OilIslands.WASHES (%d found)" % found.size())
	# Near and far builds of the first island.
	var ws := _t.get_tree().root.get_node("/root/WorldState")
	var off3: Vector3 = ws.get("world_offset")
	var lm0: Dictionary = ids[0]
	var near := Node3D.new()
	near.position = -off3
	city.add_child(near)
	Landmarks.build(lm0, near, null, plan, true)
	var near_tris := OilIslandBuild.last_triangles
	var far := Node3D.new()
	far.position = -off3
	city.add_child(far)
	Landmarks.build(lm0, far, null, plan, false)
	var far_tris := OilIslandBuild.last_triangles
	var n := _scan(near)
	var f2 := _scan(far)
	_t._check(n.mesh and f2.mesh, "both oil island copies have their mesh")
	_t._check(n.shapes > 10 and f2.shapes == 0, "the detailed oil island collides, the far one does not (%d / %d shapes)" % [n.shapes, f2.shapes])
	_t._check(n.palms > 20 and n.palms == f2.palms, "the far oil island plants the detailed one's palms (%d near, %d far)" % [n.palms, f2.palms])
	_t._check(n.boulders > 500 and f2.boulders == 0, "boulders on the detailed revetment only (%d near, %d far)" % [n.boulders, f2.boulders])
	_t._check(f2.shadowed == 0, "the far oil island's planting casts no shadow (%d)" % f2.shadowed)
	_t._check(far_tris > 2000 and far_tris < near_tris and near_tris < 60000,
		"oil island mesh budget (near %d, far %d triangles)" % [near_tris, far_tris])
	var lamps := 0
	for l in near.find_children("*", "OmniLight3D", true, false):
		if (l as Node).is_in_group("lamp_light"):
			lamps += 1
	_t._check(OS.has_feature("web") or lamps == (OilIslands.ISLANDS[0].towers as int) + 1, "the detailed oil island's floods are lamp_light omnis (%d)" % lamps)
	near.free()
	far.free()


func _scan(root: Node) -> Dictionary:
	var out := {"mesh": false, "shapes": 0, "palms": 0, "boulders": 0, "shadowed": 0}
	for c in root.find_children("*", "", true, false):
		if c is MeshInstance3D and String(c.name).begins_with("OilIsland_"):
			out.mesh = true
		if c is CollisionShape3D:
			out.shapes += 1
		if c is MultiMeshInstance3D and (c as MultiMeshInstance3D).multimesh:
			var mm := (c as MultiMeshInstance3D).multimesh
			var nm := String(c.name)
			if nm.contains("palm_"):
				if nm.begins_with("Batch_"):
					out.palms += mm.instance_count
				if (c as GeometryInstance3D).cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
					out.shadowed += 1
			elif nm.begins_with("Batch_oil_boulder"):
				out.boulders += mm.instance_count
	return out
