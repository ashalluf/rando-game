class_name BoatMesh
extends RefCounted
## The marina's boats, built in code at real size (Marina, MarinaBuild): a sailboat (masthead
## sloop, furled main under its cover on the boom, roller-furled jib, standing rigging, pulpits and
## lifelines; variant 1 adds a dodger and a bimini), a flybridge motor yacht (variant 1 an express
## cruiser under a raked hardtop), a sport-fishing boat (flybridge over a forward cabin, open
## cockpit; variant 1 a tuna tower and outriggers) and a runabout (a bowrider; variant 1 a centre
## console under a T-top).
##
## Frame: metres, the bow toward -Z (Godot's forward), the stern +Z, the waterline at y 0, the
## centre line x 0. Each type is built at Marina.REF_LEN and scaled to a boat's length.
##
## Per vertex: COLOR.rgb the part's colour (sRGB, as written), COLOR.a its region / 16 (REGION_*,
## shaders/boat.gdshader paints by it: the hull takes the boat's paint, the canvas its canvas
## colour, glass lights at night); UV metres along the part (the deck's non-skid, the teak). Three
## levels: NEAR (everything, ~2-4k triangles), MID (no lifelines or thin lines but the stays,
## coarser hull, ~0.6-1k), FAR (a few boxes and the mast, ~60-150).

enum Region { HULL, BOTTOM, DECK, GELCOAT, GLASS, METAL, CANVAS, TEAK, LIGHT, RUBBER, SAIL, ENGINE }
enum Level { NEAR, MID, FAR }

const WHITE := Color(0.93, 0.93, 0.92)
const OFFWHITE := Color(0.88, 0.87, 0.84)
const DECK_WHITE := Color(0.86, 0.86, 0.83)
const GLASS_TINT := Color(0.06, 0.08, 0.1)
const STEEL := Color(0.78, 0.79, 0.8)
const ALU := Color(0.72, 0.73, 0.75)
const TEAK_C := Color(0.55, 0.38, 0.22)
const BLACK := Color(0.06, 0.06, 0.065)
const SAILCLOTH := Color(0.9, 0.89, 0.85)

static var _cache: Dictionary = {}


## The mesh of `type` (Marina.Type), variant 0 / 1, at `level` (Level). Cached.
static func mesh(type: int, variant: int, level: int) -> ArrayMesh:
	var key := Vector3i(type, variant, level)
	if _cache.has(key):
		return _cache[key]
	var acc := Acc.new()
	acc.level = level
	match type:
		Marina.Type.SAIL:
			_sailboat(acc, variant)
		Marina.Type.MOTOR:
			_motor_yacht(acc, variant)
		Marina.Type.FISHER:
			_sport_fisher(acc, variant)
		_:
			_runabout(acc, variant)
	var m := acc.commit()
	_cache[key] = m
	return m


## A box round a boat's hull for collision (centre, size) at reference size.
static func hull_box(type: int) -> Array:
	var length: float = Marina.REF_LEN[type]
	var beam := Marina._beam(type, length)
	var fb := [1.1, 1.8, 1.7, 0.85][type] as float
	return [Vector3(0.0, fb * 0.5 - 0.15, 0.0), Vector3(beam * 0.92, fb + 0.3, length * 0.92)]


## Height of the type's highest point over the water (mast tip, tower top) at reference size.
static func air_draft(type: int, variant: int) -> float:
	match type:
		Marina.Type.SAIL:
			return 1.1 + (14.6 if variant == 0 else 13.6)
		Marina.Type.MOTOR:
			return 6.4 if variant == 0 else 4.1
		Marina.Type.FISHER:
			return 8.2 if variant == 1 else 5.6
	return 2.2


# --- Hull -----------------------------------------------------------------------------------------

## Hull parameters: length, beam, freeboard at the stern and the bow, canoe body depth, the
## section's shape (deadrise 0 round bilge .. 1 deep V), bow fineness, transom width share,
## where the beam is widest (0 stern .. 1 bow), and how far the stern is cut short of the length.
class Hull:
	var length := 10.0
	var beam := 3.4
	var fb_stern := 1.0
	var fb_bow := 1.35
	var depth := 0.6
	var vee := 0.0
	var fine := 1.6
	var transom := 0.82
	var max_at := 0.42
	var flare := 0.08
	var rake := 0.9


## Half-beam at the sheer at t (0 stern .. 1 bow).
static func _half_beam(h: Hull, t: float) -> float:
	var b := h.beam * 0.5
	if t <= h.max_at:
		var u := t / h.max_at
		return b * lerpf(h.transom, 1.0, 1.0 - pow(1.0 - u, 2.0))
	var u := (t - h.max_at) / (1.0 - h.max_at)
	return b * pow(maxf(1.0 - pow(u, h.fine), 0.0), 0.62)


static func _sheer(h: Hull, t: float) -> float:
	return lerpf(h.fb_stern, h.fb_bow, t * t * 0.85 + t * 0.15)


static func _keel(h: Hull, t: float) -> float:
	# The canoe body's depth: shallow at the transom, deepest amidships, rising to the forefoot.
	var d := h.depth * (0.55 + 0.45 * sin(clampf(t, 0.0, 1.0) * PI * 0.85 + 0.25))
	if t > 0.8:
		d *= lerpf(1.0, 0.1, (t - 0.8) / 0.2)
	return d


static func _z(h: Hull, t: float) -> float:
	return h.length * (0.5 - t)


