class_name AirportTerminal
extends RefCounted
## The airport's buildings, as landmarks (Landmarks.build() calls in here; each has a far version
## at low detail that CityStreamer keeps, so the field reads from across the basin):
##   terminal       the head house: the check-in hall, glazed to the curb, under one long roof
##                  that sweeps up off the airside and out over the drop-off lanes like a wing,
##                  carried on branching "tree" columns standing on the curb (original design).
##   concourse_w/_e the two halves of the curved concourse: a glazed departures level over the
##                  apron-level service floor, a clerestory down the roof, the jet bridges docked
##                  to the parked airliners (Airport.gates(): one MultiMesh of the airliner model in
##                  invented liveries, shaders/airliner_livery.gdshader).
##   control_tower  a ribbed shaft with a lit glass cab and the rotating beacon on top.
##   skyhook        the landside landmark: two parabolic arches crossing over a lit glass disc
##                  restaurant on a core, floodlit at night (an original take on a jet-age icon).
##   airport_garage the multi-storey car park west of the drop-off (ArenaGrounds.garage()).
##   rental_lot     the rental-car lot east of the arch: rows of cars, a glass pavilion, a canopy.
## All names are invented; the forms are a big field's. Geometry is LandmarkGeo (one mesh a
## building, a surface per material), materials LandmarkMats. Coordinates are world, y up from
## MacroMap.tarmac_top.

const TOWER_SHAFT_TOP := 58.0
const TOWER_CAB_TOP := 66.0
## The top of the tower's roof (the rotating beacon sits on it: Airport.lights_mesh()).
const TOWER_TOP := 70.0
const HALL_GLASS_TOP := 18.0
const DEPARTURE_LEVEL := 4.6
const NAME := "RANDO INTERNATIONAL"

static var _jet_mesh: Mesh = null
static var _jet_fit: Dictionary = {}
static var _jet_mat: ShaderMaterial = null


# --- Materials ----------------------------------------------------------------------------------

static func _glass(key: String, y0: float, storey: float, depth: float) -> ShaderMaterial:
	return LandmarkMats.glass("airport_" + key, {"glass_tint": Color(0.17, 0.24, 0.28), "frame_color": Color(0.74, 0.76, 0.79),
		"grid": Vector2(1.8, minf(storey * 0.5, 3.4)), "frame_width": 0.07, "room_depth": depth, "storey": storey, "floor_y": y0,
		"interior_color": Color(1.0, 0.88, 0.70), "interior_day": 0.16, "interior_night": 1.9, "spandrel_every": 0.0})


## Roofing: pale standing-seam metal (the brushed steel shader mirrored the sky and read as a
## blue plastic sheet from the air).
static func _steel(key: String) -> ShaderMaterial:
	return LandmarkMats.facade("airport_roof_" + key, "", 1.0, {"tint": Color(0.80, 0.80, 0.79), "roughness": 0.5, "metallic": 0.25,
		"joint_spacing": Vector2(0.6, 0.0), "joint_width": 0.03, "joint_dark": 0.22, "grime": 0.15})


static func _cladding(key: String, tint: Color, y0: float) -> ShaderMaterial:
	return LandmarkMats.facade("airport_" + key, "", 1.0, {"tint": tint, "roughness": 0.45, "metallic": 0.35,
		"joint_spacing": Vector2(3.0, 1.15), "joint_width": 0.015, "joint_dark": 0.3, "grime": 0.2, "base_y": y0,
		"flood_strength": 0.45, "flood_base_y": y0, "flood_reach": 6.0, "flood_spacing": 9.0})


static func _concrete(key: String, y0: float, flood: float = 0.6) -> ShaderMaterial:
	return LandmarkMats.facade("airport_" + key, "concrete", 4.0, {"tint": Color(0.86, 0.85, 0.82), "roughness": 0.8,
		"joint_spacing": Vector2(3.0, 3.0), "joint_width": 0.02, "joint_dark": 0.25, "grime": 0.25, "base_y": y0,
		"flood_strength": flood, "flood_base_y": y0, "flood_reach": 30.0, "flood_floor": 0.35, "flood_spacing": 4.0, "night_self": 0.05})


## The soffit under the head house's roof: warm slats, lit from below after dark.
static func _soffit() -> ShaderMaterial:
	return LandmarkMats.facade("airport_soffit", "planks", 3.0, {"tint": Color(0.92, 0.70, 0.48), "roughness": 0.7,
		"joint_spacing": Vector2(0.35, 0.0), "joint_width": 0.04, "joint_dark": 0.55, "night_self": 0.35})


# --- Head house ---------------------------------------------------------------------------------

## The roof's section across the hall: [z, y of the top] from the overhang's front edge over the
## drop-off to the concourse.
const ROOF_SECTION := [[619.0, 19.5], [626.0, 22.6], [636.0, 25.0], [648.0, 26.0], [660.0, 25.2], [674.0, 22.4], [692.0, 17.4]]
const ROOF_X0 := -452.0
const ROOF_X1 := -248.0
const ROOF_THICK := 1.1


static func _roof_y(z: float) -> float:
	for i in ROOF_SECTION.size() - 1:
		var a: Array = ROOF_SECTION[i]
		var b: Array = ROOF_SECTION[i + 1]
		if z <= float(b[0]):
			return lerpf(float(a[1]), float(b[1]), clampf((z - float(a[0])) / (float(b[0]) - float(a[0])), 0.0, 1.0))
	return float(ROOF_SECTION[ROOF_SECTION.size() - 1][1])


