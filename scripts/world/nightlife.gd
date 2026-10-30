class_name NightLife
extends RefCounted
## The city's night life (GAME_PLAN G5 street life, after dark): a line outside a club or a busy
## bar on the downtown, midtown and beach-town blocks - people standing along the wall behind a
## brass-and-velvet rope, a bouncer working the gap at the door, the entrance lit (a club's
## cantilevered canopy with its name, downlights and LED edge and a black runner; a bar's
## projecting lightbox and sconces), smokers outside the bars. Taxis and ride-hail cars pull up
## double-parked on their hazards to take people home (NightPickups). On a premiere night a
## Broadway movie palace rolls out a red carpet between crowd barriers full of fans, and
## searchlights on carts at the kerb sweep the sky (SkyBeam), as they do on a club's opening
## night.
##
## Where: a FULL chunk's buildings record every ground-floor shop's front (Building.shop_fronts,
## Parklets' list); a RESTAURANT that is open at night (Building.shop_open: its glass is lit) is
## a bar, or by a hash a club, and a tower's LOBBY a club (the rooftop kind, its line at the
## lobby door). Each rolls a hash of the seed and the shop against ODDS by district; the line
## runs along the wall toward the farther corner. Never a parklet's shop, a block with camps, the
## fashion district's goods or Broadway's racks; never round a corner.
##
## When: the line and the people come from the hour the chunk is built at (queue_size(): a club
## from 21:30, longest round midnight, gone by 03:00; a bar's short line from 21:00), the
## premieres and openings from the night's number (DayNight.day_count) and a hash. Every roll is
## a hash of the seed and the shop (or the palace), never the block rng; nothing goes through
## CityChunk._add_prop and nothing takes the parking lane (the searchlight carts stand on the
## pavement at the kerb), so no stream or id the block had moves. FULL chunks; an LOD chunk gets
## only a premiere's sky beams. `NIGHTLIFE=0` in the environment is the A/B. Static: call with
## the chunk.

enum Kind { BAR, CLUB }

# --- Tunables --------------------------------------------------------------------------------

## Chance a candidate shop (an open restaurant, a tower lobby) is a venue, by district.
const ODDS := {
	CityPlan.District.DOWNTOWN: 0.32,
	CityPlan.District.MIDTOWN: 0.3,
	CityPlan.District.BEACHTOWN: 0.34,
}
## Share of the restaurant venues that are clubs (the rest are bars), by district.
const CLUB_SHARE := {
	CityPlan.District.DOWNTOWN: 0.5,
	CityPlan.District.MIDTOWN: 0.4,
	CityPlan.District.BEACHTOWN: 0.25,
}
## Most venues on one block, and how far apart two stand along the pavement (m).
const MAX_PER_BLOCK := 2
const MIN_APART := 18.0
## Most people a chunk spawns for its venues (one build step each).
const MAX_PEOPLE := 34
## The pavement a venue needs between its wall and the kerb (m), and the most it may have.
const MIN_PAVE := 3.1
const FRONT_REACH := 7.0
## How far from the block's corners a line keeps (m along the wall from the pavement's end).
const CORNER_KEEP := 4.5
## The longest a line runs along the wall (m), and the shortest room a venue needs for one.
const MAX_RUN := 14.5
const MIN_RUN := 4.5
## The line: the first person's distance along the wall from the door's middle, the spacing
## between people, how far out from the wall they stand.
const QUEUE_HEAD := 1.35
const QUEUE_PITCH := 0.74
const QUEUE_OUT := 0.72
## Seconds between the door letting the head of the line in (club, bar), and how long somebody
## is inside before they come out again (to a waiting car, or back round to the line's tail).
const ADMIT_SECONDS := {Kind.CLUB: Vector2(18.0, 42.0), Kind.BAR: Vector2(10.0, 26.0)}
const INSIDE_SECONDS := Vector2(45.0, 140.0)
## Chance, a night, that a club has its opening (searchlights), and a palace a premiere.
const OPENING_ODDS := 0.18
const PREMIERE_ODDS := 0.34
## A premiere's hours (the carpet is out, the fans behind the barriers, the beams up).
const PREMIERE_HOURS := Vector2(19.5, 25.0)
## The premiere's carpet width, and how many fans stand behind each barrier row at most.
const CARPET_W := 2.6
const FANS_PER_SIDE := 9
## The people who make a venue's scene - its bouncers, the first of its line, a premiere's first
## fans - spawn even when the crowd cap is full (they are still counted against it) and are never
## trimmed when Quality lowers the cap: a club with a rope and nobody behind it reads as closed.
const SCENE_PEOPLE := 10
## Draw distances (m) and shadow reach.
const ENTRANCE_DRAW := 220.0
const ROPE_DRAW := 110.0
const CART_DRAW := 260.0
const SIGN_DRAW := 260.0
const SHADOW_DISTANCE := 45.0
## Velvet / canopy / carpet accents (sRGB): oxblood, royal purple, black, emerald, navy, gold.
const ACCENTS := [Color(0.42, 0.04, 0.06), Color(0.24, 0.07, 0.34), Color(0.05, 0.05, 0.06),
	Color(0.04, 0.24, 0.16), Color(0.06, 0.09, 0.26), Color(0.55, 0.42, 0.18)]
