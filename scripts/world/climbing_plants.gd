class_name ClimbingPlants
extends RefCounted
## Southern California planting that grows ON things: bougainvillea (magenta, orange, white)
## spilling over garden walls, house walls, sound walls and car-park walls and hanging down; ivy
## and creeping fig climbing walls and freeway sound walls; star jasmine through chain-link,
## pickets and board fences; wisteria and grape over back-yard pergolas; trumpet vine up the
## wooden utility poles - and the accent plants in the front-garden beds (agave, aloe, red-hot
## poker, lavender, lantana).
##
## How it is drawn: leaf cards and bract clusters built here in code, each cut from ONE painted
## atlas (tools/make_climbers.py -> assets/textures/climbers/) and worn on ONE shader
## (shaders/climbers.gdshader: wind sway weighted per vertex, alpha cut-out held up through the
## mips, translucency, wet leaves, the colour-space include). A FULL chunk's climbers are ONE mesh
## (`Climbers`, drawn to DRAW_DISTANCE) with a lighter shadows-only twin (`ClimbersShadow`, every
## SHADOW_STRIDE-th card, to SHADOW_DISTANCE), and its accent plants another (`ClimberAccents`,
## to ACCENT_DISTANCE): three draws a chunk where a batch per species would be eight. Cards hug
## what they grow on: sampled over the face on a jittered grid inside the plant's own outline
## (ragged by noise, thinning toward its edge), a few centimetres off the wall for creeping fig, a
## mounded mat for ivy, a mass that billows out at the top and spills over a wall's coping and
## down its far side, with strands hanging under gravity for bougainvillea. LOD chunks and the far
## city get nothing (the wall's own paint carries it there).
##
## Where: the walls the chunk itself built - YardFill's upright boxes (ch._yard_walls: garden
## walls, fences, pickets, chain-link, sound walls, yard walls), every house face HouseBuild walls
## (house_face(), with its openings, so a vine frames a window instead of covering it), LotFill's
## car-park walls and chain-link (note_run()), low-rise Building walls (only where StreetWear's
## _paintable() says the shader draws plain wall), the utility poles StreetDetail planted, and the
## back-yard decks and tiled patios (a pergola is built over some, its timber in YardFill's walls
## mesh); the accent plants in YardFill's mulch and decomposed-granite beds.
## How much: a share per CityPlan.District (DISTRICT_SHARE: the beach town and the suburbs lush,
## downtown rare), and per surface kind (the *_ODDS tables).
##
## Seeding: every roll is a generator hashed from the seed and the wall / face / pole / bed - never
## the block's or a Building's rng - so nothing the seed already builds moves.
##
## Static: CityChunk runs build() as a build step of a FULL chunk; it moves itself to just before
## the finish (the yards' walls are laid by deferred steps), then runs inside a time budget.

# --- Tunables ----------------------------------------------------------------------------------

## Off: nothing is built (the A/B). CLIMBERS=0 in the environment.
static var enabled: bool = OS.get_environment("CLIMBERS") != "0"
## Keeps every card centre a house face got with that face's holes, for the checks.
static var debug: bool = false

## How lush each district is, a multiplier on every odds below
## (DOWNTOWN, MIDTOWN, SUBURBS, INDUSTRIAL, CAMPUS, BEACHTOWN).
const DISTRICT_SHARE := [0.08, 0.4, 0.85, 0.2, 0.45, 1.0]
## Chance per ~SPECIMEN_STEP metres of a yard wall that a plant grows there, by YardFill wall kind
## (W_STUCCO .. W_POST), and which species: [bougainvillea, ivy, creeping fig, star jasmine].
const SPECIMEN_STEP := 8.0
const WALL_ODDS := [0.3, 0.2, 0.22, 0.45, 0.0, 0.22, 0.22, 0.22, 0.0, 0.0]
const WALL_SPECIES := [
	[0.62, 0.08, 0.3, 0.0],   # stucco garden wall / fence
	[0.3, 0.3, 0.0, 0.4],     # timber fence
	[0.15, 0.0, 0.0, 0.85],   # pickets
	[0.22, 0.48, 0.3, 0.0],   # freeway sound wall
	[0.0, 0.0, 0.0, 0.0],     # hedge
	[0.15, 0.4, 0.45, 0.0],   # concrete
	[0.2, 0.45, 0.35, 0.0],   # brick
	[0.15, 0.25, 0.0, 0.6],   # chain-link
	[0.0, 0.0, 0.0, 0.0],
	[0.0, 0.0, 0.0, 0.0],
]
## A wall this close to the block's edge (m) is a front wall: planted on its street side, its
## odds times FRONT_GAIN.
const FRONT_REACH := 9.0
const FRONT_GAIN := 1.8
## A house face's chance of a climber (stucco walls take bougainvillea or fig, clad ones ivy).
const HOUSE_ODDS := 0.32
## A low-rise Building face's chance of a creeping fig / ivy patch (most Buildings in the yard
## districts are gone to houses; this is midtown and the boulevards).
const BUILDING_ODDS := 0.22
const BUILDING_MAX_TOP := 14.0
## A utility pole's chance of trumpet vine.
const POLE_ODDS := 0.16
## A back-yard deck or patio's chance of a pergola (wisteria or grape on it).
const PERGOLA_ODDS := 0.4
const PERGOLA_MIN := Vector2(3.2, 3.0)
const PERGOLA_HEIGHT := 2.55
## Accent plants per square metre of mulch bed and of decomposed granite.
const ACCENTS_PER_M2_MULCH := 0.22
const ACCENTS_PER_M2_DG := 0.16

## Draw distances (m) and the shadow twin's.
const DRAW_DISTANCE := 140.0
const ACCENT_DISTANCE := 95.0
const SHADOW_DISTANCE := 70.0
const SHADOW_STRIDE := 3
## Plants are drawn in square tiles this big (m), each a node with its own range (_tile()).
const TILE := 64.0
## Per-chunk caps (cards; accent triangles).
const MAX_CARDS := 7000
const MAX_ACCENT_TRIS := 30000
## Time a build step may spend (us) before it hands back to the streamer.
const STEP_BUDGET_US := 2500

# --- Atlas (tools/make_climbers.py) -----------------------------------------------------------

const ATLAS_COLS := 8
const ATLAS_ROWS := 6
const CELL_PX := 256.0
const CELL_INSET := 6.0 / 256.0
const C_IVY := [0, 1, 2, 3]
const C_IVY_MAT := [4, 5]
const C_FIG := [6, 7]
const C_BOUG_LEAF := [8, 9]
const C_BRACT := [[10, 11], [12, 13], [14, 15]]  # magenta, orange, white
const C_JASMINE := [16, 17]
const C_JASMINE_FLOWER := [18, 19]
const C_WIST_LEAF := [20, 21]
const C_WIST_FLOWER := [22, 23]
const C_GRAPE_LEAF := [24, 25]
const C_GRAPE := 26
const C_TRUMPET_LEAF := [27, 28]
const C_TRUMPET_FLOWER := [29, 30]
const C_WOOD := 31
const C_AGAVE := [32, 33]
const C_ALOE := 34
const C_POKER := 35
const C_LAVENDER := 36
const C_LANTANA := [37, 38]
const C_STRAPS := 39
## Dense masses (the inside of a plant): bougainvillea leaf, bougainvillea in bloom (magenta,
## orange, white), jasmine in flower, wisteria, grape, trumpet vine.
const C_BOUG_MASS := 40
const C_BOUG_BLOOM := [41, 42, 43]
const C_JASMINE_MASS := 44
const C_WIST_MASS := 45
const C_GRAPE_MASS := 46
const C_TRUMPET_MASS := 47
## Share of bougainvillea colours: magenta, orange, white.
const BRACT_COLORS := [0.62, 0.84, 1.0]

enum Sp { BOUGAINVILLEA, IVY, FIG, JASMINE, WISTERIA, GRAPE, TRUMPET, AGAVE, ALOE, POKER, LAVENDER, LANTANA }
const SP_NAMES := ["bougainvillea", "ivy", "fig", "jasmine", "wisteria", "grape", "trumpet", "agave", "aloe", "poker", "lavender", "lantana"]


# --- Hooks --------------------------------------------------------------------------------------

