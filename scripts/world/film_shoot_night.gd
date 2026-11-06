class_name FilmShootNight
extends RefCounted
## A film shoot after dark (refcam5 "film_shoot_night", docs/HANDOFF.md "The film shoot at 22:00"):
## what the set's lamps DO. FilmShootBuild drew the HMIs as glowing lenses and the balloon as a lit
## ball, but at night they lit nothing - the set was a dark stretch of street with two bright dots,
## where a real night shoot is a pool of daylight in the dark city. One hook line at the end of
## FilmShootBuild.build() adds, in the FULL chunk that owns the shoot:
## - two SpotLight3Ds, one in each HMI, aimed at the action (desktop; their energy follows
##   DayNight.lamp_now, `FilmNightLights`), and the balloon's own light made a balloon's - wide,
##   soft and several times a street lamp (its OmniLight3D's range and `lamp_gain`);
## - ONE additive mesh (`FilmShootNightGlow`, shaders/film_night.gdshader, every renderer): a bloom
##   over each HMI lens and the balloon, the HMIs' beams as faint shafts of lit haze to the action,
##   the pools of light on the ground (the HMIs' crossing throw on the actors' pavement, the
##   balloon's soft wash on the road, a work light at each trailer's door and the generator).
## Nothing per frame but the lights' energy on a 0.3 s tick. `FILM_SHOOT_NIGHT=0` is the A/B.

static func _static_init() -> void: LoadPulse.compiled()  # a boot frame: docs/HANDOFF.md "The boot compile"

static var enabled: bool = OS.get_environment("FILM_SHOOT_NIGHT") != "0"

## The HMIs' real lights: range (m), cone half-angle (degrees), energy x DayNight.lamp_now.
const HMI_RANGE := 34.0
const HMI_ANGLE := 24.0
const HMI_GAIN := 5.0
const HMI_COLOR := Color(0.9, 0.95, 1.0)
## The balloon's light (FilmShootBuild's FilmBalloonLight): range and a share over a street lamp.
const BALLOON_RANGE := 26.0
const BALLOON_GAIN := 1.8
## The fill at the action (FilmShootBuild's FilmFillLight): a share over a street lamp.
const FILL_GAIN := 1.4
## Daylight-balanced HMIs, a warm-white balloon, tungsten work lights at the basecamp (sRGB).
const HMI_TINT := Color(0.86, 0.92, 1.0)
const BALLOON_TINT := Color(1.0, 0.95, 0.86)
const WORK_TINT := Color(1.0, 0.78, 0.5)
## Sizes (m): bloom over an HMI lens, over the balloon; the HMI pool's radii along / across its
## throw; the balloon's pool radius; a work light's pool radius.
const HMI_BLOOM := 2.4
const BALLOON_BLOOM := 5.5
const HMI_POOL := Vector2(9.0, 6.0)
const BALLOON_POOL := 12.0
const WORK_POOL := 3.2
## Strengths (COLOR.a: 0..1).
const HMI_BLOOM_K := 1.0
const BALLOON_BLOOM_K := 0.55
const SHAFT_K := 1.0
const HMI_POOL_K := 0.6
const BALLOON_POOL_K := 0.45
const WORK_POOL_K := 0.6
## The barricades' sheeting glow after dark (film_shoot.gdshader's `stripe_glow`, was 0.35).
const STRIPE_GLOW := 0.12

static var _material: ShaderMaterial


static func material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = load("res://shaders/film_night.gdshader")
	return _material


