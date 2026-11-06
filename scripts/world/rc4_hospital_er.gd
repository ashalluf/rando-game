class_name RcHospitalEr
extends RefCounted
## The hospital's ambulance court at night, judged from the `hospital_er` reference camera
## (tools/refcams/cameras_w7.json; docs/HANDOFF.md "The ER's ambulance court at night"). Hooks in
## HospitalBuild._er_bay(): what an ER entrance reads as at 23:00 in a 2026 game -
##  - the EMERGENCY light box a DEEP red with white letters (its red face at 1.5x red-heavy HDR went
##    through AgX as a salmon-pink panel: the box now glows under 1 and the letters carry the bloom),
##  - the canopy's underside lit: a glowing soffit and LED panels in a grid, a white wash on the court
##    under it (the old six 0.8 m lamps lit nothing a camera could see),
##  - the podium's court wall glazed at the ground floor either side of the ER doors (the waiting room
##    and the triage desk lit behind it; it was a band of black ribbon windows),
##  - the "AMBULANCE ENTRANCE" words on the fascia big enough to read from the street.
## FULL chunks only (the LOD and far tiers keep their lit panel). `RC4_HOSPITAL=0` is the A/B.

static func _static_init() -> void: LoadPulse.compiled()  # a boot frame: docs/HANDOFF.md "The boot compile"

static var enabled := OS.get_environment("RC4_HOSPITAL") != "0"

## The light box (LINEAR, hospital_sign.gdshader): a dark red face glowing under 1 at night.
const BOX_FACE := Vector3(0.26, 0.008, 0.006)
const BOX_GLOW := Vector3(1.0, 0.022, 0.014)
const BOX_NIGHT := 0.66
const BOX_DAY := 0.12
## The soffit's glow (LINEAR) at night: the canopy underside washed by its own fixtures.
const SOFFIT_GLOW := Vector3(0.95, 0.96, 0.92)
const SOFFIT_NIGHT := 0.42
## The light box's centre over the canopy (m): 4.3 put its lower half behind the fascia for anyone
## coming up the court from the street.
const SIGN_RISE := 5.5
## The court's floods on the fascia: reach (m) and their share of the lamp level.
const FLOOD_RANGE := 17.0
const FLOOD_GAIN := 1.5
## The fascia's words (m).
const FASCIA_LETTER := 0.62
## The ER wall's glazing: height (m) over the court floor and the lit room's colour.
const GLAZE_H := 4.1


## The light box's material (cached by HospitalBuild.sign_material).
static func box_material() -> ShaderMaterial:
	return HospitalBuild.sign_material("er_box_rc4", BOX_FACE, BOX_GLOW, BOX_NIGHT, BOX_DAY, true)


