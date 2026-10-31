class_name Waders
extends RefCounted
## People standing in the shallows (wave 4, rc-beach): the one thing every photograph of a Los Angeles
## beach at two in the afternoon has and the beach refcam did not - its whole near water was empty.
## The surfers sit out past the break (60 m off, a few pixels high in the swell) and the swimmers are
## few and often none in a stretch, so from the waterline the sea read as a pool nobody was in.
##
## A wader is the swimmers' standing bake (BeachFigure.beach_mesh, STAND, the person's swimsuit) put
## with its soles on the sand UNDER the water - the steep foreshore the sand mesh draws (CityChunk's
## rows: SAND_EDGE at the waterline, SAND_STEEP_Y at SAND_STEEP_AT out, SAND_LOW at SAND_WET) - in
## groups of one to three: a pair or three talking face to face, someone alone looking out to sea,
## from ankle-deep on the swash's wet sand to waist-deep where the bottom drops away. They shift
## their weight (a slow turn of a few degrees) and that is all: still figures in BeachActivity's
## water list, ticked only near the player like the swimmers.
##
## Rolled from hashes of the seed and the stretch (BeachActivity._h), never an rng: the count from
## BeachLife.plan_activity()'s "waders". `WADERS=0` in the environment turns them off (the A/B).

static var enabled: bool = OS.get_environment("WADERS") != "0"

## How far out (m from the waterline, + seaward) a group may stand, and how deep at most (m of water
## over the soles at the sea's rest level).
const S_MIN := -0.8
const S_MAX := 4.6
const MAX_DEPTH := 1.05
## The rest level of the sea (the swimmers' and the ocean plane's).
const SEA_Y := 0.15
## Spacing between people of a group (m), and how far a group stays inside the chunk's ends (m).
const SPACING := Vector2(0.75, 1.25)
const END_PAD := 4.0


## The water list entries for `count` waders in BeachActivity `act`'s stretch.
static func place(act: BeachActivity, count: int) -> Array:
	var out: Array = []
	if not enabled or count <= 0 or act.plan_ref == null or act.plan_ref.macro == null:
		return out
	var g := 0
	var i := 0
	while i < count and g < count * 2:
		var pick := act._h(["wade_n", g])
		var size := 1 if pick < 0.38 else (2 if pick < 0.8 else 3)
		size = mini(size, count - i)
		var z := lerpf(act.z0 + END_PAD, act.z1 - END_PAD, act._h(["wade_z", g]))
		# Most stand shin- to knee-deep; a few wander out to the waist.
		var s := lerpf(S_MIN, S_MAX, pow(act._h(["wade_s", g]), 1.25))
		var face := act._h(["wade_face", g]) * TAU
		for m in size:
			var who := act._person(i, "wader")
			var mesh := BeachFigure.beach_mesh(who[2], RoughSleeper.Pose.STAND, "", who[1], who[0])
			i += 1
			if mesh == null:
				continue
			# Round the group's middle, each turned to face it; alone, looking out to sea.
			var a := face + TAU * float(m) / float(size)
			var r := 0.0 if size == 1 else lerpf(SPACING.x, SPACING.y, act._h(["wade_r", g, m])) * 0.5
			var off := Vector2(cos(a), sin(a)) * r
			var yaw := PI * 0.5 + (act._h(["wade_yaw", g]) - 0.5) * 1.1
			if size > 1:
				# A node's -Z faces the way it looks: toward the middle, (-off).
				yaw = atan2(off.x, off.y)
			var ms := s + off.x * -1.0
			if bed_y(act, ms, z + off.y) < SEA_Y - MAX_DEPTH:
				continue
			var node := act._figure(mesh, null)
			out.append({"node": node, "kind": "wade", "s": ms, "z": z + off.y, "yaw": yaw,
				"phase": act._h(["wade_ph", g, m]) * TAU})
		g += 1
	return out


## The sand's height `s` metres seaward of the waterline at `z` (landward of it, negative s, the
## swash's sand as BeachLife reads it): the sand mesh's own straight runs.
static func bed_y(act: BeachActivity, s: float, z: float) -> float:
	if s <= 0.0:
		return BeachLife.sand_y(act.chunk, act.plan_ref.macro.coast_x(z) - s, z)
	if s < CityChunk.SAND_STEEP_AT:
		return lerpf(CityChunk.SAND_EDGE, CityChunk.SAND_STEEP_Y, s / CityChunk.SAND_STEEP_AT)
	return lerpf(CityChunk.SAND_STEEP_Y, CityChunk.SAND_LOW, clampf((s - CityChunk.SAND_STEEP_AT) / (CityChunk.SAND_WET - CityChunk.SAND_STEEP_AT), 0.0, 1.0))


## Each tick (near the player): soles on the sand, a slow shift of weight.
static func pose(w: Dictionary, x: float, z: float, clock: float) -> void:
	var node: Node3D = w.node
	var s: float = w.s
	if not w.has("y"):
		w.y = 0.0
		var act := node.get_parent() as BeachActivity
		if act:
			w.y = bed_y(act, s, z)
	var yaw: float = float(w.yaw) + sin(clock * 0.31 + float(w.phase)) * 0.12
	node.transform = Transform3D(Basis(Vector3.UP, yaw), Vector3(x, float(w.y), z))
