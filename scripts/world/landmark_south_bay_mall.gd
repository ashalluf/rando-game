class_name LandmarkSouthBayMall
extends RefCounted
## SOUTH BAY MALL - the big enclosed suburban shopping centre that anchors a South Bay town.
## A long blank retail bar with a department-store anchor at each end, a glazed entrance
## pavilion with a pyramid skylight over the atrium and a barrel-vaulted concourse roof behind
## it, a five-deck parking structure alongside, a surface lot with painted bays, planted islands
## and light poles, and a ring road round the whole site.
##
## This is the TYPE of building, not a copy of any real one: the name, the massing and the
## signage are original. Geography is fair game, trade dress is not.
##
## Local axes used throughout: +X runs along the mall (east), +Z is the front / lot side (south),
## so the entrance and the surface parking face +Z. Everything is added to `parent` at TRUE
## WORLD coordinates (base = anchor + pad height).
##
## Measured triangles: detailed 44.2k in 467 draw calls, far 0.9k in 61. The cost is the painted
## parking bays (9.1k, one MultiMesh), the three "SOUTH BAY MALL" TextMeshes (13.7k, cut at
## SIGN_DRAW_DISTANCE), the palms (6.5k, three MultiMeshes), the light poles (3.1k) and the deck
## columns (1.2k); everything else is boxes at twelve triangles each. LOT_ROWS and BAY_WIDTH move
## the bay count linearly, PALM_FRONDS moves the palm cost. Nothing here uses a SphereMesh, which
## is how a builder like this quietly costs ten times what its author thinks it does.

# --- Site ------------------------------------------------------------------------------------

## Half the site width, i.e. the ring road's east and west legs, in metres.
const SITE_HALF_X := 205.0
## Distance from the mall centre back (north, -Z) to the ring road's north leg, in metres.
const SITE_BACK := 76.0
## Distance from the mall centre forward (south, +Z) to the ring road's south leg, in metres.
const SITE_FRONT := 182.0
## Width of the ring road carriageway, in metres.
const RING_WIDTH := 11.0
## Thickness of every paved slab, in metres. Only the top face is ever seen: the rest is buried
## so the graded pad meets undulating ground with a skirt instead of a floating edge. The site is
## over four hundred metres across, so this has to be deeper than it looks like it needs to be.
const SLAB_THICK := 2.6
## Top of the ring road above the pad, in metres. The paved areas overlap, so each one sits at
## its own height a few centimetres apart: two coplanar slabs z-fight from the air.
const RING_TOP := 0.02
## Top of the service and deck aprons above the pad, in metres.
const APRON_TOP := 0.05
## Top of the surface car park above the pad, in metres.
const LOT_TOP := 0.08
## Height of painted road markings above the pad, in metres (just proud of the lot surface).
const MARK_TOP := 0.11
## Seed salt so the mall's random detail is stable for a given anchor.
const SEED_SALT := 528311

# --- Retail bar ------------------------------------------------------------------------------

## Length of the central windowless retail bar along X, in metres.
const BAR_LENGTH := 132.0
## Depth of the retail bar along Z, in metres.
const BAR_DEPTH := 76.0
## Height of the retail bar's blank wall to the parapet, in metres.
const BAR_HEIGHT := 13.0
## Height of the parapet standing above the bar roof, in metres.
const PARAPET_HEIGHT := 1.6

# --- Anchor department stores ----------------------------------------------------------------

## Width of one anchor store along X, in metres.
const ANCHOR_WIDTH := 40.0
## Depth of one anchor store along Z, in metres (deeper than the bar, so it reads as its own mass).
const ANCHOR_DEPTH := 88.0
## Height of one anchor store, in metres.
const ANCHOR_HEIGHT := 18.0
## Number of vertical pilasters on each long anchor wall.
const ANCHOR_PILASTERS := 9

# --- Entrance and skylights -------------------------------------------------------------------

## Width of the glazed entrance pavilion along X, in metres.
const ENTRY_WIDTH := 44.0
## How far the entrance pavilion projects in front of the bar, in metres.
const ENTRY_PROJECTION := 24.0
## Height of the glazed entrance pavilion, in metres.
const ENTRY_HEIGHT := 16.0
## Half-diagonal of the pyramid skylight over the atrium, in metres (a four-sided cone).
const PYRAMID_RADIUS := 18.0
## Height of the pyramid skylight above the pavilion roof, in metres.
const PYRAMID_HEIGHT := 11.0
## Radius of the barrel-vaulted skylight over the concourse, in metres.
const VAULT_RADIUS := 8.5
## Length of the barrel vault along the concourse, in metres.
const VAULT_LENGTH := 104.0
## Number of structural ribs across the barrel vault.
const VAULT_RIBS := 7
## Cap height of the SOUTH BAY MALL letters on the entrance fascia, in metres.
const SIGN_LETTER_HEIGHT := 2.4
## How far the sign letters keep drawing, in metres. A TextMesh is glyph outlines: one
## "SOUTH BAY MALL" is 4.5k triangles, and the three of them are a third of the whole landmark.
## Past this the dark band and the pylon panel carry the sign on their own.
const SIGN_DRAW_DISTANCE := 260.0

# --- Parking structure -------------------------------------------------------------------------

## Width of the parking structure along X, in metres.
const DECK_WIDTH := 62.0
## Depth of the parking structure along Z, in metres.
const DECK_DEPTH := 68.0
## Floor-to-floor height of one parking level, in metres.
const DECK_FLOOR := 3.4
## Number of elevated decks above the ground level.
const DECK_LEVELS := 5
## Gap between the west anchor's outer wall and the parking structure, in metres (the drive aisle).
const DECK_GAP := 14.0
## Column grid spacing inside the parking structure, in metres.
const DECK_COLUMN_STEP := 14.0
## Width of the ramp bay, measured in from the structure's east wall, in metres. Every elevated
## slab is cut away over this strip, which is what makes the ramps something you can drive.
const RAMP_BAY_X := 12.0
## Width of one ramp, in metres. Has to stay under RAMP_BAY_X.
const RAMP_WIDTH := 10.0
## Length of one ramp along Z, in metres. With DECK_FLOOR this sets the grade: 24 m to 3.4 m is
## about 1 in 7, which a car takes without scraping.
const RAMP_LENGTH := 24.0
## Distance from the deck centre to a ramp's centre, in metres. Ramps alternate north and south.
const RAMP_OFFSET := 17.0

