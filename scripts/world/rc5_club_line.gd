class_name RcClubLine
extends RefCounted
## The club line refcam (wave 8, `club_line` in tools/refcams/cameras_w8.json; docs/HANDOFF.md "A
## club's line at 23:30"): what made AFTERGLOW's line on 6th St read as a game from the pavement
## across, fixed. Hooks in SkyBeam (the searchlight beams), NightLife (the club front, its light)
## and NightLifeKit.
##
## * The beams: nightlife_beam.gdshader faded the first 2 % of its 1.7 km cone (34 m) to nothing
##   even with no volumetric fog to hand it to - the whole stretch a pavement sees. Now the shaft
##   starts at the lens (`club_look`), lens-wide (cone()), with a dense core over its first
##   `core_len` metres that thins up the sky.
##
## `RC5_CLUB_LINE=0` in the environment is the A/B (every hook a no-op: the old look).

static func _static_init() -> void: LoadPulse.compiled()  # a boot frame: docs/HANDOFF.md "The boot compile"

static var enabled: bool = OS.get_environment("RC5_CLUB_LINE") != "0"

## The lens's radius the shaft starts at (m): a searchlight's beam leaves its 0.9 m lens that wide.
const LENS_R := 0.36

static var _cone: CylinderMesh


## The beam's material (SkyBeam._ready()): the street look on.
static func beam(m: ShaderMaterial, reach: float) -> void:
	if not enabled:
		return
	m.set_shader_parameter("club_look", 1.0)
	m.set_shader_parameter("beam_len", reach)


## The beam's cone, lens-wide at the lamp: `wide` is the cone's far radius (m). null when off.
static func cone(wide: float) -> CylinderMesh:
	if not enabled:
		return null
	if _cone == null:
		_cone = CylinderMesh.new()
		_cone.top_radius = LENS_R / maxf(wide, 0.01)
		_cone.bottom_radius = 1.0
		_cone.height = 1.0
		_cone.cap_top = false
		_cone.cap_bottom = false
		_cone.radial_segments = 18
		_cone.rings = 1
	return _cone


# --- The club's front ------------------------------------------------------------------------
## * The front: the club stood under its shop's own sign band, whose name ("STORE CLOSING") read
##   over a 0.26 m line of lettering on the canopy - from across the street the club was one more
##   shop. A club takes the band (front()): a matte black fascia board `BOARD_D` proud of the wall
##   (in front of Building's TextMesh name, which it hides) over the band, an LED frame in the
##   club's colour, the name in lit letters `NAME_H` tall; and its colour washes the line (a light
##   and a pool along the rope), not only the door.

## The board's bottom and top over the pavement (m): round Building's sign band (0.77..0.93 of a
## 4.5 m storefront), how far it stands out from the wall, the most of the shop's width it takes.
const BOARD_Y := Vector2(3.42, 4.26)
const BOARD_D := 0.22
const BOARD_SHARE := 0.94
const BOARD_MAX := 7.5
const NAME_H := 0.52
## The board's name glow after dark (nightlife_sign.gdshader's night_energy; the canopy's is 7).
const NAME_GLOW := 2.6
## The light along the line: where (share of the run from the door), reach, and the pool's size.
const LINE_LIGHT_AT := 0.55
const LINE_LIGHT_REACH := 9.0

static var _boards: Dictionary = {}


