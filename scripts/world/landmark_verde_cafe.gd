class_name LandmarkVerdeCafe
extends RefCounted
## Verde Cafe: a single-storey corner coffee house on the Westside, roughly 16 x 12 m, with an
## L-shaped sidewalk patio wrapped around its glazed corner. The player meets this one on foot,
## so the detail budget goes into the shopfront (sill, mullions, transoms, a glazed door) and the
## patio (bistro tables with cups left on them, chairs, parasols, planters, railing, menu board,
## bike rack) rather than into the box itself, which is a plain stucco shell with a deep awning.
##
## Orientation is FIXED and the parent cannot rotate it: children are added at true world
## coordinates. The glazed corner is +X / +Z, so the shopfront faces +Z and the side elevation
## faces +X, and the anchor wants a corner lot with streets on its south and east sides. The
## ground is a single sample at the anchor, so the lot wants to be flat too: the 0.36 m slab
## hides about +/-0.18 m of relief and anything steeper will float.
##
## Nothing here is a real business. The name, the green trim and the sign band are original.
##
## Night: no lights. The windows, the pavement under the awning and the wash on the door are
## additive quads on shaders/light_pool.gdshader (through PropFactory.lamp_face() and
## light_pool()); the sign letters and the bulbs strung under the awning edge share
## shaders/sign_letters.gdshader, the same one the city's shop fascias use. All of them are
## driven by the `lamp_factor` shader global, which DayNight sets to
## max(night_factor, weather_darken * 0.85), so the cafe costs nothing at noon, lights itself
## at dusk and lights itself in a storm too, without a single OmniLight.
##
## Triangles, measured headless: 12,576 detailed, 413 nodes, 24 collision shapes; 72 triangles
## and 6 nodes for the far copy. The two heaviest things left are the TextMesh sign words (~1.9k)
## and the eighteen foliage balls (~2.2k). Cylinders go through _tube() and spheres through
## _leaf_mesh(), both cached and both built at the segment count the part actually needs -
## Landmarks._cyl() is fixed at 12 segments with the default ring count and a fresh mesh per
## call, which on its own was 11k triangles of railing posts and table legs.

# --- Site ---------------------------------------------------------------------------------
# Local coordinates: +X east, +Z south, the origin on the anchor. The shell sits at the back
# (north-west) of the plot and the two glazed elevations face +Z and +X, so the patio wraps the
# south-east corner. Everything is placed relative to `base`, one ground sample at the anchor,
# which keeps the cafe flat on a sloping block the way the observatory's plinth does.

## West face of the building shell, and the west edge of the whole site, in metres from the anchor.
const SHELL_X0 := -8.0
## East face of the shell: the glazed side elevation stands on this plane.
const SHELL_X1 := 3.0
## North (back) face of the shell.
const SHELL_Z0 := -6.0
## South face of the shell: the glazed shopfront stands on this plane.
const SHELL_Z1 := 1.0
## East edge of the patio paving (and of the site).
const PATIO_X1 := 7.0
## South edge of the patio paving (and of the site).
const PATIO_Z1 := 5.6
## How far the paving slab's top sits above the sampled ground, in metres.
const DECK_LIFT := 0.18
## Total thickness of the paving slab, so it still meets the pavement on a mild slope.
const PAD_T := 0.36
## West and north edge of the paving slab. The back and west walls stand OUTSIDE the shell
## planes by their own thickness, so the slab has to reach past them; cut to SHELL_X0 / SHELL_Z0
## the wall foot hangs over a 0.36 m drop and you can see daylight under the building.
const PAD_X0 := SHELL_X0 - WALL_T
const PAD_Z0 := SHELL_Z0 - WALL_T

# --- Shell --------------------------------------------------------------------------------

## Height of the stucco wall from the deck to the underside of the roof slab.
const WALL_H := 4.4
## Thickness of the solid stucco walls.
const WALL_T := 0.35
## Thickness of the flat roof slab.
const ROOF_T := 0.35
## How far the roof slab oversails the walls on every side.
const ROOF_OVERHANG := 0.45
## Height of the parapet standing on the roof slab.
const PARAPET_H := 0.8
## Thickness of the parapet.
const PARAPET_T := 0.18
## Width of the solid pier on the glazed corner, where the two shopfront runs stop.
const CORNER_PIER := 0.5

# --- Shopfront ----------------------------------------------------------------------------

## Height of the solid bulkhead under the shopfront glass.
const SILL_H := 0.45
## Height of the head of the shopfront glass above the deck.
const HEAD_H := 3.7
## Thickness of a glass pane.
const GLASS_T := 0.06
## Nominal width of one glazed bay; the run is divided into whole bays near this size.
const BAY_W := 2.1
## Width and depth of a mullion, transom or door stile.
const MULLION := 0.1
## Height of the horizontal transom bar that crosses every bay.
const TRANSOM_Y := 2.5
## Width of the door leaf drawn inside its bay.
const DOOR_W := 1.15
## Height of the door head rail.
const DOOR_H := 2.3
## Which bay of the front run is the entrance (0 is the west end); -1 for none.
const DOOR_BAY := 4
## How many whole bays the front run divides into. _glazed_run() derives the same number from the
## run length and BAY_W; this const is what the gate and the pool of light on the pavement line
## up with, so if BAY_W or the shell width moves, check the two still agree.
const FRONT_BAYS := 5
## Local X of the middle of the door bay.
const DOOR_X := SHELL_X0 + (DOOR_BAY + 0.5) * ((SHELL_X1 - CORNER_PIER - SHELL_X0) / FRONT_BAYS)

# --- Awning -------------------------------------------------------------------------------

## Height of the awning slab where it meets the wall.
const AWNING_Y := 3.58
## How far the front awning projects over the pavement.
const AWNING_REACH := 2.8
## How far the side awning projects.
const AWNING_REACH_SIDE := 2.2
## How much lower the awning's outer edge sits than its wall edge.
const AWNING_DROP := 0.42
## Thickness of the awning slab.
const AWNING_T := 0.14
## Height of the canvas valance hanging off the awning's outer edge.
const VALANCE_H := 0.38
## Spacing of the posts that hold the awning's outer edge up.
const POST_GAP := 3.4
## Radius of an awning post.
const POST_R := 0.055

# --- Sign ---------------------------------------------------------------------------------

## The cafe's name. Original: never a real coffee house.
const CAFE_NAME := "VERDE CAFE"
## The shorter word used on the side elevation's band.
const CAFE_WORD := "CAFE"
## Height of the painted sign band on the fascia.
const SIGN_BAND_H := 0.68
## Width of the sign band on the front elevation.
const SIGN_BAND_W := 7.4
## Cap height of the channel letters standing off the band.
const SIGN_LETTER_H := 0.5
## How coarsely TextMesh approximates the letter outlines, in font pixels. Raise it if the sign
## is still the most expensive thing here; drop it toward 0.5 if the curves ever look faceted.
const SIGN_CURVE_STEP := 2.5
## How hard the letters and the patio bulbs burn once the street lamps are on.
const SIGN_GLOW := 1.35