# --- Surface car park --------------------------------------------------------------------------

## Half the painted parking field's width, in metres.
const LOT_HALF_X := 120.0
## Z of the first parking row, measured from the mall centre, in metres.
const LOT_START_Z := 80.0
## Number of double-loaded parking rows.
const LOT_ROWS := 5
## Depth of one row module: stalls, aisle, stalls, in metres.
const LOT_ROW_PITCH := 17.2
## Depth of a single parking stall, in metres.
const BAY_DEPTH := 5.4
## Width of a single parking stall, in metres. The painted line count scales with this.
const BAY_WIDTH := 2.75
## Height of a parking-lot light pole, in metres.
const LIGHT_POLE_HEIGHT := 9.0

# --- Planting ------------------------------------------------------------------------------------

## Number of fronds on one palm. Each frond is a box, so this is the palm's triangle cost.
const PALM_FRONDS := 7
## Length of one palm frond, in metres.
const PALM_FROND_LENGTH := 3.4
## Trunk radius of a palm at the base, in metres.
const PALM_TRUNK_RADIUS := 0.22

# --- Colours ---------------------------------------------------------------------------------

const STUCCO := Color(0.82, 0.77, 0.68)
const STUCCO_DARK := Color(0.56, 0.52, 0.46)
const ANCHOR_WARM := Color(0.76, 0.66, 0.54)
const ANCHOR_COOL := Color(0.74, 0.74, 0.73)
const CONCRETE := Color(0.72, 0.71, 0.69)
const TRIM := Color(0.30, 0.31, 0.34)
const GLASS_TINT := Color(0.55, 0.72, 0.82)
const PAINT_WHITE := Color(0.94, 0.94, 0.90)


## Entry point. `statics` is null for the far copy, `detailed` false builds the silhouette only.
static func build(anchor: Vector2, parent: Node3D, statics: StaticBody3D, plan: CityPlan, detailed: bool) -> void:
	var base := Vector3(anchor.x, _pad_height(plan, anchor), anchor.y)
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED_SALT + int(anchor.x) * 7919 + int(anchor.y) * 104729
	var batch := MultiMeshBatch.new()

	_site(parent, statics, base, detailed)
	_retail_bar(parent, statics, base, batch, rng, detailed)
	_anchor_store(parent, statics, base, -_anchor_offset(), ANCHOR_WARM, detailed)
	_anchor_store(parent, statics, base, _anchor_offset(), ANCHOR_COOL, detailed)
	_entrance(parent, statics, base, detailed)
	_parking_deck(parent, statics, base, batch, detailed)
	if detailed:
		_service_yard(parent, statics, base, rng)
		_lot_markings(parent, base, batch)
		_lot_planting(parent, statics, base, batch, rng)
		_pylon_sign(parent, statics, base)
	batch.build(parent)


## Centre-to-centre distance from the retail bar to one anchor store, in metres.
static func _anchor_offset() -> float:
	return BAR_LENGTH * 0.5 + ANCHOR_WIDTH * 0.5


## The graded pad the whole site sits on: the highest ground under the building footprint, so no
## corner of the mall is left floating on a slope.
static func _pad_height(plan: CityPlan, anchor: Vector2) -> float:
	if plan == null:
		return 0.1
	var h := plan.height_at(anchor)
	var hx := _anchor_offset() + ANCHOR_WIDTH * 0.5
	var hz := ANCHOR_DEPTH * 0.5
	for c: Vector2 in [Vector2(-hx, -hz), Vector2(hx, -hz), Vector2(-hx, hz), Vector2(hx, hz)]:
		h = maxf(h, plan.height_at(anchor + c))
	return h + 0.1


# --- Site: ring road, lot deck, plaza ----------------------------------------------------------

static func _site(parent: Node3D, statics: StaticBody3D, base: Vector3, detailed: bool) -> void:
	var asphalt := PropFactory.pbr("asphalt", 7.5, Color(0.55, 0.55, 0.57))
	# Ring road, four legs. Corners overlap; nobody sees the seam under the asphalt. Each paved
	# area gets its own top height a few centimetres apart, because two coplanar slabs z-fight.
	var span_x := SITE_HALF_X * 2.0 + RING_WIDTH
	var span_z := SITE_FRONT + SITE_BACK + RING_WIDTH
	var mid_z := (SITE_FRONT - SITE_BACK) * 0.5
	var ring_y := base.y + RING_TOP
	_pave(parent, statics, Vector3(span_x, SLAB_THICK, RING_WIDTH), Vector3(base.x, ring_y, base.z - SITE_BACK), asphalt)
	_pave(parent, statics, Vector3(span_x, SLAB_THICK, RING_WIDTH), Vector3(base.x, ring_y, base.z + SITE_FRONT), asphalt)
	_pave(parent, statics, Vector3(RING_WIDTH, SLAB_THICK, span_z), Vector3(base.x - SITE_HALF_X, ring_y, base.z + mid_z), asphalt)
	_pave(parent, statics, Vector3(RING_WIDTH, SLAB_THICK, span_z), Vector3(base.x + SITE_HALF_X, ring_y, base.z + mid_z), asphalt)

	# Service and deck aprons on the north and west sides, so the mall is not an island.
	var apron_y := base.y + APRON_TOP
	_pave(parent, statics, Vector3(300.0, SLAB_THICK, 38.0), Vector3(base.x, apron_y, base.z - 57.0), asphalt)
	_pave(parent, statics, Vector3(96.0, SLAB_THICK, 150.0), Vector3(base.x - 152.0, apron_y, base.z + 10.0), asphalt)
	_pave(parent, statics, Vector3(80.0, SLAB_THICK, 150.0), Vector3(base.x + 150.0, apron_y, base.z + 10.0), asphalt)

	# The surface car park deck itself: one big slab from the plaza to the south ring leg, and wide
	# enough to MEET the ring road's side legs. At the painted field's own width it stopped sixty
	# metres short of them and left a band of bare ground between the lot and its own access road.
	var lot_depth := SITE_FRONT - 72.0
	_pave(parent, statics, Vector3(SITE_HALF_X * 2.0, SLAB_THICK, lot_depth), Vector3(base.x, base.y + LOT_TOP, base.z + 72.0 + lot_depth * 0.5), asphalt)

	# Entrance plaza in front of the glazed pavilion, and the frontage walk that runs on past
	# both anchors. The walks sit 2 cm lower than the plaza so the overlap does not z-fight.
	var plaza := Landmarks._box(parent, statics, Vector3(BAR_LENGTH + 6.0, 0.4, 38.0), base + Vector3(0.0, 0.26, 57.0), CONCRETE, true)
	plaza.material_override = PropFactory.pbr("paving", 3.0, Color(0.92, 0.90, 0.86))
	for dx: float in [-1.0, 1.0]:
		var walk := Landmarks._box(parent, statics, Vector3(ANCHOR_WIDTH + 14.0, 0.4, 32.0), base + Vector3(dx * _anchor_offset(), 0.24, 60.0), CONCRETE, true)
		walk.material_override = PropFactory.pbr("sidewalk", 3.0, Color(0.94, 0.93, 0.90))
	if not detailed:
		return
	# Kerb along the plaza edge and a crosswalk out into the lot.
	Landmarks._box(parent, null, Vector3(224.0, 0.3, 0.5), base + Vector3(0.0, 0.35, 76.0), Color(0.88, 0.87, 0.84), false)
	for i in 9:
		Landmarks._box(parent, null, Vector3(0.9, 0.04, 3.6), base + Vector3(-8.0 + i * 2.0, MARK_TOP, 78.0), PAINT_WHITE, false)


