class_name RiverLook
## The LA River from the bed (wave 5, refcam `la_river`, docs/HANDOFF.md "The LA River from the
## bed"): the `river_look` shader global the river's shaders read. 1 (the default) is the reviewed
## look: the low flow mirrors the channel's own banks and is turbid, the bed and banks keep their
## joints and stains at a grazing angle, the shaded bank takes the sunlit one's bounce; 0 is the old
## look exactly (`RIVER_LOOK=0` in the environment, the A/B). Also gates RiverDebris (litter, weeds).

static var _applied := false


static func enabled() -> bool:
	return OS.get_environment("RIVER_LOOK") != "0"


## Pushes the global once (RiverBuild calls it when it makes its materials).
static func apply() -> void:
	if _applied:
		return
	_applied = true
	RenderingServer.global_shader_parameter_set("river_look", 1.0 if enabled() else 0.0)


## The water sheet's vertex colour at `s` (river_water.gdshader's channel): the +o direction in
## world xz as 0..1 (r, g), the bed's half width / 40 (b), the bank's height / 10 (a).
static func water_color(rv: LaRiver, s: float) -> Color:
	var lat := (rv.point(s, 1.0) - rv.point(s, 0.0)).normalized()
	return Color(lat.x * 0.5 + 0.5, lat.y * 0.5 + 0.5, rv.bed_half(s) / 40.0, rv.depth(s) / 10.0)


## The water's mirror in GDScript (rw_mirror() in river_water.gdshader, change both): what a
## reflected ray `r` (world, heading up) from the water at `o0` metres off the centre line meets.
## 0 the bank's face, 1 the fence band over the coping, 2 the sky. `lat` is the +o direction.
static func mirror_hit(r: Vector3, o0: float, lat: Vector2, bed_half: float, depth: float) -> int:
	var a := Vector2(r.x, r.z).dot(lat)
	var up := maxf(r.y, 0.0005)
	var sg := 1.0 if a >= 0.0 else -1.0
	var aa := maxf(absf(a), 1e-4)
	var o_top := bed_half + depth * LaRiver.SLOPE
	var t_top := (o_top - sg * o0) / aa
	var h_top := toe_over_water() + depth
	if up * t_top >= h_top + 2.2:
		return 2
	if up * t_top >= h_top:
		return 1
	return 0


## How far the bank's toe stands over the low flow's surface (the shader's RW_TOE).
static func toe_over_water() -> float:
	return LaRiver.BED_FALL + LaRiver.LF_DEPTH - LaRiver.WATER_DEPTH
