class_name LoadPulse
extends RefCounted
## Keeps the window alive through the load (owner, 2026-11-05, on the Mac: "5 minutes ... just the
## Godot logo and then ... sounds of the world but still just the Godot logo"; docs/HANDOFF.md
## "The Mac launch").
##
## Three things made the window freeze for minutes:
## 1. Everything up to the loading screen (macro map, the bake, the far landmarks, the first
##    streaming, the near far city: ~2 minutes on a 4-core box, cold) ran inside ONE
##    CityStreamer._ready(), so not a single frame was presented.
## 2. Every frame drew the 3D city behind the loading screen's shade. On Forward+ a draw waits for
##    the ubershader pipeline of every surface it draws (Godot's PipelineHashMapRD); on a first
##    launch on Metal (no baked shaders, empty caches) that is thousands of pipelines, so the
##    loading screen's first frame - and every frame after it while more of the city arrived -
##    waited minutes.
## 3. The ambience started in its _ready() under all of that.
##
## So: `tick()` is called from inside the long loops (one line each) and presents a frame of its
## own loading picture with RenderingServer.force_draw() when `interval_ms` has gone by. On the
## RenderingDevice renderers (Forward+ / Mobile: the Mac) the window's 3D is switched off while the
## load runs, so a frame draws nothing of the city - and a 4 x 4 off-screen viewport of an empty
## world is drawn instead: ANY 3D render makes RenderForwardClustered hand every new surface's
## pipelines to the worker threads (it drains its whole dirty list, visible or not), so they compile
## in the background while the bar moves. `drain()` waits for those compiles (a low-priority fence
## task on the WorkerThreadPool) before the city is shown. Compatibility compiles at draw time on
## the main thread and keeps its old behaviour (the 3D only skipped for the pulse's own frames).
## The master bus is muted from begin() to end(). Nothing here changes what is built or drawn once
## the load is done: same settings, same city, same quality.
##
## Inactive (every call a bool test) in headless runs, on the web, under --noload / --nohud and
## with LOAD_PULSE=0 (the A/B).

## Milliseconds between two presented frames inside a long loop.
static var interval_ms: int = 80
## Frames of the (still nearly empty) world drawn at begin() on the RenderingDevice renderers,
## so every pipeline requirement the city's frames will have (SDFGI's pass, motion vectors, normal
## and roughness, separate specular, the reflection probes' and shadowed omni lights' passes) is
## known before the city's surfaces are handed to the compilers - set later, every surface would
## be compiled again for it, at the reveal.
const PRIME_FRAMES := 4

static var active: bool = false
static var _canvas: RID
static var _item: RID
static var _last_us: int = 0
static var _t0_ms: int = 0
static var _stage: String = ""
static var _stage_from: float = 0.0
static var _stage_to: float = 0.0
static var _stage_t0: int = 0
static var _stage_tau: float = 20.0
static var _progress: float = 0.0
static var _shown: float = 0.0
static var _note: String = ""
static var _alpha: float = 1.0
static var _root: Viewport = null
static var _held: bool = false
static var _priming: bool = false
static var _drain_vp: RID
static var _drain_cam: RID
static var _drain_scenario: RID
static var _bus_was: bool = false
static var _rd: bool = false
## Frames presented by tick() (outside the normal main loop) and their time, for LoadClock.
## Every .gdshader loaded at boot (keep_shaders()), held for the session.
static var _shaders: Array[Shader] = []
static var _kept_materials: Array[ShaderMaterial] = []
static var pulses: int = 0
static var pulse_usec: int = 0
## The longest time the window went without a new frame during the load, and the step it was in
## (every frame counts, the pulse's and the main loop's: RenderingServer.frame_post_draw). Gaps
## over GAP_REPORT_MS are printed as they happen (a Mac launch log shows where it stalled).
static var max_gap_ms: int = 0
static var max_gap_stage: String = ""
static var _last_frame_us: int = 0
const GAP_REPORT_MS := 2000