# --- Patio --------------------------------------------------------------------------------

## Height of the patio railing.
const RAIL_H := 0.95
## Spacing of the railing posts.
const RAIL_POST_GAP := 1.55
## Radius of a railing post.
const RAIL_R := 0.045
## Half-width of the gap left in the front railing for the patio entrance. The gap is centred on
## DOOR_X, so you step off the pavement and straight at the door rather than at a rail post.
const GATE_HALF := 1.0
const GATE_X0 := DOOR_X - GATE_HALF
const GATE_X1 := DOOR_X + GATE_HALF
## Radius of a bistro table top.
const TABLE_R := 0.42
## Height of a bistro table top.
const TABLE_H := 0.74
## Height of a chair seat.
const CHAIR_SEAT_H := 0.45
## How far a chair sits from the centre of its table.
const CHAIR_REACH := 0.92
## Radius of a parasol canopy (a square market parasol: the cone helper is four-sided).
const PARASOL_R := 1.5
## Height of the underside of a parasol canopy.
const PARASOL_H := 2.3
## Size of a planter box: width along its run, height, depth.
const PLANTER_W := 1.7
const PLANTER_H := 0.55
const PLANTER_D := 0.7
## Shrubs per planter, and the range of their radius in metres.
const PLANTER_SHRUBS := 3
const SHRUB_R := Vector2(0.32, 0.44)
## Spacing of the bulbs on the string lights under the awning edge.
const BULB_GAP := 1.0
## Height, depth and spacing of the two bike hoops by the gate.
const RACK_H := 0.78
const RACK_W := 0.62
const RACK_GAP := 0.8

# --- Street trees ---------------------------------------------------------------------------
# Landmarks._tree() plants a 4 m trunk under a 6.4 m sphere. That is sized for the observatory
# and the campus quad; in front of a single-storey shopfront it reads as a lollipop and swallows
# the sign, so the two pavement trees here are built locally and kept under the parapet.

## Radius of one crown lobe.
const TREE_CROWN_R := 1.75
## Height of the underside of the canopy: the trunk is clear below this.
const TREE_CLEAR := 2.8
## Radius of the trunk at the ground; it tapers to 70% of this at the crown.
const TREE_TRUNK_R := 0.17

# --- Night --------------------------------------------------------------------------------

## Colour of the light spilling out of the windows after dark.
const WARM := Color(1.0, 0.84, 0.58)
## Strength of the additive glow over the shopfront glass.
const WINDOW_GLOW := 1.15
## Strength of the pool of light the shopfront throws onto the patio.
const PATIO_POOL := 0.95

# --- Colours ------------------------------------------------------------------------------

## Stucco walls.
const STUCCO := Color(0.93, 0.91, 0.86)
## The deep green of the trim, the awning and the sign band.
const TRIM := Color(0.13, 0.27, 0.21)
## Lighter green for the valance piping and the planters' bands.
const TRIM_LIGHT := Color(0.22, 0.4, 0.31)
## Dark metal: railings, table frames, chairs, door furniture.
const METAL := Color(0.22, 0.23, 0.24)
## Warm timber: the counter, the menu board, the planter boxes.
const WOOD := Color(0.4, 0.28, 0.18)
## Canvas cream for the valance and the parasols.
const CANVAS := Color(0.88, 0.86, 0.8)

## Salt for the per-anchor rng, so the same corner always lays its patio out the same way.
const SEED_SALT := 0x5EDECAFE

## The shared sign-letter material, built on first use (see _sign_material()).
static var _sign_mat: ShaderMaterial = null
## The shared foliage ball (see _leaf_mesh()).
static var _leaf: SphereMesh = null


# --- Shared primitives ----------------------------------------------------------------------

## A cached cylinder. Landmarks._cyl() leaves CylinderMesh.rings at its default and builds a new
## mesh per call, which is 144 triangles and a fresh resource for every one of the twenty-odd
## railing posts. PropFactory.cylinder() builds with rings = 1 - the same silhouette for half the
## triangles - and caches by key, so one mesh serves the whole run. Keys here are all "cafe_".
static func _tube(parent: Node3D, key: String, radius: float, height: float, pos: Vector3,
		color: Color, segments: int) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = PropFactory.cylinder(key, radius, height, color, -1.0, segments)
	mi.position = pos
	parent.add_child(mi)
	return mi


## A cached foliage ball of unit radius 0.9, scaled by the caller. PropFactory.bush() is a
## 16 x 10 sphere at 352 triangles, which is a lot to spend eighteen times on shrubs 0.4 m across
## and crown lobes seen from across the road; 10 x 6 is 120 and the silhouette is the same at
## these sizes. It is a true sphere, unlike bush(), so the caller's Y scale means what it says.
static func _leaf_mesh() -> SphereMesh:
	if _leaf != null:
		return _leaf
	_leaf = SphereMesh.new()
	_leaf.radius = 0.9
	_leaf.height = 1.8
	_leaf.radial_segments = 10
	_leaf.rings = 6
	return _leaf


# --- Entry point --------------------------------------------------------------------------

static func build(anchor: Vector2, parent: Node3D, statics: StaticBody3D, plan: CityPlan, detailed: bool) -> void:
	var ground: float = plan.height_at(anchor) if plan != null else 0.0
	var base := Vector3(anchor.x, ground + DECK_LIFT, anchor.y)
	if not detailed:
		_far(parent, statics, base)
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED_SALT ^ (int(anchor.x) * 73856093) ^ (int(anchor.y) * 19349663)
	_pad(parent, statics, base)
	_shell(parent, statics, base)
	_glazed_run(parent, statics, base, true, SHELL_Z1, SHELL_X0, SHELL_X1 - CORNER_PIER, DOOR_BAY)
	_glazed_run(parent, statics, base, false, SHELL_X1, SHELL_Z0, SHELL_Z1 - CORNER_PIER, -1)
	_interior(parent, statics, base)
	_awning(parent, base, true, SHELL_Z1, SHELL_X0, SHELL_X1, AWNING_REACH)
	_awning(parent, base, false, SHELL_X1, SHELL_Z0, SHELL_Z1, AWNING_REACH_SIDE)
	_signs(parent, base)
	_patio(parent, statics, base, rng)
	_night(parent, base)
	_street(parent, base, anchor, plan, rng)


