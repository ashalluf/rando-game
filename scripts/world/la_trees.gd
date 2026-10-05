class_name LaTrees
extends RefCounted
## The trees that make the city read as Los Angeles (2026-10-05): eucalyptus, Italian cypress,
## olive, Indian laurel fig, California sycamore and coral tree, and the knee-to-head-height
## accents - bird of paradise, agave, yucca and dragon tree (dracaena). Poly Haven has none of
## them, so every one is BUILT IN CODE at real size, the way PropFactory.palm() is: a skeleton
## grown once per variant from its own seed (trunk, limbs, branches, twigs with pipe-model radii),
## the foliage as leaf cards whose outline the shader cuts (shaders/la_tree.gdshader: lanceolate,
## oval, palmate, trifoliate, scale sprays, swords, paddles, flowers), and a hand-built LOD ladder
## emitted from that same data - leaves merged `stride` at a time into one card of the same area,
## then each twig's cluster drawn as two and then one cut cluster card, thinner limbs dropped - so
## every level is the same tree. One vertex buffer per variant, the coarser levels its LODs at an
## `edge` that is the level's departure in metres (Viewport mesh_lod_threshold does the rest), the
## shadow twin the same ladder from SHADOW_LEVEL, and the mesh flagged "foliage_ladder" so
## MultiMeshBatch scales the edges by its biggest instance. One surface, one material per species:
## a batch is one draw and its twin one more.
##
## Placement is hashes of seed + place, called AFTER every existing roll (CityChunk._add_tree(),
## LotFill._tree(), YardFill._shrub(), LotFill._shrub(), HouseKit.build()), so nothing a seed
## already built moves: a share of blocks swap their street species (figs downtown, coral and
## olive and sycamore out from it), park and plaza trees swap by 30 m cell (eucalyptus stands,
## sycamore groves, olives in raised planters and roundabouts), the freeway's right-of-way tree
## row is eucalyptus, Spanish and Craftsman houses get a pair of cypress columns either side of
## the front walk and a few accents in the front garden, and some shrubs in the yards and
## forecourt planters are agave, yucca, bird of paradise or dracaena. `enabled` false (LA_TREES=0
## in the environment) leaves the city exactly as it was: the A/B.

enum Species { EUCALYPTUS, CYPRESS, OLIVE, FIG, SYCAMORE, CORAL, BIRD_OF_PARADISE, AGAVE, YUCCA, DRACAENA }
const NAMES := ["eucalyptus", "cypress", "olive", "fig", "sycamore", "coral", "bird_of_paradise", "agave", "yucca", "dracaena"]
## Variants per species (each a mesh, so a batch: a block or a lot uses one by hash).
const VARIANTS := 2
## Native heights in metres (the mesh is built at this size; instances scale 0.6-1.25).
const HEIGHT := [24.0, 13.0, 6.5, 11.0, 15.0, 10.0, 1.45, 0.8, 4.0, 5.0]
## The planted range in metres per species, as CITY_TREE_TARGET is for the scanned trees.
const TARGET := [
	Vector2(17.0, 27.0), Vector2(8.0, 13.0), Vector2(4.5, 7.0), Vector2(8.0, 11.0), Vector2(11.0, 17.0),
	Vector2(7.5, 11.0), Vector2(1.1, 1.6), Vector2(0.55, 1.05), Vector2(2.6, 4.6), Vector2(3.4, 5.8),
]

## Shader kinds (UV2.x; shaders/la_tree.gdshader's K_*). Bark under 8, leaves from 8.
const B_SMOOTH := 0
const B_EUC := 1
const B_SYC := 2
const B_OLIVE := 3
const B_FIBRE := 4
const B_STEM := 5
const L_LANCE := 8
const L_OVAL := 9
const L_PALMATE := 10
const L_SCALE := 11
const L_CLUSTER := 12
const L_SUCC := 13
const L_SUCC_VAR := 14
const L_SWORD := 15
const L_PADDLE := 16
const L_FLOWER := 17
const L_TRIFOL := 18
## A sprig card: a stem with its leaves cut out (style 0 oval, 1 hanging sickles, 2 narrow pairs).
const L_SPRIG := 19

## The ladder. `stride` leaves to a card (0: cluster cards, `cards` a cluster), `sides` scales a
## tube's sides, `seg` its rings, `min_r` drops tubes thinner than that at their start (metres),
## `leaf_segs` caps a leaf's segments. The edge is worked out per species (_edges()).
const LEVELS := [
	{"i": 0, "stride": 1, "cards": 0, "sides": 1.0, "seg": 1.0, "min_r": 0.0, "leaf_segs": 4},
	{"i": 1, "stride": 3, "cards": 0, "sides": 0.7, "seg": 0.6, "min_r": 0.0, "leaf_segs": 2},
	{"i": 2, "stride": 8, "cards": 0, "sides": 0.5, "seg": 0.4, "min_r": 0.02, "leaf_segs": 1},
	{"i": 3, "stride": 0, "cards": 2, "sides": 0.4, "seg": 0.3, "min_r": 0.05, "leaf_segs": 1},
	{"i": 4, "stride": 0, "cards": 1, "sides": 0.3, "seg": 0.2, "min_r": 0.12, "leaf_segs": 1},
]
## The level the shadow twin starts at: a merged leaf of three is a few centimetres, which no
## cascade resolves.
const SHADOW_LEVEL := 1
## As FoliageLod.COUNTER_EDGE: the last level repeated at an edge nothing reaches, so the
## renderer's counter counts a batch of these like every other LOD'd batch (CLAUDE.md trap 3).
const COUNTER_EDGE := 1.0e6

static var enabled: bool = OS.get_environment("LA_TREES") != "0"
static var _cache := {}
static var _mats := {}
static var _shadow := {}
static var _crown := {}


# =================================================================================================
# Meshes
# =================================================================================================

## Species `sp`'s variant `v` (0..VARIANTS-1), built once and cached.
static func mesh(sp: int, v: int = 0) -> Mesh:
	var key := "%d_%d" % [sp, v]
	if _cache.has(key):
		return _cache[key]
	var data := _grow(sp, v)
	var levels: Array = []
	for l in LEVELS.size():
		levels.append(_emit(data, LEVELS[l]))
	var edges := _edges(data)
	var m := _ladder(levels, edges, 0)
	m.surface_set_material(0, material(sp))
	m.set_meta("foliage_ladder", true)
	var tw := _ladder(levels, edges, SHADOW_LEVEL)
	tw.surface_set_material(0, material(sp))
	PropFactory._shadow_proxies[m] = tw
	_shadow[key] = tw
	_crown[key] = data.crown
	_cache[key] = m
	return m


## The shadow twin of a variant (the ladder from SHADOW_LEVEL).
static func shadow_mesh(sp: int, v: int = 0) -> Mesh:
	mesh(sp, v)
	return _shadow["%d_%d" % [sp, v]]


## A variant's crown as built: {"centre": Vector3, "radii": Vector3}, at native size.
static func crown(sp: int, v: int = 0) -> Dictionary:
	mesh(sp, v)
	return _crown["%d_%d" % [sp, v]]


## Every level's indexed arrays of a variant, for the checks (level 0 first).
static func level_arrays(sp: int, v: int = 0) -> Array:
	var data := _grow(sp, v)
	var out: Array = []
	for l in LEVELS.size():
		out.append(_emit(data, LEVELS[l]))
	return out


## The edge (metres of departure from the full tree) of each level of a variant.
static func level_edges(sp: int, v: int = 0) -> Array:
	return _edges(_grow(sp, v))


## One material per species (its wind, gloss and translucency in uniforms).
static func material(sp: int) -> ShaderMaterial:
	if _mats.has(sp):
		return _mats[sp]
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/la_tree.gdshader")
	var p: Dictionary = _params(sp, 0)
	m.set_shader_parameter("bend_scale", float(p.get("bend", 0.0012)))
	m.set_shader_parameter("flutter", float(p.get("flutter", 0.03)))
	m.set_shader_parameter("leaf_roughness", float(p.get("rough", 0.7)))
	m.set_shader_parameter("leaf_specular", float(p.get("spec", 0.35)))
	m.set_shader_parameter("translucency", float(p.get("trans", 0.4)))
	var under: Color = p.get("under", Color(1.08, 1.08, 1.0))
	m.set_shader_parameter("underside", Vector3(under.r, under.g, under.b))
	_mats[sp] = m
	return m


## Builds every variant and returns the materials, for the loading screen (LoadingScreen draws
## each through a one-instance MultiMesh, the only way these are drawn).
static func warm() -> Array:
	if not enabled:
		return []
	var out: Array = []
	for sp in NAMES.size():
		for v in VARIANTS:
			mesh(sp, v)
		out.append(material(sp))
	return out


## Uniform scale that makes species `sp` stand `metres` tall.
static func scale_for(sp: int, metres: float) -> float:
	return metres / float(HEIGHT[sp])


## A height in the species' planted range from a hash value 0..1.
static func height_at(sp: int, t: float) -> float:
	var r: Vector2 = TARGET[sp]
	return lerpf(r.x, r.y, clampf(t, 0.0, 1.0))


# =================================================================================================
# Placement (hooks; hashes only, after every existing roll)
# =================================================================================================