## Stage (a LoadClock name) -> [progress at its start, progress at its end, a typical length in
## seconds on a cold launch]. The bar creeps toward the end of a stage on that time constant, so
## it never sits still and never jumps backwards. Unknown stages keep the bar where it is.
const STAGES := {
	"compile the game": [0.0, 0.03, 20.0, "Compiling scripts"],
	"queue the shaders": [0.03, 0.12, 120.0, "Compiling shaders (first launch only)"],
	"macro map": [0.03, 0.05, 7.0, "Laying out the basin"],
	"ground bake": [0.05, 0.16, 25.0, "Painting the far ground"],
	"far landmarks": [0.16, 0.21, 8.0, "Building the landmarks"],
	"first streaming": [0.21, 0.38, 50.0, "Building the streets"],
	"far city within the immediate radius": [0.33, 0.38, 19.0, "Building the skyline"],
	"screen: shaders and effects": [0.38, 0.47, 16.0, "Compiling shaders"],
	"screen: camp figures": [0.47, 0.48, 1.0, "Preparing people"],
	"screen: beach figures": [0.48, 0.51, 4.0, "Preparing the beach"],
	"screen: arroyos": [0.51, 0.52, 2.0, "Carving the canyons"],
	"screen: preload world": [0.52, 0.53, 2.0, "Building the city"],
	"far city": [0.53, 0.62, 40.0, "Building the skyline"],
	"screen: rehearsal": [0.62, 0.74, 20.0, "Rehearsing cars, people and effects"],
	"screen: trees": [0.74, 0.75, 1.0, "Growing the trees"],
	"screen: rigs": [0.75, 0.78, 5.0, "Preparing people"],
	"screen: traffic": [0.78, 0.79, 1.0, "Filling the streets"],
	"screen: final streaming": [0.79, 0.80, 1.0, "Building the city"],
	"graphics": [0.80, 0.99, 30.0, "Compiling graphics (first launch only)"],
	"screen: city graphics": [0.38, 0.45, 60.0, "Compiling graphics (first launch only)"],
}


## Loads every shader file under res://shaders and keeps it (and one material of it).
static func keep_shaders() -> void:
	if not _shaders.is_empty():
		return
	for f in DirAccess.get_files_at("res://shaders"):
		var name := f.trim_suffix(".remap")
		if not name.ends_with(".gdshader"):
			continue
		var sh := load("res://shaders/" + name) as Shader
		if sh and sh.get_mode() == Shader.MODE_SPATIAL:
			_shaders.append(sh)
		tick()


## Compiles every kept shader, ONE A FRAME (await it): Godot starts a material shader's compile
## only when a surface first uses it (ShaderRD::version_is_valid) and the main thread waits there
## for all its variants - so a city build that met each shader for the first time stopped the
## window for that long, stage after stage (2-15 s gaps on lavapipe while the landmarks built).
## Here each frame draws one 2 cm quad with one shader into a private 4 px viewport, so a frame
## waits for one shader; the build then finds them compiled. RenderingDevice renderers only.
static func compile_shaders(tree: SceneTree) -> int:
	if not active or not _rd or _shaders.is_empty():
		return 0
	var t0 := Time.get_ticks_msec()
	# The advanced variant group (motion vectors: TAA) is switched on the first time a frame is drawn
	# with them, and from then every shader compiles that group as well; switched on later (the
	# city's prime) it was compiled again for every shader on first use. Two frames of an empty
	# world with TAA on the window first.
	var probe_cam := Camera3D.new()
	tree.root.add_child(probe_cam)
	probe_cam.make_current()
	var taa_was := tree.root.use_taa
	tree.root.use_taa = true
	await tree.process_frame
	await tree.process_frame
	tree.root.use_taa = taa_was
	probe_cam.queue_free()
	var scenario := RenderingServer.scenario_create()
	var cam := RenderingServer.camera_create()
	RenderingServer.camera_set_perspective(cam, 60.0, 0.05, 10.0)
	var vp := RenderingServer.viewport_create()
	RenderingServer.viewport_set_size(vp, 4, 4)
	RenderingServer.viewport_set_scenario(vp, scenario)
	RenderingServer.viewport_attach_camera(vp, cam)
	RenderingServer.viewport_set_update_mode(vp, RenderingServer.VIEWPORT_UPDATE_ALWAYS)
	RenderingServer.viewport_set_active(vp, true)
	var quad := QuadMesh.new()
	quad.size = Vector2(0.02, 0.02)
	var items: Array[RID] = []
	var mats: Array[ShaderMaterial] = []
	var worst := 0
	for i in _shaders.size():
		var mat := ShaderMaterial.new()
		mat.shader = _shaders[i]
		mats.append(mat)
		var inst := RenderingServer.instance_create2(quad.get_rid(), scenario)
		RenderingServer.instance_geometry_set_material_override(inst, mat.get_rid())
		RenderingServer.instance_set_transform(inst, Transform3D(Basis(), Vector3(0, 0, -0.3)))
		items.append(inst)
		note("%d / %d shaders" % [i + 1, _shaders.size()])
		paint()
		var f0 := Time.get_ticks_msec()
		await tree.process_frame
		worst = maxi(worst, Time.get_ticks_msec() - f0)
	await tree.process_frame
	for inst in items:
		RenderingServer.free_rid(inst)
	RenderingServer.viewport_set_active(vp, false)
	RenderingServer.free_rid(vp)
	RenderingServer.free_rid(cam)
	RenderingServer.free_rid(scenario)
	_kept_materials = mats
	note("")
	print("LOADING shaders compiled one a frame: %d, worst frame %d ms" % [_shaders.size(), worst])
	return Time.get_ticks_msec() - t0


