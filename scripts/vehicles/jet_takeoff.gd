class_name JetTakeoff
extends RefCounted
## An airliner taking off at night, seen from the grass beside the runway (refcam5 "jet_takeoff",
## tools/refcams/cameras_w8.json: 27R's departure end at 19:15 clear). What that view found, kept
## in one place so JET_TAKEOFF=0 is the old jet:
##
## - The infield the camera stands on was a black void filling the lower half of the frame: the
##   airport's grass is a flat lawn slab with no blades, and at night nothing lit it. infield()
##   plants the city's lawn tufts on it (FULL chunks, at `TUFT_DENSITY` a square metre, cut into
##   `TUFT_PATCH` m patches so a long strip is not thinned) and lays each elevated edge light's
##   glow on the ground round its foot (white by the runways, blue by the taxiways): one shadowless
##   additive batch, `jt_edge_pool`, lamp_factor-driven like every pool.
## - The engines at take-off thrust bent the air for 26 m behind the nozzle, a few pixels of wobble
##   lost in a still. A real take-off blast shimmers a long way back over the runway: the cones
##   grow with the thrust (`PLUME_GAIN`) and bend harder (`BEND_GAIN`) - at idle they are as they
##   were.
## - Its landing and taxi lights were glare dots: seen from the side at night a real one's beam is
##   a shaft of lit haze reaching down the runway ahead. One additive cone a lamp
##   (shaders/jet_beam.gdshader), shown only while the landing lights are on and only after dark
##   (lamp_factor), fog-free, gone past `BEAM_RANGE`. Desktop and web alike (no screen read).
## - The wingtip nav lights and strobes were hung at a fixed 36 m span; the airliner model's is
##   32 m, so from beside the runway they floated two metres off each tip (and 1.7 m under it, 2.5 m
##   aft of it: the tip rises with the dihedral). fitted_span() takes the model's own span
##   (AmbientJet._build_model(), before the lights are built) and `AIRLINER_TIP` its tip's height
##   and station, measured off jet_airliner.glb's vertices.
## - A jet that started out rolling (a staged take-off) never had its landing lights or strobes
##   switched on (only LINEUP did), and AirportNight.landing_pool() threw on the unset parameter
##   every tick: the roll turns them on.
## - Stills: refcams' "air_flash" holds the staged jet's strobes and beacons at their flash
##   (aircraft_lights.gdshader `flash_hold`); in play they flash as before.
## Nothing rolls; every number is a constant here.

static var enabled: bool = OS.get_environment("JET_TAKEOFF") != "0"

## The infield's tufts a square metre (the lawns' 1.9 thinned: mown, dry airfield grass) and the
## largest patch one _add_grass() call takes (its own cap per patch would thin a long strip).
const TUFT_DENSITY := 0.7
const TUFT_PATCH := 60.0
## An edge light's glow on the ground: radius (m) and strength, white and blue.
const EDGE_POOL_RADIUS := 8.0
const EDGE_POOL_STRENGTH := 0.55
const TAXI_POOL_STRENGTH := 0.35
## The infield tufts' lawn: the straw's tint (sRGB, LawnsCloseup's look) and full dryness, so the
## blades are the dry airfield grass under them rather than a watered lawn's green.
const TUFT_TINT := Color(0.86, 0.80, 0.58)
## The exhaust shimmer's length and bend at take-off thrust against idle (1 = the old cone).
const PLUME_GAIN := 2.1
const BEND_GAIN := 1.8
## The landing lights' beams: length (m), how wide they open (radians, half angle) and how bright.
const BEAM_LENGTH := 55.0
const BEAM_HALF_ANGLE := 0.09
const BEAM_STRENGTH := 0.07
const BEAM_RANGE := 900.0


## The infield of an airport chunk (Airport.build_chunk(), FULL): tufts on the grass, the edge
## lights' glow round their feet. Every roll is _add_grass()'s own hash of the patch.
static func infield(ch: CityChunk, area: Rect2, macro: MacroMap) -> void:
	if not enabled or ch.level != CityChunk.Level.FULL:
		return
	var lawn := _tuft_look()
	for g: Rect2 in Airport.grass_rects(macro):
		var r := g.intersection(area)
		if r.size.x < 2.0 or r.size.y < 2.0:
			continue
		var nx := maxi(1, ceili(r.size.x / TUFT_PATCH))
		var nz := maxi(1, ceili(r.size.y / TUFT_PATCH))
		for i in nx:
			for j in nz:
				var sub := Rect2(r.position + Vector2(r.size.x * i / nx, r.size.y * j / nz), Vector2(r.size.x / nx, r.size.y / nz))
				ch._add_grass(sub, TUFT_DENSITY / ch.grass_per_sqm, 0.0, [], lawn, g, Airport.GRASS_TOP)
	var white := PropFactory.light_pool(Color(1.0, 0.9, 0.72), EDGE_POOL_STRENGTH, 3.0)
	var blue := PropFactory.light_pool(Color(0.35, 0.5, 1.0), TAXI_POOL_STRENGTH, 3.0)
	var flat := Basis(Vector3.RIGHT, -PI * 0.5).scaled_local(Vector3(EDGE_POOL_RADIUS * 2.0, EDGE_POOL_RADIUS * 2.0, 1.0))
	for spec: Array in Airport.edge_light_spots(macro):
		var p: Vector3 = spec[0]
		if not area.has_point(Vector2(p.x, p.z)):
			continue
		# A pool's instance custom must be clear: alpha 1 makes light_pool.gdshader a NightLamps
		# point source (CLAUDE.md, the port at night).
		ch._batch.add("jt_edge_pool", white if bool(spec[1]) else blue, Transform3D(flat, Vector3(p.x, Airport.GRASS_TOP + 0.03, p.z)), Color.WHITE, Color(0.0, 0.0, 0.0, 0.0))
	ch._batch.set_no_shadow("jt_edge_pool")


