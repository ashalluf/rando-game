class_name VesselMesh
extends RefCounted
## The ocean traffic's hulls, built in code at real size (OceanTraffic, Vessel), on BoatMesh's
## accumulator, hull loft and fittings so they paint with the marina's shader (boat_body /
## vessel.gdshader: COLOR.a the region, COLOR.rgb the part's sRGB colour, the hull in the
## material's solo_paint):
##   - a sloop under sail: the marina's sailboat hull and rig without its furled sails, and the
##     sails themselves as their own meshes (main_sail() on its boom, jib() on its forestay) so
##     Vessel can sheet them, swing them across on a tack and heel the boat under them;
##   - a harbour tug (~28 m): a beamy hull with a high flared bow, bow and side fendering, two
##     decks of house with the wheelhouse glazed all round, twin stacks, mast, towing winch, H-bitt;
##   - a pilot boat (~16 m): deep-V, a raised cabin with big windows and PILOT on its sides, a
##     rubber rub rail all round, a light mast;
##   - a fast catamaran ferry (~42 m): two slender demihulls under a bridge deck, a two-deck
##     passenger house with window bands, the wheelhouse on top, the line's name on the sides.
## The motor yacht, sport fisher and runabout are BoatMesh's own (hull()). Frame: metres, the
## bow toward -Z, the waterline at y 0, the centre line x 0. Three levels (BoatMesh.Level). Cached.

enum Kind { SAIL, MOTOR, FISHER, RUNABOUT, PILOT, TUG, FERRY }

## Reference length of each kind's mesh (metres); Vessel scales a hull to its own length.
const REF_LEN := [11.0, 17.0, 13.0, 6.5, 16.0, 28.0, 42.0]
## Beam at the reference length.
const REF_BEAM := [3.63, 4.93, 4.16, 2.34, 4.9, 10.0, 11.2]

const WHITE := BoatMesh.WHITE
const OFFWHITE := BoatMesh.OFFWHITE
const STEEL := BoatMesh.STEEL
const ALU := BoatMesh.ALU
const BLACK := BoatMesh.BLACK
const GLASS := BoatMesh.GLASS_TINT
const SAILCLOTH := Color(0.94, 0.93, 0.89)
const R := BoatMesh.Region

## The ferry line (invented) and its boats' names.
const FERRY_LINE := "PACIFIC TERN"
const FERRY_NAMES := ["TERN EXPRESS", "TERN SPIRIT"]
## The ferry's livery: white with a band and stripe in the line's teal.
const FERRY_BAND := Color(0.05, 0.36, 0.42)
const FERRY_STRIPE := Color(0.95, 0.62, 0.18)

static var _cache: Dictionary = {}


static func hull(kind: int, variant: int, level: int) -> ArrayMesh:
	match kind:
		Kind.MOTOR:
			return BoatMesh.mesh(Marina.Type.MOTOR, variant, level)
		Kind.FISHER:
			return BoatMesh.mesh(Marina.Type.FISHER, variant, level)
		Kind.RUNABOUT:
			return BoatMesh.mesh(Marina.Type.RUNABOUT, variant, level)
	var key := "h%d_%d_%d" % [kind, variant, level]
	if _cache.has(key):
		return _cache[key]
	var acc := BoatMesh.Acc.new()
	acc.level = level
	match kind:
		Kind.SAIL:
			_sail_hull(acc, variant)
		Kind.PILOT:
			_pilot(acc)
		Kind.TUG:
			_tug(acc, variant)
		_:
			_ferry(acc, variant)
	var m := acc.commit()
	_cache[key] = m
	return m


## Waterline length and beam of a kind at reference size (what the hull rides the sea across).
static func ride_size(kind: int) -> Vector2:
	return Vector2(float(REF_LEN[kind]) * 0.9, float(REF_BEAM[kind]))


## The box round a kind's hull for collision at reference size: [centre, size].
static func hull_box(kind: int) -> Array:
	var l := float(REF_LEN[kind])
	var b := float(REF_BEAM[kind])
	match kind:
		Kind.SAIL:
			return [Vector3(0.0, 0.6, 0.0), Vector3(b * 0.9, 1.9, l * 0.92)]
		Kind.TUG:
			return [Vector3(0.0, 3.0, 0.0), Vector3(b * 0.95, 8.0, l * 0.95)]
		Kind.FERRY:
			return [Vector3(0.0, 4.0, 0.0), Vector3(b, 9.0, l * 0.95)]
		Kind.PILOT:
			return [Vector3(0.0, 2.0, 0.0), Vector3(b * 0.9, 4.5, l * 0.92)]
		Kind.MOTOR:
			return [Vector3(0.0, 2.0, 0.0), Vector3(b * 0.92, 4.6, l * 0.92)]
		Kind.FISHER:
			return [Vector3(0.0, 1.8, 0.0), Vector3(b * 0.92, 4.2, l * 0.92)]
	return [Vector3(0.0, 0.5, 0.0), Vector3(b * 0.9, 1.4, l * 0.92)]


