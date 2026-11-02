class_name BoatKit
extends RefCounted
## The player's boats as code-built meshes at real size (Boat, scripts/vehicles/boat.gd): the
## SALTRUNNER 24, a 7.4 m deep-V bowrider with an open cockpit, and the WAVEKITE, a 3.3 m
## three-seat personal watercraft. Both invented. They are written with BoatMesh's accumulator
## and hull sections (the marina's boats) and wear its shader in solo mode (boat.gdshader: what a
## vertex is in COLOR.a / 16, BoatMesh.Region; the hull's paint is `solo_paint`; no bobbing - the
## body rides the water itself).
##
## Body space: origin on the design waterline amidships, bow toward -Z, +X to starboard (the
## helm's side), Y up. Three levels (BoatMesh.Level), each its own MeshInstance3D faded by
## visibility range (Boat._build()).

enum Kind { SPEEDBOAT, JETSKI }

## [length, beam] of each kind (metres).
const SIZE := [Vector2(7.4, 2.55), Vector2(3.3, 1.2)]
## Where the driver's hips sit in body space (the helm's bucket seat, the front of the saddle).
const SEAT := [Vector3(0.6, 0.82, 0.56), Vector3(0.0, 0.93, 0.4)]
## Hand grips (body space): the handlebar's grips (the wheel is drawn round its own centre).
const GRIPS := [[Vector3(0.45, 1.1, -0.07), Vector3(0.75, 1.1, -0.07)], [Vector3(-0.33, 1.06, -0.4), Vector3(0.33, 1.06, -0.4)]]
## Accent colours (sRGB) of the hull graphic, by a hash of the boat.
const ACCENTS := [Color(0.05, 0.06, 0.08), Color(0.62, 0.05, 0.06), Color(0.04, 0.2, 0.45), Color(0.9, 0.42, 0.04), Color(0.0, 0.42, 0.43)]
const VINYL := Color(0.93, 0.92, 0.88)
const DARK := Color(0.05, 0.05, 0.06)

static var _cache: Dictionary = {}
static var _material: ShaderMaterial


## The mesh of `kind` at `level` with hull graphic accent `accent` (index into ACCENTS). Cached.
static func mesh(kind: int, level: int, accent: int) -> ArrayMesh:
	var key := Vector3i(kind, level, accent)
	if _cache.has(key):
		return _cache[key]
	var acc := BoatMesh.Acc.new()
	acc.level = level
	var ac: Color = ACCENTS[accent % ACCENTS.size()]
	if kind == Kind.JETSKI:
		_jetski(acc, ac)
	else:
		_speedboat(acc, ac)
	var m := acc.commit()
	_cache[key] = m
	return m


## The shared shader as a solo material of this paint and canvas index (Marina.CANVAS: the
## upholstery piping, the boot stripe), lit stern light on (flag 16).
static func material(paint: Color, canvas: int) -> ShaderMaterial:
	if _material == null:
		_material = MarinaBuild.boat_material().duplicate() as ShaderMaterial
		_material.set_shader_parameter("solo", 1.0)
	var m := _material.duplicate() as ShaderMaterial
	m.set_shader_parameter("solo_paint", Vector3(paint.r, paint.g, paint.b))
	m.set_shader_parameter("solo_flags", float(canvas % 6) + 16.0)
	return m


static func triangles(kind: int, level: int) -> int:
	return mesh(kind, level, 0).surface_get_array_index_len(0) / 3


# --- The hull -------------------------------------------------------------------------------------

static func _hull_of(kind: int) -> BoatMesh.Hull:
	var h := BoatMesh.Hull.new()
	var s: Vector2 = SIZE[kind]
	h.length = s.x
	h.beam = s.y
	if kind == Kind.JETSKI:
		h.fb_stern = 0.36
		h.fb_bow = 0.6
		h.depth = 0.3
		h.vee = 1.0
		h.transom = 0.86
		h.max_at = 0.4
		h.fine = 1.5
		h.flare = 0.05
		h.rake = 0.35
	else:
		h.fb_stern = 0.9
		h.fb_bow = 1.3
		h.depth = 0.52
		h.vee = 1.0
		h.transom = 0.9
		h.max_at = 0.34
		h.fine = 1.85
		h.flare = 0.12
		h.rake = 0.85
	return h


