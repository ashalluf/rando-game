class_name MotionBlurEffect
extends CompositorEffect
## Per-pixel motion blur (VISUAL_ROADMAP #12), Forward+ only. A CompositorEffect at
## POST_TRANSPARENT: it runs on the HDR frame at the internal resolution, after the transparent
## pass and BEFORE TAA / FSR 2.2 (the last callback Godot offers), which is where the temporal
## pass cleans up its noise and the tonemapper sees a blurred highlight as a streak of light.
## The five compute kernels are in `shaders/motion_blur.glsl` (see its header). `CameraPost`
## (scripts/player/camera_post.gd) builds this only when the renderer has a RenderingDevice
## (never on Compatibility / the web / the headless check) and sets its knobs every frame.
##
## Frame-rate independent: the engine's velocity is one rendered frame's displacement, so it is
## scaled by `shutter / reference_fps / frame_seconds` - the blur is what a camera with that
## exposure would see, whether the frame took 16 ms or 50 ms. Blur lengths are in pixels of a
## 1080-line frame and scaled to the internal resolution, so every quality level blurs alike.

const SHADER_PATH := "res://shaders/motion_blur.glsl"
const CONTEXT := &"motion_blur"
const KERNELS: Array[StringName] = [&"prepare", &"tile_x", &"tile_y", &"neighbor", &"gather"]

# Knobs; CameraPost owns the tunable copies (its @exports) and writes these every frame.
var strength: float = 1.0
var shutter: float = 0.5
var reference_fps: float = 60.0
var max_blur_px: float = 40.0
var threshold_px: float = 3.0
var samples: int = 12
var soft_z: float = 0.06
## Seconds the frame being drawn covers (real time, not scaled by Engine.time_scale).
var frame_seconds: float = 1.0 / 60.0
## Set for one frame to forget the camera's history: a teleport or an origin re-centre would
## otherwise read as a kilometre of motion. Cleared by the render callback.
var cut: bool = false
## A camera that moves further than this in one frame is taken as a cut (metres).
var max_camera_jump: float = 30.0

## True once the kernels compiled; false on a renderer without a RenderingDevice.
var ready: bool = false
## Frames the effect actually blurred (tests and tools read it).
var frames_drawn: int = 0

var _rd: RenderingDevice
var _shaders: Array[RID] = []
var _pipelines: Array[RID] = []
var _sampler: RID
var _prev_transform := Transform3D()
var _prev_projection := Projection()
var _has_prev: bool = false
var _frame: int = 0
var _tile: int = 0
var _size := Vector2i.ZERO


func _init() -> void:
	effect_callback_type = EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
	needs_motion_vectors = true
	_rd = RenderingServer.get_rendering_device()
	if _rd == null:
		enabled = false
		return
	RenderingServer.call_on_render_thread(_build)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _rd != null:
		# Freeing a shader frees the pipelines made from it.
		for shader in _shaders:
			if shader.is_valid():
				_rd.free_rid(shader)
		if _sampler.is_valid():
			_rd.free_rid(_sampler)


func _build() -> void:
	var file := load(SHADER_PATH) as RDShaderFile
	if file == null:
		push_error("MotionBlurEffect: %s did not load" % SHADER_PATH)
		return
	for kernel in KERNELS:
		var spirv := file.get_spirv(kernel)
		if spirv == null or spirv.compile_error_compute != "":
			push_error("MotionBlurEffect: kernel %s: %s" % [kernel, spirv.compile_error_compute if spirv else "missing"])
			return
		var shader := _rd.shader_create_from_spirv(spirv, "motion_blur_%s" % kernel)
		if not shader.is_valid():
			push_error("MotionBlurEffect: kernel %s did not build" % kernel)
			return
		_shaders.append(shader)
		_pipelines.append(_rd.compute_pipeline_create(shader))
	var state := RDSamplerState.new()
	state.min_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
	state.mag_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
	state.repeat_u = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	state.repeat_v = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	_sampler = _rd.sampler_create(state)
	ready = true


