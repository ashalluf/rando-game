class_name HospitalBuild
extends RefCounted
## Builds a hospital campus (Hospital.layout()) in a chunk: FULL - the podium and bed tower
## (HospitalTower, a Building), the glazed lobby and the main entrance canopy over the drop-off
## loop, the ER entrance with its lit red EMERGENCY sign, the covered ambulance bay (three bays,
## an ambulance parked in the first, sliding doors), the rooftop helipad (a plain H in a circle,
## the touchdown square, green perimeter lights, floodlights, a windsock, the safety net), the
## parking structure (ArenaGrounds.garage) or a surface lot, lawns, raised beds and trees, the
## drives' kerb cuts and the night's light pools; LOD and the far city - the tower's coded boxes
## (FarBuilding.boxes(), exactly as any planned building), the garage, the canopies, the red ER
## sign as a lit panel and the helipad's beacons, over a lawn slab.
##
## Everything is laid out in the campus frame (u along the front street, v back from it, see
## Hospital.layout()); the frame is axis-aligned, so a frame rect is a world rect. Rolls: hashes of
## the layout's seed only (a private RandomNumberGenerator seeded from it for the planting), never
## the chunk's or the block's rng.

## The thin ground pieces' lift over the pavement (m): lawn under paving under asphalt.
const LIFT_LAWN := 0.03
const LIFT_PAVE := 0.05
const LIFT_ROAD := 0.07
const CANOPY_H := 5.4
const BAY_CANOPY_H := 4.6
const LOBBY_H := 9.0
## The ER sign's letters (m) and how far out of the podium wall the sign stands.
const ER_LETTER := 1.45
## Colours of the lit signs (LINEAR; hospital_sign.gdshader).
const SIGN_RED_FACE := Vector3(0.62, 0.035, 0.025)
const SIGN_RED_GLOW := Vector3(1.0, 0.10, 0.05)
const SIGN_WHITE_FACE := Vector3(0.85, 0.86, 0.86)
const SIGN_WHITE_GLOW := Vector3(0.95, 0.97, 1.0)
## Helipad lights.
const PAD_GREEN := Color(0.15, 1.0, 0.35, 1.0)
const PAD_WHITE := Color(1.0, 0.96, 0.88, 1.0)
const BEACON_RED := Color(1.0, 0.08, 0.04, 1.0)

static var _mats: Dictionary = {}
static var _ambulance_mesh: Mesh = null


## The block's build steps: the ground, the tower, the entrances, the helipad, the garage and
## the planting, one a step (CityChunk._block_steps after the pavement).
static func steps(ch: CityChunk, block: Dictionary) -> Array[Callable]:
	var lay := Hospital.layout(ch.plan, ch.ix, ch.iz)
	var st := {"lay": lay}
	var out: Array[Callable] = []
	out.append(func() -> void: _begin(ch, st))
	out.append(func() -> void: _ground(ch, st))
	out.append(func() -> void: _tower(ch, st))
	if ch.level == CityChunk.Level.FULL and not ch.capturing:
		out.append(func() -> void: _entrances(ch, st))
		out.append(func() -> void: _er_bay(ch, st))
		out.append(func() -> void: _helipad(ch, st))
		out.append(func() -> void: _garage(ch, st))
		out.append(func() -> void: _planting(ch, st))
		out.append(func() -> void: _finish(ch, st))
	else:
		out.append(func() -> void: _far(ch, st))
	return out


static func build(ch: CityChunk, lay: Dictionary) -> void:
	for s in steps(ch, ch.plan.block(ch.ix, ch.iz)):
		s.call()


# --- Frame helpers -----------------------------------------------------------------------------

static func _p(lay: Dictionary, u: float, v: float, y: float) -> Vector3:
	var q := Hospital.fp(lay, u, v)
	return Vector3(q.x, y, q.y)


static func _r(lay: Dictionary, u0: float, v0: float, u1: float, v1: float) -> Rect2:
	return Hospital.fr(lay, Rect2(u0, v0, u1 - u0, v1 - v0))


## A frame direction (du, dv) in world XZ as a Vector3.
static func _d(lay: Dictionary, du: float, dv: float) -> Vector3:
	var q: Vector2 = (lay.a as Vector2) * du + (lay.n as Vector2) * dv
	return Vector3(q.x, 0.0, q.y)


## A world-space box over frame rect (u0, v0)-(u1, v1) from ya to yb.
static func _fbox(g: LandmarkGeo, lay: Dictionary, key: String, u0: float, v0: float, u1: float, v1: float, ya: float, yb: float,
		col: Color = Color.WHITE, bevel: float = 0.0, statics: StaticBody3D = null) -> void:
	var r := _r(lay, u0, v0, u1, v1)
	var c := r.get_center()
	var size := Vector3(r.size.x, yb - ya, r.size.y)
	g.box(key, Vector3(c.x, (ya + yb) * 0.5, c.y), size, col, Basis(), bevel, false, 0.0, true)
	if statics:
		LandmarkGeo.shape_box(statics, Vector3(c.x, (ya + yb) * 0.5, c.y), size)


## The yaw that turns a mesh's +Z onto world direction `d`.
static func _yaw_z(d: Vector3) -> float:
	return atan2(d.x, d.z)


# --- Materials -----------------------------------------------------------------------------------

static func _use(g: LandmarkGeo, y0: float, seed_value: int) -> void:
	var yk := int(roundf(y0))
	g.use("h_conc", LandmarkMats.facade("hosp_conc_%d" % yk, "concrete", 3.5, {"tint": Color(0.86, 0.85, 0.82), "roughness": 0.85,
		"joint_spacing": Vector2(3.0, 1.5), "joint_width": 0.012, "joint_dark": 0.2, "grime": 0.25, "base_y": y0}))
	g.use("h_white", LandmarkMats.plain("hosp_white", Color(0.86, 0.87, 0.86), 0.42))
	g.use("h_metal", LandmarkMats.plain("hosp_metal", Color(0.56, 0.58, 0.60), 0.32, 0.35))
	g.use("h_dark", LandmarkMats.plain("hosp_dark", Color(0.07, 0.075, 0.08), 0.5))
	g.use("h_glass", LandmarkMats.glass("hosp_lobby_%d" % yk, {"glass_tint": Color(0.16, 0.22, 0.25), "frame_color": Color(0.80, 0.82, 0.84),
		"grid": Vector2(1.6, 4.5), "frame_width": 0.06, "room_depth": 9.0, "storey": 4.5, "floor_y": y0,
		"interior_color": Color(1.0, 0.95, 0.85), "interior_day": 0.22, "interior_night": 1.9, "seed": float(seed_value % 997)}))
	g.use("h_door", LandmarkMats.glass("hosp_door_%d" % yk, {"glass_tint": Color(0.12, 0.17, 0.19), "frame_color": Color(0.70, 0.72, 0.74),
		"grid": Vector2(1.1, 2.6), "frame_width": 0.07, "room_depth": 6.0, "storey": 3.4, "floor_y": y0,
		"interior_color": Color(0.92, 0.97, 1.0), "interior_day": 0.3, "interior_night": 2.2}))
	g.use("h_paint", LandmarkMats.plain("hosp_paint", Color(0.93, 0.93, 0.90), 0.7))
	g.use("h_red", LandmarkMats.plain("hosp_red", Color(0.62, 0.05, 0.04), 0.55))
	g.use("h_yellow", LandmarkMats.plain("hosp_yellow", Color(0.86, 0.64, 0.08), 0.6))
	g.use("h_heli", LandmarkMats.plain("hosp_heli", Color(0.20, 0.21, 0.22), 0.88))
	g.use("h_lamp", FireStation.material("light"))


