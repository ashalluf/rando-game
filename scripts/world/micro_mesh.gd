class_name MicroMesh
extends RefCounted
## The meshes of the 2026 Los Angeles street's micromobility (Micromobility, BikeRider): the two
## invented scooter operators' shared e-scooters, the BASIN BIKE share scheme's bikes, docks and
## solar kiosk, inverted-U bike racks, the bike lanes' flexible delineator posts, and the
## riders' own bikes - a drop-bar road bike, a beach cruiser, a longtail cargo bike with a kid
## seat on its deck - all built here in code at real size (700c and 26" wheels with laced
## spokes, a 10" scooter wheel, 172.5 mm cranks, a 73.5 degree seat tube) on one shader
## (shaders/micromobility.gdshader).
##
## Frame of every vehicle: origin on the ground halfway between the wheels' contact points...
## no: origin on the ground UNDER THE BOTTOM BRACKET (a scooter: under the deck's middle), +y up,
## the nose toward -z, the drive side +x. Wheels spin about x.
##
## Vertex colour alpha codes (round(a * 20)) say what a face is; UV2 is (roughness, metallic).
## A vehicle is built in PARTS for a rider (frame, front and rear wheel about their axles, the
## crank about the bottom bracket, each pedal about its spindle) and merged WHOLE for the parked
## fleets and the debris a knocked rider leaves. Names are invented: the scooter operators
## SKOOTA and KWIKR, the share scheme BASIN BIKE (Basin Metro's sister brand).

enum Kind { ROAD, CRUISER, CARGO, SHARE, SCOOTER_A, SCOOTER_B }

# Vertex colour alpha codes, read by shaders/micromobility.gdshader (round(a * 20)).
const A_FIXED := 0.0
const A_METAL := 0.1
const A_RUBBER := 0.2
const A_HEAD := 0.3
const A_TAIL := 0.4
const A_SCREEN := 0.5
const A_SOLAR := 0.6
const A_MAP := 0.7
const A_REFLECT := 0.8
const A_TAPE := 0.85
const A_PAINT := 0.9
const A_PAINT2 := 0.95

## Geometry of each kind (metres, the frame above): wheel centres, radius, the saddle top, the
## grips (hands, +x side; the other mirrored), bottom bracket height, crank length, pedal half
## track, how far the rider's chest leans (degrees from upright), the deck for a scooter.
const GEO := {
	Kind.ROAD: {"rear": Vector3(0.0, 0.335, 0.41), "front": Vector3(0.0, 0.335, -0.585), "r": 0.335, "tyre": 0.026,
		"bb": 0.27, "crank": 0.1725, "q": 0.105, "saddle": Vector3(0.0, 0.965, 0.215), "grip": Vector3(0.205, 0.905, -0.625),
		"lean": 44.0, "spokes": 24, "ratio": 2.9},
	Kind.CRUISER: {"rear": Vector3(0.0, 0.335, 0.47), "front": Vector3(0.0, 0.335, -0.66), "r": 0.335, "tyre": 0.058,
		"bb": 0.29, "crank": 0.165, "q": 0.11, "saddle": Vector3(0.0, 0.905, 0.265), "grip": Vector3(0.29, 1.05, -0.33),
		"lean": 9.0, "spokes": 36, "ratio": 2.1},
	Kind.CARGO: {"rear": Vector3(0.0, 0.27, 0.78), "front": Vector3(0.0, 0.27, -0.63), "r": 0.27, "tyre": 0.06,
		"bb": 0.27, "crank": 0.165, "q": 0.11, "saddle": Vector3(0.0, 0.92, 0.2), "grip": Vector3(0.27, 1.06, -0.38),
		"lean": 14.0, "spokes": 36, "ratio": 2.3},
	Kind.SHARE: {"rear": Vector3(0.0, 0.335, 0.45), "front": Vector3(0.0, 0.335, -0.66), "r": 0.335, "tyre": 0.045,
		"bb": 0.28, "crank": 0.165, "q": 0.11, "saddle": Vector3(0.0, 0.93, 0.25), "grip": Vector3(0.28, 1.04, -0.36),
		"lean": 12.0, "spokes": 32, "ratio": 2.0},
	Kind.SCOOTER_A: {"rear": Vector3(0.0, 0.125, 0.43), "front": Vector3(0.0, 0.125, -0.47), "r": 0.125, "tyre": 0.05,
		"deck": 0.165, "grip": Vector3(0.235, 1.1, -0.36), "lean": 4.0},
	Kind.SCOOTER_B: {"rear": Vector3(0.0, 0.125, 0.43), "front": Vector3(0.0, 0.125, -0.47), "r": 0.125, "tyre": 0.05,
		"deck": 0.165, "grip": Vector3(0.235, 1.1, -0.36), "lean": 4.0},
}

## The operators (invented): name, body colour, accent, the deck's lettering colour.
const OPERATORS := [
	{"name": "SKOOTA", "body": Color(0.02, 0.66, 0.74), "accent": Color(0.95, 0.96, 0.95), "ink": Color(0.97, 0.98, 0.97)},
	{"name": "KWIKR", "body": Color(0.96, 0.58, 0.04), "accent": Color(0.09, 0.09, 0.1), "ink": Color(0.08, 0.08, 0.09)},
]
## The share scheme (invented): Basin Metro's coral with charcoal.
const SHARE_NAME := "BASIN BIKE"
const SHARE_CORAL := Color(0.93, 0.36, 0.28)
const SHARE_DARK := Color(0.13, 0.14, 0.15)
## Frame paints the riders' own bikes come in (sRGB), by kind.
const PAINTS := {
	Kind.ROAD: [Color(0.06, 0.06, 0.07), Color(0.92, 0.92, 0.9), Color(0.7, 0.06, 0.05), Color(0.08, 0.36, 0.5), Color(0.38, 0.4, 0.42), Color(0.12, 0.2, 0.42)],
	Kind.CRUISER: [Color(0.55, 0.82, 0.8), Color(0.93, 0.6, 0.62), Color(0.95, 0.88, 0.62), Color(0.1, 0.1, 0.11), Color(0.7, 0.12, 0.12), Color(0.85, 0.85, 0.82)],
	Kind.CARGO: [Color(0.2, 0.3, 0.22), Color(0.12, 0.13, 0.14), Color(0.6, 0.62, 0.62), Color(0.78, 0.44, 0.12)],
}

static var _meshes: Dictionary = {}
static var _material: ShaderMaterial


# --- Public ----------------------------------------------------------------------------------

## The whole vehicle as one mesh (parked fleets, debris): every part in its resting pose.
static func whole(kind: int) -> Mesh:
	var key := "whole_%d" % kind
	if _meshes.has(key):
		return _meshes[key]
	var st := _begin()
	_frame(st, kind, true)
	var g: Dictionary = GEO[kind]
	_wheel(st, kind, g.front, true)
	_wheel(st, kind, g.rear, false)
	if g.has("crank"):
		_crank(st, kind, Transform3D(Basis(Vector3.RIGHT, 0.6), Vector3(0.0, float(g.bb), 0.0)))
		for s: float in [-1.0, 1.0]:
			var a := 0.6 + (0.0 if s > 0.0 else PI)
			var p := Vector3(s * float(g.q), float(g.bb) + cos(a) * float(g.crank), sin(a) * float(g.crank))
			_pedal(st, Transform3D(Basis(), p), s)
	return _finish(st, key)


## One part of a vehicle for a rider: "frame", "front", "rear" (wheels, about the axle), "crank"
## (about the bottom bracket) and "pedal" (about its spindle, drive side; mirror for the left).
static func part(kind: int, which: String) -> Mesh:
	var key := "%s_%d" % [which, kind]
	if _meshes.has(key):
		return _meshes[key]
	var st := _begin()
	var g: Dictionary = GEO[kind]
	match which:
		"frame":
			_frame(st, kind, false)
		"front":
			_wheel(st, kind, Vector3.ZERO, true)
		"rear":
			_wheel(st, kind, Vector3.ZERO, false)
		"crank":
			_crank(st, kind, Transform3D.IDENTITY)
		"pedal":
			_pedal(st, Transform3D.IDENTITY, 1.0)
	return _finish(st, key)


## A share-bike dock (one post and its stretch of base plate, the bike side toward -z).
static func dock() -> Mesh:
	if _meshes.has("dock"):
		return _meshes["dock"]
	var st := _begin()
	var steel := Color(0.2, 0.21, 0.22, A_METAL)
	var rm := Vector2(0.45, 0.85)
	# Base plate (0.85 m of it, so a row of docks makes one), with a tread pattern of bolts.
	_box(st, Vector3(0.0, 0.02, 0.15), Vector3(0.85, 0.04, 0.9), 0.012, Color(0.32, 0.33, 0.34, A_METAL), Vector2(0.6, 0.8))
	for bx: float in [-0.33, 0.33]:
		for bz: float in [-0.2, 0.5]:
			_cyl(st, Transform3D(Basis(), Vector3(bx, 0.04, bz)), 0.012, 0.012, 0.008, Color(0.5, 0.5, 0.5, A_METAL), Vector2(0.4, 1.0), 6)
	# The post: a rounded column leaning a little toward the bike, the lock mouth at wheel height.
	var post := Transform3D(Basis(Vector3.RIGHT, 0.08), Vector3(0.0, 0.04, 0.32))
	_bbox(st, post.translated_local(Vector3(0.0, 0.42, 0.0)), Vector3(0.11, 0.84, 0.14), 0.035, Color(SHARE_DARK.r, SHARE_DARK.g, SHARE_DARK.b, A_PAINT2), Vector2(0.4, 0.2))
	_bbox(st, post.translated_local(Vector3(0.0, 0.86, -0.01)), Vector3(0.12, 0.05, 0.16), 0.02, Color(SHARE_CORAL.r, SHARE_CORAL.g, SHARE_CORAL.b, A_PAINT), Vector2(0.35, 0.1))
	# The lock: a dark mouth facing the bike, a steel jaw, the status light on top.
	_bbox(st, post.translated_local(Vector3(0.0, 0.52, -0.075)), Vector3(0.07, 0.16, 0.03), 0.01, Color(0.03, 0.03, 0.035), Vector2(0.6, 0.0))
	_bbox(st, post.translated_local(Vector3(0.0, 0.52, -0.088)), Vector3(0.05, 0.03, 0.01), 0.003, steel, rm)
	_bbox(st, post.translated_local(Vector3(0.0, 0.888, -0.03)), Vector3(0.04, 0.008, 0.04), 0.003, Color(0.15, 0.95, 0.35, A_SCREEN), Vector2(0.2, 0.0))
	# A dock number plate.
	_bbox(st, post.translated_local(Vector3(0.0, 0.72, -0.072)), Vector3(0.06, 0.04, 0.004), 0.0, Color(0.95, 0.95, 0.93), Vector2(0.4, 0.0))
	return _finish(st, "dock")


