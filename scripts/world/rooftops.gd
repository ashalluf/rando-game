class_name Rooftops
extends RefCounted
## Tower roofs (owner, 2026-10-05: "tower roofs are what the player sees most while flying - make
## them real"). On top of the roof plant Building already lays (units, ducts, bulkheads, tanks,
## spires, antennas - Building._build_roof_props()), a tall building's highest roof gets what
## real Los Angeles towers carry:
##   - a HELIPAD: the old fire code gave nearly every flat-topped high-rise one. A raised steel
##     deck over the plant (the plant stays under it), the touchdown paint (perimeter line, dashed
##     aiming line, the yellow circle, the H, the weight box), green perimeter lights and floods
##     lit after dark, a safety-net shelf round the edge, a windsock, the access stair, and on
##     some a parked helicopter in a private livery;
##   - a POOL DECK (hotels and apartment towers): a raised deck in timber or porcelain round a
##     traced pool (shaders/rooftop.gdshader K_WATER: the tank, its tiles, caustics, the sky by
##     Fresnel, the underwater lights at night), loungers and umbrellas, a glass balustrade, a
##     cabana bar with its lit sign, string lights and potted palms;
##   - or a ROOF GARDEN: pavers, a lawn, planter boxes of shrubs, a pergola with benches and
##     string lights;
##   - a MECHANICAL PENTHOUSE with louvred screens, a TELECOM MAST (sector panels, microwave
##     dishes, a beacon) and on glass towers a WINDOW-WASHING MACHINE on its rails with its jib
##     over the parapet, the cradle parked beside it or hanging part-way down the facade.
## Every roll is a hash of the building's seed (salt "rooftops"), never Building._rng or its
## _roof_rng, and the plan reads the plant Building placed (roof_props) and the parts only, so
## the near building (generate()) and the far boxes (FarBuilding.boxes() after roof_plan()) plan
## the same roof. Pieces stand where the plant is not: the kit's own roof plant is handed the
## pieces' rects to keep off (Building._kit_roof_plant(), its private stream), and a helipad
## stands over the plant on columns that skip whatever stands under them.
##
## Drawn as ONE mesh per building on shaders/rooftop.gdshader (+ a glass surface for the
## balustrades), a MultiMesh per planting kind, the helicopter as its model; collision on the
## building's own body. The far tiers get boxes (far_boxes(); FarBuilding.Plant.HELIPAD and POOL
## are painted by building_lod.gdshader). ROOFTOPS=0 in the environment turns it all off (the A/B).

static var enabled: bool = OS.get_environment("ROOFTOPS") != "0"

const SALT := "rooftops"
## The tallest pieces of the existing plant: a raised pad must not stand over them. (A plain
## antenna mast where the pad goes is taken down instead: hidden().)
const TALL_PLANT := ["spire", "water_tower"]
## Plant a piece may stand in place of (it is cleared from under a pool deck, a garden, a
## penthouse, a mast or a washing machine, near and far alike: clear_plant(), hidden()). Its rolls
## are still made - nothing on the roof moves - it is just not drawn. The rest of the plant (stair
## bulkheads, tanks, cooling towers, signs, masts) is never covered.
const HIDEABLE := ["ac", "ducts", "solar", "skylight"]

## Helipads: on buildings at least this tall (m), this share of them; deck sizes (m), how high
## the deck stands over the roof, how far the safety-net shelf reaches beyond it.
const PAD_MIN_HEIGHT := 75.0
const PAD_SHARE := 0.8
const PAD_SIZE := Vector2(14.0, 21.0)
## The smallest deck a pad shrinks to on a slender tower.
const PAD_MIN := 11.0
const PAD_RISE := 3.4
const PAD_NET := 1.5
## Share of pads with a helicopter parked on them.
const HELI_SHARE := 0.32
## Pool decks and gardens: heights (m) and shares (a building rolls a pool first, then a garden).
const POOL_HEIGHTS := Vector2(26.0, 230.0)
const POOL_SHARE := 0.3
const GARDEN_HEIGHTS := Vector2(18.0, 160.0)
const GARDEN_SHARE := 0.3
## How high a pool deck stands over the roof (on pedestals; the tank reaches down to the slab).
const DECK_RISE := 0.95
## The strip along a pool deck's +z side the steps come up from (part of its zone).
const STEP_STRIP := 1.2
## Mechanical penthouses, telecom masts, window-washing machines.
const PENT_MIN_HEIGHT := 38.0
const PENT_SHARE := 0.45
const MAST_MIN_HEIGHT := 55.0
const MAST_SHARE := 0.35
const BMU_MIN_HEIGHT := 45.0
const BMU_SHARE := 0.75
## Share of window-washing machines with the cradle out on the facade.
const BMU_HANG_SHARE := 0.45
## Past this the near pieces stop drawing (the far boxes carry them from the LOD ring out).
const DRAW_DISTANCE := 650.0

## The invented rooftop bars (never a real venue's name).
const BAR_NAMES := ["LAST LIGHT", "AZOTEA", "SOLANA", "THE LOOKOUT", "MIRADOR", "SUNDOWNER", "HIGH TIDE", "CIELO"]
## Helicopter liveries (upper, lower, stripe): invented operators' private colourways.
const HELI_LIVERIES := [
	[Color(0.90, 0.90, 0.91), Color(0.09, 0.11, 0.16), Color(0.72, 0.56, 0.22)],
	[Color(0.06, 0.07, 0.08), Color(0.30, 0.31, 0.33), Color(0.80, 0.12, 0.08)],
	[Color(0.88, 0.88, 0.86), Color(0.70, 0.71, 0.72), Color(0.08, 0.30, 0.55)],
	[Color(0.14, 0.24, 0.20), Color(0.86, 0.85, 0.80), Color(0.86, 0.85, 0.80)],
]
## Umbrella and cushion cloths, deck finishes (sRGB as written).
const CANVAS := [Color(0.86, 0.83, 0.74), Color(0.12, 0.17, 0.28), Color(0.66, 0.33, 0.22), Color(0.52, 0.58, 0.46),
	Color(0.92, 0.91, 0.88), Color(0.86, 0.68, 0.36)]
const DECK_WOOD := Color(0.56, 0.42, 0.30)
const DECK_TILES := [Color(0.80, 0.77, 0.71), Color(0.46, 0.45, 0.43), Color(0.72, 0.70, 0.66)]

## Colours of the kit's materials.
const STEEL := Color(0.46, 0.48, 0.50)
const DARK_STEEL := Color(0.20, 0.21, 0.22)
const PAD_DECK := Color(0.33, 0.35, 0.35)
const SAFETY_YELLOW := Color(0.86, 0.64, 0.10)
const WHITE_PAINT := Color(0.88, 0.88, 0.86)
const CONCRETE := Color(0.66, 0.65, 0.62)
const PENT_METAL := [Color(0.62, 0.63, 0.63), Color(0.50, 0.52, 0.53), Color(0.74, 0.72, 0.68)]

## The air traffic's helicopter (Helicopter.MODEL; named by path: Helicopter needs the autoloads).
const HELI_MODEL := "res://assets/models/helicopter.glb"

static var _glass_material: StandardMaterial3D = null
static var _material: ShaderMaterial = null
static var _heli_scene: PackedScene = null


# --- The plan ------------------------------------------------------------------------------

static func _h(b: Building, tag: String, i: int = 0) -> float:
	return float(absi(hash([b.seed, SALT, tag, i])) % 100003) / 100003.0


## The part whose roof the pieces go on: the highest that is not a podium (-1 for none).
static func top_part(b: Building) -> int:
	var best := -1
	var top := -INF
	for i in b.parts.size():
		var part: Dictionary = b.parts[i]
		if int(part.get("podium", 0)) > 0:
			continue
		var t: float = part.center.y + part.size.y * 0.5
		if t > top + 0.01:
			top = t
			best = i
	return best