## One half-section at t, from the keel (centre line) up to the sheer: `n` points (x >= 0).
static func _section(h: Hull, t: float, n: int) -> PackedVector3Array:
	var pts := PackedVector3Array()
	var b := _half_beam(h, t)
	var s := _sheer(h, t)
	var k := _keel(h, t)
	var z := _z(h, t)
	# At the bow the stem rakes forward as it rises (the stem's foot is aft of its head).
	var stem := 0.0
	if t > 0.85:
		stem = (t - 0.85) / 0.15
	for i in n:
		var u := float(i) / float(n - 1)
		var x: float
		var y: float
		# Deep V: a straight run of deadrise to the chine at 60 %, then the flared topsides.
		var xv: float
		var yv: float
		var uc := 0.58
		if u <= uc:
			var w := u / uc
			xv = b * 0.9 * w
			yv = lerpf(-k, -k * 0.12 + 0.05, w)
		else:
			var w := (u - uc) / (1.0 - uc)
			xv = lerpf(b * 0.9, b, pow(w, 0.6))
			yv = lerpf(-k * 0.12 + 0.05, s, w)
		# Round bilge: a quarter superellipse.
		var a := u * PI * 0.5
		var xr := b * pow(sin(a), 0.7)
		var yr := lerpf(-k, s, 1.0 - pow(cos(a), 1.6))
		x = lerpf(xr, xv, h.vee)
		y = lerpf(yr, yv, h.vee)
		# Topside flare: the sheer stands out a little past the waterline's beam.
		if y > 0.0:
			x = lerpf(x * (1.0 - h.flare), x, clampf(y / maxf(s, 0.1), 0.0, 1.0))
		pts.append(Vector3(x, y, z - stem * h.rake * clampf((y + k) / (s + k), 0.0, 1.0) * 0.6))
	return pts


## The hull shell, both sides, the transom, the deck at the sheer, a rubbing strake.
static func _hull(acc: Acc, h: Hull, deck_col: Color = DECK_WHITE, bulwark := 0.0) -> void:
	var nt := [26, 12, 6][acc.level] as int
	var ns := [9, 6, 3][acc.level] as int
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
	# Hull: paint above the waterline, bottom below - split by region per vertex is not possible
	# in one grid, so the shader splits by height (REGION_HULL draws the antifouling under y 0).
	acc.grid(rows_r, WHITE, Region.HULL, func(p: Vector3) -> Vector3: return Vector3(p.x, p.y - 0.3, 0.0))
	acc.grid(rows_l, WHITE, Region.HULL, func(p: Vector3) -> Vector3: return Vector3(p.x, p.y - 0.3, 0.0))
	# Transom: the stern section filled, facing aft.
	var tr := PackedVector3Array()
	var sec0 := rows_r[0]
	for i in range(sec0.size() - 1, -1, -1):
		tr.append(Vector3(-sec0[i].x, sec0[i].y, sec0[i].z))
	for i in sec0.size():
		tr.append(sec0[i])
	acc.fan(tr, WHITE, Region.HULL, Vector3(0.0, 0.0, 1.0))
	# Deck: across the sheer at each station, a little camber.
	var deck_rows: Array[PackedVector3Array] = []
	for i in nt + 1:
		var sr: Vector3 = rows_r[i][ns - 1]
		var row := PackedVector3Array()
		for j in 5:
			var w := float(j) / 4.0
			var x := lerpf(-sr.x, sr.x, w)
			var camber := 0.04 * h.beam * (1.0 - pow(2.0 * w - 1.0, 2.0))
			row.append(Vector3(x, sr.y + camber, sr.z))
		deck_rows.append(row)
	acc.grid(deck_rows, deck_col, Region.DECK, func(_p: Vector3) -> Vector3: return Vector3.UP)
	# Rubbing strake and toe rail along the sheer.
	if acc.level != Level.FAR:
		for side: float in [-1.0, 1.0]:
			var strake := PackedVector3Array()
			var top := PackedVector3Array()
			var lip := PackedVector3Array()
			for i in nt + 1:
				var sr: Vector3 = rows_r[i][ns - 1]
				strake.append(Vector3(side * (sr.x + 0.04), sr.y - 0.12, sr.z))
				top.append(Vector3(side * (sr.x + 0.04), sr.y + 0.01, sr.z))
				lip.append(Vector3(side * (sr.x - 0.02), sr.y + 0.06 + bulwark, sr.z))
			acc.grid([strake, top] as Array[PackedVector3Array], OFFWHITE, Region.GELCOAT, func(_p: Vector3) -> Vector3: return Vector3(side, 0.0, 0.0))
			acc.grid([PackedVector3Array(top), lip] as Array[PackedVector3Array], STEEL if bulwark < 0.05 else WHITE, Region.METAL if bulwark < 0.05 else Region.GELCOAT, func(_p: Vector3) -> Vector3: return Vector3(side, 0.3, 0.0))


## Point on the sheer at t, side +-1.
static func _sheer_point(h: Hull, t: float, side: float, inset := 0.0) -> Vector3:
	return Vector3(side * maxf(_half_beam(h, t) - inset, 0.0), _sheer(h, t), _z(h, t))


# --- Superstructure helpers ---------------------------------------------------------------------

## A cabin: a frustum from deck height `y0` to `y0 + height` between t0 (aft) and t1 (fore),
## `w0` wide at the base (fraction of the beam there), sides leaning in by `tumble`, its front
## raked back by `rake` metres; a band of windows on the sides and the front.
static func _cabin(acc: Acc, h: Hull, t0: float, t1: float, y0: float, height: float, w_frac: float, rake: float, tumble: float, win: Vector2, col: Color = WHITE, front_win := true) -> void:
	var za := _z(h, t0)
	var zf := _z(h, t1)
	var wa := _half_beam(h, t0) * w_frac
	var wf := _half_beam(h, t1) * w_frac
	var y1 := y0 + height
	# Base and top corner rings: aft-left, aft-right, fore-right, fore-left.
	var base := [Vector3(-wa, y0, za), Vector3(wa, y0, za), Vector3(wf, y0, zf), Vector3(-wf, y0, zf)]
	var top := [Vector3(-wa + tumble, y1, za - 0.05), Vector3(wa - tumble, y1, za - 0.05), Vector3(wf - tumble, y1, zf + rake), Vector3(-wf + tumble, y1, zf + rake)]
	var wy0 := y0 + height * win.x
	var wy1 := y0 + height * win.y
	for f in 4:
		var a: Vector3 = base[f]
		var b: Vector3 = base[(f + 1) % 4]
		var c: Vector3 = top[(f + 1) % 4]
		var d: Vector3 = top[f]
		var want := ((a + b) * 0.5 - Vector3(0.0, (a + b).y * 0.5, (za + zf) * 0.5)).normalized()
		if f == 0:
			want = Vector3(0.0, 0.0, 1.0)
		var glazed := (f == 1 or f == 3) or (f == 2 and front_win)
		if glazed and acc.level != Level.FAR:
			var a1 := a.lerp(d, (wy0 - y0) / height)
			var b1 := b.lerp(c, (wy0 - y0) / height)
			var a2 := a.lerp(d, (wy1 - y0) / height)
			var b2 := b.lerp(c, (wy1 - y0) / height)
			acc.quad(a, b, b1, a1, col, Region.GELCOAT, want)
			acc.quad(a1, b1, b2, a2, GLASS_TINT, Region.GLASS, want)
			acc.quad(a2, b2, c, d, col, Region.GELCOAT, want)
		else:
			acc.quad(a, b, c, d, col if not glazed else GLASS_TINT.lerp(col, 0.4), Region.GELCOAT, want)
	acc.quad(top[0], top[1], top[2], top[3], col, Region.GELCOAT, Vector3.UP)


