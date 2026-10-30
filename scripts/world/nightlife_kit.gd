class_name NightLifeKit
extends RefCounted
## The hardware of the city's night life (NightLife), built here in code at real size on one
## shader (shaders/nightlife.gdshader): a club's cantilevered entrance canopy with its lit fascia,
## downlights and LED edge, the portal round its door and the black runner out of it; a bar's
## projecting lightbox and its wall sconces; the line's brass stanchions and sagging velvet rope;
## a premiere's red carpet with its gold stanchions and the galvanised crowd barriers either side;
## and the searchlight cart (a trailer chassis with its generator, the turntable, the yoke and the
## drum with its lens). Every mesh is one surface in StreetClutter's vertex format (colour alpha =
## what the face is, UV in metres, UV2 = roughness and metallic), so a chunk's night life is a
## handful of MultiMesh draws.
##
## Frames. An entrance, a rope line, a carpet: origin on the pavement at the foot of the wall in
## the middle of the door, +x along the wall, +z out toward the kerb, y up. A searchlight cart:
## origin on the ground under its turntable, the drawbar toward -z. The yoke turns about y over
## the turntable (YOKE_Y up); the drum about x at the trunnions (TRUNNION_Y over the yoke's foot),
## its lens toward -z (a SpotLight3D's way).

# Vertex colour alpha codes, read by shaders/nightlife.gdshader (round(a * 20)).
const A_METAL := 0.05
const A_VELVET := 0.1
const A_CANOPY := 0.15
const A_LED := 0.2
const A_DOWN := 0.25
const A_CARPET := 0.3
const A_RUBBER := 0.35
const A_PAINT := 0.4
const A_LENS := 0.45
const A_BOX := 0.5
const A_GALV := 0.55

## The club canopy: its width along the wall, depth out over the pavement, underside height.
const CANOPY_W := 3.6
const CANOPY_D := 2.5
const CANOPY_Y := 3.05
const CANOPY_T := 0.34
## The runner out of a club's door: width and how far out it reaches.
const RUNNER_W := 1.5
const RUNNER_L := 2.3
## Stanchions: spacing along the line, how far out from the wall the rope runs, post height.
const POST_PITCH := 1.75
const ROPE_OUT := 1.55
const POST_H := 0.96
## Where the first post of a line stands along the wall from the door's middle (the bouncer
## works the gap between it and the door).
const FIRST_POST := 1.0
## A searchlight cart: the turntable's top, the trunnions over it, the drum's radius.
const YOKE_Y := 1.18
const TRUNNION_Y := 0.78
const DRUM_R := 0.46
const DRUM_L := 1.05
## Galvanised crowd barrier panel length and height.
const BARRIER_L := 2.3
const BARRIER_H := 1.1
## LED colours for the club fronts (sRGB, picked per venue by NightLife).
const LED_COLORS := [Color(1.0, 0.72, 0.38), Color(1.0, 0.25, 0.75), Color(0.3, 0.8, 1.0), Color(0.75, 0.4, 1.0)]

const BRASS := Color(0.82, 0.64, 0.34, A_METAL)
const CHROME := Color(0.86, 0.87, 0.9, A_METAL)
const BLACK := Color(0.03, 0.03, 0.035, A_RUBBER)
const GALV := Color(0.62, 0.64, 0.66, A_GALV)
const STEEL := Color(0.08, 0.08, 0.085, A_RUBBER)
const ACCENT := Color(1, 1, 1, A_PAINT)

static var _meshes: Dictionary = {}
static var _material: ShaderMaterial
static var _solo: ShaderMaterial
static var _sign_material: ShaderMaterial


static func material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = load("res://shaders/nightlife.gdshader")
	return _material


## The material for a mesh drawn alone (the searchlight's yoke and drum): always lit, dark paint.
static func solo_material() -> ShaderMaterial:
	if _solo == null:
		_solo = material().duplicate() as ShaderMaterial
		_solo.set_shader_parameter("solo_lit", 1.0)
		_solo.set_shader_parameter("solo_paint", Vector3(0.13, 0.13, 0.14))
	return _solo


## The lettering's material: the venue's colour, glowing after dark (shaders/nightlife_sign).
static func sign_material(tint: Color) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/nightlife_sign.gdshader")
	mat.set_shader_parameter("tint", Vector3(tint.r, tint.g, tint.b))
	return mat


