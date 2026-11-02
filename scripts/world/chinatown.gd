class_name Chinatown
extends RefCounted
## Chinatown (2026-10-05, fleet task "chinatown"): the district north of the civic centre, where
## the real one stands relative to downtown at 1:1 - on N Broadway and N Hill St north of Cesar
## Chavez Ave, which DowntownReal pins on every seed. The real neighbourhood's FORMS: a gateway
## over Broadway, two- and three-storey shop buildings with sweeping glazed-tile roofs, tiled pent
## eaves and painted rafters, red columns and lattice, lanterns strung across the streets and lit
## at night, a central plaza with a pagoda-roofed hall, shops with their goods out front. Every
## NAME is invented (the gate, the plaza, the hall, every shop); no real business, association or
## landmark name anywhere, and nothing caricatured: real materials, real proportions, a working
## neighbourhood street.
##
## WHERE is a site table, never placed by hand:
## - the district: the blocks between Olive St and Main St (pinned avenues), from Cesar Chavez Ave
##   (pinned) north NORTH_REACH metres, on CITY ground (the hills start ~500 m north);
## - the plaza: the Hill St - Broadway block whose centre is nearest PLAZA_NORTH of Cesar Chavez
##   (the real central plaza is ~400 m north of it, between the same two streets);
## - the gate: over Broadway GATE_NORTH of Cesar Chavez (the real Broadway gate's place), slid
##   along the road segment clear of the junctions and of the pavement's lamp and tree slots.
## CityPlan.block() calls apply() AFTER every roll and override (so no seed, lot or roll moves):
## it marks the district's blocks ("chinatown": "block" / "plaza"), makes a mall or big box rolled
## there ordinary lots, and the plaza's block a PLAZA (skipping anything another feature claimed:
## a site, grounds, a school, a hospital). Lots: CityChunk._build_lot() asks claims() after the
## other claims (the pad roll is made), and the street-facing lots it takes are ChinatownKit's
## shop buildings; dress() keeps the district's other buildings low and in brick and stucco.
## Every roll is a hash of seed + lot / block, never a chunk, block or Building rng.
##
## FULL chunks: ONE mesh a block on chinatown.gdshader (every building, the lanterns, the gate,
## the plaza hall), one collision body, light pools under the lantern strings. LOD and the far
## city: boxes and roof slabs (lod_box), the gate and the hall as boxes.
##
## Off (CHINATOWN=0 in the environment): none of it - the A/B for stills and frame counts.

const NAME := "CHINATOWN"
const GATE_NAME := "GATE OF GOLDEN HARMONY"
const PLAZA_NAME := "JADE LANTERN PLAZA"
const HALL_NAME := "HALL OF SPRING WIND"

const WEST_AVENUE := "OLIVE ST"
const EAST_AVENUE := "MAIN ST"
const SOUTH_STREET := "CESAR CHAVEZ AVE"
## How far north of Cesar Chavez's centre line the district reaches (block centres).
const NORTH_REACH := 520.0
## The plaza's block: between these two avenues, its centre nearest this far north of Cesar Chavez.
const PLAZA_AVENUES := ["HILL ST", "BROADWAY"]
const PLAZA_NORTH := 400.0
## The gate over Broadway, this far north of Cesar Chavez's centre line.
const GATE_AVENUE := "BROADWAY"
const GATE_NORTH := 52.0
## Lanterns are strung across these avenues and across every cross street between them.
const LANTERN_AVENUES := ["HILL ST", "BROADWAY"]

## A street-facing lot is a Chinatown shop building with these odds (the rest are dressed Buildings).
const CLAIM_ODDS := 0.86
const MIN_FRONTAGE := 7.0
## The district's other buildings: low, brick and stucco.
const HEIGHT_LIMIT := 20.0

## The shops (invented; English names as the real street's signs carry them alongside Chinese).
const SHOP_NAMES := ["JADE MOON TEA HOUSE", "SILVER CRANE HERBS", "LUCKY PLUM GROCERY", "HARBOR LANTERN NOODLES",
	"SEVEN PINES BAKERY", "RED BRIDGE DUMPLINGS", "EAST WIND GIFTS", "PLUM BLOSSOM BOOKS", "GOOD FORTUNE SEAFOOD",
	"TWIN CARP JEWELRY", "BAMBOO GROVE FLORIST", "LONG LIFE PHARMACY", "AUTUMN MOON KITCHEN", "GOLDEN MILLET MARKET",
	"JADE COURT BBQ", "HAPPY SPRING TOYS", "WILLOW HOUSE CERAMICS", "MOUNTAIN MIST TEAS", "NINE RIVERS IMPORTS",
	"PEONY GARDEN RESTAURANT", "BRIGHT STAR HARDWARE", "KIND HEART HERBS", "WHITE HERON TAILOR", "SOUTH HILL ROAST DUCK",
	"SPRING ORCHARD FRUIT", "OLD STONE WOK", "LOTUS POND DIM SUM", "CRANE AND PINE STUDIO"]
