class_name LandmarkMasjidAlNoor
extends RefCounted
## Masjid Al Noor ("the mosque of light"): a neighbourhood mosque on the South Bay flats, about
## 40 m across and 58 m deep including its walled forecourt. A square prayer hall carries a
## square-to-octagon transition, an octagonal drum with eight clerestory lanterns, and one large
## dome. A single slender minaret with a balcony and a small capped roof stands where the
## entrance porch meets the courtyard wall. A five-bay porch of two-centred (pointed) arches
## fronts the hall, and arcaded riwaqs run down both sides of the forecourt to a low octagonal
## ablution fountain at its centre. The hall is open: you can walk in through the porch.
##
## The design is original and is not modelled on any existing mosque. There is no figurative
## imagery of any kind and no calligraphy: the ornament is geometry only - a stepped merlon
## parapet, a tiled band of diamonds under the eaves, and crescent finials on the dome, on the
## minaret cap and on the fountain. The single word of lettering is NOOR on the gate pylon, drawn
## with Landmarks._text(); that FONT only holds R U A N D O W, and NOOR fits it exactly.
##
## Local frame: +X east, +Z south, origin on the anchor at the centre of the prayer hall, y = 0
## at the top of the podium. The entrance and the forecourt face +Z (south); the mihrab is on the
## -Z (north) wall, which is roughly the qibla direction from this coast.
##
## Triangle budget, counted off the built scene: 26.7k for the detailed build (1.8k meshes, 105
## collision shapes) - roughly 8k of it in the three arcades and their arch bands, 4k in the
## merlon parapets, 4k in the arched windows and lanterns, 1.4k in the six courtyard trees - and
## 864 for the far copy, which is the podium, the hall block, the drum, the dome and the minaret.

## Seed salt, so the courtyard planting and paving jitter is the same every time the chunk
## streams back in. Never call the global randf() / randi() here.
const SEED_SALT := 0x4E4F4F52

# --- Site -------------------------------------------------------------------------------------

## How far the podium top sits above the ground sampled at the anchor, in metres.
const PODIUM_LIFT := 0.24
## Thickness of the podium slab, so it still meets the pavement on a mild slope, in metres.
const PODIUM_T := 0.55
## Half the width of the walled site (the site is 2 x this across), in metres.
const SITE_X := 18.0
## Half the width of the square prayer hall, in metres: the hall is 28 x 28.
const HALL_HALF := 14.0
## Depth of the entrance porch in front of the hall, in metres.
const PORCH_D := 5.5
## South face of the hall, where the porch starts, in metres from the anchor.
const PORCH_Z0 := HALL_HALF
## Front plane of the porch arcade and the north edge of the forecourt, in metres.
const PORCH_Z1 := HALL_HALF + PORCH_D
## South edge of the forecourt, where the gate wall stands, in metres.
const COURT_Z1 := 42.0
## North edge of the site behind the qibla wall, in metres (negative: it is north of the anchor).
## It has to clear the mihrab bay, which pushes about 2.8 m out of that wall.
const SITE_Z0 := -20.0

# --- Prayer hall ------------------------------------------------------------------------------

## Height from the podium to the top of the hall roof slab, in metres.
const WALL_H := 10.0
## Thickness of the hall roof slab, in metres.
const ROOF_T := 0.8
## Underside of the roof slab, which is the top of the hall walls, in metres.
const WALL_TOP := WALL_H - ROOF_T
## Thickness of the solid stucco hall walls, in metres.
const WALL_T := 0.6
## Clear width of the doorway in the south wall, in metres.
const DOOR_W := 3.6
## Height of the rectangular hole left in the wall for the doorway, in metres. It has to clear
## the apex of the door arch, which the spandrel boxes then fill in to.
const DOOR_H := 6.9
## Springing height of the door arch, in metres.
const DOOR_SPRING := 4.4
## Height of the solid parapet band standing on the roof slab, in metres.
const PARAPET_H := 0.9
## Half the square opening left in the roof and the transition block under the dome, in metres.
const OCULUS_HALF := 9.0

# --- Parapet and tile band --------------------------------------------------------------------

## Spacing between stepped merlons along a parapet, in metres.
const MERLON_STEP := 1.5
## Width of the lower block of a merlon, in metres.
const MERLON_W := 0.78
## Height of the lower block of a merlon; the step on top is 0.55 of this, in metres.
const MERLON_H := 0.52
## Thickness of a merlon through the parapet, in metres.
const MERLON_T := 0.3
## Height of the tiled band that runs under the eaves, in metres.
const TILE_BAND_H := 0.62
## Drop of the centre of the tiled band below the top of the wall, in metres.
const TILE_BAND_DROP := 1.15
## Spacing of the diamonds picked out along the tiled band, in metres.
const TILE_DIAMOND_STEP := 1.6
## Side of one diamond in the tiled band (a square turned 45 degrees), in metres.
const TILE_DIAMOND := 0.3

# --- Transition, drum and dome ----------------------------------------------------------------

## Half the width of the square transition block that sits on the roof under the drum, in metres.
const TRANS_HALF := 11.0
## Height of the transition block, in metres.
const TRANS_H := 1.8
## Top of the transition block, in metres above the podium.
const TRANS_TOP := WALL_H + TRANS_H
## Apothem (centre to flat) of the octagonal drum, in metres.
const DRUM_A := 9.0
## Height of the drum from the transition block to the cornice, in metres.
const DRUM_H := 5.0
## Thickness of a drum panel, in metres.
const DRUM_T := 0.55
## Top of the drum, in metres above the podium.
const DRUM_TOP := TRANS_TOP + DRUM_H
## Apothem of the cornice ring that caps the drum, in metres.
const CORNICE_A := 9.7
## Thickness of that cornice ring, in metres.
const CORNICE_T := 0.5
## Springing plane of the dome, in metres above the podium.
const DOME_BASE := DRUM_TOP + CORNICE_T
## Radius of the dome; the dome is a hemisphere, so this is also its rise, in metres.
const DOME_R := 9.4
## Crown of the dome, where the finial stands, in metres above the podium.
const DOME_APEX := DOME_BASE + DOME_R
## Clear width of one clerestory lantern in a drum panel, in metres.
const LANTERN_W := 1.7
## Height of the straight part of a clerestory lantern below its arch, in metres.
const LANTERN_H := 2.3

# --- Minaret ----------------------------------------------------------------------------------

## Where the minaret stands, in metres east of the anchor. Its plinth deliberately engages both
## the porch end wall and the forecourt wall; move it further out and it looks bolted on, move it
## in and it fouls the east riwaq.
const MIN_X := 15.7
## Where the minaret stands, in metres south of the anchor, level with the middle of the porch.
const MIN_Z := 16.8
## Side of the square minaret plinth, in metres.
const MIN_BASE := 4.6
## Height of the minaret plinth, in metres.
const MIN_BASE_H := 3.4
## Apothem of the octagonal main shaft, in metres. Shaft slenderness is what sells a minaret.
const MIN_A := 1.7
## Top of the main shaft, where the corbel under the balcony starts, in metres.
const MIN_SHAFT_TOP := 24.0
## Apothem of the balcony slab, in metres.
const BALC_A := 2.9
## Thickness of the balcony slab, in metres.
const BALC_T := 0.55
## Height of the balcony railing, in metres.
const BALC_RAIL_H := 1.1
## Apothem of the short upper shaft above the balcony, in metres.
const MIN_TOP_A := 1.2
## Height of that upper shaft, in metres.
const MIN_TOP_H := 5.6
## Radius of the little dome that caps the minaret, in metres.
const MIN_CAP_R := 1.75

# --- Porch, riwaq and forecourt ---------------------------------------------------------------