## The canopy's lit underside, LED panels and the wash on the court. `y_court` is the court's
## surface, `y_soffit` the canopy's underside.
static func canopy(ch: CityChunk, g: LandmarkGeo, lay: Dictionary, node: Node3D, batch: MultiMeshBatch, y_court: float, y_soffit: float) -> void:
	var canopy: Rect2 = lay.canopy
	var u0 := canopy.position.x
	var u1 := canopy.end.x
	var v0 := canopy.position.y
	var v1 := canopy.end.y
	# The soffit: one quad just under the slab, facing down, glowing like a lit ceiling.
	var mi := MeshInstance3D.new()
	mi.name = "ERSoffit"
	var qm := QuadMesh.new()
	var r := HospitalBuild._r(lay, u0 + 0.05, v0 + 0.05, u1 - 0.05, v1 - 0.05)
	qm.size = r.size
	qm.material = HospitalBuild.sign_material("er_soffit", Vector3(0.80, 0.80, 0.78), SOFFIT_GLOW, SOFFIT_NIGHT, 0.0)
	mi.mesh = qm
	mi.transform = Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(r.get_center().x, y_soffit - 0.012, r.get_center().y))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.add_child(mi)
	# LED panels in a grid (3 across the canopy's depth, 5 along it).
	for i in 3:
		var u := lerpf(u0 + 1.6, u1 - 1.6, float(i) / 2.0)
		for k in 5:
			var v := lerpf(v0 + 1.4, v1 - 1.4, float(k) / 4.0)
			HospitalBuild._fbox(g, lay, "h_lamp", u - 0.6, v - 0.3, u + 0.6, v + 0.3, y_soffit - 0.05, y_soffit - 0.013)
	# The wash on the court: one broad white pool under the canopy, a softer one spilling out.
	var c := HospitalBuild._p(lay, (u0 + u1) * 0.5, (v0 + v1) * 0.5, y_court + 0.03)
	var span := HospitalBuild._r(lay, u0, v0, u1, v1).size
	batch.add("h_pool", PropFactory.light_pool(Color(0.95, 0.97, 1.0), 0.95),
			Transform3D(Basis(Vector3.RIGHT, -PI * 0.5).scaled(Vector3(span.x * 1.25, 1.0, span.y * 1.15)), c))
	var oy := court_y(func(x: float, z: float) -> float: return ch._gy(x, z), lay, u1 + 4.0, (v0 + v1) * 0.5)
	var out := HospitalBuild._p(lay, u1 + 4.0, (v0 + v1) * 0.5, oy + 0.028)
	batch.add("h_pool", PropFactory.light_pool(Color(0.95, 0.97, 1.0), 0.55),
			Transform3D(Basis(Vector3.RIGHT, -PI * 0.5).scaled(Vector3(14.0, 1.0, 14.0)), out))
	# Two floods on the fascia's street face light the court and its ramp out to the street (the
	# canopy's own lamp reaches 14 m round its middle and left the ramp a black wall); a real
	# lamp_light each on desktop, and their lamp heads.
	for k in 2:
		var v := lerpf(v0 + 1.2, v1 - 1.2, float(k))
		HospitalBuild._fbox(g, lay, "h_metal", u1 + 0.1, v - 0.35, u1 + 0.5, v + 0.35, y_soffit + 0.05, y_soffit + 0.3)
		HospitalBuild._fbox(g, lay, "h_lamp", u1 + 0.5, v - 0.3, u1 + 0.54, v + 0.3, y_soffit + 0.08, y_soffit + 0.27)
		if OS.has_feature("web"):
			continue
		var l := OmniLight3D.new()
		l.name = "ERFlood%d" % k
		l.omni_range = FLOOD_RANGE
		l.omni_attenuation = 1.3
		l.light_energy = 0.0
		l.light_color = Color(0.96, 0.97, 1.0)
		l.shadow_enabled = false
		l.distance_fade_enabled = true
		l.distance_fade_begin = 90.0
		l.distance_fade_length = 25.0
		l.position = HospitalBuild._p(lay, u1 + 1.2, v, y_soffit + 0.2)
		l.set_meta("lamp_gain", FLOOD_GAIN)
		l.add_to_group("lamp_light")
		node.add_child(l)


## The podium's court wall glazed at the ground floor, skipping the door portals `doors`
## ([v, half width] each), from v `va` to `vb`; a mullion frame and a transom band over it.
## Returns how many runs of glass it laid.
static func glazing(g: LandmarkGeo, lay: Dictionary, wall_u: float, va: float, vb: float, doors: Array, y0: float) -> int:
	var cuts: Array = []
	for d: Array in doors:
		cuts.append([float(d[0]) - float(d[1]) - 0.45, float(d[0]) + float(d[1]) + 0.45])
	cuts.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var runs: Array = []
	var at := va
	for c: Array in cuts:
		if float(c[0]) - at > 0.8:
			runs.append([at, float(c[0])])
		at = maxf(at, float(c[1]))
	if vb - at > 0.8:
		runs.append([at, vb])
	for run: Array in runs:
		var a := float(run[0])
		var b := float(run[1])
		HospitalBuild._fbox(g, lay, "h_glass", wall_u + 0.02, a, wall_u + 0.1, b, y0 + 0.02, y0 + GLAZE_H)
		# The frame: a sill, a head and the transom band of metal over it.
		HospitalBuild._fbox(g, lay, "h_metal", wall_u + 0.0, a - 0.08, wall_u + 0.16, b + 0.08, y0 + GLAZE_H, y0 + GLAZE_H + 0.35)
		HospitalBuild._fbox(g, lay, "h_metal", wall_u + 0.0, a - 0.08, wall_u + 0.16, b + 0.08, y0 - 0.02, y0 + 0.08)
		HospitalBuild._fbox(g, lay, "h_metal", wall_u + 0.0, a - 0.08, wall_u + 0.16, a + 0.04, y0, y0 + GLAZE_H)
		HospitalBuild._fbox(g, lay, "h_metal", wall_u + 0.0, b - 0.04, wall_u + 0.16, b + 0.08, y0, y0 + GLAZE_H)
	return runs.size()


