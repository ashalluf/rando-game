class_name FerrisWheel
extends Node3D
## The pier park's Ferris wheel (PierPark): a real spoked wheel - two laced box rims, twenty
## spokes a side to a flanged hub, a cross tie at every spoke carrying a gondola pin - on two
## tubular A-frames over a boarding platform, with twenty open gondolas under striped canopies.
##
## It turns in the VERTEX SHADER (pier_park.gdshader, ride 1): the body rotates about +Z round the
## hub at OMEGA, each gondola is translated with its pin so it hangs plumb, nothing per frame on
## the CPU, and the far copy (the same meshes at a lower detail) turns with it. After dark the LED
## strips along every spoke and round both rims run chasing patterns (the shader's led_pattern(),
## lamp_factor) - the park's icon from the beach and the hills.
##
## The node stands on the deck under the hub, unturned: the wheel's plane is world XY (it faces
## north and south, broadside to the beach). Collision is a PierRideBody (metal: shot, it sparks
## and keeps turning): the legs, the hub, the platform and each rim as a ring of boxes, which a
## turning wheel can share because a rim is the same shape at any angle.

## Radius of the gondola pins (the outer rim), metres.
const RADIUS := 13.0
## Height of the hub over the deck, metres.
const HUB_H := 16.8
## The two rims stand this far either side of the wheel's plane, metres.
const RIM_Z := 1.6
## Depth of the laced rim (outer ring to inner ring), metres.
const RIM_DEPTH := 1.4
## Spokes a side, and gondolas.
const SPOKES := 20
## Turning speed, rad/s: a turn in two and a half minutes.
const OMEGA := TAU / 150.0
## How far the A-frames' feet spread along the pier (x) and across it (z), metres.
const LEG_SPREAD_X := 7.6
const LEG_Z := 3.6
const LEG_FOOT_Z := 4.8
## The boarding platform's height over the deck, metres.
const PLATFORM_H := 0.6

const WHITE := Color(0.93, 0.92, 0.88)
const STEEL := Color(0.78, 0.78, 0.76)
const GONDOLA_COLORS: Array[Color] = [Color(0.78, 0.12, 0.12), Color(0.95, 0.72, 0.12), Color(0.10, 0.42, 0.72),
	Color(0.10, 0.58, 0.55), Color(0.92, 0.42, 0.10), Color(0.55, 0.20, 0.55)]

static var _meshes: Dictionary = {}


## Builds the wheel standing on the deck at `at` (world) under `parent`. `statics` (or null for
## the far copy) is not used: the wheel carries its own PierRideBody.
static func build(at: Vector3, parent: Node3D, detailed: bool) -> FerrisWheel:
	var wheel := FerrisWheel.new()
	wheel.name = "FerrisWheel"
	wheel.position = at
	parent.add_child(wheel)
	var key := "near" if detailed else "far"
	if not _meshes.has(key):
		_meshes[key] = _meshes_for(detailed)
	var meshes: Array = _meshes[key]
	for i in 3:
		var mi := MeshInstance3D.new()
		mi.name = ["Frame", "Wheel", "WheelLights"][i]
		mi.mesh = meshes[i]
		# The far copy is a silhouette and lights a kilometre off: its shadows are nobody's; nor
		# are the LEDs' anywhere.
		# The near wheel's shadow is drawn by the far copy's wheel (shadows only, the same
		# turning material): its spokes and gondolas throw the same shadow at a fifth of the cost
		# in every cascade.
		if not detailed or i >= 1:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		wheel.add_child(mi)
	if detailed:
		if not _meshes.has("far"):
			_meshes["far"] = _meshes_for(false)
		var sh := MeshInstance3D.new()
		sh.name = "WheelShadow"
		sh.mesh = _meshes["far"][1]
		sh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		wheel.add_child(sh)
	if detailed:
		wheel._add_body()
	return wheel


## [frame, turning wheel, its lights].
static func _meshes_for(detailed: bool) -> Array:
	var turning := _turning_mesh(detailed)
	return [_static_mesh(detailed), turning[0], turning[1]]


static func wheel_material() -> ShaderMaterial:
	return PierMesh.material("wheel", 1, {"hub": Vector3(0.0, HUB_H, 0.0), "omega": OMEGA, "count": float(SPOKES),
		"radius": RADIUS, "spokes": float(SPOKES)})


