class_name FwdReviewI
## Forward+ review i (fleet wave 8, docs/HANDOFF.md "Forward+ review i"): what waves 7-8's look
## work drew differently on the Mac's renderer (Forward+) from the opengl3 stills it was tuned on,
## fixed. One switch, FWD_REVIEW_I=0, puts every look fix back (the A/B). Pure statics; each hook is
## one line in the system it touches. Compatibility (the web, the stills) is untouched by every one.

static var enabled: bool = OS.get_environment("FWD_REVIEW_I") != "0"


## At load (SkyExtras, beside FwdReviewH): the `fwd_review_i` shader global
## (shaders/fwd_review_i.gdshaderinc: fi_add(), an additive amount handed over in display numbers on
## Forward+ - the jet's landing-light beams). project.godot's default is 1.
static func apply() -> void:
	RenderingServer.global_shader_parameter_set("fwd_review_i", 1.0 if enabled else 0.0)


## A broad additive pool on light_pool.gdshader added in DISPLAY numbers on Forward+
## (`display_add_fwd`, fwd-review-h's path): on the default path a 16 m pool's tint is added in linear
## HDR and the runway's edge-light glows (JetTakeoff.infield()) were bright blue and cream discs down
## both edges on the Mac, faint pools on opengl3. Returns the mesh.
static func display_pool(mesh: Mesh) -> Mesh:
	if enabled and mesh != null and mesh.surface_get_material(0) is ShaderMaterial:
		(mesh.surface_get_material(0) as ShaderMaterial).set_shader_parameter("display_add_fwd", true)
	return mesh