## The station's kiosk: a pole with the solar panel on top, the cabinet with its screen and card
## reader on the front (+z... the user faces -z: the screen faces -z), the map panel on its back.
static func kiosk() -> Mesh:
	if _meshes.has("kiosk"):
		return _meshes["kiosk"]
	var st := _begin()
	var dark := Color(SHARE_DARK.r, SHARE_DARK.g, SHARE_DARK.b, A_PAINT2)
	var coral := Color(SHARE_CORAL.r, SHARE_CORAL.g, SHARE_CORAL.b, A_PAINT)
	var rm := Vector2(0.4, 0.25)
	_box(st, Vector3(0.0, 0.025, 0.0), Vector3(0.75, 0.05, 0.6), 0.015, Color(0.32, 0.33, 0.34, A_METAL), Vector2(0.6, 0.8))
	# The cabinet: a tall rounded box.
	_bbox(st, Transform3D(Basis(), Vector3(0.0, 0.85, 0.0)), Vector3(0.52, 1.6, 0.34), 0.05, dark, rm)
	_bbox(st, Transform3D(Basis(), Vector3(0.0, 1.62, 0.0)), Vector3(0.54, 0.1, 0.36), 0.03, coral, rm)
	# Screen (lit), keypad, card slot, a coral band with the name over it.
	_bbox(st, Transform3D(Basis(Vector3.RIGHT, -0.18), Vector3(0.0, 1.3, -0.172)), Vector3(0.34, 0.24, 0.02), 0.008, Color(0.03, 0.03, 0.035), Vector2(0.2, 0.0))
	_quad(st, Vector3(-0.15, 1.2, -0.187), Vector3(0.15, 1.2, -0.187), Vector3(0.15, 1.4, -0.205), Vector3(-0.15, 1.4, -0.205), Vector3(0.0, 0.18, -1.0), Color(0.35, 0.75, 0.85, A_SCREEN), Vector2(0.1, 0.0))
	for kx in 3:
		for ky in 4:
			_box(st, Vector3(-0.06 + kx * 0.04, 0.98 + ky * 0.035, -0.176), Vector3(0.03, 0.025, 0.012), 0.003, Color(0.55, 0.56, 0.57, A_METAL), Vector2(0.4, 0.9))
	_box(st, Vector3(0.12, 1.05, -0.176), Vector3(0.08, 0.14, 0.02), 0.008, Color(0.08, 0.08, 0.09), Vector2(0.4, 0.0))
	_box(st, Vector3(0.12, 1.1, -0.188), Vector3(0.05, 0.006, 0.004), 0.0, Color(0.15, 0.85, 0.4, A_SCREEN), Vector2(0.4, 0.0))
	_box(st, Vector3(0.0, 0.78, -0.171), Vector3(0.48, 0.08, 0.01), 0.0, coral, rm)
	StreetVendors._text(st, SHARE_NAME, 0.05, Transform3D(Basis(Vector3.UP, PI), Vector3(0.0, 0.78, -0.177)), Color(0.98, 0.97, 0.95), 0.44)
	StreetVendors._text(st, SHARE_NAME, 0.055, Transform3D(Basis(Vector3.UP, PI), Vector3(0.0, 1.62, -0.181)), Color(0.98, 0.97, 0.95), 0.48)
	StreetVendors._text(st, SHARE_NAME, 0.055, Transform3D(Basis(), Vector3(0.0, 1.62, 0.181)), Color(0.98, 0.97, 0.95), 0.48)
	# The map panel on the back: a lit case in a frame.
	_bbox(st, Transform3D(Basis(), Vector3(0.0, 0.95, 0.18)), Vector3(0.46, 0.95, 0.03), 0.01, Color(0.6, 0.61, 0.62, A_METAL), Vector2(0.35, 0.8))
	_page(st, Vector3(-0.2, 1.38, 0.197), Vector3(0.2, 1.38, 0.197), Vector3(0.2, 0.52, 0.197), Vector3(-0.2, 0.52, 0.197), Vector3(0.0, 0.0, 1.0), A_MAP)
	# The pole and the solar panel on its tilted frame.
	_cyl(st, Transform3D(Basis(), Vector3(0.0, 1.66, 0.05)), 0.035, 0.03, 0.75, Color(0.55, 0.56, 0.57, A_METAL), Vector2(0.35, 0.9), 10)
	var panel := Transform3D(Basis(Vector3.RIGHT, -0.42), Vector3(0.0, 2.44, 0.05))
	_bbox(st, panel, Vector3(0.78, 0.04, 0.62), 0.012, Color(0.7, 0.71, 0.72, A_METAL), Vector2(0.3, 0.9))
	var tl := panel * Vector3(-0.37, 0.022, -0.29)
	var tr := panel * Vector3(0.37, 0.022, -0.29)
	var br := panel * Vector3(0.37, 0.022, 0.29)
	var bl := panel * Vector3(-0.37, 0.022, 0.29)
	_page(st, tl, tr, br, bl, panel.basis.y, A_SOLAR)
	_tube(st, [Vector3(0.0, 2.3, 0.05), panel * Vector3(0.0, -0.02, 0.15)], 0.02, 6, Color(0.55, 0.56, 0.57, A_METAL), Vector2(0.35, 0.9))
	return _finish(st, "kiosk")


## An inverted-U bike rack, galvanised, in its two base flanges (along x).
static func rack() -> Mesh:
	if _meshes.has("rack"):
		return _meshes["rack"]
	var st := _begin()
	var galv := Color(0.62, 0.63, 0.63, A_METAL)
	var rm := Vector2(0.42, 0.9)
	var pts: Array = [Vector3(-0.34, 0.0, 0.0), Vector3(-0.34, 0.55, 0.0)]
	for i in range(1, 12):
		var a := PI * float(i) / 12.0
		pts.append(Vector3(-cos(a) * 0.34, 0.55 + sin(a) * 0.34, 0.0))
	pts.append(Vector3(0.34, 0.55, 0.0))
	pts.append(Vector3(0.34, 0.0, 0.0))
	_tube(st, pts, 0.024, 10, galv, rm)
	for s: float in [-1.0, 1.0]:
		_cyl(st, Transform3D(Basis(), Vector3(s * 0.34, 0.0, 0.0)), 0.07, 0.07, 0.012, galv, rm, 12)
		for b in 3:
			var a := TAU * float(b) / 3.0
			_cyl(st, Transform3D(Basis(), Vector3(s * 0.34 + cos(a) * 0.05, 0.012, sin(a) * 0.05)), 0.008, 0.008, 0.01, Color(0.4, 0.4, 0.4, A_METAL), rm, 6)
	return _finish(st, "rack")


## A flexible delineator post (the bike lane's buffer): white, two reflective bands, a black
## base bolted to the road.
static func delineator() -> Mesh:
	if _meshes.has("delineator"):
		return _meshes["delineator"]
	var st := _begin()
	var white := Color(0.9, 0.9, 0.88)
	var rm := Vector2(0.45, 0.0)
	_cyl(st, Transform3D(Basis(), Vector3.ZERO), 0.11, 0.1, 0.03, Color(0.05, 0.05, 0.055), Vector2(0.8, 0.0), 14)
	_cyl(st, Transform3D(Basis(), Vector3(0.0, 0.03, 0.0)), 0.045, 0.04, 0.06, Color(0.06, 0.06, 0.065), Vector2(0.8, 0.0), 12)
	_cyl(st, Transform3D(Basis(), Vector3(0.0, 0.09, 0.0)), 0.04, 0.036, 0.62, white, rm, 12)
	for y: float in [0.71, 0.81]:
		_cyl(st, Transform3D(Basis(), Vector3(0.0, y, 0.0)), 0.0365, 0.0355, 0.075, Color(0.95, 0.95, 0.95, A_REFLECT), Vector2(0.3, 0.0), 12)
	_cyl(st, Transform3D(Basis(), Vector3(0.0, 0.785, 0.0)), 0.0355, 0.0352, 0.025, white, rm, 12)
	_cyl(st, Transform3D(Basis(), Vector3(0.0, 0.885, 0.0)), 0.035, 0.026, 0.02, white, rm, 12)
	return _finish(st, "delineator")


static func material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = load("res://shaders/micromobility.gdshader")
	return _material