## HouseBuild._wing(): one wall face of a house, `foot` the world point at the face's start at the
## house's floor level, `t` / `n` world tangent and outward normal, `length` and `top` (metres up
## from the floor), `holes` the openings ([a0, a1, y0, y1, kind] in the face's own coordinates),
## `mat` the wall material ("h_wall" stucco, "h_siding", ...).
static func house_face(ch: CityChunk, h: Dictionary, foot: Vector3, t: Vector3, n: Vector3, length: float, top: float, holes: Array, hidden: Array[Vector2], mat: String, which: String = "") -> void:
	if not enabled or ch.capturing or ch.level != CityChunk.Level.FULL:
		return
	# The spans another wing stands against are holes the whole height (no leaves inside it).
	var all := holes.duplicate()
	for sp in hidden:
		all.append([sp.x, sp.y, -10.0, 100.0])
	_list(ch, "climb_house").append([foot, t, n, length, top, all, mat, int(h.seed), bool(h.get("beach", false)), which])


## LotFill._edge_run(): a car park's low wall or chain-link run, centre `c`, `length` along x or z.
static func note_run(ch: CityChunk, c: Vector2, length: float, along_x: bool, base: float, height: float, kind: String) -> void:
	if not enabled or ch.capturing or ch.level != CityChunk.Level.FULL:
		return
	_list(ch, "climb_runs").append([c, length, along_x, base, height, kind])


static func _list(ch: CityChunk, key: String) -> Array:
	if not ch.has_meta(key):
		ch.set_meta(key, [])
	return ch.get_meta(key)


# --- The build step ----------------------------------------------------------------------------

## The step: first moves itself to just before the finish, then gathers the jobs and runs them in
## STEP_BUDGET_US slices (false = run me again), then commits the meshes.
static func build(ch: CityChunk) -> bool:
	if not enabled or ch.level != CityChunk.Level.FULL or ch.capturing:
		return true
	# Deferred steps (the yards' walls and planting) were inserted just before the finish, so
	# after this step: go behind them.
	if ch._step < ch._steps.size() - 2:
		ch._steps.insert(ch._steps.size() - 1, build.bind(ch))
		return true
	var st: Dictionary = ch.get_meta("climb_state", {})
	if st.is_empty():
		st = _begin(ch)
		ch.set_meta("climb_state", st)
	var t0 := Time.get_ticks_usec()
	var jobs: Array = st.jobs
	st.usec = int(st.get("usec", 0))
	while int(st.next) < jobs.size():
		(jobs[int(st.next)] as Callable).call()
		st.next = int(st.next) + 1
		if Time.get_ticks_usec() - t0 > STEP_BUDGET_US:
			st.usec = int(st.usec) + Time.get_ticks_usec() - t0
			return false
	var t1 := Time.get_ticks_usec()
	_commit(ch, st)
	st.usec = int(st.usec) + Time.get_ticks_usec() - t0
	(ch.get_meta("climbers") as Dictionary)["usec"] = st.usec
	(ch.get_meta("climbers") as Dictionary)["commit_usec"] = Time.get_ticks_usec() - t1
	ch.remove_meta("climb_state")
	for k in ["climb_house", "climb_runs"]:
		if ch.has_meta(k):
			ch.remove_meta(k)
	return true


static func _begin(ch: CityChunk) -> Dictionary:
	var plan: CityPlan = ch.plan
	var block := plan.block(ch.ix, ch.iz)
	var district := int(block.district)
	var share := float(DISTRICT_SHARE[district])
	var st := {"jobs": [], "next": 0, "leaf": {}, "shadow": {}, "accent": {}, "counts": {}, "share": share,
		"district": district, "ch": ch, "cards": 0, "accent_tris": 0, "spots": [], "debug_faces": [], "debug_centres": []}
	if share <= 0.0 or ch.zone == MacroMap.Zone.HILLS:
		return st
	var jobs: Array = st.jobs
	# The rarer, showier pieces first (poles, pergolas, houses), so a block crowded with yard walls
	# spends the card cap on them last.
	var data: Dictionary = ch._batch.data()
	if data.has("upole"):
		for xf: Transform3D in data["upole"].xforms:
			jobs.append(_pole.bind(st, xf))
	# Back-yard decks and patios (pergolas), and the beds (accent plants). Pergola timber goes
	# into YardFill's walls, which commit at the finish, after this step.
	for g: Array in ch._yard_ground:
		var kind := int(g[1])
		if kind == YardFill.G_DECK or kind == YardFill.G_TILE:
			jobs.append(_pergola.bind(st, g))
		elif kind == YardFill.G_MULCH or kind == YardFill.G_DG:
			jobs.append(_bed.bind(st, g))
	for f: Array in (ch.get_meta("climb_house", []) as Array):
		jobs.append(_house.bind(st, f))
	for r: Array in (ch.get_meta("climb_runs", []) as Array):
		jobs.append(_lot_run.bind(st, r))
	for part: Dictionary in StreetWear._ground_parts(ch):
		jobs.append(_building.bind(st, part))
	# Yard walls: merged into straight runs first (they are laid in pieces of up to 6 m).
	for run: Dictionary in _yard_runs(ch._yard_walls):
		jobs.append(_yard_wall.bind(st, run))
	return st


static func _rng(parts: Array) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = hash(parts)
	return r


static func _count(st: Dictionary, sp: int, n: int) -> void:
	var c: Dictionary = st.counts
	c[SP_NAMES[sp]] = int(c.get(SP_NAMES[sp], 0)) + n


## Smooth 1D noise, -1..1, cheap: a few incommensurate sines.
static func _wobble(x: float, s: float) -> float:
	return 0.5 * sin(x * 1.7 + s) + 0.3 * sin(x * 3.9 + s * 2.3) + 0.2 * sin(x * 8.3 + s * 4.1)


# --- Geometry -------------------------------------------------------------------------------------

## One mesh in the making: flat arrays, appended per card.
class Acc:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var tg := PackedFloat32Array()
	var c := PackedColorArray()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var idx := PackedInt32Array()
	## Where the shader fades this mesh's cards out (m), carried in UV2.y.
	var fade := 140.0

	func vert(p: Vector3, nn: Vector3, tan: Vector3, col: Color, u: Vector2, flower: float, bsign: float = 1.0) -> int:
		v.append(p)
		n.append(nn)
		tg.append(tan.x)
		tg.append(tan.y)
		tg.append(tan.z)
		tg.append(bsign)
		c.append(col)
		uv.append(u)
		uv2.append(Vector2(flower, fade))
		return v.size() - 1

	## Two triangles a, b, c, d (in order round the quad), front toward `want`.
	func quad(ia: int, ib: int, ic: int, id: int, want: Vector3) -> void:
		var fn := (v[ic] - v[ia]).cross(v[ib] - v[ia])
		if fn.dot(want) >= 0.0:
			idx.append_array([ia, ib, ic, ia, ic, id])
		else:
			idx.append_array([ia, ic, ib, ia, id, ic])

	func tris() -> int:
		return idx.size() / 3

	func mesh(mat: Material) -> ArrayMesh:
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = v
		arr[Mesh.ARRAY_NORMAL] = n
		arr[Mesh.ARRAY_TANGENT] = tg
		arr[Mesh.ARRAY_COLOR] = c
		arr[Mesh.ARRAY_TEX_UV] = uv
		arr[Mesh.ARRAY_TEX_UV2] = uv2
		arr[Mesh.ARRAY_INDEX] = idx
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		m.surface_set_material(0, mat)
		return m


## The mesh in the making for the TILE metres square `p` falls in: a node's visibility range is
## measured to the centre of its bounds, so a chunk-wide mesh on a long block would vanish long
## before its near end was out of reach.
static func _tile(st: Dictionary, kind: String, p: Vector3) -> Acc:
	var tiles: Dictionary = st[kind]
	var k := Vector2i(floori(p.x / TILE), floori(p.z / TILE))
	if not tiles.has(k):
		var acc := Acc.new()
		acc.fade = {"leaf": DRAW_DISTANCE, "shadow": SHADOW_DISTANCE, "accent": ACCENT_DISTANCE}[kind]
		tiles[k] = acc
	return tiles[k]


static func _cell_uv(cell: int, u: float, v: float) -> Vector2:
	var col := cell % ATLAS_COLS
	var row := cell / ATLAS_COLS
	var uu := lerpf(CELL_INSET, 1.0 - CELL_INSET, u)
	var vv := lerpf(CELL_INSET, 1.0 - CELL_INSET, v)
	return Vector2((float(col) + uu) / float(ATLAS_COLS), (float(row) + vv) / float(ATLAS_ROWS))


