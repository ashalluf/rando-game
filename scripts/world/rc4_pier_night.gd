class_name RcPierNight
extends RefCounted
## The pier at night from the beach, second pass (fleet wave 7, `rc4-pier-night-2`, refcam
## pier_night: the pier and its wheel from the sand at 21:00 clear). The first pass (PierNight)
## gave the wheel and the deck their lights; the frame still measured p50 ~21 and read as a black
## frame with a few lit dots. What fixed it, in the order the eye reads the frame:
##
## * **The eye's exposure on a dark coast** (`exposure_gain()`, one hook in DayNight._apply()):
##   the night exposure is set for a lit street (night_exposure, the grade), and on the open sand
##   under the moon there is nothing a street has - so the beach, the sea and the sky all sat in
##   the bottom tenth of the range. A camera on the coast at night opens up by `COAST_GAIN`, the
##   way an eye or a photographer meters a dark beach: weighted by how far the camera stands from
##   the coast (`coast_weight()`: 1 on the sand and over the sea, 0 `COAST_REACH` m inland) and by
##   how deep into the night the light is (`DARK_FROM` .. `DARK_TO` of DayNight's moonlight), so
##   the golden hour, the sunset at the Esplanade and every street at night are untouched.
## * **The pier's lamps light the pier** (`dress_material()`, pier_park.gdshader `wash`): the
##   real OmniLights fade out at 90 m and the Compatibility renderer has none past that, so from
##   the beach the stands, rails, arcade and the white steel were black shapes between the lit
##   points. Each pier_park surface now takes the light of the two lamp rows (line sources) and
##   the midway's glows (`GLOWS`: the carousel, the arcade, the bumper hall, the wheel's base,
##   the stands), by distance and facing, after dark.
## * **The pier's light on the sand and the water** (`push()`, beach_sand.gdshader and
##   ocean.gdshader `pier_wash`): the lamp rows as warm line sources lighting the sand beside and
##   beyond the pier (none straight under the deck: the lamps stand on it) and a warm wash on the
##   sea round the piles, both off `lamp_factor`.
##
## `RC4_PIER_NIGHT=0` in the environment is the A/B: every number and shader as before.

static var enabled: bool = OS.get_environment("RC4_PIER_NIGHT") != "0"

## The coast's exposure lives in CoastExposure (scripts/world/coast_exposure.gd): DayNight calls it
## every frame and must not pull this file's Landmarks / Weather graph into the sky tools.


# --- The park lit by its own lamps --------------------------------------------------------------

## pier_park.gdshader's wash: overall gain, the floor every surface gets after dark.
const WASH := 0.55
const WASH_FLOOR := 0.035
## The downlights under the deck that light the piles (x the lamp rows' strength).
const WASH_UNDER := 3.0
## The midway's glows (park frame x, y, z; intensity; colour): what lights the platform's south
## faces toward the beach, which the lamp rows (along the main deck) never see.
const GLOWS: Array = [
	[Vector3(-108.0, 10.5, 40.0), 26.0, Color(1.0, 0.78, 0.48)],   # the carousel's crown
	[Vector3(-83.0, 9.0, -14.0), 18.0, Color(0.92, 0.70, 1.0)],    # the arcade's front
	[Vector3(-120.0, 9.0, -14.0), 14.0, Color(1.0, 0.82, 0.6)],    # the bumper hall
	[Vector3(-150.0, 9.5, 37.0), 24.0, Color(0.85, 0.75, 1.0)],    # the wheel's base and queue
	[Vector3(-38.0, 8.8, 11.2), 9.0, Color(1.0, 0.82, 0.55)],      # a candy stand
	[Vector3(-199.5, 8.8, 47.0), 9.0, Color(1.0, 0.82, 0.55)],     # the funnel-cake stand
	[Vector3(-176.0, 10.0, 56.0), 12.0, Color(1.0, 0.85, 0.6)],    # the west platform's tables
	[Vector3(-70.0, 10.0, 30.0), 14.0, Color(1.0, 0.8, 0.55)],     # the coaster's station
]


## Gives one of PierMesh's pier_park materials the wash (a no-op with the A/B off).
static func dress_material(mat: ShaderMaterial) -> void:
	if not enabled or mat == null:
		return
	var anchor := pier_anchor()
	mat.set_shader_parameter("wash", WASH)
	mat.set_shader_parameter("wash_floor", WASH_FLOOR)
	mat.set_shader_parameter("wash_under", WASH_UNDER)
	mat.set_shader_parameter("wash_anchor", Vector3(anchor.x, 0.0, anchor.y))
	mat.set_shader_parameter("wash_row", Vector4(PierPark.LAMP_FROM, PierPark.LAMP_FROM - float(PierPark.LAMP_COUNT - 1) * PierPark.LAMP_STEP,
		PierPark.LAMP_Z, PierPark.DECK_TOP + 5.35))
	var pts := PackedVector4Array()
	var cols := PackedVector3Array()
	for g: Array in GLOWS:
		var p: Vector3 = g[0]
		pts.append(Vector4(p.x, p.y, p.z, float(g[1])))
		var c: Color = g[2]
		cols.append(Vector3(c.r, c.g, c.b))
	mat.set_shader_parameter("wash_pts", pts)
	mat.set_shader_parameter("wash_pt_col", cols)
	mat.set_shader_parameter("wash_pt_count", pts.size())


## RANDO PIER's anchor (true world XZ), from its Landmarks entry.
static func pier_anchor() -> Vector2:
	for lm: Dictionary in Landmarks.all():
		if str(lm.id) == "pier":
			return lm.anchor
	return Vector2(-940.0, -350.0)


# --- The piers' light on the sand and the water -------------------------------------------------

