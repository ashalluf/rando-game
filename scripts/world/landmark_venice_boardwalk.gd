class_name LandmarkVeniceBoardwalk
extends RefCounted
## VENICE BOARDWALK - Ocean Front Walk, the 400 m promenade behind the sand at Venice.
##
## One entry point:
##
##   build(anchor, parent, statics, plan, detailed)
##
## This is a LINEAR landmark, not a building: it runs 400 m along +-Z and is thin in X. The
## ocean is at -X everywhere on this map (MacroMap.zone_at() calls anything west of coast_x()
## water), so the layout reads, from the sea inland:
##
##   x -48 .. -22   sand: the skate park, two basketball courts, the outdoor weights area
##   x -24.5        the graffiti art wall, painted panels facing the walk
##   x -19, -7.8    the double row of tall palms, staggered half a spacing between the rows
##   x -14.6 .. -10 the vendor stalls under bright canvas, facing the walk
##   x  -5.5 .. 5.5 the walk itself: pale concrete panels with a dark inlaid diamond pattern
##   x   7 .. 23    the beachfront strip: one and two storey shops, shutters, murals, signs
##
## So the anchor wants roughly 49 m of sand on its ocean side and 24 m of buildable land on its
## inland side. Nudge the whole thing across the sand with WALK_SHIFT_X rather than by moving
## the anchor, so the shore-side facilities stay on sand.
##
## THE HOLE PROBLEM: this landmark is additive geometry laid on top of streamed terrain, and
## nothing here can cut a hole in the sand. A bowl dug 3.4 m down would simply be full of
## terrain. So the skate park is a raised concrete plateau (PARK_DECK_H above the sand) with the
## bowl and the snake run cut down through it to sand level, reached by a berm ramp. From the
## walk it reads exactly like a sunken bowl, and the player can drop in and climb out.
##
## Muscle Beach and the bowl are where the triangles went, as asked.
##
## Triangles, measured by walking the built tree at two anchors: 37,800 - 38,900 detailed
## (about 880 nodes and 220 collision shapes) and about 2,700 far (40 nodes, no collision). The big line items detailed are the palms
## (three MultiMeshes), the weights area, the shop strip, the bowl and snake run, the walk and
## its inlay, the stalls and the two courts. PALM_FRONDS, PALM_SPACING, BOWL_SEGMENTS and
## COURT_ARC_SEGMENTS are the dials that move it most.
##
## Names: Venice is geography, which is fine. Every business here is invented - the shop signs
## are abstract colour blocks with no letters at all, the art wall reads ONWARD and the weights
## area's arch reads RANDO, which is this project's own in-world name. No real trade dress, no
## copy of any real building.

# --- Site ----------------------------------------------------------------------------------

## Seed salt, so the same anchor always produces the same boardwalk.
const SEED_SALT := 5210923
## Length of the promenade along Z, in metres.
const LENGTH := 400.0
## Sideways shift of the whole landmark across the beach, in metres (+ is inland).
const WALK_SHIFT_X := 0.0
## Width of the concrete walk, in metres.
const PATH_WIDTH := 11.0
## Length of one paving panel of the walk along Z, in metres.
const PANEL_LEN := 8.0
## Thickness of the walk slab, in metres.
const PATH_SLAB_T := 0.45
## Height of the walk surface above the sand, in metres.
const PATH_TOP := 0.22
## Width of the darker kerb band down each side of the walk, in metres.
const KERB_W := 0.55
## Side of one inlaid diamond in the paving pattern, in metres.
const INLAY_SIZE := 1.8
## Number of long collision boxes the walk slab is covered by (one per LENGTH/this metres).
const PATH_SHAPES := 8

# --- Beachfront shop strip -------------------------------------------------------------------

## Local X of the shop fronts, in metres (the face that looks at the walk).
const SHOP_FRONT_X := 7.0
## Depth of the shop strip inland, in metres.
const SHOP_DEPTH := 16.0
## First and last Z the strip covers, in metres.
const SHOP_Z_FROM := -192.0
const SHOP_Z_TO := 192.0
## Narrowest and widest shop frontage, in metres.
const SHOP_MIN_W := 13.0
const SHOP_MAX_W := 29.0
## Gap between neighbouring shops, in metres.
const SHOP_GAP := 1.1
## Height of one storey, in metres.
const STOREY_H := 4.3
## Chance a shop is two storeys rather than one.
const TWO_STOREY_CHANCE := 0.55
## Height of the roll-up shutter over a shopfront, in metres.
const SHUTTER_H := 3.1
## Depth the awning reaches out over the walk, in metres.
const AWNING_REACH := 2.4

# --- Palms -----------------------------------------------------------------------------------

## Local X of the two palm rows, in metres.
const PALM_ROW_X: Array = [-7.8, -19.0]
## Distance between palms along a row, in metres (the rows are staggered by half of this).
const PALM_SPACING := 15.0
## Shortest and tallest palm, in metres.
const PALM_MIN_H := 12.0
const PALM_MAX_H := 19.5
## Fronds on one palm, detailed and far. Each frond is a box, so this is the palm's cost.
const PALM_FRONDS := 9
const PALM_FRONDS_FAR := 4
## Length of one frond, in metres.
const PALM_FROND_LEN := 3.2
## Trunk radius at the foot, in metres.
const PALM_TRUNK_R := 0.34

# --- Vendor stalls -----------------------------------------------------------------------------

## Local X of the stall line, in metres.
const STALL_X := -12.5
## Stall table: depth across the walk and width along it, in metres.
const STALL_D := 3.2
const STALL_W := 3.0
## Distance between stalls along Z, in metres.
const STALL_SPACING := 4.6
## First and last Z of the stall run, in metres.
const STALL_Z_FROM := -108.0
const STALL_Z_TO := 128.0
## Height of the canvas canopy above the sand, in metres.
const CANOPY_H := 2.7

# --- Skate park ---------------------------------------------------------------------------------

## Centre of the skate park in local coordinates, in metres.
const SKATE_X := -33.0
const SKATE_Z := -140.0
## Size of the concrete plateau: across the beach, then along it, in metres.
const SKATE_W := 30.0
const SKATE_L := 44.0
## Height of the plateau deck above the sand, in metres. This is also the bowl's depth.
const PARK_DECK_H := 3.2
## Rim radius of the bowl, in metres.
const BOWL_R := 9.0
## Radius of the bowl's flat floor, in metres.
const BOWL_FLOOR_R := 6.4
## Radius where the steep wall turns into the bottom transition, in metres.
const BOWL_KNEE_R := 8.2
## Height of the knee above the bowl floor, in metres.
const BOWL_KNEE_Y := 1.0
## Panels around the bowl. Two rows of this many boxes, so 24 tris each: the main bowl cost.
const BOWL_SEGMENTS := 16
## Thickness of a bowl wall panel, in metres.
const BOWL_PANEL_T := 0.45
## Length of the snake run along Z, in metres, and how many straight pieces it is cut into.
const SNAKE_LEN := 27.0
const SNAKE_SEGMENTS := 9
## Width of the snake run channel floor, in metres.
const SNAKE_W := 4.4
## How far the snake run weaves across the park, in metres.
const SNAKE_AMP := 2.6
## Depth of the snake run below the deck, in metres.
const SNAKE_DEPTH := 2.0

# --- Basketball ---------------------------------------------------------------------------------

## Centre X of both courts in local coordinates, in metres.
const COURT_X := -33.0
## Centre Z of each court, in metres.
const COURT_Z: Array = [-84.0, -50.0]
## Court slab: width across the beach, length along it, in metres.
const COURT_W := 15.2
const COURT_L := 28.0
## Width of a painted line, in metres.
const LINE_W := 0.12
## Segments in a painted arc (centre circle, keys, three point line).
const COURT_ARC_SEGMENTS := 11
## Height of the rim above the court, in metres.
const HOOP_H := 3.05

# --- Weights area (Muscle Beach) ------------------------------------------------------------------

## Centre of the weights area in local coordinates, in metres.
const GYM_X := -35.0
const GYM_Z := 28.0
## Size of the fenced pad: across the beach, then along it, in metres.
const GYM_W := 26.0
const GYM_L := 30.0
## Height of the pad above the sand, in metres.
const GYM_PAD_H := 0.3
## Radius of a steel bar, in metres.
const BAR_R := 0.055
## Height of the pull-up frame's top bar above the pad, in metres.
const RIG_H := 2.5
## Height of the arch over the entrance, in metres.
const ARCH_H := 4.6

# --- Art wall and furniture -------------------------------------------------------------------

