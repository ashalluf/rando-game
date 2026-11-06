class_name PierDay
## Rando Pier by day, at arm's length (refcam `pier_day`, tools/refcams/cameras_w6.json; docs/HANDOFF.md
## "The pier by day from the deck"). Three things that gave the 15:00 deck away, each behind one
## switch (`PIER_DAY=0` is the A/B: the pier exactly as before):
##
## - THE DECK was one tiled plank photo: a smooth brown sheet at grazing angles, no boards, no gaps,
##   no wear. `deck_material()` is `shaders/pier_deck.gdshader`: transverse boards (BOARD_W wide,
##   butt joints staggered per board), the dark gaps between them box-filtered by the pixel, each
##   board its own weathered tone (silver-grey, darker, the odd newer replacement), grain along the
##   board, nail pairs over the joists, a cupped tilt, a polished wear path down the promenade,
##   grime along the rail and stains / gum. All from the mesh's own coordinates (the park frame).
## - THE PARK'S PAINT was showroom clean. `pier_park.gdshader`'s `weathered` uniform (0 = the old
##   look, PierMesh.material() sets WEATHERED) adds salt grime toward the deck, sun fade, rust
##   streaks on the white steel and a blotchy tone, all faded under a pixel.
## - THE CROWD was 48 people for 16,000 m2 of deck: a summer afternoon pier is packed.
##   `extra_people()` adds up to EXTRA_PEOPLE more by the hour the chunk is built at (`density()`)
##   and the weather, mostly on the promenade (PROMENADE), some in twos and threes; they are
##   ordinary PierGoers in the crowd cap.

static func _static_init() -> void: LoadPulse.compiled()  # a boot frame: docs/HANDOFF.md "The boot compile"

## The whole pass (`PIER_DAY=0` turns it off).
static var enabled: bool = OS.get_environment("PIER_DAY") != "0"

## The extra people at the busiest hour.
const EXTRA_PEOPLE := 110
## The weathering strength handed to pier_park.gdshader.
const WEATHERED := 1.0
## Board width across the deck and the gap between boards (metres).
const BOARD_W := 0.145
const GAP_W := 0.011
## The walk-graph nodes on the main promenade (PierPark.WALK_NODES), where the extras start.
const PROMENADE: Array[int] = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13]

static var _deck: Material


## How full the pier is at `hour` (0..1): a few morning walkers, full from late morning into the
## early evening, thinning after dark toward midnight (each extra person is a draw call even far
## off: the pier_night camera paid +18 % draws for the old curve's full crowd at 21:00).
static func density(hour: float) -> float:
	var h := fposmod(hour, 24.0)
	if h < 7.0:
		return 0.08
	if h < 12.0:
		return lerpf(0.15, 1.0, smoothstep(7.0, 12.0, h))
	if h < 19.0:
		return 1.0
	return lerpf(1.0, 0.15, smoothstep(19.0, 23.5, h))


## How many extra people the pier gets at `hour` in the weather of `node`'s scene.
static func extra_people(hour: float, weather: float = 1.0) -> int:
	if not enabled:
		return 0
	return roundi(float(EXTRA_PEOPLE) * density(hour) * clampf(weather, 0.0, 1.0))


## The deck's material: the board shader, or (off) the old plank photo.
static func deck_material() -> Material:
	if not enabled:
		return PropFactory.pbr("planks", 2.4, Color(0.78, 0.70, 0.62))
	if _deck == null:
		var mat := ShaderMaterial.new()
		mat.shader = load("res://shaders/pier_deck.gdshader")
		mat.set_shader_parameter("board_w", BOARD_W)
		mat.set_shader_parameter("gap_w", GAP_W)
		var pts := PackedVector2Array()
		for p: Vector2 in PierPark.OUTLINE:
			pts.append(p)
		mat.set_shader_parameter("outline", pts)
		mat.set_shader_parameter("outline_count", pts.size())
		_deck = mat
	return _deck


## pier_park.gdshader's weathering strength.
static func weathered() -> float:
	return WEATHERED if enabled else 0.0


## Spots at the rail where people stop and look out to sea (the chunk's queue spots, which the life
## layer's _plan_queue() fills): park frame [p, yaw facing out], along the main pier's open rails
## and its sea end, clear of the benches, the lamps and the stands. Empty when off.
static func rail_spots() -> Array:
	var out: Array = []
	if not enabled:
		return out
	var benches := PierPark.benches()
	for side: float in [-1.0, 1.0]:
		var z := side * (12.0 - 0.6)
		var yaw := 0.0 if side < 0.0 else PI
		for span: Vector2 in [Vector2(-276.0, -166.0) if side < 0.0 else Vector2(-276.0, -209.0), Vector2(-60.0, -4.0)]:
			var x := span.y
			while x >= span.x:
				var p := Vector2(x, z)
				if _clear_of(p, benches):
					out.append([p, yaw])
				x -= RAIL_SPOT_STEP
	var zz := -9.0
	while zz <= 9.0:
		out.append([Vector2(-280.0 + 0.6, zz), PI * 0.5])
		zz += 3.0
	return out


## Every RAIL_SPOT_STEP metres along a rail.
const RAIL_SPOT_STEP := 3.6


static func _clear_of(p: Vector2, benches: Array) -> bool:
	for b: Array in benches:
		if p.distance_to(b[0] as Vector2) < 1.6:
			return false
	for k in PierPark.LAMP_COUNT:
		if absf(p.x - (PierPark.LAMP_FROM - PierPark.LAMP_STEP * float(k))) < 0.9:
			return false
	for st: Array in PierPark.STANDS:
		if absf(p.x - float(st[0])) < 3.4 and signf(float(st[1])) == signf(p.y):
			return false
	return true


## A chamfer on the stands' and booths' boxes (PierMesh.box's vertical-edge bevel): their corners
## caught no light and read as cut blocks. 0 when off.
static func bevel(b: float) -> float:
	return b if enabled else 0.0