## Lamp intensity per metre of row (pier_wash.gdshaderinc pw_gain) and the glows' scale there.
const SAND_GAIN := 1.4
const SAND_PT_GAIN := 1.0


## Hands the sand's or the ocean's material the piers' lamp rows (Weather.pier_light_lines()),
## which side of each the deck is, and RANDO PIER's midway glows. A no-op with the A/B off.
static func push(mat: ShaderMaterial) -> void:
	if not enabled or mat == null:
		return
	var lines := Weather.pier_light_lines()
	var a := PackedVector4Array()
	var b := PackedVector4Array()
	var sides := PackedFloat32Array()
	for i in mini(lines.size(), 10):
		var l: Array = lines[i]
		a.append(l[0])
		b.append(l[1])
		sides.append(deck_side(lines, i))
	while a.size() < 10:
		a.append(Vector4.ZERO)
		b.append(Vector4.ZERO)
		sides.append(0.0)
	mat.set_shader_parameter("pw_lines", a)
	mat.set_shader_parameter("pw_info", b)
	mat.set_shader_parameter("pw_side", sides)
	mat.set_shader_parameter("pw_count", mini(lines.size(), 10))
	mat.set_shader_parameter("pw_gain", SAND_GAIN)
	mat.set_shader_parameter("pw_pt_gain", SAND_PT_GAIN)
	var anchor := pier_anchor()
	var pts := PackedVector4Array()
	var cols := PackedVector3Array()
	for g: Array in GLOWS:
		if pts.size() >= 8:
			break
		var p: Vector3 = g[0]
		pts.append(Vector4(anchor.x + p.x, p.y, anchor.y + p.z, float(g[1])))
		var c: Color = g[2]
		cols.append(Vector3(c.r, c.g, c.b))
	mat.set_shader_parameter("pw_pts", pts)
	mat.set_shader_parameter("pw_pt_col", cols)
	mat.set_shader_parameter("pw_pt_count", pts.size())


## Which side of row `i` its deck is (+1 left of a->b, -1 right, 0 none): toward the nearest other
## row of lamps (a pier's two rows face each other across its deck; the horseshoe's chords too).
static func deck_side(lines: Array, i: int) -> float:
	var l: Vector4 = (lines[i] as Array)[0]
	var a := Vector2(l.x, l.y)
	var dir := (Vector2(l.z, l.w) - a).normalized()
	var m := Vector2(-dir.y, dir.x)
	var mid := (a + Vector2(l.z, l.w)) * 0.5
	var best := INF
	var side := 0.0
	for j in lines.size():
		if j == i:
			continue
		var o: Vector4 = (lines[j] as Array)[0]
		var om := (Vector2(o.x, o.y) + Vector2(o.z, o.w)) * 0.5
		var d := om.distance_to(mid)
		if d < best and d < 120.0:
			best = d
			side = signf((om - mid).dot(m))
	return side


# --- People on the sand after dark --------------------------------------------------------------

## Strollers on the wet sand by a lit pier at night: at most this many a chunk, within PIER_REACH
## metres (along the shore) of a pier's root, between NIGHT_FROM and NIGHT_TO.
const STROLLERS := 7
const PIER_REACH := 420.0
const NIGHT_FROM := 19.3
const NIGHT_TO := 23.5


## How many strollers a stretch of shore `z0`..`z1` gets at `hour` (pure: the plan and hashes).
static func stroller_count(plan: CityPlan, z0: float, z1: float, hour: float, weather: float) -> int:
	if not enabled or plan == null:
		return 0
	var h := fposmod(hour, 24.0)
	if h < NIGHT_FROM or h > NIGHT_TO or weather < 0.4:
		return 0
	var zc := (z0 + z1) * 0.5
	var near := INF
	for lm: Dictionary in Landmarks.all():
		if str(lm.id) in ["pier", "manhattan_pier", "redondo_pier"]:
			near = minf(near, absf((lm.anchor as Vector2).y - zc))
	if near > PIER_REACH:
		return 0
	var late := 1.0 - smoothstep(21.5, NIGHT_TO, h)
	var f := (1.0 - near / PIER_REACH) * late * weather
	var r := float(absi(hash([plan.seed, "rc4_stroll", floori(zc / 50.0)])) % 1000) / 1000.0
	return roundi(STROLLERS * f * (0.6 + 0.4 * r))


## Puts the strollers in a FULL beach chunk (BeachLife.build()), in the crowd cap, as build steps.
static func night_strollers(ch: CityChunk, z0: float, z1: float, hour: float, weather: float) -> void:
	var n := stroller_count(ch.plan, z0, z1, hour, weather)
	if OS.get_environment("RC4_DEBUG") != "" and n > 0:
		print("RC4 strollers %d in chunk %d,%d (z %.0f..%.0f, hour %.2f)" % [n, ch.ix, ch.iz, z0, z1, hour])
	for i in n:
		ch._run_or_defer(func() -> bool:
			_add_stroller(ch, z0, z1, i)
			return true)


static func _add_stroller(ch: CityChunk, z0: float, z1: float, i: int) -> void:
	if not ch._take_crowd_room():
		return
	var plan := ch.plan
	var model: int = BeachGoer.BEACH_MODELS[absi(hash([plan.seed, ch.ix, ch.iz, "rc4_model", i])) % BeachGoer.BEACH_MODELS.size()]
	var w := BeachWalker.new()
	w.plan_ref = plan
	w.clothed = true
	w.z_lo = z0 + 2.0
	w.z_hi = z1 - 2.0
	w.setup(BeachLife.sand_ring(ch, z0, z1), 4.0, BeachGoer.seed_for(model, 40 + i))
	var start := w._random_ring_point(4.0)
	w.position = Vector3(start.x, BeachLife.sand_y(ch, start.x, start.y) + 0.1, start.y)
	ch.add_child(w)