## The wingspan the lights are hung at: the model's own (`measured`, metres) when it is a sane
## share of the old figure, else the old one.
static func fitted_span(old: float, measured: float) -> float:
	if not enabled or measured < old * 0.6 or measured > old * 1.3:
		return old
	return measured


## The airliner model's wingtip: height over the wheels as a share of the model's height, and how
## far aft of the body's origin as a share of its length (5.2 m up, 2.4 m aft on the 38 m jet).
const AIRLINER_TIP := Vector2(0.38, 0.063)


## The shimmer cone's length factor at engine level `level` (0 idle .. 1 take-off).
static func plume_scale(level: float) -> float:
	if not enabled:
		return 1.0
	return lerpf(1.0, PLUME_GAIN, smoothstep(0.55, 1.0, level))


## The shimmer's bend at `level`, from the material's old `base`.
static func bend(base: float, level: float) -> float:
	if not enabled:
		return base
	return base * lerpf(1.0, BEND_GAIN, smoothstep(0.55, 1.0, level))


static var _tuft_mat: Material = null


## A stand-in lawn material carrying only the look LawnsCloseup reads off a lawn (lawn_look()).
static func _tuft_look() -> Material:
	if _tuft_mat == null:
		_tuft_mat = StandardMaterial3D.new()
		_tuft_mat.set_meta("lawn_seed_index", 517)
		_tuft_mat.set_meta("lawn_tint", TUFT_TINT)
		_tuft_mat.set_meta("lawn_dryness", 1.0)
		_tuft_mat.set_meta("lawn_striped", false)
	return _tuft_mat


static var _beam_mesh: CylinderMesh = null
static var _beam_mat: ShaderMaterial = null


## One beam under `parent` for each landing light `spots` ([position, direction] in the jet's
## frame). Returns the beams (hidden until show_beams()).
static func build_beams(parent: Node3D, spots: Array) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if not enabled or parent == null:
		return out
	if _beam_mesh == null:
		_beam_mesh = CylinderMesh.new()
		_beam_mesh.top_radius = 0.35
		_beam_mesh.bottom_radius = BEAM_LENGTH * tan(BEAM_HALF_ANGLE)
		_beam_mesh.height = BEAM_LENGTH
		_beam_mesh.radial_segments = 14
		_beam_mesh.rings = 1
		_beam_mesh.cap_top = false
		_beam_mesh.cap_bottom = false
		_beam_mat = ShaderMaterial.new()
		_beam_mat.shader = load("res://shaders/jet_beam.gdshader")
		_beam_mat.set_shader_parameter("strength", BEAM_STRENGTH)
		_beam_mesh.material = _beam_mat
	for s: Array in spots:
		var at: Vector3 = s[0]
		var dir: Vector3 = (s[1] as Vector3).normalized()
		var mi := MeshInstance3D.new()
		mi.name = "LandingBeam%d" % out.size()
		mi.mesh = _beam_mesh
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		mi.visibility_range_end = BEAM_RANGE
		# The cylinder's axis is +Y with its narrow top at +h/2: the top sits at the lamp and the
		# cone opens along `dir`, so the mesh's -Y runs along `dir`.
		var y := -dir
		var x := y.cross(Vector3.FORWARD if absf(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
		var z := x.cross(y).normalized()
		var b := Basis(x, y, z)
		mi.transform = Transform3D(b, at + dir * BEAM_LENGTH * 0.5)
		mi.visible = false
		parent.add_child(mi)
		out.append(mi)
	return out


## Shows or hides the beams (the landing lights on and the jet flying, after dark).
static func show_beams(beams: Array[MeshInstance3D], on: bool) -> void:
	for b in beams:
		if is_instance_valid(b) and b.visible != on:
			b.visible = on
