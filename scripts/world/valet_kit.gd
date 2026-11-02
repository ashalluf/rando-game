class_name ValetKit
extends RefCounted
## The hardware of a valet stand (Valets), built in code at real size on the street vendors'
## shader (StreetVendors.material(): what a face is in the vertex alpha, paint from
## INSTANCE_CUSTOM.rgb), so every piece is one MultiMesh draw a chunk:
##
## * the PODIUM: a lectern on a steel plinth in the stand's paint, brass bands, a lit panel on
##   its road face with VALET and the (invented) operator's name, a sloped desk with the ticket
##   book and a gooseneck lamp that burns after dark;
## * the KEY BOX: a steel cabinet on a post, its door standing open on rows of hooks and tags;
## * the SIGN: an A-frame board at the kerb, VALET PARKING and the rate, both faces;
## * a CONE with its reflective collar, at each end of the zone;
## * the umbrella's weighted BASE (the canvas is StreetVendors.umbrella_mesh()).
##
## Frame: +z is the road (the podium's lettered face), x along the kerb, y up from the pavement.

## The operators (invented), one per stand by hash.
const OPERATORS := ["GOLDLINE VALET", "SILVER KEY", "CURBSIDE COURT", "BRASS & KEY", "ORCHID VALET"]
## The posted rates a sign can carry (dollars).
const RATES := [12, 15, 18, 20, 25, 32]
## Podium: half width, depth, desk height (m).
const PODIUM_W := 0.3
const PODIUM_D := 0.24
const PODIUM_H := 1.12

static var _meshes: Dictionary = {}