## A flat paved slab whose TOP sits at `pos.y`, with the bulk of it buried so undulating ground
## under the pad never shows through.
static func _pave(parent: Node3D, statics: StaticBody3D, size: Vector3, pos: Vector3, mat: Material) -> void:
	var slab := Landmarks._box(parent, statics, size, Vector3(pos.x, pos.y - size.y * 0.5, pos.z), Color(0.5, 0.5, 0.52), true)
	slab.material_override = mat


# --- The retail bar ---------------------------------------------------------------------------

static func _retail_bar(parent: Node3D, statics: StaticBody3D, base: Vector3, batch: MultiMeshBatch, rng: RandomNumberGenerator, detailed: bool) -> void:
	# The blank box. A mall has no windows on the outside; that blankness IS the look.
	var wall := Landmarks._box(parent, statics, Vector3(BAR_LENGTH, BAR_HEIGHT, BAR_DEPTH), base + Vector3(0.0, BAR_HEIGHT * 0.5, 0.0), STUCCO, true)
	wall.material_override = PropFactory.pbr("plaster_beige", 9.0, Color(0.96, 0.92, 0.84))
	# Parapet ring: four thin boxes standing proud of the roof edge.
	var py := BAR_HEIGHT + PARAPET_HEIGHT * 0.5
	Landmarks._box(parent, statics, Vector3(BAR_LENGTH + 1.0, PARAPET_HEIGHT, 1.0), base + Vector3(0.0, py, -BAR_DEPTH * 0.5), STUCCO_DARK, false)
	Landmarks._box(parent, statics, Vector3(BAR_LENGTH + 1.0, PARAPET_HEIGHT, 1.0), base + Vector3(0.0, py, BAR_DEPTH * 0.5), STUCCO_DARK, false)
	Landmarks._box(parent, statics, Vector3(1.0, PARAPET_HEIGHT, BAR_DEPTH + 1.0), base + Vector3(-BAR_LENGTH * 0.5, py, 0.0), STUCCO_DARK, false)
	Landmarks._box(parent, statics, Vector3(1.0, PARAPET_HEIGHT, BAR_DEPTH + 1.0), base + Vector3(BAR_LENGTH * 0.5, py, 0.0), STUCCO_DARK, false)
	_vault(parent, base, detailed)
	if not detailed:
		return

	# Horizontal reveal bands and a split-face base course, so 132 m of blank wall has a scale.
	for dz: float in [-1.0, 1.0]:
		var z := dz * (BAR_DEPTH * 0.5 + 0.12)
		Landmarks._box(parent, null, Vector3(BAR_LENGTH, 2.2, 0.3), base + Vector3(0.0, 1.1, z), STUCCO_DARK, false)
		Landmarks._box(parent, null, Vector3(BAR_LENGTH, 0.5, 0.35), base + Vector3(0.0, 9.4, z), Color(0.66, 0.60, 0.50), false)
	for dx: float in [-1.0, 1.0]:
		var x := dx * (BAR_LENGTH * 0.5 + 0.12)
		Landmarks._box(parent, null, Vector3(0.3, 2.2, BAR_DEPTH), base + Vector3(x, 1.1, 0.0), STUCCO_DARK, false)

	# Secondary mall entrances on the long front wall, either side of the atrium.
	for dx: float in [-1.0, 1.0]:
		var ex := dx * 46.0
		Landmarks._box(parent, statics, Vector3(12.0, 6.0, 1.2), base + Vector3(ex, 3.0, BAR_DEPTH * 0.5 + 0.6), TRIM, false)
		var door := Landmarks._box(parent, null, Vector3(9.0, 4.4, 0.5), base + Vector3(ex, 2.4, BAR_DEPTH * 0.5 + 1.3), GLASS_TINT, false)
		door.material_override = WeaponFX.unshaded(Color(0.45, 0.60, 0.70))
		Landmarks._box(parent, statics, Vector3(15.0, 0.5, 5.0), base + Vector3(ex, 6.4, BAR_DEPTH * 0.5 + 3.0), Color(0.86, 0.85, 0.82), false)
		for cx: float in [-6.0, 6.0]:
			Landmarks._cyl(parent, null, 0.18, 6.2, base + Vector3(ex + cx, 3.1, BAR_DEPTH * 0.5 + 5.2), TRIM)

	# Rooftop plant: the field of HVAC units that makes a mall roof read from the air.
	var unit := PropFactory.box("sbm_hvac", Vector3(3.2, 1.7, 2.4), Color(0.70, 0.71, 0.72))
	var duct := PropFactory.box("sbm_duct", Vector3(1.0, 0.8, 8.0), Color(0.62, 0.63, 0.66))
	for i in 9:
		for j in 4:
			var ux := -58.0 + i * 14.5
			var uz := -30.0 + j * 20.0
			if absf(uz) < VAULT_RADIUS + 4.0:
				continue
			var s := rng.randf_range(0.75, 1.5)
			batch.add("sbm_hvac", unit, Transform3D(Basis(Vector3.UP, rng.randf_range(-0.1, 0.1)).scaled(Vector3(s, 1.0, s)), base + Vector3(ux, BAR_HEIGHT + 0.85, uz)))
	for i in 5:
		batch.add("sbm_duct", duct, Transform3D(Basis(), base + Vector3(-48.0 + i * 24.0, BAR_HEIGHT + 0.4, -26.0)))