## The fascia board `width` m wide in a club's LED colour `led` (NightLifeKit's frame: x along
## the wall, z out, y up, origin on the pavement at the door's middle).
static func board(width: float, led: int) -> Mesh:
	var w := snappedf(width, 0.1)
	var key := "%d_%d" % [int(w * 10.0), led]
	if _boards.has(key):
		return _boards[key]
	var st := StreetClutter._begin()
	var lc: Color = NightLifeKit.LED_COLORS[led % NightLifeKit.LED_COLORS.size()]
	var led_col := Color(lc.r, lc.g, lc.b, NightLifeKit.A_LED)
	var face := Color(0.035, 0.035, 0.04, NightLifeKit.A_RUBBER)
	var h := BOARD_Y.y - BOARD_Y.x
	var cy := (BOARD_Y.x + BOARD_Y.y) * 0.5
	NightLifeKit._box(st, Vector3(0.0, cy, BOARD_D * 0.5), Vector3(w, h, BOARD_D), face, Vector2(0.7, 0.0), 0.012)
	# The LED frame, a hair proud of the face: top, bottom and the two ends.
	var z := BOARD_D + 0.008
	var e := 0.035
	NightLifeKit._box(st, Vector3(0.0, BOARD_Y.y - 0.06, z), Vector3(w - 0.1, e, 0.016), led_col, Vector2(0.3, 0.0))
	NightLifeKit._box(st, Vector3(0.0, BOARD_Y.x + 0.06, z), Vector3(w - 0.1, e, 0.016), led_col, Vector2(0.3, 0.0))
	for s: float in [-1.0, 1.0]:
		NightLifeKit._box(st, Vector3(s * (w * 0.5 - 0.05), cy, z), Vector3(e, h - 0.12 + e, 0.016), led_col, Vector2(0.3, 0.0))
	# A cove of the LED's light washing the wall above the board (an upturned strip on its top).
	NightLifeKit._box(st, Vector3(0.0, BOARD_Y.y + 0.012, BOARD_D * 0.5), Vector3(w - 0.2, 0.02, 0.03), led_col, Vector2(0.3, 0.0))
	st.generate_tangents()
	var mesh := st.commit()
	mesh.surface_set_material(0, NightLifeKit.material())
	_boards[key] = mesh
	return mesh


## A club's front (NightLife._build_venue): the board over its shop's sign band, the name on it,
## the line's light and pool. `shop_w` the shop's width (m), `xf` the venue's frame, `tint` its
## LED colour (sRGB). Off: nothing.
static func front(chunk: CityChunk, holder: Node3D, v: Dictionary, xf: Transform3D, shop_w: float, tint: Color, custom: Color, gy: float) -> void:
	if not enabled:
		return
	var w := clampf(shop_w * BOARD_SHARE, 3.0, BOARD_MAX)
	var led := int(v.led)
	var k := "nl_board_%d_%d" % [int(snappedf(w, 0.1) * 10.0), led]
	chunk._batch.add(k, board(w, led), xf, Color.WHITE, custom)
	chunk._batch.set_draw_distance(k, NightLife.SIGN_DRAW)
	chunk._batch.set_shadow_distance(k, NightLife.SHADOW_DISTANCE)
	NightLife._sign(holder, String(v.name), xf * Vector3(0.0, (BOARD_Y.x + BOARD_Y.y) * 0.5, BOARD_D + 0.012), xf.basis, NAME_H, w - 0.5, tint, gy)
	# The name burns at NAME_GLOW, not the canopy lettering's 7: at that the club's colour went
	# white through AgX and the board read as one more shop sign.
	var sign_mi := holder.get_child(holder.get_child_count() - 1) as MeshInstance3D
	if sign_mi and sign_mi.material_override is ShaderMaterial:
		(sign_mi.material_override as ShaderMaterial).set_shader_parameter("night_energy", NAME_GLOW)
	if not bool(v.get("open", false)):
		return
	# The club's colour on the line: a light over the middle of it, a pool along the rope.
	var along: Vector2 = v.along
	var run := float(v.run)
	var mid := (v.door as Vector2) + along * (run * LINE_LIGHT_AT) + (v.out as Vector2) * 1.0
	var col := tint.lerp(Color(1.0, 0.85, 0.7), 0.35)
	NightLife._add_light(holder, Vector3(mid.x, CityChunk.SIDEWALK_TOP + 3.0 + gy, mid.y), LINE_LIGHT_REACH, col)
	var pool_at := (v.door as Vector2) + along * (run * 0.5) + (v.out as Vector2) * 1.0
	var pb := Basis(Vector3.RIGHT, -PI * 0.5)
	var yaw := atan2(xf.basis.z.x, xf.basis.z.z)
	var pool := Transform3D(Basis(Vector3.UP, yaw) * pb.scaled(Vector3(run + 2.0, 1.0, 3.2)), Vector3(pool_at.x, CityChunk.SIDEWALK_TOP + 0.07, pool_at.y))
	chunk._batch.add("nl_pool", PropFactory.shop_spill(), pool, Color(col.r, col.g, col.b, 0.55))