## A tube from a to b, radii r0 / r1, `sides` sides (end caps off).
static func _tube(acc: Acc, a: Vector3, b: Vector3, r0: float, r1: float, sides: int, col: Color, region: int) -> void:
	acc.tube(a, b, r0, r1, sides, col, region)


## A thin line (rigging, lifelines): two crossed strips (NEAR only unless `keep`).
static func _line(acc: Acc, a: Vector3, b: Vector3, w: float, col: Color, region: int, keep := false) -> void:
	if acc.level == Level.FAR or (acc.level == Level.MID and not keep):
		return
	acc.line(a, b, w, col, region)


## Stanchions and lifelines along both sides between t0 and t1 (a bow pulpit's run).
static func _rails(acc: Acc, h: Hull, t0: float, t1: float, height: float, posts: int, wires: int) -> void:
	if acc.level != Level.NEAR:
		return
	for side: float in [-1.0, 1.0]:
		var prev_tops: Array = []
		for i in posts:
			var t := lerpf(t0, t1, float(i) / float(posts - 1))
			var p := _sheer_point(h, t, side, 0.08)
			var q := p + Vector3(-side * 0.02, height, 0.0)
			acc.tube(p, q, 0.014, 0.014, 4, STEEL, Region.METAL)
			prev_tops.append(p)
		for w in wires:
			var hy := height * float(w + 1) / float(wires)
			for i in posts - 1:
				var a: Vector3 = prev_tops[i] + Vector3(0.0, hy, 0.0)
				var b: Vector3 = prev_tops[i + 1] + Vector3(0.0, hy, 0.0)
				acc.tube(a, b, 0.008, 0.008, 3, STEEL, Region.METAL)


## A bow pulpit: a hoop over the bow at `height`.
static func _pulpit(acc: Acc, h: Hull, height: float) -> void:
	if acc.level != Level.NEAR:
		return
	var pts: Array = []
	for i in 7:
		var t := lerpf(0.86, 0.995, float(i) / 6.0)
		pts.append(_sheer_point(h, t, 1.0, 0.07))
	var ring: Array = []
	for i in range(pts.size() - 1, -1, -1):
		ring.append(Vector3(-(pts[i] as Vector3).x, (pts[i] as Vector3).y, (pts[i] as Vector3).z))
	for p in pts:
		ring.append(p)
	for i in ring.size() - 1:
		var a: Vector3 = ring[i] + Vector3(0.0, height, 0.0)
		var b: Vector3 = ring[i + 1] + Vector3(0.0, height, 0.0)
		acc.tube(a, b, 0.016, 0.016, 4, STEEL, Region.METAL)
	for i in [0, 3, ring.size() - 4, ring.size() - 1]:
		var p: Vector3 = ring[i]
		acc.tube(p, p + Vector3(0.0, height, 0.0), 0.016, 0.016, 4, STEEL, Region.METAL)


# --- Sailboat -------------------------------------------------------------------------------------

