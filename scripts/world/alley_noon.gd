class_name AlleyNoon
extends RefCounted
## The service alley at noon (wave 8, refcam `alley_noon`: a downtown alley at 12:00 clear, eye level
## halfway down). What read as a game there, in the order the eye found it:
##   - the ground was spotted with bright blue-white splotches: AlleyNight's standing water (puddles
##     that never dry, for the night's mirror) under a noon sky, each mirroring the open sky through
##     the engine's reflection - paint spilt on the slab, not water in a canyon. By day
##     (`day_dry`, alley_ground.gdshader, faded in as lamp_factor falls) the slab's dips dry out,
##     the gutter's water breaks into short shallow runs, and what water is left mirrors the
##     ALLEY - the shaded foot of the far wall, its sunlit top, a slit of sky - by its own
##     emitted mirror, with the engine's sky reflection turned down (`day_mirror()`);
##   - the 96-gallon carts in the foreground were two boxes and a slab: they are moulded now - a
##     body tapering to the foot with chamfered corners, a rim, a domed lid with a front lip, the
##     handle on its posts, an axle and bigger wheels (`cart()`);
##   - the leaning mattress was a blank pale box: it is quilted (a puffed, tufted grid), bowed,
##     piped round its face, grimy at the foot and stained (`mattress()`);
##   - the back doors' concrete stoops were bright white blocks floating on the slab: worn
##     concrete now, with a dark lip of grime where they meet the ground (`stoop()`).
## Every variation is a hash of where the prop stands (IndustrialKit._xf's origin), never an rng:
## AlleyKit's rngs make the same calls, so no prop moves. The alley at night (alley_night) is drawn
## exactly as before: the water's day terms are 0 once lamp_factor is 1.
## Off (the A/B): ALLEY_NOON=0 in the environment.

static func _static_init() -> void: LoadPulse.compiled()  # a boot frame: docs/HANDOFF.md "The boot compile"

static var enabled: bool = OS.get_environment("ALLEY_NOON") != "0"

## The stoop's worn concrete (AlleyKit's was a bright 0.72 white) and its grime lip.
const STOOP_PAINT := Color(0.52, 0.51, 0.48)
const STOOP_GRIME := Color(0.2, 0.19, 0.17)
## The mattress: quilting cells across and along, how far a cell puffs and a tuft sinks (m), the bow.
const QUILT_X := 5
const QUILT_Y := 8
const PUFF := 0.015
const TUFT := 0.009
const BOW := 0.06


## The alley ground's shared material: the day terms on (alley_ground.gdshader `day_dry`).
static func ground(mat: ShaderMaterial) -> void:
	mat.set_shader_parameter("day_dry", 1.0 if enabled else 0.0)


static func _h01(parts: Array) -> float:
	return float(absi(hash(parts)) % 100003) / 100003.0


## A hash of where the prop being written stands (IndustrialKit's placement), and a salt.
static func _here(salt: String) -> float:
	var o := IndustrialKit._xf.origin
	return _h01([int(round(o.x * 20.0)), int(round(o.z * 20.0)), salt])


## One triangle in the prop's local frame, turned to face `out` (IndustrialKit's winding: front faces
## clockwise to the viewer), its flat normal, into `st` through IndustrialKit's placement.
static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, out: Vector3, col: Color, uvs: Array, h: float) -> void:
	var xf := IndustrialKit._xf
	var pa := xf * a
	var pb := xf * b
	var pc := xf * c
	var ua: Vector2 = uvs[0]
	var ub: Vector2 = uvs[1]
	var uc: Vector2 = uvs[2]
	var n := (pb - pa).cross(pc - pa)
	if n.length_squared() < 1e-12:
		return
	var wo := xf.basis * out
	if n.dot(wo) > 0.0:
		var t := pb
		pb = pc
		pc = t
		var tu := ub
		ub = uc
		uc = tu
		n = -n
	n = -n.normalized()
	IndustrialKit.tris += 1
	for k in 3:
		st.set_normal(n)
		st.set_color(col)
		st.set_uv([ua, ub, uc][k])
		st.set_uv2(Vector2(h, 0.0))
		st.add_vertex([pa, pb, pc][k])


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, out: Vector3, col: Color, h: float) -> void:
	var ua := Vector2(0.0, a.y)
	var ub := Vector2((b - a).length(), b.y)
	var uc := Vector2((b - a).length(), c.y)
	var ud := Vector2(0.0, d.y)
	_tri(st, a, b, c, out, col, [ua, ub, uc], h)
	_tri(st, a, c, d, out, col, [ua, uc, ud], h)