## The far copy: the silhouette only, 72 triangles in six boxes. It keeps collision on the
## slab, the shell and the roof, so a player who flies out here lands on it instead of through
## it; everything else is decoration and is dropped.
static func _far(parent: Node3D, statics: StaticBody3D, base: Vector3) -> void:
	var w := SHELL_X1 - SHELL_X0
	var d := SHELL_Z1 - SHELL_Z0
	var cx := (SHELL_X0 + SHELL_X1) * 0.5
	var cz := (SHELL_Z0 + SHELL_Z1) * 0.5
	Landmarks._box(parent, statics, Vector3(PATIO_X1 - PAD_X0, PAD_T, PATIO_Z1 - PAD_Z0),
			base + Vector3((PAD_X0 + PATIO_X1) * 0.5, -PAD_T * 0.5, (PAD_Z0 + PATIO_Z1) * 0.5), Color(0.78, 0.77, 0.74), true)
	Landmarks._box(parent, statics, Vector3(w, WALL_H, d), base + Vector3(cx, WALL_H * 0.5, cz), STUCCO, true)
	Landmarks._box(parent, statics, Vector3(w + ROOF_OVERHANG * 2.0, ROOF_T, d + ROOF_OVERHANG * 2.0),
			base + Vector3(cx, WALL_H + ROOF_T * 0.5, cz), STUCCO.darkened(0.15), true)
	Landmarks._box(parent, null, Vector3(w + ROOF_OVERHANG * 2.0, PARAPET_H, PARAPET_T),
			base + Vector3(cx, WALL_H + ROOF_T + PARAPET_H * 0.5, SHELL_Z1 + ROOF_OVERHANG), STUCCO, false)
	Landmarks._box(parent, null, Vector3(SIGN_BAND_W, SIGN_BAND_H, 0.2),
			base + Vector3(cx, (HEAD_H + WALL_H) * 0.5, SHELL_Z1 + 0.1), TRIM, false)
	var awn := Landmarks._box(parent, null, Vector3(w + 0.4, AWNING_T, AWNING_REACH),
			base + Vector3(cx, AWNING_Y - AWNING_DROP * 0.5, SHELL_Z1 + AWNING_REACH * 0.5), TRIM, false)
	awn.rotation.x = atan2(AWNING_DROP, AWNING_REACH)


# --- Ground and shell ---------------------------------------------------------------------

static func _pad(parent: Node3D, statics: StaticBody3D, base: Vector3) -> void:
	# One slab under the shell and the L of patio, so the cafe reads as a single raised corner.
	var pad := Landmarks._box(parent, statics, Vector3(PATIO_X1 - PAD_X0, PAD_T, PATIO_Z1 - PAD_Z0),
			base + Vector3((PAD_X0 + PATIO_X1) * 0.5, -PAD_T * 0.5, (PAD_Z0 + PATIO_Z1) * 0.5), Color(0.8, 0.79, 0.76), true)
	pad.material_override = PropFactory.pbr("paving", 2.4, Color(0.92, 0.9, 0.86))
	# Timber floor inside the shop, just proud of the paving.
	var floor_mi := Landmarks._box(parent, null, Vector3(SHELL_X1 - SHELL_X0, 0.06, SHELL_Z1 - SHELL_Z0),
			base + Vector3((SHELL_X0 + SHELL_X1) * 0.5, 0.03, (SHELL_Z0 + SHELL_Z1) * 0.5), WOOD.lightened(0.15), false)
	floor_mi.material_override = PropFactory.material(WOOD.lightened(0.15), 0.6)


static func _shell(parent: Node3D, statics: StaticBody3D, base: Vector3) -> void:
	var w := SHELL_X1 - SHELL_X0
	var d := SHELL_Z1 - SHELL_Z0
	var cx := (SHELL_X0 + SHELL_X1) * 0.5
	var cz := (SHELL_Z0 + SHELL_Z1) * 0.5
	var stucco := PropFactory.pbr("plaster_white", 3.2, STUCCO)
	# Back and west walls are solid; the other two elevations are the shopfront.
	var back := Landmarks._box(parent, statics, Vector3(w + WALL_T * 2.0, WALL_H, WALL_T),
			base + Vector3(cx, WALL_H * 0.5, SHELL_Z0 - WALL_T * 0.5), STUCCO, true)
	back.material_override = stucco
	var west := Landmarks._box(parent, statics, Vector3(WALL_T, WALL_H, d + WALL_T),
			base + Vector3(SHELL_X0 - WALL_T * 0.5, WALL_H * 0.5, cz - WALL_T * 0.5), STUCCO, true)
	west.material_override = stucco
	# Solid pier on the glazed corner.
	var pier := Landmarks._box(parent, statics, Vector3(CORNER_PIER, WALL_H, CORNER_PIER),
			base + Vector3(SHELL_X1 - CORNER_PIER * 0.5, WALL_H * 0.5, SHELL_Z1 - CORNER_PIER * 0.5), STUCCO, true)
	pier.material_override = stucco
	# Roof slab and parapet ring.
	var roof := Landmarks._box(parent, statics, Vector3(w + ROOF_OVERHANG * 2.0, ROOF_T, d + ROOF_OVERHANG * 2.0),
			base + Vector3(cx, WALL_H + ROOF_T * 0.5, cz), STUCCO.darkened(0.12), true)
	roof.material_override = PropFactory.pbr("concrete", 2.6, Color(0.78, 0.76, 0.73))
	var ry := WALL_H + ROOF_T + PARAPET_H * 0.5
	var rw := w + ROOF_OVERHANG * 2.0
	var rd := d + ROOF_OVERHANG * 2.0
	for dz: float in [-1.0, 1.0]:
		var band := Landmarks._box(parent, null, Vector3(rw, PARAPET_H, PARAPET_T),
				base + Vector3(cx, ry, cz + dz * (rd * 0.5 - PARAPET_T * 0.5)), STUCCO, false)
		band.material_override = stucco
	for dx: float in [-1.0, 1.0]:
		var band2 := Landmarks._box(parent, null, Vector3(PARAPET_T, PARAPET_H, rd - PARAPET_T * 2.0),
				base + Vector3(cx + dx * (rw * 0.5 - PARAPET_T * 0.5), ry, cz), STUCCO, false)
		band2.material_override = stucco
	# Rooftop kit: two condensers and a flue, visible because the player can jump this high.
	var top := WALL_H + ROOF_T
	for i in 2:
		Landmarks._box(parent, null, Vector3(1.5, 0.9, 1.2), base + Vector3(cx - 2.4 + i * 3.0, top + 0.45, cz - 1.2), Color(0.62, 0.63, 0.65), false)
		Landmarks._cyl(parent, null, 0.5, 0.12, base + Vector3(cx - 2.4 + i * 3.0, top + 0.95, cz - 1.2), Color(0.45, 0.46, 0.48))
	Landmarks._cyl(parent, null, 0.22, 1.4, base + Vector3(cx + 3.4, top + 0.7, cz + 1.4), Color(0.55, 0.56, 0.58))