static func _sailboat(acc: Acc, variant: int) -> void:
	var h := Hull.new()
	h.length = Marina.REF_LEN[Marina.Type.SAIL]
	h.beam = Marina._beam(Marina.Type.SAIL, h.length)
	h.fb_stern = 0.95
	h.fb_bow = 1.32
	h.depth = 0.55
	h.vee = 0.15
	h.transom = 0.78
	h.max_at = 0.36
	h.fine = 1.5
	h.rake = 0.7
	_hull(acc, h)
	var deck := _sheer(h, 0.5)
	# The fin keel and the spade rudder (seen in the yard).
	if acc.level != Level.FAR:
		acc.box(Transform3D(Basis(), Vector3(0.0, -_keel(h, 0.52) - 0.85, _z(h, 0.52))), Vector3(0.14, 1.7, 1.25), BLACK, Region.BOTTOM)
		acc.box(Transform3D(Basis(), Vector3(0.0, -_keel(h, 0.52) - 1.65, _z(h, 0.52) + 0.15)), Vector3(0.42, 0.28, 1.6), BLACK, Region.BOTTOM)
		acc.box(Transform3D(Basis(), Vector3(0.0, -_keel(h, 0.1) - 0.5, _z(h, 0.1))), Vector3(0.08, 1.1, 0.55), BLACK, Region.BOTTOM)
	# The coachroof forward of the cockpit, a low raked cabin with a strip of ports.
	_cabin(acc, h, 0.36, 0.7, deck - 0.05, 0.55, 0.62, 0.6, 0.18, Vector2(0.38, 0.72), WHITE, false)
	# The cockpit: a coaming round a well aft, teak seats.
	if acc.level != Level.FAR:
		var cz0 := _z(h, 0.08)
		var cz1 := _z(h, 0.35)
		var cw := _half_beam(h, 0.2) * 0.72
		var cy := _sheer(h, 0.2)
		for side: float in [-1.0, 1.0]:
			acc.box(Transform3D(Basis(), Vector3(side * cw, cy + 0.17, (cz0 + cz1) * 0.5)), Vector3(0.06, 0.34, cz0 - cz1), WHITE, Region.GELCOAT)
			acc.box(Transform3D(Basis(), Vector3(side * (cw - 0.28), cy + 0.06, (cz0 + cz1) * 0.5)), Vector3(0.45, 0.06, cz0 - cz1 - 0.3), TEAK_C, Region.TEAK)
		# The wheel on its pedestal.
		if acc.level == Level.NEAR:
			var wz := _z(h, 0.14)
			acc.tube(Vector3(0.0, cy, wz), Vector3(0.0, cy + 0.85, wz), 0.06, 0.05, 6, STEEL, Region.METAL)
			var r := 0.55
			var prev := Vector3(0.0, cy + 0.85 + r, wz - 0.05)
			for i in range(1, 17):
				var a := TAU * float(i) / 16.0
				var p := Vector3(sin(a) * r, cy + 0.85 + cos(a) * r, wz - 0.05)
				acc.tube(prev, p, 0.018, 0.018, 4, STEEL, Region.METAL)
				prev = p
	# Mast, boom, sail cover, the furled jib, standing rigging, spreaders, the masthead light.
	var mast_h := 14.6 if variant == 0 else 13.6
	var mt := 0.6
	var mz := _z(h, mt)
	var my := _sheer(h, mt) + 0.5
	var top := Vector3(0.0, my + mast_h, mz)
	acc.tube(Vector3(0.0, my - 0.4, mz), top, 0.11, 0.07, [8, 6, 4][acc.level], ALU, Region.METAL)
	if acc.level != Level.FAR:
		var bz := _z(h, 0.06)
		var by := my + 1.35
		acc.tube(Vector3(0.0, by, mz + 0.1), Vector3(0.0, by + 0.12, bz), 0.07, 0.06, 6 if acc.level == Level.NEAR else 4, ALU, Region.METAL)
		# The sail cover: a fat tapered roll on the boom.
		acc.tube(Vector3(0.0, by + 0.22, mz + 0.15), Vector3(0.0, by + 0.3, bz + 0.5), 0.26, 0.12, 8 if acc.level == Level.NEAR else 5, Color.WHITE, Region.CANVAS)
		# The jib rolled on the forestay, a long spindle.
		var stem := _sheer_point(h, 0.995, 0.0) + Vector3(0.0, 0.1, 0.0)
		var fore_top := top + Vector3(0.0, -0.3, 0.0)
		acc.tube(stem + (fore_top - stem) * 0.02, stem.lerp(fore_top, 0.45), 0.05, 0.11, 6 if acc.level == Level.NEAR else 4, SAILCLOTH, Region.SAIL)
		acc.tube(stem.lerp(fore_top, 0.45), stem.lerp(fore_top, 0.97), 0.11, 0.025, 6 if acc.level == Level.NEAR else 4, SAILCLOTH, Region.SAIL)
		_line(acc, stem, fore_top, 0.012, STEEL, Region.METAL, true)
		# Backstay to the transom.
		var tr := Vector3(0.0, _sheer(h, 0.0) + 0.1, _z(h, 0.0))
		_line(acc, top, tr, 0.012, STEEL, Region.METAL, true)
		# Spreaders and shrouds.
		var sp_y := my + mast_h * 0.52
		for side: float in [-1.0, 1.0]:
			var tip := Vector3(side * 1.05, sp_y, mz + 0.2)
			if acc.level == Level.NEAR:
				acc.tube(Vector3(0.0, sp_y, mz), tip, 0.03, 0.02, 4, ALU, Region.METAL)
			var plate := _sheer_point(h, mt - 0.03, side, 0.1)
			_line(acc, plate, tip, 0.01, STEEL, Region.METAL, true)
			_line(acc, tip, top + Vector3(0.0, -0.2, 0.0), 0.01, STEEL, Region.METAL, true)
			_line(acc, _sheer_point(h, mt + 0.05, side, 0.1), Vector3(side * 0.06, sp_y, mz), 0.009, STEEL, Region.METAL)
			_line(acc, _sheer_point(h, mt - 0.12, side, 0.1), Vector3(side * 0.06, sp_y, mz), 0.009, STEEL, Region.METAL)
		# Topping lift and a halyard slapping down the mast.
		_line(acc, top + Vector3(0.0, -0.1, 0.1), Vector3(0.0, by + 0.12, bz + 0.1), 0.008, BLACK, Region.RUBBER)
		_line(acc, top + Vector3(0.0, -0.2, -0.12), Vector3(0.0, my + 0.5, mz - 0.12), 0.008, OFFWHITE, Region.SAIL)
	# The masthead: a cap, a windex, the anchor light.
	acc.box(Transform3D(Basis(), top + Vector3(0.0, 0.05, 0.0)), Vector3(0.16, 0.1, 0.32), ALU, Region.METAL)
	acc.octa(top + Vector3(0.0, 0.18, 0.0), 0.06 if acc.level != Level.FAR else 0.12, Color(1.0, 0.98, 0.9), Region.LIGHT)
	if acc.level == Level.NEAR:
		acc.tube(top + Vector3(0.0, 0.1, 0.0), top + Vector3(0.0, 0.55, -0.1), 0.01, 0.01, 3, BLACK, Region.METAL)
	_rails(acc, h, 0.08, 0.86, 0.62, 6, 2)
	_pulpit(acc, h, 0.62)
	if variant == 1 and acc.level != Level.FAR:
		# A dodger over the companionway and a bimini over the cockpit, on stainless hoops.
		var dz := _z(h, 0.36)
		var cy := _sheer(h, 0.3)
		var dw := _half_beam(h, 0.36) * 0.7
		_canvas_hood(acc, Vector3(0.0, cy, dz), dw, 0.95, 0.9, true)
		var bz2 := _z(h, 0.17)
		_canvas_hood(acc, Vector3(0.0, cy, bz2), _half_beam(h, 0.17) * 0.78, 1.9, 1.5, false)


