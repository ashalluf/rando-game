class_name StormDrama
extends Node3D
## Storms that read as a storm (fleet wave 3, "storm-drama"; docs/HANDOFF.md "Storm drama"):
## Weather's child, made in its _ready() and driven from its _process() with the storm's weight
## and the rain. It adds, on top of what Weather already does (the drops, splashes, curtain,
## lens rain, lightning flash and delayed thunder, tyre spray, roof splashes):
##
## - GUSTS: one pure clock, `gust(t)` (peaky: short strong gusts, long lulls). It leans every
##   tree and palm hard downwind (`lean_for()`, added to the `wind_lean` global the Santa Ana
##   uses, which every tree shader's gust front runs along), throws the drops sideways (the rain
##   emitter's gravity), thickens the tyre spray and drives the litter.
## - RAIN SHEETS: Weather's rain curtain shader gains `sheets` - denser veils laid on the TRUE
##   world along the wind, running downwind at SHEET_SPEED - and its streaks slant with the wind;
##   a second, inner curtain (INNER_RADIUS, desktop only) puts the sheets inside the street, where
##   the outer one stands behind the buildings. From the air the outer curtain reaches down to
##   the ground.
## - LIGHTNING: a bolt for every strike nearer than BOLT_REACH (a jagged ribbon with branches from
##   the cloud base to the ground, one mesh, additive and fog-free, `shaders/storm_bolt.gdshader`),
##   the sky's flash pulled toward the strike (sky.gdshader `flash_dir` / `flash_spread`: the cloud
##   base round it lights), and the ambient fill raised for the flash (DayNight reads
##   FLASH_AMBIENT): the whole street lights for the frame, not just the faces toward it. The
##   thunder's delay is Weather's (distance / 343 m/s).
## - THE SKY: a darker, greener grey by day (SKY_TOP / SKY_HORIZON / FOG / CLOUD), applied by
##   DayNight through its `storm` hook; nights keep the city's sodium cloud base.
## - RUN-OFF: streams pouring off the roof edges round the camera and drip lines off awnings and
##   canopies, found by a few world-layer rays a probe (one probe every PROBE_SECONDS), drawn as ONE
##   MultiMesh (`shaders/storm_runoff.gdshader`), each with a splash where it lands.
## - LITTER: wet leaves and paper tossed down the street in the gusts (one CPUParticles3D).
##
## Every roll is a hash (the probe directions, the bolt's shape: the strike counter), never
## Weather's rng, so the lightning's timing and every city roll are untouched. STORM_DRAMA=0 in
## the environment is the A/B (nothing is built, every hook is a no-op). STORM_FLASH=<s> forces a
## strike that many seconds after load, at STORM_FLASH_DIST metres toward STORM_FLASH_AZ degrees
## (for stills); STORM_FLASH_HOLD=<level> then holds that flash (and its bolt) for the shot.

static var enabled: bool = OS.get_environment("STORM_DRAMA") != "0"

## The storm's wind, the way Weather's rain_wind (6, 0, 2) blows (XZ, unit).
const WIND_DIR := Vector2(0.949, 0.316)
## How far a full storm leans the trees (wind_lean's length; the Santa Ana's is 1.0).
const LEAN := 0.7
## The lean that is left in a lull (a share of LEAN).
const LEAN_LULL := 0.45
## Rain sheets: how fast they run downwind (m/s) and how much of the curtain they take.
const SHEET_SPEED := 13.0
const SHEETS := 0.85
## The inner curtain round the camera (metres) and its opacity against the outer one's.
const INNER_RADIUS := 22.0
const INNER_HEIGHT := 34.0
const INNER_OPACITY := 0.62
## A strike nearer than this many metres shows its bolt.
const BOLT_REACH := 2600.0
## Bolt: the cloud base it comes out of (metres over the camera's ground) and the ribbon's
## half-width at a metre's distance (so it is about two pixels wide at any range).
const BOLT_BASE := 820.0
const BOLT_WIDTH_PER_M := 0.0021
## The ambient fill a full flash adds (times DayNight's ambient energy).
const FLASH_AMBIENT := 0.8
## The sky's flash toward the strike: the share spread over the whole sky (1 = the old even flash).
const FLASH_SPREAD := 0.3
## Storm sky by day: darker and greener than the rain's grey (Colors, as DayNight passes them).
const SKY_TOP := Color(0.105, 0.128, 0.122)
const SKY_HORIZON := Color(0.205, 0.238, 0.222)
const FOG := Color(0.25, 0.285, 0.268)
const CLOUD := Color(0.36, 0.40, 0.385)
## Cloud cover a storm adds on top of Weather's (no blue gaps in a storm).
const COVER := 0.35
## Rain wind at a full gust, times Weather's rain_wind.
const GUST_RAIN := 1.9
## Run-off: how many streams at most, how far from the camera, how often a probe runs.
const MAX_STREAMS := 26
const STREAM_REACH := 32.0
const PROBE_SECONDS := 0.18
## A roof lower than this pours visibly (a tower's water is a mist by the time it is down).
const ROOF_MAX := 40.0