## A lit sign material (hospital_sign.gdshader), cached per look.
static func sign_material(key: String, face: Vector3, glow: Vector3, night: float, day: float, box: bool = false) -> ShaderMaterial:
	var k := "sign_" + key
	if _mats.has(k):
		return _mats[k]
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/hospital_sign.gdshader")
	m.set_shader_parameter("face_color", face)
	m.set_shader_parameter("glow_color", glow)
	m.set_shader_parameter("night_energy", night)
	m.set_shader_parameter("day_energy", day)
	m.set_shader_parameter("box_face", 1.0 if box else 0.0)
	_mats[k] = m
	return m


## Channel letters (a TextMesh, cached per text and size) on a lit material.
static func _text_mesh(txt: String, height: float, mat: Material, depth: float = 0.12) -> TextMesh:
	var k := "tm_%s_%.2f_%d" % [txt, height, mat.get_instance_id()]
	if _mats.has(k):
		return _mats[k]
	var tm := TextMesh.new()
	tm.text = txt
	tm.font_size = 48
	tm.pixel_size = height / 48.0
	tm.depth = depth
	tm.curve_step = 1.5
	tm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tm.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tm.material = mat
	_mats[k] = tm
	return tm


static func _text(parent: Node3D, node_name: String, txt: String, height: float, mat: Material, at: Vector3, facing: Vector3, draw: float) -> MeshInstance3D:
	if OS.has_feature("web") and draw < 150.0:
		return null
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = _text_mesh(txt, height, mat)
	mi.transform = Transform3D(Basis(Vector3.UP, _yaw_z(facing)), at)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = draw
	parent.add_child(mi)
	return mi


## The parked ambulance: the body's far twin (its wheels baked, ~8k triangles), white gloss.
static func ambulance_mesh() -> Mesh:
	if _ambulance_mesh != null:
		return _ambulance_mesh
	var scene: PackedScene = load("res://assets/models/road_ambulance.glb")
	if scene == null:
		return null
	var root := scene.instantiate()
	var far := root.get_node_or_null("road_ambulance_far") as MeshInstance3D
	if far == null or far.mesh == null:
		root.free()
		return null
	var mesh := far.mesh.duplicate() as ArrayMesh
	root.free()
	for i in mesh.get_surface_count():
		var src := mesh.surface_get_material(i) as StandardMaterial3D
		if src == null:
			continue
		if String(src.resource_name).begins_with("paint"):
			var pm := StandardMaterial3D.new()
			pm.albedo_color = Color(0.93, 0.93, 0.92)
			pm.roughness = 0.22
			pm.clearcoat_enabled = true
			pm.clearcoat = 0.8
			pm.vertex_color_use_as_albedo = false
			mesh.surface_set_material(i, pm)
		else:
			var part := Vehicle._part_material(src)
			if part != null:
				mesh.surface_set_material(i, part)
	_ambulance_mesh = mesh
	return mesh


# --- Steps ---------------------------------------------------------------------------------------

static func _begin(ch: CityChunk, st: Dictionary) -> void:
	var lay: Dictionary = st.lay
	var inner: Rect2 = lay.inner
	var c := inner.get_center()
	# One floor level for the campus: the pavement's at the block's highest corner, so nothing is
	# buried (Hospital only takes a level block, within a metre).
	var hi: float = lay.floor_gy
	st.y0 = hi + CityChunk.SIDEWALK_TOP
	st.gy = hi
	if ch.level == CityChunk.Level.FULL and not ch.capturing:
		var node := Node3D.new()
		node.name = "Hospital"
		node.add_to_group("hospital")
		node.set_meta("block", lay.block)
		ch.add_child(node)
		st.node = node
		var statics := StaticBody3D.new()
		statics.name = "HospitalBody"
		statics.collision_layer = 1
		statics.collision_mask = 0
		node.add_child(statics)
		st.statics = statics
		var g := LandmarkGeo.new()
		_use(g, float(st.y0), int(lay.seed))
		st.g = g
		st.batch = MultiMeshBatch.new()
		st.lights = []
	# The lawns, the drives, the plaza: what is not one of them is lawn.
	ch._lot_rects.append(inner)


## The ground: asphalt drives and the court, paving under the canopies and along the front, the
## rest lawn - a partition (Parks.minus), never one slab over another.
static func _ground(ch: CityChunk, st: Dictionary) -> void:
	var lay: Dictionary = st.lay
	var W: float = lay.W
	var D: float = lay.D
	var full: bool = ch.level == CityChunk.Level.FULL and not ch.capturing
	var asphalt: Array[Rect2] = []
	var paving: Array[Rect2] = []
	var loop: Rect2 = lay.loop
	var court: Rect2 = lay.court
	var podium: Rect2 = lay.podium
	# The drop-off loop: two legs from the street, the drive across the front under the canopy.
	asphalt.append(_r(lay, loop.position.x, 0.0, loop.position.x + 7.0, 8.5))
	asphalt.append(_r(lay, loop.end.x - 7.0, 0.0, loop.end.x, 8.5))
	asphalt.append(_r(lay, loop.position.x, 8.5, loop.end.x, 15.5))
	# The ambulance court from the ER street to the bays.
	asphalt.append(_r(lay, court.position.x, court.position.y, W, court.end.y))
	# The surface lot and its drive, or the garage's drive from the back street.
	var lot: Rect2 = lay.lot
	var garage: Rect2 = lay.garage
	if garage.size.x > 0.0:
		var gu := garage.position.x + garage.size.x * 0.5
		asphalt.append(_r(lay, gu - 5.0, garage.end.y, gu + 5.0, D))
	# The front plaza along the podium, the walk from the street, the walk to the ER doors.
	paving.append(_r(lay, podium.position.x, 15.5, podium.end.x, podium.position.y))
	paving.append(_r(lay, loop.position.x - 5.0, 0.0, loop.position.x - 1.5, 15.5))
	paving.append(_r(lay, court.position.x, podium.position.y, W, court.position.y))
	# What the buildings stand on is lawn too (the podium's plinth covers it).
	var holes: Array = []
	holes.append_array(asphalt)
	holes.append_array(paving)
	if lot.size.x > 0.0:
		holes.append(Hospital.fr(lay, lot))
	var lawns := Parks.minus(lay.inner, holes, 0.5)
	var lawn_mat := PropFactory.lawn(Color(0.34, 0.46, 0.22), int(lay.seed) % 9973, 0.3, 2.6)
	var asphalt_mat := PropFactory.road("asphalt", 4.0, Color(0.56, 0.56, 0.57), int(lay.seed) % 9967, 0.0, 0.5)
	var paving_mat := PropFactory.road("paving", 2.6, Color(0.92, 0.91, 0.88), int(lay.seed) % 9949, 1.5, 0.25)
	for r in lawns:
		ch._add_slab(Vector3(r.get_center().x, CityChunk.SIDEWALK_TOP + LIFT_LAWN * 0.5, r.get_center().y), Vector3(r.size.x, LIFT_LAWN, r.size.y),
				ch.style.grass, false, lawn_mat)
	if not full:
		# The far tiers see the drives and the plaza as pavement and the lot as asphalt.
		for r in asphalt:
			ch._add_slab(Vector3(r.get_center().x, CityChunk.SIDEWALK_TOP + LIFT_LAWN * 0.5, r.get_center().y), Vector3(r.size.x, LIFT_LAWN, r.size.y),
					ch.style.asphalt, false, asphalt_mat)
		return
	for r in asphalt:
		ch._add_slab(Vector3(r.get_center().x, CityChunk.SIDEWALK_TOP + LIFT_ROAD * 0.5, r.get_center().y), Vector3(r.size.x, LIFT_ROAD, r.size.y),
				ch.style.asphalt, false, asphalt_mat)
	for r in paving:
		ch._add_slab(Vector3(r.get_center().x, CityChunk.SIDEWALK_TOP + LIFT_PAVE * 0.5, r.get_center().y), Vector3(r.size.x, LIFT_PAVE, r.size.y),
				ch.style.sidewalk, false, paving_mat)
	# The kerb cuts: a concrete apron over the pavement and a lip down into the gutter.
	var g: LandmarkGeo = st.g
	var cuts := Hospital.kerb_cuts(ch.plan, lay)
	if garage.size.x > 0.0:
		var gu := garage.position.x + garage.size.x * 0.5
		cuts.append({"at": Hospital.fp(lay, gu, D + ch.plan.sidewalk_width), "out": Vector2(lay.n), "width": 10.0})
	for cut: Dictionary in cuts:
		var at: Vector2 = cut.at
		var out: Vector2 = cut.get("out", Vector2.ZERO)
		if out == Vector2.ZERO:
			# The kerb cut's way to the road: from the inner rect's edge out through `at`.
			var inner: Rect2 = lay.inner
			var c := inner.get_center()
			var d := at - c
			out = Vector2(signf(d.x), 0.0) if absf(d.x) / inner.size.x > absf(d.y) / inner.size.y else Vector2(0.0, signf(d.y))
		_kerb_cut(ch, g, at, out, float(cut.width))
	# Paint: the bays' lines and AMBULANCE ONLY, a red kerb along the court, the loop's arrows.
	var y_paint := float(st.gy) + CityChunk.SIDEWALK_TOP + LIFT_ROAD + 0.006
	var canopy: Rect2 = lay.canopy
	for k in 4:
		var v := canopy.position.y + 0.0 + float(k) * 5.2
		_fbox(g, lay, "h_paint", court.position.x + 0.4, v - 0.06, court.position.x + 9.5, v + 0.06, y_paint - 0.004, y_paint, Color.WHITE)
	_fbox(g, lay, "h_red", court.position.x + 9.5, canopy.position.y, court.position.x + 9.62, canopy.position.y + 15.6, y_paint - 0.004, y_paint)
	var paint := sign_material("ambulance_paint", Vector3(0.80, 0.80, 0.76), Vector3(0.0, 0.0, 0.0), 0.0, 0.0)
	var node: Node3D = st.node
	for k in 3:
		var b: Vector2 = (lay.bays as Array)[k]
		if OS.has_feature("web"):
			continue
		# Laid flat, read by a driver coming in from the street: the letters' tops toward the
		# building, their reading direction to the driver's right.
		var mi := MeshInstance3D.new()
		mi.name = "BayText%d" % k
		mi.mesh = _flat_text("AMBULANCE", 0.72, paint)
		var toward := _d(lay, -1.0, 0.0)
		mi.transform = Transform3D(Basis(toward.cross(Vector3.UP), toward, Vector3.UP), _p(lay, b.x + 6.2, b.y, y_paint + 0.002))
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visibility_range_end = 90.0
		node.add_child(mi)