## The A-frames, the drive, the boarding platform: still.
static func _static_mesh(detailed: bool) -> ArrayMesh:
	var g := PierMesh.new()
	g.use("s", PierMesh.material("park"))
	g.slot("s")
	var sides := 8 if detailed else 5
	var hub := Vector3(0.0, HUB_H, 0.0)
	g.kind = PierMesh.K_PAINT
	for zs: float in [-1.0, 1.0]:
		var top := hub + Vector3(0.0, 0.0, zs * LEG_Z)
		var feet: Array[Vector3] = []
		for xs: float in [-1.0, 1.0]:
			var foot := Vector3(xs * LEG_SPREAD_X, 0.0, zs * LEG_FOOT_Z)
			feet.append(foot)
			g.tube(foot, top, 0.42, 0.3, WHITE, sides, true)
			if detailed:
				# A footing plate and its bolts.
				g.kind = PierMesh.K_METAL
				g.abox(foot + Vector3(0.0, 0.08, 0.0), Vector3(1.4, 0.16, 1.4), STEEL)
				g.kind = PierMesh.K_PAINT
		# Braces between the legs of an A-frame: a tie and a lattice up to the bearing.
		for f in [0.28, 0.55]:
			var a := feet[0].lerp(top, f)
			var b := feet[1].lerp(top, f)
			g.tube(a, b, 0.16, 0.16, WHITE, sides)
		if detailed:
			for f in [0.0, 0.28]:
				var f2: float = f + 0.27
				g.tube(feet[0].lerp(top, f), feet[1].lerp(top, f2), 0.1, 0.1, WHITE, 6)
				g.tube(feet[1].lerp(top, f), feet[0].lerp(top, f2), 0.1, 0.1, WHITE, 6)
		# The bearing block on top of the frame.
		g.kind = PierMesh.K_METAL
		g.abox(top + Vector3(0.0, 0.0, zs * 0.15), Vector3(1.3, 1.4, 0.7), STEEL, 0.0, true)
		g.kind = PierMesh.K_PAINT
	# Ties across the two A-frames at the foot (they stand on one platform).
	for xs: float in [-1.0, 1.0]:
		g.tube(Vector3(xs * LEG_SPREAD_X * 0.72, 4.6, -LEG_FOOT_Z * 0.85), Vector3(xs * LEG_SPREAD_X * 0.72, 4.6, LEG_FOOT_Z * 0.85), 0.14, 0.14, WHITE, sides)
	# The axle.
	g.kind = PierMesh.K_METAL
	g.tube(hub + Vector3(0.0, 0.0, -LEG_Z - 0.4), hub + Vector3(0.0, 0.0, LEG_Z + 0.4), 0.32, 0.32, STEEL, sides, true)
	# Boarding platform under the bottom of the wheel, with steps at both ends and rails.
	g.kind = PierMesh.K_BOARDS
	g.abox(Vector3(0.0, PLATFORM_H * 0.5, 0.0), Vector3(9.0, PLATFORM_H, 4.4), Color(0.55, 0.42, 0.30))
	if detailed:
		for xs: float in [-1.0, 1.0]:
			for k in 3:
				var h := PLATFORM_H * float(k + 1) / 4.0
				g.abox(Vector3(xs * (4.5 + 0.3 + 0.3 * float(2 - k)), h * 0.5, 0.0), Vector3(0.3, h, 2.2), Color(0.55, 0.42, 0.30))
		g.kind = PierMesh.K_METAL
		for zs: float in [-1.0, 1.0]:
			var y := PLATFORM_H + 1.05
			var z := zs * 2.1
			g.tube(Vector3(-4.4, y, z), Vector3(4.4, y, z), 0.035, 0.035, STEEL, 6)
			g.tube(Vector3(-4.4, y - 0.5, z), Vector3(4.4, y - 0.5, z), 0.025, 0.025, STEEL, 6)
			var x := -4.4
			while x <= 4.41:
				g.tube(Vector3(x, PLATFORM_H, z), Vector3(x, y, z), 0.03, 0.03, STEEL, 6)
				x += 1.1
		# The drive: a motor house at the bottom with the tyres that bear on the rim.
		g.kind = PierMesh.K_PAINT
		g.abox(Vector3(3.1, PLATFORM_H + 1.1, -1.7), Vector3(1.6, 2.2, 0.9), Color(0.25, 0.42, 0.55), 0.04)
		g.kind = PierMesh.K_WINDOW
		g.abox(Vector3(3.1, PLATFORM_H + 1.5, -1.24), Vector3(1.1, 0.7, 0.02), Color(0.9, 0.8, 0.6))
		g.kind = PierMesh.K_RUBBER
		for xs: float in [-1.0, 1.0]:
			for zs: float in [-1.0, 1.0]:
				var c := Vector3(xs * 0.75, HUB_H - RADIUS - 0.45, zs * RIM_Z)
				g.tube(c - Vector3(0, 0, 0.18), c + Vector3(0, 0, 0.18), 0.42, 0.42, Color(0.1, 0.1, 0.1), 10, true)
		g.kind = PierMesh.K_METAL
		var tyre_y := HUB_H - RADIUS - 0.45
		for xs: float in [-1.0, 1.0]:
			for zs: float in [-1.0, 1.0]:
				g.abox(Vector3(xs * 0.75, (tyre_y + PLATFORM_H) * 0.5, zs * (RIM_Z + 0.32)), Vector3(0.3, tyre_y - PLATFORM_H, 0.22), STEEL)
	return g.build_mesh()


