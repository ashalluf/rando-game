class_name LoadingScreen
extends CanvasLayer
## Covers the first seconds of a session and does the work that otherwise stalls the game LATER
## (owner, 2026-09-22: "is tehre anyway we can just have a loading screen at the start of the
## game that loads a bunch of stuff and takes like 40-60 seconds so that it doesnt need to be
## lagging the entire time?").
##
## Two jobs, and they are the two an open-world game does up front:
##
## 1. COMPILE EVERY SHADER. Godot compiles a shader the first time it is actually drawn, so the
##    first explosion, the first rainfall, the first car paint or building finish the player has
##    not seen yet each cost a stall in the middle of play. Drawing one surface per shader here
##    pays all of it once, before the session starts, and it never comes back.
## 2. BUILD A WIDE RESIDENT AREA. The streamer's normal window is two blocks of full detail;
##    the first minute of driving is otherwise solid chunk generation. This builds far past that
##    while the screen is still up.
##
## What it deliberately does NOT claim to fix: the world is endless, so the player can always
## reach unbuilt ground, and the per-frame draw call count is unchanged. A loading screen cannot
## precompute a frame that has not happened.

## Blocks of full detail built before the game starts, against CityStreamer's usual load radius.
@export var preload_radius_blocks: int = 5
## Frames to hold each warm-up batch on screen. One is enough for the compile; two is insurance
## against a driver that defers.
@export var warm_frames: int = 2
## Shaders drawn together in one warm-up batch (each batch holds `warm_frames` frames).
@export var shader_batch: int = 16

signal finished

var _label: Label
var _bar: ColorRect
var _fill: ColorRect
var _shade: ColorRect
var _progress: float = 0.0
## Only the shader files whose names contain one of these (empty: all). For the first-use probe
## (tools/shader_warm/), which cannot fit every shader's pipelines in lavapipe's memory.
static var only_shaders: PackedStringArray = []
## WARM_LOG=1 in the environment: print what each warm-up step costs (tools/shader_warm/).
var _warm_log := OS.get_environment("WARM_LOG") == "1"
## Frames the screen has waited out and the time they took (LoadClock's report: on a software
## renderer a frame of the city is seconds, on the Mac a few milliseconds).
var frames_waited: int = 0
## Milliseconds of work between two frames of the bar in the baking loops (see _due()).
@export var bar_interval_ms: int = 350
var _last_frame: int = 0
var frame_usec: int = 0


func _ready() -> void:
	layer = 128
	_build_ui()


func _build_ui() -> void:
	_shade = ColorRect.new()
	_shade.color = Color(0.055, 0.06, 0.075)
	_shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_shade)
	_label = Label.new()
	_label.text = "Loading"
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.set_anchors_preset(Control.PRESET_CENTER)
	_label.offset_left = -300.0
	_label.offset_right = 300.0
	_label.offset_top = -10.0
	_label.offset_bottom = 24.0
	_label.add_theme_color_override("font_color", Color(0.82, 0.84, 0.88))
	_shade.add_child(_label)
	_bar = ColorRect.new()
	_bar.color = Color(0.16, 0.17, 0.20)
	_bar.set_anchors_preset(Control.PRESET_CENTER)
	_bar.offset_left = -220.0
	_bar.offset_right = 220.0
	_bar.offset_top = 34.0
	_bar.offset_bottom = 40.0
	_shade.add_child(_bar)
	_fill = ColorRect.new()
	_fill.color = Color(0.78, 0.80, 0.84)
	_fill.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	_fill.offset_right = 0.0
	_bar.add_child(_fill)


func _step(text: String, fraction: float) -> void:
	_progress = fraction
	if _label:
		_label.text = text
	if _fill:
		_fill.offset_right = 440.0 * clampf(fraction, 0.0, 1.0)