static func _finish(st: SurfaceTool, key: String) -> Mesh:
	st.generate_tangents()
	var mesh := st.commit()
	mesh.surface_set_material(0, material())
	_meshes[key] = mesh
	return mesh


static func _box(st: SurfaceTool, c: Vector3, size: Vector3, col: Color, rm: Vector2, bevel: float = 0.0) -> void:
	StreetClutter._bbox(st, Transform3D(Basis(), c), size, bevel, col, rm)


static func _disc(st: SurfaceTool, c: Vector3, r: float, h: float, col: Color, rm: Vector2, sides: int = 12) -> void:
	StreetClutter._cyl(st, Transform3D(Basis(), c), r, r, h, col, rm, sides)


## A stanchion standing at `p` (its foot): a weighted base, a polished post, a ball top.
static func _stanchion(st: SurfaceTool, p: Vector3, metal: Color) -> void:
	var rm := Vector2(0.2, 1.0)
	StreetClutter._cyl(st, Transform3D(Basis(), p), 0.17, 0.15, 0.035, metal, rm, 16)
	StreetClutter._cyl(st, Transform3D(Basis(), p + Vector3(0.0, 0.035, 0.0)), 0.05, 0.026, 0.05, metal, rm, 12)
	StreetClutter._cyl(st, Transform3D(Basis(), p + Vector3(0.0, 0.08, 0.0)), 0.026, 0.024, POST_H - 0.12, metal, rm, 10)
	StreetClutter._cyl(st, Transform3D(Basis(), p + Vector3(0.0, POST_H - 0.05, 0.0)), 0.034, 0.042, 0.03, metal, rm, 10)
	StreetClutter._cyl(st, Transform3D(Basis(), p + Vector3(0.0, POST_H - 0.02, 0.0)), 0.042, 0.012, 0.06, metal, rm, 10)


## A velvet rope from post top `a` to `b`, hooked on, sagging a fifth of a metre.
static func _rope(st: SurfaceTool, a: Vector3, b: Vector3, sag: float) -> void:
	var path: Array = []
	var n := 10
	for i in n + 1:
		var f := float(i) / n
		path.append(a.lerp(b, f) - Vector3(0.0, 4.0 * sag * f * (1.0 - f), 0.0))
	StreetClutter._tube(st, path, 0.022, 8, Color(1, 1, 1, A_VELVET), Vector2(0.92, 0.0))
	# The brass snap hooks at both ends.
	for p: Vector3 in [a, b]:
		StreetClutter._cyl(st, Transform3D(Basis(), p - Vector3(0.0, 0.04, 0.0)), 0.026, 0.026, 0.05, BRASS, Vector2(0.2, 1.0), 8)


