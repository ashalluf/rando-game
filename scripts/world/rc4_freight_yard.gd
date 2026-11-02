class_name RcFreightYard
extends RefCounted
## The freight yard refcam's fixes (wave 7, rc4-freight-yard; camera `freight_yard` in
## tools/refcams/cameras_w7.json, docs/HANDOFF.md "The freight yard at 16:30"). Hooks, one line each,
## in FreightKit (the ties' placement and draw range) and FreightYard (the ladder's bed):
##
##   * the yard's timber ties were never seen: a chunk's ties are one MultiMesh, and a node's
##     visibility range is measured to the centre of its bounds - the yard's blocks are ~520 m
##     wide, so from anywhere on the storage tracks the centre was past FreightKit's 260 m and every
##     rail in the yard lay on bare ballast. `tie_range()` adds the batch's own half diagonal;
##   * every track piece laid northward (the ladder) threw its ties kilometres off the track
##     (FreightKit.ties() divided by maxf(zb - za, 1e-4)); and the ladder had no bed at all, its
##     rails floating 0.65 m over the dirt: `ladder_ballast()` lays one under it.
##
## RC4_FREIGHT_YARD=0 in the environment puts every one of them back (the A/B).

static var enabled: bool = OS.get_environment("RC4_FREIGHT_YARD") != "0"


## The draw range for a chunk's tie MultiMesh: `base` past the farthest tie, not past the batch's
## centre. `buf` is FreightKit's 12-float-per-tie transform buffer (origin x at 3, z at 11).
static func tie_range(buf: PackedFloat32Array, base: float) -> float:
	if not enabled or buf.size() < 12:
		return base
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	var i := 0
	while i + 11 < buf.size():
		var p := Vector2(buf[i + 3], buf[i + 11])
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
		i += 12
	return base + (hi - lo).length() * 0.5


## The ballast bed under one piece of the yard's diagonal ladder (p0 to p1 in plan, rail tops
## ya, yb, the ground ga, gb under them): the top a hair under the storage tracks' beds (the two
## overlap where a track leaves the ladder; coplanar, they would z-fight) and a shoulder each side
## down to the ground, as FreightKit.ballast() lays them for a straight track.
static func ladder_ballast(kit: FreightKit, p0: Vector2, p1: Vector2, ya: float, yb: float, ga: float, gb: float) -> void:
	if not enabled:
		return
	var d := p1 - p0
	if d.length() < 0.01:
		return
	var along := d.normalized()
	var side := Vector2(-along.y, along.x)
	# Run a little past each end so the pieces' beds meet without a notch at the joints.
	var e0 := p0 - along * 0.05
	var e1 := p1 + along * 0.05
	var ta := ya - FreightKit.BALLAST_DROP - 0.012
	var tb := yb - FreightKit.BALLAST_DROP - 0.012
	var col := FreightKit.tcol(FreightKit.BALLAST_COL, FreightKit.T_BALLAST)
	var h := FreightKit.BALLAST_HALF
	var l0 := e0 - side * h
	var r0 := e0 + side * h
	var l1 := e1 - side * h
	var r1 := e1 + side * h
	var s0 := p0.length()
	var s1 := s0 + d.length()
	kit.quad(kit.track, Vector3(l0.x, ta, l0.y), Vector3(r0.x, ta, r0.y), Vector3(r1.x, tb, r1.y), Vector3(l1.x, tb, l1.y), Vector3.UP, col,
		Vector2(s0, -h), Vector2(s0, h), Vector2(s1, h), Vector2(s1, -h), Vector2(0.0, 0.7))
	for sg: float in [-1.0, 1.0]:
		var a0 := e0 + side * h * sg
		var a1 := e1 + side * h * sg
		var o0 := a0 + side * sg * maxf(ta - ga, 0.05) * 1.6
		var o1 := a1 + side * sg * maxf(tb - gb, 0.05) * 1.6
		var out := Vector3(side.x * sg, 1.2, side.y * sg).normalized()
		kit.quad(kit.track, Vector3(a0.x, ta, a0.y), Vector3(o0.x, minf(ga, ta) - 0.02, o0.y), Vector3(o1.x, minf(gb, tb) - 0.02, o1.y), Vector3(a1.x, tb, a1.y),
			out, col, Vector2(s0, sg * 2.0), Vector2(s0, sg * 3.0), Vector2(s1, sg * 3.0), Vector2(s1, sg * 2.0), Vector2(0.0, 0.28))
	kit.set("_track_any", true)


## Weeds: a yard's ballast is never clean. Foxtail and wild oat tufts (VacantKit's) along the
## toes of every bed and in the strips between them, a few up in the ballast by the rails, and
## mustard and fennel where the ladder leaves dirt beside it - every one a hash of the seed and
## the spot. Batched by 40 m cell (`fy_tuft_<v>_<cell>`), so a draw range is measured to a
## cell's centre and not to a 520 m chunk's.
const WEED_CELL := 40.0
const WEED_STEP := 0.85
const WEED_DISTANCE := 85.0
const TALL_DISTANCE := 120.0
const MAX_WEEDS := 1400


## The yard's dressing on its tracks' step (FreightYard._tracks_step): the weeds and the switch
## stands. FULL only.
static func dress(y: FreightYard) -> void:
	weeds(y)
	switch_stands(y)