## True where the pulse may run: a real window, not the web, not switched off.
static func supported() -> bool:
	if OS.has_feature("web") or DisplayServer.get_name() == "headless":
		return false
	return OS.get_environment("LOAD_PULSE") != "0"


## Starts the pulse: mutes the master bus, puts the loading picture up and presents it at once,
## then (RenderingDevice renderers) primes the pipeline requirements and holds the 3D off.
static func begin(viewport: Viewport) -> void:
	if viewport == null or not supported():
		return
	if not active:
		begin_picture(viewport)
	if _rd and not _held:
		_prime()
		_hold_3d()


## The picture alone (the boot scene, before the city exists): the canvas up, the sound muted, a
## frame presented at once.
static func begin_picture(viewport: Viewport) -> void:
	if active or not supported() or viewport == null:
		return
	active = true
	_t0_ms = Time.get_ticks_msec()
	_rd = RenderingServer.get_rendering_device() != null
	_bus_was = AudioServer.is_bus_mute(0)
	AudioServer.set_bus_mute(0, true)
	_canvas = RenderingServer.canvas_create()
	RenderingServer.viewport_attach_canvas(viewport.get_viewport_rid(), _canvas)
	RenderingServer.viewport_set_canvas_stacking(viewport.get_viewport_rid(), _canvas, 129, 0)
	_item = RenderingServer.canvas_item_create()
	RenderingServer.canvas_item_set_parent(_item, _canvas)
	_root = viewport
	_stage = "Starting"
	_last_frame_us = Time.get_ticks_usec()
	if not RenderingServer.frame_post_draw.is_connected(_on_frame):
		RenderingServer.frame_post_draw.connect(_on_frame)
	tick(true)


static func _on_frame() -> void:
	if not active:
		return
	var now := Time.get_ticks_usec()
	var gap := (now - _last_frame_us) / 1000
	_last_frame_us = now
	if gap > max_gap_ms:
		max_gap_ms = gap
		max_gap_stage = _stage
	if gap > GAP_REPORT_MS:
		print("LOADING frame gap: %d ms in '%s' (at %d ms)" % [gap, _stage, Time.get_ticks_msec()])