const CARPET_RED := Color(0.5, 0.03, 0.04)
## The searchlight carts' paint (sRGB): a rental fleet's white, a grey, a dark blue.
const CART_PAINTS := [Color(0.85, 0.85, 0.83), Color(0.36, 0.38, 0.4), Color(0.1, 0.13, 0.22)]
## The venues' names: invented, never a real club or bar.
const CLUB_NAMES := ["NOCTURNE", "VELVET HOUR", "SUBLEVEL", "HALCYON", "GILT ROOM", "MERIDIAN",
	"OBSIDIAN", "AFTERGLOW", "PALMLIGHT", "STATIC", "MIDNIGHT ARC", "LUMEN", "SOLSTICE", "VANTA"]
const BAR_NAMES := ["LAST CALL", "COPPER STILL", "LOW TIDE", "OXBOW", "NIGHT OWL", "BRASS KEY",
	"LANTERN ROOM", "ARBOR", "TIN CUP", "GOLDEN HOUR", "RED DOOR", "SIDE DOOR", "HIGH WIRE"]
## The lettering's colour per club LED (NightLifeKit.LED_COLORS), and the bars' lightboxes.
const BAR_LETTERS := [Color(1.0, 0.72, 0.36), Color(1.0, 0.33, 0.24), Color(0.4, 0.85, 1.0)]

## Hour of the day to force while building (tests and stills); < 0 reads the DayNight clock.
static var force_hour: float = -1.0
## Odds forced for every candidate (stills: `NIGHTLIFE_ODDS=1`); < 0 the table's.
static var force_odds: float = float(OS.get_environment("NIGHTLIFE_ODDS")) if OS.get_environment("NIGHTLIFE_ODDS") != "" else -1.0
## Forces tonight's premieres and openings on (`NIGHTLIFE_PREMIERE=1`, stills).
static var force_events: bool = OS.get_environment("NIGHTLIFE_PREMIERE") == "1"
## The night's number to use (tests); < 0 reads DayNight.
static var force_night: int = -1
## Off: no night life at all (the A/B, `NIGHTLIFE=0` in the environment).
static var enabled: bool = OS.get_environment("NIGHTLIFE") != "0"
## Every venue built (their dicts), for NightPickups; pruned as chunks go.
static var venues: Array = []


static func _h01(parts: Array) -> float:
	return float(absi(hash(parts)) % 100003) * (1.0 / 100003.0)


# --- Time ------------------------------------------------------------------------------------

static func hour_now(node: Node) -> float:
	return StreetVendors.hour_now(node) if force_hour < 0.0 else force_hour


## Which night it is: the DayNight's day, the one before it until dawn.
static func night_now(node: Node, hour: float) -> int:
	if force_night >= 0:
		return force_night
	var day := 0
	if node != null and node.is_inside_tree():
		var scene := node.get_tree().current_scene
		var dn := scene.get_node_or_null("DayNight") if scene else null
		if dn != null:
			day = int(dn.get("day_count"))
	return day - 1 if fposmod(hour, 24.0) < 6.0 else day


## The hour as a night clock: 18.0 .. 30.0 (past midnight is 24 + h), so a night is one range.
static func night_hour(hour: float) -> float:
	var h := fposmod(hour, 24.0)
	return h + 24.0 if h < 6.0 else h


## Whether a venue of `kind` is open at `hour` (its lights on, the rope out).
static func open_at(kind: int, hour: float) -> bool:
	var h := night_hour(hour)
	if kind == Kind.CLUB:
		return h >= 21.5 and h < 27.0
	return h >= 17.0 and h < 26.0


