class_name SkatePark
extends RefCounted
## THE PIT - the boardwalk's skate park, poured concrete built in code at real size (fleet wave 3,
## "skate-park": "a concrete bowl and street section near the beach boardwalk ... with skaters
## riding them, spectators on the edge, graffiti").
##
## It stands where LandmarkVeniceBoardwalk always put its skate park (SKATE_X / SKATE_Z, the pad
## keeps the world's axes) and replaces that primitive-box park: `LandmarkVeniceBoardwalk.
## _skate_park()` hands over to build() while `enabled` (SKATE_PARK=0 in the environment is the
## A/B: the old boxes). Nothing is rolled from any rng the city has: the layout is constants, and
## everything that varies (riders, spectators, graffiti) is a hash of the anchor.
##
## THE GROUND: a beach's sand is a thin mesh over the GroundBody (y 0), so nothing can be dug into
## it (the boardwalk's header, "the hole problem"). So the park is a poured platform, as the old
## one was: a HIGH DECK (H_HI over the sand) with the pool and the snake run cut down through it to
## a floor just over the sand, a stair set, two hubba ledges and a bank down to a LOW TERRACE
## (H_LO) with the street section and a concrete mini ramp, board-formed retaining walls round it
## all - which is where the graffiti goes - railings on the high deck's drops, a ramp up from the
## sand on the walk side, and round planters where the boardwalk's palm row stands in it.
##
## Park-local frame: +X inland (toward the walk), +Z up the beach, origin at the pad's centre on the
## sand, y up. The park is W x L (x -15..15, z -22..22).
##
## Drawn: ONE mesh (a surface for the concrete and steel, one shader, `shaders/skate_park.gdshader`,
## what a face is in COLOR.a as kind / 16 - see K_*), cached per anchor and level; ONE concave
## collision shape from the same triangles (the coping and rails included, so a car can grind).
## The far copy (the boardwalk's far build) is the same builder with the small parts left out.
## The life (skaters on their lines, spectators) is SkateParkLife (scripts/world/skate_park_life.gd),
## detailed copy only.

## Off (SKATE_PARK=0): LandmarkVeniceBoardwalk builds its old box park.
static var enabled: bool = OS.get_environment("SKATE_PARK") != "0"

const ID := "skate_park"
## The invented name on the park's sign.
const NAME := "THE PIT"

# --- Massing --------------------------------------------------------------------------------------

const HALF_W := 15.0
const HALF_L := 22.0
## The high deck's top and the low terrace's over the sand, and the floor the pits are cut to.
const H_HI := 3.0
const H_LO := 1.3
const FLOOR := 0.25
## The step from the high deck to the terrace runs z 0 .. STEP_RUN on x > STEP_X; west of STEP_X
## it is a sheer wall at z 0 (the terrace starts there).
const STEP_X := 1.0
const STEP_RUN := 3.0
## The stair set: x STAIR_X0 .. STAIR_X1, STAIR_COUNT risers. The hubbas either side are HUBBA_W
## wide and stand HUBBA_H over the nosing line. East of the second hubba the bank runs to the wall.
const STAIR_X0 := 1.6
const STAIR_X1 := 7.6
const STAIR_COUNT := 9
const HUBBA_W := 0.6
const HUBBA_H := 0.48
## The handrail down the middle of the stairs: its height over the nosing line, its radius.
const RAIL_H := 0.82
const RAIL_R := 0.026
## Walls: board-formed concrete, CAP_W wide cap band on top standing CAP_H proud.
## How far the walls' feet go under the lowest sand, and the pad's clearance over the highest.
const WALL_FOOT := -0.3
const SAND_CLEAR := 0.04
const CAP_W := 0.36
const CAP_H := 0.05

# --- The pool ------------------------------------------------------------------------------------

## A squared oval (superellipse) pool: centre, half axes, exponent; Rt the transition's radius
## (the rest of the depth is vertical just under the coping, the "vert").
const POOL_C := Vector2(5.5, -11.5)
const POOL_A := 6.0
const POOL_B := 8.4
const POOL_EXP := 2.7
const POOL_RT := 2.3
## Points round the rim (the near level; the far copy takes a quarter).
const POOL_POINTS := 112
## The pool's coping: bullnose blocks this long, this far over the deck, rounding this far into the
## pool; the tile band under it, this deep.
const COPING_BLOCK := 0.6
const COPING_BACK := 0.32
const COPING_NOSE := 0.07
const TILE_BAND := 0.16

# --- The snake run -------------------------------------------------------------------------------

## A channel weaving down the sea side: its centre line runs SNAKE_Z0 -> SNAKE_Z1 at x SNAKE_X plus
## a sine of SNAKE_AMP (one and a half waves); SNAKE_HALF is half its width rim to rim. Depth from
## SNAKE_DEPTH.x at its head to .y at its tail; the vert is SNAKE_VERT, the rest transition.
const SNAKE_X := -9.0
const SNAKE_Z0 := -18.4
const SNAKE_Z1 := -4.6
const SNAKE_AMP := 1.25
const SNAKE_WAVES := 1.0
const SNAKE_HALF := 3.0
const SNAKE_DEPTH := Vector2(1.55, 2.45)
const SNAKE_VERT := 0.15

# --- The mini ramp -------------------------------------------------------------------------------

## A concrete mini ramp on the terrace's sea side, ridden along z: x MINI_X0..MINI_X1, the flat's
## middle at MINI_ZC, MINI_FLAT long; each wall a quarter of radius MINI_R cut at MINI_H, a deck
## MINI_DECK deep behind its steel coping.
const MINI_X0 := -14.4
const MINI_X1 := -6.6
const MINI_ZC := 11.6
const MINI_FLAT := 5.6
const MINI_R := 2.6
const MINI_H := 1.85
const MINI_DECK := 1.7
const COPING_R := 0.033

# --- Street section on the terrace ----------------------------------------------------------------

## [x0, x1, z0, z1, height]: the manual pad, the long ledge, the funbox.
const MANUAL := [2.4, 4.6, 6.2, 13.4, 0.3]
const LEDGE := [6.5, 7.1, 5.6, 15.6, 0.46]
const FUNBOX := [8.6, 12.6, 15.4, 19.4, 0.6]
const FUNBOX_KICK := 1.3
## The flat bar: x, z0, z1, height.
const FLATBAR := [10.2, 6.0, 13.2, 0.36]
## The ramp up from the sand on the walk side: z0, z1 and its run out over the sand.
const ACCESS_Z := Vector2(10.4, 15.6)
const ACCESS_RUN := 8.0

## Railings on the high deck's drops: post pitch, top and mid rail heights.
const RAIL_PITCH := 2.0
const RAIL_TOP := 1.05
const RAIL_MID := 0.55
const PIPE_R := 0.024

# --- Kinds (COLOR.a = kind / 16; shaders/skate_park.gdshader's K_*) -------------------------------

const K_DECK := 0
const K_BOWL := 1
const K_COPING := 2
const K_TILE := 3
const K_STEEL := 4
const K_WALL := 5
const K_STAIR := 6
const K_SOIL := 7
const K_CAP := 8
const K_PAINT := 9
const K_LEDGE := 10
const K_GRIP := 11
const K_WOOD := 12
const K_WHEEL := 13
const K_LAMP := 14

## Floodlight poles: park-local XZ, the surface they stand on; POLE_H tall, the head reaching
## POLE_ARM toward the park's middle.
const POLES := [[Vector2(-14.4, -21.3), H_HI], [Vector2(12.4, -21.3), H_HI], [Vector2(-14.5, 21.4), H_LO],
	[Vector2(11.8, 21.5), H_LO], [Vector2(-14.5, 1.4), H_LO]]
const POLE_H := 8.5
const POLE_ARM := 1.3

const GALV := Color(0.56, 0.57, 0.58)
const LEDGE_RED := Color(0.42, 0.05, 0.035)
const LEDGE_GREY := Color(0.6, 0.6, 0.6)

static var _meshes: Dictionary = {}
static var _faces: Dictionary = {}
static var _material: ShaderMaterial
static var _pits: Dictionary = {}
## The site's sand under the pad, relative to the origin (lowest, and at the access ramp's foot):
## set by build() before the geometry, which is cached per anchor.
static var _foot: float = WALL_FOOT
static var _ramp_low: float = 0.02


