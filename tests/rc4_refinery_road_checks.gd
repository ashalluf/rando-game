extends RefCounted
## The refinery's road at night (RcRefineryRoad, refcam refinery_night in tools/refcams/cameras_w6.json),
## for tests/smoke_test.gd. Loaded at run time, not named there, so it compiles after the autoloads.
##
## The road shader's block is off by default (rr_on 0: every other road bit for bit) and its falloffs
## are the GDScript copy's; the roads and pavements near the plant are dressed with its flares and
## fence masts, far ones are not; the street lamps along the plant's perimeter are patchy (a share
## out, pure); the pavement ring is wound to face up with a kerb face; a FULL site chunk wears it.

const EYE := Vector2(3180.0, 5838.0)

var _t: Node


func run(t: Node, city: Node3D) -> void:
	_t = t
	_shader()
	if not Refinery.enabled:
		return
	var plan: CityPlan = city.plan
	var lay := Refinery.layout(plan)
	if lay.is_empty():
		return
	_lights(plan, lay)
	_roads(plan, lay)
	_lamps(plan, lay)
	_chunk(city, plan, lay)


## A material's rr_on (unset reads null: off).
func _on(m: ShaderMaterial) -> bool:
	var v: Variant = m.get_shader_parameter("rr_on")
	return v != null and float(v) > 0.5


func _shader() -> void:
	var inc := FileAccess.get_file_as_string("res://shaders/refinery_road.gdshaderinc")
	var road := FileAccess.get_file_as_string("res://shaders/road.gdshader")
	_t._check(road.contains("#include \"res://shaders/refinery_road.gdshaderinc\"") and road.contains("if (rr_on > 0.5)"),
		"rc4-refinery-road: road.gdshader takes the plant's light behind rr_on")
	_t._check(inc.contains("uniform float rr_on = 0.0;"), "rc4-refinery-road: rr_on is off by default (every other road unchanged)")
	_t._check(inc.contains("uniform vec4 rr_masts[%d];" % RcRefineryRoad.MAX_MASTS) and inc.contains("uniform vec4 rr_flares[8];"),
		"rc4-refinery-road: the shader's slots are RcRefineryRoad's")
	_t._check(inc.contains("float fall = (half_d * half_d) / (half_d * half_d + dist * dist);")
		and inc.contains("return pow(q, -1.5) * (1.0 - smoothstep(reach * 0.7, reach, r));"),
		"rc4-refinery-road: the shader's falloffs are RcRefineryRoad.light_at()'s")
	_t._check(FileAccess.get_file_as_string("res://shaders/refinery.gdshader").contains("uniform float rc4_look = 0.0;"),
		"rc4-refinery-road: the plant's old tank look is the default (rc4_look 0)")
	var lamp := FileAccess.get_file_as_string("res://shaders/street_lamp.gdshader")
	_t._check(lamp.contains("is_out = INSTANCE_CUSTOM.b;"), "rc4-refinery-road: a lamp that is out is dark (INSTANCE_CUSTOM.b)")


func _lights(plan: CityPlan, lay: Dictionary) -> void:
	var fl := RcRefineryRoad.flares(lay, plan)
	var ms := RcRefineryRoad.masts(lay, plan)
	var inner: Rect2 = lay.inner
	var on_fence := true
	for m: Vector4 in ms:
		var p := Vector2(m.x, m.z)
		var edge := minf(minf(p.x - inner.position.x, inner.end.x - p.x), minf(p.y - inner.position.y, inner.end.y - p.y))
		on_fence = on_fence and edge <= RcRefineryRoad.MAST_FENCE and inner.has_point(p)
	_t._check(fl.size() > 0 and ms.size() >= 8 and ms.size() <= RcRefineryRoad.MAX_MASTS and on_fence,
		"rc4-refinery-road: the road takes %d flares and %d fence-line masts" % [fl.size(), ms.size()])
	# Brighter near the flares than at the eye, and nothing far away.
	var gy := plan.height_at(EYE)
	var f0 := Vector2(fl[0].x, fl[0].z) if fl.size() > 0 else EYE
	var near := RcRefineryRoad.light_at(lay, plan, Vector3(f0.x, gy, (lay.rect as Rect2).end.y + 7.0))
	var at_eye := RcRefineryRoad.light_at(lay, plan, Vector3(EYE.x, gy, EYE.y))
	var far := RcRefineryRoad.light_at(lay, plan, Vector3(EYE.x + 900.0, gy, EYE.y + 400.0))
	_t._check(near > at_eye * 2.0 and at_eye > 0.0 and far == 0.0,
		"rc4-refinery-road: the flares' light falls off along the street (%.3f near, %.3f at the eye, %.3f far)" % [near, at_eye, far])


