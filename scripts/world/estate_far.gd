class_name EstateFar
## The hillside estates as the basin sees them, past the FULL chunks: the LOD chunks' copy and the
## far city's (Skyline). Each estate HillRoads places is a few unit boxes on
## shaders/far_estate.gdshader - the pad standing on its retaining walls with a lawn (or a gravel
## garden) on top, the paved motor court, hedges along the sides, the house with its windows and
## its roof, the pool with its coping - and its lamps: two on the gate piers, two at the door,
## garden lights round the lawn and lamps down a long driveway, which light after dark and never
## shrink under a pixel or two, so a canyon of estates reads at night from across the basin as
## what it is: dark ground with lit windows, garden lights and a turquoise pool. They used to be
## one pale box each (a pavers slab under it at LOD), which read as a grey disc on the dark hills.
##
## Everything is laid out in the estate's frame as CityChunk._build_mansions builds the real one
## (x across the pad, z toward the gate, the house 4 m back), and every roll is a hash of the
## estate's seed, except the pool's side and offset, which replay that function's own first two
## rolls so the pool does not jump at the hand-over. `parts()` is pure.
##
## ESTATE_NIGHT=0 in the environment puts the old pale box (and the LOD's pavers pad) back: the A/B.

## Part kinds (far_estate.gdshader): pad, house, roof, pool, lamp, plain (court, coping, hedge).
const K_PAD := 0
const K_HOUSE := 1
const K_ROOF := 2
const K_POOL := 3
const K_LAMP := 4
const K_PLAIN := 5
## Added to the kind when the part stands on the real terrain (a LOD chunk drew it), not the far plane.
const REAL := 8

## The pad as CityChunk builds it (ESTATE_PAD) and how far its retaining walls go down below the
## deck, so a pad seated on a sloping far plane never shows daylight under its downhill side.
const PAD := Vector3(26.0, 0.4, 22.0)
const SKIRT := 6.0
## Lamp heads (metres): the shader grows them to lamp_min_angle with distance.
const LAMP_SIZE := 0.35
## Driveway lamps every this many metres down a drive longer than DRIVE_MIN.
const DRIVE_LAMP_STEP := 18.0
const DRIVE_MIN := 8.0

## Garden tops (LINEAR): watered lawn mostly, now and then a gravel and succulent garden.
const LAWNS: Array[Color] = [Color(0.055, 0.10, 0.03), Color(0.07, 0.115, 0.035), Color(0.045, 0.085, 0.028), Color(0.19, 0.16, 0.115)]
## Walls (LINEAR): the stucco CityChunk paints the estates' walls, a little darker.
## (At 0.8-0.9, like the old box's 0.92, a house glowed white in the moonlight across the basin.)
const WALLS: Array[Color] = [Color(0.50, 0.46, 0.39), Color(0.44, 0.37, 0.28), Color(0.53, 0.51, 0.47), Color(0.34, 0.28, 0.21), Color(0.20, 0.18, 0.16)]
## Roofs (LINEAR): clay tile, dark gravel, grey membrane, dark standing seam.
const ROOFS: Array[Color] = [Color(0.26, 0.085, 0.045), Color(0.22, 0.10, 0.06), Color(0.10, 0.095, 0.09), Color(0.32, 0.31, 0.29), Color(0.05, 0.05, 0.055)]
## The FULL estate's lawn (CityChunk._build_mansions): [centre over the deck, size] in the pad's
## frame, down both sides of the motor court and behind the house, under the pool and the walls.
const LAWN_PIECES: Array = [[Vector3(-9.25, 0.03, 0.0), Vector3(7.5, 0.06, 21.0)], [Vector3(9.25, 0.03, 0.0), Vector3(7.5, 0.06, 21.0)],
	[Vector3(0.0, 0.03, -8.5), Vector3(11.0, 0.06, 4.0)]]
const COURT := Color(0.40, 0.37, 0.32)
const COPING := Color(0.62, 0.60, 0.56)
const HEDGE := Color(0.022, 0.045, 0.018)

static var enabled: bool = OS.get_environment("ESTATE_NIGHT") != "0"
static var _material: ShaderMaterial
static var _mesh: Mesh


## The shared material (one for the far city and every LOD chunk; CityStreamer gives it the far
## plane's uniforms as it does far_canopy's).
static func material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = load("res://shaders/far_estate.gdshader")
	return _material