## Local X of the painted wall, in metres (it faces the walk, at +X).
const WALL_X := -24.5
## First and last Z of the wall run, in metres.
const WALL_Z_FROM := 92.0
const WALL_Z_TO := 168.0
## Height, thickness and panel width of the art wall, in metres.
const WALL_H := 4.6
const WALL_T := 0.5
const WALL_PANEL := 5.4
## Distance between benches, bins and lamp posts along the walk, in metres.
const BENCH_SPACING := 26.0
const BIN_SPACING := 33.0
const LAMP_SPACING := 30.0
## Height of a lamp post above the walk, in metres.
const LAMP_H := 5.2
## Z positions of the outdoor showers, in metres.
const SHOWER_Z: Array = [-64.0, -14.0, 122.0]
## Height of a shower head above the sand, in metres.
const SHOWER_H := 2.6

# --- Colours ------------------------------------------------------------------------------------

const CONCRETE_PALE := Color(0.84, 0.82, 0.77)
const CONCRETE_GREY := Color(0.62, 0.61, 0.58)
const CONCRETE_DARK := Color(0.45, 0.44, 0.42)
const SAND_PAD := Color(0.80, 0.72, 0.55)
const STEEL := Color(0.56, 0.58, 0.60)
const SHUTTER_GREY := Color(0.52, 0.54, 0.55)
const PALM_TRUNK_C := Color(0.54, 0.47, 0.37)
const PALM_FROND_C := Color(0.27, 0.46, 0.24)
const PALM_CROWN_C := Color(0.33, 0.40, 0.23)
const COURT_BLUE := Color(0.20, 0.32, 0.42)
const RUBBER_BLACK := Color(0.11, 0.11, 0.12)
## Bright canvas for the stall canopies, picked per stall.
const CANVAS: Array = [
	Color(0.90, 0.24, 0.22), Color(0.96, 0.66, 0.16), Color(0.18, 0.55, 0.78),
	Color(0.20, 0.64, 0.42), Color(0.92, 0.88, 0.28), Color(0.76, 0.28, 0.62),
]
## Paint for murals, signs and the art wall, picked per panel.
const PAINT: Array = [
	Color(0.94, 0.30, 0.26), Color(0.99, 0.72, 0.15), Color(0.16, 0.62, 0.86),
	Color(0.22, 0.74, 0.48), Color(0.68, 0.30, 0.82), Color(0.99, 0.44, 0.62),
	Color(0.10, 0.12, 0.16), Color(0.98, 0.96, 0.92),
]
## Painted stucco for the shop facades.
const FACADE: Array = [
	Color(0.93, 0.90, 0.84), Color(0.88, 0.84, 0.76), Color(0.82, 0.86, 0.86),
	Color(0.94, 0.82, 0.66), Color(0.78, 0.82, 0.74), Color(0.90, 0.88, 0.90),
]


## Builds the boardwalk. `statics` may be null (the far copy has no collision at all), and
## `detailed` false means the silhouette only: the walk slab, the palm row and the shop strip.
static func build(anchor: Vector2, parent: Node3D, statics: StaticBody3D, plan: CityPlan, detailed: bool) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = _salt(anchor, 1)
	var batch := MultiMeshBatch.new()
	if not detailed:
		_far(anchor, parent, plan, batch)
		batch.build(parent)
		return
	_walk(anchor, parent, statics, plan, batch)
	_palm_rows(anchor, parent, plan, batch, true)
	_shop_strip(anchor, parent, statics, plan, batch, true)
	_stalls(anchor, parent, statics, plan, batch)
	_art_wall(anchor, parent, statics, plan, rng)
	_skate_park(anchor, parent, statics, plan)
	_courts(anchor, parent, statics, plan, batch)
	_muscle_beach(anchor, parent, statics, plan, batch)
	_furniture(anchor, parent, statics, plan, batch)
	batch.build(parent)


## The far copy: one long slab, half the palms with four fronds each, and the shop boxes.
## About 2,600 triangles.
static func _far(anchor: Vector2, parent: Node3D, plan: CityPlan, batch: MultiMeshBatch) -> void:
	var slab := Landmarks._box(parent, null, Vector3(PATH_WIDTH, PATH_SLAB_T, LENGTH), _at(anchor, plan, 0.0, 0.0, PATH_TOP - PATH_SLAB_T * 0.5), CONCRETE_PALE, false)
	slab.material_override = PropFactory.pbr("sidewalk", 6.0, CONCRETE_PALE)
	_palm_rows(anchor, parent, plan, batch, false)
	_shop_strip(anchor, parent, null, plan, batch, false)


# --- The walk ----------------------------------------------------------------------------------

## Pale concrete panels with a dark diamond inlay down the middle and a kerb band each side.
## One MultiMesh per element; collision is PATH_SHAPES long boxes rather than one per panel.
static func _walk(anchor: Vector2, parent: Node3D, statics: StaticBody3D, plan: CityPlan, batch: MultiMeshBatch) -> void:
	var panel := _bmesh(Vector3(PATH_WIDTH - KERB_W * 2.0, PATH_SLAB_T, PANEL_LEN - 0.14), PropFactory.pbr("sidewalk", 5.0, CONCRETE_PALE))
	var kerb := _bmesh(Vector3(KERB_W, PATH_SLAB_T + 0.06, PANEL_LEN - 0.14), PropFactory.pbr("concrete", 4.0, CONCRETE_GREY))
	var inlay := _bmesh(Vector3(INLAY_SIZE, 0.05, INLAY_SIZE), PropFactory.material(CONCRETE_DARK, 0.75))
	var band := _bmesh(Vector3(PATH_WIDTH - KERB_W * 2.0, 0.05, 0.3), PropFactory.material(CONCRETE_GREY, 0.8))
	var count := int(LENGTH / PANEL_LEN)
	var slab_y := PATH_TOP - PATH_SLAB_T * 0.5
	for i in count:
		var z := -LENGTH * 0.5 + (float(i) + 0.5) * PANEL_LEN
		batch.add("vbw_walk", panel, Transform3D(Basis(), _at(anchor, plan, 0.0, z, slab_y)))
		for side: float in [-1.0, 1.0]:
			batch.add("vbw_walk_kerb", kerb, Transform3D(Basis(), _at(anchor, plan, side * (PATH_WIDTH - KERB_W) * 0.5, z, slab_y + 0.03)))
		# Two diamonds per panel, turned 45 degrees, plus a joint band across the panel end.
		for d in 2:
			var dz := z + (float(d) - 0.5) * PANEL_LEN * 0.5
			batch.add("vbw_walk_inlay", inlay, Transform3D(Basis(Vector3.UP, PI * 0.25), _at(anchor, plan, 0.0, dz, PATH_TOP + 0.01)))
		batch.add("vbw_walk_band", band, Transform3D(Basis(), _at(anchor, plan, 0.0, z + PANEL_LEN * 0.5, PATH_TOP + 0.005)))
	if statics != null:
		var span := LENGTH / float(PATH_SHAPES)
		for i in PATH_SHAPES:
			var z := -LENGTH * 0.5 + (float(i) + 0.5) * span
			Landmarks._shape(statics, Vector3(PATH_WIDTH, PATH_SLAB_T, span), _at(anchor, plan, 0.0, z, slab_y))


# --- Palms -------------------------------------------------------------------------------------

## The double row. Both rows walk the same index sequence in the far copy so the two versions
## agree; the far copy just skips every other palm and drops the frond count.
static func _palm_rows(anchor: Vector2, parent: Node3D, plan: CityPlan, batch: MultiMeshBatch, detailed: bool) -> void:
	var fronds := PALM_FRONDS if detailed else PALM_FRONDS_FAR
	var trunk := _cmesh(PALM_TRUNK_R, PALM_TRUNK_R * 0.55, 1.0, 7, PropFactory.material(PALM_TRUNK_C, 0.9))
	var crown := _bmesh(Vector3(1.05, 0.95, 1.05), PropFactory.material(PALM_CROWN_C, 0.9))
	var frond := _bmesh(Vector3(0.55, 0.09, PALM_FROND_LEN), PropFactory.material(PALM_FROND_C, 0.85))
	var count := int(LENGTH / PALM_SPACING)
	for row in PALM_ROW_X.size():
		var rng := RandomNumberGenerator.new()
		rng.seed = _salt(anchor, 17 + row)
		var x: float = PALM_ROW_X[row]
		for i in count:
			var h := rng.randf_range(PALM_MIN_H, PALM_MAX_H)
			var yaw := rng.randf_range(0.0, TAU)
			var lean := rng.randf_range(-0.05, 0.05)
			var jitter := rng.randf_range(-0.8, 0.8)
			if not detailed and i % 2 == 1:
				continue
			var z := -LENGTH * 0.5 + (float(i) + 0.5 + float(row) * 0.5) * PALM_SPACING + jitter
			if absf(z) > LENGTH * 0.5:
				continue
			_palm(batch, _at(anchor, plan, x, z, 0.0), h, yaw, lean, fronds, trunk, crown, frond, rng)