## A hand-thrown switch stand beside every turnout off the ladder: a cast base on two head ties, the
## post, the throw lever lying in its keeper and the target on top - yellow-faced along the track,
## red across it. Written into Industrial's walls mesh (one casting mesh a chunk); no collision.
static func switch_stands(y: FreightYard) -> void:
	if not enabled or not y.full:
		return
	for t: Dictionary in y.lay.tracks:
		var p := Vector2(float(t.x) + 2.45, float(t.z1) + 3.2)
		if not y.area.has_point(p):
			continue
		var g := y._y(p) + FreightRail.TRACK_DEPTH - FreightKit.BALLAST_DROP
		var ch := y.ch
		var steel := Color(0.11, 0.105, 0.1)
		Industrial._wbox(ch, Transform3D(Basis(), Vector3(p.x, g + 0.06, p.y)), Vector3(0.62, 0.12, 0.42), IndustrialKit.K_STEEL, steel)
		Industrial._wbox(ch, Transform3D(Basis(), Vector3(p.x, g + 0.62, p.y)), Vector3(0.1, 1.0, 0.1), IndustrialKit.K_STEEL, steel)
		Industrial._wbox(ch, Transform3D(Basis(Vector3.UP, 0.12), Vector3(p.x + 0.34, g + 0.2, p.y + 0.05)), Vector3(0.72, 0.05, 0.05), IndustrialKit.K_STEEL, Color(0.14, 0.13, 0.12))
		Industrial._wbox(ch, Transform3D(Basis(), Vector3(p.x, g + 1.27, p.y)), Vector3(0.05, 0.3, 0.42), IndustrialKit.K_STEEL, Color(0.78, 0.6, 0.08))
		Industrial._wbox(ch, Transform3D(Basis(), Vector3(p.x, g + 1.27, p.y)), Vector3(0.42, 0.3, 0.05), IndustrialKit.K_STEEL, Color(0.6, 0.07, 0.05))


static func weeds(y: FreightYard) -> void:
	if not enabled or not y.full:
		return
	var ch := y.ch
	var seed: int = y.plan.seed
	var lines: Array = []
	for j in (y.lay.tracks as Array).size():
		var t: Dictionary = y.lay.tracks[j]
		lines.append([Vector2(float(t.x), float(t.z0)), Vector2(float(t.x), float(t.z1)), j])
	lines.append([y.lay.ladder[0], y.lay.ladder[1], 99])
	# The two mains through the yard: only their outer shoulders.
	var ax: float = y.fr.avenue_x
	var gz0: float = y.fr.yard_rect.position.y
	var gz1: float = y.fr.yard_rect.end.y
	lines.append([Vector2(ax - FreightRail.TRACK_HALF, gz0), Vector2(ax - FreightRail.TRACK_HALF, gz1), 100])
	var count := 0
	var keys := {}
	for ln: Array in lines:
		var a: Vector2 = ln[0]
		var b: Vector2 = ln[1]
		var id: int = ln[2]
		var d := b - a
		var len := d.length()
		if len < 1.0:
			continue
		var along := d / len
		var side := Vector2(-along.y, along.x)
		var n := int(len / WEED_STEP)
		for i in n:
			var s := (float(i) + 0.5) * WEED_STEP
			for sg: int in [-1, 1]:
				if id == 100 and sg > 0:
					continue
				var h := absi(hash([seed, "fy_weed", id, i, sg]))
				var r := float(h % 1000) / 1000.0
				# Thicker where the yard is quiet: the ladder's open side and the tracks' far ends.
				var dens := 0.42 if id >= 99 else 0.3
				if r > dens:
					continue
				var off := FreightKit.BALLAST_HALF + 0.1 + float((h >> 10) % 100) / 100.0 * 1.1
				# Now and then up in the ballast, by the rail.
				var inside := (h >> 17) % 11 == 0
				if inside:
					off = 0.95 + float((h >> 21) % 40) / 100.0
				var p := a + along * s + side * float(sg) * off
				if not y.area.has_point(p):
					continue
				count += 1
				if count > MAX_WEEDS:
					return
				var v := (h >> 7) % 2
				var sc := (0.55 if inside else 0.8) + float((h >> 12) % 60) / 100.0
				var yaw := float((h >> 4) % 628) / 100.0
				var top := CityChunk.SIDEWALK_TOP + Industrial.LIFT + (FreightRail.TRACK_DEPTH - FreightKit.BALLAST_DROP - 0.03 if inside else 0.0)
				var cell := Vector2i(floori(p.x / WEED_CELL), floori(p.y / WEED_CELL))
				var key := "fy_tuft_%d_%d_%d" % [v, cell.x, cell.y]
				var dry := 0.85 + float((h >> 3) % 30) / 100.0
				ch._batch.add(key, VacantKit.tuft(v), Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(sc, sc * (0.8 + float((h >> 9) % 50) / 100.0), sc)), Vector3(p.x, top, p.y)),
					Color(dry, dry * 0.97, dry * 0.86))
				keys[key] = WEED_DISTANCE
				# A taller weed where the ground is open (the ladder's side, the mains' outer edge).
				if id >= 99 and not inside and (h >> 14) % 9 == 0:
					var fen := (h >> 15) % 3 == 0
					var key2 := ("fy_fennel_%d_%d" if fen else "fy_mustard_%d_%d") % [cell.x, cell.y]
					var q := p + side * float(sg) * 0.6
					ch._batch.add(key2, VacantKit.fennel() if fen else VacantKit.mustard(), Transform3D(Basis(Vector3.UP, yaw * 1.7).scaled(Vector3.ONE * (0.7 + sc * 0.3)), Vector3(q.x, CityChunk.SIDEWALK_TOP + Industrial.LIFT, q.y)),
						Color(0.9, 0.88, 0.8))
					keys[key2] = TALL_DISTANCE
	for k: String in keys:
		ch._batch.set_no_shadow(k)
		ch._batch.set_draw_distance(k, float(keys[k]))