## Runs the whole sequence. `city` is the CityStreamer. Awaits frames throughout so the bar
## actually draws; a loading screen that blocks the main thread shows nothing at all.
func run(city: Node3D) -> void:
	await _frames(2)
	_step("Compiling shaders", 0.05)
	LoadClock.start("screen: shaders and effects")
	await _warm_shaders()
	LoadClock.stop("screen: shaders and effects")
	# The people at the camps who sit, lie or slump are baked static figures (CampFigure), one
	# per model and pose: a few tens of milliseconds each, done here rather than by the first
	# downtown chunks.
	var kinds: Array = CampFigure.kinds()
	var t_camp := Time.get_ticks_usec()
	LoadClock.start("screen: camp figures")
	for i in kinds.size():
		if _due():
			_step("Preparing people", 0.3 + 0.25 * float(i) / float(maxi(kinds.size(), 1)))
			await _frames(1)
		var k: Array = kinds[i]
		CampFigure.mesh_for(CampFigure.seed_for(k[0], k[1], k[2]), k[1])
	t_camp = Time.get_ticks_usec() - t_camp
	LoadClock.stop("screen: camp figures")
	# The beach's people (BeachFigure): every beach rig in every beach pose, and the cyclists'
	# pedalling flipbooks, so the first beach chunk does not bake them.
	var t_beach := Time.get_ticks_usec()
	LoadClock.start("screen: beach figures")
	var beach := BeachFigure.kinds()
	for i in beach.size():
		if _due():
			_step("Preparing the beach", 0.3 + 0.25 * float(i) / float(maxi(beach.size(), 1)))
			await _frames(1)
		BeachFigure.warm_kind(beach[i])
	print("LOADING beach: %d figures and flipbooks %d ms" % [beach.size(), (Time.get_ticks_usec() - t_beach) / 1000])
	LoadClock.stop("screen: beach figures")
	_step("Building the city", 0.55)
	await _frames(1)
	LoadClock.start("screen: preload world")
	_preload_world(city)
	LoadClock.stop("screen: preload world")
	await _frames(2)
	# The far city for the whole basin (Skyline), so the first look round from a rooftop sees
	# every block out to the horizon rather than watching the far half fill in.
	_step("Building the skyline", 0.8)
	await _frames(1)
	if city.has_method("finish_far_city"):
		city.call("finish_far_city")
	await _frames(1)
	# The rehearsal (WarmRehearsal): the real cars, people and effects drawn once behind the shade,
	# so their pipelines exist before play; and the decal atlas packed for good.
	await WarmRehearsal.run(city, get_viewport().get_camera_3d(),
			func(f: float, text: String) -> void: _step(text, 0.8 + 0.08 * f), _warm_log)
	# The hills' shrubs and oaks, cut to their triangle budgets (tenths of a second the first
	# time), so the first hill block after the spawn does not pay for it mid-flight.
	LoadClock.start("screen: trees")
	PropFactory.model_chaparral()
	for v in PropFactory.HILL_OAKS.size():
		PropFactory.model_hill_oak(v)
	# Every tree species on its LOD ladder (FoliageLod: thinned copies of the leaf cards and
	# twigs, 0.1-0.5 s a species on a slow machine), so the first block of one - a hill tree on
	# the way up a slope - does not pay for it. Most are built already by the blocks round the
	# spawn; this is the rest.
	for v in PropFactory.CITY_TREES.size():
		PropFactory.model_tree(v)
	for v in PropFactory.HILL_TREES.size():
		PropFactory.model_hill_tree(v)
	LoadClock.stop("screen: trees")
	LoadClock.start("screen: rigs")
	# Cutting a character's limbs apart takes tens of milliseconds the first time for each
	# model, which is a hitch on the first rocket into a crowd; here it is part of the wait.
	var models: Array = Pedestrian.MODELS
	var t_rigs := 0
	for i in models.size():
		if _due():
			_step("Preparing people (%d/%d)" % [i + 1, models.size()], 0.9 + 0.1 * float(i) / float(maxi(models.size(), 1)))
			await _frames(1)
		var t0 := Time.get_ticks_usec()
		Ragdoll.warm_limbs(models[i], self)
		# The welded bodies, and the hats fitted to this rig's head (the police cap too for the
		# rigs that wear the uniform).
		Pedestrian.warm_far_mesh(models[i], self, models[i] in PoliceOfficer.OFFICER_MODELS)
		t_rigs += Time.get_ticks_usec() - t0
	# The people's share of the wait (the camp figures, then every rig's limbs, welded bodies and
	# hats), for measuring a change of models: the rest of the loading screen does not depend on them.
	# The dogs' meshes (DogMesh, built in code: every breed's three levels and fur shells).
	var t_dogs := Time.get_ticks_usec()
	DogMesh.warm()
	print("LOADING dogs: %d ms" % ((Time.get_ticks_usec() - t_dogs) / 1000))
	print("LOADING people: %d camp figures %d ms, %d rigs %d ms" % [kinds.size(), t_camp / 1000, models.size(), t_rigs / 1000])
	LoadClock.stop("screen: rigs")
	_step("Ready", 1.0)
	await _frames(2)
	await _fade_out()
	print("LOADING screen frames: %d waited, %d ms" % [frames_waited, frame_usec / 1000])
	LoadClock.loaded(get_tree())
	finished.emit()
	queue_free()