## Draws PRIME_FRAMES of the world as it stands (the player, the sky - the city is not built yet)
## with a probe and two shadowed omni lights beside the camera, presenting the picture over them:
## see PRIME_FRAMES.
static func _prime() -> void:
	var cam := _root.get_camera_3d()
	var holder := Node3D.new()
	holder.name = "LoadPulsePrime"
	var parent: Node = cam if cam else _root
	parent.add_child(holder)
	var probe := ReflectionProbe.new()
	probe.update_mode = ReflectionProbe.UPDATE_ONCE
	probe.size = Vector3(0.05, 0.05, 0.05)
	holder.add_child(probe)
	for mode in [OmniLight3D.SHADOW_CUBE, OmniLight3D.SHADOW_DUAL_PARABOLOID]:
		var omni := OmniLight3D.new()
		omni.shadow_enabled = true
		omni.omni_shadow_mode = mode
		omni.omni_range = 0.02
		omni.light_energy = 0.0001
		omni.position = Vector3(0, 0, -1)
		holder.add_child(omni)
	# No geometry in these frames (the far plane a centimetre past the near one, the probe and the
	# lights a few centimetres across): only the environment's passes run, so nothing waits on a
	# mesh pipeline (with the player and the sky in view this was 82 s of no frame on lavapipe).
	var far_was := cam.far if cam else 0.0
	if cam:
		cam.far = cam.near + 0.01
	_priming = true
	for i in PRIME_FRAMES:
		tick(true)
	_priming = false
	if cam:
		cam.far = far_was
	holder.queue_free()


## The window draws no 3D; the off-screen viewport keeps the compilers fed.
static func _hold_3d() -> void:
	if _held:
		return
	_held = true
	_root.disable_3d = true
	_drain_scenario = RenderingServer.scenario_create()
	_drain_cam = RenderingServer.camera_create()
	_drain_vp = RenderingServer.viewport_create()
	RenderingServer.viewport_set_size(_drain_vp, 4, 4)
	RenderingServer.viewport_set_scenario(_drain_vp, _drain_scenario)
	RenderingServer.viewport_attach_camera(_drain_vp, _drain_cam)
	RenderingServer.viewport_set_update_mode(_drain_vp, RenderingServer.VIEWPORT_UPDATE_ALWAYS)
	# Not fed yet: while the city is BUILT nothing is handed to the compilers. A shader made then
	# (every new BaseMaterial3D feature set is one) compiles at once on the workers; queued behind
	# the city's thousands of pipelines, its first material made the main thread wait for all of
	# them (2-15 s without a frame on lavapipe while the landmarks built). feed() starts it.
	RenderingServer.viewport_set_active(_drain_vp, false)


## Hands every surface that exists, and every new one from now on, to the compilers (the loading
## screen calls it, then settle()): the off-screen viewport is drawn every frame.
static func feed() -> void:
	if _held and _drain_vp.is_valid():
		RenderingServer.viewport_set_active(_drain_vp, true)


## Waits, presenting frames, until everything handed to the compilers so far has been taken up
## (a low-priority fence task on the WorkerThreadPool). Await it. Returns the milliseconds.
static func settle(tree: SceneTree) -> int:
	if not active or not _rd:
		return 0
	var t0 := Time.get_ticks_msec()
	var p0 := _pipelines()
	await tree.process_frame
	await tree.process_frame
	var fence := WorkerThreadPool.add_task(_fence, false, "LoadPulseFence")
	while not WorkerThreadPool.is_task_completed(fence):
		note("%d pipelines" % (_pipelines() - p0))
		paint()
		await tree.process_frame
	WorkerThreadPool.wait_for_task_completion(fence)
	note("")
	return Time.get_ticks_msec() - t0


## The window's 3D comes back (the city is drawn again).
static func _release_3d() -> void:
	if not _held:
		return
	_held = false
	if _drain_vp.is_valid():
		RenderingServer.viewport_set_active(_drain_vp, false)
		RenderingServer.free_rid(_drain_vp)
		RenderingServer.free_rid(_drain_cam)
		RenderingServer.free_rid(_drain_scenario)
	_drain_vp = RID()
	_drain_cam = RID()
	_drain_scenario = RID()
	if is_instance_valid(_root):
		_root.disable_3d = false


## True while the window's 3D is held off (for the checks and the loading screen).
static func holding() -> bool:
	return _held