## The glazed barrel vault running the length of the concourse. Half of the cylinder is buried in
## the roof; a kerb box hides the joint.
static func _vault(parent: Node3D, base: Vector3, detailed: bool) -> void:
	var kerb := Landmarks._box(parent, null, Vector3(VAULT_LENGTH + 3.0, 1.2, VAULT_RADIUS * 2.0 + 2.2), base + Vector3(0.0, BAR_HEIGHT + 0.6, 0.0), STUCCO_DARK, false)
	kerb.material_override = PropFactory.material(Color(0.60, 0.57, 0.52), 0.8)
	var glass := Landmarks._cyl(parent, null, VAULT_RADIUS, VAULT_LENGTH, base + Vector3(0.0, BAR_HEIGHT + 1.0, 0.0), GLASS_TINT)
	glass.rotation.z = PI * 0.5
	glass.material_override = WeaponFX.unshaded(GLASS_TINT, 0.55)
	if not detailed:
		return
	# Ribs: short boxes stepped round the upper half of the arc.
	var segments := 9
	for r in VAULT_RIBS:
		var rx := -VAULT_LENGTH * 0.5 + 2.0 + r * (VAULT_LENGTH - 4.0) / float(VAULT_RIBS - 1)
		for s in segments:
			var a := -PI * 0.5 + (float(s) + 0.5) * PI / float(segments)
			var chord := PI * VAULT_RADIUS / float(segments) + 0.2
			var rib := Landmarks._box(parent, null, Vector3(0.5, 0.28, chord), base + Vector3(rx, BAR_HEIGHT + 1.0 + cos(a) * (VAULT_RADIUS + 0.2), sin(a) * (VAULT_RADIUS + 0.2)), TRIM, false)
			rib.rotation.x = a


# --- Anchor department stores ------------------------------------------------------------------

## One anchor: a taller blank mass with pilasters, a crown band, a projecting entry canopy and a
## small rooftop penthouse, so it reads as its own store rather than more of the bar.
static func _anchor_store(parent: Node3D, statics: StaticBody3D, base: Vector3, offset_x: float, tone: Color, detailed: bool) -> void:
	var c := base + Vector3(offset_x, 0.0, 0.0)
	var body := Landmarks._box(parent, statics, Vector3(ANCHOR_WIDTH, ANCHOR_HEIGHT, ANCHOR_DEPTH), c + Vector3(0.0, ANCHOR_HEIGHT * 0.5, 0.0), tone, true)
	body.material_override = PropFactory.pbr("concrete_painted", 8.0, tone * 1.18)
	# Crown band and parapet.
	Landmarks._box(parent, statics, Vector3(ANCHOR_WIDTH + 1.4, 2.4, ANCHOR_DEPTH + 1.4), c + Vector3(0.0, ANCHOR_HEIGHT - 1.2, 0.0), tone.darkened(0.35), false)
	Landmarks._box(parent, statics, Vector3(ANCHOR_WIDTH + 1.0, 1.2, ANCHOR_DEPTH + 1.0), c + Vector3(0.0, ANCHOR_HEIGHT + 0.6, 0.0), tone.darkened(0.15), false)
	if not detailed:
		return
	# Pilasters down both long walls.
	for i in ANCHOR_PILASTERS:
		var pz := -ANCHOR_DEPTH * 0.5 + 6.0 + i * (ANCHOR_DEPTH - 12.0) / float(ANCHOR_PILASTERS - 1)
		for dx: float in [-1.0, 1.0]:
			Landmarks._box(parent, null, Vector3(0.7, ANCHOR_HEIGHT - 3.0, 2.2), c + Vector3(dx * (ANCHOR_WIDTH * 0.5 + 0.3), (ANCHOR_HEIGHT - 3.0) * 0.5, pz), tone.darkened(0.22), false)
	# Base course all round.
	for dx: float in [-1.0, 1.0]:
		Landmarks._box(parent, null, Vector3(0.4, 2.0, ANCHOR_DEPTH), c + Vector3(dx * (ANCHOR_WIDTH * 0.5 + 0.2), 1.0, 0.0), STUCCO_DARK, false)
	Landmarks._box(parent, null, Vector3(ANCHOR_WIDTH, 2.0, 0.4), c + Vector3(0.0, 1.0, ANCHOR_DEPTH * 0.5 + 0.2), STUCCO_DARK, false)
	# Street entrance on the lot side, with a deep canopy on round columns.
	var fz := ANCHOR_DEPTH * 0.5
	var glass := Landmarks._box(parent, null, Vector3(16.0, 6.5, 0.6), c + Vector3(0.0, 3.4, fz + 0.4), GLASS_TINT, false)
	glass.material_override = WeaponFX.unshaded(Color(0.42, 0.56, 0.66))
	Landmarks._box(parent, statics, Vector3(22.0, 0.6, 7.0), c + Vector3(0.0, 7.2, fz + 3.0), Color(0.88, 0.87, 0.84), false)
	# Props at the ends only: a column in the middle of a shop doorway is the giveaway that nobody
	# stood in front of this thing.
	for cx: float in [-9.0, 9.0]:
		Landmarks._cyl(parent, null, 0.28, 7.0, c + Vector3(cx, 3.5, fz + 5.8), Color(0.55, 0.55, 0.58))
	# House mark high on the blank wall over the entrance. A department store is the one part of a
	# mall that signs itself to the car park, and forty metres of bare stucco is what makes an
	# anchor read as a warehouse instead. Abstract on purpose: a shape, not anybody's logo.
	var mark := tone.darkened(0.55)
	var ring := Landmarks._cyl(parent, null, 2.6, 0.4, c + Vector3(0.0, ANCHOR_HEIGHT - 5.5, fz + 0.2), mark)
	ring.rotation.x = PI * 0.5
	var eye := Landmarks._cyl(parent, null, 1.3, 0.4, c + Vector3(0.0, ANCHOR_HEIGHT - 5.5, fz + 0.45), tone.lightened(0.35))
	eye.rotation.x = PI * 0.5
	Landmarks._box(parent, null, Vector3(15.0, 0.55, 0.35), c + Vector3(0.0, ANCHOR_HEIGHT - 9.4, fz + 0.2), mark, false)
	# Rooftop penthouse and a stair bulkhead.
	Landmarks._box(parent, statics, Vector3(12.0, 3.4, 10.0), c + Vector3(0.0, ANCHOR_HEIGHT + 1.7, -12.0), Color(0.68, 0.68, 0.67), false)
	Landmarks._box(parent, statics, Vector3(5.0, 2.6, 5.0), c + Vector3(0.0, ANCHOR_HEIGHT + 1.3, 22.0), Color(0.66, 0.66, 0.65), false)