var storm: float = 0.0
var rain: float = 0.0
var gust_now: float = 0.0
## Bolts drawn since load (the checks read it).
var bolts: int = 0

var _weather: Node
var _clock: float = 0.0
var _strikes: int = 0
var _inner: MeshInstance3D
var _inner_mat: ShaderMaterial
var _bolt: MeshInstance3D
var _bolt_mat: ShaderMaterial
var _bolt_age: float = -1.0
var _runoff: MultiMeshInstance3D
var _runoff_mat: ShaderMaterial
var _streams: Array[Dictionary] = []
var _stream_keys := {}
var _probe_left: float = 0.0
var _probe_n: int = 0
var _dirty: bool = false
var _offset_was := Vector3.INF
var _litter: CPUParticles3D
var _web: bool = OS.has_feature("web")
var _forced_at: float = -1.0
var _hold: float = float(OS.get_environment("STORM_FLASH_HOLD")) if OS.get_environment("STORM_FLASH_HOLD") != "" else 0.0
var _holding: bool = false
var _curtain_height0: float = 70.0


## Gust strength 0..1 at time `t` (seconds). Peaky on purpose: short strong gusts and long lulls,
## the way a storm's wind comes down a street. Pure (the checks and the shaders' uniforms use it).
static func gust(t: float) -> float:
	var a := 0.5 + 0.5 * sin(t * TAU / 23.0)
	var b := 0.5 + 0.5 * sin(t * TAU / 9.7 + 1.3)
	var c := 0.5 + 0.5 * sin(t * TAU / 4.1 + 0.4)
	var g := smoothstep(0.32, 0.92, a * 0.62 + b * 0.38)
	return clampf(g * (0.78 + 0.22 * c), 0.0, 1.0)


## The trees' lean for a storm of weight `w` at time `t` (XZ, wind_lean's units).
static func lean_for(w: float, t: float) -> Vector2:
	if not enabled or w <= 0.0:
		return Vector2.ZERO
	return WIND_DIR * LEAN * w * (LEAN_LULL + (1.0 - LEAN_LULL) * gust(t))


## The sky's daytime storm colours lerped in: weight `w`, `moon` DayNight's moonlight (nights keep
## the sodium cloud base). Returns [top, horizon].
static func sky(top: Color, horizon: Color, w: float, moon: float) -> Array:
	var k := clampf(w, 0.0, 1.0) * (1.0 - clampf(moon, 0.0, 1.0)) if enabled else 0.0
	return [top.lerp(SKY_TOP, k), horizon.lerp(SKY_HORIZON, k)]


## A bolt's channel from `top` to `bottom`: midpoint displacement from a hash of `seed`, so the
## same strike draws the same bolt. Returns the main channel's points then each branch's, as
## [PackedVector3Array main, Array[PackedVector3Array] branches].
static func bolt_paths(seed: int, top: Vector3, bottom: Vector3) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([seed, "storm_bolt"])
	var main := _channel(rng, top, bottom, 6, 0.16)
	var branches: Array[PackedVector3Array] = []
	var count := rng.randi_range(2, 4)
	for i in count:
		var k := rng.randi_range(int(main.size() * 0.15), int(main.size() * 0.7))
		var from := main[k]
		var drop := (top.y - bottom.y) * rng.randf_range(0.12, 0.3)
		var side := Vector3(rng.randf_range(-1.0, 1.0), 0.0, rng.randf_range(-1.0, 1.0)).normalized()
		var to := from + side * drop * rng.randf_range(0.5, 1.0) + Vector3.DOWN * drop
		branches.append(_channel(rng, from, to, 4, 0.22))
	return [main, branches]