## A leaf card: centred at `p`, `ax` across (unit), `ay` along it from the stalk end to the tip
## (unit), `w` x `h` metres, bent at its middle by `bend` (metres of the tip pushed along
## `mass_n`). Its normal leans toward `mass_n`, the plant mass's outward direction, so a mass
## lights as a volume. `free0` / `free1` the wind weight at the stalk end and the tip. The atlas
## cell is drawn with its bottom (v = 1) at the stalk end. Every SHADOW_STRIDE-th card also goes
## into the shadow twin.
static func _card(st: Dictionary, p: Vector3, ax: Vector3, ay: Vector3, mass_n: Vector3, w: float, h: float, cell: int,
		tint: Color, free0: float, free1: float, flower: float = 0.0, bend: float = 0.0) -> void:
	if int(st.cards) >= MAX_CARDS:
		return
	st.cards = int(st.cards) + 1
	if debug:
		(st.debug_centres as Array).append(p)
	_card_into(_tile(st, "leaf", p), p, ax, ay, mass_n, w, h, cell, tint, free0, free1, flower, bend)
	if int(st.cards) % SHADOW_STRIDE == 0:
		# The twin's cards stand in for SHADOW_STRIDE of them: a little bigger.
		_card_into(_tile(st, "shadow", p), p, ax, ay, mass_n, w * 1.35, h * 1.35, cell, tint, free0, free1, flower, bend)


static func _card_into(acc: Acc, p: Vector3, ax: Vector3, ay: Vector3, mass_n: Vector3, w: float, h: float, cell: int,
		tint: Color, free0: float, free1: float, flower: float, bend: float) -> void:
	var face_n := ax.cross(ay).normalized()
	if face_n.dot(mass_n) < 0.0:
		face_n = -face_n
	var nn := (face_n * 0.4 + mass_n * 0.6).normalized()
	# The binormal must run up the atlas cell (toward the tip) for the normal map.
	var bs := 1.0 if nn.cross(ax).dot(ay) > 0.0 else -1.0
	var hw := ax * (w * 0.5)
	var b := p - ay * (h * 0.5)
	var m := p
	var e := p + ay * (h * 0.5) + mass_n * bend
	var fm := lerpf(free0, free1, 0.5)
	var c0 := Color(tint.r, tint.g, tint.b, free0)
	var cm := Color(tint.r, tint.g, tint.b, fm)
	var c1 := Color(tint.r, tint.g, tint.b, free1)
	var i0 := acc.vert(b - hw, nn, ax, c0, _cell_uv(cell, 0.0, 1.0), flower, bs)
	var i1 := acc.vert(b + hw, nn, ax, c0, _cell_uv(cell, 1.0, 1.0), flower, bs)
	if absf(bend) > 0.005:
		var i2 := acc.vert(m + hw, nn, ax, cm, _cell_uv(cell, 1.0, 0.5), flower, bs)
		var i3 := acc.vert(m - hw, nn, ax, cm, _cell_uv(cell, 0.0, 0.5), flower, bs)
		var i4 := acc.vert(e + hw, nn, ax, c1, _cell_uv(cell, 1.0, 0.0), flower, bs)
		var i5 := acc.vert(e - hw, nn, ax, c1, _cell_uv(cell, 0.0, 0.0), flower, bs)
		acc.quad(i0, i1, i2, i3, face_n)
		acc.quad(i3, i2, i4, i5, face_n)
	else:
		var i2 := acc.vert(e + hw, nn, ax, c1, _cell_uv(cell, 1.0, 0.0), flower, bs)
		var i3 := acc.vert(e - hw, nn, ax, c1, _cell_uv(cell, 0.0, 0.0), flower, bs)
		acc.quad(i0, i1, i2, i3, face_n)


## A card lying in a wall's plane (normal n), turned by `ang` about the normal.
static func _flat_axes(t: Vector3, n: Vector3, ang: float) -> Array:
	var up := n.cross(t).normalized()
	if up.y < 0.0:
		up = -up
	var ay := (up * cos(ang) + t * sin(ang)).normalized()
	var ax := ay.cross(n).normalized()
	return [ax, ay]


static func _leaf_tint(rng: RandomNumberGenerator, sun: float = 1.0) -> Color:
	var k := rng.randf_range(0.82, 1.14) * sun
	return Color(k * rng.randf_range(0.94, 1.06), k, k * rng.randf_range(0.9, 1.04))


# --- Wall plants ------------------------------------------------------------------------------------

## A wall face to plant on: `o` the world point at u = 0 on the face at its foot, `t` along,
## `n` outward, `len`, `top` (metres over o), `thick` (0 for a face of a building: nothing to spill
## over), `holes` [a0, a1, y0, y1] to keep the leaves off.
static func _face(o: Vector3, t: Vector3, n: Vector3, length: float, top: float, thick: float, holes: Array = []) -> Dictionary:
	return {"o": o, "t": t, "n": n, "len": length, "top": top, "thick": thick, "holes": holes}


static func _in_hole(f: Dictionary, u: float, y: float, grow: float = 0.0) -> bool:
	for hl: Array in f.holes:
		if u > float(hl[0]) - grow and u < float(hl[1]) + grow and y > float(hl[2]) - grow and y < float(hl[3]) + grow:
			return true
	return false


static func _at(f: Dictionary, u: float, y: float, off: float) -> Vector3:
	return (f.o as Vector3) + (f.t as Vector3) * u + Vector3.UP * y + (f.n as Vector3) * off


## Creeping fig or ivy climbing a face from a root at `u0`: a fan that widens to `spread` metres
## and reaches `reach` up (clipped to the face's top), ragged at its edge.
static func _climber(st: Dictionary, f: Dictionary, u0: float, spread: float, reach: float, sp: int, rng: RandomNumberGenerator) -> void:
	var t: Vector3 = f.t
	var n: Vector3 = f.n
	var length: float = f.len
	var height: float = minf(reach, float(f.top) - 0.05)
	if height < 0.4:
		return
	var fig := sp == Sp.FIG
	var spacing := 0.27 if fig else 0.3
	var s := rng.randf() * 100.0
	var cards := 0
	var c0 := int(st.cards)
	var y := 0.05
	while y < height:
		var hy := y / height
		# Half width at this height: narrow at the root, full by a third up, ragged.
		var hw := spread * 0.5 * (0.25 + 0.75 * smoothstep(0.0, 0.35, hy)) * (1.0 + 0.25 * _wobble(y * 2.0, s))
		var u := u0 - hw
		while u < u0 + hw:
			var uu := u + rng.randf_range(-0.4, 0.4) * spacing
			var yy := y + rng.randf_range(-0.4, 0.4) * spacing
			var edge := absf(uu - u0) / maxf(hw, 0.05)
			# The top edge is ragged too: shoots run ahead of the mass.
			var top_edge := height * (0.82 + 0.18 * _wobble(uu * 3.0, s + 7.0))
			var keep := (1.0 - smoothstep(0.65, 1.0, edge)) * (1.0 - smoothstep(top_edge - 0.4, top_edge, yy))
			if uu > 0.02 and uu < length - 0.02 and yy < float(f.top) - 0.03 and rng.randf() < keep and not _in_hole(f, uu, yy, 0.04):
				var mound := (1.0 - edge * edge) * (0.02 if fig else 0.09)
				var off := (0.012 if fig else 0.03) + mound + rng.randf() * (0.008 if fig else 0.04)
				var p := _at(f, uu, yy, off)
				var mass_n := (n + Vector3.UP * 0.25).normalized()
				if fig or rng.randf() < 0.55:
					var axes := _flat_axes(t, n, rng.randf_range(-PI, PI))
					var cell: int = (C_FIG[rng.randi() % 2]) if fig else (C_IVY_MAT[rng.randi() % 2])
					var size := rng.randf_range(0.5, 0.66) if fig else rng.randf_range(0.55, 0.72)
					_card(st, p, axes[0], axes[1], mass_n, size, size, cell, _leaf_tint(rng), 0.0, 0.06 if fig else 0.15)
				else:
					# A sprig standing off the mat, pointing up and out.
					var lean := rng.randf_range(0.35, 0.9)
					var turn := rng.randf_range(-1.0, 1.0)
					var ay := (Vector3.UP * cos(lean) + n * sin(lean) + t * turn * 0.4).normalized()
					var ax := ay.cross(n).normalized()
					if ax.length_squared() < 0.01:
						ax = t
					var size := rng.randf_range(0.42, 0.6)
					_card(st, p + ay * size * 0.3, ax, ay, mass_n, size, size, C_IVY[rng.randi() % 4], _leaf_tint(rng), 0.05, 0.4, 0.0, 0.04)
				cards += 1
			u += spacing
		y += spacing
	_count(st, sp, int(st.cards) - c0)