## One palm: a tapered 7-sided trunk, a box crown and a ring of drooping box fronds.
## About 150 triangles detailed, 80 far, and every part is batched.
static func _palm(batch: MultiMeshBatch, at: Vector3, height: float, yaw: float, lean: float, fronds: int, trunk: Mesh, crown: Mesh, frond: Mesh, rng: RandomNumberGenerator) -> void:
	var tilt := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, lean)
	batch.add("vbw_palm_trunk", trunk, Transform3D(tilt * Basis.from_scale(Vector3(1.0, height, 1.0)), at + tilt * Vector3(0.0, height * 0.5, 0.0)))
	var top := at + tilt * Vector3(0.0, height, 0.0)
	batch.add("vbw_palm_crown", crown, Transform3D(tilt, top))
	for i in fronds:
		var a := yaw + TAU * float(i) / float(fronds)
		var droop := rng.randf_range(0.28, 0.66)
		var b := Basis(Vector3.UP, a) * Basis(Vector3.RIGHT, droop)
		batch.add("vbw_palm_frond", frond, Transform3D(b, top + b * Vector3(0.0, 0.0, PALM_FROND_LEN * 0.5)))


# --- Beachfront shop strip ---------------------------------------------------------------------

## The frontages, decided once from the anchor so the far copy and the detailed copy agree.
## Each entry: centre Z, frontage width, storey count and a seed for that shop's own detail.
static func _shop_spans(anchor: Vector2) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = _salt(anchor, 101)
	var spans: Array = []
	var z := SHOP_Z_FROM
	while z < SHOP_Z_TO - SHOP_MIN_W:
		var w: float = minf(rng.randf_range(SHOP_MIN_W, SHOP_MAX_W), SHOP_Z_TO - z)
		var storeys := 2 if rng.randf() < TWO_STOREY_CHANCE else 1
		spans.append({"z": z + w * 0.5, "w": w, "storeys": storeys, "seed": rng.randi()})
		z += w + SHOP_GAP
	return spans


static func _shop_strip(anchor: Vector2, parent: Node3D, statics: StaticBody3D, plan: CityPlan, batch: MultiMeshBatch, detailed: bool) -> void:
	for span: Dictionary in _shop_spans(anchor):
		var storeys: int = span.storeys
		var w: float = span.w
		var centre_z: float = span.z
		var h := float(storeys) * STOREY_H
		var pos := _at(anchor, plan, SHOP_FRONT_X + SHOP_DEPTH * 0.5, centre_z, h * 0.5)
		var rng := RandomNumberGenerator.new()
		rng.seed = int(span.seed)
		var facade: Color = FACADE[rng.randi() % FACADE.size()]
		if not detailed:
			Landmarks._box(parent, null, Vector3(SHOP_DEPTH, h, w), pos, facade, false)
			Landmarks._box(parent, null, Vector3(SHOP_DEPTH + 0.5, 0.6, w + 0.4), pos + Vector3(0.0, h * 0.5 + 0.3, 0.0), facade.darkened(0.25), false)
			continue
		_shop(parent, statics, batch, pos, w, h, storeys, facade, rng)


## One shopfront: painted body, parapet, roll-up shutter, awning, sign board, and a mural on
## the upper wall of about half of them. Roughly 30 boxes, so ~360 triangles a shop.
static func _shop(parent: Node3D, statics: StaticBody3D, batch: MultiMeshBatch, pos: Vector3, w: float, h: float, storeys: int, facade: Color, rng: RandomNumberGenerator) -> void:
	var finish := Building.Finish.FLAT if rng.randf() < 0.7 else Building.Finish.BRICK
	var style := Building.WindowStyle.PUNCHED if storeys > 1 else Building.WindowStyle.RIBBON
	Landmarks._facade_box(parent, statics, Vector3(SHOP_DEPTH, h, w), pos, facade, finish, style, SHUTTER_H)
	# Parapet, so the roofline is not a bare edge.
	Landmarks._box(parent, statics, Vector3(SHOP_DEPTH + 0.5, 0.7, w + 0.4), pos + Vector3(0.0, h * 0.5 + 0.35, 0.0), facade.darkened(0.3), false)
	var front := pos.x - SHOP_DEPTH * 0.5
	var foot := pos.y - h * 0.5
	# Roll-up shutter, open on some units, with its ribs batched.
	var open := rng.randf() < 0.45
	var shutter_w := w * rng.randf_range(0.6, 0.82)
	var shutter_h := SHUTTER_H if not open else SHUTTER_H * 0.35
	var shutter_y := foot + (SHUTTER_H - shutter_h * 0.5) if open else foot + shutter_h * 0.5
	Landmarks._box(parent, null, Vector3(0.16, shutter_h, shutter_w), Vector3(front - 0.09, shutter_y, pos.z), SHUTTER_GREY, false)
	var rib := _bmesh(Vector3(0.05, 0.1, shutter_w - 0.1), PropFactory.material(SHUTTER_GREY.darkened(0.25), 0.6))
	var ribs := maxi(2, int(shutter_h / 0.45))
	for i in ribs:
		var ry := shutter_y - shutter_h * 0.5 + (float(i) + 0.5) * shutter_h / float(ribs)
		batch.add("vbw_shutter_rib", rib, Transform3D(Basis(), Vector3(front - 0.18, ry, pos.z)))
	if open:
		# The dark recess of an open unit, with a counter across it.
		Landmarks._box(parent, null, Vector3(0.4, SHUTTER_H - 0.4, shutter_w), Vector3(front + 0.2, foot + (SHUTTER_H - 0.4) * 0.5, pos.z), Color(0.13, 0.12, 0.12), false)
		Landmarks._box(parent, null, Vector3(0.5, 0.12, shutter_w * 0.9), Vector3(front - 0.15, foot + 1.02, pos.z), Color(0.55, 0.42, 0.28), false)
	# Awning over the shopfront, tilted down toward the walk.
	if rng.randf() < 0.7:
		var canvas: Color = CANVAS[rng.randi() % CANVAS.size()]
		_obox(parent, null, Vector3(AWNING_REACH, 0.1, w * 0.86), Vector3(front - AWNING_REACH * 0.5, foot + SHUTTER_H + 0.5, pos.z), Vector3(0.0, 0.0, 0.22), PropFactory.material(canvas, 0.85), false)
		Landmarks._box(parent, null, Vector3(0.12, 0.45, w * 0.86), Vector3(front - AWNING_REACH + 0.1, foot + SHUTTER_H + 0.2, pos.z), canvas.darkened(0.2), false)
	# Sign board above the shopfront: a painted board with abstract colour blocks for lettering.
	var board: Color = PAINT[rng.randi() % PAINT.size()]
	var sign_y := foot + SHUTTER_H + 1.35
	Landmarks._box(parent, null, Vector3(0.22, 1.1, w * 0.7), Vector3(front - 0.14, sign_y, pos.z), board, false).material_override = WeaponFX.unshaded(board)
	var blocks := rng.randi_range(4, 7)
	var ink: Color = Color(0.08, 0.08, 0.1) if board.get_luminance() > 0.4 else Color(0.97, 0.95, 0.9)
	var glyph := _bmesh(Vector3(0.04, 0.44, 0.34), WeaponFX.unshaded(ink))
	for i in blocks:
		var gz := pos.z - w * 0.24 + (float(i) + 0.5) * (w * 0.48 / float(blocks))
		batch.add("vbw_sign_glyph", glyph, Transform3D(Basis().scaled(Vector3(1.0, rng.randf_range(0.7, 1.0), rng.randf_range(0.5, 1.2))), Vector3(front - 0.27, sign_y, gz)))
	# Mural on the upper wall, a few flat colour fields with a bar across them.
	if storeys > 1 and rng.randf() < 0.65:
		var fields := rng.randi_range(2, 4)
		var mural_w := w * 0.8
		for i in fields:
			var c: Color = PAINT[rng.randi() % PAINT.size()]
			var fw := mural_w / float(fields)
			var mz := pos.z - mural_w * 0.5 + (float(i) + 0.5) * fw
			Landmarks._box(parent, null, Vector3(0.1, STOREY_H * 0.72, fw - 0.15), Vector3(front - 0.07, foot + STOREY_H + STOREY_H * 0.5, mz), c, false).material_override = WeaponFX.unshaded(c)
		var stripe: Color = PAINT[rng.randi() % PAINT.size()]
		Landmarks._box(parent, null, Vector3(0.12, 0.5, mural_w), Vector3(front - 0.09, foot + STOREY_H + STOREY_H * 0.72, pos.z), stripe, false).material_override = WeaponFX.unshaded(stripe)
	# A rooftop hoarding on a few units, and a vent box on the rest.
	if rng.randf() < 0.3:
		var hoard: Color = PAINT[rng.randi() % PAINT.size()]
		Landmarks._box(parent, null, Vector3(0.2, 2.2, w * 0.6), Vector3(front + 1.2, h + 1.3, pos.z), hoard, false).material_override = WeaponFX.unshaded(hoard)
		for side: float in [-1.0, 1.0]:
			Landmarks._box(parent, null, Vector3(0.14, 1.4, 0.14), Vector3(front + 1.2, h + 0.4, pos.z + side * w * 0.27), STEEL, false)
	else:
		Landmarks._box(parent, null, Vector3(1.6, 0.9, 1.4), Vector3(pos.x + 2.0, h + 0.8, pos.z + rng.randf_range(-3.0, 3.0)), CONCRETE_GREY, false)