## Street species by district: [odds a block's kerb rows swap, [[species, weight], ...]].
const STREET := {
	CityPlan.District.DOWNTOWN: [0.55, [[Species.FIG, 0.8], [Species.CORAL, 0.1], [Species.OLIVE, 0.1]]],
	CityPlan.District.MIDTOWN: [0.45, [[Species.FIG, 0.45], [Species.CORAL, 0.2], [Species.OLIVE, 0.15], [Species.SYCAMORE, 0.1], [Species.EUCALYPTUS, 0.1]]],
	CityPlan.District.SUBURBS: [0.35, [[Species.SYCAMORE, 0.25], [Species.CORAL, 0.2], [Species.OLIVE, 0.2], [Species.EUCALYPTUS, 0.2], [Species.FIG, 0.15]]],
	CityPlan.District.INDUSTRIAL: [0.35, [[Species.EUCALYPTUS, 0.6], [Species.FIG, 0.4]]],
	CityPlan.District.CAMPUS: [0.4, [[Species.SYCAMORE, 0.4], [Species.EUCALYPTUS, 0.3], [Species.OLIVE, 0.3]]],
	CityPlan.District.BEACHTOWN: [0.3, [[Species.CORAL, 0.35], [Species.FIG, 0.3], [Species.OLIVE, 0.2], [Species.EUCALYPTUS, 0.15]]],
}
## Park and plaza trees: a 30 m cell's odds of a stand, and what it is.
const PARK_CELL := 30.0
const PARK_ODDS := 0.45
const PARK := [[Species.EUCALYPTUS, 0.35], [Species.SYCAMORE, 0.3], [Species.CORAL, 0.15], [Species.OLIVE, 0.1], [Species.FIG, 0.1]]
## A tree in a raised planter (more than this over the pavement) or a roundabout is an olive this often.
const PLANTER_LIFT := 0.3
const PLANTER_OLIVE := 0.5
## Share of a swapped street block's trees that are the new species.
const STREET_SHARE := 0.88
## Street rows are narrowed across the street to this (instance scale), so a crown keeps off the
## building line - a laurel fig is pruned to the same shape on a real downtown pavement.
const STREET_ACROSS := 0.72
## The most a street tree's crown reaches across the pavement, and a yard or plaza tree's any way
## (metres): no crown through a facade.
const STREET_REACH := 2.9
const YARD_REACH := 3.2
## Lot and yard trees (LotFill._tree): the freeway's tree row within this of a deck edge.
const ROW_REACH := 12.0
const ROW_EUCALYPTUS := 0.9
## Per-chunk caps on what HouseKit and the shrub swaps add.
const MAX_CYPRESS := 16
const MAX_ACCENTS := 40
## A Spanish or Craftsman house's odds of a cypress pair, and of front-garden accents.
const CYPRESS_ODDS := {HouseKit.Style.SPANISH: 0.7, HouseKit.Style.CRAFTSMAN: 0.45, HouseKit.Style.MIDCENTURY: 0.15, HouseKit.Style.STUCCO_BOX: 0.12}
const ACCENT_ODDS := 0.6
## A shrub's odds of being an accent instead (yards; forecourt planters).
const SHRUB_ACCENT := 0.22
const PLANTER_ACCENT := 0.3


static func _h01(a: Array) -> float:
	return float(absi(hash(a)) % 100000) / 100000.0


static func _pick(table: Array, t: float) -> int:
	var total := 0.0
	for e: Array in table:
		total += float(e[1])
	var run := 0.0
	for e: Array in table:
		run += float(e[1]) / total
		if t < run:
			return int(e[0])
	return int(table[-1][0])


## The species block (ix, iz)'s kerb rows swap to, or -1 (pure: the plan and hashes).
static func street_species(plan: CityPlan, ix: int, iz: int) -> int:
	if not enabled:
		return -1
	var row: Array = STREET.get(int(plan.block(ix, iz).district), [0.0, []])
	if _h01([plan.seed, ix, iz, "la_street"]) >= float(row[0]):
		return -1
	return _pick(row[1], _h01([plan.seed, ix, iz, "la_street_sp"]))


## From CityChunk._add_tree(), after its rolls: plants this tree as one of ours and returns true,
## or returns false (the caller plants its own). `street`: a kerb row (it passes a lean).
static func street_or_park(ch: CityChunk, at: Vector3, yaw: float, tint: Color, street: Vector2) -> bool:
	if not enabled or ch._jacaranda_street:
		return false
	var plan := ch.plan
	var block := plan.block(ch.ix, ch.iz)
	var district: int = block.district
	var sp := -1
	var key := Vector2i(roundi(at.x * 4.0), roundi(at.z * 4.0))
	if street != Vector2.ZERO:
		sp = street_species(plan, ch.ix, ch.iz)
		if sp < 0 or _h01([plan.seed, key, "la_share"]) >= STREET_SHARE:
			return false
	elif at.y > CityChunk.SIDEWALK_TOP + PLANTER_LIFT:
		if _h01([plan.seed, key, "la_planter"]) >= PLANTER_OLIVE:
			return false
		sp = Species.OLIVE
	else:
		var cell := Vector2i(floori(at.x / PARK_CELL), floori(at.z / PARK_CELL))
		if _h01([plan.seed, cell, "la_park"]) >= PARK_ODDS or _h01([plan.seed, key, "la_share"]) >= 0.85:
			return false
		sp = _pick(PARK, _h01([plan.seed, cell, "la_park_sp"]))
		# Downtown's plazas are not eucalyptus woods.
		if district == CityPlan.District.DOWNTOWN and sp == Species.EUCALYPTUS:
			sp = Species.FIG
	var v := absi(hash([plan.seed, ch.ix, ch.iz, sp, "la_v"])) % VARIANTS
	var h := height_at(sp, _h01([plan.seed, key, "la_h"]))
	if street != Vector2.ZERO and sp == Species.EUCALYPTUS:
		# A kerbside gum is a young one: a full 25 m tree's crown fills the street.
		h = lerpf(10.0, 14.0, _h01([plan.seed, key, "la_h"]))
	var rx: float = (crown(sp, absi(hash([plan.seed, ch.ix, ch.iz, sp, "la_v"])) % VARIANTS).radii as Vector3).x / float(HEIGHT[sp])
	if street != Vector2.ZERO:
		# Across the pavement the crown keeps off the building line.
		h = minf(h, STREET_REACH / (rx * STREET_ACROSS))
	elif block.kind != CityPlan.BlockKind.PARK:
		# A plaza or a courtyard has buildings round it.
		h = minf(h, YARD_REACH * 1.3 / rx)
	var s := scale_for(sp, h)
	var basis := Basis(Vector3.UP, yaw).scaled(Vector3(s, s, s))
	if street != Vector2.ZERO:
		# Narrowed across the street: local x is turned to the street's direction.
		var along := Vector3(-street.y, 0.0, street.x)
		var b := Basis(along, Vector3.UP, along.cross(Vector3.UP))
		basis = b * Basis.from_scale(Vector3(s, s, s * STREET_ACROSS)) * Basis(Vector3.UP, PI * float(absi(hash([key, "flip"])) % 2))
	_add(ch, sp, v, Transform3D(basis, at), tint)
	return true


## A gully's share of sycamores (CityChunk._plant_hills, `wet` its hollow 0..1).
const GULLY_SYCAMORE := 0.45


## From CityChunk._plant_hills(), after its rolls: a California sycamore instead of the gully oak
## in the wettest hollows, now and then.
static func gully_tree(ch: CityChunk, at: Vector3, yaw: float, wet: float) -> bool:
	if not enabled or wet < 0.45:
		return false
	var key := Vector2i(roundi(at.x * 2.0), roundi(at.z * 2.0))
	if _h01([ch.plan.seed, key, "la_gully"]) >= GULLY_SYCAMORE:
		return false
	var v := absi(hash([ch.plan.seed, ch.ix, ch.iz, "la_gully_v"])) % VARIANTS
	var s := scale_for(Species.SYCAMORE, lerpf(9.0, 15.0, _h01([ch.plan.seed, key, "la_h"])))
	_add(ch, Species.SYCAMORE, v, Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(s, s, s)), at), Color(1, 1, 1))
	return true


## From LotFill._tree() (yards, planters, campuses, the freeway's tree row), after its rolls.
static func lot_tree(ch: CityChunk, at: Vector3, yaw: float, tint: Color) -> bool:
	if not enabled:
		return false
	var plan := ch.plan
	var district: int = plan.block(ch.ix, ch.iz).district
	var p := Vector2(at.x, at.z)
	var key := Vector2i(roundi(at.x * 4.0), roundi(at.z * 4.0))
	var sp := -1
	var deck := YardFill._deck_distance(plan, p)
	if deck < ROW_REACH:
		if _h01([plan.seed, key, "la_row"]) >= ROW_EUCALYPTUS:
			return false
		sp = Species.EUCALYPTUS
	else:
		var t := _h01([plan.seed, key, "la_lot"])
		match district:
			CityPlan.District.SUBURBS, CityPlan.District.BEACHTOWN:
				if t < 0.22:
					sp = Species.OLIVE
				elif t < 0.32:
					sp = Species.CORAL
				elif t < 0.38:
					sp = Species.SYCAMORE
			CityPlan.District.CAMPUS:
				if t < 0.35:
					sp = Species.SYCAMORE
				elif t < 0.5:
					sp = Species.EUCALYPTUS
				elif t < 0.65:
					sp = Species.OLIVE
			_:
				if t < 0.35:
					sp = Species.OLIVE
				elif t < 0.55:
					sp = Species.FIG
	if sp < 0:
		return false
	var v := absi(hash([plan.seed, ch.ix, ch.iz, sp, "la_v"])) % VARIANTS
	var h := height_at(sp, _h01([plan.seed, key, "la_h"]))
	if sp == Species.EUCALYPTUS and deck < ROW_REACH:
		# The crown keeps off the deck: its radius at this size stays inside the gap to the edge.
		var c := crown(sp, v)
		var r: float = (c.radii as Vector3).x
		h = minf(h, maxf(deck - 1.0, 3.0) / r * float(HEIGHT[sp]))
		h = maxf(h, 12.0)
	elif district != CityPlan.District.CAMPUS:
		h = minf(h, YARD_REACH / ((crown(sp, v).radii as Vector3).x / float(HEIGHT[sp])))
	var s := scale_for(sp, h)
	_add(ch, sp, v, Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(s, s, s)), at), tint)
	return true


## From YardFill._shrub() / LotFill._shrub(), after their rolls: an accent instead, now and then.
## `odds` the share; `at` on the ground the shrub stands on.
static func accent_shrub(ch: CityChunk, at: Vector3, odds: float) -> bool:
	if not enabled or ch.level != CityChunk.Level.FULL:
		return false
	var key := Vector2i(roundi(at.x * 4.0), roundi(at.z * 4.0))
	if _h01([ch.plan.seed, key, "la_accent"]) >= odds:
		return false
	var n: int = ch.get_meta("la_accents", 0)
	if n >= MAX_ACCENTS:
		return false
	ch.set_meta("la_accents", n + 1)
	# One accent species a chunk for the shrub swaps (a batch each), the variant by lot.
	var sp: int = [Species.AGAVE, Species.BIRD_OF_PARADISE, Species.YUCCA, Species.DRACAENA][absi(hash([ch.plan.seed, ch.ix, ch.iz, "la_accent_sp"])) % 4]
	var v := absi(hash([ch.plan.seed, key, "la_v"])) % VARIANTS
	var s := scale_for(sp, height_at(sp, _h01([ch.plan.seed, key, "la_h"])))
	_add(ch, sp, v, Transform3D(Basis(Vector3.UP, _h01([ch.plan.seed, key, "la_yaw"]) * TAU).scaled(Vector3(s, s, s)), at), Color(1, 1, 1))
	return true