# --- Entrance pavilion, atrium skylight and the sign band ----------------------------------------

static func _entrance(parent: Node3D, statics: StaticBody3D, base: Vector3, detailed: bool) -> void:
	var front := BAR_DEPTH * 0.5 + ENTRY_PROJECTION * 0.5
	var face := BAR_DEPTH * 0.5 + ENTRY_PROJECTION
	# The glazed box itself, using the building shader so it gets real curtain-wall glazing.
	Landmarks._facade_box(parent, statics, Vector3(ENTRY_WIDTH, ENTRY_HEIGHT, ENTRY_PROJECTION),
		base + Vector3(0.0, ENTRY_HEIGHT * 0.5, front), Color(0.52, 0.62, 0.70),
		Building.Finish.GLASS, Building.WindowStyle.CURTAIN, 0.0)
	# Pyramid skylight over the atrium. _cone is a four-sided cone, i.e. a pyramid.
	Landmarks._cone(parent, PYRAMID_RADIUS, PYRAMID_HEIGHT, base + Vector3(0.0, ENTRY_HEIGHT + PYRAMID_HEIGHT * 0.5, front), GLASS_TINT)
	var lantern := Landmarks._box(parent, null, Vector3(1.6, 1.4, 1.6), base + Vector3(0.0, ENTRY_HEIGHT + PYRAMID_HEIGHT + 0.5, front), Color(1.0, 0.94, 0.78), false)
	lantern.material_override = WeaponFX.unshaded(Color(1.0, 0.92, 0.72))
	# Sign band across the fascia: a solid band with the mall's name standing off it.
	var band := Landmarks._box(parent, statics, Vector3(30.0, 3.4, 1.0), base + Vector3(0.0, ENTRY_HEIGHT - 3.0, face + 0.5), Color(0.30, 0.33, 0.38), false)
	band.material_override = PropFactory.material(Color(0.26, 0.29, 0.34), 0.5)
	if not detailed:
		return
	# The name. The far copy gets the dark band on its own: nobody reads 2.4 m letters from two
	# kilometres away, and the glyph outlines are not cheap.
	_letters(parent, base + Vector3(0.0, ENTRY_HEIGHT - 3.0, face + 1.1), SIGN_LETTER_HEIGHT, 0.0)
	# Mullions across the glazed face, a brow canopy and the doors underneath.
	for i in 11:
		Landmarks._box(parent, null, Vector3(0.35, ENTRY_HEIGHT - 1.0, 0.35), base + Vector3(-20.0 + i * 4.0, (ENTRY_HEIGHT - 1.0) * 0.5, face + 0.25), Color(0.80, 0.80, 0.82), false)
	Landmarks._box(parent, null, Vector3(ENTRY_WIDTH + 2.0, 0.5, 1.4), base + Vector3(0.0, ENTRY_HEIGHT - 5.4, face + 0.7), Color(0.86, 0.85, 0.82), false)
	Landmarks._box(parent, statics, Vector3(30.0, 0.7, 8.0), base + Vector3(0.0, 6.6, face + 4.0), Color(0.88, 0.87, 0.84), false)
	# Again, nothing planted in front of the main doors.
	for cx: float in [-13.0, 13.0]:
		Landmarks._cyl(parent, null, 0.3, 6.4, base + Vector3(cx, 3.5, face + 7.4), Color(0.55, 0.55, 0.58))
	var doors := Landmarks._box(parent, null, Vector3(24.0, 4.6, 0.5), base + Vector3(0.0, 2.6, face + 0.35), GLASS_TINT, false)
	doors.material_override = WeaponFX.unshaded(Color(0.48, 0.62, 0.72))
	# Bollards and benches on the plaza.
	for i in 13:
		Landmarks._cyl(parent, null, 0.16, 1.0, base + Vector3(-24.0 + i * 4.0, 0.95, face + 8.6), Color(0.35, 0.36, 0.38))


## The mall's name as extruded letters. Always cut at SIGN_DRAW_DISTANCE, and always built from
## the SIGN_LETTER_HEIGHT mesh scaled to size, so PropFactory caches one TextMesh for all three
## copies instead of one per size.
static func _letters(parent: Node3D, at: Vector3, height: float, yaw: float) -> void:
	var node := MeshInstance3D.new()
	node.mesh = PropFactory.text_mesh("SOUTH BAY MALL", SIGN_LETTER_HEIGHT)
	node.material_override = PropFactory.material(Color(1.0, 0.93, 0.74), 0.4, true)
	node.position = at
	node.rotation.y = yaw
	node.scale = Vector3.ONE * (height / SIGN_LETTER_HEIGHT)
	node.visibility_range_end = SIGN_DRAW_DISTANCE
	node.visibility_range_end_margin = SIGN_DRAW_DISTANCE * 0.15
	node.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	parent.add_child(node)


## A pylon sign out at the lot entrance, the way every mall announces itself from the road.
static func _pylon_sign(parent: Node3D, statics: StaticBody3D, base: Vector3) -> void:
	# Past the last stall row, in the gap before the frontage palms: a pylon standing in the
	# middle of six painted bays is the sort of thing you only notice once and never unsee.
	var at := base + Vector3(0.0, 0.0, SITE_FRONT - 12.0)
	Landmarks._box(parent, statics, Vector3(7.0, 1.0, 3.0), at + Vector3(0.0, 0.5, 0.0), CONCRETE, true)
	Landmarks._box(parent, statics, Vector3(2.6, 11.0, 1.4), at + Vector3(0.0, 6.5, 0.0), Color(0.34, 0.35, 0.38), true)
	var panel := Landmarks._box(parent, statics, Vector3(10.0, 4.6, 1.8), at + Vector3(0.0, 13.6, 0.0), Color(0.22, 0.25, 0.30), false)
	panel.material_override = PropFactory.material(Color(0.20, 0.23, 0.28), 0.5)
	for dz: float in [-1.0, 1.0]:
		_letters(parent, at + Vector3(0.0, 13.6, dz * 1.0), 1.0, 0.0 if dz > 0.0 else PI)