## A LoadClock stage begins (LoadClock.start calls this): the step text and the bar's range.
static func stage(name: String) -> void:
	if not active or not STAGES.has(name):
		return
	var s: Array = STAGES[name]
	_stage = s[3]
	_stage_from = maxf(float(s[0]), _progress)
	_stage_to = maxf(float(s[1]), _stage_from)
	_stage_tau = float(s[2])
	_stage_t0 = Time.get_ticks_msec()
	_progress = _stage_from


## The loading screen's own step text and progress (it maps its 0..1 onto ours from 0.38).
static func step(text: String, fraction: float) -> void:
	if not active:
		return
	_stage = text
	var p := lerpf(0.38, 0.80, clampf(fraction, 0.0, 1.0))
	if p > _progress:
		_progress = p
		_stage_from = p
		_stage_to = p
		_stage_t0 = Time.get_ticks_msec()


## The boot compile (docs/HANDOFF.md "The boot compile"): most of the game is ONE dependency cycle
## (tools/boot_compile/deps.py), and GDScript compiles a cycle in a single load() call - 15-20 s on
## a 4-core box with no frame of its own. Every script in the cycle calls this from its static
## initialiser (`static func _static_init() -> void: LoadPulse.compiled()`, added by
## `deps.py --hook`), which Godot runs as each script finishes compiling, INSIDE that one call:
## so the picture is presented (tick()) between scripts and the count moves. Outside the boot's
## picture it is one increment and a bool test. Changes nothing a script does.
static var compiled_count: int = 0
## The boot's count of scripts before the current load() and the total (0: no count shown).
static var compile_base: int = 0
static var compile_total: int = 0
static var _compile_shown: int = 0
## The longest time between two compiled() calls since compile_mark() (a probe's measure of how
## long the picture can hold still inside the cycle) and the script that ended it.
static var compile_max_gap_us: int = 0
static var compile_max_gap_after: String = ""
static var _compile_last_us: int = 0
## tools/boot_compile/compile_probe.gd: every compiled() call's time and caller (debug builds).
static var compile_trace: Array = []
static var _tracing: bool = false


static func compiled() -> void:
	compiled_count += 1
	var now := Time.get_ticks_usec()
	if _compile_last_us > 0 and now - _compile_last_us > compile_max_gap_us:
		compile_max_gap_us = now - _compile_last_us
		compile_max_gap_after = str(compiled_count)
	_compile_last_us = now
	if _tracing:
		var st := get_stack()
		compile_trace.append([now, str(st[1]["source"]) if st.size() > 1 else "?"])
	if not active:
		return
	if compile_total > 0:
		compile_progress(compile_base + compiled_count, compile_total)
	tick()


## Starts the gap measure (compile_max_gap_us) from now.
static func compile_mark() -> void:
	_compile_last_us = Time.get_ticks_usec()
	compile_max_gap_us = 0
	compile_max_gap_after = ""


## The "n / N scripts" line, never counting down (a script the cycle compiled early is counted
## again when the boot reaches it).
static func compile_progress(done: int, total: int) -> void:
	_compile_shown = clampi(maxi(_compile_shown, done), 0, total)
	_note = "%d / %d scripts" % [_compile_shown, total]
	# The bar follows the count across the compile's share of it (STAGES "compile the game").
	if total > 0 and active:
		var share: Array = STAGES["compile the game"]
		_progress = maxf(_progress, lerpf(float(share[0]), float(share[1]), float(_compile_shown) / total))


## A second line under the step (the pipeline count while the graphics compile).
static func note(text: String) -> void:
	_note = text