## A ring of `pts` (x, z) at y0 joined to the ring `pts1` at y1: the side walls, each quad facing out
## from the rings' centre.
static func _loft(st: SurfaceTool, pts0: Array, y0: float, pts1: Array, y1: float, col: Color) -> void:
	var n := pts0.size()
	var cen := Vector2.ZERO
	for p: Vector2 in pts0:
		cen += p
	cen /= float(n)
	for i in n:
		var j := (i + 1) % n
		var a0: Vector2 = pts0[i]
		var b0: Vector2 = pts0[j]
		var a1: Vector2 = pts1[i]
		var b1: Vector2 = pts1[j]
		var mid := (a0 + b0) * 0.5 - cen
		_quad(st, Vector3(a0.x, y0, a0.y), Vector3(b0.x, y0, b0.y), Vector3(b1.x, y1, b1.y), Vector3(a1.x, y1, a1.y), Vector3(mid.x, 0.0, mid.y), col, y1)


## A flat cap over the ring `pts` at y, facing `up` (1 up, -1 down).
static func _cap(st: SurfaceTool, pts: Array, y: float, up: float, col: Color) -> void:
	var cen := Vector2.ZERO
	for p: Vector2 in pts:
		cen += p
	cen /= float(pts.size())
	for i in pts.size():
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[(i + 1) % pts.size()]
		_tri(st, Vector3(cen.x, y, cen.y), Vector3(a.x, y, a.y), Vector3(b.x, y, b.y), Vector3(0.0, up, 0.0), col,
			[cen, a, b], 1.0)


## A rectangle `w` x `d` round (cx, cz) with its corners chamfered by `ch`: eight points, CCW in x/z.
static func _chamfer(cx: float, cz: float, w: float, d: float, ch: float) -> Array:
	var x := w * 0.5
	var z := d * 0.5
	return [Vector2(cx - x + ch, cz - z), Vector2(cx + x - ch, cz - z), Vector2(cx + x, cz - z + ch), Vector2(cx + x, cz + z - ch),
		Vector2(cx + x - ch, cz + z), Vector2(cx - x + ch, cz + z), Vector2(cx - x, cz + z - ch), Vector2(cx - x, cz - z + ch)]


# --- The props (AlleyKit's local frame: x along the wall, y up, z out of the wall) ---------------

## A moulded 96-gallon wheeled cart, the footprint of AlleyKit's (0.6 x 0.68, lid at 1.0 m, handle
## and wheels at -z): the body tapering to its foot with chamfered corners and two moulded ribs, a
## rim, a domed lid with a front lip and the hinge at the back, the handle on its posts, the axle
## and its wheels. ~200 triangles. Returns false (draw the old one) when off.
static func cart(st: SurfaceTool, paint: Color, lid: Color) -> bool:
	if not enabled:
		return false
	var body := IndustrialKit.kind_color(IndustrialKit.K_PLASTIC, paint)
	var dark := IndustrialKit.kind_color(IndustrialKit.K_PLASTIC, paint * 0.72)
	var lid_c := IndustrialKit.kind_color(IndustrialKit.K_PLASTIC, lid)
	var foot := _chamfer(0.0, 0.02, 0.5, 0.56, 0.07)
	var waist := _chamfer(0.0, 0.01, 0.56, 0.63, 0.08)
	var top := _chamfer(0.0, 0.0, 0.6, 0.68, 0.08)
	var rim := _chamfer(0.0, 0.0, 0.64, 0.72, 0.08)
	_loft(st, foot, 0.08, waist, 0.5, body)
	# A moulded rib round the middle (a step out and back).
	var rib := _chamfer(0.0, 0.01, 0.585, 0.655, 0.08)
	_loft(st, waist, 0.5, rib, 0.53, dark)
	_loft(st, rib, 0.53, rib, 0.58, dark)
	_loft(st, rib, 0.58, top, 0.6, body)
	_loft(st, top, 0.6, top, 0.93, body)
	_cap(st, foot, 0.08, -1.0, dark)
	# The rim, a band standing out under the lid.
	_loft(st, top, 0.93, rim, 0.945, dark)
	_loft(st, rim, 0.945, rim, 0.975, dark)
	# The lid: a slab with a shallow dome and a lip hanging over the front (+z).
	var lid0 := _chamfer(0.0, 0.03, 0.66, 0.79, 0.07)
	var lid1 := _chamfer(0.0, 0.03, 0.6, 0.72, 0.09)
	_loft(st, lid0, 0.975, lid0, 1.0, lid_c)
	_loft(st, lid0, 1.0, lid1, 1.03, lid_c)
	_cap(st, lid1, 1.03, 1.0, lid_c)
	_cap(st, lid0, 0.975, -1.0, lid_c)
	# The front lip's grip.
	AlleyKit._box(st, Vector3(0.0, 0.985, 0.425), Vector3(0.3, 0.035, 0.04), IndustrialKit.K_PLASTIC, lid * 0.8)
	# The handle: two moulded posts off the back and the bar between them, the hinge pins.
	for sx: float in [-0.22, 0.22]:
		AlleyKit._box(st, Vector3(sx, 0.9, -0.365), Vector3(0.05, 0.12, 0.07), IndustrialKit.K_PLASTIC, paint * 0.8)
	AlleyKit._box(st, Vector3(0.0, 0.95, -0.4), Vector3(0.5, 0.035, 0.035), IndustrialKit.K_PLASTIC, paint * 0.75)
	# The wheel housings, the axle, the wheels (bigger than the old 0.13, hubs).
	for sx: float in [-1.0, 1.0]:
		AlleyKit._box(st, Vector3(sx * 0.22, 0.14, -0.31), Vector3(0.1, 0.16, 0.14), IndustrialKit.K_PLASTIC, paint * 0.7)
		var wx := sx * 0.31
		IndustrialKit.cyl(st, Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(wx - 0.035 * (1.0 if sx > 0.0 else 0.0), 0.15, -0.33)), 0.15, 0.07, IndustrialKit.K_RUBBER, Color(0.06, 0.06, 0.06), 14, true)
		IndustrialKit.cyl(st, Transform3D(Basis(Vector3.FORWARD, PI * 0.5), Vector3(wx + (0.0 if sx > 0.0 else -0.012), 0.15, -0.33)), 0.06, 0.084, IndustrialKit.K_PLASTIC, paint * 0.6, 8, true)
	AlleyKit._box(st, Vector3(0.0, 0.15, -0.33), Vector3(0.6, 0.025, 0.025), IndustrialKit.K_GALV, Color(0.5, 0.5, 0.48))
	return true


