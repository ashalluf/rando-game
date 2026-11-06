class_name ArenaNight
extends RefCounted
## The arena district on an event night (rc5-arena-night, refcam `arena_night` in
## tools/refcams/cameras_w8.json; docs/HANDOFF.md "STARLIGHT PLAZA on an event night").
##
## What the view gave away at 21:00, in the order the eye lands on it:
## 1. Two blank walls: the theatre's dark box over its glass lobby and the cinema block over the
##    screens were 40 % of the frame, flat navy panels with nothing on them. `facades()`: the
##    theatre's plaza face gets vertical LED blades (a gradient up each one), both boxes a lit cove
##    band along the parapet, and the cinema block the plaza's name in channel letters between
##    the screens and its parapet.
## 2. The screens lit nothing: `spill()` lays a pool in front of each one whose colour is the
##    screen's current slide (shaders/arena_spill.gdshader, the screen shader's own pick), and on
##    Forward+ desktop one cool OmniLight in front of the screen wall for the people.
## 3. The hotel read as an office slab with a dark top: `hotel_crown()` lights the crown from inside
##    (a lantern behind the glass fins, an LED band at its foot and lip), the long faces' name bigger.
## 4. No event: `event_tonight()` (a hash of seed + night against `EVENT_ODDS`) brings out
##    searchlight carts on the plaza and at the arena's corner (NightLife's SkyBeam) and a fuller
##    plaza (`crowd_gain()`).
## Every roll is a hash. ARENA_NIGHT=0 in the environment is the A/B (the district as before);
## ARENA_EVENT=1 / 0 forces an event night on / off.

static var enabled: bool = OS.get_environment("ARENA_NIGHT") != "0"

## Share of nights the arena has an event (most do: a home team and the concerts between).
const EVENT_ODDS := 0.62
## The plaza's people on an event night, times its own count (PlazaCrowd still caps the density).
const EVENT_CROWD := 1.8

## The emissive gain of the facade's LED (unshaded albedo over 1 blooms on both renderers).
const LED_GAIN := 1.45
## Theatre blades: spacing along the face (m), width, how far proud.
const BLADE_PITCH := 4.2
const BLADE_W := 0.28
const BLADE_PROUD := 0.18
## The two colours up a blade (bottom, top), display numbers.
const BLADE_LOW := Color(0.36, 0.22, 1.0)
const BLADE_HIGH := Color(1.0, 0.3, 0.72)
const COVE := Color(1.0, 0.82, 0.62)
const PLAZA_NAME := "STARLIGHT PLAZA"
## The hotel crown's lantern (display numbers) and its gain.
const CROWN_LIGHT := Color(0.62, 0.8, 1.0)
const CROWN_GAIN := 1.15

## The event night the last plaza build decided (crowd_gain() reads it: the crowd is asked for
## right after the landmark is built, CityChunk._build_landmarks()).
static var event_now: bool = false

static var _mats: Dictionary = {}


static func env_event() -> int:
	var e := OS.get_environment("ARENA_EVENT")
	return -1 if e == "" else int(e)


static func _h01(parts: Array) -> float:
	return float(absi(hash(parts)) % 100003) / 100003.0


## Whether night `night` (NightLife.night_now()) has an event at the arena.
static func event_tonight(seed_value: int, night: int) -> bool:
	var f := env_event()
	if f >= 0:
		return f == 1
	return _h01([seed_value, night, "arena_event"]) < EVENT_ODDS


## Whether the detailed copy being built now is on an event night, at an hour the event is on.
static func event_for_build() -> bool:
	var node := CivicSites.ctx.get("chunk", null) as Node
	if node == null:
		return false
	var plan_seed := int((node as CityChunk).plan.seed)
	var hour := NightLife.hour_now(node)
	var h := fposmod(hour, 24.0)
	if h < 17.5 and h > 1.0 and env_event() != 1:
		return false
	return event_tonight(plan_seed, NightLife.night_now(node, hour))


## The plaza crowd's count on an event night.
static func crowd_gain(base: int) -> int:
	if not enabled or not event_now:
		return base
	return roundi(float(base) * EVENT_CROWD)