## Number of arched bays across the entrance porch.
const PORCH_BAYS := 5
## Width of one porch pier, in metres.
const PIER_W := 1.4
## Depth of one porch pier through the arcade, in metres.
const PIER_D := 1.2
## Springing height of the porch arches, in metres.
const PORCH_SPRING := 4.4
## Height to the top of the porch roof slab, in metres.
const PORCH_H := 8.2
## Thickness of the porch roof slab, in metres.
const PORCH_ROOF_T := 0.7
## Depth of the arcaded riwaq down each side of the forecourt, in metres.
const RIWAQ_D := 3.4
## Number of arched bays in one riwaq.
const RIWAQ_BAYS := 6
## Side of one square riwaq column, in metres.
const RIWAQ_COL := 0.9
## Springing height of the riwaq arches, in metres.
const RIWAQ_SPRING := 3.2
## Height to the top of the riwaq roof slab, in metres.
const RIWAQ_H := 6.4
## Height of the plain forecourt wall, in metres.
const COURT_WALL_H := 4.2
## Thickness of the forecourt wall, in metres.
const COURT_WALL_T := 0.5
## Clear width of the gateway in the forecourt wall, in metres.
const GATE_W := 5.0
## Width of the raised gate pylon around that gateway, in metres.
const GATE_PYLON_W := 9.0
## Height of the gate pylon, in metres.
const GATE_PYLON_H := 8.8
## Springing height of the gate arch, in metres.
const GATE_SPRING := 3.2

# --- Ablution fountain -------------------------------------------------------------------------

## Apothem of the octagonal fountain basin, in metres.
const FOUNT_A := 3.4
## Height of the basin rim above the paving, in metres.
const FOUNT_RIM_H := 0.6
## Thickness of the basin rim, in metres.
const FOUNT_RIM_T := 0.45
## Radius at which the ablution seats stand around the basin, in metres.
const FOUNT_SEAT_R := 5.2

# --- Arch geometry -----------------------------------------------------------------------------

## How far the two centres of a pointed arch sit off the axis, as a fraction of the half span.
## 0 gives a round arch, 0.35 gives the gently pointed profile used all over this building.
const ARCH_POINT := 0.35
## Number of voussoir boxes per half arch. Seven reads smooth and costs 168 triangles per arch.
const ARCH_SEGS := 7
## Depth of an arch band through the wall, in metres.
const ARCH_BAND := 0.5
## Number of boxes in a crescent finial.
const CRESCENT_SEGS := 14

# --- Colours ------------------------------------------------------------------------------------

## Sand-coloured stucco: every wall in the place.
const STUCCO := Color(0.86, 0.80, 0.67)
## Pale cast stone for arch bands, copings, sills and the fountain rim.
const TRIM := Color(0.93, 0.90, 0.83)
## The tilework teal, used for the eaves band, the dome and the drum cornice.
const TILE := Color(0.13, 0.46, 0.48)
## The second tile colour, a deeper blue, alternating along the eaves band.
const TILE2 := Color(0.15, 0.29, 0.52)
## Brass for the finials, the crescents and the lamp frames.
const BRASS := Color(0.82, 0.68, 0.34)
## Warm light behind every window: this is a mosque called "the light".
const GLASS := Color(0.98, 0.87, 0.60)
## The prayer carpet.
const CARPET := Color(0.34, 0.21, 0.25)
## Timber for the minbar and the door leaves.
const WOOD := Color(0.36, 0.24, 0.15)
## Still water in the fountain basin.
const WATER := Color(0.22, 0.45, 0.50)


# --- Materials ----------------------------------------------------------------------------------
# PropFactory caches everything it returns, so these one-liners are lookups, not allocations.
# The two below that need flags PropFactory does not set keep their own static instance, because
# a PropFactory material is shared and must never be mutated.

static var _glass_mat: StandardMaterial3D = null
static var _water_mat: StandardMaterial3D = null
static var _soffit_mat: StandardMaterial3D = null


static func _stucco() -> Material:
	return PropFactory.pbr("plaster_beige", 3.0, STUCCO)


static func _stone() -> Material:
	return PropFactory.pbr("plaster_white", 2.4, TRIM)


static func _paving() -> Material:
	return PropFactory.pbr("paving", 2.2, Color(0.90, 0.88, 0.82))


static func _court_paving() -> Material:
	return PropFactory.pbr("paving", 2.2, Color(0.84, 0.81, 0.74))


static func _tile() -> Material:
	return PropFactory.material(TILE, 0.25)


static func _tile2() -> Material:
	return PropFactory.material(TILE2, 0.25)


static func _dome_mat() -> Material:
	return PropFactory.material(TILE.lightened(0.06), 0.2)


static func _brass() -> Material:
	return PropFactory.material(BRASS, 0.3)


static func _wood() -> Material:
	return PropFactory.material(WOOD, 0.6)


static func _carpet() -> Material:
	return PropFactory.material(CARPET, 0.95)


## Self-lit window glass. Unshaded so the lanterns read from the street at any hour without an
## OmniLight; the mosque costs nothing in lights.
static func _glass() -> Material:
	if _glass_mat == null:
		_glass_mat = WeaponFX.unshaded(GLASS, 0.92)
	return _glass_mat


static func _water() -> Material:
	if _water_mat == null:
		_water_mat = StandardMaterial3D.new()
		_water_mat.albedo_color = WATER
		_water_mat.roughness = 0.08
		_water_mat.metallic = 0.35
	return _water_mat


## The underside of the dome, seen from inside the hall: the same hemisphere turned inside out by
## culling front faces instead of back ones.
static func _soffit() -> Material:
	if _soffit_mat == null:
		_soffit_mat = StandardMaterial3D.new()
		_soffit_mat.albedo_color = Color(0.82, 0.74, 0.60)
		_soffit_mat.roughness = 0.9
		_soffit_mat.cull_mode = BaseMaterial3D.CULL_FRONT
	return _soffit_mat


# --- Primitive helpers ---------------------------------------------------------------------------

## An axis-aligned box with a material instead of a flat colour.
static func _box(parent: Node3D, statics: StaticBody3D, size: Vector3, pos: Vector3, mat: Material, collide: bool) -> MeshInstance3D:
	var mesh := Landmarks._box(parent, statics, size, pos, Color.WHITE, collide)
	mesh.material_override = mat
	return mesh


## A box turned about Y. Landmarks._shape() can only place axis-aligned shapes, so the matching
## collision shape is built here with its own transform.
static func _rbox(parent: Node3D, statics: StaticBody3D, size: Vector3, pos: Vector3, yaw: float, mat: Material, collide: bool) -> MeshInstance3D:
	var mesh := _box(parent, null, size, pos, mat, false)
	mesh.rotation.y = yaw
	if collide and statics != null:
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = size
		cs.shape = box
		cs.transform = Transform3D(Basis(Vector3.UP, yaw), pos)
		statics.add_child(cs)
	return mesh


## A regular prism, `sides` facets, given by its apothem so drums and shafts line up with the
## panels built beside them. `rings = 1` keeps an octagonal shaft down to 32 triangles.
static func _poly(parent: Node3D, statics: StaticBody3D, apothem: float, height: float, sides: int, pos: Vector3, mat: Material, collide: bool) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	var circum := apothem / cos(PI / float(sides))
	cyl.top_radius = circum
	cyl.bottom_radius = circum
	cyl.height = height
	cyl.radial_segments = sides
	cyl.rings = 1
	mesh.mesh = cyl
	mesh.material_override = mat
	mesh.position = pos
	mesh.rotation.y = -PI / float(sides)
	parent.add_child(mesh)
	if collide and statics != null:
		var cs := CollisionShape3D.new()
		var shape := CylinderShape3D.new()
		shape.radius = apothem
		shape.height = height
		cs.shape = shape
		cs.position = pos
		statics.add_child(cs)
	return mesh


## A hollow octagonal ring of eight panels: a band or a cornice that has to be seen through,
## because _poly() builds a solid prism and would cap the opening under the dome. 96 triangles.
static func _ring(parent: Node3D, statics: StaticBody3D, apothem: float, height: float, thickness: float, pos: Vector3, mat: Material, collide: bool) -> void:
	var panel_w := 2.0 * apothem * tan(PI / 8.0) * 1.03
	for i in 8:
		var th := float(i) * PI * 0.25
		_rbox(parent, statics, Vector3(panel_w, height, thickness), pos + Vector3(sin(th), 0.0, cos(th)) * apothem, th, mat, collide)