# --- The sloop under sail -------------------------------------------------------------------------

## Where the sailing rig stands at reference size (hull frame): the gooseneck (the mast's aft face
## at boom height), the boom's length, the mast top, the stem fitting (the jib's tack) and the
## jib's clew at rest. Shared by the hull, the sails and Vessel (which pivots them).
static func rig(variant: int) -> Dictionary:
	var h := _sail_hull_params()
	var mast_h := 14.6 if variant == 0 else 13.6
	var mt := 0.6
	var mz := BoatMesh._z(h, mt)
	var my := BoatMesh._sheer(h, mt) + 0.5
	var by := my + 1.35
	var bz := BoatMesh._z(h, 0.06)
	var stem := BoatMesh._sheer_point(h, 0.995, 0.0) + Vector3(0.0, 0.1, 0.0)
	var top := Vector3(0.0, my + mast_h, mz)
	return {
		"gooseneck": Vector3(0.0, by, mz + 0.1),
		"boom": bz - (mz + 0.1),
		"top": top,
		"mast_foot": Vector3(0.0, my - 0.4, mz),
		"stem": stem,
		"fore_top": top + Vector3(0.0, -0.6, -0.02),
		"clew": Vector3(0.0, BoatMesh._sheer(h, 0.5) + 0.75, mz + 1.6),
	}


static func _sail_hull_params() -> BoatMesh.Hull:
	var h := BoatMesh.Hull.new()
	h.length = float(REF_LEN[Kind.SAIL])
	h.beam = float(REF_BEAM[Kind.SAIL])
	h.fb_stern = 0.95
	h.fb_bow = 1.32
	h.depth = 0.55
	h.vee = 0.15
	h.transom = 0.78
	h.max_at = 0.36
	h.fine = 1.5
	h.rake = 0.7
	return h


static func _sail_hull(acc: BoatMesh.Acc, variant: int) -> void:
	var h := _sail_hull_params()
	BoatMesh._hull(acc, h)
	var deck := BoatMesh._sheer(h, 0.5)
	if acc.level != BoatMesh.Level.FAR:
		acc.box(Transform3D(Basis(), Vector3(0.0, -BoatMesh._keel(h, 0.52) - 0.85, BoatMesh._z(h, 0.52))), Vector3(0.14, 1.7, 1.25), BLACK, R.BOTTOM)
		acc.box(Transform3D(Basis(), Vector3(0.0, -BoatMesh._keel(h, 0.1) - 0.5, BoatMesh._z(h, 0.1))), Vector3(0.08, 1.1, 0.55), BLACK, R.BOTTOM)
	BoatMesh._cabin(acc, h, 0.36, 0.7, deck - 0.05, 0.55, 0.62, 0.6, 0.18, Vector2(0.38, 0.72), WHITE, false)
	var r := rig(variant)
	if acc.level != BoatMesh.Level.FAR:
		var cz0 := BoatMesh._z(h, 0.08)
		var cz1 := BoatMesh._z(h, 0.35)
		var cw := BoatMesh._half_beam(h, 0.2) * 0.72
		var cy := BoatMesh._sheer(h, 0.2)
		for side: float in [-1.0, 1.0]:
			acc.box(Transform3D(Basis(), Vector3(side * cw, cy + 0.17, (cz0 + cz1) * 0.5)), Vector3(0.06, 0.34, cz0 - cz1), WHITE, R.GELCOAT)
			acc.box(Transform3D(Basis(), Vector3(side * (cw - 0.28), cy + 0.06, (cz0 + cz1) * 0.5)), Vector3(0.45, 0.06, cz0 - cz1 - 0.3), BoatMesh.TEAK_C, R.TEAK)
		if acc.level == BoatMesh.Level.NEAR:
			var wz := BoatMesh._z(h, 0.14)
			acc.tube(Vector3(0.0, cy, wz), Vector3(0.0, cy + 0.85, wz), 0.06, 0.05, 6, STEEL, R.METAL)
			var rr := 0.55
			var prev := Vector3(0.0, cy + 0.85 + rr, wz - 0.05)
			for i in range(1, 17):
				var a := TAU * float(i) / 16.0
				var p := Vector3(sin(a) * rr, cy + 0.85 + cos(a) * rr, wz - 0.05)
				acc.tube(prev, p, 0.018, 0.018, 4, STEEL, R.METAL)
				prev = p
			# The helmsman and a crew sitting up to windward: dark figures in the cockpit.
			acc.box(Transform3D(Basis(), Vector3(0.0, cy + 0.45, wz + 0.55)), Vector3(0.42, 0.8, 0.3), Color(0.12, 0.13, 0.16), R.GELCOAT)
			acc.box(Transform3D(Basis(), Vector3(0.0, cy + 0.98, wz + 0.55)), Vector3(0.2, 0.24, 0.22), Color(0.55, 0.42, 0.33), R.GELCOAT)
	var top: Vector3 = r.top
	acc.tube(r.mast_foot, top, 0.11, 0.07, [8, 6, 4][acc.level], ALU, R.METAL)
	if acc.level != BoatMesh.Level.FAR:
		var stem: Vector3 = r.stem
		var fore_top: Vector3 = r.fore_top
		BoatMesh._line(acc, stem, fore_top, 0.014, STEEL, R.METAL, true)
		var tr := Vector3(0.0, BoatMesh._sheer(h, 0.0) + 0.1, BoatMesh._z(h, 0.0))
		BoatMesh._line(acc, top, tr, 0.012, STEEL, R.METAL, true)
		var mz := top.z
		var my: float = (r.mast_foot as Vector3).y + 0.4
		var sp_y := my + (top.y - my) * 0.52
		for side: float in [-1.0, 1.0]:
			var tip := Vector3(side * 1.05, sp_y, mz + 0.2)
			if acc.level == BoatMesh.Level.NEAR:
				acc.tube(Vector3(0.0, sp_y, mz), tip, 0.03, 0.02, 4, ALU, R.METAL)
			var plate := BoatMesh._sheer_point(h, 0.57, side, 0.1)
			BoatMesh._line(acc, plate, tip, 0.01, STEEL, R.METAL, true)
			BoatMesh._line(acc, tip, top + Vector3(0.0, -0.2, 0.0), 0.01, STEEL, R.METAL, true)
			BoatMesh._line(acc, BoatMesh._sheer_point(h, 0.65, side, 0.1), Vector3(side * 0.06, sp_y, mz), 0.009, STEEL, R.METAL)
	acc.box(Transform3D(Basis(), top + Vector3(0.0, 0.05, 0.0)), Vector3(0.16, 0.1, 0.32), ALU, R.METAL)
	acc.octa(top + Vector3(0.0, 0.18, 0.0), 0.06 if acc.level != BoatMesh.Level.FAR else 0.12, Color(1.0, 0.98, 0.9), R.LIGHT)
	BoatMesh._rails(acc, h, 0.08, 0.86, 0.62, 6, 2)
	BoatMesh._pulpit(acc, h, 0.62)
	if variant == 1 and acc.level != BoatMesh.Level.FAR:
		var dz := BoatMesh._z(h, 0.36)
		var cy2 := BoatMesh._sheer(h, 0.3)
		BoatMesh._canvas_hood(acc, Vector3(0.0, cy2, dz), BoatMesh._half_beam(h, 0.36) * 0.7, 0.95, 0.9, true)