# --- Shopfront ----------------------------------------------------------------------------

## A local offset on a glazed run: `s` is the distance along the run, `y` the height above the
## deck, `off` the offset out of the wall plane (positive is outward, towards the street).
static func _run_pos(axis_x: bool, plane: float, s: float, y: float, off: float) -> Vector3:
	return Vector3(s, y, plane + off) if axis_x else Vector3(plane + off, y, s)


## A box size on a glazed run: `along` runs with the wall, `thick` is across it.
static func _run_size(axis_x: bool, along: float, h: float, thick: float) -> Vector3:
	return Vector3(along, h, thick) if axis_x else Vector3(thick, h, along)


## One glazed elevation, divided into whole bays near BAY_W: bulkhead, pane, mullions, two
## transoms, the fascia over the head and, in `door_bay`, a glazed door.
static func _glazed_run(parent: Node3D, statics: StaticBody3D, base: Vector3, axis_x: bool,
		plane: float, a: float, b: float, door_bay: int) -> void:
	var length := b - a
	var bays: int = maxi(1, int(round(length / BAY_W)))
	var bay := length / float(bays)
	var mid := (a + b) * 0.5
	var glass := PropFactory.storefront_glass()
	var frame := PropFactory.material(TRIM, 0.4)
	var stucco := PropFactory.pbr("plaster_white", 3.2, STUCCO)
	for i in bays:
		var c := a + (i + 0.5) * bay
		var is_door := i == door_bay
		var foot := 0.04 if is_door else SILL_H
		if not is_door:
			var sill := Landmarks._box(parent, null, _run_size(axis_x, bay, SILL_H, 0.3),
					base + _run_pos(axis_x, plane, c, SILL_H * 0.5, -0.05), STUCCO, false)
			sill.material_override = stucco
			var nose := Landmarks._box(parent, null, _run_size(axis_x, bay, 0.07, 0.4),
					base + _run_pos(axis_x, plane, c, SILL_H, 0.0), STUCCO.darkened(0.1), false)
			nose.material_override = stucco
		var pane := Landmarks._box(parent, null, _run_size(axis_x, bay - MULLION, HEAD_H - foot, GLASS_T),
				base + _run_pos(axis_x, plane, c, (foot + HEAD_H) * 0.5, 0.0), Color(0.25, 0.32, 0.38), false)
		pane.material_override = glass
		if is_door:
			_door(parent, base, axis_x, plane, c, frame)
	# Mullions at every bay edge, ends included.
	for i in bays + 1:
		var m := Landmarks._box(parent, null, _run_size(axis_x, MULLION, HEAD_H, MULLION * 1.7),
				base + _run_pos(axis_x, plane, a + i * bay, HEAD_H * 0.5, 0.02), TRIM, false)
		m.material_override = frame
	# Head and mid transoms across the whole run.
	for ty: float in [TRANSOM_Y, HEAD_H - MULLION * 0.5]:
		var t := Landmarks._box(parent, null, _run_size(axis_x, length, MULLION, MULLION * 1.7),
				base + _run_pos(axis_x, plane, mid, ty, 0.02), TRIM, false)
		t.material_override = frame
	# Fascia over the head, flush with the wall face, and the collision that stops the player
	# walking through the glass.
	# Stops at the corner pier rather than running through it: the pier is solid to the roof, so
	# extending both fascias over the corner put two coplanar faces in the same 0.5 m patch and
	# the corner flickered.
	var fascia := Landmarks._box(parent, null, _run_size(axis_x, length, WALL_H - HEAD_H, WALL_T),
			base + _run_pos(axis_x, plane, mid, (HEAD_H + WALL_H) * 0.5, -WALL_T * 0.5), STUCCO, false)
	fascia.material_override = stucco
	if statics:
		Landmarks._shape(statics, _run_size(axis_x, length, WALL_H, 0.25), base + _run_pos(axis_x, plane, mid, WALL_H * 0.5, 0.0))


## The door leaf drawn inside its glazed bay: stiles, head rail, kick plate and a pull handle.
static func _door(parent: Node3D, base: Vector3, axis_x: bool, plane: float, c: float, frame: Material) -> void:
	for side: float in [-1.0, 1.0]:
		var stile := Landmarks._box(parent, null, _run_size(axis_x, MULLION, DOOR_H, MULLION * 1.6),
				base + _run_pos(axis_x, plane, c + side * DOOR_W * 0.5, DOOR_H * 0.5, 0.03), TRIM, false)
		stile.material_override = frame
	var head := Landmarks._box(parent, null, _run_size(axis_x, DOOR_W, MULLION, MULLION * 1.6),
			base + _run_pos(axis_x, plane, c, DOOR_H, 0.03), TRIM, false)
	head.material_override = frame
	var kick := Landmarks._box(parent, null, _run_size(axis_x, DOOR_W, 0.28, MULLION * 1.6),
			base + _run_pos(axis_x, plane, c, 0.14, 0.03), TRIM, false)
	kick.material_override = frame
	Landmarks._cyl(parent, null, 0.025, 1.0, base + _run_pos(axis_x, plane, c + DOOR_W * 0.5 - 0.22, 1.05, 0.12), Color(0.72, 0.68, 0.58))


## What the player sees through the glass: counter, back bar, machine, pendants and two tables.
static func _interior(parent: Node3D, statics: StaticBody3D, base: Vector3) -> void:
	var counter := Landmarks._box(parent, statics, Vector3(5.2, 1.05, 0.72), base + Vector3(-4.6, 0.55, -3.2), WOOD, true)
	counter.material_override = PropFactory.material(WOOD, 0.55)
	Landmarks._box(parent, null, Vector3(5.4, 0.06, 0.86), base + Vector3(-4.6, 1.1, -3.2), Color(0.18, 0.19, 0.2), false)
	# Back bar and three shelves against the north wall.
	Landmarks._box(parent, null, Vector3(6.4, 2.3, 0.3), base + Vector3(-4.6, 1.15, -5.65), TRIM, false)
	for i in 3:
		Landmarks._box(parent, null, Vector3(6.0, 0.05, 0.42), base + Vector3(-4.6, 1.1 + i * 0.5, -5.42), WOOD.lightened(0.2), false)
	# Espresso machine and a grinder on the counter.
	Landmarks._box(parent, null, Vector3(1.1, 0.5, 0.6), base + Vector3(-5.6, 1.38, -3.2), Color(0.72, 0.73, 0.75), false)
	Landmarks._cyl(parent, null, 0.16, 0.55, base + Vector3(-4.4, 1.4, -3.2), Color(0.3, 0.31, 0.33))
	# Pendant lamps over the counter: unshaded bulbs, lit day and night, seen through the glass.
	for i in 3:
		var px := -6.2 + i * 1.6
		Landmarks._cyl(parent, null, 0.02, 1.2, base + Vector3(px, WALL_H - 0.6, -2.6), METAL)
		var shade := Landmarks._cyl(parent, null, 0.22, 0.22, base + Vector3(px, WALL_H - 1.3, -2.6), TRIM)
		shade.material_override = PropFactory.material(TRIM, 0.35)
		var bulb := Landmarks._box(parent, null, Vector3(0.14, 0.1, 0.14), base + Vector3(px, WALL_H - 1.44, -2.6), WARM, false)
		bulb.material_override = WeaponFX.unshaded(Color(1.0, 0.9, 0.7))
	for at: Vector2 in [Vector2(0.4, -1.6), Vector2(-1.6, -0.2)]:
		_table(parent, null, base, at, 0.0)