static func build_head_house(parent: Node3D, statics: StaticBody3D, macro: MacroMap, detailed: bool) -> void:
	var y0: float = macro.tarmac_top if macro else 0.1
	var hh := Airport.HEAD_HOUSE
	var g := LandmarkGeo.new()
	g.use("glass", _glass("hall", y0, 22.0, 26.0))
	g.use("steel", _steel("roof"))
	g.use("soffit", _soffit())
	g.use("concrete", _concrete("hall", y0))
	g.use("metal", LandmarkMats.plain("airport_metal", Color(0.78, 0.79, 0.81), 0.35, 0.6))
	g.use("dark", LandmarkMats.plain("airport_dark", Color(0.06, 0.065, 0.07), 0.5, 0.3))
	# The glazed walls: front (to the curb) and both ends, up to under the roof.
	var front := hh.position.y
	g.wall("glass", Vector2(hh.end.x, front), Vector2(hh.position.x, front), y0, y0 + _roof_y(front) - ROOF_THICK - 0.2, Color.WHITE, statics != null)
	for end in 2:
		var x := hh.position.x if end == 0 else hh.end.x
		var z0 := front
		var z1 := hh.end.y
		var top := y0 + minf(_roof_y(z0), _roof_y(z1)) - ROOF_THICK - 0.2
		if end == 0:
			g.wall("glass", Vector2(x, z0), Vector2(x, z1), y0, top, Color.WHITE, statics != null)
		else:
			g.wall("glass", Vector2(x, z1), Vector2(x, z0), y0, top, Color.WHITE, statics != null)
	# The plinth line and the entrance vestibules along the front: dark glass boxes with frames.
	g.box("concrete", Vector3((hh.position.x + hh.end.x) * 0.5, y0 + 0.25, front - 0.4), Vector3(hh.size.x, 0.5, 0.8), Color.WHITE)
	if detailed:
		var x := hh.position.x + 15.0
		while x < hh.end.x - 10.0:
			g.box("metal", Vector3(x, y0 + 1.75, front - 1.6), Vector3(7.0, 3.5, 3.2), Color(0.85, 0.86, 0.88), Basis(), 0.04)
			g.box("dark", Vector3(x, y0 + 1.5, front - 3.22), Vector3(5.6, 2.9, 0.06), Color.WHITE)
			x += 30.0
	# The roof: steel on top, slatted soffit underneath, a fascia round the edge.
	var nx := 24 if detailed else 8
	for i in nx:
		var xa := lerpf(ROOF_X0, ROOF_X1, float(i) / float(nx))
		var xb := lerpf(ROOF_X0, ROOF_X1, float(i + 1) / float(nx))
		for j in ROOF_SECTION.size() - 1:
			var a: Array = ROOF_SECTION[j]
			var b: Array = ROOF_SECTION[j + 1]
			var za := float(a[0])
			var zb := float(b[0])
			var ya := y0 + float(a[1])
			var yb := y0 + float(b[1])
			var nrm := Vector3(0.0, zb - za, -(yb - ya)).normalized()
			g.quad("steel", Vector3(xa, ya, za), Vector3(xb, ya, za), Vector3(xb, yb, zb), Vector3(xa, yb, zb), nrm,
				Vector2(xa, za), Vector2(xb, za), Vector2(xb, zb), Vector2(xa, zb), Color.WHITE, statics != null)
			g.quad("soffit", Vector3(xa, ya - ROOF_THICK, za), Vector3(xb, ya - ROOF_THICK, za), Vector3(xb, yb - ROOF_THICK, zb), Vector3(xa, yb - ROOF_THICK, zb), -nrm,
				Vector2(xa, ya), Vector2(xb, ya), Vector2(xb, yb), Vector2(xa, yb), Color.WHITE)
	for end in 2:
		var x := ROOF_X0 if end == 0 else ROOF_X1
		var out := Vector3(-1.0 if end == 0 else 1.0, 0.0, 0.0)
		for j in ROOF_SECTION.size() - 1:
			var a: Array = ROOF_SECTION[j]
			var b: Array = ROOF_SECTION[j + 1]
			var ya := y0 + float(a[1])
			var yb := y0 + float(b[1])
			g.quad("metal", Vector3(x, ya, float(a[0])), Vector3(x, yb, float(b[0])), Vector3(x, yb - ROOF_THICK, float(b[0])), Vector3(x, ya - ROOF_THICK, float(a[0])), out,
				Vector2(float(a[0]), ya), Vector2(float(b[0]), yb), Vector2(float(b[0]), yb - ROOF_THICK), Vector2(float(a[0]), ya - ROOF_THICK), Color(0.9, 0.9, 0.92))
	var z_front := float(ROOF_SECTION[0][0])
	var y_front := y0 + float(ROOF_SECTION[0][1])
	g.quad("metal", Vector3(ROOF_X0, y_front, z_front), Vector3(ROOF_X1, y_front, z_front), Vector3(ROOF_X1, y_front - ROOF_THICK, z_front), Vector3(ROOF_X0, y_front - ROOF_THICK, z_front),
		Vector3(0.0, 0.2, -1.0).normalized(), Vector2(ROOF_X0, y_front), Vector2(ROOF_X1, y_front), Vector2(ROOF_X1, y_front - ROOF_THICK), Vector2(ROOF_X0, y_front - ROOF_THICK), Color(0.9, 0.9, 0.92))
	# The tree columns on the curb: a trunk, then four branches up to the soffit.
	var cz := 629.0
	var x := hh.position.x
	while x <= hh.end.x + 0.5:
		var top := Vector3(x, y0 + 11.0, cz)
		g.cylinder("metal", Vector3(x, y0, cz), 0.55, 11.0, 12 if detailed else 6, Color(0.88, 0.89, 0.9), 0.42, statics != null, false)
		for b: Vector2 in [Vector2(-6.0, -5.0), Vector2(6.0, -5.0), Vector2(-6.0, 5.0), Vector2(6.0, 5.0)]:
			var tz := cz + b.y
			var tip := Vector3(x + b.x, y0 + _roof_y(tz) - ROOF_THICK + 0.05, tz)
			_strut(g, "metal", top, tip, 0.34, Color(0.88, 0.89, 0.9))
		x += 30.0
	# Lit DEPARTURES boards on three of the columns' trunks, over the curb (their dark backs here,
	# the lettering one mesh below).
	var boards: Array = []
	for k in 3:
		var bx := (hh.position.x + hh.end.x) * 0.5 + (float(k) - 1.0) * 60.0
		g.box("dark", Vector3(bx, y0 + 7.4, cz - 0.68), Vector3(12.0, 1.5, 0.25), Color.WHITE)
		boards.append(["DEPARTURES  %s" % ["A", "B", "C"][k], 1.0, Transform3D(Basis(Vector3.UP, PI), Vector3(bx, y0 + 7.4, cz - 0.82))])
	# Inside, seen through the glass: the check-in islands and the mezzanine edge.
	if detailed:
		var ix := hh.position.x + 22.0
		while ix < hh.end.x - 15.0:
			g.box("metal", Vector3(ix, y0 + 0.6, front + 16.0), Vector3(14.0, 1.2, 2.0), Color(0.75, 0.76, 0.78))
			g.box("dark", Vector3(ix, y0 + 2.6, front + 17.2), Vector3(14.0, 2.2, 0.3), Color.WHITE)
			ix += 30.0
		g.box("concrete", Vector3((hh.position.x + hh.end.x) * 0.5, y0 + 8.6, front + 30.0), Vector3(hh.size.x - 2.0, 0.6, 22.0), Color.WHITE)
	# The name along the fascia, facing the drop-off.
	var batch := MultiMeshBatch.new()
	g.commit(parent, "HeadHouse")
	g.commit_collision(statics)
	if statics:
		LandmarkGeo.shape_box(statics, Vector3((hh.position.x + hh.end.x) * 0.5, y0 + 10.0, (hh.position.y + hh.end.y) * 0.5), Vector3(hh.size.x, 20.0, hh.size.y))
	if detailed:
		var sign := MeshInstance3D.new()
		sign.name = "TerminalName"
		sign.mesh = PropFactory.text_mesh(NAME, 2.2)
		sign.material_override = PropFactory.material(Color(0.95, 0.95, 0.95), 0.5)
		sign.position = Vector3((ROOF_X0 + ROOF_X1) * 0.5, y_front - ROOF_THICK * 0.5, z_front - 0.15)
		sign.rotation.y = PI
		sign.rotation.x = -0.24
		parent.add_child(sign)
		var dep := MeshInstance3D.new()
		dep.name = "DeparturesBoards"
		dep.mesh = Airport.merged_text(boards, LandmarkMats.glow("airport_departures", Color(1.0, 0.82, 0.22)))
		dep.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(dep)
	batch.build(parent)
	_occluder(parent, [[Vector3((hh.position.x + hh.end.x) * 0.5, y0 + 9.0, (hh.position.y + hh.end.y) * 0.5), Vector3(hh.size.x - 4.0, 16.0, hh.size.y - 6.0)]], detailed and statics != null)


