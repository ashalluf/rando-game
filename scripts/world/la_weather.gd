class_name LaWeather
extends RefCounted
## Los Angeles weather beyond rain: the numbers the marine layer and the Santa Ana share between
## Weather (the Environment, DayNight's hooks), MarineLayer (the deck and the evening fog bank),
## SantaAnaFx (blowing litter and dust, the brush fire) and HeatHaze. Pure functions of the hour
## and the place, so a still at 09:00 and a test agree on where the deck is.
##
## The marine layer ("June gloom") is a stratus deck from DECK_BASE to DECK_TOP. Where it is, is
## one number: `edge_x(hour, z)` - the deck covers everything WEST of it (the ocean side; the
## coast runs north-south at MacroMap.coast_base_x). Overnight the edge is far inland, so the
## whole basin is under it; through the morning it burns off from inland toward the coast
## (downtown clears about 10:30, the beach about 12:00); in the afternoon it waits offshore as a
## bank; from 17:00 it rolls back in LOW (a fog bank on the water, its top `BANK_TOP`), standing
## about a mile off the beach at 18:30, ashore by 20:30 and over the city by 22:00.

## Underside and top of the stratus deck (true world metres). Downtown's tallest towers (262-335 m)
## stand into it.
const DECK_BASE := 255.0
const DECK_TOP := 520.0
## The evening fog bank's underside and top: it comes in off the water lower than the morning deck.
const BANK_BASE := 130.0
const BANK_TOP := 300.0
## Where the height fog starts thickening toward the deck (m): a tower fades from here up.
const FOG_START := 195.0
## Height fog density under the deck (negative: thicker going UP, Godot's height fog).
const FOG_DENSITY := -0.028
## Edge offsets from the coast line (m, + inland): overnight, the start of the burn-off, the
## afternoon bank offshore.
const NIGHT_EDGE := 9000.0
const MORNING_EDGE := 6500.0
const BANK_EDGE := -2600.0
## The burn-off runs from BURN_START to BURN_END (hours), the bank comes back in from ROLL_START,
## reaches the beach at ROLL_COAST and is NIGHT_EDGE inland by ROLL_END.
const BURN_START := 9.3
const BURN_END := 14.0
const ROLL_START := 17.0
const ROLL_COAST := 20.5
const ROLL_END := 23.5
## Metres over which the deck thins out at its edge (either side of the line).
const EDGE_SOFT := 320.0
## The Santa Ana blows from the north-east, down the passes and out to sea (game +X east, -Z
## north, so toward -X and +Z). Unit vector in XZ.
const SANTA_ANA_DIR := Vector2(-0.74, 0.67)
## The fire's search window: the front range north-west of downtown (true world XZ; its crest is
## ~380 m, 3 km from Pershing Square, in sight of downtown and midtown), and its grid step.
const FIRE_WINDOW := Rect2(-1200.0, -1900.0, 2200.0, 800.0)
const FIRE_STEP := 100.0

static var _fire_cache: Dictionary = {}


## Where the edge sits relative to the coast at `hour` (m, + inland).
static func edge_offset(hour: float) -> float:
	var h := fposmod(hour, 24.0)
	if h < BURN_START:
		return NIGHT_EDGE if h < 6.0 else lerpf(NIGHT_EDGE, MORNING_EDGE, smoothstep(6.0, BURN_START, h))
	if h < BURN_END:
		# Fast at first over the warm inland valleys, slowing as it reaches the cool coast.
		var t := (h - BURN_START) / (BURN_END - BURN_START)
		return lerpf(MORNING_EDGE, BANK_EDGE, 1.0 - pow(1.0 - t, 1.6))
	if h < ROLL_START:
		return BANK_EDGE
	if h < ROLL_COAST:
		return lerpf(BANK_EDGE, 0.0, smoothstep(ROLL_START, ROLL_COAST, h))
	if h < ROLL_END:
		return lerpf(0.0, NIGHT_EDGE, smoothstep(ROLL_COAST, ROLL_END, h))
	return NIGHT_EDGE


## The edge's wander along the coast (m): a deck edge is never a ruler line. Mirrored in
## shaders/marine_layer.gdshader edge_wob().
static func edge_wobble(z: float) -> float:
	return 260.0 * sin(z * 0.0011 + 1.3) + 140.0 * sin(z * 0.0029 + 0.4)


## True world X of the deck's edge at `hour`, at `z` (the deck is west of it).
static func edge_x(coast_x: float, hour: float, z: float) -> float:
	return coast_x + edge_offset(hour) + edge_wobble(z)


## How much deck stands over (x, z) at `hour`, 0..1.
static func cover_at(coast_x: float, hour: float, x: float, z: float) -> float:
	return 1.0 - smoothstep(-EDGE_SOFT, EDGE_SOFT, x - edge_x(coast_x, hour, z))


## How much the evening fog BANK reads as a wall (it comes in low off the water); the morning
## edge is a deck lifting and thinning, not a wall.
static func bank_amount(hour: float) -> float:
	var h := fposmod(hour, 24.0)
	return smoothstep(ROLL_START - 0.6, ROLL_START + 0.3, h) * (1.0 - smoothstep(ROLL_END - 1.5, ROLL_END, h))


## The deck's underside and top at `hour`: the morning deck, or lower while the evening bank is in.
static func deck_heights(hour: float) -> Vector2:
	var b := bank_amount(hour)
	return Vector2(lerpf(DECK_BASE, BANK_BASE, b), lerpf(DECK_TOP, BANK_TOP, b))


## Where the height fog starts thickening toward the deck at `hour` (m).
static func fog_start(hour: float) -> float:
	return deck_heights(hour).x - (DECK_BASE - FOG_START)


## The camera's place relative to the deck: 1 under it, 1 inside it, falling to 0 once above
## the top (above June gloom it is a sunny day over a white sea).
static func under_deck(cam_y: float, top: float = DECK_TOP) -> float:
	return 1.0 - smoothstep(top - 40.0, top + 60.0, cam_y)


## How hot the afternoon is for heat shimmer, 0..1 (none before 10:30 or after 18:00).
static func afternoon_heat(hour: float) -> float:
	var h := fposmod(hour, 24.0)
	return smoothstep(10.5, 13.0, h) * (1.0 - smoothstep(16.5, 18.0, h))


## The brush fire's site on the front range: a crest point picked by a hash of the seed from the
## highest ground in FIRE_WINDOW (true world, y the ground). Cached per seed; ~600 height samples.
static func fire_site(plan: Variant) -> Vector3:
	if plan == null or plan.get("macro") == null:
		return Vector3(800.0, 400.0, -2400.0)
	var seed_v: int = int(plan.get("seed")) if plan.get("seed") != null else 0
	if _fire_cache.has(seed_v):
		return _fire_cache[seed_v]
	var macro: Variant = plan.get("macro")
	var best := Vector3(800.0, -1.0e9, -2400.0)
	var best_score := -1.0e9
	var x := FIRE_WINDOW.position.x
	while x <= FIRE_WINDOW.end.x:
		var z := FIRE_WINDOW.position.y
		while z <= FIRE_WINDOW.end.y:
			var h: float = macro.height_at(Vector2(x, z))
			# A hash per cell so the seed picks which of the high crests burns, not always the peak.
			var jitter := float(hash([seed_v, int(x), int(z), "brush_fire"]) % 1000) / 1000.0
			var score := h * (0.82 + 0.18 * jitter)
			if score > best_score:
				best_score = score
				best = Vector3(x, h, z)
			z += FIRE_STEP
		x += FIRE_STEP
	_fire_cache[seed_v] = best
	return best