## Bougainvillea grown up a face from `u0`: a woody trunk, then a shrub mass that domes out from
## the wall (deeper toward its top, where its weight bends the canes out), spilling over the
## coping and down the far side of a wall it tops (`thick` > 0), with canes hanging under gravity.
## Dense mass cards inside, sprigs round the silhouette, bracts mostly on the outer surface.
## `width` metres of wall it covers at its widest. On a tall house wall it is a shrub a few metres
## up the corner rather than a sheet to the roof.
static func _bougainvillea(st: Dictionary, f: Dictionary, u0: float, width: float, rng: RandomNumberGenerator, color: int) -> void:
	var t: Vector3 = f.t
	var n: Vector3 = f.n
	var length: float = f.len
	var top: float = f.top
	var thick: float = f.thick
	var bract_cells: Array = C_BRACT[color]
	var bloom_mass: int = C_BOUG_BLOOM[color]
	var s := rng.randf() * 100.0
	var cards := 0
	var c0 := int(st.cards)
	var bloom := rng.randf_range(0.5, 0.8)
	var reach := top if (top < 3.2 or rng.randf() < 0.25) else minf(top, rng.randf_range(2.4, 4.6))
	var spills := reach >= top - 0.05
	# The trunk: one or two old canes, mostly hidden by the mass.
	for k in rng.randi_range(1, 2):
		var ru := u0 + rng.randf_range(-0.2, 0.2)
		var h := reach * 0.45
		var steps := maxi(1, int(h / 0.6))
		for i in steps:
			var yy := (float(i) + 0.5) * h / float(steps)
			_card(st, _at(f, ru + _wobble(yy, s + k) * 0.12, yy, 0.06), t, Vector3.UP, n, 0.2, h / float(steps) * 1.15, C_WOOD, Color(1, 1, 1), 0.0, 0.03)
			cards += 1
	var spacing := 0.32
	var y := 0.2
	var y_end := reach + (0.42 if spills else 0.3)
	while y < y_end:
		var hy := clampf(y / maxf(reach, 0.3), 0.0, 1.2)
		var hw := width * 0.5 * (0.4 + 0.6 * smoothstep(0.0, 0.6, hy)) * (1.0 + 0.2 * _wobble(y * 2.5, s))
		if not spills:
			hw *= sqrt(maxf(0.0, 1.0 - smoothstep(0.7, 1.1, hy)))
		elif y > top:
			hw *= 1.0 - (y - top) / 0.5 * 0.4
		var u := u0 - hw
		while u < u0 + hw:
			var uu := u + rng.randf_range(-0.45, 0.45) * spacing
			var yy := y + rng.randf_range(-0.45, 0.45) * spacing
			var edge := absf(uu - u0) / maxf(hw, 0.05)
			var keep := 1.0 - smoothstep(0.7, 1.05, edge)
			if uu > -0.3 and uu < length + 0.3 and rng.randf() < keep and not _in_hole(f, uu, yy, 0.3):
				var over := spills and yy > top - 0.02
				# The dome: deepest in the middle and toward the top.
				var dome := (1.0 - edge * edge) * (0.25 + 0.75 * smoothstep(0.0, 1.0, hy))
				var bulge := 0.07 + 0.5 * dome * rng.randf_range(0.7, 1.1)
				var bloom_here := bloom * (0.5 + 0.5 * hy)
				for layer in 2:
					var outer := layer == 1
					if outer and rng.randf() < 0.35:
						continue
					var p: Vector3
					var mass_n: Vector3
					if over:
						var back := rng.randf_range(-0.1, thick + (0.4 if thick > 0.0 else 0.0))
						p = _at(f, uu, top + 0.05 + rng.randf() * 0.22 + (0.12 if outer else 0.0), bulge * 0.5 - back)
						mass_n = (Vector3.UP + n * 0.3).normalized()
					else:
						p = _at(f, uu, yy, (bulge if outer else bulge * 0.45) + 0.03)
						mass_n = (n + Vector3.UP * 0.3).normalized()
					var flower := rng.randf() < bloom_here * (1.0 if outer else 0.7)
					var size: float
					var cell: int
					var ax: Vector3
					var ay: Vector3
					if not outer or edge < 0.55:
						# Mass: a dense card facing out of the dome, tilted a little.
						cell = bloom_mass if flower else C_BOUG_MASS
						size = rng.randf_range(0.7, 0.95)
						var nn := (mass_n + t * (uu - u0) / maxf(hw, 0.3) * 0.5 + Vector3(rng.randf_range(-0.2, 0.2), rng.randf_range(-0.2, 0.2), rng.randf_range(-0.2, 0.2))).normalized()
						var axes := _flat_axes(t, nn if not over else Vector3.UP, rng.randf_range(-PI, PI)) if not over else [t, n]
						ax = axes[0]
						ay = axes[1]
						if over:
							ay = (n * rng.randf_range(0.3, 1.0) + t * rng.randf_range(-0.6, 0.6)).normalized()
							ax = ay.cross(Vector3.UP).normalized()
					else:
						# The silhouette: sprigs leaning out of it.
						cell = bract_cells[rng.randi() % 2] if flower else C_BOUG_LEAF[rng.randi() % 2]
						size = rng.randf_range(0.5, 0.7)
						var lean := rng.randf_range(0.2, 1.2)
						var side := signf(uu - u0)
						ay = (Vector3.UP * cos(lean) + n * sin(lean) * 0.7 + t * side * rng.randf_range(0.2, 0.8)).normalized()
						ax = ay.cross(mass_n).normalized()
					if ax.length_squared() < 0.01:
						ax = t
					var tint := Color(1, 1, 1) * rng.randf_range(0.9, 1.08) if flower else _leaf_tint(rng)
					_card(st, p, ax, ay, mass_n, size, size, cell, tint, 0.08, 0.35 if outer else 0.15, 1.0 if flower else 0.0, 0.06 if outer else 0.02)
					cards += 1
			u += spacing
		y += spacing
	# Canes hanging off the top (or arching out of a shrub), outward then down, free at the tip.
	var strands := int(width * rng.randf_range(0.9, 1.6))
	var from := top if spills else reach * 0.9
	for k in strands:
		var su := u0 + rng.randf_range(-0.5, 0.5) * width
		if su < -0.2 or su > length + 0.2:
			continue
		var slen := rng.randf_range(0.5, minf(1.8, from * 0.8))
		var segs := maxi(2, int(slen / 0.3))
		var out := rng.randf_range(0.3, 0.6)
		for i in segs:
			var q := (float(i) + 0.5) / float(segs)
			var yy := from + 0.15 - slen * q * q * 1.1 + 0.25 * q
			if _in_hole(f, su, yy, 0.05):
				continue
			var p := _at(f, su + rng.randf_range(-0.08, 0.08), yy, 0.12 + out * sin(q * PI * 0.5))
			var ay := (Vector3.UP * (1.0 - q) * 0.6 + n * 0.4 - Vector3.UP * q).normalized()
			var flower := rng.randf() < bloom * 0.85
			var cell: int = bract_cells[rng.randi() % 2] if flower else C_BOUG_LEAF[rng.randi() % 2]
			_card(st, p, t, ay, (n + Vector3.UP * 0.2).normalized(), 0.46, 0.48, cell,
				Color(1, 1, 1) if flower else _leaf_tint(rng), 0.3 + 0.6 * q, 0.5 + 0.5 * q, 1.0 if flower else 0.0)
			cards += 1
	_count(st, Sp.BOUGAINVILLEA, int(st.cards) - c0)


