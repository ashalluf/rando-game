class_name Rc5CemeteryDawn
extends RefCounted
## The memorial park at dawn under the marine layer (refcam `cemetery_dawn`,
## tools/refcams/cameras_w8.json: Hollycrest at 06:30, eye level among the stones on the rise;
## docs/HANDOFF.md "The memorial park at dawn"). What the first frame gave away, fixed in order:
##
## - THE SUN UNDER THE DECK STILL MADE A GLARE PATH: a full stratus deck leaves no sun disc, yet
##   the cut sun kept its full specular, so every glossy surface toward the east (the dewy lawn
##   most of all) drew a hard white streak like a low clear sun on wet tarmac. `sun_specular()`
##   takes the sun's specular down with DayNight's `marine` (its diffuse light is untouched).
## - THE LAWN WAS A PRINTED CARPET: the park's turf had no blades (the block's grass step does not
##   run in a cemetery). `grass()` plants the city's own mown tufts (LawnsCloseup's blade and lawn
##   data) over the rise, off the drive, the buildings, the trunks and every stone.
## - NO MIST: at dawn under the deck a park on a rise sits in a low ground mist; the far trees and
##   the mausoleum stood as crisp as at noon. `mist_box()` lays a box over the chunk's part of the
##   site whose shader (`shaders/cemetery_mist.gdshader`) integrates a height mist hugging the
##   rise, wisped by slow noise, cut by the scene's depth; its strength is `mist()` (the morning
##   hours times how humid the weather is), pushed by `tick()` from DayNight.
## - THE LANTERNS WERE SIMPLY OFF: photocells switch on the ambient light, and under a June-gloom
##   deck it is still dusk-dark well after sunrise. `lamp_hold()` keeps the lamps on under the deck
##   until the sun is a dozen degrees up, fading: at 06:30 the lanterns are going out.
##
## `RC5_CEMETERY_DAWN=0` in the environment turns all four off (the A/B).

static func _static_init() -> void: LoadPulse.compiled()  # a boot frame: docs/HANDOFF.md "The boot compile"

static var enabled: bool = OS.get_environment("RC5_CEMETERY_DAWN") != "0"

## The sun's specular left under a full deck (1 = a clear sun's).
const MARINE_SPECULAR := 0.12
## The photocells' hold under the deck: full below HOLD.x of sun elevation (sin), gone at HOLD.y.
const HOLD := Vector2(0.04, 0.24)
## How much of the night's lamp level the hold keeps at most.
const HOLD_LEVEL := 0.8
## Grass density on the cemetery lawn (CityChunk._add_grass's scale: 1 a park's) and how far its
## cells draw (m): past ~60 m a mown tuft is under a pixel tall and the lawn's texture carries it
## (at 0.75 and the lawns' 86 m the blades cost +0.87 M triangles in the refcam).
const GRASS_DENSITY := 0.5
const GRASS_DRAW := 60.0
## The memorial park's lawn after the morning's watering under the deck: beaded dew, not a film
## (lawn.gdshader `spray_rough`; 0.32 a sprinkler's film, which mirrored the bright east sky as a
## glare path across the whole rise).
const DEW_ROUGH := 0.66
## How much of a mist's damp (Weather's road_mist) leaves leave unglazed (the `rc5_mist_leaf`
## global in foliage, foliage_tex, la_tree): the deck's 0.3 damp read as a rain soak on every crown,
## silver-white leaves against the grey sky.
const MIST_LEAF := 0.85
## Tufts kept this far (m) from a stone's centre.
const STONE_CLEAR := 0.75
## The mist box's height over the lawn's lowest point (m), the rise included.
const MIST_TOP := 14.0
## Mist: the morning's hours (rise, fall) and how much a clear morning keeps.
const MIST_HOURS := Vector4(4.3, 5.5, 8.4, 10.2)
const HUMID_CLEAR := 0.3

static var _mist_mats: Array[ShaderMaterial] = []
static var _mist_shader: Shader = null
static var mist_now: float = 0.0
static var _leaf_set: bool = false


## DayNight's sun specular for a `marine` share (0..1) of deck over the camera.
static func sun_specular(marine: float) -> float:
	if not enabled:
		return 1.0
	return lerpf(1.0, MARINE_SPECULAR, clampf(marine, 0.0, 1.0))


