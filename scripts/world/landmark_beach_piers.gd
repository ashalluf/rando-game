class_name LandmarkBeachPiers
extends RefCounted
## BEACH PIERS - the two South Bay piers, in one file because they share a sea level, a deck
## height, a pile system and a railing. Two entry points:
##
##   build_manhattan()  a narrow straight concrete pier, 280 m of plain deck on paired piles,
##                      low railing, globe lamps, benches, and a small octagonal building with a
##                      tiled pyramid roof standing on the round head at the seaward end. That
##                      little roundhouse IS the silhouette, so everything else stays plain.
##   build_redondo()    a wide timber horseshoe: it runs out to sea, sweeps round a half circle
##                      and comes back, so it encloses a lagoon of water. Two storeys of small
##                      shops and restaurants with pitched roofs and rooftop hoardings, fishing
##                      rails all round the outer edge, a stair down to a lower fishing deck at
##                      the apex, and a two-level car park at its root on the land.
##   build()            forwards to build_manhattan() so the file still satisfies the one-entry
##                      -point convention that Landmarks.build() expects.
##
## Sea level is y = 0 (the water surface mesh sits at 0.15). Both decks are at DECK_Y, the same
## height Landmarks._build_pier() uses, so all three piers of the map agree; the piles run from
## PILE_FOOT, well under the water, up to the underside of the deck.
##
## The Redondo root has to meet the land as well as the sea: its car park stands on the median
## ground behind the anchor (never more than RD_PARK_FILL above the lowest corner under it), and
## a link - flat onto the upper parking deck, a ramp otherwise - always ties that back to the
## deck, so the pier stays walkable wherever the shore behind it is not at sea level.
##
## Names: the towns are geography (fine). Every business on the Redondo pier is invented - the
## big rooftop sign reads ROUNDWOOD, which is nobody. No real trade dress, no copied building.
##
## Triangles, measured: Manhattan 6,960 detailed (122 nodes, 6 collision shapes) and 856 far;
## Redondo 18,098 detailed (582 nodes, 65 collision shapes) and 1,212 far. The money on Redondo
## goes on the deck planks, the piles and braces, the fishing rails, the twenty-odd shops, the
## car park and the ROUNDWOOD block letters; drop RD_PLANK_STEP, RD_RAIL_POST_STEP or
## RD_ARC_STEPS to claw any of it back.

# --- Shared ----------------------------------------------------------------------------------

## Seed salt so both piers' random detail is stable for a given anchor.
const SEED_SALT := 774113
## Height of the centre of the deck slab above sea level, in metres. Landmarks._build_pier()
## uses the same number; change all three together or the piers stop agreeing.
const DECK_Y := 6.0
## Thickness of a deck slab, in metres.
const DECK_T := 0.8
## How far below sea level the piles are driven, in metres (their visible foot).
const PILE_FOOT := -3.0

# --- Manhattan pier --------------------------------------------------------------------------

## Total length of the Manhattan pier from the shore to the seaward face of the head, in metres.
const MH_LENGTH := 280.0
## Width of the straight concrete deck, in metres.
const MH_WIDTH := 8.0
## Radius of the round head the roundhouse stands on, in metres.
const MH_END_RADIUS := 11.0
## Distance between pile bents along the deck, in metres.
const MH_PILE_STEP := 12.0
## Radius of one concrete pile, in metres.
const MH_PILE_R := 0.45
## Distance from the deck centreline to a pile of the pair, in metres.
const MH_PILE_GAUGE := 2.9
## Height of the railing above the deck surface, in metres.
const MH_RAIL_H := 1.1
## Distance between railing posts, in metres.
const MH_RAIL_POST_STEP := 4.0
## Distance between lamp posts along the deck, in metres.
const MH_LAMP_STEP := 28.0
## Height of a lamp post from the deck to the globe, in metres.
const MH_LAMP_H := 4.6
## Distance between benches along the deck, in metres.
const MH_BENCH_STEP := 44.0
## Circumradius of the octagonal roundhouse wall, in metres.
const MH_HOUSE_R := 6.2
## Height of the roundhouse wall from the deck to the eave, in metres.
const MH_HOUSE_H := 4.4
## Circumradius of the oversailing eave, in metres.
const MH_EAVE_R := 7.6
## Rise of the tiled pyramid roof above the eave, in metres.
const MH_ROOF_H := 3.6
## Length of the ramp from the sand up to the deck, in metres.
const MH_RAMP_LEN := 26.0

# --- Redondo horseshoe -----------------------------------------------------------------------

## How far seaward of the anchor the two legs of the horseshoe start, in metres.
const RD_ROOT_X := 14.0
## Length of each straight leg before the half-circle bend, in metres.
const RD_STRAIGHT := 150.0
## Half the distance between the two legs' centrelines, i.e. the bend radius, in metres.
const RD_HALF_SPAN := 55.0
## Width of the timber deck, in metres.
const RD_DECK_W := 16.0
## Segments the half-circle bend is cut into for the detailed build.
const RD_ARC_STEPS := 14
## Segments one straight leg is cut into for the detailed build.
const RD_STRAIGHT_STEPS := 10
## Segments the bend is cut into for the far build. Eight, not six: the bend is the whole
## silhouette of this pier from the shore, and six reads as a hexagon.
const RD_FAR_ARC_STEPS := 8
## Segments one straight leg is cut into for the far build.
const RD_FAR_STRAIGHT_STEPS := 3
## Radius of one timber pile, in metres.
const RD_PILE_R := 0.38
## Distance from the deck centreline to a pile of the pair, in metres.
const RD_PILE_GAUGE := 6.0
## Distance between the dark gaps of the deck planking, in metres.
const RD_PLANK_STEP := 2.4
## Height of the fishing rail above the deck surface, in metres.
const RD_RAIL_H := 1.15
## Distance between fishing-rail posts, in metres.
const RD_RAIL_POST_STEP := 3.2
## Depth of a shop block across the deck, in metres.
const RD_SHOP_D := 9.0
## Height of a shop's ground storey, in metres.
const RD_SHOP_H1 := 4.0
## Height of a shop's upper storey, in metres.
const RD_SHOP_H2 := 3.4
## Rise of a shop's pitched roof above the upper storey, in metres.
const RD_ROOF_RISE := 2.2
## Chance a deck segment is left as open promenade instead of getting a shop.
const RD_SHOP_GAP_CHANCE := 0.24
## Chance a shop is a single storey rather than two. A pier of identical two-storey blocks reads
## as one long ribbon; the real thing has its roofline stepping up and down all the way out.
const RD_SHOP_SINGLE_CHANCE := 0.38
## Height of the lower fishing deck above sea level, in metres.
const RD_LOWER_Y := 2.9
## Width of the lower fishing deck out from the pier's outer edge, in metres.
const RD_LOWER_W := 11.0
## Length of the lower fishing deck along the pier, in metres.
const RD_LOWER_LEN := 34.0
## Gap between the anchor and the near edge of the car park, in metres.
const RD_PARK_GAP := 8.0
## Depth of the car park inland along +X, in metres.
const RD_PARK_D := 64.0
## Width of the car park along Z, in metres.
const RD_PARK_W := 70.0
## Headroom needed under the upper parking deck before it is worth building, in metres.
const RD_PARK_CLEAR := 4.2
## The most the car park's surface is allowed to stand above the lowest ground under it, in
## metres: a lot on a slope is cut into the high side and filled on the low one, never perched.
const RD_PARK_FILL := 3.0
## Width of the ramp up to the upper parking deck, in metres. The deck leaves a slot this wide
## along its seaward edge so the ramp comes out ON the deck instead of under it.
const RD_RAMP_W := 7.0
## Width of one painted parking bay, in metres.
const RD_BAY := 2.6
## Cell size of the ROUNDWOOD block letters, in metres (letters are 5 x 7 cells).
const RD_SIGN_CELL := 0.55
## The rooftop hoarding's word. Every glyph must exist in Landmarks.FONT, which only holds
## R, U, A, N, D, O and W - hence this name and not a longer one.
const RD_SIGN_TEXT := "ROUNDWOOD"
## Index of the deck segment the ROUNDWOOD hoarding stands over. It lands on the return leg, so
## the segment runs along X and Landmarks._text() (which always draws along +X) reads square on.
## This segment and its two neighbours are forced to carry shops so the sign is never floating.
const RD_SIGN_SEGMENT := RD_STRAIGHT_STEPS + RD_ARC_STEPS + 5

