class_name LongBeachSand
extends RefCounted
## The sand of Long Beach, on San Pedro Bay's north shore east of the port (rc5-oil-islands-dusk,
## wave 8). MacroMap calls the strip `bay_beach_depth` north of `bay_z` BEACH, but every beach
## builder lays sand for the WEST coast (CityChunk._build_sand(): rows of constant z running inland
## along +x from MacroMap.coast_x()), so on this east-west shore nobody built anything: a BEACH
## chunk there laid its two road strips (the +Z one on the waterline) and the rest was the horizon
## plane, which the bake calls water at height 0 - from the sand the oil islands were seen over
## flat, glossy, square sheets of "sea" with a dark edge and a road through the surf.
##
## Here the beach is laid the other way round: rows of constant x, the sea to +z (south). The
## profile is the west beach's (CityChunk's SAND_* numbers and tones): the drowned toe, the steep
## step, the waterline at `MacroMap.bay_z` (where the ocean shader's surf breaks), the swash, the
## berm, and the landward lip dipping under the beachfront road at the macro relief's height. The
## chunk's own road strips are not built (the sand covers them; SandRoads tells the traffic). The
## sand runs out under the sea to the chunk's seaward edge, where the ocean chunks' water starts; a
## slice of sea of its own on the strip (the west beach's _build_water(true)) was tried and stood up
## as a wall of mirrored sky over the shore here (the surf's vertex stage on a plane landward of the
## bay's shore table), hiding the port's cranes - left out. Palms along the back of the sand and a
## lifeguard tower now and then (hashes of the seed and x, no roll). Same material as every beach
## (PropFactory.beach_sand_material(): its swash reads UV2.x = metres landward of the waterline).
##
## Pure geometry of the plan (no roll): nothing else in the city moves. `LONG_BEACH_SAND=0` in the
## environment is the A/B (the chunk builds its roads and nothing else, as before).

static func _static_init() -> void: LoadPulse.compiled()  # a boot frame: docs/HANDOFF.md "The boot compile"

static var enabled: bool = OS.get_environment("LONG_BEACH_SAND") != "0"

## Sand steps along the shore (m).
const STEP := 9.0
## How far the sand's landward lip sits under the ground at the beachfront road (m).
const LIP_SINK := 0.04
## The landward band rising from the lip to the backshore (m).
const LIP_RUN := 2.5
## Palms along the back of the sand: a slot every PALM_STEP m, PALM_ODDS of them planted.
const PALM_STEP := 17.0
const PALM_ODDS := 0.62
## The palms stand on the dry sand between these shares of the way from the waterline to the lip
## (Long Beach's stand in twos and threes out on the sand, along the beach path).
const PALM_ACROSS := Vector2(0.55, 0.85)
## A lifeguard tower in TOWER_ODDS of every TOWER_CELL m of shore.
const TOWER_CELL := 240.0
const TOWER_ODDS := 0.7


## True for a BEACH chunk of the bay's north shore that the west-coast beach does not build.
static func claims(ch: CityChunk) -> bool:
	if not enabled or ch.plan == null or ch.plan.macro == null:
		return false
	var block: Dictionary = ch.plan.block(ch.ix, ch.iz)
	return claims_block(ch.plan, block.rect as Rect2)


## The same test from the plan alone (SandRoads asks it).
static func claims_block(plan: CityPlan, rect: Rect2) -> bool:
	if not enabled or plan == null or plan.macro == null:
		return false
	var m: MacroMap = plan.macro
	var c := rect.get_center()
	if m.zone_at(c) != MacroMap.Zone.BEACH:
		return false
	if c.x <= m.port_rect.end.x or c.x >= m.bay_east_x:
		return false
	if c.y < m.bay_z - m.bay_beach_depth - 20.0 or c.y > m.bay_z:
		return false
	# The west coast's own beach (a chunk holding coast_x) is CityChunk's.
	var cx := m.coast_x(c.y)
	return not (cx >= rect.position.x and cx < rect.end.x + 200.0)


