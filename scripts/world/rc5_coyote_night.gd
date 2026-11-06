class_name Rc5CoyoteNight
extends RefCounted
## The suburban street at 02:00 (refcam5 `coyote_night` in tools/refcams/cameras_w8.json,
## docs/HANDOFF.md "Coyotes and raccoons at 02:00"). What gave the small hours away as a game:
##   * EYESHINE: a coyote or a raccoon at night is first seen as two points of light - the
##     tapetum throwing the light back toward the eye. Every WildAnimal carries a pair of
##     camera-facing sprites on its head bone (`attach_eyes()`, one hook in WildAnimal._ready()),
##     shaders/wild_eyeshine.gdshader: lit only after dark (lamp_factor), only while the eye faces
##     the camera, never under `MIN_PX` pixels, in the species' tapetum colour (`TAPETUM`).
##   * THE SMALL HOURS' STREET: the house blocks of the suburbs and the beach town kept their whole
##     planned crowd at 02:00 (a chunk builds its count whatever the hour, and BusyStreets only thins
##     out of view toward a quarter of it): people strolling a dark residential street at 2 a.m.
##     `crowd_gain()` (pure, the hour) takes those blocks down to `SMALL_HOURS_KEEP` between
##     midnight and five; a walker the block's build makes is kept by a hash of its seed after its
##     roll (`keep_walker()`, nothing else moves) and BusyStreets tops up to the same share.
##   * TIMERS: landscape lighting (path lights, facade and cypress uplights) is on a timer that
##     ends at midnight (`timer_level()`: off from 00:30 until morning); the porch lights stay. The
##     glow instances carry alpha + 2 (`TIMER_FLAG`) and house_glow / house_lamp read `city_hour`.
##   * NO DRAWN CONE IN CLEAR AIR: the lamp's light shaft (night_shaft.gdshader) read as a pink
##     column against a clear night sky; `clear_cut` fades it out below the haze of an overcast night
##     (halos stay: they are the lens, not the air).
## RC5_COYOTE_NIGHT=0 in the environment is the A/B (every change off, the old look exactly).

static func _static_init() -> void: LoadPulse.compiled()  # a boot frame: docs/HANDOFF.md "The boot compile"

static var enabled: bool = OS.get_environment("RC5_COYOTE_NIGHT") != "0"

## Tapetum colours (display numbers, added): a canid's yellow-green, a raccoon's amber, a deer's
## pale blue-white, the small ones a dull red-amber.
const TAPETUM := {
	"coyote": Color(0.86, 1.0, 0.52), "raccoon": Color(1.0, 0.86, 0.42), "deer": Color(0.82, 0.94, 1.0),
	"rabbit": Color(1.0, 0.55, 0.3), "squirrel": Color(1.0, 0.6, 0.32),
}
## The sprite's smallest size on screen (pixels at 1080 lines) and its strength.
const MIN_PX := 2.6
const EYE_GAIN := 3.5
## Share of a suburban house block's walkers out at 01:00-04:30 (ramped from 23:00, back by 06:00).
const SMALL_HOURS_KEEP := 0.12
## Landscape timers: on until 23:30, off by 00:30, back on (they are off by day anyway) from 17:00.
const TIMER_OFF_FROM := 23.5
const TIMER_OFF_BY := 24.5
const TIMER_FLAG := 2.0

static var _eye_mats: Dictionary = {}
static var _eye_mesh: QuadMesh


## 1 while the landscape timers keep their lamps on at `hour`, 0 once they are off (pure; the
## shaders' copy reads city_hour).
static func timer_level(hour: float) -> float:
	var h := fposmod(hour, 24.0)
	if h < 12.0:
		h += 24.0
	return 1.0 - clampf((h - TIMER_OFF_FROM) / (TIMER_OFF_BY - TIMER_OFF_FROM), 0.0, 1.0)


## The share of a suburban house block's planned walkers out at `hour` (1 outside the small hours).
static func small_hours(hour: float) -> float:
	var h := fposmod(hour, 24.0)
	if h >= 23.0:
		return lerpf(1.0, SMALL_HOURS_KEEP, clampf((h - 23.0) / 2.0, 0.0, 1.0))
	if h < 1.0:
		return lerpf(1.0, SMALL_HOURS_KEEP, clampf((h + 1.0) / 2.0, 0.0, 1.0))
	if h <= 4.5:
		return SMALL_HOURS_KEEP
	return lerpf(SMALL_HOURS_KEEP, 1.0, clampf((h - 4.5) / 1.5, 0.0, 1.0))


