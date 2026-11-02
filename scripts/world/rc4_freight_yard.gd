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