# --- Vendor stalls -----------------------------------------------------------------------------

## A run of trestle tables under bright canvas along the beach side of the walk, in loose
## groups. Tables, legs, poles and goods are batched; the canopy colour is per instance.
static func _stalls(anchor: Vector2, parent: Node3D, statics: StaticBody3D, plan: CityPlan, batch: MultiMeshBatch) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = _salt(anchor, 37)
	var white := PropFactory.material(Color.WHITE, 0.9)
	var table := _bmesh(Vector3(STALL_D, 0.09, STALL_W), PropFactory.material(Color(0.58, 0.46, 0.32), 0.85))
	var cloth := _bmesh(Vector3(STALL_D + 0.06, 0.75, STALL_W + 0.06), white)
	var canopy := _bmesh(Vector3(STALL_D + 1.0, 0.07, STALL_W + 0.5), white)
	var valance := _bmesh(Vector3(0.06, 0.32, STALL_W + 0.5), white)
	var pole := _cmesh(0.045, 0.045, CANOPY_H, 6, PropFactory.material(STEEL, 0.5))
	var goods := _bmesh(Vector3(0.36, 0.26, 0.3), white)
	var rack := _bmesh(Vector3(0.08, 1.5, STALL_W * 0.8), PropFactory.material(STEEL, 0.5))
	var count := int((STALL_Z_TO - STALL_Z_FROM) / STALL_SPACING)
	for i in count:
		var z := STALL_Z_FROM + (float(i) + 0.5) * STALL_SPACING
		var colour: Color = CANVAS[rng.randi() % CANVAS.size()]
		var skip := rng.randf() < 0.26
		var shift := rng.randf_range(-0.35, 0.35)
		var has_rack := rng.randf() < 0.4
		var items := rng.randi_range(3, 6)
		if skip:
			continue
		var at := _at(anchor, plan, STALL_X + shift, z, 0.0)
		batch.add("vbw_stall_table", table, Transform3D(Basis(), at + Vector3(0.0, 0.92, 0.0)))
		batch.add("vbw_stall_cloth", cloth, Transform3D(Basis(), at + Vector3(0.0, 0.5, 0.0)), colour.lightened(0.45))
		batch.add("vbw_stall_canopy", canopy, Transform3D(Basis(), at + Vector3(0.0, CANOPY_H, 0.0)), colour)
		for side: float in [-1.0, 1.0]:
			batch.add("vbw_stall_valance", valance, Transform3D(Basis(), at + Vector3(side * (STALL_D + 1.0) * 0.5, CANOPY_H - 0.18, 0.0)), colour.darkened(0.15))
			for end: float in [-1.0, 1.0]:
				batch.add("vbw_stall_pole", pole, Transform3D(Basis(), at + Vector3(side * STALL_D * 0.5, CANOPY_H * 0.5, end * STALL_W * 0.5)))
		for g in items:
			var c: Color = PAINT[rng.randi() % PAINT.size()]
			var gz := (float(g) + 0.5) * STALL_W / float(items) - STALL_W * 0.5
			batch.add("vbw_stall_goods", goods, Transform3D(Basis(Vector3.UP, rng.randf_range(-0.3, 0.3)) * Basis.from_scale(Vector3(rng.randf_range(0.7, 1.3), rng.randf_range(0.6, 1.6), 1.0)), at + Vector3(rng.randf_range(-0.6, 0.6), 1.1, gz)), c)
		if has_rack:
			batch.add("vbw_stall_rack", rack, Transform3D(Basis(), at + Vector3(STALL_D * 0.5 + 0.2, 1.55, 0.0)))
			for g in 4:
				var c: Color = PAINT[rng.randi() % PAINT.size()]
				batch.add("vbw_stall_hang", goods, Transform3D(Basis().scaled(Vector3(0.3, 2.2, 0.55)), at + Vector3(STALL_D * 0.5 + 0.28, 1.75, -STALL_W * 0.3 + float(g) * STALL_W * 0.2)), c)
		if statics != null:
			Landmarks._shape(statics, Vector3(STALL_D, 0.95, STALL_W), at + Vector3(0.0, 0.48, 0.0))


# --- Graffiti art wall -------------------------------------------------------------------------

## Tall painted panels facing the walk, each with two or three flat colour fields and a band.
## The middle of the run carries ONWARD in block letters (the only glyphs this project's FONT
## has are R U A N D O W, so the word is chosen to fit it).
static func _art_wall(anchor: Vector2, parent: Node3D, statics: StaticBody3D, plan: CityPlan, rng: RandomNumberGenerator) -> void:
	var run := WALL_Z_TO - WALL_Z_FROM
	var panels := int(run / WALL_PANEL)
	var face := WALL_X + WALL_T * 0.5
	for i in panels:
		var z := WALL_Z_FROM + (float(i) + 0.5) * WALL_PANEL
		var h := WALL_H * rng.randf_range(0.82, 1.0)
		var at := _at(anchor, plan, WALL_X, z, h * 0.5)
		Landmarks._box(parent, statics, Vector3(WALL_T, h, WALL_PANEL - 0.12), at, CONCRETE_GREY, true)
		Landmarks._box(parent, null, Vector3(WALL_T + 0.3, 0.22, WALL_PANEL), at + Vector3(0.0, h * 0.5 + 0.1, 0.0), CONCRETE_DARK, false)
		var fields := rng.randi_range(2, 3)
		for f in fields:
			var c: Color = PAINT[rng.randi() % PAINT.size()]
			var fw := (WALL_PANEL - 0.4) / float(fields)
			var fz := z - (WALL_PANEL - 0.4) * 0.5 + (float(f) + 0.5) * fw
			var panel := Landmarks._box(parent, null, Vector3(0.09, h * rng.randf_range(0.5, 0.86), fw - 0.12), _at(anchor, plan, face + 0.04, fz, h * 0.48), c, false)
			panel.material_override = WeaponFX.unshaded(c)
		var stripe: Color = PAINT[rng.randi() % PAINT.size()]
		Landmarks._box(parent, null, Vector3(0.11, 0.35, WALL_PANEL - 0.3), _at(anchor, plan, face + 0.05, z, h * 0.22), stripe, false).material_override = WeaponFX.unshaded(stripe)
	# The word, facing +X (the walk). A yawed pivot turns Landmarks._text(), which draws along
	# its parent's +X and faces its parent's +Z, to look down the beach.
	var mid := (WALL_Z_FROM + WALL_Z_TO) * 0.5
	var pivot := Node3D.new()
	pivot.position = _at(anchor, plan, face + 0.12, mid, 1.15)
	pivot.rotation.y = PI * 0.5
	parent.add_child(pivot)
	Landmarks._text("ONWARD", 0.42, Vector3.ZERO, pivot, Color(0.99, 0.95, 0.86))


# --- Skate park ----------------------------------------------------------------------------------

