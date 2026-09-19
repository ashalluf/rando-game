class_name Landmarks
extends RefCounted
## Fixed one-off places on the west-coast map, built from primitives: the hill sign, the pier
## with its Ferris wheel and coaster loop, the observatory. Each has a world anchor; the chunk
## that contains the anchor builds the detailed version, and CityStreamer keeps a far version
## of every landmark alive so the skyline never loses them. All names and designs are original.

const SIGN_TEXT := "RANDOWOOD"
const PIER_NAME := "RANDO PIER"

## 5 x 7 block font for the hill sign. Rows top to bottom, '#' is a block.
const FONT := {
	"R": ["####.", "#...#", "#...#", "####.", "#.#..", "#..#.", "#...#"],
	"A": [".###.", "#...#", "#...#", "#####", "#...#", "#...#", "#...#"],
	"N": ["#...#", "##..#", "#.#.#", "#..##", "#...#", "#...#", "#...#"],
	"D": ["####.", "#...#", "#...#", "#...#", "#...#", "#...#", "####."],
	"O": [".###.", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."],
	"W": ["#...#", "#...#", "#...#", "#.#.#", "#.#.#", "##.##", "#...#"],
}


## Every landmark: id, anchor (world XZ), and a rough footprint radius.
static func all() -> Array[Dictionary]:
	return [
		{"id": "sign", "anchor": Vector2(0.0, -1180.0), "radius": 400.0},
		{"id": "pier", "anchor": Vector2(-940.0, -350.0), "radius": 200.0},
		{"id": "observatory", "anchor": Vector2(260.0, -1320.0), "radius": 60.0},
	]


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
		"pier":
			_build_pier(lm.anchor, parent, statics, plan, detailed)
		"observatory":
			_build_observatory(lm.anchor, parent, statics, plan, detailed)


# --- Hill sign ------------------------------------------------------------------------------

static func _build_sign(anchor: Vector2, parent: Node3D, statics: StaticBody3D, plan: CityPlan, detailed: bool) -> void:
	var cell := 6.0
	var letter_w := 5 * cell
	var gap := cell * 1.5
	var total := SIGN_TEXT.length() * letter_w + (SIGN_TEXT.length() - 1) * gap
	var x := anchor.x - total * 0.5
	var white := Color(0.96, 0.96, 0.94)
	for ch in SIGN_TEXT:
		var rows: Array = FONT.get(ch, FONT["O"])
		var base_y := plan.height_at(Vector2(x + letter_w * 0.5, anchor.y)) + 2.0
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
		if detailed:
			# Legs down to the slope.
			for lx: float in [0.5, letter_w - 0.5]:
				var ground := plan.height_at(Vector2(x + lx, anchor.y + 1.5))
				var h := maxf(base_y - ground + 1.0, 1.0)
				_cyl(parent, null, 0.35, h, Vector3(x + lx, ground + h * 0.5, anchor.y + 1.5), Color(0.35, 0.35, 0.36))
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


static func _dome(parent: Node3D, statics: StaticBody3D, radius: float, pos: Vector3, color: Color) -> void:
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


static func _shape(statics: StaticBody3D, size: Vector3, pos: Vector3) -> void:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = pos
	statics.add_child(shape)