## What goes on `b`'s top roof: {"part", "c" (the part's centre), "size", "top" (roof height),
## "feats": [{"kind", "at" (Vector2 from the part's centre), "size" (Vector2, x and z), ...}]},
## or {} for nothing. Pure: the parts, the plant on that roof (b.roof_props) and hashes.
static func plan(b: Building) -> Dictionary:
	if not enabled or b.shape == Building.Shape.WAREHOUSE or b.height < GARDEN_HEIGHTS.x:
		return {}
	var ti := top_part(b)
	if ti < 0:
		return {}
	var part: Dictionary = b.parts[ti]
	var size: Vector3 = part.size
	var c: Vector3 = part.center
	var top: float = c.y + size.y * 0.5
	var inset := 2.8 if b._chamfered else 1.2
	var half := Vector2(size.x * 0.5 - inset, size.z * 0.5 - inset)
	if half.x < 3.0 or half.y < 3.0:
		return {}
	# The plant on this roof, as rects from the part's centre.
	var low: Array[Rect2] = []
	var keep: Array[Rect2] = []
	var tall: Array[Rect2] = []
	for prop: Array in b.roof_props:
		if int(prop[3]) != ti:
			continue
		var kind: String = prop[0]
		var at: Vector3 = prop[1]
		var fp: Vector2 = b._prop_footprint(kind)
		if kind == "billboard":
			fp = Vector2(7.0, 7.0)
		var r := Rect2(Vector2(at.x - c.x, at.z - c.z) - fp * 0.5, fp).grow(0.4)
		low.append(r)
		if not HIDEABLE.has(kind):
			keep.append(r)
		if TALL_PLANT.has(kind):
			tall.append(r)
	var feats: Array = []
	var taken: Array[Rect2] = []
	var h := b.height
	var glass := b.finish == Building.Finish.GLASS or b.window_style == Building.WindowStyle.CURTAIN
	# 1. The helipad, raised over the plant: only the tall plant is in its way.
	if h >= PAD_MIN_HEIGHT and _h(b, "pad") < PAD_SHARE:
		var deck := floorf(lerpf(PAD_SIZE.x, PAD_SIZE.y, _h(b, "pad size")))
		# The deck and its net shelf inside the roof's whole outline (the net may reach over the
		# plant strip by the parapet, not past it).
		var full := Vector2(size.x * 0.5 - 0.3, size.z * 0.5 - 0.3)
		var foot := deck + PAD_NET * 2.0
		while deck >= PAD_MIN and (foot > full.x * 2.0 or foot > full.y * 2.0):
			deck -= 1.0
			foot = deck + PAD_NET * 2.0
		if deck >= PAD_MIN:
			var spot = _fit_centre(Vector2(foot, foot), full, tall)
			if spot != null:
				var pad_rect := Rect2(spot - Vector2(foot, foot) * 0.5, Vector2(foot, foot))
				var f := {"kind": "helipad", "at": spot, "size": Vector2(foot, foot), "deck": deck,
					"turn": int(_h(b, "pad turn") * 4.0) % 4, "heli": _h(b, "heli") < HELI_SHARE,
					"livery": int(_h(b, "heli livery") * HELI_LIVERIES.size()) % HELI_LIVERIES.size(),
					"sock": int(_h(b, "sock") * 4.0) % 4}
				# The stair up to the deck: along the first side (from a hashed start) whose strip
				# under the shelf is clear of the plant, else a caged ladder.
				f.stair = -1
				var s0 := int(_h(b, "stair") * 4.0) % 4
				for k in 4:
					var side := (s0 + k) % 4
					var sr := _stair_rect(spot, deck, side)
					if _clear(sr, low) and _inside(sr, full):
						f.stair = side
						break
				feats.append(f)
				taken.append(pad_rect)
	# Everything else stands in place of the small plant (hidden()), never on the rest.
	var blocked: Array[Rect2] = keep.duplicate()
	blocked.append_array(taken)
	# 2. A pool deck, else a roof garden (never under the pad).
	var has_pad := not feats.is_empty()
	if not has_pad and h >= POOL_HEIGHTS.x and h <= POOL_HEIGHTS.y and _h(b, "pool") < POOL_SHARE:
		var length := floorf(lerpf(8.0, 14.0, _h(b, "pool len")))
		var width := snappedf(lerpf(3.6, 5.6, _h(b, "pool wid")), 0.2)
		while length >= 6.0:
			var zone := Vector2(length + 1.2 + 3.4, width + 1.2 + 2.6 + STEP_STRIP)
			var got = _fit_any(b, "pool spot", zone, half, blocked)
			if got != null:
				var f := {"kind": "pool", "at": got[0], "size": got[1], "swap": got[2], "len": length, "wid": width,
					"wood": _h(b, "pool deck") < 0.45, "tile": int(_h(b, "pool tile") * 3.0) % 3,
					"canvas": int(_h(b, "pool canvas") * CANVAS.size()) % CANVAS.size(),
					"bar": int(_h(b, "bar name") * BAR_NAMES.size()) % BAR_NAMES.size(), "flip": _h(b, "pool flip") < 0.5}
				feats.append(f)
				blocked.append(Rect2(got[0] - got[1] * 0.5, got[1]))
				break
			length -= 2.0
	if true:
		if not has_pad and not _has(feats, "pool") and h >= GARDEN_HEIGHTS.x and h <= GARDEN_HEIGHTS.y and _h(b, "garden") < GARDEN_SHARE:
			var zone := Vector2(floorf(lerpf(7.0, 12.0, _h(b, "garden len"))), floorf(lerpf(5.0, 8.0, _h(b, "garden wid"))))
			var got = _fit_any(b, "garden spot", zone, half, blocked)
			if got == null:
				got = _fit_any(b, "garden spot2", zone * 0.75, half, blocked)
			if got != null:
				feats.append({"kind": "garden", "at": got[0], "size": got[1], "swap": got[2],
					"flip": _h(b, "garden flip") < 0.5, "tile": int(_h(b, "garden tile") * 3.0) % 3})
				blocked.append(Rect2(got[0] - got[1] * 0.5, got[1]))
	# 3. A mechanical penthouse with louvred screens.
	if h >= PENT_MIN_HEIGHT and _h(b, "pent") < PENT_SHARE:
		var zone := Vector2(floorf(lerpf(5.0, 9.0, _h(b, "pent len"))), floorf(lerpf(4.0, 6.0, _h(b, "pent wid"))))
		var got = _fit_any(b, "pent spot", zone, half, blocked)
		if got != null:
			feats.append({"kind": "penthouse", "at": got[0], "size": got[1], "swap": got[2],
				"tall": lerpf(3.4, 4.6, _h(b, "pent tall")), "paint": int(_h(b, "pent paint") * 3.0) % 3})
			blocked.append(Rect2(got[0] - got[1] * 0.5, got[1]))
	# 4. A telecom mast.
	if h >= MAST_MIN_HEIGHT and _h(b, "mast") < MAST_SHARE:
		var got = _fit_any(b, "mast spot", Vector2(2.6, 2.6), half, blocked)
		if got != null:
			feats.append({"kind": "mast", "at": got[0], "size": got[1], "h": lerpf(9.0, 18.0, _h(b, "mast h")),
				"yaw": _h(b, "mast yaw") * TAU, "dishes": 1 + int(_h(b, "mast dishes") * 3.0) % 3})
			blocked.append(Rect2(got[0] - got[1] * 0.5, got[1]))
	# 5. The window-washing machine on a glass tower, on its rails along an edge.
	if glass and h >= BMU_MIN_HEIGHT and _h(b, "bmu") < BMU_SHARE:
		var got = _fit_edge(b, Vector2(6.4, 3.0), half, blocked)
		if got != null:
			var f := {"kind": "bmu", "at": got[0], "size": got[1], "side": got[2],
				"hang": _h(b, "bmu hang") < BMU_HANG_SHARE, "drop": lerpf(0.18, 0.7, _h(b, "bmu drop"))}
			# How far the facade is beyond the machine's outer side, and how far down the cradle hangs.
			var nrm := _side_normal(got[2])
			var out := absf(nrm.x) * (size.x * 0.5) + absf(nrm.y) * (size.z * 0.5)
			var along_edge: float = (got[0] as Vector2).dot(nrm)
			f.reach = out - along_edge
			f.depth = clampf(f.drop * size.y, 6.0, maxf(size.y - 4.0, 6.0))
			feats.append(f)
			blocked.append(Rect2(got[0] - got[1] * 0.5, got[1]))
	if feats.is_empty():
		return {}
	return {"part": ti, "c": c, "size": size, "top": top, "feats": feats, "rise": b.parapet_rise(part)}


static func _has(feats: Array, kind: String) -> bool:
	for f: Dictionary in feats:
		if f.kind == kind:
			return true
	return false


static func _clear(r: Rect2, blocked: Array[Rect2]) -> bool:
	for o in blocked:
		if r.intersects(o):
			return false
	return true


static func _inside(r: Rect2, half: Vector2) -> bool:
	return r.position.x >= -half.x - 0.01 and r.position.y >= -half.y - 0.01 and r.end.x <= half.x + 0.01 and r.end.y <= half.y + 0.01


## The free spot nearest the roof's centre for a rect of `size` inside +-`half` (1 m grid), or null.
static func _fit_centre(size: Vector2, half: Vector2, blocked: Array[Rect2]):
	var room := half - size * 0.5
	if room.x < 0.0 or room.y < 0.0:
		return null
	var best = null
	var best_d := INF
	var nx := int(floorf(room.x))
	var nz := int(floorf(room.y))
	for ix in range(-nx, nx + 1):
		for iz in range(-nz, nz + 1):
			var p := Vector2(ix, iz)
			var d := p.length_squared()
			if d >= best_d:
				continue
			if _clear(Rect2(p - size * 0.5, size), blocked):
				best = p
				best_d = d
	return best


## A free spot for a rect of `size` (either way round) inside +-`half`: candidates on a grid
## visited in a hashed order (a permutation), the first that is clear. [centre, size as placed,
## swapped] or null.
static func _fit_any(b: Building, tag: String, size: Vector2, half: Vector2, blocked: Array[Rect2]):
	var flip := _h(b, tag + " turn") < 0.5
	for k in 2:
		var s := size if (k == 0) != flip else Vector2(size.y, size.x)
		var room := half - s * 0.5
		if room.x < 0.0 or room.y < 0.0:
			continue
		var step := clampf(minf(s.x, s.y) * 0.3, 1.0, 3.0)
		var nx := int(floorf(room.x * 2.0 / step)) + 1
		var nz := int(floorf(room.y * 2.0 / step)) + 1
		var count := nx * nz
		var start := absi(hash([b.seed, SALT, tag, k])) % count
		var stride := _coprime(count, absi(hash([b.seed, SALT, tag, "stride"])) % 97 + 31)
		for j in count:
			var cell := (start + j * stride) % count
			var p := Vector2(-room.x + float(cell % nx) * step, -room.y + float(cell / nx) * step)
			p.x = minf(p.x, room.x)
			p.y = minf(p.y, room.y)
			if _clear(Rect2(p - s * 0.5, s), blocked):
				return [p, s, s != size]
	return null


static func _coprime(n: int, s: int) -> int:
	var k := maxi(s, 1)
	while _gcd(n, k) != 1:
		k += 1
	return k


static func _gcd(a: int, b: int) -> int:
	while b != 0:
		var t := a % b
		a = b
		b = t
	return a


## Outward normal of a roof side: 0 +X, 1 +Z, 2 -X, 3 -Z (as a Vector2 in x, z).
static func _side_normal(side: int) -> Vector2:
	return [Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0), Vector2(0, -1)][side]


## A rect along one of the four sides, its outer edge on the area's edge. [centre, size, side].
static func _fit_edge(b: Building, size: Vector2, half: Vector2, blocked: Array[Rect2]):
	var s0 := int(_h(b, "bmu side") * 4.0) % 4
	for k in 4:
		var side := (s0 + k) % 4
		var nrm := _side_normal(side)
		var s := Vector2(size.x, size.y) if nrm.x == 0.0 else Vector2(size.y, size.x)
		var room := half - s * 0.5
		if room.x < 0.0 or room.y < 0.0:
			continue
		var along_room := room.x if nrm.x == 0.0 else room.y
		var n_steps := int(floorf(along_room * 2.0)) + 1
		var start := absi(hash([b.seed, SALT, "bmu along", side])) % n_steps
		for j in n_steps:
			var t := -along_room + float((start + j) % n_steps) * 0.5
			var p := Vector2(t, nrm.y * room.y) if nrm.x == 0.0 else Vector2(nrm.x * room.x, t)
			if _clear(Rect2(p - s * 0.5, s), blocked):
				return [p, s, side]
	return null


