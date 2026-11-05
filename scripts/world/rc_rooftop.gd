class_name RcRooftop
extends RefCounted
## The rooftop refcam (wave 6, `rooftop_golden` in tools/refcams/cameras_w6.json: downtown from a
## tower's helipad at 17:45, looking over the skyline to the basin and the sea; docs/HANDOFF.md "The
## skyline from a tower's roof"). One switch for what that view found:
##   * LandmarkRoofs: the downtown towers' bare mechanical boxes clad as louvred penthouses and
##     their flat roofs dressed with plant (its own LANDMARK_ROOFS=0 as well);
##   * the offshore island against a low sun as the air draws it (`island_soft` in
##     shaders/offshore_island.gdshaderinc), not a hard dark brown strip.
## RC_ROOFTOP=0 is the A/B of all of it (the city exactly as before).

static var enabled := OS.get_environment("RC_ROOFTOP") != "0"


## The sky shader's `island_soft` (OffshoreIsland pushes it once).
static func island_soft() -> float:
	return 1.0 if enabled else 0.0


## rooftop.gdshader's `pad_closeup` (Rooftops.material() sets it once): the helipad deck's planks,
## grit and worn paint up close.
static func pad_closeup() -> float:
	return 1.0 if enabled else 0.0


## The helipad's windsock in its own frame (the hoop at the origin, streaming along +Y, +Z down):
## a cone of cloth in SOCK_RINGS rings round SOCK_SIDES, sagging more toward the tail, the rings a
## little rippled, open at both ends - the
## old one was one 10-sided cone, a faceted orange tube in the middle of the rooftop view. UV.y
## runs from the hoop along the cloth as before (the shader's five bands every 0.48 m).
const SOCK_LEN := 2.4
const SOCK_RINGS := 8
const SOCK_SIDES := 18
const SOCK_DROOP := 0.42

static func windsock(g: RooftopGeo) -> void:
	var col := g._col(Color.WHITE, 15)
	var nb := g.xf.basis.inverse().transposed()
	var base := g.v.size()
	var circ := TAU * 0.38
	for j in SOCK_RINGS + 1:
		var t := float(j) / float(SOCK_RINGS)
		var along := t * SOCK_LEN
		var r := lerpf(0.38, 0.13, t) * (1.0 + 0.04 * sin(t * 9.0))
		# The tail sags (the frame's +Z is down: Rooftops builds it as (up x wind) x wind), more
		# toward the end: a parabola.
		var sag := SOCK_DROOP * t * t
		var centre := Vector3(0.0, along, sag)
		for k in SOCK_SIDES + 1:
			var a := TAU * float(k) / float(SOCK_SIDES)
			var dir := Vector3(cos(a), 0.0, sin(a))
			# Slack cloth: the sides fold in a little between the stitched seams.
			var rr := r * (1.0 - 0.05 * absf(sin(a * 2.0)) * t)
			g.v.append(g.xf * (centre + dir * rr))
			g.n.append((nb * dir).normalized())
			g.c.append(col)
			g.uv.append(Vector2(circ * float(k) / float(SOCK_SIDES), along))
			g.uv2.append(g.param)
	var row := SOCK_SIDES + 1
	for j in SOCK_RINGS:
		for k in SOCK_SIDES:
			var i0 := base + j * row + k
			var i1 := i0 + 1
			var i2 := i0 + row
			var i3 := i2 + 1
			# Both faces: the cloth is seen from inside through its open mouth.
			g.idx.append_array(PackedInt32Array([i0, i2, i1, i1, i2, i3, i0, i1, i2, i1, i3, i2]))
