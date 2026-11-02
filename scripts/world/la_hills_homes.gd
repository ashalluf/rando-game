class_name LaHillsHomes
extends RefCounted
## Houses on Los Angeles' hills (LaHills' "homes" hills: Echo Park, Elysian Heights, Solano Canyon,
## Boyle Heights, San Pedro): what a house on a 20-30 % lot stands on. HouseBuild already sets the
## floor at the highest corner of the house and runs its walls down to the lowest; here, at FULL:
##  - STILTS: where the ground falls more than STILT_DROP under a wing, the walls stop a skirt below
##    the floor (house_base(), one hook in HouseBuild.setup()) and the wing stands on a ring beam,
##    posts on footings down to the ground and X bracing in the tall bays, with a soffit under it;
##  - a GARAGE AT THE STREET: where the house stands GARAGE_RISE or more over its kerb, a concrete
##    garage is cut into the bank at the kerb on the driveway, its roof a deck at the yard's level;
##  - STAIRS from the pavement up to the front door (concrete steps on a solid stringer, a pipe rail).
## Everything of a chunk is one mesh on FootbridgeKit's material ("HillHomes") and one body, committed
## by commit() from LaHillsBuild.kerb_walls()' step. Hashes only (seed + lot), never a roll.

const STILT_DROP := 2.8
const SKIRT := 0.7
const POST := 0.26
const POST_EVERY := 3.4
const BEAM_H := 0.4
const GARAGE_RISE := 2.6
const GARAGE_H := 2.75
const GARAGE_D := 6.4
const GARAGE_MIN_W := 3.4
const STAIR_RISE := 0.9
const STEP_RISE := 0.18
const STEP_RUN := 0.3
const STAIR_W := 1.3
const POST_COLORS := [Color(0.80, 0.78, 0.74), Color(0.30, 0.22, 0.16), Color(0.24, 0.25, 0.26)]
const DOOR_COLORS := [Color(0.86, 0.84, 0.78), Color(0.42, 0.30, 0.20), Color(0.26, 0.30, 0.33), Color(0.62, 0.20, 0.16)]


## True for a house this pass dresses: FULL, the hills on, a plain house (no apartment block, no
## lower levels of its own) whose lot is on a home hill.
static func wants(ch: CityChunk, h: Dictionary) -> bool:
	if not LaHills.enabled or ch.capturing or ch.level != CityChunk.Level.FULL or h.is_empty():
		return false
	var lh: LaHills = ch.plan.macro.la_hills if ch.plan.macro else null
	if lh == null:
		return false
	for w: Dictionary in h.wings:
		if float(w.get("y", 0.0)) != 0.0:
			return false
	var f: Dictionary = h.f
	return lh.homes_at((f.o as Vector2) + (f.u as Vector2) * float(f.U) * 0.5 + (f.v as Vector2) * float(f.V) * 0.5)


## HouseBuild.setup()'s hook: how far below the floor a house's walls run. A wing on stilts keeps a
## skirt; every other house is what HouseBuild worked out.
static func house_base(ch: CityChunk, h: Dictionary, base: float, drop: float) -> float:
	if drop > STILT_DROP and not h.has("apt") and wants(ch, h):
		return -HouseKit.FLOOR_LIFT - SKIRT
	return base


static func _acc(ch: CityChunk) -> Array:
	if not ch.has_meta("la_hill_homes"):
		var g := LandmarkGeo.new()
		g.use("fb", FootbridgeKit.material())
		var body := StaticBody3D.new()
		body.name = "HillHomesBody"
		body.collision_layer = 1
		body.collision_mask = 0
		ch.set_meta("la_hill_homes", [g, body, 0])
	return ch.get_meta("la_hill_homes")