## A square-section strut from a to b (the tree columns' branches, the arch's ribs).
static func _strut(g: LandmarkGeo, key: String, a: Vector3, b: Vector3, w: float, col: Color) -> void:
	var d := b - a
	var length := d.length()
	if length < 0.01:
		return
	var up := Vector3.UP if absf(d.normalized().y) < 0.95 else Vector3.RIGHT
	var basis := Basis.looking_at(d / length, up)
	g.box(key, (a + b) * 0.5, Vector3(w, w, length), col, basis)


# --- Concourse ----------------------------------------------------------------------------------

## One half of the concourse (west: the gates west of due south of the arc's centre), its jet
## bridges and the airliners parked at its gates.
static func build_concourse(parent: Node3D, statics: StaticBody3D, macro: MacroMap, detailed: bool, west: bool) -> void:
	var y0: float = macro.tarmac_top if macro else 0.1
	var c := Airport.ARC_CENTRE
	var r := Airport.CONCOURSE_RADIUS
	var hw := Airport.CONCOURSE_HALF
	var h := Airport.CONCOURSE_HEIGHT
	# Angles in LandmarkGeo's ellipse frame (t from +X toward +Z) for a = PI/2 - t.
	var t0 := PI * 0.5 if west else PI * 0.5 - Airport.CONCOURSE_ARC
	var t1 := PI * 0.5 + Airport.CONCOURSE_ARC if west else PI * 0.5
	var segs := 40 if detailed else 12
	var g := LandmarkGeo.new()
	g.use("glass", _glass("concourse", y0 + DEPARTURE_LEVEL, h - DEPARTURE_LEVEL - 0.6, 9.0))
	g.use("base", _cladding("concourse_base", Color(0.40, 0.42, 0.45), y0))
	g.use("steel", _steel("concourse"))
	g.use("metal", LandmarkMats.plain("airport_metal", Color(0.78, 0.79, 0.81), 0.35, 0.6))
	g.use("dark", LandmarkMats.plain("airport_dark", Color(0.06, 0.065, 0.07), 0.5, 0.3))
	var col := statics != null
	var ro := Vector2(r + hw, r + hw)
	var ri := Vector2(r - hw, r - hw)
	# Service level (dark cladding), the glazed departures level, both faces.
	g.band("base", c, ro, ro, y0, y0 + DEPARTURE_LEVEL, t0, t1, segs, Color.WHITE, col)
	g.band("glass", c, ro, ro, y0 + DEPARTURE_LEVEL, y0 + h - 0.6, t0, t1, segs, Color.WHITE, col)
	g.band("base", c, ri, ri, y0, y0 + DEPARTURE_LEVEL, t0, t1, segs, Color.WHITE, col, true)
	g.band("glass", c, ri, ri, y0 + DEPARTURE_LEVEL, y0 + h - 0.6, t0, t1, segs, Color.WHITE, col, true)
	# A slab edge between the levels, the roof with its overhang, fascia and soffit.
	var re := Vector2(r + hw + 1.4, r + hw + 1.4)
	var rie := Vector2(r - hw - 1.0, r - hw - 1.0)
	g.band("metal", c, re, re, y0 + h - 0.7, y0 + h + 0.5, t0, t1, segs, Color(0.92, 0.92, 0.94), col)
	g.band("metal", c, rie, rie, y0 + h - 0.7, y0 + h + 0.5, t0, t1, segs, Color(0.92, 0.92, 0.94), col, true)
	g.ring_flat("metal", c, rie, re, y0 + h - 0.7, t0, t1, segs, Color(0.7, 0.71, 0.73), false, true)
	g.ring_flat("steel", c, rie, re, y0 + h + 0.5, t0, t1, segs, Color.WHITE, col)
	g.band("metal", c, ro + Vector2(0.15, 0.15), ro + Vector2(0.15, 0.15), y0 + DEPARTURE_LEVEL - 0.35, y0 + DEPARTURE_LEVEL + 0.15, t0, t1, segs, Color(0.85, 0.86, 0.88))
	# The clerestory down the middle of the roof.
	var rc0 := Vector2(r - 3.5, r - 3.5)
	var rc1 := Vector2(r + 3.5, r + 3.5)
	g.band("glass", c, rc1, rc1, y0 + h + 0.5, y0 + h + 2.6, t0, t1, segs, Color.WHITE)
	g.band("glass", c, rc0, rc0, y0 + h + 0.5, y0 + h + 2.6, t0, t1, segs, Color.WHITE, false, true)
	g.ring_flat("steel", c, rc0 - Vector2(0.5, 0.5), rc1 + Vector2(0.5, 0.5), y0 + h + 2.6, t0, t1, segs, Color.WHITE)
	# Depth on the apron face: a steel fin every 9 m standing proud of the glass, and a sunshade
	# band of louvres across the departures level (flat glass a whole concourse long read as one
	# sheet of plastic).
	var a_from := PI * 0.5 - t1
	var a_to := PI * 0.5 - t0
	var rf := r + hw
	var n_fins := int((a_to - a_from) * rf / 9.0)
	for i in n_fins + 1:
		var a := lerpf(a_from, a_to, float(i) / float(maxi(n_fins, 1)))
		var nrm := Airport.arc_normal(a)
		var p := Airport.arc_point(a, rf + 0.35)
		g.box("metal", Vector3(p.x, y0 + h * 0.5, p.y), Vector3(0.35, h - 0.4, 0.7), Color(0.86, 0.87, 0.89), Basis(Vector3.UP, atan2(nrm.x, nrm.y)), 0.03 if detailed else 0.0)
	if detailed:
		var rl := Vector2(rf + 1.1, rf + 1.1)
		for k in 3:
			var yl := y0 + 9.6 + float(k) * 0.42
			g.ring_flat("metal", c, ro, rl, yl, t0, t1, segs, Color(0.82, 0.83, 0.85))
			g.ring_flat("metal", c, ro, rl, yl - 0.06, t0, t1, segs, Color(0.6, 0.61, 0.63), false, true)
	# The end wall at the outer end of this half.
	var t_end := t1 if west else t0
	var e0 := LandmarkGeo.ell(c, ri, t_end)
	var e1 := LandmarkGeo.ell(c, ro, t_end)
	if west:
		g.wall("base", e1, e0, y0, y0 + DEPARTURE_LEVEL, Color.WHITE, col)
		g.wall("glass", e1, e0, y0 + DEPARTURE_LEVEL, y0 + h - 0.6, Color.WHITE, col)
	else:
		g.wall("base", e0, e1, y0, y0 + DEPARTURE_LEVEL, Color.WHITE, col)
		g.wall("glass", e0, e1, y0 + DEPARTURE_LEVEL, y0 + h - 0.6, Color.WHITE, col)
	# Jet bridges and the parked airliners at this half's gates.
	# Every stand gets an instance, the empty one too (collapsed): AirportGround shows, hides and
	# repaints each as jets arrive and leave (register_gate_jets(), below).
	var jets := MultiMeshBatch.new()
	var jet_gates := PackedInt32Array()
	var gate_list := Airport.gates()
	for gi in gate_list.size():
		var gate: Dictionary = gate_list[gi]
		var a: float = gate.a
		if (a < 0.0) != west:
			continue
		_jet_bridge(g, statics, gate, y0, detailed, parent, gi)
		var xf := jet_transform(gate.centre, gate.yaw, y0)
		if bool(gate.empty):
			xf = Transform3D(Basis().scaled(Vector3.ZERO), Vector3(0.0, -10000.0, 0.0))
		jets.add("gate_jet", jet_mesh(), xf, Color.WHITE, Color(float(gate.livery) / 8.0, 0.0, 0.0, 1.0))
		jet_gates.append(gi)
	# Gate signs over the doors on the apron face (the number lit at night).
	g.commit(parent, "ConcourseW" if west else "ConcourseE")
	g.commit_collision(statics)
	var nodes := jets.build(parent)
	if nodes.has("gate_jet"):
		(nodes["gate_jet"] as MultiMeshInstance3D).material_override = jet_material()
		var twin: Node = (nodes["gate_jet"] as Node).get_meta("shadow_twin", null) if (nodes["gate_jet"] as Node).has_meta("shadow_twin") else null
		if twin:
			(twin as MultiMeshInstance3D).material_override = jet_material()
		if macro:
			AirportGround.register_gate_jets(nodes["gate_jet"], jet_gates, y0, macro)
	if detailed:
		# The gate numbers over the apron face, lit: one mesh for the half.
		var items: Array = []
		for gate in Airport.gates():
			var a: float = gate.a
			if (a < 0.0) != west:
				continue
			var at := Airport.arc_point(a, r + hw + 0.25)
			var n: Vector2 = gate.n
			items.append([str(gate.number), 1.6, Transform3D(Basis(Vector3.UP, atan2(n.x, n.y)), Vector3(at.x, y0 + h - 1.6, at.y))])
		var sign := MeshInstance3D.new()
		sign.name = "GateNumbers"
		sign.mesh = Airport.merged_text(items, LandmarkMats.glow("airport_gate_no", Color(1.0, 0.82, 0.25)))
		sign.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(sign)