## A half-section at t (keel to sheer, starboard), a planing hull's: a straight run of deadrise
## out to a chine whose plan narrows to the bow faster than the deck's (a fine entry), the flared
## topsides from the chine to the sheer, and a stem raked well forward of its forefoot.
static func _section(h: BoatMesh.Hull, t: float, n: int) -> PackedVector3Array:
	var pts := PackedVector3Array()
	var b := BoatMesh._half_beam(h, t)
	var bc := b * 0.84
	if t > h.max_at:
		var u := (t - h.max_at) / (1.0 - h.max_at)
		bc = h.beam * 0.5 * 0.84 * pow(maxf(1.0 - pow(u, 1.25), 0.0), 1.05)
	var s := BoatMesh._sheer(h, t)
	var k := BoatMesh._keel(h, t)
	var z := BoatMesh._z(h, t)
	var cy := -k * 0.12 + 0.04
	var uc := 0.5
	for i in n:
		var u := float(i) / float(n - 1)
		var x: float
		var y: float
		if u <= uc:
			var w := u / uc
			# A little concave near the keel (the hollow of a deep V), straight to the chine.
			x = bc * w
			y = lerpf(-k, cy, w) - 0.04 * k * sin(w * PI)
		else:
			var w := (u - uc) / (1.0 - uc)
			x = lerpf(bc, b, pow(w, 0.55))
			y = lerpf(cy, s, w)
			x = lerpf(x * (1.0 - h.flare), x, w)
		var hf := clampf((y + k) / maxf(s + k, 0.01), 0.0, 1.0)
		var stem := 0.0
		if t > 0.68:
			stem = pow((t - 0.68) / 0.32, 1.6) * h.rake * pow(1.0 - hf, 1.4)
		pts.append(Vector3(x, y, z + stem))
	return pts


## The shell (both sides, the transom), lifting strakes on the bottom, the rubbing strake, and a
## hull graphic in `ac` sweeping up toward the bow. No deck: each kind lays its own.
static func _shell(acc: BoatMesh.Acc, h: BoatMesh.Hull, ac: Color) -> Array[PackedVector3Array]:
	var nt := [30, 14, 6][acc.level] as int
	var ns := [11, 7, 3][acc.level] as int
	var rows_r: Array[PackedVector3Array] = []
	var rows_l: Array[PackedVector3Array] = []
	for i in nt + 1:
		var t := float(i) / nt
		var sec := _section(h, t, ns)
		rows_r.append(sec)
		var m := PackedVector3Array()
		for p in sec:
			m.append(Vector3(-p.x, p.y, p.z))
		rows_l.append(m)
	# The bottom and the topsides as two grids, so the chine is a crisp edge (one grid averaged
	# its normals across it and the hull read as a soft tub).
	var ci := (ns - 1) / 2
	for rows: Array[PackedVector3Array] in [rows_r, rows_l]:
		var bottom: Array[PackedVector3Array] = []
		var top: Array[PackedVector3Array] = []
		for r in rows:
			bottom.append(r.slice(0, ci + 1))
			top.append(r.slice(ci))
		acc.grid(bottom, BoatMesh.WHITE, BoatMesh.Region.HULL, func(p: Vector3) -> Vector3: return Vector3(p.x, p.y - 0.3, 0.0))
		acc.grid(top, BoatMesh.WHITE, BoatMesh.Region.HULL, func(p: Vector3) -> Vector3: return Vector3(p.x, 0.0, 0.0))
	var tr := PackedVector3Array()
	var sec0 := rows_r[0]
	for i in range(sec0.size() - 1, -1, -1):
		tr.append(Vector3(-sec0[i].x, sec0[i].y, sec0[i].z))
	for i in sec0.size():
		tr.append(sec0[i])
	acc.fan(tr, BoatMesh.WHITE, BoatMesh.Region.HULL, Vector3(0.0, 0.0, 1.0))
	if acc.level == BoatMesh.Level.FAR:
		return rows_r
	# Lifting strakes: two a side, small steps along the bottom from the transom to the forefoot.
	for side: float in [-1.0, 1.0]:
		for u: float in [0.22, 0.42]:
			var a := PackedVector3Array()
			var b := PackedVector3Array()
			for i in nt + 1:
				var t := float(i) / nt
				if t > 0.78:
					break
				var sec := _section(h, t, 33)
				var p: Vector3 = sec[int(u * 32.0)]
				var q: Vector3 = sec[int(u * 32.0) + 1]
				var out := Vector3(side * p.x, p.y, p.z)
				a.append(out)
				b.append(out + (Vector3(side * (q.x - p.x), q.y - p.y, 0.0)).normalized() * 0.05 + Vector3(0.0, -0.025, 0.0))
			if a.size() > 2:
				acc.grid([a, b] as Array[PackedVector3Array], BoatMesh.WHITE, BoatMesh.Region.BOTTOM, func(_p: Vector3) -> Vector3: return Vector3(side * 0.3, -1.0, 0.0))
	# The rubbing strake (black rubber) and the hull graphic: a band below the sheer that dips
	# toward the stern and sweeps up and thins toward the bow.
	for side: float in [-1.0, 1.0]:
		var strake_a := PackedVector3Array()
		var strake_b := PackedVector3Array()
		var g_top := PackedVector3Array()
		var g_bot := PackedVector3Array()
		for i in nt + 1:
			var t := float(i) / nt
			var sr: Vector3 = rows_r[i][rows_r[i].size() - 1]
			strake_a.append(Vector3(side * (sr.x + 0.035), sr.y - 0.07, sr.z))
			strake_b.append(Vector3(side * (sr.x + 0.035), sr.y + 0.005, sr.z))
			if t > 0.03 and t < 0.86:
				var sec := rows_r[i]
				# The band rides the topside a little out from the shell (no z-fight).
				var drop := lerpf(0.42, 0.14, t) * (h.fb_bow / 1.18)
				var width := lerpf(0.16, 0.03, pow(t / 0.86, 1.4)) * (h.fb_bow / 1.18)
				var y0 := sr.y - drop
				g_top.append(_on_side(sec, y0 + width, side, 0.012))
				g_bot.append(_on_side(sec, y0, side, 0.012))
		acc.grid([strake_a, strake_b] as Array[PackedVector3Array], DARK, BoatMesh.Region.RUBBER, func(_p: Vector3) -> Vector3: return Vector3(side, 0.0, 0.0))
		if g_top.size() > 2:
			acc.grid([g_bot, g_top] as Array[PackedVector3Array], ac, BoatMesh.Region.GELCOAT, func(_p: Vector3) -> Vector3: return Vector3(side, 0.15, 0.0))
	return rows_r