## The park's origin in the world: the boardwalk's own placement, lifted onto the sand. The
## beach's berm crest (CityChunk._sand_y(), up to 1.3 m) runs under the pad, so the old park's bowl
## floor at the plan's ground was buried a metre deep in sand: the pad stands on the highest sand
## under it, and its walls run down to the lowest.
static func origin(anchor: Vector2, plan: CityPlan) -> Vector3:
	var o := LandmarkVeniceBoardwalk._at(anchor, plan, LandmarkVeniceBoardwalk.SKATE_X, LandmarkVeniceBoardwalk.SKATE_Z, 0.0)
	return o + Vector3(0.0, _sand_range(plan, o).y + SAND_CLEAR, 0.0)


## The sand's lowest and highest over the pad (and the access ramp's foot), over `o`'s ground.
static func _sand_range(plan: CityPlan, o: Vector3) -> Vector2:
	var lo := INF
	var hi := -INF
	for i in 7:
		for j in 9:
			var p := Vector2(o.x + lerpf(-HALF_W, HALF_W + ACCESS_RUN, float(i) / 6.0), o.z + lerpf(-HALF_L, HALF_L, float(j) / 8.0))
			var y := sand_y(plan, p) - o.y
			lo = minf(lo, y)
			hi = maxf(hi, y)
	return Vector2(lo, hi)


## The beach sand's height at world XZ `p`: CityChunk._sand_y()'s profile across the beach.
static func sand_y(plan: CityPlan, p: Vector2) -> float:
	if plan == null or plan.macro == null:
		return 0.0
	var water_x: float = plan.macro.coast_x(p.y)
	var width: float = maxf(plan.macro.beach_width_at(p.y), 1.0)
	var across := clampf((p.x - water_x) / width, 0.0, 1.0)
	var crest := CityChunk.SAND_CREST + CityChunk.SAND_CUSP * sin(p.y * 0.11) * cos(p.y * 0.047)
	if across <= CityChunk.SAND_BERM_AT:
		return lerpf(CityChunk.SAND_EDGE, CityChunk.SAND_EDGE + crest, across / CityChunk.SAND_BERM_AT)
	var t := (across - CityChunk.SAND_BERM_AT) / (1.0 - CityChunk.SAND_BERM_AT)
	return lerpf(CityChunk.SAND_EDGE + crest, CityChunk.SAND_HIGH, t * t * (3.0 - 2.0 * t))


## Builds the park under `parent` (the landmark's holder, true world space), its collision on
## `statics`, and - detailed - its life. Called by LandmarkVeniceBoardwalk._skate_park().
static func build(anchor: Vector2, parent: Node3D, statics: StaticBody3D, plan: CityPlan, detailed: bool) -> Node3D:
	var base := origin(anchor, plan)
	var palms := palm_spots(anchor, plan)
	var root := Node3D.new()
	root.name = "SkatePark"
	root.position = base
	if detailed and OS.get_environment("SKATE_DEBUG") == "1":
		print("SKATE origin %.1f,%.2f,%.1f  EYE overview %.1f,%.1f,%.1f,135,-30  EYE pool %.1f,%.1f,%.1f,180,-22" % [
			base.x, base.y, base.z, base.x + 26.0, base.y + 20.0, base.z - 26.0,
			base.x + 5.0, base.y + H_HI + 1.7, base.z - 21.0])
	parent.add_child(root)
	var key := "%d|%d|%s" % [int(anchor.x), int(anchor.y), "near" if detailed else "far"]
	if not _meshes.has(key):
		var sr := _sand_range(plan, base)
		_foot = sr.x + WALL_FOOT
		_ramp_low = sand_y(plan, Vector2(base.x + HALF_W + ACCESS_RUN, base.z + (ACCESS_Z.x + ACCESS_Z.y) * 0.5)) - base.y + 0.02
		var geo := Geo.new(detailed)
		_build_geo(geo, palms, detailed)
		_meshes[key] = geo.commit(material())
		_faces[key] = geo.faces()
	var mi := MeshInstance3D.new()
	mi.name = "Concrete"
	mi.mesh = _meshes[key]
	if not detailed:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	if statics != null:
		var cs := CollisionShape3D.new()
		cs.name = "SkateParkShape"
		var shape := ConcavePolygonShape3D.new()
		shape.backface_collision = true
		shape.set_faces(_faces[key])
		cs.shape = shape
		# The landmark's statics sit in the holder's own frame (CityChunk's _statics: identity).
		cs.transform = statics.transform.affine_inverse() * Transform3D(Basis(), base)
		statics.add_child(cs)
	if detailed and not OS.has_feature("web"):
		for spot: Vector3 in lamp_spots():
			var l := OmniLight3D.new()
			l.omni_range = 26.0
			l.omni_attenuation = 1.2
			l.light_energy = 0.0
			l.light_color = Color(0.92, 0.95, 1.0)
			l.shadow_enabled = false
			l.distance_fade_enabled = true
			l.distance_fade_begin = 140.0
			l.distance_fade_length = 30.0
			l.position = spot
			l.add_to_group("lamp_light")
			root.add_child(l)
	if detailed:
		var life := SkateParkLife.new()
		life.name = "SkateParkLife"
		life.anchor = anchor
		root.add_child(life)
	return root


static func material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = load("res://shaders/skate_park.gdshader")
		_material.set_shader_parameter("concrete_tex", PropFactory.texture("concrete", "Color"))
		_material.set_shader_parameter("concrete_nrm", PropFactory.texture("concrete", "NormalGL"))
		_material.set_shader_parameter("tag_atlas", load("res://assets/textures/street_wear/street_wear_tags.png"))
	return _material


# --- Pure layout -----------------------------------------------------------------------------------

## The boardwalk's palms that stand inside the pad (park-local XZ): the same rolls
## LandmarkVeniceBoardwalk._palm_rows() makes, in its order. Each gets a planter.
static func palm_spots(anchor: Vector2, plan: CityPlan) -> PackedVector2Array:
	var out := PackedVector2Array()
	var B := LandmarkVeniceBoardwalk
	var base := origin(anchor, plan)
	var count := int(B.LENGTH / B.PALM_SPACING)
	for row in B.PALM_ROW_X.size():
		var rng := RandomNumberGenerator.new()
		rng.seed = B._salt(anchor, 17 + row)
		var x: float = B.PALM_ROW_X[row]
		for i in count:
			rng.randf_range(B.PALM_MIN_H, B.PALM_MAX_H)
			rng.randf_range(0.0, TAU)
			rng.randf_range(-0.05, 0.05)
			var jitter := rng.randf_range(-0.8, 0.8)
			rng.randi()
			var z := -B.LENGTH * 0.5 + (float(i) + 0.5 + float(row) * 0.5) * B.PALM_SPACING + jitter
			if absf(z) > B.LENGTH * 0.5:
				continue
			var w := B._at(anchor, plan, x, z, 0.0)
			var p := Vector2(w.x - base.x, w.z - base.z)
			if absf(p.x) < HALF_W - 0.6 and absf(p.y) < HALF_L - 0.6:
				out.append(p)
	return out


## The pool's rim, anticlockwise seen from above in (x, z), `n` points.
static func pool_rim(n: int = POOL_POINTS) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in n:
		var t := TAU * float(i) / float(n)
		var c := cos(t)
		var s := sin(t)
		var x := signf(c) * pow(absf(c), 2.0 / POOL_EXP) * POOL_A
		var z := signf(s) * pow(absf(s), 2.0 / POOL_EXP) * POOL_B
		out.append(POOL_C + Vector2(x, z))
	return _even(out, n)


## The snake run's centre line x at `z` and its depth there.
static func snake_x(z: float) -> float:
	var t := clampf((z - SNAKE_Z0) / (SNAKE_Z1 - SNAKE_Z0), 0.0, 1.0)
	return SNAKE_X + SNAKE_AMP * sin(t * TAU * SNAKE_WAVES)


static func snake_depth(z: float) -> float:
	var t := clampf((z - SNAKE_Z0) / (SNAKE_Z1 - SNAKE_Z0), 0.0, 1.0)
	return lerpf(SNAKE_DEPTH.x, SNAKE_DEPTH.y, t)