## A raised concrete plateau with a round bowl cut through it to sand level and a snake run
## trenched across its shore side, plus a small street plaza of ledges and rails. Park-local
## coordinates here: +X is inland, +Z is up the beach, origin at SKATE_X / SKATE_Z, y = 0 is
## the sand. Roughly 2,900 triangles and about 80 collision shapes.
static func _skate_park(anchor: Vector2, parent: Node3D, statics: StaticBody3D, plan: CityPlan) -> void:
	var base := _at(anchor, plan, SKATE_X, SKATE_Z, 0.0)
	var deck := PropFactory.pbr("concrete", 5.0, CONCRETE_PALE)
	var half_w := SKATE_W * 0.5
	var half_l := SKATE_L * 0.5
	var bowl_x := 5.0
	var bowl_z := -9.0
	var slot_a := -13.5
	var slot_b := -5.5
	var snake_z0 := -19.0
	var snake_z1 := snake_z0 + SNAKE_LEN
	# The deck, as rectangles that leave a square hole for the bowl and a slot for the snake run.
	var plates: Array = [
		[-half_w, bowl_x - BOWL_R, -half_l, snake_z0],
		[-half_w, bowl_x - BOWL_R, snake_z1, half_l],
		[-half_w, slot_a, snake_z0, snake_z1],
		[slot_b, bowl_x - BOWL_R, snake_z0, snake_z1],
		[bowl_x - BOWL_R, bowl_x + BOWL_R, -half_l, bowl_z - BOWL_R],
		[bowl_x - BOWL_R, bowl_x + BOWL_R, bowl_z + BOWL_R, half_l],
		[bowl_x + BOWL_R, half_w, -half_l, half_l],
	]
	for p: Array in plates:
		var sx: float = p[1] - p[0]
		var sz: float = p[3] - p[2]
		if sx <= 0.05 or sz <= 0.05:
			continue
		var at := base + Vector3((p[0] + p[1]) * 0.5, PARK_DECK_H - 0.3, (p[2] + p[3]) * 0.5)
		Landmarks._box(parent, statics, Vector3(sx, 0.6, sz), at, CONCRETE_PALE, true).material_override = deck
	# The four corners of the bowl's square hole, stepped round the arc in three boxes each.
	var corners: Array = [[7.4, 3.8, 9.0, 9.0], [3.8, 7.4, 9.0, 9.0], [5.9, 5.9, 9.0, 9.0]]
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			for c: Array in corners:
				var w: float = c[2] - c[0]
				var l: float = c[3] - c[1]
				var at := base + Vector3(bowl_x + sx * (c[0] + w * 0.5), PARK_DECK_H - 0.3, bowl_z + sz * (c[1] + l * 0.5))
				Landmarks._box(parent, statics, Vector3(w, 0.6, l), at, CONCRETE_PALE, true).material_override = deck
	# Fascia walls round the plateau, so it reads as a poured pad and not a floating slab.
	for side: float in [-1.0, 1.0]:
		Landmarks._box(parent, null, Vector3(SKATE_W + 0.3, PARK_DECK_H, 0.4), base + Vector3(0.0, PARK_DECK_H * 0.5, side * half_l), CONCRETE_GREY, false).material_override = PropFactory.pbr("concrete", 4.0, CONCRETE_GREY)
		Landmarks._box(parent, null, Vector3(0.4, PARK_DECK_H, SKATE_L), base + Vector3(side * half_w, PARK_DECK_H * 0.5, 0.0), CONCRETE_GREY, false).material_override = PropFactory.pbr("concrete", 4.0, CONCRETE_GREY)
	# Ramp up from the sand on the walk side, with a kerb each side.
	var ramp_len := 5.0
	_obox(parent, statics, Vector3(ramp_len + 0.6, 0.4, 6.0), base + Vector3(half_w + ramp_len * 0.5, PARK_DECK_H * 0.5, half_l - 6.0), Vector3(0.0, 0.0, -atan2(PARK_DECK_H, ramp_len)), deck, true)
	_bowl(parent, statics, base + Vector3(bowl_x, 0.0, bowl_z))
	_snake(parent, statics, base, slot_a, slot_b, snake_z0, snake_z1)
	_street_section(parent, statics, base, Vector3(-4.0, PARK_DECK_H, half_l - 9.0))


## The bowl: two rows of tilted panels round a BOWL_SEGMENTS-gon, a flat floor at sand level and
## a pale coping ring at the rim. Steep at the top, flat at the bottom, so it is skateable.
static func _bowl(parent: Node3D, statics: StaticBody3D, centre: Vector3) -> void:
	var mat := PropFactory.pbr("concrete", 4.0, CONCRETE_PALE)
	var rows: Array = [
		{"r0": BOWL_R, "r1": BOWL_KNEE_R, "y0": PARK_DECK_H, "y1": BOWL_KNEE_Y},
		{"r0": BOWL_KNEE_R, "r1": BOWL_FLOOR_R, "y0": BOWL_KNEE_Y, "y1": 0.0},
	]
	for row: Dictionary in rows:
		var run: float = row.r0 - row.r1
		var drop: float = row.y0 - row.y1
		var slant: float = sqrt(run * run + drop * drop)
		var tilt := atan2(drop, run)
		var r_mid: float = (row.r0 + row.r1) * 0.5
		var y_mid: float = (row.y0 + row.y1) * 0.5
		var chord: float = 2.0 * row.r0 * tan(PI / float(BOWL_SEGMENTS)) * 1.1
		for i in BOWL_SEGMENTS:
			var a := TAU * float(i) / float(BOWL_SEGMENTS)
			var o := Vector3(sin(a), 0.0, cos(a))
			_obox(parent, statics, Vector3(chord, BOWL_PANEL_T, slant), centre + o * r_mid + Vector3(0.0, y_mid, 0.0), Vector3(tilt, a + PI, 0.0), mat, true)
	_poly_node(parent, statics, BOWL_FLOOR_R + 0.2, 0.5, BOWL_SEGMENTS, centre + Vector3(0.0, -0.25, 0.0), mat, true)
	var coping := PropFactory.material(Color(0.88, 0.86, 0.82), 0.35)
	var lip := 2.0 * BOWL_R * tan(PI / float(BOWL_SEGMENTS)) * 1.1
	for i in BOWL_SEGMENTS:
		var a := TAU * float(i) / float(BOWL_SEGMENTS)
		var o := Vector3(sin(a), 0.0, cos(a))
		_obox(parent, null, Vector3(lip, 0.2, 0.45), centre + o * BOWL_R + Vector3(0.0, PARK_DECK_H + 0.08, 0.0), Vector3(0.0, a + PI, 0.0), coping, false)


## The snake run: a trench across the shore side of the plateau with a weaving floor and banked
## walls that rise to the deck. The banks are wide where the channel swings away from the slot
## edge and steep where it swings toward it, which is what gives a snake run its shape.
static func _snake(parent: Node3D, statics: StaticBody3D, base: Vector3, slot_a: float, slot_b: float, z0: float, z1: float) -> void:
	var mat := PropFactory.pbr("concrete", 4.5, CONCRETE_PALE)
	var mid := (slot_a + slot_b) * 0.5
	var floor_y := PARK_DECK_H - SNAKE_DEPTH
	# Solid fill under the trench floor, so the trench is a cut in concrete and not a shelf.
	Landmarks._box(parent, null, Vector3(slot_b - slot_a, floor_y, z1 - z0), base + Vector3(mid, floor_y * 0.5, (z0 + z1) * 0.5), CONCRETE_GREY, false).material_override = PropFactory.pbr("concrete", 4.0, CONCRETE_GREY)
	var seg_len := (z1 - z0) / float(SNAKE_SEGMENTS)
	for i in SNAKE_SEGMENTS:
		var t0 := float(i) / float(SNAKE_SEGMENTS)
		var t1 := float(i + 1) / float(SNAKE_SEGMENTS)
		var x0 := mid + sin(t0 * TAU) * SNAKE_AMP
		var x1 := mid + sin(t1 * TAU) * SNAKE_AMP
		var cz := z0 + (t0 + t1) * 0.5 * (z1 - z0)
		var cx := (x0 + x1) * 0.5
		var yaw := _face_yaw(Vector2(x1 - x0, seg_len))
		var length := Vector2(x1 - x0, seg_len).length()
		_obox(parent, statics, Vector3(SNAKE_W, 0.5, length * 1.08), base + Vector3(cx, floor_y - 0.25, cz), Vector3(0.0, yaw, 0.0), mat, true)
		for side: float in [-1.0, 1.0]:
			var edge := cx + side * SNAKE_W * 0.5
			var outer := slot_b if side > 0.0 else slot_a
			var run: float = maxf(absf(outer - edge), 0.7)
			var slant := sqrt(run * run + SNAKE_DEPTH * SNAKE_DEPTH)
			var pitch := -atan2(SNAKE_DEPTH, run)
			var wall_yaw := PI * 0.5 if side > 0.0 else -PI * 0.5
			_obox(parent, statics, Vector3(length * 1.15, 0.45, slant), base + Vector3(edge + side * run * 0.5, floor_y + SNAKE_DEPTH * 0.5, cz), Vector3(pitch, wall_yaw, 0.0), mat, true)


