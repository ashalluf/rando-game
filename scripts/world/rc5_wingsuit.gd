class_name Rc5Wingsuit
extends RefCounted
## The wingsuit refcam pass (rc5-wingsuit-golden, docs/HANDOFF.md "The wingsuit at golden hour"):
## what the camera chasing the hero over Bunker Hill sees that was not the suit's. The suit itself
## is WingsuitFx (WINGSUIT_LOOK=0 its A/B); this is the world side:
##   * THE LATTICE museum's roof (LandmarkCivicCenter._museum): a flat 52 m white slab from above,
##     the brightest thing under the glide - now the veil carried over the top as the real
##     building's skylight lattice: deep ribs on the veil's cell grid over dark glazing, a solid
##     white border round it.
## RC5_WINGSUIT=0 is the A/B.

static var enabled: bool = OS.get_environment("RC5_WINGSUIT") != "0"

## The roof lattice: border kept solid (m), rib depth and width (m), the cell (as the veil's).
const ROOF_BORDER := 2.4
const RIB_DEPTH := 0.9
const RIB_WIDTH := 0.34
const ROOF_CELL := Vector2(2.3, 3.0)


## The roof's skylight lattice on the museum box `r` whose coping top is at `top`: a dark glazed
## field inset by ROOF_BORDER, and the ribs over it in the veil material. Returns the boxes laid.
static func museum_roof(g: LandmarkGeo, r: Rect2, top: float, detailed: bool) -> int:
	var field := r.grow(-ROOF_BORDER)
	if field.size.x <= 0.0 or field.size.y <= 0.0:
		return 0
	var c := field.get_center()
	# The glazing, a hair proud of the coping so it never z-fights it from the air.
	g.box("vault", Vector3(c.x, top + 0.04, c.y), Vector3(field.size.x, 0.08, field.size.y))
	var n := 1
	var cols := maxi(2, roundi(field.size.x / ROOF_CELL.x))
	var rows := maxi(2, roundi(field.size.y / ROOF_CELL.y))
	var bevel := 0.06 if detailed else 0.0
	var y := top + RIB_DEPTH * 0.5
	# Ribs running north-south (between the columns) and east-west (between the rows), each the
	# whole field long; the ends meet the border.
	for i in cols + 1:
		var x := field.position.x + field.size.x * float(i) / float(cols)
		g.box("veil", Vector3(x, y, c.y), Vector3(RIB_WIDTH, RIB_DEPTH, field.size.y), Color.WHITE, Basis(), bevel)
		n += 1
	for j in rows + 1:
		var z := field.position.y + field.size.y * float(j) / float(rows)
		g.box("veil", Vector3(c.x, y, z), Vector3(field.size.x, RIB_DEPTH * 0.82, RIB_WIDTH), Color.WHITE, Basis(), bevel)
		n += 1
	return n



## The concert hall's steel (brushed_steel.gdshader `look`): polished stainless mirroring this
## hour's sky - the sails were flat beige from above at golden hour and blew out where the sun hit.
static func steel_look() -> float:
	return 1.0 if enabled else 0.0


## The downtown towers' lit crowns (tower_crown.gdshader `dusk_hold`): their glow waits for dusk.
static func crown_dusk_hold() -> float:
	return 1.0 if enabled else 0.0