## The turning wheel: hub, spokes, laced rims, cross ties, the LEDs and the gondolas.
static func _turning_mesh(detailed: bool) -> Array:
	var g := PierMesh.new()
	g.use("w", wheel_material())
	g.use("wl", wheel_material())
	g.light_slot = "wl"
	g.slot("w")
	var hub := Vector3(0.0, HUB_H, 0.0)
	var sides := 6 if detailed else 4
	var ring_steps := SPOKES * (4 if detailed else 2)
	var inner := RADIUS - RIM_DEPTH
	g.anim = 0.0
	g.kind = PierMesh.K_PAINT
	# The hub drum and its two spoke flanges.
	g.kind = PierMesh.K_METAL
	g.tube(hub + Vector3(0, 0, -1.25), hub + Vector3(0, 0, 1.25), 1.0, 1.0, STEEL, 12 if detailed else 8, true)
	g.kind = PierMesh.K_PAINT
	for zs: float in [-1.0, 1.0]:
		g.tube(hub + Vector3(0, 0, zs * 1.25), hub + Vector3(0, 0, zs * 1.55), 1.55, 1.55, WHITE, 16 if detailed else 8, true)
	for zs: float in [-1.0, 1.0]:
		var z := zs * RIM_Z
		# Outer and inner rings.
		for r: float in [RADIUS, inner]:
			var pts := PackedVector3Array()
			for i in ring_steps:
				var a := TAU * float(i) / float(ring_steps)
				pts.append(hub + Vector3(cos(a) * r, sin(a) * r, z))
			g.sweep(pts, 0.12 if r == RADIUS else 0.1, WHITE, sides, true)
		# Lacing between them: a zigzag, two members a spoke bay.
		if detailed:
			for i in SPOKES * 2:
				var a0 := TAU * float(i) / float(SPOKES * 2)
				var a1 := TAU * float(i + 1) / float(SPOKES * 2)
				var r0 := RADIUS if i % 2 == 0 else inner
				var r1 := inner if i % 2 == 0 else RADIUS
				g.tube(hub + Vector3(cos(a0) * r0, sin(a0) * r0, z), hub + Vector3(cos(a1) * r1, sin(a1) * r1, z), 0.055, 0.055, WHITE, 4)
		# The spokes, from the flange to the inner ring.
		for i in SPOKES:
			var a := TAU * float(i) / float(SPOKES)
			var d := Vector3(cos(a), sin(a), 0.0)
			g.tube(hub + d * 1.45 + Vector3(0, 0, zs * 1.5), hub + d * inner + Vector3(0, 0, z), 0.09, 0.07, WHITE, sides)
			if detailed:
				# A radial post across the rim at every spoke.
				g.tube(hub + d * inner + Vector3(0, 0, z), hub + d * RADIUS + Vector3(0, 0, z), 0.08, 0.08, WHITE, 4)
	# Cross ties between the rims at every spoke, carrying the gondola pins; and the diagonal
	# bracing across the two rims every other bay.
	for i in SPOKES:
		var a := TAU * float(i) / float(SPOKES)
		var d := Vector3(cos(a), sin(a), 0.0)
		g.kind = PierMesh.K_PAINT
		g.tube(hub + d * RADIUS + Vector3(0, 0, -RIM_Z), hub + d * RADIUS + Vector3(0, 0, RIM_Z), 0.1, 0.1, WHITE, sides)
		g.tube(hub + d * inner + Vector3(0, 0, -RIM_Z), hub + d * inner + Vector3(0, 0, RIM_Z), 0.08, 0.08, WHITE, sides)
		if detailed and i % 2 == 0:
			var a1 := TAU * float(i + 1) / float(SPOKES)
			var d1 := Vector3(cos(a1), sin(a1), 0.0)
			g.tube(hub + d * RADIUS + Vector3(0, 0, -RIM_Z), hub + d1 * RADIUS + Vector3(0, 0, RIM_Z), 0.05, 0.05, WHITE, 4)
	# LEDs: a strip down every spoke on its outer face and round both rings of both rims.
	g.kind = PierMesh.K_LED
	var lw := 0.13 if detailed else 0.9
	for zs: float in [-1.0, 1.0]:
		var z := zs * (RIM_Z + (0.09 if detailed else 0.3))
		for i in SPOKES:
			g.anim = float(i)
			var a := TAU * float(i) / float(SPOKES)
			var d := Vector3(cos(a), sin(a), 0.0)
			_led_bar(g, hub, d, 1.6, inner, zs * (1.5 + (0.1 if detailed else 0.3)), z, lw)
		for r: float in ([RADIUS, inner] if detailed else [RADIUS]):
			for i in ring_steps:
				var a0 := TAU * float(i) / float(ring_steps)
				var a1 := TAU * float(i + 1) / float(ring_steps)
				# The spoke number, continuous round the rim, so the patterns run round it too.
				g.anim = float(i) * float(SPOKES) / float(ring_steps)
				var p0 := hub + Vector3(cos(a0) * r, sin(a0) * r, z)
				var p1 := hub + Vector3(cos(a1) * r, sin(a1) * r, z)
				_led_seg(g, hub, p0, p1, lw, r)
	g.anim = 0.0
	# The gondolas.
	for i in SPOKES:
		var a := TAU * float(i) / float(SPOKES)
		var pin := hub + Vector3(cos(a), sin(a), 0.0) * RADIUS
		g.anim = float(i + 1)
		_gondola(g, pin, GONDOLA_COLORS[i % GONDOLA_COLORS.size()], detailed)
	g.anim = 0.0
	return [g.build_mesh(["w"]), g.build_mesh(["wl"])]