## How many people stand in the line at `hour`: a club's from 21:30, longest from 23:00 to
## 01:00, gone by 03:00; a bar's short line from 21:00 to its last call. `key` makes each venue
## its own (0.55..1.0 of the peak).
static func queue_size(kind: int, hour: float, key: int) -> int:
	if not open_at(kind, hour):
		return 0
	var h := night_hour(hour)
	var peak := 15.0 if kind == Kind.CLUB else 5.0
	var shape := 0.0
	if kind == Kind.CLUB:
		shape = smoothstep(21.5, 23.0, h) * (1.0 - smoothstep(25.0, 27.0, h))
	else:
		shape = smoothstep(21.0, 22.5, h) * (1.0 - smoothstep(24.5, 25.8, h))
	var own := 0.55 + 0.45 * _h01([key, "nl_peak"])
	return int(round(peak * shape * own))


## Whether the night's events are on at `hour` on night `night`: a club's opening, a palace's premiere.
static func opening(seed: int, key: int, night: int) -> bool:
	return force_events or _h01([seed, key, night, "nl_opening"]) < OPENING_ODDS


static func premiere(seed: int, num: int, night: int, hour: float) -> bool:
	var h := night_hour(hour)
	if h < PREMIERE_HOURS.x or h >= PREMIERE_HOURS.y:
		return false
	return force_events or _h01([seed, num, night, "nl_premiere"]) < PREMIERE_ODDS


# --- Placement -------------------------------------------------------------------------------

## Whether this chunk's block can have venues at all (cheap: the steps are only queued if so).
static func wanted(chunk: CityChunk, block: Dictionary) -> bool:
	if chunk.level != CityChunk.Level.FULL or chunk.plan == null or chunk.capturing:
		return false
	return wanted_block(chunk, block)


## Whether a block (CityPlan.block()) can have venues: plain buildings in a district with odds,
## nobody else's pavement (camps, the fashion district's goods, Broadway's racks).
static func wanted_block(chunk: CityChunk, block: Dictionary) -> bool:
	if not enabled:
		return false
	if block.has("site") or block.has("grounds") or block.has("chinatown") or block.has("hospital"):
		return false
	if int(block.get("kind", CityPlan.BlockKind.BUILDINGS)) != CityPlan.BlockKind.BUILDINGS:
		return false
	if not ODDS.has(int(block.get("district", -1))):
		return false
	var plan := chunk.plan
	if Encampment.block_flags(plan, chunk.ix, chunk.iz) != 0 or Broadway.block_side(plan, chunk.ix, chunk.iz) != 0:
		return false
	if FashionDistrict.wanted(chunk, block):
		return false
	return true


## The venues of this chunk's block, from its buildings' shop fronts: pure in the buildings (no
## rolls but hashes), so tests ask it directly. Each is a Dictionary - see _venue().
static func plan_chunk(chunk: CityChunk, block: Dictionary) -> Array:
	var plan := chunk.plan
	var rect: Rect2 = block.rect
	var district := int(block.get("district", -1))
	var odds := float(ODDS.get(district, 0.0)) if force_odds < 0.0 else force_odds
	var parklet_keys := {}
	if Parklets.wanted(chunk, block):
		for pk: Dictionary in Parklets.plan_chunk(chunk, block):
			parklet_keys[int(pk.key)] = true
	var fronts: Array = []
	for child in chunk.get_children():
		var b := child as Building
		if b == null:
			continue
		for f: Array in b.shop_fronts:
			var room := int(f[3])
			if room != Building.ShopRoom.RESTAURANT and room != Building.ShopRoom.LOBBY:
				continue
			if room == Building.ShopRoom.RESTAURANT and not Building.shop_open(int(f[4])):
				continue
			var p: Vector3 = b.transform * (f[0] as Vector3)
			var n: Vector3 = (b.transform.basis * (f[1] as Vector3)).normalized()
			fronts.append([Vector2(p.x, p.z), Vector2(n.x, n.z), float(f[2]), room, hash([b.seed, int(f[4])]), int(f[4])])
	# Stable order whatever order the buildings were added in.
	fronts.sort_custom(func(x: Array, y: Array) -> bool: return x[4] < y[4])
	var out: Array = []
	for f: Array in fronts:
		var key := int(f[4])
		if parklet_keys.has(key):
			continue
		if _h01([plan.seed, "nightlife", key]) >= odds:
			continue
		var v := _venue(plan, chunk, rect, district, f)
		if v.is_empty():
			continue
		var clear := true
		for o: Dictionary in out:
			if (o.door as Vector2).distance_to(v.door) < MIN_APART:
				clear = false
		if not clear:
			continue
		out.append(v)
		if out.size() >= MAX_PER_BLOCK:
			break
	return out