## The mainsail on its boom, in the boom's frame: the gooseneck at the origin, the boom along +Z,
## the luff up +Y. `side` is the leeward side the sail bellies to (+1 starboard, -1 port).
static func main_sail(variant: int, side: float, level: int) -> ArrayMesh:
	var key := "main%d_%d_%d" % [variant, int(side), level]
	if _cache.has(key):
		return _cache[key]
	var acc := BoatMesh.Acc.new()
	acc.level = level
	var r := rig(variant)
	var lb: float = r.boom
	var luff: float = (r.top as Vector3).y - (r.gooseneck as Vector3).y - 0.5
	# The boom, and the vang down to the mast foot.
	acc.tube(Vector3(0.0, 0.0, 0.0), Vector3(0.0, 0.06, lb + 0.15), 0.07, 0.06, [6, 4, 3][level], ALU, R.METAL)
	if level == BoatMesh.Level.NEAR:
		acc.tube(Vector3(0.0, -0.05, 0.0), Vector3(0.0, -0.2, lb + 0.1), 0.02, 0.02, 3, BLACK, R.RUBBER)
	var rows := [12, 6, 2][level] as int
	var cols := [7, 4, 2][level] as int
	var grid: Array[PackedVector3Array] = []
	for i in rows + 1:
		var v := float(i) / float(rows)
		var y := 0.12 + v * luff
		# Chord: the foot's length tapering to a narrow head, with a little roach bulging the leech.
		var chord := lb * (1.0 - v) + 0.18 * v + lb * 0.1 * sin(PI * v)
		var depth := chord * 0.085 * (1.0 - 0.35 * v)
		# Twist: the upper sail falls off to leeward.
		var tw := side * v * 0.16
		var row := PackedVector3Array()
		for j in cols + 1:
			var u := float(j) / float(cols)
			var bel := sin(PI * pow(u, 0.75)) * depth
			var lx := side * bel
			var lz := 0.06 + u * chord
			row.append(Vector3(lx * cos(tw) + lz * sin(tw), y, -lx * sin(tw) + lz * cos(tw)))
		grid.append(row)
	acc.grid(grid, SAILCLOTH, R.SAIL, func(_p: Vector3) -> Vector3: return Vector3(side, 0.0, 0.0))
	if level == BoatMesh.Level.NEAR:
		# Battens and the leech line: thin darker lines across the sail, and the sail number.
		for k in 4:
			var v := 0.2 + float(k) * 0.19
			var i := roundi(v * rows)
			var row: PackedVector3Array = grid[mini(i, rows)]
			var a := row[cols].lerp(row[0], 0.35)
			BoatMesh._line(acc, row[cols] + Vector3(side * 0.01, 0.0, 0.0), a + Vector3(side * 0.01, 0.0, 0.0), 0.04, Color(0.8, 0.79, 0.75), R.SAIL)
	var m := acc.commit()
	_cache[key] = m
	return m


