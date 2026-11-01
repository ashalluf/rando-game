class_name RcHills
## The hills reference camera's fixes (fleet wave 4, `rc-hills`; docs/HANDOFF.md "The hills
## refcam"): what read fake in the front range from 260 m at 15:00. `RC_HILLS=0` in the
## environment is the A/B - every fix below goes back to main's look.
##
## - Summit crags: broad, low tors bedded in the crown instead of spires (RockOutcrops._make_tor).
## - Far tors: the ones under a few pixels dropped, the rest darkened (apply_rock()).
## - Steep faces: the terrain's textures laid from the side, not stretched down them (apply_terrain()).
## - Shrub clumps gathered into thickets with gaps, sized by the field (cluster()).
## - The ridge sign: sheet-metal letters on a pipe frame, not 5 x 7 pixel boxes (HillSignLetters).
## - The far ridge sign kept off the plane inside the LOD ring (seat_far_sign()).

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


## The hill scatter's clumps (HillScatter.step()): a slow field in world metres that gathers them
## into thickets. Under CLUSTER_GAP (plus a little per clump) a clump is left out; above it a clump
## is scaled by the field (0.75-1.6x FULL, 0.85-1.3x LOD). Value noise, two octaves (CLUSTER_CELL and a third of it).
const CLUSTER_GAP := 0.24
const CLUSTER_CELL := 21.0


static func _lattice(i: int, j: int) -> float:
	var h := (i * 73856093) ^ (j * 19349663)
	h = (h ^ (h >> 13)) * 1274126177
	return float((h ^ (h >> 16)) & 65535) / 65535.0


static func _vnoise(p: Vector2) -> float:
	var i := int(floor(p.x))
	var j := int(floor(p.y))
	var f := p - Vector2(i, j)
	var u := f * f * (Vector2(3.0, 3.0) - 2.0 * f)
	return lerpf(lerpf(_lattice(i, j), _lattice(i + 1, j), u.x), lerpf(_lattice(i, j + 1), _lattice(i + 1, j + 1), u.x), u.y)


static func cluster(p: Vector2) -> float:
	var n := _vnoise(p / CLUSTER_CELL) * 0.7 + _vnoise(p / (CLUSTER_CELL / 3.0) + Vector2(17.3, 4.1)) * 0.3
	return clampf((n - 0.5) * 1.6 + 0.5, 0.0, 1.0)


## The far ridge sign (CityStreamer._seat_far_sign(), far_canopy.gdshader's rigid mode): not
## moved onto the plane while the camera is inside the LOD ring round it (the real terrain is drawn
## there), fully seated from SIGN_SEAT_MARGIN past it.
const SIGN_SEAT_MARGIN := 320.0


static func seat_far_sign(m: ShaderMaterial, lod_reach: float) -> void:
	if not on():
		return
	m.set_shader_parameter("rigid_real_reach", Vector2(lod_reach, lod_reach + SIGN_SEAT_MARGIN))