## A club's entrance: the canopy (cantilevered off the wall on two chrome tie rods), its fascia
## and LED edge in colour `led` (an index into LED_COLORS), the downlights in its soffit, a portal
## round the door with an LED reveal, and the black runner out of it. The canopy and the portal
## take the instance's accent; the runner is black.
static func club_entrance(led: int) -> Mesh:
	var key := "club_%d" % led
	if _meshes.has(key):
		return _meshes[key]
	var st := StreetClutter._begin()
	var lc: Color = LED_COLORS[led % LED_COLORS.size()]
	var led_col := Color(lc.r, lc.g, lc.b, A_LED)
	var hw := CANOPY_W * 0.5
	var y0 := CANOPY_Y
	var canopy := Color(1, 1, 1, A_CANOPY)
	var crm := Vector2(0.55, 0.35)
	# The slab: top, soffit, fascia front and returns (a box), the soffit stepped up inside the
	# fascia so the downlights sit in a recess.
	_box(st, Vector3(0.0, y0 + CANOPY_T - 0.04, CANOPY_D * 0.5), Vector3(CANOPY_W, 0.08, CANOPY_D), canopy, crm, 0.01)
	_box(st, Vector3(0.0, y0 + CANOPY_T * 0.5, CANOPY_D - 0.05), Vector3(CANOPY_W, CANOPY_T, 0.1), canopy, crm, 0.01)
	for s: float in [-1.0, 1.0]:
		_box(st, Vector3(s * (hw - 0.05), y0 + CANOPY_T * 0.5, CANOPY_D * 0.5), Vector3(0.1, CANOPY_T, CANOPY_D), canopy, crm, 0.01)
	StreetClutter._quad(st, Vector3(-hw + 0.1, y0 + 0.12, 0.02), Vector3(hw - 0.1, y0 + 0.12, 0.02),
		Vector3(hw - 0.1, y0 + 0.12, CANOPY_D - 0.1), Vector3(-hw + 0.1, y0 + 0.12, CANOPY_D - 0.1), Vector3.DOWN, BLACK, Vector2(0.6, 0.0))
	# The LED strip under the fascia's lower edge, all the way round the three open sides.
	_box(st, Vector3(0.0, y0 - 0.012, CANOPY_D - 0.05), Vector3(CANOPY_W, 0.024, 0.04), led_col, Vector2(0.3, 0.0))
	for s: float in [-1.0, 1.0]:
		_box(st, Vector3(s * (hw - 0.05), y0 - 0.012, CANOPY_D * 0.5), Vector3(0.04, 0.024, CANOPY_D), led_col, Vector2(0.3, 0.0))
	# Two rows of three downlights in the soffit.
	for row in 2:
		for col in 3:
			var p := Vector3((float(col) - 1.0) * 1.05, y0 + 0.1, 0.75 + float(row) * 1.0)
			_disc(st, p, 0.075, 0.02, CHROME, Vector2(0.25, 1.0), 12)
			StreetClutter._quad(st, p + Vector3(-0.045, -0.002, -0.045), p + Vector3(0.045, -0.002, -0.045),
				p + Vector3(0.045, -0.002, 0.045), p + Vector3(-0.045, -0.002, 0.045), Vector3.DOWN, Color(1, 1, 1, A_DOWN), Vector2(0.2, 0.0))
	# The tie rods up to the wall, with their plates.
	for s: float in [-1.0, 1.0]:
		var a := Vector3(s * (hw - 0.25), y0 + CANOPY_T, CANOPY_D - 0.3)
		var b := Vector3(s * (hw - 0.25), y0 + 1.55, 0.02)
		StreetClutter._tube(st, [a, b], 0.018, 8, CHROME, Vector2(0.2, 1.0))
		_box(st, b + Vector3(0.0, 0.0, -0.005), Vector3(0.16, 0.16, 0.02), CHROME, Vector2(0.25, 1.0))
	# The portal round the door: jambs and head proud of the wall, an LED reveal inside them.
	var dw := 1.1
	var dh := 2.75
	for s: float in [-1.0, 1.0]:
		_box(st, Vector3(s * (dw + 0.11), dh * 0.5, 0.06), Vector3(0.22, dh, 0.12), canopy, crm, 0.008)
		_box(st, Vector3(s * (dw - 0.005), dh * 0.5, 0.03), Vector3(0.02, dh - 0.05, 0.05), led_col, Vector2(0.3, 0.0))
	_box(st, Vector3(0.0, dh + 0.11, 0.06), Vector3(dw * 2.0 + 0.44, 0.22, 0.12), canopy, crm, 0.008)
	_box(st, Vector3(0.0, dh - 0.015, 0.03), Vector3(dw * 2.0, 0.02, 0.05), led_col, Vector2(0.3, 0.0))
	# The runner: black carpet with a brushed metal nosing at its street end.
	var rh := RUNNER_W * 0.5
	var ry := 0.012
	StreetClutter._quad(st, Vector3(-rh, ry, 0.02), Vector3(rh, ry, 0.02), Vector3(rh, ry, RUNNER_L), Vector3(-rh, ry, RUNNER_L), Vector3.UP, Color(0.03, 0.03, 0.035, A_CARPET), Vector2(0.95, 0.0))
	_box(st, Vector3(0.0, ry * 0.5, RUNNER_L), Vector3(RUNNER_W + 0.02, ry + 0.004, 0.035), CHROME, Vector2(0.3, 1.0))
	return _finish(st, key)