## From HouseKit.build() at FULL: a cypress pair either side of the front walk of a Spanish or
## Craftsman house (now and then another style), and a few accents in the front garden. All in the
## house's yard frame (YardFill: u along the street, v back from the front edge).
static func house(ch: CityChunk, h: Dictionary) -> void:
	if not enabled or ch.level != CityChunk.Level.FULL or ch.capturing:
		return
	var plan := ch.plan
	var s: int = h.seed
	var f: Dictionary = h.f
	var U: float = f.U
	var door_u: float = h.door_u
	var door_v: float = h.door_v
	var drive: Vector2 = h.drive
	var base := CityChunk.SIDEWALK_TOP + YardFill.LIFT
	var front := door_v
	var style: int = h.style
	var clear := func(u: float, r: float) -> bool:
		return u > r and u < U - r and not (drive.y > drive.x and u > drive.x - r - 0.4 and u < drive.y + r + 0.4)
	if front >= 2.6 and _h01([plan.seed, s, "la_cypress"]) < float(CYPRESS_ODDS.get(style, 0.0)):
		var n: int = ch.get_meta("la_cypress", 0)
		var v := absi(hash([plan.seed, s, "la_cyp_v"])) % VARIANTS
		var ht := height_at(Species.CYPRESS, _h01([plan.seed, s, "la_cyp_h"]))
		# Flanking the walk up to the door, or the house's front corners when the walk is in the way.
		var gap := 1.5 + _h01([plan.seed, s, "la_cyp_gap"]) * 0.8
		var vv := clampf(front - 1.0, 1.2, front - 0.8)
		for side: float in [-1.0, 1.0]:
			# Flanking the walk, or further along the front when the drive is there.
			var u := door_u + side * gap
			for step in 3:
				if clear.call(u, 0.9):
					break
				u += side * 1.3
			if n >= MAX_CYPRESS or not clear.call(u, 0.9):
				continue
			n += 1
			var p := YardFill._fp(f, u, vv)
			# Where they stand, for the checks and the probe (the door's side of the pair).
			var at: Array = ch.get_meta("la_cypress_at", [])
			at.append(Vector3(p.x, base, p.y))
			ch.set_meta("la_cypress_at", at)
			var hs := ht * (0.95 + 0.1 * _h01([plan.seed, s, side, "la_cyp_hs"]))
			var sc := scale_for(Species.CYPRESS, hs)
			_add(ch, Species.CYPRESS, v, Transform3D(Basis(Vector3.UP, _h01([plan.seed, s, side]) * TAU).scaled(Vector3(sc, sc, sc)), Vector3(p.x, base, p.y)), Color(1, 1, 1))
		ch.set_meta("la_cypress", n)
	if front >= 3.0 and _h01([plan.seed, s, "la_accents"]) < ACCENT_ODDS:
		var na: int = ch.get_meta("la_accents", 0)
		var picks := [Species.AGAVE, Species.BIRD_OF_PARADISE, Species.YUCCA, Species.DRACAENA]
		# Spanish and modern gardens are dry (agave, yucca, dragon trees); a Craftsman's lush.
		var sp: int = picks[absi(hash([plan.seed, s, "la_acc_sp"])) % 4]
		if style == HouseKit.Style.CRAFTSMAN and sp != Species.BIRD_OF_PARADISE:
			sp = Species.BIRD_OF_PARADISE if _h01([plan.seed, s, "la_lush"]) < 0.6 else sp
		var count := 1 + absi(hash([plan.seed, s, "la_acc_n"])) % 3
		for i in count:
			if na >= MAX_ACCENTS:
				break
			var u := lerpf(1.2, U - 1.2, _h01([plan.seed, s, i, "la_acc_u"]))
			if absf(u - door_u) < 1.4 or not clear.call(u, 0.8):
				continue
			var v := lerpf(0.9, front - 0.9, _h01([plan.seed, s, i, "la_acc_v"]))
			na += 1
			var p := YardFill._fp(f, u, v)
			var sc := scale_for(sp, height_at(sp, _h01([plan.seed, s, i, "la_acc_h"])))
			var var_i := absi(hash([plan.seed, s, i, "la_acc_var"])) % VARIANTS
			_add(ch, sp, var_i, Transform3D(Basis(Vector3.UP, _h01([plan.seed, s, i]) * TAU).scaled(Vector3(sc, sc, sc)), Vector3(p.x, base, p.y)), Color(1, 1, 1))
		ch.set_meta("la_accents", na)


static func _add(ch: CityChunk, sp: int, v: int, xf: Transform3D, tint: Color) -> void:
	# What stands where (species, position), for the checks and the probe: the headless renderer
	# keeps no instance data to read back.
	var at: Array = ch.get_meta("la_at", [])
	at.append([sp, xf.origin])
	ch.set_meta("la_at", at)
	ch._batch.add("la_%s_%d" % [NAMES[sp], v], mesh(sp, v), xf, tint)


## The showroom's row (CityStreamer, `?showroom`): every species and variant side by side.
static func showroom(parent: Node3D, at: Vector3, forward: Vector3, right: Vector3, yaw: float) -> void:
	if not enabled:
		return
	var x := 0.0
	var spacing := [16.0, 5.0, 8.0, 12.0, 15.0, 12.0, 3.0, 3.0, 4.0, 5.0]
	var total := 0.0
	for sp in NAMES.size():
		total += float(spacing[sp]) * VARIANTS
	x = -total * 0.5
	for sp in NAMES.size():
		for v in VARIANTS:
			x += float(spacing[sp]) * 0.5
			var mi := MeshInstance3D.new()
			mi.mesh = mesh(sp, v)
			mi.position = at + forward * 60.0 + right * x + Vector3.UP * CityChunk.SIDEWALK_TOP
			mi.rotation.y = yaw
			parent.add_child(mi)
			x += float(spacing[sp]) * 0.5


# =================================================================================================
# Growing a tree (one pass of the variant's rng; every level is emitted from it)
# =================================================================================================