## A venue at shop front `f` ([door, normal, width, room, key, shop key]) or {} when the pavement
## does not take one. {door (the wall point at the door's middle), out (to the kerb), along (the
## way the line runs), side (+1 / -1: along is the frame's +x or -x), run (m), kind, key,
## shop_key, name, led, accent, road (axis, index, dir with the venue on its kerb side, along
## coordinate of the door), kerb (m from the wall)}.
static func _venue(plan: CityPlan, chunk: CityChunk, rect: Rect2, district: int, f: Array) -> Dictionary:
	var p: Vector2 = f[0]
	var n: Vector2 = f[1]
	var key := int(f[4])
	var face := -1
	if n.y > 0.9:
		face = 0
	elif n.y < -0.9:
		face = 1
	elif n.x > 0.9:
		face = 2
	elif n.x < -0.9:
		face = 3
	if face < 0:
		return {}
	var kerb: float = [rect.end.y, rect.position.y, rect.end.x, rect.position.x][face]
	var depth := absf(kerb - (p.y if face < 2 else p.x))
	if depth < MIN_PAVE or depth > FRONT_REACH:
		return {}
	# Room along the wall each way to the pavement's corners less CORNER_KEEP.
	var t := Vector2(-n.y, n.x)
	var along_c := p.dot(t)
	var span := Vector2(rect.position.x, rect.end.x) if face < 2 else Vector2(rect.position.y, rect.end.y)
	var lo := span.x + CORNER_KEEP
	var hi := span.y - CORNER_KEEP
	var room_pos: float
	var room_neg: float
	var c := p.x if face < 2 else p.y
	var t_sign := t.x if face < 2 else t.y
	if t_sign > 0.0:
		room_pos = hi - c
		room_neg = c - lo
	else:
		room_pos = c - lo
		room_neg = hi - c
	var go := 1.0 if room_pos >= room_neg else -1.0
	if absf(room_pos - room_neg) < 1.0:
		go = 1.0 if _h01([key, "nl_way"]) < 0.5 else -1.0
	var run := minf(MAX_RUN, room_pos if go > 0.0 else room_neg)
	if run < MIN_RUN:
		return {}
	var along := t * go
	var out3 := Vector3(n.x, 0.0, n.y)
	var x_axis := Vector3.UP.cross(out3)
	var side := 1 if Vector3(along.x, 0.0, along.y).dot(x_axis) > 0.0 else -1
	var kind := Kind.CLUB
	if int(f[3]) == Building.ShopRoom.RESTAURANT and _h01([plan.seed, key, "nl_club"]) >= float(CLUB_SHARE.get(district, 0.3)):
		kind = Kind.BAR
	var names: Array = CLUB_NAMES if kind == Kind.CLUB else BAR_NAMES
	var name: String = names[int(_h01([plan.seed, key, "nl_name"]) * names.size()) % names.size()]
	# The road in front: axis, index, the direction whose kerb lane is the venue's side.
	var axis := CityPlan.AXIS_Z if face < 2 else CityPlan.AXIS_X
	var index := 0
	var dir := 1
	match face:
		0:
			index = chunk.iz + 1
			dir = -1
		1:
			index = chunk.iz
			dir = 1
		2:
			index = chunk.ix + 1
			dir = 1
		3:
			index = chunk.ix
			dir = -1
	return {"door": p, "out": n, "along": along, "side": side, "run": run, "kind": kind, "key": key,
		"shop_key": int(f[5]), "name": name, "kerb": depth, "face": face,
		"led": int(_h01([plan.seed, key, "nl_led"]) * NightLifeKit.LED_COLORS.size()) % NightLifeKit.LED_COLORS.size(),
		"accent": ACCENTS[int(_h01([plan.seed, key, "nl_accent"]) * ACCENTS.size()) % ACCENTS.size()],
		"metal": int(_h01([plan.seed, key, "nl_metal"]) < 0.3),
		"road": [axis, index, dir, p.y if axis == CityPlan.AXIS_X else p.x]}


## Where person `slot` of a venue's line stands (chunk space), and the way they face.
static func slot_spot(v: Dictionary, slot: int) -> Array:
	var along: Vector2 = v.along
	var out: Vector2 = v.out
	var key := int(v.key)
	var d := QUEUE_HEAD + float(slot) * QUEUE_PITCH + (_h01([key, slot, "nl_gap"]) - 0.5) * 0.16
	var o := QUEUE_OUT + (_h01([key, slot, "nl_out"]) - 0.5) * 0.22
	var spot: Vector2 = (v.door as Vector2) + along * d + out * o
	var face := -along + out * 0.18 + along.orthogonal() * (_h01([key, slot, "nl_turn"]) - 0.5) * 0.7
	return [spot, atan2(-face.x, -face.y)]