## What each shop puts out front (index into GOODS; -1 nothing): by the name's trade.
const SHOP_GOODS := [3, 4, 0, -1, 2, -1, 1, 5, 0, -1, 2, 4, -1, 0, -1, 1, 5, 4, 1, -1, 5, 4, -1, -1, 0, -1, -1, 1]
## The goods: produce tables, souvenir racks, flower buckets, potted plants by a tea house,
## herb and dried-goods bins, stacked crates and boxes.
enum Goods { PRODUCE, RACKS, FLOWERS, PLANTS, BINS, CRATES }
## Short words for the vertical blade signs, stacked letter by letter.
const BLADE_WORDS := ["TEA", "HERBS", "MARKET", "NOODLE", "BAKERY", "DIM SUM", "GIFTS", "JADE", "BOOKS", "BBQ", "FRUIT", "SEAFOOD"]

static var enabled: bool = OS.get_environment("CHINATOWN") != "0"
static var _plaza: Dictionary = {}
static var _gate: Dictionary = {}


# --- Where ---------------------------------------------------------------------------------------

static func _pin_x(name: String, fallback: float) -> float:
	var pin := DowntownReal.named(CityPlan.AXIS_X, name)
	return float(pin[0]) if not pin.is_empty() else fallback


static func _pin_w(axis: int, name: String, fallback: float) -> float:
	var pin := DowntownReal.named(axis, name)
	return float(pin[1]) if not pin.is_empty() else fallback


static func avenue_x(name: String) -> float:
	return _pin_x(name, NAN)


## Cesar Chavez Ave's centre line z.
static func south_z() -> float:
	var pin := DowntownReal.named(CityPlan.AXIS_Z, SOUTH_STREET)
	return float(pin[0]) if not pin.is_empty() else -1726.3


## The district's extent in world XZ (block centres inside it are the district's).
static func extent() -> Rect2:
	var x0 := _pin_x(WEST_AVENUE, 2739.6)
	var x1 := _pin_x(EAST_AVENUE, 3235.7)
	var z1 := south_z()
	return Rect2(x0, z1 - NORTH_REACH, x1 - x0, NORTH_REACH)


static func in_district(plan: CityPlan, rect: Rect2) -> bool:
	if not enabled or plan == null or plan.macro == null:
		return false
	var c := rect.get_center()
	if not extent().has_point(c):
		return false
	return plan.zone_at(c) == MacroMap.Zone.CITY


## The plaza's block index for this plan (Vector2i), or (-99999, 0) when none fits.
static func plaza_block(plan: CityPlan) -> Vector2i:
	if _plaza.has(plan.seed):
		return _plaza[plan.seed]
	var none := Vector2i(-99999, 0)
	var xa := avenue_x(PLAZA_AVENUES[0])
	var xb := avenue_x(PLAZA_AVENUES[1])
	var out := none
	if not is_nan(xa) and not is_nan(xb):
		var k := plan.block_index_at(Vector2((xa + xb) * 0.5, south_z() - PLAZA_NORTH))
		# The block must run from one avenue to the other (they are adjacent pinned roads).
		if absf(plan.road_pos(CityPlan.AXIS_X, k.x) - xa) < 0.05 and absf(plan.road_pos(CityPlan.AXIS_X, k.x + 1) - xb) < 0.05:
			out = k
	_plaza[plan.seed] = out
	return out


## CityPlan.block(), after every roll and override: marks the district's blocks.
static func apply(plan: CityPlan, b: Dictionary) -> void:
	var rect: Rect2 = b.rect
	if not in_district(plan, rect):
		return
	if b.has("site") or b.has("grounds") or b.has("hospital") or b.kind == CityPlan.BlockKind.SCHOOL:
		return
	if plan.river_block(int(b.ix), int(b.iz)) or plan.marina_block(int(b.ix), int(b.iz)):
		return
	# The neighbourhood is built solid: a mall, big box or bare seeded plaza rolled here is lots.
	if b.kind == CityPlan.BlockKind.MALL or b.kind == CityPlan.BlockKind.BIGBOX or b.kind == CityPlan.BlockKind.PLAZA:
		b.kind = CityPlan.BlockKind.BUILDINGS
	if Vector2i(int(b.ix), int(b.iz)) == plaza_block(plan) and rect.size.x > 60.0 and rect.size.y > 60.0:
		b.kind = CityPlan.BlockKind.PLAZA
		b["chinatown"] = "plaza"
		return
	b["chinatown"] = "block"


static func block_role(plan: CityPlan, ix: int, iz: int) -> String:
	if not enabled or plan == null or plan.macro == null:
		return ""
	return str(plan.block(ix, iz).get("chinatown", ""))


## CityChunk._block_steps(): this chunk has Chinatown work (its block, or the gate's road).
static func wanted(ch: CityChunk, block: Dictionary) -> bool:
	return enabled and ch.plan != null and ch.plan.macro != null and block.has("chinatown")


# --- The gate -------------------------------------------------------------------------------------