## The jib, in its own frame: the tack (stem fitting) at the origin, its luff up the forestay. The
## sail lies on the centre line at rest; Vessel turns it about the forestay to sheet it.
static func jib(variant: int, side: float, level: int) -> ArrayMesh:
	var key := "jib%d_%d_%d" % [variant, int(side), level]
	if _cache.has(key):
		return _cache[key]
	var acc := BoatMesh.Acc.new()
	acc.level = level
	var r := rig(variant)
	var stem: Vector3 = r.stem
	var head: Vector3 = (r.fore_top as Vector3) - stem
	head = head * 0.93
	var clew: Vector3 = (r.clew as Vector3) - stem
	var rows := [10, 5, 2][level] as int
	var cols := [6, 3, 2][level] as int
	var grid: Array[PackedVector3Array] = []
	for i in rows + 1:
		var v := float(i) / float(rows)
		var pl := head * v
		var pe := clew.lerp(head, v)
		var chord := pl.distance_to(pe)
		var row := PackedVector3Array()
		for j in cols + 1:
			var u := float(j) / float(cols)
			var bel := sin(PI * pow(u, 0.7)) * chord * 0.1
			row.append(pl.lerp(pe, u) + Vector3(side * bel, 0.0, 0.0))
		grid.append(row)
	acc.grid(grid, SAILCLOTH, R.SAIL, func(_p: Vector3) -> Vector3: return Vector3(side, 0.0, 0.0))
	var m := acc.commit()
	_cache[key] = m
	return m


# --- The pilot boat -------------------------------------------------------------------------------

static func _pilot(acc: BoatMesh.Acc) -> void:
	var h := BoatMesh.Hull.new()
	h.length = float(REF_LEN[Kind.PILOT])
	h.beam = float(REF_BEAM[Kind.PILOT])
	h.fb_stern = 1.5
	h.fb_bow = 2.6
	h.depth = 1.1
	h.vee = 0.9
	h.transom = 0.9
	h.max_at = 0.38
	h.fine = 1.9
	h.flare = 0.16
	h.rake = 1.1
	BoatMesh._hull(acc, h, Color(0.3, 0.31, 0.3), 0.0)
	var buff := Color(0.86, 0.84, 0.78)
	# The house: a tall raised cabin with big windows, its roof a platform for the mast.
	var y0 := BoatMesh._sheer(h, 0.45)
	BoatMesh._cabin(acc, h, 0.36, 0.72, y0, 2.15, 0.86, 0.45, 0.08, Vector2(0.42, 0.88), buff)
	var top_y := y0 + 2.15
	if acc.level != BoatMesh.Level.FAR:
		# The rub rail: a heavy black rubber fender round the sheer.
		for side: float in [-1.0, 1.0]:
			var prev := Vector3.ZERO
			for i in 15:
				var t := lerpf(0.02, 0.97, float(i) / 14.0)
				var p := BoatMesh._sheer_point(h, t, side) + Vector3(side * 0.08, -0.3, 0.0)
				if i > 0:
					acc.tube(prev, p, 0.16, 0.16, 6 if acc.level == BoatMesh.Level.NEAR else 4, BLACK, R.RUBBER)
				prev = p
		# PILOT in big letters on both sides of the house.
		var cz := (BoatMesh._z(h, 0.36) + BoatMesh._z(h, 0.72)) * 0.5
		for side: float in [-1.0, 1.0]:
			var wx := BoatMesh._half_beam(h, 0.54) * 0.86 + 0.02
			_text(acc, "PILOT", 0.62, Vector3(side * wx, y0 + 0.5, cz + 0.3), Vector3(0.0, 0.0, -side), Vector3(side, 0.0, 0.0), Color(0.08, 0.08, 0.09))
		# Mast on the house roof: radar, lights, an antenna.
		var mz := BoatMesh._z(h, 0.52)
		acc.tube(Vector3(0.0, top_y, mz), Vector3(0.0, top_y + 3.2, mz), 0.06, 0.05, 6, WHITE, R.GELCOAT)
		acc.box(Transform3D(Basis(), Vector3(0.0, top_y + 2.0, mz)), Vector3(1.6, 0.08, 0.08), WHITE, R.GELCOAT)
		acc.box(Transform3D(Basis(), Vector3(0.0, top_y + 0.35, mz + 0.4)), Vector3(1.4, 0.12, 0.35), Color(0.15, 0.15, 0.16), R.METAL)
		acc.tube(Vector3(0.6, top_y, mz + 0.8), Vector3(0.6, top_y + 2.4, mz + 0.8), 0.02, 0.01, 3, WHITE, R.METAL)
		# Handrails on the house roof and the foredeck grab rail.
		BoatMesh._rails(acc, h, 0.72, 0.93, 0.8, 4, 1)
		# The aft deck's towing post and a liferaft canister.
		acc.tube(Vector3(0.0, BoatMesh._sheer(h, 0.1), BoatMesh._z(h, 0.1)), Vector3(0.0, BoatMesh._sheer(h, 0.1) + 0.7, BoatMesh._z(h, 0.1)), 0.12, 0.12, 6, STEEL, R.METAL)
		acc.tube(Vector3(-0.9, top_y + 0.25, BoatMesh._z(h, 0.4)), Vector3(-0.2, top_y + 0.25, BoatMesh._z(h, 0.4)), 0.25, 0.25, 6, WHITE, R.GELCOAT)