## The airliner model (Aircraft.MODELS AIRLINER) as one mesh, and the transform that parks it:
## nose toward `yaw`'s forward, wheels on y0, its centre over `centre`.
static func jet_mesh() -> Mesh:
	if _jet_mesh != null:
		return _jet_mesh
	var path: String = Aircraft.MODELS.get(Aircraft.Kind.AIRLINER, "")
	if path != "" and ResourceLoader.exists(path):
		var scene := load(path) as PackedScene
		var inst := scene.instantiate() as Node3D if scene else null
		if inst:
			var mis := inst.find_children("*", "MeshInstance3D", true, false)
			if not mis.is_empty():
				var mi := mis[0] as MeshInstance3D
				_jet_mesh = mi.mesh
				var box := mi.mesh.get_aabb()
				_jet_fit = {"scale": Airport.JET_LENGTH / maxf(box.size.x, 0.01), "centre": box.get_center(), "bottom": box.position.y}
			inst.free()
	if _jet_mesh == null:
		var cap := CapsuleMesh.new()
		cap.radius = 2.0
		cap.height = Airport.JET_LENGTH
		_jet_mesh = cap
		_jet_fit = {"scale": 1.0, "centre": Vector3.ZERO, "bottom": -2.0, "capsule": true}
	return _jet_mesh


