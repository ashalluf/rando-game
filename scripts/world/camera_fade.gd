class_name CameraFade
## The camera never sits in a tree (rc2-hero-foot, 2026-11-01; docs/HANDOFF.md "The on-foot
## camera behind the hero"). The on-foot camera rides 6.5 m behind the hero on a spring arm that
## collides with the world layer only; street trees, palms and the LA trees have no collision, so
## on a tree-lined pavement the lens went through crowns and trunks (the hero_foot refcam's other
## pavements were half leaves). Every tree material dithers out what comes within FAR metres of the
## camera, gone inside NEAR (shaders/camera_fade.gdshaderinc for the three tree shaders; the
## scanned trees' bark is a StandardMaterial3D and takes its own pixel-dither distance fade).
## Never in the directional shadow pass. CAMERA_FADE=0 is the A/B.

static var enabled: bool = OS.get_environment("CAMERA_FADE") != "0"

## Gone inside this many metres of the camera, whole past FAR. The hero stands 6.5 m out, the
## aiming camera 3.8 m: neither ever fades a tree beside him.
const NEAR := 1.1
const FAR := 3.4


## A tree material (TreesCloseup.mark() for the shaders, TreesCloseup.dress() for the bark).
static func mark(mat: Material) -> void:
	if mat == null or not enabled:
		return
	if mat is ShaderMaterial:
		(mat as ShaderMaterial).set_shader_parameter("cf_near", NEAR)
		(mat as ShaderMaterial).set_shader_parameter("cf_far", FAR)
	elif mat is BaseMaterial3D:
		var m := mat as BaseMaterial3D
		m.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_DITHER
		m.distance_fade_min_distance = NEAR
		m.distance_fade_max_distance = FAR
