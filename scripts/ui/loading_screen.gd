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

signal finished

var _label: Label
var _bar: ColorRect
var _fill: ColorRect
var _shade: ColorRect
var _progress: float = 0.0


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
	await _warm_shaders()
	_step("Building the city", 0.55)
	await _frames(1)
	_preload_world(city)
	await _frames(2)
	# Cutting a character's limbs apart takes tens of milliseconds the first time for each
	# model, which is a hitch on the first rocket into a crowd; here it is part of the wait.
	var models: Array = Pedestrian.MODELS
	for i in models.size():
		_step("Preparing people (%d/%d)" % [i + 1, models.size()], 0.9 + 0.1 * float(i) / float(maxi(models.size(), 1)))
		await _frames(1)
		Ragdoll.warm_limbs(models[i], self)
		Pedestrian.warm_far_mesh(models[i], self)
	_step("Ready", 1.0)
	await _frames(2)
	await _fade_out()
	finished.emit()
	queue_free()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


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
		_step("Compiling shaders (%d/%d)" % [i, files.size()], 0.05 + 0.45 * float(i) / float(maxi(files.size(), 1)))
		await _frames(warm_frames)
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
		if name.ends_with(".gdshader"):
			out.append("res://shaders/" + name)
	return out


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
