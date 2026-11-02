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

static var enabled := OS.get_environment("RC4_HOSPITAL") != "0"

## The light box (LINEAR, hospital_sign.gdshader): a dark red face glowing under 1 at night.
const BOX_FACE := Vector3(0.30, 0.012, 0.008)
const BOX_GLOW := Vector3(1.0, 0.035, 0.018)
const BOX_NIGHT := 0.78
const BOX_DAY := 0.12
## The soffit's glow (LINEAR) at night: the canopy underside washed by its own fixtures.
const SOFFIT_GLOW := Vector3(0.95, 0.96, 0.92)
const SOFFIT_NIGHT := 0.42
## The fascia's words (m).
const FASCIA_LETTER := 0.62
## The ER wall's glazing: height (m) over the court floor and the lit room's colour.
const GLAZE_H := 4.1


## The light box's material (cached by HospitalBuild.sign_material).
static func box_material() -> ShaderMaterial:
	return HospitalBuild.sign_material("er_box_rc4", BOX_FACE, BOX_GLOW, BOX_NIGHT, BOX_DAY, true)


## The canopy's lit underside, LED panels and the wash on the court. `y_court` is the court's
## surface, `y_soffit` the canopy's underside.
static func canopy(g: LandmarkGeo, lay: Dictionary, node: Node3D, batch: MultiMeshBatch, y_court: float, y_soffit: float) -> void:
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
	var out := HospitalBuild._p(lay, u1 + 4.0, (v0 + v1) * 0.5, y_court + 0.028)
	batch.add("h_pool", PropFactory.light_pool(Color(0.95, 0.97, 1.0), 0.55),
			Transform3D(Basis(Vector3.RIGHT, -PI * 0.5).scaled(Vector3(14.0, 1.0, 14.0)), out))


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
