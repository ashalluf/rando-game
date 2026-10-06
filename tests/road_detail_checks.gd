extends RefCounted
## The road's hardware (RoadHardware: covers, valves, kerb inlets, utility cuts, steel plates,
## raised markers, Botts' dots), for tests/smoke_test.gd. Loaded at run time, not named there, so
## it compiles after the autoloads.
##
## Builds FULL midtown chunks straight from the plan (city._new_chunk + build()) and checks: every
## kind is laid; each kind is ONE shadowless batch on the road hardware shader; nothing on the
## carriageway reaches into the crosswalks and stop lines at a road's ends; the shader's K_*
## constants are RoadHardware's; the light rail's trackway is kept clear; and the block built
## with it off is the same block (hash-seeded, the chunk rng untouched), with the old pieces back.
## Placements come from the chunk's "road_hardware" meta (instance transforms read back as
## identity under --headless).

var _t: Object

const LANE_KINDS := ["cover", "valve", "cut", "plate", "marker", "botts"]
const KEYS := ["rh_cover_round", "rh_cover_square", "rh_valve", "rh_cut", "rh_plate", "rh_marker", "rh_botts", "rh_inlet", "rh_inlet_grate"]
## A crosswalk ends 3.3 m into the road from the junction square, its stop line 3.5 m.
const CROSSWALK_REACH := 3.5


func run(t: Object, city: Node3D) -> void:
	_t = t
	var plan: CityPlan = city.plan
	_shader_kinds()
	_pure(plan)
	_built(city, plan)


func _shader_kinds() -> void:
	var src := FileAccess.get_file_as_string("res://shaders/road_hardware.gdshader")
	var names := ["K_IRON", "K_FRAME", "K_ASPHALT", "K_SEAL", "K_CONCRETE", "K_STEEL", "K_VOID", "K_CERAMIC", "K_REFLECT", "K_PAINT", "K_CUT", "K_PLATE"]
	var consts: Dictionary = (load("res://scripts/world/road_hardware.gd") as GDScript).get_script_constant_map()
	var bad: Array = []
	for i in names.size():
		if src.find("const int %s = %d;" % [names[i], i]) < 0 or int(consts.get(names[i], -1)) != i:
			bad.append(names[i])
	_t._check(bad.is_empty(), "the road hardware shader's surface kinds match RoadHardware's (%s)" % [bad])


func _pure(plan: CityPlan) -> void:
	_t._check(RoadHardware.INLET_ALONG - RoadHardware.INLET_APRON >= 3.3 + 0.2,
		"a kerb inlet's apron starts past the crosswalk (%.1f m from the corner)" % (RoadHardware.INLET_ALONG - RoadHardware.INLET_APRON))
	_t._check(RoadHardware.END_STREET >= CROSSWALK_REACH + 2.0 and RoadHardware.END_AVENUE >= 10.7 + 1.0,
		"lane items keep clear of crosswalks, stop lines and lane arrows")
	# The rail trackway: a point on the rail street's centre line is refused.
	var rail := LightRail.of(plan)
	if rail != null:
		var road := {"axis": CityPlan.AXIS_X, "index": rail.avenue_index, "c": plan.road_pos(CityPlan.AXIS_X, rail.avenue_index), "w": 24.0, "a": 0.0, "b": 100.0, "along_z": true}
		var p := RoadHardware.road_point(road, 50.0, 0.5)
		_t._check(not RoadHardware._lane_ok(plan, road, p, 0.5) and RoadHardware._lane_ok(plan, road, RoadHardware.road_point(road, 50.0, 8.0), 8.0),
			"nothing is laid on the light rail's trackway, but its outer lanes still get covers")