## A small sphere for finial knops. 8 x 4 segments, 64 triangles.
static func _ball(parent: Node3D, radius: float, pos: Vector3, mat: Material) -> void:
	var mesh := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	sphere.radial_segments = 8
	sphere.rings = 4
	mesh.mesh = sphere
	mesh.material_override = mat
	mesh.position = pos
	parent.add_child(mesh)


## An empty node to hang a rotated group off, so arches and crescents can be laid out in a plain
## local XY plane and then turned to face whichever wall they belong to.
static func _pivot(parent: Node3D, pos: Vector3, yaw: float) -> Node3D:
	var node := Node3D.new()
	node.position = pos
	node.rotation.y = yaw
	parent.add_child(node)
	return node


## Yaw for a pivot whose local +Z should point along the world direction (dx, dz).
static func _facing(dx: float, dz: float) -> float:
	return atan2(dx, dz)


## Rise of a two-centred arch of this span, from the springing line to the point, in metres.
static func _arch_rise(span: float) -> float:
	var p := ARCH_POINT
	return span * 0.5 * sqrt((1.0 + p) * (1.0 + p) - p * p)


## Half the clear width of a two-centred arch `y` metres above its springing line.
static func _arch_half_width(span: float, y: float) -> float:
	var a := span * 0.5
	var d := a * ARCH_POINT
	var r := a + d
	return maxf(sqrt(maxf(r * r - y * y, 0.0)) - d, 0.0)


## One two-centred (pointed) arch band, drawn in the local XY plane of `pivot`: it spans `span`
## metres along local X centred on x = 0, springs from local y = `spring`, is `band` metres deep
## in the radial direction and `depth` metres thick through the wall. Returns the apex height in
## the pivot's local frame so the caller can stack a lintel or a spandrel on top of it.
static func _arch(pivot: Node3D, span: float, spring: float, band: float, depth: float, segs: int, mat: Material) -> float:
	var a := span * 0.5
	var d := a * ARCH_POINT
	var r := a + d
	var apex := sqrt(maxf(r * r - d * d, 0.0))
	var end_ang := atan2(apex, d)
	for side: float in [1.0, -1.0]:
		var prev := Vector2(a * side, 0.0)
		for i in range(1, segs + 1):
			var th := end_ang * float(i) / float(segs)
			var point := Vector2((r * cos(th) - d) * side, r * sin(th))
			var seg := point - prev
			var mid := (prev + point) * 0.5
			var piece := _box(pivot, null, Vector3(seg.length() * 1.08, band, depth), Vector3(mid.x, spring + mid.y, 0.0), mat, false)
			piece.rotation.z = atan2(seg.y, seg.x)
			prev = point
	return spring + apex


## Glass filling an arched opening: a plain pane up to the springing line, then three strips that
## step in with the curve of the head.
static func _arch_glass(pivot: Node3D, span: float, spring: float, below: float, depth: float, mat: Material) -> void:
	_box(pivot, null, Vector3(span, below, depth), Vector3(0.0, spring - below * 0.5, 0.0), mat, false)
	var rise := _arch_rise(span)
	for i in 3:
		var y0 := rise * float(i) / 3.0
		var y1 := rise * float(i + 1) / 3.0
		var w := _arch_half_width(span, (y0 + y1) * 0.5) * 2.0
		if w < 0.08:
			continue
		_box(pivot, null, Vector3(w, y1 - y0, depth), Vector3(0.0, spring + (y0 + y1) * 0.5, 0.0), mat, false)


## Fills the two corners between a pointed opening and the rectangular hole that was actually
## left in the wall, so a doorway or a gateway reads as an arch from both sides. `out_half` is
## half the width of the hole and `top` its head, both measured in the pivot's local frame.
static func _spandrel(pivot: Node3D, span: float, spring: float, out_half: float, top: float, depth: float, mat: Material) -> void:
	var rise := _arch_rise(span)
	var strips := 5
	for i in strips:
		var y0 := rise * float(i) / float(strips)
		var y1 := rise * float(i + 1) / float(strips)
		var half := _arch_half_width(span, (y0 + y1) * 0.5)
		var w := out_half - half
		if w > 0.02:
			for side: float in [-1.0, 1.0]:
				_box(pivot, null, Vector3(w, y1 - y0, depth), Vector3(side * (half + w * 0.5), spring + (y0 + y1) * 0.5, 0.0), mat, false)
	if top > spring + rise + 0.02:
		_box(pivot, null, Vector3(out_half * 2.0, top - spring - rise, depth), Vector3(0.0, (top + spring + rise) * 0.5, 0.0), mat, false)


## A run of stepped merlons along one straight parapet edge, standing on `y`. `axis_x` true means
## the run travels along X at a fixed Z.
static func _merlons(parent: Node3D, base: Vector3, axis_x: bool, from_s: float, to_s: float, fixed: float, y: float, mat: Material) -> void:
	var length := absf(to_s - from_s)
	if length < MERLON_STEP:
		return
	var count := maxi(2, int(length / MERLON_STEP))
	var step := length / float(count)
	var start := minf(from_s, to_s)
	var low := Vector3(MERLON_W, MERLON_H, MERLON_T) if axis_x else Vector3(MERLON_T, MERLON_H, MERLON_W)
	var high := Vector3(MERLON_W * 0.5, MERLON_H * 0.55, MERLON_T) if axis_x else Vector3(MERLON_T, MERLON_H * 0.55, MERLON_W * 0.5)
	for i in count:
		var s := start + (float(i) + 0.5) * step
		var at := base + (Vector3(s, y, fixed) if axis_x else Vector3(fixed, y, s))
		_box(parent, null, low, at + Vector3(0.0, MERLON_H * 0.5, 0.0), mat, false)
		_box(parent, null, high, at + Vector3(0.0, MERLON_H * 1.275, 0.0), mat, false)


## The band of tilework under the eaves of one elevation, with diamonds picked out along it in
## two colours. `out` is the outward normal of the face in that axis (+1 or -1).
static func _tile_band(parent: Node3D, base: Vector3, axis_x: bool, from_s: float, to_s: float, fixed: float, y: float, out: float) -> void:
	var length := absf(to_s - from_s)
	var mid := (from_s + to_s) * 0.5
	var band_size := Vector3(length, TILE_BAND_H, 0.12) if axis_x else Vector3(0.12, TILE_BAND_H, length)
	var band_at := base + (Vector3(mid, y, fixed + out * 0.06) if axis_x else Vector3(fixed + out * 0.06, y, mid))
	_box(parent, null, band_size, band_at, _tile(), false)
	var count := maxi(2, int(length / TILE_DIAMOND_STEP))
	var step := length / float(count)
	var start := minf(from_s, to_s)
	var d := TILE_DIAMOND
	for i in count:
		var s := start + (float(i) + 0.5) * step
		var at := base + (Vector3(s, y, fixed + out * 0.14) if axis_x else Vector3(fixed + out * 0.14, y, s))
		var mat: Material = _tile2() if i % 2 == 0 else _stone()
		var gem := _box(parent, null, Vector3(d, d, 0.08) if axis_x else Vector3(0.08, d, d), at, mat, false)
		if axis_x:
			gem.rotation.z = PI * 0.25
		else:
			gem.rotation.x = PI * 0.25


## A crescent finial: an arc of boxes in the local XY plane of a pivot, widest at the bottom and
## tapering to a point at each horn, with the opening facing up. 14 boxes, 168 triangles.
static func _crescent(parent: Node3D, pos: Vector3, yaw: float, radius: float, band: float, depth: float, mat: Material) -> void:
	var pivot := _pivot(parent, pos, yaw)
	var a0 := deg_to_rad(125.0)
	var a1 := deg_to_rad(415.0)
	for i in CRESCENT_SEGS:
		var t0 := float(i) / float(CRESCENT_SEGS)
		var t1 := float(i + 1) / float(CRESCENT_SEGS)
		var p0 := Vector2(cos(lerpf(a0, a1, t0)), sin(lerpf(a0, a1, t0))) * radius
		var p1 := Vector2(cos(lerpf(a0, a1, t1)), sin(lerpf(a0, a1, t1))) * radius
		var seg := p1 - p0
		var mid := (p0 + p1) * 0.5
		var width := maxf(band * sin(PI * (t0 + t1) * 0.5), 0.05)
		var piece := _box(pivot, null, Vector3(seg.length() * 1.15, width, depth), Vector3(mid.x, mid.y, 0.0), mat, false)
		piece.rotation.z = atan2(seg.y, seg.x)