# --- Parking structure ----------------------------------------------------------------------------

## Z of the slab edge where ramp `index` lands, in metres from the deck centre. `run` is half the
## ramp's footprint along Z. Ramps alternate north and south, so each slab is cut away on the side
## the ramp below it climbs from, and the landing overlaps the ramp's top end by 40 cm.
static func _ramp_landing_z(index: int, run: float) -> float:
	return (-RAMP_OFFSET + run - 0.4) if index % 2 == 0 else (RAMP_OFFSET - run + 0.4)


## Five open decks on a column grid, with spandrel edges, internal ramps and a stair core.
## Only the ground-floor columns get collision: the full grid would be hundreds of shapes.
static func _parking_deck(parent: Node3D, statics: StaticBody3D, base: Vector3, batch: MultiMeshBatch, detailed: bool) -> void:
	var cx := -(_anchor_offset() + ANCHOR_WIDTH * 0.5 + DECK_GAP + DECK_WIDTH * 0.5)
	var c := base + Vector3(cx, 0.0, 0.0)
	var slab_colour := Color(0.74, 0.73, 0.71)
	var concrete := PropFactory.pbr("concrete", 6.0, Color(0.92, 0.91, 0.89))
	var pitch := atan(DECK_FLOOR / RAMP_LENGTH)
	var run := RAMP_LENGTH * 0.5 * cos(pitch)
	for level in DECK_LEVELS + 1:
		var y := level * DECK_FLOOR
		if level == 0:
			var ground := Landmarks._box(parent, statics, Vector3(DECK_WIDTH, 0.4, DECK_DEPTH), c + Vector3(0.0, y + 0.2, 0.0), slab_colour, true)
			ground.material_override = concrete
			continue
		# Every elevated slab is cut away over the ramp bay: a solid floor plate would put three
		# hundred square metres of concrete across the top of the ramp below it. What is left is
		# the main plate plus the landing strip at the end the ramp climbs to.
		var slab := Landmarks._box(parent, statics, Vector3(DECK_WIDTH - RAMP_BAY_X, 0.4, DECK_DEPTH), c + Vector3(-RAMP_BAY_X * 0.5, y + 0.2, 0.0), slab_colour, true)
		slab.material_override = concrete
		var land := _ramp_landing_z(level - 1, run)
		var near := (level - 1) % 2 == 0
		var lz0 := land if near else -DECK_DEPTH * 0.5
		var lz1 := DECK_DEPTH * 0.5 if near else land
		var landing := Landmarks._box(parent, statics, Vector3(RAMP_BAY_X, 0.4, lz1 - lz0), c + Vector3(DECK_WIDTH * 0.5 - RAMP_BAY_X * 0.5, y + 0.2, (lz0 + lz1) * 0.5), slab_colour, true)
		landing.material_override = concrete
		# Spandrel band round the open edge of each deck. Collidable: now that the ramps go
		# somewhere, a car gets up here, and 1.1 m of upstand is what keeps it on the deck.
		for dz: float in [-1.0, 1.0]:
			Landmarks._box(parent, statics, Vector3(DECK_WIDTH + 0.8, 1.1, 0.6), c + Vector3(0.0, y + 0.95, dz * DECK_DEPTH * 0.5), Color(0.68, 0.67, 0.65), true)
		for dx: float in [-1.0, 1.0]:
			Landmarks._box(parent, statics, Vector3(0.6, 1.1, DECK_DEPTH + 0.8), c + Vector3(dx * DECK_WIDTH * 0.5, y + 0.95, 0.0), Color(0.68, 0.67, 0.65), true)
	# Stair and lift core at the north-west corner, standing above the top deck.
	var core_h := DECK_LEVELS * DECK_FLOOR + 4.5
	var core := Landmarks._box(parent, statics, Vector3(9.0, core_h, 9.0), c + Vector3(-DECK_WIDTH * 0.5 + 4.5, core_h * 0.5, -DECK_DEPTH * 0.5 + 4.5), Color(0.70, 0.69, 0.67), true)
	core.material_override = concrete
	Landmarks._box(parent, statics, Vector3(10.4, 0.6, 10.4), c + Vector3(-DECK_WIDTH * 0.5 + 4.5, core_h + 0.3, -DECK_DEPTH * 0.5 + 4.5), TRIM, false)
	if not detailed:
		return

	# Column grid. Batched: one box mesh, a few hundred instances, one draw call.
	var column := PropFactory.box("sbm_deck_column", Vector3(0.75, DECK_FLOOR, 0.75), Color(0.66, 0.65, 0.63))
	var nx := int(floor((DECK_WIDTH - 6.0) / DECK_COLUMN_STEP)) + 1
	var nz := int(floor((DECK_DEPTH - 6.0) / DECK_COLUMN_STEP)) + 1
	for level in DECK_LEVELS:
		for i in nx:
			for j in nz:
				var px := -(nx - 1) * DECK_COLUMN_STEP * 0.5 + i * DECK_COLUMN_STEP
				# Nothing stands in the ramp bay: that strip is cut out of every slab above it.
				if px > DECK_WIDTH * 0.5 - RAMP_BAY_X:
					continue
				var pz := -(nz - 1) * DECK_COLUMN_STEP * 0.5 + j * DECK_COLUMN_STEP
				var at := c + Vector3(px, level * DECK_FLOOR + DECK_FLOOR * 0.5 + 0.2, pz)
				batch.add("sbm_deck_column", column, Transform3D(Basis(), at))
				if level == 0 and statics:
					Landmarks._shape(statics, Vector3(0.75, DECK_FLOOR, 0.75), at)
	# Ramps in the east bay, one per level change: tilted slabs you really can drive, because the
	# slab above each one is cut away over the bay and the run comes out onto the landing strip.
	for level in DECK_LEVELS:
		var rz := (-1.0 if level % 2 == 0 else 1.0) * RAMP_OFFSET
		var dir := 1.0 if level % 2 == 0 else -1.0
		# The ramp's TOP surface has to meet the slab tops, not its centre line: hence half the
		# ramp thickness taken off the 0.4 that lifts a slab's top above its level.
		var at := c + Vector3(DECK_WIDTH * 0.5 - RAMP_BAY_X * 0.5 - 1.0, level * DECK_FLOOR + DECK_FLOOR * 0.5 + 0.225, rz)
		var ramp := Landmarks._box(parent, null, Vector3(RAMP_WIDTH, 0.35, RAMP_LENGTH), at, slab_colour, false)
		ramp.rotation.x = -pitch * dir
		ramp.material_override = concrete
		if statics:
			var shape := CollisionShape3D.new()
			var box := BoxShape3D.new()
			box.size = Vector3(RAMP_WIDTH, 0.35, RAMP_LENGTH)
			shape.shape = box
			shape.position = at
			shape.rotation.x = -pitch * dir
			statics.add_child(shape)
	# Light poles and a couple of palms on the top deck, plus signage on the entry face.
	for i in 4:
		_light_pole(batch, c + Vector3(-18.0 + i * 12.0, DECK_LEVELS * DECK_FLOOR + 0.4, 0.0), 0.0, 5.5)
	var entry_sign := Landmarks._box(parent, null, Vector3(6.0, 1.6, 0.4), c + Vector3(DECK_WIDTH * 0.5 + 0.3, 4.2, DECK_DEPTH * 0.5 - 8.0), Color(0.90, 0.30, 0.20), false)
	entry_sign.material_override = WeaponFX.unshaded(Color(0.95, 0.35, 0.22))