# --- Awning -------------------------------------------------------------------------------

## The deep awning over the pavement: a sloped slab, a canvas valance, rafters and posts.
static func _awning(parent: Node3D, base: Vector3, axis_x: bool, plane: float, a: float, b: float, reach: float) -> void:
	var length := b - a
	var mid := (a + b) * 0.5
	var slope := atan2(AWNING_DROP, reach)
	var slab := Landmarks._box(parent, null, _run_size(axis_x, length + 0.4, AWNING_T, reach),
			base + _run_pos(axis_x, plane, mid, AWNING_Y - AWNING_DROP * 0.5, reach * 0.5), TRIM, false)
	slab.material_override = PropFactory.material(TRIM, 0.85)
	# The outer edge has to drop, which is +X about the run for a front awning and -Z for a side one.
	if axis_x:
		slab.rotation.x = slope
	else:
		slab.rotation.z = -slope
	var edge_y := AWNING_Y - AWNING_DROP
	var valance := Landmarks._box(parent, null, _run_size(axis_x, length + 0.4, VALANCE_H, 0.08),
			base + _run_pos(axis_x, plane, mid, edge_y - VALANCE_H * 0.5, reach), CANVAS, false)
	valance.material_override = PropFactory.material(CANVAS, 0.9)
	Landmarks._box(parent, null, _run_size(axis_x, length + 0.4, 0.09, 0.14),
			base + _run_pos(axis_x, plane, mid, edge_y, reach), TRIM_LIGHT, false)
	# Rafters under the canvas and posts at the outer edge.
	var posts: int = maxi(2, int(round(length / POST_GAP)) + 1)
	for i in posts:
		var s := a + length * float(i) / float(posts - 1)
		var raf := Landmarks._box(parent, null, _run_size(axis_x, 0.08, 0.1, reach),
				base + _run_pos(axis_x, plane, s, AWNING_Y - AWNING_DROP * 0.5 - 0.11, reach * 0.5), TRIM.darkened(0.2), false)
		if axis_x:
			raf.rotation.x = slope
		else:
			raf.rotation.z = -slope
		_tube(parent, "cafe_awning_post", POST_R, edge_y - VALANCE_H,
				base + _run_pos(axis_x, plane, s, (edge_y - VALANCE_H) * 0.5, reach - 0.12), METAL, 6)


# --- Signs --------------------------------------------------------------------------------

## The painted band on each fascia with channel letters standing off it. The letters use the
## signage neon material, so they are paint by day and glow once lamp_factor comes up.
static func _signs(parent: Node3D, base: Vector3) -> void:
	var front_x := (SHELL_X0 + SHELL_X1 - CORNER_PIER) * 0.5
	var band_y := (HEAD_H + WALL_H) * 0.5
	var band := Landmarks._box(parent, null, Vector3(SIGN_BAND_W, SIGN_BAND_H, 0.16), base + Vector3(front_x, band_y, SHELL_Z1 + 0.08), TRIM, false)
	band.material_override = PropFactory.material(TRIM, 0.45)
	_letters(parent, CAFE_NAME, base + Vector3(front_x, band_y, SHELL_Z1 + 0.22), 0.0)
	var side_z := (SHELL_Z0 + SHELL_Z1 - CORNER_PIER) * 0.5
	var band2 := Landmarks._box(parent, null, Vector3(0.16, SIGN_BAND_H, 4.0), base + Vector3(SHELL_X1 + 0.08, band_y, side_z), TRIM, false)
	band2.material_override = PropFactory.material(TRIM, 0.45)
	_letters(parent, CAFE_WORD, base + Vector3(SHELL_X1 + 0.22, band_y, side_z), PI * 0.5)


## Channel letters: matte cream paint by day, warm once `lamp_factor` comes up, which is what
## DayNight sets to max(night_factor, weather_darken * 0.85).
##
## This is shaders/sign_letters.gdshader, the same shader the city puts on every shop fascia, so
## the cafe's name brightens with the street rather than on its own curve. It is loaded by path
## rather than through Signage.text_mesh(): naming `Signage` pulls in `CityChunk`, which pulls in
## the `WorldState` autoload, and `--check-only` cannot resolve an autoload, so the file would
## stop compiling on its own. A resource path has no such dependency. Built once and shared by
## both bands.
static func _sign_material() -> ShaderMaterial:
	if _sign_mat != null:
		return _sign_mat
	_sign_mat = ShaderMaterial.new()
	_sign_mat.shader = load("res://shaders/sign_letters.gdshader")
	_sign_mat.set_shader_parameter("ink", Color(0.94, 0.92, 0.86))
	_sign_mat.set_shader_parameter("glow", SIGN_GLOW)
	return _sign_mat


static func _letters(parent: Node3D, txt: String, at: Vector3, yaw: float) -> void:
	var tm := TextMesh.new()
	tm.text = txt
	tm.font_size = 48
	tm.pixel_size = SIGN_LETTER_H / 48.0
	# Real channel letters stand off the band, so give them depth rather than making a decal.
	tm.depth = 0.07
	# Default 0.5 px is font-editor precision. At 0.5 m cap height on a fascia read from the
	# pavement it buys nothing and costs about 2k triangles across the two words.
	tm.curve_step = SIGN_CURVE_STEP
	tm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tm.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tm.material = _sign_material()
	var mi := MeshInstance3D.new()
	mi.mesh = tm
	mi.transform = Transform3D(Basis(Vector3.UP, yaw), at)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


# --- Patio --------------------------------------------------------------------------------

