class_name FwdReviewH
## Forward+ review h (fleet wave 8, docs/HANDOFF.md "Forward+ review h"): what waves 6-7's look
## work drew differently on the Mac's renderer (Forward+) from the opengl3 stills, fixed. One
## switch, FWD_REVIEW_H=0, puts every look fix back the way it was (the A/B). Pure statics; each
## hook is one line in the system it touches.

static var enabled: bool = OS.get_environment("FWD_REVIEW_H") != "0"


## At load (SkyExtras, beside FwdReviewG): the `fwd_review_h` shader global
## (shaders/fwd_review_h.gdshaderinc: a light level handed over in the renderer's own space on
## Forward+ - the refinery's flares, the port's floods). project.godot's default is 1.
static func apply() -> void:
	RenderingServer.global_shader_parameter_set("fwd_review_h", 1.0 if enabled else 0.0)


## A float shader parameter that may not be set yet (null until someone sets it: Godot hands back
## null, not the shader's default, for an untouched parameter). `fallback` when it is not a number.
static func param(mat: ShaderMaterial, name: String, fallback: float = 0.0) -> float:
	var v: Variant = mat.get_shader_parameter(name) if mat != null else null
	if v is float or v is int or v is bool:
		return float(v)
	return fallback


## A broad additive pool on light_pool.gdshader added in DISPLAY numbers on Forward+
## (`display_add_fwd`: fwd-review-e's `display_add` conversion, as the freeway's and the port's pools
## have, without display_add's ease from the air): on the default path the tint is added
## in linear HDR, so a pool's faint tail (a few % of its centre) shows several times stronger on the
## Mac than in the opengl3 stills it was tuned on, and the pool spreads into a flat carpet (the
## bonfires' firelight across the whole beach, the landing lights' pool down the runway).
## Compatibility is untouched (the shader's branch is Forward+ only). Returns the mesh.
static func display_pool(mesh: Mesh) -> Mesh:
	if enabled and mesh != null and mesh.surface_get_material(0) is ShaderMaterial:
		(mesh.surface_get_material(0) as ShaderMaterial).set_shader_parameter("display_add_fwd", true)
	return mesh
