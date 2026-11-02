class_name NightSkyline
extends RefCounted
## Downtown at night (docs/HANDOFF.md "The night skyline"): the towers' own light. Offices lit in
## their own colour temperature by tenancy and cleaners' floors lit end to end
## (window_lights.gdshaderinc: window_temp(), window_lit()), crown washes in white or a colour on
## half the tall parts and floodlit masonry (tower_wash()) - all integer rolls on the building's
## seed, shared by the near walls (building.gdshader) and the far boxes (building_lod.gdshader) -
## and the red aviation lights flashing out of phase at their own rates (aircraft_lights.gdshader
## kind 2, TowerMesh.light_mesh(), the near roof spires' beacons: aviation_beacon.gdshader).
## `NIGHT_SKYLINE=0` in the environment turns it off (the A/B): the `night_skyline` global goes to
## 0 and the meshes are built as before.

static var enabled: bool = OS.get_environment("NIGHT_SKYLINE") != "0"

## window_lights.gdshaderinc's CLEANERS_FLOOR: a floor whose roll (salt 60) is at or over this is
## lit end to end.
const CLEANERS_FLOOR := 0.955
## window_temp()'s tenancy shares (salt 66, cumulative) and multipliers before the luminance is
## put back: cool LED, neutral, warm halogen, old fluorescent; the rest the building's own light.
const TEMP_EDGES: Array[float] = [0.22, 0.40, 0.50, 0.56]
const TEMPS: Array[Vector3] = [Vector3(0.74, 0.98, 1.55), Vector3(0.88, 1.0, 1.25), Vector3(1.10, 0.93, 0.72), Vector3(0.80, 1.08, 1.0)]
const CLEANERS_TEMP := Vector3(0.78, 1.0, 1.42)
## tower_wash(): the share of tall parts with a crown wash (salt 65) and of masonry with floods (68).
const CROWN_SHARE := 0.5
const FLOOD_SHARE := 0.6
static var _beacon_material: ShaderMaterial = null


## Pushes the switch to the shaders (DayNight._ready()).
static func install() -> void:
	RenderingServer.global_shader_parameter_set("night_skyline", 1.0 if enabled else 0.0)


## Turns the pass on or off at once (tests).
static func set_enabled(on: bool) -> void:
	enabled = on
	install()


## window_lights.gdshaderinc's wl_roll(): 0..1 from 24 bits of the shared integer hash.
static func roll(key: int, salt: int) -> float:
	return float(Building.shop_hash(key & 0xFFFFFFFF, salt) >> 8) / 16777216.0


## wl_face_row(): the key of a storey of one wall, a bay index short.
static func face_row(b_seed: int, face: int, row: int) -> int:
	return ((clampi(b_seed, 0, 999) * 8 + clampi(face, 0, 7)) * 256 + clampi(row, 0, 255)) * 256


## True when floor `row` of a building with seed `b_seed` (% 1000) is a cleaners' floor.
static func cleaners_floor(b_seed: int, row: int) -> bool:
	return roll(clampi(b_seed, 0, 999) * 256 + clampi(row, 0, 255), 60) >= CLEANERS_FLOOR


## Which of TEMPS an office (the three-bay run of `col`) is lit in, -1 the building's own light,
## 4 the cleaners' cold fluorescent. The shader's window_temp() picks the same.
static func temp_index(b_seed: int, face: int, row: int, col: int) -> int:
	if cleaners_floor(b_seed, row):
		return 4
	var t := roll(face_row(b_seed, face, row) + clampi(col / 3, 0, 255), 66)
	for i in TEMP_EDGES.size():
		if t < TEMP_EDGES[i]:
			return i
	return -1


## True when a tall part of building `b_seed` wears a crown wash, and the colour roll it takes.
static func crown_washed(b_seed: int) -> bool:
	return roll(clampi(b_seed, 0, 999), 65) < CROWN_SHARE


## A red aviation light's phase, from where it stands (TowerMesh.light_mesh()): towers' beacons
## used to take theirs from their index, so every tower's first beacon flashed in step.
static func light_phase(at: Vector3, index: int) -> float:
	var h := hash([snappedf(at.x, 0.1), snappedf(at.y, 0.1), snappedf(at.z, 0.1), index])
	return float(h & 0xFFFF) / 65536.0


## The near roof spires' beacon (Building._commit_roof()): flashing like the far mast's, on the
## building's own phase, where it used to burn steady. One shared material (every beacon is red).
static func beacon_material(color: Color) -> Material:
	if _beacon_material == null:
		_beacon_material = ShaderMaterial.new()
		_beacon_material.shader = load("res://shaders/aviation_beacon.gdshader")
	# As the old unshaded StandardMaterial3D drew it: decoded from sRGB on Forward+, raw on the
	# Compatibility renderer.
	var c := color if RenderingServer.get_current_rendering_method() == "gl_compatibility" else color.srgb_to_linear()
	_beacon_material.set_shader_parameter("color", Vector3(c.r, c.g, c.b))
	return _beacon_material