## A unit box wearing material(), for the LOD chunks' batch.
static func mesh() -> Mesh:
	if _mesh == null:
		var box := BoxMesh.new()
		box.size = Vector3.ONE
		box.material = material()
		_mesh = box
	return _mesh


## 0..1 from the estate's seed and a tag.
static func _h(s: int, tag: Variant) -> float:
	return float(absi(hash([s, "estate_far", tag])) % 10007) / 10007.0


## Every part of estate `m` (a HillRoads mansion: pos, height, yaw, seed, drive_from): an Array of
## [Transform3D of a unit box, linear Color (alpha 1), custom Color]. `real` when the parts stand
## on the real terrain (a LOD chunk); `ground` (Callable Vector2 -> float, may be invalid) is the
## real ground for the driveway lamps.
static func parts(m: Dictionary, real: bool, ground: Callable = Callable()) -> Array:
	var out: Array = []
	var s: int = int(m.seed)
	var pos: Vector2 = m.pos
	var yaw: float = m.yaw
	var basis := Basis(Vector3.UP, yaw)
	var deck := float(m.height) + PAD.y
	var centre := Vector3(pos.x, deck, pos.y)
	var add := func(local: Vector3, size: Vector3, kind: int, color: Color, variant: float) -> void:
		var at := centre + basis * local
		var off := Vector2(at.x - pos.x, at.z - pos.y)
		var code := float(kind + (REAL if real else 0)) + clampf(variant, 0.0, 0.99)
		out.append([Transform3D(basis.scaled_local(size), at), Color(color.r, color.g, color.b, 1.0), Color(at.y - deck, code, off.x, off.y)])
	# The pad, its top the garden, on its retaining walls.
	var lawn: Color = LAWNS[int(_h(s, "lawn") * LAWNS.size()) % LAWNS.size()]
	add.call(Vector3(0.0, 0.02 - (SKIRT + PAD.y) * 0.5, 0.0), Vector3(PAD.x, SKIRT + PAD.y, PAD.z), K_PAD, lawn, 0.0)
	# The motor court from the gate to the house's door.
	add.call(Vector3(0.0, 0.05, 6.4), Vector3(11.0, 0.06, 9.0), K_PLAIN, COURT, 0.0)
	# Hedges down both sides.
	for sx: float in [-1.0, 1.0]:
		add.call(Vector3(sx * (PAD.x * 0.5 - 0.7), 0.85, -0.5), Vector3(1.1, 1.7, PAD.z - 3.0), K_PLAIN, HEDGE, 0.0)
	# The house: CityChunk's 18 x 13 villa, give or take, 4 m back.
	var w := lerpf(15.5, 19.0, _h(s, "w"))
	var d := lerpf(11.0, 13.5, _h(s, "d"))
	var hh := lerpf(6.2, 8.4, _h(s, "hh"))
	var hz := -4.0
	var wall: Color = WALLS[int(_h(s, "wall") * WALLS.size()) % WALLS.size()]
	add.call(Vector3(0.0, hh * 0.5, hz), Vector3(w, hh, d), K_HOUSE, wall, _h(s, "win"))
	var roof: Color = ROOFS[int(_h(s, "roof") * ROOFS.size()) % ROOFS.size()]
	add.call(Vector3(0.0, hh + 0.3, hz), Vector3(w + 0.8, 0.6, d + 0.8), K_ROOF, roof, 0.0)
	# A lower wing on one side now and then.
	if _h(s, "wing") < 0.5:
		var side := -1.0 if _h(s, "wside") < 0.5 else 1.0
		var ww := lerpf(5.0, 7.0, _h(s, "ww"))
		add.call(Vector3(side * (w * 0.5 + ww * 0.5 - 0.5), 1.9, hz - 1.0), Vector3(ww, 3.8, d - 3.0), K_HOUSE, wall, _h(s, "win2"))
		add.call(Vector3(side * (w * 0.5 + ww * 0.5 - 0.5), 4.05, hz - 1.0), Vector3(ww + 0.6, 0.5, d - 2.4), K_ROOF, roof, 0.0)
	# The pool: CityChunk._build_mansions' first two rolls on the estate's seed.
	var rng := RandomNumberGenerator.new()
	rng.seed = s
	var pool_x := (1.0 if rng.randf() < 0.5 else -1.0) * rng.randf_range(5.0, 6.5)
	add.call(Vector3(pool_x, 0.04, 6.0), Vector3(6.4, 0.1, 8.4), K_PLAIN, COPING, 0.0)
	add.call(Vector3(pool_x, 0.1, 6.0), Vector3(5.4, 0.06, 7.4), K_POOL, Color(0.04, 0.32, 0.42), 0.0)
	# Lamps: the gate piers, the door, garden lights round the lawn.
	var tone := _h(s, "tone")
	var front := PAD.z * 0.5
	for sx: float in [-1.0, 1.0]:
		add.call(Vector3(sx * 3.0, 2.5, front - 0.35), Vector3.ONE * LAMP_SIZE, K_LAMP, Color.WHITE, tone)
		add.call(Vector3(sx * 2.2, 2.6, hz + d * 0.5 + 0.3), Vector3.ONE * LAMP_SIZE, K_LAMP, Color.WHITE, tone)
	var garden := 3 + int(_h(s, "gn") * 4.0)
	for i in garden:
		var a := _h(s, ["ga", i])
		# Round the pad's edge, kept off the gate and the court.
		var p := Vector3(lerpf(-PAD.x * 0.5 + 1.6, PAD.x * 0.5 - 1.6, a), 0.6, lerpf(1.0, front - 1.4, _h(s, ["gz", i])))
		if absf(p.x) < 6.5:
			p.x = signf(p.x if p.x != 0.0 else 1.0) * 7.0
		add.call(p, Vector3.ONE * LAMP_SIZE * 0.8, K_LAMP, Color.WHITE, clampf(tone + 0.2, 0.0, 0.99))
	# Lamps down a long driveway, on the real ground beside it.
	var from: Vector2 = m.get("drive_from", pos)
	var gate := pos + Vector2(basis.z.x, basis.z.z) * (front + 0.4)
	var length := from.distance_to(gate)
	if length > DRIVE_MIN and ground.is_valid():
		var dir := (from - gate) / length
		var n := Vector2(-dir.y, dir.x)
		var k := DRIVE_LAMP_STEP * 0.5
		while k < length:
			var q := gate + dir * k + n * 2.8 * (1.0 if int(k / DRIVE_LAMP_STEP) % 2 == 0 else -1.0)
			var gy: float = ground.call(q)
			var at := Vector3(q.x, gy + 1.0, q.y)
			var code := float(K_LAMP + (REAL if real else 0)) + clampf(tone, 0.0, 0.99)
			out.append([Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * LAMP_SIZE), at), Color(1, 1, 1, 1), Color(at.y - deck, code, q.x - pos.x, q.y - pos.y)])
			k += DRIVE_LAMP_STEP
	return out