static func _flat_text(txt: String, height: float, mat: Material) -> TextMesh:
	var k := "flat_%s_%.2f" % [txt, height]
	if _mats.has(k):
		return _mats[k]
	var tm := TextMesh.new()
	tm.text = txt
	tm.font_size = 48
	tm.pixel_size = height / 48.0
	tm.depth = 0.0
	tm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tm.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tm.material = mat
	_mats[k] = tm
	return tm


## A drive across the pavement at `at` (on the kerb line), `out` toward the road: a concrete
## apron flush over the pavement and a lip falling into the gutter.
static func _kerb_cut(ch: CityChunk, g: LandmarkGeo, at: Vector2, out: Vector2, width: float) -> void:
	var sw := ch.plan.sidewalk_width
	var side := Vector2(-out.y, out.x)
	var gy := ch._gy(at.x, at.y)
	var top := gy + CityChunk.SIDEWALK_TOP + 0.012
	var road := gy + CityChunk.ROAD_TOP + 0.012
	var inner := at - out * sw
	var c := (at + inner) * 0.5
	var size := Vector3(absf(out.x) * sw + absf(side.x) * width, 0.024, absf(out.y) * sw + absf(side.y) * width)
	g.box("h_conc", Vector3(c.x, top - 0.012, c.y), size, Color(0.92, 0.91, 0.88))
	var a := at - side * (width * 0.5)
	var b := at + side * (width * 0.5)
	var lip := 0.9
	var a2 := a + out * lip
	var b2 := b + out * lip
	var up := Vector3(-out.x * 0.15, 1.0, -out.y * 0.15).normalized()
	g.quad("h_conc", Vector3(a.x, top, a.y), Vector3(b.x, top, b.y), Vector3(b2.x, road, b2.y), Vector3(a2.x, road, a2.y), up,
			Vector2(0, 0), Vector2(width, 0), Vector2(width, lip), Vector2(0, lip), Color(0.9, 0.89, 0.86))


## The podium and bed tower (HospitalTower, a Building): placed on its rect, its plinth reaching
## past the lowest corner. FULL builds it; LOD and the far city take its coded boxes.
static func _tower(ch: CityChunk, st: Dictionary) -> void:
	var lay: Dictionary = st.lay
	var b := make_tower(ch, lay, float(st.y0))
	st.tower_node = b
	if ch.level == CityChunk.Level.FULL and not ch.capturing:
		ch.add_child(b)
		ch.building_count += 1
		return
	var style := b.plan_only()
	var base := b.position
	for part in b.parts:
		_occluder_and_shape(ch, b, part)
	if FarBuilding.enabled:
		for fb: Array in FarBuilding.boxes(b, style, b.plinth_depth):
			var xf: Transform3D = fb[0]
			var at: Vector3 = base + xf.origin
			at.y -= ch._gy(at.x, at.z)
			ch._batch.add("lod_box", PropFactory.unit_box(), Transform3D(xf.basis, at), fb[1], fb[2])
	else:
		var custom := Color(float(b.window_style) / 4.0, style.lit_ratio, float(b.seed % 997) / 997.0, 0.0)
		for part in b.parts:
			var at: Vector3 = base + (part.center as Vector3)
			at.y -= ch._gy(at.x, at.z)
			ch._batch.add("lod_box", PropFactory.unit_box(), Transform3D(Basis().scaled(part.size), at), b.part_lod_color(part), custom)
	ch.building_count += 1
	b.free()


static func _occluder_and_shape(ch: CityChunk, b: Building, part: Dictionary) -> void:
	var size: Vector3 = part.size
	var centre: Vector3 = part.center
	ch._add_lod_shape(size, b.position + centre)
	ch._occluder_boxes.append([Transform3D(Basis(), b.position), centre, size])


## The hospital's Building, set up and placed but not generated (the caller adds it or plans it).
static func make_tower(ch: CityChunk, lay: Dictionary, y0: float) -> HospitalTower:
	var b := HospitalTower.new()
	b.seed = int(lay.seed) % 1000003
	var pod := Hospital.fr(lay, lay.podium)
	var tow := Hospital.fr(lay, lay.tower)
	var c := pod.get_center()
	b.lot_size = pod.size
	b.podium_size = Vector3(pod.size.x, float(lay.podium_h), pod.size.y)
	b.tower_size = Vector3(tow.size.x, float(lay.tower_h), tow.size.y)
	b.tower_offset = tow.get_center() - c
	b.min_height = float(lay.podium_h) + float(lay.tower_h)
	b.max_height = b.min_height
	var gmin := INF
	for p: Vector2 in [pod.position, pod.end, Vector2(pod.end.x, pod.position.y), Vector2(pod.position.x, pod.end.y)]:
		gmin = minf(gmin, ch._gy(p.x, p.y))
	b.plinth_depth = (y0 - CityChunk.SIDEWALK_TOP) - gmin + CityChunk.SIDEWALK_TOP + 0.6
	b.position = Vector3(c.x, y0, c.y)
	b.name = "HospitalTower"
	return b