## Presents a frame now if `interval_ms` has gone by (or `force`). Call it from inside any loop
## that can run for more than a fraction of a second during the load.
static func tick(force: bool = false) -> void:
	if not active:
		return
	var now := Time.get_ticks_usec()
	if not force and now - _last_us < interval_ms * 1000:
		return
	if OS.get_thread_caller_id() != OS.get_main_thread_id():
		return
	paint()
	# Keep the window responding (no spinning cursor) and present the frame.
	DisplayServer.process_events()
	var t := Time.get_ticks_usec()
	# The pulse's own frames never draw the city on Compatibility either (a frame of it is seconds
	# on a software renderer); the normal frames in between still do, as before.
	var skip_3d := not _held and not _priming and is_instance_valid(_root) and not _root.disable_3d
	if skip_3d:
		_root.disable_3d = true
	RenderingServer.force_draw(true, 0.0)
	if skip_3d:
		_root.disable_3d = false
	_last_us = Time.get_ticks_usec()
	pulses += 1
	pulse_usec += _last_us - t
	# LOAD_PULSE_SHOT=<png>: the picture saved once, at the 200th pulse (LOAD_PULSE_SHOT_AT=n: the
	# n-th) - a still for the docs.
	if OS.get_environment("LOAD_PULSE_SHOT") != "" and pulses == (OS.get_environment("LOAD_PULSE_SHOT_AT").to_int() if OS.get_environment("LOAD_PULSE_SHOT_AT") != "" else 200) and is_instance_valid(_root):
		_root.get_texture().get_image().save_png(OS.get_environment("LOAD_PULSE_SHOT"))