## Species parameters. Linear albedos (vertex colours reach both renderers raw).
static func _params(sp: int, v: int) -> Dictionary:
	match sp:
		Species.EUCALYPTUS:
			# Blue gum: a tall clear trunk of peeling cream and grey, ascending limbs, an open
			# crown of separate clumps with sky between, the leaves hanging in long sickles.
			return {"kind": "broad", "height": 24.0, "trunks": 1 + v, "spread": 0.9, "fork": 0.38, "leader": 0.75, "lean": 0.9,
				"crown_c": 0.62, "crown_r": Vector2(7.2, 8.0), "clumps": 15, "clump_r": 2.2, "clusters": 260, "shell": 0.6,
				"cluster_r": 0.6, "leaves": 9, "leaf_len": 0.5, "leaf_w": 0.24, "leaf_kind": L_SPRIG, "sprig": 1, "mode": "hang", "leaf_segs": 2,
				"droop": 0.25, "limbs": 7, "group": 5, "gnarl": 0.22, "twig_r": 0.011, "trunk_k": 3.8, "bark_kind": B_EUC,
				"bark": Color(0.63, 0.61, 0.55), "leaf": [Color(0.15, 0.20, 0.16), Color(0.24, 0.29, 0.22)], "cluster_style": 1,
				"bend": 0.0011, "flutter": 0.05, "rough": 0.62, "spec": 0.38, "trans": 0.35, "under": Color(1.05, 1.08, 1.06), "strips": 9}
		Species.CYPRESS:
			return {"kind": "column", "height": 13.0, "radius": 0.85 + 0.15 * v, "clusters": 520, "cluster_r": 0.32, "leaves": 7,
				"leaf_len": 0.36, "leaf_w": 0.2, "leaf_kind": L_SCALE, "twig_r": 0.012, "bark_kind": B_FIBRE,
				"bark": Color(0.30, 0.24, 0.18), "leaf": [Color(0.045, 0.075, 0.035), Color(0.075, 0.105, 0.05)], "cluster_style": 2,
				"bend": 0.0013, "flutter": 0.012, "rough": 0.8, "spec": 0.25, "trans": 0.2, "under": Color(1, 1, 1)}
		Species.OLIVE:
			# Short, twisted, often more than one stem; a rounded open head of narrow grey-green
			# leaves that show silver underneath.
			return {"kind": "broad", "height": 6.5, "trunks": 2 + v, "spread": 0.5, "fork": 0.24, "leader": 0.0, "lean": 0.5,
				"crown_c": 0.64, "crown_r": Vector2(3.3, 2.2), "clumps": 0, "clusters": 170, "shell": 0.45,
				"cluster_r": 0.4, "leaves": 9, "leaf_len": 0.3, "leaf_w": 0.18, "leaf_kind": L_SPRIG, "sprig": 2, "mode": "up", "leaf_segs": 1,
				"droop": 0.0, "limbs": 6, "group": 5, "gnarl": 0.45, "twig_r": 0.008, "trunk_k": 3.6, "bark_kind": B_OLIVE,
				"bark": Color(0.42, 0.40, 0.35), "leaf": [Color(0.19, 0.21, 0.15), Color(0.27, 0.29, 0.21)], "cluster_style": 0,
				"bend": 0.002, "flutter": 0.02, "rough": 0.7, "spec": 0.32, "trans": 0.25, "under": Color(1.75, 1.8, 1.7)}
		Species.FIG:
			# Indian laurel fig: the downtown street tree. Smooth grey trunk with a root flare,
			# clear to 3 m, then a dense round head of small glossy dark leaves.
			return {"kind": "broad", "height": 11.0, "trunks": 1, "spread": 0.0, "fork": 0.27, "leader": 0.15, "lean": 0.25,
				"crown_c": 0.6, "crown_r": Vector2(5.3, 4.2), "clumps": 0, "clusters": 300, "shell": 0.25,
				"cluster_r": 0.55, "leaves": 14, "leaf_len": 0.46, "leaf_w": 0.38, "leaf_kind": L_SPRIG, "sprig": 0, "mode": "spread", "leaf_segs": 1,
				"droop": 0.05, "limbs": 6 + v, "group": 6, "gnarl": 0.12, "twig_r": 0.009, "trunk_k": 3.4, "bark_kind": B_SMOOTH,
				"bark": Color(0.42, 0.41, 0.37), "leaf": [Color(0.07, 0.14, 0.035), Color(0.13, 0.21, 0.06)], "cluster_style": 0,
				"bend": 0.0008, "flutter": 0.025, "rough": 0.55, "spec": 0.36, "trans": 0.3, "under": Color(1.25, 1.3, 1.15)}
		Species.SYCAMORE:
			# California sycamore: leaning, crooked, often two or three trunks, white bark mottled
			# tan and grey, an irregular open crown of big palmate leaves.
			return {"kind": "broad", "height": 15.0, "trunks": 1 + v * 2, "spread": 1.2, "fork": 0.3, "leader": 0.45, "lean": 2.6,
				"crown_c": 0.66, "crown_r": Vector2(6.4, 4.6), "clumps": 9, "clump_r": 2.3, "clusters": 190, "shell": 0.5,
				"cluster_r": 0.6, "leaves": 18, "leaf_len": 0.27, "leaf_w": 0.27, "leaf_kind": L_PALMATE, "mode": "spread", "leaf_segs": 1,
				"droop": 0.1, "limbs": 7, "group": 5, "gnarl": 0.35, "twig_r": 0.011, "trunk_k": 3.2, "bark_kind": B_SYC,
				"bark": Color(0.66, 0.64, 0.57), "leaf": [Color(0.13, 0.20, 0.06), Color(0.22, 0.30, 0.09)], "cluster_style": 0,
				"bend": 0.0012, "flutter": 0.04, "rough": 0.72, "spec": 0.3, "trans": 0.45, "under": Color(1.3, 1.35, 1.2)}
		Species.CORAL:
			# Coral tree: broad and spreading on thick grey limbs, trifoliate leaves, and the red
			# flower spikes over the crown in late winter.
			return {"kind": "broad", "height": 10.0, "trunks": 1, "spread": 0.0, "fork": 0.25, "leader": 0.0, "lean": 0.4,
				"crown_c": 0.62, "crown_r": Vector2(5.6, 3.3), "clumps": 0, "clusters": 180, "shell": 0.4,
				"cluster_r": 0.55, "leaves": 18, "leaf_len": 0.3, "leaf_w": 0.26, "leaf_kind": L_TRIFOL, "mode": "spread", "leaf_segs": 1,
				"droop": 0.08, "limbs": 5, "group": 5, "gnarl": 0.25, "twig_r": 0.013, "trunk_k": 3.6, "bark_kind": B_SMOOTH,
				"bark": Color(0.40, 0.39, 0.35), "leaf": [Color(0.12, 0.21, 0.06), Color(0.19, 0.29, 0.08)], "cluster_style": 0,
				"flowers": 0.35 + 0.3 * v, "flower": Color(0.85, 0.08, 0.03),
				"bend": 0.0012, "flutter": 0.035, "rough": 0.66, "spec": 0.35, "trans": 0.42, "under": Color(1.25, 1.3, 1.15)}
		Species.BIRD_OF_PARADISE:
			return {"kind": "strelitzia", "height": 1.45, "bend": 0.01, "flutter": 0.02, "rough": 0.55, "spec": 0.4, "trans": 0.35,
				"leaf": [Color(0.09, 0.16, 0.08), Color(0.14, 0.22, 0.11)], "under": Color(1.2, 1.25, 1.2)}
		Species.AGAVE:
			return {"kind": "agave", "height": 1.25, "variegated": v == 1, "bend": 0.0, "flutter": 0.0, "rough": 0.5, "spec": 0.45,
				"trans": 0.15, "leaf": [Color(0.25, 0.32, 0.30), Color(0.33, 0.40, 0.37)], "under": Color(1, 1, 1)}
		Species.YUCCA:
			return {"kind": "rosettes", "height": 4.0, "stems": 3 + v, "branching": 1, "leaf_len": 0.7, "leaf_w": 0.045, "rosette": 34,
				"bark_kind": B_FIBRE, "bark": Color(0.34, 0.30, 0.24), "dead": true, "upright": 0.35,
				"bend": 0.004, "flutter": 0.02, "rough": 0.5, "spec": 0.4, "trans": 0.3,
				"leaf": [Color(0.10, 0.17, 0.06), Color(0.16, 0.24, 0.09)], "under": Color(1.15, 1.2, 1.1)}
		Species.DRACAENA:
			return {"kind": "rosettes", "height": 5.0, "stems": 1, "branching": 3, "leaf_len": 0.55, "leaf_w": 0.04, "rosette": 30,
				"bark_kind": B_SMOOTH, "bark": Color(0.46, 0.44, 0.39), "dead": false, "upright": 0.55,
				"bend": 0.0025, "flutter": 0.012, "rough": 0.5, "spec": 0.42, "trans": 0.2,
				"leaf": [Color(0.12, 0.20, 0.15), Color(0.18, 0.26, 0.19)], "under": Color(1.15, 1.18, 1.15)}
	return {}


## A tube: points along its centre line and a radius at each.
class Tube:
	var pts: PackedVector3Array
	var radii: PackedFloat32Array
	var kind: int
	var color: Color
	var sides: int = 8
	var cap := false


## A cluster: where a twig ends, its leaves (each [pos, dir, side, len, width, kind, colour,
## normal, segs, droop, rnd]) and what a cluster card there looks like.
class Cluster:
	var p: Vector3
	var out: Vector3
	var r: float
	var leaves: Array = []
	var color: Color
	var style: int = 0
	var card_kind: int = L_CLUSTER


## Everything a variant is: tubes, clusters, loose leaves (drawn at every level as they are, e.g.
## a rosette's swords), and the numbers the edges come from.
class TreeData:
	var tubes: Array[Tube] = []
	var clusters: Array[Cluster] = []
	var solids: Array = []
	var leaf_len := 0.1
	var cluster_r := 0.4
	var crown := {}


static func _grow(sp: int, v: int) -> TreeData:
	var p := _params(sp, v)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(["la_tree", sp, v])
	match String(p.kind):
		"broad":
			return _grow_broad(p, rng)
		"column":
			return _grow_column(p, rng)
		"agave":
			return _grow_agave(p, rng)
		"rosettes":
			return _grow_rosettes(p, rng)
		"strelitzia":
			return _grow_strelitzia(p, rng)
	return TreeData.new()


static func _rand_unit(rng: RandomNumberGenerator) -> Vector3:
	var u := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1))
	while u.length_squared() > 1.0 or u.length_squared() < 0.01:
		u = Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1))
	return u.normalized()


## A smooth bent polyline from a to b through a control point (quadratic Bezier), `n` segments.
static func _bend(a: Vector3, c: Vector3, b: Vector3, n: int) -> PackedVector3Array:
	var out := PackedVector3Array()
	for i in n + 1:
		var t := float(i) / float(n)
		out.append(a.lerp(c, t).lerp(c.lerp(b, t), t))
	return out


## Radii from r0 to r1 along a polyline (by length), with an optional root flare.
static func _taper(pts: PackedVector3Array, r0: float, r1: float, flare: float = 0.0) -> PackedFloat32Array:
	var total := 0.0
	for i in range(1, pts.size()):
		total += pts[i].distance_to(pts[i - 1])
	var out := PackedFloat32Array()
	var run := 0.0
	for i in pts.size():
		if i > 0:
			run += pts[i].distance_to(pts[i - 1])
		var t := run / maxf(total, 1e-4)
		var r := lerpf(r0, r1, pow(t, 0.8))
		if flare > 0.0:
			r *= 1.0 + flare * exp(-run * 3.5)
		out.append(r)
	return out


static func _tube(pts: PackedVector3Array, radii: PackedFloat32Array, kind: int, color: Color, sides: int) -> Tube:
	var t := Tube.new()
	t.pts = pts
	t.radii = radii
	t.kind = kind
	t.color = color
	t.sides = sides
	return t


## Sides for a tube by its radius.
static func _sides(r: float) -> int:
	if r > 0.2:
		return 14
	if r > 0.08:
		return 9
	if r > 0.03:
		return 6
	return 4


## The closest point index of a polyline to p.
static func _nearest(pts: PackedVector3Array, p: Vector3, from: int = 0) -> int:
	var best := from
	var bd := INF
	for i in range(from, pts.size()):
		var d := pts[i].distance_squared_to(p)
		if d < bd:
			bd = d
			best = i
	return best