## The main entrance: the glazed lobby standing out of the podium, the canopy over the drop-off
## drive on round columns, downlights, the hospital's name on the canopy and on a monument sign
## in the loop's island, and its name lit along the top of the tower.
static func _entrances(ch: CityChunk, st: Dictionary) -> void:
	var lay: Dictionary = st.lay
	var g: LandmarkGeo = st.g
	var statics: StaticBody3D = st.statics
	var node: Node3D = st.node
	var y0: float = st.y0
	var podium: Rect2 = lay.podium
	var loop: Rect2 = lay.loop
	var uc := loop.position.x + loop.size.x * 0.5
	var v_face := podium.position.y
	# The lobby: a glass box 24 m wide standing 3.6 m out of the podium, double height, a white roof
	# slab with a thin fascia, two pairs of sliding doors.
	var lu0 := uc - 12.0
	var lu1 := uc + 12.0
	var lv0 := v_face - 3.6
	var lv1 := v_face + 0.4
	var p0 := Hospital.fp(lay, lu0, lv0)
	var p1 := Hospital.fp(lay, lu1, lv0)
	var p2 := Hospital.fp(lay, lu1, lv1)
	var p3 := Hospital.fp(lay, lu0, lv1)
	_owall(g, "h_glass", p0, p1, y0, y0 + LOBBY_H, _d(lay, 0.0, -1.0))
	_owall(g, "h_glass", p1, p2, y0, y0 + LOBBY_H, _d(lay, 1.0, 0.0))
	_owall(g, "h_glass", p3, p0, y0, y0 + LOBBY_H, _d(lay, -1.0, 0.0))
	_fbox(g, lay, "h_white", lu0 - 0.4, lv0 - 0.4, lu1 + 0.4, lv1, y0 + LOBBY_H, y0 + LOBBY_H + 0.9, Color.WHITE, 0.04, statics)
	_fbox(g, lay, "h_metal", lu0 - 0.45, lv0 - 0.45, lu1 + 0.45, lv0 - 0.35, y0 + LOBBY_H + 0.15, y0 + LOBBY_H + 0.75)
	LandmarkGeo.shape_box(statics, _p(lay, uc, (lv0 + lv1) * 0.5, y0 + LOBBY_H * 0.5), Vector3(24.0, LOBBY_H, 4.0).abs() if absf((lay.a as Vector2).x) > 0.5 else Vector3(4.0, LOBBY_H, 24.0))
	# Mullions every 1.6 m standing proud of the glass, a transom at the door head.
	var n_m := 15
	for i in n_m + 1:
		var u := lu0 + float(i) * 24.0 / float(n_m)
		_fbox(g, lay, "h_metal", u - 0.05, lv0 - 0.08, u + 0.05, lv0 + 0.02, y0, y0 + LOBBY_H)
	_fbox(g, lay, "h_metal", lu0, lv0 - 0.1, lu1, lv0 + 0.02, y0 + 3.0, y0 + 3.15)
	# Sliding doors: dark frames and the leaves, slid a little apart.
	for du: float in [-5.0, 5.0]:
		var dc := uc + du
		_fbox(g, lay, "h_dark", dc - 1.7, lv0 - 0.16, dc + 1.7, lv0 - 0.06, y0 + 2.6, y0 + 2.95)
		for s: float in [-1.0, 1.0]:
			_fbox(g, lay, "h_door", dc + s * 0.25, lv0 - 0.14, dc + s * 1.55, lv0 - 0.10, y0 + 0.02, y0 + 2.6)
			_fbox(g, lay, "h_dark", dc + s * 1.55, lv0 - 0.16, dc + s * 1.65, lv0 - 0.06, y0, y0 + 2.6)
		# The mat inside the doors.
		_fbox(g, lay, "h_dark", dc - 1.5, lv0 - 1.8, dc + 1.5, lv0 - 0.2, y0 + LIFT_PAVE - 0.03, y0 + LIFT_PAVE + 0.004)
	# The canopy over the drive: a white slab on round columns along the drive's outer edge.
	var cu0 := uc - 13.0
	var cu1 := uc + 13.0
	var cv0 := 7.6
	var cv1 := lv0
	_fbox(g, lay, "h_white", cu0, cv0, cu1, cv1, y0 + CANOPY_H, y0 + CANOPY_H + 0.55, Color.WHITE, 0.05, statics)
	_fbox(g, lay, "h_metal", cu0 - 0.08, cv0 - 0.08, cu1 + 0.08, cv0 + 0.1, y0 + CANOPY_H + 0.05, y0 + CANOPY_H + 0.9)
	for i in 4:
		var u := lerpf(cu0 + 1.2, cu1 - 1.2, float(i) / 3.0)
		var base := _p(lay, u, cv0 + 0.9, 0.0)
		var gy := ch._gy(base.x, base.z) + CityChunk.SIDEWALK_TOP + LIFT_ROAD
		g.cylinder("h_metal", Vector3(base.x, gy, base.z), 0.32, y0 + CANOPY_H - gy, 14, Color.WHITE)
		LandmarkGeo.shape_box(statics, Vector3(base.x, (gy + y0 + CANOPY_H) * 0.5, base.z), Vector3(0.6, y0 + CANOPY_H - gy, 0.6))
		# A bollard pair guarding each column.
	# Downlights under the canopy, and their pools on the drive.
	for i in 6:
		for j in 2:
			var u := lerpf(cu0 + 2.0, cu1 - 2.0, float(i) / 5.0)
			var v := lerpf(cv0 + 2.0, cv1 - 1.5, float(j))
			_fbox(g, lay, "h_lamp", u - 0.35, v - 0.35, u + 0.35, v + 0.35, y0 + CANOPY_H - 0.03, y0 + CANOPY_H + 0.001)
	for i in 3:
		var u := lerpf(cu0 + 4.0, cu1 - 4.0, float(i) / 2.0)
		(st.batch as MultiMeshBatch).add("h_pool", PropFactory.light_pool(Color(1.0, 0.94, 0.82), 1.1),
				Transform3D(Basis(Vector3.RIGHT, -PI * 0.5).scaled(Vector3(9.0, 1.0, 9.0)), _p(lay, u, (cv0 + cv1) * 0.5, y0 + LIFT_ROAD + 0.02)))
	# Words on the canopy's fascia and the hospital's name over the lobby, lit white.
	var white := sign_material("white", SIGN_WHITE_FACE, SIGN_WHITE_GLOW, 2.2, 0.25)
	var out := _d(lay, 0.0, -1.0)
	_text(node, "EntranceWords", "MAIN ENTRANCE", 0.55, white, _p(lay, uc, cv0 - 0.12, y0 + CANOPY_H + 0.47), out, 140.0)
	_text(node, "LobbyName", String(lay.name), 0.85, white, _p(lay, uc, lv0 - 0.47, y0 + LOBBY_H + 0.45), out, 220.0)
	# The name along the top of the tower, toward the front street, in big lit letters.
	var tower: Rect2 = lay.tower
	var top := y0 + float(lay.podium_h) + float(lay.tower_h)
	var tname := String(lay.name).replace(" MEDICAL CENTER", "").replace(" HOSPITAL", "")
	var letter := clampf(tower.size.x / maxf(float(tname.length()) * 0.75, 1.0), 1.2, 2.6)
	_text(node, "TowerName", tname, letter, white, _p(lay, tower.position.x + tower.size.x * 0.5, tower.position.y - 0.28, top - letter * 0.9), out, 900.0)
	# The monument sign in the loop's island: a stone plinth with the name both ways.
	var mu := uc
	var mv := 4.0
	var mg := ch._gy(Hospital.fp(lay, mu, mv).x, Hospital.fp(lay, mu, mv).y) + CityChunk.SIDEWALK_TOP + LIFT_LAWN
	_fbox(g, lay, "h_conc", mu - 4.2, mv - 0.45, mu + 4.2, mv + 0.45, mg - 0.2, mg + 1.5, Color(0.80, 0.78, 0.74), 0.04, statics)
	_fbox(g, lay, "h_dark", mu - 4.4, mv - 0.55, mu + 4.4, mv + 0.55, mg - 0.2, mg + 0.25, Color.WHITE, 0.03)
	var mono := String(lay.name)
	var mh := clampf(7.6 / maxf(float(mono.length()) * 0.62, 1.0), 0.28, 0.55)
	_text(node, "Monument", mono, mh, white, _p(lay, mu, mv - 0.47, mg + 0.9), out, 120.0)
	_text(node, "MonumentBack", mono, mh, white, _p(lay, mu, mv + 0.47, mg + 0.9), -out, 120.0)
	var red := sign_material("red", SIGN_RED_FACE, SIGN_RED_GLOW, 2.6, 0.3)
	_text(node, "MonumentER", "EMERGENCY  >", mh * 0.95, red, _p(lay, mu, mv - 0.47, mg + 0.45), out, 120.0)