## The lamp level the photocells hold under the deck (0..1) at sun elevation `elevation` (sin).
static func lamp_hold(marine: float, elevation: float) -> float:
	if not enabled or marine <= 0.0 or elevation < -0.1:
		return 0.0
	return HOLD_LEVEL * clampf(marine, 0.0, 1.0) * (1.0 - smoothstep(HOLD.x, HOLD.y, elevation))


## The ground mist's strength (0..1) at `hour`: the morning's hours times how humid the air is -
## a full marine deck over the camera (DayNight.marine) 1, overcast or rain (weather_darken) 0.6,
## a clear morning HUMID_CLEAR, none in a Santa Ana.
static func mist(hour: float, marine: float, darken: float, santa_ana: float) -> float:
	if not enabled:
		return 0.0
	var h := fposmod(hour, 24.0)
	var t := smoothstep(MIST_HOURS.x, MIST_HOURS.y, h) * (1.0 - smoothstep(MIST_HOURS.z, MIST_HOURS.w, h))
	var humid := maxf(maxf(clampf(marine, 0.0, 1.0), 0.6 * clampf(darken, 0.0, 1.0)), HUMID_CLEAR)
	return clampf(t * humid * (1.0 - clampf(santa_ana, 0.0, 1.0)), 0.0, 1.0)


## From DayNight._apply(): the mist's strength and colour (the fog's light, linear) to every box.
static func tick(hour: float, marine: float, darken: float, santa_ana: float, fog_light: Color) -> void:
	mist_now = mist(hour, marine, darken, santa_ana)
	if not _leaf_set:
		_leaf_set = true
		RenderingServer.global_shader_parameter_set("rc5_mist_leaf", MIST_LEAF if enabled else 0.0)
	if _mist_mats.is_empty():
		return
	var lin := fog_light.srgb_to_linear()
	var col := Vector3(lin.r, lin.g, lin.b)
	var keep: Array[ShaderMaterial] = []
	for m in _mist_mats:
		if m == null or m.get_reference_count() <= 1:
			continue
		m.set_shader_parameter("amount", mist_now)
		m.set_shader_parameter("mist_color", col)
		keep.append(m)
	_mist_mats = keep


## The memorial park's lawn material (CemeteryBuild._ground()): dew, not a sprinkler's film.
static func dress_lawn(mat: Material) -> void:
	if mat is ShaderMaterial:
		(mat as ShaderMaterial).set_shader_parameter("spray_rough", DEW_ROUGH if enabled else 0.32)


## The build steps added to a FULL cemetery chunk (CemeteryBuild.steps(), after the stones).
static func steps(ch: CityChunk, st: Dictionary) -> Array[Callable]:
	var out: Array[Callable] = []
	if not enabled or ch.level != CityChunk.Level.FULL or ch.capturing:
		return out
	out.append(func() -> void: grass(ch, st))
	out.append(func() -> void: mist_box(ch, st))
	return out