func _built(city: Node3D, plan: CityPlan) -> void:
	# Midtown blocks of buildings with an avenue among their roads (Botts' dots are avenue lane lines).
	var centre := plan.block_index_at(Vector2(950.0, 650.0))
	var keys: Array[Vector2i] = []
	for dz in range(-3, 4):
		for dx in range(-3, 4):
			var k := centre + Vector2i(dx, dz)
			var b := plan.block(k.x, k.y)
			if int(b.district) != CityPlan.District.MIDTOWN or int(b.kind) != CityPlan.BlockKind.BUILDINGS or b.has("site"):
				continue
			if plan.zone_at((b.rect as Rect2).get_center()) != MacroMap.Zone.CITY:
				continue
			keys.append(k)
	_t._check(keys.size() >= 4, "midtown has blocks of buildings to lay road hardware on (%d)" % keys.size())
	# Avenue blocks first.
	keys.sort_custom(func(p: Vector2i, q: Vector2i) -> bool: return _has_avenue(plan, p) and not _has_avenue(plan, q))
	var seen := {}
	var batch_ok := true
	var reach_bad: Array = []
	var same := true
	var old_back := true
	var count := 0
	for k in keys.slice(0, 5):
		var chunk: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
		chunk.build()
		var rec: Array = chunk.get_meta("road_hardware", [])
		count += rec.size()
		var rect: Rect2 = plan.block(k.x, k.y).rect
		var roads := RoadHardware.roads_of(plan, k.x, k.y, rect)
		for r: Dictionary in rec:
			seen[r.kind] = true
			if r.kind in LANE_KINDS:
				var m := _margin(r, roads)
				if m < CROSSWALK_REACH:
					reach_bad.append("%s %.1f" % [r.kind, m])
		for key: String in KEYS:
			var node := chunk.get_node_or_null("Batch_" + key) as MultiMeshInstance3D
			if node == null:
				continue
			var mesh: Mesh = node.multimesh.mesh
			var mat := mesh.surface_get_material(0) as ShaderMaterial
			batch_ok = batch_ok and mesh.get_surface_count() == 1 and mat != null and mat.shader.resource_path.ends_with("road_hardware.gdshader") \
				and node.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var sig := _signature(chunk)
		chunk.get_parent().remove_child(chunk)
		chunk.free()
		RoadHardware.enabled = false
		var bare: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
		bare.build()
		RoadHardware.enabled = true
		same = same and _signature(bare) == sig
		for key: String in KEYS:
			old_back = old_back and bare.get_node_or_null("Batch_" + key) == null
		old_back = old_back and (bare.get_node_or_null("Batch_grate") != null or bare.get_node_or_null("Batch_kerb_inlet") != null)
		bare.get_parent().remove_child(bare)
		bare.free()
	var missing := ["cover", "valve", "cut", "inlet", "marker", "botts"].filter(func(kd: String) -> bool: return not seen.has(kd))
	_t._check(missing.is_empty(), "midtown roads carry covers, valves, inlets, cuts, markers and Botts' dots (missing %s; %d pieces)" % [missing, count])
	_t._check(batch_ok, "each kind of road hardware is one shadowless batch on its shader")
	_t._check(reach_bad.is_empty(), "nothing on the carriageway reaches into a crosswalk or stop line (%s)" % [reach_bad.slice(0, 6)])
	_t._check(same, "the road hardware rolls nothing from the block: built without it, the block is the same")
	_t._check(old_back, "off (ROAD_DETAIL=0), no road hardware batch and the old grates and inlets are back")


func _has_avenue(plan: CityPlan, k: Vector2i) -> bool:
	return plan.road_width(CityPlan.AXIS_X, k.x + 1) > plan.street_width + 1.0 or plan.road_width(CityPlan.AXIS_Z, k.y + 1) > plan.street_width + 1.0


## How far a lane piece's extent stays from either end of its road segment (metres).
func _margin(r: Dictionary, roads: Array) -> float:
	var p: Vector2 = r.pos
	var half := 0.06
	match String(r.kind):
		"cover":
			half = RoadHardware.COLLAR_SQ * 1.42 if r.get("square", false) else RoadHardware.COLLAR_R
		"valve":
			half = RoadHardware.VALVE_COLLAR_R
		"cut":
			half = (r.size as Vector2).y * 0.5
		"plate":
			half = RoadHardware.PLATE.y * 0.5 + RoadHardware.PLATE_RAMP
	var best := INF
	for road: Dictionary in roads:
		var across := p.x if road.along_z else p.y
		var along := p.y if road.along_z else p.x
		if absf(across - float(road.c)) > float(road.w) * 0.5 + 0.5:
			continue
		best = minf(along - float(road.a), float(road.b) - along) - half
	# A piece on neither road (a storm drain's cover in front of an inlet on a -X / -Z kerb) is
	# placed from its inlet, which is past the crosswalk by construction.
	return best if best < INF else 99.0


## Buildings, props and trash cans of a chunk, by position.
func _signature(chunk: CityChunk) -> Array:
	var out: Array = []
	for c in chunk.get_children():
		if c is Building or c is TrashCan:
			var p: Vector3 = (c as Node3D).position
			out.append("%s %.2f %.2f" % [c.get_class(), p.x, p.z])
	for r in chunk.prop_records:
		out.append("%s %.2f %.2f" % [r.kind, (r.position as Vector3).x, (r.position as Vector3).z])
	out.sort()
	return out