## A bar's front: a lightbox projecting from the wall over the door on a steel bracket (its two
## faces glow in the accent), and a sconce either side of the door.
static func bar_entrance() -> Mesh:
	var key := "bar"
	if _meshes.has(key):
		return _meshes[key]
	var st := StreetClutter._begin()
	var rm := Vector2(0.5, 0.4)
	var bx := 1.35
	var by := 3.55
	var bz := 0.95
	# Bracket arms off the wall.
	for y: float in [by + 0.5, by - 0.48]:
		_box(st, Vector3(bx, y, 0.42), Vector3(0.05, 0.05, 0.84), STEEL, rm)
	_box(st, Vector3(bx, by, 0.02), Vector3(0.18, 1.2, 0.04), STEEL, rm)
	# The box: a frame in the canopy paint, two glowing faces (+x and -x).
	var w := 1.0
	var h := 0.9
	var t := 0.24
	_box(st, Vector3(bx, by, bz), Vector3(t, h, w), Color(1, 1, 1, A_CANOPY), Vector2(0.5, 0.3), 0.02)
	for s: float in [-1.0, 1.0]:
		var x := bx + s * (t * 0.5 + 0.004)
		StreetClutter._quad(st, Vector3(x, by - h * 0.5 + 0.07, bz - w * 0.5 + 0.07), Vector3(x, by - h * 0.5 + 0.07, bz + w * 0.5 - 0.07),
			Vector3(x, by + h * 0.5 - 0.07, bz + w * 0.5 - 0.07), Vector3(x, by + h * 0.5 - 0.07, bz - w * 0.5 + 0.07), Vector3(s, 0.0, 0.0), Color(1, 1, 1, A_BOX), Vector2(0.3, 0.0))
	# Sconces either side of the door: a backplate, an arm and a shade with its lamp under it.
	for s: float in [-1.0, 1.0]:
		var c := Vector3(s * 1.05, 2.45, 0.0)
		_box(st, c + Vector3(0.0, 0.0, 0.01), Vector3(0.12, 0.2, 0.02), BRASS, Vector2(0.3, 1.0))
		StreetClutter._tube(st, [c + Vector3(0.0, 0.0, 0.02), c + Vector3(0.0, 0.08, 0.2)], 0.012, 6, BRASS, Vector2(0.3, 1.0))
		StreetClutter._cyl(st, Transform3D(Basis(), c + Vector3(0.0, 0.0, 0.2)), 0.11, 0.05, 0.14, BLACK, Vector2(0.5, 0.0), 12)
		StreetClutter._quad(st, c + Vector3(-0.06, -0.002, 0.14), c + Vector3(0.06, -0.002, 0.14), c + Vector3(0.06, -0.002, 0.26), c + Vector3(-0.06, -0.002, 0.26), Vector3.DOWN, Color(1, 1, 1, A_DOWN), Vector2(0.2, 0.0))
	return _finish(st, key)


## The line's stanchions and velvet rope: `posts` posts from FIRST_POST along +x (or -x, `side`
## -1) at ROPE_OUT from the wall, a rope between each pair. The rope takes the accent.
static func rope_line(posts: int, side: int, metal: int) -> Mesh:
	var key := "rope_%d_%d_%d" % [posts, side, metal]
	if _meshes.has(key):
		return _meshes[key]
	var st := StreetClutter._begin()
	var m: Color = BRASS if metal == 0 else CHROME
	var tops: Array = []
	for i in posts:
		var p := Vector3(float(side) * (FIRST_POST + float(i) * POST_PITCH), 0.0, ROPE_OUT)
		_stanchion(st, p, m)
		tops.append(p + Vector3(0.0, POST_H - 0.06, 0.0))
	for i in posts - 1:
		_rope(st, tops[i], tops[i + 1], 0.2)
	return _finish(st, key)


## A premiere's red carpet out of a palace's door to the kerb, `length` long, `width` wide, with
## gold stanchions and rope down both edges (a gap at the kerb), and a row of galvanised crowd
## barriers behind each rope where the fans stand. The carpet and the rope take the accent.
static func premiere(length: float, width: float) -> Mesh:
	var key := "premiere_%d_%d" % [int(length * 10.0), int(width * 10.0)]
	if _meshes.has(key):
		return _meshes[key]
	var st := StreetClutter._begin()
	var hw := width * 0.5
	var y := 0.014
	StreetClutter._quad(st, Vector3(-hw, y, 0.0), Vector3(hw, y, 0.0), Vector3(hw, y, length), Vector3(-hw, y, length), Vector3.UP, Color(1, 1, 1, A_CARPET), Vector2(0.95, 0.0))
	for s: float in [-1.0, 1.0]:
		_box(st, Vector3(s * (hw + 0.01), y * 0.5, length * 0.5), Vector3(0.03, y + 0.004, length), BRASS, Vector2(0.3, 1.0))
	var posts := maxi(2, int(floor((length - 1.2) / POST_PITCH)) + 1)
	for s: float in [-1.0, 1.0]:
		var tops: Array = []
		for i in posts:
			var p := Vector3(s * (hw + 0.35), 0.0, 0.6 + float(i) * (length - 1.6) / float(posts - 1))
			_stanchion(st, p, BRASS)
			tops.append(p + Vector3(0.0, POST_H - 0.06, 0.0))
		for i in posts - 1:
			_rope(st, tops[i], tops[i + 1], 0.16)
		# The crowd barriers, end to end behind the rope.
		var panels := maxi(1, int(floor((length - 0.8) / BARRIER_L)))
		for i in panels:
			_barrier(st, Vector3(s * (hw + 1.45), 0.0, 0.5 + (float(i) + 0.5) * BARRIER_L))
	return _finish(st, key)