# --- The court's floor -----------------------------------------------------------------------
## The campus floor is the block's HIGHEST corner (Hospital.layout's floor_gy), and the canopy,
## the bays, their paint, the wheel stops and a backing ambulance all stand on it; but the court's
## asphalt was a relief-following ground slab, so on a sloping block (the medical centre falls 1.9 m
## to its ER street) everything on it floated over a court that sank away under it. The court (and
## the walk to the ER doors beside it) is now a level deck at the floor out to RAMP_FROM metres
## short of the block's edge, then a ramp down to the pavement there, with retaining kerb walls
## along its sides where it stands over the lawn.

## How far in from the block's edge (m along u) the ramp to the street starts.
const RAMP_FROM := 14.0
## Rows across the court (m) the deck is cut into, so the ramp follows the pavement's own height.
const ROW := 2.0


## The court's surface (true world y) at frame point (u, v), or NAN outside it.
static func court_y(ch_gy: Callable, lay: Dictionary, u: float, v: float) -> float:
	var court: Rect2 = lay.court
	var floor_y := float(lay.floor_gy) + CityChunk.SIDEWALK_TOP + HospitalBuild.LIFT_ROAD
	var W: float = lay.W
	var u0 := W - RAMP_FROM
	if u <= u0:
		return floor_y
	var edge := Hospital.fp(lay, W, clampf(v, court.position.y, court.end.y))
	var low := float(ch_gy.call(edge.x, edge.y)) + CityChunk.SIDEWALK_TOP + 0.02
	var t := clampf((u - u0) / RAMP_FROM, 0.0, 1.0)
	# Eased at both ends (a vertical curve), so neither break is a crease a car bumps over.
	t = t * t * (3.0 - 2.0 * t)
	return lerpf(floor_y, minf(low, floor_y), t)


## court_y() at a true world XZ point (the frame's u, v worked out from it).
static func court_y_world(ch_gy: Callable, lay: Dictionary, p: Vector2) -> float:
	var d := p - (lay.o as Vector2)
	return court_y(ch_gy, lay, d.dot(lay.a as Vector2), d.dot(lay.n as Vector2))