func _render_callback(_callback_type: int, render_data: RenderData) -> void:
	if not ready:
		return
	var buffers := render_data.get_render_scene_buffers() as RenderSceneBuffersRD
	var scene := render_data.get_render_scene_data() as RenderSceneDataRD
	if buffers == null or scene == null or buffers.get_view_count() != 1:
		return
	var size := buffers.get_internal_size()
	if size.x < 16 or size.y < 16:
		return
	# The camera's reprojection, for the pixels with no velocity of their own (see the shader).
	# get_cam_projection() is the corrected one (y flipped, reverse-Z in 0..1, the TAA jitter in
	# its z column); the jitter is dropped so a still camera reprojects to exactly zero.
	var cam_transform := scene.get_cam_transform()
	var cam_projection := scene.get_cam_projection()
	cam_projection.z.x = 0.0
	cam_projection.z.y = 0.0
	var moved := cam_transform.origin.distance_to(_prev_transform.origin)
	var valid := _has_prev and not cut and moved <= max_camera_jump
	var reprojection := Projection.IDENTITY
	if valid:
		reprojection = _prev_projection * Projection(_prev_transform.affine_inverse() * cam_transform) * cam_projection.inverse()
	_prev_transform = cam_transform
	_prev_projection = cam_projection
	_has_prev = true
	cut = false
	# A cut frame is left alone entirely: every moving object's own velocity is wrong in it too.
	if not valid:
		return
	var scale := strength * shutter / maxf(reference_fps, 1.0) / clampf(frame_seconds, 0.002, 0.25)
	if scale <= 0.0001:
		return
	var res_scale := float(size.y) / 1080.0
	var max_radius := maxf(1.0, max_blur_px * 0.5 * res_scale)
	var tile := int(ceil(max_radius))
	if tile != _tile or size != _size:
		if buffers.has_texture(CONTEXT, &"blur"):
			buffers.clear_context(CONTEXT)
		_tile = tile
		_size = size
	var grid := Vector2i((size.x + tile - 1) / tile, (size.y + tile - 1) / tile)
	var blur := _texture(buffers, &"blur", RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT, size)
	var copy := _texture(buffers, &"copy", RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT, size)
	var tile_x := _texture(buffers, &"tile_x", RenderingDevice.DATA_FORMAT_R16G16_SFLOAT, Vector2i(grid.x, size.y))
	var tiles := _texture(buffers, &"tiles", RenderingDevice.DATA_FORMAT_R16G16_SFLOAT, grid)
	var neighbors := _texture(buffers, &"neighbors", RenderingDevice.DATA_FORMAT_R16G16_SFLOAT, grid)
	var color := buffers.get_color_layer(0)
	var depth := buffers.get_depth_layer(0)
	var velocity := buffers.get_velocity_layer(0)
	if not (color.is_valid() and depth.is_valid() and velocity.is_valid()):
		return
	# Linear depth from the reverse-Z buffer: the corrected projection's z row is depth =
	# a + b / distance, with a = near / (far - near) and b = far * near / (far - near).
	var depth_a: float = cam_projection.z.z
	var depth_b: float = cam_projection.w.z
	if not (depth_b > 0.0):
		return
	_frame += 1
	var push := PackedFloat32Array()
	for c in 4:
		var col: Vector4 = reprojection[c]
		push.append_array([col.x, col.y, col.z, col.w])
	push.append_array([float(size.x), float(size.y), scale, threshold_px * res_scale, max_radius,
			depth_a, depth_b, soft_z, float(clampi(samples, 4, 32)), float(_frame % 1024),
			1.0, float(tile)])
	var push_bytes := push.to_byte_array()

	# One compute list per kernel: the render graph then orders them by the images they share.
	_rd.draw_command_begin_label("Motion Blur", Color(0.9, 0.6, 0.2))
	_dispatch(0, [_sampled(0, depth), _image(1, velocity), _image(2, color), _image(3, blur),
			_image(4, copy)], push_bytes, size)
	_dispatch(1, [_image(0, blur), _image(1, tile_x)], push_bytes, Vector2i(grid.x, size.y))
	_dispatch(2, [_image(0, tile_x), _image(1, tiles)], push_bytes, grid)
	_dispatch(3, [_image(0, tiles), _image(1, neighbors)], push_bytes, grid)
	_dispatch(4, [_image(0, copy), _image(1, blur), _image(2, neighbors), _image(3, color)],
			push_bytes, size)
	_rd.draw_command_end_label()
	frames_drawn += 1


func _dispatch(kernel: int, uniforms: Array, push_bytes: PackedByteArray, extent: Vector2i) -> void:
	var shader := _shaders[kernel]
	var set_rid := UniformSetCacheRD.get_cache(shader, 0, uniforms)
	var list := _rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(list, _pipelines[kernel])
	_rd.compute_list_bind_uniform_set(list, set_rid, 0)
	_rd.compute_list_set_push_constant(list, push_bytes, push_bytes.size())
	_rd.compute_list_dispatch(list, (extent.x + 7) / 8, (extent.y + 7) / 8, 1)
	_rd.compute_list_end()


func _texture(buffers: RenderSceneBuffersRD, name: StringName, format: int, extent: Vector2i) -> RID:
	if buffers.has_texture(CONTEXT, name):
		return buffers.get_texture(CONTEXT, name)
	var usage := RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
	return buffers.create_texture(CONTEXT, name, format, usage, RenderingDevice.TEXTURE_SAMPLES_1,
			extent, 1, 1, true, false)


func _image(binding: int, texture: RID) -> RDUniform:
	var u := RDUniform.new()
	u.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u.binding = binding
	u.add_id(texture)
	return u


func _sampled(binding: int, texture: RID) -> RDUniform:
	var u := RDUniform.new()
	u.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	u.binding = binding
	u.add_id(_sampler)
	u.add_id(texture)
	return u