## Stem, knop and crescent: the finial that tops the dome, the minaret cap and the fountain.
static func _finial(parent: Node3D, at: Vector3, scale_m: float) -> void:
	var brass := _brass()
	_poly(parent, null, 0.16 * scale_m, 1.1 * scale_m, 8, at + Vector3(0.0, 0.55 * scale_m, 0.0), brass, false)
	_ball(parent, 0.3 * scale_m, at + Vector3(0.0, 1.1 * scale_m, 0.0), brass)
	_crescent(parent, at + Vector3(0.0, 1.4 * scale_m + 0.62 * scale_m, 0.0), 0.0, 0.62 * scale_m, 0.2 * scale_m, 0.1 * scale_m, brass)


## One arched window: pane, glazing bars, sill, jambs and a pointed arch band. `at` sits on the
## wall face at sill level and the pivot's local +Z is the outward normal.
static func _window(parent: Node3D, at: Vector3, yaw: float, span: float, below: float) -> void:
	var pivot := _pivot(parent, at, yaw)
	var stone := _stone()
	_arch_glass(pivot, span, below, below, 0.1, _glass())
	_box(pivot, null, Vector3(0.16, below, 0.22), Vector3(-(span + 0.16) * 0.5, below * 0.5, 0.06), stone, false)
	_box(pivot, null, Vector3(0.16, below, 0.22), Vector3((span + 0.16) * 0.5, below * 0.5, 0.06), stone, false)
	_box(pivot, null, Vector3(span + 0.6, 0.18, 0.34), Vector3(0.0, -0.09, 0.08), stone, false)
	_box(pivot, null, Vector3(0.08, below, 0.12), Vector3(0.0, below * 0.5, 0.05), stone, false)
	_arch(pivot, span + 0.32, below, 0.34, 0.24, ARCH_SEGS, stone)


# --- Entry points --------------------------------------------------------------------------------

static func build(anchor: Vector2, parent: Node3D, statics: StaticBody3D, plan: CityPlan, detailed: bool) -> void:
	var ground: float = plan.height_at(anchor) if plan != null else 0.0
	var base := Vector3(anchor.x, ground + PODIUM_LIFT, anchor.y)
	if not detailed:
		_far(parent, statics, base)
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED_SALT ^ (int(anchor.x) * 73856093) ^ (int(anchor.y) * 19349663)
	_podium(parent, statics, base, rng)
	_hall(parent, statics, base)
	_interior(parent, statics, base)
	_crown(parent, statics, base)
	_porch(parent, statics, base)
	_minaret(parent, statics, base)
	_courtyard(parent, statics, base, rng)
	_fountain(parent, statics, base)


## The far copy: the podium, the hall block, the transition, the drum, the dome and the whole
## minaret, which is the only part of this building anyone reads from a mile away. No props, no
## arcades, no windows. About 900 triangles.
static func _far(parent: Node3D, statics: StaticBody3D, base: Vector3) -> void:
	var stucco := _stucco()
	var stone := _stone()
	_box(parent, statics, Vector3(SITE_X * 2.0, PODIUM_T, COURT_Z1 - SITE_Z0), base + Vector3(0.0, -PODIUM_T * 0.5, (SITE_Z0 + COURT_Z1) * 0.5), _paving(), true)
	_box(parent, statics, Vector3(HALL_HALF * 2.0, WALL_H, HALL_HALF * 2.0 + PORCH_D), base + Vector3(0.0, WALL_H * 0.5, PORCH_D * 0.5), stucco, true)
	_box(parent, statics, Vector3(TRANS_HALF * 2.0, TRANS_H, TRANS_HALF * 2.0), base + Vector3(0.0, WALL_H + TRANS_H * 0.5, 0.0), stucco, true)
	_poly(parent, statics, DRUM_A, DRUM_H, 8, base + Vector3(0.0, TRANS_TOP + DRUM_H * 0.5, 0.0), stucco, true)
	_poly(parent, null, CORNICE_A, CORNICE_T, 8, base + Vector3(0.0, DRUM_TOP + CORNICE_T * 0.5, 0.0), stone, false)
	var dome := Landmarks._dome(parent, statics, DOME_R, base + Vector3(0.0, DOME_BASE, 0.0), TILE)
	dome.material_override = _dome_mat()
	var min_at := Vector3(MIN_X, 0.0, MIN_Z)
	_box(parent, statics, Vector3(MIN_BASE, MIN_BASE_H, MIN_BASE), base + min_at + Vector3(0.0, MIN_BASE_H * 0.5, 0.0), stucco, true)
	_poly(parent, statics, MIN_A, MIN_SHAFT_TOP - MIN_BASE_H, 8, base + min_at + Vector3(0.0, (MIN_SHAFT_TOP + MIN_BASE_H) * 0.5, 0.0), stucco, true)
	_poly(parent, statics, BALC_A, BALC_T, 8, base + min_at + Vector3(0.0, MIN_SHAFT_TOP + BALC_T * 0.5, 0.0), stone, true)
	var upper := MIN_SHAFT_TOP + BALC_T
	_poly(parent, statics, MIN_TOP_A, MIN_TOP_H, 8, base + min_at + Vector3(0.0, upper + MIN_TOP_H * 0.5, 0.0), stucco, true)
	var cap := Landmarks._dome(parent, null, MIN_CAP_R, base + min_at + Vector3(0.0, upper + MIN_TOP_H, 0.0), TILE)
	cap.material_override = _dome_mat()


# --- Podium --------------------------------------------------------------------------------------

static func _podium(parent: Node3D, statics: StaticBody3D, base: Vector3, rng: RandomNumberGenerator) -> void:
	# One slab under the whole walled site, so the mosque stands level on a sloping block.
	var slab_z0 := SITE_Z0
	var slab_z1 := COURT_Z1 + COURT_WALL_T
	_box(parent, statics, Vector3(SITE_X * 2.0 + 1.2, PODIUM_T, slab_z1 - slab_z0), base + Vector3(0.0, -PODIUM_T * 0.5, (slab_z0 + slab_z1) * 0.5), _paving(), true)
	# The forecourt paving is a shade cooler than the hall podium, with a jittered tone per seed.
	var court_tone := _court_paving()
	var court := _box(parent, null, Vector3(SITE_X * 2.0 - 0.2, 0.08, COURT_Z1 - PORCH_Z1 - 0.2), base + Vector3(0.0, 0.04, (PORCH_Z1 + COURT_Z1) * 0.5), court_tone, false)
	court.position.x += rng.randf_range(-0.05, 0.05)
	# Three entrance steps outside the gate, and the same at the porch lip.
	for i in 3:
		var t := float(i)
		_box(parent, statics, Vector3(GATE_PYLON_W + 2.4 + t * 1.2, 0.2, 0.9), base + Vector3(0.0, -0.1 - t * 0.2, COURT_Z1 + COURT_WALL_T + 0.45 + t * 0.9), _stone(), true)


# --- Prayer hall ----------------------------------------------------------------------------------