## The most people a venue's line holds (its run).
static func line_room(v: Dictionary) -> int:
	return maxi(1, int(floor((float(v.run) - QUEUE_HEAD - 0.4) / QUEUE_PITCH)) + 1)


## The frame of a venue (chunk space, no relief: the batch adds it): x along the wall (toward
## `side`), y up, z out to the kerb, origin on the pavement at the door's middle.
static func frame(v: Dictionary) -> Transform3D:
	var out3 := Vector3((v.out as Vector2).x, 0.0, (v.out as Vector2).y)
	var x_axis := Vector3.UP.cross(out3)
	var door: Vector2 = v.door
	return Transform3D(Basis(x_axis, Vector3.UP, out3), Vector3(door.x, CityChunk.SIDEWALK_TOP, door.y))


# --- Building --------------------------------------------------------------------------------

## The night life's steps for a FULL chunk: the venues and the premiere, then a person a step.
static func steps(chunk: CityChunk, block: Dictionary) -> Array:
	var out: Array = []
	if not enabled or chunk.plan == null or chunk.capturing:
		return out
	if chunk.level != CityChunk.Level.FULL:
		# An LOD chunk keeps only a premiere's beams (they are what reads from across the basin).
		if not _palaces_here(chunk).is_empty():
			out.append(func() -> void: _build_premieres(chunk, false))
		return out
	var venues_here := wanted(chunk, block)
	var palaces := not _palaces_here(chunk).is_empty()
	if not venues_here and not palaces:
		return out
	out.append(func() -> void: build_block(chunk, block, venues_here))
	for i in MAX_PEOPLE:
		out.append(func() -> void: spawn_person(chunk, i))
	return out


static func _palaces_here(chunk: CityChunk) -> Array:
	var out: Array = []
	if not Broadway.enabled:
		return out
	for p: Dictionary in Broadway.palaces(chunk.plan):
		if p.block == Vector2i(chunk.ix, chunk.iz):
			out.append(p)
	return out


## Lays out this block's venues: the entrance, the rope, the sign, the light, and plans who
## stands where; and a palace's premiere. A build step of a FULL chunk, after the parklets.
static func build_block(chunk: CityChunk, block: Dictionary, with_venues: bool) -> void:
	var hour := hour_now(chunk)
	var people: Array = chunk.get_meta("nightlife_people", [])
	var holder := Node3D.new()
	holder.name = "NightLife"
	chunk.add_child(holder)
	var built: Array = []
	if with_venues:
		var night := night_now(chunk, hour)
		for v: Dictionary in plan_chunk(chunk, block):
			_build_venue(chunk, block, v, hour, night, holder, people)
			built.append(v)
	if not built.is_empty():
		NightPickups.ensure(chunk)
	chunk.set_meta("nightlife", built)
	chunk.set_meta("nightlife_people", people)
	_build_premieres(chunk, true, holder, people, block)
	for k in ["nl_bar", "nl_cart"]:
		chunk._batch.set_shadow_distance(k, SHADOW_DISTANCE)
	_prune()