## The snake run's rim: the centre line offset SNAKE_HALF either way with a half circle at each end.
static func snake_rim(step: float = 0.45) -> PackedVector2Array:
	var centre := PackedVector2Array()
	var n := maxi(8, int((SNAKE_Z1 - SNAKE_Z0) / step))
	for i in n + 1:
		var z := lerpf(SNAKE_Z0, SNAKE_Z1, float(i) / float(n))
		centre.append(Vector2(snake_x(z), z))
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	for i in centre.size():
		var a: Vector2 = centre[maxi(i - 1, 0)]
		var b: Vector2 = centre[mini(i + 1, centre.size() - 1)]
		var t := (b - a).normalized()
		var nrm := Vector2(-t.y, t.x)
		left.append(centre[i] + nrm * SNAKE_HALF)
		right.append(centre[i] - nrm * SNAKE_HALF)
	var out := PackedVector2Array()
	var caps := 10
	# Up the right side, round the tail, down the left side, round the head.
	for i in right.size():
		out.append(right[i])
	var tail := centre[centre.size() - 1]
	var t1 := (centre[centre.size() - 1] - centre[centre.size() - 2]).normalized()
	for k in range(1, caps):
		var a := -PI * 0.5 + PI * float(k) / float(caps)
		var d := t1 * cos(a) + Vector2(-t1.y, t1.x) * sin(a)
		out.append(tail + d * SNAKE_HALF)
	for i in range(left.size() - 1, -1, -1):
		out.append(left[i])
	var head := centre[0]
	var t0 := (centre[1] - centre[0]).normalized()
	for k in range(1, caps):
		var a := PI * 0.5 + PI * float(k) / float(caps)
		var d := t0 * cos(a) + Vector2(-t0.y, t0.x) * sin(a)
		out.append(head + d * SNAKE_HALF)
	if _area(out) < 0.0:
		out.reverse()
	return out


## The pits cut through the high deck: [rim, depth per rim point, Rt per rim point, coping kind].
static func pits(detailed: bool = true) -> Array:
	if _pits.has(detailed):
		return _pits[detailed]
	var out: Array = []
	var rim := pool_rim(POOL_POINTS if detailed else POOL_POINTS / 4)
	var depth := PackedFloat32Array()
	var rt := PackedFloat32Array()
	for p in rim:
		depth.append(H_HI - FLOOR)
		rt.append(POOL_RT)
	out.append({"name": "pool", "rim": rim, "depth": depth, "rt": rt, "coping": K_COPING, "tile": true})
	var srim := snake_rim(0.45 if detailed else 1.8)
	var sd := PackedFloat32Array()
	var srt := PackedFloat32Array()
	for p in srim:
		var d := snake_depth(p.y)
		sd.append(d)
		srt.append(minf(d - SNAKE_VERT, SNAKE_HALF - 0.9))
	out.append({"name": "snake", "rim": srim, "depth": sd, "rt": srt, "coping": K_CAP, "tile": false})
	_pits[detailed] = out
	return out


## The pit wall's profile at `d` metres in from the rim (or the deepest point past it): [y over
## the floor's level, outward normal's (inward, up) split]. `depth` the pit's depth there, `rt`
## its transition radius.
static func profile(d: float, depth: float, rt: float) -> Array:
	if d <= 0.0:
		return [depth, 0.0]
	if d >= rt:
		return [0.0, PI * 0.5]
	# The quarter circle: d = rt (1 - cos phi), y = rt (1 - sin phi).
	var phi := acos(clampf(1.0 - d / rt, -1.0, 1.0))
	return [rt * (1.0 - sin(phi)), phi]


## The surface height (park-local y) of the mini ramp's riding surface at `z` (the flat, the two
## quarters, the decks).
static func mini_y(z: float) -> float:
	var dz := absf(z - MINI_ZC) - MINI_FLAT * 0.5
	if dz <= 0.0:
		return H_LO
	var reach := mini_reach()
	if dz <= reach:
		return H_LO + MINI_R - sqrt(maxf(MINI_R * MINI_R - dz * dz, 0.0))
	return H_LO + MINI_H


## How far a mini ramp quarter runs along z.
static func mini_reach() -> float:
	return sqrt(maxf(MINI_R * MINI_R - (MINI_R - MINI_H) * (MINI_R - MINI_H), 0.0))


## The z of the stair set's nosing line at height `y` and back (the hubbas and the rail follow it).
static func stair_y(z: float) -> float:
	return lerpf(H_HI, H_LO, clampf(z / STEP_RUN, 0.0, 1.0))


## Height of the walkable top at park-local XZ `p` (the pits, the terrace and its step, the mini
## ramp, the street pieces; the sand outside). What the skater lines and the checks are worked
## against.
static func surface_y(p: Vector2) -> float:
	if absf(p.x) > HALF_W or absf(p.y) > HALF_L:
		return 0.0
	if p.y < 0.0 or (p.y < STEP_RUN and p.x > STEP_X):
		if p.y >= 0.0:
			if p.x > STAIR_X1 + HUBBA_W:
				return stair_y(p.y)
			if p.x >= STAIR_X0 and p.x <= STAIR_X1:
				var k := mini(int(p.y / (STEP_RUN / float(STAIR_COUNT))), STAIR_COUNT - 1)
				return H_HI - float(k + 1) * (H_HI - H_LO) / float(STAIR_COUNT)
			return stair_y(p.y) + HUBBA_H
		for pit: Dictionary in pits():
			var rim: PackedVector2Array = pit.rim
			if Geometry2D.is_point_in_polygon(p, rim):
				var d := _dist_to_poly(p, rim)
				var i := _nearest_index(p, rim)
				var depth: float = pit.depth[i]
				var rt: float = pit.rt[i]
				return H_HI - depth + float(profile(d, depth, rt)[0])
		return H_HI
	if p.x >= MINI_X0 and p.x <= MINI_X1 and absf(p.y - MINI_ZC) <= MINI_FLAT * 0.5 + mini_reach() + MINI_DECK:
		return mini_y(p.y)
	for b: Array in [MANUAL, LEDGE]:
		if p.x >= b[0] and p.x <= b[1] and p.y >= b[2] and p.y <= b[3]:
			return H_LO + float(b[4])
	if p.x >= FUNBOX[0] and p.x <= FUNBOX[1]:
		if p.y >= FUNBOX[2] and p.y <= FUNBOX[3]:
			return H_LO + FUNBOX[4]
		var kd := maxf(FUNBOX[2] - p.y, p.y - FUNBOX[3])
		if kd > 0.0 and kd < FUNBOX_KICK:
			return H_LO + FUNBOX[4] * (1.0 - kd / FUNBOX_KICK)
	return H_LO


# --- Geometry -------------------------------------------------------------------------------------

static func _build_geo(g: Geo, palms: PackedVector2Array, detailed: bool) -> void:
	var pit_list := pits(detailed)
	_high_deck(g, pit_list, palms)
	for pit: Dictionary in pit_list:
		_pit(g, pit, detailed)
	_terrace(g)
	_step(g)
	_walls(g)
	_mini_ramp(g, detailed)
	_street(g, detailed)
	_access(g)
	for p in palms:
		_planter(g, p, H_HI if p.y < 0.0 else H_LO, detailed)
	for pole: Array in POLES:
		_pole(g, pole[0], float(pole[1]), detailed)
	if detailed:
		# The park's name, painted big on the walls the boardwalk and the beach path see.
		_letters(g, NAME, 1.15, Vector3(HALF_W + 0.012, H_HI - 1.0, -12.0), Vector3.RIGHT, Color(0.86, 0.84, 0.78))
		_letters(g, NAME, 0.7, Vector3(-4.0, H_LO - 0.62, HALF_L + 0.012), Vector3.BACK, Color(0.80, 0.16, 0.10))
	if detailed:
		_railings(g, palms)
		_stair_rail(g)


