class_name WindowInteriors
extends RefCounted
## The rooms behind the windows, second pass (docs/HANDOFF.md "Rooms behind the windows, second
## pass"): homes as well as offices in the city's buildings - a lamp-lit living room with a sofa,
## a picture and a shelf, the TV's flicker, somebody walking across now and then, drapes, sheers,
## roller, venetian and vertical blinds, a window open by day with its curtain moving in the
## draught - and offices with people at their desks and their screens glowing. Shaders:
## shaders/window_interiors.gdshaderinc (the integer rolls, shared by building.gdshader and
## building_lod.gdshader, so a tower's homes keep their lamps, TVs and curtains across the LOD
## line) and shaders/window_rooms.gdshaderinc (the near traces). This is the GDScript copy of the
## rolls; tests/window_interiors_checks.gd holds the two together.
## `WINDOW_INTERIORS=0` in the environment turns it off (the A/B): the `window_interiors` global
## goes to 0 and every window is the first pass's office.

static var enabled: bool = OS.get_environment("WINDOW_INTERIORS") != "0"

## window_interiors.gdshaderinc's WI_HOME_* (per mille of buildings, by Building.WindowStyle).
const HOME_SHARE: Array[int] = [520, 90, 160, 380]
## WI_COVER_* (cumulative per mille): drapes, sheers, roller, venetian, vertical; then bare.
const COVER_EDGES: Array[int] = [300, 520, 700, 830, 900]
enum Cover { DRAPES, SHEER, ROLLER, VENETIAN, VERTICAL, BARE }
const TV := 300
const OPEN := 70
const WALKER := 450
const WORKER := 560


## Pushes the switch to the shaders (DayNight._ready()).
static func install() -> void:
	RenderingServer.global_shader_parameter_set("window_interiors", 1.0 if enabled else 0.0)


static func set_enabled(on: bool) -> void:
	enabled = on
	install()


## wi_key(): a window's key, (seed % 1000, face, row, col) as the shaders count them.
static func key(b_seed: int, face: int, row: int, col: int) -> int:
	return NightSkyline.face_row(b_seed, face, row) + clampi(col, 0, 255)


## wi_pm(): 0..999.
static func pm(k: int, salt: int) -> int:
	return Building.shop_hash(k & 0xFFFFFFFF, salt) % 1000


## wi_home(): is building `b_seed` (% 1000) with window style `style` flats rather than offices.
static func home(b_seed: int, style: int) -> bool:
	if not enabled:
		return false
	return pm(clampi(b_seed, 0, 999), 100) < HOME_SHARE[clampi(style, 0, 3)]


## wi_cover().
static func cover(k: int) -> int:
	var r := pm(k, 101)
	for i in COVER_EDGES.size():
		if r < COVER_EDGES[i]:
			return i
	return Cover.BARE


static func tv(k: int) -> bool:
	return pm(k, 102) < TV


static func open_window(k: int) -> bool:
	var c := cover(k)
	return (c == Cover.DRAPES or c == Cover.SHEER) and pm(k, 103) < OPEN


static func walker(k: int) -> bool:
	return pm(k, 104) < WALKER


static func worker(k: int) -> bool:
	return pm(k, 106) < WORKER