## The point on a section (starboard half, keel to sheer) at height y, on side `side`, pushed
## `out` metres off the shell.
static func _on_side(sec: PackedVector3Array, y: float, side: float, out: float) -> Vector3:
	for j in range(sec.size() - 1, 0, -1):
		var a: Vector3 = sec[j - 1]
		var b: Vector3 = sec[j]
		if (a.y <= y and b.y >= y) or j == 1:
			var f := clampf((y - a.y) / maxf(b.y - a.y, 0.0001), 0.0, 1.0)
			var p := a.lerp(b, f)
			return Vector3(side * (p.x + out), p.y, p.z)
	return Vector3(side * sec[sec.size() - 1].x, y, sec[0].z)


## A deck at the sheer between t0 and t1 (camber), inset `inset` from the shell, raised `lift`.
static func _deck(acc: BoatMesh.Acc, h: BoatMesh.Hull, t0: float, t1: float, inset: float, lift: float, col: Color, region: int, steps: int) -> void:
	var rows: Array[PackedVector3Array] = []
	for i in steps + 1:
		var t := lerpf(t0, t1, float(i) / steps)
		var b := maxf(BoatMesh._half_beam(h, t) - inset, 0.0)
		var y := BoatMesh._sheer(h, t) + lift
		var row := PackedVector3Array()
		for j in 5:
			var w := float(j) / 4.0
			var camber := 0.035 * h.beam * (1.0 - pow(2.0 * w - 1.0, 2.0))
			row.append(Vector3(lerpf(-b, b, w), y + camber, BoatMesh._z(h, t)))
		rows.append(row)
	acc.grid(rows, col, region, func(_p: Vector3) -> Vector3: return Vector3.UP)


## A rounded block (a seat cushion, a bolster): a box with its top edges rolled `r` metres.
static func _cushion(acc: BoatMesh.Acc, xf: Transform3D, size: Vector3, r: float, col: Color, region: int) -> void:
	if acc.level == BoatMesh.Level.FAR:
		acc.box(xf, size, col, region)
		return
	var hx := size.x * 0.5
	var hz := size.z * 0.5
	var steps := 4 if acc.level == BoatMesh.Level.NEAR else 2
	# Rings of the plan outline (a rectangle) from the base up over the rolled top edge.
	var rings: Array[PackedVector3Array] = []
	var profile: Array[Vector2] = [Vector2(0.0, -size.y * 0.5)]
	for k in steps + 1:
		var a := float(k) / steps * PI * 0.5
		profile.append(Vector2(r * (1.0 - cos(a)), size.y * 0.5 - r + r * sin(a)))
	for pr: Vector2 in profile:
		var ring := PackedVector3Array()
		var ex := maxf(hx - pr.x, 0.01)
		var ez := maxf(hz - pr.x, 0.01)
		for c in 4:
			var sx := 1.0 if c == 0 or c == 1 else -1.0
			var sz := 1.0 if c == 1 or c == 2 else -1.0
			ring.append(xf * Vector3(sx * ex, pr.y, sz * ez))
		ring.append(ring[0])
		rings.append(ring)
	var centre := xf.origin
	acc.grid(rings, col, region, func(p: Vector3) -> Vector3: return (p - centre))
	var top := rings[rings.size() - 1]
	acc.fan(PackedVector3Array([top[0], top[1], top[2], top[3]]), col, region, xf.basis.y)