func _frames(n: int) -> void:
	var t0 := Time.get_ticks_usec()
	for i in n:
		await get_tree().process_frame
	frames_waited += n
	frame_usec += Time.get_ticks_usec() - t0
	_last_frame = Time.get_ticks_usec()


## True once `bar_interval_ms` of work has gone by since the last frame: the loops that bake
## people hand the bar a frame by the clock, not every few items (each frame draws the city behind
## the screen, which a fixed count paid for 40 times over for a few seconds of work).
func _due() -> bool:
	return Time.get_ticks_usec() - _last_frame >= bar_interval_ms * 1000


## Draws one surface per shader in front of the camera for a couple of frames. Uniform VALUES do
## not create new variants - the shader code does - so one material per .gdshader file warms
## every material in the game that uses it.
func _warm_shaders() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var holder := Node3D.new()
	cam.add_child(holder)
	var files := _shader_files()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.02, 0.02)
	var i := 0
	for path in files:
		var shader: Shader = load(path) as Shader
		if shader == null:
			continue
		var mat := ShaderMaterial.new()
		mat.shader = shader
		var mi := MeshInstance3D.new()
		mi.mesh = quad
		mi.material_override = mat
		# Just in front of the near plane, tiny, so it costs no fill but is definitely drawn.
		mi.position = Vector3(0.0, 0.0, -0.3)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(mi)
		i += 1
		# A batch of shaders a draw: every quad of it is drawn in the same frames, so each shader
		# still compiles here, but the frames waited out (a whole city frame each, behind the
		# screen) are `warm_frames` a batch rather than a shader - 250 frames were 18 minutes on a
		# software renderer and several seconds on the Mac. WARM_LOG times them one at a time.
		if i % (1 if _warm_log else shader_batch) == 0 or i == files.size():
			_step("Compiling shaders (%d/%d)" % [i, files.size()], 0.05 + 0.45 * float(i) / float(maxi(files.size(), 1)))
			var t_shader := Time.get_ticks_usec()
			await _frames(warm_frames)
			if _warm_log:
				print("WARM shader %s %d ms rss %d MB" % [path.get_file(), (Time.get_ticks_usec() - t_shader) / 1000, OS.get_static_memory_usage() / 1048576])
	# The effect materials are StandardMaterial3D, not .gdshader files, so the loop above never
	# drew them, and a particle system draws through a MultiMesh - its own pipeline variant. The
	# first rocket used to compile all of it mid-blast. Drawn here once as a one-instance
	# MultiMesh laid out the way CPUParticles3D lays its buffer out.
	var effects: Array = WeaponFX.warm_materials()
	effects.append(Ragdoll.wound_material())
	# The facade kit only ever draws through a MultiMesh too, so the quads above warmed the wrong
	# variant of its shaders; and the pieces are loaded here, not by the first building to use one.
	if Building.kit_enabled:
		effects.append_array(PropFactory.kit_materials())
	# The encampment kit, likewise (Encampment; only ever drawn through the chunks' batches).
	effects.append_array(PropFactory.camp_materials())
	# The port's kit: its meshes built here (a crane is ~20 ms of GDScript a pose) and its two
	# shaders drawn through a MultiMesh, the only way the containers and gantries are drawn.
	effects.append_array(PortKit.warm())
	# The street vendors' trucks, carts and umbrellas (StreetVendors), built in code.
	effects.append_array(StreetVendors.warm())
	effects.append_array(BoulevardSigns.warm())
	FarmersMarketKit.warm()
	effects.append(FarmersMarketKit.material())
	# The billboards' faces and steel (Billboards), only ever drawn through the chunks' batches.
	effects.append_array(Billboards.warm())
	# The beach's towels, umbrellas, chairs, boards, the net and the tower (BeachLife).
	effects.append_array(BeachLife.warm())
	# The pier park's meshes (PierPark), built here rather than by the chunk that streams it in.
	effects.append_array(PierPark.warm())
	# The code-built Los Angeles trees and accents (LaTrees): built here, ~2 s of GDScript.
	effects.append_array(LaTrees.warm())
	# The utility poles' hardware (UtilityPoles), built in code.
	effects.append_array(UtilityPoles.warm())
	# Car damage: the flames, the glass cubes and the engine smoke (CarDamage).
	effects.append_array(CarDamage.warm_materials())
	# The hillside houses' glass, pool water and site materials (HillHomeKit).
	effects.append_array(HillHomeKit.warm())
	# The boost's streaks of air (BoostTrail), so the first boost does not stall.
	effects.append(BoostTrail.streak_material())
	# What a blast leaves (BlastAftermath): the crater's maps, the slabs, the leaves.
	effects.append_array(BlastAftermath.warm())
	for mat: Material in effects:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.use_custom_data = true
		mm.mesh = quad
		mm.instance_count = 1
		mm.set_instance_transform(0, Transform3D.IDENTITY)
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = mat
		mmi.position = Vector3(0.0, 0.0, -0.3)
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(mmi)
	for mat: Material in WeaponFX.warm_mesh_materials():
		var mi := MeshInstance3D.new()
		mi.mesh = quad
		mi.material_override = mat
		mi.position = Vector3(0.0, 0.0, -0.3)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(mi)
	# Blood decals: the first to use a texture repacks the decal atlas.
	for dec: Node3D in WeaponFX.warm_decals():
		dec.position = Vector3(0.0, 0.0, -0.3)
		holder.add_child(dec)
	_step("Compiling effects", 0.5)
	await _frames(warm_frames)
	await _frames(1)
	holder.queue_free()


func _shader_files() -> PackedStringArray:
	var out := PackedStringArray()
	var dir := DirAccess.open("res://shaders")
	if dir == null:
		return out
	for f in dir.get_files():
		# Exported builds see .remap; the editor sees the file itself.
		var name := f.trim_suffix(".remap")
		if not only_shaders.is_empty() and not _wanted(name):
			continue
		if name.ends_with(".gdshader"):
			out.append("res://shaders/" + name)
	return out


func _wanted(file: String) -> bool:
	for k in only_shaders:
		if file.contains(k):
			return true
	return false


## Builds a much wider area than the streamer's normal window, so the opening minute of driving
## is not solid chunk generation.
func _preload_world(city: Node3D) -> void:
	if city == null:
		return
	var was: int = city.get("load_radius_blocks")
	city.set("load_radius_blocks", maxi(preload_radius_blocks, was))
	city.call("update_streaming", true)
	city.set("load_radius_blocks", was)


func _fade_out() -> void:
	var t := 0.0
	while t < 0.45:
		t += get_process_delta_time()
		var a: float = 1.0 - clampf(t / 0.45, 0.0, 1.0)
		if _shade:
			_shade.modulate.a = a
		await get_tree().process_frame