func _roads(plan: CityPlan, lay: Dictionary) -> void:
	var rect: Rect2 = lay.rect
	var iz := plan.block_index_at(Vector2(rect.get_center().x, rect.end.y + 3.0)).y
	# The street along the plant's south side is the +Z road of the row inside it.
	var found := false
	for i in range(iz - 1, iz + 2):
		if absf(plan.road_pos(CityPlan.AXIS_Z, i) - (rect.end.y + plan.road_width(CityPlan.AXIS_Z, i) * 0.5)) < 1.5:
			found = RcRefineryRoad.perimeter_road(plan, CityPlan.AXIS_Z, i) and RcRefineryRoad.near_road(plan, CityPlan.AXIS_Z, i)
	_t._check(found, "rc4-refinery-road: the plant's south street is a perimeter road, near it")
	var far_idx := plan.block_index_at(Vector2(rect.get_center().x, rect.position.y - RcRefineryRoad.NEAR - 600.0)).y
	_t._check(not RcRefineryRoad.near_road(plan, CityPlan.AXIS_Z, far_idx), "rc4-refinery-road: a street 1 km off is not dressed")
	var base := PropFactory.road("asphalt", 7.0, Color(0.8, 0.8, 0.8), 4242)
	var d := RcRefineryRoad.road_material(base, plan, CityPlan.AXIS_Z, iz)
	if RcRefineryRoad.enabled:
		_t._check(d != base and _on(d) and not _on(base),
			"rc4-refinery-road: a near road wears a dressed copy, the shared material is untouched")
		_t._check(RcRefineryRoad.road_material(base, plan, CityPlan.AXIS_Z, far_idx) == base, "rc4-refinery-road: a far road keeps its material")


func _lamps(plan: CityPlan, lay: Dictionary) -> void:
	var rect: Rect2 = lay.rect
	var out := 0
	var lit := 0
	var same := true
	for i in 60:
		var p := Vector2(rect.position.x + rect.size.x * (i + 0.5) / 60.0, rect.end.y + 15.0)
		var s := RcRefineryRoad.lamp_state(plan, p)
		same = same and s == RcRefineryRoad.lamp_state(plan, p)
		if s.is_empty():
			continue
		if s.out:
			out += 1
		else:
			lit += 1
	if RcRefineryRoad.enabled:
		_t._check(same and out > 10 and lit > 10, "rc4-refinery-road: the plant's street lamps are patchy, pure (%d out, %d dim)" % [out, lit])
	_t._check(RcRefineryRoad.lamp_state(plan, rect.get_center() + Vector2(0.0, rect.size.y + 300.0)).is_empty(),
		"rc4-refinery-road: a lamp a block away burns as before")


func _chunk(city: Node3D, plan: CityPlan, lay: Dictionary) -> void:
	var rect: Rect2 = lay.rect
	# The pavement ring's piece, wound face up, with a kerb face down to the road (CPU-side arrays).
	var k := plan.block_index_at(Vector2(EYE.x, rect.end.y - 20.0))
	var chunk: CityChunk = city._new_chunk(k, CityChunk.Level.FULL)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var piece := Rect2(rect.end.x - 40.0, rect.end.y - Refinery.PAVEMENT, 40.0, Refinery.PAVEMENT)
	RcRefineryRoad.ring_piece(chunk, st, piece, rect, CityChunk.SIDEWALK_TOP)
	var arr := st.commit_to_arrays()
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var n: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var up_ok := v.size() >= 6 and (v[1] - v[0]).cross(v[2] - v[0]).y < 0.0
	# Every face: clockwise toward its normal (Godot's front face).
	var faces_ok := true
	var kerb := 0
	for i in range(0, v.size(), 3):
		var g := (v[i + 1] - v[i]).cross(v[i + 2] - v[i])
		faces_ok = faces_ok and g.dot(n[i]) < 0.0
		if absf(n[i].y) < 0.5:
			kerb += 1
	_t._check(up_ok and faces_ok and kerb == 4, "rc4-refinery-road: the pavement ring faces up, with its kerb faces (%d kerb triangles)" % kerb)
	if not RcRefineryRoad.enabled:
		chunk.queue_free()
		return
	chunk.build()
	var dressed := 0
	for c in chunk.get_children():
		if c is MeshInstance3D and (c as MeshInstance3D).material_override is ShaderMaterial:
			var m := (c as MeshInstance3D).material_override as ShaderMaterial
			if m.shader != null and m.shader.resource_path.ends_with("road.gdshader") and _on(m):
				dressed += 1
	_t._check(dressed >= 2, "rc4-refinery-road: the site chunk's street and pavement wear the plant's light (%d meshes)" % dressed)
	_t._check(int(chunk.get_meta("rr_verge", 0)) > 20, "rc4-refinery-road: weeds grow along the fence's foot (%d)" % int(chunk.get_meta("rr_verge", 0)))
	var look: Variant = RefineryKit.material().get_shader_parameter("rc4_look")
	_t._check(look != null and float(look) > 0.5, "rc4-refinery-road: the plant's tanks take their floods in fans")
	chunk.queue_free()
	# The flares' smoke: one node of puffs on its own shader.
	var host := Node3D.new()
	RcRefineryRoad.add_smoke(host, [Vector3(0.0, 90.0, 0.0), Vector3(30.0, 80.0, 0.0)])
	var smoke := host.get_node_or_null("RefineryFlareSmoke") as MeshInstance3D
	_t._check(smoke != null and smoke.material_override == RcRefineryRoad.smoke_material() and smoke.custom_aabb.size.y > 100.0,
		"rc4-refinery-road: the flares trail smoke")
	host.free()
