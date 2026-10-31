class_name RcHills
## The hills reference camera's fixes (fleet wave 4, `rc-hills`; docs/HANDOFF.md "The hills
## refcam"): what read fake in the front range from 260 m at 15:00. `RC_HILLS=0` in the
## environment is the A/B - every fix below goes back to main's look.
##
## - Summit crags: broad, low tors bedded in the crown instead of spires (RockOutcrops._make_tor).
## - Far tors: the ones under a few pixels dropped, the rest darkened (apply_rock()).
## - Steep faces: the terrain's textures laid from the side, not stretched down them (apply_terrain()).

static var _on: int = -1


static func on() -> bool:
	if _on < 0:
		_on = 0 if OS.get_environment("RC_HILLS") == "0" else 1
	return _on == 1


## The far tors (rock_outcrop.gdshader far_mode, RockFar's far cells): a tor under
## FAR_CULL_NDC of the frame is dropped (each at its own point in the range), and the aerial
## blend's tone is darkened. From 260 m the back ranges were covered in pale square flecks: every
## small tor on the plane, lit up-facing in full sun against a slope the plane paints and hazes.
const FAR_CULL_NDC := Vector2(0.010, 0.024)
const FAR_GREY_GAIN := 0.72


static func apply_rock(m: ShaderMaterial, far: bool) -> void:
	if not on() or not far:
		return
	m.set_shader_parameter("far_cull_ndc", FAR_CULL_NDC)
	m.set_shader_parameter("far_grey_gain", FAR_GREY_GAIN)


## The hill tiles' terrain (terrain.gdshader): steep faces take their textures from the side, and
## the dirt and rock tiles' structure fades out past TILE_FADE_PX metres a pixel.
const TILE_FADE_PX := Vector2(0.7, 1.8)


static func apply_terrain(m: ShaderMaterial) -> void:
	m.set_shader_parameter("side_mix", 1.0 if on() else 0.0)
	m.set_shader_parameter("tile_fade_px", TILE_FADE_PX if on() else Vector2.ZERO)