## The gate over Broadway: {"block": Vector2i (the chunk that builds it: the block west of the
## avenue, which owns the road), "x": centre line, "z", "width": the carriageway}, or {}.
static func gate(plan: CityPlan) -> Dictionary:
	if _gate.has(plan.seed):
		return _gate[plan.seed]
	var out: Dictionary = {}
	_gate[plan.seed] = out
	var x := avenue_x(GATE_AVENUE)
	if is_nan(x):
		return out
	var w := _pin_w(CityPlan.AXIS_X, GATE_AVENUE, 20.0)
	var want := south_z() - GATE_NORTH
	var k := plan.block_index_at(Vector2(x - 20.0, want))
	if not (block_role(plan, k.x, k.y) != "" and block_role(plan, k.x + 1, k.y) != ""):
		return out
	var b: Rect2 = plan.block(k.x, k.y).rect
	var z0 := b.position.y + 12.0
	var z1 := b.end.y - 12.0
	if z1 <= z0:
		return out
	# Clear of the pavement's lamp and tree slots on both sides (CityChunk._build_sidewalk_props:
	# lamps every lamp_spacing from 1/4 or 1/2 of it, trees every tree_spacing from 3/4).
	var best := clampf(want, z0, z1)
	var best_cost := INF
	var lamp := 24.0
	var tree := 14.0 * 0.85
	var z := z0
	while z <= z1:
		var t := z - b.position.y
		var cost := absf(z - want) * 0.05
		for off: float in [lamp * 0.25, lamp * 0.5]:
			var d := absf(fposmod(t - off + lamp * 0.5, lamp) - lamp * 0.5)
			cost += maxf(0.0, 3.0 - d) * 4.0
		var dt := absf(fposmod(t - tree * 0.75 + tree * 0.5, tree) - tree * 0.5)
		cost += maxf(0.0, 2.0 - dt) * 2.0
		if cost < best_cost:
			best_cost = cost
			best = z
		z += 0.5
	out.merge({"block": k, "x": x, "z": best, "width": w})
	return out


# --- Lots ----------------------------------------------------------------------------------------

## Which street a lot of block (ix, iz) faces, as an outward direction (Vector2, unit), or ZERO:
## an edge lot on the inner pavement line, the avenue side first, then the longer frontage.
static func lot_front(plan: CityPlan, ix: int, iz: int, lot: Dictionary) -> Vector2:
	var inner := (plan.block(ix, iz).rect as Rect2).grow(-plan.sidewalk_width)
	var c: Vector2 = lot.center
	var s: Vector2 = lot.size
	var best := Vector2.ZERO
	var best_score := -INF
	var sides := [
		[Vector2(-1, 0), c.x - s.x * 0.5 - inner.position.x, s.y],
		[Vector2(1, 0), inner.end.x - (c.x + s.x * 0.5), s.y],
		[Vector2(0, -1), c.y - s.y * 0.5 - inner.position.y, s.x],
		[Vector2(0, 1), inner.end.y - (c.y + s.y * 0.5), s.x],
	]
	for sd: Array in sides:
		var gap: float = sd[1]
		if gap > 4.0:
			continue
		var frontage: float = sd[2]
		var score := frontage + (30.0 if (sd[0] as Vector2).y == 0.0 else 0.0)
		if score > best_score:
			best_score = score
			best = sd[0]
	return best


## CityChunk._build_lot(): is this lot one of Chinatown's shop buildings?
static func claims(plan: CityPlan, ix: int, iz: int, lot: Dictionary) -> bool:
	if block_role(plan, ix, iz) != "block":
		return false
	if lot.get("yard", false) or lot.get("parking", false) or not lot.get("edge", false):
		return false
	var s: Vector2 = lot.size
	if minf(s.x, s.y) < MIN_FRONTAGE:
		return false
	if lot_front(plan, ix, iz, lot) == Vector2.ZERO:
		return false
	return h01([plan.seed, int(lot.seed), "ct_claim"]) < CLAIM_ODDS


static func build_lot(ch: CityChunk, lot: Dictionary) -> void:
	ChinatownKit.build_lot(ch, lot, lot_front(ch.plan, ch.ix, ch.iz, lot))


## CityChunk._build_lot(): the district's other buildings, low and in brick and stucco (both
## levels, so the far copy agrees). Nothing else about them moves.
static func dress(ch: CityChunk, lot: Dictionary, building: Building) -> void:
	if block_role(ch.plan, ch.ix, ch.iz) == "":
		return
	building.finish_options.assign([Building.Finish.BRICK, Building.Finish.FLAT, Building.Finish.FLAT])
	building.max_height = minf(building.max_height, HEIGHT_LIMIT)
	building.min_height = minf(building.min_height, building.max_height * 0.85)


## CityChunk._block_steps(): the plaza (its PLAZA branch) - ChinatownKit.
static func build_plaza(ch: CityChunk, block: Dictionary) -> void:
	ChinatownKit.build_plaza(ch, block)


## CityChunk._block_steps(), after the lots (both levels): the lanterns over the roads this chunk
## owns, the gate when it owns its road, then the block's one mesh and body.
static func block_step(ch: CityChunk, block: Dictionary) -> void:
	ChinatownKit.block_step(ch, block)


static func h01(parts: Array) -> float:
	return float(absi(hash(parts)) % 100003) / 100003.0