## The podium with operator `op`'s name on its face.
static func podium(op: int) -> Mesh:
	var key := "podium_%d" % op
	if _meshes.has(key):
		return _meshes[key]
	var st := StreetClutter._begin()
	var paint := Color(1, 1, 1, StreetVendors.A_PAINT)
	var dark := Color(0.06, 0.06, 0.065, StreetVendors.A_STEEL)
	var brass := Color(0.78, 0.6, 0.3, StreetVendors.A_STEEL)
	var rm_paint := Vector2(0.35, 0.0)
	var rm_metal := Vector2(0.32, 1.0)
	# Plinth and feet.
	StreetVendors._box(st, Vector3(0.0, 0.035, 0.0), Vector3(PODIUM_W * 2.0 + 0.1, 0.07, PODIUM_D * 2.0 + 0.1), 0.012, dark, Vector2(0.5, 0.8))
	# The body, a little narrower at the foot (a lectern's taper), as two stacked boxes.
	StreetVendors._box(st, Vector3(0.0, 0.07 + 0.2, 0.0), Vector3(PODIUM_W * 2.0 - 0.04, 0.4, PODIUM_D * 2.0 - 0.04), 0.01, paint, rm_paint)
	StreetVendors._box(st, Vector3(0.0, 0.47 + (PODIUM_H - 0.55) * 0.5, 0.0), Vector3(PODIUM_W * 2.0, PODIUM_H - 0.55, PODIUM_D * 2.0), 0.012, paint, rm_paint)
	# Brass bands round the waist and under the desk.
	for y: float in [0.47, PODIUM_H - 0.1]:
		StreetVendors._box(st, Vector3(0.0, y, 0.0), Vector3(PODIUM_W * 2.0 + 0.012, 0.025, PODIUM_D * 2.0 + 0.012), 0.004, brass, rm_metal)
	# The sloped desk: high at the road face, falling toward the valet behind it.
	var desk := Transform3D(Basis(Vector3.RIGHT, -0.2), Vector3(0.0, PODIUM_H - 0.02, -0.02))
	StreetVendors._xbox(st, desk, Vector3(PODIUM_W * 2.0 + 0.08, 0.035, PODIUM_D * 2.0 + 0.1), 0.008, Color(0.16, 0.1, 0.06, StreetVendors.A_FIXED), Vector2(0.4, 0.0))
	# A ticket book and claim checks on it, a pen.
	StreetVendors._xbox(st, desk * Transform3D(Basis(), Vector3(-0.08, 0.03, 0.0)), Vector3(0.2, 0.025, 0.14), 0.003, Color(0.93, 0.9, 0.82, StreetVendors.A_FIXED), Vector2(0.8, 0.0))
	StreetVendors._xbox(st, desk * Transform3D(Basis(), Vector3(-0.08, 0.044, -0.01)), Vector3(0.17, 0.003, 0.11), 0.0, Color(0.85, 0.2, 0.15, StreetVendors.A_FIXED), Vector2(0.8, 0.0))
	StreetClutter._tube(st, [desk * Vector3(0.1, 0.03, 0.06), desk * Vector3(0.22, 0.03, -0.02)], 0.005, 5, Color(0.05, 0.05, 0.08, StreetVendors.A_FIXED), Vector2(0.3, 0.0))
	# The gooseneck lamp at the back corner and its shade, the bulb lit after dark.
	var lamp_foot := desk * Vector3(0.24, 0.02, -0.18)
	var lamp_head := lamp_foot + Vector3(-0.08, 0.3, 0.12)
	StreetClutter._tube(st, [lamp_foot, lamp_foot + Vector3(0.0, 0.18, 0.0), lamp_head], 0.008, 6, brass, rm_metal)
	StreetClutter._cyl(st, Transform3D(Basis(Vector3.RIGHT, 0.5), lamp_head + Vector3(0.0, -0.04, 0.0)), 0.07, 0.03, 0.08, Color(0.08, 0.2, 0.12, StreetVendors.A_STEEL), Vector2(0.3, 0.6), 12)
	StreetVendors._sphere(st, lamp_head + Vector3(0.0, -0.05, 0.02), 0.022, Color(1.0, 0.86, 0.6, StreetVendors.A_BULB), Vector2(0.2, 0.0), 6)
	# The lit panel on the road face and its lettering.
	var face_z := PODIUM_D + 0.004
	var panel_c := Vector3(0.0, 0.79, face_z)
	StreetClutter._quad(st, panel_c + Vector3(-0.24, -0.16, 0.0), panel_c + Vector3(0.24, -0.16, 0.0), panel_c + Vector3(0.24, 0.16, 0.0), panel_c + Vector3(-0.24, 0.16, 0.0),
		Vector3.BACK, Color(0.97, 0.9, 0.72, StreetVendors.A_GLOW), Vector2(0.35, 0.0))
	StreetVendors._box(st, panel_c + Vector3(0.0, 0.0, -0.006), Vector3(0.5, 0.34, 0.012), 0.002, brass, rm_metal)
	StreetVendors._text(st, "VALET", 0.11, Transform3D(Basis(), panel_c + Vector3(0.0, 0.045, 0.002)), Color(0.08, 0.06, 0.05, StreetVendors.A_FIXED), 0.42)
	StreetVendors._text(st, OPERATORS[op % OPERATORS.size()], 0.042, Transform3D(Basis(), panel_c + Vector3(0.0, -0.085, 0.002)), Color(0.45, 0.12, 0.08, StreetVendors.A_FIXED), 0.42)
	# A brass kick plate at the foot of the road face.
	StreetVendors._box(st, Vector3(0.0, 0.16, PODIUM_D - 0.012), Vector3(PODIUM_W * 2.0 - 0.06, 0.16, 0.012), 0.002, brass, rm_metal)
	return _finish(st, key)