## A ring (a steering wheel's rim) of `segs` tube pieces about `c` in the plane normal to `axis`.
static func _ring(acc: BoatMesh.Acc, c: Vector3, axis: Vector3, radius: float, thick: float, segs: int, col: Color, region: int) -> void:
	var a := axis.normalized()
	var u := a.cross(Vector3.UP if absf(a.y) < 0.9 else Vector3.RIGHT).normalized()
	var v := a.cross(u).normalized()
	for i in segs:
		var p0 := c + (u * cos(TAU * i / segs) + v * sin(TAU * i / segs)) * radius
		var p1 := c + (u * cos(TAU * (i + 1) / segs) + v * sin(TAU * (i + 1) / segs)) * radius
		acc.tube(p0, p1, thick, thick, 5 if acc.level == BoatMesh.Level.NEAR else 3, col, region)


# --- SALTRUNNER 24 --------------------------------------------------------------------------------

static func _speedboat(acc: BoatMesh.Acc, ac: Color) -> void:
	var h := _hull_of(Kind.SPEEDBOAT)
	var rows := _shell(acc, h, ac)
	var near := acc.level == BoatMesh.Level.NEAR
	var far := acc.level == BoatMesh.Level.FAR
	var gw := 0.24 # the gunwale's width
	var t_aft := 0.14 # the engine box / sun pad, aft of the cockpit
	var t_fore := 0.6 # the windscreen and the foredeck forward of it
	var sole := 0.18 # the cockpit floor over the waterline
	# Foredeck and the sun pad deck over the engine.
	_deck(acc, h, t_fore, 1.0, 0.0, 0.0, BoatMesh.DECK_WHITE, BoatMesh.Region.DECK, [10, 5, 2][acc.level])
	_deck(acc, h, 0.0, t_aft, 0.0, -0.16, BoatMesh.DECK_WHITE, BoatMesh.Region.DECK, 2)
	if far:
		_deck(acc, h, t_aft, t_fore, 0.0, -0.5, BoatMesh.DECK_WHITE, BoatMesh.Region.DECK, 2)
	else:
		# The open cockpit: gunwales, the inner liner down to the sole, the sole, the bulkheads.
		var steps := [10, 5, 2][acc.level] as int
		for side: float in [-1.0, 1.0]:
			var top_out := PackedVector3Array()
			var top_in := PackedVector3Array()
			var low_in := PackedVector3Array()
			for i in steps + 1:
				var t := lerpf(t_aft, t_fore, float(i) / steps)
				var b := BoatMesh._half_beam(h, t)
				var y := BoatMesh._sheer(h, t)
				var z := BoatMesh._z(h, t)
				top_out.append(Vector3(side * b, y, z))
				top_in.append(Vector3(side * (b - gw), y + 0.02, z))
				low_in.append(Vector3(side * (b - gw - 0.06), sole, z))
			acc.grid([top_out, top_in] as Array[PackedVector3Array], BoatMesh.DECK_WHITE, BoatMesh.Region.DECK, func(_p: Vector3) -> Vector3: return Vector3.UP)
			acc.grid([top_in, low_in] as Array[PackedVector3Array], BoatMesh.OFFWHITE, BoatMesh.Region.GELCOAT, func(_p: Vector3) -> Vector3: return Vector3(-side, 0.2, 0.0))
			# Side bolsters on the liner (vinyl).
			if near:
				var zc := BoatMesh._z(h, 0.33)
				var bx := BoatMesh._half_beam(h, 0.33) - gw - 0.1
				_cushion(acc, Transform3D(Basis(Vector3.FORWARD, side * 0.1), Vector3(side * bx, BoatMesh._sheer(h, 0.33) - 0.33, zc)), Vector3(0.12, 0.34, 2.2), 0.05, VINYL, BoatMesh.Region.RUBBER)
		var sole_rows: Array[PackedVector3Array] = []
		for i in steps + 1:
			var t := lerpf(t_aft, t_fore, float(i) / steps)
			var b := BoatMesh._half_beam(h, t) - gw - 0.06
			sole_rows.append(PackedVector3Array([Vector3(-b, sole, BoatMesh._z(h, t)), Vector3(0.0, sole, BoatMesh._z(h, t)), Vector3(b, sole, BoatMesh._z(h, t))]))
		acc.grid(sole_rows, Color(0.72, 0.7, 0.66), BoatMesh.Region.DECK, func(_p: Vector3) -> Vector3: return Vector3.UP)
		for e: Array in [[t_aft, 1.0, -0.16], [t_fore, -1.0, 0.0]]:
			var t: float = e[0]
			var b := BoatMesh._half_beam(h, t) - gw
			var y := BoatMesh._sheer(h, t) + float(e[2])
			var z := BoatMesh._z(h, t)
			acc.quad(Vector3(-b, sole, z), Vector3(b, sole, z), Vector3(b, y, z), Vector3(-b, y, z), BoatMesh.OFFWHITE, BoatMesh.Region.GELCOAT, Vector3(0.0, 0.0, -float(e[1])))
	var cy := BoatMesh._sheer(h, 0.4)
	# Swim platform (teak), the transom's boarding ladder, the sterndrive leg and its prop.
	var tz := BoatMesh._z(h, 0.0)
	var tb := BoatMesh._half_beam(h, 0.0)
	acc.box(Transform3D(Basis(), Vector3(0.0, 0.26, tz + 0.36)), Vector3(tb * 1.9, 0.07, 0.72), Color(0.6, 0.42, 0.25), BoatMesh.Region.TEAK)
	acc.box(Transform3D(Basis(Vector3.RIGHT, 0.32), Vector3(0.0, -0.15, tz + 0.42)), Vector3(0.16, 0.7, 0.42), DARK, BoatMesh.Region.ENGINE)
	acc.box(Transform3D(Basis(), Vector3(0.0, -0.5, tz + 0.55)), Vector3(0.22, 0.2, 0.55), DARK, BoatMesh.Region.ENGINE)
	if not far:
		var hub := Vector3(0.0, -0.5, tz + 0.88)
		acc.tube(hub - Vector3(0, 0, 0.08), hub + Vector3(0, 0, 0.1), 0.06, 0.03, 6, BoatMesh.STEEL, BoatMesh.Region.METAL)
		for k in 3:
			var a := TAU * k / 3.0
			var d := Vector3(cos(a), sin(a), 0.0)
			var d2 := Vector3(cos(a + 0.9), sin(a + 0.9), 0.0)
			acc.tri(hub, hub + d * 0.2 + Vector3(0, 0, 0.04), hub + d2 * 0.19 - Vector3(0, 0, 0.04), BoatMesh.STEEL, BoatMesh.Region.METAL, Vector3(0, 0, 1))
		for side: float in [-0.35, 0.35]:
			acc.tube(Vector3(side, 0.3, tz + 0.7), Vector3(side, 0.85, tz + 0.08), 0.018, 0.018, 4, BoatMesh.STEEL, BoatMesh.Region.METAL)
	# The sun pad: cushions on the engine box, and the bench across the aft bulkhead.
	var pad_y := BoatMesh._sheer(h, 0.07) - 0.16
	_cushion(acc, Transform3D(Basis(), Vector3(0.0, pad_y + 0.06, BoatMesh._z(h, 0.07))), Vector3(tb * 1.6, 0.12, 0.85), 0.04, VINYL, BoatMesh.Region.RUBBER)
	if not far:
		var bz := BoatMesh._z(h, t_aft) - 0.3
		var bw := BoatMesh._half_beam(h, t_aft + 0.03) - gw - 0.1
		_cushion(acc, Transform3D(Basis(), Vector3(0.0, sole + 0.22, bz)), Vector3(bw * 2.0, 0.44, 0.52), 0.06, VINYL, BoatMesh.Region.RUBBER)
		_cushion(acc, Transform3D(Basis(Vector3.RIGHT, -0.18), Vector3(0.0, sole + 0.62, bz + 0.25)), Vector3(bw * 2.0, 0.42, 0.12), 0.05, VINYL, BoatMesh.Region.RUBBER)
	# The helm (starboard) and the passenger's console, the windscreen across them.
	var wz := BoatMesh._z(h, t_fore)
	var console_z := wz + 0.35
	for side: float in [-1.0, 1.0]:
		var cx := side * 0.6
		if far:
			acc.box(Transform3D(Basis(), Vector3(cx, (sole + cy) * 0.5, console_z)), Vector3(0.7, cy - sole, 0.6), BoatMesh.WHITE, BoatMesh.Region.GELCOAT)
			continue
		acc.box(Transform3D(Basis(), Vector3(cx, (sole + cy - 0.05) * 0.5, console_z - 0.05)), Vector3(0.72, cy - 0.05 - sole, 0.62), BoatMesh.WHITE, BoatMesh.Region.GELCOAT)
		# The dash: a raked top, dark, gauges on the helm's.
		acc.quad(Vector3(cx - 0.36, cy - 0.05, console_z + 0.26), Vector3(cx + 0.36, cy - 0.05, console_z + 0.26), Vector3(cx + 0.34, cy + 0.12, console_z - 0.3), Vector3(cx - 0.34, cy + 0.12, console_z - 0.3), DARK, BoatMesh.Region.RUBBER, Vector3(0.0, 1.0, 0.45))
		if side > 0.0 and near:
			for g in 3:
				acc.octa(Vector3(cx - 0.18 + g * 0.18, cy + 0.05, console_z - 0.06), 0.045, Color(0.1, 0.12, 0.14), BoatMesh.Region.GLASS)
			# The wheel: a rim on a raked column, three spokes.
			var wc := Vector3(cx, cy + 0.08, console_z + 0.32)
			var axis := Vector3(0.0, 0.55, 1.0).normalized()
			_ring(acc, wc, axis, 0.19, 0.016, 16, DARK, BoatMesh.Region.RUBBER)
			acc.tube(wc - axis * 0.2, wc, 0.025, 0.03, 6, BoatMesh.STEEL, BoatMesh.Region.METAL)
			for k in 3:
				var a := TAU * k / 3.0 + PI * 0.5
				var u := axis.cross(Vector3.UP).normalized()
				var v := axis.cross(u).normalized()
				acc.tube(wc, wc + (u * cos(a) + v * sin(a)) * 0.18, 0.012, 0.012, 4, BoatMesh.STEEL, BoatMesh.Region.METAL)
			# Throttle lever on the gunwale side.
			acc.tube(Vector3(cx + 0.42, cy - 0.05, console_z + 0.2), Vector3(cx + 0.44, cy + 0.18, console_z + 0.1), 0.015, 0.015, 4, BoatMesh.STEEL, BoatMesh.Region.METAL)
			acc.octa(Vector3(cx + 0.44, cy + 0.2, console_z + 0.09), 0.03, DARK, BoatMesh.Region.ENGINE)
		# Bucket seats behind the consoles: a base, a seat, a back.
		var sz := console_z + 0.95
		acc.box(Transform3D(Basis(), Vector3(cx, sole + 0.2, sz)), Vector3(0.36, 0.4, 0.36), BoatMesh.OFFWHITE, BoatMesh.Region.GELCOAT)
		_cushion(acc, Transform3D(Basis(), Vector3(cx, sole + 0.47, sz)), Vector3(0.58, 0.14, 0.55), 0.05, VINYL, BoatMesh.Region.RUBBER)
		_cushion(acc, Transform3D(Basis(Vector3.RIGHT, -0.22), Vector3(cx, sole + 0.84, sz + 0.3)), Vector3(0.56, 0.62, 0.13), 0.05, VINYL, BoatMesh.Region.RUBBER)
		if near:
			# Piping in the canvas colour along the seat back's top.
			acc.box(Transform3D(Basis(Vector3.RIGHT, -0.22), Vector3(cx, sole + 1.16, sz + 0.37)), Vector3(0.5, 0.03, 0.14), BoatMesh.WHITE, BoatMesh.Region.CANVAS)
	# Windscreen: three raked panes wrapping round to the gunwales, a chrome top rail.
	var ww := BoatMesh._half_beam(h, t_fore) - 0.05
	var rake := 0.42
	var wh := 0.46
	var pts := [Vector3(-ww, cy, wz + 0.35), Vector3(-0.55, cy + 0.02, wz), Vector3(0.55, cy + 0.02, wz), Vector3(ww, cy, wz + 0.35)]
	for k in 3:
		var a: Vector3 = pts[k]
		var b: Vector3 = pts[k + 1]
		var a2 := a + Vector3(0.0, wh, rake) - Vector3(signf(a.x) * 0.06 if k != 1 else 0.0, 0.0, 0.0)
		var b2 := b + Vector3(0.0, wh, rake) - Vector3(signf(b.x) * 0.06 if k != 1 else 0.0, 0.0, 0.0)
		var out := (a + b) * 0.5 - Vector3(0.0, cy, wz + 0.6)
		acc.quad(a, b, b2, a2, BoatMesh.GLASS_TINT, BoatMesh.Region.GLASS, Vector3(out.x, 0.3, out.z))
		if not far:
			acc.tube(a2, b2, 0.015, 0.015, 4, BoatMesh.STEEL, BoatMesh.Region.METAL)
			acc.tube(a, a2, 0.012, 0.012, 4, BoatMesh.STEEL, BoatMesh.Region.METAL)
	# Bow rails, cleats, the nav lights at the bow, the stern light on its pole.
	if not far:
		for side: float in [-1.0, 1.0]:
			var prev := Vector3.ZERO
			for k in 5:
				var t := lerpf(0.72, 0.97, k / 4.0)
				var p := BoatMesh._sheer_point(h, t, side, 0.08) + Vector3(0.0, 0.32, 0.0)
				acc.tube(p - Vector3(0.0, 0.32, 0.0), p, 0.012, 0.012, 4, BoatMesh.STEEL, BoatMesh.Region.METAL)
				if k > 0:
					acc.tube(prev, p, 0.013, 0.013, 4, BoatMesh.STEEL, BoatMesh.Region.METAL)
				prev = p
			var nav := BoatMesh._sheer_point(h, 0.9, side, 0.02) + Vector3(0.0, 0.04, 0.0)
			acc.octa(nav, 0.035, Color(0.75, 0.05, 0.04) if side < 0.0 else Color(0.05, 0.6, 0.15), BoatMesh.Region.GLASS)
			for t: float in [0.1, 0.75]:
				acc.box(Transform3D(Basis(), BoatMesh._sheer_point(h, t, side, 0.12) + Vector3(0, 0.03, 0)), Vector3(0.04, 0.05, 0.2), BoatMesh.STEEL, BoatMesh.Region.METAL)
		var pole := Vector3(-tb + 0.3, BoatMesh._sheer(h, 0.02), tz - 0.15)
		acc.tube(pole, pole + Vector3(0.0, 0.85, 0.0), 0.012, 0.012, 4, BoatMesh.STEEL, BoatMesh.Region.METAL)
		acc.octa(pole + Vector3(0.0, 0.9, 0.0), 0.04, Color.WHITE, BoatMesh.Region.LIGHT)