static func _channel(rng: RandomNumberGenerator, a: Vector3, b: Vector3, depth: int, rough: float) -> PackedVector3Array:
	var pts := PackedVector3Array([a, b])
	var amp := a.distance_to(b) * rough
	for d in depth:
		var next := PackedVector3Array()
		for i in pts.size() - 1:
			next.append(pts[i])
			var m := (pts[i] + pts[i + 1]) * 0.5
			m += Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-0.35, 0.35), rng.randf_range(-1.0, 1.0)) * amp
			next.append(m)
		next.append(pts[pts.size() - 1])
		pts = next
		amp *= 0.52
	return pts


func _ready() -> void:
	_weather = get_parent()
	var f := OS.get_environment("STORM_FLASH")
	if f != "":
		_forced_at = f.to_float()
	_build_inner()
	_build_bolt()
	_build_runoff()
	_build_litter()


func _build_inner() -> void:
	if _web or _weather == null:
		return
	var outer_mat: ShaderMaterial = _weather.get("_curtain_mat")
	if outer_mat == null:
		return
	var cyl := CylinderMesh.new()
	cyl.top_radius = INNER_RADIUS
	cyl.bottom_radius = INNER_RADIUS
	cyl.height = INNER_HEIGHT
	cyl.radial_segments = 40
	cyl.rings = 1
	cyl.cap_top = false
	cyl.cap_bottom = false
	_inner_mat = ShaderMaterial.new()
	_inner_mat.shader = outer_mat.shader
	_inner_mat.set_shader_parameter("height", INNER_HEIGHT)
	_inner_mat.set_shader_parameter("radius", INNER_RADIUS)
	# Fewer cells round a smaller circle: a streak stays about as wide in metres.
	_inner_mat.set_shader_parameter("cells_gain", 0.4)
	_inner_mat.set_shader_parameter("rows_gain", 0.5)
	_inner_mat.set_shader_parameter("bottom_fade", 0.03)
	_inner = MeshInstance3D.new()
	_inner.name = "RainSheetsInner"
	_inner.mesh = cyl
	_inner.material_override = _inner_mat
	_inner.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_inner.visible = false
	add_child(_inner)


func _build_bolt() -> void:
	_bolt_mat = ShaderMaterial.new()
	_bolt_mat.shader = load("res://shaders/storm_bolt.gdshader")
	_bolt = MeshInstance3D.new()
	_bolt.name = "LightningBolt"
	_bolt.material_override = _bolt_mat
	_bolt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_bolt.visible = false
	# Built in the world's own space each strike; the node itself never moves.
	_bolt.top_level = true
	add_child(_bolt)


func _build_runoff() -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	# Colours on: Compatibility hands a MultiMesh without them a COLOR that is not the vertex's.
	mm.use_colors = true
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	mm.mesh = quad
	mm.instance_count = MAX_STREAMS * 2
	mm.visible_instance_count = 0
	_runoff_mat = ShaderMaterial.new()
	_runoff_mat.shader = load("res://shaders/storm_runoff.gdshader")
	_runoff = MultiMeshInstance3D.new()
	_runoff.name = "RunOff"
	_runoff.multimesh = mm
	_runoff.material_override = _runoff_mat
	_runoff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_runoff.top_level = true
	_runoff.visible = false
	add_child(_runoff)


func _build_litter() -> void:
	_litter = CPUParticles3D.new()
	_litter.name = "StormLitter"
	_litter.amount = 36 if _web else 72
	_litter.lifetime = 3.6
	_litter.local_coords = false
	_litter.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_litter.emission_box_extents = Vector3(26.0, 2.0, 26.0)
	_litter.direction = Vector3(WIND_DIR.x, 0.3, WIND_DIR.y)
	_litter.spread = 22.0
	_litter.initial_velocity_min = 7.0
	_litter.initial_velocity_max = 15.0
	_litter.gravity = Vector3(0.0, -3.5, 0.0)
	_litter.angular_velocity_min = -900.0
	_litter.angular_velocity_max = 900.0
	_litter.angle_max = 360.0
	_litter.scale_amount_min = 0.07
	_litter.scale_amount_max = 0.24
	_litter.damping_max = 2.0
	# Wet leaves, dark and glossy, and soaked scraps of paper and card.
	var tint := Gradient.new()
	tint.set_color(0, Color(0.20, 0.15, 0.08))
	tint.set_color(1, Color(0.70, 0.69, 0.64))
	tint.add_point(0.4, Color(0.26, 0.24, 0.12))
	tint.add_point(0.7, Color(0.34, 0.22, 0.11))
	tint.add_point(0.86, Color(0.52, 0.44, 0.30))
	_litter.color_initial_ramp = tint
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0))
	fade.set_color(1, Color(1, 1, 1, 0))
	fade.add_point(0.06, Color(1, 1, 1, 1))
	fade.add_point(0.85, Color(1, 1, 1, 1))
	_litter.color_ramp = fade
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = SantaAnaFx._leaf_texture()
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	mat.alpha_scissor_threshold = 0.5
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.billboard_keep_scale = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.roughness = 0.3
	quad.material = mat
	_litter.mesh = quad
	_litter.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_litter.visibility_aabb = AABB(Vector3(-80, -20, -80), Vector3(160, 50, 160))
	_litter.emitting = false
	add_child(_litter)


