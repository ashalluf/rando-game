class_name Landmarks
extends RefCounted
## Fixed one-off places on the west-coast map, built from primitives: the hill sign, the pier
## with its Ferris wheel and coaster loop, the observatory. Each has a world anchor; the chunk
## that contains the anchor builds the detailed version, and CityStreamer keeps a far version
## of every landmark alive so the skyline never loses them. All names and designs are original.

const SIGN_TEXT := "SHALLUFERWOOD"
## The second hill sign, on the affluent slope below the first.
const HILLS_SIGN_TEXT := "SHALLUFER HILLS"
## Metres the hill sign spans, whatever the text says. The letters are scaled to fit it, so a
## longer name does not run off the ridge or through the lots the landmark radius reserves.
const SIGN_SPAN := 342.0
const PIER_NAME := "RANDO PIER"

## 5 x 7 block font for the hill sign. Rows top to bottom, '#' is a block.
const FONT := {
	"R": ["####.", "#...#", "#...#", "####.", "#.#..", "#..#.", "#...#"],
	"U": ["#...#", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."],
	"A": [".###.", "#...#", "#...#", "#####", "#...#", "#...#", "#...#"],
	"N": ["#...#", "##..#", "#.#.#", "#..##", "#...#", "#...#", "#...#"],
	"D": ["####.", "#...#", "#...#", "#...#", "#...#", "#...#", "####."],
	"O": [".###.", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."],
	"W": ["#...#", "#...#", "#...#", "#.#.#", "#.#.#", "##.##", "#...#"],
	"S": [".####", "#....", "#....", ".###.", "....#", "....#", "####."],
	"H": ["#...#", "#...#", "#...#", "#####", "#...#", "#...#", "#...#"],
	"L": ["#....", "#....", "#....", "#....", "#....", "#....", "#####"],
	"F": ["#####", "#....", "#....", "####.", "#....", "#....", "#...."],
	"E": ["#####", "#....", "#....", "####.", "#....", "#....", "#####"],
	"I": [".###.", "..#..", "..#..", "..#..", "..#..", "..#..", ".###."],
	" ": [".....", ".....", ".....", ".....", ".....", ".....", "....."],
}


## Every landmark: id, anchor (world XZ), and a rough footprint radius.
static func all() -> Array[Dictionary]:
	return [
		{"id": "sign", "anchor": Vector2(0.0, -1180.0), "radius": 400.0},
		{"id": "hills_sign", "anchor": Vector2(480.0, -960.0), "radius": 70.0},
		{"id": "pier", "anchor": Vector2(-940.0, -350.0), "radius": 200.0},
		{"id": "observatory", "anchor": Vector2(260.0, -1320.0), "radius": 60.0},
		{"id": "crown_tower", "anchor": Vector2(700.0, 250.0), "radius": 34.0},
		{"id": "five_drums", "anchor": Vector2(590.0, 340.0), "radius": 42.0},
		{"id": "stack_tower", "anchor": Vector2(640.0, 150.0), "radius": 26.0},
		{"id": "needle", "anchor": Vector2(770.0, 330.0), "radius": 30.0},
		{"id": "campus_hall", "anchor": Vector2(-620.0, -520.0), "radius": 95.0},
		{"id": "twin_glass", "anchor": Vector2(600.0, 210.0), "radius": 46.0},
		{"id": "terminal", "anchor": Vector2(-350.0, 715.0), "radius": 120.0},
		{"id": "hangars", "anchor": Vector2(30.0, 830.0), "radius": 90.0},
		{"id": "cargo_ship", "anchor": Vector2(800.0, 1420.0), "radius": 100.0},
		# The LA set. Anchors are placed the way the real chain runs: the boardwalk on the sand
		# at Venice, a straight pier off Manhattan Beach, the timber horseshoe at Redondo where
		# the coast meets the headland, the enclosed mall inland behind them, a corner coffee
		# house on the Westside and a neighbourhood mosque in the city.
		{"id": "venice_boardwalk", "anchor": Vector2(-949.0, -340.0), "radius": 230.0},
		{"id": "manhattan_pier", "anchor": Vector2(-690.0, 1100.0), "radius": 210.0},
		{"id": "redondo_pier", "anchor": Vector2(-765.0, 1450.0), "radius": 210.0},
		# 215, not 150: the mall grades and paves a site 210 m out in X and 187 m to the south,
		# and radius is what stops city lots being planted in it and keeps the relief flat
		# under it. At 150 the west half of the parking structure had blocks growing through it.
		{"id": "south_bay_mall", "anchor": Vector2(-250.0, 1250.0), "radius": 215.0},
		{"id": "verde_cafe", "anchor": Vector2(-900.0, -430.0), "radius": 22.0},
		# The mosque sits on one suburban parcel, not on a crossroads: (-180, 120) put the
		# prayer hall on the intersection of the road at x -177 and the road at z 118, with
		# the forecourt straddling the carriageway. This anchor is the middle of the block
		# bounded by those two roads, set so the gate steps stop just short of the south
		# pavement. Radius 52 covers the 45 m from the hall centre to the gate steps.
		{"id": "masjid_al_noor", "anchor": Vector2(-235.7, 165.2), "radius": 52.0},
		# --- Downtown LA civic set (owner, 2026-09-24: "downtown must match real downtown LA,
		# we need staple center we need all day"). Real FORMS in their real places relative to
		# the core; every NAME is invented (LandmarkArenaDistrict, LandmarkCivicCenter).
		# Position, footprint and orientation of each - and the real building's position in
		# metres from a downtown origin - live in ONE table, CivicSites.SITES, so re-laying
		# downtown only has to change that table. Each is a block site ("site": "block"): it
		# takes the whole block its anchor falls in (Landmarks.claims()) and is laid out inside
		# that block's pavement, so it never sits on a road whatever the seed.
		# South-west of the core: the arena, its entertainment plaza north across the street,
		# the plaza's hotel tower on the next block east, the convention centre south.
		# North-east: city hall (it used to stand across the road at x 824, under the 110 deck),
		# the park north of its steps, the concert hall and the museum, the station past the 5.
		CivicSites.entry("arena"), CivicSites.entry("live_plaza"), CivicSites.entry("live_hotel"),
		CivicSites.entry("convention_center"), CivicSites.entry("ziggurat_hall"), CivicSites.entry("civic_park"),
		CivicSites.entry("concert_hall"), CivicSites.entry("lattice_museum"), CivicSites.entry("pueblo_station"),
	]


static var _site_anchors: PackedVector2Array = PackedVector2Array()
static var _site_anchors_ready: bool = false


## True when a landmark takes the whole block `rect` (its "site" is "block" and its anchor lies
## inside it). CityPlan then plans nothing else there: no lots, and the block's own park, plaza
## or mall roll is overridden, so the landmark has the block to itself.
static func claims(rect: Rect2) -> bool:
	if not _site_anchors_ready:
		for lm in all():
			if lm.get("site", "") == "block":
				_site_anchors.append(lm.anchor)
		_site_anchors_ready = true
	for a in _site_anchors:
		if rect.has_point(a):
			return true
	return false


## The ground a block-site landmark is laid out on: the block its anchor falls in, inside the
## pavement ring (which stays pavement, with the street's lamps, trees and walkers on it).
## Layouts fit themselves to this rect, so a different seed's grid moves the landmark with it
## rather than putting it across a road.
static func site_rect(plan: CityPlan, anchor: Vector2) -> Rect2:
	if plan == null:
		return Rect2(anchor - Vector2(40.0, 40.0), Vector2(80.0, 80.0))
	var idx := plan.block_index_at(anchor)
	var rect: Rect2 = plan.block(idx.x, idx.y).rect
	return rect.grow(-plan.sidewalk_width)


## Crowds a landmark wants in its detailed version: [[rect, sidewalk, count], ...]. The chunk
## spawns them as ordinary pedestrians (the ring they wander is `rect` inset by `sidewalk`, and a
## `sidewalk` of half the rect's size lets them mill about the whole of it).
static func crowds(lm: Dictionary, plan: CityPlan) -> Array:
	if CivicSites.SITES.has(lm.id):
		return CivicSites.crowds(lm.id, plan)
	return []


## True when world XZ `p` (grown by `pad` metres) is inside a landmark building that stands on
## city ground the street grid does not know about, so street things must not be put there.
static func covers(plan: CityPlan, p: Vector2, pad: float) -> bool:
	for lm in all():
		if lm.id == "venice_boardwalk" and p.distance_to(lm.anchor) < float(lm.radius) + pad:
			if LandmarkVeniceBoardwalk.covers(lm.anchor, plan, p, pad):
				return true
	return false


static func in_rect(rect: Rect2) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for lm in all():
		if rect.has_point(lm.anchor):
			result.append(lm)
	return result


## Builds a landmark under `parent` (children at true world coordinates). `statics` may be null
## (far version: no collision). Returns nothing; the builder adds nodes directly.
static func build(lm: Dictionary, parent: Node3D, statics: StaticBody3D, plan: CityPlan, detailed: bool) -> void:
	match lm.id:
		"sign":
			_build_sign(lm.anchor, parent, statics, plan, detailed)
		"hills_sign":
			_build_hills_sign(lm.anchor, parent, statics, plan, detailed)
		"pier":
			_build_pier(lm.anchor, parent, statics, plan, detailed)
		"observatory":
			_build_observatory(lm.anchor, parent, statics, plan, detailed)
		"crown_tower":
			_build_crown_tower(lm.anchor, parent, statics, detailed)
		"five_drums":
			_build_five_drums(lm.anchor, parent, statics, detailed)
		"stack_tower":
			_build_stack_tower(lm.anchor, parent, statics, detailed)
		"needle":
			_build_needle(lm.anchor, parent, statics, detailed)
		"campus_hall":
			_build_campus_hall(lm.anchor, parent, statics, detailed)
		"twin_glass":
			_build_twin_glass(lm.anchor, parent, statics, detailed)
		"terminal":
			_build_terminal(lm.anchor, parent, statics, plan, detailed)
		"hangars":
			_build_hangars(lm.anchor, parent, statics, detailed)
		"cargo_ship":
			_build_cargo_ship(lm.anchor, parent, statics, detailed)
		"venice_boardwalk":
			LandmarkVeniceBoardwalk.build(lm.anchor, parent, statics, plan, detailed)
		"manhattan_pier":
			LandmarkBeachPiers.build_manhattan(lm.anchor, parent, statics, plan, detailed)
		"redondo_pier":
			LandmarkBeachPiers.build_redondo(lm.anchor, parent, statics, plan, detailed)
		"south_bay_mall":
			LandmarkSouthBayMall.build(lm.anchor, parent, statics, plan, detailed)
		"verde_cafe":
			LandmarkVerdeCafe.build(lm.anchor, parent, statics, plan, detailed)
		"masjid_al_noor":
			LandmarkMasjidAlNoor.build(lm.anchor, parent, statics, plan, detailed)
		# Downtown LA civic set (see all() and CivicSites).
		"arena", "live_plaza", "live_hotel", "convention_center", "ziggurat_hall", "civic_park", "concert_hall", "lattice_museum", "pueblo_station":
			CivicSites.build(lm.id, parent, statics, plan, detailed)


# --- Hill sign ------------------------------------------------------------------------------

## The ridge sign's letter line in world XZ - the first and last letter centres - and the real
## ground its letters are levelled on, the highest under any of them. The far version stands on
## the far ground rather than the real one and is seated from these by far_canopy.gdshader.
static func sign_line(anchor: Vector2, plan: CityPlan) -> Dictionary:
	var n := SIGN_TEXT.length()
	var cell: float = SIGN_SPAN / (float(n) * 5.0 + float(n - 1) * 1.5)
	var letter_w := 5.0 * cell
	var gap := cell * 1.5
	var total := float(n) * letter_w + float(n - 1) * gap
	var x := anchor.x - total * 0.5
	var ground := -1e20
	for i in n:
		ground = maxf(ground, plan.height_at(Vector2(x + (float(i) + 0.5) * (letter_w + gap), anchor.y)))
	return {
		"a": Vector2(x + 0.5 * letter_w, anchor.y),
		"b": Vector2(x + total - 0.5 * letter_w, anchor.y),
		"ground": ground,
	}


static func _build_sign(anchor: Vector2, parent: Node3D, statics: StaticBody3D, plan: CityPlan, detailed: bool) -> void:
	# Fit the name to the ridge rather than fixing the letter size: SHALLUFERWOOD is thirteen
	# characters where RANDOWOOD was nine, and at the old fixed 6 m cell it would have run half
	# a kilometre across the hill and straight through the lots the landmark radius reserves.
	var n := SIGN_TEXT.length()
	var cell: float = SIGN_SPAN / (float(n) * 5.0 + float(n - 1) * 1.5)
	var letter_w := 5.0 * cell
	var gap := cell * 1.5
	var total := float(n) * letter_w + float(n - 1) * gap
	var x := anchor.x - total * 0.5
	var white := Color(0.96, 0.96, 0.94)
	# ONE level line for the whole name, taken from the highest ground under it. Each letter
	# used to sit on the ground beneath itself, which on an uneven ridge sank whichever letters
	# landed in a fold - the S of SHALLUFERWOOD vanished into the hillside entirely and the name
	# read HALLUFERWOOD. A hill sign is built level on legs of different lengths, which is what
	# the leg loop below already draws; the letters just were not using it.
	var base_y: float = sign_line(anchor, plan).ground + 2.0
	for ch in SIGN_TEXT:
		var rows: Array = FONT.get(ch, FONT["O"])
		for r in rows.size():
			var row: String = rows[r]
			var c := 0
			while c < row.length():
				if row[c] != "#":
					c += 1
					continue
				var run := 0
				while c + run < row.length() and row[c + run] == "#":
					run += 1
				var size := Vector3(run * cell, cell, 2.0)
				var pos := Vector3(x + (c + run * 0.5) * cell, base_y + (rows.size() - 1 - r + 0.5) * cell, anchor.y)
				_box(parent, statics, size, pos, white, detailed)
				c += run
		if detailed and ch != " ":
			# Legs down to the slope.
			for lx: float in [0.5, letter_w - 0.5]:
				var ground := plan.height_at(Vector2(x + lx, anchor.y + 1.5))
				var h := maxf(base_y - ground + 1.0, 1.0)
				_cyl(parent, null, 0.35, h, Vector3(x + lx, ground + h * 0.5, anchor.y + 1.5), Color(0.35, 0.35, 0.36))
		x += letter_w + gap


# --- Shallufer Hills sign -------------------------------------------------------------------

## The civic sign on the slope below the ridge letters: a low landscaped bank with the name
## standing on it, a clipped hedge behind, and a stone kerb in front. Original design - it is a
## name on a planted bank, not a copy of any real municipality's badge.
##
## Much smaller lettering than the ridge sign (this one is read from the road, not from across
## the basin), so it uses its own cell size rather than SIGN_SPAN.
static func _build_hills_sign(anchor_xz: Vector2, parent: Node3D, statics: StaticBody3D, plan: CityPlan, detailed: bool) -> void:
	var cell := 1.15
	var n := HILLS_SIGN_TEXT.length()
	var letter_w := 5.0 * cell
	var gap := cell * 1.5
	var total := float(n) * letter_w + float(n - 1) * gap
	var ground := plan.height_at(anchor_xz)
	var cream := Color(0.94, 0.92, 0.86)
	var hedge := Color(0.15, 0.24, 0.13)
	var stone := Color(0.72, 0.70, 0.65)
	var lawn := Color(0.24, 0.34, 0.18)
	# The bank the name sits on, then a clipped hedge behind it so the cream letters have
	# something dark to read against - which is the whole trick of this kind of sign.
	_box(parent, statics, Vector3(total + 10.0, 1.6, 7.0), Vector3(anchor_xz.x, ground + 0.8, anchor_xz.y), lawn, detailed)
	_box(parent, statics, Vector3(total + 8.0, 3.2, 1.6), Vector3(anchor_xz.x, ground + 3.2, anchor_xz.y - 2.4), hedge, detailed)
	# Stone kerb along the front.
	_box(parent, statics, Vector3(total + 10.0, 0.5, 0.7), Vector3(anchor_xz.x, ground + 1.8, anchor_xz.y + 3.2), stone, detailed)
	var x := anchor_xz.x - total * 0.5
	var base_y := ground + 1.7
	for ch in HILLS_SIGN_TEXT:
		var rows: Array = FONT.get(ch, FONT["O"])
		for r in rows.size():
			var row: String = rows[r]
			var c := 0
			while c < row.length():
				if row[c] != "#":
					c += 1
					continue
				var run := 0
				while c + run < row.length() and row[c + run] == "#":
					run += 1
				_box(parent, null,
					Vector3(run * cell, cell, 0.45),
					Vector3(x + (c + run * 0.5) * cell, base_y + (rows.size() - 1 - r + 0.5) * cell, anchor_xz.y),
					cream, false)
				c += run
		x += letter_w + gap


# --- Pier -----------------------------------------------------------------------------------

static func _build_pier(anchor: Vector2, parent: Node3D, statics: StaticBody3D, _plan: CityPlan, detailed: bool) -> void:
	var deck_y := 6.0
	var length := 280.0
	var width := 24.0
	var wood := Color(0.55, 0.40, 0.25)
	var dark := Color(0.30, 0.25, 0.20)
	# Deck runs west from the anchor (the beach end) out over the water.
	var center := Vector3(anchor.x - length * 0.5, deck_y, anchor.y)
	_box(parent, statics, Vector3(length, 0.8, width), center, wood, true)
	# Ramp from the sand up to the deck.
	var ramp_len := 30.0
	var ramp := _box(parent, statics, Vector3(ramp_len, 0.8, 8.0), Vector3(anchor.x + ramp_len * 0.5 - 2.0, deck_y * 0.5, anchor.y), wood, true)
	ramp.rotation.z = atan2(deck_y, ramp_len)
	# Railings.
	for side: float in [-1.0, 1.0]:
		_box(parent, statics, Vector3(length, 1.0, 0.15), center + Vector3(0.0, 0.9, side * (width * 0.5 - 0.1)), dark, true)
	# Piles.
	var step := 12.0 if detailed else 40.0
	var px := anchor.x - 6.0
	while px > anchor.x - length + 4.0:
		for side: float in [-1.0, 1.0]:
			_cyl(parent, null, 0.5, deck_y + 2.0, Vector3(px, deck_y * 0.5 - 1.0, anchor.y + side * (width * 0.5 - 2.0)), dark)
		px -= step
	# Entrance arch with the name.
	var arch_x := anchor.x - 8.0
	for side: float in [-1.0, 1.0]:
		_box(parent, statics, Vector3(0.8, 9.0, 0.8), Vector3(arch_x, deck_y + 4.5, anchor.y + side * 9.0), Color(0.2, 0.5, 0.7), true)
	_box(parent, statics, Vector3(1.2, 2.4, 20.0), Vector3(arch_x, deck_y + 9.6, anchor.y), Color(0.95, 0.85, 0.3), true)
	var label := Label3D.new()
	label.text = PIER_NAME
	label.font_size = 160
	label.pixel_size = 0.02
	label.outline_size = 24
	label.modulate = Color(0.15, 0.15, 0.2)
	label.position = Vector3(arch_x + 0.7, deck_y + 9.6, anchor.y)
	label.rotation.y = PI * 0.5
	parent.add_child(label)
	# Ferris wheel.
	_build_ferris_wheel(Vector3(anchor.x - 110.0, deck_y, anchor.y), parent, statics, detailed)
	# Coaster loop near the end.
	_build_coaster(Vector3(anchor.x - 220.0, deck_y, anchor.y), parent, statics, detailed)
	if not detailed:
		return
	# Booths and lamps along the deck.
	var colors := [Color(0.9, 0.3, 0.3), Color(0.3, 0.6, 0.9), Color(0.95, 0.75, 0.2), Color(0.5, 0.8, 0.4)]
	for i in 6:
		var bx := anchor.x - 30.0 - i * 12.0
		var side := 1.0 if i % 2 == 0 else -1.0
		var col: Color = colors[i % colors.size()]
		_box(parent, statics, Vector3(4.0, 3.0, 3.0), Vector3(bx, deck_y + 1.9, anchor.y + side * 8.0), col, true)
		_box(parent, null, Vector3(4.6, 0.3, 4.2), Vector3(bx, deck_y + 3.6, anchor.y + side * 7.5), col.darkened(0.3), false)
	for i in 10:
		var lx := anchor.x - 20.0 - i * 26.0
		for side: float in [-1.0, 1.0]:
			_cyl(parent, null, 0.1, 5.0, Vector3(lx, deck_y + 2.9, anchor.y + side * (width * 0.5 - 1.0)), Color(0.28, 0.29, 0.32))
			_box(parent, null, Vector3(0.6, 0.2, 0.3), Vector3(lx, deck_y + 5.5, anchor.y + side * (width * 0.5 - 1.0)), Color(1.0, 0.95, 0.8), false)


static func _build_ferris_wheel(at: Vector3, parent: Node3D, statics: StaticBody3D, detailed: bool) -> void:
	var radius := 24.0
	var hub := at + Vector3(0.0, radius + 6.0, 0.0)
	var steel := Color(0.85, 0.2, 0.25)
	# A-frame supports (visual) and one collision box for the whole footprint.
	for side: float in [-1.0, 1.0]:
		var leg := _box(parent, null, Vector3(1.2, radius + 8.0, 1.2), hub + Vector3(0.0, -(radius + 6.0) * 0.5, side * 6.0), Color(0.3, 0.3, 0.32), false)
		leg.rotation.x = side * 0.18
	if statics:
		_shape(statics, Vector3(6.0, 8.0, 14.0), at + Vector3(0.0, 4.0, 0.0))
	var wheel := FerrisWheel.new()
	wheel.position = hub
	parent.add_child(wheel)
	var spokes := 12 if detailed else 6
	for i in spokes:
		var angle := TAU * i / spokes
		var spoke := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.4, radius * 2.0, 0.4)
		spoke.mesh = box
		spoke.material_override = PropFactory.material(steel)
		spoke.rotation.z = angle
		wheel.add_child(spoke)
	# Rim segments.
	var segments := 24 if detailed else 12
	for i in segments:
		var angle := TAU * (i + 0.5) / segments
		var seg := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(TAU * radius / segments + 0.3, 0.5, 0.5)
		seg.mesh = box
		seg.material_override = PropFactory.material(steel)
		seg.position = Vector3(cos(angle), sin(angle), 0.0) * radius
		seg.rotation.z = angle + PI * 0.5
		wheel.add_child(seg)
	# Gondolas hang from the rim and stay upright.
	var gondola_colors := [Color(0.95, 0.75, 0.2), Color(0.3, 0.6, 0.9), Color(0.5, 0.8, 0.4), Color(0.9, 0.4, 0.6)]
	for i in segments / 2:
		var angle := TAU * i / (segments / 2)
		var g := Node3D.new()
		g.position = Vector3(cos(angle), sin(angle), 0.0) * radius
		wheel.add_child(g)
		wheel.gondolas.append(g)
		var cab := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(2.4, 2.2, 2.4)
		cab.mesh = box
		cab.material_override = PropFactory.material(gondola_colors[i % gondola_colors.size()])
		cab.position = Vector3(0.0, -1.6, 0.0)
		g.add_child(cab)


static func _build_coaster(at: Vector3, parent: Node3D, statics: StaticBody3D, detailed: bool) -> void:
	var radius := 14.0
	var rail := Color(0.95, 0.6, 0.15)
	var center := at + Vector3(0.0, radius + 2.0, 0.0)
	var segments := 24 if detailed else 12
	for i in segments:
		var angle := TAU * (i + 0.5) / segments
		var seg := _box(parent, null, Vector3(TAU * radius / segments + 0.3, 0.5, 2.0), center + Vector3(cos(angle), sin(angle), 0.0) * radius, rail, false)
		seg.rotation.z = angle + PI * 0.5
	# Straight track in and out of the loop, plus supports.
	_box(parent, statics, Vector3(60.0, 0.5, 2.0), at + Vector3(0.0, 2.0, 0.0), rail, true)
	for i in 5:
		_cyl(parent, null, 0.25, 2.0, at + Vector3(-28.0 + i * 14.0, 1.0, 0.0), Color(0.3, 0.3, 0.32))
	for side: float in [-1.0, 1.0]:
		var brace := _box(parent, null, Vector3(0.6, radius * 2.0 + 4.0, 0.6), center + Vector3(side * radius * 0.7, 0.0, 0.0), Color(0.3, 0.3, 0.32), false)
		brace.rotation.z = -side * 0.35
	if statics:
		_shape(statics, Vector3(radius * 2.0 + 2.0, radius * 2.0 + 2.0, 3.0), center)
	# A little parked train.
	for i in 3:
		_box(parent, null, Vector3(3.0, 1.6, 1.8), at + Vector3(-24.0 + i * 3.4, 3.1, 0.0), Color(0.2, 0.5, 0.85), false)


# --- Observatory ----------------------------------------------------------------------------

static func _build_observatory(anchor: Vector2, parent: Node3D, statics: StaticBody3D, plan: CityPlan, detailed: bool) -> void:
	var ground := plan.height_at(anchor)
	var base_y := ground + 4.0
	var white := Color(0.94, 0.93, 0.90)
	var copper := Color(0.35, 0.55, 0.50)
	# Tall plinth so it never floats on the slope, then the main hall.
	_box(parent, statics, Vector3(56.0, 30.0, 34.0), Vector3(anchor.x, base_y - 15.0 + 0.5, anchor.y), Color(0.75, 0.72, 0.68), true)
	_box(parent, statics, Vector3(48.0, 10.0, 26.0), Vector3(anchor.x, base_y + 5.0, anchor.y), white, true)
	# Center drum and dome, two side domes.
	_cyl(parent, statics, 9.0, 8.0, Vector3(anchor.x, base_y + 14.0, anchor.y), white)
	_dome(parent, statics, 9.0, Vector3(anchor.x, base_y + 18.0, anchor.y), copper)
	for side: float in [-1.0, 1.0]:
		_cyl(parent, statics, 5.0, 4.0, Vector3(anchor.x + side * 19.0, base_y + 12.0, anchor.y), white)
		_dome(parent, statics, 5.0, Vector3(anchor.x + side * 19.0, base_y + 14.0, anchor.y), copper)
	# Front lawn and a viewing terrace facing the city (south, +Z).
	_box(parent, statics, Vector3(70.0, 1.0, 20.0), Vector3(anchor.x, base_y - 0.5, anchor.y + 27.0), Color(0.38, 0.5, 0.28), true)
	if not detailed:
		return
	for i in 7:
		_box(parent, statics, Vector3(0.3, 1.1, 0.3), Vector3(anchor.x - 30.0 + i * 10.0, base_y + 0.55, anchor.y + 36.5), Color(0.3, 0.3, 0.32), true)
	_box(parent, null, Vector3(70.0, 0.15, 0.15), Vector3(anchor.x, base_y + 1.1, anchor.y + 36.5), Color(0.3, 0.3, 0.32), false)
	# Coin telescopes on the terrace.
	for i in 3:
		_cyl(parent, null, 0.12, 1.3, Vector3(anchor.x - 20.0 + i * 20.0, base_y + 0.65, anchor.y + 34.0), Color(0.3, 0.3, 0.32))
		var scope := _box(parent, null, Vector3(0.3, 0.3, 1.2), Vector3(anchor.x - 20.0 + i * 20.0, base_y + 1.4, anchor.y + 34.0), Color(0.85, 0.85, 0.88), false)
		scope.rotation.x = -0.3


# --- Downtown skyline -----------------------------------------------------------------------

const GLASS_DARK := Color(0.16, 0.24, 0.36)
const GLASS_GREEN := Color(0.14, 0.30, 0.30)
const PLINTH := Color(0.62, 0.60, 0.58)

## The tallest tower: square shaft, glass, a lit crown of fins and a spire.
static func _build_crown_tower(anchor: Vector2, parent: Node3D, statics: StaticBody3D, detailed: bool) -> void:
	var base := Vector3(anchor.x, 0.25, anchor.y)
	_facade_box(parent, statics, Vector3(44.0, 14.0, 44.0), base + Vector3(0.0, 7.0, 0.0), PLINTH, Building.Finish.PANELS, Building.WindowStyle.RIBBON, 6.0)
	_facade_box(parent, statics, Vector3(34.0, 190.0, 34.0), base + Vector3(0.0, 14.0 + 95.0, 0.0), GLASS_DARK, Building.Finish.GLASS, Building.WindowStyle.CURTAIN, 0.0)
	var top := base.y + 204.0
	# Crown: a ring of fins and a glowing band.
	var fins := 16 if detailed else 8
	for i in fins:
		var a := TAU * i / fins
		var fin := _box(parent, null, Vector3(1.2, 14.0, 3.0), Vector3(base.x + cos(a) * 19.0, top + 7.0, base.z + sin(a) * 19.0), Color(0.9, 0.9, 0.92), false)
		fin.rotation.y = -a
	var band := _box(parent, null, Vector3(36.0, 1.5, 36.0), Vector3(base.x, top + 14.5, base.z), Color(1.0, 0.85, 0.5), false)
	band.material_override = WeaponFX.unshaded(Color(1.0, 0.85, 0.5))
	_cyl(parent, statics, 1.0, 40.0, Vector3(base.x, top + 34.0, base.z), Color(0.8, 0.8, 0.82))
	if statics:
		_shape(statics, Vector3(38.0, 16.0, 38.0), Vector3(base.x, top + 8.0, base.z))


## Five mirrored glass cylinders on a shared podium.
static func _build_five_drums(anchor: Vector2, parent: Node3D, statics: StaticBody3D, detailed: bool) -> void:
	var base := Vector3(anchor.x, 0.25, anchor.y)
	_facade_box(parent, statics, Vector3(80.0, 18.0, 80.0), base + Vector3(0.0, 9.0, 0.0), PLINTH, Building.Finish.PANELS, Building.WindowStyle.RIBBON, 6.0)
	var mirror := Color(0.55, 0.65, 0.75)
	_mirror_cyl(parent, statics, 15.0, 120.0, base + Vector3(0.0, 18.0 + 60.0, 0.0), mirror)
	for dx: float in [-1.0, 1.0]:
		for dz: float in [-1.0, 1.0]:
			_mirror_cyl(parent, statics, 11.0, 88.0, base + Vector3(dx * 26.0, 18.0 + 44.0, dz * 26.0), mirror)
	if detailed:
		# Floor rings on the central drum.
		for i in 6:
			_cyl(parent, null, 15.6, 0.6, base + Vector3(0.0, 18.0 + 18.0 * (i + 1), 0.0), Color(0.3, 0.32, 0.36))


## A round tower with overhanging floor discs and a needle.
static func _build_stack_tower(anchor: Vector2, parent: Node3D, statics: StaticBody3D, detailed: bool) -> void:
	var base := Vector3(anchor.x, 0.25, anchor.y)
	var cream := Color(0.92, 0.90, 0.84)
	var floors := 13
	var floor_h := 4.6
	_cyl(parent, statics, 12.0, floors * floor_h, base + Vector3(0.0, floors * floor_h * 0.5, 0.0), Color(0.18, 0.28, 0.36))
	var discs := floors if detailed else floors / 2
	for i in discs:
		var step := floors / float(discs)
		_cyl(parent, null, 14.5, 0.9, base + Vector3(0.0, (i + 1) * step * floor_h, 0.0), cream)
	var top := base.y + floors * floor_h
	_cyl(parent, statics, 5.0, 4.0, base + Vector3(0.0, top - base.y + 2.0, 0.0), cream)
	_cyl(parent, null, 0.5, 30.0, Vector3(base.x, top + 19.0, base.z), Color(0.85, 0.2, 0.2))
	var beacon := _box(parent, null, Vector3(1.2, 1.2, 1.2), Vector3(base.x, top + 34.5, base.z), Color(1.0, 0.2, 0.2), false)
	beacon.material_override = WeaponFX.unshaded(Color(1.0, 0.25, 0.2))


## The tallest thing in town: a slim tapering glass needle, 320 m plus a 70 m mast.
static func _build_needle(anchor: Vector2, parent: Node3D, statics: StaticBody3D, detailed: bool) -> void:
	var base := Vector3(anchor.x, 0.25, anchor.y)
	_facade_box(parent, statics, Vector3(46.0, 10.0, 46.0), base + Vector3(0.0, 5.0, 0.0), PLINTH, Building.Finish.PANELS, Building.WindowStyle.RIBBON, 6.0)
	var y := base.y + 10.0
	var w := 30.0
	var tiers := [110.0, 90.0, 70.0, 50.0]
	for i in tiers.size():
		var h: float = tiers[i]
		_facade_box(parent, statics, Vector3(w, h, w), Vector3(base.x, y + h * 0.5, base.z), GLASS_GREEN, Building.Finish.GLASS, Building.WindowStyle.CURTAIN, 0.0)
		y += h
		w -= 5.0
	# Crown: lit ring and a mast with a beacon.
	var ring := _cyl(parent, null, w * 0.5 + 2.0, 1.2, Vector3(base.x, y + 0.6, base.z), Color(1.0, 0.9, 0.6))
	ring.material_override = WeaponFX.unshaded(Color(1.0, 0.9, 0.6))
	_cyl(parent, statics, 1.6, 70.0, Vector3(base.x, y + 35.0, base.z), Color(0.82, 0.82, 0.86))
	var beacon := _box(parent, null, Vector3(1.5, 1.5, 1.5), Vector3(base.x, y + 70.8, base.z), Color(1.0, 0.2, 0.2), false)
	beacon.material_override = WeaponFX.unshaded(Color(1.0, 0.25, 0.2))
	if detailed:
		for i in 8:
			var a := TAU * i / 8
			_box(parent, null, Vector3(0.8, 6.0, 2.0), Vector3(base.x + cos(a) * (w * 0.5 + 1.0), y + 3.5, base.z + sin(a) * (w * 0.5 + 1.0)), Color(0.9, 0.9, 0.92), false).rotation.y = -a


## Twin glass towers on a shared podium, joined by a sky bridge near the top.
static func _build_twin_glass(anchor: Vector2, parent: Node3D, statics: StaticBody3D, detailed: bool) -> void:
	var base := Vector3(anchor.x, 0.25, anchor.y)
	_facade_box(parent, statics, Vector3(84.0, 16.0, 50.0), base + Vector3(0.0, 8.0, 0.0), PLINTH, Building.Finish.PANELS, Building.WindowStyle.RIBBON, 6.0)
	var h := 210.0
	for dx: float in [-1.0, 1.0]:
		var cx := base.x + dx * 24.0
		_facade_box(parent, statics, Vector3(28.0, h, 34.0), Vector3(cx, base.y + 16.0 + h * 0.5, base.z), GLASS_DARK, Building.Finish.GLASS, Building.WindowStyle.CURTAIN, 0.0)
		# Crown fins and a short spire on each tower.
		var top := base.y + 16.0 + h
		_facade_box(parent, statics, Vector3(18.0, 9.0, 22.0), Vector3(cx, top + 4.5, base.z), GLASS_DARK, Building.Finish.GLASS, Building.WindowStyle.CURTAIN, 0.0)
		_cyl(parent, null, 0.6, 26.0, Vector3(cx, top + 9.0 + 13.0, base.z), Color(0.85, 0.85, 0.88))
		var tip := _box(parent, null, Vector3(0.8, 0.8, 0.8), Vector3(cx, top + 35.4, base.z), Color(1.0, 0.2, 0.15), false)
		tip.material_override = WeaponFX.unshaded(Color(1.0, 0.25, 0.2))
	# Sky bridge two-thirds up, glowing at night like a lit floor.
	var bridge_y := base.y + 16.0 + h * 0.68
	_facade_box(parent, statics, Vector3(22.0, 7.0, 12.0), Vector3(base.x, bridge_y, base.z), Color(0.75, 0.78, 0.82), Building.Finish.GLASS, Building.WindowStyle.RIBBON, 0.0)
	if detailed:
		for i in 3:
			_box(parent, null, Vector3(22.0, 0.5, 0.4), Vector3(base.x, bridge_y - 3.5 + i * 3.4, base.z + 6.2), Color(0.3, 0.32, 0.36), false)


# --- University campus ----------------------------------------------------------------------

const BRICK_RED := Color(0.62, 0.32, 0.24)
const CAMPUS_TEXT := "RANDO U"

## The heart of the campus: a brick main hall with twin towers and a dome, grand steps, a quad
## with paths and a fountain in front, a bell tower and a lettered sign. Original design.
static func _build_campus_hall(anchor: Vector2, parent: Node3D, statics: StaticBody3D, detailed: bool) -> void:
	var base := Vector3(anchor.x, 0.25, anchor.y)
	var stone := Color(0.86, 0.82, 0.74)
	# Quad lawn with cross paths (the hall faces +Z, the quad lies in front of it).
	var lawn := _box(parent, statics, Vector3(120.0, 0.3, 80.0), base + Vector3(0.0, 0.15, 30.0), Color(0.45, 0.62, 0.32), true)
	lawn.material_override = PropFactory.pbr("grass", 5.0, Color(0.8, 0.95, 0.75))
	for path_size: Vector3 in [Vector3(6.0, 0.1, 80.0), Vector3(120.0, 0.1, 6.0)]:
		var path := _box(parent, null, path_size, base + Vector3(0.0, 0.36, 30.0), stone, false)
		path.material_override = PropFactory.pbr("paving", 3.0, Color(0.95, 0.93, 0.9))
	# Main hall: brick, punched windows, a stone plinth and steps.
	_facade_box(parent, statics, Vector3(76.0, 3.0, 34.0), base + Vector3(0.0, 1.5, -40.0), stone, Building.Finish.PANELS, Building.WindowStyle.NARROW, 0.0)
	_facade_box(parent, statics, Vector3(72.0, 22.0, 30.0), base + Vector3(0.0, 3.0 + 11.0, -40.0), BRICK_RED, Building.Finish.BRICK, Building.WindowStyle.PUNCHED, 0.0)
	for i in 4:
		_box(parent, statics, Vector3(24.0 - i * 4.0, 0.7, 6.0 - i * 1.2), base + Vector3(0.0, 0.35 + i * 0.7, -22.0 + i * 1.0), stone, true)
	# Portico columns.
	for i in 6:
		_cyl(parent, statics, 0.9, 14.0, base + Vector3(-15.0 + i * 6.0, 3.0 + 7.0, -23.5), stone)
	_box(parent, statics, Vector3(36.0, 2.0, 5.0), base + Vector3(0.0, 3.0 + 15.0, -23.5), stone, true)
	# Twin towers on the front corners with pyramid caps.
	for dx: float in [-1.0, 1.0]:
		var tx := base.x + dx * 30.0
		_facade_box(parent, statics, Vector3(12.0, 40.0, 12.0), Vector3(tx, base.y + 3.0 + 20.0, base.z - 28.0), BRICK_RED, Building.Finish.BRICK, Building.WindowStyle.NARROW, 0.0)
		_cone(parent, 7.5, 8.0, Vector3(tx, base.y + 43.0 + 4.0, base.z - 28.0), Color(0.35, 0.45, 0.5))
	# Dome on a drum over the center.
	_cyl(parent, statics, 11.0, 8.0, base + Vector3(0.0, 25.0 + 4.0, -40.0), stone)
	var dome := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 11.5
	sphere.height = 23.0
	sphere.radial_segments = 24 if detailed else 12
	sphere.rings = 12 if detailed else 6
	dome.mesh = sphere
	dome.material_override = PropFactory.material(Color(0.36, 0.5, 0.48), 0.5)
	dome.position = base + Vector3(0.0, 33.0, -40.0)
	parent.add_child(dome)
	if statics:
		_shape(statics, Vector3(22.0, 12.0, 22.0), base + Vector3(0.0, 39.0, -40.0))
	# Bell tower off the north-east corner, lit belfry.
	var bt := base + Vector3(52.0, 0.0, -10.0)
	_facade_box(parent, statics, Vector3(9.0, 46.0, 9.0), bt + Vector3(0.0, 23.0, 0.0), BRICK_RED, Building.Finish.BRICK, Building.WindowStyle.NARROW, 0.0)
	var belfry := _box(parent, statics, Vector3(7.5, 5.0, 7.5), bt + Vector3(0.0, 48.5, 0.0), Color(1.0, 0.9, 0.7), true)
	belfry.material_override = WeaponFX.unshaded(Color(1.0, 0.88, 0.62))
	_cone(parent, 6.0, 7.0, bt + Vector3(0.0, 51.0 + 3.5, 0.0), Color(0.35, 0.45, 0.5))
	# Fountain in the middle of the quad.
	var fc := base + Vector3(0.0, 0.3, 30.0)
	_cyl(parent, statics, 7.0, 1.0, fc + Vector3(0.0, 0.5, 0.0), stone)
	var water := _cyl(parent, null, 6.4, 0.3, fc + Vector3(0.0, 0.95, 0.0), Color(0.3, 0.65, 0.85))
	var wmat := StandardMaterial3D.new()
	wmat.albedo_color = Color(0.3, 0.65, 0.85)
	wmat.roughness = 0.05
	water.material_override = wmat
	_cyl(parent, statics, 1.2, 4.0, fc + Vector3(0.0, 2.5, 0.0), stone)
	_cyl(parent, null, 3.0, 0.4, fc + Vector3(0.0, 4.5, 0.0), stone)
	# Sign wall at the front of the quad with the letters on it.
	var sign_at := base + Vector3(0.0, 0.3, 72.0)
	_box(parent, statics, Vector3(30.0, 2.4, 1.2), sign_at + Vector3(0.0, 1.2, 0.0), stone, true)
	_text(CAMPUS_TEXT, 0.5, sign_at + Vector3(0.0, 2.8, 0.0), parent, Color(0.2, 0.22, 0.3))
	if detailed:
		# Trees along the quad edges.
		for i in 8:
			for dz: float in [-1.0, 1.0]:
				_tree(parent, base + Vector3(-52.0 + i * 15.0, 0.3, 30.0 + dz * 36.0))


static func _cone(parent: Node3D, radius: float, height: float, pos: Vector3, color: Color) -> void:
	var mesh := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.0
	cyl.bottom_radius = radius
	cyl.height = height
	cyl.radial_segments = 4
	mesh.mesh = cyl
	mesh.rotation.y = PI * 0.25
	mesh.material_override = PropFactory.material(color, 0.7)
	mesh.position = pos
	parent.add_child(mesh)


static func _tree(parent: Node3D, at: Vector3) -> void:
	_cyl(parent, null, 0.35, 4.0, at + Vector3(0.0, 2.0, 0.0), Color(0.4, 0.28, 0.18))
	var crown := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 3.2
	sphere.height = 6.4
	sphere.radial_segments = 10
	sphere.rings = 5
	crown.mesh = sphere
	crown.material_override = PropFactory.material(Color(0.25, 0.5, 0.22), 0.9)
	crown.position = at + Vector3(0.0, 6.2, 0.0)
	parent.add_child(crown)


## Block letters from FONT along +X, centered on `center` (which is the bottom-center).
static func _text(text: String, cell: float, center: Vector3, parent: Node3D, color: Color) -> void:
	var letter_w := 5 * cell
	var gap := cell * 1.5
	var total := text.length() * letter_w + (text.length() - 1) * gap
	var x := center.x - total * 0.5
	for ch in text:
		if ch == " ":
			x += letter_w + gap
			continue
		var rows: Array = FONT.get(ch, FONT["O"])
		for r in rows.size():
			var row: String = rows[r]
			var c := 0
			while c < row.length():
				if row[c] != "#":
					c += 1
					continue
				var run := 0
				while c + run < row.length() and row[c + run] == "#":
					run += 1
				_box(parent, null, Vector3(run * cell, cell, 0.3), Vector3(x + (c + run * 0.5) * cell, center.y + (rows.size() - 1 - r + 0.5) * cell, center.z), color, false)
				c += run
		x += letter_w + gap


# --- Airport terminal and cargo ship ---------------------------------------------------------

## Terminal hall, control tower, and a saucer-shaped restaurant on crossed arches.
static func _build_terminal(anchor: Vector2, parent: Node3D, statics: StaticBody3D, plan: CityPlan, detailed: bool) -> void:
	var macro: MacroMap = plan.macro if plan else null
	var base := Vector3(anchor.x, macro.tarmac_top if macro else 0.1, anchor.y)
	_facade_box(parent, statics, Vector3(160.0, 12.0, 40.0), base + Vector3(0.0, 6.0, -60.0), Color(0.80, 0.80, 0.78), Building.Finish.PANELS, Building.WindowStyle.RIBBON, 0.0)
	# Control tower.
	_cyl(parent, statics, 4.0, 46.0, base + Vector3(-100.0, 23.0, -60.0), Color(0.85, 0.85, 0.83))
	_cyl(parent, statics, 9.0, 6.0, base + Vector3(-100.0, 49.0, -60.0), Color(0.25, 0.4, 0.55))
	_cyl(parent, null, 9.5, 0.8, base + Vector3(-100.0, 52.4, -60.0), Color(0.85, 0.85, 0.83))
	# Saucer restaurant on four crossed arches, beside the hall (clear of the apron taxi lane).
	var sc := base + Vector3(0.0, 0.0, -34.0)
	for i in 4:
		var a := PI * 0.25 + i * PI * 0.5
		var leg := _box(parent, null, Vector3(2.0, 34.0, 2.0), sc + Vector3(cos(a) * 12.0, 15.0, sin(a) * 12.0), Color(0.92, 0.92, 0.9), false)
		leg.rotation.z = -cos(a) * 0.55
		leg.rotation.x = sin(a) * 0.55
	_cyl(parent, statics, 2.5, 28.0, sc + Vector3(0.0, 14.0, 0.0), Color(0.6, 0.6, 0.62))
	_cyl(parent, statics, 14.0, 4.0, sc + Vector3(0.0, 28.0, 0.0), Color(0.92, 0.92, 0.9))
	_cyl(parent, null, 12.0, 3.0, sc + Vector3(0.0, 31.5, 0.0), Color(0.25, 0.4, 0.55))
	_dome(parent, null, 4.0, sc + Vector3(0.0, 33.0, 0.0), Color(0.92, 0.92, 0.9))
	# Jet bridges reaching from the hall toward the apron (the flyable jets park below them).
	for i in 4:
		_box(parent, statics, Vector3(3.0, 3.0, 18.0), base + Vector3(-60.0 + i * 40.0, 5.5, -31.0), Color(0.7, 0.72, 0.75), detailed)
		_box(parent, null, Vector3(2.0, 4.0, 2.0), base + Vector3(-60.0 + i * 40.0, 2.0, -24.0), Color(0.5, 0.5, 0.52), false)
	# The kerb and the road come from MacroMap, which is also where TrafficManager reads the lane
	# paths that have to sit on them.
	_build_dropoff(parent, statics, macro, detailed)


## The drop-off loop in front of the terminal: a dark two-way road with a median, lane lines,
## a raised curb strip along the hall with pillars and "DEPARTURES" signs. Traffic crawls the
## loop lanes from MacroMap.terminal_loops; the crowd on the curb comes from the airport chunk.
static func _build_dropoff(parent: Node3D, statics: StaticBody3D, macro: MacroMap, detailed: bool) -> void:
	if macro == null:
		return
	var curb: Rect2 = macro.terminal_curb
	var y: float = macro.tarmac_top
	var road: Rect2 = macro.terminal_road
	var rc := road.get_center()
	var asphalt := _box(parent, null, Vector3(road.size.x, macro.dropoff_top - y, road.size.y), Vector3(rc.x, (y + macro.dropoff_top) * 0.5, rc.y), Color(0.5, 0.5, 0.52), false)
	# 0.79, not 0.55: the tint is sRGB-decoded and multiplies a texture whose own mean is already
	# asphalt's reflectance, so 0.55 laid this at an albedo of 0.022. See CityChunk.ROAD_TINTS.
	asphalt.material_override = PropFactory.pbr("asphalt", 7.0, Color(0.79, 0.79, 0.81))
	# Median and lane lines.
	_box(parent, null, Vector3(road.size.x - 30.0, 0.16, 1.6), Vector3(rc.x, y + 0.14, rc.y), Color(0.72, 0.72, 0.7), false)
	for lz: float in [617.5, 602.5]:
		_box(parent, null, Vector3(road.size.x - 34.0, 0.012, 0.14), Vector3(rc.x, y + 0.068, lz), Color(0.95, 0.95, 0.95), false)
	for lz: float in [623.6, 596.4]:
		_box(parent, null, Vector3(road.size.x - 30.0, 0.012, 0.14), Vector3(rc.x, y + 0.068, lz), Color(0.9, 0.9, 0.9), false)
	# Curb strip along the hall, a step up, with pillars carrying a canopy and the signs.
	var cc := curb.get_center()
	var strip := _box(parent, statics, Vector3(curb.size.x + 20.0, 0.24, curb.size.y + 1.0), Vector3(cc.x, y + 0.12, cc.y + 0.5), Color(0.8, 0.79, 0.76), detailed)
	strip.material_override = PropFactory.pbr("sidewalk", 3.0, Color(0.95, 0.95, 0.95))
	for i in 7:
		var px := curb.position.x - 6.0 + i * (curb.size.x + 12.0) / 6.0
		_box(parent, statics, Vector3(0.7, 6.0, 0.7), Vector3(px, y + 3.2, curb.position.y + 1.2), Color(0.6, 0.62, 0.66), detailed)
	_box(parent, null, Vector3(curb.size.x + 20.0, 0.5, 9.0), Vector3(cc.x, y + 6.4, curb.position.y + 4.0), Color(0.85, 0.86, 0.88), false)
	if detailed:
		for sx: float in [cc.x - 50.0, cc.x, cc.x + 50.0]:
			var sign := MeshInstance3D.new()
			sign.mesh = PropFactory.text_mesh("DEPARTURES", 1.1)
			sign.material_override = PropFactory.material(Color(1.0, 0.85, 0.2), 0.5, true)
			sign.position = Vector3(sx, y + 5.4, curb.position.y - 0.3)
			sign.rotation.y = PI # TextMesh reads from +Z; the road is on the -Z side
			parent.add_child(sign)


## Three hangars with barrel roofs, a fuel farm and a beacon at the east end of the field.
static func _build_hangars(anchor: Vector2, parent: Node3D, statics: StaticBody3D, detailed: bool) -> void:
	var base := Vector3(anchor.x, 0.1, anchor.y)
	var wall := Color(0.78, 0.78, 0.76)
	for i in 3:
		var at := base + Vector3(0.0, 0.0, -60.0 + i * 60.0)
		_box(parent, statics, Vector3(60.0, 12.0, 44.0), at + Vector3(0.0, 6.0, 0.0), wall, true)
		var roof := _cyl(parent, statics, 22.0, 60.0, at + Vector3(0.0, 12.0, 0.0), Color(0.6, 0.62, 0.66))
		roof.rotation.z = PI * 0.5
		# Big door face on the west side.
		_box(parent, null, Vector3(0.4, 10.0, 36.0), at + Vector3(-30.1, 5.0, 0.0), Color(0.45, 0.5, 0.58), false)
	for i in 3:
		_cyl(parent, statics, 6.0, 9.0, base + Vector3(45.0, 4.5, -30.0 + i * 24.0), Color(0.9, 0.9, 0.92))
	_cyl(parent, statics, 1.0, 18.0, base + Vector3(45.0, 9.0, 60.0), Color(0.85, 0.85, 0.88))
	var beacon := _box(parent, null, Vector3(1.4, 1.4, 1.4), base + Vector3(45.0, 18.9, 60.0), Color(1.0, 1.0, 1.0), false)
	beacon.material_override = WeaponFX.unshaded(Color(1.0, 1.0, 0.9))
	if detailed:
		for i in 6:
			_box(parent, null, Vector3(3.0, 2.2, 1.6), base + Vector3(-40.0 + i * 8.0, 1.2, 75.0), Color(0.85, 0.7, 0.2), false)


## A container ship moored in the harbor, bow pointing west.
static func _build_cargo_ship(anchor: Vector2, parent: Node3D, statics: StaticBody3D, detailed: bool) -> void:
	var at := Vector3(anchor.x, 0.0, anchor.y)
	var hull := Color(0.55, 0.15, 0.12)
	_box(parent, statics, Vector3(180.0, 12.0, 30.0), at + Vector3(0.0, 2.0, 0.0), hull, true)
	var bow := _box(parent, statics, Vector3(24.0, 12.0, 24.0), at + Vector3(-92.0, 2.0, 0.0), hull, true)
	bow.rotation.y = PI * 0.25
	_box(parent, statics, Vector3(182.0, 1.0, 32.0), at + Vector3(0.0, 8.5, 0.0), Color(0.3, 0.3, 0.32), true)
	# Bridge at the stern, funnel, containers on deck.
	_box(parent, statics, Vector3(14.0, 22.0, 26.0), at + Vector3(78.0, 20.0, 0.0), Color(0.92, 0.92, 0.9), true)
	_box(parent, null, Vector3(16.0, 3.0, 28.0), at + Vector3(78.0, 32.0, 0.0), Color(0.25, 0.4, 0.55), false)
	_cyl(parent, statics, 3.0, 10.0, at + Vector3(84.0, 36.0, 0.0), Color(0.85, 0.65, 0.2))
	var colors := [Color(0.8, 0.25, 0.2), Color(0.2, 0.45, 0.75), Color(0.85, 0.6, 0.15), Color(0.3, 0.6, 0.35)]
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var stacks := 10 if detailed else 5
	var stack_step := 14.0 if detailed else 28.0
	for i in stacks:
		var x := -70.0 + i * stack_step
		for row in 3:
			var z := (row - 1) * 8.0
			var height := rng.randi_range(2, 4) if detailed else 3
			for h in height:
				_box(parent, null, Vector3(12.0, 2.6, 2.4 * 3.0), at + Vector3(x, 9.0 + 1.3 + h * 2.6, z), colors[rng.randi() % colors.size()], false)
			if statics:
				_shape(statics, Vector3(12.0, 2.6 * height, 7.2), at + Vector3(x, 9.0 + 1.3 * height, z))


# --- Building-shader helpers -----------------------------------------------------------------

## A box that uses the building shader so it gets windows and lit floors.
static func _facade_box(parent: Node3D, statics: StaticBody3D, size: Vector3, pos: Vector3, facade: Color, finish: int, style: int, storefront: float) -> MeshInstance3D:
	var mat := ShaderMaterial.new()
	mat.shader = Building.SHADER
	mat.set_shader_parameter("facade_color", facade)
	mat.set_shader_parameter("accent_color", facade.darkened(0.55))
	mat.set_shader_parameter("facade_finish", finish)
	mat.set_shader_parameter("window_style", style)
	mat.set_shader_parameter("window_tint", Color(0.4, 0.55, 0.7))
	mat.set_shader_parameter("lit_color", Color(1.0, 0.85, 0.55))
	mat.set_shader_parameter("lit_ratio", 0.45)
	var pitch := 2.2
	mat.set_shader_parameter("window_pitch_x", size.x / maxi(1, roundi(size.x / pitch)))
	mat.set_shader_parameter("window_pitch_z", size.z / maxi(1, roundi(size.z / pitch)))
	var bottom := pos.y - size.y * 0.5
	var usable := size.y - storefront
	mat.set_shader_parameter("floor_height", usable / maxi(1, roundi(usable / 3.6)))
	mat.set_shader_parameter("ground_floor_height", bottom + storefront)
	mat.set_shader_parameter("has_storefront", storefront > 0.0)
	mat.set_shader_parameter("part_size", size)
	mat.set_shader_parameter("seed", float(int(pos.x + pos.z * 7.0) % 1000))
	Building._apply_wall_texture(mat, finish, false)
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = mat
	mesh.position = pos
	parent.add_child(mesh)
	if statics:
		_shape(statics, size, pos)
	return mesh


static func _mirror_cyl(parent: Node3D, statics: StaticBody3D, radius: float, height: float, pos: Vector3, color: Color) -> void:
	var mesh := _cyl(parent, statics, radius, height, pos, color)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = 0.85
	mat.roughness = 0.12
	mesh.material_override = mat


# --- Helpers --------------------------------------------------------------------------------

static func _box(parent: Node3D, statics: StaticBody3D, size: Vector3, pos: Vector3, color: Color, collide: bool) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = PropFactory.material(color)
	mesh.position = pos
	parent.add_child(mesh)
	if collide and statics:
		_shape(statics, size, pos)
	return mesh


static func _cyl(parent: Node3D, statics: StaticBody3D, radius: float, height: float, pos: Vector3, color: Color) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = height
	cyl.radial_segments = 12
	mesh.mesh = cyl
	mesh.material_override = PropFactory.material(color)
	mesh.position = pos
	parent.add_child(mesh)
	if statics:
		var shape := CollisionShape3D.new()
		var s := CylinderShape3D.new()
		s.radius = radius
		s.height = height
		shape.shape = s
		shape.position = pos
		statics.add_child(shape)
	return mesh


static func _dome(parent: Node3D, statics: StaticBody3D, radius: float, pos: Vector3, color: Color) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	sphere.is_hemisphere = true
	sphere.radial_segments = 16
	sphere.rings = 8
	mesh.mesh = sphere
	mesh.material_override = PropFactory.material(color, 0.5)
	mesh.position = pos
	parent.add_child(mesh)
	if statics:
		var shape := CollisionShape3D.new()
		var s := SphereShape3D.new()
		s.radius = radius
		shape.shape = s
		shape.position = pos
		statics.add_child(shape)
	return mesh


static func _shape(statics: StaticBody3D, size: Vector3, pos: Vector3) -> void:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = pos
	statics.add_child(shape)