## One bike-rack crowd barrier, its length along z, standing at `c` (its foot's middle).
static func _barrier(st: SurfaceTool, c: Vector3) -> void:
	var hl := BARRIER_L * 0.5 - 0.04
	var rm := Vector2(0.45, 0.8)
	# Top and bottom rails, the end posts with their flat feet, bars between.
	StreetClutter._tube(st, [c + Vector3(0.0, BARRIER_H, -hl), c + Vector3(0.0, BARRIER_H, hl)], 0.02, 6, GALV, rm)
	StreetClutter._tube(st, [c + Vector3(0.0, 0.22, -hl), c + Vector3(0.0, 0.22, hl)], 0.02, 6, GALV, rm)
	for s: float in [-1.0, 1.0]:
		StreetClutter._tube(st, [c + Vector3(0.0, 0.0, s * hl), c + Vector3(0.0, BARRIER_H, s * hl)], 0.02, 6, GALV, rm)
		_box(st, c + Vector3(0.0, 0.01, s * hl), Vector3(0.6, 0.02, 0.05), GALV, rm)
	var bars := 13
	for i in bars:
		var z := -hl + (float(i) + 1.0) * (2.0 * hl) / float(bars + 1)
		_box(st, c + Vector3(0.0, (BARRIER_H + 0.22) * 0.5, z), Vector3(0.016, BARRIER_H - 0.22, 0.016), GALV, rm)


## The searchlight's cart: a two-axle trailer chassis on four wheels with a drawbar, the
## generator housing in the instance's paint at the drawbar end, the turntable under the yoke.
static func searchlight_cart() -> Mesh:
	var key := "cart"
	if _meshes.has(key):
		return _meshes[key]
	var st := StreetClutter._begin()
	var rm := Vector2(0.5, 0.5)
	# Chassis rails and deck.
	_box(st, Vector3(0.0, 0.5, 0.15), Vector3(1.25, 0.08, 2.2), GALV, rm, 0.01)
	for s: float in [-1.0, 1.0]:
		_box(st, Vector3(s * 0.58, 0.42, 0.15), Vector3(0.08, 0.14, 2.3), STEEL, rm)
	# Wheels on two axles, mudguards over them.
	for zz: float in [-0.55, 0.85]:
		for s: float in [-1.0, 1.0]:
			var wheel := Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(s * 0.62, 0.3, zz))
			StreetClutter._cyl(st, wheel.translated_local(Vector3(0.0, -0.09, 0.0)), 0.3, 0.3, 0.18, Color(0.04, 0.04, 0.04, A_RUBBER), Vector2(0.85, 0.0), 14)
			StreetClutter._cyl(st, wheel.translated_local(Vector3(0.0, -0.095 * s, 0.0)), 0.16, 0.16, 0.19, GALV, rm, 10)
			_box(st, Vector3(s * 0.62, 0.66, zz), Vector3(0.24, 0.03, 0.7), STEEL, rm, 0.01)
	# The drawbar and its jack.
	StreetClutter._tube(st, [Vector3(-0.5, 0.45, -0.9), Vector3(0.0, 0.42, -1.65), Vector3(0.5, 0.45, -0.9)], 0.04, 6, STEEL, rm)
	StreetClutter._cyl(st, Transform3D(Basis(), Vector3(0.0, 0.0, -1.55)), 0.035, 0.035, 0.45, GALV, rm, 8)
	_box(st, Vector3(0.0, 0.02, -1.55), Vector3(0.18, 0.04, 0.18), STEEL, rm)
	# The generator housing, with louvres.
	_box(st, Vector3(0.0, 0.88, -0.62), Vector3(1.1, 0.68, 0.8), ACCENT, Vector2(0.45, 0.4), 0.03)
	for i in 6:
		_box(st, Vector3(0.556, 0.68 + float(i) * 0.075, -0.62), Vector3(0.012, 0.025, 0.55), STEEL, rm)
		_box(st, Vector3(-0.556, 0.68 + float(i) * 0.075, -0.62), Vector3(0.012, 0.025, 0.55), STEEL, rm)
	# The turntable and its base.
	_box(st, Vector3(0.0, 0.7, 0.35), Vector3(0.9, 0.36, 0.9), ACCENT, Vector2(0.45, 0.4), 0.03)
	StreetClutter._cyl(st, Transform3D(Basis(), Vector3(0.0, 0.88, 0.35)), 0.44, 0.4, YOKE_Y - 0.88, GALV, rm, 20)
	return _finish(st, key)