## The broadleaf trees: clusters sampled in the crown, limbs grown to groups of them by direction,
## branches to sub-groups, twigs to each cluster (pipe-model radii), leaves round each twig's end.
static func _grow_broad(p: Dictionary, rng: RandomNumberGenerator) -> TreeData:
	var d := TreeData.new()
	var H: float = p.height
	var cr: Vector2 = p.crown_r
	var centre := Vector3(0.0, H * float(p.crown_c), 0.0)
	var lean_dir := Vector3(cos(rng.randf() * TAU), 0.0, 0.0)
	lean_dir = Vector3(1, 0, 0).rotated(Vector3.UP, rng.randf() * TAU)
	var lean: float = float(p.lean) * rng.randf_range(0.6, 1.0)
	centre += lean_dir * lean * 0.8
	d.crown = {"centre": centre, "radii": Vector3(cr.x, cr.y, cr.x)}
	d.leaf_len = p.leaf_len
	d.cluster_r = p.cluster_r
	var crown_top := centre.y + cr.y
	var crown_bottom := centre.y - cr.y
	var fork_y := H * float(p.fork)
	# Cluster points: uniform in the envelope pushed toward its shell, or in clumps (an open crown).
	var pts: Array[Vector3] = []
	var n_clusters: int = p.clusters
	var clumps: int = p.get("clumps", 0)
	var clump_c: Array[Vector3] = []
	for i in clumps:
		var u := _rand_unit(rng)
		u.y = absf(u.y) * 0.7 + 0.05 if rng.randf() < 0.45 else u.y
		clump_c.append(centre + Vector3(u.x * cr.x, u.y * cr.y, u.z * cr.x) * pow(rng.randf_range(0.35, 1.0), 0.5) * 0.82)
	var tries := 0
	while pts.size() < n_clusters and tries < n_clusters * 30:
		tries += 1
		var q: Vector3
		if clumps > 0:
			var cc: Vector3 = clump_c[pts.size() % clumps]
			q = cc + _rand_unit(rng) * float(p.clump_r) * pow(rng.randf(), 0.4)
		else:
			var u := _rand_unit(rng) * pow(rng.randf(), float(p.shell))
			q = centre + Vector3(u.x * cr.x, u.y * cr.y, u.z * cr.x)
		var e := (q - centre) / Vector3(cr.x, cr.y, cr.x)
		if e.length() > 1.05 or q.y < fork_y + 0.8:
			continue
		# A flatter underside: the crown is lifted off the pavement, not a ball on a stick.
		if e.y < -0.55 and rng.randf() < 0.7:
			continue
		pts.append(q)
	# Trunks: from the base (spread for a multi-stem tree) to the fork, leaning toward the crown.
	var trunks: int = p.trunks
	var limbs: int = p.limbs
	var gnarl: float = p.gnarl
	var twig_r: float = p.twig_r
	var bark: Color = p.bark
	var bark_kind: int = p.bark_kind
	var leader: float = p.leader
	var trunk_lines: Array[PackedVector3Array] = []
	var trunk_tops: Array[Vector3] = []
	for k in trunks:
		var a := TAU * float(k) / float(trunks) + rng.randf_range(-0.4, 0.4)
		var base := Vector3(cos(a), 0.0, sin(a)) * float(p.spread) * 0.25 * float(mini(trunks - 1, 1))
		var top_y := fork_y + leader * (crown_top - fork_y) * 0.85
		var top := Vector3(centre.x, top_y, centre.z) + Vector3(cos(a), 0.0, sin(a)) * float(p.spread) * (1.0 if trunks > 1 else 0.0)
		top += lean_dir * lean * (top_y / H) * 0.4
		var ctrl := base.lerp(top, 0.5) + Vector3(rng.randf_range(-1, 1), 0.0, rng.randf_range(-1, 1)) * gnarl * 0.6 + lean_dir * lean * 0.15
		var n := clampi(int(top.distance_to(base) / 0.5), 6, 24)
		var line := _bend(base, ctrl, top, n)
		# Gnarl along the stem.
		for i in range(1, line.size() - 1):
			line[i] += Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.3, 0.3), rng.randf_range(-1, 1)) * gnarl * 0.12
		trunk_lines.append(line)
		trunk_tops.append(top)
	# Limbs: directions spread round the crown, each takes the clusters it points at best.
	var limb_dirs: Array[Vector3] = []
	for i in limbs:
		var a := TAU * (float(i) + rng.randf_range(-0.3, 0.3)) / float(limbs)
		var pitch := rng.randf_range(0.45, 1.15)
		limb_dirs.append(Vector3(cos(a) * cos(pitch), sin(pitch), sin(a) * cos(pitch)))
	var groups: Array = []
	for i in limbs:
		groups.append([])
	var fork_c := Vector3(centre.x, fork_y, centre.z)
	for q in pts:
		var dir := (q - fork_c).normalized()
		var best := 0
		var bd := -INF
		for i in limbs:
			var s := dir.dot(limb_dirs[i])
			if s > bd:
				bd = s
				best = i
		groups[best].append(q)
	var total := float(pts.size())
	var leaf_kind: int = p.leaf_kind
	var colors: Array = p.leaf
	for i in limbs:
		var g: Array = groups[i]
		if g.is_empty():
			continue
		var tk := i % trunks
		var tline: PackedVector3Array = trunk_lines[tk]
		var cen := Vector3.ZERO
		var mean_y := 0.0
		for q: Vector3 in g:
			cen += q
			mean_y += q.y
		cen /= float(g.size())
		# Where the limb leaves its trunk: up the leader by how high its clusters sit.
		var rank := clampf((mean_y / g.size() - crown_bottom) / maxf(crown_top - crown_bottom, 1.0), 0.0, 1.0)
		var at_i := clampi(int(lerpf(tline.size() * 0.55, tline.size() - 1, rank * leader + (1.0 - leader))), 0, tline.size() - 1)
		if leader <= 0.0:
			at_i = tline.size() - 1
		var s0 := tline[at_i]
		var e0 := s0.lerp(cen, 0.82)
		var ctrl := s0.lerp(e0, 0.5) + Vector3.UP * s0.distance_to(e0) * 0.12 + _rand_unit(rng) * gnarl * s0.distance_to(e0) * 0.25
		var limb := _bend(s0, ctrl, e0, clampi(int(s0.distance_to(e0) / 0.45), 4, 14))
		var lr := twig_r * sqrt(float(g.size())) * 1.1
		d.tubes.append(_tube(limb, _taper(limb, lr, lr * 0.45), bark_kind, bark, _sides(lr)))
		# Branches to sub-groups (k-means by position, two passes).
		var nb := maxi(1, int(ceil(float(g.size()) / float(p.group))))
		var bc: Array[Vector3] = []
		for j in nb:
			bc.append(g[int(float(j) * g.size() / nb)])
		var assign := PackedInt32Array()
		assign.resize(g.size())
		for _pass in 2:
			var sums: Array[Vector3] = []
			var cnt := PackedInt32Array()
			sums.resize(nb)
			cnt.resize(nb)
			for j in nb:
				sums[j] = Vector3.ZERO
			for qi in g.size():
				var q: Vector3 = g[qi]
				var bj := 0
				var bdd := INF
				for j in nb:
					var dd := q.distance_squared_to(bc[j])
					if dd < bdd:
						bdd = dd
						bj = j
				assign[qi] = bj
				sums[bj] += q
				cnt[bj] += 1
			for j in nb:
				if cnt[j] > 0:
					bc[j] = sums[j] / float(cnt[j])
		for j in nb:
			var members: Array[Vector3] = []
			for qi in g.size():
				if assign[qi] == j:
					members.append(g[qi])
			if members.is_empty():
				continue
			var li := _nearest(limb, bc[j], 1)
			var bs := limb[li]
			var be := bs.lerp(bc[j], 0.85)
			var bctrl := bs.lerp(be, 0.5) + Vector3.UP * bs.distance_to(be) * 0.1 + _rand_unit(rng) * gnarl * bs.distance_to(be) * 0.2
			var branch := _bend(bs, bctrl, be, clampi(int(bs.distance_to(be) / 0.35), 2, 8))
			var br := twig_r * sqrt(float(members.size())) * 1.05
			d.tubes.append(_tube(branch, _taper(branch, br, br * 0.5), bark_kind, bark, _sides(br)))
			for q in members:
				var bi := _nearest(branch, q)
				var ts := branch[bi]
				var outw := (q - centre) / Vector3(cr.x, cr.y, cr.x)
				var te := q - outw.normalized() * float(p.cluster_r) * 0.3
				var twig := _bend(ts, ts.lerp(te, 0.5) + Vector3.UP * 0.1 * ts.distance_to(te), te, 2)
				d.tubes.append(_tube(twig, _taper(twig, twig_r, twig_r * 0.5), bark_kind, bark, 3))
				d.clusters.append(_cluster(p, rng, q, centre, cr, leaf_kind, colors))
	# The trunks, radius from what they carry (the pipe model), with a root flare.
	for k in trunks:
		var line: PackedVector3Array = trunk_lines[k]
		var r := twig_r * sqrt(total / float(trunks)) * float(p.trunk_k) * 0.5
		var r_top := r * (0.55 if leader > 0.0 else 0.8)
		var t := _tube(line, _taper(line, r, r_top, 0.45), bark_kind, bark * 0.92, _sides(r))
		d.tubes.append(t)
		# A leader runs on into the crown, thinning out.
		if leader > 0.0:
			var top := trunk_tops[k]
			var tip := top + Vector3.UP * (crown_top - top.y) * 0.75 + lean_dir * lean * 0.15
			var up := _bend(top, top.lerp(tip, 0.5) + _rand_unit(rng) * gnarl * 0.5, tip, 6)
			d.tubes.append(_tube(up, _taper(up, r_top, twig_r * 2.0), bark_kind, bark, _sides(r_top)))
	# Eucalyptus: long strips of shed bark hanging off the trunk.
	for i in int(p.get("strips", 0)):
		var line: PackedVector3Array = trunk_lines[i % trunks]
		var y := rng.randf_range(1.2, line[-1].y * 0.95)
		var li := _nearest(line, Vector3(line[0].x, y, line[0].z))
		var a := rng.randf() * TAU
		var r := twig_r * sqrt(total / float(trunks)) * float(p.trunk_k) * 0.5 * 0.85
		var s0 := line[li] + Vector3(cos(a), 0.0, sin(a)) * r * 1.02
		var len := rng.randf_range(0.6, 1.6)
		d.solids.append(["strip", s0, Vector3(cos(a), 0.0, sin(a)), len, rng.randf_range(0.05, 0.12), Color(0.52, 0.42, 0.32) * rng.randf_range(0.8, 1.1)])
	# Coral flowers: spikes over the outer clusters.
	var fodds: float = p.get("flowers", 0.0)
	if fodds > 0.0:
		var fc: Color = p.flower
		for c in d.clusters:
			if c.out.y > 0.05 and rng.randf() < fodds:
				var up := (c.out * 0.4 + Vector3.UP).normalized()
				d.solids.append(["flower", c.p + up * c.r * 0.6, up, rng.randf_range(0.22, 0.32), rng.randf(), fc * rng.randf_range(0.85, 1.1)])
	return d


