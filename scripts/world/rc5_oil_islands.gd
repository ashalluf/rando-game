class_name Rc5OilIslands
extends RefCounted
## The oil islands at dusk from the Long Beach sand (refcam `oil_islands_dusk`, wave 8,
## docs/HANDOFF.md "The oil islands at dusk from the Long Beach sand").
##
## - The bay mirrors the islands' floods: every rig tower (its two gels at the screens' and panels'
##   albedo and the island shader's wash energy), each waterfall and each sound wall's pools are a
##   lit slab the ocean shader meets the reflected ray with (shaders/oil_island_mirror.gdshaderinc),
##   so after dark the islands stand on long broken columns of their own colour. Pushed with the
##   piers' rows (one line in Weather._push_pier_lights()).
##
## - The towers' floods are thrown UP the faces (oil_island.gdshader `dusk_look`): a cone from
##   each lamp at the foot, the gel's hue held, the crowns falling into the dusk so the screens and
##   derricks stand as silhouettes; the falls lamp-lit, not a white block.
##
## `RC5_OIL_ISLANDS=0` in the environment is the A/B (no sources pushed: the ocean is as before).

static var enabled: bool = OS.get_environment("RC5_OIL_ISLANDS") != "0"

## A tower's floods as the island shader draws them at the foot: the screens' albedo (~0.75) times
## the wash energy (oil_island.gdshader wash_energy 2.6), at the dusk look's cone and afterglow.
const TOWER_GAIN := 1.4
## A tower's screens stand this far out of its centre (OilIslands.TOWER_HALF plus the fins).
const TOWER_HALF := 6.5
## The falls' glow (oil_island.gdshader falls_glow and its blue-white).
const FALLS_COLOR := Color(0.55, 0.85, 1.0)
const FALLS_GAIN := 0.55
## The sound wall's pools, seen along the island: fewer and lower than a tower's.
const WALL_GAIN := 0.32


## [[Vector4(x, z, half width, top y), Color(linear rgb with energy, foot y)], ...].
static func sources() -> Array:
	var out: Array = []
	if not enabled or not OilIslands.enabled:
		return out
	for i in OilIslands.ISLANDS.size():
		var isl: Dictionary = OilIslands.ISLANDS[i]
		var wall_col := Color(0, 0, 0)
		for t: Dictionary in OilIslands.towers(i):
			var at := OilIslands.to_world(i, t.at)
			var gel: Color = (OilIslands.WASHES[int(t.wash)] + OilIslands.WASHES[int(t.wash2)]) * 0.5
			wall_col += gel
			out.append([Vector4(at.x, at.y, TOWER_HALF, OilIslands.PAD_Y + float(t.h)),
				Color(gel.r * TOWER_GAIN, gel.g * TOWER_GAIN, gel.b * TOWER_GAIN, OilIslands.PAD_Y)])
		var fa := OilIslands.falls_angle(i)
		var fp := OilIslands.to_world(i, OilIslands.ring_local(i, fa, 4.0))
		out.append([Vector4(fp.x, fp.y, OilIslands.FALLS_WIDTH * 0.5, OilIslands.PAD_Y + OilIslands.FALLS_TOP),
			Color(FALLS_COLOR.r * FALLS_GAIN, FALLS_COLOR.g * FALLS_GAIN, FALLS_COLOR.b * FALLS_GAIN, 0.3)])
		var n := float(OilIslands.towers(i).size())
		wall_col = wall_col / maxf(n, 1.0) * WALL_GAIN
		var half: Vector2 = isl.half
		var c := OilIslands.to_world(i, Vector2.ZERO)
		out.append([Vector4(c.x, c.y, (half.x - OilIslands.WALL_IN) * 0.9, OilIslands.PAD_Y + OilIslands.WALL_H.x * 0.6),
			Color(wall_col.r, wall_col.g, wall_col.b, OilIslands.PAD_Y)])
	return out


## Hands the sources to an ocean material (Weather, with the piers' rows).
static func push(mat: ShaderMaterial) -> void:
	if mat == null:
		return
	var src := sources()
	var a := PackedVector4Array()
	var b := PackedVector4Array()
	for s: Array in src:
		if a.size() >= 16:
			break
		a.append(s[0])
		var c: Color = s[1]
		b.append(Vector4(c.r, c.g, c.b, c.a))
	var count := a.size()
	while a.size() < 16:
		a.append(Vector4.ZERO)
		b.append(Vector4.ZERO)
	mat.set_shader_parameter("isl_src", a)
	mat.set_shader_parameter("isl_col", b)
	mat.set_shader_parameter("isl_count", count)


## The island material's look (OilIslandBuild.material()).
static func dress(mat: ShaderMaterial) -> void:
	mat.set_shader_parameter("dusk_look", 1.0 if enabled else 0.0)