# --- The tug --------------------------------------------------------------------------------------

static func _tug(acc: BoatMesh.Acc, variant: int) -> void:
	var h := BoatMesh.Hull.new()
	h.length = float(REF_LEN[Kind.TUG])
	h.beam = float(REF_BEAM[Kind.TUG])
	h.fb_stern = 1.6
	h.fb_bow = 3.3
	h.depth = 3.2
	h.vee = 0.25
	h.transom = 0.9
	h.max_at = 0.5
	h.fine = 1.25
	h.flare = 0.12
	h.rake = 0.6
	BoatMesh._hull(acc, h, Color(0.42, 0.13, 0.1), 0.9)
	var house := Color(0.92, 0.9, 0.84) if variant == 0 else Color(0.88, 0.72, 0.28)
	var stack := Color(0.75, 0.16, 0.1) if variant == 0 else Color(0.1, 0.22, 0.4)
	# The main deckhouse and the wheelhouse on it, glazed all round and a little proud.
	var y0 := BoatMesh._sheer(h, 0.55)
	BoatMesh._cabin(acc, h, 0.4, 0.74, y0 - 0.2, 2.6, 0.78, 0.0, 0.05, Vector2(0.45, 0.8), house, false)
	var y1 := y0 + 2.4
	BoatMesh._cabin(acc, h, 0.5, 0.69, y1, 2.3, 0.8, 0.25, 0.04, Vector2(0.3, 0.9), house)
	var y2 := y1 + 2.3
	if acc.level != BoatMesh.Level.FAR:
		# Fendering: the bow pudding (a fat rubber roll round the stem) and the side fenders.
		var prev := Vector3.ZERO
		for i in 9:
			var t := lerpf(0.8, 1.0, float(i) / 8.0)
			var p := BoatMesh._sheer_point(h, t, 1.0) + Vector3(0.15, -0.4, -0.15 * float(i) / 8.0)
			if i > 0:
				acc.tube(prev, p, 0.55, 0.55, 8 if acc.level == BoatMesh.Level.NEAR else 5, BLACK, R.RUBBER)
			prev = p
		prev = Vector3.ZERO
		for i in 9:
			var t := lerpf(0.8, 1.0, float(i) / 8.0)
			var p := BoatMesh._sheer_point(h, t, -1.0) + Vector3(-0.15, -0.4, -0.15 * float(i) / 8.0)
			if i > 0:
				acc.tube(prev, p, 0.55, 0.55, 8 if acc.level == BoatMesh.Level.NEAR else 5, BLACK, R.RUBBER)
			prev = p
		for side: float in [-1.0, 1.0]:
			# A band of rubber blocks along the sides at the sheer.
			var prev2 := Vector3.ZERO
			for i in 10:
				var t := lerpf(0.0, 0.82, float(i) / 9.0)
				var p := BoatMesh._sheer_point(h, t, side) + Vector3(side * 0.18, -0.55, 0.0)
				if i > 0:
					acc.tube(prev2, p, 0.3, 0.3, 6 if acc.level == BoatMesh.Level.NEAR else 4, BLACK, R.RUBBER)
				prev2 = p
			# Old tyres hung on the bulwark.
			if acc.level == BoatMesh.Level.NEAR:
				for k in 4:
					var t := 0.2 + float(k) * 0.15
					var p := BoatMesh._sheer_point(h, t, side) + Vector3(side * 0.42, -1.4, 0.0)
					acc.tube(p + Vector3(-side * 0.1, 0.0, 0.0), p + Vector3(side * 0.22, 0.0, 0.0), 0.45, 0.45, 8, Color(0.07, 0.07, 0.07), R.RUBBER)
		# Twin stacks behind the wheelhouse, banded in the company colour with black tops.
		var sz := BoatMesh._z(h, 0.43)
		for side: float in [-1.0, 1.0]:
			var a := Vector3(side * 1.6, y0 + 2.2, sz)
			acc.tube(a, a + Vector3(0.0, 3.0, 0.2), 0.42, 0.38, 8 if acc.level == BoatMesh.Level.NEAR else 5, stack, R.GELCOAT)
			acc.tube(a + Vector3(0.0, 3.0, 0.2), a + Vector3(0.0, 3.6, 0.24), 0.38, 0.37, 8 if acc.level == BoatMesh.Level.NEAR else 5, BLACK, R.GELCOAT)
		# The mast on the wheelhouse: a tripod-ish pole, yard, radar, lights.
		var mz := BoatMesh._z(h, 0.6)
		acc.tube(Vector3(0.0, y2, mz), Vector3(0.0, y2 + 5.0, mz), 0.12, 0.08, 6, house, R.GELCOAT)
		acc.box(Transform3D(Basis(), Vector3(0.0, y2 + 3.4, mz)), Vector3(2.6, 0.12, 0.12), house, R.GELCOAT)
		acc.box(Transform3D(Basis(), Vector3(0.0, y2 + 0.5, mz + 0.6)), Vector3(2.2, 0.14, 0.4), Color(0.15, 0.15, 0.16), R.METAL)
		acc.tube(Vector3(0.0, y2, mz + 0.6), Vector3(0.0, y2 + 0.45, mz + 0.6), 0.1, 0.1, 6, house, R.GELCOAT)
		# Wheelhouse roof rail.
		var ww := BoatMesh._half_beam(h, 0.6) * 0.8
		for side: float in [-1.0, 1.0]:
			acc.box(Transform3D(Basis(), Vector3(side * ww, y2 + 0.5, mz)), Vector3(0.05, 0.05, 4.0), STEEL, R.METAL)
		# The towing winch and its drum on the aft deck, the H-bitt at the stern, the staple.
		var dy := BoatMesh._sheer(h, 0.25)
		acc.box(Transform3D(Basis(), Vector3(0.0, dy + 0.6, BoatMesh._z(h, 0.32))), Vector3(3.6, 1.2, 1.6), Color(0.3, 0.35, 0.32), R.METAL)
		acc.tube(Vector3(-1.5, dy + 1.0, BoatMesh._z(h, 0.32)), Vector3(1.5, dy + 1.0, BoatMesh._z(h, 0.32)), 0.7, 0.7, 10 if acc.level == BoatMesh.Level.NEAR else 6, Color(0.14, 0.14, 0.14), R.METAL)
		var bz := BoatMesh._z(h, 0.08)
		for side: float in [-1.0, 1.0]:
			acc.tube(Vector3(side * 1.2, dy, bz), Vector3(side * 1.2, dy + 1.4, bz), 0.22, 0.22, 6, Color(0.82, 0.78, 0.2), R.METAL)
		acc.box(Transform3D(Basis(), Vector3(0.0, dy + 1.2, bz)), Vector3(2.6, 0.32, 0.32), Color(0.82, 0.78, 0.2), R.METAL)
		# The bow's bitts and the forward winch.
		acc.box(Transform3D(Basis(), Vector3(0.0, BoatMesh._sheer(h, 0.86) + 0.5, BoatMesh._z(h, 0.86))), Vector3(2.0, 1.0, 1.2), Color(0.3, 0.35, 0.32), R.METAL)
	else:
		acc.box(Transform3D(Basis(), Vector3(0.0, y2 + 2.0, BoatMesh._z(h, 0.5))), Vector3(3.0, 4.0, 0.6), stack, R.GELCOAT)