## The high deck: the rectangle less the pits, laid by a Delaunay over the rims, a grid kept clear
## of them, and the edges; triangles inside a pit dropped.
static func _high_deck(g: Geo, pit_list: Array, palms: PackedVector2Array) -> void:
	var pts := PackedVector2Array()
	var x0 := -HALF_W
	var x1 := HALF_W
	var z0 := -HALF_L
	var z1 := 0.0
	var step := 1.0
	var nx := int((x1 - x0) / step)
	var nz := int((z1 - z0) / step)
	for i in nx + 1:
		pts.append(Vector2(x0 + float(i) * step, z0))
		pts.append(Vector2(x0 + float(i) * step, z1))
	for j in range(1, nz):
		pts.append(Vector2(x0, z0 + float(j) * step))
		pts.append(Vector2(x1, z0 + float(j) * step))
	var rims: Array = []
	for pit: Dictionary in pit_list:
		rims.append(pit.rim)
		pts.append_array(pit.rim)
	for i in range(1, nx):
		for j in range(1, nz):
			var p := Vector2(x0 + float(i) * step, z0 + float(j) * step)
			var clear := true
			for rim: PackedVector2Array in rims:
				if Geometry2D.is_point_in_polygon(p, rim) or _dist_to_poly(p, rim) < 0.45:
					clear = false
					break
			if clear:
				pts.append(p)
	var tris := Geometry2D.triangulate_delaunay(pts)
	for t in range(0, tris.size(), 3):
		var a := pts[tris[t]]
		var b := pts[tris[t + 1]]
		var c := pts[tris[t + 2]]
		var m := (a + b + c) / 3.0
		if m.x < x0 or m.x > x1 or m.y < z0 or m.y > z1:
			continue
		var inside := false
		for rim: PackedVector2Array in rims:
			if Geometry2D.is_point_in_polygon(m, rim):
				inside = true
				break
		if inside:
			continue
		g.tri(Vector3(a.x, H_HI, a.y), Vector3(b.x, H_HI, b.y), Vector3(c.x, H_HI, c.y), Vector3.UP, K_DECK)


## A pit: the wall swept down its profile from the rim, the floor laid inside, the coping or the
## rounded lip on top, and the tile band under a pool's coping.
static func _pit(g: Geo, pit: Dictionary, detailed: bool) -> void:
	var rim: PackedVector2Array = pit.rim
	var n := rim.size()
	var inward := _inward(rim)
	var steps := 9 if detailed else 4
	var rows: Array = []
	# Rows from the rim down: the vert, then the quarter circle, its last row the floor's edge.
	var along := PackedFloat32Array()
	var acc := 0.0
	for i in n:
		along.append(acc)
		acc += rim[i].distance_to(rim[(i + 1) % n])
	for i in n:
		var row: Array = []
		var depth: float = pit.depth[i]
		var rt: float = pit.rt[i]
		var vert := maxf(depth - rt, 0.0)
		var inn: Vector2 = inward[i]
		# [d, y, phi]
		row.append([0.0, H_HI, 0.0])
		if pit.tile and vert > TILE_BAND + 0.05:
			row.append([0.0, H_HI - 0.04, 0.0])
			row.append([0.0, H_HI - 0.04 - TILE_BAND, 0.0])
		row.append([0.0, H_HI - vert, 0.0])
		for k in range(1, steps + 1):
			var phi := PI * 0.5 * float(k) / float(steps)
			row.append([rt * (1.0 - cos(phi)), H_HI - vert - rt * sin(phi), phi])
		var out: Array = []
		for r: Array in row:
			var p: Vector2 = rim[i] + inn * float(r[0])
			out.append([Vector3(p.x, r[1], p.y), Vector3(inn.x * cos(r[2]), sin(r[2]), inn.y * cos(r[2])), r[1]])
		rows.append(out)
	for i in n:
		var j := (i + 1) % n
		var ra: Array = rows[i]
		var rb: Array = rows[j]
		var m := mini(ra.size(), rb.size())
		for k in m - 1:
			var y_top: float = ra[k][2]
			var kind := K_BOWL
			if pit.tile and k == 1 and ra.size() > 3 and absf(y_top - (H_HI - 0.04)) < 0.01:
				kind = K_TILE
			var u0 := along[i]
			var u1 := along[i] + rim[i].distance_to(rim[j])
			g.quad_n([ra[k][0], rb[k][0], rb[k + 1][0], ra[k + 1][0]], [ra[k][1], rb[k][1], rb[k + 1][1], ra[k + 1][1]], kind,
				[Vector2(u0, ra[k][2]), Vector2(u1, rb[k][2]), Vector2(u1, rb[k + 1][2]), Vector2(u0, ra[k + 1][2])])
	# The floor: the last row's ring, triangulated.
	var ring := PackedVector2Array()
	var ys := PackedFloat32Array()
	for i in n:
		var last: Vector3 = (rows[i] as Array)[(rows[i] as Array).size() - 1][0]
		ring.append(Vector2(last.x, last.z))
		ys.append(last.y)
	var idx := Geometry2D.triangulate_polygon(ring)
	for t in range(0, idx.size(), 3):
		var a := Vector3(ring[idx[t]].x, ys[idx[t]], ring[idx[t]].y)
		var b := Vector3(ring[idx[t + 1]].x, ys[idx[t + 1]], ring[idx[t + 1]].y)
		var c := Vector3(ring[idx[t + 2]].x, ys[idx[t + 2]], ring[idx[t + 2]].y)
		var nrm := (b - a).cross(c - a).normalized()
		if nrm.y < 0.0:
			nrm = -nrm
		g.tri(a, b, c, nrm, K_BOWL)
	# The lip: bullnose coping blocks on the pool, a rounded concrete edge on the snake.
	var prof: Array
	if pit.coping == K_COPING:
		prof = [[-COPING_BACK, 0.0, Vector2(0.0, -1.0)], [-COPING_BACK, CAP_H * 0.6, Vector2(-1.0, 0.0)],
			[-COPING_BACK + 0.02, CAP_H, Vector2(-0.3, 1.0)], [0.0, CAP_H, Vector2(0.0, 1.0)],
			[COPING_NOSE * 0.7, CAP_H - COPING_NOSE * 0.3, Vector2(0.7, 0.7)], [COPING_NOSE, -0.03, Vector2(1.0, 0.0)],
			[COPING_NOSE * 0.6, -0.09, Vector2(0.6, -0.8)], [0.0, -0.1, Vector2(0.0, -1.0)]]
	else:
		prof = [[-0.18, 0.0, Vector2(0.0, 1.0)], [-0.04, 0.0, Vector2(0.3, 1.0)], [0.02, -0.03, Vector2(0.8, 0.6)], [0.03, -0.09, Vector2(1.0, 0.0)]]
	if not detailed:
		prof = [prof[0], prof[prof.size() / 2], prof[prof.size() - 1]]
	for i in n:
		var j := (i + 1) % n
		var u0 := along[i]
		var u1 := along[i] + rim[i].distance_to(rim[j])
		var ia: Vector2 = inward[i]
		var ib: Vector2 = inward[j]
		for k in prof.size() - 1:
			var pa: Array = prof[k]
			var pb: Array = prof[k + 1]
			var v := [
				_lip(rim[i], ia, pa), _lip(rim[j], ib, pa), _lip(rim[j], ib, pb), _lip(rim[i], ia, pb)]
			var nn := [_lip_n(ia, pa), _lip_n(ib, pa), _lip_n(ib, pb), _lip_n(ia, pb)]
			g.quad_n(v, nn, pit.coping, [Vector2(u0, float(k)), Vector2(u1, float(k)), Vector2(u1, float(k + 1)), Vector2(u0, float(k + 1))])


static func _lip(r: Vector2, inn: Vector2, p: Array) -> Vector3:
	var q := r + inn * float(p[0])
	return Vector3(q.x, H_HI + float(p[1]), q.y)


static func _lip_n(inn: Vector2, p: Array) -> Vector3:
	var d: Vector2 = p[2]
	return Vector3(inn.x * d.x, d.y, inn.y * d.x).normalized()