## The strip under the pad's shelf the stair stands in, on `side` (pad-centred).
static func _stair_rect(spot: Vector2, deck: float, side: int) -> Rect2:
	var nrm := _side_normal(side)
	var along := Vector2(-nrm.y, nrm.x)
	var centre := spot + nrm * (deck * 0.5 + 0.7) + along * (deck * 0.5 - 3.25)
	var ext := along.abs() * 4.7 + nrm.abs() * 1.3
	return Rect2(centre - ext * 0.5, ext)


## The kit's roof plant on part `part_index` keeps off these rects (from the part's centre).
## Building._kit_roof_plant() calls it with the plant of that part already placed.
static func keep_out(b: Building, part_index: int) -> Array[Rect2]:
	var out: Array[Rect2] = []
	if part_index != top_part(b):
		return out
	var p := plan(b)
	b.set_meta("rooftops_plan", p)
	if p.is_empty():
		return out
	for f: Dictionary in p.feats:
		out.append(Rect2(f.at - f.size * 0.5, f.size).grow(0.3))
	return out


## Which of `b`'s roof props (indices into roof_props) the pieces of plan `p` stand in place of:
## the small plant (HIDEABLE) on the top roof whose footprint reaches a piece on the roof (not the
## raised pad, whose columns step round what is under it).
static func hidden(b: Building, p: Dictionary) -> Dictionary:
	var out := {}
	if p.is_empty():
		return out
	var c: Vector3 = p.c
	var zones: Array[Rect2] = []
	var pads: Array[Rect2] = []
	for f: Dictionary in p.feats:
		var r := Rect2(f.at - f.size * 0.5, f.size).grow(0.2)
		if f.kind == "helipad":
			pads.append(r)
		else:
			zones.append(r)
	for i in b.roof_props.size():
		var prop: Array = b.roof_props[i]
		if int(prop[3]) != int(p.part):
			continue
		var kind: String = prop[0]
		var small := HIDEABLE.has(kind)
		if not small and kind != "antenna":
			continue
		var at: Vector3 = prop[1]
		var fp: Vector2 = b._prop_footprint(kind)
		if kind == "ducts":
			fp = Vector2(7.6, 7.6)
		var r := Rect2(Vector2(at.x - c.x, at.z - c.z) - fp * 0.5, fp)
		for z in (zones if small else zones + pads):
			if r.intersects(z):
				out[i] = true
				break
	return out


## Takes the plant the pieces stand in place of off a generating Building (after its
## _build_roof_props(), before _commit_roof()): its primitives (each prop's range in _roof_prims
## starts at its rolls.prims), its air-conditioning units and their collision. No roll is undone.
static func clear_plant(b: Building) -> void:
	if not enabled:
		return
	var p: Dictionary
	if b.has_meta("rooftops_plan"):
		p = b.get_meta("rooftops_plan")
	else:
		p = plan(b)
		b.set_meta("rooftops_plan", p)
	var hide := hidden(b, p)
	if hide.is_empty():
		return
	var drop := {}
	var unit_drop := {false: {}, true: {}}
	var spot_drop := {}
	var unit_k := {false: 0, true: 0}
	var spot_k := 0
	var shapes: Array[Vector3] = []
	for i in b.roof_props.size():
		var prop: Array = b.roof_props[i]
		var rolls: Dictionary = prop[2]
		var is_ac: bool = prop[0] == "ac"
		var rusted: bool = rolls.get("rusted", false)
		if hide.has(i):
			var start: int = rolls.get("prims", -1)
			var end := b._roof_prims.size()
			for j in range(i + 1, b.roof_props.size()):
				var nxt: int = (b.roof_props[j][2] as Dictionary).get("prims", -1)
				if nxt >= 0:
					end = nxt
					break
			if start >= 0:
				for k in range(start, end):
					drop[k] = true
			if is_ac:
				unit_drop[rusted][unit_k[rusted]] = true
				spot_drop[spot_k] = true
				shapes.append((prop[1] as Vector3) + Vector3(0.0, 0.8, 0.0))
		if is_ac:
			unit_k[rusted] += 1
			spot_k += 1
	if not drop.is_empty():
		var kept: Array = []
		for k in b._roof_prims.size():
			if not drop.has(k):
				kept.append(b._roof_prims[k])
		b._roof_prims = kept
	for rusted: bool in [false, true]:
		if b._roof_units.has(rusted) and not (unit_drop[rusted] as Dictionary).is_empty():
			var kept_u: Array = []
			var list: Array = b._roof_units[rusted]
			for k in list.size():
				if not unit_drop[rusted].has(k):
					kept_u.append(list[k])
			if kept_u.is_empty():
				b._roof_units.erase(rusted)
			else:
				b._roof_units[rusted] = kept_u
	if not spot_drop.is_empty():
		var kept_s: Array[Vector3] = []
		for k in b.roof_unit_spots.size():
			if not spot_drop.has(k):
				kept_s.append(b.roof_unit_spots[k])
		b.roof_unit_spots = kept_s
	for child in b.get_children():
		var cs := child as CollisionShape3D
		if cs == null:
			continue
		for at in shapes:
			if cs.position.distance_squared_to(at) < 0.0025:
				b.remove_child(cs)
				cs.queue_free()
				break


# --- Near: the pieces built -----------------------------------------------------------------

## Builds the rooftop pieces onto `b` (after its roof plant). Called from Building.generate().
static func build(b: Building) -> void:
	if not enabled:
		return
	var p: Dictionary
	if b.has_meta("rooftops_plan"):
		p = b.get_meta("rooftops_plan")
		b.remove_meta("rooftops_plan")
	else:
		p = plan(b)
	if p.is_empty():
		return
	var g := RooftopGeo.new()
	var glass := RooftopGeo.new()
	var plants := {}  # mesh key -> [Mesh, [Transform3D]]
	var c: Vector3 = p.c
	var top: float = p.top
	for f: Dictionary in p.feats:
		var at2: Vector2 = f.at
		var origin := Vector3(c.x + at2.x, top, c.z + at2.y)
		match f.kind:
			"helipad":
				_helipad(b, g, f, origin, p, plants)
			"pool":
				_pool(b, g, glass, f, origin, plants)
			"garden":
				_garden(b, g, f, origin, plants)
			"penthouse":
				_penthouse(b, g, f, origin)
			"mast":
				_mast(g, f, origin)
			"bmu":
				_bmu(g, f, origin, p)
	var mesh := ArrayMesh.new()
	var arr := g.arrays()
	if not arr.is_empty():
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		mesh.surface_set_material(mesh.get_surface_count() - 1, material())
	var garr := glass.arrays()
	if not garr.is_empty():
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, garr)
		mesh.surface_set_material(mesh.get_surface_count() - 1, glass_material())
	if mesh.get_surface_count() > 0:
		var node := MeshInstance3D.new()
		node.name = "Rooftop"
		node.mesh = mesh
		node.visibility_range_end = DRAW_DISTANCE
		node.visibility_range_end_margin = 40.0
		node.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		b.add_child(node)
	if not plants.is_empty():
		var batch := MultiMeshBatch.new()
		for key: String in plants:
			var entry: Array = plants[key]
			for xf: Transform3D in entry[1]:
				# Neutral tint and per-instance variety (foliage_tex.gdshader reads both).
				batch.add(key, entry[0], xf, Color(1.0, 1.0, 1.0), Color(0.3, 0.5, 0.5, 0.0))
			batch.set_draw_distance(key, 260.0)
		var holder := Node3D.new()
		holder.name = "RoofPlanting"
		b.add_child(holder)
		batch.build(holder)
	b.set_meta("rooftops_tris", g.tri_count() + glass.tri_count())
	b.set_meta("rooftops", p)


static func material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = load("res://shaders/rooftop.gdshader")
	return _material


static func glass_material() -> StandardMaterial3D:
	if _glass_material == null:
		var m := StandardMaterial3D.new()
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color = Color(0.62, 0.74, 0.74, 0.22)
		m.roughness = 0.06
		m.metallic_specular = 0.7
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_glass_material = m
	return _glass_material


static func _box_shape(b: Building, size: Vector3, at: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	cs.position = at
	b.add_child(cs)


static func _add_plant(plants: Dictionary, key: String, mesh: Mesh, xf: Transform3D) -> void:
	if mesh == null:
		return
	if not plants.has(key):
		plants[key] = [mesh, []]
	(plants[key][1] as Array).append(xf)


## Transform turning a feature's frame by quarter turns about its origin.
static func _frame(origin: Vector3, quarter: int) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, -PI * 0.5 * float(quarter)), origin)


# --- Helipad -------------------------------------------------------------------------------