static func _build_venue(chunk: CityChunk, block: Dictionary, v: Dictionary, hour: float, night: int, holder: Node3D, people: Array) -> void:
	var plan := chunk.plan
	var key := int(v.key)
	var kind := int(v.kind)
	var xf := frame(v)
	var open_now := open_at(kind, hour)
	var seed01 := _h01([plan.seed, key, "nl_seed"]) * 0.49
	var accent: Color = v.accent
	var lit := 0.5 if open_now else 0.0
	var custom := Color(accent.r, accent.g, accent.b, lit + seed01)
	var gy := chunk._gy((v.door as Vector2).x, (v.door as Vector2).y)
	v.chunk = chunk
	v.open = open_now
	v.members = []
	v.inside = []
	v.pickup = null
	v.admit_ms = 0
	v.gy = gy
	var tint: Color
	if kind == Kind.CLUB:
		var k := "nl_club_%d" % int(v.led)
		chunk._batch.add(k, NightLifeKit.club_entrance(int(v.led)), xf, Color.WHITE, custom)
		chunk._batch.set_draw_distance(k, ENTRANCE_DRAW)
		chunk._batch.set_shadow_distance(k, SHADOW_DISTANCE)
		tint = NightLifeKit.LED_COLORS[int(v.led)]
		_sign(holder, String(v.name), xf * Vector3(0.0, NightLifeKit.CANOPY_Y + NightLifeKit.CANOPY_T * 0.5, NightLifeKit.CANOPY_D + 0.012), xf.basis, 0.26, NightLifeKit.CANOPY_W - 0.4, tint, gy)
	else:
		chunk._batch.add("nl_bar", NightLifeKit.bar_entrance(), xf, Color.WHITE, custom)
		chunk._batch.set_draw_distance("nl_bar", ENTRANCE_DRAW)
		tint = BAR_LETTERS[absi(key) % BAR_LETTERS.size()]
		for s: float in [-1.0, 1.0]:
			# Both faces of the lightbox (the frame's +x / -x), the letters a hair proud of each.
			var b := Basis(xf.basis.z * -s, Vector3.UP, xf.basis.x * s)
			_sign(holder, String(v.name), xf * Vector3(1.35 + s * 0.135, 3.55, 0.95), b, 0.17, 0.82, Color(0.08, 0.06, 0.05), gy)
	v.tint = tint
	# The line: who stands in it tonight, and the rope beside it.
	var size := mini(queue_size(kind, hour, key), line_room(v))
	if open_now and (kind == Kind.CLUB or size >= 3):
		var posts := clampi(int(ceil((float(v.run) - NightLifeKit.FIRST_POST) / NightLifeKit.POST_PITCH)) + 1, 2, 9)
		var rk := "nl_rope_%d_%d_%d" % [posts, int(v.side), int(v.metal)]
		chunk._batch.add(rk, NightLifeKit.rope_line(posts, int(v.side), int(v.metal)), xf, Color.WHITE, custom)
		chunk._batch.set_draw_distance(rk, ROPE_DRAW)
		chunk._batch.set_shadow_distance(rk, 25.0)
	v.admit_ms = 0
	var seconds: Vector2 = ADMIT_SECONDS[kind]
	v.period = lerpf(seconds.x, seconds.y, _h01([key, "nl_period"]))
	for slot in size:
		people.append({"kind": "queue", "venue": v, "slot": slot, "seed": hash([plan.seed, key, slot, "nl_q"]), "rect": block.rect})
	if open_now:
		people.append({"kind": "bouncer", "venue": v, "slot": 0, "seed": hash([plan.seed, key, "nl_b0"]), "rect": block.rect})
		if kind == Kind.CLUB and size >= 6:
			people.append({"kind": "bouncer", "venue": v, "slot": 1, "seed": hash([plan.seed, key, "nl_b1"]), "rect": block.rect})
		if kind == Kind.BAR:
			var smokers := int(_h01([key, int(hour), "nl_smoke"]) * 3.2)
			for i in smokers:
				people.append({"kind": "smoker", "venue": v, "slot": i, "seed": hash([plan.seed, key, i, "nl_s"]), "rect": block.rect})
	# The entrance's light and its pool on the pavement.
	if open_now:
		var pool_at := xf * Vector3(0.0, 0.0, 1.6)
		var pb := Basis(Vector3.RIGHT, -PI * 0.5)
		var pool := Transform3D(Basis(Vector3.UP, atan2(xf.basis.z.x, xf.basis.z.z)) * pb.scaled(Vector3(4.2, 1.0, 3.6)), Vector3(pool_at.x, CityChunk.SIDEWALK_TOP + 0.07, pool_at.z))
		var pc := tint.lerp(Color(1.0, 0.8, 0.55), 0.55)
		chunk._batch.add("nl_pool", PropFactory.shop_spill(), pool, Color(pc.r, pc.g, pc.b, 0.85))
		chunk._batch.set_no_shadow("nl_pool")
		chunk._batch.set_draw_distance("nl_pool", ENTRANCE_DRAW)
		_add_light(holder, xf * Vector3(0.0, 2.75 if kind == Kind.CLUB else 2.6, 1.2) + Vector3(0.0, gy, 0.0), 8.5, tint.lerp(Color(1.0, 0.8, 0.6), 0.6))
	# A club's opening: two searchlights at the kerb either side of the door.
	if kind == Kind.CLUB and open_now and opening(plan.seed, key, night):
		for s: float in [-1.0, 1.0]:
			var at := xf * Vector3(s * 3.4, 0.0, float(v.kerb) - 0.95)
			_add_searchlight(chunk, holder, at, xf.basis, hash([plan.seed, key, s, "nl_sl"]), true)
	venues.append(v)


## The venue's name: TextMesh lettering in the venue's colour, lit after dark.
static func _sign(holder: Node3D, text: String, at: Vector3, basis: Basis, height: float, room: float, tint: Color, gy: float) -> void:
	var mi := MeshInstance3D.new()
	mi.name = "NightSign%d" % holder.get_child_count()
	mi.mesh = PropFactory.text_mesh(text, height)
	var lin := tint.srgb_to_linear()
	mi.material_override = NightLifeKit.sign_material(lin)
	var wide := float(text.length()) * height * 0.62
	var fit := minf(1.0, room / maxf(wide, 0.01))
	mi.transform = Transform3D(Basis(basis.x * fit, basis.y * fit, basis.z), at + Vector3(0.0, gy, 0.0))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = SIGN_DRAW
	holder.add_child(mi)


