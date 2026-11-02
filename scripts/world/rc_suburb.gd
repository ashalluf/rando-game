class_name RcSuburb
## The suburb refcam (wave 5, rc2-suburb; docs/HANDOFF.md "The suburban street at 09:30"): what a
## suburban residential street gave away at eye level, fixed behind one switch.
##
## - Decomposed-granite front gardens read as orange clay courts (the tinted dry-ground scan):
##   lot_yard.gdshader's `dg_real` draws them a pale crushed-granite tan with grains.
## - The kerbs of a residential street were nearly empty at 09:30 (a suburb block's "parked" cap
##   of 8 spread over ~60 stalls, then the bins and the swept streets took some of those):
##   `resident_roll()` puts a resident's car on `RESIDENT_ODDS` of the stalls the block's own pass
##   and BusyStreets left undecided, from a hash of seed + spot after every roll, with every
##   keep-clear the old pass has (CityChunk._park_resident()), so nothing the seed built moves.
## - Lawn grass tufts stood up to 0.7 m in 2-3 cm blades: `TUFT_SCALE` cuts them to mowing height.
## - The parkway's soil edge was a vertical lawn-textured wall (a dark carpet-tile edge): a 45 degree
##   bevel (LawnsCloseup._strip_mesh()).
## - The code-built street trees' narrow-leaf sprigs were dithered per pixel from 4-8 m out (meant
##   for TAA to resolve); with no TAA (the web, Compatibility) they drew as horizontal streaks.
##   la_tree.gdshader's `sprig_dither_fix` holds the dither off until a leaf really is under a
##   pixel on Compatibility.
##
## RC2_SUBURB=0 is the A/B (all of it off). Checks: tests/rc2_suburb_checks.gd. Probe:
## tools/rc2_suburb/yard_probe.tscn (the front-garden kinds round a point).

static var enabled: bool = OS.get_environment("RC2_SUBURB") != "0"

## A lawn tuft's scale on top of its own (CityChunk._add_grass()): the blades stood 25 cm on
## average and up to 0.7 m, 2-3 cm wide - swords, not turf - so every lawn and parkway read as
## weeds at eye level. Half the height (mean ~12 cm), three quarters the width.
const TUFT_SCALE := Vector3(0.75, 0.5, 0.75)

## Share of the undecided kerb stalls of a residential block a resident's car takes.
const RESIDENT_ODDS := 0.3
## The districts whose kerbs are residents' (houses with no garage room for every car).
const RESIDENT_DISTRICTS := [CityPlan.District.SUBURBS, CityPlan.District.BEACHTOWN]


## Whether `district` gets the residents' cars.
static func residential(district: int) -> bool:
	return enabled and district in RESIDENT_DISTRICTS


## A pure roll per kerb stall (seed + the stall's position), independent of BusyStreets' roll.
static func resident_roll(seed_value: int, spot: Array) -> bool:
	var p: Vector3 = spot[0]
	return float(absi(hash([seed_value, roundi(p.x * 4.0), roundi(p.z * 4.0), "rc2_resident"])) % 10007) / 10007.0 < RESIDENT_ODDS


## That stall's car (its look and facing), from its own rng.
static func resident_rng(seed_value: int, spot: Array) -> RandomNumberGenerator:
	var p: Vector3 = spot[0]
	var r := RandomNumberGenerator.new()
	r.seed = hash([seed_value, roundi(p.x * 4.0), roundi(p.z * 4.0), "rc2_resident_car"])
	return r


## The yard ground material's switch (YardFill.yard_material()).
static func dress_yard(mat: ShaderMaterial) -> void:
	mat.set_shader_parameter("dg_real", 1.0 if enabled else 0.0)