static func jet_transform(centre: Vector2, yaw: float, y0: float) -> Transform3D:
	jet_mesh()
	var s: float = _jet_fit.scale
	if _jet_fit.has("capsule"):
		return Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, PI * 0.5), Vector3(centre.x, y0 + 2.0, centre.y))
	# The model lies along x with its nose at -x; turned -90 degrees its nose points -z, and the
	# stand's yaw turns -z onto the nose's heading.
	var basis := Basis(Vector3.UP, yaw) * Basis(Vector3.UP, -PI * 0.5) * Basis().scaled(Vector3.ONE * s)
	var mc: Vector3 = _jet_fit.centre
	var offset := basis * Vector3(mc.x, _jet_fit.bottom, mc.z)
	return Transform3D(basis, Vector3(centre.x, y0, centre.y) - offset)


static func jet_material() -> ShaderMaterial:
	if _jet_mat == null:
		_jet_mat = ShaderMaterial.new()
		_jet_mat.shader = load("res://shaders/airliner_livery.gdshader")
		_jet_mat.set_shader_parameter("cabin_glow", 0.35)
	return _jet_mat


## A livery material for one jet (AmbientJet's airliners): `livery` 0..5.
static func livery_material(livery: int) -> ShaderMaterial:
	var key := "livery_%d" % livery
	if LandmarkMats._cache.has(key):
		return LandmarkMats._cache[key]
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/airliner_livery.gdshader")
	mat.set_shader_parameter("livery", float(livery % Airport.LIVERIES))
	mat.set_shader_parameter("cabin_glow", 0.8)
	LandmarkMats._cache[key] = mat
	return mat


## A jet bridge: the rotunda at the concourse face, a two-section telescoping tunnel sloping down
## to the cab docked at the parked jet's forward door, the drive column with its wheel bogie.
static func _jet_bridge(g: LandmarkGeo, statics: StaticBody3D, gate: Dictionary, y0: float, detailed: bool, parent: Node3D = null, gate_index: int = -1) -> void:
	var bridge_mat := LandmarkMats.facade("airport_bridge", "", 1.0, {"tint": Color(0.80, 0.81, 0.83), "roughness": 0.4, "metallic": 0.4,
		"joint_spacing": Vector2(0.22, 0.0), "joint_width": 0.02, "joint_dark": 0.18, "flood_strength": 0.0})
	g.use("bridge", bridge_mat)
	var n: Vector2 = gate.n
	var t: Vector2 = gate.t
	var rot: Vector2 = gate.rotunda
	var door: Vector3 = gate.door
	if bool(gate.empty):
		# Parked back against the building, the cab turned along it.
		door = Vector3(rot.x, 0.0, rot.y) + Vector3(n.x, 0.0, n.y) * 9.0 + Vector3(t.x, 0.0, t.y) * 3.0 + Vector3(0.0, 4.4, 0.0)
	var floor_r := y0 + DEPARTURE_LEVEL
	# The rotunda: a short drum on a column.
	g.cylinder("bridge", Vector3(rot.x, y0, rot.y), 0.7, DEPARTURE_LEVEL - 0.4, 8, Color(0.6, 0.6, 0.62))
	g.cylinder("bridge", Vector3(rot.x, floor_r - 0.4, rot.y), 2.3, 3.4, 12 if detailed else 6, Color.WHITE)
	if detailed and parent != null and gate_index >= 0 and JetBridge.posable:
		# Near: the tunnels, cab and drive column are a JetBridge, posed from the stand's state
		# (AirportGround); the far copy keeps the static bridge below.
		var jb := JetBridge.new()
		jb.name = "JetBridge%d" % gate_index
		var mats: Array[Material] = [bridge_mat, LandmarkMats.plain("airport_dark", Color(0.06, 0.065, 0.07), 0.5, 0.3), LandmarkMats.plain("airport_metal", Color(0.78, 0.79, 0.81), 0.35, 0.6)]
		jb.setup(gate_index, y0, detailed, mats)
		parent.add_child(jb)
		return
	# The cab sits off the door on the port side (-t), facing the fuselage.
	var cab := door - Vector3(t.x, 0.0, t.y) * 1.9
	cab.y = y0 + door.y - 0.6
	var start := Vector3(rot.x, floor_r + 1.3, rot.y)
	var end := cab - Vector3(t.x, 0.0, t.y) * 1.7 + Vector3(0.0, 1.3, 0.0)
	var mid := start.lerp(end, 0.5)
	_tunnel(g, start, mid + (end - start).normalized() * 0.6, 3.2, 3.1)
	_tunnel(g, mid - (end - start).normalized() * 0.6, end, 3.0, 2.9)
	# Cab: a box turned to the fuselage, a dark bellows face, the canopy.
	var face := atan2(t.x, t.y)
	g.box("bridge", cab + Vector3(0.0, 1.3, 0.0), Vector3(3.6, 3.0, 3.2), Color.WHITE, Basis(Vector3.UP, face), 0.05 if detailed else 0.0)
	g.box("dark", cab + Vector3(t.x, 0.0, t.y) * 1.62 + Vector3(0.0, 1.3, 0.0), Vector3(3.2, 2.7, 0.12), Color.WHITE, Basis(Vector3.UP, face))
	# Drive column under the outer tunnel: two legs, a bogie with its wheels.
	var dc := end.lerp(start, 0.18)
	dc.y = y0
	for s: float in [-0.9, 0.9]:
		var leg := dc + Vector3(n.x, 0.0, n.y) * s
		g.box("metal", leg + Vector3(0.0, (end.y - 1.6 - y0) * 0.5, 0.0), Vector3(0.3, end.y - 1.6 - y0, 0.3), Color(0.75, 0.76, 0.78))
	g.box("metal", dc + Vector3(0.0, 0.55, 0.0), Vector3(2.6, 0.5, 1.2), Color(0.85, 0.65, 0.1), Basis(Vector3.UP, atan2(n.x, n.y)))
	if detailed:
		for s: float in [-1.0, 1.0]:
			g.cylinder("dark", dc + Vector3(n.x, 0.0, n.y) * (s * 1.1) - Vector3(t.x, 0.0, t.y) * 0.4, 0.45, 0.4, 8, Color.WHITE)
	if statics:
		var d := end - start
		LandmarkGeo.shape_box(statics, (start + end) * 0.5, Vector3(3.2, 3.1, d.length()), Basis.looking_at(d.normalized(), Vector3.UP))