## The terrace: the L of z 0..L/2 less the step's corner, at H_LO.
static func _terrace(g: Geo) -> void:
	var poly := PackedVector2Array([Vector2(-HALF_W, 0.0), Vector2(STEP_X, 0.0), Vector2(STEP_X, STEP_RUN),
		Vector2(HALF_W, STEP_RUN), Vector2(HALF_W, HALF_L), Vector2(-HALF_W, HALF_L)])
	# Cut into a grid of strips so the shading and the collision are not one long sliver.
	for zi in 11:
		var za := lerpf(0.0, HALF_L, float(zi) / 11.0)
		var zb := lerpf(0.0, HALF_L, float(zi + 1) / 11.0)
		for xi in 10:
			var xa := lerpf(-HALF_W, HALF_W, float(xi) / 10.0)
			var xb := lerpf(-HALF_W, HALF_W, float(xi + 1) / 10.0)
			var cell := PackedVector2Array([Vector2(xa, za), Vector2(xb, za), Vector2(xb, zb), Vector2(xa, zb)])
			for piece: PackedVector2Array in Geometry2D.intersect_polygons(cell, poly):
				var idx := Geometry2D.triangulate_polygon(piece)
				for t in range(0, idx.size(), 3):
					g.tri(_v(piece[idx[t]], H_LO), _v(piece[idx[t + 1]], H_LO), _v(piece[idx[t + 2]], H_LO), Vector3.UP, K_DECK)


## The step down: the sheer wall west of STEP_X, the hubbas, the stairs, the bank.
static func _step(g: Geo) -> void:
	# The drop wall (faces +z), graffiti on it; and its rounded concrete cap.
	g.box_face(Vector3(-HALF_W, H_LO, 0.0), Vector3(STEP_X, H_LO, 0.0), Vector3(STEP_X, H_HI, 0.0), Vector3(-HALF_W, H_HI, 0.0), Vector3.BACK, K_WALL, 0.0)
	g.quad(Vector3(-HALF_W, H_HI, -0.02), Vector3(STEP_X, H_HI, -0.02), Vector3(STEP_X, H_HI + 0.0, 0.06), Vector3(-HALF_W, H_HI, 0.06), Vector3.UP, K_CAP)
	var rise := (H_HI - H_LO) / float(STAIR_COUNT)
	var run := STEP_RUN / float(STAIR_COUNT)
	for k in STAIR_COUNT:
		var top := H_HI - float(k + 1) * rise
		var z_a := float(k) * run
		var z_b := float(k + 1) * run
		# The riser (faces +z), the tread, and a steel nosing angle on its edge.
		g.quad(Vector3(STAIR_X0, top, z_a), Vector3(STAIR_X1, top, z_a), Vector3(STAIR_X1, top + rise, z_a), Vector3(STAIR_X0, top + rise, z_a), Vector3.BACK, K_STAIR)
		g.quad(Vector3(STAIR_X0, top, z_a), Vector3(STAIR_X1, top, z_a), Vector3(STAIR_X1, top, z_b), Vector3(STAIR_X0, top, z_b), Vector3.UP, K_STAIR)
		g.quad(Vector3(STAIR_X0, top + 0.004, z_a - 0.005), Vector3(STAIR_X1, top + 0.004, z_a - 0.005), Vector3(STAIR_X1, top + 0.004, z_a + 0.045), Vector3(STAIR_X0, top + 0.004, z_a + 0.045), Vector3.UP, K_STEEL, GALV)
	# The hubbas: a block each side, its top the nosing line plus HUBBA_H, steel angle on the edges.
	for hx: float in [STAIR_X0 - HUBBA_W, STAIR_X1]:
		var xa := hx
		var xb := hx + HUBBA_W
		var t0 := H_HI + HUBBA_H
		var t1 := H_LO + HUBBA_H
		g.quad(Vector3(xa, t0, 0.0), Vector3(xb, t0, 0.0), Vector3(xb, t1, STEP_RUN), Vector3(xa, t1, STEP_RUN), Vector3(0.0, STEP_RUN, H_HI - H_LO).normalized(), K_LEDGE, LEDGE_GREY)
		g.quad(Vector3(xa, H_LO, STEP_RUN), Vector3(xb, H_LO, STEP_RUN), Vector3(xb, t1, STEP_RUN), Vector3(xa, t1, STEP_RUN), Vector3.BACK, K_LEDGE, LEDGE_GREY)
		g.quad(Vector3(xa, H_HI, 0.0), Vector3(xb, H_HI, 0.0), Vector3(xb, t0, 0.0), Vector3(xa, t0, 0.0), Vector3.FORWARD, K_LEDGE, LEDGE_GREY)
		for sx: float in [xa, xb]:
			var nrm := Vector3.LEFT if sx == xa else Vector3.RIGHT
			g.quad(Vector3(sx, H_LO, STEP_RUN), Vector3(sx, H_LO, 0.0), Vector3(sx, t0, 0.0), Vector3(sx, t1, STEP_RUN), nrm, K_WALL)
			_angle(g, Vector3(sx, t0, 0.0), Vector3(sx, t1, STEP_RUN), nrm)
	# The bank.
	var bx0 := STAIR_X1 + HUBBA_W
	var bn := Vector3(0.0, STEP_RUN, H_HI - H_LO).normalized()
	for k in 3:
		var za := STEP_RUN * float(k) / 3.0
		var zb := STEP_RUN * float(k + 1) / 3.0
		g.quad(Vector3(bx0, stair_y(za), za), Vector3(HALF_W, stair_y(za), za), Vector3(HALF_W, stair_y(zb), zb), Vector3(bx0, stair_y(zb), zb), bn, K_DECK)
	# The cheek over the bank at the walk side wall.
	g.tri(Vector3(HALF_W, H_HI, 0.0), Vector3(HALF_W, H_LO, STEP_RUN), Vector3(HALF_W, H_HI, STEP_RUN), Vector3.LEFT, K_WALL)


## A steel angle along an edge from `a` to `b` (its outer face toward `side`).
static func _angle(g: Geo, a: Vector3, b: Vector3, side: Vector3) -> void:
	var w := 0.05
	var dn := Vector3(0.0, -w, 0.0)
	g.quad(a + side * 0.004, b + side * 0.004, b + side * 0.004 + dn, a + side * 0.004 + dn, side, K_STEEL, GALV)
	var inn := -side * w
	var up := Vector3(0.0, 0.004, 0.0)
	g.quad(a + up, b + up, b + up + inn, a + up + inn, Vector3.UP, K_STEEL, GALV)


## The retaining walls round the pad (their outer faces carry the graffiti) and their caps.
static func _walls(g: Geo) -> void:
	# [from, to, outward normal, top]: going round anticlockwise from the south-west corner.
	var runs: Array = [
		[Vector2(-HALF_W, -HALF_L), Vector2(HALF_W, -HALF_L), Vector3.FORWARD, H_HI],
		[Vector2(HALF_W, -HALF_L), Vector2(HALF_W, STEP_RUN), Vector3.RIGHT, H_HI],
		[Vector2(HALF_W, STEP_RUN), Vector2(HALF_W, HALF_L), Vector3.RIGHT, H_LO],
		[Vector2(HALF_W, HALF_L), Vector2(-HALF_W, HALF_L), Vector3.BACK, H_LO],
		[Vector2(-HALF_W, HALF_L), Vector2(-HALF_W, 0.0), Vector3.LEFT, H_LO],
		[Vector2(-HALF_W, 0.0), Vector2(-HALF_W, -HALF_L), Vector3.LEFT, H_HI],
	]
	var u := 0.0
	for r: Array in runs:
		var a: Vector2 = r[0]
		var b: Vector2 = r[1]
		var nrm: Vector3 = r[2]
		var top: float = r[3]
		var o := Vector3(nrm.x, 0.0, nrm.z) * 0.05
		var len := a.distance_to(b)
		g.box_face(_v(a, _foot), _v(b, _foot), _v(b, top), _v(a, top), nrm, K_WALL, u)
		# The cap: a band standing CAP_H proud, a lip over the face.
		var inn := -Vector3(nrm.x, 0.0, nrm.z) * (CAP_W - 0.05)
		g.quad(_v(a, top + CAP_H) + o, _v(b, top + CAP_H) + o, _v(b, top + CAP_H) + inn, _v(a, top + CAP_H) + inn, Vector3.UP, K_CAP)
		g.quad(_v(a, top - 0.06) + o, _v(b, top - 0.06) + o, _v(b, top + CAP_H) + o, _v(a, top + CAP_H) + o, nrm, K_CAP)
		g.quad(_v(a, top) + inn, _v(b, top) + inn, _v(b, top + CAP_H) + inn, _v(a, top + CAP_H) + inn, -nrm, K_CAP)
		u += len