# --- Palette ----------------------------------------------------------------------------------

const CONCRETE_TINT := Color(0.80, 0.79, 0.76)
const CONCRETE_DARK := Color(0.56, 0.55, 0.53)
const TIMBER := Color(0.50, 0.37, 0.25)
const TIMBER_DARK := Color(0.30, 0.23, 0.16)
const TIMBER_PALE := Color(0.66, 0.56, 0.43)
const RAIL_BLUE := Color(0.20, 0.34, 0.44)
const GLASS := Color(0.16, 0.22, 0.26)
const TILE_RED := Color(0.62, 0.26, 0.18)
const TILE_RIDGE := Color(0.71, 0.34, 0.24)
const LAMP_WARM := Color(1.0, 0.94, 0.78)
## Diameter of the pool of light a pier lamp throws on the deck, in metres. The street lamps use
## 13; a pier lamp is lower and closer together than a street one.
const LAMP_POOL := 9.0
const PAINT_WHITE := Color(0.90, 0.89, 0.85)
## Shop colours, picked per shop from the seeded rng.
const SHOP_COLORS: Array[Color] = [
	Color(0.86, 0.83, 0.76), Color(0.74, 0.78, 0.76), Color(0.84, 0.70, 0.55),
	Color(0.62, 0.68, 0.72), Color(0.88, 0.76, 0.64), Color(0.70, 0.62, 0.56),
]
## Awning / hoarding colours, picked per shop from the seeded rng.
const TRIM_COLORS: Array[Color] = [
	Color(0.85, 0.25, 0.22), Color(0.20, 0.45, 0.70), Color(0.95, 0.72, 0.20),
	Color(0.25, 0.60, 0.42), Color(0.80, 0.40, 0.55),
]


# --- Entry points -------------------------------------------------------------------------

## Convention entry point: the file's default landmark is the Manhattan pier.
static func build(anchor: Vector2, parent: Node3D, statics: StaticBody3D, plan: CityPlan, detailed: bool) -> void:
	build_manhattan(anchor, parent, statics, plan, detailed)


## The straight concrete pier. `anchor` is the landward end of the deck; it runs west (-X) out
## over the water, the same way Landmarks._build_pier() does.
static func build_manhattan(anchor: Vector2, parent: Node3D, statics: StaticBody3D, plan: CityPlan, detailed: bool) -> void:
	var deck_top := DECK_Y + DECK_T * 0.5
	var straight := MH_LENGTH - MH_END_RADIUS
	var head := Vector3(anchor.x - straight, DECK_Y, anchor.y)
	var concrete := _concrete()
	var batch := MultiMeshBatch.new()

	# Deck slab and the round head it ends on.
	_obox(parent, statics, Vector3(straight, DECK_T, MH_WIDTH),
			Vector3(anchor.x - straight * 0.5, DECK_Y, anchor.y), Vector3.ZERO, concrete, true)
	_poly(parent, statics, MH_END_RADIUS, MH_END_RADIUS, DECK_T, 16, head, 0.0, concrete, true)
	_mh_ramp(parent, statics, anchor, plan, concrete)
	_mh_piles(batch, anchor, head, detailed)
	_mh_roundhouse(parent, statics, head, deck_top, detailed)
	if not detailed:
		_mh_rails(parent, batch, anchor, head, straight, deck_top, 5, false)
		batch.build(parent)
		return
	_mh_rails(parent, batch, anchor, head, straight, deck_top, 16, true)
	_mh_lamps(batch, anchor, straight, deck_top)
	_mh_benches(parent, anchor, straight, deck_top)
	_mh_head_benches(parent, head, deck_top)
	_mh_sign(parent, statics, anchor, deck_top)
	batch.build(parent)


## The timber horseshoe. `anchor` is on the shore at the centreline of the approach; the pier
## runs west (-X) out over the water and the car park sits inland of it.
static func build_redondo(anchor: Vector2, parent: Node3D, statics: StaticBody3D, plan: CityPlan, detailed: bool) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED_SALT ^ (int(anchor.x) * 73856093) ^ (int(anchor.y) * 19349663)
	var deck_top := DECK_Y + DECK_T * 0.5
	var pts := _rd_path(anchor, RD_ARC_STEPS if detailed else RD_FAR_ARC_STEPS,
			RD_STRAIGHT_STEPS if detailed else RD_FAR_STRAIGHT_STEPS)
	var batch := MultiMeshBatch.new()
	var timber := PropFactory.material(TIMBER, 0.92)

	_rd_deck(parent, statics, pts, anchor, timber, batch, detailed)
	_rd_piles(batch, pts, detailed)
	if not detailed:
		_rd_far_shops(parent, pts, deck_top)
		_rd_car_park(parent, statics, anchor, plan, false)
		batch.build(parent)
		return
	var flags := _rd_shop_flags(pts.size() - 1, rng)
	# The deck segment the stair down to the lower deck lands on: the first one past the apex of
	# the bend. Both the rails and the lower deck take it, so the railing opens exactly there.
	var stair_seg: int = mini(pts.size() / 2, pts.size() - 2)
	_rd_shops(parent, statics, pts, flags, deck_top, rng)
	_rd_rails(parent, batch, pts, flags, deck_top, stair_seg)
	_rd_lower_deck(parent, statics, batch, pts, deck_top, stair_seg)
	_rd_lamps(batch, pts, deck_top)
	_rd_entrance(parent, statics, anchor, deck_top)
	_rd_sign(parent, pts, deck_top)
	_rd_car_park(parent, statics, anchor, plan, true)
	batch.build(parent)


# --- Manhattan parts ------------------------------------------------------------------------

## The ramp from the sand up onto the deck, with a rotated collision box so the player can walk it.
static func _mh_ramp(parent: Node3D, statics: StaticBody3D, anchor: Vector2, plan: CityPlan, mat: Material) -> void:
	var ground: float = plan.height_at(anchor + Vector2(MH_RAMP_LEN, 0.0)) if plan != null else 0.0
	var top := DECK_Y - DECK_T * 0.5
	var rise := maxf(top - ground, 0.5)
	var run := MH_RAMP_LEN
	var pitch := atan2(rise, run)
	var length := sqrt(rise * rise + run * run)
	_obox(parent, statics, Vector3(length, DECK_T, MH_WIDTH),
			Vector3(anchor.x + run * 0.5, ground + rise * 0.5, anchor.y), Vector3(0.0, 0.0, -pitch), mat, true)