## Star jasmine through a fence (chain-link, pickets, boards): a dense mat in the fence's plane on
## both sides from the foot to a little over the top, `width` metres from `u0`, white flowers.
static func _jasmine(st: Dictionary, f: Dictionary, u0: float, width: float, rng: RandomNumberGenerator) -> void:
	var t: Vector3 = f.t
	var n: Vector3 = f.n
	var top: float = f.top
	var s := rng.randf() * 100.0
	var cards := 0
	var c0 := int(st.cards)
	var spacing := 0.28
	var bloom := rng.randf_range(0.3, 0.6)
	var y := 0.1
	while y < top + 0.3:
		var hw := width * 0.5 * (1.0 + 0.18 * _wobble(y * 3.0, s))
		var u := u0 - hw
		while u < u0 + hw:
			var uu := u + rng.randf_range(-0.45, 0.45) * spacing
			var yy := y + rng.randf_range(-0.4, 0.4) * spacing
			var edge := absf(uu - u0) / maxf(hw, 0.05)
			var keep := (1.0 - smoothstep(0.7, 1.0, edge)) * (1.0 - smoothstep(top + 0.05, top + 0.3, yy))
			if uu > 0.0 and uu < float(f.len) and rng.randf() < keep:
				for side: float in [1.0, -1.0]:
					if rng.randf() < 0.3:
						continue
					var nn := n * side
					# The face is the fence's +n surface; the far side is `thick` behind it.
					var off := rng.randf_range(0.02, 0.12)
					var p := _at(f, uu, yy, off) if side > 0.0 else _at(f, uu, yy, -off - float(f.thick))
					var axes := _flat_axes(t, nn, rng.randf_range(-PI, PI))
					var flower := rng.randf() < bloom * (0.5 + 0.5 * yy / maxf(top, 0.3))
					var is_mass := rng.randf() < 0.6
					var cell: int = C_JASMINE_MASS if is_mass else (C_JASMINE_FLOWER[rng.randi() % 2] if flower else C_JASMINE[rng.randi() % 2])
					var size := rng.randf_range(0.6, 0.8) if is_mass else rng.randf_range(0.46, 0.62)
					_card(st, p, axes[0], axes[1], (nn + Vector3.UP * 0.2).normalized(), size, size, cell, _leaf_tint(rng), 0.0, 0.25,
						0.6 if flower else 0.0, 0.03)
					cards += 1
			u += spacing
		y += spacing
	_count(st, Sp.JASMINE, int(st.cards) - c0)


## A plant (species picked from `weights`: bougainvillea, ivy, fig, jasmine) for face `f` at `u0`.
static func _plant_on(st: Dictionary, f: Dictionary, u0: float, weights: Array, rng: RandomNumberGenerator, max_width: float) -> void:
	var total := 0.0
	for w: float in weights:
		total += w
	if total <= 0.0:
		return
	var roll := rng.randf() * total
	var pick := 0
	for i in weights.size():
		roll -= float(weights[i])
		if roll <= 0.0:
			pick = i
			break
	match pick:
		0:
			var c := rng.randf()
			var color := 0 if c < BRACT_COLORS[0] else (1 if c < BRACT_COLORS[1] else 2)
			_bougainvillea(st, f, u0, minf(rng.randf_range(2.2, 4.8), max_width), rng, color)
		1:
			_climber(st, f, u0, minf(rng.randf_range(1.8, 4.5), max_width), rng.randf_range(1.5, 6.0), Sp.IVY, rng)
		2:
			_climber(st, f, u0, minf(rng.randf_range(1.5, 4.0), max_width), rng.randf_range(1.2, 5.0), Sp.FIG, rng)
		3:
			_jasmine(st, f, u0, minf(rng.randf_range(1.6, 3.6), max_width), rng)
	(st.spots as Array).append([SP_NAMES[[Sp.BOUGAINVILLEA, Sp.IVY, Sp.FIG, Sp.JASMINE][pick]], _at(f, u0, 0.0, 0.0), f.n])


# --- Sources ------------------------------------------------------------------------------------------

## YardFill's upright boxes merged into straight runs: same kind, same line, same thickness, end
## to end. Each run keeps its pieces (for the top height along it).
static func _yard_runs(walls: Array) -> Array:
	var groups := {}
	for w: Array in walls:
		var kind := int(w[2])
		if kind >= WALL_ODDS.size() or float(WALL_ODDS[kind]) <= 0.0:
			continue
		var s: Vector3 = w[0]
		var c: Vector3 = w[1]
		var h := float(w[4])
		var along_x := s.x >= s.z
		var length := s.x if along_x else s.z
		var thick := s.z if along_x else s.x
		if length < 0.9 or h < 0.6 or thick > 1.2:
			continue
		var line := c.z if along_x else c.x
		var gk := "%d:%d:%d:%d" % [kind, 1 if along_x else 0, roundi(line * 20.0), roundi(thick * 100.0)]
		if not groups.has(gk):
			groups[gk] = []
		(groups[gk] as Array).append({"a": (c.x if along_x else c.z) - length * 0.5, "b": (c.x if along_x else c.z) + length * 0.5,
			"top": c.y + s.y * 0.5, "h": h, "c": c, "s": s})
	var runs: Array = []
	for gk: String in groups:
		var pieces: Array = groups[gk]
		pieces.sort_custom(func(p: Dictionary, q: Dictionary) -> bool: return float(p.a) < float(q.a))
		var parts := gk.split(":")
		var kind := int(parts[0])
		var along_x := parts[1] == "1"
		var cur: Dictionary = {}
		for p: Dictionary in pieces:
			if not cur.is_empty() and float(p.a) <= float(cur.b) + 0.15:
				cur.b = maxf(float(cur.b), float(p.b))
				(cur.pieces as Array).append(p)
			else:
				if not cur.is_empty():
					runs.append(cur)
				cur = {"kind": kind, "along_x": along_x, "a": p.a, "b": p.b, "pieces": [p], "s": p.s, "c": p.c}
		if not cur.is_empty():
			runs.append(cur)
	return runs


static func _yard_wall(st: Dictionary, run: Dictionary) -> void:
	var ch: CityChunk = st.ch
	var kind := int(run.kind)
	var along_x: bool = run.along_x
	var a: float = run.a
	var b: float = run.b
	var length := b - a
	var p0: Dictionary = (run.pieces as Array)[0]
	var s: Vector3 = p0.s
	var c: Vector3 = p0.c
	var thick := s.z if along_x else s.x
	var line := c.z if along_x else c.x
	var h := float(p0.h)
	var top_y := float(p0.top)
	var rng := _rng([ch.plan.seed, "climb_wall", kind, roundi(line * 10.0), roundi(a * 10.0)])
	var odds := float(WALL_ODDS[kind]) * float(st.share)
	# A wall near the block's edge is a front wall: it is planted on its street side, and more
	# often (the front garden is the one people plant for show).
	var rect: Rect2 = ch.plan.block(ch.ix, ch.iz).rect
	var lo := rect.position.y if along_x else rect.position.x
	var hi := rect.end.y if along_x else rect.end.x
	var street_side := 0.0
	if line - lo < FRONT_REACH:
		street_side = -1.0
	elif hi - line < FRONT_REACH:
		street_side = 1.0
	if street_side != 0.0:
		odds = minf(odds * FRONT_GAIN, 0.9)
	var n_spots := maxi(1, int(round(length / SPECIMEN_STEP)))
	for k in n_spots:
		if rng.randf() >= odds:
			continue
		var u0 := (float(k) + rng.randf_range(0.25, 0.75)) * length / float(n_spots)
		var side := 1.0 if rng.randf() < 0.5 else -1.0
		if street_side != 0.0 and rng.randf() < 0.85:
			side = street_side
		var t := Vector3(1, 0, 0) if along_x else Vector3(0, 0, 1)
		var n := (Vector3(0, 0, 1) if along_x else Vector3(1, 0, 0)) * side
		# The face: foot at the visible base (top - h), along t from a.
		var at := a + u0
		var pc := Vector3(at, 0.0, line) if along_x else Vector3(line, 0.0, at)
		var piece_top := top_y
		for p: Dictionary in run.pieces:
			if at >= float(p.a) - 0.01 and at <= float(p.b) + 0.01:
				piece_top = float(p.top)
				break
		var foot := pc - t * u0 + n * (thick * 0.5)
		foot.y = piece_top - h
		var f := _face(foot, t, n, length, h, thick)
		var weights: Array = WALL_SPECIES[kind]
		_plant_on(st, f, u0, weights, rng, length + 0.6)