## A vertical wall from p0 to p1 facing `out` (LandmarkGeo.wall() faces the right of p0 -> p1;
## the campus frame may be mirrored, so the ends are swapped when that is the wrong side).
static func _owall(g: LandmarkGeo, key: String, p0: Vector2, p1: Vector2, y0: float, y1: float, out: Vector3) -> void:
	var d := p1 - p0
	if Vector2(-d.y, d.x).dot(Vector2(out.x, out.z)) < 0.0:
		g.wall(key, p1, p0, y0, y1)
	else:
		g.wall(key, p0, p1, y0, y1)


## The ER: the ambulance bays' canopy against the podium's ER-side wall on a row of columns, the
## sliding doors at the back of the bays, wheel stops, the big lit red EMERGENCY sign on the
## podium wall over the canopy, AMBULANCE ENTRANCE on the canopy fascia, an ambulance backed into
## the first bay, the court's light pools.
static func _er_bay(ch: CityChunk, st: Dictionary) -> void:
	var lay: Dictionary = st.lay
	var g: LandmarkGeo = st.g
	var statics: StaticBody3D = st.statics
	var node: Node3D = st.node
	var batch: MultiMeshBatch = st.batch
	var y0: float = st.y0
	var canopy: Rect2 = lay.canopy
	var court: Rect2 = lay.court
	var wall_u := court.position.x
	var cu1 := canopy.end.x
	var y_court := float(st.gy) + CityChunk.SIDEWALK_TOP + LIFT_ROAD
	# The canopy: a deep white slab with a metal fascia, on three columns.
	_fbox(g, lay, "h_white", wall_u, canopy.position.y, cu1, canopy.end.y, y0 + BAY_CANOPY_H, y0 + BAY_CANOPY_H + 0.6, Color.WHITE, 0.05, statics)
	_fbox(g, lay, "h_red", cu1 - 0.1, canopy.position.y - 0.08, cu1 + 0.1, canopy.end.y + 0.08, y0 + BAY_CANOPY_H + 0.05, y0 + BAY_CANOPY_H + 0.95)
	for k in 3:
		var v := lerpf(canopy.position.y + 0.6, canopy.end.y - 0.6, float(k) / 2.0)
		var base := _p(lay, cu1 - 0.6, v, 0.0)
		g.cylinder("h_metal", Vector3(base.x, y_court, base.z), 0.3, y0 + BAY_CANOPY_H - y_court, 14)
		LandmarkGeo.shape_box(statics, Vector3(base.x, (y_court + y0 + BAY_CANOPY_H) * 0.5, base.z), Vector3(0.6, y0 + BAY_CANOPY_H - y_court, 0.6))
		# A yellow-banded guard post at each column's foot.
		_fbox(g, lay, "h_yellow", cu1 - 0.95, v - 0.35, cu1 - 0.25, v + 0.35, y_court, y_court + 0.9, Color.WHITE, 0.03)
	# Downlights and pools under the canopy, and two more pools out on the court.
	for k in 3:
		var b: Vector2 = (lay.bays as Array)[k]
		for du: float in [1.8, 6.5]:
			_fbox(g, lay, "h_lamp", wall_u + du - 0.4, b.y - 0.4, wall_u + du + 0.4, b.y + 0.4, y0 + BAY_CANOPY_H - 0.03, y0 + BAY_CANOPY_H + 0.001)
		batch.add("h_pool", PropFactory.light_pool(Color(0.92, 0.96, 1.0), 1.15),
				Transform3D(Basis(Vector3.RIGHT, -PI * 0.5).scaled(Vector3(7.0, 1.0, 7.0)), _p(lay, wall_u + 4.5, b.y, y_court + 0.02)))
	for f: float in [0.35, 0.8]:
		batch.add("h_pool", PropFactory.light_pool(Color(1.0, 0.86, 0.62), 0.9),
				Transform3D(Basis(Vector3.RIGHT, -PI * 0.5).scaled(Vector3(11.0, 1.0, 11.0)), _p(lay, wall_u + 16.0, lerpf(court.position.y, court.end.y, f), y_court + 0.02)))
	# The ER doors at the back of the bays (the podium's wall, facing the street): a wide pair at
	# the middle bay with a lit transom, and a single pair at the third; a portal frame round them.
	var out := _d(lay, 1.0, 0.0)
	var doors: Array[float] = [((lay.bays as Array)[1] as Vector2).y, ((lay.bays as Array)[2] as Vector2).y]
	for di in doors.size():
		var dv := doors[di]
		var half := 1.9 if di == 0 else 1.4
		_fbox(g, lay, "h_metal", wall_u + 0.0, dv - half - 0.35, wall_u + 0.3, dv + half + 0.35, y0, y0 + 3.3)
		_fbox(g, lay, "h_door", wall_u + 0.3, dv - half, wall_u + 0.36, dv + half, y0 + 0.02, y0 + 2.75)
		_fbox(g, lay, "h_dark", wall_u + 0.3, dv - 0.03, wall_u + 0.4, dv + 0.03, y0 + 0.02, y0 + 2.75)
		_fbox(g, lay, "h_lamp", wall_u + 0.3, dv - half, wall_u + 0.38, dv + half, y0 + 2.8, y0 + 3.15)
	# Wheel stops at the back of each bay: an ambulance backs up to them.
	for k in 3:
		var b: Vector2 = (lay.bays as Array)[k]
		for s: float in [-1.0, 1.0]:
			_fbox(g, lay, "h_yellow", wall_u + 1.0, b.y + s * 0.95 - 0.5, wall_u + 1.25, b.y + s * 0.95 + 0.5, y_court, y_court + 0.14, Color.WHITE, 0.02)
	# The EMERGENCY sign: a light box on the podium wall over the canopy, red letters lit.
	var mid := (canopy.position.y + canopy.end.y) * 0.5
	var sign_w := 15.5
	var sy := y0 + BAY_CANOPY_H + 4.3
	_fbox(g, lay, "h_white", wall_u, mid - sign_w * 0.5, wall_u + 0.45, mid + sign_w * 0.5, sy - 1.2, sy + 1.25, Color.WHITE, 0.05)
	var red := sign_material("red", SIGN_RED_FACE, SIGN_RED_GLOW, 2.6, 0.3)
	var box_mat := sign_material("er_box", Vector3(0.9, 0.9, 0.88), Vector3(0.9, 0.92, 0.95), 0.45, 0.04, true)
	var face := MeshInstance3D.new()
	face.name = "ERSignFace"
	var qm := QuadMesh.new()
	qm.size = Vector2(sign_w - 0.4, 2.15)
	qm.material = box_mat
	face.mesh = qm
	face.transform = Transform3D(Basis(Vector3.UP, _yaw_z(out)), _p(lay, wall_u + 0.46, mid, sy + 0.02))
	face.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.add_child(face)
	_text(node, "ERSign", "EMERGENCY", ER_LETTER, red, _p(lay, wall_u + 0.52, mid, sy + 0.02), out, 900.0)
	var white := sign_material("white", SIGN_WHITE_FACE, SIGN_WHITE_GLOW, 2.2, 0.25)
	_text(node, "AmbulanceWords", "AMBULANCE ENTRANCE", 0.42, white, _p(lay, cu1 + 0.12, mid, y0 + BAY_CANOPY_H + 0.5), out, 130.0)
	# The red glow it throws on the court at night.
	batch.add("h_pool_red", PropFactory.light_pool(Color(1.0, 0.18, 0.12), 0.7),
			Transform3D(Basis(Vector3.RIGHT, -PI * 0.5).scaled(Vector3(12.0, 1.0, 7.0)), _p(lay, cu1 + 3.0, mid, y_court + 0.025)))
	# The parked ambulance, backed into the first bay, nose to the street.
	var am := ambulance_mesh()
	if am != null:
		var b0: Vector2 = (lay.bays as Array)[0]
		var mi := MeshInstance3D.new()
		mi.name = "ParkedAmbulance"
		mi.mesh = am
		var fwd := out
		mi.transform = Transform3D(Basis(Vector3.UP, atan2(-fwd.x, -fwd.z)), _p(lay, b0.x, b0.y, y_court))
		mi.visibility_range_end = 220.0
		node.add_child(mi)
		LandmarkGeo.shape_box(statics, _p(lay, b0.x, b0.y, y_court + 1.4), Vector3(2.6, 2.8, 6.9) if absf(out.z) > 0.5 else Vector3(6.9, 2.8, 2.6))


