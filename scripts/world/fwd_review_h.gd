class_name FwdReviewH
## Forward+ review h (fleet wave 8, docs/HANDOFF.md "Forward+ review h"): what waves 6-7's look
## work drew differently on the Mac's renderer (Forward+) from the opengl3 stills, fixed. One
## switch, FWD_REVIEW_H=0, puts every look fix back the way it was (the A/B). Pure statics; each
## hook is one line in the system it touches.

static var enabled: bool = OS.get_environment("FWD_REVIEW_H") != "0"


## A float shader parameter that may not be set yet (null until someone sets it: Godot hands back
## null, not the shader's default, for an untouched parameter). `fallback` when it is not a number.
static func param(mat: ShaderMaterial, name: String, fallback: float = 0.0) -> float:
	var v: Variant = mat.get_shader_parameter(name) if mat != null else null
	if v is float or v is int or v is bool:
		return float(v)
	return fallback
