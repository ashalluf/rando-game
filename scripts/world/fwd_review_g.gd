class_name FwdReviewG
## Forward+ review g (fleet wave 5, docs/HANDOFF.md "Forward+ review g"): what wave 4's look work
## drew differently on the Mac's renderer (Forward+) from the opengl3 stills, fixed. One switch,
## FWD_REVIEW_G=0, puts every fix back the way it was (the A/B). Pure statics; each hook is one
## line in the system it touches.

static var enabled: bool = OS.get_environment("FWD_REVIEW_G") != "0"


## The sky (SkyExtras): the closed deck past the cloud volume's 90 km reach is handed over as its
## haze (sky.gdshader `far_deck`), not cut off at the horizon.
static func apply_sky(sky: ShaderMaterial) -> void:
	if sky != null:
		sky.set_shader_parameter("far_deck", 1.0 if enabled else 0.0)