# --- WAVEKITE --------------------------------------------------------------------------------------

static func _jetski(acc: BoatMesh.Acc, ac: Color) -> void:
	var h := _hull_of(Kind.JETSKI)
	_shell(acc, h, ac)
	var far := acc.level == BoatMesh.Level.FAR
	var near := acc.level == BoatMesh.Level.NEAR
	# The footwell tray at the sheer, non-skid mats in it.
	_deck(acc, h, 0.0, 0.92, 0.0, 0.0, Color(0.16, 0.17, 0.18), BoatMesh.Region.DECK, [10, 5, 2][acc.level])
	# The upper deck: one loft from the transom to the bow, a rounded section whose width and
	# height follow the seat, the steering pod and the hood. [t, half width, height over sheer].
	var keys := [[0.0, 0.3, 0.2], [0.06, 0.32, 0.36], [0.14, 0.24, 0.42], [0.46, 0.22, 0.45], [0.52, 0.3, 0.46],
		[0.6, 0.42, 0.58], [0.68, 0.46, 0.55], [0.82, 0.38, 0.42], [0.93, 0.22, 0.26], [1.0, 0.02, 0.06]]
	var nt := [26, 12, 6][acc.level] as int
	var nu := [9, 5, 3][acc.level] as int
	var rows: Array[PackedVector3Array] = []
	for i in nt + 1:
		var t := float(i) / nt
		var k := 0
		while k < keys.size() - 2 and t > float(keys[k + 1][0]):
			k += 1
		var a: Array = keys[k]
		var b: Array = keys[k + 1]
		var f := clampf((t - float(a[0])) / (float(b[0]) - float(a[0])), 0.0, 1.0)
		f = f * f * (3.0 - 2.0 * f)
		var hw := minf(lerpf(float(a[1]), float(b[1]), f), BoatMesh._half_beam(h, t) * 0.92)
		var ht := lerpf(float(a[2]), float(b[2]), f)
		var y0 := BoatMesh._sheer(h, t) - 0.02
		var z := BoatMesh._z(h, t)
		var row := PackedVector3Array()
		for j in nu * 2 + 1:
			var ang := PI * float(j) / float(nu * 2)
			var cx := -cos(ang)
			var sy := pow(sin(ang), 0.45)
			row.append(Vector3(hw * signf(cx) * pow(absf(cx), 0.7), y0 + ht * sy, z))
		rows.append(row)
	acc.grid(rows, BoatMesh.WHITE, BoatMesh.Region.HULL, func(p: Vector3) -> Vector3: return Vector3(p.x, 0.6, 0.0))
	# The saddle: three cushions in a row (driver, two passengers), the accent piping, a grab strap.
	var seat_y := BoatMesh._sheer(h, 0.3) + 0.38
	_cushion(acc, Transform3D(Basis(Vector3.RIGHT, 0.04), Vector3(0.0, seat_y, BoatMesh._z(h, 0.3))), Vector3(0.44, 0.16, 1.18), 0.07, DARK, BoatMesh.Region.RUBBER)
	if not far:
		acc.box(Transform3D(Basis(), Vector3(0.0, seat_y + 0.085, BoatMesh._z(h, 0.33))), Vector3(0.06, 0.02, 0.95), ac, BoatMesh.Region.GELCOAT)
		acc.tube(Vector3(-0.2, seat_y + 0.1, BoatMesh._z(h, 0.18)), Vector3(0.2, seat_y + 0.1, BoatMesh._z(h, 0.18)), 0.02, 0.02, 4, DARK, BoatMesh.Region.RUBBER)
	# The handlebar on its pod, grips, throttle lever, mirrors, a smoked visor over the gauges.
	var pz := BoatMesh._z(h, 0.55)
	var py := BoatMesh._sheer(h, 0.55) + 0.5
	acc.box(Transform3D(Basis(Vector3.RIGHT, -0.5), Vector3(0.0, py + 0.08, pz + 0.05)), Vector3(0.2, 0.22, 0.16), DARK, BoatMesh.Region.ENGINE)
	var g0: Vector3 = GRIPS[Kind.JETSKI][0]
	var g1: Vector3 = GRIPS[Kind.JETSKI][1]
	acc.tube(Vector3(g0.x + 0.05, g0.y, g0.z), Vector3(g1.x - 0.05, g1.y, g1.z), 0.016, 0.016, 5, BoatMesh.STEEL, BoatMesh.Region.METAL)
	for g: Vector3 in [g0, g1]:
		acc.tube(g - Vector3(signf(g.x) * 0.06, 0.0, 0.0), g + Vector3(signf(g.x) * 0.06, 0.0, 0.0), 0.022, 0.022, 6, DARK, BoatMesh.Region.RUBBER)
	if not far:
		acc.tube(Vector3(0.0, py + 0.05, pz + 0.05), Vector3(0.0, g0.y, g0.z), 0.03, 0.025, 5, DARK, BoatMesh.Region.ENGINE)
		acc.quad(Vector3(-0.24, py + 0.12, pz - 0.18), Vector3(0.24, py + 0.12, pz - 0.18), Vector3(0.2, py + 0.3, pz - 0.05), Vector3(-0.2, py + 0.3, pz - 0.05), BoatMesh.GLASS_TINT, BoatMesh.Region.GLASS, Vector3(0.0, 0.6, -1.0))
		for side: float in [-1.0, 1.0]:
			var mb := Vector3(side * 0.3, py + 0.1, pz - 0.12)
			acc.tube(mb, mb + Vector3(side * 0.08, 0.1, 0.0), 0.01, 0.01, 4, DARK, BoatMesh.Region.RUBBER)
			acc.box(Transform3D(Basis(), mb + Vector3(side * 0.11, 0.13, 0.0)), Vector3(0.12, 0.07, 0.02), DARK, BoatMesh.Region.ENGINE)
	# The pump's nozzle under the stern, the ride plate, sponsons, the tow eye.
	var tz := BoatMesh._z(h, 0.0)
	acc.tube(Vector3(0.0, -0.12, tz - 0.25), Vector3(0.0, -0.1, tz + 0.12), 0.11, 0.09, 8 if near else 5, DARK, BoatMesh.Region.ENGINE)
	acc.box(Transform3D(Basis(), Vector3(0.0, -0.24, tz - 0.12)), Vector3(0.42, 0.02, 0.4), BoatMesh.ALU, BoatMesh.Region.METAL)
	if not far:
		for side: float in [-1.0, 1.0]:
			acc.box(Transform3D(Basis(Vector3.FORWARD, side * 0.3), Vector3(side * 0.56, 0.05, tz - 0.35)), Vector3(0.05, 0.14, 0.42), DARK, BoatMesh.Region.RUBBER)
		acc.tube(Vector3(0.0, 0.33, tz + 0.02), Vector3(0.0, 0.33, tz + 0.12), 0.03, 0.03, 4, BoatMesh.STEEL, BoatMesh.Region.METAL)
		# A reboarding step on the transom.
		acc.box(Transform3D(Basis(), Vector3(0.0, 0.08, tz + 0.1)), Vector3(0.3, 0.03, 0.16), DARK, BoatMesh.Region.RUBBER)