## One twig's cluster: its leaves round the twig end, laid by the species' mode.
static func _cluster(p: Dictionary, rng: RandomNumberGenerator, q: Vector3, centre: Vector3, cr: Vector2, kind: int, colors: Array) -> Cluster:
	var c := Cluster.new()
	c.p = q
	var e := (q - centre) / Vector3(cr.x, cr.y, cr.x)
	c.out = (e / Vector3(cr.x, cr.y, cr.x)).normalized() if e.length() > 0.01 else Vector3.UP
	c.r = p.cluster_r
	c.style = p.get("cluster_style", 0)
	# Ambient occlusion baked in: deep inside the crown and on its underside is darker.
	var depth := clampf(1.0 - e.length(), 0.0, 1.0)
	var ao := lerpf(1.0, 0.45, pow(depth, 0.9)) * lerpf(0.72, 1.0, clampf(e.y * 0.5 + 0.5, 0.0, 1.0))
	var c0: Color = colors[0]
	var c1: Color = colors[1]
	c.color = c0.lerp(c1, rng.randf()) * ao
	var mode: String = p.get("mode", "spread")
	var ll: float = p.leaf_len
	var lw: float = p.leaf_w
	for i in int(p.leaves):
		var off := _rand_unit(rng) * c.r * pow(rng.randf_range(0.15, 1.0), 0.6)
		off += c.out * c.r * 0.25
		var pos := q + off
		var lo := (off.normalized() * 0.6 + c.out * 0.8).normalized()
		var dir: Vector3
		var target: Vector3
		match mode:
			"hang":
				dir = (Vector3.DOWN * 1.0 + lo * 0.45 + _rand_unit(rng) * 0.3).normalized()
				target = c.out
			"up":
				dir = (lo * 0.8 + Vector3.UP * 0.7 + _rand_unit(rng) * 0.35).normalized()
				target = (c.out + Vector3.UP * 0.6).normalized()
			_:
				dir = (lo * 1.0 + Vector3.UP * 0.25 + _rand_unit(rng) * 0.45).normalized()
				target = (c.out + Vector3.UP * 0.9).normalized()
		var side := dir.cross(target)
		if side.length_squared() < 1e-4:
			side = dir.cross(Vector3.RIGHT)
		side = side.normalized().rotated(dir, rng.randf_range(-0.6, 0.6))
		var face := side.cross(dir).normalized()
		if face.dot(c.out) < 0.0:
			face = -face
		var nrm := (face * 0.35 + c.out * 0.65).normalized()
		var size := rng.randf_range(0.8, 1.2)
		var le := (q + off - centre) / Vector3(cr.x, cr.y, cr.x)
		var lao := lerpf(1.0, 0.5, pow(clampf(1.0 - le.length(), 0.0, 1.0), 0.9)) * lerpf(0.72, 1.0, clampf(le.y * 0.5 + 0.5, 0.0, 1.0))
		var col := c0.lerp(c1, rng.randf()) * lao
		c.leaves.append([pos, dir, side, ll * size, lw * size, kind, col, nrm, int(p.get("leaf_segs", 1)), float(p.get("droop", 0.0)), rng.randf(), int(p.get("sprig", 0))])
	# Keep neighbours together, so a merged leaf stands where its three or eight were.
	var axis := c.out.cross(Vector3.UP if absf(c.out.y) < 0.9 else Vector3.RIGHT).normalized()
	var ax2 := c.out.cross(axis)
	c.leaves.sort_custom(func(a: Array, b: Array) -> bool:
		var da: Vector3 = a[0] - q
		var db: Vector3 = b[0] - q
		return atan2(da.dot(ax2), da.dot(axis)) < atan2(db.dot(ax2), db.dot(axis)))
	return c


## Italian cypress: a narrow column of upward scale sprays round a straight trunk.
static func _grow_column(p: Dictionary, rng: RandomNumberGenerator) -> TreeData:
	var d := TreeData.new()
	var H: float = p.height
	var R: float = p.radius
	d.leaf_len = p.leaf_len
	d.cluster_r = p.cluster_r
	d.crown = {"centre": Vector3(0.0, H * 0.5, 0.0), "radii": Vector3(R, H * 0.5, R)}
	var profile := func(t: float) -> float:
		# Widest a third of the way up, a pointed flame at the top, tucked in at the foot.
		return R * pow(clampf(1.0 - t, 0.0, 1.0), 0.75) * smoothstep(0.0, 0.14, t) * 1.12
	var trunk := PackedVector3Array()
	for i in 13:
		var t := float(i) / 12.0
		trunk.append(Vector3(rng.randf_range(-0.02, 0.02), H * 0.94 * t, rng.randf_range(-0.02, 0.02)))
	var tr := 0.16 + 0.02 * R
	d.tubes.append(_tube(trunk, _taper(trunk, tr, 0.03, 0.4), p.bark_kind, p.bark, 9))
	var colors: Array = p.leaf
	var c0: Color = colors[0]
	var c1: Color = colors[1]
	for i in int(p.clusters):
		var t := pow(rng.randf(), 0.9) * 0.98 + 0.02
		var a := rng.randf() * TAU
		var r: float = profile.call(t) * rng.randf_range(0.72, 1.02)
		var q := Vector3(cos(a) * r, H * t, sin(a) * r)
		var out := Vector3(cos(a), 0.25, sin(a)).normalized()
		var c := Cluster.new()
		c.p = q
		c.out = out
		c.r = p.cluster_r
		c.style = 2
		c.card_kind = L_SCALE
		var ao := lerpf(0.55, 1.0, r / maxf(profile.call(t), 0.05)) * lerpf(0.75, 1.0, t)
		c.color = c0.lerp(c1, rng.randf()) * ao
		# A branchlet from the trunk up to it where the foot of the column shows it.
		var ts := Vector3(0.0, maxf(q.y - r * 1.2, 0.3), 0.0)
		var tw := _bend(ts, ts.lerp(q, 0.5) + Vector3.UP * 0.1, q, 2)
		if t < 0.16:
			d.tubes.append(_tube(tw, _taper(tw, float(p.twig_r) * 1.5, float(p.twig_r) * 0.6), B_FIBRE, Color(0.24, 0.2, 0.15), 3))
		for j in int(p.leaves):
			var off := _rand_unit(rng) * c.r * 0.7 + out * c.r * 0.3
			var dir := (Vector3.UP * 1.0 + out * 0.35 + _rand_unit(rng) * 0.3).normalized()
			var side := dir.cross(out).normalized().rotated(dir, rng.randf_range(-0.5, 0.5))
			var face := side.cross(dir).normalized()
			if face.dot(out) < 0.0:
				face = -face
			var sz := rng.randf_range(0.8, 1.2)
			var lao := ao * rng.randf_range(0.85, 1.1)
			c.leaves.append([q + off - dir * float(p.leaf_len) * 0.4, dir, side, float(p.leaf_len) * sz, float(p.leaf_w) * sz, L_SCALE,
				c0.lerp(c1, rng.randf()) * lao, (face * 0.3 + out * 0.7).normalized(), 1, 0.0, rng.randf()])
		d.clusters.append(c)
	return d


## Agave: a rosette of thick grey-blue leaves, channelled on top and keeled below, the outer ones
## arching over and down. Built as solids (they keep their shape at every level, fewer segments).
static func _grow_agave(p: Dictionary, rng: RandomNumberGenerator) -> TreeData:
	var d := TreeData.new()
	d.leaf_len = 0.4
	d.cluster_r = 0.4
	d.crown = {"centre": Vector3(0.0, 0.5, 0.0), "radii": Vector3(1.1, 0.6, 1.1)}
	var n := rng.randi_range(24, 30)
	var colors: Array = p.leaf
	var golden := PI * (3.0 - sqrt(5.0))
	for i in n:
		var t := float(i) / float(n - 1)
		# Outer (old) leaves long and low; inner ones short and upright.
		var a := float(i) * golden + rng.randf_range(-0.1, 0.1)
		var elev := lerpf(0.32, 1.35, pow(t, 0.9)) + rng.randf_range(-0.08, 0.08)
		var len := lerpf(1.05, 0.45, t) * rng.randf_range(0.9, 1.08)
		var w := lerpf(0.14, 0.09, t)
		var col: Color = (colors[0] as Color).lerp(colors[1], rng.randf()) * lerpf(0.85, 1.0, t)
		d.solids.append(["agave", Vector3(0.0, 0.05 + 0.25 * t, 0.0), a, elev, len, w, col, bool(p.variegated), rng.randf(), lerpf(0.5, 0.05, t)])
	return d


## Yucca (several fibrous stems, branching, with dead leaves skirting each head) and dragon tree
## (one stout trunk branching in forks into an umbrella). Both end in rosettes of swords.
static func _grow_rosettes(p: Dictionary, rng: RandomNumberGenerator) -> TreeData:
	var d := TreeData.new()
	var H: float = p.height
	var stems: int = p.stems
	var branching: int = p.branching
	var bark: Color = p.bark
	var bk: int = p.bark_kind
	d.leaf_len = p.leaf_len
	d.cluster_r = float(p.leaf_len) * 0.8
	var tips: Array = []
	var ends: Array = []
	if stems == 1:
		# Dragon tree: trunk to 40 % then three levels of forks.
		var top := Vector3(0.0, H * 0.4, 0.0)
		var trunk := _bend(Vector3.ZERO, Vector3(0.05, H * 0.2, 0.0), top, 6)
		d.tubes.append(_tube(trunk, _taper(trunk, 0.24, 0.2, 0.5), bk, bark, 12))
		ends.append([top, Vector3.UP, 0.2, H * 0.16])
		for lvl in branching:
			var next: Array = []
			for e: Array in ends:
				var k := 2 + (1 if rng.randf() < 0.45 else 0)
				var a0 := rng.randf() * TAU
				for j in k:
					var a := a0 + TAU * float(j) / float(k)
					var dir := ((e[1] as Vector3) * 1.0 + Vector3(cos(a), 0.0, sin(a)) * 0.62).normalized()
					var len: float = float(e[3]) * rng.randf_range(0.8, 1.05)
					var s: Vector3 = e[0]
					var tip := s + dir * len
					var line := _bend(s, s + dir * len * 0.5 + Vector3.UP * len * 0.12, tip, 4)
					var r: float = float(e[2]) * (0.85 if lvl == 0 else 0.7)
					d.tubes.append(_tube(line, _taper(line, r, r * 0.85), bk, bark, _sides(r)))
					next.append([tip, (dir + Vector3.UP * 0.6).normalized(), r * 0.85, len * 0.78])
			ends = next
		for e: Array in ends:
			tips.append([e[0], e[1]])
	else:
		for k in stems:
			var a := TAU * float(k) / float(stems) + rng.randf_range(-0.5, 0.5)
			var tilt := rng.randf_range(0.12, 0.38)
			var len := H * rng.randf_range(0.5, 0.82)
			var dir := (Vector3.UP + Vector3(cos(a), 0.0, sin(a)) * tilt).normalized()
			var base := Vector3(cos(a), 0.0, sin(a)) * 0.12
			var tip := base + dir * len
			var line := _bend(base, base + dir * len * 0.5 + Vector3(cos(a), 0.0, sin(a)) * 0.1, tip, 8)
			d.tubes.append(_tube(line, _taper(line, 0.12, 0.08, 0.6), bk, bark, 9))
			if branching > 0 and rng.randf() < 0.6:
				var at := line[5]
				var bd := (dir + Vector3(-sin(a), 0.0, cos(a)) * 0.6).normalized()
				var bt := at + bd * len * 0.35
				var bl := _bend(at, at.lerp(bt, 0.5) + Vector3.UP * 0.1, bt, 3)
				d.tubes.append(_tube(bl, _taper(bl, 0.075, 0.06), bk, bark, 7))
				tips.append([bt, bd])
			tips.append([tip, dir])
	var colors: Array = p.leaf
	for tp: Array in tips:
		var c := Cluster.new()
		c.p = tp[0]
		c.out = (tp[1] as Vector3)
		c.r = d.cluster_r
		c.card_kind = L_SWORD
		c.style = 3
		c.color = (colors[0] as Color).lerp(colors[1], rng.randf())
		var n: int = p.rosette
		var golden := PI * (3.0 - sqrt(5.0))
		var up: Vector3 = tp[1]
		var ref := Vector3.RIGHT if absf(up.x) < 0.9 else Vector3.FORWARD
		var ax1 := up.cross(ref).normalized()
		var ax2 := up.cross(ax1)
		for i in n:
			var t := float(i) / float(n - 1)
			var a := float(i) * golden
			# Inner leaves upright, outer ones out and over.
			var elev := lerpf(1.45, -0.25 if p.dead else 0.15, pow(t, 0.8) * (1.0 - float(p.upright) * 0.3))
			var dir := (up * sin(elev) + (ax1 * cos(a) + ax2 * sin(a)) * cos(elev)).normalized()
			var side := dir.cross(up).normalized()
			if side.length_squared() < 0.01:
				side = ax1
			var face := side.cross(dir).normalized()
			var col: Color = (colors[0] as Color).lerp(colors[1], rng.randf()) * lerpf(0.75, 1.0, 1.0 - t * 0.5)
			var nrm := (face * 0.4 + dir * 0.3 + up * 0.5).normalized()
			c.leaves.append([c.p + dir * 0.02, dir, side, float(p.leaf_len) * rng.randf_range(0.8, 1.1), float(p.leaf_w) * 2.0, L_SWORD, col, nrm, 3,
				0.25 + 0.4 * t, rng.randf()])
		if p.dead:
			# The skirt of dead leaves hanging under the head.
			for i in 12:
				var a := rng.randf() * TAU
				var dir := (Vector3.DOWN * 0.9 + (ax1 * cos(a) + ax2 * sin(a)) * 0.35).normalized()
				var side := dir.cross(up).normalized()
				if side.length_squared() < 0.01:
					side = ax1
				var outv := (ax1 * cos(a) + ax2 * sin(a))
				c.leaves.append([c.p - up * 0.08 + outv * 0.04, dir, side, float(p.leaf_len) * 0.7, float(p.leaf_w) * 2.0, L_SWORD,
					Color(0.36, 0.29, 0.18) * rng.randf_range(0.8, 1.1), (outv + Vector3.UP * 0.2).normalized(), 2, 0.0, rng.randf()])
		d.clusters.append(c)
	var top := 0.0
	for tp: Array in tips:
		top = maxf(top, (tp[0] as Vector3).y)
	d.crown = {"centre": Vector3(0.0, top * 0.6, 0.0), "radii": Vector3(H * 0.35, top * 0.5, H * 0.35)}
	return d