## The yoke: a fork off the turntable carrying the drum's trunnions at TRUNNION_Y. Origin at the
## turntable's top (the cart's (0, YOKE_Y, 0.35)).
static func searchlight_yoke() -> Mesh:
	var key := "yoke"
	if _meshes.has(key):
		return _meshes[key]
	var st := StreetClutter._begin()
	var col := Color(1, 1, 1, A_PAINT)
	var rm := Vector2(0.45, 0.4)
	StreetClutter._cyl(st, Transform3D(Basis(), Vector3.ZERO), 0.38, 0.36, 0.08, col, rm, 20)
	_box(st, Vector3(0.0, 0.12, 0.0), Vector3(1.3, 0.1, 0.24), col, rm, 0.02)
	for s: float in [-1.0, 1.0]:
		_box(st, Vector3(s * 0.6, 0.12 + TRUNNION_Y * 0.5, 0.0), Vector3(0.09, TRUNNION_Y, 0.2), col, rm, 0.02)
		StreetClutter._cyl(st, Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(s * 0.62, TRUNNION_Y + 0.08, 0.0)), 0.09, 0.09, 0.08, GALV, rm, 12)
	return _finish(st, key)


## The drum: a barrel of DRUM_R along z, the lens at -z behind a ring, cooling rings, a hood at
## the back. Origin on the trunnion axis.
static func searchlight_drum() -> Mesh:
	var key := "drum"
	if _meshes.has(key):
		return _meshes[key]
	var st := StreetClutter._begin()
	var col := Color(1, 1, 1, A_PAINT)
	var rm := Vector2(0.4, 0.45)
	var along := Basis(Vector3.RIGHT, PI * 0.5)
	# The barrel from the back (+z) to the front (-z).
	StreetClutter._cyl(st, Transform3D(along, Vector3(0.0, 0.0, -DRUM_L * 0.5)), DRUM_R, DRUM_R * 0.92, DRUM_L, col, rm, 28)
	# Cooling rings.
	for i in 5:
		var z := -DRUM_L * 0.3 + float(i) * DRUM_L * 0.13
		StreetClutter._cyl(st, Transform3D(along, Vector3(0.0, 0.0, z)), DRUM_R + 0.03, DRUM_R + 0.03, 0.025, GALV, Vector2(0.4, 0.8), 28)
	# The front ring and the lens behind it.
	StreetClutter._cyl(st, Transform3D(along, Vector3(0.0, 0.0, -DRUM_L * 0.5 - 0.06)), DRUM_R + 0.04, DRUM_R + 0.04, 0.08, CHROME, Vector2(0.2, 1.0), 28)
	var n := 28
	var zc := -DRUM_L * 0.5 - 0.035
	for i in n:
		var a0 := TAU * float(i) / n
		var a1 := TAU * float(i + 1) / n
		var r := DRUM_R - 0.02
		StreetClutter._tri(st, Vector3(0.0, 0.0, zc), Vector3(cos(a0) * r, sin(a0) * r, zc), Vector3(cos(a1) * r, sin(a1) * r, zc), Vector3.FORWARD, Color(1, 1, 1, A_LENS), Vector2(0.05, 0.0))
	# The hood at the back.
	StreetClutter._cyl(st, Transform3D(along, Vector3(0.0, 0.0, DRUM_L * 0.5)), DRUM_R * 0.92, DRUM_R * 0.6, 0.22, col, rm, 24)
	return _finish(st, key)


## Builds every mesh once (the loading screen).
static func warm() -> Array:
	var out: Array = []
	for i in LED_COLORS.size():
		out.append(club_entrance(i))
	out.append(bar_entrance())
	out.append(searchlight_cart())
	out.append(searchlight_yoke())
	out.append(searchlight_drum())
	return out