## The concrete mini ramp: the riding surface swept across x, its decks, side walls (painted on),
## the back walls, steel coping.
static func _mini_ramp(g: Geo, detailed: bool) -> void:
	var reach := mini_reach()
	var z_lo := MINI_ZC - MINI_FLAT * 0.5 - reach - MINI_DECK
	var z_hi := MINI_ZC + MINI_FLAT * 0.5 + reach + MINI_DECK
	var prof := PackedVector2Array()
	var steps := 14 if detailed else 5
	prof.append(Vector2(z_lo, H_LO + MINI_H))
	for k in range(steps, -1, -1):
		var dz := reach * float(k) / float(steps)
		prof.append(Vector2(MINI_ZC - MINI_FLAT * 0.5 - dz, mini_y(MINI_ZC - MINI_FLAT * 0.5 - dz)))
	for k in steps + 1:
		var dz := reach * float(k) / float(steps)
		prof.append(Vector2(MINI_ZC + MINI_FLAT * 0.5 + dz, mini_y(MINI_ZC + MINI_FLAT * 0.5 + dz)))
	prof.append(Vector2(z_hi, H_LO + MINI_H))
	for k in prof.size() - 1:
		var a := prof[k]
		var b := prof[k + 1]
		var t := (b - a).normalized()
		var nrm := Vector3(0.0, t.x, -t.y)
		if nrm.y < 0.0:
			nrm = -nrm
		if absf(t.y) < 0.01 and absf(a.y - H_LO) < 0.01:
			nrm = Vector3.UP
		var kind := K_DECK if absf(a.y - (H_LO + MINI_H)) < 0.01 and absf(b.y - (H_LO + MINI_H)) < 0.01 else K_BOWL
		g.quad(Vector3(MINI_X0, a.y, a.x), Vector3(MINI_X1, a.y, a.x), Vector3(MINI_X1, b.y, b.x), Vector3(MINI_X0, b.y, b.x), nrm, kind)
	# Side walls: the profile closed along the terrace, triangulated.
	var side := PackedVector2Array()
	for p in prof:
		side.append(p)
	side.append(Vector2(z_hi, H_LO))
	side.append(Vector2(z_lo, H_LO))
	var idx := Geometry2D.triangulate_polygon(side)
	for sx: float in [MINI_X0, MINI_X1]:
		var nrm := Vector3.LEFT if sx == MINI_X0 else Vector3.RIGHT
		for t in range(0, idx.size(), 3):
			g.tri(Vector3(sx, side[idx[t]].y, side[idx[t]].x), Vector3(sx, side[idx[t + 1]].y, side[idx[t + 1]].x), Vector3(sx, side[idx[t + 2]].y, side[idx[t + 2]].x), nrm, K_WALL, Color(1, 1, 1), true)
	for z: float in [z_lo, z_hi]:
		var nrm := Vector3.FORWARD if z == z_lo else Vector3.BACK
		g.box_face(Vector3(MINI_X0, H_LO, z), Vector3(MINI_X1, H_LO, z), Vector3(MINI_X1, H_LO + MINI_H, z), Vector3(MINI_X0, H_LO + MINI_H, z), nrm, K_WALL, 40.0)
	# Coping pipes at the lips, and a railing round the back of each deck.
	for s: float in [-1.0, 1.0]:
		var zc := MINI_ZC + s * (MINI_FLAT * 0.5 + reach)
		g.tube(Vector3(MINI_X0, H_LO + MINI_H - 0.01, zc), Vector3(MINI_X1, H_LO + MINI_H - 0.01, zc), COPING_R, 10 if detailed else 4, K_STEEL, GALV)
		if detailed:
			var zb := MINI_ZC + s * (MINI_FLAT * 0.5 + reach + MINI_DECK - 0.1)
			_rail_run(g, Vector3(MINI_X0 + 0.1, H_LO + MINI_H, zb), Vector3(MINI_X1 - 0.1, H_LO + MINI_H, zb))


## The street pieces on the terrace.
static func _street(g: Geo, detailed: bool) -> void:
	_block(g, MANUAL, K_LEDGE, LEDGE_GREY, detailed)
	_block(g, LEDGE, K_LEDGE, LEDGE_RED, detailed)
	# The funbox: a block with a kicker bank each end.
	var fb: Array = FUNBOX
	var h: float = fb[4]
	_block(g, fb, K_DECK, Color(1, 1, 1), false)
	for s: float in [-1.0, 1.0]:
		var z_edge: float = fb[2] if s < 0.0 else fb[3]
		var z_out := z_edge + s * FUNBOX_KICK
		var nrm := Vector3(0.0, FUNBOX_KICK, -s * h).normalized()
		g.quad(Vector3(fb[0], H_LO + h, z_edge), Vector3(fb[1], H_LO + h, z_edge), Vector3(fb[1], H_LO, z_out), Vector3(fb[0], H_LO, z_out), nrm, K_DECK)
		for sx: float in [fb[0], fb[1]]:
			g.tri(Vector3(sx, H_LO, z_edge), Vector3(sx, H_LO + h, z_edge), Vector3(sx, H_LO, z_out), Vector3.LEFT if sx == fb[0] else Vector3.RIGHT, K_WALL)
		if detailed:
			_angle(g, Vector3(fb[0], H_LO + h, z_edge), Vector3(fb[1], H_LO + h, z_edge), Vector3(0.0, 0.0, s))
	# The flat bar: a round rail on three posts.
	var bx: float = FLATBAR[0]
	var bh: float = FLATBAR[3]
	g.tube(Vector3(bx, H_LO + bh, FLATBAR[1]), Vector3(bx, H_LO + bh, FLATBAR[2]), 0.032, 10 if detailed else 4, K_STEEL, Color(0.13, 0.13, 0.14))
	for k in 3:
		var z := lerpf(FLATBAR[1] + 0.3, FLATBAR[2] - 0.3, float(k) / 2.0)
		g.tube(Vector3(bx, H_LO, z), Vector3(bx, H_LO + bh, z), 0.03, 6, K_STEEL, Color(0.13, 0.13, 0.14))
		g.quad(Vector3(bx - 0.09, H_LO + 0.006, z - 0.09), Vector3(bx + 0.09, H_LO + 0.006, z - 0.09), Vector3(bx + 0.09, H_LO + 0.006, z + 0.09), Vector3(bx - 0.09, H_LO + 0.006, z + 0.09), Vector3.UP, K_STEEL, Color(0.13, 0.13, 0.14))


## A box sitting on the terrace ([x0, x1, z0, z1, h]): top, four sides, steel angle on the top edges
## (a ledge's are what gets ground).
static func _block(g: Geo, b: Array, kind: int, tint: Color, edges: bool) -> void:
	var x0: float = b[0]
	var x1: float = b[1]
	var z0: float = b[2]
	var z1: float = b[3]
	var top: float = H_LO + float(b[4])
	g.quad(Vector3(x0, top, z0), Vector3(x1, top, z0), Vector3(x1, top, z1), Vector3(x0, top, z1), Vector3.UP, kind, tint)
	g.quad(Vector3(x0, H_LO, z0), Vector3(x1, H_LO, z0), Vector3(x1, top, z0), Vector3(x0, top, z0), Vector3.FORWARD, kind, tint)
	g.quad(Vector3(x0, H_LO, z1), Vector3(x1, H_LO, z1), Vector3(x1, top, z1), Vector3(x0, top, z1), Vector3.BACK, kind, tint)
	g.quad(Vector3(x0, H_LO, z0), Vector3(x0, H_LO, z1), Vector3(x0, top, z1), Vector3(x0, top, z0), Vector3.LEFT, kind, tint)
	g.quad(Vector3(x1, H_LO, z0), Vector3(x1, H_LO, z1), Vector3(x1, top, z1), Vector3(x1, top, z0), Vector3.RIGHT, kind, tint)
	if edges:
		_angle(g, Vector3(x0, top, z0), Vector3(x0, top, z1), Vector3.LEFT)
		_angle(g, Vector3(x1, top, z0), Vector3(x1, top, z1), Vector3.RIGHT)


