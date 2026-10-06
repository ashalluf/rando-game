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
## hill_splat.gdshaderinc: the stand noise's octave weights and bias (hill_stand_noise()).
const STAND_PATCH_W := 0.2
const STAND_MID_W := 0.1
const STAND_BUSH_W := 0.4
const STAND_FINE_W := 0.3
const STAND_BIAS := 0.35

## The shader's uniforms this file mirrors, by name, for the smoke test.
const MIRRORED := {
	"chaparral_amount": CHAPARRAL_AMOUNT, "north_brush": NORTH_BRUSH,
	"dirt_slope_start": DIRT_SLOPE_START, "dirt_slope_end": DIRT_SLOPE_END,
	"rock_slope_start": ROCK_SLOPE_START, "rock_slope_end": ROCK_SLOPE_END,
	"trail_amount": TRAIL_AMOUNT,
	"drain_brush": DRAIN_BRUSH, "gentle_grass": GENTLE_GRASS,
	"gully_scree": GULLY_SCREE, "crest_rock": CREST_ROCK, "topo_weight": TOPO_WEIGHT,
	"south_grass": SOUTH_GRASS, "crown_edge": CROWN_EDGE,
}
## The shader constants this file mirrors, by name, for the smoke test.
const MIRRORED_CONSTS := {"CROWN_CELL": CROWN_CELL, "CROWN_MEAN": CROWN_MEAN,
	"STAND_PATCH_W": STAND_PATCH_W, "STAND_MID_W": STAND_MID_W, "STAND_BUSH_W": STAND_BUSH_W,
	"STAND_FINE_W": STAND_FINE_W, "STAND_BIAS": STAND_BIAS}


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
static func ground(w: Vector2, grad: Vector2, trails: bool = true, drain: float = 0.0) -> Dictionary:
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
	var th := 0.5 + (coverage - 0.5) * TOPO_WEIGHT
	var bush := vnoise(w * 0.29 + Vector2(3.7, 3.7))
	var frag := patchy * STAND_PATCH_W + vnoise(w * 0.12 + Vector2(17.0, 17.0)) * STAND_MID_W \
			+ (bush - 0.5) * STAND_BUSH_W + (vnoise(w * 0.9 + Vector2(51.0, 51.0)) - 0.5) * STAND_FINE_W + STAND_BIAS
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