## Paired piles with a cap beam over each bent. Batched: one MultiMesh for the piles, one for the
## caps. Far builds keep the same piles at a coarser spacing so the silhouette still has legs.
static func _mh_piles(batch: MultiMeshBatch, anchor: Vector2, head: Vector3, detailed: bool) -> void:
	var step := MH_PILE_STEP if detailed else MH_PILE_STEP * 4.0
	var top := DECK_Y - DECK_T * 0.5
	var h := top - PILE_FOOT
	var pile := _cyl_mesh(MH_PILE_R, h, 8 if detailed else 6, _concrete())
	var cap := _box_mesh(Vector3(0.9, 0.55, MH_PILE_GAUGE * 2.0 + 1.2), PropFactory.material(CONCRETE_DARK))
	var x := anchor.x - 5.0
	while x > head.x - MH_END_RADIUS * 0.5:
		for side: float in [-1.0, 1.0]:
			batch.add("mh_pile", pile, _xform(Vector3(x, PILE_FOOT + h * 0.5, anchor.y + side * MH_PILE_GAUGE), 0.0))
		batch.add("mh_cap", cap, _xform(Vector3(x, top - 0.3, anchor.y), 0.0))
		x -= step
	# Six more under the round head, in a ring.
	for i in 6:
		var a := TAU * i / 6.0
		var p := Vector3(head.x + cos(a) * (MH_END_RADIUS - 2.4), PILE_FOOT + h * 0.5, head.z + sin(a) * (MH_END_RADIUS - 2.4))
		batch.add("mh_pile", pile, _xform(p, 0.0))


## Low railing down both sides of the straight deck and right round the head.
static func _mh_rails(parent: Node3D, batch: MultiMeshBatch, anchor: Vector2, head: Vector3, straight: float, deck_top: float, head_posts: int, posts: bool) -> void:
	var steel := PropFactory.material(RAIL_BLUE, 0.6)
	var post := _box_mesh(Vector3(0.12, MH_RAIL_H, 0.12), steel)
	var rail_y := deck_top + MH_RAIL_H
	for side: float in [-1.0, 1.0]:
		var z := anchor.y + side * (MH_WIDTH * 0.5 - 0.25)
		_obox(parent, null, Vector3(straight, 0.1, 0.1), Vector3(anchor.x - straight * 0.5, rail_y, z), Vector3.ZERO, steel, false)
		_obox(parent, null, Vector3(straight, 0.08, 0.08), Vector3(anchor.x - straight * 0.5, deck_top + MH_RAIL_H * 0.55, z), Vector3.ZERO, steel, false)
		if not posts:
			continue
		var n := int(straight / MH_RAIL_POST_STEP)
		for i in n:
			var x := anchor.x - 2.0 - i * MH_RAIL_POST_STEP
			batch.add("mh_post", post, _xform(Vector3(x, deck_top + MH_RAIL_H * 0.5, z), 0.0))
	# The head: a ring of posts with a straight rail chord between each pair.
	var r := MH_END_RADIUS - 0.35
	var chord := 2.0 * r * sin(PI / head_posts)
	for i in head_posts:
		var a := TAU * i / head_posts
		batch.add("mh_post", post, _xform(Vector3(head.x + cos(a) * r, deck_top + MH_RAIL_H * 0.5, head.z + sin(a) * r), 0.0))
		var mid := a + PI / head_posts
		var p := Vector3(head.x + cos(mid) * r * cos(PI / head_posts), rail_y, head.z + sin(mid) * r * cos(PI / head_posts))
		_obox(parent, null, Vector3(chord + 0.1, 0.1, 0.1), p, Vector3(0.0, -mid - PI * 0.5, 0.0), steel, false)


## Globe lamps down both sides of the deck.
static func _mh_lamps(batch: MultiMeshBatch, anchor: Vector2, straight: float, deck_top: float) -> void:
	var pole := _cyl_mesh(0.1, MH_LAMP_H, 6, PropFactory.material(RAIL_BLUE, 0.6))
	var globe := _sphere_mesh(0.34, _lamp_glow())
	var pool := PropFactory.light_pool()
	var n := int(straight / MH_LAMP_STEP)
	for i in n:
		var x := anchor.x - 14.0 - i * MH_LAMP_STEP
		for side: float in [-1.0, 1.0]:
			var z := anchor.y + side * (MH_WIDTH * 0.5 - 0.7)
			batch.add("mh_pole", pole, _xform(Vector3(x, deck_top + MH_LAMP_H * 0.5, z), 0.0))
			batch.add("mh_globe", globe, _xform(Vector3(x, deck_top + MH_LAMP_H + 0.3, z), 0.0))
			batch.add("mh_pool", pool, _pool_xform(Vector3(x, deck_top + 0.06, z), LAMP_POOL))
	batch.set_no_shadow("mh_pool")


## Benches, alternating sides, facing the water.
static func _mh_benches(parent: Node3D, anchor: Vector2, straight: float, deck_top: float) -> void:
	var n := int(straight / MH_BENCH_STEP)
	for i in n:
		var x := anchor.x - 26.0 - i * MH_BENCH_STEP
		var side := 1.0 if i % 2 == 0 else -1.0
		_bench(parent, Vector3(x, deck_top, anchor.y + side * (MH_WIDTH * 0.5 - 1.3)), side)


## Benches round the roundhouse on the pier head, backs to the building and faces to the water,
## one to each face of the octagon except the landward one with the door in it. The head is
## where everybody ends up standing, and bare it reads as an empty concrete disc.
static func _mh_head_benches(parent: Node3D, head: Vector3, deck_top: float) -> void:
	for j in range(1, 8):
		var a := TAU * j / 8.0
		var at := Vector3(head.x + cos(a) * 8.8, deck_top, head.z + sin(a) * 8.8)
		_bench(parent, at, -1.0, _yaw(Vector2(-sin(a), cos(a))))


## The name board on the two entrance posts at the shore end.
static func _mh_sign(parent: Node3D, statics: StaticBody3D, anchor: Vector2, deck_top: float) -> void:
	var post_mat := PropFactory.material(CONCRETE_DARK)
	var x := anchor.x - 3.0
	for side: float in [-1.0, 1.0]:
		_obox(parent, statics, Vector3(0.5, 5.4, 0.5), Vector3(x, deck_top + 2.7, anchor.y + side * (MH_WIDTH * 0.5 + 0.3)), Vector3.ZERO, post_mat, true)
	_obox(parent, null, Vector3(0.35, 1.5, MH_WIDTH + 1.4), Vector3(x, deck_top + 5.6, anchor.y), Vector3.ZERO, PropFactory.material(PAINT_WHITE), false)
	var label := Label3D.new()
	label.text = "MANHATTAN PIER"
	label.font_size = 140
	label.pixel_size = 0.0085
	label.outline_size = 20
	label.modulate = Color(0.12, 0.20, 0.30)
	label.position = Vector3(x + 0.25, deck_top + 5.6, anchor.y)
	label.rotation.y = PI * 0.5
	parent.add_child(label)