## The street plaza on the deck: two ledges, a funbox with a kicker each side and a flat rail.
static func _street_section(parent: Node3D, statics: StaticBody3D, base: Vector3, at: Vector3) -> void:
	var mat := PropFactory.pbr("concrete", 3.0, CONCRETE_PALE)
	var steel := PropFactory.material(STEEL, 0.35)
	for i in 2:
		var ledge := base + at + Vector3(float(i) * 5.5, 0.3, -3.0 - float(i) * 2.0)
		Landmarks._box(parent, statics, Vector3(1.0, 0.6, 7.0), ledge, CONCRETE_PALE, true).material_override = mat
		Landmarks._box(parent, null, Vector3(1.1, 0.12, 7.1), ledge + Vector3(0.0, 0.32, 0.0), Color(0.80, 0.78, 0.74), false)
	var box_at := base + at + Vector3(11.0, 0.35, 3.0)
	Landmarks._box(parent, statics, Vector3(4.0, 0.7, 5.0), box_at, CONCRETE_PALE, true).material_override = mat
	for side: float in [-1.0, 1.0]:
		_obox(parent, statics, Vector3(4.0, 0.3, 2.6), box_at + Vector3(0.0, -0.18, side * 3.7), Vector3(-side * 0.28, 0.0, 0.0), mat, true)
	var rail_at := base + at + Vector3(3.0, 0.0, 7.0)
	for side: float in [-1.0, 1.0]:
		Landmarks._cyl(parent, null, 0.06, 0.6, rail_at + Vector3(0.0, 0.3, side * 3.2), STEEL)
	_obox(parent, statics, Vector3(0.09, 0.09, 7.0), rail_at + Vector3(0.0, 0.62, 0.0), Vector3.ZERO, steel, true)


# --- Basketball ------------------------------------------------------------------------------------

## Two courts side by side on the sand: a tinted asphalt slab, painted lines from one unit line
## mesh scaled per segment, and a hoop at each end. About 1,200 triangles a court.
static func _courts(anchor: Vector2, parent: Node3D, statics: StaticBody3D, plan: CityPlan, batch: MultiMeshBatch) -> void:
	var line := _bmesh(Vector3(LINE_W, 0.03, 1.0), PropFactory.material(Color(0.95, 0.94, 0.90), 0.8))
	for c in COURT_Z.size():
		var court_z: float = COURT_Z[c]
		var base := _at(anchor, plan, COURT_X, court_z, 0.0)
		Landmarks._box(parent, statics, Vector3(COURT_W, 0.3, COURT_L), base + Vector3(0.0, 0.05, 0.0), COURT_BLUE, true).material_override = PropFactory.pbr("asphalt_aerial", 7.0, COURT_BLUE)
		var y := 0.21
		# Sidelines, baselines and the halfway line.
		for side: float in [-1.0, 1.0]:
			_line(batch, line, base + Vector3(side * (COURT_W * 0.5 - 0.5), y, 0.0), 0.0, COURT_L - 1.0)
			_line(batch, line, base + Vector3(0.0, y, side * (COURT_L * 0.5 - 0.5)), PI * 0.5, COURT_W - 1.0)
		_line(batch, line, base + Vector3(0.0, y, 0.0), PI * 0.5, COURT_W - 1.0)
		_arc(batch, line, base + Vector3(0.0, y, 0.0), 1.8, 0.0, TAU, COURT_ARC_SEGMENTS)
		for end: float in [-1.0, 1.0]:
			var baseline := end * (COURT_L * 0.5 - 0.5)
			var key_far := baseline - end * 5.8
			# The key: two rails and the free-throw line, then the arc over it.
			for side: float in [-1.0, 1.0]:
				_line(batch, line, base + Vector3(side * 2.45, y, (baseline + key_far) * 0.5), 0.0, 5.8)
			_line(batch, line, base + Vector3(0.0, y, key_far), PI * 0.5, 4.9)
			_arc(batch, line, base + Vector3(0.0, y, key_far), 1.8, 0.0, PI, COURT_ARC_SEGMENTS / 2 + 1)
			_arc(batch, line, base + Vector3(0.0, y, baseline - end * 1.2), 6.3, 0.35, PI - 0.35, COURT_ARC_SEGMENTS)
			_hoop(parent, statics, base + Vector3(0.0, 0.2, baseline - end * 1.2), end)


## A pole, a kinked arm, a backboard, a rim ring and a stub of net. About 190 triangles.
static func _hoop(parent: Node3D, statics: StaticBody3D, at: Vector3, facing: float) -> void:
	var pole := at + Vector3(0.0, 0.0, facing * 2.4)
	Landmarks._cyl(parent, statics, 0.14, HOOP_H + 0.9, pole + Vector3(0.0, (HOOP_H + 0.9) * 0.5, 0.0), STEEL)
	Landmarks._box(parent, null, Vector3(0.7, 0.7, 0.7), pole + Vector3(0.0, 0.2, 0.0), CONCRETE_GREY, false)
	Landmarks._box(parent, null, Vector3(0.16, 0.16, 2.4), pole + Vector3(0.0, HOOP_H + 0.75, -facing * 1.2), STEEL, false)
	var board := at + Vector3(0.0, HOOP_H + 0.45, -facing * 0.15)
	Landmarks._box(parent, statics, Vector3(1.8, 1.05, 0.08), board, Color(0.92, 0.92, 0.94), true)
	Landmarks._box(parent, null, Vector3(0.62, 0.46, 0.12), board + Vector3(0.0, -0.18, -facing * 0.06), Color(0.9, 0.3, 0.26), false)
	var rim := board + Vector3(0.0, -0.42, -facing * 0.42)
	for i in 8:
		var a := TAU * float(i) / 8.0
		_obox(parent, null, Vector3(0.18, 0.05, 0.05), rim + Vector3(sin(a) * 0.23, 0.0, cos(a) * 0.23), Vector3(0.0, a, 0.0), PropFactory.material(Color(0.92, 0.42, 0.14), 0.4), false)
	for i in 6:
		var a := TAU * float(i) / 6.0
		_obox(parent, null, Vector3(0.04, 0.45, 0.04), rim + Vector3(sin(a) * 0.19, -0.24, cos(a) * 0.19), Vector3(0.0, a, 0.0), PropFactory.material(Color(0.94, 0.94, 0.9), 0.9), false)


# --- Weights area ------------------------------------------------------------------------------------