static func _hall(parent: Node3D, statics: StaticBody3D, base: Vector3) -> void:
	var stucco := _stucco()
	var stone := _stone()
	var inner := HALL_HALF - WALL_T * 0.5
	# Four walls. The south wall is split around the doorway.
	_box(parent, statics, Vector3(HALL_HALF * 2.0, WALL_TOP, WALL_T), base + Vector3(0.0, WALL_TOP * 0.5, -inner), stucco, true)
	_box(parent, statics, Vector3(WALL_T, WALL_TOP, HALL_HALF * 2.0 - WALL_T * 2.0), base + Vector3(-inner, WALL_TOP * 0.5, 0.0), stucco, true)
	_box(parent, statics, Vector3(WALL_T, WALL_TOP, HALL_HALF * 2.0 - WALL_T * 2.0), base + Vector3(inner, WALL_TOP * 0.5, 0.0), stucco, true)
	var jamb := (HALL_HALF * 2.0 - DOOR_W) * 0.5
	for side: float in [-1.0, 1.0]:
		_box(parent, statics, Vector3(jamb, WALL_TOP, WALL_T), base + Vector3(side * (DOOR_W + jamb) * 0.5, WALL_TOP * 0.5, inner), stucco, true)
	_box(parent, statics, Vector3(DOOR_W, WALL_TOP - DOOR_H, WALL_T), base + Vector3(0.0, (WALL_TOP + DOOR_H) * 0.5, inner), stucco, true)
	# Roof slab, built as a ring so the dome is open to the hall below.
	var ring := HALL_HALF - OCULUS_HALF
	var roof_y := WALL_H - ROOF_T * 0.5
	for side: float in [-1.0, 1.0]:
		_box(parent, statics, Vector3(HALL_HALF * 2.0, ROOF_T, ring), base + Vector3(0.0, roof_y, side * (HALL_HALF + OCULUS_HALF) * 0.5), stucco, true)
		_box(parent, statics, Vector3(ring, ROOF_T, OCULUS_HALF * 2.0), base + Vector3(side * (HALL_HALF + OCULUS_HALF) * 0.5, roof_y, 0.0), stucco, true)
	# Parapet band and its merlons, on all four roof edges.
	var pary := WALL_H + PARAPET_H * 0.5
	for side: float in [-1.0, 1.0]:
		_box(parent, null, Vector3(HALL_HALF * 2.0, PARAPET_H, 0.34), base + Vector3(0.0, pary, side * (HALL_HALF - 0.17)), stone, false)
		_box(parent, null, Vector3(0.34, PARAPET_H, HALL_HALF * 2.0 - 0.68), base + Vector3(side * (HALL_HALF - 0.17), pary, 0.0), stone, false)
		_merlons(parent, base, true, -HALL_HALF, HALL_HALF, side * (HALL_HALF - 0.17), WALL_H + PARAPET_H, stone)
		_merlons(parent, base, false, -HALL_HALF + 0.5, HALL_HALF - 0.5, side * (HALL_HALF - 0.17), WALL_H + PARAPET_H, stone)
	# Tilework under the eaves. The south elevation is left plain: the porch roof covers it.
	var band_y := WALL_TOP - TILE_BAND_DROP
	_tile_band(parent, base, true, -HALL_HALF + 0.4, HALL_HALF - 0.4, -HALL_HALF, band_y, -1.0)
	for side: float in [-1.0, 1.0]:
		_tile_band(parent, base, false, -HALL_HALF + 0.4, HALL_HALF - 0.4, side * HALL_HALF, band_y, side)
	# Arched windows: three down each flank, two flanking the mihrab on the qibla wall.
	for side: float in [-1.0, 1.0]:
		for z: float in [-8.0, 0.0, 8.0]:
			_window(parent, base + Vector3(side * (HALL_HALF + 0.02), 3.2, z), _facing(side, 0.0), 1.8, 3.4)
	for x: float in [-6.6, 6.6]:
		_window(parent, base + Vector3(x, 3.2, -HALL_HALF - 0.02), _facing(0.0, -1.0), 1.8, 3.4)
	_mihrab_bay(parent, statics, base)
	_portal(parent, statics, base)


## The mihrab reads outside as a faceted bay pushed out of the qibla wall, capped by a little
## dome. Half of the prism is buried in the wall.
static func _mihrab_bay(parent: Node3D, statics: StaticBody3D, base: Vector3) -> void:
	var at := Vector3(0.0, 0.0, -HALL_HALF - 1.2)
	_poly(parent, statics, 2.6, 7.2, 8, base + at + Vector3(0.0, 3.6, 0.0), _stucco(), true)
	_poly(parent, null, 2.85, 0.4, 8, base + at + Vector3(0.0, 7.4, 0.0), _stone(), false)
	var cap := Landmarks._dome(parent, null, 2.85, base + at + Vector3(0.0, 7.6, 0.0), TILE)
	cap.material_override = _dome_mat()
	_poly(parent, null, 2.64, TILE_BAND_H, 8, base + at + Vector3(0.0, 6.5, 0.0), _tile(), false)


## The doorway: a raised frame of two jambs and a head band, a pointed opening filled in to the
## rectangular hole in the wall, and two timber leaves standing open against the jambs so the
## hall can actually be walked into.
static func _portal(parent: Node3D, statics: StaticBody3D, base: Vector3) -> void:
	var stone := _stone()
	var face := HALL_HALF + 0.3
	var frame_w := DOOR_W + 2.4
	var frame_h := PORCH_H - PORCH_ROOF_T - 0.1
	var jamb := (frame_w - DOOR_W) * 0.5
	for side: float in [-1.0, 1.0]:
		_box(parent, statics, Vector3(jamb, frame_h, 0.6), base + Vector3(side * (DOOR_W + jamb) * 0.5, frame_h * 0.5, face), stone, true)
	_box(parent, statics, Vector3(frame_w, frame_h - DOOR_H, 0.6), base + Vector3(0.0, (frame_h + DOOR_H) * 0.5, face), stone, true)
	# Turn the rectangular hole into a pointed one, from both sides of the wall.
	for out: float in [1.0, -1.0]:
		var fill := _pivot(parent, base + Vector3(0.0, 0.0, HALL_HALF * out), _facing(0.0, out))
		_spandrel(fill, DOOR_W, DOOR_SPRING, DOOR_W * 0.5, DOOR_H, WALL_T * 1.05, _stucco())
	var pivot := _pivot(parent, base + Vector3(0.0, 0.0, face + 0.32), 0.0)
	_arch(pivot, DOOR_W + 0.44, DOOR_SPRING, 0.42, 0.24, ARCH_SEGS, _tile())
	_tile_band(parent, base, true, -frame_w * 0.5 + 0.3, frame_w * 0.5 - 0.3, face + 0.3, frame_h - 0.3, 1.0)
	var leaf_w := DOOR_W * 0.5 - 0.06
	for side: float in [-1.0, 1.0]:
		var hinge := Vector3(side * DOOR_W * 0.5, 0.0, face + 0.36)
		var dir := Vector3(side * 0.17, 0.0, 0.985)
		var yaw := atan2(-dir.z, dir.x)
		_rbox(parent, null, Vector3(leaf_w, DOOR_SPRING, 0.12), base + hinge + dir * (leaf_w * 0.5) + Vector3(0.0, DOOR_SPRING * 0.5, 0.0), yaw, _wood(), false)


# --- Inside the hall --------------------------------------------------------------------------------

static func _interior(parent: Node3D, statics: StaticBody3D, base: Vector3) -> void:
	var stone := _stone()
	var inner := HALL_HALF - WALL_T
	# Carpet, with the prayer rows picked out as lighter bands running across it.
	_box(parent, null, Vector3(inner * 2.0, 0.1, inner * 2.0), base + Vector3(0.0, 0.05, 0.0), _carpet(), false)
	for i in 7:
		var z := -inner + 1.6 + float(i) * (inner * 2.0 - 3.2) / 6.0
		_box(parent, null, Vector3(inner * 2.0 - 1.0, 0.03, 0.16), base + Vector3(0.0, 0.11, z), PropFactory.material(CARPET.lightened(0.22), 0.95), false)
	# Four piers carrying the transition block, one under each corner of the opening.
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			_box(parent, statics, Vector3(1.3, WALL_TOP, 1.3), base + Vector3(sx * 6.6, WALL_TOP * 0.5, sz * 6.6), _stucco(), true)
			_box(parent, null, Vector3(1.7, 0.3, 1.7), base + Vector3(sx * 6.6, WALL_TOP - 0.15, sz * 6.6), stone, false)
	# The mihrab niche in the qibla wall: tilework in a pointed recess, nothing figurative.
	var niche := _pivot(parent, base + Vector3(0.0, 0.0, -inner + 0.06), 0.0)
	_arch_glass(niche, 3.2, 4.2, 4.2, 0.16, _tile2())
	_arch(niche, 3.6, 4.2, 0.36, 0.2, ARCH_SEGS, stone)
	_box(niche, null, Vector3(0.24, 4.2, 0.24), Vector3(-1.72, 2.1, 0.06), stone, false)
	_box(niche, null, Vector3(0.24, 4.2, 0.24), Vector3(1.72, 2.1, 0.06), stone, false)
	_minbar(parent, base)
	# The underside of the dome, turned inside out so it reads from the carpet.
	var soffit := Landmarks._dome(parent, null, DOME_R - 0.35, base + Vector3(0.0, DOME_BASE, 0.0), TILE)
	soffit.material_override = _soffit()
	# Four hanging lamps on brass stems, level with the tops of the piers.
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var at := Vector3(sx * 4.6, 0.0, sz * 4.6)
			_poly(parent, null, 0.05, 2.6, 6, base + at + Vector3(0.0, WALL_TOP - 1.3, 0.0), _brass(), false)
			_ball(parent, 0.42, base + at + Vector3(0.0, WALL_TOP - 2.9, 0.0), _glass())
			_poly(parent, null, 0.46, 0.14, 8, base + at + Vector3(0.0, WALL_TOP - 2.5, 0.0), _brass(), false)