## The octagonal end building: wall, glazed band, eave, tiled pyramid roof with hip ridges.
static func _mh_roundhouse(parent: Node3D, statics: StaticBody3D, head: Vector3, deck_top: float, detailed: bool) -> void:
	# A CylinderMesh with eight radial segments IS an octagonal prism; the -22.5 degree spin puts
	# a flat face (and the door) on the landward +X side instead of a corner.
	var spin := -PI / 8.0
	var white := PropFactory.material(Color(0.93, 0.92, 0.88), 0.75)
	_poly(parent, statics, MH_HOUSE_R, MH_HOUSE_R, MH_HOUSE_H, 8, head + Vector3(0.0, deck_top - DECK_Y + MH_HOUSE_H * 0.5, 0.0), spin, white, true)
	var roof_y := deck_top + MH_HOUSE_H
	_poly(parent, null, MH_EAVE_R, MH_EAVE_R, 0.35, 8, Vector3(head.x, roof_y + 0.18, head.z), spin, PropFactory.material(TIMBER_PALE), false)
	_poly(parent, null, MH_EAVE_R, 0.35, MH_ROOF_H, 8, Vector3(head.x, roof_y + 0.35 + MH_ROOF_H * 0.5, head.z), spin, _tile(), false)
	if not detailed:
		return
	# Glazed band, door, hip ridges, finial, and a bit of trim.
	_poly(parent, null, MH_HOUSE_R + 0.06, MH_HOUSE_R + 0.06, 1.9, 8, Vector3(head.x, deck_top + 2.6, head.z), spin, PropFactory.material(GLASS, 0.25), false)
	_poly(parent, null, MH_HOUSE_R + 0.05, MH_HOUSE_R + 0.05, 0.28, 8, Vector3(head.x, deck_top + MH_HOUSE_H - 0.5, head.z), spin, PropFactory.material(TIMBER_DARK), false)
	_obox(parent, null, Vector3(0.3, 2.4, 1.5), Vector3(head.x + MH_HOUSE_R * 0.94, deck_top + 1.2, head.z), Vector3.ZERO, PropFactory.material(TIMBER_DARK), false)
	var ridge_mat := PropFactory.material(TILE_RIDGE, 0.7)
	var hip := sqrt(MH_EAVE_R * MH_EAVE_R + MH_ROOF_H * MH_ROOF_H)
	for i in 8:
		var a := spin + TAU * i / 8.0
		var arm := _pivot(parent, Vector3(head.x, roof_y + 0.35, head.z), -a)
		var slab := _obox(arm, null, Vector3(hip, 0.16, 0.34), Vector3(MH_EAVE_R * 0.5, MH_ROOF_H * 0.5, 0.0), Vector3.ZERO, ridge_mat, false)
		slab.rotation.z = atan2(MH_ROOF_H, -MH_EAVE_R)
	_poly(parent, null, 0.5, 0.5, 0.5, 8, Vector3(head.x, roof_y + MH_ROOF_H + 0.6, head.z), spin, ridge_mat, false)
	_cyl_node(parent, 0.09, 3.2, 6, Vector3(head.x, roof_y + MH_ROOF_H + 2.4, head.z), PropFactory.material(CONCRETE_DARK))


# --- Redondo parts ----------------------------------------------------------------------------