# --- The ferry ------------------------------------------------------------------------------------

static func _ferry(acc: BoatMesh.Acc, variant: int) -> void:
	var length := float(REF_LEN[Kind.FERRY])
	var beam := float(REF_BEAM[Kind.FERRY])
	var dh := BoatMesh.Hull.new()
	dh.length = length
	dh.beam = 2.9
	dh.fb_stern = 2.4
	dh.fb_bow = 3.1
	dh.depth = 1.4
	dh.vee = 0.75
	dh.transom = 0.85
	dh.max_at = 0.4
	dh.fine = 2.6
	dh.flare = 0.05
	dh.rake = 1.4
	var off := beam * 0.5 - dh.beam * 0.5
	for side: float in [-1.0, 1.0]:
		var tmp := BoatMesh.Acc.new()
		tmp.level = acc.level
		BoatMesh._hull(tmp, dh, Color(0.75, 0.76, 0.76), 0.0)
		_append(acc, tmp, Transform3D(Basis(), Vector3(side * off, 0.0, 0.0)))
	# The bridge deck between the hulls: its underside (the wet deck) 2.2 m over the water.
	var z0 := length * 0.46
	var z1 := -length * 0.4
	acc.box(Transform3D(Basis(), Vector3(0.0, 3.0, (z0 + z1) * 0.5)), Vector3(beam - 0.6, 1.0, z0 - z1), WHITE, R.GELCOAT)
	# The bow fairing: the bridge deck's front swept down and back between the demihulls.
	var fw := beam * 0.5 - 0.5
	acc.quad(Vector3(-fw, 3.5, z1), Vector3(fw, 3.5, z1), Vector3(fw * 0.6, 2.6, z1 + 4.0), Vector3(-fw * 0.6, 2.6, z1 + 4.0), WHITE, R.GELCOAT, Vector3(0.0, -0.3, -1.0))
	# The main passenger house: a long box with a raked, rounded front and a band of windows.
	var hz0 := length * 0.42
	var hz1 := -length * 0.3
	var hw := beam * 0.5 - 0.3
	_house(acc, hw, 3.5, 6.2, hz0, hz1, 6.5, Vector2(0.3, 0.86), FERRY_BAND, variant)
	# The upper deck: shorter, set back, and the wheelhouse forward on top of it.
	var uz0 := length * 0.2
	var uz1 := -length * 0.2
	_house(acc, hw - 0.5, 6.2, 8.6, uz0, uz1, 4.5, Vector2(0.25, 0.88), FERRY_BAND, variant)
	if acc.level != BoatMesh.Level.FAR:
		# The open sun deck aft of the upper house: a rail round it.
		for side: float in [-1.0, 1.0]:
			acc.box(Transform3D(Basis(), Vector3(side * (hw - 0.1), 7.2, (uz0 + hz0) * 0.5)), Vector3(0.05, 1.0, hz0 - uz0), Color(0.75, 0.82, 0.86), R.GLASS)
		acc.box(Transform3D(Basis(), Vector3(0.0, 7.2, hz0 - 0.05)), Vector3(hw * 2.0, 1.0, 0.05), Color(0.75, 0.82, 0.86), R.GLASS)
		# Wheelhouse roof: mast, radar, the horn and lights.
		var mz := uz1 + 2.0
		acc.tube(Vector3(0.0, 8.6, mz), Vector3(0.0, 12.4, mz + 0.3), 0.12, 0.08, 6, WHITE, R.GELCOAT)
		acc.box(Transform3D(Basis(), Vector3(0.0, 11.2, mz + 0.2)), Vector3(3.0, 0.12, 0.12), WHITE, R.GELCOAT)
		acc.box(Transform3D(Basis(), Vector3(0.0, 9.0, mz + 1.0)), Vector3(2.4, 0.14, 0.4), Color(0.15, 0.15, 0.16), R.METAL)
		# Waterjet housings on the transoms.
		for side: float in [-1.0, 1.0]:
			acc.box(Transform3D(Basis(), Vector3(side * off, 0.6, length * 0.5 + 0.5)), Vector3(1.2, 1.0, 1.2), Color(0.5, 0.52, 0.54), R.METAL)
		# The line's name on both sides of the house, and the vessel's on the bows.
		var name: String = FERRY_NAMES[variant % FERRY_NAMES.size()]
		for side: float in [-1.0, 1.0]:
			_text(acc, FERRY_LINE, 0.42, Vector3(side * (hw + 0.035), 3.98, (hz0 + hz1) * 0.5 + 2.0), Vector3(0.0, 0.0, -side), Vector3(side, 0.0, 0.0), WHITE)
			_text(acc, name, 0.42, Vector3(side * (off + dh.beam * 0.5 + 0.03), 2.4, -length * 0.36), Vector3(0.0, 0.0, -side), Vector3(side, 0.0, 0.0), Color(0.1, 0.12, 0.14))
		# Railings along the main deck's side walkways are glass panels (in the house's box).
	else:
		acc.box(Transform3D(Basis(), Vector3(0.0, 1.4, 0.0)), Vector3(beam * 0.9, 2.6, length * 0.9), WHITE, R.GELCOAT)