## Each frame from Weather: `w` the storm's weight, `r` the rain, `low` Weather's low detail.
func drive(w: float, r: float, delta: float, player: Node3D, low: bool) -> void:
	storm = w
	rain = r
	_clock += delta
	gust_now = gust(_clock) * w
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	var cam_pos := cam.global_position if cam else (player.global_position if player else Vector3.ZERO)
	var ground := _ground_y(cam_pos)
	var high := cam_pos.y - ground
	_drive_rain(w, r, cam_pos, ground, high, low)
	_drive_bolt(delta, cam_pos)
	_drive_runoff(delta, r, cam_pos, ground, high, low)
	if _litter:
		var on := w > 0.3 and not low and high < 40.0
		if _litter.emitting != on:
			_litter.emitting = on
		if on:
			_litter.global_position = Vector3(cam_pos.x, ground + 1.2, cam_pos.z) - Vector3(WIND_DIR.x, 0.0, WIND_DIR.y) * 10.0
			_litter.speed_scale = 0.55 + 0.9 * gust_now
	var spray: Node = _weather.get("_spray") if _weather else null
	if spray:
		spray.set("gain", 1.0 + 0.9 * w)
	if _forced_at >= 0.0 and _clock >= _forced_at and _weather and _weather.has_method("force_strike"):
		_forced_at = -1.0
		var dist := float(OS.get_environment("STORM_FLASH_DIST")) if OS.get_environment("STORM_FLASH_DIST") != "" else 900.0
		var az := deg_to_rad(float(OS.get_environment("STORM_FLASH_AZ")) if OS.get_environment("STORM_FLASH_AZ") != "" else 0.0)
		_weather.force_strike(dist, Vector3(cos(az), 0.0, sin(az)))
		_holding = _hold > 0.0


func _ground_y(p: Vector3) -> float:
	var streamer := _weather.get_parent() if _weather else null
	if streamer and streamer.has_method("surface_height_at"):
		return float(streamer.surface_height_at(p))
	return 0.0


func _drive_rain(w: float, r: float, cam: Vector3, ground: float, high: float, low: bool) -> void:
	if _weather == null:
		return
	var drops: CPUParticles3D = _weather.get("_rain")
	var wind: Vector3 = _weather.get("rain_wind")
	if drops:
		var k := 1.0 + (GUST_RAIN - 1.0) * gust_now
		drops.gravity = Vector3(wind.x * k, -36.0, wind.z * k)
	var outer: MeshInstance3D = _weather.get("_curtain")
	var outer_mat: ShaderMaterial = _weather.get("_curtain_mat")
	if outer_mat:
		outer_mat.set_shader_parameter("sheets", SHEETS * w)
		outer_mat.set_shader_parameter("gust", gust_now)
		outer_mat.set_shader_parameter("slant", (0.25 + 0.6 * gust_now) * w)
	if outer and outer.visible:
		# From the air the curtain reaches down to the street, so the city below is seen through
		# the rain rather than under a band of it at the camera's height.
		var h0: float = _weather.get("curtain_height")
		var bottom := minf(cam.y - h0 * 0.22, ground)
		var top := cam.y + h0 * 0.78
		var s := maxf(1.0, (top - bottom) / h0)
		outer.scale = Vector3(1.0, s, 1.0)
		outer.global_position = Vector3(cam.x, (top + bottom) * 0.5, cam.z)
		if outer_mat:
			outer_mat.set_shader_parameter("rows_gain", s)
	if _inner:
		var on := r > 0.3 and w > 0.05 and not low and high < 60.0
		_inner.visible = on
		if on:
			_inner.global_position = Vector3(cam.x, ground + INNER_HEIGHT * 0.5 - 2.0, cam.z)
			var curtain_opacity: float = _weather.get("curtain_opacity")
			_inner_mat.set_shader_parameter("strength", curtain_opacity * INNER_OPACITY * r * w)
			_inner_mat.set_shader_parameter("sheets", SHEETS * w)
			_inner_mat.set_shader_parameter("gust", gust_now)
			_inner_mat.set_shader_parameter("slant", (0.25 + 0.6 * gust_now) * w)