## FilmShootBuild.build()'s hook (after its lights): the glow mesh and the lights.
static func dress(ch: CityChunk, m: Dictionary, lay: Dictionary) -> void:
	if not enabled:
		return
	FilmShootKit.material().set_shader_parameter("stripe_glow", STRIPE_GLOW)
	FilmShootKit.material().set_shader_parameter("canvas_look", 1.0)
	var acc := Acc.new()
	var act: Dictionary = lay.action
	var act2 := FilmShoot.point(m, float(act.t), float(act.o))
	var act_y := ch.ground_y(act2.x, act2.y)
	var target := Vector3(act2.x, act_y + 1.3, act2.y)
	var lights: Array = []
	for h: Dictionary in lay.hmis:
		var lens := hmi_lens(ch, m, h)
		var dir := (target - lens).normalized()
		acc.bloom(lens, dir, HMI_BLOOM, HMI_TINT, HMI_BLOOM_K)
		acc.shaft(lens, target, 3.2, HMI_TINT, SHAFT_K)
		lights.append([lens, target])
	# The HMIs' crossing throw on the actors' pavement: one pool from each, stretched along its throw.
	for h: Dictionary in lay.hmis:
		var lens := hmi_lens(ch, m, h)
		var flat := Vector2(target.x - lens.x, target.z - lens.z).normalized()
		var c := Vector2(act2.x, act2.y) + flat * 1.5
		acc.pool(Vector3(c.x, act_y + 0.03, c.y), flat, HMI_POOL, HMI_TINT, HMI_POOL_K)
	# The balloon: its bloom and the soft wash it lays on the road under it.
	var bl: Dictionary = lay.balloon
	var b2 := FilmShoot.point(m, float(bl.t), float(bl.o))
	var by := CityChunk.ROAD_TOP + ch._gy(b2.x, b2.y)
	acc.bloom(Vector3(b2.x, by + FilmShootKit.BALLOON_Y, b2.y), Vector3.UP, BALLOON_BLOOM, BALLOON_TINT, BALLOON_BLOOM_K)
	acc.pool(Vector3(b2.x, by + 0.03, b2.y), Vector2(1, 0), Vector2(BALLOON_POOL, BALLOON_POOL), BALLOON_TINT, BALLOON_POOL_K)
	# Work lights at the basecamp: over each trailer's door side and the generator, toward the road.
	var cs := float(m.camp_side)
	for c: Dictionary in lay.camp:
		var o := float(c.o) - cs * (float(c.w) * 0.5 + 1.3)
		var p := FilmShoot.point(m, float(c.t), o)
		var gy := CityChunk.ROAD_TOP + ch._gy(p.x, p.y)
		acc.pool(Vector3(p.x, gy + 0.03, p.y), Vector2(1, 0), Vector2(WORK_POOL, WORK_POOL), WORK_TINT, WORK_POOL_K)
		var lamp := FilmShoot.point(m, float(c.t), float(c.o) - cs * float(c.w) * 0.52)
		acc.bloom(Vector3(lamp.x, gy + 2.7, lamp.y), Vector3.UP, 0.6, WORK_TINT, 0.5)
	var mi := MeshInstance3D.new()
	mi.name = "FilmShootNightGlow"
	mi.mesh = acc.mesh()
	mi.material_override = material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	mi.visibility_range_end = FilmShootBuild.BIG_DRAW
	# The quads are moved in the vertex shader (blooms grow with distance): a box round them all.
	mi.custom_aabb = acc.bounds().grow(8.0)
	ch.add_child(mi)
	if OS.has_feature("web"):
		return
	_lights(ch, lights)


## Micromobility's keep-clear hook: the film set's pavement (the actors' marks and the stretch
## the HMIs throw on) is cleared of shared scooters and bikes, as a location crew clears it. Points
## [Vector2, radius] for chunk (ix, iz) - the shoot's set side may be either block beside its street.
static func keep_clear_points(plan: CityPlan, ix: int, iz: int) -> Array:
	var out: Array = []
	if not enabled or not FilmShoot.enabled or plan == null or plan.macro == null:
		return out
	for owner: Vector2i in [Vector2i(ix, iz), Vector2i(ix - 1, iz), Vector2i(ix, iz - 1)]:
		var m := FilmShoot.shoot_of_chunk(plan, owner.x, owner.y)
		if m.is_empty():
			continue
		var lay := FilmShoot.layout(m)
		var tr: Dictionary = lay.track
		var act: Dictionary = lay.action
		var t := float(tr.t0) - 10.0
		while t <= float(tr.t1) + 10.0:
			out.append([FilmShoot.point(m, t, float(act.o)), 3.2])
			t += 3.0
	return out


## Where an HMI's lens is (its fresnel's centre, chunk space), FilmShootKit.hmi()'s numbers.
static func hmi_lens(ch: CityChunk, m: Dictionary, h: Dictionary) -> Vector3:
	var xf := FilmShootBuild.xf_at(m, float(h.t), float(h.o), h.aim)
	var tilt := Basis(Vector3.RIGHT, deg_to_rad(8.0))
	var local := Vector3(0.0, FilmShootKit.HMI_Y, 0.0) + tilt * Vector3(0.0, 0.0, 0.32)
	var p := xf * local
	p.y += ch._gy(xf.origin.x, xf.origin.z)
	return p