## The LED's material (shaders/arena_led.gdshader): the vertex colour in display numbers times
## `gain`, full after dark, dull by day.
static func led_material(key: String, gain: float) -> ShaderMaterial:
	if _mats.has(key):
		return _mats[key]
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/arena_led.gdshader")
	mat.set_shader_parameter("gain", gain)
	_mats[key] = mat
	return mat


## 1. The facades' light: blades up the theatre's plaza face over its lobby, cove bands on both
## parapets, the plaza's name on the cinema block. `face_x` the theatre's plaza face, `z0..z1` the
## run of it over the lobby, `th_top` its parapet; `nb` the cinema block, `face_z` its plaza face,
## `nb_top` its parapet. Near and far copies alike (the far copy is what the freeway sees).
static func facades(g: LandmarkGeo, batch: MultiMeshBatch, face_x: float, z0: float, z1: float, th_top: float,
		nb: Rect2, face_z: float, nb_top: float, y0: float, detailed: bool) -> void:
	if not enabled:
		return
	g.use("an_led", led_material("led", LED_GAIN))
	# From over the theatre's name on the lobby roof to just under the parapet.
	var lo := y0 + 18.0
	var hi := th_top - 1.4
	var n := maxi(2, int((z1 - z0) / BLADE_PITCH))
	var segs := 6 if detailed else 2
	for i in n:
		var z := z0 + (float(i) + 0.5) * (z1 - z0) / float(n)
		for s in segs:
			var t0 := float(s) / float(segs)
			var t1 := float(s + 1) / float(segs)
			var c := BLADE_LOW.lerp(BLADE_HIGH, (t0 + t1) * 0.5)
			# Each blade fades out toward both ends, so it reads as a light line, not a stripe.
			var fade := sin(PI * (t0 + t1) * 0.5)
			c = c * (0.35 + 0.65 * fade)
			g.box("an_led", Vector3(face_x + BLADE_PROUD * 0.5, lerpf(lo, hi, (t0 + t1) * 0.5), z),
				Vector3(BLADE_PROUD, (hi - lo) / float(segs) + 0.02, BLADE_W), Color(c.r, c.g, c.b))
	# Cove bands along the parapets (the theatre's plaza edge, the cinema block's south edge).
	g.box("an_led", Vector3(face_x + 0.12, th_top - 0.5, (z0 + z1) * 0.5), Vector3(0.24, 0.22, z1 - z0 + 4.0), COVE)
	g.box("an_led", Vector3(nb.get_center().x, nb_top - 0.5, face_z + 0.12), Vector3(nb.size.x - 1.0, 0.22, 0.24), COVE)
	g.box("an_led", Vector3(nb.get_center().x, y0 + 20.2, face_z + 0.12), Vector3(nb.size.x - 1.0, 0.14, 0.2), COVE * 0.8)
	# The plaza's name, lit, centred between the screens' top and the parapet.
	batch.add("an_plaza_name", Signage.text_mesh(PLAZA_NAME, 2.6, Signage.Letters.LIT),
		Transform3D(LandmarkArenaDistrict._face(PI, 1.0), Vector3(nb.get_center().x, y0 + 23.6, face_z + 0.3)), Color(1.0, 0.9, 0.78))
	batch.set_no_shadow("an_plaza_name")


## 2. A screen's pool on the ground in front of it: `at` the screen's centre (its face), `w` its
## width, `fwd` the way it faces (horizontal), `seed_value` the screen's seed (LedScreen.add()).
static func spill(parent: Node3D, at: Vector3, w: float, fwd: Vector3, seed_value: float, y0: float, depth: float = 26.0, strength: float = 0.55) -> void:
	if not enabled:
		return
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/arena_spill.gdshader")
	mat.set_shader_parameter("seed", seed_value)
	mat.set_shader_parameter("slide_count", LedScreen.SLIDES.size())
	var qw := w + 12.0
	mat.set_shader_parameter("screen_share", clampf(w / qw, 0.2, 0.95))
	mat.set_shader_parameter("strength", strength)
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	var mi := MeshInstance3D.new()
	mi.name = "ArenaSpill%d" % parent.get_child_count()
	mi.mesh = quad
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	var f := Vector3(fwd.x, 0.0, fwd.z).normalized()
	var right := Vector3.UP.cross(f)
	# Lie the unit quad flat: its +Y (UV v = 0) onto -f, back to the wall; its normal up.
	var xf := Transform3D(Basis(right, -f, Vector3.UP).scaled_local(Vector3(qw, depth, 1.0)), Vector3(at.x, y0 + 0.06, at.z) + f * depth * 0.5)
	mi.transform = xf
	mi.visibility_range_end = 240.0
	parent.add_child(mi)