## Weather's strike, at `dist` metres toward `dir` (XZ, unit). Draws a bolt when near enough.
func on_strike(dist: float, dir: Vector3) -> void:
	_strikes += 1
	if dist > BOLT_REACH or _bolt == null:
		return
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == null:
		return
	var c := cam.global_position
	var ground := _ground_y(c)
	var foot := Vector3(c.x, ground, c.z) + dir * dist
	var top := foot + Vector3(-dir.x * dist * 0.08, BOLT_BASE, -dir.z * dist * 0.08)
	var paths := bolt_paths(_strikes, top, foot)
	_bolt.mesh = _ribbons(paths, c, maxf(1.0, dist * BOLT_WIDTH_PER_M))
	_bolt.global_transform = Transform3D.IDENTITY
	_bolt_age = 0.0
	bolts += 1


## The flash this frame: Weather's flicker, or the held one of a still (STORM_FLASH_HOLD).
func held_flash(flash: float) -> float:
	return _hold if _holding else flash


## The flash's flicker this frame (Weather's), and the sky's flash direction.
func on_flash(flash: float, sky: ShaderMaterial, dir: Vector3) -> void:
	if _bolt_mat:
		_bolt_mat.set_shader_parameter("level", flash)
	if _bolt:
		_bolt.visible = _bolt_age >= 0.0 and flash > 0.001
	if sky:
		sky.set_shader_parameter("flash_dir", Vector3(dir.x, 0.32, dir.z).normalized())
		sky.set_shader_parameter("flash_spread", FLASH_SPREAD)


func _drive_bolt(delta: float, _cam: Vector3) -> void:
	if _bolt_age >= 0.0:
		_bolt_age += delta
		if _bolt_age > 1.2 and not _holding:
			_bolt_age = -1.0
			if _bolt:
				_bolt.visible = false