## A passenger house deck: from y0 to y1, between z0 (aft) and z1 (fore), half width w, its front
## raked and rounded over `nose` metres, a window band (fractions of its height) and a livery
## stripe under the windows.
static func _house(acc: BoatMesh.Acc, w: float, y0: float, y1: float, z0: float, z1: float, nose: float, win: Vector2, band: Color, _variant: int) -> void:
	var hgt := y1 - y0
	var segs := 5 if acc.level == BoatMesh.Level.NEAR else 2
	# Plan outline (x, z) of the house, going round: aft-left, aft-right, the right side forward,
	# the rounded nose, back down the left. Then extruded up in three bands: wall, glass, wall.
	var ring := PackedVector2Array()
	ring.append(Vector2(-w, z0))
	ring.append(Vector2(w, z0))
	for i in segs + 1:
		var a := PI * 0.5 * float(i) / float(segs)
		ring.append(Vector2(w * cos(a) + 0.0 * sin(a), z1 + nose - nose * sin(a)))
	for i in range(segs, -1, -1):
		var a := PI * 0.5 * float(i) / float(segs)
		ring.append(Vector2(-w * cos(a), z1 + nose - nose * sin(a)))
	var hy := [y0, y0 + hgt * win.x, y0 + hgt * win.y, y1]
	var cols := [WHITE, GLASS, WHITE]
	var regions := [R.GELCOAT, R.GLASS, R.GELCOAT]
	# The rake: the upper rings lean back over the nose.
	for b in 3:
		var ya: float = hy[b]
		var yb: float = hy[b + 1]
		var ra := (ya - y0) / hgt * 2.4
		var rb := (yb - y0) / hgt * 2.4
		for i in ring.size():
			var p := ring[i]
			var q := ring[(i + 1) % ring.size()]
			var fwd_p := clampf((z1 + nose - p.y) / maxf(nose, 0.1), 0.0, 1.0)
			var fwd_q := clampf((z1 + nose - q.y) / maxf(nose, 0.1), 0.0, 1.0)
			var a := Vector3(p.x, ya, p.y + ra * fwd_p)
			var bb := Vector3(q.x, ya, q.y + ra * fwd_q)
			var c := Vector3(q.x, yb, q.y + rb * fwd_q)
			var d := Vector3(p.x, yb, p.y + rb * fwd_p)
			var mid := Vector2((p.x + q.x) * 0.5, (p.y + q.y) * 0.5)
			var want := Vector3(mid.x, 0.0, mid.y - (z0 + z1) * 0.5)
			if i == 0:
				want = Vector3(0.0, 0.0, 1.0)
			acc.quad(a, bb, c, d, cols[b], regions[b], want)
	# The livery band under the windows and a thin stripe in it.
	if acc.level != BoatMesh.Level.FAR:
		for side: float in [-1.0, 1.0]:
			var yb2: float = hy[1]
			acc.box(Transform3D(Basis(), Vector3(side * (w + 0.015), yb2 - 0.35, (z0 + z1 + nose) * 0.5)), Vector3(0.02, 0.55, z0 - z1 - nose), band, R.GELCOAT)
			acc.box(Transform3D(Basis(), Vector3(side * (w + 0.02), yb2 - 0.72, (z0 + z1 + nose) * 0.5)), Vector3(0.02, 0.12, z0 - z1 - nose), FERRY_STRIPE, R.GELCOAT)
	# The roof.
	var roof := PackedVector3Array()
	for p in ring:
		var fwd := clampf((z1 + nose - p.y) / maxf(nose, 0.1), 0.0, 1.0)
		roof.append(Vector3(p.x, y1, p.y + 2.4 * fwd))
	acc.fan(roof, WHITE, R.GELCOAT, Vector3.UP)