## A canvas hood (dodger or bimini) centred at `at` (deck level), half width `w`, height `hgt`,
## length `len` aft from `at`; a dodger's front is closed with a window.
static func _canvas_hood(acc: Acc, at: Vector3, w: float, hgt: float, len: float, dodger: bool) -> void:
	var n := 6 if acc.level == Level.NEAR else 3
	var rows: Array[PackedVector3Array] = []
	for j in 2:
		var row := PackedVector3Array()
		var z := at.z + (0.0 if j == 0 else len)
		var hh := hgt * (1.0 if j == 0 else (0.85 if dodger else 1.0))
		for i in n + 1:
			var a := PI * float(i) / float(n)
			row.append(Vector3(-cos(a) * w, at.y + hh - (1.0 - sin(a)) * hgt * 0.32, z))
		rows.append(row)
	acc.grid(rows, Color.WHITE, Region.CANVAS, func(p: Vector3) -> Vector3: return Vector3(p.x * 0.3, 1.0, 0.0))
	if dodger:
		var front := PackedVector3Array()
		for p in rows[0]:
			front.append(p)
		front.append(Vector3(w, at.y, at.z))
		front.append(Vector3(-w, at.y, at.z))
		var win := PackedVector3Array()
		var pts := rows[0]
		acc.fan(front, Color.WHITE, Region.CANVAS, Vector3(0.0, 0.0, -1.0))
		for i in range(1, pts.size() - 1):
			win.append(pts[i] + Vector3(0.0, -0.18, -0.01))
		win.append(Vector3(w * 0.7, at.y + hgt * 0.4, at.z - 0.01))
		win.append(Vector3(-w * 0.7, at.y + hgt * 0.4, at.z - 0.01))
		acc.fan(win, GLASS_TINT, Region.GLASS, Vector3(0.0, 0.0, -1.0))
	elif acc.level == Level.NEAR:
		for side: float in [-1.0, 1.0]:
			acc.tube(Vector3(side * w, at.y, at.z + len * 0.3), Vector3(side * w, at.y + hgt * 0.68, at.z + len * 0.3), 0.015, 0.015, 4, STEEL, Region.METAL)


# --- Motor yacht ----------------------------------------------------------------------------------

static func _motor_yacht(acc: Acc, variant: int) -> void:
	var h := Hull.new()
	h.length = Marina.REF_LEN[Marina.Type.MOTOR]
	h.beam = Marina._beam(Marina.Type.MOTOR, h.length)
	h.fb_stern = 1.45
	h.fb_bow = 2.15
	h.depth = 0.95
	h.vee = 0.85
	h.transom = 0.93
	h.max_at = 0.33
	h.fine = 1.9
	h.flare = 0.12
	h.rake = 1.3
	_hull(acc, h)
	# The swim platform across the transom.
	var tz := _z(h, 0.0)
	acc.box(Transform3D(Basis(), Vector3(0.0, 0.45, tz + 0.65)), Vector3(h.beam * 0.86, 0.12, 1.3), TEAK_C, Region.TEAK)
	if variant == 0:
		# Main deck saloon with big windows, the flybridge over it with a hardtop and radar arch.
		var y0 := _sheer(h, 0.3)
		_cabin(acc, h, 0.14, 0.66, y0, 2.0, 0.88, 0.9, 0.12, Vector2(0.3, 0.85), WHITE)
		var fy := y0 + 2.0
		# Flybridge deck rails (a low coaming) and helm seats.
		if acc.level != Level.FAR:
			var fz0 := _z(h, 0.2)
			var fz1 := _z(h, 0.6)
			var fw := _half_beam(h, 0.35) * 0.78
			for side: float in [-1.0, 1.0]:
				acc.box(Transform3D(Basis(), Vector3(side * fw, fy + 0.35, (fz0 + fz1) * 0.5)), Vector3(0.08, 0.7, fz0 - fz1), WHITE, Region.GELCOAT)
			acc.box(Transform3D(Basis(), Vector3(0.0, fy + 0.35, fz1 + 0.2)), Vector3(fw * 2.0, 0.7, 0.12), WHITE, Region.GELCOAT)
			acc.box(Transform3D(Basis(), Vector3(0.0, fy + 0.3, fz1 + 1.2)), Vector3(1.6, 0.6, 0.6), Color.WHITE, Region.CANVAS)
			acc.box(Transform3D(Basis(), Vector3(0.0, fy + 0.3, (fz0 + fz1) * 0.5 + 0.8)), Vector3(fw * 1.5, 0.45, 1.8), Color.WHITE, Region.CANVAS)
			# Hardtop on posts, radar dome on it.
			var hz0 := fz0 - 0.2
			var hz1 := fz1 + 1.7
			for side: float in [-1.0, 1.0]:
				for z: float in [hz0, hz1]:
					acc.tube(Vector3(side * (fw - 0.2), fy + 0.6, z), Vector3(side * (fw - 0.25), fy + 2.2, z), 0.05, 0.05, 6, STEEL, Region.METAL)
			acc.box(Transform3D(Basis(), Vector3(0.0, fy + 2.28, (hz0 + hz1) * 0.5)), Vector3(fw * 2.0, 0.16, hz0 - hz1 + 0.6), WHITE, Region.GELCOAT)
			acc.tube(Vector3(0.0, fy + 2.36, (hz0 + hz1) * 0.5), Vector3(0.0, fy + 2.62, (hz0 + hz1) * 0.5), 0.32, 0.3, 8, WHITE, Region.GELCOAT)
			acc.octa(Vector3(0.0, fy + 2.75, (hz0 + hz1) * 0.5 + 0.6), 0.05, Color(1.0, 0.98, 0.9), Region.LIGHT)
		# The windscreen of the lower helm, tinted, raked.
		_rails(acc, h, 0.62, 0.9, 0.75, 4, 1)
		_pulpit(acc, h, 0.75)
	else:
		# Express cruiser: a low cabin forward, the cockpit under a raked hardtop with glass.
		var y0 := _sheer(h, 0.4)
		_cabin(acc, h, 0.42, 0.78, y0, 0.55, 0.7, 1.2, 0.2, Vector2(0.45, 0.75), WHITE, false)
		if acc.level != Level.FAR:
			var hz0 := _z(h, 0.22)
			var hz1 := _z(h, 0.45)
			var hw := _half_beam(h, 0.34) * 0.86
			var cy := _sheer(h, 0.3)
			# Windscreen.
			acc.quad(Vector3(-hw, cy, hz1), Vector3(hw, cy, hz1), Vector3(hw * 0.95, cy + 1.25, hz1 + 0.9), Vector3(-hw * 0.95, cy + 1.25, hz1 + 0.9), GLASS_TINT, Region.GLASS, Vector3(0.0, 0.5, -1.0))
			# The hardtop's legs, sloping aft.
			for side: float in [-1.0, 1.0]:
				acc.quad(Vector3(side * hw, cy, hz0), Vector3(side * hw, cy, hz0 - 0.5), Vector3(side * hw * 0.95, cy + 1.3, hz0 - 0.9), Vector3(side * hw * 0.95, cy + 1.3, hz0 - 0.3), WHITE, Region.GELCOAT, Vector3(side, 0.0, 0.0))
			acc.box(Transform3D(Basis(Vector3.RIGHT, 0.05), Vector3(0.0, cy + 1.32, (hz0 + hz1) * 0.5 + 0.2)), Vector3(hw * 1.95, 0.1, hz0 - hz1 + 0.6), WHITE, Region.GELCOAT)
			acc.box(Transform3D(Basis(), Vector3(0.0, cy + 0.35, hz0 + 1.6)), Vector3(hw * 1.7, 0.45, 1.2), Color.WHITE, Region.CANVAS)
		_pulpit(acc, h, 0.6)