## Camera-facing ribbons along every path of a bolt (UV.x across, UV.y down, UV2.x 1 on branches).
func _ribbons(paths: Array, eye: Vector3, width: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var all: Array = [paths[0]]
	all.append_array(paths[1])
	for pi in all.size():
		var pts: PackedVector3Array = all[pi]
		var branch := 0.0 if pi == 0 else 1.0
		var w := width * (1.0 if pi == 0 else 0.6)
		for i in pts.size() - 1:
			var a := pts[i]
			var b := pts[i + 1]
			var along := (b - a).normalized()
			var side_a := along.cross(eye - a).normalized() * w
			var side_b := along.cross(eye - b).normalized() * w
			var va := float(i) / float(pts.size() - 1)
			var vb := float(i + 1) / float(pts.size() - 1)
			var quad := [[a - side_a, Vector2(-1, va)], [a + side_a, Vector2(1, va)], [b + side_b, Vector2(1, vb)],
				[a - side_a, Vector2(-1, va)], [b + side_b, Vector2(1, vb)], [b - side_b, Vector2(-1, vb)]]
			for q in quad:
				st.set_uv(q[1])
				st.set_uv2(Vector2(branch, 0.0))
				st.add_vertex(q[0])
	return st.commit()


func _drive_runoff(delta: float, r: float, cam: Vector3, ground: float, high: float, low: bool) -> void:
	if _runoff == null:
		return
	var on := r > 0.25 and not low
	_runoff.visible = on and not _streams.is_empty()
	if not on:
		if not _streams.is_empty():
			_streams.clear()
			_stream_keys.clear()
			_dirty = true
	else:
		_runoff_mat.set_shader_parameter("flow", clampf(r, 0.0, 1.0))
		_runoff_mat.set_shader_parameter("gust", gust_now)
		_probe_left -= delta
		if _probe_left <= 0.0 and high < 30.0:
			_probe_left = PROBE_SECONDS
			_probe(cam, ground)
		# Drop what is left behind.
		var cw := WorldState.to_world(cam)
		for i in range(_streams.size() - 1, -1, -1):
			var s: Dictionary = _streams[i]
			var p: Vector3 = s["at"]
			if Vector2(p.x - cw.x, p.z - cw.z).length() > STREAM_REACH * 1.35:
				_stream_keys.erase(s["key"])
				_streams.remove_at(i)
				_dirty = true
	if WorldState.world_offset != _offset_was:
		_offset_was = WorldState.world_offset
		_dirty = true
	if _dirty:
		_dirty = false
		_write_runoff()


## One probe: a ray out along the street from the camera's ground to a wall, then down from over
## the roof (its edge) and in front of the wall (an awning or a canopy). Directions run round the
## golden angle, so a few seconds of probes cover every side.
func _probe(cam: Vector3, ground: float) -> void:
	if _streams.size() >= MAX_STREAMS:
		return
	var space := get_world_3d().direct_space_state if is_inside_tree() else null
	if space == null:
		return
	_probe_n += 1
	var az := float(_probe_n) * 2.39996
	var dir := Vector3(cos(az), 0.0, sin(az))
	var from := Vector3(cam.x, ground + 2.4, cam.z)
	var hit := _ray(space, from, from + dir * STREAM_REACH)
	if hit.is_empty():
		return
	var n: Vector3 = hit["normal"]
	if absf(n.y) > 0.3:
		return
	n = Vector3(n.x, 0.0, n.z).normalized()
	var at: Vector3 = hit["position"]
	# The roof over the wall.
	var inside := at - n * 0.6
	var roof := _ray(space, inside + Vector3.UP * (ROOF_MAX + 30.0), inside + Vector3.UP * 0.5)
	var seed01 := fposmod(float(_probe_n) * 0.618034, 1.0)
	if not roof.is_empty():
		var top: float = (roof["position"] as Vector3).y
		if top - ground > 3.0 and top - ground < ROOF_MAX:
			var x := at + n * 0.32
			var foot := _ray(space, Vector3(x.x, top - 0.6, x.z), Vector3(x.x, ground - 3.0, x.z))
			var fy: float = (foot["position"] as Vector3).y if not foot.is_empty() else ground
			_add_stream(Vector3(x.x, top - 0.08, x.z), fy, 0, 0.16 + 0.22 * seed01, seed01)
	# An awning or canopy in front of the wall.
	var out := at + n * 1.5
	var edge := _ray(space, Vector3(out.x, at.y + 5.0, out.z), Vector3(out.x, ground + 0.3, out.z))
	if not edge.is_empty():
		var ey: float = (edge["position"] as Vector3).y
		if ey - ground > 2.1 and ey - ground < 6.5:
			var e := at + n * 1.7
			_add_stream(Vector3(e.x, ey - 0.03, e.z), ground, 2, 2.2, seed01)


func _ray(space: PhysicsDirectSpaceState3D, a: Vector3, b: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(a, b, 1)
	q.hit_from_inside = false
	return space.intersect_ray(q)


func _add_stream(top: Vector3, foot_y: float, kind: int, width: float, seed01: float) -> void:
	var tw := WorldState.to_world(top)
	var key := Vector3i(roundi(tw.x / 2.2), kind, roundi(tw.z / 2.2))
	if _stream_keys.has(key) or top.y - foot_y < 1.5:
		return
	_stream_keys[key] = true
	_streams.append({"at": tw, "foot": foot_y + (tw.y - top.y), "kind": kind, "w": width, "seed": seed01, "key": key})
	_dirty = true


func _write_runoff() -> void:
	var mm := _runoff.multimesh
	var i := 0
	for s in _streams:
		var at := WorldState.to_local(s["at"])
		var foot: float = float(s["foot"]) - (float((s["at"] as Vector3).y) - at.y)
		var h := at.y - foot
		var kind: int = s["kind"]
		var w: float = s["w"]
		mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3(w, h, 1.0)), Vector3(at.x, foot + h * 0.5, at.z)))
		mm.set_instance_custom_data(i, Color(float(kind), h, s["seed"], 1.0))
		mm.set_instance_color(i, Color.WHITE)
		i += 1
		if kind == 0:
			# The splash where it lands.
			mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3(0.9, 0.6, 1.0)), Vector3(at.x, foot + 0.3, at.z)))
			mm.set_instance_custom_data(i, Color(1.0, 0.6, s["seed"], 1.0))
			mm.set_instance_color(i, Color.WHITE)
			i += 1
	mm.visible_instance_count = i
	if i > 0:
		_runoff.custom_aabb = AABB(Vector3(-1.0e4, -1.0e4, -1.0e4), Vector3(2.0e4, 2.0e4, 2.0e4))


## The storm's own clock (seconds since load), what gust() is read at.
func clock() -> float:
	return _clock


## How many streams are standing (the checks read it).
func stream_count() -> int:
	return _streams.size()