static func _patio(parent: Node3D, statics: StaticBody3D, base: Vector3, rng: RandomNumberGenerator) -> void:
	# Railing: the front run with a gap for the entrance, the east run, and a short return
	# along the north edge of the side patio.
	_rail(parent, statics, base, Vector2(SHELL_X0, PATIO_Z1), Vector2(GATE_X0, PATIO_Z1))
	_rail(parent, statics, base, Vector2(GATE_X1, PATIO_Z1), Vector2(PATIO_X1, PATIO_Z1))
	_rail(parent, statics, base, Vector2(PATIO_X1, SHELL_Z0), Vector2(PATIO_X1, PATIO_Z1))
	_rail(parent, statics, base, Vector2(SHELL_X1, SHELL_Z0), Vector2(PATIO_X1, SHELL_Z0))
	# Tables: a row under the awning, a row out in the sun with parasols, two on the side patio.
	# The east end of both rows stops short of DOOR_X, so the gate opens onto a clear walk in to
	# the door instead of onto the back of a chair.
	var shaded: Array[Vector2] = [Vector2(-6.6, 2.55), Vector2(-3.9, 2.55), Vector2(-1.2, 2.55)]
	var sunny: Array[Vector2] = [Vector2(-6.2, 4.55), Vector2(-3.3, 4.55), Vector2(-0.4, 4.55)]
	var side: Array[Vector2] = [Vector2(5.7, -3.9), Vector2(5.7, -1.0)]
	for at: Vector2 in shaded:
		_bistro(parent, statics, base, at, rng.randf_range(-0.25, 0.25), false, rng)
	for at: Vector2 in sunny:
		_bistro(parent, statics, base, at, rng.randf_range(-0.25, 0.25), true, rng)
	for i in side.size():
		_bistro(parent, statics, base, side[i], PI * 0.5 + rng.randf_range(-0.25, 0.25), i == 0, rng)
	# Planters along the rails. The east one used to sit at x 2.5, which put a 1.7 m box with
	# collision on it squarely across the gate: the patio could not be walked into at all.
	_planter(parent, statics, base, Vector2(-7.0, 5.05), true, rng)
	_planter(parent, statics, base, Vector2(5.6, 5.05), true, rng)
	_planter(parent, statics, base, Vector2(6.35, -5.0), false, rng)
	_planter(parent, statics, base, Vector2(6.35, 3.0), false, rng)
	_menu_board(parent, base, Vector2(2.6, 2.3), -0.5)
	_bike_rack(parent, base, Vector2(GATE_X1 + 1.4, PATIO_Z1 - 0.75))
	# Bulbs on the outer edge of both awnings, the patio's own light after dark.
	_string_lights(parent, base, true, SHELL_Z1, SHELL_X0, SHELL_X1, AWNING_REACH)
	_string_lights(parent, base, false, SHELL_X1, SHELL_Z0, SHELL_Z1, AWNING_REACH_SIDE)


## A straight railing run: posts on RAIL_POST_GAP centres, a top rail and a mid rail, and one
## collision box for the whole run. Axis-aligned; `from` and `to` are local XZ.
static func _rail(parent: Node3D, statics: StaticBody3D, base: Vector3, from_v: Vector2, to_v: Vector2) -> void:
	var delta := to_v - from_v
	var axis_x := absf(delta.x) >= absf(delta.y)
	var length := absf(delta.x) if axis_x else absf(delta.y)
	if length < 0.4:
		return
	var mid := (from_v + to_v) * 0.5
	var posts: int = maxi(2, int(round(length / RAIL_POST_GAP)) + 1)
	for i in posts:
		var t := float(i) / float(posts - 1)
		var p := from_v.lerp(to_v, t)
		_tube(parent, "cafe_rail_post", RAIL_R, RAIL_H, base + Vector3(p.x, RAIL_H * 0.5, p.y), METAL, 6)
	for ry: float in [RAIL_H - 0.03, RAIL_H * 0.5]:
		var bar := Landmarks._box(parent, null, Vector3(length, 0.06, 0.05) if axis_x else Vector3(0.05, 0.06, length),
				base + Vector3(mid.x, ry, mid.y), METAL, false)
		bar.material_override = PropFactory.material(METAL, 0.45)
	if statics:
		Landmarks._shape(statics, Vector3(length, RAIL_H, 0.12) if axis_x else Vector3(0.12, RAIL_H, length),
				base + Vector3(mid.x, RAIL_H * 0.5, mid.y))


## One round bistro table with two chairs and, optionally, a square market parasol.
static func _bistro(parent: Node3D, statics: StaticBody3D, base: Vector3, at: Vector2, yaw: float,
		parasol: bool, rng: RandomNumberGenerator) -> void:
	_table(parent, statics, base, at, yaw)
	var dir := Vector2(sin(yaw), cos(yaw)) * CHAIR_REACH
	_chair(parent, base, at + dir, yaw + PI)
	_chair(parent, base, at - dir, yaw)
	if not parasol:
		return
	# The pole has to clear the canopy apex (PARASOL_H + 0.45 with _cone centred on its own
	# midpoint) or the finial sits inside the shade where nobody can see it.
	var pole_h := PARASOL_H + 0.55
	_tube(parent, "cafe_parasol_pole", 0.04, pole_h, base + Vector3(at.x, pole_h * 0.5, at.y), Color(0.75, 0.72, 0.66), 6)
	var shade := CANVAS if rng.randf() < 0.5 else TRIM_LIGHT
	Landmarks._cone(parent, PARASOL_R, 0.45, base + Vector3(at.x, PARASOL_H + 0.22, at.y), shade)
	Landmarks._box(parent, null, Vector3(0.09, 0.16, 0.09), base + Vector3(at.x, pole_h, at.y), METAL, false)
	_cups(parent, base, at, rng)


static func _table(parent: Node3D, statics: StaticBody3D, base: Vector3, at: Vector2, yaw: float) -> void:
	var top := _tube(parent, "cafe_table_top", TABLE_R, 0.05, base + Vector3(at.x, TABLE_H, at.y), Color(0.86, 0.84, 0.79), 14)
	top.material_override = PropFactory.material(Color(0.86, 0.84, 0.79), 0.35)
	top.rotation.y = yaw
	_tube(parent, "cafe_table_stem", 0.05, TABLE_H, base + Vector3(at.x, TABLE_H * 0.5, at.y), METAL, 8)
	_tube(parent, "cafe_table_foot", 0.28, 0.04, base + Vector3(at.x, 0.02, at.y), METAL, 10)
	if statics:
		Landmarks._shape(statics, Vector3(TABLE_R * 1.9, TABLE_H, TABLE_R * 1.9), base + Vector3(at.x, TABLE_H * 0.5, at.y))