# --- Sport fisher -------------------------------------------------------------------------------

static func _sport_fisher(acc: Acc, variant: int) -> void:
	var h := Hull.new()
	h.length = Marina.REF_LEN[Marina.Type.FISHER]
	h.beam = Marina._beam(Marina.Type.FISHER, h.length)
	h.fb_stern = 1.25
	h.fb_bow = 2.3
	h.depth = 0.85
	h.vee = 0.9
	h.transom = 0.95
	h.max_at = 0.3
	h.fine = 2.2
	h.flare = 0.18
	h.rake = 1.5
	_hull(acc, h, DECK_WHITE, 0.0)
	# The cabin forward of the open cockpit, its windscreen and the flybridge on top.
	var y0 := _sheer(h, 0.45)
	_cabin(acc, h, 0.4, 0.74, y0, 1.35, 0.92, 0.7, 0.1, Vector2(0.35, 0.8), WHITE)
	var fy := y0 + 1.35
	if acc.level != Level.FAR:
		var fz0 := _z(h, 0.42)
		var fz1 := _z(h, 0.68)
		var fw := _half_beam(h, 0.52) * 0.8
		# Flybridge console, seats, a bimini frame.
		acc.box(Transform3D(Basis(), Vector3(0.0, fy + 0.5, fz1 + 0.6)), Vector3(fw * 1.6, 1.0, 0.7), WHITE, Region.GELCOAT)
		acc.box(Transform3D(Basis(), Vector3(0.0, fy + 1.05, fz1 + 0.35)), Vector3(fw * 1.5, 0.12, 0.08), GLASS_TINT, Region.GLASS)
		acc.box(Transform3D(Basis(), Vector3(0.0, fy + 0.35, fz1 + 1.7)), Vector3(1.4, 0.7, 0.55), Color.WHITE, Region.CANVAS)
		for side: float in [-1.0, 1.0]:
			acc.box(Transform3D(Basis(), Vector3(side * fw, fy + 0.4, (fz0 + fz1) * 0.5)), Vector3(0.07, 0.8, fz0 - fz1), WHITE, Region.GELCOAT)
		# The cockpit's fighting chair.
		var cz := _z(h, 0.15)
		var cy := _sheer(h, 0.15) - 0.55
		acc.tube(Vector3(0.0, cy, cz), Vector3(0.0, cy + 0.55, cz), 0.07, 0.07, 6, STEEL, Region.METAL)
		acc.box(Transform3D(Basis(), Vector3(0.0, cy + 0.7, cz)), Vector3(0.6, 0.25, 0.6), Color.WHITE, Region.CANVAS)
		# The cockpit sole is low behind the cabin: a coaming inside the sheer.
		var cw := _half_beam(h, 0.2) * 0.9
		acc.box(Transform3D(Basis(), Vector3(0.0, _sheer(h, 0.2) - 0.75, _z(h, 0.2))), Vector3(cw * 2.0, 0.04, _z(h, 0.02) - _z(h, 0.38)), DECK_WHITE, Region.DECK)
		if variant == 1:
			# The tuna tower: four legs from the flybridge to a top station and its hardtop.
			var tz := (fz0 + fz1) * 0.5 + 0.4
			var ty := fy + 4.2
			for sx: float in [-1.0, 1.0]:
				for sz: float in [-1.0, 1.0]:
					acc.tube(Vector3(sx * fw * 0.85, fy, tz + sz * 1.3), Vector3(sx * 0.6, ty, tz + sz * 0.55), 0.04, 0.04, 6 if acc.level == Level.NEAR else 4, ALU, Region.METAL)
			acc.box(Transform3D(Basis(), Vector3(0.0, ty, tz)), Vector3(1.3, 0.08, 1.2), ALU, Region.METAL)
			acc.box(Transform3D(Basis(), Vector3(0.0, ty + 1.15, tz)), Vector3(1.5, 0.08, 1.4), WHITE, Region.GELCOAT)
			for sx: float in [-1.0, 1.0]:
				for sz: float in [-1.0, 1.0]:
					acc.tube(Vector3(sx * 0.6, ty, tz + sz * 0.55), Vector3(sx * 0.65, ty + 1.1, tz + sz * 0.6), 0.03, 0.03, 4, ALU, Region.METAL)
			acc.octa(Vector3(0.0, ty + 1.3, tz), 0.05, Color(1.0, 0.98, 0.9), Region.LIGHT)
			# Outriggers, swung up.
			for side: float in [-1.0, 1.0]:
				_line(acc, Vector3(side * fw * 0.85, fy + 0.8, tz), Vector3(side * 3.4, fy + 6.8, tz + 2.2), 0.05, ALU, Region.METAL, true)
		else:
			# A bimini over the flybridge.
			_canvas_hood(acc, Vector3(0.0, fy + 0.15, fz1 + 0.1), fw * 0.95, 1.9, 2.2, false)
	_rails(acc, h, 0.72, 0.9, 0.7, 3, 1)
	_pulpit(acc, h, 0.7)