static func _helipad(b: Building, g: RooftopGeo, f: Dictionary, origin: Vector3, p: Dictionary, plants: Dictionary) -> void:
	var deck: float = f.deck
	var hd := deck * 0.5
	var rise := PAD_RISE
	g.xf = Transform3D(Basis(), origin)
	g.param = Vector2(deck, 0.0)
	# The deck: its painted top (UV from its centre, turned a quarter on odd turns so the H
	# lies either way), the slab edge.
	var u := [Vector2(-hd, -hd), Vector2(hd, -hd), Vector2(hd, hd), Vector2(-hd, hd)]
	if int(f.turn) % 2 == 1:
		for k in 4:
			u[k] = Vector2(u[k].y, -u[k].x)
	g.quad(Vector3(-hd, rise, -hd), Vector3(hd, rise, -hd), Vector3(hd, rise, hd), Vector3(-hd, rise, hd), Vector3.UP, PAD_DECK, 3,
		u[0], u[1], u[2], u[3])
	g.param = Vector2.ZERO
	for s in 4:
		var nrm := _side_normal(s)
		var n3 := Vector3(nrm.x, 0.0, nrm.y)
		var t3 := Vector3(-nrm.y, 0.0, nrm.x)
		var a := n3 * hd - t3 * hd
		var bb := n3 * hd + t3 * hd
		g.quad(a + Vector3(0, rise - 0.3, 0), bb + Vector3(0, rise - 0.3, 0), bb + Vector3(0, rise, 0), a + Vector3(0, rise, 0), n3, CONCRETE, 2,
			Vector2(0, 0), Vector2(deck, 0), Vector2(deck, 0.3), Vector2(0, 0.3))
	g.quad(Vector3(-hd, rise - 0.3, -hd), Vector3(hd, rise - 0.3, -hd), Vector3(hd, rise - 0.3, hd), Vector3(-hd, rise - 0.3, hd), Vector3.DOWN, DARK_STEEL, 1,
		Vector2(-hd, -hd), Vector2(hd, -hd), Vector2(hd, hd), Vector2(-hd, hd))
	# Girders: the perimeter and a grid under it, and the columns down to the roof - skipping any
	# that would land on a unit (the plant stays under the pad).
	var beam_y := rise - 0.3 - 0.22
	var lines := 4
	for k in lines:
		var t := -hd + deck * float(k) / float(lines - 1)
		g.beam(Vector3(-hd, beam_y, t), Vector3(hd, beam_y, t), 0.22, 0.44, STEEL, 1)
		g.beam(Vector3(t, beam_y - 0.02, -hd), Vector3(t, beam_y - 0.02, hd), 0.2, 0.4, STEEL, 1)
	var low: Array[Rect2] = []
	for prop: Array in (b.roof_props if b != null else []):
		if int(prop[3]) == int(p.part):
			var fp: Vector2 = b._prop_footprint(prop[0])
			var at: Vector3 = prop[1]
			low.append(Rect2(Vector2(at.x, at.z) - fp * 0.5, fp).grow(0.3))
	for ix in lines:
		for iz in lines:
			var lp := Vector3(-hd + deck * float(ix) / float(lines - 1), 0.0, -hd + deck * float(iz) / float(lines - 1))
			var wp := g.xf * lp
			var hit := false
			for r in low:
				if r.has_point(Vector2(wp.x, wp.z)):
					hit = true
					break
			if hit:
				continue
			g.box(lp + Vector3(0.0, (beam_y - 0.2) * 0.5, 0.0), Vector3(0.32, beam_y - 0.2, 0.32), STEEL, 1)
			g.box(lp + Vector3(0.0, 0.08, 0.0), Vector3(0.6, 0.16, 0.6), CONCRETE, 2)
			# Knee braces.
			g.beam(lp + Vector3(0.0, beam_y - 1.3, 0.0), lp + Vector3(0.9 * signf(-lp.x + 0.01), beam_y - 0.25, 0.0), 0.1, 0.1, STEEL, 1)
	# The safety-net shelf: a frame of tubes out from the deck edge, netting across it, a little
	# below the deck and rising outward; open where the stair comes up.
	var shelf_in := rise - 0.25
	var shelf_out := rise - 0.05
	var stair: int = f.stair
	for s in 4:
		var nrm := _side_normal(s)
		var n3 := Vector3(nrm.x, 0.0, nrm.y)
		var t3 := Vector3(-nrm.y, 0.0, nrm.x)
		var t_lo := -hd
		var t_hi := hd
		var gap_lo := INF
		var gap_hi := INF
		if s == stair:
			gap_lo = hd - 2.0
			gap_hi = hd - 0.1
		var segs: Array = []
		if gap_lo < INF:
			segs = [[t_lo, gap_lo], [gap_hi, t_hi]]
		else:
			segs = [[t_lo, t_hi]]
		for seg: Array in segs:
			var t0: float = seg[0]
			var t1: float = seg[1]
			if t1 - t0 < 0.3:
				continue
			var a_in := n3 * hd + t3 * t0 + Vector3(0, shelf_in, 0)
			var b_in := n3 * hd + t3 * t1 + Vector3(0, shelf_in, 0)
			var a_out := n3 * (hd + PAD_NET) + t3 * t0 + Vector3(0, shelf_out, 0)
			var b_out := n3 * (hd + PAD_NET) + t3 * t1 + Vector3(0, shelf_out, 0)
			g.quad2(a_in, b_in, b_out, a_out, Vector3(0, 1, 0), Color(0.30, 0.30, 0.28), 4,
				Vector2(t0, 0), Vector2(t1, 0), Vector2(t1, PAD_NET), Vector2(t0, PAD_NET))
			g.beam(a_out, b_out, 0.06, 0.06, STEEL, 1)
			# Brackets every 2 m.
			var nb := int(ceilf((t1 - t0) / 2.0))
			for k in nb + 1:
				var t := lerpf(t0, t1, float(k) / float(maxi(nb, 1)))
				var root := n3 * hd + t3 * t + Vector3(0, shelf_in - 0.25, 0)
				g.beam(root, n3 * (hd + PAD_NET) + t3 * t + Vector3(0, shelf_out, 0), 0.05, 0.05, STEEL, 1)
		# Perimeter lights, flush on the deck edge every 2.5 m, green; floods at the corners.
		var nl := maxi(int(deck / 2.5), 3)
		for k in nl + 1:
			var t := -hd + deck * float(k) / float(nl)
			var lp := n3 * (hd - 0.25) + t3 * t + Vector3(0, rise, 0)
			g.cyl(lp, 0.09, 0.07, 0.09, 6, Color(0.25, 1.0, 0.4), 5)
		var corner := n3 * (hd + 0.35) + t3 * (hd + 0.35) + Vector3(0, rise, 0)
		g.box(corner + Vector3(0, 0.12, 0), Vector3(0.3, 0.24, 0.3), DARK_STEEL, 1)
		g.box(corner + Vector3(0, 0.3, 0) - (n3 + t3) * 0.12, Vector3(0.24, 0.16, 0.06), Color(1.0, 0.95, 0.85), 5)
	# The windsock: a mast at a corner of the shelf, the hoop, the striped sock streaming off.
	var sn := _side_normal(int(f.sock))
	var sn3 := Vector3(sn.x, 0.0, sn.y)
	var st3 := Vector3(-sn.y, 0.0, sn.x)
	var mast_at := sn3 * (hd + PAD_NET - 0.3) + st3 * (-hd + 0.6) + Vector3(0, shelf_out - 0.1, 0)
	g.cyl(mast_at, 0.06, 0.045, 3.2, 8, WHITE_PAINT, 0)
	g.cyl(mast_at + Vector3(0, 1.0, 0), 0.065, 0.065, 0.4, 8, Color(0.85, 0.15, 0.08), 0)
	var hoop := mast_at + Vector3(0, 3.05, 0)
	var wind := (Vector3(0.7, 0.0, 0.5) + st3 * 0.4).normalized()
	var saved := g.xf
	var sock_basis := Basis(Vector3.UP.cross(wind).normalized(), wind, Vector3.UP.cross(wind).normalized().cross(wind)).orthonormalized()
	# Drooping a little: the tail end lower.
	sock_basis = sock_basis.rotated(Vector3.UP.cross(wind).normalized(), 0.25)
	g.xf = saved * Transform3D(sock_basis, hoop)
	g.cyl(Vector3.ZERO, 0.38, 0.14, 2.4, 10, Color.WHITE, 15, false, false)
	g.xf = saved
	g.beam(mast_at + Vector3(0, 3.05, 0), hoop + wind * 0.05, 0.03, 0.03, STEEL, 1)
	g.box(mast_at + Vector3(0, 3.25, 0), Vector3(0.18, 0.18, 0.18), Color(1.0, 0.15, 0.08), 17)
	# The stair (or a caged ladder) up from the roof to the deck.
	if stair >= 0:
		_stair(g, stair, hd, rise)
	else:
		var ln := _side_normal(int(f.turn) % 4)
		var l3 := Vector3(ln.x, 0, ln.y)
		var base := l3 * (hd + 0.2)
		var lt := Vector3(-ln.y, 0, ln.x)
		for sgn: float in [-0.25, 0.25]:
			g.box(base + lt * sgn + Vector3(0, rise * 0.5 + 0.5, 0), Vector3(0.05, rise + 1.0, 0.05), SAFETY_YELLOW, 0)
		for k in int(rise / 0.3):
			g.beam(base - lt * 0.25 + Vector3(0, 0.3 * float(k + 1), 0), base + lt * 0.25 + Vector3(0, 0.3 * float(k + 1), 0), 0.03, 0.03, SAFETY_YELLOW, 0)
	# Collision: the deck and its shelf.
	if b != null:
		_box_shape(b, Vector3(deck, 0.3, deck), g.xf * Vector3(0, rise - 0.15, 0))
	if f.heli and b != null:
		_parked_helicopter(b, g.xf * Vector3(0.3, rise, -0.4), int(f.turn), int(f.livery))
	g.xf = Transform3D.IDENTITY


## A steel stair under the shelf on `side`, climbing along the deck edge from the roof to the
## gap left in the net (t from hd - 5.5 to hd - 1.0 along the side).
static func _stair(g: RooftopGeo, side: int, hd: float, rise: float) -> void:
	var nrm := _side_normal(side)
	var n3 := Vector3(nrm.x, 0.0, nrm.y)
	var t3 := Vector3(-nrm.y, 0.0, nrm.x)
	var off := n3 * (hd + 0.7)
	var steps := int(ceilf(rise / 0.19))
	var t0 := hd - 5.5
	var t1 := hd - 1.0
	var run := (t1 - t0) / float(steps)
	for k in steps:
		var t := lerpf(t0, t1, (float(k) + 0.5) / float(steps))
		var y := rise * float(k + 1) / float(steps)
		g.box(off + t3 * t + Vector3(0, y - 0.025, 0), t3.abs() * run + n3.abs() * 0.95 + Vector3(0, 0.05, 0), DARK_STEEL, 16)
	for sgn: float in [-0.5, 0.5]:
		var a := off + t3 * t0 + n3 * sgn
		var bb := off + t3 * t1 + n3 * sgn + Vector3(0, rise, 0)
		g.beam(a + Vector3(0, 0.05, 0), bb - Vector3(0, 0.1, 0), 0.04, 0.24, DARK_STEEL, 1)
		g.beam(a + Vector3(0, 1.0, 0), bb + Vector3(0, 1.0, 0), 0.045, 0.045, SAFETY_YELLOW, 0)
		g.beam(a + Vector3(0, 0.5, 0), bb + Vector3(0, 0.5, 0), 0.03, 0.03, SAFETY_YELLOW, 0)
		g.box(a + Vector3(0, 0.5, 0), Vector3(0.05, 1.0, 0.05), SAFETY_YELLOW, 0)
		g.box(bb + Vector3(0, 0.5, 0), Vector3(0.05, 1.0, 0.05), SAFETY_YELLOW, 0)