## The court and the walk beside it as one level deck with its ramp (FULL chunks), in place of the
## two ground slabs. `g` carries "h_court" (the asphalt) and "h_walk" (the paving).
static func court(ch: CityChunk, st: Dictionary, lay: Dictionary, asphalt: Material, paving: Material) -> void:
	# Its own mesh (and collision): the deck takes the floods' light on Compatibility, where a mesh
	# draws only its few nearest lights and the campus mesh has dozens round it.
	var g := LandmarkGeo.new()
	HospitalBuild._use(g, float(st.y0), int(lay.seed))
	g.use("h_court", asphalt)
	g.use("h_walk", paving)
	var court: Rect2 = lay.court
	var podium: Rect2 = lay.podium
	var W: float = lay.W
	var gy := func(x: float, z: float) -> float: return ch._gy(x, z)
	var u_cuts: Array[float] = [court.position.x]
	var n := 6
	for i in n + 1:
		u_cuts.append(W - RAMP_FROM + RAMP_FROM * float(i) / float(n))
	# The walk (paving, v from the podium's front edge to the court) and the court (asphalt).
	for part: Array in [["h_walk", podium.position.y, court.position.y], ["h_court", court.position.y, court.end.y]]:
		var key: String = part[0]
		var va: float = part[1]
		var vb: float = part[2]
		if vb - va < 0.1:
			continue
		var rows := maxi(1, ceili((vb - va) / ROW))
		for j in rows:
			var v0 := lerpf(va, vb, float(j) / float(rows))
			var v1 := lerpf(va, vb, float(j + 1) / float(rows))
			for i in u_cuts.size() - 1:
				var u0: float = u_cuts[i]
				var u1: float = u_cuts[i + 1]
				var p := [Vector2(u0, v0), Vector2(u1, v0), Vector2(u1, v1), Vector2(u0, v1)]
				var q: Array[Vector3] = []
				var uv: Array[Vector2] = []
				for c: Vector2 in p:
					var w := Hospital.fp(lay, c.x, c.y)
					q.append(Vector3(w.x, court_y(gy, lay, c.x, c.y), w.y))
					uv.append(Vector2((c.x - court.position.x) / (W - court.position.x), (c.y - va) / (vb - va)))
				g.quad(key, q[0], q[1], q[2], q[3], Vector3.UP, uv[0], uv[1], uv[2], uv[3], Color.WHITE, true)
	# Retaining kerb walls along both long sides, from the lawn up to the deck (and 15 cm over it).
	for v: float in [podium.position.y, court.end.y]:
		for i in u_cuts.size() - 1:
			var u0: float = u_cuts[i]
			var u1: float = u_cuts[i + 1]
			var a := Hospital.fp(lay, u0, v)
			var b := Hospital.fp(lay, u1, v)
			var ta := court_y(gy, lay, u0, v) + 0.15
			var tb := court_y(gy, lay, u1, v) + 0.15
			var ba := float(ch._gy(a.x, a.y)) + CityChunk.SIDEWALK_TOP - 0.05
			var bb := float(ch._gy(b.x, b.y)) + CityChunk.SIDEWALK_TOP - 0.05
			if ta - ba < 0.05 and tb - bb < 0.05:
				continue
			# Outward: away from the court's middle, along the frame's n.
			var sgn := signf(v - (podium.position.y + court.end.y) * 0.5)
			var out := Vector3((lay.n as Vector2).x, 0.0, (lay.n as Vector2).y) * sgn
			var o := out * 0.25
			g.quad("h_conc", Vector3(a.x, ba, a.y) + o, Vector3(b.x, bb, b.y) + o, Vector3(b.x, tb, b.y) + o, Vector3(a.x, ta, a.y) + o, out,
					Vector2(0.0, ba), Vector2(a.distance_to(b), bb), Vector2(a.distance_to(b), tb), Vector2(0.0, ta), Color(0.9, 0.89, 0.86), true)
			g.quad("h_conc", Vector3(a.x, ta, a.y), Vector3(b.x, tb, b.y), Vector3(b.x, tb, b.y) + o, Vector3(a.x, ta, a.y) + o, Vector3.UP,
					Vector2(0.0, 0.0), Vector2(a.distance_to(b), 0.0), Vector2(a.distance_to(b), 0.25), Vector2(0.0, 0.25), Color(0.9, 0.89, 0.86), true)
			g.quad("h_conc", Vector3(a.x, ta - 0.15, a.y), Vector3(b.x, tb - 0.15, b.y), Vector3(b.x, tb, b.y), Vector3(a.x, ta, a.y), -out,
					Vector2(0.0, 0.0), Vector2(a.distance_to(b), 0.0), Vector2(a.distance_to(b), 0.15), Vector2(0.0, 0.15), Color(0.9, 0.89, 0.86), true)
	g.commit(st.node, "ERCourt", false)
	g.commit_collision(st.statics)
	# Light pools down the ramp, each tilted to the slope under it (the floods' light on both
	# renderers; a flat pool would cut into the slope).
	var batch: MultiMeshBatch = st.batch
	for f: float in [0.3, 0.75]:
		var u := W - RAMP_FROM * (1.0 - f)
		for vf: float in [0.3, 0.7]:
			var v := lerpf(court.position.y, court.end.y, vf)
			var y0 := court_y(gy, lay, u - 1.5, v)
			var y1 := court_y(gy, lay, u + 1.5, v)
			var along := Vector3((lay.a as Vector2).x, 0.0, (lay.a as Vector2).y)
			var up := (Vector3.UP - along * ((y1 - y0) / 3.0)).normalized()
			var side := up.cross(along).normalized()
			var fwd := up.cross(side).normalized()
			var b := Basis(side * 12.0, fwd * 12.0, up)
			var c := Hospital.fp(lay, u, v)
			batch.add("h_pool", PropFactory.light_pool(Color(0.95, 0.97, 1.0), 0.4, 1.6), Transform3D(b, Vector3(c.x, court_y(gy, lay, u, v) + 0.05, c.y)))