## The minbar: a short flight of steps with side panels and a small canopy, in timber. No
## carving, no lettering.
static func _minbar(parent: Node3D, base: Vector3) -> void:
	var wood := _wood()
	var at := Vector3(3.0, 0.0, -HALL_HALF + 2.6)
	var steps := 5
	for i in steps:
		var h := 0.42 * float(i + 1)
		_box(parent, null, Vector3(1.3, 0.42, 0.55), base + at + Vector3(0.0, h - 0.21, 0.55 * float(steps - 1 - i) + 0.3), wood, false)
	for side: float in [-1.0, 1.0]:
		_box(parent, null, Vector3(0.12, 1.5, 0.55 * float(steps) + 0.6), base + at + Vector3(side * 0.71, 1.05, 0.55 * float(steps) * 0.5), wood, false)
	_box(parent, null, Vector3(1.5, 0.16, 1.1), base + at + Vector3(0.0, 2.94, 0.3), wood, false)
	for side: float in [-1.0, 1.0]:
		_box(parent, null, Vector3(0.12, 0.9, 0.12), base + at + Vector3(side * 0.64, 2.47, 0.3), wood, false)


# --- Transition, drum and dome ------------------------------------------------------------------------

static func _crown(parent: Node3D, statics: StaticBody3D, base: Vector3) -> void:
	var stucco := _stucco()
	var stone := _stone()
	# The transition block, another ring so the dome stays open to the hall.
	var ring := TRANS_HALF - OCULUS_HALF
	var ty := WALL_H + TRANS_H * 0.5
	for side: float in [-1.0, 1.0]:
		_box(parent, statics, Vector3(TRANS_HALF * 2.0, TRANS_H, ring), base + Vector3(0.0, ty, side * (TRANS_HALF + OCULUS_HALF) * 0.5), stucco, true)
		_box(parent, statics, Vector3(ring, TRANS_H, OCULUS_HALF * 2.0), base + Vector3(side * (TRANS_HALF + OCULUS_HALF) * 0.5, ty, 0.0), stucco, true)
	# Chamfered corners: the square turning into the octagon the drum stands on.
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var yaw := _facing(sx * 0.70711, sz * 0.70711)
			_rbox(parent, null, Vector3(6.0, TRANS_H + 0.2, 1.5), base + Vector3(sx * 7.6, ty, sz * 7.6), yaw, stone, false)
	# Octagonal drum: eight panels, so it is hollow and reads from the carpet as well as the street.
	var panel_w := 2.0 * DRUM_A * tan(PI / 8.0) * 1.03
	var drum_y := TRANS_TOP + DRUM_H * 0.5
	for i in 8:
		var th := float(i) * PI * 0.25
		var out := Vector3(sin(th), 0.0, cos(th))
		_rbox(parent, statics, Vector3(panel_w, DRUM_H, DRUM_T), base + out * DRUM_A + Vector3(0.0, drum_y, 0.0), th, stucco, true)
		# Pilaster on the joint between this panel and the next.
		var edge := th + PI * 0.125
		_rbox(parent, null, Vector3(0.6, DRUM_H, 0.6), base + Vector3(sin(edge), 0.0, cos(edge)) * (DRUM_A / cos(PI / 8.0)) + Vector3(0.0, drum_y, 0.0), edge, stone, false)
		# Clerestory lantern: this is where the mosque gets its name.
		var sill := TRANS_TOP + 0.9
		var lamp := _pivot(parent, base + out * (DRUM_A + DRUM_T * 0.5) + Vector3(0.0, sill, 0.0), th)
		_arch_glass(lamp, LANTERN_W, LANTERN_H, LANTERN_H, 0.2, _glass())
		_arch(lamp, LANTERN_W + 0.3, LANTERN_H, 0.3, 0.2, 5, stone)
		_box(lamp, null, Vector3(LANTERN_W + 0.7, 0.16, 0.3), Vector3(0.0, -0.08, 0.06), stone, false)
	# Tiled band under the drum cornice, then the cornice itself.
	_ring(parent, null, DRUM_A + 0.35, TILE_BAND_H, 0.3, base + Vector3(0.0, DRUM_TOP - 0.55, 0.0), _tile(), false)
	_ring(parent, statics, CORNICE_A, CORNICE_T, 1.5, base + Vector3(0.0, DRUM_TOP + CORNICE_T * 0.5, 0.0), stone, true)
	# The dome, and the crescent that finishes it.
	var dome := Landmarks._dome(parent, statics, DOME_R, base + Vector3(0.0, DOME_BASE, 0.0), TILE)
	dome.material_override = _dome_mat()
	_ring(parent, null, DOME_R * 0.99, 0.5, 0.7, base + Vector3(0.0, DOME_BASE + 0.15, 0.0), _tile(), false)
	_finial(parent, base + Vector3(0.0, DOME_APEX, 0.0), 1.6)


# --- Entrance porch ------------------------------------------------------------------------------

static func _porch(parent: Node3D, statics: StaticBody3D, base: Vector3) -> void:
	var stucco := _stucco()
	var stone := _stone()
	var head := PORCH_H - PORCH_ROOF_T
	# Solid walls close the two ends of the porch.
	for side: float in [-1.0, 1.0]:
		_box(parent, statics, Vector3(0.5, head, PORCH_D), base + Vector3(side * (HALL_HALF - 0.25), head * 0.5, PORCH_Z0 + PORCH_D * 0.5), stucco, true)
	# Six piers, five arched bays.
	var pitch := (HALL_HALF * 2.0 - PIER_W) / float(PORCH_BAYS)
	var front := PORCH_Z1 - PIER_D * 0.5
	var clear := pitch - PIER_W
	for i in PORCH_BAYS + 1:
		var x := -HALL_HALF + PIER_W * 0.5 + float(i) * pitch
		_box(parent, statics, Vector3(PIER_W, head, PIER_D), base + Vector3(x, head * 0.5, front), stone, true)
		_box(parent, null, Vector3(PIER_W + 0.3, 0.26, PIER_D + 0.3), base + Vector3(x, PORCH_SPRING - 0.13, front), stone, false)
	for i in PORCH_BAYS:
		var cx := -HALL_HALF + PIER_W * 0.5 + (float(i) + 0.5) * pitch
		var pivot := _pivot(parent, base + Vector3(cx, 0.0, front), 0.0)
		_arch(pivot, clear + 0.36, PORCH_SPRING, 0.5, PIER_D * 0.92, ARCH_SEGS, stone)
		_spandrel(pivot, clear + 0.36, PORCH_SPRING, pitch * 0.5, head, PIER_D * 0.82, stucco)
	# Roof slab, its tiled fascia, and the parapet that finishes it.
	var slab_d := PORCH_D + 0.3
	_box(parent, statics, Vector3(HALL_HALF * 2.0, PORCH_ROOF_T, slab_d), base + Vector3(0.0, PORCH_H - PORCH_ROOF_T * 0.5, PORCH_Z0 + slab_d * 0.5), stone, true)
	_tile_band(parent, base, true, -HALL_HALF + 0.4, HALL_HALF - 0.4, PORCH_Z1 + 0.3, PORCH_H - PORCH_ROOF_T * 0.5, 1.0)
	_box(parent, null, Vector3(HALL_HALF * 2.0, PARAPET_H, 0.34), base + Vector3(0.0, PORCH_H + PARAPET_H * 0.5, PORCH_Z1 + 0.13), stone, false)
	_merlons(parent, base, true, -HALL_HALF, HALL_HALF, PORCH_Z1 + 0.13, PORCH_H + PARAPET_H, stone)
	for side: float in [-1.0, 1.0]:
		_box(parent, null, Vector3(0.34, PARAPET_H, slab_d - 0.4), base + Vector3(side * (HALL_HALF - 0.17), PORCH_H + PARAPET_H * 0.5, PORCH_Z0 + slab_d * 0.5), stone, false)
		_merlons(parent, base, false, PORCH_Z0 + 0.4, PORCH_Z1, side * (HALL_HALF - 0.17), PORCH_H + PARAPET_H, stone)
	# A lantern on the two middle piers, either side of the door.
	for side: float in [-1.0, 1.0]:
		var at := Vector3(side * pitch * 0.5, PORCH_SPRING - 0.9, front - PIER_D * 0.5 - 0.2)
		_box(parent, null, Vector3(0.1, 0.1, 0.4), base + at + Vector3(0.0, 0.4, 0.2), _brass(), false)
		_ball(parent, 0.26, base + at, _glass())