static func _house(st: Dictionary, fa: Array) -> void:
	var ch: CityChunk = st.ch
	var foot: Vector3 = fa[0]
	var t: Vector3 = fa[1]
	var n: Vector3 = fa[2]
	var length: float = fa[3]
	var top: float = fa[4]
	var holes: Array = fa[5]
	var mat: String = fa[6]
	if length < 2.5 or top < 2.0:
		return
	var rng := _rng([ch.plan.seed, "climb_house", int(fa[7]), roundi(foot.x * 10.0), roundi(foot.z * 10.0)])
	# The front of the house is the one planted for show; the back yard's walls less.
	var gain: float = {"front": 1.7, "back": 0.6}.get(String(fa[9]), 1.0)
	if rng.randf() >= minf(HOUSE_ODDS * gain * float(st.share), 0.85):
		return
	var hl: Array = []
	for o: Array in holes:
		hl.append([float(o[0]), float(o[1]), float(o[2]), float(o[3]) if o.size() > 3 else float(o[2]) + 1.0])
	var f := _face(foot, t, n, length, top, 0.0, hl)
	# At a corner or between two openings: the widest stretch of plain wall.
	var u0 := _free_spot(hl, length, rng)
	var weights := [0.6, 0.05, 0.35, 0.0] if mat == "h_wall" else [0.25, 0.6, 0.15, 0.0]
	_plant_on(st, f, u0, weights, rng, minf(length, 4.0))
	if debug:
		(st.debug_faces as Array).append(f)


## The middle of the widest stretch of a face between its openings (or a corner if it is wide).
static func _free_spot(holes: Array, length: float, rng: RandomNumberGenerator) -> float:
	var edges: Array[Vector2] = []
	for hl: Array in holes:
		edges.append(Vector2(float(hl[0]), float(hl[1])))
	edges.sort_custom(func(p: Vector2, q: Vector2) -> bool: return p.x < q.x)
	var best := Vector2(0.0, length)
	var best_w := -1.0
	var cur := 0.0
	for e in edges:
		if e.x - cur > best_w:
			best_w = e.x - cur
			best = Vector2(cur, e.x)
		cur = maxf(cur, e.y)
	if length - cur > best_w:
		best = Vector2(cur, length)
	if best.y - best.x > 3.0:
		# A wide stretch: grow up near one of its ends (a corner, or beside a window).
		return best.x + 0.9 if rng.randf() < 0.5 else best.y - 0.9
	return (best.x + best.y) * 0.5


static func _lot_run(st: Dictionary, r: Array) -> void:
	var ch: CityChunk = st.ch
	var c: Vector2 = r[0]
	var length: float = r[1]
	var along_x: bool = r[2]
	var base: float = r[3]
	var height: float = r[4]
	var kind: String = r[5]
	if kind == "hedge":
		return
	var rng := _rng([ch.plan.seed, "climb_lot", roundi(c.x * 10.0), roundi(c.y * 10.0)])
	var odds := (0.35 if kind == "wall" else 0.3) * maxf(float(st.share), 0.25)
	var t := Vector3(1, 0, 0) if along_x else Vector3(0, 0, 1)
	var n_spots := maxi(1, int(round(length / 8.0)))
	for k in n_spots:
		if rng.randf() >= odds:
			continue
		var side := 1.0 if rng.randf() < 0.5 else -1.0
		var n := (Vector3(0, 0, 1) if along_x else Vector3(1, 0, 0)) * side
		var thick := 0.3 if kind == "wall" else 0.0
		var start := Vector3(c.x, 0.0, c.y) - t * (length * 0.5) + n * (thick * 0.5)
		var u0 := (float(k) + rng.randf_range(0.25, 0.75)) * length / float(n_spots)
		var at := start + t * u0
		start.y = base + ch._gy(at.x, at.z)
		var f := _face(start, t, n, length, height, thick)
		var weights := [0.55, 0.2, 0.25, 0.0] if kind == "wall" else [0.2, 0.25, 0.0, 0.55]
		_plant_on(st, f, u0, weights, rng, length)


static func _building(st: Dictionary, part: Dictionary) -> void:
	var ch: CityChunk = st.ch
	if float(part.top) > BUILDING_MAX_TOP or bool(part.get("parking", false)):
		return
	var size: Vector3 = part.size
	var center: Vector3 = part.center
	for face in 4:
		var along_x := face >= 2
		var length := size.x if along_x else size.z
		if length < 4.0:
			continue
		var rng := _rng([ch.plan.seed, "climb_bld", roundi(center.x * 10.0), roundi(center.z * 10.0), face])
		if rng.randf() >= BUILDING_ODDS * float(st.share):
			continue
		var u0 := rng.randf_range(1.0, length - 1.0)
		# Plant only where the wall at the foot is plain (not a shop window or door).
		if not StreetWear._paintable(part, face, u0, float(part.base) + 0.4):
			continue
		var n := StreetWear._normal(face)
		var p0 := StreetWear._face_point(part, face, 0.0, float(part.base))
		var p1 := StreetWear._face_point(part, face, 1.0, float(part.base))
		var t := (p1 - p0).normalized()
		var height := float(part.top) - float(part.base)
		# Holes: the window cells the shader draws, sampled on a coarse grid, so the leaves keep off
		# the glass.
		var holes: Array = []
		var y := 0.4
		while y < height - 0.3:
			var u := maxf(0.0, u0 - 3.0)
			while u < minf(length, u0 + 3.0):
				if not StreetWear._paintable(part, face, u + 0.2, float(part.base) + y + 0.2):
					holes.append([u, u + 0.4, y, y + 0.4])
				u += 0.4
			y += 0.4
		var f := _face(p0 + n * 0.005, t, n, length, height, 0.0, holes)
		_climber(st, f, u0, rng.randf_range(1.6, 3.6), rng.randf_range(2.5, minf(9.0, height)), Sp.FIG if rng.randf() < 0.6 else Sp.IVY, rng)
		(st.spots as Array).append(["building", p0 + t * u0])


## Trumpet vine up a wooden utility pole: a cylinder of leaves up to 3-6 m, a mass with orange
## trumpets at the top of it.
static func _pole(st: Dictionary, xf: Transform3D) -> void:
	var ch: CityChunk = st.ch
	var foot := Vector3(xf.origin.x, xf.origin.y - StreetDetail.POLE_HEIGHT * 0.5, xf.origin.z)
	var rng := _rng([ch.plan.seed, "climb_pole", roundi(foot.x * 10.0), roundi(foot.z * 10.0)])
	if rng.randf() >= POLE_ODDS * float(st.share):
		return
	foot.y += ch._gy(foot.x, foot.z)
	var reach := rng.randf_range(3.0, 6.0)
	var cards := 0
	var c0 := int(st.cards)
	var y := 0.2
	while y < reach + 0.6:
		var top_mass := smoothstep(reach - 1.6, reach, y)
		var r := 0.18 + 0.05 * sin(y * 2.0) + top_mass * rng.randf_range(0.3, 0.7)
		var around := maxi(3, int(TAU * r / 0.24))
		for k in around:
			if rng.randf() < 0.3 * (1.0 - top_mass):
				continue
			var a := (float(k) + rng.randf()) / float(around) * TAU
			var dir := Vector3(sin(a), 0.0, cos(a))
			var p := foot + Vector3(0.0, y + rng.randf_range(-0.1, 0.1), 0.0) + dir * r
			var flower := top_mass > 0.3 and rng.randf() < 0.45
			var cell: int = C_TRUMPET_FLOWER[rng.randi() % 2] if flower else (C_TRUMPET_MASS if rng.randf() < 0.5 else C_TRUMPET_LEAF[rng.randi() % 2])
			var ay := (Vector3.UP * rng.randf_range(0.2, 1.0) + dir * rng.randf_range(0.2, 0.8) - Vector3.UP * top_mass * 0.6).normalized()
			var ax := ay.cross(dir).normalized()
			if ax.length_squared() < 0.01:
				ax = Vector3(cos(a), 0.0, -sin(a))
			_card(st, p, ax, ay, (dir + Vector3.UP * 0.2).normalized(), 0.55, 0.55, cell, _leaf_tint(rng), 0.1 + 0.4 * top_mass,
				0.3 + 0.6 * top_mass, 1.0 if flower else 0.0, 0.05)
			cards += 1
		y += 0.26
	_count(st, Sp.TRUMPET, int(st.cards) - c0)
	(st.spots as Array).append(["trumpet", foot])