## A light under the entrance, driven with the street lamps (DayNight sets the group's energy;
## Quality turns the group off at the low levels). Under the holder, not the chunk.
static func _add_light(holder: Node3D, at: Vector3, reach: float, tint: Color) -> void:
	if OS.has_feature("web"):
		return
	var light := OmniLight3D.new()
	light.name = "NightLight%d" % holder.get_child_count()
	light.position = at
	light.omni_range = reach
	light.omni_attenuation = 1.3
	light.light_color = tint
	light.light_energy = 0.0
	light.shadow_enabled = false
	light.distance_fade_enabled = true
	light.distance_fade_begin = 55.0
	light.distance_fade_length = 15.0
	light.add_to_group("lamp_light")
	holder.add_child(light)


## A searchlight cart at `at` (chunk space, on the pavement), its long side along the kerb
## (`b`'s x), and its beam (SkyBeam). `cart` false: the beam alone (an LOD chunk).
static func _add_searchlight(chunk: CityChunk, holder: Node3D, at: Vector3, b: Basis, seed_value: int, cart: bool) -> void:
	var gy := chunk._gy(at.x, at.z)
	var yaw_b := Basis(b.z, Vector3.UP, -b.x).orthonormalized()
	var xf := Transform3D(yaw_b, Vector3(at.x, CityChunk.SIDEWALK_TOP, at.z))
	if cart:
		var paint: Color = CART_PAINTS[absi(seed_value) % CART_PAINTS.size()]
		chunk._batch.add("nl_cart", NightLifeKit.searchlight_cart(), xf, Color.WHITE, Color(paint.r, paint.g, paint.b, 0.5))
		chunk._batch.set_draw_distance("nl_cart", CART_DRAW)
	var beam := SkyBeam.new()
	beam.name = "SkyBeam%d" % holder.get_child_count()
	beam.seed_value = seed_value
	beam.with_head = cart
	beam.transform = Transform3D(yaw_b, xf * Vector3(0.0, NightLifeKit.YOKE_Y, 0.35) + Vector3(0.0, gy, 0.0))
	holder.add_child(beam)


## A palace's premiere (Broadway), tonight and at this hour: the red carpet out of its doors to
## the kerb between gold stanchions and crowd barriers, fans behind them, and four searchlights
## at the kerb. `full` false (an LOD chunk): the beams alone.
static func _build_premieres(chunk: CityChunk, full: bool, holder: Node3D = null, people: Array = [], block: Dictionary = {}) -> void:
	var plan := chunk.plan
	var hour := hour_now(chunk)
	var night := night_now(chunk, hour)
	for p: Dictionary in _palaces_here(chunk):
		var num := int((p.spec as Dictionary).num)
		if not premiere(plan.seed, num, night, hour):
			continue
		# One premiere a block at most (Broadway's palaces stand three to a block in places).
		if holder != null and holder.has_meta("premiere"):
			break
		if holder == null:
			holder = Node3D.new()
			holder.name = "NightLife"
			chunk.add_child(holder)
		holder.set_meta("premiere", num)
		var f := BroadwayTheatre.frame(chunk, p)
		var pxf: Transform3D = f[0]
		var to_kerb := float(f[3])
		var g := chunk._gy(pxf.origin.x, pxf.origin.z)
		var base := Transform3D(pxf.basis, pxf.origin - Vector3(0.0, g, 0.0))
		var length := maxf(2.0, to_kerb - 0.35)
		var seed_value := hash([plan.seed, num, "nl_premiere"])
		if full:
			var key := "nl_premiere_%d" % int(length * 10.0)
			chunk._batch.add(key, NightLifeKit.premiere(length, CARPET_W), base, Color.WHITE, Color(CARPET_RED.r, CARPET_RED.g, CARPET_RED.b, 0.5))
			chunk._batch.set_draw_distance(key, ENTRANCE_DRAW)
			chunk._batch.set_shadow_distance(key, SHADOW_DISTANCE)
			# Fans behind the barriers, facing the carpet; the pool of the press lights on it.
			var rect: Rect2 = block.get("rect", Rect2())
			var rows := clampi(int((length - 0.8) / 0.62), 1, FANS_PER_SIDE)
			for s: float in [-1.0, 1.0]:
				for i in rows:
					var z := 0.8 + float(i) * 0.62 + (_h01([seed_value, s, i, "nl_fz"]) - 0.5) * 0.2
					var x := s * (CARPET_W * 0.5 + 1.45 + 0.5 + _h01([seed_value, s, i, "nl_fx"]) * 0.35)
					var at := base * Vector3(x, 0.0, z)
					var face := (base.basis * Vector3(-s, 0.0, 0.25)).normalized()
					people.append({"kind": "fan", "venue": {}, "slot": i, "seed": hash([seed_value, s, i, "nl_fan"]), "rect": rect,
						"spot": Vector2(at.x, at.z), "yaw": atan2(-face.x, -face.z)})
			var pool_at := base * Vector3(0.0, 0.0, length * 0.5)
			var pb := Basis(Vector3.RIGHT, -PI * 0.5)
			var pool := Transform3D(Basis(Vector3.UP, atan2(base.basis.z.x, base.basis.z.z)) * pb.scaled(Vector3(5.0, 1.0, length + 1.5)), Vector3(pool_at.x, CityChunk.SIDEWALK_TOP + 0.07, pool_at.z))
			chunk._batch.add("nl_pool", PropFactory.shop_spill(), pool, Color(1.0, 0.82, 0.7, 0.42))
			chunk._batch.set_no_shadow("nl_pool")
			_add_light(holder, base * Vector3(0.0, 4.5, length * 0.5) + Vector3(0.0, g, 0.0), 11.0, Color(1.0, 0.9, 0.8))
		for x: float in [-8.4, -5.3, 5.3, 8.4]:
			var at := base * Vector3(x, 0.0, to_kerb - 0.95)
			_add_searchlight(chunk, holder, at, base.basis, hash([seed_value, x, "nl_sl"]), full)