# --- Minaret --------------------------------------------------------------------------------------

static func _minaret(parent: Node3D, statics: StaticBody3D, base: Vector3) -> void:
	var stucco := _stucco()
	var stone := _stone()
	var at := Vector3(MIN_X, 0.0, MIN_Z)
	# Square plinth with a tiled band and a cornice where the octagonal shaft takes over.
	_box(parent, statics, Vector3(MIN_BASE, MIN_BASE_H, MIN_BASE), base + at + Vector3(0.0, MIN_BASE_H * 0.5, 0.0), stucco, true)
	_box(parent, null, Vector3(MIN_BASE + 0.08, TILE_BAND_H, MIN_BASE + 0.08), base + at + Vector3(0.0, MIN_BASE_H - 1.0, 0.0), _tile(), false)
	_box(parent, null, Vector3(MIN_BASE + 0.45, 0.32, MIN_BASE + 0.45), base + at + Vector3(0.0, MIN_BASE_H, 0.0), stone, false)
	# The shaft: long, plain, one tiled ring about half way up to break the height.
	_poly(parent, statics, MIN_A, MIN_SHAFT_TOP - MIN_BASE_H, 8, base + at + Vector3(0.0, (MIN_BASE_H + MIN_SHAFT_TOP) * 0.5, 0.0), stucco, true)
	_poly(parent, null, MIN_A + 0.07, TILE_BAND_H, 8, base + at + Vector3(0.0, (MIN_BASE_H + MIN_SHAFT_TOP) * 0.5, 0.0), _tile(), false)
	# Three stepped rings corbel the balcony out of the shaft.
	for i in 3:
		_poly(parent, null, MIN_A + 0.25 + float(i) * 0.4, 0.3, 8, base + at + Vector3(0.0, MIN_SHAFT_TOP + 0.15 + float(i) * 0.3, 0.0), stone, false)
	var slab_y := MIN_SHAFT_TOP + 0.9
	_poly(parent, statics, BALC_A, BALC_T, 16, base + at + Vector3(0.0, slab_y + BALC_T * 0.5, 0.0), stone, true)
	var deck := slab_y + BALC_T
	# Eight railing panels and a coping ring around the balcony.
	var rail_a := BALC_A - 0.14
	var rail_w := 2.0 * rail_a * tan(PI / 8.0) * 1.03
	for i in 8:
		var th := float(i) * PI * 0.25
		_rbox(parent, null, Vector3(rail_w, BALC_RAIL_H, 0.16), base + at + Vector3(sin(th), 0.0, cos(th)) * rail_a + Vector3(0.0, deck + BALC_RAIL_H * 0.5, 0.0), th, stone, false)
	_poly(parent, null, rail_a + 0.1, 0.12, 8, base + at + Vector3(0.0, deck + BALC_RAIL_H + 0.06, 0.0), stone, false)
	# Upper shaft with four little arched openings, cornice, cap dome and crescent.
	_poly(parent, statics, MIN_TOP_A, MIN_TOP_H, 8, base + at + Vector3(0.0, deck + MIN_TOP_H * 0.5, 0.0), stucco, true)
	for i in 4:
		var th := float(i) * PI * 0.5
		var out := Vector3(sin(th), 0.0, cos(th))
		var slot := _pivot(parent, base + at + out * (MIN_TOP_A + 0.02) + Vector3(0.0, deck + 1.4, 0.0), th)
		_arch_glass(slot, 0.68, 1.2, 1.2, 0.14, _glass())
		_arch(slot, 0.88, 1.2, 0.18, 0.14, 4, stone)
	var cap_y := deck + MIN_TOP_H
	_poly(parent, null, MIN_TOP_A + 0.5, 0.35, 8, base + at + Vector3(0.0, cap_y + 0.175, 0.0), stone, false)
	var cap := Landmarks._dome(parent, null, MIN_CAP_R, base + at + Vector3(0.0, cap_y + 0.35, 0.0), TILE)
	cap.material_override = _dome_mat()
	_finial(parent, base + at + Vector3(0.0, cap_y + 0.35 + MIN_CAP_R, 0.0), 0.75)


# --- Walled forecourt ------------------------------------------------------------------------------

static func _courtyard(parent: Node3D, statics: StaticBody3D, base: Vector3, rng: RandomNumberGenerator) -> void:
	var stucco := _stucco()
	var stone := _stone()
	var court_len := COURT_Z1 - PORCH_Z1
	var court_mid := (PORCH_Z1 + COURT_Z1) * 0.5
	var inset := SITE_X - COURT_WALL_T * 0.5
	for side: float in [-1.0, 1.0]:
		# The forecourt flanks carry the riwaq roof, so they stand as tall as it does.
		_box(parent, statics, Vector3(COURT_WALL_T, RIWAQ_H, court_len), base + Vector3(side * inset, RIWAQ_H * 0.5, court_mid), stucco, true)
		# The side yards beside the hall keep the plain low wall.
		var yard_len := PORCH_Z1 - SITE_Z0
		_box(parent, statics, Vector3(COURT_WALL_T, COURT_WALL_H, yard_len), base + Vector3(side * inset, COURT_WALL_H * 0.5, (SITE_Z0 + PORCH_Z1) * 0.5), stucco, true)
		_merlons(parent, base, false, SITE_Z0, PORCH_Z1, side * inset, COURT_WALL_H, stone)
	_box(parent, statics, Vector3(SITE_X * 2.0, COURT_WALL_H, COURT_WALL_T), base + Vector3(0.0, COURT_WALL_H * 0.5, SITE_Z0 + COURT_WALL_T * 0.5), stucco, true)
	_merlons(parent, base, true, -SITE_X, SITE_X, SITE_Z0 + COURT_WALL_T * 0.5, COURT_WALL_H, stone)
	# Gate wall either side of the pylon.
	var seg := (SITE_X * 2.0 - GATE_PYLON_W) * 0.5
	for side: float in [-1.0, 1.0]:
		var cx := side * (GATE_PYLON_W + seg) * 0.5
		_box(parent, statics, Vector3(seg, COURT_WALL_H, COURT_WALL_T), base + Vector3(cx, COURT_WALL_H * 0.5, COURT_Z1), stucco, true)
		_merlons(parent, base, true, cx - seg * 0.5, cx + seg * 0.5, COURT_Z1, COURT_WALL_H, stone)
	_gate(parent, statics, base)
	_riwaq(parent, statics, base)
	# Six trees in the court, jittered a little per seed so two mosques never plant alike.
	for sx: float in [-1.0, 1.0]:
		for z: float in [23.5, 30.75, 38.0]:
			var at := Vector3(sx * 10.0 + rng.randf_range(-0.6, 0.6), 0.02, z + rng.randf_range(-0.7, 0.7))
			_poly(parent, statics, 1.25, 0.5, 8, base + at + Vector3(0.0, 0.25, 0.0), stone, true)
			Landmarks._tree(parent, base + at + Vector3(0.0, 0.5, 0.0))


