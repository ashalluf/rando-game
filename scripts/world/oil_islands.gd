class_name OilIslands
extends RefCounted
## The decorated oil islands in San Pedro Bay (the FORM of the ones off Long Beach; every name
## invented): man-made islands of boulders a couple of hundred metres across, 600-700 m off the
## Long Beach sand east of the port (MacroMap.port_rect, bay_z, bay_east_x), each hiding a
## drilling site behind a planted berm, a sound wall and tall pastel towers that screen the rigs,
## with a waterfall down its shore face and coloured floodlight on the towers after dark.
##
## A DATA TABLE, like the replica areas: the islands are not seeded, they stand where the table
## says on every seed. Everything inside one (its outline's wobble, the towers' heights, colours
## and shapes, the palms) is a hash of the island's index and a salt (`h01()`), never an rng, so
## nothing else in the city rolls differently. Each island is its own landmark
## (`Landmarks.all()` appends `entries()`); `OilIslandBuild.build()` makes the far copy
## (CityStreamer's, the horizon view from the shore and the air) and the detailed one (the chunk
## that holds its anchor), the same builder with the small parts left out far.
##
## `OIL_ISLANDS=0` in the environment leaves them out (the A/B).

const ID_PREFIX := "oil_island_"
const OPERATOR := "BASIN CREST OIL CO."

## The islands: anchor (true world XZ), half extents of the pad (along / across its long axis),
## the long axis' turn (radians, from +X toward +Z), name, the number of rig towers.
const ISLANDS: Array[Dictionary] = [
	{"anchor": Vector2(3720.0, 6905.0), "half": Vector2(118.0, 74.0), "yaw": 0.10, "name": "KESTREL ISLAND", "towers": 4},
	{"anchor": Vector2(4060.0, 6985.0), "half": Vector2(104.0, 68.0), "yaw": -0.07, "name": "HALCYON ISLAND", "towers": 3},
	{"anchor": Vector2(4385.0, 6900.0), "half": Vector2(96.0, 62.0), "yaw": 0.16, "name": "CORVINA ISLAND", "towers": 3},
]

## The pad's top (metres over the sea's mean level, y 0), the revetment's rings outward of the
## pad edge: [distance out, height] - the crest cap, the waterline, the toe, the apron on the bed.
const PAD_Y := 4.5
const RINGS: Array = [[0.0, PAD_Y], [2.6, 4.25], [10.5, 0.0], [17.5, -3.6], [22.0, -5.2]]
## The planted berm inside the pad edge: from `BERM_IN` to `BERM_OUT` metres in, `BERM_H` high.
const BERM_OUT := 1.5
const BERM_IN := 17.0
const BERM_H := 2.2
## The sound wall's ring, metres in from the pad edge, and its heights over the pad.
const WALL_IN := 19.0
const WALL_H := Vector2(8.0, 12.5)
## Points round the outline (the far copy uses half).
const OUTLINE_SEGS := 120
## The waterfall faces the shore (north, -Z) - the side the city sees.
const FALLS_WIDTH := 20.0
const FALLS_TOP := 12.5
## A rig tower: footprint half size and height range over the pad.
const TOWER_HALF := 5.0
const TOWER_H := Vector2(46.0, 64.0)
## The night washes on the towers (linear RGB, the floods' gel colours).
const WASHES: Array[Color] = [
	Color(1.0, 0.25, 0.62), Color(0.55, 0.28, 1.0), Color(0.15, 0.55, 1.0), Color(0.1, 0.9, 0.62),
	Color(1.0, 0.62, 0.18), Color(1.0, 0.38, 0.3), Color(0.78, 0.55, 1.0), Color(0.2, 0.95, 0.95),
]
## The towers' pastel panels (sRGB paint).
const PASTELS: Array[Color] = [
	Color(0.96, 0.72, 0.66), Color(0.68, 0.86, 0.8), Color(0.8, 0.74, 0.92), Color(0.98, 0.88, 0.6),
	Color(0.62, 0.8, 0.93), Color(0.95, 0.66, 0.78),
]

static var enabled: bool = OS.get_environment("OIL_ISLANDS") != "0"


static func entries() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not enabled:
		return out
	for i in ISLANDS.size():
		var isl: Dictionary = ISLANDS[i]
		var half: Vector2 = isl.half
		out.append({"id": ID_PREFIX + str(i), "anchor": isl.anchor, "radius": half.x + 30.0})
	return out


static func is_island(id: String) -> bool:
	return id.begins_with(ID_PREFIX)


static func index_of(id: String) -> int:
	return int(id.substr(ID_PREFIX.length()))


## A hash in 0..1 of the island, a salt and a number.
static func h01(island: int, salt: String, n: int = 0) -> float:
	return float(hash([island, "oil_islands", salt, n]) & 0xffffff) / 16777216.0