## A rider's own material: the frame paint (sRGB, as a Vector3 so Forward+ does not decode it)
## and the lamps lit while it is ridden.
static func rider_material(paint: Color) -> ShaderMaterial:
	var m := material().duplicate() as ShaderMaterial
	m.set_shader_parameter("paint_uniform", Vector3(paint.r, paint.g, paint.b))
	m.set_shader_parameter("use_uniform_paint", true)
	m.set_shader_parameter("lights_on", 1.0)
	return m


## Builds every mesh once (the loading screen).
static func warm() -> void:
	for k in Kind.size():
		whole(k)
		for p: String in ["frame", "front", "rear", "crank", "pedal"]:
			if k >= Kind.SCOOTER_A and (p == "crank" or p == "pedal"):
				continue
			part(k, p)
	dock()
	kiosk()
	rack()
	delineator()


static func triangles(mesh: Mesh) -> int:
	if mesh == null or mesh.get_surface_count() == 0:
		return 0
	var arr := mesh.surface_get_arrays(0)
	if arr.is_empty():
		return 0
	return (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3


# --- Wheels ----------------------------------------------------------------------------------

## A wheel at `c` (its axle along x): tyre, rim, laced spokes, hub; a scooter's is a small solid
## tyre on a five-spoke alloy disc, the front one round a hub motor.
static func _wheel(st: SurfaceTool, kind: int, c: Vector3, front: bool) -> void:
	var g: Dictionary = GEO[kind]
	var r: float = g.r
	var tw: float = g.tyre
	var black := Color(0.035, 0.035, 0.038, A_RUBBER)
	var rub := Vector2(0.85, 0.0)
	var silver := Color(0.72, 0.73, 0.74, A_METAL)
	var rm := Vector2(0.28, 1.0)
	var scooter := kind >= Kind.SCOOTER_A
	var segs := 28 if not scooter else 20
	# Tyre: a torus, its section a little flattened on the tread.
	_torus(st, c, r - tw * 0.5, Vector2(tw * 0.5, tw * 0.55), segs, 8, black, rub)
	if scooter:
		var op: Dictionary = OPERATORS[kind - Kind.SCOOTER_A]
		var disc := Color(0.16, 0.16, 0.17, A_METAL)
		_torus(st, c, r - tw - 0.006, Vector2(0.01, 0.022), segs, 4, disc, Vector2(0.4, 0.9))
		for s: float in [-1.0, 1.0]:
			_disc(st, c + Vector3(s * 0.012, 0.0, 0.0), 0.028, r - tw - 0.01, s, segs, disc, Vector2(0.4, 0.9))
		var hub_r := 0.062 if front else 0.035
		_cylx(st, c, hub_r, 0.07, Color(0.1, 0.1, 0.11, A_METAL) if front else silver, Vector2(0.45, 0.8), 16)
		for k in 5:
			var a := TAU * float(k) / 5.0 + 0.3
			var d := Vector3(0.0, cos(a), sin(a))
			_bbox(st, Transform3D(Basis(Vector3.RIGHT, -a), c + d * (r - tw) * 0.62), Vector3(0.026, (r - tw) * 0.6, 0.012), 0.004, disc, Vector2(0.4, 0.9))
		# A coloured ring on the hub's face.
		_disc(st, c + Vector3(0.036, 0.0, 0.0), 0.0, hub_r * 0.8, 1.0, 16, Color(op.body.r, op.body.g, op.body.b, A_PAINT), Vector2(0.35, 0.2))
		return
	# Rim: a box section, a braking track on its side, the valve.
	var rim_r := r - tw + 0.004
	var rim := silver if kind != Kind.SHARE else Color(0.18, 0.19, 0.2, A_METAL)
	if kind == Kind.ROAD:
		rim = Color(0.06, 0.06, 0.065, A_METAL)
	_torus(st, c, rim_r - 0.01, Vector2(0.012, 0.009 if kind == Kind.ROAD else 0.011), segs, 4, rim, Vector2(0.35, 0.9))
	if kind == Kind.ROAD:
		# Deep carbon-look rims with a band of decal.
		_torus(st, c, rim_r - 0.035, Vector2(0.03, 0.009), segs, 4, rim, Vector2(0.3, 0.2))
	_cylx(st, c + Vector3(0.0, rim_r - 0.03, 0.0).rotated(Vector3.RIGHT, 0.4), 0.003, 0.03, silver, rm, 4)
	# Hub with its two flanges.
	var hub_w := 0.1 if front else 0.13
	_cylx(st, c, 0.019, hub_w, Color(0.6, 0.61, 0.62, A_METAL), rm, 12)
	for s: float in [-1.0, 1.0]:
		_cylx(st, c + Vector3(s * hub_w * 0.32, 0.0, 0.0), 0.032, 0.006, Color(0.6, 0.61, 0.62, A_METAL), rm, 14)
	# The cassette and the hub's dynamo bulge on the share bike.
	if not front:
		for k in 6:
			_cylx(st, c + Vector3(0.035 + k * 0.006, 0.0, 0.0), 0.048 - k * 0.004, 0.002, Color(0.5, 0.5, 0.52, A_METAL), Vector2(0.3, 1.0), 16)
	elif kind == Kind.SHARE:
		_cylx(st, c, 0.042, 0.06, Color(0.2, 0.2, 0.21, A_METAL), rm, 16)
	# Spokes: tangent laced, alternate flanges, three-sided tubes (they are 2 mm wire).
	var n: int = g.spokes
	for k in n:
		var side := 1.0 if k % 2 == 0 else -1.0
		var a := TAU * float(k) / float(n)
		var lace := 0.55 * (1.0 if (k / 2) % 2 == 0 else -1.0)
		var hub_p := c + Vector3(side * hub_w * 0.32, cos(a + lace) * 0.028, sin(a + lace) * 0.028)
		var rim_p := c + Vector3(side * 0.003, cos(a) * (rim_r - 0.012), sin(a) * (rim_r - 0.012))
		if kind == Kind.ROAD:
			rim_p = c + Vector3(side * 0.003, cos(a) * (rim_r - 0.065), sin(a) * (rim_r - 0.065))
		_tube(st, [hub_p, rim_p], 0.0012, 3, silver if kind != Kind.ROAD else Color(0.08, 0.08, 0.085, A_METAL), rm)


# --- The crank set -----------------------------------------------------------------------------

## Chainring(s) and both crank arms about the bottom bracket, the drive-side arm pointing along
## the transform's +y... the arm points to local +y (crank angle 0 = drive arm up).
static func _crank(st: SurfaceTool, kind: int, xf: Transform3D) -> void:
	var g: Dictionary = GEO[kind]
	var cl: float = g.crank
	var q: float = g.q
	var silver := Color(0.66, 0.67, 0.68, A_METAL)
	var dark := Color(0.09, 0.09, 0.1, A_METAL)
	var arm := dark if kind == Kind.ROAD else silver
	var ring_r := 0.105 if kind == Kind.ROAD else 0.095
	# Chainring: a toothed ring with five spider arms.
	_torus(st, xf * Vector3(0.05, 0.0, 0.0), ring_r - 0.006, Vector2(0.002, 0.012), 36, 4, Color(0.3, 0.3, 0.32, A_METAL), Vector2(0.35, 1.0), xf.basis)
	if kind == Kind.ROAD:
		_torus(st, xf * Vector3(0.044, 0.0, 0.0), ring_r - 0.03, Vector2(0.002, 0.01), 32, 4, Color(0.3, 0.3, 0.32, A_METAL), Vector2(0.35, 1.0), xf.basis)
	for k in 5:
		var a := TAU * float(k) / 5.0
		var d := Vector3(0.0, cos(a), sin(a))
		_tube(st, [xf * Vector3(0.047, 0.0, 0.0), xf * (Vector3(0.048, 0.0, 0.0) + d * (ring_r - 0.012))], 0.006, 4, arm, Vector2(0.35, 0.9))
	if kind == Kind.CRUISER or kind == Kind.SHARE:
		# A chain guard ring over the ring.
		_torus(st, xf * Vector3(0.062, 0.0, 0.0), ring_r + 0.006, Vector2(0.002, 0.008), 32, 4, Color(0.75, 0.76, 0.77, A_METAL), Vector2(0.3, 1.0), xf.basis)
	# Spindle and the two arms (drive arm up, the other down).
	_tube(st, [xf * Vector3(-q + 0.03, 0.0, 0.0), xf * Vector3(q - 0.03, 0.0, 0.0)], 0.012, 8, Color(0.5, 0.5, 0.52, A_METAL), Vector2(0.3, 1.0))
	for s: float in [-1.0, 1.0]:
		var top := Vector3(s * (q - 0.025), s * cl, 0.0)
		var base := Vector3(s * 0.06, 0.0, 0.0)
		var axis := (top - base).normalized()
		_bbox(st, Transform3D(xf.basis * Basis(Quaternion(Vector3.UP, axis)), xf * ((top + base) * 0.5)), Vector3(0.016, (top - base).length() + 0.03, 0.032), 0.007, arm, Vector2(0.3, 1.0))


## A pedal on its spindle: platform with a cage on a cruiser, clipless-looking on a road bike.
static func _pedal(st: SurfaceTool, xf: Transform3D, side: float) -> void:
	var dark := Color(0.08, 0.08, 0.085, A_METAL)
	var rm := Vector2(0.45, 0.6)
	_tube(st, [xf * Vector3(0.0, 0.0, 0.0), xf * Vector3(side * 0.04, 0.0, 0.0)], 0.006, 6, Color(0.6, 0.6, 0.62, A_METAL), Vector2(0.3, 1.0))
	_bbox(st, xf.translated_local(Vector3(side * 0.07, 0.0, 0.0)), Vector3(0.095, 0.022, 0.085), 0.008, dark, rm)
	for z: float in [-0.042, 0.042]:
		_box(st, xf * Vector3(side * 0.07, 0.0, z), Vector3(0.1, 0.006, 0.006), 0.0, Color(0.85, 0.5, 0.1, A_REFLECT), Vector2(0.3, 0.0))


# --- Frames ----------------------------------------------------------------------------------

static func _frame(st: SurfaceTool, kind: int, parked: bool) -> void:
	match kind:
		Kind.ROAD:
			_road_frame(st)
		Kind.CRUISER:
			_cruiser_frame(st)
		Kind.CARGO:
			_cargo_frame(st)
		Kind.SHARE:
			_share_frame(st)
		_:
			_scooter_frame(st, kind - Kind.SCOOTER_A, parked)


## The frame's paint: pure "paint" code (the instance's or the rider's colour).
static func _paint() -> Color:
	return Color(1.0, 1.0, 1.0, A_PAINT)


static func _road_frame(st: SurfaceTool) -> void:
	var g: Dictionary = GEO[Kind.ROAD]
	var paint := _paint()
	var rm := Vector2(0.22, 0.25)
	var dark := Color(0.06, 0.06, 0.065)
	var bb := Vector3(0.0, g.bb, 0.0)
	var rear: Vector3 = g.rear
	var front: Vector3 = g.front
	var st_dir := Vector3(0.0, sin(deg_to_rad(73.5)), cos(deg_to_rad(73.5)))
	var st_top := bb + st_dir * 0.53
	var ht_top := Vector3(0.0, 0.81, -0.455)
	var ht_dir := Vector3(0.0, -sin(deg_to_rad(73.0)), -cos(deg_to_rad(73.0)))
	var ht_bot := ht_top + ht_dir * 0.15
	# Main triangle: oversized down tube, slim top tube sloping to the seat cluster.
	_tube(st, [ht_bot, bb + Vector3(0.0, 0.02, -0.02)], 0.022, 10, paint, rm)
	_tube(st, [ht_top + Vector3(0.0, -0.02, 0.0), st_top + Vector3(0.0, -0.03, -0.01)], 0.016, 10, paint, rm)
	_tube(st, [bb, st_top], 0.017, 10, paint, rm)
	_tube(st, [ht_bot + Vector3(0.0, -0.025, 0.0), ht_top + Vector3(0.0, 0.015, 0.0)], 0.024, 12, paint, rm)
	_cylx(st, bb, 0.024, 0.09, paint, rm, 14)
	# Stays: chain stays from the bottom bracket, seat stays from the seat cluster.
	for s: float in [-1.0, 1.0]:
		var drop := rear + Vector3(s * 0.064, 0.0, 0.0)
		_tube(st, [bb + Vector3(s * 0.035, 0.0, 0.02), bb + Vector3(s * 0.05, 0.005, 0.15), drop], 0.0115, 8, paint, rm)
		_tube(st, [st_top + Vector3(s * 0.015, -0.04, 0.01), drop + Vector3(0.0, 0.01, -0.01)], 0.0095, 8, paint, rm)
		# The fork's blades, raked forward at the bottom.
		var crown := ht_bot + Vector3(s * 0.04, -0.03, 0.0)
		_tube(st, [crown, crown.lerp(front + Vector3(s * 0.05, 0.0, 0.0), 0.5) + Vector3(0.0, 0.0, -0.01), front + Vector3(s * 0.05, 0.0, -0.025)], 0.0125, 8, paint, rm)
		_box(st, drop, Vector3(0.008, 0.03, 0.03), 0.003, Color(0.4, 0.4, 0.42, A_METAL), Vector2(0.4, 0.9))
	_bbox(st, Transform3D(Basis(), ht_bot + Vector3(0.0, -0.03, 0.0)), Vector3(0.11, 0.035, 0.05), 0.012, paint, rm)
	# Seat post, saddle, stem and bars.
	var saddle: Vector3 = g.saddle
	_tube(st, [st_top - st_dir * 0.03, saddle + Vector3(0.0, -0.035, -0.01)], 0.0136, 10, Color(0.08, 0.08, 0.085, A_METAL), Vector2(0.4, 0.5))
	_saddle(st, saddle, 0.27, 0.135, 0.05, dark, true)
	var clamp := ht_top + Vector3(0.0, 0.06, -0.015)
	_tube(st, [ht_top + Vector3(0.0, 0.0, 0.0), ht_top + Vector3(0.0, 0.055, -0.012)], 0.017, 10, dark, Vector2(0.45, 0.4))
	var bar_c := clamp + Vector3(0.0, -0.005, -0.1)
	_tube(st, [clamp, bar_c], 0.016, 10, dark, Vector2(0.45, 0.4))
	_drop_bars(st, bar_c, Color(0.05, 0.05, 0.055, A_TAPE))
	# Brakes on the fork crown and the seat stays' bridge, cables, the rear derailleur.
	_bbox(st, Transform3D(Basis(), ht_bot + Vector3(0.0, -0.055, -0.045)), Vector3(0.05, 0.05, 0.02), 0.008, Color(0.1, 0.1, 0.11, A_METAL), Vector2(0.4, 0.8))
	_bbox(st, Transform3D(Basis(), rear + Vector3(0.0, 0.31, -0.02)), Vector3(0.05, 0.04, 0.02), 0.008, Color(0.1, 0.1, 0.11, A_METAL), Vector2(0.4, 0.8))
	_bbox(st, Transform3D(Basis(Vector3.RIGHT, 0.4), rear + Vector3(0.075, -0.06, 0.02)), Vector3(0.02, 0.08, 0.04), 0.006, Color(0.12, 0.12, 0.13, A_METAL), Vector2(0.4, 0.8))
	_chain(st, Kind.ROAD)
	# A bottle cage with a bottle on the down tube.
	var dt_mid := ht_bot.lerp(bb, 0.55)
	var dt_dir := (bb - ht_bot).normalized()
	var bottle := Transform3D(Basis(Quaternion(Vector3.UP, -dt_dir)), dt_mid + Vector3(0.0, 0.045, 0.012))
	_cyl(st, bottle.translated_local(Vector3(0.0, -0.1, 0.0)), 0.035, 0.035, 0.2, Color(0.85, 0.86, 0.84), Vector2(0.45, 0.0), 12)


static func _drop_bars(st: SurfaceTool, c: Vector3, tape: Color) -> void:
	var rm := Vector2(0.75, 0.0)
	_tube(st, [c + Vector3(-0.2, 0.0, 0.0), c + Vector3(0.2, 0.0, 0.0)], 0.0125, 10, tape, rm)
	for s: float in [-1.0, 1.0]:
		var pts := [
			c + Vector3(s * 0.2, 0.0, 0.0), c + Vector3(s * 0.205, 0.008, -0.04), c + Vector3(s * 0.208, 0.012, -0.075),
			c + Vector3(s * 0.21, -0.01, -0.105), c + Vector3(s * 0.21, -0.06, -0.11), c + Vector3(s * 0.21, -0.11, -0.09),
			c + Vector3(s * 0.21, -0.135, -0.05), c + Vector3(s * 0.21, -0.135, -0.0),
		]
		_tube(st, pts, 0.0125, 10, tape, rm)
		# Brake hoods and levers.
		_bbox(st, Transform3D(Basis(Vector3.RIGHT, -0.5), c + Vector3(s * 0.208, 0.03, -0.085)), Vector3(0.032, 0.07, 0.04), 0.012, Color(0.05, 0.05, 0.055, A_RUBBER), Vector2(0.7, 0.0))
		_tube(st, [c + Vector3(s * 0.208, 0.03, -0.11), c + Vector3(s * 0.208, -0.05, -0.125), c + Vector3(s * 0.205, -0.1, -0.11)], 0.006, 6, Color(0.1, 0.1, 0.11, A_METAL), Vector2(0.35, 0.9))


static func _chain(st: SurfaceTool, kind: int) -> void:
	var g: Dictionary = GEO[kind]
	var bb := Vector3(0.05, float(g.bb), 0.0)
	var rear := Vector3(0.05, (g.rear as Vector3).y, (g.rear as Vector3).z)
	var ring := 0.1
	var cog := 0.035
	var steel := Color(0.25, 0.25, 0.27, A_METAL)
	var rm := Vector2(0.45, 1.0)
	_tube(st, [bb + Vector3(0.0, ring, 0.0), rear + Vector3(0.0, cog, 0.0)], 0.004, 4, steel, rm)
	_tube(st, [bb + Vector3(0.0, -ring, 0.0), rear + Vector3(0.0, -cog - 0.03, -0.03), rear + Vector3(0.0, -cog, 0.0)], 0.004, 4, steel, rm)


static func _cruiser_frame(st: SurfaceTool) -> void:
	var g: Dictionary = GEO[Kind.CRUISER]
	var paint := _paint()
	var rm := Vector2(0.2, 0.2)
	var chrome := Color(0.8, 0.81, 0.82, A_METAL)
	var crm := Vector2(0.12, 1.0)
	var bb := Vector3(0.0, g.bb, 0.0)
	var rear: Vector3 = g.rear
	var front: Vector3 = g.front
	var ht_top := Vector3(0.0, 0.86, -0.5)
	var ht_bot := Vector3(0.0, 0.66, -0.56)
	var st_top := bb + Vector3(0.0, 0.5, 0.17)
	# The swoop: a double top tube curving down from the head tube past the seat tube to the
	# rear axle (a cantilever cruiser), and a fat curved down tube.
	var swoop: Array = []
	for i in 9:
		var t := float(i) / 8.0
		swoop.append(Vector3(0.0, lerpf(0.8, 0.5, t) + sin(t * PI) * 0.05, lerpf(-0.5, 0.42, t)))
	_tube(st, swoop, 0.019, 10, paint, rm)
	var dtube: Array = []
	for i in 7:
		var t := float(i) / 6.0
		dtube.append(ht_bot.lerp(bb, t) + Vector3(0.0, 0.0, -0.06) * sin(t * PI))
	_tube(st, dtube, 0.024, 10, paint, rm)
	_tube(st, [bb, st_top], 0.019, 10, paint, rm)
	_tube(st, [ht_bot + Vector3(0.0, -0.02, 0.0), ht_top + Vector3(0.0, 0.02, 0.0)], 0.024, 12, paint, rm)
	_cylx(st, bb, 0.026, 0.09, paint, rm, 14)
	for s: float in [-1.0, 1.0]:
		var drop := rear + Vector3(s * 0.068, 0.0, 0.0)
		_tube(st, [bb + Vector3(s * 0.04, 0.0, 0.02), drop], 0.012, 8, paint, rm)
		_tube(st, [st_top + Vector3(s * 0.02, -0.03, 0.01), drop + Vector3(0.0, 0.01, -0.01)], 0.011, 8, paint, rm)
		var crown := ht_bot + Vector3(s * 0.045, -0.03, 0.0)
		_tube(st, [crown, crown.lerp(front + Vector3(s * 0.055, 0.0, 0.0), 0.6) + Vector3(0.0, 0.0, -0.05), front + Vector3(s * 0.055, 0.0, -0.03)], 0.014, 8, paint, rm)
	# Fenders over both wheels, in paint, with chrome stays.
	_fender(st, front, float(g.r) + 0.03, 0.075, -0.3, 2.3, paint, rm)
	_fender(st, rear, float(g.r) + 0.03, 0.075, 0.35, 3.1, paint, rm)
	# A chain guard plate in paint.
	_bbox(st, Transform3D(Basis(Vector3.RIGHT, -atan2(rear.y - float(g.bb), rear.z)), Vector3(0.075, (float(g.bb) + rear.y) * 0.5 + 0.02, rear.z * 0.45)), Vector3(0.006, 0.09, rear.z + 0.12), 0.003, paint, rm)
	# Saddle: a wide sprung seat on a chrome post.
	var saddle: Vector3 = g.saddle
	_tube(st, [st_top - Vector3(0.0, 0.03, 0.01), saddle + Vector3(0.0, -0.05, -0.02)], 0.0135, 10, chrome, crm)
	_saddle(st, saddle, 0.26, 0.24, 0.07, Color(0.32, 0.18, 0.09), false)
	for s: float in [-1.0, 1.0]:
		_cyl(st, Transform3D(Basis(), saddle + Vector3(s * 0.06, -0.12, 0.07)), 0.012, 0.012, 0.08, chrome, crm, 8)
	# Swept-back bars on a tall stem, white grips.
	var clamp := ht_top + Vector3(0.0, 0.12, 0.0)
	_tube(st, [ht_top, clamp], 0.016, 10, chrome, crm)
	var grip: Vector3 = g.grip
	for s: float in [-1.0, 1.0]:
		var pts := [clamp, clamp + Vector3(s * 0.12, 0.0, -0.01), clamp + Vector3(s * 0.22, 0.02, 0.06), Vector3(s * grip.x * 0.92, grip.y, grip.z - 0.02)]
		_tube(st, pts, 0.011, 10, chrome, crm)
		_tube(st, [Vector3(s * grip.x * 0.92, grip.y, grip.z - 0.02), Vector3(s * (grip.x + 0.03), grip.y, grip.z + 0.06)], 0.017, 10, Color(0.92, 0.9, 0.84, A_RUBBER), Vector2(0.75, 0.0))
	# A bell.
	_sphere(st, clamp + Vector3(-0.1, 0.03, -0.01), 0.022, Color(0.85, 0.86, 0.87, A_METAL), crm, 10)
	_chain(st, Kind.CRUISER)
	# Kickstand (folded) and a rear reflector.
	_tube(st, [bb + Vector3(-0.05, -0.02, 0.06), bb + Vector3(-0.06, 0.02, 0.32)], 0.008, 6, chrome, crm)
	_box(st, rear + Vector3(0.0, 0.29, 0.31), Vector3(0.06, 0.03, 0.01), 0.004, Color(0.8, 0.05, 0.03, A_REFLECT), Vector2(0.3, 0.0))


static func _cargo_frame(st: SurfaceTool) -> void:
	var g: Dictionary = GEO[Kind.CARGO]
	var paint := _paint()
	var rm := Vector2(0.3, 0.2)
	var dark := Color(0.09, 0.09, 0.1, A_METAL)
	var bb := Vector3(0.0, g.bb, 0.0)
	var rear: Vector3 = g.rear
	var front: Vector3 = g.front
	var ht_top := Vector3(0.0, 0.84, -0.5)
	var ht_bot := Vector3(0.0, 0.62, -0.55)
	var st_top := bb + Vector3(0.0, 0.48, 0.16)
	# A step-through main frame: one big curved down tube with the battery on it.
	var dtube: Array = []
	for i in 7:
		var t := float(i) / 6.0
		dtube.append(ht_top.lerp(bb, t) + Vector3(0.0, -0.12, 0.0) * sin(t * PI))
	_tube(st, dtube, 0.028, 12, paint, rm)
	_bbox(st, Transform3D(Basis(Quaternion(Vector3.UP, (ht_top - bb).normalized())), ht_top.lerp(bb, 0.55) + Vector3(0.0, -0.055, 0.035)), Vector3(0.07, 0.36, 0.09), 0.02, Color(0.12, 0.12, 0.13), Vector2(0.5, 0.1))
	_tube(st, [bb, st_top], 0.02, 10, paint, rm)
	_tube(st, [ht_bot, ht_top + Vector3(0.0, 0.02, 0.0)], 0.026, 12, paint, rm)
	_cylx(st, bb, 0.05, 0.1, Color(0.15, 0.15, 0.16), Vector2(0.5, 0.3), 14)
	# The long tail: twin rails from the seat tube and the bottom bracket out past the rear axle.
	var deck_y := 0.6
	for s: float in [-1.0, 1.0]:
		_tube(st, [bb + Vector3(s * 0.04, 0.0, 0.03), rear + Vector3(s * 0.075, 0.0, 0.0)], 0.014, 8, paint, rm)
		_tube(st, [st_top + Vector3(s * 0.02, -0.05, 0.0), Vector3(s * 0.15, deck_y - 0.02, 0.25), Vector3(s * 0.15, deck_y - 0.02, 1.05)], 0.013, 8, paint, rm)
		_tube(st, [rear + Vector3(s * 0.075, 0.0, 0.0), Vector3(s * 0.15, deck_y - 0.02, 0.62)], 0.012, 8, paint, rm)
		_tube(st, [Vector3(s * 0.15, deck_y - 0.02, 1.05), Vector3(s * 0.15, 0.36, 1.05), rear + Vector3(s * 0.075, 0.02, 0.15)], 0.011, 8, paint, rm)
		# Footboards (running boards) for the passenger, and the side guards.
		_bbox(st, Transform3D(Basis(), Vector3(s * 0.2, 0.33, 0.6)), Vector3(0.12, 0.012, 0.5), 0.004, dark, Vector2(0.6, 0.6))
		_tube(st, [Vector3(s * 0.16, deck_y - 0.02, 0.32), Vector3(s * 0.27, deck_y - 0.12, 0.38), Vector3(s * 0.27, deck_y - 0.12, 0.92), Vector3(s * 0.16, deck_y - 0.02, 0.98)], 0.01, 6, dark, Vector2(0.45, 0.8))
		var crown := ht_bot + Vector3(s * 0.05, -0.02, 0.0)
		_tube(st, [crown, front + Vector3(s * 0.06, 0.0, -0.02)], 0.016, 8, paint, rm)
	# The deck: bamboo-coloured boards.
	for k in 5:
		_bbox(st, Transform3D(Basis(), Vector3(-0.12 + k * 0.06, deck_y, 0.65)), Vector3(0.052, 0.014, 0.82), 0.004, Color(0.66, 0.5, 0.3), Vector2(0.65, 0.0))
	# The kid seat on the deck: a moulded shell with a high back, side wings, a harness.
	var seat := Color(0.96, 0.78, 0.08)
	var srm := Vector2(0.45, 0.0)
	_bbox(st, Transform3D(Basis(), Vector3(0.0, deck_y + 0.07, 0.64)), Vector3(0.3, 0.08, 0.3), 0.03, seat, srm)
	_bbox(st, Transform3D(Basis(Vector3.RIGHT, 0.14), Vector3(0.0, deck_y + 0.3, 0.8)), Vector3(0.32, 0.46, 0.05), 0.025, seat, srm)
	for s: float in [-1.0, 1.0]:
		_bbox(st, Transform3D(Basis(Vector3.FORWARD, s * 0.15), Vector3(s * 0.16, deck_y + 0.22, 0.7)), Vector3(0.035, 0.26, 0.24), 0.015, seat, srm)
		_bbox(st, Transform3D(Basis(), Vector3(s * 0.06, deck_y + 0.3, 0.77)), Vector3(0.025, 0.35, 0.006), 0.0, Color(0.12, 0.12, 0.14), Vector2(0.7, 0.0))
	_bbox(st, Transform3D(Basis(), Vector3(0.0, deck_y + 0.12, 0.63)), Vector3(0.24, 0.03, 0.22), 0.012, Color(0.2, 0.22, 0.24), Vector2(0.8, 0.0))
	# Fenders, the rear one under the deck.
	_fender(st, front, float(g.r) + 0.03, 0.08, -0.3, 2.3, Color(0.1, 0.1, 0.11), Vector2(0.5, 0.2))
	# Saddle, a riser stem and flat bars with ergo grips.
	var saddle: Vector3 = g.saddle
	_tube(st, [st_top - Vector3(0.0, 0.03, 0.01), saddle + Vector3(0.0, -0.04, -0.01)], 0.015, 10, dark, Vector2(0.4, 0.6))
	_saddle(st, saddle, 0.26, 0.17, 0.06, Color(0.08, 0.08, 0.085), false)
	var clamp := ht_top + Vector3(0.0, 0.14, -0.02)
	_tube(st, [ht_top, clamp], 0.017, 10, dark, Vector2(0.4, 0.6))
	var grip: Vector3 = g.grip
	_tube(st, [Vector3(-grip.x + 0.06, clamp.y + 0.02, clamp.z + 0.02), Vector3(grip.x - 0.06, clamp.y + 0.02, clamp.z + 0.02)], 0.013, 10, dark, Vector2(0.4, 0.6))
	for s: float in [-1.0, 1.0]:
		_tube(st, [Vector3(s * (grip.x - 0.06), clamp.y + 0.02, clamp.z + 0.02), Vector3(s * (grip.x + 0.035), clamp.y + 0.02, clamp.z + 0.03)], 0.018, 10, Color(0.08, 0.08, 0.085, A_RUBBER), Vector2(0.75, 0.0))
	# A front lamp on the head tube and the rear one under the deck's end.
	_bbox(st, Transform3D(Basis(), ht_top + Vector3(0.0, -0.05, -0.045)), Vector3(0.05, 0.04, 0.05), 0.012, Color(0.1, 0.1, 0.11), Vector2(0.4, 0.4))
	_box(st, ht_top + Vector3(0.0, -0.05, -0.072), Vector3(0.04, 0.03, 0.005), 0.0, Color(0.95, 0.95, 0.9, A_HEAD), Vector2(0.1, 0.0))
	_box(st, Vector3(0.0, deck_y - 0.03, 1.08), Vector3(0.08, 0.03, 0.01), 0.003, Color(0.85, 0.05, 0.03, A_TAIL), Vector2(0.1, 0.0))
	_chain(st, Kind.CARGO)


static func _share_frame(st: SurfaceTool) -> void:
	var g: Dictionary = GEO[Kind.SHARE]
	var coral := Color(SHARE_CORAL.r, SHARE_CORAL.g, SHARE_CORAL.b, A_PAINT)
	var dark := Color(SHARE_DARK.r, SHARE_DARK.g, SHARE_DARK.b, A_PAINT2)
	var rm := Vector2(0.32, 0.15)
	var bb := Vector3(0.0, g.bb, 0.0)
	var rear: Vector3 = g.rear
	var front: Vector3 = g.front
	var ht_top := Vector3(0.0, 0.88, -0.52)
	var ht_bot := Vector3(0.0, 0.64, -0.57)
	var st_top := bb + Vector3(0.0, 0.47, 0.17)
	# A heavy step-through aluminium frame: one fat curved tube, the seat tube, the stays.
	var dtube: Array = []
	for i in 9:
		var t := float(i) / 8.0
		dtube.append(ht_top.lerp(bb, t) + Vector3(0.0, -0.17, 0.02) * sin(t * PI))
	_tube(st, dtube, 0.032, 12, coral, rm)
	_tube(st, [bb, st_top], 0.025, 12, coral, rm)
	_tube(st, [ht_bot, ht_top + Vector3(0.0, 0.02, 0.0)], 0.03, 12, coral, rm)
	_cylx(st, bb, 0.03, 0.1, dark, rm, 14)
	for s: float in [-1.0, 1.0]:
		var drop := rear + Vector3(s * 0.07, 0.0, 0.0)
		_tube(st, [bb + Vector3(s * 0.04, 0.0, 0.02), drop], 0.014, 8, coral, rm)
		_tube(st, [st_top + Vector3(s * 0.02, -0.04, 0.01), drop + Vector3(0.0, 0.01, -0.01)], 0.013, 8, coral, rm)
		var crown := ht_bot + Vector3(s * 0.05, -0.03, 0.0)
		_tube(st, [crown, crown.lerp(front + Vector3(s * 0.055, 0.0, 0.0), 0.6) + Vector3(0.0, 0.0, -0.04), front + Vector3(s * 0.055, 0.0, -0.025)], 0.016, 8, dark, rm)
		# The skirt guard over the back wheel's top quarter.
		var guard: Array = []
		for i in 7:
			var a := lerpf(0.25, 1.6, float(i) / 6.0)
			guard.append(rear + Vector3(s * 0.06, cos(a) * (float(g.r) + 0.01), -sin(a) * (float(g.r) + 0.01)))
		for i in 6:
			var a0: Vector3 = guard[i]
			var a1: Vector3 = guard[i + 1]
			var in0 := rear + (a0 - rear) * 0.62 + Vector3(s * 0.0, 0.0, 0.0)
			var in1 := rear + (a1 - rear) * 0.62
			in0.x = a0.x
			in1.x = a1.x
			_quad(st, a0, a1, in1, in0, Vector3(s, 0.0, 0.0), dark, Vector2(0.5, 0.0))
		StreetVendors._text(st, SHARE_NAME, 0.032, Transform3D(Basis(Vector3.UP, s * PI * 0.5) * Basis(Vector3.BACK, 0.0), rear + Vector3(s * 0.064, 0.2, -0.12)), Color(0.97, 0.96, 0.94), 0.2)
	# Fenders and the chain case: dark.
	_fender(st, front, float(g.r) + 0.03, 0.07, -0.25, 2.4, dark, Vector2(0.5, 0.1))
	_fender(st, rear, float(g.r) + 0.03, 0.07, 0.3, 3.1, dark, Vector2(0.5, 0.1))
	_bbox(st, Transform3D(Basis(Vector3.RIGHT, -atan2(rear.y - float(g.bb), rear.z)), Vector3(0.08, (float(g.bb) + rear.y) * 0.5 + 0.01, rear.z * 0.45)), Vector3(0.025, 0.13, rear.z + 0.18), 0.012, dark, rm)
	# The front basket on its carrier: a wire box (rails and mesh).
	var bc := front + Vector3(0.0, 0.5, -0.05)
	var bw := Vector3(0.18, 0.1, 0.15)
	for y: float in [-bw.y, bw.y]:
		_tube(st, [bc + Vector3(-bw.x, y, -bw.z), bc + Vector3(bw.x, y, -bw.z), bc + Vector3(bw.x, y, bw.z), bc + Vector3(-bw.x, y, bw.z), bc + Vector3(-bw.x, y, -bw.z)], 0.005, 4, dark, Vector2(0.5, 0.6))
	for k in 7:
		var x := lerpf(-bw.x, bw.x, float(k) / 6.0)
		for z: float in [-bw.z, bw.z]:
			_tube(st, [bc + Vector3(x, -bw.y, z), bc + Vector3(x, bw.y, z)], 0.003, 3, dark, Vector2(0.5, 0.6))
		_tube(st, [bc + Vector3(x, -bw.y, -bw.z), bc + Vector3(x, -bw.y, bw.z)], 0.003, 3, dark, Vector2(0.5, 0.6))
	for k in 5:
		var z := lerpf(-bw.z, bw.z, float(k) / 4.0)
		for x: float in [-bw.x, bw.x]:
			_tube(st, [bc + Vector3(x, -bw.y, z), bc + Vector3(x, bw.y, z)], 0.003, 3, dark, Vector2(0.5, 0.6))
	_tube(st, [bc + Vector3(0.0, -bw.y, bw.z), ht_bot + Vector3(0.0, 0.05, -0.04)], 0.008, 6, dark, Vector2(0.5, 0.6))
	for s: float in [-1.0, 1.0]:
		_tube(st, [bc + Vector3(s * 0.1, -bw.y, -bw.z * 0.5), front + Vector3(s * 0.055, 0.02, -0.02)], 0.006, 6, dark, Vector2(0.5, 0.6))
	# The dock's nose: a lock block on the front of the head tube, and the number plate.
	_bbox(st, Transform3D(Basis(), ht_bot + Vector3(0.0, -0.02, -0.06)), Vector3(0.05, 0.07, 0.06), 0.012, dark, rm)
	_bbox(st, Transform3D(Basis(), bc + Vector3(0.0, 0.0, -bw.z - 0.005)), Vector3(0.2, 0.09, 0.004), 0.002, Color(0.96, 0.95, 0.93), Vector2(0.4, 0.0))
	StreetVendors._text(st, SHARE_NAME, 0.026, Transform3D(Basis(Vector3.UP, PI), bc + Vector3(0.0, 0.015, -bw.z - 0.009)), Color(SHARE_CORAL.r * 0.9, SHARE_CORAL.g * 0.9, SHARE_CORAL.b * 0.9), 0.18)
	StreetVendors._text(st, "%04d" % 2147, 0.022, Transform3D(Basis(Vector3.UP, PI), bc + Vector3(0.0, -0.022, -bw.z - 0.009)), Color(0.1, 0.1, 0.11), 0.1)
	# Saddle, quill stem, upright bars, grips, the hub dynamo's lamps.
	var saddle: Vector3 = g.saddle
	_tube(st, [st_top - Vector3(0.0, 0.03, 0.01), saddle + Vector3(0.0, -0.05, -0.01)], 0.015, 10, Color(0.6, 0.61, 0.62, A_METAL), Vector2(0.35, 0.9))
	_bbox(st, Transform3D(Basis(), st_top + Vector3(0.0, 0.0, 0.0)), Vector3(0.05, 0.03, 0.05), 0.01, dark, rm)
	_saddle(st, saddle, 0.26, 0.2, 0.065, Color(0.07, 0.07, 0.075), false)
	var clamp := ht_top + Vector3(0.0, 0.11, 0.01)
	_tube(st, [ht_top, clamp], 0.017, 10, dark, rm)
	var grip: Vector3 = g.grip
	for s: float in [-1.0, 1.0]:
		_tube(st, [clamp, clamp + Vector3(s * 0.14, 0.01, 0.01), Vector3(s * (grip.x - 0.05), grip.y, grip.z - 0.02)], 0.012, 10, dark, rm)
		_tube(st, [Vector3(s * (grip.x - 0.05), grip.y, grip.z - 0.02), Vector3(s * (grip.x + 0.04), grip.y, grip.z + 0.02)], 0.017, 10, Color(0.08, 0.08, 0.085, A_RUBBER), Vector2(0.8, 0.0))
	_bbox(st, Transform3D(Basis(), bc + Vector3(0.0, -bw.y - 0.035, -bw.z + 0.02)), Vector3(0.06, 0.04, 0.05), 0.012, dark, rm)
	_box(st, bc + Vector3(0.0, -bw.y - 0.035, -bw.z - 0.007), Vector3(0.045, 0.028, 0.004), 0.0, Color(0.95, 0.95, 0.9, A_HEAD), Vector2(0.1, 0.0))
	_box(st, rear + Vector3(0.0, 0.3, 0.33), Vector3(0.06, 0.03, 0.02), 0.004, Color(0.85, 0.05, 0.03, A_TAIL), Vector2(0.1, 0.0))


## The operators' shared e-scooter: a deck with grip tape and the battery inside, the rear
## fender with the tail lamp, the stem from the front fork with the operator's colour, the
## lettering and the QR plate, the bar with the display, throttle, brake lever and bell, and on a
## parked one the kickstand down (the rider's has it up).
static func _scooter_frame(st: SurfaceTool, op_index: int, parked: bool) -> void:
	var g: Dictionary = GEO[Kind.SCOOTER_A + op_index]
	var op: Dictionary = OPERATORS[op_index]
	var body := Color(op.body.r, op.body.g, op.body.b, A_PAINT)
	var accent := Color(op.accent.r, op.accent.g, op.accent.b, A_PAINT2)
	var rm := Vector2(0.3, 0.15)
	var dark := Color(0.08, 0.08, 0.085)
	var drm := Vector2(0.5, 0.3)
	var rear: Vector3 = g.rear
	var front: Vector3 = g.front
	var deck_y: float = g.deck
	# Deck: a rounded slab in the body colour, the grip tape on top, the dark underside.
	_bbox(st, Transform3D(Basis(), Vector3(0.0, deck_y - 0.03, -0.02)), Vector3(0.18, 0.06, 0.62), 0.025, body, rm)
	_bbox(st, Transform3D(Basis(), Vector3(0.0, deck_y - 0.06, -0.02)), Vector3(0.16, 0.025, 0.58), 0.01, dark, drm)
	_bbox(st, Transform3D(Basis(), Vector3(0.0, deck_y + 0.002, -0.03)), Vector3(0.15, 0.006, 0.5), 0.002, Color(0.05, 0.05, 0.055, A_TAPE), Vector2(0.95, 0.0))
	for s: float in [-1.0, 1.0]:
		StreetVendors._text(st, op.name, 0.03, Transform3D(Basis(Vector3.UP, s * PI * 0.5), Vector3(s * 0.0905, deck_y - 0.03, -0.02)), op.ink, 0.36)
		# Side reflectors.
		_box(st, Vector3(s * 0.091, deck_y - 0.03, 0.24), Vector3(0.004, 0.015, 0.05), 0.0, Color(0.9, 0.5, 0.05, A_REFLECT), Vector2(0.3, 0.0))
	# Rear: the fender over the wheel (in the accent), the tail lamp on its end, the brake pad.
	_fender(st, rear, float(g.r) + 0.02, 0.07, 0.05, 1.9, accent, rm)
	_box(st, rear + Vector3(0.0, 0.08, 0.13), Vector3(0.05, 0.022, 0.012), 0.004, Color(0.8, 0.05, 0.03, A_TAIL), Vector2(0.1, 0.0))
	for s: float in [-1.0, 1.0]:
		_tube(st, [Vector3(s * 0.05, deck_y - 0.03, 0.27), rear + Vector3(s * 0.04, 0.0, 0.0)], 0.012, 8, dark, drm)
	# The neck: from the deck's nose up to the fork, then the stem leaning back to the bar.
	var neck := Vector3(0.0, deck_y + 0.06, -0.36)
	_tube(st, [Vector3(0.0, deck_y - 0.02, -0.3), neck + Vector3(0.0, 0.0, -0.02)], 0.03, 12, body, rm)
	var fork_top := Vector3(0.0, 0.3, -0.44)
	for s: float in [-1.0, 1.0]:
		_tube(st, [fork_top + Vector3(s * 0.035, 0.0, 0.0), front + Vector3(s * 0.04, 0.0, 0.0)], 0.014, 8, dark, drm)
	_fender(st, front, float(g.r) + 0.02, 0.07, -0.4, 1.4, accent, rm)
	var stem_bot := Vector3(0.0, 0.26, -0.44)
	var stem_top := Vector3(0.0, 1.03, -0.34)
	_tube(st, [stem_bot, stem_top], 0.022, 12, body, rm)
	_tube(st, [stem_bot + Vector3(0.0, -0.02, 0.0), stem_bot + Vector3(0.0, 0.12, 0.016)], 0.03, 12, dark, drm)
	# A folding clamp, the cable, a coloured band up the stem's front with the name.
	_tube(st, [stem_bot.lerp(stem_top, 0.3) - Vector3(0.0, 0.03, 0.0), stem_bot.lerp(stem_top, 0.3) + Vector3(0.0, 0.03, 0.0)], 0.026, 12, accent, rm)
	var sdir := (stem_top - stem_bot).normalized()
	var label := Transform3D(Basis(Vector3.UP, PI) * Basis(Vector3.BACK, PI * 0.5), stem_bot.lerp(stem_top, 0.62) + Vector3(0.0, 0.0, -0.0235))
	label.basis = Basis(Quaternion(Vector3.UP, sdir)) * label.basis
	StreetVendors._text(st, op.name, 0.026, label, op.accent if op_index == 0 else op.accent, 0.3)
	# QR plate.
	var qr := stem_bot.lerp(stem_top, 0.84) + Vector3(0.0, 0.0, -0.022)
	_quad(st, qr + Vector3(-0.022, -0.022, 0.0), qr + Vector3(0.022, -0.022, 0.0), qr + Vector3(0.022, 0.022, 0.004), qr + Vector3(-0.022, 0.022, 0.004), Vector3(0.0, 0.1, -1.0), Color(0.95, 0.95, 0.94, A_SCREEN - 0.05), Vector2(0.4, 0.0))
	# Headlight on the stem's front.
	var hl := stem_bot.lerp(stem_top, 0.92) + Vector3(0.0, 0.0, -0.03)
	_bbox(st, Transform3D(Basis(), hl), Vector3(0.05, 0.03, 0.03), 0.01, dark, drm)
	_box(st, hl + Vector3(0.0, 0.0, -0.016), Vector3(0.04, 0.022, 0.004), 0.0, Color(0.95, 0.96, 0.92, A_HEAD), Vector2(0.1, 0.0))
	# The bar: grips, brake lever, thumb throttle, bell, the display unit in the middle.
	var grip: Vector3 = g.grip
	var bar_y := stem_top.y + 0.035
	_tube(st, [Vector3(-grip.x + 0.06, bar_y, stem_top.z), Vector3(grip.x - 0.06, bar_y, stem_top.z)], 0.012, 10, dark, drm)
	for s: float in [-1.0, 1.0]:
		_tube(st, [Vector3(s * (grip.x - 0.06), bar_y, stem_top.z), Vector3(s * (grip.x + 0.04), bar_y, stem_top.z)], 0.017, 10, Color(0.06, 0.06, 0.065, A_RUBBER), Vector2(0.8, 0.0))
		_tube(st, [Vector3(s * (grip.x - 0.08), bar_y + 0.005, stem_top.z - 0.02), Vector3(s * (grip.x + 0.01), bar_y - 0.005, stem_top.z - 0.07)], 0.005, 6, Color(0.6, 0.6, 0.62, A_METAL), Vector2(0.3, 1.0))
	_bbox(st, Transform3D(Basis(), Vector3(0.11, bar_y + 0.005, stem_top.z + 0.012)), Vector3(0.03, 0.035, 0.025), 0.008, dark, drm)
	_sphere(st, Vector3(-0.1, bar_y + 0.02, stem_top.z - 0.01), 0.018, Color(0.8, 0.81, 0.82, A_METAL), Vector2(0.15, 1.0), 8)
	_bbox(st, Transform3D(Basis(Vector3.RIGHT, -0.5), Vector3(0.0, bar_y + 0.03, stem_top.z + 0.01)), Vector3(0.11, 0.025, 0.08), 0.012, body, rm)
	_quad(st, Vector3(-0.04, bar_y + 0.052, stem_top.z + 0.028), Vector3(0.04, bar_y + 0.052, stem_top.z + 0.028), Vector3(0.04, bar_y + 0.032, stem_top.z - 0.008), Vector3(-0.04, bar_y + 0.032, stem_top.z - 0.008), Vector3(0.0, 1.0, 0.5), Color(0.25, 0.85, 0.95, A_SCREEN), Vector2(0.1, 0.0))
	# The kickstand: down on a parked scooter (it leans on it), up on the ridden one.
	var ks := Vector3(-0.09, deck_y - 0.06, 0.05)
	if parked:
		_tube(st, [ks, ks + Vector3(-0.08, -deck_y + 0.065, 0.06)], 0.008, 6, dark, drm)
	else:
		_tube(st, [ks, ks + Vector3(-0.005, 0.0, 0.16)], 0.008, 6, dark, drm)


## A saddle at `c` (its top), nose toward -z: a lofted shell, narrow nose, rails under it.
static func _saddle(st: SurfaceTool, c: Vector3, length: float, width: float, height: float, col: Color, racing: bool) -> void:
	var rm := Vector2(0.55, 0.0)
	var rows := 8
	var cols := 10
	var grid: Array = []
	for i in rows + 1:
		var t := float(i) / float(rows)
		var z := lerpf(-length * 0.5, length * 0.5, t)
		var w := lerpf(width * (0.22 if racing else 0.35), width * 0.5, smoothstep(0.1, 0.75, t))
		var dip := sin(t * PI) * 0.008
		var row: Array = []
		for j in cols + 1:
			var u := float(j) / float(cols)
			var a := lerpf(-PI * 0.55, PI * 0.55, u)
			row.append(c + Vector3(sin(a) * w, (cos(a) - 1.0) * height * 0.5 - dip, z))
		grid.append(row)
	for i in rows:
		for j in cols:
			var n := ((grid[i][j] as Vector3) + (grid[i + 1][j + 1] as Vector3)) * 0.5 - (c + Vector3(0.0, -height * 0.8, 0.0))
			_quad(st, grid[i][j], grid[i][j + 1], grid[i + 1][j + 1], grid[i + 1][j], n, col, rm)
	# Underside and rails.
	_quad(st, grid[0][0], grid[0][cols], grid[rows][cols], grid[rows][0], Vector3.DOWN, col.darkened(0.3), rm)
	for s: float in [-1.0, 1.0]:
		_tube(st, [c + Vector3(s * 0.02, -height * 0.9, -length * 0.42), c + Vector3(s * 0.035, -height - 0.015, 0.0), c + Vector3(s * 0.04, -height * 0.8, length * 0.4)], 0.0035, 4, Color(0.6, 0.6, 0.62, A_METAL), Vector2(0.3, 1.0))


## A fender: a band of `width` at `radius` round `c` from angle a0 to a1 (0 = straight up,
## positive toward -z, the front).
static func _fender(st: SurfaceTool, c: Vector3, radius: float, width: float, a0: float, a1: float, col: Color, rm: Vector2) -> void:
	var n := 14
	var prev_l := Vector3.ZERO
	var prev_r := Vector3.ZERO
	for i in n + 1:
		var a := lerpf(a0, a1, float(i) / float(n))
		var d := Vector3(0.0, cos(a), -sin(a))
		var p := c + d * radius
		var l := p + Vector3(-width * 0.5, 0.0, 0.0) - d * 0.012
		var r := p + Vector3(width * 0.5, 0.0, 0.0) - d * 0.012
		var m := p
		if i > 0:
			var prev_m := (prev_l + prev_r) * 0.5 + d * 0.012
			_quad(st, prev_l, prev_m, m, l, d, col, rm)
			_quad(st, prev_m, prev_r, r, m, d, col, rm)
			_quad(st, prev_l, l, m, prev_m, -d, col.darkened(0.25), rm)
			_quad(st, prev_m, m, r, prev_r, -d, col.darkened(0.25), rm)
		prev_l = l
		prev_r = r


# --- Geometry helpers ------------------------------------------------------------------------

static func _begin() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st


static func _finish(st: SurfaceTool, key: String) -> Mesh:
	st.generate_tangents()
	var mesh := st.commit()
	mesh.surface_set_material(0, material())
	_meshes[key] = mesh
	return mesh


static func _box(st: SurfaceTool, c: Vector3, size: Vector3, bevel: float, col: Color, rm: Vector2) -> void:
	StreetClutter._bbox(st, Transform3D(Basis(), c), size, bevel, _code(col), rm)


static func _bbox(st: SurfaceTool, xf: Transform3D, size: Vector3, bevel: float, col: Color, rm: Vector2) -> void:
	StreetClutter._bbox(st, xf, size, bevel, _code(col), rm)


static func _tube(st: SurfaceTool, path: Array, r: float, sides: int, col: Color, rm: Vector2) -> void:
	StreetClutter._tube(st, path, r, sides, _code(col), rm)
	# Close the ends of a thick tube (thin ones are never seen end on).
	if r > 0.01 and path.size() >= 2:
		for e in 2:
			var a: Vector3 = path[0] if e == 0 else path[path.size() - 1]
			var b: Vector3 = path[1] if e == 0 else path[path.size() - 2]
			var along := (a - b).normalized()
			_disc_at(st, a, along, r, sides, _code(col), rm)


static func _cyl(st: SurfaceTool, xf: Transform3D, r0: float, r1: float, height: float, col: Color, rm: Vector2, sides: int) -> void:
	StreetClutter._cyl(st, xf, r0, r1, height, _code(col), rm, sides)


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, want: Vector3, col: Color, rm: Vector2) -> void:
	StreetClutter._quad(st, a, b, c, d, want, _code(col), rm)