## After HouseKit.build() (CityChunk._build_house()): the house's stilts, street garage and stairs.
static func dress(ch: CityChunk, h: Dictionary) -> void:
	if not wants(ch, h):
		return
	var f: Dictionary = h.f
	var o: Vector2 = f.o
	var fu: Vector2 = f.u
	var fv: Vector2 = f.v
	var gmax := -INF
	var gmin := INF
	for r: Rect2 in HouseKit.ground_parts(h):
		for c: Vector2 in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
			var gy := ch._gy(c.x, c.y)
			gmax = maxf(gmax, gy)
			gmin = minf(gmin, gy)
	var lift := CityChunk.SIDEWALK_TOP + YardFill.LIFT
	var floor_y := gmax + lift + HouseKit.FLOOR_LIFT
	var a := _acc(ch)
	var g: LandmarkGeo = a[0]
	var body: StaticBody3D = a[1]
	var ps := ch.plan.seed
	var s := int(h.seed)
	var built := false
	# --- Stilts.
	if gmax - gmin > STILT_DROP and not h.has("apt"):
		var under := floor_y - HouseKit.FLOOR_LIFT - SKIRT
		var pc: Color = POST_COLORS[absi(hash([ps, s, "stilt"])) % POST_COLORS.size()]
		for w: Dictionary in h.wings:
			var r: Rect2 = w.r
			built = _stilts(ch, g, o, fu, fv, r, under, lift, pc) or built
	# --- The garage at the street and the stairs to the door.
	var dv := 0.0
	var garage_u := Vector2.ZERO
	var drive: Vector2 = h.drive
	if drive.y - drive.x > 0.5 and str((h.garage as Dictionary).get("kind", "")) != "tuck":
		var gu := Vector2(drive.x, drive.y)
		if gu.y - gu.x < GARAGE_MIN_W:
			var m := (gu.x + gu.y) * 0.5
			gu = Vector2(m - GARAGE_MIN_W * 0.5, m + GARAGE_MIN_W * 0.5)
		var mid := o + fu * ((gu.x + gu.y) * 0.5)
		var kerb := ch._gy(mid.x, mid.y) + lift
		var back := o + fu * ((gu.x + gu.y) * 0.5) + fv * GARAGE_D
		var yard := ch._gy(back.x, back.y) + lift
		if floor_y - kerb >= GARAGE_RISE and yard - kerb >= GARAGE_RISE * 0.6:
			_garage(g, body, o, fu, fv, gu, kerb, DOOR_COLORS[absi(hash([ps, s, "gdoor"])) % DOOR_COLORS.size()])
			garage_u = gu
			dv = GARAGE_D
			built = true
	var du: float = h.door_u
	var door_v: float = h.door_v
	if garage_u != Vector2.ZERO and du > garage_u.x - STAIR_W and du < garage_u.y + STAIR_W:
		# Beside the garage, on the side with more room.
		du = garage_u.x - STAIR_W * 0.5 - 0.4 if garage_u.x > float(f.U) - garage_u.y else garage_u.y + STAIR_W * 0.5 + 0.4
		du = clampf(du, STAIR_W * 0.5 + 0.2, float(f.U) - STAIR_W * 0.5 - 0.2)
	built = _stairs(ch, g, body, o, fu, fv, du, door_v, floor_y, lift) or built
	if built:
		a[2] = int(a[2]) + 1


## Posts every POST_EVERY round and through a wing, from footings on the ground up to a ring beam
## under its floor, braced where they are tall; a soffit closes the underside.
static func _stilts(ch: CityChunk, g: LandmarkGeo, o: Vector2, fu: Vector2, fv: Vector2, r: Rect2, under: float, lift: float, pc: Color) -> bool:
	var nu := maxi(1, ceili(r.size.x / POST_EVERY))
	var nv := maxi(1, ceili(r.size.y / POST_EVERY))
	var any := false
	var tops := {}
	for i in nu + 1:
		for j in nv + 1:
			var uu := r.position.x + r.size.x * float(i) / float(nu)
			var vv := r.position.y + r.size.y * float(j) / float(nv)
			uu = clampf(uu, r.position.x + POST * 0.6, r.end.x - POST * 0.6)
			vv = clampf(vv, r.position.y + POST * 0.6, r.end.y - POST * 0.6)
			var p := o + fu * uu + fv * vv
			var gy := ch._gy(p.x, p.y) + lift
			var top := under - BEAM_H
			if top - gy < 0.25:
				continue
			any = true
			tops[Vector2i(i, j)] = gy
			g.box("fb", Vector3(p.x, (gy - 0.3 + top) * 0.5, p.y), Vector3(POST, top - gy + 0.3, POST), FootbridgeKit.kc(pc, FootbridgeKit.K_PAINT))
			g.box("fb", Vector3(p.x, gy - 0.1, p.y), Vector3(0.6, 0.35, 0.6), FootbridgeKit.kc(LaHillsBuild.CONCRETE, FootbridgeKit.K_CONCRETE))
	if not any:
		return false
	# The ring beam and the soffit.
	var c := o + fu * r.get_center().x + fv * r.get_center().y
	var sz := (Vector2(absf(fu.x), absf(fu.y)) * r.size.x + Vector2(absf(fv.x), absf(fv.y)) * r.size.y)
	g.box("fb", Vector3(c.x, under - BEAM_H * 0.5, c.y), Vector3(sz.x, BEAM_H, sz.y), FootbridgeKit.kc(pc.darkened(0.15), FootbridgeKit.K_PAINT))
	# X bracing between neighbouring posts on the wing's edges where the bay is tall.
	for i in nu + 1:
		for j in nv + 1:
			if not tops.has(Vector2i(i, j)):
				continue
			for d: Vector2i in [Vector2i(1, 0), Vector2i(0, 1)]:
				var k := Vector2i(i, j) + d
				if not tops.has(k):
					continue
				var edge := (d.x == 1 and (j == 0 or j == nv)) or (d.y == 1 and (i == 0 or i == nu))
				if not edge:
					continue
				var p0 := _pt(o, fu, fv, r, i, j, nu, nv)
				var p1 := _pt(o, fu, fv, r, k.x, k.y, nu, nv)
				var top := under - BEAM_H
				var b0: float = maxf(float(tops[Vector2i(i, j)]), float(tops[k])) + 0.4
				if top - b0 < 2.0:
					continue
				LaHillsBuild._tube(g, Vector3(p0.x, b0, p0.y), Vector3(p1.x, top - 0.1, p1.y), 0.05, pc.darkened(0.3))
				LaHillsBuild._tube(g, Vector3(p1.x, b0, p1.y), Vector3(p0.x, top - 0.1, p0.y), 0.05, pc.darkened(0.3))
	return true


