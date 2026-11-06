extends RefCounted
## The Coral Line's aerial structure at night (RcRailAerial, the rail_aerial reference camera in
## tools/refcams/cameras_w8.json), for tests/smoke_test.gd. Loaded at run time, not named there,
## so it compiles after the autoloads.
##
## Checks: the downlights hang between columns on the structure and never over a freeway; a FULL
## chunk on the structure builds the wire ribbons (no wire left in the fine prism mesh), the
## walkway lamps' lenses, the pools and the structure on the rail's own material with its washes;
## the ribbon vertices sit on their centre line with the tangent in NORMAL; the camera row looks
## at the structure over the 110 with a train staged on it; RC5_RAIL_AERIAL=0 is the kit as before.

var _t: Object


func run(t: Object, city: Node) -> void:
	_t = t
	var was := RcRailAerial.enabled
	RcRailAerial.enabled = true
	var plan: CityPlan = city.get("plan")
	var line := LightRail.of(plan)
	_t._check(line != null, "rail_aerial: the light rail resolves")
	if line == null:
		RcRailAerial.enabled = was
		return
	_spots(plan, line)
	_ribbon()
	_camera(plan, line)
	_chunk(city, plan, line)
	RcRailAerial.enabled = false
	var base := FreewayKit.structure_material()
	_t._check(RcRailAerial.structure_material(base) == base, "RC5_RAIL_AERIAL=0: the structure keeps the freeway's material")
	RcRailAerial.enabled = was


func _spots(plan: CityPlan, line: LightRail) -> void:
	var spots := RcRailAerial.soffit_spots(line, plan, func(_p: Vector2) -> bool: return true)
	var ok := not spots.is_empty()
	var off_col := true
	for s: float in spots:
		var smp := line.sample(s)
		ok = ok and int(smp.mode) == LightRail.Mode.AERIAL and not plan.macro.freeway.blocks(smp.pos, 4.0)
		var k := (s - 5.0) / LightRailKit.COLUMN_SPACING
		off_col = off_col and absf(k - roundf(k)) > 0.3
	_t._check(ok and off_col, "rail_aerial: %d downlight pairs, all on the structure, between columns, none over a freeway" % spots.size())


func _ribbon() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var a := Vector3(1.0, 20.0, 2.0)
	var b := Vector3(9.0, 20.4, 2.0)
	RcRailAerial.wire(st, a, b, 0.0065, RcRailAerial.KIND_WIRE, 2.0, 10.0)
	var arr := st.commit().surface_get_arrays(0)
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var n: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var uv: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
	var uv2: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV2]
	var ok := v.size() == 6
	var sides := 0.0
	for i in v.size():
		var on := (v[i] - a).cross(b - a).length() < 1e-4
		ok = ok and on and n[i].dot((b - a).normalized()) > 0.99 and is_equal_approx(uv2[i].x, 0.0065)
		sides += uv[i].x
	_t._check(ok and absf(sides) < 1e-4, "rail_aerial: a wire is a ribbon on its centre line (tangent in NORMAL, radius in UV2, both sides)")


func _camera(plan: CityPlan, line: LightRail) -> void:
	var f := FileAccess.open("res://tools/refcams/cameras_w8.json", FileAccess.READ)
	var row: Dictionary = {}
	if f:
		var d: Variant = JSON.parse_string(f.get_as_text())
		if d is Dictionary:
			for c: Dictionary in d.cameras:
				if String(c.name) == "rail_aerial":
					row = c
	_t._check(not row.is_empty() and row.has("rail_s"), "rail_aerial: the camera row stages a train (rail_s)")
	if row.is_empty():
		return
	var eye: Array = row.eye
	var yaw := deg_to_rad(float(eye[3]))
	var fwd := Vector2(-sin(yaw), -cos(yaw))
	var rs := String(row.rail_s).split(":", false)
	var smp := line.sample(rs[0].to_float() + LightRail.TRAIN_LENGTH * 0.5 * (1.0 if rs[1].to_int() == 1 else -1.0))
	var to: Vector2 = (smp.pos as Vector2) - Vector2(float(eye[0]), float(eye[2]))
	var ang := rad_to_deg(fwd.angle_to(to.normalized()))
	var over_110 := false
	for fo: Dictionary in line.flyovers:
		var q := line.sample(float(fo.s))
		var segs: Array = plan.macro.freeway.segments_in(Rect2(q.pos - Vector2(4, 4), Vector2(8, 8)))
		for g: Dictionary in segs:
			if int(g.route) < plan.macro.freeway.routes.size() and String(plan.macro.freeway.routes[int(g.route)].name).begins_with("110") \
					and (q.pos as Vector2).distance_to(Vector2(float(eye[0]), float(eye[2]))) < 160.0:
				over_110 = true
	_t._check(int(smp.mode) == LightRail.Mode.AERIAL and absf(ang) < float(row.get("fov", 55)) * 0.75 and over_110,
		"rail_aerial: the camera looks at the staged train on the structure (%.0f degrees off), the 110 flyover within reach" % ang)


func _chunk(city: Node, plan: CityPlan, line: LightRail) -> void:
	var at: Vector2 = line.sample(2600.0).pos
	var k := plan.block_index_at(at + Vector2(0.0, -3.0))
	var chunk: CityChunk = city.call("_new_chunk", k, CityChunk.Level.FULL)
	chunk.build()
	var wires: MeshInstance3D = chunk.get_node_or_null("RailWiresLit")
	var st: MeshInstance3D = chunk.get_node_or_null("RailStructure")
	var glow: MeshInstance3D = chunk.get_node_or_null("RailGlow")
	var fine: MeshInstance3D = chunk.get_node_or_null("RailDetail")
	# RcRailCrossing's ribbons ("RailWires") keep the at-grade line; none on the structure here.
	var wire_ok := wires != null and wires.mesh != null and wires.mesh.get_surface_count() == 1 \
		and wires.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF \
		and (wires.material_override as ShaderMaterial).shader.resource_path.ends_with("rail_wire.gdshader")
	_t._check(wire_ok and fine == null, "rail_aerial: the structure's overhead wires are one lit ribbon mesh (rail_wire.gdshader), none left as prisms")
	var mat := st.material_override as ShaderMaterial if st else null
	var wash: Variant = mat.get_shader_parameter("rail_wash") if mat else null
	_t._check(mat != null and mat != FreewayKit.structure_material() and wash is Vector2 and (wash as Vector2).x > 0.0,
		"rail_aerial: the structure wears the rail's own material with the column and soffit washes")
	var lenses := 0
	if st and st.mesh:
		var cols: PackedColorArray = st.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
		for c in cols:
			if int(round(c.a * FreewayKit.KIND_SCALE)) == FreewayKit.S_LENS:
				lenses += 1
	_t._check(lenses >= 24 and glow != null, "rail_aerial: lamp lenses on the structure (%d lens vertices) and their pools" % lenses)
	# The build's parked cars live under the city root: free them with the chunk (flake rule).
	for car in chunk.get("_cars"):
		if is_instance_valid(car):
			(car as Node).queue_free()
	chunk.get_parent().remove_child(chunk)
	chunk.free()