## The helipad on the tower roof: a steel deck on legs over the roof, the touchdown square in
## yellow, a white circle and a plain H (never a cross), the safety net round its edge, a ramp
## down to the roof, a windsock on a mast, green perimeter lights and floods (aircraft_lights,
## lit with the lamps), red beacons on the tower's corners.
static func _helipad(ch: CityChunk, st: Dictionary) -> void:
	var lay: Dictionary = st.lay
	var g: LandmarkGeo = st.g
	var statics: StaticBody3D = st.statics
	var y0: float = st.y0
	var tower: Rect2 = lay.tower
	var roof := y0 + float(lay.podium_h) + float(lay.tower_h)
	var deck := roof + 2.2
	var side := minf(tower.size.y - 1.0, 18.0)
	var tc := Vector2(tower.position.x + tower.size.x * 0.5, tower.position.y + tower.size.y * 0.5)
	var u0 := tc.x - side * 0.5
	var u1 := tc.x + side * 0.5
	var v0 := tc.y - side * 0.5
	var v1 := tc.y + side * 0.5
	_fbox(g, lay, "h_heli", u0, v0, u1, v1, deck - 0.35, deck, Color.WHITE, 0.03, statics)
	# Legs and the steel under it.
	for i in 3:
		for j in 3:
			var u := lerpf(u0 + 1.0, u1 - 1.0, float(i) / 2.0)
			var v := lerpf(v0 + 1.0, v1 - 1.0, float(j) / 2.0)
			_fbox(g, lay, "h_metal", u - 0.22, v - 0.22, u + 0.22, v + 0.22, roof, deck - 0.35)
	for j in 2:
		var v := v0 + 1.0 + float(j) * (side - 2.0)
		_fbox(g, lay, "h_dark", u0 + 0.5, v - 0.15, u1 - 0.5, v + 0.15, deck - 0.85, deck - 0.35)
	# The safety net: a 1.5 m shelf round the deck, just below it, its edge rail.
	var net := 1.5
	for e in 4:
		var r: Rect2
		match e:
			0: r = Rect2(u0 - net, v0 - net, side + net * 2.0, net)
			1: r = Rect2(u0 - net, v1, side + net * 2.0, net)
			2: r = Rect2(u0 - net, v0, net, side)
			_: r = Rect2(u1, v0, net, side)
		_fbox(g, lay, "h_dark", r.position.x, r.position.y, r.end.x, r.end.y, deck - 0.55, deck - 0.5, Color(0.6, 0.6, 0.6))
	_fbox(g, lay, "h_metal", u0 - net, v0 - net, u1 + net, v0 - net + 0.06, deck - 0.6, deck - 0.2)
	_fbox(g, lay, "h_metal", u0 - net, v1 + net - 0.06, u1 + net, v1 + net, deck - 0.6, deck - 0.2)
	_fbox(g, lay, "h_metal", u0 - net, v0 - net, u0 - net + 0.06, v1 + net, deck - 0.6, deck - 0.2)
	_fbox(g, lay, "h_metal", u1 + net - 0.06, v0 - net, u1 + net, v1 + net, deck - 0.6, deck - 0.2)
	# Markings: the touchdown square's yellow border, the white circle, the H.
	var ym := deck + 0.004
	var bw := 0.3
	_fbox(g, lay, "h_yellow", u0 + 0.6, v0 + 0.6, u1 - 0.6, v0 + 0.6 + bw, deck - 0.01, ym)
	_fbox(g, lay, "h_yellow", u0 + 0.6, v1 - 0.6 - bw, u1 - 0.6, v1 - 0.6, deck - 0.01, ym)
	_fbox(g, lay, "h_yellow", u0 + 0.6, v0 + 0.6, u0 + 0.6 + bw, v1 - 0.6, deck - 0.01, ym)
	_fbox(g, lay, "h_yellow", u1 - 0.6 - bw, v0 + 0.6, u1 - 0.6, v1 - 0.6, deck - 0.01, ym)
	var cw := Hospital.fp(lay, tc.x, tc.y)
	var rr := side * 0.36
	g.ring_flat("h_paint", cw, Vector2(rr - 0.5, rr - 0.5), Vector2(rr, rr), ym + 0.002, 0.0, TAU, 40)
	# The H, its legs across the approach (along u, from the front street).
	var hh := side * 0.36
	var hw := side * 0.22
	_fbox(g, lay, "h_paint", tc.x - hw * 0.5, tc.y - hh * 0.5, tc.x - hw * 0.5 + 0.7, tc.y + hh * 0.5, deck - 0.01, ym + 0.003)
	_fbox(g, lay, "h_paint", tc.x + hw * 0.5 - 0.7, tc.y - hh * 0.5, tc.x + hw * 0.5, tc.y + hh * 0.5, deck - 0.01, ym + 0.003)
	_fbox(g, lay, "h_paint", tc.x - hw * 0.5, tc.y - 0.35, tc.x + hw * 0.5, tc.y + 0.35, deck - 0.01, ym + 0.003)
	# The ramp down to the roof on the tower's far side, and its rails.
	var ru0 := u1 + net
	var ru1 := minf(ru0 + 7.0, tower.end.x - 0.6)
	if ru1 - ru0 > 3.0:
		var a := _p(lay, ru0, tc.y - 1.0, deck - 0.05)
		var b := _p(lay, ru0, tc.y + 1.0, deck - 0.05)
		var c := _p(lay, ru1, tc.y + 1.0, roof + 0.1)
		var d := _p(lay, ru1, tc.y - 1.0, roof + 0.1)
		g.quad("h_heli", a, b, c, d, Vector3.UP, Vector2(0, 0), Vector2(2, 0), Vector2(2, ru1 - ru0), Vector2(0, ru1 - ru0))
		g.quad("h_heli", d, c, b, a, Vector3.DOWN, Vector2(0, 0), Vector2(2, 0), Vector2(2, ru1 - ru0), Vector2(0, ru1 - ru0))
	# The windsock on a mast at the roof's corner.
	var wu := tower.position.x + 1.2
	var wv := tower.position.y + 1.2
	var wb := _p(lay, wu, wv, roof)
	g.cylinder("h_metal", wb, 0.07, 5.0, 8)
	var sock_dir := _d(lay, 0.7, 0.7).normalized()
	var sock_basis := Basis(Vector3.UP, atan2(sock_dir.x, sock_dir.z))
	g.use("h_orange", LandmarkMats.plain("hosp_orange", Color(0.95, 0.38, 0.06), 0.8))
	for k in 3:
		var seg_c := wb + Vector3(0.0, 4.7 - float(k) * 0.08, 0.0) + sock_dir * (0.4 + float(k) * 0.62)
		var w := 0.62 - float(k) * 0.13
		g.box("h_orange" if k != 1 else "h_paint", seg_c, Vector3(w, w, 0.6), Color.WHITE, sock_basis)
	# Lights: green round the deck's edge and white floods at its corners, red beacons on the
	# tower's corners (the aircraft lights mesh: they read from across the basin at night).
	var lights: Array = st.lights
	var per := 5
	for e in 4:
		for i in per:
			var f := float(i) / float(per)
			var q: Vector2
			match e:
				0: q = Vector2(lerpf(u0, u1, f), v0)
				1: q = Vector2(lerpf(u1, u0, f), v1)
				2: q = Vector2(u0, lerpf(v1, v0, f))
				_: q = Vector2(u1, lerpf(v0, v1, f))
			lights.append([_p(lay, q.x, q.y, deck + 0.12), PAD_GREEN, 0.5, 4, 0.0])
	for q: Vector2 in [Vector2(u0 - net, v0 - net), Vector2(u1 + net, v0 - net), Vector2(u1 + net, v1 + net), Vector2(u0 - net, v1 + net)]:
		lights.append([_p(lay, q.x, q.y, deck + 0.6), PAD_WHITE, 0.9, 4, 0.0])
		_fbox(g, lay, "h_metal", q.x - 0.08, q.y - 0.08, q.x + 0.08, q.y + 0.08, deck - 0.6, deck + 0.55)
	var tr := Hospital.fr(lay, tower)
	var ph := fposmod(float(lay.seed) * 0.000137, 1.0)
	for q: Vector2 in [tr.position, tr.end, Vector2(tr.end.x, tr.position.y), Vector2(tr.position.x, tr.end.y)]:
		var inset := (tr.get_center() - q).normalized() * 0.6
		lights.append([Vector3(q.x + inset.x, roof + 1.6, q.y + inset.y), BEACON_RED, 1.1, 2, ph])
	# The deck's own glow from the floods (an additive pool on the deck at night).
	(st.batch as MultiMeshBatch).add("h_pool", PropFactory.light_pool(Color(1.0, 0.95, 0.85), 0.6),
			Transform3D(Basis(Vector3.RIGHT, -PI * 0.5).scaled(Vector3(side * 1.1, 1.0, side * 1.1)), Vector3(cw.x, deck + 0.03, cw.y)))