## A pergola over a back-yard deck or patio: four posts, two beams, rafters, YardFill's timber; then
## wisteria (racemes hanging under the rafters) or grape (bunches) over it.
static func _pergola(st: Dictionary, g: Array) -> void:
	var ch: CityChunk = st.ch
	var r: Rect2 = g[0]
	if r.size.x < PERGOLA_MIN.x or r.size.y < PERGOLA_MIN.y:
		return
	var rng := _rng([ch.plan.seed, "climb_pergola", roundi(r.position.x * 10.0), roundi(r.position.y * 10.0)])
	if rng.randf() >= PERGOLA_ODDS * float(st.share):
		return
	var q := Rect2(r.position + Vector2(0.4, 0.4), Vector2(minf(r.size.x - 0.8, 5.5), minf(r.size.y - 0.8, 4.5)))
	var base := CityChunk.SIDEWALK_TOP + YardFill.LIFT
	var wood: Color = YardFill.TIMBERS[rng.randi() % YardFill.TIMBERS.size()]
	var H := PERGOLA_HEIGHT
	var along_x := q.size.x >= q.size.y
	for c: Vector2 in [q.position, Vector2(q.end.x, q.position.y), q.end, Vector2(q.position.x, q.end.y)]:
		YardFill._box_wall(ch, Vector3(0.15, H, 0.15), Vector3(c.x, base, c.y), YardFill.W_WOOD, wood)
	var g0 := ch._gy(q.get_center().x, q.get_center().y)
	# Beams along the long side, rafters across them every 0.45 m, overhanging.
	for side in 2:
		var y := base + H - 0.04
		if along_x:
			var z := q.position.y if side == 0 else q.end.y
			YardFill._box_wall(ch, Vector3(q.size.x + 0.6, 0.2, 0.08), Vector3(q.get_center().x, y - 0.16, z), YardFill.W_WOOD, wood, false)
		else:
			var x := q.position.x if side == 0 else q.end.x
			YardFill._box_wall(ch, Vector3(0.08, 0.2, q.size.y + 0.6), Vector3(x, y - 0.16, q.get_center().y), YardFill.W_WOOD, wood, false)
	var span := q.size.x if along_x else q.size.y
	var nr := maxi(3, int(span / 0.45))
	for i in nr + 1:
		var a := float(i) / float(nr)
		if along_x:
			YardFill._box_wall(ch, Vector3(0.05, 0.14, q.size.y + 0.5), Vector3(q.position.x + q.size.x * a, base + H + 0.04, q.get_center().y), YardFill.W_WOOD, wood, false)
		else:
			YardFill._box_wall(ch, Vector3(q.size.x + 0.5, 0.14, 0.05), Vector3(q.get_center().x, base + H + 0.04, q.position.y + q.size.y * a), YardFill.W_WOOD, wood, false)
	var top := base + H + 0.18 + g0
	var wisteria := rng.randf() < 0.6
	var cards := 0
	var c0 := int(st.cards)
	# The vine's trunk up one post.
	var cp := q.position if rng.randf() < 0.5 else q.end
	for i in 6:
		var y := base + g0 + (float(i) + 0.5) * H / 6.0
		_card(st, Vector3(cp.x + 0.12, y, cp.y + 0.12), Vector3(1, 0, -1).normalized(), Vector3.UP, Vector3(1, 0, 1).normalized(), 0.2,
			H / 6.0 * 1.2, C_WOOD, Color(0.9, 0.9, 0.9), 0.0, 0.0)
		cards += 1
	# The canopy: cards over the rafters, a little ragged at the edges, drooping off the sides.
	var step := 0.28
	var x := q.position.x - 0.3
	while x < q.end.x + 0.3:
		var z := q.position.y - 0.3
		while z < q.end.y + 0.3:
			var px := x + rng.randf_range(-0.4, 0.4) * step
			var pz := z + rng.randf_range(-0.4, 0.4) * step
			var inside := Vector2(px, pz)
			var dx := maxf(q.position.x - px, px - q.end.x)
			var dz := maxf(q.position.y - pz, pz - q.end.y)
			var out := maxf(dx, dz)
			if rng.randf() < 1.0 - smoothstep(-0.1, 0.35, out) * 0.9:
				var droop := maxf(out, 0.0) * 1.2
				var p := Vector3(inside.x, top + rng.randf_range(-0.02, 0.18) - droop, inside.y)
				var ang := rng.randf() * TAU
				var ay := (Vector3(sin(ang), 0.0, cos(ang)) + Vector3.UP * rng.randf_range(-0.2, 0.5)).normalized()
				var ax := ay.cross(Vector3.UP).normalized()
				var is_mass := rng.randf() < 0.65
				var cell: int = (C_WIST_MASS if wisteria else C_GRAPE_MASS) if is_mass else (C_WIST_LEAF[rng.randi() % 2] if wisteria else C_GRAPE_LEAF[rng.randi() % 2])
				if is_mass:
					var axes := _flat_axes(Vector3(1, 0, 0), (Vector3.UP + Vector3(rng.randf_range(-0.4, 0.4), 0.0, rng.randf_range(-0.4, 0.4))).normalized(), rng.randf() * TAU)
					ax = axes[0]
					ay = axes[1]
				_card(st, p, ax, ay, Vector3.UP, 0.75 if is_mass else 0.62, 0.75 if is_mass else 0.62, cell, _leaf_tint(rng), 0.15, 0.4, 0.0, 0.06)
				cards += 1
				# A lower layer hanging off the rafters: leaves seen from under the pergola.
				if out < 0.0 and rng.randf() < 0.45:
					var a3 := rng.randf() * TAU
					var ay3 := (Vector3(sin(a3), 0.0, cos(a3)) * 0.5 - Vector3.UP).normalized()
					var ax3 := Vector3(cos(a3), 0.0, -sin(a3))
					_card(st, p - Vector3.UP * 0.22, ax3, ay3, Vector3.DOWN, 0.5, 0.5, C_WIST_LEAF[rng.randi() % 2] if wisteria else C_GRAPE_LEAF[rng.randi() % 2],
						_leaf_tint(rng, 0.85), 0.3, 0.6)
					cards += 1
				# Hanging under it: racemes, or grape bunches.
				var hang := 0.35 if wisteria else 0.09
				if out < 0.1 and rng.randf() < hang:
					var len := rng.randf_range(0.35, 0.6) if wisteria else rng.randf_range(0.2, 0.28)
					var cell2: int = (C_WIST_FLOWER[rng.randi() % 2]) if wisteria else C_GRAPE
					var a2 := rng.randf() * PI
					var axh := Vector3(cos(a2), 0.0, sin(a2))
					var hp := Vector3(p.x, top - 0.08 - len * 0.5, p.z)
					var face_n := axh.cross(Vector3.UP).normalized()
					_card(st, hp, axh, Vector3.UP, face_n, len * (0.45 if wisteria else 0.8), len, cell2, Color(1, 1, 1) * rng.randf_range(0.9, 1.05), 0.6, 0.2, 1.0)
					cards += 1
			z += step
		x += step
	_count(st, Sp.WISTERIA if wisteria else Sp.GRAPE, int(st.cards) - c0)
	(st.spots as Array).append(["pergola", Vector3(q.get_center().x, top, q.get_center().y)])


# --- Accent plants -----------------------------------------------------------------------------------

## A mulch bed or a decomposed-granite garden: agave and aloe in the gravel, lavender, lantana and
## red-hot poker in the beds, spaced along the rect.
static func _bed(st: Dictionary, g: Array) -> void:
	var ch: CityChunk = st.ch
	var r: Rect2 = g[0]
	var kind := int(g[1])
	var lift := float(g[3])
	if minf(r.size.x, r.size.y) < 0.6:
		return
	var rng := _rng([ch.plan.seed, "climb_bed", roundi(r.position.x * 10.0), roundi(r.position.y * 10.0)])
	var dens := (ACCENTS_PER_M2_MULCH if kind == YardFill.G_MULCH else ACCENTS_PER_M2_DG) * float(st.share)
	var n := int(r.get_area() * dens + rng.randf())
	n = mini(n, 14)
	var placed: Array[Vector2] = []
	for i in n:
		if int(st.accent_tris) >= MAX_ACCENT_TRIS:
			return
		var p := Vector2(rng.randf_range(r.position.x + 0.3, r.end.x - 0.3), rng.randf_range(r.position.y + 0.3, r.end.y - 0.3))
		var clash := false
		for q in placed:
			if q.distance_to(p) < 0.9:
				clash = true
				break
		if clash:
			continue
		placed.append(p)
		var foot := Vector3(p.x, CityChunk.SIDEWALK_TOP + lift + ch._gy(p.x, p.y), p.y)
		var roll := rng.randf()
		var acc := _tile(st, "accent", foot)
		var before := acc.tris()
		var sp: int
		if kind == YardFill.G_DG:
			sp = Sp.AGAVE if roll < 0.45 else (Sp.ALOE if roll < 0.75 else (Sp.LAVENDER if roll < 0.88 else Sp.LANTANA))
		else:
			sp = Sp.LAVENDER if roll < 0.3 else (Sp.LANTANA if roll < 0.6 else (Sp.POKER if roll < 0.8 else (Sp.AGAVE if roll < 0.92 else Sp.ALOE)))
		match sp:
			Sp.AGAVE:
				_rosette(acc, foot, rng, rng.randi_range(16, 24), rng.randf_range(0.45, 0.85), 0.15, C_AGAVE[0 if rng.randf() < 0.75 else 1], 0.35, 1.3)
			Sp.ALOE:
				_rosette(acc, foot, rng, rng.randi_range(12, 18), rng.randf_range(0.3, 0.5), 0.09, C_ALOE, 0.75, 1.45)
			Sp.POKER:
				_clump(acc, foot, rng, C_STRAPS, 0.75, 0.6, 3)
				for k in rng.randi_range(3, 6):
					var o := Vector3(rng.randf_range(-0.2, 0.2), 0.0, rng.randf_range(-0.2, 0.2))
					_cross(acc, foot + o, rng, C_POKER, 0.22, rng.randf_range(0.8, 1.15), 2, 1.0)
			Sp.LAVENDER:
				_clump(acc, foot, rng, C_LAVENDER, rng.randf_range(0.55, 0.8), rng.randf_range(0.45, 0.65), 3)
			_:
				_mound(acc, foot, rng, C_LANTANA[rng.randi() % 2], rng.randf_range(0.45, 0.7))
		st.accent_tris = int(st.accent_tris) + acc.tris() - before
		_count(st, sp, 1)


