class_name RcRidgeSign
## The ridge-sign reference camera's fixes (fleet wave 6, `rc3-ridge-sign`; docs/HANDOFF.md "The
## ridge sign refcam"): what read fake in the big sign on the front range from 120 m at 16:30.
## `RC3_SIGN=0` in the environment is the A/B - every fix below goes back to main's look.
##
## - The letters: each stroke a mitred ribbon (clean bowls and corners, no box notches or coplanar
##   faces fighting), on a sheet-metal shader (4 x 8 ft panels, seams, dust at the foot, streaks
##   from the fixings) instead of one flat cream colour (HillSignLetters._letters_v2()).
## - The frame: braced to the slope (raking struts), not a cage of bare poles hanging below.
## - The hill round it: the code-built shrubs gathered into thickets with gaps by RcHills' cluster
##   field and sized by it (CityChunk._plant_hills), not one even scatter of identical green balls.

static var _on: int = -1


static func on() -> bool:
	if _on < 0:
		_on = 0 if OS.get_environment("RC3_SIGN") == "0" else 1
	return _on == 1


## The hills' code-built shrubs (CityChunk._plant_hills, HillShrub): from the ridge sign every stand
## was one even scatter of identical round mounds - polka dots. RcHills' cluster field (its own
## phase and a wider cell here) gathers them: under SHRUB_GAP (+ a little by the shrub's own size
## roll) a shrub is left out, above it it is scaled up to SHRUB_SCALE.y where the field is full, so
## the mounds of a thicket close up and the gaps between thickets show the straw. The scale to
## apply, 0 for none. Pure: a point and its size roll, nothing else.
const SHRUB_GAP := 0.3
const SHRUB_SCALE := Vector2(0.7, 1.55)
const SHRUB_FIELD_SCALE := 0.7


static func shrub_gather(p: Vector2, size_roll: float) -> float:
	if not on():
		return 1.0
	var c := RcHills.cluster(p * SHRUB_FIELD_SCALE + Vector2(53.0, -21.0))
	if c < SHRUB_GAP + 0.14 * size_roll:
		return 0.0
	return lerpf(SHRUB_SCALE.x, SHRUB_SCALE.y, clampf((c - SHRUB_GAP) / (1.0 - SHRUB_GAP), 0.0, 1.0))


## A plaza block past the FULL ring (CityChunk._build_plaza at LOD, and the far city's capture of
## it) was one bare slab of paving: from the ridge a 230 m tan square at the foot of the hill. It
## now lays the four lawn beds the FULL build furnishes (the same rects as _furnish_plaza(), worked
## out from the block alone: no roll), a little proud of the paving.
static func plaza_far_beds(ch, inner: Rect2) -> void:
	if not on():
		return
	var center := inner.get_center()
	var basin_r := minf(inner.size.x, inner.size.y) * 0.12
	var keep := basin_r + 9.0
	var bw := clampf(inner.size.x * 0.24, 8.0, 26.0)
	var bd := clampf(inner.size.y * 0.24, 8.0, 26.0)
	var lawn := PropFactory.lawn(Color(0.40, 0.52, 0.24), hash([ch.plan.seed, ch.ix, ch.iz, "plaza_bed"]), 0.2, 0.0)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var off := Vector2(sx * maxf(keep + bw * 0.5, inner.size.x * 0.26), sz * maxf(keep * 0.7 + bd * 0.5, inner.size.y * 0.26))
			var c := center + off
			var bed := Rect2(c - Vector2(bw, bd) * 0.5, Vector2(bw, bd))
			if not inner.grow(-7.0).encloses(bed):
				continue
			ch._add_slab(Vector3(c.x, 0.25 + 0.3, c.y), Vector3(bw, 0.5, bd), ch.style.grass, false, lawn)


## The horizon plane under a block that straddles a hill's foot (MacroMap.bake()): the chunk takes
## its zone from the block's centre, so a block whose centre is on the slope builds hill terrain
## over its flat basin half too - but the bake painted that half by its own zone, a city district,
## and the far plane drew it as an empty grid of grey streets (four blocks of it at the foot of the
## ridge sign, 800 m out). The bake now asks this for each city pixel: the zone of the block there.
static func block_zone_fn(plan) -> Callable:
	if not on():
		return Callable()
	var cache := {}
	return func(pos: Vector2) -> int:
		var bi: Vector2i = plan.block_index_at(pos)
		if not cache.has(bi):
			var b: Dictionary = plan.block(bi.x, bi.y)
			cache[bi] = int(plan.zone_at((b.rect as Rect2).get_center()))
		return cache[bi]


## The tors a hill chunk claims stand on the terrain that chunk draws (RockBuild._claim ->
## RockFar.claim): a LOD tile samples the ground every ~14 m and cuts a sharp summit tens of metres
## low, so the summit crag RcHills beds in the crown, left at the true height, floated in the sky
## over the drawn hill (a pale slab over the ridge west of the sign). id -> metres to move it
## (clamped: a tor never goes up, and never further down than its own height under the true ground
## would bury it whole). Empty when off.
const TOR_DROP_MAX := 40.0


static func tor_drops(ch, ids: Array) -> Dictionary:
	var out := {}
	if not on():
		return out
	var all: Array = RockOutcrops.tors(ch.plan)
	for id: int in ids:
		if id < 0 or id >= all.size():
			continue
		var t: Dictionary = all[id]
		var p: Vector2 = t.pos
		var drawn: float = ch._terrain_height(p)
		var dy := drawn - float(ch.plan.height_at(p))
		if bool(t.get("summit", false)):
			dy = minf(dy, _overhang(ch, t))
		dy = clampf(dy, -TOR_DROP_MAX, 0.0)
		if dy < -0.5:
			out[int(t.id)] = dy
	return out



## A summit crag is broad and low (RcHills) but the front range's summits are spikes: its far end
## stood out over the falling ground, a pale slab in the sky. The drop that brings the tor's
## footprint edges (eight points round its bounds, through its own basis) down to where the lowest
## OVERHANG_SHARE of its height meets the ground the chunk draws there.
const OVERHANG_SHARE := 0.3


static func _overhang(ch, t: Dictionary) -> float:
	var b: AABB = RockKit.bounds(int(t.kind))
	var basis: Basis = t.basis
	var origin := Vector3(t.pos.x, float(t.y), t.pos.y)
	var lo := INF
	var h := (basis * Vector3(0.0, b.size.y, 0.0)).y
	for i in 8:
		var a := TAU * float(i) / 8.0
		var l := Vector3(b.get_center().x + cos(a) * b.size.x * 0.5, b.position.y, b.get_center().z + sin(a) * b.size.z * 0.5)
		var w := origin + basis * l
		var need: float = ch._terrain_height(Vector2(w.x, w.z)) - (w.y + h * OVERHANG_SHARE)
		lo = minf(lo, need)
	return minf(lo, 0.0)