## The build steps for a claimed chunk: the sand, then its slice of sea.
static func steps(ch: CityChunk) -> Array[Callable]:
	var out: Array[Callable] = []
	out.append(build_sand.bind(ch))
	if not ch.capturing:
		out.append(dress.bind(ch))
	return out


## Height of the sand `across` of the way from the waterline (0) to the landward lip (1), at x.
static func profile_y(across: float, x: float, lip_y: float) -> float:
	var crest := CityChunk.SAND_CREST + CityChunk.SAND_CUSP * sin(x * 0.11) * cos(x * 0.047)
	var high := maxf(CityChunk.SAND_HIGH, lip_y + 0.12)
	if across <= CityChunk.SAND_BERM_AT:
		return lerpf(CityChunk.SAND_EDGE, CityChunk.SAND_EDGE + crest, across / CityChunk.SAND_BERM_AT)
	var t := (across - CityChunk.SAND_BERM_AT) / (1.0 - CityChunk.SAND_BERM_AT)
	return lerpf(CityChunk.SAND_EDGE + crest, high, t * t * (3.0 - 2.0 * t))


## The rows across the beach at x, seaward to landward: [z, y, tone index].
static func rows_at(plan: CityPlan, own: Rect2, x: float) -> Array:
	var m: MacroMap = plan.macro
	var zw := m.bay_z
	var z0 := own.position.y
	var width := maxf(zw - z0, 8.0)
	var lip_y := m.height_at(Vector2(x, z0)) - LIP_SINK
	var out: Array = []
	var toe := own.end.y
	var steep := zw + CityChunk.SAND_STEEP_AT
	var toe_y := lerpf(CityChunk.SAND_STEEP_Y, CityChunk.SAND_LOW, clampf((toe - steep) / (CityChunk.SAND_WET - CityChunk.SAND_STEEP_AT), 0.0, 1.0))
	if toe > steep + 0.5:
		out.append([toe, toe_y, 0])
	out.append([steep, CityChunk.SAND_STEEP_Y, 1])
	out.append([zw, CityChunk.SAND_EDGE, 2])
	out.append([zw - CityChunk.SAND_SWASH, profile_y(CityChunk.SAND_SWASH / width, x, lip_y), 3])
	out.append([zw - width * CityChunk.SAND_BERM_AT, profile_y(CityChunk.SAND_BERM_AT, x, lip_y), 4])
	out.append([z0 + LIP_RUN, profile_y(1.0 - LIP_RUN / width, x, lip_y), 5])
	out.append([z0, lip_y, 5])
	return out


static func build_sand(ch: CityChunk) -> void:
	var plan := ch.plan
	var own := ch.owned_rect()
	var zw := plan.macro.bay_z
	var width := maxf(zw - own.position.y, 8.0)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := maxi(1, ceili(own.size.x / STEP))
	var prev: Array = []
	var prev_x := 0.0
	var quads := 0
	for i in n + 1:
		var x := own.position.x + own.size.x * float(i) / float(n)
		var row := rows_at(plan, own, x)
		if i > 0 and prev.size() == row.size():
			for k in row.size() - 1:
				var a := Vector3(prev_x, float(prev[k][1]), float(prev[k][0]))
				var b := Vector3(prev_x, float(prev[k + 1][1]), float(prev[k + 1][0]))
				var c := Vector3(x, float(row[k + 1][1]), float(row[k + 1][0]))
				var d := Vector3(x, float(row[k][1]), float(row[k][0]))
				var ta: Color = CityChunk.SAND_TONES[int(prev[k][2])]
				var tb: Color = CityChunk.SAND_TONES[int(prev[k + 1][2])]
				for pair in [[a, ta], [b, tb], [c, tb], [a, ta], [c, tb], [d, ta]]:
					var v: Vector3 = pair[0]
					st.set_color(pair[1] as Color)
					st.set_uv(Vector2(v.x, v.z) * CityChunk.SAND_UV_SCALE)
					st.set_uv2(Vector2(zw - v.z, width))
					st.add_vertex(v)
				quads += 1
		prev = row
		prev_x = x
	if quads == 0:
		return
	st.generate_normals()
	st.generate_tangents()
	if ch.capturing:
		return
	var mesh := MeshInstance3D.new()
	mesh.name = "LongBeachSand"
	mesh.mesh = st.commit()
	mesh.material_override = PropFactory.beach_sand_material()
	ch.add_child(mesh)
	if ch.level != CityChunk.Level.FULL:
		return
	# The dry sand's collider in bands along the profile (the west beach's way).
	var bands := CityChunk.SAND_COLLIDER_BANDS
	var band := width / float(bands)
	var cx := own.get_center().x
	for k in bands:
		var across := (float(k) + 0.5) / float(bands)
		var z := zw - width * across
		var y := profile_y(across, cx, plan.macro.height_at(Vector2(cx, own.position.y)) - LIP_SINK)
		ch._add_shape(Vector3(own.size.x + 0.2, 0.4, band + 0.2), Vector3(cx, y - 0.2, z))


