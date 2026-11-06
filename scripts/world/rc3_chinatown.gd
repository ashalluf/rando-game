class_name Rc3Chinatown
extends RefCounted
## The Chinatown refcam (wave 6, `chinatown_dusk` in tools/refcams/cameras_w6.json: the plaza, its
## hall and the plaza gate at 19:15, eye level; docs/HANDOFF.md "The Chinatown plaza at dusk").
## What the view gave away, fixed here, all behind one switch:
## - the shop glass was a flat pale slab: chinatown.gdshader's `rc3` traces a shop room behind it
##   (shelves of goods on the walls, a counter, the ceiling's light panels; true parallax);
## - the lanterns blew out to pale pink balls through AgX: their silk is held to a deep red-orange
##   (green ~0.4 of red in the hot core, red under ~1.6), the ribs and gilt ends dark;
## - the hall was a flat red box lit evenly by the street wash: its screens are lit from inside
##   (UV2 flag LIT_FLAG on the hall's lattice: always lit after dark), its upper storeys get side
##   screens, the lacquer takes less wash;
## - the court held a handful of people: PLAZA_PEOPLE in the evening (each through the crowd cap);
## - the lanterns were 8-sided: 12 sides near (LANTERN_SIDES), the silhouette of a round lantern.
## Off (RC3_CHINATOWN=0 in the environment): the district exactly as before (the shader's `rc3` 0
## is bit-identical, the hall and the lanterns built as they were).

static var enabled: bool = OS.get_environment("RC3_CHINATOWN") != "0"

## UV2.y of a lattice face that is lit inside every night (the hall), with UV2.x 0 (no sway).
const LIT_FLAG := 2.0
const LANTERN_SIDES := 12
## How much of the street wash the lacquer (kind 0) keeps (the shader's `lacquer_wash`).
const LACQUER_WASH := 0.45


## ChinatownKit.material(): the shader's parameters.
static func apply(mat: ShaderMaterial) -> void:
	mat.set_shader_parameter("rc3", 1.0 if enabled else 0.0)
	mat.set_shader_parameter("lacquer_wash", LACQUER_WASH if enabled else 1.0)


## The plaza court's people (ChinatownKit.PLAZA_PEOPLE before): the evening crowd of a real
## plaza, still each one through the crowd cap.
const PLAZA_PEOPLE := 30


static func plaza_people(old: int) -> int:
	return PLAZA_PEOPLE if enabled else old


static func lantern_sides() -> int:
	return LANTERN_SIDES if enabled else 8