## Mown tufts over the chunk's part of the lawn, following the rise (the batch adds the relief).
static func grass(ch: CityChunk, st: Dictionary) -> void:
	var pl: Dictionary = st.pl
	var part: Rect2 = st.part
	if part.size.x < 1.0 or part.size.y < 1.0:
		return
	# Stones: the 0.5 m cells within STONE_CLEAR of each.
	var stones := {}
	for gr: Array in Cemetery.graves(pl, st.own as Rect2, 0, 1):
		var p: Vector2 = gr[1]
		var r := STONE_CLEAR * (2.2 if not String(gr[0]).begins_with("flat") else 1.0)
		for j in range(floori((p.y - r) * 2.0), floori((p.y + r) * 2.0) + 1):
			for i in range(floori((p.x - r) * 2.0), floori((p.x + r) * 2.0) + 1):
				stones[Vector2i(i, j)] = true
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([ch.plan.seed, ch.ix, ch.iz, "rc5_cem_grass"])
	var count := int(part.get_area() * ch.grass_per_sqm * GRASS_DENSITY * LawnsCloseup.density_gain())
	var blade := LawnsCloseup.tuft()
	var closeup := LawnsCloseup.enabled
	var lawn := PropFactory.lawn(CemeteryBuild.LAWN_TINT, hash([ch.plan.seed, "cem_lawn"]), 0.1, 3.4)
	var look := LawnsCloseup.lawn_look(lawn, hash([ch.plan.seed, "cem_lawn"]))
	var site: Rect2 = pl.site
	var keys := {}
	for k in count:
		var p := Vector2(rng.randf_range(part.position.x, part.end.x), rng.randf_range(part.position.y, part.end.y))
		var sc := rng.randf_range(0.55, 1.5)
		var yaw := rng.randf_range(0.0, TAU)
		var jit := Color(rng.randf_range(0.85, 1.1), rng.randf_range(0.9, 1.1), rng.randf_range(0.85, 1.05))
		var phase := rng.randf()
		if Cemetery._masked(pl, p) or stones.has(Vector2i(floori(p.x * 2.0), floori(p.y * 2.0))):
			continue
		var basis := Basis(Vector3.UP, yaw).scaled(Vector3(sc, sc * 0.9, sc))
		basis = basis.scaled(RcSuburb.TUFT_SCALE) if RcSuburb.enabled else basis
		var y := CityChunk.SIDEWALK_TOP + CemeteryBuild.LAWN_LIFT + Cemetery.height(pl, p) + 0.02
		var key := "cemgrass_%d_%d" % [floori(p.x / CityChunk.GRASS_CELL), floori(p.y / CityChunk.GRASS_CELL)]
		keys[key] = true
		if closeup:
			ch._batch.add(key, blade, Transform3D(basis, Vector3(p.x, y, p.y)), LawnsCloseup.tuft_color(look, jit),
				LawnsCloseup.tuft_data(phase, look, LawnsCloseup.edge_distance(site, p)))
		else:
			ch._batch.add(key, blade, Transform3D(basis, Vector3(p.x, y, p.y)), jit, Color(phase, 0.0, 0.0))
	var draw_to := minf(LawnsCloseup.grass_distance(ch.grass_distance), GRASS_DRAW)
	for key: String in keys:
		ch._batch.set_no_shadow(key)
		ch._batch.set_draw_distance(key, draw_to)


## A box over the chunk's part of the site carrying the ground mist.
static func mist_box(ch: CityChunk, st: Dictionary) -> void:
	var pl: Dictionary = st.pl
	var part: Rect2 = st.part
	if part.size.x < 2.0 or part.size.y < 2.0:
		return
	if _mist_shader == null:
		_mist_shader = load("res://shaders/cemetery_mist.gdshader")
	# The lowest ground of the part (the relief), so the box's floor is under all of it.
	var lo := INF
	var hi := -INF
	for p: Vector2 in [part.position, part.end, Vector2(part.position.x, part.end.y), Vector2(part.end.x, part.position.y), part.get_center()]:
		var g := ch._gy(p.x, p.y)
		lo = minf(lo, g)
		hi = maxf(hi, g)
	var base := lo + CityChunk.SIDEWALK_TOP - 0.5
	var top := hi + CityChunk.SIDEWALK_TOP + float(pl.H) + MIST_TOP
	var mat := ShaderMaterial.new()
	mat.shader = _mist_shader
	mat.render_priority = 1
	# Everything in the box's own space (its centre at the origin): the shader never needs the
	# origin shift. The rise as Cemetery.height(): crown, its height and its four extents.
	var c := part.get_center()
	var cy := (base + top) * 0.5
	var crown: Vector2 = pl.crown
	var ground0 := ch._gy(c.x, c.y) + CityChunk.SIDEWALK_TOP + CemeteryBuild.LAWN_LIFT - cy
	mat.set_shader_parameter("crown", Vector4(crown.x - c.x, crown.y - c.y, float(pl.H), ground0))
	mat.set_shader_parameter("extent", Vector4(float(pl.hx0), float(pl.hx1), float(pl.hz0), float(pl.hz1)))
	mat.set_shader_parameter("half_size", Vector3(part.size.x, top - base, part.size.y) * 0.5)
	mat.set_shader_parameter("amount", mist_now)
	_mist_mats.append(mat)
	var mi := MeshInstance3D.new()
	mi.name = "CemeteryMist"
	var box := BoxMesh.new()
	box.size = Vector3(part.size.x, top - base, part.size.y)
	mi.mesh = box
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3(c.x, cy, c.y)
	ch.add_child(mi)