## The parking structure behind the podium (ArenaGrounds.garage, its drive-in to the back
## street), or a surface lot by the court.
static func _garage(ch: CityChunk, st: Dictionary) -> void:
	var lay: Dictionary = st.lay
	var g: LandmarkGeo = st.g
	var statics: StaticBody3D = st.statics
	var y0: float = st.y0
	var garage: Rect2 = lay.garage
	if garage.size.x > 0.0:
		var entry := _world_side(lay.n as Vector2)
		ArenaGrounds.garage(g, st.batch, st.node, statics, Hospital.fr(lay, garage), 4, y0, true, int(lay.seed) % 99991, entry)
	var lot: Rect2 = lay.lot
	if lot.size.x > 0.0:
		ArenaGrounds.surface_lot(g, st.batch, st.node, Hospital.fr(lay, lot), y0 + 0.02, int(lay.seed) % 99989)


## The block side (0 N, 1 E, 2 S, 3 W, ArenaGrounds' entry_side) a world direction points to.
static func _world_side(d: Vector2) -> int:
	if absf(d.x) > absf(d.y):
		return 1 if d.x > 0.0 else 3
	return 2 if d.y > 0.0 else 0


## Lawns planted: a row of trees along the front street and the ER street, raised beds along the
## front plaza, trees in the loop's island.
static func _planting(ch: CityChunk, st: Dictionary) -> void:
	var lay: Dictionary = st.lay
	var g: LandmarkGeo = st.g
	var batch: MultiMeshBatch = st.batch
	var statics: StaticBody3D = st.statics
	var y0: float = st.y0
	var rng := RandomNumberGenerator.new()
	rng.seed = int(lay.seed) ^ 0x5eed
	var W: float = lay.W
	var podium: Rect2 = lay.podium
	var loop: Rect2 = lay.loop
	var court: Rect2 = lay.court
	var tv := 1 + int(lay.seed) % 3
	var trees: Array[Vector2] = []
	# Along the front street, clear of the drive legs and the walk.
	var u := 3.0
	while u < W - 2.0:
		var in_loop := u > loop.position.x - 6.5 and u < loop.end.x + 1.5
		if not in_loop or (u > loop.position.x + 9.0 and u < loop.end.x - 9.0):
			trees.append(Vector2(u, 2.2))
		u += 9.0
	# Along the ER street, clear of the court and the lot's drive.
	var v := 3.0
	while v < float(lay.D) - 2.0:
		if v < court.position.y - 2.5 or v > court.end.y + 2.5:
			trees.append(Vector2(W - 2.2, v))
		v += 9.0
	# Down the side away from the ER.
	v = podium.position.y + 4.0
	while v < podium.end.y - 2.0:
		trees.append(Vector2(2.6, v))
		v += 10.0
	var lot: Rect2 = lay.lot
	var lot_w := Hospital.fr(lay, lot)
	for t in trees:
		var w := Hospital.fp(lay, t.x, t.y)
		if lot.size.x > 0.0 and lot_w.grow(1.0).has_point(w):
			continue
		var gy := ch._gy(w.x, w.y) + CityChunk.SIDEWALK_TOP + LIFT_LAWN
		var sc := PropFactory.city_tree_scale(tv, rng.randf_range(7.0, 10.0))
		batch.add("tree_%d" % tv, PropFactory.model_tree(tv), Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(sc, sc, sc)), Vector3(w.x, gy, w.y)),
				Color.WHITE, Color(rng.randf(), rng.randf(), rng.randf(), rng.randf_range(0.5, 1.0)))
	# Palms in the loop's island either side of the monument.
	for s: float in [-1.0, 1.0]:
		var w := Hospital.fp(lay, loop.position.x + loop.size.x * 0.5 + s * 9.0, 4.0)
		var pv := (int(lay.seed) + int(s + 1.0)) % PropFactory.PALM_VARIANTS
		batch.add("palm_%d" % pv, PropFactory.palm(pv), Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(w.x, ch._gy(w.x, w.y) + CityChunk.SIDEWALK_TOP + LIFT_LAWN, w.y)))
	# Raised beds along the front plaza either side of the lobby.
	var uc := loop.position.x + loop.size.x * 0.5
	for s: float in [-1.0, 1.0]:
		var bu0 := uc + s * 14.5
		var bu1 := uc + s * 14.5 + s * minf(10.0, podium.size.x * 0.5 - 15.0)
		if absf(bu1 - bu0) < 3.0:
			continue
		var r := _r(lay, minf(bu0, bu1), 16.2, maxf(bu0, bu1), 18.2)
		ArenaGrounds.bed(g, batch, statics, r, y0 + LIFT_PAVE - 0.05, int(lay.seed) % 991 + int(s + 2.0), 0.0, false, true)