## A cool light in front of the screen wall for the people on the plaza (Forward+ desktop: the
## spill pools do the ground everywhere). In the lamp_light group, so DayNight drives it.
static func screen_light(parent: Node3D, at: Vector3) -> void:
	if not enabled or OS.has_feature("web") or RenderingServer.get_rendering_device() == null:
		return
	var light := OmniLight3D.new()
	light.name = "ArenaScreenLight"
	light.position = at
	light.omni_range = 34.0
	light.omni_attenuation = 1.4
	light.light_color = Color(0.78, 0.82, 1.0)
	light.light_energy = 0.0
	light.set_meta("lamp_gain", 1.3)
	light.shadow_enabled = false
	light.distance_fade_enabled = true
	light.distance_fade_begin = 110.0
	light.distance_fade_length = 30.0
	light.add_to_group("lamp_light")
	parent.add_child(light)


## 3. The hotel's crown: a lantern inside the screen of glass fins (`sc` the slab's centre, `slab`
## its size, `top` the roof), an LED band at its foot and at its lip.
static func hotel_crown(g: LandmarkGeo, sc: Vector3, slab: Vector3, top: float) -> void:
	if not enabled:
		return
	g.use("an_crown", led_material("crown", CROWN_GAIN))
	# The lantern: lit glass a metre inside the fins, brightest low (an uplit screen).
	var steps := 4
	for i in steps:
		var t := (float(i) + 0.5) / float(steps)
		var c := CROWN_LIGHT * lerpf(1.0, 0.55, t)
		g.box("an_crown", Vector3(sc.x, top + 0.5 + t * 9.0, sc.z), Vector3(slab.x - 1.6, 9.0 / float(steps) + 0.02, slab.z - 1.6), Color(c.r, c.g, c.b))
	g.box("an_crown", Vector3(sc.x, top + 1.3, sc.z), Vector3(slab.x + 1.2, 0.5, slab.z + 1.2), Color(1.0, 1.0, 1.0))
	g.box("an_crown", Vector3(sc.x, top + 10.0, sc.z), Vector3(slab.x + 0.9, 0.3, slab.z + 0.9), CROWN_LIGHT)


## The crown's glass fins' material key: lit from below like the lantern behind them (a fin's
## faces glow, brightest at its foot), or the old plain white fin.
static func crown_fin_key(g: LandmarkGeo) -> String:
	if not enabled:
		return "fin"
	g.use("an_fin", led_material("crown_fin", 0.75))
	return "an_fin"


## The hotel name's height on the long faces (3.2 m before).
static func hotel_name_height(old: float) -> float:
	return 4.6 if enabled else old


## 4. Searchlights for an event night: carts in the landmark's frame at `spots` (x, z, heading
## yaw: the way the beams lean), in `batch` and their SkyBeams under `parent`.
static func searchlights(parent: Node3D, batch: MultiMeshBatch, spots: Array, y0: float, seed_value: int) -> void:
	if not enabled:
		return
	for i in spots.size():
		var s: Vector3 = spots[i]
		var yaw_b := Basis(Vector3.UP, s.z)
		var xf := Transform3D(yaw_b, Vector3(s.x, y0, s.y))
		var paint: Color = NightLife.CART_PAINTS[i % NightLife.CART_PAINTS.size()]
		batch.add("an_cart", NightLifeKit.searchlight_cart(), xf, Color.WHITE, Color(paint.r, paint.g, paint.b, 0.5))
		var beam := SkyBeam.new()
		beam.name = "ArenaBeam%d" % i
		beam.seed_value = hash([seed_value, "arena_beam", i])
		beam.with_head = true
		beam.transform = Transform3D(yaw_b, xf * Vector3(0.0, NightLifeKit.YOKE_Y, 0.35))
		parent.add_child(beam)