## A box tunnel from a to b (centre line of its floor + half its height), w wide, h tall, with a
## band of windows along both sides.
static func _tunnel(g: LandmarkGeo, a: Vector3, b: Vector3, w: float, h: float) -> void:
	var d := b - a
	var basis := Basis.looking_at(d.normalized(), Vector3.UP)
	g.box("bridge", (a + b) * 0.5, Vector3(w, h, d.length()), Color.WHITE, basis, 0.0, false, 0.0, true)
	for s: float in [-1.0, 1.0]:
		g.box("dark", (a + b) * 0.5 + basis * Vector3(s * (w * 0.5 + 0.01), 0.25, 0.0), Vector3(0.02, 0.8, d.length() - 0.8), Color.WHITE, basis)


# --- Control tower ------------------------------------------------------------------------------

static func build_tower(parent: Node3D, statics: StaticBody3D, macro: MacroMap, detailed: bool) -> void:
	var y0: float = macro.tarmac_top if macro else 0.1
	var at := Airport.TOWER_AT
	var g := LandmarkGeo.new()
	g.use("concrete", _concrete("tower", y0, 0.9))
	g.use("glass", LandmarkMats.glass("airport_cab", {"glass_tint": Color(0.12, 0.20, 0.22), "frame_color": Color(0.30, 0.32, 0.34),
		"grid": Vector2(2.2, 3.5), "frame_width": 0.12, "room_depth": 9.0, "storey": 7.0, "floor_y": y0 + TOWER_SHAFT_TOP + 1.0,
		"interior_color": Color(0.70, 0.95, 0.85), "interior_day": 0.12, "interior_night": 1.3}))
	g.use("base_glass", _glass("tower_base", y0, 4.0, 7.0))
	g.use("metal", LandmarkMats.plain("airport_metal", Color(0.78, 0.79, 0.81), 0.35, 0.6))
	g.use("dark", LandmarkMats.plain("airport_dark", Color(0.06, 0.065, 0.07), 0.5, 0.3))
	var col := statics != null
	var segs := 16 if detailed else 8
	# The base building: a low glazed block round the foot.
	var base := PackedVector2Array([at + Vector2(-16.0, -7.0), at + Vector2(14.0, -7.0), at + Vector2(14.0, 9.0), at + Vector2(-16.0, 9.0)])
	g.prism("base_glass", base, y0, y0 + 8.0, Color.WHITE, col, true, false, "metal")
	# The shaft: a core with four fins tapering in as it rises (a cross in plan).
	g.cylinder("concrete", Vector3(at.x, y0, at.y), 3.6, TOWER_SHAFT_TOP, segs, Color.WHITE, 3.0, col, false)
	for k in 4:
		var ang := float(k) * PI * 0.5 + PI * 0.25
		var dir := Vector3(cos(ang), 0.0, sin(ang))
		var fin_basis := Basis.looking_at(dir, Vector3.UP)
		var lean := Basis(fin_basis.x, 0.035) * fin_basis
		g.box("concrete", Vector3(at.x, y0, at.y) + dir * 3.6 + Vector3(0.0, TOWER_SHAFT_TOP * 0.5, 0.0), Vector3(0.9, TOWER_SHAFT_TOP, 3.4), Color.WHITE, lean)
	# The services floor, the catwalk, the cab (glass leaning out), the roof and the mast.
	var c2 := at
	var ys := y0 + TOWER_SHAFT_TOP
	g.band("dark", c2, Vector2(5.0, 5.0), Vector2(7.2, 7.2), ys - 2.5, ys, 0.0, TAU, segs, Color.WHITE, col)
	g.ring_flat("metal", c2, Vector2(3.0, 3.0), Vector2(8.4, 8.4), ys, 0.0, TAU, segs, Color(0.75, 0.76, 0.78), col)
	g.band("metal", c2, Vector2(8.4, 8.4), Vector2(8.4, 8.4), ys, ys + 1.1, 0.0, TAU, segs, Color(0.85, 0.86, 0.88))
	g.band("glass", c2, Vector2(7.2, 7.2), Vector2(8.6, 8.6), ys + 0.4, y0 + TOWER_CAB_TOP, 0.0, TAU, segs, Color.WHITE, col)
	g.ring_flat("dark", c2, Vector2(0.5, 0.5), Vector2(9.4, 9.4), y0 + TOWER_CAB_TOP, 0.0, TAU, segs, Color.WHITE, false, true)
	g.band("metal", c2, Vector2(9.4, 9.4), Vector2(9.0, 9.0), y0 + TOWER_CAB_TOP, y0 + TOWER_CAB_TOP + 1.2, 0.0, TAU, segs, Color(0.92, 0.92, 0.94), col)
	g.dome("metal", c2, Vector2(9.0, 9.0), y0 + TOWER_CAB_TOP + 1.2, 1.6, segs, 3, Color(0.88, 0.88, 0.9), col)
	g.cylinder("metal", Vector3(at.x, y0 + TOWER_CAB_TOP + 2.6, at.y), 0.35, TOWER_TOP - TOWER_CAB_TOP - 2.6, 8, Color(0.7, 0.7, 0.72))
	if detailed:
		# Consoles round the inside of the cab, seen through the glass.
		for k in 12:
			var ang := TAU * float(k) / 12.0
			var p := c2 + Vector2(cos(ang), sin(ang)) * 6.2
			g.box("dark", Vector3(p.x, ys + 1.3, p.y), Vector3(2.8, 1.0, 1.1), Color.WHITE, Basis(Vector3.UP, -ang + PI * 0.5))
		for k in 3:
			var ang := TAU * float(k) / 3.0 + 0.4
			var p := c2 + Vector2(cos(ang), sin(ang)) * 3.0
			_strut(g, "metal", Vector3(p.x, y0 + TOWER_CAB_TOP + 2.0, p.y), Vector3(at.x, y0 + TOWER_TOP - 0.4, at.y), 0.12, Color(0.7, 0.7, 0.72))
	g.commit(parent, "ControlTower")
	g.commit_collision(statics)
	_occluder(parent, [[Vector3(at.x, y0 + TOWER_SHAFT_TOP * 0.5, at.y), Vector3(4.0, TOWER_SHAFT_TOP - 4.0, 4.0)]], detailed and statics != null)