## A parked helicopter: the air traffic's model (assets/models/helicopter.glb) in a private
## livery, rotors still and tied fore and aft. Its own node (it is a model), drawn to 400 m.
static func _parked_helicopter(b: Building, at: Vector3, quarter: int, livery: int) -> void:
	if _heli_scene == null:
		if not ResourceLoader.exists(HELI_MODEL):
			return
		_heli_scene = load(HELI_MODEL)
	var inst := _heli_scene.instantiate() as Node3D
	if inst == null:
		return
	for nm: String in ["LiveryPolice", "LiveryNews", "Searchlight", "CameraBall"]:
		var gone := inst.find_child(nm, true, false)
		if gone:
			gone.get_parent().remove_child(gone)
			gone.free()
	var cols: Array = HELI_LIVERIES[livery]
	var mats := {"paint": _paint(cols[0], true), "paint2": _paint(cols[1], true), "stripe": _paint(cols[2], true),
		"glass": _paint(Color(0.03, 0.04, 0.05), false)}
	(mats["glass"] as StandardMaterial3D).roughness = 0.05
	(mats["glass"] as StandardMaterial3D).metallic = 0.6
	for n in inst.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		mi.visibility_range_end = 420.0
		for si in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(si)
			var key := src.resource_name if src else ""
			if mats.has(key):
				mi.set_surface_override_material(si, mats[key])
	# Blades parked at 45 degrees off the boom, the way they are tied down.
	var rotor := inst.find_child("MainRotor", true, false) as Node3D
	if rotor:
		rotor.rotate_object_local(Vector3.UP, PI * 0.25)
	inst.name = "ParkedHelicopter"
	inst.transform = Transform3D(Basis(Vector3.UP, -PI * 0.5 * float(quarter) + PI * 0.25), at)
	b.add_child(inst)


static var _heli_paints: Dictionary = {}


