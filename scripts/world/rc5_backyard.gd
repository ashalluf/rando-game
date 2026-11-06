class_name Rc5Backyard
extends RefCounted
## The suburban back yard from its patio on a Saturday afternoon (refcam5 `backyard_pool`,
## tools/refcams/cameras_w8.json; docs/HANDOFF.md "The back yard pool on a Saturday").
## RC5_BACKYARD=0 in the environment is the A/B: the yards exactly as before.
##
## - THE WEEKEND BARBECUE. Grills only cooked at dinner (17:06-21:30), so a Saturday afternoon's
##   yards had cold grills and no smoke. On a Saturday or Sunday `WEEKEND_SHARE` of the households
##   with a grill fire it up for a late lunch too (11:30-17:36, each its own window from its seed;
##   about two in five at 15:00, more than at dinner on a weekday: a weekend afternoon): the
##   `weekend` uniform on BackyardKit's grill and smoke materials, set from the day each time a
##   chunk's yards are built (`day_hook()`); backyard.gdshader and backyard_smoke.gdshader's
##   cooking() read it (the two copies agree; checked).

static var enabled: bool = OS.get_environment("RC5_BACKYARD") != "0"

## The share of the households with a grill (by its seed) that also cook at lunch on a weekend. Copied in both shaders' cooking() (`weekend_share`).
const WEEKEND_SHARE := 0.6
## The lunch window's start range and length range (hours), also in both shaders.
const LUNCH_START := Vector2(11.5, 14.0)
const LUNCH_LEN := Vector2(2.2, 3.6)
## FarmersMarket's days: 0 Sunday .. 6 Saturday.
const WEEKEND_DAYS := [0, 6]

## Forces the weekend flag (stills, checks): -1 the calendar, 0 a weekday, 1 a weekend.
static var force_weekend: int = -1


## 1 on a Saturday or Sunday (FarmersMarket's calendar: the game starts on a Saturday).
static func is_weekend(node: Node) -> bool:
	if force_weekend >= 0:
		return force_weekend == 1
	return FarmersMarket.weekday(node) in WEEKEND_DAYS


## Hands the day to the grill and smoke materials (Backyards.block(), every chunk build).
static func day_hook(ch: Node) -> void:
	var w := 1.0 if enabled and is_weekend(ch) else 0.0
	BackyardKit.material().set_shader_parameter("weekend", w)
	BackyardKit.smoke_material().set_shader_parameter("weekend", w)


## The same window as the shaders' cooking() (GDScript copy, for checks and probes).
static func cooking(seed: float, hour: float, weekend: bool, cook_share: float = 0.55) -> float:
	var on := 0.0
	if seed < cook_share:
		var s := seed / maxf(cook_share, 0.001)
		var start := 17.1 + s * 1.2
		var length := 1.5 + fposmod(s * 7.31, 1.0) * 1.6
		on = smoothstep(start, start + 0.15, hour) * (1.0 - smoothstep(start + length - 0.2, start + length, hour))
	if weekend and seed < WEEKEND_SHARE:
		var q := seed / WEEKEND_SHARE
		var ls := lerpf(LUNCH_START.x, LUNCH_START.y, fposmod(q * 3.17, 1.0))
		var ll := lerpf(LUNCH_LEN.x, LUNCH_LEN.y, fposmod(q * 5.71, 1.0))
		on = maxf(on, smoothstep(ls, ls + 0.15, hour) * (1.0 - smoothstep(ls + ll - 0.2, ls + ll, hour)))
	return on


# --- The pool ------------------------------------------------------------------------------------
## - THE POOL was a flat turquoise sheet at the lawn's level with a strip of pale stone round it:
##   no water line, no depth, no tank. Now each yard pool is a quad at the coping's top on
##   shaders/rc5_yard_pool.gdshader, which traces the whole pool under it (water a hand below the
##   coping behind a mosaic band, refraction, a sloping plaster floor with its stripe, caustics,
##   the sunny wall's shadow, absorption, the sky and the yard mirrored). The chunk's pools are ONE
##   mesh (`YardPools`), committed with YardFill's ground; the old pool piece stays under it.

## The pool's quad over SIDEWALK_TOP (YardFill.LIFT + the coping's 0.06), and where the floats sit:
## a little into it (Backyards._yard_top()), so a ring or a mat is half in the water, not under it.
const POOL_TOP := 0.11
const FLOAT_LIFT := 0.1

