class_name PortFill
extends RefCounted
## The container yard as full as a working terminal's (refcam port_crane, docs/HANDOFF.md "The
## container terminal from the crane"). The old yard rolled 1-3 boxes a pile and left 35 % of
## the slots empty, so from 45 m it read as a car park with a few boxes scattered on it. After
## every old roll (the block rng's slots and heights, the port_kit stream's looks) this tops each
## pile up to a terminal's 3-4 tiers and fills most of the empty slots - all from its OWN stream,
## hash(seed, ix, iz, "port_fill"), so every box the yard had before keeps its place and look.
## The truck lanes stay empty. PORT_FILL=0 is the A/B.

static var enabled: bool = OS.get_environment("PORT_FILL") != "0"

## Share of the rolled-empty slots that get a pile.
const FILL_SLOTS := 0.78
## A pile is topped up to this many tiers ...
const TIERS := 3
## ... and to one more this often (an RTG's 1-over-4).
const TALL_SHARE := 0.45
## Now and then a pile stays low (a slot being worked down).
const LOW_SHARE := 0.12


static func rng_for(seed_value: int, ix: int, iz: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = hash([seed_value, ix, iz, "port_fill"])
	return r


## Whether a slot the block rng left empty gets a pile (draws from `fill` only when enabled).
static func fills_slot(fill: RandomNumberGenerator) -> bool:
	return enabled and fill.randf() < FILL_SLOTS


## The tiers a pile of `n` boxes is topped up to.
static func target(n: int, fill: RandomNumberGenerator) -> int:
	if not enabled:
		return n
	var r := fill.randf()
	if r < LOW_SHARE:
		return n
	var t := TIERS + (1 if fill.randf() < TALL_SHARE else 0)
	return maxi(n, t)

## The yard's paving wear (road.gdshader's patches, cracks and oil): a terminal's concrete is
## patched and stained by thousands of tractor and straddle passes a day (was 0.6, a pavement's).
const YARD_WEAR := 1.5
