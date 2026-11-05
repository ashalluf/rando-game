class_name SuburbNight
extends RefCounted
## The suburban street at night (refcam5 `suburb_night`, tools/refcams/cameras_w8.json; docs/HANDOFF.md
## "The suburban street at 21:30"). Three fixes for what read as day-for-night on a residential street:
##
## 1. **The moon in the residential districts** (SuburbMoon, `scripts/world/suburb_moon.gd`, one factor in DayNight's moon energy).
##    A suburb has no light of its own but its lamps, porches and windows, and under the city's moon
##    (NightStreetReview.MOON, set for a lit downtown) every pavement, lawn and road stood at 100-120
##    of 255 with crisp moon shadows - the lamp pools vanished in it. With the camera in SUBURBS or
##    BEACHTOWN (not on the open coast, CoastExposure's place) the moon is `MOON_GAIN` of itself,
##    eased over `EASE_SECONDS` of the real clock, only deep into the night (`DARK_FROM`..`DARK_TO` of
##    DayNight's moonlight: the dusk and the blue hour are untouched).
## 2. **Lit windows light the yard** (`window_spill()`, one hook at the end of HouseBuild._glass()):
##    a soft warm trapezoid on the ground in front of every ground-floor pane, drawn by
##    shaders/suburb_spill.gdshader, which works out whether THAT pane is lit (and whether it is the
##    TV room) from the same house key and pane roll house_glass.gdshader uses (HouseNights' hash), so
##    a dark window throws nothing and the TV room throws blue. One shadowless batch a FULL chunk
##    (`SPILL_KEY`), drawn to `SPILL_DISTANCE`; nothing by day (lamp_factor).
## 3. **Porch lanterns** (house_glow.gdshader shape 2 and house_lamp.gdshader's lens, both behind the
##    `suburb_night` uniform this sets): the wall wash is a point source's falloff with the cap's cut
##    above the lamp, not a soft disc; the lens is glass panes in a frame round a bulb, not a white box.
##
## Every roll is the house key's; no rng, prop id or other batch moves. `SUBURB_NIGHT=0` is the A/B.

static var enabled: bool = OS.get_environment("SUBURB_NIGHT") != "0"

## The window spill batch, and how far it draws (m).
const SPILL_KEY := "sn_spill"
const SPILL_DISTANCE := 140.0
## A spill's reach from the wall (m) and how much wider than the pane it ends.
const SPILL_REACH := 3.4
const SPILL_SPREAD := 1.9
## A pane whose sill stands more than this over the yard is not a ground-floor window (m).
const GROUND_FLOOR := 2.4
## The fixed pane rolls HouseBuild gives a garage door's lights and a mid-century door's light:
## not rooms, so no spill.
const NOT_ROOMS := [0.1, 0.3]

# =================================================================================================
# The window spill (FULL chunks)
# =================================================================================================

static var _spill_mesh: QuadMesh


static func spill_mesh() -> QuadMesh:
	if _spill_mesh == null:
		_spill_mesh = QuadMesh.new()
		_spill_mesh.size = Vector2.ONE
		var mat := ShaderMaterial.new()
		mat.shader = load("res://shaders/suburb_spill.gdshader")
		_spill_mesh.material = mat
	return _spill_mesh


## The pane's roll as the glass shader reads it back: the vertex colour's alpha is stored in 8 bits.
static func pane_q(rnd: float) -> int:
	return clampi(int(round(rnd * 255.0)), 0, 255)


## One pane's spill (HouseBuild._glass(): frame points a, b, heights y0..y1 over the house's floor,
## facing n, the pane's roll). Only ground-floor room windows of the house kit's own houses.
static func window_spill(b: HouseBuild, a: Vector2, e: Vector2, y0: float, y1: float, n: Vector2, rnd: float) -> void:
	if not enabled or not HouseNights.enabled or b.ch == null or b.ch.get("_batch") == null:
		return
	for r: float in NOT_ROOMS:
		if absf(rnd - r) < 0.0001:
			return
	# The hill homes have their own glass (hill_glass.gdshader) and their own yard levels.
	var sp := String((b.get_script() as Script).resource_path)
	if sp.ends_with("hill_home_build.gd"):
		return
	var ch := b.ch
	var foot := (b.L(a, y0) + b.L(e, y0)) * 0.5
	var ground_y := ch._gy(foot.x, foot.z) + CityChunk.SIDEWALK_TOP + YardFill.LIFT + 0.03
	if foot.y - ground_y > GROUND_FLOOR or y1 - y0 < 0.5:
		return
	var out := b.N(n)
	out.y = 0.0
	if out.length_squared() < 1e-6:
		return
	out = out.normalized()
	var width := (b.L(e, y0) - b.L(a, y0)).length()
	if width < 0.3:
		return
	# The quad: from the wall's foot out SPILL_REACH, SPILL_SPREAD x as wide as the pane at its far end.
	var ay := out * SPILL_REACH
	var ax := out.cross(Vector3.UP) * (width * SPILL_SPREAD)
	var at := Vector3(foot.x, ground_y, foot.z) + out * (SPILL_REACH * 0.5 + 0.1)
	at.y -= ch._gy(at.x, at.z)
	# r: the house key, g: the pane's 8-bit roll (both exact as half floats), b: the pane's share of
	# the quad's far width (the trapezoid's near end), a: strength by the pane's height.
	var c := Color(float(HouseNights.key(b.seed)), float(pane_q(rnd)), 1.0 / SPILL_SPREAD, clampf((y1 - y0) / 1.4, 0.4, 1.0))
	ch._batch.add(SPILL_KEY, spill_mesh(), Transform3D(Basis(ax, ay, Vector3.UP * 0.01), at), c)


## The batch's draw distance and shadows (HouseNights.finish(), the chunk's finish).
static func finish(ch: CityChunk) -> void:
	if not enabled:
		return
	ch._batch.set_no_shadow(SPILL_KEY)
	ch._batch.set_draw_distance(SPILL_KEY, SPILL_DISTANCE)


## The lantern look switch on the two house-night materials (HouseNights' glow and lamp shaders).
static func dress_materials(glow: ShaderMaterial, lamp: ShaderMaterial) -> void:
	var on := 1.0 if enabled else 0.0
	if glow:
		glow.set_shader_parameter("suburb_night", on)
	if lamp:
		lamp.set_shader_parameter("suburb_night", on)