## Bird of paradise: a clump of paddle leaves on long stalks and a few beaked flowers.
static func _grow_strelitzia(p: Dictionary, rng: RandomNumberGenerator) -> TreeData:
	var d := TreeData.new()
	d.leaf_len = 0.38
	d.cluster_r = 0.3
	d.crown = {"centre": Vector3(0.0, 0.8, 0.0), "radii": Vector3(0.7, 0.7, 0.7)}
	var colors: Array = p.leaf
	var c := Cluster.new()
	c.p = Vector3(0.0, 0.9, 0.0)
	c.out = Vector3.UP
	c.r = 0.5
	c.card_kind = L_PADDLE
	c.style = 3
	c.color = colors[0]
	var n := rng.randi_range(16, 22)
	for i in n:
		var a := rng.randf() * TAU
		var tilt := rng.randf_range(0.05, 0.42)
		var len := rng.randf_range(0.65, 1.0)
		var dir := (Vector3.UP + Vector3(cos(a), 0.0, sin(a)) * tilt).normalized()
		var base := Vector3(cos(a), 0.0, sin(a)) * rng.randf_range(0.02, 0.12)
		var tip := base + dir * len
		var stalk := _bend(base, base + dir * len * 0.5 + Vector3(cos(a), 0.0, sin(a)) * 0.03, tip, 3)
		d.tubes.append(_tube(stalk, _taper(stalk, 0.012, 0.008), B_STEM, Color(0.16, 0.22, 0.12), 4))
		# The blade carries on from the stalk, twisted to face out.
		var bdir := (dir + Vector3(cos(a), 0.0, sin(a)) * rng.randf_range(0.0, 0.6)).normalized()
		var side := bdir.cross(Vector3(cos(a), 0.0, sin(a))).normalized().rotated(bdir, rng.randf_range(-0.7, 0.7))
		if side.length_squared() < 0.01:
			side = Vector3(-sin(a), 0.0, cos(a))
		var face := side.cross(bdir).normalized()
		if face.dot(Vector3(cos(a), 0.3, sin(a))) < 0.0:
			face = -face
		var col: Color = (colors[0] as Color).lerp(colors[1], rng.randf())
		c.leaves.append([tip, bdir, side, rng.randf_range(0.32, 0.45), rng.randf_range(0.26, 0.32), L_PADDLE, col,
			(face * 0.6 + Vector3(cos(a), 0.4, sin(a)).normalized() * 0.4).normalized(), 4, 0.12, rng.randf()])
	d.clusters.append(c)
	# Flowers: a stalk to a horizontal green-purple beak with orange sepals standing off it.
	for i in rng.randi_range(3, 6):
		var a := rng.randf() * TAU
		var len := rng.randf_range(0.8, 1.15)
		var base := Vector3(cos(a), 0.0, sin(a)) * 0.08
		var tip := base + Vector3(cos(a) * 0.12, len, sin(a) * 0.12)
		var stalk := _bend(base, base.lerp(tip, 0.5), tip, 3)
		d.tubes.append(_tube(stalk, _taper(stalk, 0.01, 0.008), B_STEM, Color(0.18, 0.22, 0.13), 4))
		var head := Vector3(cos(a + 1.6), 0.15, sin(a + 1.6)).normalized()
		d.solids.append(["beak", tip, head, 0.17, rng.randf()])
	return d


# =================================================================================================
# Emitting a level
# =================================================================================================

class G:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var idx := PackedInt32Array()

	func vert(p: Vector3, nn: Vector3, col: Color, t: Vector2, t2: Vector2) -> int:
		v.append(p)
		n.append(nn)
		c.append(col)
		uv.append(t)
		uv2.append(t2)
		return v.size() - 1

	func tri(a: int, b: int, cc: int) -> void:
		idx.append(a)
		idx.append(b)
		idx.append(cc)

	func quad(a: int, b: int, cc: int, d: int) -> void:
		tri(a, b, cc)
		tri(a, cc, d)

	func arrays() -> Array:
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = v
		arr[Mesh.ARRAY_NORMAL] = n
		arr[Mesh.ARRAY_COLOR] = c
		arr[Mesh.ARRAY_TEX_UV] = uv
		arr[Mesh.ARRAY_TEX_UV2] = uv2
		arr[Mesh.ARRAY_INDEX] = idx
		return arr


static func _emit(d: TreeData, lv: Dictionary) -> Array:
	var g := G.new()
	for t in d.tubes:
		_emit_tube(g, t, lv)
	for c in d.clusters:
		_emit_cluster(g, c, lv)
	for s: Array in d.solids:
		_emit_solid(g, s, lv)
	return g.arrays()


static func _emit_tube(g: G, t: Tube, lv: Dictionary) -> void:
	if t.radii.size() < 2 or t.radii[0] < float(lv.min_r):
		return
	var sides := maxi(3, roundi(float(t.sides) * float(lv.sides)))
	# Every k-th ring, the ends kept.
	var step := maxi(1, roundi(1.0 / maxf(float(lv.seg), 0.05)))
	var rings: Array[int] = []
	for i in range(0, t.pts.size(), step):
		rings.append(i)
	if rings[-1] != t.pts.size() - 1:
		rings.append(t.pts.size() - 1)
	if rings.size() < 2:
		return
	var tang := (t.pts[1] - t.pts[0]).normalized()
	var ref := Vector3.RIGHT if absf(tang.x) < 0.9 else Vector3.FORWARD
	var nrm := tang.cross(ref).normalized()
	var circ := TAU * t.radii[0]
	var along := 0.0
	var prev_i := -1
	var prev_p := t.pts[0]
	for ri in rings.size():
		var i: int = rings[ri]
		var p := t.pts[i]
		var nt: Vector3
		if i < t.pts.size() - 1:
			nt = (t.pts[mini(i + 1, t.pts.size() - 1)] - t.pts[maxi(i - 1, 0)]).normalized()
		else:
			nt = (t.pts[i] - t.pts[i - 1]).normalized()
		# Parallel transport of the frame.
		nrm = (nrm - nt * nrm.dot(nt)).normalized()
		var bin := nt.cross(nrm)
		along += p.distance_to(prev_p)
		prev_p = p
		var base := g.v.size()
		var shade := t.color * lerpf(0.8, 1.0, clampf(p.y / 3.0, 0.0, 1.0))
		shade.a = 1.0
		for k in sides + 1:
			var a := TAU * float(k) / float(sides)
			var dir := nrm * cos(a) + bin * sin(a)
			g.vert(p + dir * t.radii[i], dir, shade, Vector2(float(k) / float(sides) * circ, along), Vector2(float(t.kind), 0.5))
		if prev_i >= 0:
			for k in sides:
				g.quad(prev_i + k, prev_i + k + 1, base + k + 1, base + k)
		prev_i = base


static func _leaf_quad(g: G, base: Vector3, dir: Vector3, side: Vector3, length: float, width: float, kind: int, col: Color, nrm: Vector3, segs: int, droop: float, rnd: float, style: int = 0) -> void:
	var start := g.v.size()
	var down := Vector3.DOWN
	for i in segs + 1:
		var t := float(i) / float(segs)
		var c := base + dir * length * t + down * droop * length * t * t
		var hw := width * 0.5
		g.vert(c - side * hw, nrm, col, Vector2(-1.0, t), Vector2(float(kind) + 0.25 * float(style), rnd))
		g.vert(c + side * hw, nrm, col, Vector2(1.0, t), Vector2(float(kind) + 0.25 * float(style), rnd))
	for i in segs:
		var a := start + i * 2
		g.quad(a, a + 1, a + 3, a + 2)