## An agave or aloe: `count` leaves from the centre, each a folded blade (a V across its midrib) of
## three segments, rising steeply in the middle and splaying out round the rim, curving up at the
## tip.
static func _rosette(acc: Acc, foot: Vector3, rng: RandomNumberGenerator, count: int, length: float, width: float, cell: int, upright: float, curl: float) -> void:
	var golden := 2.39996
	var a0 := rng.randf() * TAU
	for i in count:
		var f := float(i) / float(count)
		var ang := a0 + float(i) * golden
		var dir := Vector3(sin(ang), 0.0, cos(ang))
		var side := Vector3(cos(ang), 0.0, -sin(ang))
		# Inner leaves stand up, outer ones lie out.
		var elev := lerpf(1.35, 0.35, f) * upright + rng.randf_range(-0.1, 0.1)
		var ln := length * lerpf(0.55, 1.0, f) * rng.randf_range(0.9, 1.08)
		var w := width * lerpf(0.7, 1.0, f)
		var tint := Color(1, 1, 1) * rng.randf_range(0.9, 1.08)
		var segs := 3
		var p := foot + Vector3(0.0, 0.03, 0.0)
		var prev_c := p
		var prev_l := -1
		var prev_r := -1
		var prev_m := -1
		for s in segs + 1:
			var q := float(s) / float(segs)
			var e := elev + curl * q * q * (1.0 - elev / 1.6) * 0.5
			var axis := (dir * cos(e) + Vector3.UP * sin(e)).normalized()
			var c := prev_c if s == 0 else prev_c + axis * (ln / float(segs))
			var hw := w * 0.5 * (1.0 - pow(q, 1.6) * 0.95)
			var fold := hw * 0.45
			var up_n := axis.cross(side).normalized()
			if up_n.y < 0.0:
				up_n = -up_n
			var bs := 1.0 if up_n.cross(side).dot(axis) > 0.0 else -1.0
			var v := 1.0 - q
			var col := Color(tint.r, tint.g, tint.b, 0.04 * q)
			var il := acc.vert(c - side * hw, up_n, side, col, _cell_uv(cell, 0.5 - 0.5 * (hw / (w * 0.5)) * 0.95, v), 0.0, bs)
			var im := acc.vert(c + up_n * fold, up_n, side, col, _cell_uv(cell, 0.5, v), 0.0, bs)
			var ir := acc.vert(c + side * hw, up_n, side, col, _cell_uv(cell, 0.5 + 0.5 * (hw / (w * 0.5)) * 0.95, v), 0.0, bs)
			if s > 0:
				acc.quad(prev_l, prev_m, im, il, up_n)
				acc.quad(prev_m, prev_r, ir, im, up_n)
			prev_l = il
			prev_m = im
			prev_r = ir
			prev_c = c


## Crossed vertical cards (a spike, a clump's blades): `planes` cards round a vertical axis.
static func _cross(acc: Acc, foot: Vector3, rng: RandomNumberGenerator, cell: int, w: float, h: float, planes: int, flower: float = 0.0) -> void:
	var a0 := rng.randf() * PI
	var tilt := Vector3(rng.randf_range(-0.12, 0.12), 1.0, rng.randf_range(-0.12, 0.12)).normalized()
	for k in planes:
		var a := a0 + float(k) * PI / float(planes)
		var ax := Vector3(cos(a), 0.0, sin(a))
		var n := ax.cross(tilt).normalized()
		_card_into(acc, foot + tilt * (h * 0.5), ax, tilt, (n + Vector3.UP * 0.6).normalized(), w, h, cell, Color(1, 1, 1) * rng.randf_range(0.9, 1.06), 0.0, 0.3, flower, 0.0)


static func _clump(acc: Acc, foot: Vector3, rng: RandomNumberGenerator, cell: int, w: float, h: float, planes: int) -> void:
	_cross(acc, foot, rng, cell, w, h, planes)


## A low mound of crossed cards (lantana): a ring of cards leaning out round a centre one.
static func _mound(acc: Acc, foot: Vector3, rng: RandomNumberGenerator, cell: int, size: float) -> void:
	_cross(acc, foot, rng, cell, size * 1.2, size, 2, 0.6)
	var n := 5
	for k in n:
		var a := float(k) / float(n) * TAU + rng.randf() * 0.5
		var dir := Vector3(sin(a), 0.0, cos(a))
		var ay := (Vector3.UP * 0.7 + dir * 0.7).normalized()
		var ax := Vector3(cos(a), 0.0, -sin(a))
		_card_into(acc, foot + dir * size * 0.35 + Vector3.UP * size * 0.3, ax, ay, (dir + Vector3.UP).normalized(), size, size, cell,
			Color(1, 1, 1) * rng.randf_range(0.9, 1.06), 0.0, 0.3, 0.6, 0.0)


# --- Commit ---------------------------------------------------------------------------------------

static func _commit(ch: CityChunk, st: Dictionary) -> void:
	var tris := {"leaf": 0, "shadow": 0, "accent": 0}
	var nodes := 0
	# Each tile's range is the plants' reach plus the distance from its centre to its corner;
	# the shader fades the cards themselves out at their own distance (fade_far).
	var reach := TILE * 0.71
	for kind: String in ["leaf", "shadow", "accent"]:
		var tiles: Dictionary = st[kind]
		for k: Vector2i in tiles:
			var acc: Acc = tiles[k]
			if acc.tris() == 0:
				continue
			tris[kind] = int(tris[kind]) + acc.tris()
			var mi := MeshInstance3D.new()
			mi.name = {"leaf": "Climbers", "shadow": "ClimbersShadow", "accent": "ClimberAccents"}[kind] + "_%d_%d" % [k.x, k.y]
			mi.mesh = acc.mesh(material())
			mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
			match kind:
				"leaf":
					mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
					MultiMeshBatch._set_draw_distance(mi, DRAW_DISTANCE + reach)
				"shadow":
					mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
					MultiMeshBatch._set_draw_distance(mi, SHADOW_DISTANCE + reach)
				_:
					MultiMeshBatch._set_draw_distance(mi, ACCENT_DISTANCE + reach)
			mi.add_to_group("climbers")
			ch.add_child(mi)
			nodes += 1
	ch.set_meta("climbers", {"counts": st.counts, "cards": st.cards, "leaf_tris": tris.leaf, "shadow_tris": tris.shadow,
		"accent_tris": tris.accent, "nodes": nodes, "spots": st.spots, "faces": st.debug_faces, "centres": st.debug_centres})


static var _material: ShaderMaterial = null


static func material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = load("res://shaders/climbers.gdshader")
		_material.set_shader_parameter("albedo_tex", load("res://assets/textures/climbers/climbers_albedo.png"))
		_material.set_shader_parameter("normal_tex", load("res://assets/textures/climbers/climbers_normal.png"))
		_material.set_shader_parameter("atlas_size", Vector2(ATLAS_COLS * CELL_PX, ATLAS_ROWS * CELL_PX))
	return _material