## The horseshoe centreline, in true world XZ: out along z = -RD_HALF_SPAN, round a half circle
## whose centre is the seaward end of the straights, and back along z = +RD_HALF_SPAN.
static func _rd_path(anchor: Vector2, arc_steps: int, straight_steps: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var bend := Vector2(anchor.x - RD_ROOT_X - RD_STRAIGHT, anchor.y)
	for i in straight_steps + 1:
		var t := float(i) / straight_steps
		pts.append(Vector2(anchor.x - RD_ROOT_X - t * RD_STRAIGHT, anchor.y - RD_HALF_SPAN))
	for i in range(1, arc_steps + 1):
		var a := -PI * 0.5 - PI * float(i) / arc_steps
		pts.append(bend + Vector2(cos(a), sin(a)) * RD_HALF_SPAN)
	for i in range(1, straight_steps + 1):
		var t := float(i) / straight_steps
		pts.append(Vector2(anchor.x - RD_ROOT_X - RD_STRAIGHT + t * RD_STRAIGHT, anchor.y + RD_HALF_SPAN))
	return pts


## How far a deck segment must run past path point `i` for the outside of the turn to stay solid:
## half the deck width times the tangent of half the turn angle, plus a little overlap.
static func _rd_joint_ext(pts: PackedVector2Array, i: int) -> float:
	if i <= 0 or i >= pts.size() - 1:
		return 0.35
	var d0 := (pts[i] - pts[i - 1]).normalized()
	var d1 := (pts[i + 1] - pts[i]).normalized()
	return 0.35 + RD_DECK_W * 0.5 * tan(absf(d0.angle_to(d1)) * 0.5)


## Deck segments along the path, the cross deck that ties the two legs together at the root, and
## the planking gaps. Local axes inside a segment pivot: +X runs along the path, +Z is the OUTER
## side of the horseshoe, -Z the lagoon side.
static func _rd_deck(parent: Node3D, statics: StaticBody3D, pts: PackedVector2Array, anchor: Vector2, timber: Material, batch: MultiMeshBatch, detailed: bool) -> void:
	var plank := _box_mesh(Vector3(0.14, 0.07, RD_DECK_W - 0.2), PropFactory.material(TIMBER_DARK, 0.95))
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var d := (b - a).normalized()
		# Each end runs past its path point by half the turn there: without that, every joint on
		# the OUTSIDE of the bend leaves a wedge-shaped hole in the deck (and in its collision)
		# wide enough to drop a player into the sea.
		var ext_a := _rd_joint_ext(pts, i)
		var ext_b := _rd_joint_ext(pts, i + 1)
		var length := a.distance_to(b) + ext_a + ext_b
		var mid := (a + b) * 0.5 + d * ((ext_b - ext_a) * 0.5)
		var yaw := _yaw(d)
		_obox(parent, statics, Vector3(length, DECK_T, RD_DECK_W), Vector3(mid.x, DECK_Y, mid.y), Vector3(0.0, yaw, 0.0), timber, true)
		if not detailed:
			continue
		var planks := int(length / RD_PLANK_STEP)
		for k in planks:
			var t := (float(k) + 0.5) / planks - 0.5
			var p := mid + d * (t * length)
			batch.add("rd_plank", plank, _xform(Vector3(p.x, DECK_Y + DECK_T * 0.5 + 0.02, p.y), yaw))
	# Root cross deck joining the two legs, and the approach spur to the land.
	var root_x := anchor.x - RD_ROOT_X
	_obox(parent, statics, Vector3(RD_DECK_W, DECK_T, RD_HALF_SPAN * 2.0 + RD_DECK_W),
			Vector3(root_x, DECK_Y, anchor.y), Vector3.ZERO, timber, true)
	_obox(parent, statics, Vector3(RD_ROOT_X + 2.0, DECK_T, RD_DECK_W + 4.0),
			Vector3(anchor.x - RD_ROOT_X * 0.5 + 1.0, DECK_Y, anchor.y), Vector3.ZERO, timber, true)


## Two piles per bent under every path point, a cross brace above the water, and a diagonal pair.
static func _rd_piles(batch: MultiMeshBatch, pts: PackedVector2Array, detailed: bool) -> void:
	var top := DECK_Y - DECK_T * 0.5
	var h := top - PILE_FOOT
	var pile := _cyl_mesh(RD_PILE_R, h, 8 if detailed else 5, PropFactory.material(TIMBER_DARK, 0.95))
	var brace := _box_mesh(Vector3(0.28, 0.28, RD_PILE_GAUGE * 2.0), PropFactory.material(TIMBER_DARK, 0.95))
	for i in pts.size():
		var p := pts[i]
		var d: Vector2
		if i < pts.size() - 1:
			d = (pts[i + 1] - p).normalized()
		else:
			d = (p - pts[i - 1]).normalized()
		var n := Vector2(-d.y, d.x)
		var yaw := _yaw(d)
		for side: float in [-1.0, 1.0]:
			var q := p + n * (side * RD_PILE_GAUGE)
			batch.add("rd_pile", pile, _xform(Vector3(q.x, PILE_FOOT + h * 0.5, q.y), 0.0))
		if detailed:
			batch.add("rd_brace", brace, _xform(Vector3(p.x, 1.6, p.y), yaw))
			batch.add("rd_brace", brace, _xform(Vector3(p.x, 4.4, p.y), yaw))


## Which deck segments carry a shop. Deterministic: the rng is seeded from the anchor.
static func _rd_shop_flags(segments: int, rng: RandomNumberGenerator) -> Array[bool]:
	var flags: Array[bool] = []
	for i in segments:
		# The first and last segment of each leg stay open, and so does the apex of the bend,
		# where the stair down to the lower deck lands.
		var near_root := i <= 0 or i >= segments - 1
		var apex := absi(i - segments / 2) <= 1
		var under_sign := absi(i - RD_SIGN_SEGMENT) <= 1
		var keep := rng.randf() > RD_SHOP_GAP_CHANCE
		flags.append(under_sign or (not near_root and not apex and keep))
	return flags


## Shops along the lagoon side of the deck, one or two storeys apiece. The three under the
## ROUNDWOOD hoarding are always two, because that is what its legs stand on.
static func _rd_shops(parent: Node3D, statics: StaticBody3D, pts: PackedVector2Array, flags: Array[bool], deck_top: float, rng: RandomNumberGenerator) -> void:
	for i in flags.size():
		if not flags[i]:
			continue
		var a := pts[i]
		var b := pts[i + 1]
		var d := (b - a).normalized()
		var mid := (a + b) * 0.5
		var inner := Vector2(d.y, -d.x)
		var off := RD_DECK_W * 0.5 - RD_SHOP_D * 0.5
		var at := mid + inner * off
		var tall := absi(i - RD_SIGN_SEGMENT) <= 1 or rng.randf() > RD_SHOP_SINGLE_CHANCE
		_rd_shop(parent, statics, Vector3(at.x, deck_top, at.y), _yaw(d), a.distance_to(b) - 1.6, rng, tall)


## One shop block. Built inside a yawed pivot so every part is in easy local coordinates: +X along
## the pier, +Z toward the promenade (the shopfront side), -Z toward the lagoon edge.
static func _rd_shop(parent: Node3D, statics: StaticBody3D, at: Vector3, yaw: float, length: float, rng: RandomNumberGenerator, tall: bool) -> void:
	var wall := PropFactory.material(SHOP_COLORS[rng.randi() % SHOP_COLORS.size()], 0.9)
	var trim := TRIM_COLORS[rng.randi() % TRIM_COLORS.size()]
	var pivot := _pivot(parent, at, yaw)
	var front := RD_SHOP_D * 0.5
	var glass := PropFactory.material(GLASS, 0.2)
	var dark := PropFactory.material(TIMBER_DARK, 0.9)
	var upper: float = RD_SHOP_H2 if tall else 0.0
	var eave := RD_SHOP_H1 + upper
	# The storeys and the pitched roof (one PrismMesh: eight triangles for the whole thing).
	_obox(pivot, null, Vector3(length, RD_SHOP_H1, RD_SHOP_D), Vector3(0.0, RD_SHOP_H1 * 0.5, 0.0), Vector3.ZERO, wall, false)
	if tall:
		_obox(pivot, null, Vector3(length - 0.5, upper, RD_SHOP_D - 0.7), Vector3(0.0, RD_SHOP_H1 + upper * 0.5, 0.0), Vector3.ZERO, wall, false)
	var roof := PrismMesh.new()
	roof.size = Vector3((RD_SHOP_D + 0.5) if tall else (RD_SHOP_D + 0.9), RD_ROOF_RISE, length + 0.4)
	roof.material = PropFactory.material(TIMBER_DARK, 0.85)
	var roof_node := MeshInstance3D.new()
	roof_node.mesh = roof
	roof_node.position = Vector3(0.0, eave + RD_ROOF_RISE * 0.5, 0.0)
	roof_node.rotation.y = PI * 0.5
	pivot.add_child(roof_node)
	# Shopfront, sign band, awning and its posts.
	_obox(pivot, null, Vector3(length - 1.4, RD_SHOP_H1 - 1.5, 0.3), Vector3(0.0, (RD_SHOP_H1 - 1.5) * 0.5 + 0.25, front + 0.1), Vector3.ZERO, glass, false)
	_obox(pivot, null, Vector3(length - 0.6, 0.85, 0.35), Vector3(0.0, RD_SHOP_H1 - 0.5, front + 0.2), Vector3.ZERO, WeaponFX.unshaded(trim), false)
	var awning := _obox(pivot, null, Vector3(length - 0.9, 0.14, 2.2), Vector3(0.0, RD_SHOP_H1 - 1.35, front + 1.1), Vector3.ZERO, PropFactory.material(trim, 0.85), false)
	awning.rotation.x = 0.16
	for sx: float in [-0.5, 0.5]:
		_cyl_node(pivot, 0.07, RD_SHOP_H1 - 1.5, 5, Vector3(sx * (length - 1.4), (RD_SHOP_H1 - 1.5) * 0.5, front + 2.0), dark)
	# Upper windows and the narrow balcony rail in front of them, on the two-storey ones.
	if tall:
		var bays := maxi(2, int(length / 3.4))
		for k in bays:
			var bx := (float(k) + 0.5) / bays - 0.5
			_obox(pivot, null, Vector3(1.3, 1.7, 0.25), Vector3(bx * (length - 1.2), RD_SHOP_H1 + upper * 0.55, front - 0.2), Vector3.ZERO, glass, false)
		_obox(pivot, null, Vector3(length - 0.5, 0.12, 1.2), Vector3(0.0, RD_SHOP_H1 + 0.06, front + 0.2), Vector3.ZERO, dark, false)
		_obox(pivot, null, Vector3(length - 0.5, 0.1, 0.1), Vector3(0.0, RD_SHOP_H1 + 0.95, front + 0.75), Vector3.ZERO, dark, false)
	# Roughly a third of them get a hoarding standing on the roof.
	if rng.randf() < 0.36:
		_obox(pivot, null, Vector3(length * 0.7, 2.4, 0.22), Vector3(0.0, eave + RD_ROOF_RISE + 1.2, 0.3), Vector3.ZERO, WeaponFX.unshaded(trim.lightened(0.15)), false)
		for sx: float in [-0.34, 0.34]:
			_obox(pivot, null, Vector3(0.16, RD_ROOF_RISE + 1.0, 0.16), Vector3(sx * length, eave + RD_ROOF_RISE * 0.5 + 0.2, 0.3), Vector3.ZERO, dark, false)
	# One rotated collision box for the whole block.
	if statics != null:
		var shape := CollisionShape3D.new()
		var s := BoxShape3D.new()
		s.size = Vector3(length, eave, RD_SHOP_D)
		shape.shape = s
		shape.position = at + Vector3(0.0, eave * 0.5, 0.0)
		shape.rotation.y = yaw
		statics.add_child(shape)


## A single long bar of shop-coloured boxes for the far copy, so the horseshoe still reads as
## built-up rather than as a bare deck.
static func _rd_far_shops(parent: Node3D, pts: PackedVector2Array, deck_top: float) -> void:
	var wall := PropFactory.material(SHOP_COLORS[0], 0.9)
	var roof := PropFactory.material(TIMBER_DARK, 0.85)
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var d := (b - a).normalized()
		var inner := Vector2(d.y, -d.x)
		var at := (a + b) * 0.5 + inner * (RD_DECK_W * 0.5 - RD_SHOP_D * 0.5)
		var length := a.distance_to(b) + 0.6
		var yaw := _yaw(d)
		_obox(parent, null, Vector3(length, RD_SHOP_H1 + RD_SHOP_H2, RD_SHOP_D), Vector3(at.x, deck_top + (RD_SHOP_H1 + RD_SHOP_H2) * 0.5, at.y), Vector3(0.0, yaw, 0.0), wall, false)
		_obox(parent, null, Vector3(length, 0.9, RD_SHOP_D + 0.5), Vector3(at.x, deck_top + RD_SHOP_H1 + RD_SHOP_H2 + 0.45, at.y), Vector3(0.0, yaw, 0.0), roof, false)


## Fishing rails: the outer edge everywhere except the segment the stair drops through, and the
## lagoon edge wherever a shop does not already close it off.
static func _rd_rails(parent: Node3D, batch: MultiMeshBatch, pts: PackedVector2Array, flags: Array[bool], deck_top: float, stair_seg: int) -> void:
	var mat := PropFactory.material(TIMBER_PALE, 0.9)
	var post := _box_mesh(Vector3(0.14, RD_RAIL_H, 0.14), mat)
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var d := (b - a).normalized()
		var n := Vector2(-d.y, d.x)
		var length := a.distance_to(b)
		var mid := (a + b) * 0.5
		var yaw := _yaw(d)
		var sides: Array[float] = []
		if i != stair_seg:
			sides.append(1.0)
		if not flags[i]:
			sides.append(-1.0)
		for side: float in sides:
			var edge := mid + n * (side * (RD_DECK_W * 0.5 - 0.3))
			for level: float in [RD_RAIL_H, RD_RAIL_H * 0.52]:
				_obox(parent, null, Vector3(length + 0.4, 0.1, 0.1), Vector3(edge.x, deck_top + level, edge.y), Vector3(0.0, yaw, 0.0), mat, false)
			var count := maxi(1, int(length / RD_RAIL_POST_STEP))
			for k in count:
				var t := (float(k) + 0.5) / count - 0.5
				var p := edge + d * (t * length)
				batch.add("rd_post", post, _xform(Vector3(p.x, deck_top + RD_RAIL_H * 0.5, p.y), yaw))


## The lower fishing deck hung off the outer edge at the apex of the bend, with its own piles,
## a railing and a flight of stairs down from the main deck.
static func _rd_lower_deck(parent: Node3D, statics: StaticBody3D, batch: MultiMeshBatch, pts: PackedVector2Array, deck_top: float, stair_seg: int) -> void:
	var i := stair_seg
	var p := pts[i]
	var d := (pts[i] - pts[i - 1]).normalized()
	var n := Vector2(-d.y, d.x)
	var at := p + n * (RD_DECK_W * 0.5 + RD_LOWER_W * 0.5 - 1.0)
	var yaw := _yaw(d)
	var timber := PropFactory.material(TIMBER, 0.92)
	var dark := PropFactory.material(TIMBER_DARK, 0.95)
	_obox(parent, statics, Vector3(RD_LOWER_LEN, DECK_T * 0.7, RD_LOWER_W), Vector3(at.x, RD_LOWER_Y, at.y), Vector3(0.0, yaw, 0.0), timber, true)
	var pivot := _pivot(parent, Vector3(at.x, RD_LOWER_Y, at.y), yaw)
	for level: float in [1.0, 0.5]:
		_obox(pivot, null, Vector3(RD_LOWER_LEN, 0.1, 0.1), Vector3(0.0, 0.4 + level, RD_LOWER_W * 0.5 - 0.3), Vector3.ZERO, timber, false)
	for k in 10:
		var bx := (float(k) + 0.5) / 10.0 - 0.5
		_obox(pivot, null, Vector3(0.14, 1.0, 0.14), Vector3(bx * RD_LOWER_LEN, 0.9, RD_LOWER_W * 0.5 - 0.3), Vector3.ZERO, timber, false)
	# Piles under it.
	var h := RD_LOWER_Y - PILE_FOOT
	var pile := _cyl_mesh(RD_PILE_R, h, 6, dark)
	for k in 4:
		var bx := (float(k) + 0.5) / 4.0 - 0.5
		for sz: float in [-0.32, 0.32]:
			var q := at + d * (bx * RD_LOWER_LEN) + n * (sz * RD_LOWER_W)
			batch.add("rd_pile", pile, _xform(Vector3(q.x, PILE_FOOT + h * 0.5, q.y), 0.0))
	# Stair down from the main deck's outer edge onto the lower deck. It gets a frame of its own
	# on the deck segment it lands on: the bend curves away from this platform's tangent, so a
	# stair head hung off THIS pivot would finish up to two metres clear of the deck edge, in
	# mid air. _rd_rails() leaves the outer railing of `stair_seg` open for it.
	var drop := deck_top - (RD_LOWER_Y + DECK_T * 0.35)
	var run := 7.0
	var steps := 10
	var sa := pts[stair_seg]
	var sb := pts[stair_seg + 1]
	var sd := (sb - sa).normalized()
	var sn := Vector2(-sd.y, sd.x)
	var syaw := _yaw(sd)
	var head := (sa + sb) * 0.5 + sn * (RD_DECK_W * 0.5 - 0.6)
	var stair := _pivot(parent, Vector3(head.x, deck_top, head.y), syaw)
	for k in steps:
		var t := (float(k) + 0.5) / float(steps)
		_obox(stair, null, Vector3(1.8, 0.18, run / steps + 0.12),
				Vector3(0.0, -drop * t + 0.09, t * run), Vector3.ZERO, dark, false)
	# Hand rails down both sides of the flight, so the gap in the fishing rail reads as a stair
	# head and not as a hole someone forgot to fence.
	for sx: float in [-1.0, 1.0]:
		var hand := _obox(stair, null, Vector3(0.1, 0.1, sqrt(drop * drop + run * run)),
				Vector3(sx * 1.05, RD_RAIL_H - drop * 0.5, run * 0.5), Vector3.ZERO, timber, false)
		hand.rotation.x = atan2(drop, run)
		for k in 4:
			var t := (float(k) + 0.5) / 4.0
			_obox(stair, null, Vector3(0.1, RD_RAIL_H, 0.1),
					Vector3(sx * 1.05, RD_RAIL_H * 0.5 - drop * t, t * run), Vector3.ZERO, timber, false)
	if statics != null:
		var flight := CollisionShape3D.new()
		var fs := BoxShape3D.new()
		fs.size = Vector3(1.8, 0.35, sqrt(drop * drop + run * run))
		flight.shape = fs
		var mid := head + sn * (run * 0.5)
		flight.position = Vector3(mid.x, deck_top - drop * 0.5 + 0.05, mid.y)
		flight.basis = Basis(Vector3.UP, syaw) * Basis(Vector3.RIGHT, atan2(drop, run))
		statics.add_child(flight)


## Lamp posts down the promenade side, spaced by segment.
static func _rd_lamps(batch: MultiMeshBatch, pts: PackedVector2Array, deck_top: float) -> void:
	var pole := _cyl_mesh(0.11, 5.0, 6, PropFactory.material(TIMBER_DARK, 0.8))
	var globe := _sphere_mesh(0.36, _lamp_glow())
	var pool := PropFactory.light_pool()
	for i in pts.size() - 1:
		if i % 2 != 0:
			continue
		var a := pts[i]
		var b := pts[i + 1]
		var d := (b - a).normalized()
		var n := Vector2(-d.y, d.x)
		var at := (a + b) * 0.5 + n * (RD_DECK_W * 0.5 - 1.2)
		batch.add("rd_pole", pole, _xform(Vector3(at.x, deck_top + 2.5, at.y), 0.0))
		batch.add("rd_globe", globe, _xform(Vector3(at.x, deck_top + 5.3, at.y), 0.0))
		batch.add("rd_pool", pool, _pool_xform(Vector3(at.x, deck_top + 0.06, at.y), LAMP_POOL))
	batch.set_no_shadow("rd_pool")


## Entrance gate over the approach spur.
static func _rd_entrance(parent: Node3D, statics: StaticBody3D, anchor: Vector2, deck_top: float) -> void:
	var timber := PropFactory.material(TIMBER_DARK, 0.9)
	var x := anchor.x - 2.0
	for side: float in [-1.0, 1.0]:
		_obox(parent, statics, Vector3(0.9, 7.0, 0.9), Vector3(x, deck_top + 3.5, anchor.y + side * (RD_DECK_W * 0.5 + 1.2)), Vector3.ZERO, timber, true)
	_obox(parent, null, Vector3(0.7, 2.0, RD_DECK_W + 4.2), Vector3(x, deck_top + 7.4, anchor.y), Vector3.ZERO, PropFactory.material(TIMBER_PALE, 0.9), false)
	var label := Label3D.new()
	label.text = "REDONDO WHARF"
	label.font_size = 150
	label.pixel_size = 0.011
	label.outline_size = 22
	label.modulate = Color(0.16, 0.12, 0.08)
	label.position = Vector3(x + 0.45, deck_top + 7.4, anchor.y)
	label.rotation.y = PI * 0.5
	parent.add_child(label)


## The big block-letter hoarding standing on the shop roofs of the return leg. Landmarks._text()
## draws along +X facing +-Z, which is exactly the orientation of that leg, so no rotation is
## needed - and RD_SIGN_SEGMENT guarantees there are shop roofs underneath it.
static func _rd_sign(parent: Node3D, pts: PackedVector2Array, deck_top: float) -> void:
	var i: int = mini(RD_SIGN_SEGMENT, pts.size() - 2)
	var a := pts[i]
	var b := pts[i + 1]
	var d := (b - a).normalized()
	var inner := Vector2(d.y, -d.x)
	# Shop centreline, then out to its shopfront face, where the hoarding stands.
	var at := (a + b) * 0.5 + inner * (RD_DECK_W * 0.5 - RD_SHOP_D * 0.5) - inner * (RD_SHOP_D * 0.5 - 0.6)
	var base := deck_top + RD_SHOP_H1 + RD_SHOP_H2 + RD_ROOF_RISE + 0.2
	var centre := Vector3(at.x, base, at.y)
	var width := RD_SIGN_TEXT.length() * 5.0 * RD_SIGN_CELL + (RD_SIGN_TEXT.length() - 1) * 1.5 * RD_SIGN_CELL
	var back := Vector3(0.0, 7.0 * RD_SIGN_CELL * 0.5, inner.y * 0.3)
	_obox(parent, null, Vector3(width + 2.0, 7.0 * RD_SIGN_CELL + 1.0, 0.25), centre + back,
			Vector3.ZERO, PropFactory.material(Color(0.14, 0.13, 0.12), 0.9), false)
	Landmarks._text(RD_SIGN_TEXT, RD_SIGN_CELL, centre, parent, Color(0.98, 0.86, 0.35))
	for sx: float in [-0.5, 0.5]:
		_obox(parent, null, Vector3(0.2, 3.6, 0.2), centre + Vector3(sx * width, -1.8, inner.y * 0.3),
				Vector3.ZERO, PropFactory.material(TIMBER_DARK, 0.9), false)


## The car park at the root, on the land: a surface lot always, plus an upper deck on columns
## level with the pier whenever the ground leaves enough headroom underneath.
static func _rd_car_park(parent: Node3D, statics: StaticBody3D, anchor: Vector2, plan: CityPlan, detailed: bool) -> void:
	var ground := 0.1
	var low := 0.1
	if plan != null:
		var hs: Array[float] = []
		for c: Vector2 in [Vector2(RD_PARK_GAP + RD_PARK_D * 0.5, 0.0),
				Vector2(RD_PARK_GAP, -RD_PARK_W * 0.5), Vector2(RD_PARK_GAP, RD_PARK_W * 0.5),
				Vector2(RD_PARK_GAP + RD_PARK_D, -RD_PARK_W * 0.5), Vector2(RD_PARK_GAP + RD_PARK_D, RD_PARK_W * 0.5)]:
			hs.append(plan.height_at(anchor + c))
		hs.sort()
		low = hs[0]
		# The median of the five samples, and never more than a storey of fill above the lowest
		# of them. Taking the highest corner (which is what this did) put the whole lot on a
		# twenty-metre podium wherever the shore behind the pier climbs into a headland.
		ground = minf(hs[hs.size() / 2], low + RD_PARK_FILL)
	var cx := anchor.x + RD_PARK_GAP + RD_PARK_D * 0.5
	var asphalt := PropFactory.pbr("asphalt", 8.0, Color(0.42, 0.42, 0.44))
	var concrete := _concrete()
	_obox(parent, statics, Vector3(RD_PARK_D, 1.2, RD_PARK_W), Vector3(cx, ground - 0.6, anchor.y), Vector3.ZERO, asphalt, true)
	# The lot is flat but the shore behind a pier rarely is: where the ground falls away under it,
	# stand it on a retaining podium rather than leaving a slab hanging in the air.
	if ground - low > 0.6:
		var wall_h := ground - low - 0.2
		_obox(parent, statics, Vector3(RD_PARK_D - 0.6, wall_h, RD_PARK_W - 0.6),
				Vector3(cx, ground - 1.2 - wall_h * 0.5, anchor.y), Vector3.ZERO, concrete, true)
	var two_level := DECK_Y - ground >= RD_PARK_CLEAR
	if two_level:
		# Columns, then the upper deck at the pier's own level so the two meet flush. The deck
		# stops short of the seaward edge: that strip is the ramp's slot, left open so a car can
		# actually drive out onto the deck instead of into its underside.
		var rise := DECK_Y - ground
		var run := RD_PARK_D * 0.6
		var ramp_len := sqrt(rise * rise + run * run)
		var ramp_z := anchor.y - RD_PARK_W * 0.5 + 0.5 + RD_RAMP_W * 0.5
		var gate_x := cx + RD_PARK_D * 0.1 + ramp_len * 0.5
		var deck_w := RD_PARK_W - RD_RAMP_W - 0.5
		var deck_z := anchor.y + RD_PARK_W * 0.5 - deck_w * 0.5
		if detailed:
			var col := _cyl_mesh(0.42, rise, 8, concrete)
			var batch := MultiMeshBatch.new()
			for ix in 5:
				for iz in 6:
					var p := Vector3(cx - RD_PARK_D * 0.42 + ix * RD_PARK_D * 0.21,
							ground + rise * 0.5,
							deck_z - deck_w * 0.4 + iz * deck_w * 0.16)
					batch.add("rd_col", col, _xform(p, 0.0))
			batch.build(parent)
		_obox(parent, statics, Vector3(RD_PARK_D, DECK_T, deck_w), Vector3(cx, DECK_Y, deck_z), Vector3.ZERO, concrete, true)
		# Spandrel band round the upper deck: open at the pier side, and open at the head of the
		# ramp so the last twelve metres of the climb have somewhere to turn out.
		_obox(parent, statics, Vector3(RD_PARK_D, 1.1, 0.5), Vector3(cx, DECK_Y + 1.0, deck_z + deck_w * 0.5), Vector3.ZERO, concrete, false)
		_obox(parent, statics, Vector3(0.5, 1.1, deck_w), Vector3(cx + RD_PARK_D * 0.5, DECK_Y + 1.0, deck_z), Vector3.ZERO, concrete, false)
		var band_end := gate_x - 12.0
		var band_start := cx - RD_PARK_D * 0.5
		if band_end - band_start > 4.0:
			_obox(parent, statics, Vector3(band_end - band_start, 1.1, 0.5),
					Vector3((band_end + band_start) * 0.5, DECK_Y + 1.0, deck_z - deck_w * 0.5), Vector3.ZERO, concrete, false)
		# Ramp from the surface lot up to the deck, in its slot along the seaward edge.
		_obox(parent, statics, Vector3(ramp_len, DECK_T, RD_RAMP_W),
				Vector3(cx + RD_PARK_D * 0.1, ground + rise * 0.5, ramp_z), Vector3(0.0, 0.0, atan2(rise, run)), concrete, true)
		# Link from the deck to the pier root: both are at DECK_Y, so it is flat.
		_obox(parent, statics, Vector3(RD_PARK_GAP + 2.0, DECK_T, RD_DECK_W + 4.0),
				Vector3(anchor.x + RD_PARK_GAP * 0.5, DECK_Y, anchor.y), Vector3.ZERO, concrete, true)
	else:
		# No upper deck, so the pier has to meet the ground itself: a ramp from the deck down to
		# the lot (or up to it, where the shore behind the pier is higher than the deck). Without
		# this the whole pier is cut off from the land the moment the shore is not at sea level.
		var climb := ground - DECK_Y
		var reach := maxf(RD_PARK_GAP + 8.0, absf(climb) * 4.0)
		_obox(parent, statics, Vector3(sqrt(climb * climb + reach * reach), DECK_T, RD_DECK_W + 4.0),
				Vector3(anchor.x - 2.0 + reach * 0.5, DECK_Y + climb * 0.5, anchor.y),
				Vector3(0.0, 0.0, atan2(climb, reach)), concrete, true)
	if not detailed:
		return
	# Painted bays on the surface lot and a few light poles.
	var paint := PropFactory.material(PAINT_WHITE, 0.9, true)
	var batch2 := MultiMeshBatch.new()
	var line := _box_mesh(Vector3(5.0, 0.04, 0.16), paint)
	var rows := int(RD_PARK_W / RD_BAY)
	for r in rows:
		var z := anchor.y - RD_PARK_W * 0.5 + (r + 0.5) * RD_BAY
		for c in 2:
			batch2.add("rd_bay", line, _xform(Vector3(cx - RD_PARK_D * 0.25 + c * RD_PARK_D * 0.5, ground + 0.04, z), 0.0))
	var pole := _cyl_mesh(0.16, 9.0, 6, PropFactory.material(CONCRETE_DARK))
	# On the top deck when there is one: a nine metre pole standing on the lot underneath it goes
	# straight up through the slab.
	var pole_y := (DECK_Y + DECK_T * 0.5 + 4.5) if two_level else (ground + 4.5)
	for ix in 2:
		for iz in 3:
			batch2.add("rd_lightpole", pole, _xform(Vector3(cx - RD_PARK_D * 0.25 + ix * RD_PARK_D * 0.5, pole_y, anchor.y - RD_PARK_W * 0.33 + iz * RD_PARK_W * 0.33), 0.0))
	batch2.build(parent)


# --- Small shared pieces ------------------------------------------------------------------------

## A slatted bench facing the water. `face` is +1 or -1: which way the backrest looks (along
## local -Z or +Z). `yaw` turns the whole bench, so it can also sit round the curve of the head.
static func _bench(parent: Node3D, at: Vector3, face: float, yaw: float = 0.0) -> void:
	var wood := PropFactory.material(TIMBER_PALE, 0.9)
	var metal := PropFactory.material(CONCRETE_DARK)
	var pivot := _pivot(parent, at, yaw)
	_obox(pivot, null, Vector3(2.2, 0.12, 0.6), Vector3(0.0, 0.48, 0.0), Vector3.ZERO, wood, false)
	_obox(pivot, null, Vector3(2.2, 0.55, 0.1), Vector3(0.0, 0.8, -face * 0.28), Vector3.ZERO, wood, false)
	for sx: float in [-0.85, 0.85]:
		_obox(pivot, null, Vector3(0.1, 0.45, 0.55), Vector3(sx, 0.22, 0.0), Vector3.ZERO, metal, false)


# --- Helpers ------------------------------------------------------------------------------------
# Landmarks._box() / _cyl() only take a plain Colour and an axis-aligned collision box, so these
# two wrap the same idea with a Material and a rotation. Landmarks._text(), the block-letter
# font, is used directly.

## One box mesh with euler rotation, an explicit material, and optional rotated collision.
## `pos` is in `parent`'s space but a collision shape goes on `statics`, which is in world space:
## pass `collide` false (or a null `statics`) whenever `parent` is one of the local pivots.
static func _obox(parent: Node3D, statics: StaticBody3D, size: Vector3, pos: Vector3, rot: Vector3, mat: Material, collide: bool) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = mat
	mesh.position = pos
	mesh.rotation = rot
	parent.add_child(mesh)
	if collide and statics != null:
		var shape := CollisionShape3D.new()
		var s := BoxShape3D.new()
		s.size = size
		shape.shape = s
		shape.position = pos
		shape.rotation = rot
		statics.add_child(shape)
	return mesh


## An n-sided prism or pyramid (a CylinderMesh with a low radial_segments count is exactly that).
## Collision, when asked for, is a plain cylinder of the larger radius.
static func _poly(parent: Node3D, statics: StaticBody3D, bottom_r: float, top_r: float, height: float, sides: int, pos: Vector3, yaw: float, mat: Material, collide: bool) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = top_r
	cyl.bottom_radius = bottom_r
	cyl.height = height
	cyl.radial_segments = sides
	cyl.rings = 0
	mesh.mesh = cyl
	mesh.material_override = mat
	mesh.position = pos
	mesh.rotation.y = yaw
	parent.add_child(mesh)
	if collide and statics != null:
		var shape := CollisionShape3D.new()
		var s := CylinderShape3D.new()
		s.radius = maxf(bottom_r, top_r) * 0.94
		s.height = height
		shape.shape = s
		shape.position = pos
		statics.add_child(shape)
	return mesh


## A cheap cylinder node (no collision) with a chosen segment count.
static func _cyl_node(parent: Node3D, radius: float, height: float, sides: int, pos: Vector3, mat: Material) -> MeshInstance3D:
	return _poly(parent, null, radius, radius, height, sides, pos, 0.0, mat, false)


## An empty yawed node to hang local-space children off.
static func _pivot(parent: Node3D, pos: Vector3, yaw: float) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	n.rotation.y = yaw
	parent.add_child(n)
	return n


## Yaw that points a node's local +X along the world XZ direction `d`.
static func _yaw(d: Vector2) -> float:
	return atan2(-d.y, d.x)


static func _xform(pos: Vector3, yaw: float) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw), pos)