## The gate pylon: a pointed gateway, a tiled panel with the one word of lettering this building
## carries, and merlons on top.
static func _gate(parent: Node3D, statics: StaticBody3D, base: Vector3) -> void:
	var stucco := _stucco()
	var stone := _stone()
	var cheek := (GATE_PYLON_W - GATE_W) * 0.5
	var hole_top := GATE_SPRING + _arch_rise(GATE_W) + 0.24
	for side: float in [-1.0, 1.0]:
		_box(parent, statics, Vector3(cheek, GATE_PYLON_H, 0.9), base + Vector3(side * (GATE_W + cheek) * 0.5, GATE_PYLON_H * 0.5, COURT_Z1), stucco, true)
	_box(parent, statics, Vector3(GATE_PYLON_W, GATE_PYLON_H - hole_top, 0.9), base + Vector3(0.0, (GATE_PYLON_H + hole_top) * 0.5, COURT_Z1), stucco, true)
	for out: float in [1.0, -1.0]:
		var face := _pivot(parent, base + Vector3(0.0, 0.0, COURT_Z1 + out * 0.45), _facing(0.0, out))
		_spandrel(face, GATE_W, GATE_SPRING, GATE_W * 0.5, hole_top, 0.92, stucco)
		_arch(face, GATE_W + 0.5, GATE_SPRING, 0.5, 0.22, ARCH_SEGS, stone)
	# Tiled panel and the name, facing the street.
	_box(parent, null, Vector3(6.2, 2.0, 0.12), base + Vector3(0.0, 7.7, COURT_Z1 + 0.5), _tile2(), false)
	Landmarks._text("NOOR", 0.2, base + Vector3(0.0, 7.05, COURT_Z1 + 0.62), parent, TRIM)
	_box(parent, null, Vector3(GATE_PYLON_W + 0.5, 0.3, 1.3), base + Vector3(0.0, GATE_PYLON_H + 0.15, COURT_Z1), stone, false)
	_merlons(parent, base, true, -GATE_PYLON_W * 0.5, GATE_PYLON_W * 0.5, COURT_Z1, GATE_PYLON_H + 0.3, stone)


## The arcades down both sides of the forecourt: square columns, pointed arches, a flat roof with
## a merlon parapet on its inner edge.
static func _riwaq(parent: Node3D, statics: StaticBody3D, base: Vector3) -> void:
	var stone := _stone()
	var stucco := _stucco()
	var col_x := SITE_X - RIWAQ_D
	var pitch := (COURT_Z1 - PORCH_Z1 - RIWAQ_COL) / float(RIWAQ_BAYS)
	var clear := pitch - RIWAQ_COL
	var head := RIWAQ_H - 0.6
	for side: float in [-1.0, 1.0]:
		for i in RIWAQ_BAYS + 1:
			var z := PORCH_Z1 + RIWAQ_COL * 0.5 + float(i) * pitch
			_box(parent, statics, Vector3(RIWAQ_COL, head, RIWAQ_COL), base + Vector3(side * col_x, head * 0.5, z), stone, true)
			_box(parent, null, Vector3(RIWAQ_COL + 0.26, 0.22, RIWAQ_COL + 0.26), base + Vector3(side * col_x, RIWAQ_SPRING - 0.11, z), stone, false)
		for i in RIWAQ_BAYS:
			var cz := PORCH_Z1 + RIWAQ_COL * 0.5 + (float(i) + 0.5) * pitch
			var pivot := _pivot(parent, base + Vector3(side * col_x, 0.0, cz), -PI * 0.5)
			_arch(pivot, clear + 0.3, RIWAQ_SPRING, 0.42, RIWAQ_COL * 0.92, ARCH_SEGS, stone)
			_spandrel(pivot, clear + 0.3, RIWAQ_SPRING, pitch * 0.5, head, RIWAQ_COL * 0.82, stucco)
		# Roof slab from the column line back to the forecourt wall, and its parapet.
		var slab_w := RIWAQ_D + RIWAQ_COL * 0.5
		var slab_x := side * (SITE_X - slab_w * 0.5)
		_box(parent, statics, Vector3(slab_w, 0.6, COURT_Z1 - PORCH_Z1), base + Vector3(slab_x, RIWAQ_H - 0.3, (PORCH_Z1 + COURT_Z1) * 0.5), stone, true)
		var lip := side * (col_x - RIWAQ_COL * 0.5 + 0.17)
		_box(parent, null, Vector3(0.34, PARAPET_H, COURT_Z1 - PORCH_Z1), base + Vector3(lip, RIWAQ_H + PARAPET_H * 0.5, (PORCH_Z1 + COURT_Z1) * 0.5), stone, false)
		_merlons(parent, base, false, PORCH_Z1, COURT_Z1, lip, RIWAQ_H + PARAPET_H, stone)
		_tile_band(parent, base, false, PORCH_Z1 + 0.4, COURT_Z1 - 0.4, lip, RIWAQ_H - 0.3, -side)
		# Two lanterns hung under the arcade.
		for z: float in [PORCH_Z1 + pitch * 1.5, PORCH_Z1 + pitch * 4.5]:
			_poly(parent, null, 0.05, 1.0, 6, base + Vector3(side * (col_x + RIWAQ_D * 0.5), head - 0.5, z), _brass(), false)
			_ball(parent, 0.3, base + Vector3(side * (col_x + RIWAQ_D * 0.5), head - 1.2, z), _glass())


# --- Ablution fountain ------------------------------------------------------------------------------

static func _fountain(parent: Node3D, statics: StaticBody3D, base: Vector3) -> void:
	var stone := _stone()
	var at := Vector3(0.0, 0.0, (PORCH_Z1 + COURT_Z1) * 0.5)
	_poly(parent, null, FOUNT_SEAT_R + 1.4, 0.08, 16, base + at + Vector3(0.0, 0.06, 0.0), _paving(), false)
	# Eight rim panels make the octagonal basin.
	var rim_w := 2.0 * FOUNT_A * tan(PI / 8.0) * 1.03
	for i in 8:
		var th := float(i) * PI * 0.25
		var out := Vector3(sin(th), 0.0, cos(th))
		_rbox(parent, statics, Vector3(rim_w, FOUNT_RIM_H, FOUNT_RIM_T), base + at + out * FOUNT_A + Vector3(0.0, FOUNT_RIM_H * 0.5, 0.0), th, stone, true)
		# A brass tap over each panel, for wudu.
		_poly(parent, null, 0.05, 0.34, 6, base + at + out * (FOUNT_A + 0.16) + Vector3(0.0, FOUNT_RIM_H + 0.17, 0.0), _brass(), false)
	_poly(parent, null, FOUNT_A - FOUNT_RIM_T, 0.2, 8, base + at + Vector3(0.0, 0.1, 0.0), _tile2(), false)
	_poly(parent, null, FOUNT_A - FOUNT_RIM_T - 0.06, 0.06, 16, base + at + Vector3(0.0, FOUNT_RIM_H - 0.22, 0.0), _water(), false)
	# Centre pier, bowl, little dome and a crescent to match the ones overhead.
	_poly(parent, statics, 0.6, 1.4, 8, base + at + Vector3(0.0, 0.9, 0.0), stone, true)
	_poly(parent, null, 1.2, 0.24, 8, base + at + Vector3(0.0, 1.72, 0.0), stone, false)
	_poly(parent, null, 0.5, 0.5, 8, base + at + Vector3(0.0, 2.09, 0.0), stone, false)
	var cap := Landmarks._dome(parent, null, 0.8, base + at + Vector3(0.0, 2.34, 0.0), TILE)
	cap.material_override = _dome_mat()
	_finial(parent, base + at + Vector3(0.0, 3.14, 0.0), 0.34)
	# Low seats around the basin, turned to face it.
	for i in 8:
		var th := float(i) * PI * 0.25 + PI * 0.125
		var out := Vector3(sin(th), 0.0, cos(th))
		_rbox(parent, statics, Vector3(0.9, 0.44, 0.5), base + at + out * FOUNT_SEAT_R + Vector3(0.0, 0.22, 0.0), th, stone, true)