static func _sphere(st: SurfaceTool, c: Vector3, r: float, col: Color, rm: Vector2, seg: int) -> void:
	StreetVendors._ellipsoid(st, c, Vector3(r, r, r), Basis(), _code(col), rm, seg, maxi(seg / 2, 3))


## A cylinder along x centred on `c`.
static func _cylx(st: SurfaceTool, c: Vector3, r: float, width: float, col: Color, rm: Vector2, sides: int) -> void:
	var b := Basis(Vector3.BACK, -PI * 0.5)
	StreetClutter._cyl(st, Transform3D(b, c - b * Vector3(0.0, width * 0.5, 0.0)), r, r, width, _code(col), rm, sides)


## A printed face (UV 0..1 over it): the solar cells, the map.
static func _page(st: SurfaceTool, tl: Vector3, tr: Vector3, br: Vector3, bl: Vector3, n: Vector3, code: float) -> void:
	StreetClutter._page(st, tl, tr, br, bl, n, code, Vector2.ZERO, Vector2(0.3, 0.0))


## A torus round the x axis at `c` (or round `basis`'s x): ring radius `R`, section radii (across
## the ring, along the axle).
static func _torus(st: SurfaceTool, c: Vector3, R: float, sec: Vector2, segs: int, sides: int, col: Color, rm: Vector2, basis: Basis = Basis()) -> void:
	col = _code(col)
	var rings: Array = []
	for i in segs + 1:
		var a := TAU * float(i) / float(segs)
		var radial := Vector3(0.0, cos(a), sin(a))
		var row: Array = []
		for k in sides + 1:
			var b := TAU * float(k) / float(sides) + (PI / float(sides) if sides == 4 else 0.0)
			var off := radial * cos(b) * sec.x + Vector3(sin(b) * sec.y, 0.0, 0.0)
			var nrm := (radial * cos(b) / maxf(sec.x, 1e-4) + Vector3(sin(b) / maxf(sec.y, 1e-4), 0.0, 0.0)).normalized()
			row.append([c + basis * (radial * R + off), basis * nrm])
		rings.append(row)
	for i in segs:
		for k in sides:
			var p00: Array = rings[i][k]
			var p01: Array = rings[i][k + 1]
			var p10: Array = rings[i + 1][k]
			var p11: Array = rings[i + 1][k + 1]
			StreetClutter._smooth_quad(st, p00[0], p10[0], p11[0], p01[0], p00[1], p10[1], p11[1], p01[1], col, rm)