## The key cabinet on its post, its door standing open on the hooks.
static func key_box() -> Mesh:
	if _meshes.has("key_box"):
		return _meshes["key_box"]
	var st := StreetClutter._begin()
	var steel := Color(0.12, 0.13, 0.14, StreetVendors.A_STEEL)
	var rm := Vector2(0.45, 0.85)
	StreetVendors._box(st, Vector3(0.0, 0.02, 0.0), Vector3(0.3, 0.04, 0.3), 0.01, steel, rm)
	StreetClutter._cyl(st, Transform3D(Basis(), Vector3(0.0, 0.04, 0.0)), 0.035, 0.035, 1.05, Color(0.5, 0.51, 0.53, StreetVendors.A_STEEL), Vector2(0.35, 1.0), 10)
	# The cabinet: back, sides, top and bottom (open at the front, +z).
	var c := Vector3(0.0, 1.32, 0.0)
	var w := 0.44
	var h := 0.58
	var d := 0.12
	var paint := Color(1, 1, 1, StreetVendors.A_PAINT)
	StreetVendors._box(st, c + Vector3(0.0, 0.0, -d * 0.5 + 0.008), Vector3(w, h, 0.016), 0.0, paint, Vector2(0.4, 0.2))
	for s: float in [-1.0, 1.0]:
		StreetVendors._box(st, c + Vector3(s * (w * 0.5 - 0.008), 0.0, 0.0), Vector3(0.016, h, d), 0.0, paint, Vector2(0.4, 0.2))
		StreetVendors._box(st, c + Vector3(0.0, s * (h * 0.5 - 0.008), 0.0), Vector3(w, 0.016, d), 0.0, paint, Vector2(0.4, 0.2))
	# Rows of hooks with keys and coloured tags.
	var tags := [Color(0.85, 0.15, 0.1), Color(0.95, 0.8, 0.2), Color(0.15, 0.4, 0.8), Color(0.2, 0.6, 0.3), Color(0.95, 0.95, 0.92)]
	for row in 4:
		for col in 6:
			if (row * 7 + col * 3) % 5 == 1:
				continue
			var hp := c + Vector3(-w * 0.5 + 0.06 + col * 0.064, h * 0.5 - 0.1 - row * 0.12, -d * 0.5 + 0.03)
			StreetClutter._tube(st, [hp, hp + Vector3(0.0, 0.0, 0.03)], 0.003, 4, Color(0.7, 0.7, 0.72, StreetVendors.A_STEEL), Vector2(0.3, 1.0))
			StreetVendors._box(st, hp + Vector3(0.0, -0.03, 0.028), Vector3(0.012, 0.035, 0.004), 0.0, Color(0.55, 0.56, 0.6, StreetVendors.A_STEEL), Vector2(0.3, 1.0))
			var tc: Color = tags[(row + col * 2) % tags.size()]
			StreetVendors._box(st, hp + Vector3(0.0, -0.065, 0.03), Vector3(0.03, 0.04, 0.003), 0.0, Color(tc.r, tc.g, tc.b, StreetVendors.A_FIXED), Vector2(0.7, 0.0))
	# The door, hinged at the cabinet's left front edge, swung open past square.
	var hinge := c + Vector3(-w * 0.5, 0.0, d * 0.5)
	var door := Transform3D(Basis(Vector3.UP, -1.9), hinge) * Transform3D(Basis(), Vector3(w * 0.5, 0.0, 0.008))
	StreetVendors._xbox(st, door, Vector3(w, h, 0.016), 0.003, paint, Vector2(0.4, 0.2))
	StreetVendors._xbox(st, door * Transform3D(Basis(), Vector3(w * 0.38, 0.0, -0.02)), Vector3(0.02, 0.1, 0.02), 0.003, Color(0.75, 0.75, 0.78, StreetVendors.A_STEEL), Vector2(0.25, 1.0))
	return _finish(st, "key_box")