## The outdoor gym on the sand: a fenced concrete pad with a stage, two pull-up rigs, monkey
## bars, dip bars, a squat rack, benches, a dumbbell rack and plate trees. This and the bowl are
## the two things that make the boardwalk read, so it gets the most parts: about 7,000 triangles.
static func _muscle_beach(anchor: Vector2, parent: Node3D, statics: StaticBody3D, plan: CityPlan, batch: MultiMeshBatch) -> void:
	var base := _at(anchor, plan, GYM_X, GYM_Z, 0.0)
	var pad := PropFactory.pbr("concrete", 5.0, SAND_PAD)
	var steel := PropFactory.material(STEEL, 0.35)
	var black := PropFactory.material(RUBBER_BLACK, 0.85)
	var half_w := GYM_W * 0.5
	var half_l := GYM_L * 0.5
	Landmarks._box(parent, statics, Vector3(GYM_W, GYM_PAD_H * 2.0, GYM_L), base, SAND_PAD, true).material_override = pad
	# Fence: posts round the perimeter with a gap on the walk side, and two rails a side.
	var post := _cmesh(0.06, 0.06, 1.25, 6, steel)
	var rail := _bmesh(Vector3(0.07, 0.07, 1.0), steel)
	var step := 3.0
	for side: float in [-1.0, 1.0]:
		var along := int(GYM_L / step)
		for i in along + 1:
			var z := -half_l + float(i) * GYM_L / float(along)
			if side > 0.0 and absf(z) < 4.6:
				continue
			batch.add("vbw_gym_post", post, Transform3D(Basis(), base + Vector3(side * half_w, GYM_PAD_H + 0.62, z)))
		var across := int(GYM_W / step)
		for i in across + 1:
			var x := -half_w + float(i) * GYM_W / float(across)
			batch.add("vbw_gym_post", post, Transform3D(Basis(), base + Vector3(x, GYM_PAD_H + 0.62, side * half_l)))
		for h: float in [0.62, 1.14]:
			# Along the beach-parallel edge, running in X...
			batch.add("vbw_gym_rail", rail, Transform3D(Basis(Vector3.UP, PI * 0.5) * Basis.from_scale(Vector3(1.0, 1.0, GYM_W)), base + Vector3(0.0, GYM_PAD_H + h, side * half_l)))
			# ...and along the end edges, running in Z, broken by the entrance on the walk side.
			if side < 0.0:
				batch.add("vbw_gym_rail", rail, Transform3D(Basis.from_scale(Vector3(1.0, 1.0, GYM_L)), base + Vector3(side * half_w, GYM_PAD_H + h, 0.0)))
			else:
				for end: float in [-1.0, 1.0]:
					batch.add("vbw_gym_rail", rail, Transform3D(Basis.from_scale(Vector3(1.0, 1.0, half_l - 4.6)), base + Vector3(side * half_w, GYM_PAD_H + h, end * (half_l + 4.6) * 0.5)))
	# Entrance arch with the block letters over it, facing the walk.
	var arch_x := half_w + 0.7
	for end: float in [-1.0, 1.0]:
		Landmarks._box(parent, statics, Vector3(0.34, ARCH_H, 0.34), base + Vector3(arch_x, ARCH_H * 0.5, end * 4.5), CONCRETE_GREY, true)
	Landmarks._box(parent, null, Vector3(0.5, 0.55, 9.6), base + Vector3(arch_x, ARCH_H + 0.2, 0.0), CONCRETE_GREY, false)
	var pivot := Node3D.new()
	pivot.position = base + Vector3(arch_x + 0.3, ARCH_H + 0.6, 0.0)
	pivot.rotation.y = PI * 0.5
	parent.add_child(pivot)
	Landmarks._text("RANDO", 0.26, Vector3.ZERO, pivot, Color(0.95, 0.35, 0.18))
	# Stage at the back of the pad, where the lifting happens.
	var stage := base + Vector3(-half_w + 6.0, GYM_PAD_H + 0.3, -half_l + 3.0)
	Landmarks._box(parent, statics, Vector3(10.0, 0.6, 5.0), stage, CONCRETE_PALE, true).material_override = pad
	for i in 2:
		Landmarks._box(parent, statics, Vector3(10.0, 0.2, 0.6), stage + Vector3(0.0, -0.2 - float(i) * 0.2, 2.8 + float(i) * 0.6), CONCRETE_GREY, true)
	Landmarks._box(parent, null, Vector3(2.2, 0.12, 2.2), stage + Vector3(-2.0, 0.34, 0.0), RUBBER_BLACK, false).material_override = black
	# Two pull-up rigs: four uprights, a top bar each way, and rungs across one of them.
	for r in 2:
		var rig := base + Vector3(-half_w + 5.0 + float(r) * 7.5, GYM_PAD_H, 4.0 + float(r) * 6.0)
		for sx: float in [-1.0, 1.0]:
			for sz: float in [-1.0, 1.0]:
				_ocyl(parent, statics, 0.07, RIG_H, rig + Vector3(sx * 1.4, RIG_H * 0.5, sz * 2.4), Vector3.ZERO, 8, steel, true)
			_bar(parent, statics, rig + Vector3(sx * 1.4, RIG_H, 0.0), 4.8, 2, BAR_R, steel, true)
		if r == 0:
			for i in 7:
				_bar(parent, null, rig + Vector3(0.0, RIG_H, -2.1 + float(i) * 0.7), 2.8, 0, BAR_R, steel, false)
		else:
			_bar(parent, statics, rig + Vector3(0.0, RIG_H, -1.2), 2.8, 0, BAR_R, steel, true)
			_bar(parent, null, rig + Vector3(0.0, RIG_H - 0.7, 1.2), 2.8, 0, BAR_R, steel, false)
			for sx: float in [-1.0, 1.0]:
				_ocyl(parent, null, 0.035, 1.1, rig + Vector3(sx * 0.5, RIG_H - 0.55, -1.2), Vector3.ZERO, 6, black, false)
				_ocyl(parent, null, 0.13, 0.06, rig + Vector3(sx * 0.5, RIG_H - 1.1, -1.2), Vector3(PI * 0.5, 0.0, 0.0), 8, black, false)
	# Dip bars and a low parallel bar.
	var dip := base + Vector3(2.0, GYM_PAD_H, -8.0)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			_ocyl(parent, statics, 0.06, 1.3, dip + Vector3(sx * 0.55, 0.65, sz * 0.9), Vector3.ZERO, 6, steel, true)
		_bar(parent, statics, dip + Vector3(sx * 0.55, 1.3, 0.0), 2.0, 2, BAR_R, steel, true)
	# Squat rack with a loaded bar.
	var rack := base + Vector3(7.0, GYM_PAD_H, -3.0)
	for sz: float in [-1.0, 1.0]:
		_ocyl(parent, statics, 0.08, 1.9, rack + Vector3(0.0, 0.95, sz * 0.8), Vector3.ZERO, 8, steel, true)
		_ocyl(parent, null, 0.05, 0.3, rack + Vector3(0.18, 1.8, sz * 0.8), Vector3(0.0, 0.0, PI * 0.5), 6, steel, false)
	_bar(parent, statics, rack + Vector3(0.18, 1.9, 0.0), 2.6, 2, 0.045, steel, true)
	for sz: float in [-1.0, 1.0]:
		for p in 2:
			_ocyl(parent, null, 0.24, 0.07, rack + Vector3(0.18, 1.9, sz * (1.05 + float(p) * 0.09)), Vector3(PI * 0.5, 0.0, 0.0), 10, black, false)
	# Benches: one flat, two inclined.
	for b in 3:
		var bench := base + Vector3(6.5 + float(b % 2) * 3.0, GYM_PAD_H, 3.0 + float(b) * 3.2)
		Landmarks._box(parent, statics, Vector3(0.7, 0.16, 2.0), bench + Vector3(0.0, 0.45, 0.0), RUBBER_BLACK, true).material_override = black
		if b > 0:
			_obox(parent, null, Vector3(0.7, 0.16, 1.1), bench + Vector3(0.0, 0.66, -1.2), Vector3(0.5, 0.0, 0.0), black, false)
		for sz: float in [-1.0, 1.0]:
			Landmarks._box(parent, null, Vector3(0.5, 0.45, 0.12), bench + Vector3(0.0, 0.22, sz * 0.85), STEEL, false)
	# Dumbbell rack: two tiers of a dozen dumbbells, all batched.
	var db := base + Vector3(9.5, GYM_PAD_H, 9.0)
	var db_bar := _cmesh(0.028, 0.028, 0.34, 6, black)
	var db_head := _cmesh(0.085, 0.085, 0.12, 8, black)
	for tier in 2:
		var ty := 0.45 + float(tier) * 0.42
		Landmarks._box(parent, statics, Vector3(0.5, 0.1, 3.2), db + Vector3(float(tier) * 0.18, ty, 0.0), STEEL, true)
		for i in 6:
			var dz := -1.35 + float(i) * 0.54
			var spin := Basis(Vector3.BACK, PI * 0.5)
			batch.add("vbw_db_bar", db_bar, Transform3D(spin, db + Vector3(float(tier) * 0.18, ty + 0.14, dz)))
			for sx: float in [-1.0, 1.0]:
				batch.add("vbw_db_head", db_head, Transform3D(spin, db + Vector3(float(tier) * 0.18 + sx * 0.2, ty + 0.14, dz)))
	for sz: float in [-1.0, 1.0]:
		Landmarks._box(parent, null, Vector3(0.6, 0.9, 0.1), db + Vector3(0.1, 0.45, sz * 1.6), STEEL, false)
	# Plate trees.
	for t in 2:
		var tree := base + Vector3(4.0 + float(t) * 2.4, GYM_PAD_H, 11.5)
		_ocyl(parent, statics, 0.09, 1.3, tree + Vector3(0.0, 0.65, 0.0), Vector3.ZERO, 6, steel, true)
		for p in 3:
			_ocyl(parent, null, 0.27, 0.08, tree + Vector3(0.0, 0.35 + float(p) * 0.33, 0.22), Vector3(PI * 0.5, 0.0, 0.0), 10, black, false)


# --- Benches, bins, lamps, showers -----------------------------------------------------------------