static func _pt(o: Vector2, fu: Vector2, fv: Vector2, r: Rect2, i: int, j: int, nu: int, nv: int) -> Vector2:
	var uu := clampf(r.position.x + r.size.x * float(i) / float(nu), r.position.x + POST * 0.6, r.end.x - POST * 0.6)
	var vv := clampf(r.position.y + r.size.y * float(j) / float(nv), r.position.y + POST * 0.6, r.end.y - POST * 0.6)
	return o + fu * uu + fv * vv


## A garage cut into the bank at the kerb: concrete walls and a deck over, a sectional door in its
## street face, at the kerb's level.
static func _garage(g: LandmarkGeo, body: StaticBody3D, o: Vector2, fu: Vector2, fv: Vector2, gu: Vector2, kerb: float, door: Color) -> void:
	var w := gu.y - gu.x + 0.6
	var c := o + fu * ((gu.x + gu.y) * 0.5) + fv * (GARAGE_D * 0.5)
	var sz := Vector2(absf(fu.x), absf(fu.y)) * w + Vector2(absf(fv.x), absf(fv.y)) * GARAGE_D
	var top := kerb + GARAGE_H
	var conc := FootbridgeKit.kc(LaHillsBuild.CONCRETE.darkened(0.05), FootbridgeKit.K_CONCRETE)
	g.box("fb", Vector3(c.x, (kerb - 1.0 + top) * 0.5, c.y), Vector3(sz.x, top - kerb + 1.0, sz.y), conc)
	LandmarkGeo.shape_box(body, Vector3(c.x, (kerb - 1.0 + top) * 0.5, c.y), Vector3(sz.x, top - kerb + 1.0, sz.y))
	# The deck's slab edge and a pipe rail along the street.
	var e := o + fu * ((gu.x + gu.y) * 0.5) + fv * 0.05
	var ez := Vector2(absf(fu.x), absf(fu.y)) * (w + 0.2) + Vector2(absf(fv.x), absf(fv.y)) * 0.3
	g.box("fb", Vector3(e.x, top + 0.1, e.y), Vector3(ez.x, 0.2, ez.y), FootbridgeKit.kc(LaHillsBuild.CONCRETE.lightened(0.1), FootbridgeKit.K_CONCRETE))
	var r0 := o + fu * (gu.x - 0.2) + fv * 0.15
	var r1 := o + fu * (gu.y + 0.2) + fv * 0.15
	LaHillsBuild._tube(g, Vector3(r0.x, top + 1.0, r0.y), Vector3(r1.x, top + 1.0, r1.y), 0.03, LaHillsBuild.RAIL_PAINT)
	var n := maxi(2, ceili(w / 1.6))
	for i in n + 1:
		var p := r0.lerp(r1, float(i) / float(n))
		LaHillsBuild._tube(g, Vector3(p.x, top + 0.2, p.y), Vector3(p.x, top + 1.0, p.y), 0.025, LaHillsBuild.RAIL_PAINT)
	# The door: a panel standing just proud of the street face, its sections as grooves.
	var d := o + fu * ((gu.x + gu.y) * 0.5) - fv * 0.02
	var dw := gu.y - gu.x - 0.3
	var dz := Vector2(absf(fu.x), absf(fu.y)) * dw + Vector2(absf(fv.x), absf(fv.y)) * 0.06
	var dh := GARAGE_H - 0.45
	g.box("fb", Vector3(d.x, kerb + dh * 0.5, d.y), Vector3(dz.x, dh, dz.y), FootbridgeKit.kc(door, FootbridgeKit.K_PAINT))
	for k in range(1, 4):
		var yy := kerb + dh * float(k) / 4.0
		var gz := Vector2(absf(fu.x), absf(fu.y)) * dw + Vector2(absf(fv.x), absf(fv.y)) * 0.08
		g.box("fb", Vector3(d.x, yy, d.y), Vector3(gz.x, 0.03, gz.y), FootbridgeKit.kc(door.darkened(0.45), FootbridgeKit.K_DARK))
	# A lamp over the door.
	g.box("fb", Vector3(d.x, kerb + GARAGE_H - 0.2, d.y) - Vector3(fv.x, 0.0, fv.y) * 0.08, Vector3(0.22, 0.14, 0.22), FootbridgeKit.kc(Color(1.0, 0.9, 0.7), FootbridgeKit.K_LAMP))