## The A-frame sign with rate `rate` (an index of RATES).
static func sign(rate: int) -> Mesh:
	var key := "sign_%d" % rate
	if _meshes.has(key):
		return _meshes[key]
	var st := StreetClutter._begin()
	var board_w := 0.62
	var board_h := 1.02
	var lean := 0.16
	for side: float in [1.0, -1.0]:
		# Each board leans in to meet the other at the top; its face looks out along +-z.
		var b := Basis(Vector3.RIGHT, -lean * side)
		var xf := Transform3D(b, Vector3(0.0, board_h * 0.5 * cos(lean), side * board_h * 0.5 * sin(lean)))
		StreetVendors._xbox(st, xf, Vector3(board_w, board_h, 0.022), 0.006, Color(0.05, 0.05, 0.055, StreetVendors.A_FIXED), Vector2(0.55, 0.0))
		var face := Transform3D(b if side > 0.0 else b * Basis(Vector3.UP, PI), xf.origin + b.z * side * 0.0125)
		StreetClutter._quad(st, face * Vector3(-0.27, -0.42, 0.0), face * Vector3(0.27, -0.42, 0.0), face * Vector3(0.27, 0.42, 0.0), face * Vector3(-0.27, 0.42, 0.0),
			face.basis.z, Color(0.94, 0.92, 0.86, StreetVendors.A_FIXED), Vector2(0.6, 0.0))
		var ink := Color(0.06, 0.06, 0.07, StreetVendors.A_FIXED)
		var red := Color(0.62, 0.08, 0.07, StreetVendors.A_FIXED)
		StreetVendors._text(st, "VALET", 0.13, face * Transform3D(Basis(), Vector3(0.0, 0.26, 0.003)), ink, 0.5)
		StreetVendors._text(st, "PARKING", 0.075, face * Transform3D(Basis(), Vector3(0.0, 0.11, 0.003)), ink, 0.5)
		StreetVendors._text(st, "$%d" % RATES[rate % RATES.size()], 0.15, face * Transform3D(Basis(), Vector3(0.0, -0.1, 0.003)), red, 0.5)
		StreetVendors._text(st, "CASH OR CARD", 0.035, face * Transform3D(Basis(), Vector3(0.0, -0.3, 0.003)), ink, 0.5)
	# The hinge rod across the top and the spreader chains.
	StreetClutter._tube(st, [Vector3(-board_w * 0.5, board_h * cos(lean) - 0.02, 0.0), Vector3(board_w * 0.5, board_h * cos(lean) - 0.02, 0.0)], 0.01, 6, Color(0.6, 0.6, 0.62, StreetVendors.A_STEEL), Vector2(0.3, 1.0))
	for s: float in [-1.0, 1.0]:
		var y := 0.35
		StreetClutter._tube(st, [Vector3(s * 0.26, y, -(board_h * 0.5 - y) * tan(lean) - 0.12), Vector3(s * 0.26, y, (board_h * 0.5 - y) * tan(lean) + 0.12)], 0.003, 3, Color(0.6, 0.6, 0.62, StreetVendors.A_STEEL), Vector2(0.3, 1.0))
	return _finish(st, key)


## A traffic cone with its reflective collar.
static func cone() -> Mesh:
	if _meshes.has("cone"):
		return _meshes["cone"]
	var st := StreetClutter._begin()
	var orange := Color(0.95, 0.32, 0.06, StreetVendors.A_FIXED)
	StreetVendors._box(st, Vector3(0.0, 0.015, 0.0), Vector3(0.36, 0.03, 0.36), 0.03, Color(0.08, 0.08, 0.08, StreetVendors.A_FIXED), Vector2(0.8, 0.0))
	StreetClutter._cyl(st, Transform3D(Basis(), Vector3(0.0, 0.03, 0.0)), 0.13, 0.085, 0.28, orange, Vector2(0.55, 0.0), 14)
	StreetClutter._cyl(st, Transform3D(Basis(), Vector3(0.0, 0.31, 0.0)), 0.086, 0.06, 0.14, Color(0.95, 0.95, 0.93, StreetVendors.A_GLASS), Vector2(0.15, 0.0), 14)
	StreetClutter._cyl(st, Transform3D(Basis(), Vector3(0.0, 0.45, 0.0)), 0.061, 0.022, 0.26, orange, Vector2(0.55, 0.0), 14)
	return _finish(st, "cone")


## The umbrella's weighted base: a cast disc with the pole's socket.
static func umbrella_base() -> Mesh:
	if _meshes.has("base"):
		return _meshes["base"]
	var st := StreetClutter._begin()
	var iron := Color(0.1, 0.1, 0.11, StreetVendors.A_STEEL)
	StreetClutter._cyl(st, Transform3D(), 0.3, 0.27, 0.07, iron, Vector2(0.55, 0.7), 18)
	StreetClutter._cyl(st, Transform3D(Basis(), Vector3(0.0, 0.07, 0.0)), 0.07, 0.04, 0.1, iron, Vector2(0.45, 0.7), 12)
	StreetClutter._cyl(st, Transform3D(Basis(), Vector3(0.0, 0.17, 0.0)), 0.032, 0.032, 0.3, Color(0.55, 0.56, 0.58, StreetVendors.A_STEEL), Vector2(0.3, 1.0), 8)
	return _finish(st, "base")


static func _finish(st: SurfaceTool, key: String) -> Mesh:
	st.generate_tangents()
	var mesh := st.commit()
	mesh.surface_set_material(0, StreetVendors.material())
	_meshes[key] = mesh
	return mesh


## Builds every mesh once (the loading screen).
static func warm() -> void:
	for i in OPERATORS.size():
		podium(i)
	for i in RATES.size():
		sign(i)
	key_box()
	cone()
	umbrella_base()