## An old mattress leaning on the wall (AlleyKit's footprint: 1.4 x 1.9 x 0.2, its foot 0.33 out):
## bowed out at the belly, its face quilted - a grid of puffed cells pulled in at the tufts, flat
## shaded so the sun picks the quilting out -, piped round the face, grimy toward the foot and
## stained. ~450 triangles.
static func mattress(st: SurfaceTool, paint: Color) -> bool:
	if not enabled:
		return false
	var W := 1.4
	var L := 1.9
	var T := 0.2
	# The centre line: the foot on the ground 0.45 out, the head against the wall at 1.86, bowed out.
	var foot := Vector3(0.0, 0.0, 0.45)
	var head := Vector3(0.0, 1.86, 0.13)
	var up := (head - foot).normalized()
	var out := Vector3(0.0, up.z, -up.y).normalized() * -1.0
	if out.z < 0.0:
		out = -out
	var bow := BOW * (0.6 + 0.8 * _here("bow"))
	var stain_u := 0.25 + 0.5 * _here("stu")
	var stain_v := 0.3 + 0.5 * _here("stv")
	var stain_r := 0.12 + 0.18 * _here("str")
	var grime := Color(paint.r * 0.62, paint.g * 0.6, paint.b * 0.56)
	var stain := Color(paint.r * 0.8, paint.g * 0.68, paint.b * 0.46)
	var pipe := IndustrialKit.kind_color(IndustrialKit.K_RUBBER, paint * 0.82)
	# The face's grid points: centre line point at v (0..1 along), x across, then pushed along `out`
	# by half the thickness, the bow, and the quilting.
	var centre := func(v: float) -> Vector3:
		return foot + (head - foot) * v + out * bow * sin(PI * v)
	var face := func(u: float, v: float, lift: float) -> Vector3:
		return centre.call(v) + Vector3(u - 0.5, 0.0, 0.0) * W + out * (T * 0.5 + lift)
	var col_at := func(u: float, v: float) -> Color:
		var c := paint
		var g := 1.0 - smoothstep(0.0, 0.28, v)
		c = c.lerp(grime, g * 0.75)
		var dd := Vector2((u - stain_u) * W, (v - stain_v) * L).length()
		if dd < stain_r:
			c = c.lerp(stain, 0.6 * (1.0 - smoothstep(stain_r * 0.55, stain_r, dd)))
		return IndustrialKit.kind_color(IndustrialKit.K_RUBBER, c)
	# The quilted face.
	for j in QUILT_Y:
		for i in QUILT_X:
			var u0 := float(i) / QUILT_X
			var u1 := float(i + 1) / QUILT_X
			var v0 := float(j) / QUILT_Y
			var v1 := float(j + 1) / QUILT_Y
			var um := (u0 + u1) * 0.5
			var vm := (v0 + v1) * 0.5
			var t00: float = -TUFT if (i > 0 and j > 0) else 0.0
			var t10: float = -TUFT if (i + 1 < QUILT_X and j > 0) else 0.0
			var t11: float = -TUFT if (i + 1 < QUILT_X and j + 1 < QUILT_Y) else 0.0
			var t01: float = -TUFT if (i > 0 and j + 1 < QUILT_Y) else 0.0
			var p00: Vector3 = face.call(u0, v0, t00)
			var p10: Vector3 = face.call(u1, v0, t10)
			var p11: Vector3 = face.call(u1, v1, t11)
			var p01: Vector3 = face.call(u0, v1, t01)
			var pm: Vector3 = face.call(um, vm, PUFF * (0.8 + 0.4 * _h01([i, j, int(paint.r * 100.0)])))
			var c: Color = col_at.call(um, vm)
			var uvm := Vector2(um * W, vm * L)
			_tri(st, p00, p10, pm, out, c, [Vector2(u0 * W, v0 * L), Vector2(u1 * W, v0 * L), uvm], L)
			_tri(st, p10, p11, pm, out, c, [Vector2(u1 * W, v0 * L), Vector2(u1 * W, v1 * L), uvm], L)
			_tri(st, p11, p01, pm, out, c, [Vector2(u1 * W, v1 * L), Vector2(u0 * W, v1 * L), uvm], L)
			_tri(st, p01, p00, pm, out, c, [Vector2(u0 * W, v1 * L), Vector2(u0 * W, v0 * L), uvm], L)
	# The back (one face per row, against the wall) and the border's sides, a strip a row.
	var back := func(u: float, v: float) -> Vector3:
		return centre.call(v) + Vector3(u - 0.5, 0.0, 0.0) * W - out * T * 0.5
	for j in QUILT_Y:
		var v0 := float(j) / QUILT_Y
		var v1 := float(j + 1) / QUILT_Y
		var c: Color = col_at.call(0.5, (v0 + v1) * 0.5)
		_quad(st, back.call(0.0, v0), back.call(1.0, v0), back.call(1.0, v1), back.call(0.0, v1), -out, c, L)
		for u: float in [0.0, 1.0]:
			var side := Vector3(1.0 if u > 0.5 else -1.0, 0.0, 0.0)
			_quad(st, face.call(u, v0, 0.0), back.call(u, v0), back.call(u, v1), face.call(u, v1, 0.0), side, c, L)
		# The piping round the face's long edges.
		for u: float in [0.0, 1.0]:
			var e0: Vector3 = face.call(u, v0, 0.0)
			var e1: Vector3 = face.call(u, v1, 0.0)
			var side := Vector3(1.0 if u > 0.5 else -1.0, 0.0, 0.0)
			var e0b := e0 + side * 0.012 - out * 0.012
			var e1b := e1 + side * 0.012 - out * 0.012
			var e0f := e0 + out * 0.012
			var e1f := e1 + out * 0.012
			_quad(st, e0f, e0b, e1b, e1f, side + out, pipe, L)
	# The foot and the head: the border's ends, and the piping across them.
	for v: float in [0.0, 1.0]:
		var end := -up if v < 0.5 else up
		var c: Color = col_at.call(0.5, v)
		_quad(st, face.call(0.0, v, 0.0), face.call(1.0, v, 0.0), back.call(1.0, v), back.call(0.0, v), end, c, L)
		var a: Vector3 = face.call(0.0, v, 0.0) + out * 0.012
		var b: Vector3 = face.call(1.0, v, 0.0) + out * 0.012
		_quad(st, a, b, b + end * 0.016 - out * 0.016, a + end * 0.016 - out * 0.016, end + out, pipe, L)
	return true


## The back door's stoop (AlleyKit's footprint: 1.5 x 0.17 x 0.84, 0.42 out): worn concrete, a
## chipped nosing a shade darker, the grime lip where it meets the slab. Returns false when off.
static func stoop(st: SurfaceTool) -> bool:
	if not enabled:
		return false
	var tone := 0.9 + 0.2 * _here("stoop")
	AlleyKit._box(st, Vector3(0.0, 0.085, 0.41), Vector3(1.5, 0.17, 0.82), IndustrialKit.K_CONCRETE, STOOP_PAINT * tone)
	AlleyKit._box(st, Vector3(0.0, 0.075, 0.835), Vector3(1.48, 0.15, 0.03), IndustrialKit.K_CONCRETE, STOOP_PAINT * tone * 0.82)
	AlleyKit._box(st, Vector3(0.0, 0.012, 0.87), Vector3(1.56, 0.024, 0.07), IndustrialKit.K_CONCRETE, STOOP_GRIME)
	return true