## A flat ring (annulus) facing ±x at `c`, from radius r0 to r1.
static func _disc(st: SurfaceTool, c: Vector3, r0: float, r1: float, side: float, segs: int, col: Color, rm: Vector2) -> void:
	col = _code(col)
	for i in segs:
		var a0 := TAU * float(i) / float(segs)
		var a1 := TAU * float(i + 1) / float(segs)
		var d0 := Vector3(0.0, cos(a0), sin(a0))
		var d1 := Vector3(0.0, cos(a1), sin(a1))
		if r0 <= 0.0:
			StreetClutter._tri(st, c, c + d0 * r1, c + d1 * r1, Vector3(side, 0.0, 0.0), col, rm)
		else:
			StreetClutter._quad(st, c + d0 * r0, c + d0 * r1, c + d1 * r1, c + d1 * r0, Vector3(side, 0.0, 0.0), col, rm)


static func _disc_at(st: SurfaceTool, c: Vector3, n: Vector3, r: float, sides: int, col: Color, rm: Vector2) -> void:
	var ref := Vector3.UP if absf(n.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	var u := n.cross(ref).normalized()
	var v := n.cross(u).normalized()
	for k in sides:
		var t0 := TAU * float(k) / sides
		var t1 := TAU * float(k + 1) / sides
		StreetClutter._tri(st, c, c + (u * cos(t0) + v * sin(t0)) * r, c + (u * cos(t1) + v * sin(t1)) * r, n, col, rm)


## Colours with no code are fixed colours; StreetClutter._vtx turns an opaque non-white colour's
## alpha into its own A_FIXED (0), which is ours too, and keeps the codes we set.
static func _code(col: Color) -> Color:
	if col.a > 0.99:
		col.a = A_FIXED
	return col