static var _pool_material: ShaderMaterial = null


static func pool_material() -> ShaderMaterial:
	if _pool_material == null:
		_pool_material = ShaderMaterial.new()
		_pool_material.shader = load("res://shaders/rc5_yard_pool.gdshader")
	return _pool_material


## A pool's quad, at the coping's top (YardFill._coping: base + 0.06 over its highest corner).
## FULL chunks only (the call site is FULL-only).
static func pool(ch: CityChunk, r: Rect2) -> void:
	if not enabled:
		return
	var g := -INF
	for p: Vector2 in [r.position, r.end, Vector2(r.position.x, r.end.y), Vector2(r.end.x, r.position.y)]:
		g = maxf(g, ch._gy(p.x, p.y))
	var y := CityChunk.SIDEWALK_TOP + POOL_TOP + g - 0.003
	var list: Array = ch.get_meta("rc5_pools", [])
	list.append([r, y])
	ch.set_meta("rc5_pools", list)


## Builds the chunk's pool mesh (YardFill.commit()).
static func commit_pools(ch: CityChunk) -> void:
	if not ch.has_meta("rc5_pools"):
		return
	var list: Array = ch.get_meta("rc5_pools")
	ch.remove_meta("rc5_pools")
	if list.is_empty():
		return
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for e: Array in list:
		var r: Rect2 = e[0]
		var y: float = e[1]
		var rnd := YardFill._h01([ch.plan.seed, int(r.position.x * 10.0), int(r.position.y * 10.0), "rc5_pool"])
		var c := Color(rnd, 1.0 if HouseNights.pool_variant(r) > 0.5 else 0.0, 0.0, 1.0)
		var corners := [Vector2(0, 0), Vector2(r.size.x, 0), Vector2(r.size.x, r.size.y), Vector2(0, r.size.y)]
		# Two triangles facing up (Godot's front faces are clockwise seen from the front).
		for k: int in [0, 1, 2, 0, 2, 3]:
			var q: Vector2 = corners[k]
			st.set_normal(Vector3.UP)
			st.set_color(c)
			st.set_uv(q)
			st.set_uv2(r.size)
			st.add_vertex(Vector3(r.position.x + q.x, y, r.position.y + q.y))
	var mi := MeshInstance3D.new()
	mi.name = "YardPools"
	mi.mesh = st.commit()
	mi.material_override = pool_material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ch.add_child(mi)


# --- The fence -------------------------------------------------------------------------------------
## - THE TIMBER FENCES were a printed sheet of plank texture, the same board after board, no top,
##   no foot. lot_walls.gdshader `rc5`: every board its own tone with a rounded edge and a dark gap,
##   a 2x6 cap with its shadow, a kickboard, weathering down from the cap, dirt at the foot, nails.

static func walls_hook(mat: ShaderMaterial) -> void:
	mat.set_shader_parameter("rc5", 1.0 if enabled else 0.0)


# --- The loungers' umbrella -------------------------------------------------------------------------
## - THE LOUNGERS stood in the full sun with nothing over them: the only umbrellas were through the
##   dining tables. `LOUNGER_UMBRELLA` of the lounger pairs get a market umbrella planted behind
##   their side table, shading the heads (the same mesh and canvas palette, one more instance in
##   the pair's own prop: it breaks with it). A hash of the seed and the pair's place, no roll.

const LOUNGER_UMBRELLA := 0.6
## Where the pole stands in the pair's space (the side table is at z 0.45, the heads toward +z).
const UMBRELLA_AT := Vector3(0.0, 0.0, 0.86)


static func lounger_umbrella(seed: int, it: Dictionary, xf: Transform3D) -> Array:
	if not enabled:
		return []
	var at: Vector2 = it.at
	var key := [seed, int(round(at.x * 10.0)), int(round(at.y * 10.0)), "rc5_lounger_umb"]
	if YardFill._h01(key) >= LOUNGER_UMBRELLA:
		return []
	var canvas := float(absi(hash(key + ["canvas"])) % 8) / 8.0 + (1.0 if YardFill._h01(key + ["stripe"]) < 0.4 else 0.0)
	var ux := xf * Transform3D(Basis(Vector3.UP, YardFill._h01(key + ["turn"]) * TAU), UMBRELLA_AT)
	return [["by_umbrella", BackyardKit.get_mesh("umbrella"), ux, Color.WHITE, Color(0.2, 0.2, 0.2, canvas + 0.01)]]