## Redraws the loading picture (no present: the normal frame or tick() presents it).
static func paint() -> void:
	if not active or not _item.is_valid():
		return
	var view := _view_size()
	var p := _progress
	if _stage_to > _stage_from:
		var t := float(Time.get_ticks_msec() - _stage_t0) / 1000.0
		p = _stage_from + (_stage_to - _stage_from) * (1.0 - exp(-t / maxf(_stage_tau, 0.1)))
	_shown = maxf(_shown, p)
	var ci := _item
	RenderingServer.canvas_item_clear(ci)
	RenderingServer.canvas_item_set_modulate(ci, Color(1, 1, 1, _alpha))
	var s := HudTheme.scale(view)
	var safe := HudTheme.safe_rect(view)
	RenderingServer.canvas_item_add_rect(ci, Rect2(Vector2.ZERO, view), Color(0.035, 0.04, 0.055))
	var x := safe.position.x
	var bar_y := safe.end.y - 2.0 * s
	var bar_w := safe.size.x
	RenderingServer.canvas_item_add_rect(ci, Rect2(x, bar_y, bar_w, 3.0 * s), Color(1, 1, 1, 0.12))
	RenderingServer.canvas_item_add_rect(ci, Rect2(x, bar_y, bar_w * clampf(_shown, 0.0, 1.0), 3.0 * s), HudTheme.ACCENT)
	# A light running along the bar, so the picture visibly moves even while a stage creeps.
	var secs := float(Time.get_ticks_msec() - _t0_ms) / 1000.0
	var run := fposmod(secs * 0.45, 1.0)
	var glint_w := 90.0 * s
	RenderingServer.canvas_item_add_rect(ci, Rect2(x + (bar_w - glint_w) * run, bar_y, glint_w, 3.0 * s), Color(1, 1, 1, 0.22))
	var px := int(round(14.0 * s))
	var text_font := HudTheme.text()
	var medium := HudTheme.text_medium()
	var right := safe.end.x
	var pct := "%d%%" % int(floor(_shown * 100.0))
	text_font.draw_string(ci, Vector2(right - text_font.get_string_size(pct, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x, bar_y - 14.0 * s), pct, HORIZONTAL_ALIGNMENT_LEFT, -1, px, HudTheme.INK)
	var step_text := _stage.to_upper()
	medium.draw_string(ci, Vector2(right - 64.0 * s - medium.get_string_size(step_text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x, bar_y - 14.0 * s), step_text, HORIZONTAL_ALIGNMENT_LEFT, -1, px, HudTheme.SOFT)
	var clock := "%d:%02d" % [int(secs) / 60, int(secs) % 60]
	var info := clock if _note == "" else "%s   %s" % [_note, clock]
	medium.draw_string(ci, Vector2(right - medium.get_string_size(info, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x, bar_y - 38.0 * s), info, HORIZONTAL_ALIGNMENT_LEFT, -1, px, HudTheme.FAINT)
	var wpx := int(round(118.0 * s))
	var bold := HudTheme.display_bold()
	bold.draw_string(ci, Vector2(x - 5.0 * s, bar_y - 92.0 * s), "RANDO", HORIZONTAL_ALIGNMENT_LEFT, -1, wpx, HudTheme.INK)
	var w := bold.get_string_size("RANDO", HORIZONTAL_ALIGNMENT_LEFT, -1, wpx).x
	RenderingServer.canvas_item_add_rect(ci, Rect2(x + w + 14.0 * s, bar_y - 92.0 * s - wpx * 0.62, 6.0 * s, wpx * 0.62), HudTheme.ACCENT)
	text_font.draw_string(ci, Vector2(x + w + 32.0 * s, bar_y - 92.0 * s), "A CITY TO WRECK", HORIZONTAL_ALIGNMENT_LEFT, -1, int(round(16.0 * s)), HudTheme.SOFT)


static func _view_size() -> Vector2:
	var tree := Engine.get_main_loop() as SceneTree
	if tree and tree.root:
		return tree.root.get_visible_rect().size
	return Vector2(DisplayServer.window_get_size())


## The picture's opacity (the loading screen's fade-out).
static func set_alpha(a: float) -> void:
	_alpha = clampf(a, 0.0, 1.0)
	if active:
		paint()


## Waits (presenting frames) for every pipeline the worker threads were handed to finish
## compiling, then switches the window's 3D back on and lets the city draw behind the shade
## until a frame is quick again. Await it. RenderingDevice renderers only; elsewhere it returns.
static func drain(tree: SceneTree) -> void:
	if not active or not _rd:
		_release_3d()
		return
	LoadClock.start("graphics")
	feed()
	var t0 := Time.get_ticks_msec()
	var p0 := _pipelines()
	# One frame hands every surface that exists now to the compilers (the dirty list is drained by
	# any 3D render); then a low-priority task, which the pool runs only after every task queued
	# at high priority before it - the ubershader pipelines and the shader groups - has started.
	await tree.process_frame
	var fence := WorkerThreadPool.add_task(_fence, false, "LoadPulseFence")
	while not WorkerThreadPool.is_task_completed(fence):
		note("%d pipelines" % (_pipelines() - p0))
		paint()
		await tree.process_frame
	WorkerThreadPool.wait_for_task_completion(fence)
	var fence_ms := Time.get_ticks_msec() - t0
	# The city in view again, still behind the shade: the first frames build what a draw of the
	# whole city needs (and anything a fence could not see); held until a frame is quick.
	_release_3d()
	# Held until three frames in a row are steady (within a quarter of each other) and under a
	# second and a half: a GPU's frame is milliseconds, a software renderer's hundreds.
	var steady := 0
	var prev := -1
	for i in 40:
		var f0 := Time.get_ticks_usec()
		await tree.process_frame
		var ms := (Time.get_ticks_usec() - f0) / 1000
		if prev >= 0 and ms < 1500 and absi(ms - prev) <= maxi(prev / 4, 8):
			steady += 1
			if steady >= 3:
				break
		else:
			steady = 0
		prev = ms
	note("")
	print("LOADING graphics: %d pipelines queued, fence %d ms, %d ms in all" % [_pipelines() - p0, fence_ms, Time.get_ticks_msec() - t0])
	LoadClock.stop("graphics")


static func _fence() -> void:
	pass


static func _pipelines() -> int:
	return int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_SURFACE)) \
			+ int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_MESH))


## The load is over: the picture goes, the camera and the sound come back.
static func end() -> void:
	if not active:
		return
	_release_3d()
	if _item.is_valid():
		RenderingServer.free_rid(_item)
	if _canvas.is_valid():
		RenderingServer.free_rid(_canvas)
	_item = RID()
	_canvas = RID()
	AudioServer.set_bus_mute(0, _bus_was)
	print("LOADING pulse frames: %d presented inside loops, %d ms; longest gap between frames %d ms in '%s'" % [
			pulses, pulse_usec / 1000, max_gap_ms, max_gap_stage])
	if RenderingServer.frame_post_draw.is_connected(_on_frame):
		RenderingServer.frame_post_draw.disconnect(_on_frame)
	active = false
