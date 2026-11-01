class_name FacadeVariety
extends RefCounted
## The facade pass (fleet "facades-gta", 2026-10-29: "this needs to start looking like GTA 6"): what
## stops a generated Building reading as a box wrapped in a perfect window grid at 30-500 m. Most
## of it is shader work in shaders/facade_variety.gdshaderinc, shared by the near walls
## (building.gdshader) and the far boxes (building_lod.gdshader): pane and floor variety, blinds,
## the street opposite mirrored with parallax, the members' depth, drips off the coping. This file
## is the CPU side: the switch, the facade system a curtain wall is built with (the shader's
## fx_system(), bit for bit, for probes and checks) and the bevelled corners of the near walls.
##
## `FACADES_GTA=0` in the environment turns the whole pass off (the A/B): the walls, the caps and
## the far boxes draw exactly as before.

static var enabled: bool = OS.get_environment("FACADES_GTA") != "0"

## The curtain wall systems (fx_system()): a flush unitised wall, deep fins, slab bands.
enum System { FLUSH, FINS, BANDS }

## How much a box part's vertical corners are cut back (metres each way): a pencil-round arris
## rather than a knife edge. Small enough to sit inside the first bay's frame on every window
## style (the curtain wall's glass starts 5 % of a bay in, a shop's 6 %).
const BEVEL := 0.22
## The share of a bay a bevel may take on a part with shops (their glass and the kit's jambs start
## at 6 % of the bay).
const BEVEL_SHOP_SHARE := 0.045


## fx_system(): the building's facade system from its shader seed (Building.seed % 1000) and its
## window style. Only curtain walls have one.
static func system(shader_seed: int, window_style: int) -> int:
	if window_style != Building.WindowStyle.CURTAIN:
		return System.FLUSH
	var k := float(Building.shop_hash(clampi(shader_seed, 0, 999), 70) >> 8) / 16777216.0
	if k < 0.5:
		return System.FLUSH
	return System.FINS if k < 0.76 else System.BANDS


## How far a box part's vertical corners are cut back, 0 for none: never on a part too narrow or
## too low to carry it, and on a part with shops no more than BEVEL_SHOP_SHARE of a bay.
static func bevel(size: Vector3, pitch: float, storefront: bool) -> float:
	if not enabled or minf(size.x, size.z) < 6.0 or size.y < 5.0:
		return 0.0
	var b := BEVEL
	if storefront:
		b = minf(b, pitch * BEVEL_SHOP_SHARE)
	return b if b >= 0.06 else 0.0