## The ramp up from the sand on the walk side, with kerbs.
static func _access(g: Geo) -> void:
	var za := ACCESS_Z.x
	var zb := ACCESS_Z.y
	var x_out := HALF_W + ACCESS_RUN
	var low := _ramp_low
	var nrm := Vector3(H_LO - low, ACCESS_RUN, 0.0).normalized()
	g.quad(Vector3(HALF_W, H_LO, za), Vector3(x_out, low, za), Vector3(x_out, low, zb), Vector3(HALF_W, H_LO, zb), nrm, K_DECK)
	for z: float in [za, zb]:
		var side := Vector3.FORWARD if z == za else Vector3.BACK
		g.tri(Vector3(HALF_W, _foot, z), Vector3(HALF_W, H_LO, z), Vector3(x_out, low, z), side, K_WALL)
		g.tri(Vector3(HALF_W, _foot, z), Vector3(x_out, low, z), Vector3(x_out, minf(_foot, low - 0.3), z), side, K_WALL)


## A round planter round a palm that stands in the pad, on the surface at `top`.
static func _planter(g: Geo, c: Vector2, top: float, detailed: bool) -> void:
	var seg := 20 if detailed else 8
	var r := 1.15
	var h := 0.48
	for k in seg:
		var a0 := TAU * float(k) / float(seg)
		var a1 := TAU * float(k + 1) / float(seg)
		var d0 := Vector2(cos(a0), sin(a0))
		var d1 := Vector2(cos(a1), sin(a1))
		var o0 := c + d0 * r
		var o1 := c + d1 * r
		var i0 := c + d0 * (r - 0.18)
		var i1 := c + d1 * (r - 0.18)
		g.quad_n([_v(o0, top), _v(o1, top), _v(o1, top + h), _v(o0, top + h)], [Vector3(d0.x, 0, d0.y), Vector3(d1.x, 0, d1.y), Vector3(d1.x, 0, d1.y), Vector3(d0.x, 0, d0.y)], K_CAP)
		g.quad(_v(o0, top + h), _v(o1, top + h), _v(i1, top + h), _v(i0, top + h), Vector3.UP, K_CAP)
		g.quad_n([_v(i0, top + h), _v(i1, top + h), _v(i1, top + h - 0.12), _v(i0, top + h - 0.12)], [Vector3(-d0.x, 0, -d0.y), Vector3(-d1.x, 0, -d1.y), Vector3(-d1.x, 0, -d1.y), Vector3(-d0.x, 0, -d0.y)], K_CAP)
		g.tri(_v(c, top + h - 0.12), _v(i0, top + h - 0.12), _v(i1, top + h - 0.12), Vector3.UP, K_SOIL)


## A floodlight pole: a tapered steel column on a base plate, an arm, a flat LED head (lit after
## dark in the shader; the light itself is an OmniLight3D in the lamp group, build()).
static func _pole(g: Geo, at: Vector2, top: float, detailed: bool) -> void:
	var to_mid := (Vector2(0.0, 0.0) - at).normalized()
	var foot := _v(at, top)
	var head := foot + Vector3(0.0, POLE_H, 0.0)
	var steel := Color(0.34, 0.35, 0.36)
	g.tube(foot, head, 0.085, 10 if detailed else 5, K_STEEL, steel)
	if detailed:
		g.tube(foot, foot + Vector3(0.0, 0.5, 0.0), 0.12, 10, K_STEEL, steel)
		g.quad(foot + Vector3(-0.22, 0.01, -0.22), foot + Vector3(0.22, 0.01, -0.22), foot + Vector3(0.22, 0.01, 0.22), foot + Vector3(-0.22, 0.01, 0.22), Vector3.UP, K_STEEL, steel)
	var arm_end := head + Vector3(to_mid.x, 0.0, to_mid.y) * POLE_ARM + Vector3(0.0, 0.15, 0.0)
	g.tube(head - Vector3(0.0, 0.2, 0.0), arm_end, 0.045, 6 if detailed else 4, K_STEEL, steel)
	# The head: a flat box, its underside the LED panel, tilted a little toward the park.
	var fwd := Vector3(to_mid.x, 0.0, to_mid.y)
	var side := fwd.cross(Vector3.UP)
	var c := arm_end + fwd * 0.35
	var hw := 0.32
	var hl := 0.45
	var tilt := Vector3(0.0, -0.08, 0.0)
	var a := c - side * hw - fwd * hl
	var b := c + side * hw - fwd * hl
	var d := c + side * hw + fwd * hl + tilt
	var e := c - side * hw + fwd * hl + tilt
	var up := Vector3(0.0, 0.11, 0.0)
	g.quad(a + up, b + up, d + up, e + up, Vector3.UP, K_STEEL, steel)
	g.quad(a, b, d, e, Vector3.DOWN, K_LAMP)
	g.quad(a, b, b + up, a + up, -fwd, K_STEEL, steel)
	g.quad(e, d, d + up, e + up, fwd, K_STEEL, steel)
	g.quad(a, e, e + up, a + up, -side, K_STEEL, steel)
	g.quad(b, d, d + up, b + up, side, K_STEEL, steel)


## `text` painted on a wall face facing `nrm` (RIGHT or BACK), centred at `at`, `height` tall.
static func _letters(g: Geo, text: String, height: float, at: Vector3, nrm: Vector3, tint: Color) -> void:
	var geo: Array = FreewayKit.text_geo(text, height)
	var verts: PackedVector3Array = geo[0]
	var idx: PackedInt32Array = geo[1]
	# The reader's right along the wall: -z on a +x face, +x on a +z face.
	var right := Vector3(0.0, 0.0, -1.0) if nrm.x > 0.5 else Vector3(1.0, 0.0, 0.0)
	for t in range(0, idx.size() - 2, 3):
		var q: Array = []
		for k in 3:
			var v := verts[idx[t + k]]
			q.append(at + right * v.x + Vector3(0.0, v.y, 0.0))
		g.tri(q[0], q[1], q[2], nrm, K_PAINT, tint)


## Where the poles' lights hang (park-local), for the OmniLight3Ds.
static func lamp_spots() -> Array:
	var out: Array = []
	for pole: Array in POLES:
		var at: Vector2 = pole[0]
		var to_mid := (Vector2.ZERO - at).normalized()
		out.append(_v(at + to_mid * (POLE_ARM + 0.35), float(pole[1]) + POLE_H - 0.3))
	return out


## Galvanised pipe railings along the high deck's drops (not over the stair, the bank or the drop
## wall: those are ridden), stopping short of the planters.
static func _railings(g: Geo, palms: PackedVector2Array) -> void:
	var inset := 0.22
	var runs: Array = [
		[Vector2(-HALF_W + inset, -HALF_L + inset), Vector2(HALF_W - inset, -HALF_L + inset)],
		[Vector2(-HALF_W + inset, -HALF_L + inset), Vector2(-HALF_W + inset, -0.4)],
		[Vector2(HALF_W - inset, -HALF_L + inset), Vector2(HALF_W - inset, -0.4)],
	]
	for r: Array in runs:
		var a: Vector2 = r[0]
		var b: Vector2 = r[1]
		# Split round the planters.
		var cuts: Array = [[0.0, 1.0]]
		for p in palms:
			if p.y > 0.0:
				continue
			var t := clampf((p - a).dot(b - a) / (b - a).length_squared(), 0.0, 1.0)
			if (a + (b - a) * t).distance_to(p) < 1.6:
				var dt := 1.7 / (b - a).length()
				var nxt: Array = []
				for c: Array in cuts:
					if t - dt > c[0]:
						nxt.append([c[0], minf(t - dt, c[1])])
					if t + dt < c[1]:
						nxt.append([maxf(t + dt, c[0]), c[1]])
				cuts = nxt
		for c: Array in cuts:
			_rail_run(g, _v(a.lerp(b, c[0]), H_HI + CAP_H), _v(a.lerp(b, c[1]), H_HI + CAP_H))


## One railing from `a` to `b` (both on the surface): posts every RAIL_PITCH, top and mid rails.
static func _rail_run(g: Geo, a: Vector3, b: Vector3) -> void:
	var len := a.distance_to(b)
	if len < 0.5:
		return
	var n := maxi(1, int(ceil(len / RAIL_PITCH)))
	for k in n + 1:
		var p := a.lerp(b, float(k) / float(n))
		g.tube(p, p + Vector3(0.0, RAIL_TOP, 0.0), PIPE_R * 1.3, 6, K_STEEL, GALV)
	g.tube(a + Vector3(0.0, RAIL_TOP, 0.0), b + Vector3(0.0, RAIL_TOP, 0.0), PIPE_R * 1.4, 8, K_STEEL, GALV)
	g.tube(a + Vector3(0.0, RAIL_MID, 0.0), b + Vector3(0.0, RAIL_MID, 0.0), PIPE_R, 6, K_STEEL, GALV)