# --- The arches ---------------------------------------------------------------------------------

const ARCH_SPAN := 58.0
const ARCH_RISE := 38.0
const DISC_Y := 21.0
const DISC_R := 13.0


static func build_skyhook(parent: Node3D, statics: StaticBody3D, macro: MacroMap, detailed: bool) -> void:
	var y0: float = macro.tarmac_top if macro else 0.1
	var at := Airport.SKYHOOK_AT
	var g := LandmarkGeo.new()
	var white := LandmarkMats.facade("airport_arch", "concrete", 3.0, {"tint": Color(0.95, 0.95, 0.93), "roughness": 0.55,
		"joint_spacing": Vector2(0.0, 0.0), "grime": 0.08, "base_y": y0, "flood_strength": 1.1, "flood_base_y": y0,
		"flood_reach": 45.0, "flood_floor": 0.45, "flood_spacing": 50.0, "flood_color": Color(0.80, 0.85, 1.0), "night_self": 0.08})
	g.use("white", white)
	g.use("glass", LandmarkMats.glass("airport_disc", {"glass_tint": Color(0.14, 0.22, 0.30), "frame_color": Color(0.85, 0.86, 0.88),
		"grid": Vector2(1.4, 3.6), "frame_width": 0.06, "room_depth": 9.0, "storey": 3.6, "floor_y": y0 + DISC_Y,
		"interior_color": Color(1.0, 0.70, 0.42), "interior_day": 0.18, "interior_night": 2.2}))
	g.use("paving", LandmarkMats.paving("paving", 3.0, Color(0.95, 0.93, 0.9), 7731))
	g.use("metal", LandmarkMats.plain("airport_metal", Color(0.78, 0.79, 0.81), 0.35, 0.6))
	var col := statics != null
	var segs := 24 if detailed else 10
	# The plaza.
	g.cap("paving", LandmarkGeo.ccw(_circle(at, 34.0, segs)), y0 + 0.18)
	g.band("paving", at, Vector2(34.0, 34.0), Vector2(34.0, 34.0), y0, y0 + 0.18, 0.0, TAU, segs)
	# Two arches crossing over the centre, along the diagonals: a tapering box section swept along
	# a parabola, legs splayed.
	for k in 2:
		var ang := PI * 0.25 + float(k) * PI * 0.5
		var dir := Vector2(cos(ang), sin(ang))
		var n := 14 if detailed else 7
		var prev := Vector3.ZERO
		for i in n + 1:
			var s := lerpf(-1.0, 1.0, float(i) / float(n))
			var p2 := at + dir * (s * ARCH_SPAN * 0.5)
			var p := Vector3(p2.x, y0 + ARCH_RISE * (1.0 - s * s), p2.y)
			if i > 0:
				var w := lerpf(1.1, 2.4, absf(s))
				_strut(g, "white", prev, p, w, Color.WHITE)
			prev = p
	# The core, the disc and its glazed band, the roof dish.
	g.cylinder("white", Vector3(at.x, y0, at.y), 2.4, DISC_Y, segs, Color.WHITE, 2.0, col, false)
	g.band("white", at, Vector2(4.0, 4.0), Vector2(DISC_R, DISC_R), y0 + DISC_Y - 3.0, y0 + DISC_Y, 0.0, TAU, segs * 2, Color.WHITE, col)
	g.ring_flat("white", at, Vector2(2.0, 2.0), Vector2(4.0, 4.0), y0 + DISC_Y - 3.0, 0.0, TAU, segs, Color.WHITE, false, true)
	g.band("glass", at, Vector2(DISC_R - 0.4, DISC_R - 0.4), Vector2(DISC_R + 0.6, DISC_R + 0.6), y0 + DISC_Y, y0 + DISC_Y + 3.6, 0.0, TAU, segs * 2, Color.WHITE, col)
	g.band("white", at, Vector2(DISC_R + 0.6, DISC_R + 0.6), Vector2(DISC_R - 1.5, DISC_R - 1.5), y0 + DISC_Y + 3.6, y0 + DISC_Y + 5.0, 0.0, TAU, segs * 2, Color.WHITE, col)
	g.dome("white", at, Vector2(DISC_R - 1.5, DISC_R - 1.5), y0 + DISC_Y + 5.0, 1.5, segs * 2, 3, Color.WHITE, col)
	g.ring_flat("metal", at, Vector2(DISC_R - 0.5, DISC_R - 0.5), Vector2(DISC_R + 0.2, DISC_R + 0.2), y0 + DISC_Y, 0.0, TAU, segs * 2, Color(0.8, 0.8, 0.82), col)
	g.commit(parent, "Skyhook")
	g.commit_collision(statics)
	if detailed:
		var batch := MultiMeshBatch.new()
		for i in 8:
			var ang := TAU * float(i) / 8.0 + 0.2
			var p := at + Vector2(cos(ang), sin(ang)) * 29.0
			batch.add("palm_%d" % (i % 3), PropFactory.palm(i % 3), Transform3D(Basis(Vector3.UP, ang).scaled(Vector3.ONE * (1.1 + 0.1 * float(i % 3))), Vector3(p.x, y0 + 0.18, p.y)))
		batch.build(parent)