## A house block of the suburbs or the beach town (where the small hours empty the pavements).
static func house_block(plan: CityPlan, rect: Rect2) -> bool:
	if plan == null:
		return false
	var bi := plan.block_index_at(rect.get_center())
	var b: Dictionary = plan.block(bi.x, bi.y)
	return int(b.get("kind", -1)) == CityPlan.BlockKind.BUILDINGS and not b.has("site") \
		and int(b.get("district", -1)) in [CityPlan.District.SUBURBS, CityPlan.District.BEACHTOWN]


## BusyStreets' want for a block's ring at `hour`: the small hours' share on a house block.
static func crowd_gain(plan: CityPlan, rect: Rect2, hour: float) -> float:
	if not enabled:
		return 1.0
	var s := small_hours(hour)
	if s >= 0.999 or not house_block(plan, rect):
		return 1.0
	return s


## Whether the chunk keeps a walker its build just rolled (seed `seed_value`): on a house block in
## the small hours only its share, by a hash of the seed (the roll itself is made either way).
static func keep_walker(ch: Node, rect: Rect2, seed_value: int) -> bool:
	if not enabled:
		return true
	var plan: CityPlan = ch.get("plan")
	var keep := crowd_gain(plan, rect, BusyStreets.hour_now(ch)) * BusyStreets.crowd_factor(BusyStreets.hour_now(ch))
	if keep >= 0.999 or not house_block(plan, rect):
		return true
	return float(absi(hash([seed_value, "rc5_small_hours"])) % 1000) / 1000.0 < keep


## The flag a timed (landscape) glow instance's alpha carries.
static func timer_alpha(strength: float) -> float:
	return strength + TIMER_FLAG if enabled else strength


## The house glow / fixture materials: read the timers.
static func dress_house(mat: ShaderMaterial) -> void:
	if enabled and mat:
		mat.set_shader_parameter("timer_look", 1.0)


## The lamp shaft: none in clear air.
static func dress_shaft(mat: ShaderMaterial) -> void:
	if enabled and mat:
		mat.set_shader_parameter("clear_cut", 1.0)


## Two eyeshine sprites on the animal's head bone (WildAnimal._ready()).
static func attach_eyes(an: Node3D) -> void:
	if not enabled:
		return
	var rig: Variant = an.get("rig")
	var sp := String(an.get("species"))
	if rig == null or rig.get("skeleton") == null:
		return
	var skel: Skeleton3D = rig.skeleton
	var breed := String(rig.get("breed"))
	var bld = DogMesh.Builder.new(breed, 0)
	var head: Vector3 = bld.j["Head"]
	var att := BoneAttachment3D.new()
	att.bone_name = "Head"
	att.name = "Eyeshine"
	skel.add_child(att)
	for s in [-1.0, 1.0]:
		var ec: Array = bld.eye_centre(s)
		var c: Vector3 = ec[0]
		var look: Vector3 = (ec[1] as Vector3).normalized()
		var mi := MeshInstance3D.new()
		mi.mesh = _quad()
		mi.material_override = eye_material(sp, float(ec[2]))
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		mi.extra_cull_margin = 2.0
		# +Z of the node is the eye's look (the shader's facing term).
		var z := look
		var x := Vector3.UP.cross(z)
		if x.length_squared() < 1e-6:
			x = Vector3.RIGHT
		x = x.normalized()
		mi.transform = Transform3D(Basis(x, z.cross(x).normalized(), z), c - head)
		mi.visibility_range_end = 160.0
		att.add_child(mi)


static func _quad() -> QuadMesh:
	if _eye_mesh == null:
		_eye_mesh = QuadMesh.new()
		_eye_mesh.size = Vector2(1, 1)
	return _eye_mesh


static func eye_material(sp: String, r: float) -> ShaderMaterial:
	var key := "%s/%.4f" % [sp, r]
	if _eye_mats.has(key):
		return _eye_mats[key]
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/wild_eyeshine.gdshader")
	var c: Color = TAPETUM.get(sp, TAPETUM.coyote)
	m.set_shader_parameter("tint", Vector3(c.r, c.g, c.b))
	m.set_shader_parameter("eye_r", r)
	m.set_shader_parameter("min_px", MIN_PX)
	m.set_shader_parameter("gain", EYE_GAIN)
	_eye_mats[key] = m
	return m