## The handrail down the middle of the stairs, on a post at each end.
static func _stair_rail(g: Geo) -> void:
	var x := (STAIR_X0 + STAIR_X1) * 0.5
	var a := Vector3(x, H_HI + RAIL_H, -0.3)
	var b := Vector3(x, H_LO + RAIL_H, STEP_RUN + 0.3)
	var top := Vector3(x, H_HI + RAIL_H, -0.9)
	var bot := Vector3(x, H_LO + RAIL_H, STEP_RUN + 0.9)
	g.tube(top, a, RAIL_R * 1.5, 10, K_STEEL, GALV)
	g.tube(a, b, RAIL_R * 1.5, 10, K_STEEL, GALV)
	g.tube(b, bot, RAIL_R * 1.5, 10, K_STEEL, GALV)
	g.tube(Vector3(x, H_HI, -0.7), Vector3(x, H_HI + RAIL_H, -0.7), RAIL_R * 1.6, 8, K_STEEL, GALV)
	g.tube(Vector3(x, H_LO, STEP_RUN + 0.7), Vector3(x, H_LO + RAIL_H, STEP_RUN + 0.7), RAIL_R * 1.6, 8, K_STEEL, GALV)


# --- Helpers ---------------------------------------------------------------------------------------

static func _v(p: Vector2, y: float) -> Vector3:
	return Vector3(p.x, y, p.y)


static func _area(poly: PackedVector2Array) -> float:
	var a := 0.0
	for i in poly.size():
		var p := poly[i]
		var q := poly[(i + 1) % poly.size()]
		a += p.x * q.y - q.x * p.y
	return a * 0.5


## `poly` resampled to `n` points evenly spaced along its length.
static func _even(poly: PackedVector2Array, n: int) -> PackedVector2Array:
	var cum := PackedFloat32Array([0.0])
	for i in poly.size():
		cum.append(cum[i] + poly[i].distance_to(poly[(i + 1) % poly.size()]))
	var total := cum[cum.size() - 1]
	var out := PackedVector2Array()
	var j := 0
	for k in n:
		var s := total * float(k) / float(n)
		while j < poly.size() - 1 and cum[j + 1] < s:
			j += 1
		var seg := maxf(cum[j + 1] - cum[j], 0.0001)
		out.append(poly[j].lerp(poly[(j + 1) % poly.size()], (s - cum[j]) / seg))
	return out


## Unit normals pointing into the polygon at each vertex (mitred).
static func _inward(poly: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	var ccw := _area(poly) > 0.0
	var n := poly.size()
	for i in n:
		var a := poly[(i - 1 + n) % n]
		var b := poly[i]
		var c := poly[(i + 1) % n]
		var e0 := (b - a).normalized()
		var e1 := (c - b).normalized()
		var n0 := Vector2(-e0.y, e0.x)
		var n1 := Vector2(-e1.y, e1.x)
		if not ccw:
			n0 = -n0
			n1 = -n1
		var m := (n0 + n1).normalized()
		var cosh := maxf(m.dot(n0), 0.5)
		out.append(m / cosh)
	return out


static func _dist_to_poly(p: Vector2, poly: PackedVector2Array) -> float:
	var best := INF
	for i in poly.size():
		var q := Geometry2D.get_closest_point_to_segment(p, poly[i], poly[(i + 1) % poly.size()])
		best = minf(best, p.distance_to(q))
	return best


static func _nearest_index(p: Vector2, poly: PackedVector2Array) -> int:
	var best := INF
	var bi := 0
	for i in poly.size():
		var d := p.distance_squared_to(poly[i])
		if d < best:
			best = d
			bi = i
	return bi


## The mesh being written: packed arrays, the kind in COLOR.a, UV metres along the face, UV2 the
## park-local XZ for the noise (the shader reads its own model-space position for that too).
class Geo:
	var detailed: bool = true
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()

	func _init(d: bool) -> void:
		detailed = d

	func _add(p: Vector3, n: Vector3, kind: int, tint: Color, uv: Vector2) -> void:
		verts.append(p)
		normals.append(n)
		colors.append(Color(tint.r, tint.g, tint.b, float(kind) / 16.0 + 0.5 / 16.0))
		uvs.append(uv)

	## A triangle facing `n` (Godot's front faces wind clockwise seen from the front: the winding is
	## fixed here, so no caller has to get it right). `both` adds the back face too.
	func tri(a: Vector3, b: Vector3, c: Vector3, n: Vector3, kind: int, tint: Color = Color(1, 1, 1), both: bool = false) -> void:
		if (b - a).cross(c - a).dot(n) > 0.0:
			var t := b
			b = c
			c = t
		var uv_of := func(p: Vector3) -> Vector2:
			if absf(n.y) > 0.7:
				return Vector2(p.x, p.z)
			return Vector2(p.x * absf(n.z) + p.z * absf(n.x), p.y)
		_add(a, n, kind, tint, uv_of.call(a))
		_add(b, n, kind, tint, uv_of.call(b))
		_add(c, n, kind, tint, uv_of.call(c))
		if both:
			tri(a, b, c, -n, kind, tint, false)

	func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, kind: int, tint: Color = Color(1, 1, 1)) -> void:
		tri(a, b, c, n, kind, tint)
		tri(a, c, d, n, kind, tint)

	## A vertical wall face a-b-c-d (a, b at the foot) with UV (metres along from `u0`, height).
	func box_face(a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, kind: int, u0: float) -> void:
		var len := Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))
		quad_n([a, b, c, d], [n, n, n, n], kind, [Vector2(u0, a.y), Vector2(u0 + len, b.y), Vector2(u0 + len, c.y), Vector2(u0, d.y)])

	## A quad with its own normals and UVs per corner (a smooth surface).
	func quad_n(v: Array, nn: Array, kind: int, uv: Array = [], tint: Color = Color(1, 1, 1)) -> void:
		var face: Vector3 = (nn[0] + nn[1] + nn[2] + nn[3]).normalized()
		var order := [0, 1, 2, 0, 2, 3]
		if ((v[1] as Vector3) - (v[0] as Vector3)).cross((v[2] as Vector3) - (v[0] as Vector3)).dot(face) > 0.0:
			order = [0, 2, 1, 0, 3, 2]
		for i: int in order:
			var u: Vector2 = uv[i] if uv.size() == 4 else Vector2((v[i] as Vector3).x, (v[i] as Vector3).z)
			_add(v[i], nn[i], kind, tint, u)

	## A round tube from `a` to `b`.
	func tube(a: Vector3, b: Vector3, r: float, sides: int, kind: int, tint: Color) -> void:
		var ax := (b - a).normalized()
		var ref := Vector3.UP if absf(ax.y) < 0.9 else Vector3.RIGHT
		var s := ax.cross(ref).normalized()
		var t := ax.cross(s).normalized()
		var len := a.distance_to(b)
		for k in sides:
			var a0 := TAU * float(k) / float(sides)
			var a1 := TAU * float(k + 1) / float(sides)
			var d0 := s * cos(a0) + t * sin(a0)
			var d1 := s * cos(a1) + t * sin(a1)
			quad_n([a + d0 * r, b + d0 * r, b + d1 * r, a + d1 * r], [d0, d0, d1, d1], kind,
				[Vector2(0.0, a0 * r), Vector2(len, a0 * r), Vector2(len, a1 * r), Vector2(0.0, a1 * r)], tint)

	func commit(mat: Material) -> ArrayMesh:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_COLOR] = colors
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		var mesh := ArrayMesh.new()
		if verts.is_empty():
			return mesh
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		# Tangents from the UVs, or the shader's normal map does nothing.
		var st := SurfaceTool.new()
		st.create_from(mesh, 0)
		st.generate_tangents()
		var out := st.commit()
		out.surface_set_material(0, mat)
		return out

	func faces() -> PackedVector3Array:
		return verts