# --- Runabout -------------------------------------------------------------------------------------

static func _runabout(acc: Acc, variant: int) -> void:
	var h := Hull.new()
	h.length = Marina.REF_LEN[Marina.Type.RUNABOUT]
	h.beam = Marina._beam(Marina.Type.RUNABOUT, h.length)
	h.fb_stern = 0.72
	h.fb_bow = 0.95
	h.depth = 0.38
	h.vee = 0.95
	h.transom = 0.95
	h.max_at = 0.32
	h.fine = 1.9
	h.flare = 0.1
	h.rake = 0.6
	_hull(acc, h, DECK_WHITE, 0.0)
	var cy := _sheer(h, 0.4)
	# The outboard on the transom: a cowl on a leg.
	var tz := _z(h, 0.0)
	acc.box(Transform3D(Basis(Vector3.RIGHT, 0.12), Vector3(0.0, 0.85, tz + 0.45)), Vector3(0.52, 0.65, 0.72), BLACK, Region.ENGINE)
	acc.box(Transform3D(Basis(Vector3.RIGHT, 0.12), Vector3(0.0, 0.1, tz + 0.38)), Vector3(0.16, 0.95, 0.3), BLACK, Region.ENGINE)
	if acc.level == Level.FAR:
		return
	# The interior: seats (white vinyl) in an open hull.
	var sw := _half_beam(h, 0.35) * 0.82
	acc.box(Transform3D(Basis(), Vector3(0.0, cy - 0.3, _z(h, 0.12))), Vector3(sw * 2.0, 0.4, 0.75), Color.WHITE, Region.CANVAS)
	if variant == 0:
		# A bowrider: the split windscreen across, seats in the bow, the helm behind it.
		var wz := _z(h, 0.55)
		var ww := _half_beam(h, 0.55) * 0.92
		for side: float in [-1.0, 1.0]:
			acc.quad(Vector3(side * 0.18, cy, wz), Vector3(side * ww, cy - 0.02, wz + 0.25), Vector3(side * ww * 0.9, cy + 0.42, wz + 0.45), Vector3(side * 0.18, cy + 0.45, wz + 0.15), GLASS_TINT, Region.GLASS, Vector3(0.0, 0.4, -1.0))
		acc.box(Transform3D(Basis(), Vector3(-sw * 0.5, cy - 0.25, _z(h, 0.38))), Vector3(0.55, 0.45, 0.55), Color.WHITE, Region.CANVAS)
		acc.box(Transform3D(Basis(), Vector3(sw * 0.5, cy - 0.25, _z(h, 0.38))), Vector3(0.55, 0.45, 0.55), Color.WHITE, Region.CANVAS)
		acc.box(Transform3D(Basis(), Vector3(0.0, cy - 0.3, _z(h, 0.75))), Vector3(sw * 1.3, 0.3, 1.0), Color.WHITE, Region.CANVAS)
	else:
		# Centre console with a T-top.
		var kz := _z(h, 0.45)
		acc.box(Transform3D(Basis(), Vector3(0.0, cy - 0.05, kz)), Vector3(0.8, 1.05, 0.75), WHITE, Region.GELCOAT)
		acc.quad(Vector3(-0.4, cy + 0.47, kz - 0.38), Vector3(0.4, cy + 0.47, kz - 0.38), Vector3(0.36, cy + 0.85, kz - 0.18), Vector3(-0.36, cy + 0.85, kz - 0.18), GLASS_TINT, Region.GLASS, Vector3(0.0, 0.5, -1.0))
		for sx: float in [-1.0, 1.0]:
			for sz: float in [-0.55, 0.55]:
				acc.tube(Vector3(sx * 0.45, cy, kz + sz), Vector3(sx * 0.42, cy + 1.95, kz + sz * 0.9), 0.025, 0.025, 4 if acc.level == Level.MID else 6, STEEL, Region.METAL)
		acc.box(Transform3D(Basis(), Vector3(0.0, cy + 2.0, kz)), Vector3(1.5, 0.08, 1.9), Color.WHITE, Region.CANVAS)
	_rails(acc, h, 0.7, 0.92, 0.35, 3, 1)


# --- The accumulator ------------------------------------------------------------------------------