## A metal bistro chair, built under a pivot so the whole thing can face `yaw`.
static func _chair(parent: Node3D, base: Vector3, at: Vector2, yaw: float) -> void:
	var pivot := Node3D.new()
	pivot.position = base + Vector3(at.x, 0.0, at.y)
	pivot.rotation.y = yaw
	parent.add_child(pivot)
	Landmarks._box(pivot, null, Vector3(0.44, 0.05, 0.42), Vector3(0.0, CHAIR_SEAT_H, 0.0), METAL, false)
	for dx: float in [-1.0, 1.0]:
		for dz: float in [-1.0, 1.0]:
			Landmarks._box(pivot, null, Vector3(0.035, CHAIR_SEAT_H, 0.035), Vector3(dx * 0.18, CHAIR_SEAT_H * 0.5, dz * 0.17), METAL, false)
		var upright := Landmarks._box(pivot, null, Vector3(0.04, 0.5, 0.04), Vector3(dx * 0.19, CHAIR_SEAT_H + 0.25, -0.2), METAL, false)
		upright.rotation.x = -0.1
	for i in 2:
		var slat := Landmarks._box(pivot, null, Vector3(0.42, 0.08, 0.035), Vector3(0.0, CHAIR_SEAT_H + 0.24 + i * 0.2, -0.22 - i * 0.02), METAL, false)
		slat.rotation.x = -0.1


## A timber planter box with clipped shrubs.
##
## The shrubs are scaled copies of PropFactory.bush(), a 352-triangle sphere, not
## PropFactory.model_shrub(). The model is a scanned garden shrub: 5-9k triangles of sparse bare
## branches that read as a dead twig at the 1.5 m a planter box is seen from, and two of them
## were 40% of this landmark's whole budget. Three overlapping spheres cost a fifteenth of that
## and read as the clipped box hedge a shopfront planter actually holds.
static func _planter(parent: Node3D, statics: StaticBody3D, base: Vector3, at: Vector2, axis_x: bool,
		rng: RandomNumberGenerator) -> void:
	var size := Vector3(PLANTER_W, PLANTER_H, PLANTER_D) if axis_x else Vector3(PLANTER_D, PLANTER_H, PLANTER_W)
	var box := Landmarks._box(parent, statics, size, base + Vector3(at.x, PLANTER_H * 0.5, at.y), WOOD, true)
	box.material_override = PropFactory.material(WOOD, 0.75)
	var band := Landmarks._box(parent, null, size * Vector3(1.04, 0.12, 1.04), base + Vector3(at.x, PLANTER_H - 0.06, at.y), TRIM_LIGHT, false)
	band.material_override = PropFactory.material(TRIM_LIGHT, 0.6)
	Landmarks._box(parent, null, size * Vector3(0.9, 0.1, 0.9), base + Vector3(at.x, PLANTER_H - 0.01, at.y), Color(0.24, 0.2, 0.16), false)
	var run := PLANTER_W - 0.6
	for i in PLANTER_SHRUBS:
		var t := (float(i) / float(PLANTER_SHRUBS - 1) - 0.5) * run
		var off := Vector3(t, 0.0, 0.0) if axis_x else Vector3(0.0, 0.0, t)
		var bush := MeshInstance3D.new()
		bush.mesh = _leaf_mesh()
		# The ball is unit radius 0.9, so the scale is the radius we want over 0.9; squashed on Y
		# because a clipped shrub is wider than it is tall.
		var r := rng.randf_range(SHRUB_R.x, SHRUB_R.y)
		var sc := Vector3(r, r * 0.68, r) / 0.9
		bush.transform = Transform3D(Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(sc), base + Vector3(at.x, PLANTER_H + r * 0.42, at.y) + off)
		bush.material_override = PropFactory.material(Color(0.24, 0.44, 0.22).lightened(rng.randf_range(0.0, 0.18)), 0.9)
		parent.add_child(bush)


## Nought to two cups and saucers left on a table. Empty tables read as a showroom; this is the
## cheapest thing on the whole build that says somebody was just sitting here. Both meshes are
## cached by PropFactory.cylinder(), so all ten tables share two 8-sided primitives.
static func _cups(parent: Node3D, base: Vector3, at: Vector2, rng: RandomNumberGenerator) -> void:
	for i in rng.randi_range(0, 2):
		var a := rng.randf_range(0.0, TAU)
		var d := rng.randf_range(0.10, TABLE_R - 0.14)
		var p := base + Vector3(at.x + cos(a) * d, TABLE_H + 0.035, at.y + sin(a) * d)
		var saucer := MeshInstance3D.new()
		saucer.mesh = PropFactory.cylinder("cafe_saucer", 0.075, 0.014, Color(0.93, 0.92, 0.89), -1.0, 8)
		saucer.position = p
		parent.add_child(saucer)
		var cup := MeshInstance3D.new()
		cup.mesh = PropFactory.cylinder("cafe_cup", 0.036, 0.085, Color(0.95, 0.94, 0.92), 0.043, 8)
		cup.position = p + Vector3(0.0, 0.05, 0.0)
		parent.add_child(cup)


## Two hoop stands by the gate. Five pieces, and a pavement without one does not read as the
## Westside.
static func _bike_rack(parent: Node3D, base: Vector3, at: Vector2) -> void:
	var hoop := PropFactory.cylinder("cafe_rack_leg", 0.028, RACK_H, Color(0.3, 0.31, 0.32), -1.0, 6)
	for i in 2:
		var x := at.x + (i - 0.5) * RACK_GAP
		for dz: float in [-1.0, 1.0]:
			var leg := MeshInstance3D.new()
			leg.mesh = hoop
			leg.position = base + Vector3(x, RACK_H * 0.5, at.y + dz * RACK_W * 0.5)
			parent.add_child(leg)
		var top := Landmarks._box(parent, null, Vector3(0.05, 0.05, RACK_W), base + Vector3(x, RACK_H, at.y), METAL, false)
		top.material_override = PropFactory.material(METAL, 0.45)


## A string of bulbs slung along the outer edge of an awning. The bulbs share _sign_material(),
## so they are cream beads by day and come up warm with the street lamps, which gives the patio
## a light of its own after dark for about 130 triangles a run and no OmniLight.
static func _string_lights(parent: Node3D, base: Vector3, axis_x: bool, plane: float, a: float,
		b: float, reach: float) -> void:
	var length := b - a
	var mid := (a + b) * 0.5
	var y := AWNING_Y - AWNING_DROP - VALANCE_H - 0.05
	var wire := Landmarks._box(parent, null, _run_size(axis_x, length, 0.025, 0.025),
			base + _run_pos(axis_x, plane, mid, y, reach - 0.05), Color(0.12, 0.12, 0.13), false)
	wire.material_override = PropFactory.material(Color(0.12, 0.12, 0.13), 0.6)
	var lamps: int = maxi(2, int(round(length / BULB_GAP)))
	for i in lamps:
		var t := a + (i + 0.5) * (length / float(lamps))
		var bulb := Landmarks._box(parent, null, Vector3(0.075, 0.105, 0.075),
				base + _run_pos(axis_x, plane, t, y - 0.085, reach - 0.05), CANVAS, false)
		bulb.material_override = _sign_material()


