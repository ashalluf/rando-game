class_name HillPlanting
extends RefCounted
## Where the hills' planting goes: the ground the terrain shader paints, worked out on the CPU.
##
## shaders/terrain.gdshader decides per pixel whether a patch of hillside is dry grass, a stand
## of chaparral, bare dirt or rock, from the slope, which way the slope faces and a few octaves
## of world-space value noise. The shrubs and trees on the hills (CityChunk._plant_hills near,
## Skyline._add_hills far) have to agree with it - a bush on painted straw beside a bare painted
## brush stand reads as two layers that know nothing of each other - so this is the very same
## maths: the same hash, the same noise, the same octaves and offsets, the same thresholds.
## The numbers below are that shader's uniform defaults (nothing sets them; they live in
## shaders/hill_splat.gdshaderinc, which the terrain and the hill shells both include), and the
## smoke test reads the shader source to check they still match.
##
## Everything takes TRUE world XZ, like the shader (`world_pos.xz + world_offset`).

## terrain.gdshader: how much of the ground is chaparral, and how much more the north faces carry.
const CHAPARRAL_AMOUNT := 0.8
const NORTH_BRUSH := 0.3
## terrain.gdshader: brush in the gullies, grass on the gentle ground, scree and crest rock.
const DRAIN_BRUSH := 0.6
const GENTLE_GRASS := 0.55
const GULLY_SCREE := 0.5
const CREST_ROCK := 0.8
## terrain.gdshader: how much the land decides the stands against the patch noise.
const TOPO_WEIGHT := 0.8
const SOUTH_GRASS := 0.35
## terrain.gdshader: the slopes (1 - normal.y) where bare dirt and rock take over.
const DIRT_SLOPE_START := 0.42
const DIRT_SLOPE_END := 0.62
const ROCK_SLOPE_START := 0.5
const ROCK_SLOPE_END := 0.72
const TRAIL_AMOUNT := 0.8
## hill_splat.gdshaderinc: how far the shrub crowns push a stand's edge, the metres between the
## crowns and the crown field's mean (hill_crowns()).
const CROWN_EDGE := 0.06
const CROWN_CELL := 2.6
const CROWN_MEAN := 0.35
## hill_splat.gdshaderinc: the stand noise's octave weights and bias (hill_stand_noise()), and how
## much the fine erosion rills push the stands (hill_rill_th()). hill-ground-3: the patch octaves
## carry most of the spread, so a stand is a mass at any distance (HillGround3).
const STAND_PATCH_W := 0.5
const STAND_MID_W := 0.14
const STAND_BUSH_W := 0.18
const STAND_FINE_W := 0.12
const STAND_BIAS := 0.18
const RILL_BRUSH := 0.3
## hill_splat.gdshaderinc: the range of hill_rill_th()'s slow modulation.
const RILL_REACH_LOW := 0.2
const RILL_REACH_HIGH := 1.4
## erosion.gdshaderinc / terrain.gdshader: the fine erosion orders the rills come from.
const EROSION_JITTER := 0.45
const EROSION_BRANCH := 0.8
const EROSION_AMP := 3.0
const EROSION_CELL := 55.0

## The shader's uniforms this file mirrors, by name, for the smoke test.
const MIRRORED := {
	"chaparral_amount": CHAPARRAL_AMOUNT, "north_brush": NORTH_BRUSH,
	"dirt_slope_start": DIRT_SLOPE_START, "dirt_slope_end": DIRT_SLOPE_END,
	"rock_slope_start": ROCK_SLOPE_START, "rock_slope_end": ROCK_SLOPE_END,
	"trail_amount": TRAIL_AMOUNT,
	"drain_brush": DRAIN_BRUSH, "gentle_grass": GENTLE_GRASS,
	"gully_scree": GULLY_SCREE, "crest_rock": CREST_ROCK, "topo_weight": TOPO_WEIGHT,
	"south_grass": SOUTH_GRASS, "crown_edge": CROWN_EDGE,
	"stand_patch_w": STAND_PATCH_W, "stand_mid_w": STAND_MID_W, "stand_bush_w": STAND_BUSH_W,
	"stand_fine_w": STAND_FINE_W, "stand_bias": STAND_BIAS, "rill_brush": RILL_BRUSH,
}
## The shader constants this file mirrors, by name, for the smoke test.
const MIRRORED_CONSTS := {"CROWN_CELL": CROWN_CELL, "CROWN_MEAN": CROWN_MEAN,
	"RILL_REACH_LOW": RILL_REACH_LOW, "RILL_REACH_HIGH": RILL_REACH_HIGH}