# --- Service yard ----------------------------------------------------------------------------------

## The back of house: a sunken dock apron, roller doors, a dock canopy, trailers and bins.
static func _service_yard(parent: Node3D, statics: StaticBody3D, base: Vector3, rng: RandomNumberGenerator) -> void:
	var z := -BAR_DEPTH * 0.5
	Landmarks._box(parent, statics, Vector3(80.0, 1.4, 3.0), base + Vector3(0.0, 0.7, z - 1.5), CONCRETE, true)
	for i in 6:
		var dx := -35.0 + i * 14.0
		Landmarks._box(parent, null, Vector3(4.2, 4.6, 0.4), base + Vector3(dx, 2.3, z - 0.1), Color(0.38, 0.39, 0.42), false)
		Landmarks._box(parent, null, Vector3(4.8, 0.4, 1.6), base + Vector3(dx, 4.8, z - 0.8), Color(0.55, 0.56, 0.58), false)
	Landmarks._box(parent, statics, Vector3(84.0, 0.6, 8.0), base + Vector3(0.0, 7.2, z - 4.0), Color(0.62, 0.63, 0.65), false)
	for i in 5:
		Landmarks._cyl(parent, null, 0.22, 7.0, base + Vector3(-40.0 + i * 20.0, 3.5, z - 7.6), TRIM)
	# Trailers backed onto the dock, and the bin corral.
	for i in 3:
		var tx := -30.0 + i * 24.0 + rng.randf_range(-2.0, 2.0)
		Landmarks._box(parent, statics, Vector3(3.0, 3.4, 14.5), base + Vector3(tx, 3.1, z - 10.0), Color(0.90, 0.90, 0.88), true)
		Landmarks._box(parent, statics, Vector3(2.6, 1.6, 4.0), base + Vector3(tx, 1.9, z - 19.0), Color(0.30, 0.34, 0.44), true)
		var bogie := Landmarks._cyl(parent, null, 0.5, 2.6, base + Vector3(tx, 0.5, z - 12.0), TRIM)
		bogie.rotation.z = PI * 0.5
	for i in 4:
		Landmarks._box(parent, statics, Vector3(2.4, 1.8, 1.6), base + Vector3(44.0 + i * 3.2, 0.9, z - 6.0), Color(0.24, 0.42, 0.30), true)


# --- Surface car park: painted bays, islands, palms, light poles ---------------------------------

## Painted stall lines. Every line is one instance of a single box mesh, so the whole lot costs
## one draw call; the triangle count is LOT_ROWS * 2 * (2 * LOT_HALF_X / BAY_WIDTH) * 12.
static func _lot_markings(parent: Node3D, base: Vector3, batch: MultiMeshBatch) -> void:
	var line := PropFactory.box("sbm_bay_line", Vector3(0.14, 0.04, BAY_DEPTH), PAINT_WHITE)
	var accessible := PropFactory.box("sbm_bay_accessible", Vector3(2.4, 0.04, BAY_DEPTH), Color(0.20, 0.36, 0.70))
	var count := int(LOT_HALF_X * 2.0 / BAY_WIDTH)
	for row in LOT_ROWS:
		var z0 := LOT_START_Z + row * LOT_ROW_PITCH
		for band in 2:
			var bz := z0 + BAY_DEPTH * 0.5 if band == 0 else z0 + LOT_ROW_PITCH - BAY_DEPTH * 0.5
			for i in count + 1:
				var x := -LOT_HALF_X + i * BAY_WIDTH
				if _island_at(x):
					continue
				batch.add("sbm_bay_line", line, Transform3D(Basis(), base + Vector3(x, MARK_TOP, bz)))
			# Kerb line at the head of the band, the strip the cars nose up to.
			Landmarks._box(parent, null, Vector3(LOT_HALF_X * 2.0, 0.04, 0.14), base + Vector3(0.0, MARK_TOP, z0 + (0.4 if band == 0 else LOT_ROW_PITCH - 0.4)), PAINT_WHITE, false)
	# Accessible stalls nearest the entrance, painted blue. They have to land ON the stall grid,
	# not on a pitch of their own, or the blue pads straddle the white lines; and they start two
	# stalls east of centre because the middle island stands in the row right in front of the doors.
	var mid := int(LOT_HALF_X / BAY_WIDTH)
	for i in 6:
		var ax := -LOT_HALF_X + (float(mid + 2 + i) + 0.5) * BAY_WIDTH
		batch.add("sbm_bay_accessible", accessible, Transform3D(Basis(), base + Vector3(ax, MARK_TOP - 0.01, LOT_START_Z + BAY_DEPTH * 0.5)))


## X of planted island `k`, in metres from the mall centre. Five of them across the lot.
static func _island_x(k: int) -> float:
	return -LOT_HALF_X + 6.0 + k * (LOT_HALF_X * 2.0 - 12.0) / 4.0


## True where a planted island interrupts the run of stalls.
static func _island_at(x: float) -> bool:
	for k in 5:
		if absf(x - _island_x(k)) < 3.2:
			return true
	return false