static func _box_mesh(size: Vector3, mat: Material) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	m.material = mat
	return m


static func _cyl_mesh(radius: float, height: float, sides: int, mat: Material) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = radius
	m.bottom_radius = radius
	m.height = height
	m.radial_segments = sides
	m.rings = 0
	m.material = mat
	return m


static func _sphere_mesh(radius: float, mat: Material) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = radius
	m.height = radius * 2.0
	m.radial_segments = 8
	m.rings = 4
	m.material = mat
	return m


## The glowing part of a lamp: warm, lit like everything else by day, a little emissive so it
## still reads after dark. Unshaded white would be a flat dot at noon and no help at midnight.
static func _lamp_glow() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = LAMP_WARM
	mat.roughness = 0.4
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.9, 0.6)
	mat.emission_energy_multiplier = 1.5
	return mat


## Lays one of PropFactory's additive light-pool quads flat on the deck, `size` metres across.
## This is what the street lamps do, and it is the only thing that lights anything at night on
## the web build, so a pier without it is the one dark strip in a lit city.
static func _pool_xform(pos: Vector3, size: float) -> Transform3D:
	return Transform3D(Basis(Vector3.RIGHT, -PI * 0.5).scaled(Vector3(size, size, 1.0)), pos)


static func _concrete() -> StandardMaterial3D:
	return PropFactory.pbr("concrete", 6.0, CONCRETE_TINT)


static func _tile() -> StandardMaterial3D:
	return PropFactory.material(TILE_RED, 0.7)