## Commits the meshes, the batch and the lights.
static func _finish(ch: CityChunk, st: Dictionary) -> void:
	var g: LandmarkGeo = st.g
	var node: Node3D = st.node
	g.commit(node, "Campus", true)
	g.commit_collision(st.statics)
	var batch: MultiMeshBatch = st.batch
	for k in ["h_pool", "h_pool_red"]:
		batch.set_no_shadow(k)
	batch.build(node)
	_commit_lights(ch, node, st.lights)
	# The night lamps: a few real lights under the canopies (FULL, desktop: the lamp group).
	if not OS.has_feature("web"):
		var lay: Dictionary = st.lay
		var y0: float = st.y0
		var canopy: Rect2 = lay.canopy
		var loop: Rect2 = lay.loop
		for spot: Vector3 in [_p(lay, canopy.position.x + 5.0, canopy.position.y + canopy.size.y * 0.5, y0 + BAY_CANOPY_H - 0.6),
				_p(lay, loop.position.x + loop.size.x * 0.5, 11.0, y0 + CANOPY_H - 0.6)]:
			var l := OmniLight3D.new()
			l.omni_range = 14.0
			l.light_energy = 0.0
			l.light_color = Color(1.0, 0.95, 0.86)
			l.shadow_enabled = false
			l.distance_fade_enabled = true
			l.distance_fade_begin = 70.0
			l.distance_fade_length = 20.0
			l.position = spot
			l.add_to_group("lamp_light")
			node.add_child(l)


## The aircraft-lights mesh for `specs` ([position, colour, size, kind, phase]) under `parent`.
static func _commit_lights(_ch: CityChunk, parent: Node3D, specs: Array) -> void:
	if specs.is_empty():
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var corners := [Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(1.0, 1.0), Vector2(0.0, 1.0)]
	for spec: Array in specs:
		var code := float(spec[3]) * 10.0 + clampf(float(spec[4]), 0.0, 1.0) * 9.0
		for k: int in [0, 1, 2, 0, 2, 3]:
			st.set_color(spec[1])
			st.set_uv(corners[k])
			st.set_uv2(Vector2(spec[2], code))
			st.set_normal(Vector3.UP)
			st.add_vertex(spec[0])
	var mesh := st.commit()
	mesh.surface_set_material(0, Airport.light_material())
	var mi := MeshInstance3D.new()
	mi.name = "HelipadLights"
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 16384.0
	parent.add_child(mi)


## LOD and the far city: the garage as a parking box, the canopies and the lobby as plain
## boxes, the EMERGENCY sign as a lit red panel, the helipad deck and its beacons; the aircraft
## lights in the LOD ring (a real chunk), not in the capture.
static func _far(ch: CityChunk, st: Dictionary) -> void:
	var lay: Dictionary = st.lay
	var y0: float = st.y0
	var plain := Color(0.0, 0.0, 0.0, 1.0)
	var garage: Rect2 = lay.garage
	if garage.size.x > 0.0:
		var gr := Hospital.fr(lay, garage)
		var gh := ArenaGrounds.GARAGE_STOREY * 4.0 + 1.1
		_far_box(ch, Vector3(gr.get_center().x, y0 + gh * 0.5, gr.get_center().y), Vector3(gr.size.x, gh, gr.size.y), Color(0.62, 0.61, 0.58),
				Color(1.0 / 4.0, 0.06, float(int(lay.seed) % 997) / 997.0, 0.0))
		ch._add_lod_shape(Vector3(gr.size.x, gh, gr.size.y), Vector3(gr.get_center().x, y0 + gh * 0.5, gr.get_center().y))
	var loop: Rect2 = lay.loop
	var uc := loop.position.x + loop.size.x * 0.5
	var podium: Rect2 = lay.podium
	var cr := _r(lay, uc - 13.0, 7.6, uc + 13.0, podium.position.y - 3.6)
	_far_box(ch, Vector3(cr.get_center().x, y0 + CANOPY_H + 0.27, cr.get_center().y), Vector3(cr.size.x, 0.55, cr.size.y), Color(0.86, 0.87, 0.86), plain)
	var lr := _r(lay, uc - 12.0, podium.position.y - 3.6, uc + 12.0, podium.position.y + 0.4)
	_far_box(ch, Vector3(lr.get_center().x, y0 + LOBBY_H * 0.5, lr.get_center().y), Vector3(lr.size.x, LOBBY_H, lr.size.y), Color(0.20, 0.26, 0.30),
			Color(2.0 / 4.0, 0.7, 0.5, 0.0))
	var canopy: Rect2 = lay.canopy
	var br := Hospital.fr(lay, canopy)
	_far_box(ch, Vector3(br.get_center().x, y0 + BAY_CANOPY_H + 0.3, br.get_center().y), Vector3(br.size.x, 0.6, br.size.y), Color(0.86, 0.87, 0.86), plain)
	# The EMERGENCY sign: a lit red panel on the podium's ER wall (FarBuilding's plant PANEL).
	var court: Rect2 = lay.court
	var mid := canopy.position.y + canopy.size.y * 0.5
	var sr := _r(lay, court.position.x, mid - 7.75, court.position.x + 0.5, mid + 7.75)
	_far_box(ch, Vector3(sr.get_center().x, y0 + BAY_CANOPY_H + 4.3, sr.get_center().y), Vector3(sr.size.x, 2.45, sr.size.y), Color(0.75, 0.06, 0.04),
			Color(float(FarBuilding.Plant.PANEL), 1.0, 1.0, FarBuilding.PLANT_FLAG))
	# The helipad deck and the beacons on the tower's corners.
	var tower: Rect2 = lay.tower
	var roof := y0 + float(lay.podium_h) + float(lay.tower_h)
	var side := minf(tower.size.y - 1.0, 18.0) + 3.0
	var tc := Hospital.fp(lay, tower.position.x + tower.size.x * 0.5, tower.position.y + tower.size.y * 0.5)
	_far_box(ch, Vector3(tc.x, roof + 1.6, tc.y), Vector3(side, 1.2, side), Color(0.22, 0.23, 0.24),
			Color(float(FarBuilding.Plant.UNIT), 1.0, 0.0, FarBuilding.PLANT_FLAG))
	var tr := Hospital.fr(lay, tower)
	for q: Vector2 in [tr.position, tr.end, Vector2(tr.end.x, tr.position.y), Vector2(tr.position.x, tr.end.y)]:
		var inset := (tr.get_center() - q).normalized() * 0.6
		_far_box(ch, Vector3(q.x + inset.x, roof + 0.9, q.y + inset.y), Vector3(0.25, 1.8, 0.25), Color(0.3, 0.3, 0.3),
				Color(float(FarBuilding.Plant.BEACON_MAST), 1.0, 0.0, FarBuilding.PLANT_FLAG))
	if not ch.capturing:
		# The LOD ring's lights: the helipad's green edge and the red beacons.
		var node := Node3D.new()
		node.name = "HospitalFar"
		ch.add_child(node)
		var specs: Array = []
		var deck := roof + 2.2
		var s2 := side - 3.0
		var c2 := Vector2(tower.position.x + tower.size.x * 0.5, tower.position.y + tower.size.y * 0.5)
		for e in 4:
			for i in 5:
				var f := float(i) / 5.0
				var q: Vector2
				match e:
					0: q = Vector2(lerpf(-1, 1, f), -1)
					1: q = Vector2(lerpf(1, -1, f), 1)
					2: q = Vector2(-1, lerpf(1, -1, f))
					_: q = Vector2(1, lerpf(-1, 1, f))
				specs.append([_p(lay, c2.x + q.x * s2 * 0.5, c2.y + q.y * s2 * 0.5, deck + 0.12), PAD_GREEN, 0.5, 4, 0.0])
		var ph := fposmod(float(lay.seed) * 0.000137, 1.0)
		for q: Vector2 in [tr.position, tr.end, Vector2(tr.end.x, tr.position.y), Vector2(tr.position.x, tr.end.y)]:
			var inset := (tr.get_center() - q).normalized() * 0.6
			specs.append([Vector3(q.x + inset.x, roof + 1.6, q.y + inset.y), BEACON_RED, 1.1, 2, ph])
		_commit_lights(ch, node, specs)


## A far box at a true world centre (the chunk's batch adds the relief: taken back off here).
static func _far_box(ch: CityChunk, centre: Vector3, size: Vector3, color: Color, custom: Color) -> void:
	var at := centre
	at.y -= ch._gy(at.x, at.z)
	ch._batch.add("lod_box", PropFactory.unit_box(), Transform3D(Basis().scaled(size), at), color, custom)