## An LED strip along a spoke: from r0 to r1 on direction `d`, sliding from z0 (at the flange)
## to z1 (at the rim). UV.x is the distance from the hub (the shader's radius for the patterns).
static func _led_bar(g: PierMesh, hub: Vector3, d: Vector3, r0: float, r1: float, z0: float, z1: float, w: float) -> void:
	var a := hub + d * r0 + Vector3(0, 0, z0)
	var b := hub + d * r1 + Vector3(0, 0, z1)
	var axis := (b - a).normalized()
	var side := axis.cross(Vector3(0, 0, 1)).normalized()
	var out := Vector3(0, 0, signf(z1))
	# Two faces: the flat strip facing out, and a ridge so it reads edge-on.
	for n: Vector3 in [out, side, -side]:
		var off := n * w * 0.5
		var across := (side if n == out else out) * w * 0.5
		g.quad(a + off - across, a + off + across, b + off + across, b + off - across, n,
			Vector2(r0, 0), Vector2(r0, w), Vector2(r1, w), Vector2(r1, 0), Color(1, 1, 1))


static func _led_seg(g: PierMesh, hub: Vector3, p0: Vector3, p1: Vector3, w: float, r: float) -> void:
	var out := Vector3(0, 0, signf(p0.z))
	var radial := ((p0 + p1) * 0.5 - hub)
	radial.z = 0.0
	radial = radial.normalized()
	for n: Vector3 in [out, radial, -radial]:
		var off := n * w * 0.5
		var across := (radial if n == out else out) * w * 0.5
		g.quad(p0 + off - across, p0 + off + across, p1 + off + across, p1 + off - across, n,
			Vector2(r, 0), Vector2(r, w), Vector2(r, w), Vector2(r, 0), Color(1, 1, 1))