# --- Helpers --------------------------------------------------------------------------------------

## Flat lettering (FreewayKit.text_geo(), TextMesh outlines) at `at`, reading along `along`, its face
## toward `out`, `height` metres tall. Skipped where the TextMesh gives no geometry (headless).
static func _text(acc: BoatMesh.Acc, text: String, height: float, at: Vector3, along: Vector3, out: Vector3, col: Color) -> void:
	if acc.level == BoatMesh.Level.FAR:
		return
	var geo: Array = FreewayKit.text_geo(text, height)
	var verts: PackedVector3Array = geo[0]
	var idx: PackedInt32Array = geo[1]
	if verts.is_empty():
		return
	var up := Vector3.UP
	for i in range(0, idx.size() - 2, 3):
		var p: Array[Vector3] = []
		for k in 3:
			var v := verts[idx[i + k]]
			p.append(at + along * v.x + up * v.y + out * 0.01)
		acc.tri(p[0], p[1], p[2], col, R.GELCOAT, out)


## Appends `src`'s triangles to `acc`, moved by `xf`.
static func _append(acc: BoatMesh.Acc, src: BoatMesh.Acc, xf: Transform3D) -> void:
	var base := acc.v.size()
	for i in src.v.size():
		acc.v.append(xf * src.v[i])
		acc.n.append((xf.basis * src.n[i]).normalized())
		acc.c.append(src.c[i])
		acc.uv.append(src.uv[i])
	for i in src.idx:
		acc.idx.append(base + i)