## A flight from the back of the pavement straight up the front yard toward the door: solid concrete
## steps on the ground, a landing at the floor, a pipe rail on one side. Nothing where the rise is
## under STAIR_RISE.
static func _stairs(ch: CityChunk, g: LandmarkGeo, body: StaticBody3D, o: Vector2, fu: Vector2, fv: Vector2, du: float, door_v: float, floor_y: float, lift: float) -> bool:
	var p0 := o + fu * du + fv * 0.3
	var start := ch._gy(p0.x, p0.y) + lift
	var rise := floor_y - start
	if rise < STAIR_RISE:
		return false
	var n := ceili(rise / STEP_RISE)
	var room := maxf(door_v - 0.6, 1.0)
	var run := clampf(room / float(n), 0.22, STEP_RUN)
	var conc := FootbridgeKit.kc(LaHillsBuild.CONCRETE, FootbridgeKit.K_CONCRETE)
	var tread := FootbridgeKit.kc(LaHillsBuild.CONCRETE.lightened(0.08), FootbridgeKit.K_WALK)
	var wsz := Vector2(absf(fu.x), absf(fu.y)) * STAIR_W
	for i in n:
		var v0 := 0.3 + run * float(i)
		var v1 := v0 + run
		var c := o + fu * du + fv * ((v0 + v1) * 0.5)
		var top := start + rise * float(i + 1) / float(n)
		var gy := ch._gy(c.x, c.y) + lift - 0.3
		var sz := wsz + Vector2(absf(fv.x), absf(fv.y)) * run
		if top - gy < 0.05:
			continue
		g.box("fb", Vector3(c.x, (gy + top - 0.04) * 0.5, c.y), Vector3(sz.x, top - 0.04 - gy, sz.y), conc)
		g.box("fb", Vector3(c.x, top - 0.02, c.y), Vector3(sz.x + 0.04, 0.04, sz.y + 0.04), tread)
		LandmarkGeo.shape_box(body, Vector3(c.x, (gy + top) * 0.5, c.y), Vector3(sz.x, top - gy, sz.y))
	# The landing to the door.
	var lv0 := 0.3 + run * float(n)
	if door_v - lv0 > 0.2:
		var c := o + fu * du + fv * ((lv0 + door_v) * 0.5)
		var gy := ch._gy(c.x, c.y) + lift - 0.3
		var sz := wsz + Vector2(absf(fv.x), absf(fv.y)) * (door_v - lv0)
		if floor_y - gy > 0.05:
			g.box("fb", Vector3(c.x, (gy + floor_y) * 0.5, c.y), Vector3(sz.x, floor_y - gy, sz.y), conc)
			LandmarkGeo.shape_box(body, Vector3(c.x, (gy + floor_y) * 0.5, c.y), Vector3(sz.x, floor_y - gy, sz.y))
	# A pipe rail up one side.
	var side := fu * (STAIR_W * 0.5 - 0.06)
	var a0 := o + fu * du + side + fv * 0.35
	var a1 := o + fu * du + side + fv * (0.3 + run * float(n))
	var col := LaHillsBuild.RAIL_PAINT
	LaHillsBuild._tube(g, Vector3(a0.x, start + 0.9, a0.y), Vector3(a1.x, floor_y + 0.9, a1.y), 0.025, col)
	for t: float in [0.0, 0.5, 1.0]:
		var p := a0.lerp(a1, t)
		var y := lerpf(start, floor_y, t)
		LaHillsBuild._tube(g, Vector3(p.x, y, p.y), Vector3(p.x, y + 0.9, p.y), 0.025, col)
	return true


## The chunk's hillside house pieces as one mesh and one body (LaHillsBuild.kerb_walls()' step).
static func commit(ch: CityChunk) -> void:
	if not ch.has_meta("la_hill_homes"):
		return
	var a: Array = ch.get_meta("la_hill_homes")
	ch.remove_meta("la_hill_homes")
	var body: StaticBody3D = a[1]
	if int(a[2]) == 0:
		body.free()
		return
	ch.add_child(body)
	(a[0] as LandmarkGeo).commit(ch, "HillHomes", true, 260.0)