## The `index`-th person this chunk planned (a build step each), if the crowd cap has room.
static func spawn_person(chunk: CityChunk, index: int) -> void:
	var people: Array = chunk.get_meta("nightlife_people", [])
	if index >= people.size():
		return
	var s: Dictionary = people[index]
	var key_person := String(s.kind) == "bouncer" or (String(s.kind) != "smoker" and int(s.slot) < SCENE_PEOPLE)
	if not chunk._take_crowd_room() and not key_person:
		return
	var ped := NightGoer.new()
	var at: Vector2
	var yaw: float
	match String(s.kind):
		"queue":
			var spot := slot_spot(s.venue, int(s.slot))
			at = spot[0]
			yaw = spot[1]
			ped.setup_role(NightGoer.Role.QUEUE, s.rect, int(s.seed), s.venue, at, yaw)
		"bouncer":
			var v: Dictionary = s.venue
			var along: Vector2 = v.along
			var out: Vector2 = v.out
			var face: Vector2
			if int(s.slot) == 0:
				at = (v.door as Vector2) + along * 0.5 + out * (NightLifeKit.ROPE_OUT + 0.25)
				face = (along * 0.75 + out * 0.6).normalized()
			else:
				at = (v.door as Vector2) - along * 0.75 + out * 0.55
				face = (out - along * 0.3).normalized()
			yaw = atan2(-face.x, -face.y)
			ped.setup_role(NightGoer.Role.BOUNCER, s.rect, int(s.seed), v, at, yaw)
		"smoker":
			var v: Dictionary = s.venue
			var along: Vector2 = v.along
			var out: Vector2 = v.out
			var i := int(s.slot)
			at = (v.door as Vector2) - along * (1.55 + float(i) * 0.8) + out * (0.55 + 0.35 * float(i % 2))
			var face := (out * 0.6 + along * (0.5 if i % 2 == 0 else -0.5)).normalized()
			yaw = atan2(-face.x, -face.y)
			ped.setup_role(NightGoer.Role.SMOKER, s.rect, int(s.seed), v, at, yaw)
		_:
			at = s.spot
			yaw = float(s.yaw)
			ped.setup_role(NightGoer.Role.FAN, s.rect, int(s.seed), {}, at, yaw)
	if key_person:
		# Never freed when Quality trims the crowd (CityStreamer.trim_pedestrians()): the line and
		# the door are the scene.
		ped.set_meta("no_trim", true)
	ped.position = Vector3(at.x, chunk.ground_y(at.x, at.y) + 0.05, at.y)
	chunk.add_child(ped)


## Forgets the venues of chunks that have gone.
static func _prune() -> void:
	for i in range(venues.size() - 1, -1, -1):
		var v: Dictionary = venues[i]
		if not is_instance_valid(v.get("chunk")):
			venues.remove_at(i)


## Builds every mesh once (the loading screen).
static func warm() -> Array:
	if not enabled:
		return []
	return NightLifeKit.warm()