## One open gondola hanging plumb from `pin`: a yoke, a striped canopy with a scalloped valance,
## four posts and a tub with two facing benches and a chrome grab rail.
static func _gondola(g: PierMesh, pin: Vector3, col: Color, detailed: bool) -> void:
	var canopy_y := pin.y - 0.75
	var tub_top := pin.y - 2.05
	var tub_bot := pin.y - 3.0
	var c := Vector3(pin.x, 0.0, pin.z)
	if not detailed:
		g.kind = PierMesh.K_PAINT
		g.abox(Vector3(pin.x, (tub_top + tub_bot) * 0.5, pin.z), Vector3(1.7, tub_top - tub_bot, 1.8), col)
		g.kind = PierMesh.K_CANVAS
		g.abox(Vector3(pin.x, canopy_y - 0.1, pin.z), Vector3(1.9, 0.3, 2.0), col)
		g.kind = PierMesh.K_PAINT
		g.abox(Vector3(pin.x, (canopy_y + tub_top) * 0.5, pin.z), Vector3(0.12, canopy_y - tub_top, 1.6), WHITE)
		return
	g.kind = PierMesh.K_METAL
	# The yoke: two hanger straps from the pin to the canopy crown.
	for zs: float in [-1.0, 1.0]:
		g.tube(pin + Vector3(0, 0, zs * 0.75), Vector3(pin.x, canopy_y + 0.05, pin.z + zs * 0.4), 0.05, 0.05, STEEL, 5)
	g.tube(pin + Vector3(0, 0, -0.85), pin + Vector3(0, 0, 0.85), 0.07, 0.07, STEEL, 6, true)
	# Canopy: a low cone, striped, and a valance round its edge.
	g.kind = PierMesh.K_CANVAS
	g.cone(c, 1.2, canopy_y - 0.3, 0.12, canopy_y + 0.1, 12, col)
	g.cone(c, 1.2, canopy_y - 0.5, 1.2, canopy_y - 0.3, 12, col)
	g.cone(c, 1.2, canopy_y - 0.5, 1.2, canopy_y - 0.3, 12, col, true)
	# A neon ring round the canopy's edge (lit after dark; it rides with the gondola).
	g.kind = PierMesh.K_NEON
	g.cone(c, 1.23, canopy_y - 0.56, 1.23, canopy_y - 0.5, 12, col.lightened(0.35))
	g.kind = PierMesh.K_GOLD
	g.ellipsoid(Transform3D(Basis(), Vector3(pin.x, canopy_y + 0.15, pin.z)), Vector3(0.12, 0.12, 0.12), col, 6, 4)
	# Posts.
	g.kind = PierMesh.K_CHROME
	for xs: float in [-1.0, 1.0]:
		for zs: float in [-1.0, 1.0]:
			g.tube(Vector3(pin.x + xs * 0.58, tub_top, pin.z + zs * 0.64), Vector3(pin.x + xs * 0.72, canopy_y - 0.3, pin.z + zs * 0.78), 0.03, 0.03, STEEL, 5)
	# The tub: an oval shell open at the top (painted out, a shade darker in), a rolled lip, a
	# floor, a bench at each end.
	g.kind = PierMesh.K_PAINT
	var n_seg := 16
	var rx := 0.85
	var rz := 0.92
	for i in n_seg:
		var a0 := TAU * float(i) / float(n_seg)
		var a1 := TAU * float(i + 1) / float(n_seg)
		var d0 := Vector3(cos(a0) * rx, 0.0, sin(a0) * rz)
		var d1 := Vector3(cos(a1) * rx, 0.0, sin(a1) * rz)
		var n0 := Vector3(cos(a0) / rx, 0.0, sin(a0) / rz).normalized()
		var n1 := Vector3(cos(a1) / rx, 0.0, sin(a1) / rz).normalized()
		# The wall tucks in toward the floor like a boat's bilge.
		var b0 := c + d0 * 0.86 + Vector3(0, tub_bot, 0)
		var b1 := c + d1 * 0.86 + Vector3(0, tub_bot, 0)
		var m0 := c + d0 + Vector3(0, tub_bot + 0.3, 0)
		var m1 := c + d1 + Vector3(0, tub_bot + 0.3, 0)
		var t0 := c + d0 + Vector3(0, tub_top, 0)
		var t1 := c + d1 + Vector3(0, tub_top, 0)
		var u0 := a0 * 0.9
		var u1 := a1 * 0.9
		g.quad_n(b0, m0, m1, b1, (n0 - Vector3.UP * 0.6).normalized(), n0, n1, (n1 - Vector3.UP * 0.6).normalized(),
			Vector2(u0, 0.0), Vector2(u0, 0.3), Vector2(u1, 0.3), Vector2(u1, 0.0), col)
		g.quad_n(m0, t0, t1, m1, n0, n0, n1, n1, Vector2(u0, 0.3), Vector2(u0, 1.0), Vector2(u1, 1.0), Vector2(u1, 0.3), col)
		g.quad_n(m0, t0, t1, m1, -n0, -n0, -n1, -n1, Vector2(u0, 0.3), Vector2(u0, 1.0), Vector2(u1, 1.0), Vector2(u1, 0.3), col.darkened(0.3))
		g.tri(c + Vector3(0, tub_bot, 0), b0, b1, Vector3.DOWN, Vector2.ZERO, Vector2(u0, 0.0), Vector2(u1, 0.0), col)
		g.tri(c + Vector3(0, tub_bot + 0.1, 0), b0 + Vector3(0, 0.1, 0), b1 + Vector3(0, 0.1, 0), Vector3.UP, Vector2.ZERO, Vector2(u0, 0.0), Vector2(u1, 0.0), Color(0.3, 0.3, 0.3))
	# A white band round the middle.
	g.cone(c, rx * 1.005, tub_bot + 0.55, rx * 1.005, tub_bot + 0.62, 16, WHITE)
	g.kind = PierMesh.K_BOARDS
	for xs: float in [-1.0, 1.0]:
		g.abox(Vector3(pin.x + xs * 0.45, tub_bot + 0.45, pin.z), Vector3(0.45, 0.08, 1.3), Color(0.62, 0.45, 0.30))
		g.abox(Vector3(pin.x + xs * 0.64, tub_bot + 0.75, pin.z), Vector3(0.07, 0.55, 1.2), Color(0.62, 0.45, 0.30))
	g.kind = PierMesh.K_CHROME
	var rail := PackedVector3Array()
	for i in n_seg:
		var a := TAU * float(i) / float(n_seg)
		rail.append(c + Vector3(cos(a) * rx, tub_top + 0.03, sin(a) * rz))
	g.sweep(rail, 0.04, STEEL, 5, true)
	g.kind = PierMesh.K_PAINT