static func _emit_cluster(g: G, c: Cluster, lv: Dictionary) -> void:
	var stride: int = lv.stride
	if stride > 0:
		var n := c.leaves.size()
		var i := 0
		while i < n:
			var k := mini(stride, n - i)
			var pos := Vector3.ZERO
			var dir := Vector3.ZERO
			var area := 0.0
			for j in k:
				var l: Array = c.leaves[i + j]
				pos += l[0]
				dir += l[1]
				area += float(l[3]) * float(l[4])
			var l0: Array = c.leaves[i]
			pos /= float(k)
			dir = dir.normalized() if dir.length_squared() > 1e-4 else l0[1]
			var side: Vector3 = l0[2]
			side = (side - dir * side.dot(dir)).normalized()
			var f := sqrt(area / maxf(float(l0[3]) * float(l0[4]), 1e-6))
			var segs := mini(int(l0[8]), int(lv.leaf_segs))
			var nrm: Vector3 = l0[7]
			_leaf_quad(g, pos, dir, side, float(l0[3]) * f, float(l0[4]) * f, int(l0[5]), l0[6], nrm, segs, float(l0[9]), float(l0[10]), int(l0[11]) if l0.size() > 11 else 0)
			i += k
		return
	# Cluster cards: the cluster's leaf area on one or two cut cards, facing out.
	var cards: int = lv.cards
	var leaf_area := 0.0
	for l: Array in c.leaves:
		leaf_area += float(l[3]) * float(l[4])
	var half := c.r * (1.15 if cards == 2 else 1.35)
	var card_area := float(cards) * 4.0 * half * half
	var cover := clampf(leaf_area * 0.8 / card_area, 0.2, 0.92)
	var kind := c.card_kind
	var up := Vector3.UP if absf(c.out.y) < 0.95 else Vector3.FORWARD
	var s1 := c.out.cross(up).normalized()
	var u1 := s1.cross(c.out).normalized()
	for k in cards:
		var side := s1
		var dir := u1
		var face := c.out
		if k == 1:
			# The second card stands across the first, through the cluster's centre.
			side = c.out
			face = -s1
		var nrm := (face * 0.3 + c.out * 0.7).normalized()
		var rnd := fposmod(c.p.x * 1.7 + c.p.z * 2.3 + float(k) * 0.37, 1.0)
		if kind == L_SWORD or kind == L_PADDLE or kind == L_SCALE:
			# Rosettes and sprays keep their own leaf look, scaled up: two-thirds of the leaves.
			var nl := maxi(1, c.leaves.size() / (6 if cards == 2 else 12))
			for j in nl:
				var l: Array = c.leaves[(j * c.leaves.size()) / nl]
				var f := sqrt(float(c.leaves.size()) / float(nl) * 0.7)
				_leaf_quad(g, l[0], l[1], l[2], float(l[3]) * minf(f, 1.6), float(l[4]) * f, int(l[5]), l[6], l[7], 1, float(l[9]), float(l[10]))
			return
		var centre := c.p - dir * half
		var start := g.v.size()
		for row in 2:
			for col in 2:
				var pp := centre + dir * (2.0 * half * float(row)) + side * half * (float(col) * 2.0 - 1.0)
				g.vert(pp, nrm, c.color, Vector2(float(col) * 2.0 - 1.0, float(row)), Vector2(float(L_CLUSTER) + 0.25 * float(c.style), cover + floorf(rnd * 100.0)))
		g.quad(start, start + 1, start + 3, start + 2)


static func _emit_solid(g: G, s: Array, lv: Dictionary) -> void:
	var detail := 4 - int(lv.i)
	match String(s[0]):
		"strip":
			if int(lv.i) > 1:
				return
			var at: Vector3 = s[1]
			var out: Vector3 = s[2]
			var side := out.cross(Vector3.UP).normalized()
			var len: float = s[3]
			var w: float = s[4]
			var col: Color = s[5]
			var b := g.v.size()
			var curl := out * 0.05
			g.vert(at - side * w * 0.5, out, col, Vector2(0.0, 0.0), Vector2(float(B_STEM), 0.5))
			g.vert(at + side * w * 0.5, out, col, Vector2(w, 0.0), Vector2(float(B_STEM), 0.5))
			g.vert(at - side * w * 0.3 + Vector3.DOWN * len + curl, out, col * 0.9, Vector2(0.0, len), Vector2(float(B_STEM), 0.5))
			g.vert(at + side * w * 0.3 + Vector3.DOWN * len + curl, out, col * 0.9, Vector2(w, len), Vector2(float(B_STEM), 0.5))
			g.quad(b, b + 1, b + 3, b + 2)
		"flower":
			var at: Vector3 = s[1]
			var up: Vector3 = s[2]
			var size: float = s[3]
			var rnd: float = s[4]
			var col: Color = s[5]
			var cards := 2 if int(lv.i) <= 1 else 1
			for k in cards:
				var side := up.cross(Vector3.RIGHT.rotated(Vector3.UP, rnd * TAU + float(k) * PI * 0.5)).normalized()
				var face := side.cross(up)
				_leaf_quad(g, at - up * size * 0.3, up, side, size, size * 0.8, L_FLOWER, col, (face * 0.3 + up * 0.7).normalized(), 1, 0.0, rnd)
		"beak":
			var at: Vector3 = s[1]
			var head: Vector3 = s[2]
			var len: float = s[3]
			var rnd: float = s[4]
			# The spathe: a tapering beak.
			var pts := PackedVector3Array([at, at + head * len * 0.5 + Vector3.UP * 0.01, at + head * len])
			var t := _tube(pts, PackedFloat32Array([0.018, 0.016, 0.002]), B_STEM, Color(0.16, 0.20, 0.10), 5)
			_emit_tube(g, t, lv)
			# The orange sepals and the blue tongue standing up and forward off it.
			var side := head.cross(Vector3.UP).normalized()
			var sepals := 3 if detail > 1 else 2
			for k in sepals:
				var dir := (Vector3.UP * 1.0 + head * (0.3 + 0.25 * float(k)) + side * (float(k) - 1.0) * 0.25).normalized()
				var sd := dir.cross(head).normalized()
				_leaf_quad(g, at + head * len * 0.35, dir, sd, 0.11, 0.035, L_FLOWER, Color(1.0, 0.36, 0.03), (side * 0.3 + Vector3.UP * 0.7).normalized(), 1, 0.0, rnd, 1)
			_leaf_quad(g, at + head * len * 0.4, (Vector3.UP + head * 0.9).normalized(), side, 0.08, 0.025, L_FLOWER, Color(0.10, 0.12, 0.55), Vector3.UP, 1, 0.0, rnd, 1)
		"agave":
			_agave_leaf(g, s, detail)


## One agave leaf: a V-channelled top and a keeled underside along an arching spine, tapering to
## a dark terminal spine.
static func _agave_leaf(g: G, s: Array, detail: int) -> void:
	var at: Vector3 = s[1]
	var a: float = s[2]
	var elev: float = s[3]
	var len: float = s[4]
	var w: float = s[5]
	var col: Color = s[6]
	var varieg: bool = s[7]
	var rnd: float = s[8]
	var curl: float = s[9]
	var segs: int = [8, 5, 3, 2, 2][clampi(4 - detail, 0, 4)]
	var out := Vector3(cos(a), 0.0, sin(a))
	var side := Vector3(-sin(a), 0.0, cos(a))
	var kind := L_SUCC_VAR if varieg else L_SUCC
	var prev := -1
	for i in segs + 1:
		var t := float(i) / float(segs)
		# Rises at `elev`, then arches over by `curl` toward the tip.
		var ang := elev - curl * t * t * 2.2
		var dir := out * cos(ang) + Vector3.UP * sin(ang)
		var spine := at + (out * (cos(elev) * t - curl * 0.35 * t * t * t) + Vector3.UP * (sin(elev) * t - curl * 0.6 * t * t)) * len
		var up := dir.cross(side).normalized() * -1.0
		if up.y < 0.0:
			up = -up
		var hw := w * (0.55 + 0.45 * sin(PI * minf(t * 1.6, 1.0) * 0.5)) * (1.0 - smoothstep(0.55, 1.0, t)) + 0.004
		var th := hw * 0.45
		var b := g.v.size()
		var c2 := col
		# Four verts a ring: edges, the channel's floor, the keel.
		g.vert(spine - side * hw, (up - side * 0.6).normalized(), c2, Vector2(-1.0, t), Vector2(float(kind), rnd))
		g.vert(spine + up * th * 0.15, up, c2, Vector2(0.0, t), Vector2(float(kind), rnd))
		g.vert(spine + side * hw, (up + side * 0.6).normalized(), c2, Vector2(1.0, t), Vector2(float(kind), rnd))
		g.vert(spine - up * th, -up, c2 * 0.85, Vector2(0.0, t), Vector2(float(kind), rnd))
		if prev >= 0:
			g.quad(prev, prev + 1, b + 1, b)
			g.quad(prev + 1, prev + 2, b + 2, b + 1)
			g.quad(prev + 2, prev + 3, b + 3, b + 2)
			g.quad(prev + 3, prev, b, b + 3)
		prev = b


## Each level's edge in metres: what merging leaves, carding clusters and dropping twigs moves.
static func _edges(d: TreeData) -> Array:
	var ll := d.leaf_len
	var cr := d.cluster_r
	var e1 := ll * 0.7
	var e2 := maxf(ll * 1.5, e1 * 1.4)
	var e3 := maxf(cr * 0.9, e2 * 1.3)
	var e4 := maxf(cr * 1.8, e3 * 1.6)
	return [0.0, e1, e2, e3, e4]


## Levels `first`.. as one mesh: one vertex buffer, `first`'s triangles the base, the coarser
## ones its LODs at their edges, and the counter's copy last.
static func _ladder(levels: Array, edges: Array, first: int) -> ArrayMesh:
	var arrays: Array = (levels[first] as Array).duplicate(true)
	var lods := {}
	var offset: int = (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	var last := PackedInt32Array()
	for l in range(first + 1, levels.size()):
		var src: Array = levels[l]
		for slot in Mesh.ARRAY_MAX:
			if slot == Mesh.ARRAY_INDEX or arrays[slot] == null:
				continue
			arrays[slot].append_array(src[slot])
		var idx: PackedInt32Array = (src[Mesh.ARRAY_INDEX] as PackedInt32Array).duplicate()
		for i in idx.size():
			idx[i] += offset
		lods[float(edges[l])] = idx
		last = idx
		offset += (src[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	if last.size() > 6:
		lods[COUNTER_EDGE] = last.slice(0, last.size() - 3)
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], lods)
	return m