static func _paint(c: Color, coat: bool) -> StandardMaterial3D:
	var key := "%s %s" % [c.to_html(), coat]
	if _heli_paints.has(key):
		return _heli_paints[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = 0.25 if coat else 0.0
	m.roughness = 0.33
	if coat:
		m.clearcoat_enabled = true
		m.clearcoat = 0.7
		m.clearcoat_roughness = 0.12
	_heli_paints[key] = m
	return m


# --- Pool deck -----------------------------------------------------------------------------

static func _pool(b: Building, g: RooftopGeo, glass: RooftopGeo, f: Dictionary, origin: Vector3, plants: Dictionary) -> void:
	var zone: Vector2 = f.size
	var swap: bool = f.swap
	# Work in the zone's own frame: x along its length; the last STEP_STRIP metres of +z are the
	# roof the steps come up from, the rest the raised deck.
	g.xf = Transform3D(Basis(Vector3.UP, PI * 0.5) if swap else Basis(), origin)
	glass.xf = g.xf
	var zl := zone.y if swap else zone.x
	var zw := zone.x if swap else zone.y
	var hx := zl * 0.5
	var hz := zw * 0.5
	var dz1 := hz - STEP_STRIP
	var flip := -1.0 if f.flip else 1.0
	var length: float = f.len
	var width: float = f.wid
	var y := DECK_RISE
	var deck_col: Color = DECK_WOOD if f.wood else DECK_TILES[int(f.tile)]
	var deck_kind := 7 if f.wood else 9
	# The pool from the end away from the bar, along the -z side (the loungers have the +z side).
	var px := -flip * (hx - 0.6 - length * 0.5)
	var pz := -hz + 0.6 + width * 0.5
	var pool_min := Vector2(px - length * 0.5, pz - width * 0.5)
	var pool_max := Vector2(px + length * 0.5, pz + width * 0.5)
	var cop := 0.35
	# The deck top round the pool (four strips) and its fascia.
	_deck_strip(g, Vector2(-hx, -hz), Vector2(hx, pool_min.y - cop), y, deck_col, deck_kind)
	_deck_strip(g, Vector2(-hx, pool_max.y + cop), Vector2(hx, dz1), y, deck_col, deck_kind)
	_deck_strip(g, Vector2(-hx, pool_min.y - cop), Vector2(pool_min.x - cop, pool_max.y + cop), y, deck_col, deck_kind)
	_deck_strip(g, Vector2(pool_max.x + cop, pool_min.y - cop), Vector2(hx, pool_max.y + cop), y, deck_col, deck_kind)
	var d_lo := Vector2(-hx, -hz)
	var d_hi := Vector2(hx, dz1)
	_fascia(g, d_lo, d_hi, y)
	# Coping: stone kerb round the water.
	var cc := Color(0.86, 0.84, 0.79)
	g.box(Vector3(px, y + 0.02, pool_min.y - cop * 0.5), Vector3(length + cop * 2.0, 0.08, cop), cc, 2)
	g.box(Vector3(px, y + 0.02, pool_max.y + cop * 0.5), Vector3(length + cop * 2.0, 0.08, cop), cc, 2)
	g.box(Vector3(pool_min.x - cop * 0.5, y + 0.02, pz), Vector3(cop, 0.08, width), cc, 2)
	g.box(Vector3(pool_max.x + cop * 0.5, y + 0.02, pz), Vector3(cop, 0.08, width), cc, 2)
	# The water: UV is building space from the pool's centre, so the shader traces its tank in the
	# mesh's own space (UV2 the half size there; a quarter turn swaps the two).
	var water_y := y - 0.06
	var wc := g.xf * Vector3(px, 0, pz)
	var half_l := g.xf.basis * Vector3(length * 0.5, 0, width * 0.5)
	g.param = Vector2(absf(half_l.x), absf(half_l.z))
	var corners := [Vector3(pool_min.x, water_y, pool_min.y), Vector3(pool_max.x, water_y, pool_min.y),
		Vector3(pool_max.x, water_y, pool_max.y), Vector3(pool_min.x, water_y, pool_max.y)]
	var uvs: Array[Vector2] = []
	for q: Vector3 in corners:
		var w3: Vector3 = g.xf * q
		uvs.append(Vector2(w3.x - wc.x, w3.z - wc.z))
	g.quad(corners[0], corners[1], corners[2], corners[3], Vector3.UP, Color(0.5, 0.7, 0.75), 6, uvs[0], uvs[1], uvs[2], uvs[3])
	g.param = Vector2.ZERO
	# Steps up from the roof at the bar end.
	var bar_x := flip * (hx - 1.6)
	var nsteps := 4
	for k in nsteps:
		var sy := y * float(k + 1) / float(nsteps + 1)
		var depth := STEP_STRIP * float(nsteps - k) / float(nsteps)
		g.box(Vector3(bar_x, sy * 0.5, dz1 + depth * 0.5), Vector3(1.6, sy, depth), deck_col, deck_kind)
	# Loungers along the +z side, umbrellas between pairs.
	var canvas: Color = CANVAS[int(f.canvas)]
	var row_z := pool_max.y + cop + 1.0
	var x0 := pool_min.x + 0.5
	var x1 := pool_max.x - 0.5
	var n := maxi(int((x1 - x0) / 1.25), 2)
	for k in n:
		var lx := lerpf(x0, x1, (float(k) + 0.5) / float(n))
		_lounger(g, Vector3(lx, y, row_z), canvas, absi(b.seed) % 3 == 0)
		if k % 2 == 1 and k + 1 < n:
			_umbrella(g, Vector3(lerpf(x0, x1, float(k + 1) / float(n)), y, row_z + 0.2), canvas)
	# The cabana bar at the end: counter, back bar with bottles, a timber canopy, stools, the
	# lit sign on the canopy's fascia facing the pool.
	var bx := flip * (hx - 1.45)
	var face := -flip
	var bz := -hz + (dz1 + hz) * 0.5
	var bl := (dz1 + hz) * 0.75
	var wood := Color(0.30, 0.22, 0.16)
	g.box(Vector3(bx, y + 0.55, bz), Vector3(0.7, 1.1, bl), Color(0.32, 0.24, 0.18), 7)
	g.box(Vector3(bx, y + 1.13, bz), Vector3(0.85, 0.06, bl + 0.1), Color(0.86, 0.84, 0.80), 2)
	g.box(Vector3(bx + flip * 1.0, y + 0.9, bz), Vector3(0.45, 1.8, bl + 0.2), Color(0.24, 0.20, 0.17), 0)
	for k in 3:
		g.box(Vector3(bx + flip * 0.75, y + 1.0 + float(k) * 0.3, bz), Vector3(0.2, 0.03, bl), Color(0.75, 0.72, 0.65), 1)
		for j in 7:
			g.cyl(Vector3(bx + flip * 0.75, y + 1.03 + float(k) * 0.3, bz - bl * 0.42 + float(j) * bl * 0.14), 0.035, 0.025, 0.24, 6,
				[Color(0.2, 0.45, 0.25), Color(0.75, 0.55, 0.2), Color(0.85, 0.85, 0.8)][(j + k) % 3], 0)
	for z: float in [bz - bl * 0.5, bz + bl * 0.5]:
		g.box(Vector3(bx + flip * 1.1, y + 1.35, z), Vector3(0.1, 2.7, 0.1), wood, 7)
		g.box(Vector3(bx - flip * 0.9, y + 1.35, z), Vector3(0.1, 2.7, 0.1), wood, 7)
	g.box(Vector3(bx + flip * 0.1, y + 2.75, bz), Vector3(2.4, 0.12, bl + 0.6), wood, 7)
	var ns := maxi(int(bl / 0.7), 3)
	for k in ns:
		var sz := bz - bl * 0.42 + bl * 0.84 * (float(k) + 0.5) / float(ns)
		var sx := bx - flip * 0.75
		g.cyl(Vector3(sx, y, sz), 0.025, 0.025, 0.72, 6, Color(0.16, 0.16, 0.17), 1)
		g.cyl(Vector3(sx, y + 0.72, sz), 0.19, 0.19, 0.06, 10, Color(0.20, 0.20, 0.20), 18)
	var name_s: String = BAR_NAMES[int(f.bar)]
	var sign_w := minf(bl + 0.4, 0.3 * float(name_s.length()) + 0.6)
	var sign_at := Vector3(bx - flip * 1.08, y + 3.1, bz)
	g.box(sign_at, Vector3(0.08, 0.6, sign_w), Color(0.08, 0.08, 0.09), 1)
	g.text(name_s, 0.32, sign_at + Vector3(face * 0.05, 0, 0), Vector3(0, 0, -face), Vector3.UP, Vector3(face, 0, 0), Color(1.0, 0.70, 0.40), 11)
	# Glass balustrade round the deck (open where the steps come up), a steel top rail.
	_balustrade(g, glass, Vector3(-hx + 0.08, y, -hz + 0.08), Vector3(hx - 0.08, y, -hz + 0.08), Vector3.FORWARD)
	_balustrade(g, glass, Vector3(-hx + 0.08, y, -hz + 0.08), Vector3(-hx + 0.08, y, dz1 - 0.08), Vector3.LEFT)
	_balustrade(g, glass, Vector3(hx - 0.08, y, -hz + 0.08), Vector3(hx - 0.08, y, dz1 - 0.08), Vector3.RIGHT)
	var g0 := minf(bar_x - 0.9, bar_x + 0.9)
	var g1 := maxf(bar_x - 0.9, bar_x + 0.9)
	_balustrade(g, glass, Vector3(-hx + 0.08, y, dz1 - 0.08), Vector3(g0, y, dz1 - 0.08), Vector3.BACK)
	_balustrade(g, glass, Vector3(g1, y, dz1 - 0.08), Vector3(hx - 0.08, y, dz1 - 0.08), Vector3.BACK)
	# String lights: four runs between posts at the deck's corners.
	var post_h := 3.1
	var posts := [Vector3(-hx + 0.3, y, -hz + 0.3), Vector3(-hx + 0.3, y, dz1 - 0.3), Vector3(hx - 0.3, y, -hz + 0.3), Vector3(hx - 0.3, y, dz1 - 0.3)]
	for pp: Vector3 in posts:
		g.cyl(pp, 0.05, 0.04, post_h, 6, DARK_STEEL, 1)
	for pair: Array in [[0, 3], [1, 2], [0, 2], [1, 3]]:
		_string_lights(g, posts[pair[0]] + Vector3(0, post_h, 0), posts[pair[1]] + Vector3(0, post_h, 0))
	# Potted palms at the corners away from the bar.
	var palm := PropFactory.palm(absi(b.seed) % PropFactory.PALM_VARIANTS)
	for corner: Vector3 in [Vector3(-flip * (hx - 0.75), y, -hz + 0.75), Vector3(-flip * (hx - 0.75), y, dz1 - 0.75)]:
		g.box(corner + Vector3(0, 0.3, 0), Vector3(0.9, 0.6, 0.9), Color(0.30, 0.30, 0.31), 0)
		g.box(corner + Vector3(0, 0.61, 0), Vector3(0.8, 0.02, 0.8), Color(0.3, 0.22, 0.15), 14)
		_add_plant(plants, "palm", palm, g.xf * Transform3D(Basis(Vector3.UP, float(absi(b.seed) % 7)).scaled(Vector3.ONE * 0.3), corner + Vector3(0, 0.6, 0)))
	# Collision: the deck round the pool (the pool's floor is the roof: wade in).
	for r: Rect2 in [Rect2(d_lo, Vector2(hx * 2.0, pool_min.y - d_lo.y)), Rect2(Vector2(-hx, pool_max.y), Vector2(hx * 2.0, dz1 - pool_max.y)),
			Rect2(Vector2(-hx, pool_min.y), Vector2(pool_min.x + hx, width)), Rect2(Vector2(pool_max.x, pool_min.y), Vector2(hx - pool_max.x, width))]:
		if r.size.x < 0.05 or r.size.y < 0.05:
			continue
		var cen := g.xf * Vector3(r.get_center().x, y * 0.5, r.get_center().y)
		var sz := (g.xf.basis * Vector3(r.size.x, y, r.size.y)).abs()
		_box_shape(b, sz, cen)
	g.xf = Transform3D.IDENTITY
	glass.xf = Transform3D.IDENTITY


## The fascia round a raised deck from `lo` to `hi` (zone frame), `y` high.
static func _fascia(g: RooftopGeo, lo: Vector2, hi: Vector2, y: float) -> void:
	var col := Color(0.42, 0.41, 0.40)
	g.quad(Vector3(lo.x, 0, hi.y), Vector3(hi.x, 0, hi.y), Vector3(hi.x, y, hi.y), Vector3(lo.x, y, hi.y), Vector3.BACK, col, 2,
		Vector2(lo.x, 0), Vector2(hi.x, 0), Vector2(hi.x, y), Vector2(lo.x, y))
	g.quad(Vector3(lo.x, 0, lo.y), Vector3(hi.x, 0, lo.y), Vector3(hi.x, y, lo.y), Vector3(lo.x, y, lo.y), Vector3.FORWARD, col, 2,
		Vector2(lo.x, 0), Vector2(hi.x, 0), Vector2(hi.x, y), Vector2(lo.x, y))
	g.quad(Vector3(hi.x, 0, lo.y), Vector3(hi.x, 0, hi.y), Vector3(hi.x, y, hi.y), Vector3(hi.x, y, lo.y), Vector3.RIGHT, col, 2,
		Vector2(lo.y, 0), Vector2(hi.y, 0), Vector2(hi.y, y), Vector2(lo.y, y))
	g.quad(Vector3(lo.x, 0, lo.y), Vector3(lo.x, 0, hi.y), Vector3(lo.x, y, hi.y), Vector3(lo.x, y, lo.y), Vector3.LEFT, col, 2,
		Vector2(lo.y, 0), Vector2(hi.y, 0), Vector2(hi.y, y), Vector2(lo.y, y))


static func _deck_strip(g: RooftopGeo, lo: Vector2, hi: Vector2, y: float, col: Color, kind: int) -> void:
	if hi.x - lo.x < 0.02 or hi.y - lo.y < 0.02:
		return
	g.quad(Vector3(lo.x, y, lo.y), Vector3(hi.x, y, lo.y), Vector3(hi.x, y, hi.y), Vector3(lo.x, y, hi.y), Vector3.UP, col, kind,
		Vector2(lo.x, lo.y), Vector2(hi.x, lo.y), Vector2(hi.x, hi.y), Vector2(lo.x, hi.y))


static func _balustrade(g: RooftopGeo, glass: RooftopGeo, a: Vector3, bb: Vector3, out: Vector3) -> void:
	var len := a.distance_to(bb)
	if len < 0.3:
		return
	var h := 1.1
	glass.quad(a + Vector3(0, 0.06, 0), bb + Vector3(0, 0.06, 0), bb + Vector3(0, h - 0.04, 0), a + Vector3(0, h - 0.04, 0), out, Color.WHITE, 0,
		Vector2(0, 0), Vector2(len, 0), Vector2(len, h), Vector2(0, h))
	g.beam(a + Vector3(0, h, 0), bb + Vector3(0, h, 0), 0.06, 0.05, Color(0.70, 0.71, 0.72), 1)
	g.beam(a + Vector3(0, 0.03, 0), bb + Vector3(0, 0.03, 0), 0.08, 0.07, Color(0.30, 0.30, 0.31), 1)


static func _string_lights(g: RooftopGeo, a: Vector3, bb: Vector3) -> void:
	var len := a.distance_to(bb)
	var n := maxi(int(len / 0.7), 2)
	var sag := 0.05 * len
	var prev := a
	for k in range(1, n + 1):
		var t := float(k) / float(n)
		var q := a.lerp(bb, t) - Vector3(0, sag * 4.0 * t * (1.0 - t), 0)
		g.beam(prev, q, 0.012, 0.012, Color(0.06, 0.06, 0.06), 0)
		if k < n:
			g.box(q - Vector3(0, 0.06, 0), Vector3(0.05, 0.07, 0.05), Color(1.0, 0.8, 0.5), 10)
		prev = q


static func _lounger(g: RooftopGeo, at: Vector3, canvas: Color, teak: bool) -> void:
	var frame := Color(0.45, 0.32, 0.22) if teak else Color(0.88, 0.88, 0.86)
	var fk := 7 if teak else 0
	# Bed along z, the back raised toward -z.
	g.box(at + Vector3(0, 0.3, 0.25), Vector3(0.66, 0.06, 1.3), frame, fk)
	for dx: float in [-0.28, 0.28]:
		for dz: float in [-0.3, 0.8]:
			g.box(at + Vector3(dx, 0.14, dz), Vector3(0.05, 0.28, 0.05), frame, fk)
	g.box(at + Vector3(0, 0.38, 0.25), Vector3(0.6, 0.08, 1.25), Color(0.94, 0.93, 0.90) if canvas.v < 0.5 else canvas.lightened(0.15), 18)
	var back := Transform3D(Basis(Vector3.RIGHT, -0.75), at + Vector3(0, 0.36, -0.42))
	var saved := g.xf
	g.xf = saved * back
	g.box(Vector3(0, 0.0, -0.32), Vector3(0.6, 0.08, 0.66), Color(0.94, 0.93, 0.90) if canvas.v < 0.5 else canvas.lightened(0.15), 18)
	g.xf = saved
	# A towel on some.
	g.box(at + Vector3(0, 0.43, 0.5), Vector3(0.5, 0.02, 0.5), canvas, 18)


static func _umbrella(g: RooftopGeo, at: Vector3, canvas: Color) -> void:
	g.box(at + Vector3(0, 0.05, 0), Vector3(0.45, 0.1, 0.45), Color(0.25, 0.25, 0.26), 2)
	g.cyl(at, 0.025, 0.025, 2.5, 6, Color(0.82, 0.80, 0.76), 0)
	g.cyl(at + Vector3(0, 2.0, 0), 1.35, 0.06, 0.45, 8, canvas, 8, true, true)
	g.cyl(at + Vector3(0, 1.94, 0), 1.37, 1.35, 0.08, 8, canvas.darkened(0.1), 8, false, false)


# --- Roof garden ---------------------------------------------------------------------------

static func _garden(b: Building, g: RooftopGeo, f: Dictionary, origin: Vector3, plants: Dictionary) -> void:
	var zone: Vector2 = f.size
	var swap: bool = f.swap
	g.xf = Transform3D(Basis(Vector3.UP, PI * 0.5) if swap else Basis(), origin)
	var zl := zone.y if swap else zone.x
	var zw := zone.x if swap else zone.y
	var hx := zl * 0.5
	var hz := zw * 0.5
	var y := 0.12
	var flip := -1.0 if f.flip else 1.0
	var paver: Color = DECK_TILES[int(f.tile)]
	_deck_strip(g, Vector2(-hx, -hz), Vector2(hx, hz), y, paver, 9)
	# Planter boxes along the long sides, a lawn in the middle of the open end.
	var bush := PropFactory.model_shrub(absi(hash([b.seed, SALT, "bush"])) % 4)
	for side: float in [-1.0, 1.0]:
		var pz := side * (hz - 0.5)
		g.box(Vector3(0, y + 0.3, pz), Vector3(zl - 0.4, 0.6, 0.8), Color(0.58, 0.57, 0.54), 2)
		g.box(Vector3(0, y + 0.61, pz), Vector3(zl - 0.6, 0.02, 0.6), Color(0.26, 0.19, 0.13), 14)
		var nb := maxi(int((zl - 0.8) / 0.9), 2)
		for k in nb:
			var bx := -hx + 0.6 + (zl - 1.2) * (float(k) + 0.5) / float(nb)
			var s := 0.5 + 0.25 * float(absi(hash([b.seed, k, side])) % 100) / 100.0
			_add_plant(plants, "bush", bush, g.xf * Transform3D(Basis(Vector3.UP, float(k) * 2.1).scaled(Vector3.ONE * s), Vector3(bx, y + 0.6, pz)))
	var lawn_x0 := -hx + 0.5 if flip > 0.0 else -hx + zl * 0.45
	var lawn_x1 := lawn_x0 + zl * 0.5
	_deck_strip(g, Vector2(lawn_x0, -hz + 1.3), Vector2(lawn_x1, hz - 1.3), y + 0.04, Color(0.25, 0.34, 0.14), 13)
	g.box(Vector3((lawn_x0 + lawn_x1) * 0.5, y + 0.02, -hz + 1.25), Vector3(lawn_x1 - lawn_x0 + 0.1, 0.08, 0.1), Color(0.3, 0.3, 0.3), 1)
	g.box(Vector3((lawn_x0 + lawn_x1) * 0.5, y + 0.02, hz - 1.25), Vector3(lawn_x1 - lawn_x0 + 0.1, 0.08, 0.1), Color(0.3, 0.3, 0.3), 1)
	# The pergola over the other end: four posts, beams, slats; benches and a table under it.
	var px0 := lawn_x1 + 0.6 if flip > 0.0 else -hx + 0.6
	var px1 := hx - 0.4 if flip > 0.0 else lawn_x0 - 0.6
	if px1 - px0 > 2.0:
		var wood := Color(0.40, 0.29, 0.20)
		var pz0 := -hz + 1.3
		var pz1 := hz - 1.3
		for x: float in [px0, px1]:
			for z: float in [pz0, pz1]:
				g.box(Vector3(x, y + 1.3, z), Vector3(0.15, 2.6, 0.15), wood, 7)
		for z: float in [pz0, pz1]:
			g.box(Vector3((px0 + px1) * 0.5, y + 2.65, z), Vector3(px1 - px0 + 0.6, 0.22, 0.1), wood, 7)
		var ns := int((px1 - px0 + 0.4) / 0.35)
		for k in ns + 1:
			var x := px0 - 0.2 + float(k) * 0.35
			g.box(Vector3(x, y + 2.82, (pz0 + pz1) * 0.5), Vector3(0.05, 0.12, pz1 - pz0 + 0.5), wood, 7)
		for z: float in [pz0 + 0.4, pz1 - 0.4]:
			g.box(Vector3((px0 + px1) * 0.5, y + 0.45, z), Vector3(px1 - px0 - 0.6, 0.06, 0.45), Color(0.52, 0.38, 0.26), 7)
			g.box(Vector3((px0 + px1) * 0.5, y + 0.21, z), Vector3(px1 - px0 - 0.8, 0.42, 0.3), Color(0.30, 0.30, 0.31), 0)
		g.box(Vector3((px0 + px1) * 0.5, y + 0.72, 0), Vector3(px1 - px0 - 1.0, 0.05, 0.9), Color(0.52, 0.38, 0.26), 7)
		g.box(Vector3((px0 + px1) * 0.5, y + 0.36, 0), Vector3(0.12, 0.7, 0.12), DARK_STEEL, 1)
		_string_lights(g, Vector3(px0, y + 2.6, pz0), Vector3(px1, y + 2.6, pz1))
		_string_lights(g, Vector3(px0, y + 2.6, pz1), Vector3(px1, y + 2.6, pz0))
	g.xf = Transform3D.IDENTITY


# --- Mechanical penthouse ------------------------------------------------------------------

static func _penthouse(b: Building, g: RooftopGeo, f: Dictionary, origin: Vector3) -> void:
	var zone: Vector2 = f.size
	var h: float = f.tall
	g.xf = Transform3D(Basis(), origin)
	var hx := zone.x * 0.5 - 0.2
	var hz := zone.y * 0.5 - 0.2
	var metal: Color = PENT_METAL[int(f.paint)]
	# A plinth, louvred walls on a frame, a capped roof with an overhang, a door, a stack.
	g.box(Vector3(0, 0.1, 0), Vector3(hx * 2.0 + 0.2, 0.2, hz * 2.0 + 0.2), CONCRETE, 2)
	g.box(Vector3(0, 0.2 + (h - 0.4) * 0.5, 0), Vector3(hx * 2.0, h - 0.4, hz * 2.0), metal, 12)
	g.box(Vector3(0, h - 0.1, 0), Vector3(hx * 2.0 + 0.3, 0.2, hz * 2.0 + 0.3), metal.darkened(0.15), 0)
	for x: float in [-hx, hx]:
		for z: float in [-hz, hz]:
			g.box(Vector3(x, h * 0.5, z), Vector3(0.14, h - 0.2, 0.14), metal.darkened(0.25), 1)
	var mid := int((hx * 2.0) / 2.4)
	for k in range(1, mid):
		var x := -hx + float(k) * (hx * 2.0) / float(mid)
		for z: float in [-hz - 0.02, hz + 0.02]:
			g.box(Vector3(x, h * 0.5, z), Vector3(0.1, h - 0.4, 0.06), metal.darkened(0.25), 1)
	g.box(Vector3(hx * 0.4, 1.05, hz + 0.04), Vector3(0.95, 2.1, 0.05), Color(0.30, 0.31, 0.32), 0)
	g.box(Vector3(-hx * 0.5, h + 0.4, -hz * 0.4), Vector3(1.4, 0.6, 1.4), Color(0.60, 0.61, 0.62), 1)
	g.cyl(Vector3(-hx * 0.5, h + 0.7, -hz * 0.4), 0.55, 0.55, 0.12, 12, DARK_STEEL, 1)
	g.cyl(Vector3(hx * 0.6, h, -hz * 0.5), 0.22, 0.22, 2.0, 10, Color(0.62, 0.63, 0.64), 1)
	g.cyl(Vector3(hx * 0.6, h + 2.0, -hz * 0.5), 0.3, 0.05, 0.25, 10, Color(0.62, 0.63, 0.64), 1)
	_box_shape(b, Vector3(hx * 2.0, h, hz * 2.0), origin + Vector3(0, h * 0.5, 0))
	g.xf = Transform3D.IDENTITY


# --- Telecom mast --------------------------------------------------------------------------

static func _mast(g: RooftopGeo, f: Dictionary, origin: Vector3) -> void:
	var h: float = f.h
	g.xf = Transform3D(Basis(Vector3.UP, f.yaw), origin)
	g.box(Vector3(0, 0.15, 0), Vector3(1.6, 0.3, 1.6), CONCRETE, 2)
	g.cyl(Vector3(0, 0.3, 0), 0.24, 0.14, h, 10, Color(0.62, 0.63, 0.64), 1)
	# Equipment cabinet and a cable ladder up the pole.
	g.box(Vector3(0.95, 0.85, 0), Vector3(0.6, 1.4, 0.9), Color(0.78, 0.78, 0.75), 0)
	g.beam(Vector3(0.0, 0.3, 0.22), Vector3(0.0, h * 0.75, 0.16), 0.12, 0.03, DARK_STEEL, 1, Vector3.BACK)
	# Three sectors of panel antennas on a triangular head frame at three quarters up.
	var hy := h * 0.75
	for s in 3:
		var a := TAU * float(s) / 3.0
		var d := Vector3(cos(a), 0, sin(a))
		g.beam(Vector3(0, hy, 0), d * 0.9 + Vector3(0, hy, 0), 0.08, 0.08, STEEL, 1)
		var t := Vector3(-d.z, 0, d.x)
		for k in 3:
			var at := d * 1.0 + t * (float(k) - 1.0) * 0.38 + Vector3(0, hy, 0)
			var saved := g.xf
			g.xf = saved * Transform3D(Basis(Vector3.UP, -a), at)
			g.box(Vector3.ZERO, Vector3(0.12, 1.4, 0.3), Color(0.86, 0.86, 0.84), 20, false)
			g.xf = saved
	# Microwave dishes lower down, each facing out.
	var n: int = f.dishes
	for k in n:
		var a := TAU * float(k) / float(n) + 0.6
		var d := Vector3(cos(a), 0, sin(a))
		var dy := h * (0.45 + 0.1 * float(k))
		var saved := g.xf
		var basis := Basis(Vector3.UP, -a) * Basis(Vector3.BACK, -PI * 0.5)
		g.xf = saved * Transform3D(basis, d * 0.42 + Vector3(0, dy, 0))
		var r := 0.35 + 0.15 * float(k % 2)
		g.cyl(Vector3(0, -0.25, 0), r * 0.75, r * 0.75, 0.25, 12, Color(0.80, 0.80, 0.78), 1, true, false)
		g.cyl(Vector3.ZERO, r, r, 0.12, 14, Color(0.93, 0.93, 0.91), 20, false, true)
		g.xf = saved
	# The aviation beacon on the tip.
	g.box(Vector3(0, 0.3 + h + 0.12, 0), Vector3(0.22, 0.24, 0.22), Color(1.0, 0.15, 0.08), 17)
	g.xf = Transform3D.IDENTITY


# --- Window-washing machine ----------------------------------------------------------------

static func _bmu(g: RooftopGeo, f: Dictionary, origin: Vector3, p: Dictionary) -> void:
	# Frame: x along the edge, +z out toward the facade.
	var side: int = f.side
	var nrm := _side_normal(side)
	var yaw := atan2(nrm.x, nrm.y)
	g.xf = Transform3D(Basis(Vector3.UP, yaw), origin)
	var white := Color(0.90, 0.90, 0.88)
	# Rails on sleepers along the edge.
	for z: float in [-0.9, 0.9]:
		g.box(Vector3(0, 0.12, z), Vector3(6.2, 0.1, 0.12), DARK_STEEL, 1)
		for k in 6:
			g.box(Vector3(-2.7 + float(k) * 1.08, 0.04, z), Vector3(0.3, 0.08, 0.4), CONCRETE, 2)
	# The carriage, the turret, the counterweight, the jib reaching out over the parapet.
	g.box(Vector3(0, 0.55, 0), Vector3(2.6, 0.7, 2.2), white, 0)
	for x: float in [-1.0, 1.0]:
		for z: float in [-0.9, 0.9]:
			g.cyl(Vector3(x, 0.17, z) - Vector3(0, 0, 0), 0.16, 0.16, 0.12, 8, DARK_STEEL, 1)
	g.box(Vector3(-0.2, 1.2, -0.6), Vector3(1.6, 0.6, 0.8), Color(0.55, 0.56, 0.58), 1)
	g.box(Vector3(0.3, 1.9, 0.2), Vector3(0.8, 2.0, 0.8), white, 0)
	g.box(Vector3(0.3, 2.95, 0.2), Vector3(0.9, 0.3, 0.9), Color(0.30, 0.31, 0.33), 1)
	var reach: float = f.reach
	var jib_end := Vector3(0.3, 3.0, reach + 0.9)
	g.beam(Vector3(0.3, 3.0, -0.6), jib_end, 0.36, 0.42, white, 0)
	g.beam(Vector3(0.3, 3.9, 0.2), jib_end + Vector3(0, 0.2, -0.4), 0.05, 0.05, DARK_STEEL, 1)
	g.box(Vector3(0.3, 3.9, 0.2), Vector3(0.12, 1.4, 0.12), white, 0)
	# Head with two sheaves over the facade.
	g.box(jib_end + Vector3(0, -0.15, 0), Vector3(2.8, 0.25, 0.3), white, 0)
	var cradle_len := 4.6
	if f.hang:
		var depth: float = f.depth
		var cy := 3.0 - depth
		var cz := reach + 0.65
		for x: float in [-1.2, 1.2]:
			g.beam(jib_end + Vector3(x, -0.3, 0), Vector3(0.3 + x, cy + 1.15, cz), 0.018, 0.018, DARK_STEEL, 1)
		_cradle(g, Vector3(0.3, cy, cz), cradle_len)
	else:
		# Parked on the roof behind the machine, on its trolley.
		_cradle(g, Vector3(0.3, 0.2, -2.1), cradle_len)
	g.xf = Transform3D.IDENTITY


static func _cradle(g: RooftopGeo, at: Vector3, len: float) -> void:
	var yellow := Color(0.86, 0.70, 0.18)
	var hl := len * 0.5
	g.box(at + Vector3(0, 0.05, 0), Vector3(len, 0.08, 0.75), Color(0.40, 0.41, 0.42), 16, false)
	g.box(at + Vector3(0, 0.17, 0), Vector3(len, 0.16, 0.8), yellow, 0)
	for z: float in [-0.38, 0.38]:
		g.beam(at + Vector3(-hl, 1.1, z), at + Vector3(hl, 1.1, z), 0.05, 0.05, yellow, 0)
		g.beam(at + Vector3(-hl, 0.6, z), at + Vector3(hl, 0.6, z), 0.04, 0.04, yellow, 0)
	for x: float in [-hl, -hl * 0.33, hl * 0.33, hl]:
		for z: float in [-0.38, 0.38]:
			g.box(at + Vector3(x, 0.6, z), Vector3(0.05, 1.1, 0.05), yellow, 0)
	for x: float in [-hl + 0.3, hl - 0.3]:
		g.box(at + Vector3(x, 0.55, 0), Vector3(0.35, 0.5, 0.5), Color(0.30, 0.31, 0.33), 1)
		# Bumper wheels against the glass.
		g.cyl(at + Vector3(x, 0.4, 0.45), 0.08, 0.08, 0.06, 8, Color(0.1, 0.1, 0.1), 0)


# --- Far ------------------------------------------------------------------------------------

## The pieces as far boxes in building space, FarBuilding's format ([Transform3D, Color, Color
## custom]); after roof_plan(), so it plans what the near building builds.
static func far_boxes(b: Building, planned = null) -> Array:
	var out: Array = []
	var p: Dictionary = planned if planned is Dictionary else plan(b)
	if p.is_empty():
		return out
	var c: Vector3 = p.c
	var top: float = float(p.top) + float(p.rise)
	for f: Dictionary in p.feats:
		var at2: Vector2 = f.at
		var o := Vector3(c.x + at2.x, top, c.z + at2.y)
		var sz: Vector2 = f.size
		match f.kind:
			"helipad":
				var deck: float = f.deck
				_far(out, o + Vector3(0, PAD_RISE - 0.15, 0), Vector3(deck, 0.3, deck), PAD_DECK, FarBuilding.Plant.HELIPAD, 1.0, float(f.turn) * 0.25)
				_far(out, o + Vector3(0, (PAD_RISE - 0.3) * 0.5, 0), Vector3(deck * 0.86, PAD_RISE - 0.3, deck * 0.86), DARK_STEEL, FarBuilding.Plant.UNIT, 1.0)
			"pool":
				_far(out, o + Vector3(0, DECK_RISE * 0.5, 0), Vector3(sz.x, DECK_RISE, sz.y), DECK_WOOD if f.wood else DECK_TILES[int(f.tile)], FarBuilding.Plant.POOL, 1.0,
					0.0 if not f.swap else 1.0)
			"garden":
				_far(out, o + Vector3(0, 0.4, 0), Vector3(sz.x, 0.8, sz.y), Color(0.30, 0.40, 0.20), FarBuilding.Plant.UNIT, 0.0)
			"penthouse":
				_far(out, o + Vector3(0, float(f.tall) * 0.5, 0), Vector3(sz.x - 0.4, f.tall, sz.y - 0.4), PENT_METAL[int(f.paint)], FarBuilding.Plant.UNIT, 1.0)
			"mast":
				_far(out, o + Vector3(0, (float(f.h) + 0.5) * 0.5, 0), Vector3(0.3, float(f.h) + 0.5, 0.3), Color(0.62, 0.63, 0.64), FarBuilding.Plant.BEACON_MAST, 1.0)
			"bmu":
				_far(out, o + Vector3(0, 1.4, 0), Vector3(sz.x * 0.45, 2.8, sz.y * 0.75), Color(0.90, 0.90, 0.88), FarBuilding.Plant.UNIT, 0.0)
	return out


static func _far(out: Array, centre: Vector3, size: Vector3, colour: Color, kind: int, big: float, extra: float = 0.0) -> void:
	out.append([Transform3D(Basis.from_scale(size), centre), colour, Color(float(kind), big, extra, FarBuilding.PLANT_FLAG)])


# --- Landmark towers -----------------------------------------------------------------------

static var _landmark_pads: Dictionary = {}


## A helipad on a LandmarkDowntown tower's flat roof (its TOWERS row's "helipad": [local centre
## on the roof, deck size, quarter turns]): the same pad as a Building's, on its own node at
## `at` (the tower's anchor), with collision on `statics` when there is one.
static func landmark_helipad(parent: Node3D, at: Vector3, pad: Array, statics: StaticBody3D) -> void:
	if not enabled:
		return
	var local: Vector3 = pad[0]
	var deck: float = pad[1]
	var turn: int = pad[2] if pad.size() > 2 else 0
	var key := "%s %s %d" % [local, deck, turn]
	if not _landmark_pads.has(key):
		var g := RooftopGeo.new()
		var f := {"deck": deck, "turn": turn, "sock": (turn + 1) % 4, "stair": (turn + 2) % 4, "heli": false, "livery": 0}
		_helipad(null, g, f, Vector3.ZERO, {"c": Vector3.ZERO, "part": -1}, {})
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, g.arrays())
		mesh.surface_set_material(0, material())
		_landmark_pads[key] = mesh
	var node := MeshInstance3D.new()
	node.name = "Helipad"
	node.mesh = _landmark_pads[key]
	node.position = at + local
	parent.add_child(node)
	if statics:
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(deck, 0.3, deck)
		cs.shape = box
		cs.position = at + local + Vector3(0, PAD_RISE - 0.15, 0)
		statics.add_child(cs)