## A hash in 0..1 of the seed, a salt and a cell.
static func h01(plan: CityPlan, salt: String, n: int) -> float:
	return float(hash([plan.seed, "long_beach", salt, n]) & 0xffffff) / 16777216.0


## Palms along the back of the sand and the lifeguard towers, by the slots whose x falls in the
## chunk's owned rect (so two chunks never plant the same one).
static func dress(ch: CityChunk) -> void:
	var plan := ch.plan
	var own := ch.owned_rect()
	var zw := plan.macro.bay_z
	var width := maxf(zw - own.position.y, 8.0)
	var lip_ref := plan.macro.height_at(Vector2(own.get_center().x, own.position.y)) - LIP_SINK
	var k0 := floori(own.position.x / PALM_STEP)
	var k1 := floori(own.end.x / PALM_STEP)
	for k in range(k0, k1 + 1):
		if h01(plan, "palm", k) > PALM_ODDS:
			continue
		var x := (float(k) + 0.2 + 0.6 * h01(plan, "px", k)) * PALM_STEP
		if x < own.position.x + 2.0 or x > own.end.x - 2.0:
			continue
		var across := lerpf(PALM_ACROSS.x, PALM_ACROSS.y, h01(plan, "pz", k))
		var z := zw - width * across
		var lip_y := plan.macro.height_at(Vector2(x, own.position.y)) - LIP_SINK
		var rng := RandomNumberGenerator.new()
		rng.seed = hash([plan.seed, "long_beach_palm", k])
		ch._add_palm(Vector3(x, profile_y(across, x, lip_y) - 0.05, z), rng, ch.level == CityChunk.Level.FULL)
		# Now and then a second, shorter one beside it (palms here stand in twos and threes).
		if h01(plan, "pair", k) < 0.35:
			var dx := (h01(plan, "pdx", k) - 0.5) * 7.0
			ch._add_palm(Vector3(x + dx, profile_y(across, x + dx, lip_y) - 0.05, z + 2.5), rng, ch.level == CityChunk.Level.FULL)
	if ch.level != CityChunk.Level.FULL:
		return
	var c0 := floori(own.position.x / TOWER_CELL)
	var c1 := floori(own.end.x / TOWER_CELL)
	for c in range(c0, c1 + 1):
		if h01(plan, "tower", c) > TOWER_ODDS:
			continue
		var x := (float(c) + 0.25 + 0.5 * h01(plan, "tx", c)) * TOWER_CELL
		if x < own.position.x + 4.0 or x > own.end.x - 4.0:
			continue
		var across := lerpf(0.2, 0.42, h01(plan, "tz", c))
		var z := zw - width * across
		var at := Vector3(x, profile_y(across, x, lip_ref), z)
		# Turned to the sea (+z), a little jitter.
		var yaw := PI + (h01(plan, "ty", c) - 0.5) * 0.3
		ch._batch.add("beach_tower", BeachLife.tower_mesh(), Transform3D(Basis(Vector3.UP, yaw), at))
		ch._add_shape(Vector3(3.1, 4.8, 3.4), at + Basis(Vector3.UP, yaw) * Vector3(0.0, 2.4, 0.4), yaw)