static func _lot_planting(parent: Node3D, statics: StaticBody3D, base: Vector3, batch: MultiMeshBatch, rng: RandomNumberGenerator) -> void:
	# Planted islands inside the lot: a raised kerb, soil, a palm on the near band and a light pole
	# on the far one. ONE planter per stall band, not one across the whole row module: the drive
	# aisle runs up the middle of a module and an island bridging it walls the lot off.
	var band_z := [BAY_DEPTH * 0.5, LOT_ROW_PITCH - BAY_DEPTH * 0.5]
	for row in LOT_ROWS:
		var z0 := LOT_START_Z + row * LOT_ROW_PITCH
		for k in 5:
			for band in 2:
				var at := base + Vector3(_island_x(k), LOT_TOP, z0 + band_z[band])
				var kerb := Landmarks._box(parent, null, Vector3(5.2, 0.34, BAY_DEPTH - 0.4), at + Vector3(0.0, 0.17, 0.0), Color(0.86, 0.85, 0.82), false)
				kerb.material_override = PropFactory.pbr("sidewalk", 2.5, Color(0.94, 0.93, 0.90))
				Landmarks._box(parent, null, Vector3(4.4, 0.24, BAY_DEPTH - 1.4), at + Vector3(0.0, 0.30, 0.0), Color(0.34, 0.30, 0.24), false)
				var shrub_z := 1.3 if band == 0 else -1.3
				Landmarks._box(parent, null, Vector3(1.4, 0.9, 1.2), at + Vector3(0.0, 0.85, shrub_z), Color(0.26, 0.42, 0.24), false)
				if band == 0:
					_palm(batch, at + Vector3(0.0, 0.4, 0.0), rng.randf_range(8.0, 12.5), rng.randf_range(0.0, TAU), rng)
				else:
					# The pole goes on the island too. Standing one in the middle of a drive aisle is
					# the thing that makes a lot read as painted-on rather than built.
					_light_pole(batch, at + Vector3(0.0, 0.4, 0.0), rng.randf_range(0.0, 0.2), LIGHT_POLE_HEIGHT)
				if statics:
					# One shape per planter so a car clips the kerb; the palms themselves stay soft.
					Landmarks._shape(statics, Vector3(5.2, 0.4, BAY_DEPTH - 0.4), at + Vector3(0.0, 0.2, 0.0))
	# Palms along the ring road frontage and the entrance plaza.
	for i in 14:
		_palm(batch, base + Vector3(-160.0 + i * 24.6, LOT_TOP, SITE_FRONT - 10.0), rng.randf_range(9.0, 14.0), rng.randf_range(0.0, TAU), rng)
	for i in 8:
		_palm(batch, base + Vector3(-52.0 + i * 15.0, 0.4, 74.5), rng.randf_range(10.0, 15.0), rng.randf_range(0.0, TAU), rng)
	# Cart corrals, standing in a stall like the real ones do rather than out in the aisle.
	for i in 4:
		var at := base + Vector3(-72.0 + i * 48.0, LOT_TOP, LOT_START_Z + LOT_ROW_PITCH + BAY_DEPTH * 0.5)
		for dx: float in [-1.4, 1.4]:
			Landmarks._box(parent, null, Vector3(0.12, 1.4, 5.0), at + Vector3(dx, 0.7, 0.0), Color(0.75, 0.76, 0.78), false)
		Landmarks._box(parent, null, Vector3(3.0, 0.12, 0.12), at + Vector3(0.0, 1.35, -2.4), Color(0.75, 0.76, 0.78), false)


## A cheap low-poly palm: a tapered trunk and a ring of box fronds, both batched. About 130
## triangles a tree, against roughly 20k for PropFactory.palm() - a mall lot wants forty of them.
static func _palm(batch: MultiMeshBatch, at: Vector3, height: float, yaw: float, rng: RandomNumberGenerator) -> void:
	var trunk := PropFactory.cylinder("sbm_palm_trunk", PALM_TRUNK_RADIUS, 1.0, Color(0.52, 0.47, 0.39), PALM_TRUNK_RADIUS * 0.6, 7)
	var frond := PropFactory.box("sbm_palm_frond", Vector3(0.5, 0.1, PALM_FROND_LENGTH), Color(0.30, 0.45, 0.24))
	var crown_mesh := PropFactory.box("sbm_palm_crown", Vector3(0.9, 0.8, 0.9), Color(0.34, 0.40, 0.24))
	batch.add("sbm_palm_trunk", trunk, Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(1.0, height, 1.0)), at + Vector3(0.0, height * 0.5, 0.0)))
	var crown := at + Vector3(0.0, height, 0.0)
	batch.add("sbm_palm_crown", crown_mesh, Transform3D(Basis(Vector3.UP, yaw), crown))
	for i in PALM_FRONDS:
		var a := yaw + TAU * float(i) / float(PALM_FRONDS) + rng.randf_range(-0.18, 0.18)
		var droop := rng.randf_range(0.30, 0.75)
		var b := Basis(Vector3.UP, a) * Basis(Vector3.RIGHT, droop)
		batch.add("sbm_palm_frond", frond, Transform3D(b, crown + b * Vector3(0.0, 0.0, PALM_FROND_LENGTH * 0.5)))


## A parking-lot light pole: tapered mast, two arms, two emissive heads. All batched.
static func _light_pole(batch: MultiMeshBatch, at: Vector3, yaw: float, height: float) -> void:
	var mast := PropFactory.cylinder("sbm_light_mast", 0.17, 1.0, Color(0.24, 0.25, 0.28), 0.11, 8)
	var foot := PropFactory.box("sbm_light_foot", Vector3(0.9, 0.7, 0.9), Color(0.70, 0.70, 0.68))
	var arm := PropFactory.box("sbm_light_arm", Vector3(2.0, 0.16, 0.16), Color(0.24, 0.25, 0.28))
	batch.add("sbm_light_foot", foot, Transform3D(Basis(Vector3.UP, yaw), at + Vector3(0.0, 0.35, 0.0)))
	batch.add("sbm_light_mast", mast, Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(1.0, height, 1.0)), at + Vector3(0.0, height * 0.5 + 0.6, 0.0)))
	for dx: float in [-1.0, 1.0]:
		var side := Basis(Vector3.UP, yaw) * Vector3(dx, 0.0, 0.0)
		batch.add("sbm_light_arm", arm, Transform3D(Basis(Vector3.UP, yaw), at + side * 1.0 + Vector3(0.0, height + 0.6, 0.0)))
		batch.add("sbm_light_head", PropFactory.lamp_head(), Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(2.2, 1.6, 2.2)), at + side * 2.0 + Vector3(0.0, height + 0.5, 0.0)))