static func _circle(c: Vector2, r: float, n: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in n:
		var a := TAU * float(i) / float(n)
		out.append(c + Vector2(cos(a), sin(a)) * r)
	return out


# --- Landside: the car park and the rental lot ---------------------------------------------------

static func build_garage(parent: Node3D, statics: StaticBody3D, macro: MacroMap, detailed: bool) -> void:
	var y0: float = macro.tarmac_top if macro else 0.1
	var g := LandmarkGeo.new()
	var batch := MultiMeshBatch.new()
	ArenaGrounds.garage(g, batch, parent, statics, Airport.GARAGE_RECT, 4, y0, detailed, 90311, 1)
	g.commit(parent, "AirportGarage")
	g.commit_collision(statics)
	batch.build(parent)
	var r := Airport.GARAGE_RECT
	# No occluder: a car park's decks are open between the spandrels, and what is behind them shows.
	if detailed:
		var sign := MeshInstance3D.new()
		sign.name = "GarageSign"
		sign.mesh = PropFactory.text_mesh("PARKING  P1", 2.4)
		sign.material_override = LandmarkMats.glow("airport_sign", Color(0.95, 0.95, 0.95))
		sign.position = Vector3(r.end.x + 0.3, y0 + 14.2, r.get_center().y)
		sign.rotation.y = PI * 0.5
		parent.add_child(sign)


static func build_rental(parent: Node3D, statics: StaticBody3D, macro: MacroMap, detailed: bool) -> void:
	var y0: float = macro.tarmac_top if macro else 0.1
	var r := Airport.RENTAL_RECT
	var g := LandmarkGeo.new()
	var batch := MultiMeshBatch.new()
	var lot := Rect2(r.position + Vector2(30.0, 0.0), r.size - Vector2(30.0, 0.0))
	if detailed:
		ArenaGrounds.surface_lot(g, batch, parent, lot, y0, 4417)
	else:
		g.use("lot_asphalt", LandmarkMats.paving("asphalt", 4.0, Color(0.6, 0.6, 0.61), 4417, 0.0, 0.45))
		g.cap("lot_asphalt", LandmarkGeo.ccw(LandmarkArenaDistrict._rect_poly(lot)), y0 + 0.045)
	# The rental pavilion at the west end: a glass box under a deep flat roof, a canopy over the
	# pick-up lane in front of it.
	g.use("glass", _glass("rental", y0, 4.5, 8.0))
	g.use("metal", LandmarkMats.plain("airport_metal", Color(0.78, 0.79, 0.81), 0.35, 0.6))
	var px := r.position.x + 2.0
	var pav := PackedVector2Array([Vector2(px, r.position.y + 6.0), Vector2(px + 24.0, r.position.y + 6.0), Vector2(px + 24.0, r.position.y + 24.0), Vector2(px, r.position.y + 24.0)])
	g.prism("glass", pav, y0, y0 + 5.0, Color.WHITE, statics != null, false)
	g.box("metal", Vector3(px + 12.0, y0 + 5.3, r.position.y + 15.0), Vector3(28.0, 0.6, 22.0), Color(0.9, 0.9, 0.92), Basis(), 0.05, statics != null)
	g.box("metal", Vector3(px + 12.0, y0 + 4.6, r.position.y + 38.0), Vector3(26.0, 0.4, 14.0), Color(0.85, 0.86, 0.88), Basis(), 0.04)
	for cx: float in [px + 1.0, px + 23.0]:
		for cz: float in [r.position.y + 32.0, r.position.y + 44.0]:
			g.box("metal", Vector3(cx, y0 + 2.2, cz), Vector3(0.3, 4.4, 0.3), Color(0.7, 0.7, 0.72))
	g.commit(parent, "RentalLot")
	g.commit_collision(statics)
	batch.build(parent)
	if detailed:
		var sign := MeshInstance3D.new()
		sign.name = "RentalSign"
		sign.mesh = PropFactory.text_mesh("RENTAL CARS", 1.6)
		sign.material_override = LandmarkMats.glow("airport_sign", Color(0.95, 0.95, 0.95))
		sign.position = Vector3(px + 12.0, y0 + 5.3, r.position.y + 3.9)
		sign.rotation.y = PI
		parent.add_child(sign)


## Built only for the detailed copy. (It used to read CivicSites.ctx, which only the civic sites
## set, so the airport's never were.)
static func _occluder(parent: Node3D, boxes: Array, detailed: bool) -> void:
	LandmarkArenaDistrict._occluder(parent, boxes, 1 if detailed else 0)