## The numbers ground() uses: the constants above, or with HILL_GROUND_3=0 the old ones
## (HillGround3.OLD), as the shaders get them.
static var _w: Dictionary = {}


static func _weights() -> Dictionary:
	if _w.is_empty():
		_w = {"patch": STAND_PATCH_W, "mid": STAND_MID_W, "bush": STAND_BUSH_W, "fine": STAND_FINE_W,
			"bias": STAND_BIAS, "rill": RILL_BRUSH, "jitter": EROSION_JITTER, "branch": EROSION_BRANCH,
			"amp": EROSION_AMP}
		if not HillGround3.enabled:
			var o: Dictionary = HillGround3.OLD
			_w = {"patch": o.stand_patch_w, "mid": o.stand_mid_w, "bush": o.stand_bush_w, "fine": o.stand_fine_w,
				"bias": o.stand_bias, "rill": o.rill_brush, "jitter": o.erosion_jitter, "branch": o.erosion_branch,
				"amp": o.erosion_amp}
	return _w


## hill_splat.gdshaderinc hash12t().
static func hash12(p: Vector2) -> float:
	var x := fposmod(p.x * 0.1031, 1.0)
	var y := fposmod(p.y * 0.1031, 1.0)
	var z := x
	var d := x * (y + 33.33) + y * (z + 33.33) + z * (x + 33.33)
	x += d
	y += d
	z += d
	return fposmod((x + y) * z, 1.0)


## hill_splat.gdshaderinc vnoiset(): value noise, smoothstepped, 0..1.
static func vnoise(p: Vector2) -> float:
	var i := p.floor()
	var fx := p.x - i.x
	var fy := p.y - i.y
	fx = fx * fx * (3.0 - 2.0 * fx)
	fy = fy * fy * (3.0 - 2.0 * fy)
	var a := hash12(i)
	var b := hash12(i + Vector2(1.0, 0.0))
	var c := hash12(i + Vector2(0.0, 1.0))
	var d := hash12(i + Vector2(1.0, 1.0))
	return lerpf(lerpf(a, b, fx), lerpf(c, d, fx), fy)