static func _lights(ch: CityChunk, lights: Array) -> void:
	var holder := FilmNightLights.new()
	holder.name = "FilmNightLights"
	ch.add_child(holder)
	var i := 0
	for pair: Array in lights:
		var lens: Vector3 = pair[0]
		var target: Vector3 = pair[1]
		var s := SpotLight3D.new()
		s.name = "HMI_%d" % i
		s.spot_range = HMI_RANGE
		s.spot_angle = HMI_ANGLE
		s.spot_angle_attenuation = 0.6
		s.spot_attenuation = 0.9
		s.light_color = HMI_COLOR
		s.shadow_enabled = false
		s.light_energy = 0.0
		s.visible = false
		s.distance_fade_enabled = true
		s.distance_fade_begin = 160.0
		s.distance_fade_length = 40.0
		# Chunk space (the holder sits at the chunk's origin; look_at_from_position would take these
		# for global positions, which they are not once the origin has moved).
		s.transform = Transform3D(Basis.looking_at(target - lens, Vector3.UP), lens)
		holder.add_child(s)
		holder.spots.append(s)
		i += 1
	# FilmShootBuild's balloon and fill lights (lamp_light omnis: DayNight sets their energy x lamp_gain).
	var bl := ch.get_node_or_null("FilmBalloonLight") as OmniLight3D
	if bl != null:
		bl.omni_range = BALLOON_RANGE
		bl.omni_attenuation = 1.4
		bl.set_meta("lamp_gain", BALLOON_GAIN)
	var fl := ch.get_node_or_null("FilmFillLight") as OmniLight3D
	if fl != null:
		fl.set_meta("lamp_gain", FILL_GAIN)


## Accumulates the glow mesh's quads (chunk space).
class Acc:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var idx := PackedInt32Array()
	var box := AABB()
	var any := false

	func _vert(p: Vector3, normal: Vector3, col: Color, a: Vector2, b: Vector2) -> void:
		v.append(p)
		n.append(normal)
		c.append(col)
		uv.append(a)
		uv2.append(b)
		if any:
			box = box.expand(p)
		else:
			box = AABB(p, Vector3.ZERO)
			any = true

	func _quad(base: int) -> void:
		idx.append_array(PackedInt32Array([base, base + 1, base + 2, base, base + 2, base + 3]))

	## A camera-facing glow at `at`: four vertices on the point (the vertex shader spreads them).
	func bloom(at: Vector3, facing: Vector3, size: float, tint: Color, k: float) -> void:
		var base := v.size()
		var col := Color(tint.r, tint.g, tint.b, k)
		for q: Vector2 in [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]:
			_vert(at, facing, col, q, Vector2(0.0, size))
		_quad(base)

	## A beam of lit haze from `a` to `b` (the vertex shader turns it about its axis to the eye).
	func shaft(a: Vector3, b: Vector3, width: float, tint: Color, k: float) -> void:
		var base := v.size()
		var axis := (b - a).normalized()
		var col := Color(tint.r, tint.g, tint.b, k)
		_vert(a, axis, col, Vector2(-1, 0), Vector2(1.0, width))
		_vert(a, axis, col, Vector2(1, 0), Vector2(1.0, width))
		_vert(b, axis, col, Vector2(1, 1), Vector2(1.0, width))
		_vert(b, axis, col, Vector2(-1, 1), Vector2(1.0, width))
		_quad(base)

	## A flat pool centred at `at`, its first radius along `along` (x, z), the second across.
	func pool(at: Vector3, along: Vector2, radii: Vector2, tint: Color, k: float) -> void:
		var base := v.size()
		var u := Vector3(along.x, 0.0, along.y).normalized() * radii.x
		var w := Vector3(-along.y, 0.0, along.x).normalized() * radii.y
		var col := Color(tint.r, tint.g, tint.b, k)
		for q: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			_vert(at + u * q.x + w * q.y, Vector3.UP, col, q, Vector2(2.0, 0.0))
		_quad(base)

	func bounds() -> AABB:
		return box

	func mesh() -> ArrayMesh:
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = v
		arr[Mesh.ARRAY_NORMAL] = n
		arr[Mesh.ARRAY_COLOR] = c
		arr[Mesh.ARRAY_TEX_UV] = uv
		arr[Mesh.ARRAY_TEX_UV2] = uv2
		arr[Mesh.ARRAY_INDEX] = idx
		var out := ArrayMesh.new()
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		return out