## Collision: a PierRideBody (metal, never breaks) round the frame, the hub and the rims.
func _add_body() -> void:
	var body := PierRideBody.new()
	body.name = "WheelBody"
	add_child(body)
	var hub := Vector3(0.0, HUB_H, 0.0)
	for zs: float in [-1.0, 1.0]:
		for xs: float in [-1.0, 1.0]:
			var foot := Vector3(xs * LEG_SPREAD_X, 0.0, zs * LEG_FOOT_Z)
			var top := hub + Vector3(0.0, 0.0, zs * LEG_Z)
			_beam_shape(body, foot, top, 0.8)
	_beam_shape(body, hub + Vector3(0, 0, -LEG_Z), hub + Vector3(0, 0, LEG_Z), 2.2)
	for zs: float in [-1.0, 1.0]:
		for i in SPOKES:
			var a0 := TAU * float(i) / float(SPOKES)
			var a1 := TAU * float(i + 1) / float(SPOKES)
			var r := RADIUS - RIM_DEPTH * 0.5
			_beam_shape(body, hub + Vector3(cos(a0) * r, sin(a0) * r, zs * RIM_Z), hub + Vector3(cos(a1) * r, sin(a1) * r, zs * RIM_Z), RIM_DEPTH)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(9.0, PLATFORM_H, 4.4)
	cs.shape = bs
	cs.position = Vector3(0.0, PLATFORM_H * 0.5, 0.0)
	body.add_child(cs)


static func _beam_shape(body: CollisionObject3D, a: Vector3, b: Vector3, w: float) -> void:
	var d := b - a
	var z := d.normalized()
	var x := Vector3.UP.cross(z)
	if x.length_squared() < 1e-6:
		x = Vector3.RIGHT.cross(z)
	x = x.normalized()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(w, w, d.length())
	cs.shape = bs
	cs.transform = Transform3D(Basis(x, z.cross(x), z), (a + b) * 0.5)
	body.add_child(cs)