static func _smooth(e0: float, e1: float, x: float) -> float:
	var t := clampf((x - e0) / (e1 - e0), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


## The ground at `w` (true world XZ) whose height rises by `grad` metres per metre (dh/dx,
## dh/dz), as the terrain shader paints it:
##   brush  0..1  a chaparral stand (0.5 is the stand's edge)
##   bare   0..1  dirt: steep cuts, road banks, trails
##   rocky  0..1  rock outcrop
##   north  -1..1 which way the slope faces (+1 north)
##   slope  1 - normal.y
## The per-bush octave is in: the shader's stand edges are ragged at the scale of one bush.
## `trails` false skips the metre-wide trails (the far tier's mounds are wider than one).
## `drain` is MacroMap.drainage_at(w) (-1 spur crest .. +1 gully), which the shader gets
## through the terrain's vertex colour.
static func ground(w: Vector2, grad: Vector2, trails: bool = true, drain: float = 0.0, rill_at: float = INF) -> Dictionary:
	var n := Vector3(-grad.x, 1.0, -grad.y).normalized()
	var slope := 1.0 - clampf(n.y, 0.0, 1.0)
	var flat := Vector2(n.x, n.z).length()
	var north := -n.z / maxf(flat, 0.001) * _smooth(0.02, 0.12, slope)
	var hill := vnoise(w * 0.0028)
	var patchy := vnoise(w * 0.011) * 0.65 + vnoise(w * 0.037 + Vector2(13.1, 13.1)) * 0.35
	var gentle := 1.0 - _smooth(0.06, 0.22, slope)
	var south := maxf(-north, 0.0)
	var coverage := CHAPARRAL_AMOUNT + maxf(north, 0.0) * NORTH_BRUSH - south * SOUTH_GRASS \
			+ drain * DRAIN_BRUSH - gentle * GENTLE_GRASS + (hill - 0.5) * 0.2
	var wt := _weights()
	var th := 0.5 + (coverage - 0.5) * TOPO_WEIGHT
	# The stands follow the fine erosion rills (hill_rill_th(): the shader's z, both orders resolved).
	# `rill_at` is rill_th() off the tile's own grid when the caller has it (CityChunk._tile_rills).
	if float(wt.rill) > 0.0:
		th += (rill_at if rill_at != INF else rill_th(w, grad)) * float(wt.rill) * TOPO_WEIGHT * rill_reach(w)
	var bush := vnoise(w * 0.29 + Vector2(3.7, 3.7))
	var frag := patchy * float(wt.patch) + vnoise(w * 0.12 + Vector2(17.0, 17.0)) * float(wt.mid) \
			+ (bush - 0.5) * float(wt.bush) + (vnoise(w * 0.9 + Vector2(51.0, 51.0)) - 0.5) * float(wt.fine) + float(wt.bias)
	# The stand's edge runs round the shrub crowns (the shader's hill_stand_crowned(), resolved).
	frag -= (crown(w) - CROWN_MEAN) * CROWN_EDGE
	# The shader's stand edge is 0.09 wide in `frag`; as a 0..1 share it is the same test, softer.
	var brush := _smooth(th + 0.09, th - 0.09, frag)
	var bare := _smooth(DIRT_SLOPE_START, DIRT_SLOPE_END, slope + (patchy - 0.5) * 0.3)
	bare = maxf(bare, _smooth(0.3, 0.8, drain) * _smooth(0.32, 0.48, slope) * GULLY_SCREE)
	if trails:
		var tn := vnoise(w * 0.0065 + Vector2(41.0, 41.0))
		# A trail is about a metre wide; anything within a couple of metres of one stays clear.
		var trail := 1.0 - _smooth(0.0035, 0.012, absf(tn - 0.5))
		trail *= _smooth(0.55, 0.7, vnoise(w * 0.0021 + Vector2(7.0, 7.0))) * (1.0 - _smooth(0.18, 0.30, slope)) * TRAIL_AMOUNT
		bare = maxf(bare, trail * 0.9)
	var crag := vnoise(w * 0.021 + Vector2(29.0, 29.0))
	var rocky := _smooth(ROCK_SLOPE_START, ROCK_SLOPE_END, slope + (crag - 0.5) * 0.22)
	rocky = maxf(rocky, _smooth(0.78, 0.86, crag * 0.7 + patchy * 0.3) * _smooth(0.10, 0.22, slope))
	rocky = maxf(rocky, _smooth(0.2, 0.7, -drain) * _smooth(0.14, 0.3, slope) * _smooth(0.42, 0.62, crag * 0.6 + bush * 0.4) * CREST_ROCK)
	return {"brush": brush, "bare": bare, "rocky": rocky, "north": north, "slope": slope}


## hill_splat.gdshaderinc hill_rill_th()'s slow modulation: some faces follow their rills hard,
## others hardly (a ~180 m noise), so the streaks come and go instead of combing every slope.
static func rill_reach(w: Vector2) -> float:
	return lerpf(RILL_REACH_LOW, RILL_REACH_HIGH, vnoise(w * 0.0055 + Vector2(61.0, 61.0)))


## Whether the stands follow the rills at all (off with HILL_GROUND_3=0).
static func rills_on() -> bool:
	return float(_weights().rill) > 0.0


## The rills as the shaders' stand rule takes them (hill_rill_th()'s argument): erosion_detail().z
## times the steepness that scaled its depth, on ground falling by `grad`.
static func rill_th(w: Vector2, grad: Vector2) -> float:
	var steep := _smooth(0.08, 0.45, grad.length())
	if steep <= 0.0:
		return 0.0
	return rill(w, grad, float(_weights().amp) * steep) * steep


## erosion.gdshaderinc erosion_hash().
static func _ehash(p: Vector2) -> Vector2:
	var x := fposmod(p.x * 0.1031, 1.0)
	var y := fposmod(p.y * 0.1030, 1.0)
	var z := fposmod(p.x * 0.0973, 1.0)
	var d := x * (y + 33.33) + y * (z + 33.33) + z * (x + 33.33)
	x += d
	y += d
	z += d
	return Vector2(fposmod((x + y) * z, 1.0), fposmod((x + z) * y, 1.0))


## erosion.gdshaderinc erosion_cells(): one order at `p` (cells), stripes varying along `dir`.
static func _ecells(p: Vector2, dir: Vector2, jitter: float) -> Vector3:
	var ip := p.floor()
	var fp := p - ip
	var va := Vector3.ZERO
	var wt := 0.0
	for j in range(-2, 2):
		for i in range(-2, 2):
			var o := Vector2(i, j)
			var pp := fp + o - _ehash(ip - o) * jitter
			var w := maxf(exp(-pp.length_squared() * 2.0) - 0.0889, 0.0)
			var mag := pp.dot(dir) * TAU
			var sn := -sin(mag) * TAU
			va += Vector3(cos(mag), sn * dir.x, sn * dir.y) * w
			wt += w
	return va / maxf(wt, 0.0001)


## erosion.gdshaderinc erosion_detail().z with both orders resolved: how deep in a fine rill `w`
## sits (-1 crest .. +1 floor) on ground that falls by `grad`, the first order `amp` metres deep.
static func rill(w: Vector2, grad: Vector2, amp: float) -> float:
	var wt := _weights()
	var acc := Vector3.ZERO
	var a := amp
	var c := EROSION_CELL
	var wsum := 0.0
	for o in 2:
		var d := grad + Vector2(acc.x, acc.y) * float(wt.branch)
		var dir := Vector2(d.y, -d.x)
		var l := dir.length()
		dir = dir / l if l > 0.00001 else Vector2(1.0, 0.0)
		var f := _smooth(0.02, 0.2, l)
		var e := _ecells(w / c, dir, float(wt.jitter))
		acc.x += e.y * (a / c) * f
		acc.y += e.z * (a / c) * f
		acc.z += -e.x * f * a
		wsum += a
		a *= 0.5
		c *= 0.5
	return acc.z / maxf(wsum, 0.0001)


## hill_splat.gdshaderinc hill_crowns().x: the height (0..1) of the shrub crown canopy at `w`,
## a dome per jittered CROWN_CELL cell, the tallest of the four nearest.
static func crown(w: Vector2) -> float:
	var q := w / CROWN_CELL
	var b := (q - Vector2(0.5, 0.5)).floor()
	var best := 0.0
	for j in 2:
		for i in 2:
			var c := b + Vector2(i, j)
			var hx := hash12(c)
			var hy := hash12(c + Vector2(41.7, 17.3))
			var dv := (q - (c + Vector2(0.5, 0.5) + (Vector2(hx, hy) - Vector2(0.5, 0.5)) * 0.6)) / (0.32 + 0.3 * fposmod(hx * 7.13 + hy * 3.71, 1.0))
			var h := sqrt(maxf(1.0 - dv.length_squared(), 0.0)) * (0.55 + 0.45 * hy)
			best = maxf(best, h)
	return best


## How much of a hollow `w` sits in: the mean ground `reach` metres round it above the ground at
## it, per metre of reach. Positive in gullies and at the foot of a slope, where the water runs
## and the oaks and sycamores grow; negative on spurs and ridges. `height` is a Callable(Vector2)
## -> float.
static func hollow(w: Vector2, h: float, reach: float, height: Callable) -> float:
	var sum := 0.0
	for k in 6:
		var a := TAU * float(k) / 6.0
		sum += float(height.call(w + Vector2(cos(a), sin(a)) * reach))
	return (sum / 6.0 - h) / reach