## Everything that lines the walk itself, all batched: slat benches under the palms, drums,
## twin-globe lamp posts, outdoor showers on the sand and a couple of bike loops.
static func _furniture(anchor: Vector2, parent: Node3D, statics: StaticBody3D, plan: CityPlan, batch: MultiMeshBatch) -> void:
	var wood := PropFactory.material(Color(0.55, 0.42, 0.28), 0.85)
	var steel := PropFactory.material(STEEL, 0.4)
	var slat := _bmesh(Vector3(0.52, 0.07, 1.9), wood)
	var leg := _bmesh(Vector3(0.5, 0.42, 0.1), steel)
	var drum := _cmesh(0.42, 0.42, 1.0, 10, PropFactory.material(Color(0.24, 0.42, 0.3), 0.8))
	var drum_lid := _cmesh(0.46, 0.3, 0.16, 10, PropFactory.material(Color(0.2, 0.2, 0.22), 0.6))
	var mast := _cmesh(0.1, 0.08, LAMP_H, 8, steel)
	var arm := _bmesh(Vector3(1.1, 0.08, 0.08), steel)
	var globe := _cmesh(0.24, 0.24, 0.42, 8, WeaponFX.unshaded(Color(1.0, 0.94, 0.78)))
	var edge := PATH_WIDTH * 0.5 + 1.1
	var benches := int(LENGTH / BENCH_SPACING)
	for i in benches:
		var z := -LENGTH * 0.5 + (float(i) + 0.5) * BENCH_SPACING
		var side := -1.0 if i % 2 == 0 else 1.0
		var at := _at(anchor, plan, side * edge, z, PATH_TOP)
		batch.add("vbw_bench_slat", slat, Transform3D(Basis(), at + Vector3(0.0, 0.45, 0.0)))
		batch.add("vbw_bench_slat", slat, Transform3D(Basis(Vector3.BACK, 0.35), at + Vector3(side * 0.26, 0.72, 0.0)))
		for end: float in [-1.0, 1.0]:
			batch.add("vbw_bench_leg", leg, Transform3D(Basis(), at + Vector3(0.0, 0.21, end * 0.75)))
	var bins := int(LENGTH / BIN_SPACING)
	for i in bins:
		var z := -LENGTH * 0.5 + (float(i) + 0.5) * BIN_SPACING
		var side := 1.0 if i % 2 == 0 else -1.0
		var at := _at(anchor, plan, side * edge, z, PATH_TOP)
		batch.add("vbw_bin", drum, Transform3D(Basis(), at + Vector3(0.0, 0.5, 0.0)))
		batch.add("vbw_bin_lid", drum_lid, Transform3D(Basis(), at + Vector3(0.0, 1.06, 0.0)))
	var lamps := int(LENGTH / LAMP_SPACING)
	for i in lamps:
		var z := -LENGTH * 0.5 + (float(i) + 0.5) * LAMP_SPACING
		var at := _at(anchor, plan, -PATH_WIDTH * 0.5 - 0.7, z, PATH_TOP)
		batch.add("vbw_lamp_mast", mast, Transform3D(Basis(), at + Vector3(0.0, LAMP_H * 0.5, 0.0)))
		for side: float in [-1.0, 1.0]:
			batch.add("vbw_lamp_arm", arm, Transform3D(Basis(), at + Vector3(side * 0.55, LAMP_H - 0.1, 0.0)))
			batch.add("vbw_lamp_globe", globe, Transform3D(Basis(), at + Vector3(side * 1.05, LAMP_H - 0.3, 0.0)))
		if statics != null:
			Landmarks._shape(statics, Vector3(0.3, LAMP_H, 0.3), at + Vector3(0.0, LAMP_H * 0.5, 0.0))
	var pipe := _cmesh(0.07, 0.07, SHOWER_H, 6, steel)
	var head := _bmesh(Vector3(0.5, 0.12, 0.28), steel)
	var slab := _cmesh(1.3, 1.3, 0.16, 10, PropFactory.pbr("concrete", 3.0, CONCRETE_GREY))
	for i in SHOWER_Z.size():
		var z: float = SHOWER_Z[i]
		var at := _at(anchor, plan, -21.0, z, 0.0)
		batch.add("vbw_shower_slab", slab, Transform3D(Basis(), at + Vector3(0.0, 0.08, 0.0)))
		batch.add("vbw_shower_pipe", pipe, Transform3D(Basis(), at + Vector3(0.0, SHOWER_H * 0.5, 0.0)))
		batch.add("vbw_shower_head", head, Transform3D(Basis(), at + Vector3(0.22, SHOWER_H - 0.1, 0.0)))
	var loop := _bmesh(Vector3(0.06, 0.8, 0.06), steel)
	var loop_top := _bmesh(Vector3(0.06, 0.06, 0.9), steel)
	for i in 6:
		var z := -150.0 + float(i) * 60.0
		var at := _at(anchor, plan, PATH_WIDTH * 0.5 + 0.9, z, PATH_TOP)
		for side: float in [-1.0, 1.0]:
			batch.add("vbw_rack_leg", loop, Transform3D(Basis(), at + Vector3(0.0, 0.4, side * 0.45)))
		batch.add("vbw_rack_top", loop_top, Transform3D(Basis(), at + Vector3(0.0, 0.8, 0.0)))


# --- Helpers ---------------------------------------------------------------------------------------
# Landmarks._box() / _cyl() only take an axis-aligned shape and a flat colour, so these add the
# rotation and the material. Everything else (_facade_box, _text, _shape) is used as it is.

## Local metres to a true world position, with the sand height under it.
static func _at(anchor: Vector2, plan: CityPlan, x: float, z: float, y: float) -> Vector3:
	var p := Vector2(anchor.x + x + WALK_SHIFT_X, anchor.y + z)
	var ground := plan.height_at(p) if plan != null else 0.0
	return Vector3(p.x, ground + y, p.y)


## A seed that depends on the anchor, so a given boardwalk is always the same one.
static func _salt(anchor: Vector2, stream: int) -> int:
	return SEED_SALT ^ (stream * 2654435761) ^ (int(anchor.x) * 73856093) ^ (int(anchor.y) * 19349663)


## Yaw that turns a node's local +Z toward the world XZ direction `d`.
static func _face_yaw(d: Vector2) -> float:
	return atan2(d.x, d.y)


static func _bmesh(size: Vector3, mat: Material) -> Mesh:
	var m := BoxMesh.new()
	m.size = size
	m.material = mat
	return m


static func _cmesh(radius: float, top: float, height: float, sides: int, mat: Material) -> Mesh:
	var m := CylinderMesh.new()
	m.bottom_radius = radius
	m.top_radius = top
	m.height = height
	m.radial_segments = sides
	m.rings = 0
	m.material = mat
	return m


## A box with euler rotation, an explicit material and optional rotated collision.
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


## A cylinder with a chosen segment count, euler rotation and an explicit material.
static func _ocyl(parent: Node3D, statics: StaticBody3D, radius: float, height: float, pos: Vector3, rot: Vector3, sides: int, mat: Material, collide: bool) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.mesh = _cmesh(radius, radius, height, sides, mat)
	mesh.material_override = mat
	mesh.position = pos
	mesh.rotation = rot
	parent.add_child(mesh)
	if collide and statics != null:
		var shape := CollisionShape3D.new()
		var s := CylinderShape3D.new()
		s.radius = radius
		s.height = height
		shape.shape = s
		shape.position = pos
		shape.rotation = rot
		statics.add_child(shape)
	return mesh


## A horizontal bar of `length` along axis 0 = X, 1 = Y, 2 = Z.
static func _bar(parent: Node3D, statics: StaticBody3D, centre: Vector3, length: float, axis: int, radius: float, mat: Material, collide: bool) -> void:
	var rot := Vector3.ZERO
	if axis == 0:
		rot = Vector3(0.0, 0.0, PI * 0.5)
	elif axis == 2:
		rot = Vector3(PI * 0.5, 0.0, 0.0)
	_ocyl(parent, statics, radius, length, centre, rot, 8, mat, collide)


## A flat prism: a low-segment cylinder used for bowl floors, shower slabs and pads.
static func _poly_node(parent: Node3D, statics: StaticBody3D, radius: float, height: float, sides: int, pos: Vector3, mat: Material, collide: bool) -> void:
	var mesh := MeshInstance3D.new()
	mesh.mesh = _cmesh(radius, radius, height, sides, mat)
	mesh.material_override = mat
	mesh.position = pos
	parent.add_child(mesh)
	if collide and statics != null:
		var shape := CollisionShape3D.new()
		var s := CylinderShape3D.new()
		s.radius = radius
		s.height = height
		shape.shape = s
		shape.position = pos
		statics.add_child(shape)


## One painted line: the unit line mesh scaled to `length` and yawed about Y.
static func _line(batch: MultiMeshBatch, mesh: Mesh, at: Vector3, yaw: float, length: float) -> void:
	batch.add("vbw_court_line", mesh, Transform3D(Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(1.0, 1.0, length)), at))


## A painted arc as `segments` chords of the unit line mesh.
static func _arc(batch: MultiMeshBatch, mesh: Mesh, centre: Vector3, radius: float, from_a: float, to_a: float, segments: int) -> void:
	var span := to_a - from_a
	for i in segments:
		var a0 := from_a + span * float(i) / float(segments)
		var a1 := from_a + span * float(i + 1) / float(segments)
		var p0 := centre + Vector3(sin(a0), 0.0, cos(a0)) * radius
		var p1 := centre + Vector3(sin(a1), 0.0, cos(a1)) * radius
		var d := p1 - p0
		_line(batch, mesh, (p0 + p1) * 0.5, _face_yaw(Vector2(d.x, d.z)), d.length() * 1.08)