## The A-frame chalk board by the door.
static func _menu_board(parent: Node3D, base: Vector3, at: Vector2, yaw: float) -> void:
	var pivot := Node3D.new()
	pivot.position = base + Vector3(at.x, 0.0, at.y)
	pivot.rotation.y = yaw
	parent.add_child(pivot)
	for dz: float in [-1.0, 1.0]:
		var leaf := Landmarks._box(pivot, null, Vector3(0.72, 1.05, 0.05), Vector3(0.0, 0.53, dz * 0.17), WOOD, false)
		leaf.rotation.x = -dz * 0.16
		var slate := Landmarks._box(pivot, null, Vector3(0.6, 0.86, 0.02), Vector3(0.0, 0.55, dz * 0.2), Color(0.12, 0.13, 0.12), false)
		slate.rotation.x = -dz * 0.16
	for i in 3:
		var chalk := Landmarks._box(pivot, null, Vector3(0.36 - i * 0.06, 0.03, 0.01), Vector3(0.0, 0.82 - i * 0.16, 0.22), CANVAS, false)
		chalk.rotation.x = -0.16
		chalk.material_override = WeaponFX.unshaded(Color(0.9, 0.9, 0.86))


# --- Night --------------------------------------------------------------------------------

## An additive night quad. `yaw` aims its face (0 is +Z, PI/2 is +X), `pitch` -PI/2 lays it flat
## facing up. `tight` picks the lamp-face falloff instead of the wide pool.
static func _glow(parent: Node3D, at: Vector3, size: Vector2, yaw: float, pitch: float, strength: float, tight: bool) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = PropFactory.lamp_face(WARM, strength) if tight else PropFactory.light_pool(WARM, strength)
	var scale_basis := Basis(Vector3(size.x, 0.0, 0.0), Vector3(0.0, size.y, 0.0), Vector3(0.0, 0.0, 1.0))
	mi.transform = Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch) * scale_basis, at)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


static func _night(parent: Node3D, base: Vector3) -> void:
	var front_len := SHELL_X1 - CORNER_PIER - SHELL_X0
	var front_x := (SHELL_X0 + SHELL_X1 - CORNER_PIER) * 0.5
	var side_len := SHELL_Z1 - CORNER_PIER - SHELL_Z0
	var side_z := (SHELL_Z0 + SHELL_Z1 - CORNER_PIER) * 0.5
	var glass_mid := (SILL_H + HEAD_H) * 0.5
	# Warm light on the glass itself, just outside the pane so it adds over it.
	_glow(parent, base + Vector3(front_x, glass_mid, SHELL_Z1 + 0.09), Vector2(front_len, HEAD_H - SILL_H), 0.0, 0.0, WINDOW_GLOW, true)
	_glow(parent, base + Vector3(SHELL_X1 + 0.09, glass_mid, side_z), Vector2(side_len, HEAD_H - SILL_H), PI * 0.5, 0.0, WINDOW_GLOW, true)
	# The pool that light throws onto the patio under the awning.
	_glow(parent, base + Vector3(front_x, 0.05, SHELL_Z1 + AWNING_REACH * 0.45), Vector2(front_len + 2.0, AWNING_REACH * 1.6), 0.0, -PI * 0.5, PATIO_POOL, false)
	_glow(parent, base + Vector3(SHELL_X1 + AWNING_REACH_SIDE * 0.45, 0.05, side_z), Vector2(AWNING_REACH_SIDE * 1.6, side_len + 2.0), 0.0, -PI * 0.5, PATIO_POOL, false)
	# A tighter halo behind the sign band and a little wash on the door.
	_glow(parent, base + Vector3(front_x, (HEAD_H + WALL_H) * 0.5, SHELL_Z1 + 0.18), Vector2(SIGN_BAND_W + 1.2, SIGN_BAND_H + 0.9), 0.0, 0.0, 0.7, true)
	_glow(parent, base + Vector3(DOOR_X, 0.05, SHELL_Z1 + 1.1), Vector2(3.0, 3.0), 0.0, -PI * 0.5, 0.8, false)


# --- Street -------------------------------------------------------------------------------

## Two street trees on the kerb. They stand on the real pavement, not on the cafe's slab, so
## they take their own ground sample.
static func _street(parent: Node3D, base: Vector3, anchor: Vector2, plan: CityPlan, rng: RandomNumberGenerator) -> void:
	for spot: Vector2 in [Vector2(-5.2, 6.6), Vector2(7.8, -1.4)]:
		var world := anchor + spot
		var y: float = plan.height_at(world) if plan != null else base.y - DECK_LIFT
		_street_tree(parent, Vector3(world.x, y, world.y), rng)


## One pavement tree: a tapered trunk and three overlapping crowns, about 5 m to the top, which
## keeps it under the parapet and off the sign. Three scaled copies of the shared bush sphere
## cost roughly 1.1k triangles and read as a canopy where one big sphere reads as a lollipop.
static func _street_tree(parent: Node3D, at: Vector3, rng: RandomNumberGenerator) -> void:
	var trunk := MeshInstance3D.new()
	trunk.mesh = PropFactory.cylinder("cafe_tree_trunk", TREE_TRUNK_R, TREE_CLEAR + 0.7,
			Color(0.37, 0.29, 0.22), TREE_TRUNK_R * 0.7, 8)
	trunk.position = at + Vector3(0.0, (TREE_CLEAR + 0.7) * 0.5, 0.0)
	parent.add_child(trunk)
	var lean := rng.randf_range(0.0, TAU)
	for i in 3:
		var r := TREE_CROWN_R * rng.randf_range(0.74, 1.0)
		var a := lean + TAU * float(i) / 3.0
		var off := Vector3(cos(a), rng.randf_range(-0.12, 0.3), sin(a)) * TREE_CROWN_R * 0.45
		var lobe := MeshInstance3D.new()
		lobe.mesh = _leaf_mesh()
		lobe.transform = Transform3D(Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(Vector3(r, r * 0.7, r) / 0.9),
				at + Vector3(0.0, TREE_CLEAR + 0.75, 0.0) + off)
		lobe.material_override = PropFactory.material(Color(0.23, 0.42, 0.21).lightened(rng.randf_range(0.0, 0.14)), 0.95)
		parent.add_child(lobe)