## The trees round an estate for the far city's planting (Skyline's veg): [Transform3D of a
## canopy blob, linear Color]. A few dark crowns behind and beside the house.
static func trees(m: Dictionary) -> Array:
	var out: Array = []
	var s: int = int(m.seed)
	var pos: Vector2 = m.pos
	var basis := Basis(Vector3.UP, float(m.yaw))
	var deck := float(m.height) + PAD.y
	var n := 2 + int(_h(s, "tn") * 3.0)
	for i in n:
		var local := Vector3(lerpf(-12.0, 12.0, _h(s, ["tx", i])), 0.0, -9.5 if _h(s, ["tb", i]) < 0.6 else lerpf(-2.0, 9.0, _h(s, ["tz", i])))
		if local.z > -9.0 and absf(local.x) < 10.5:
			local.x = signf(local.x if local.x != 0.0 else 1.0) * 11.0
		var r := lerpf(2.4, 3.8, _h(s, ["tr", i]))
		# Never under Skyline.HILL_OAK_HEIGHT.x: the far hills plant no low mounds (hill_air_checks).
		var th := lerpf(6.0, 9.0, _h(s, ["th", i]))
		var at := Vector3(pos.x, deck + th * 0.3, pos.y) + basis * local
		var c := lerpf(0.85, 1.15, _h(s, ["tc", i]))
		# Alpha is Skyline's dissolve, not part of the tint.
		out.append([Transform3D(Basis(Vector3.UP, _h(s, ["ty", i]) * TAU).scaled(Vector3(r, th, r * 0.9)), at),
			Color(0.06 * c, 0.085 * c, 0.04 * c, 1.0)])
	return out