## The pad edge's local point at polar angle t (radians round the island's own frame: x along the
## long axis): a superellipse with a slow wobble, so it reads as fill pushed out by hand rather than a
## drawn oval.
static func edge_local(island: int, t: float) -> Vector2:
	var half: Vector2 = ISLANDS[island].half
	var c := cos(t)
	var s := sin(t)
	var n := 3.2
	var r := 1.0 / pow(pow(absf(c) / half.x, n) + pow(absf(s) / half.y, n), 1.0 / n)
	var wob := 1.0 + 0.045 * sin(3.0 * t + 6.0 * h01(island, "w3")) + 0.03 * sin(5.0 * t + 6.0 * h01(island, "w5")) \
		+ 0.018 * sin(9.0 * t + 6.0 * h01(island, "w9"))
	var p := Vector2(c, s) * r
	return p * wob


## Local frame -> true world XZ.
static func to_world(island: int, p: Vector2) -> Vector2:
	var isl: Dictionary = ISLANDS[island]
	return (isl.anchor as Vector2) + p.rotated(float(isl.yaw))


## True world XZ -> local frame.
static func to_local(island: int, w: Vector2) -> Vector2:
	var isl: Dictionary = ISLANDS[island]
	return (w - (isl.anchor as Vector2)).rotated(-float(isl.yaw))


## The outward normal of the outline at t (local frame).
static func edge_normal(island: int, t: float) -> Vector2:
	var a := edge_local(island, t - 0.004)
	var b := edge_local(island, t + 0.004)
	var d := b - a
	return Vector2(d.y, -d.x).normalized() if Vector2(d.y, -d.x).dot(edge_local(island, t)) > 0.0 else Vector2(-d.y, d.x).normalized()


## A point `d` metres outward of the pad edge at t (negative: in from it), local frame.
static func ring_local(island: int, t: float, d: float) -> Vector2:
	return edge_local(island, t) + edge_normal(island, t) * d


## How far `w` (true world XZ) is outside the pad edge of island i (negative inside), roughly:
## along the ray from the island's centre.
static func edge_distance(island: int, w: Vector2) -> float:
	var l := to_local(island, w)
	var t := atan2(l.y, l.x)
	return l.length() - edge_local(island, t).length()


## The ground the island stands its things on at true world XZ, or NAN when off every island:
## the pad, the berm's mound, the revetment's slope (for tests and placing).
static func surface_at(w: Vector2) -> float:
	if not enabled:
		return NAN
	for i in ISLANDS.size():
		var d := edge_distance(i, w)
		if d > float(RINGS[RINGS.size() - 1][0]):
			continue
		if d >= 0.0:
			for k in RINGS.size() - 1:
				var a: Array = RINGS[k]
				var b: Array = RINGS[k + 1]
				if d <= float(b[0]):
					return lerpf(float(a[1]), float(b[1]), (d - float(a[0])) / (float(b[0]) - float(a[0])))
		return PAD_Y + berm_height(-d)
	return NAN


## The berm's height over the pad at `inward` metres in from the pad edge.
static func berm_height(inward: float) -> float:
	if inward <= BERM_OUT or inward >= BERM_IN:
		return 0.0
	var u := (inward - BERM_OUT) / (BERM_IN - BERM_OUT)
	return BERM_H * pow(sin(PI * u), 0.8)


## The island whose pad (with its revetment) holds `w`, or -1.
static func island_at(w: Vector2) -> int:
	if not enabled:
		return -1
	for i in ISLANDS.size():
		if edge_distance(i, w) <= float(RINGS[RINGS.size() - 1][0]):
			return i
	return -1


## The rig towers of island i: local centre, height, wash index, panel colour index, a seed, and
## which corner carries the curved shell. Spread along the long axis inside the wall.
static func towers(island: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var isl: Dictionary = ISLANDS[island]
	var n: int = isl.towers
	var half: Vector2 = isl.half
	var span := half.x - WALL_IN - 22.0
	for k in n:
		var f := (float(k) + 0.5) / float(n) * 2.0 - 1.0
		var x := f * span + (h01(island, "tx", k) - 0.5) * 8.0
		var z := (h01(island, "tz", k) - 0.5) * (half.y - WALL_IN - 20.0) * 0.6
		out.append({"at": Vector2(x, z), "h": lerpf(TOWER_H.x, TOWER_H.y, h01(island, "th", k)),
			"wash": int(h01(island, "tw", k) * float(WASHES.size())) % WASHES.size(),
			"wash2": int(h01(island, "tw2", k) * float(WASHES.size())) % WASHES.size(),
			"paint": int(h01(island, "tp", k) * float(PASTELS.size())) % PASTELS.size(),
			"shell": int(h01(island, "ts", k) * 4.0) % 4,
			"seed": k})
	return out


## The angle (round the island's own frame) at which the waterfall pours: the point of the
## outline nearest the shore (world -Z), a little off it by hash.
static func falls_angle(island: int) -> float:
	var yaw: float = ISLANDS[island].yaw
	# Local direction of world -Z (north, toward Long Beach).
	var north := Vector2(0.0, -1.0).rotated(-yaw)
	return atan2(north.y, north.x) + (h01(island, "fa") - 0.5) * 0.5