## Arrays for one mesh, written directly (never SurfaceTool.append_from(): a read-back).
class Acc:
	var level := 0
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()
	var uv := PackedVector2Array()
	var idx := PackedInt32Array()

	func _col(col: Color, region: int) -> Color:
		return Color(col.r, col.g, col.b, (float(region) + 0.5) / 16.0)

	## A flat triangle facing `want` (Godot's front: (c - a) x (b - a) along the normal).
	func tri(a: Vector3, b: Vector3, cc: Vector3, col: Color, region: int, want: Vector3) -> void:
		var nn := (cc - a).cross(b - a)
		if nn.length_squared() < 1e-12:
			return
		if nn.dot(want) < 0.0:
			var t := b
			b = cc
			cc = t
			nn = -nn
		nn = nn.normalized()
		var o := v.size()
		var k := _col(col, region)
		for p: Vector3 in [a, b, cc]:
			v.append(p)
			n.append(nn)
			c.append(k)
			uv.append(_uv(p, nn))
		idx.append_array(PackedInt32Array([o, o + 1, o + 2]))

	func quad(a: Vector3, b: Vector3, cc: Vector3, d: Vector3, col: Color, region: int, want: Vector3) -> void:
		tri(a, b, cc, col, region, want)
		tri(a, cc, d, col, region, want)

	## UV in metres, planar by the dominant axis of the normal.
	func _uv(p: Vector3, nn: Vector3) -> Vector2:
		var a := nn.abs()
		if a.y >= a.x and a.y >= a.z:
			return Vector2(p.x, p.z)
		if a.x >= a.z:
			return Vector2(p.z, p.y)
		return Vector2(p.x, p.y)

	## A convex polygon fill facing `want`.
	func fan(poly: PackedVector3Array, col: Color, region: int, want: Vector3) -> void:
		for i in range(1, poly.size() - 1):
			tri(poly[0], poly[i], poly[i + 1], col, region, want)

	## Quads between consecutive rows (equal lengths), smooth normals averaged inside the grid,
	## each face wound to face `out.call(centroid)`.
	func grid(rows: Array[PackedVector3Array], col: Color, region: int, out: Callable) -> void:
		var nr := rows.size()
		var nc := rows[0].size()
		var base := v.size()
		var k := _col(col, region)
		var acc_n := PackedVector3Array()
		acc_n.resize(nr * nc)
		for r in nr:
			for j in nc:
				v.append(rows[r][j])
				c.append(k)
				n.append(Vector3.UP)
				uv.append(Vector2(rows[r][j].z, float(j) / float(maxi(nc - 1, 1)) * 2.0 + rows[r][j].y))
		for r in nr - 1:
			for j in nc - 1:
				var i00 := r * nc + j
				var i01 := r * nc + j + 1
				var i10 := (r + 1) * nc + j
				var i11 := (r + 1) * nc + j + 1
				for t: Array in [[i00, i10, i11], [i00, i11, i01]]:
					var a: Vector3 = v[base + t[0]]
					var b: Vector3 = v[base + t[1]]
					var cc: Vector3 = v[base + t[2]]
					var fn := (cc - a).cross(b - a)
					if fn.length_squared() < 1e-14:
						continue
					var want: Vector3 = out.call((a + b + cc) / 3.0)
					var ia: int = t[0]
					var ib: int = t[1]
					var ic: int = t[2]
					if fn.dot(want) < 0.0:
						var tmp := ib
						ib = ic
						ic = tmp
						fn = -fn
					idx.append_array(PackedInt32Array([base + ia, base + ib, base + ic]))
					for q: int in [ia, ib, ic]:
						acc_n[q] += fn
		for q in nr * nc:
			var nn := acc_n[q]
			n[base + q] = nn.normalized() if nn.length_squared() > 1e-14 else Vector3.UP

	## A box (local frame `xf`, size), flat faces.
	func box(xf: Transform3D, size: Vector3, col: Color, region: int) -> void:
		var h := size * 0.5
		var p: Array[Vector3] = []
		for k in 8:
			p.append(xf * Vector3(h.x * (1.0 if k & 1 else -1.0), h.y * (1.0 if k & 2 else -1.0), h.z * (1.0 if k & 4 else -1.0)))
		var faces := [[0, 1, 5, 4, Vector3.DOWN], [2, 3, 7, 6, Vector3.UP], [0, 1, 3, 2, Vector3.FORWARD], [4, 5, 7, 6, Vector3.BACK], [0, 2, 6, 4, Vector3.LEFT], [1, 3, 7, 5, Vector3.RIGHT]]
		for f: Array in faces:
			if level == Level.FAR and (f[4] as Vector3) == Vector3.DOWN:
				continue
			quad(p[f[0]], p[f[1]], p[f[2]], p[f[3]], col, region, xf.basis * (f[4] as Vector3))

	## A tapered tube from a to b, smooth sides, no caps.
	func tube(a: Vector3, b: Vector3, r0: float, r1: float, sides: int, col: Color, region: int) -> void:
		var axis := b - a
		if axis.length_squared() < 1e-8:
			return
		var d := axis.normalized()
		var side := d.cross(Vector3.UP if absf(d.y) < 0.95 else Vector3.RIGHT).normalized()
		var up := side.cross(d).normalized()
		var base := v.size()
		var k := _col(col, region)
		for j in sides + 1:
			var ang := TAU * float(j) / float(sides)
			var dir := side * cos(ang) + up * sin(ang)
			for e in 2:
				var p := (a + dir * r0) if e == 0 else (b + dir * r1)
				v.append(p)
				n.append(dir)
				c.append(k)
				uv.append(Vector2(float(j) / float(sides), float(e) * axis.length()))
		for j in sides:
			var i0 := base + j * 2
			var i1 := base + (j + 1) * 2
			# Outward winding: the face normal (c - a) x (b - a) along dir.
			var fa := v[i0]
			var fb := v[i1]
			var fc := v[i1 + 1]
			var fnrm := (fc - fa).cross(fb - fa)
			var outward := (fa + fb) * 0.5 - (a + (b - a) * 0.0)
			if fnrm.dot(outward - d * outward.dot(d)) >= 0.0:
				idx.append_array(PackedInt32Array([i0, i1, i1 + 1, i0, i1 + 1, i0 + 1]))
			else:
				idx.append_array(PackedInt32Array([i0, i1 + 1, i1, i0, i0 + 1, i1 + 1]))

	## A thin line as two crossed strips (double-sided in the shader).
	func line(a: Vector3, b: Vector3, w: float, col: Color, region: int) -> void:
		var d := (b - a).normalized()
		var s1 := d.cross(Vector3.UP if absf(d.y) < 0.95 else Vector3.RIGHT).normalized() * w * 0.5
		var s2 := d.cross(s1).normalized() * w * 0.5
		quad(a - s1, b - s1, b + s1, a + s1, col, region, s2)
		quad(a - s2, b - s2, b + s2, a + s2, col, region, s1)

	## A small octahedron (a lamp lens).
	func octa(at: Vector3, r: float, col: Color, region: int) -> void:
		var ax := [Vector3(r, 0, 0), Vector3(0, 0, r), Vector3(-r, 0, 0), Vector3(0, 0, -r)]
		for i in 4:
			var a: Vector3 = at + ax[i]
			var b: Vector3 = at + ax[(i + 1) % 4]
			var mid := (a + b) * 0.5 - at
			tri(a, b, at + Vector3(0, r * 1.4, 0), col, region, mid + Vector3(0, r, 0))
			tri(a, b, at - Vector3(0, r * 1.4, 0), col, region, mid - Vector3(0, r, 0))

	func commit() -> ArrayMesh:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = v
		arrays[Mesh.ARRAY_NORMAL] = n
		arrays[Mesh.ARRAY_COLOR] = c
		arrays[Mesh.ARRAY_TEX_UV] = uv
		arrays[Mesh.ARRAY_INDEX] = idx
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		return m

	func triangles() -> int:
		return idx.size() / 3
