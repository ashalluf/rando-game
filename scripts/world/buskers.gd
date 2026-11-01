class_name Buskers
extends RefCounted
## Street performers (VISUAL_ROADMAP, the buskers pass): a guitarist with his case open for tips,
## a drummer on upturned buckets, a breakdancer on flattened cardboard with a ring of watchers,
## a living statue painted silver on a plinth, a mariachi trio (guitarron, violin, trumpet) in
## black and silver under sombreros. On the busy pavements downtown, round the arena, across from
## MacArthur Park, in the beach town by the boardwalk, and on the plazas.
##
## Placement is pure (plan_block(): hashes of seed + block + face + kind, and the hour the chunk is
## built at), never the chunk's or block's random stream, and the build step runs after the street
## vendors (whose carts it keeps clear of) and before the parked cars and the block's walkers:
## nothing else the seed builds moves. The gear on the ground is code-built at real size
## (Buskers.Kit) on one shader (shaders/busker_prop.gdshader), one batch per kind a chunk; the
## instruments ride the performers' bones. The people are crowd rigs (Busker, BuskWatcher, both
## StreetVendors: in the crowd cap, shot and knocked like anyone, they run from gunfire and walk
## back when it is over). Passers-by stop to watch at the chunk's "vendor_queue" spots.
##
## Audio: none. No CC0 recording of a street guitar, bucket drums or a mariachi trio was reachable
## from the build box (see docs/HANDOFF.md); the performers play silently.
##
## Names are invented (none is shown anywhere). BUSKERS=0 in the environment turns it all off.

enum Kind { GUITAR, DRUMS, BREAK, STATUE, MARIACHI }
## The plaza is a place of its own (StreetVendors.Place has no plaza: its blocks read as their
## district there).
const PLAZA := 100

# --- Tunables --------------------------------------------------------------------------------

## Chance a pavement face of each place has a performer of each kind: [guitar, drums, break,
## statue, mariachi]. A block keeps the first face and kind that rolls (one performer a block);
## breakdancers only on plazas (they need the room for their ring). PLAZA rolls per slot (two a
## plaza, either side of the fountain).
const ODDS := {
	StreetVendors.Place.DOWNTOWN: [0.03, 0.025, 0.0, 0.015, 0.012],
	StreetVendors.Place.MIDTOWN: [0.018, 0.01, 0.0, 0.008, 0.015],
	StreetVendors.Place.PARK: [0.05, 0.03, 0.0, 0.03, 0.03],
	StreetVendors.Place.MACARTHUR: [0.08, 0.05, 0.0, 0.02, 0.1],
	StreetVendors.Place.ARENA: [0.07, 0.09, 0.0, 0.03, 0.03],
	StreetVendors.Place.BEACH: [0.07, 0.05, 0.0, 0.06, 0.025],
	PLAZA: [0.32, 0.22, 0.45, 0.3, 0.28],
}
## Hours each kind works [start, end] (past midnight is fine), shifted per performer by a hash.
const HOURS := {
	Kind.GUITAR: [10.0, 22.0],
	Kind.DRUMS: [11.0, 21.0],
	Kind.BREAK: [13.0, 21.5],
	Kind.STATUE: [10.0, 18.5],
	Kind.MARIACHI: [12.0, 23.0],
}
const HOURS_JITTER := 1.0
## Where on a pavement (metres in from the kerb): the performer, the tips in front, the people
## who stop to watch (the queue spots), and how far from the corners.
const PERFORM_IN := 3.15
const TIPS_IN := 2.2
const WATCH_IN := 1.05
const CORNER_KEEP := 8.0
## A breakdancer's ring: the watchers stand this far from the dancer, this many of them.
const RING_RADIUS := 3.0
const RING_WATCHERS := 5
## Most people one block's performers bring (performers and their own watchers): spawn steps.
const MAX_PEOPLE := 12
## Draw distances (m) and the shadows' reach.
const GEAR_DRAW := 110.0
const SHADOW_DISTANCE := 35.0
## Share of passers-by near a performer who stop at a watch spot, and for how long (s). The
## queue roll is StreetVendors' (QUEUE_SHARE); these are the spots' own numbers.
const WATCH_SPOTS := 3

## The drum kit's strike points in the drummer's frame (m; -Z forward, +X the drummer's right):
## the bass bucket between the knees, the high bucket on a crate to the left, a paint pail on a
## crate to the right, the pot-lid cymbal on its stand. Busker reads them for the sticks.
const DRUM_HITS := [Vector3(0.0, 0.37, -0.44), Vector3(-0.36, 0.66, -0.34), Vector3(0.36, 0.48, -0.36), Vector3(0.52, 0.78, -0.14)]
## The seat: an upturned bucket under the hips, its top this high, this far behind the feet.
const SEAT_H := 0.4
const SEAT_BACK := 0.24
## How high a living statue's plinth is.
const PLINTH_H := 0.45

## Surfaces (COLOR.a, in tenths; busker_prop.gdshader).
const A_PAINT := 0.0
const A_WOOD := 0.1
const A_BRASS := 0.2
const A_STEEL := 0.3
const A_PLASTIC := 0.4
const A_PLUSH := 0.5
const A_CARD := 0.6
const A_SILVER := 0.7
const A_RUBBER := 0.8
const A_HOLE := 0.9
const A_LED := 1.0

const K_CASE := "busk_case"
const K_DRUMS := "busk_drums"
const K_BREAK := "busk_break"
const K_PLINTH := "busk_plinth"
const K_AMP := "busk_amp"

## Rigs who play each kind (the crowd's own people: see tools/crowd/crowd_config.json). Mariachis
## are rigs in trousers with short hair, which the charro recolour and the sombrero suit.
const RIGS := {
	Kind.GUITAR: ["crowd_a", "crowd_d", "crowd_f", "crowd_h", "crowd_j", "crowd_k", "crowd_q", "crowd_t"],
	Kind.DRUMS: ["crowd_a", "crowd_b", "crowd_o", "crowd_s"],
	Kind.BREAK: ["crowd_a", "crowd_o"],
	Kind.STATUE: ["crowd_a", "crowd_d", "crowd_f", "crowd_i", "crowd_j", "crowd_t"],
	Kind.MARIACHI: ["crowd_a", "crowd_f", "crowd_g", "crowd_h", "crowd_j"],
}

static var force_hour: float = -1.0
static var enabled: bool = OS.get_environment("BUSKERS") != "0"

static var _meshes: Dictionary = {}
static var _material: ShaderMaterial


# --- Placement -------------------------------------------------------------------------------

## Whether this chunk's block can have performers at all (cheap: the steps are queued only if so).
static func wanted(chunk: CityChunk, block: Dictionary) -> bool:
	if not enabled or chunk.level != CityChunk.Level.FULL or chunk.plan == null:
		return false
	if _is_plaza(block):
		return true
	for e in 4:
		if ODDS.has(_place(chunk.plan, chunk.ix, chunk.iz, block, e)):
			return true
	return false


static func _is_plaza(block: Dictionary) -> bool:
	return not block.has("site") and int(block.get("kind", -1)) == CityPlan.BlockKind.PLAZA


static func _place(plan: CityPlan, ix: int, iz: int, block: Dictionary, e: int) -> int:
	return StreetVendors._place(plan, ix, iz, block, e)


static func _h01(parts: Array) -> float:
	return float(absi(hash(parts)) % 100003) * (1.0 / 100003.0)


static func hour_now(node: Node) -> float:
	return force_hour if force_hour >= 0.0 else StreetVendors.hour_now(node)


## A performer's own hours (the kind's, shifted by a hash).
static func hours_of(plan_seed: int, kind: int, id: Array) -> Vector2:
	var h: Array = HOURS[kind]
	var shift := (_h01([plan_seed, "busk_hours"] + id) * 2.0 - 1.0) * HOURS_JITTER
	return Vector2(float(h[0]) + shift, float(h[1]) + shift)


## The performers working block (ix, iz) at `hour`: pure, so the checks ask it directly. Each is
## {kind, face (-1 on a plaza), slot, t, place, id, seed, hours}. A plaza's slots: 0 on the
## fountain's +long side, 1 on its - side.
static func plan_block(plan: CityPlan, ix: int, iz: int, hour: float) -> Array:
	var out: Array = []
	var block := plan.block(ix, iz)
	if block.has("site"):
		return out
	if _is_plaza(block):
		for slot in 2:
			var v := _roll(plan, [ix, iz, "plaza", slot], PLAZA, hour, slot == 0)
			if not v.is_empty():
				v.face = -1
				v.slot = slot
				v.t = 0.0
				out.append(v)
		return out
	var rect: Rect2 = block.rect
	var edges := CityChunk._sidewalk_edges(rect)
	# The faces in an order of their own (a hash), so a block's performer is not always on -z.
	var first := int(_h01([plan.seed, "busk_face", ix, iz]) * 4.0)
	for i in 4:
		var e := (first + i) % 4
		var place := _place(plan, ix, iz, block, e)
		if not ODDS.has(place):
			continue
		var length := (edges[e][0] as Vector2).distance_to(edges[e][1])
		if length < CORNER_KEEP * 2.0 + 6.0:
			continue
		var v := _roll(plan, [ix, iz, e], place, hour, false)
		if v.is_empty():
			continue
		v.face = e
		v.slot = 0
		v.t = lerpf(CORNER_KEEP, length - CORNER_KEEP, _h01([plan.seed, "busk_t", ix, iz, e]))
		out.append(v)
		return out
	return out


## The kind that works this spot at `hour`, or {} (every kind rolled, the first in a hashed order
## that passes its odds and its hours wins).
static func _roll(plan: CityPlan, id: Array, place: int, hour: float, may_break: bool) -> Dictionary:
	var odds: Array = ODDS[place]
	var first := int(_h01([plan.seed, "busk_kind"] + id) * Kind.size())
	for i in Kind.size():
		var kind := (first + i) % Kind.size()
		if kind == Kind.BREAK and not may_break:
			continue
		if _h01([plan.seed, "busk", kind] + id) >= float(odds[kind]):
			continue
		var hours := hours_of(plan.seed, kind, id)
		if not StreetVendors.open_at(hours, hour):
			continue
		return {"kind": kind, "place": place, "id": "busk_%s" % "_".join(id.map(func(x): return str(x))),
			"seed": hash([plan.seed, "busker"] + id), "hours": hours}
	return {}


## A seed near `base` whose crowd rig (Pedestrian._add_model()'s pick: the first `_style` roll) is
## one of `rigs`, and who wears no hat or pack (the accessory roll after the look, the build and
## the gait: the instruments and the sombrero go where a pack or a cap would) - the performers are
## dressed for their act, so their rig is chosen, not rolled. Mirrors _add_model()'s rolls.
static func seed_for(base: int, rigs: Array) -> int:
	var models: Array = Pedestrian.MODELS
	var r := RandomNumberGenerator.new()
	for k in 256:
		var s := hash([base, k])
		r.seed = hash([s, "style"])
		var path: String = models[r.randi() % models.size()]
		r.randi()
		for i in 5:
			r.randf()
		if path.get_file().get_basename() in rigs and r.randf() >= 0.42:
			return s
	return base


## Lays out this block's performers: their gear, the spots their people stand at, the watch
## spots for passers-by. A build step of a FULL chunk, after the street vendors and before the
## parked cars and the walkers.
static func build_block(chunk: CityChunk, block: Dictionary) -> void:
	var plan: CityPlan = chunk.plan
	var rect: Rect2 = block.rect
	var occupied := StreetVendors._occupied(chunk)
	# Every prop the block has (a plaza's benches, planters and lamps, the stops' shelters).
	for r: Dictionary in chunk.prop_records:
		var rp: Vector3 = r.position
		occupied.append([Vector2(rp.x, rp.z), 1.3])
	var people: Array = chunk.get_meta("busk_people", [])
	var acts: Array = chunk.get_meta("busk_acts", [])
	for v: Dictionary in plan_block(plan, chunk.ix, chunk.iz, hour_now(chunk)):
		var spot := _spot(chunk, rect, v, occupied)
		if spot.is_empty():
			continue
		_lay_out(chunk, rect, v, spot, people)
		acts.append({"kind": v.kind, "id": v.id, "at": spot.at, "yaw": spot.yaw})
	chunk.set_meta("busk_people", people)
	chunk.set_meta("busk_acts", acts)
	for k: String in [K_CASE, K_DRUMS, K_BREAK, K_PLINTH, K_AMP]:
		chunk._batch.set_draw_distance(k, GEAR_DRAW)
		chunk._batch.set_shadow_distance(k, SHADOW_DISTANCE)


## Where performer `v` stands: {at, yaw, out (the way they face, toward the street), along}, slid
## along its pavement to clear what already stands there; {} when nowhere is clear.
static func _spot(chunk: CityChunk, rect: Rect2, v: Dictionary, occupied: Array) -> Dictionary:
	var kind := int(v.kind)
	var half := 1.9 if kind == Kind.MARIACHI else (0.9 if kind == Kind.DRUMS else 0.7)
	if int(v.face) < 0:
		# A plaza: either side of the fountain, along its long axis.
		var inner := rect.grow(-2.0)
		var c := inner.get_center()
		var basin := minf(inner.size.x, inner.size.y) * 0.12
		var long_x := inner.size.x >= inner.size.y
		var axis := Vector2(1.0, 0.0) if long_x else Vector2(0.0, 1.0)
		var sgn := 1.0 if int(v.slot) == 0 else -1.0
		var out := axis * sgn
		# Out along the axis from the fountain's rim until the pitch (and a ring) is clear.
		for k in 6:
			var reach := basin + (RING_RADIUS + 4.0 if kind == Kind.BREAK else 6.5) + float(k) * 2.5
			var at := c + out * reach
			var room := half + (RING_RADIUS if kind == Kind.BREAK else 1.2)
			if not inner.grow(-3.0).has_point(at + out * room) or not StreetVendors._clear(occupied, at, room):
				continue
			occupied.append([at, room])
			# Facing out across the plaza, the fountain behind.
			return {"at": at, "yaw": atan2(-out.x, -out.y), "out": out, "along": Vector2(-out.y, out.x)}
		return {}
	var edge: Array = CityChunk._sidewalk_edges(rect)[int(v.face)]
	var a: Vector2 = edge[0]
	var b: Vector2 = edge[1]
	var inward: Vector2 = edge[2]
	var length := a.distance_to(b)
	var dir := (b - a) / length
	for k in 9:
		var t: float = float(v.t) + [0.0, 1.5, -1.5, 3.0, -3.0, 4.5, -4.5, 6.0, -6.0][k]
		if t < CORNER_KEEP - 2.0 or t > length - CORNER_KEEP + 2.0:
			continue
		var q := a + dir * t + inward * PERFORM_IN
		var tips := a + dir * t + inward * TIPS_IN
		if StreetVendors._clear(occupied, q, half) and StreetVendors._clear(occupied, tips, 0.6) \
				and StreetVendors._clear(occupied, a + dir * t + inward * WATCH_IN, 0.5):
			occupied.append([q, half + 0.4])
			occupied.append([tips, 0.6])
			# Facing the street (the kerb), back to the buildings.
			return {"at": q, "yaw": atan2(inward.x, inward.y), "out": -inward, "along": dir}
	return {}


## The gear on the ground and the people's specs for one performer.
static func _lay_out(chunk: CityChunk, rect: Rect2, v: Dictionary, spot: Dictionary, people: Array) -> void:
	var kind := int(v.kind)
	var at: Vector2 = spot.at
	var out: Vector2 = spot.out
	var along: Vector2 = spot.along
	var yaw: float = spot.yaw
	var seed_v := int(v.seed)
	var basis := Basis(Vector3.UP, yaw)
	var xf := Transform3D(basis, Vector3(at.x, CityChunk.SIDEWALK_TOP, at.y))
	var tips_at := at + out * (PERFORM_IN - TIPS_IN)
	var variant := int(_h01([seed_v, "variant"]) * 1000.0)
	match kind:
		Kind.GUITAR, Kind.MARIACHI:
			# The case open on the ground in front, its lid up on the performer's side.
			var cxf := Transform3D(basis, Vector3(tips_at.x, CityChunk.SIDEWALK_TOP, tips_at.y))
			chunk._batch.add(K_CASE, case_mesh(), cxf)
			if kind == Kind.GUITAR and variant % 2 == 0:
				var amp := at + along * 0.75 - out * 0.05
				chunk._batch.add(K_AMP, amp_mesh(), Transform3D(Basis(Vector3.UP, yaw + 0.35), Vector3(amp.x, CityChunk.SIDEWALK_TOP, amp.y)))
		Kind.DRUMS:
			chunk._batch.add(K_DRUMS, drums_mesh(), xf)
		Kind.BREAK:
			chunk._batch.add(K_BREAK, break_mesh(), xf)
		Kind.STATUE:
			chunk._batch.add(K_PLINTH, plinth_mesh(), xf)
	var block_rect: Rect2 = rect
	# The performers.
	var performers: Array = []
	if kind == Kind.MARIACHI:
		for i in 3:
			performers.append([at + along * (float(i) - 1.0) * 1.15 - out * absf(float(i) - 1.0) * 0.25, yaw + (float(i) - 1.0) * -0.18, i])
	else:
		performers.append([at, yaw, 0])
	for p: Array in performers:
		var role: int = p[2]
		people.append({"busker": true, "kind": kind, "role": role, "at": p[0], "yaw": p[1],
			"seed": seed_for(hash([seed_v, role]), RIGS[kind]), "rect": block_rect, "id": v.id})
	# Watchers of their own: a ring round a breakdancer, a couple in front of the mariachis.
	var watchers: Array = []
	if kind == Kind.BREAK:
		for i in RING_WATCHERS:
			var ang := PI * 0.5 + (float(i) - (RING_WATCHERS - 1) * 0.5) * 0.62 + (_h01([seed_v, "ring", i]) - 0.5) * 0.2
			var d := out.rotated(ang - PI * 0.5)
			watchers.append(at + d * (RING_RADIUS + (_h01([seed_v, "ringd", i]) - 0.5) * 0.5))
	elif kind == Kind.MARIACHI:
		for i in 2:
			watchers.append(at + out * (PERFORM_IN - WATCH_IN + 0.3) + along * (float(i) - 0.5) * 1.6)
	for i in watchers.size():
		var w: Vector2 = watchers[i]
		var to := at - w
		people.append({"busker": false, "kind": kind, "role": i, "at": w, "yaw": atan2(-to.x, -to.y),
			"seed": hash([seed_v, "watcher", i]), "rect": block_rect, "id": v.id})
	# Spots for passers-by to stop and watch (the street vendors' queue mechanism).
	if kind != Kind.BREAK:
		var queue: Array = chunk.get_meta("vendor_queue", [])
		for i in WATCH_SPOTS:
			var p := at + out * (PERFORM_IN - WATCH_IN) + along * (float(i) - 1.0) * (1.0 if kind != Kind.MARIACHI else 1.7)
			if kind == Kind.MARIACHI and i != 1:
				p += out * 0.35
			var to := at - p
			queue.append({"p": p, "yaw": atan2(-to.x, -to.y), "taken": null, "record": {"busk": v.id}})
		chunk.set_meta("vendor_queue", queue)


## The `index`-th person this chunk's performers bring (a build step each), if the crowd cap has
## room. A watcher only comes with a performer who did.
static func spawn_person(chunk: CityChunk, index: int) -> void:
	var people: Array = chunk.get_meta("busk_people", [])
	if index >= people.size():
		return
	var s: Dictionary = people[index]
	var acts: Dictionary = chunk.get_meta("busk_live", {})
	if not bool(s.busker) and not acts.has(String(s.id)):
		return
	if not chunk._take_crowd_room():
		return
	var at: Vector2 = s.at
	var ped: Pedestrian
	if bool(s.busker):
		var b := Busker.new()
		b.setup_busker(s.rect, int(s.seed), at, float(s.yaw), int(s.kind), int(s.role))
		ped = b
		if not acts.has(String(s.id)):
			acts[String(s.id)] = b
			chunk.set_meta("busk_live", acts)
	else:
		var w := BuskWatcher.new()
		w.setup_watch(s.rect, int(s.seed), at, float(s.yaw))
		w.performer = acts.get(String(s.id))
		ped = w
	ped.position = Vector3(at.x, chunk.ground_y(at.x, at.y) + 0.05, at.y)
	chunk.add_child(ped)


# --- The gear --------------------------------------------------------------------------------

static func material() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = load("res://shaders/busker_prop.gdshader")
	return _material


static func _cached(key: String, build: Callable) -> ArrayMesh:
	if not _meshes.has(key):
		var k := Kit.new()
		build.call(k)
		_meshes[key] = k.commit(material())
	return _meshes[key]


## An acoustic guitar in its own frame (m): the neck along +X (the headstock end), the top facing
## +Z, the strings' side up +Y; the body's middle at the origin. `s` scales it (a guitarron is
## 1.35 and deeper), `top` / `rim` the sunburst's centre and edge, `wood` the back and sides.
static func guitar_mesh(big: bool = false) -> ArrayMesh:
	return _cached("guitar_%d" % int(big), func(k: Kit) -> void:
		if big:
			_guitar(k, 1.33, 0.2, Color(0.55, 0.32, 0.14), Color(0.16, 0.08, 0.04), Color(0.2, 0.1, 0.05))
		else:
			_guitar(k, 1.0, 0.1, Color(0.88, 0.66, 0.36), Color(0.28, 0.13, 0.05), Color(0.42, 0.22, 0.1)))


static func _body_outline(s: float, lower: Vector3, upper: Vector3, n: int) -> PackedVector2Array:
	# Two ellipses joined (lower bout and upper bout): [centre x, half length, half width] each.
	var x0 := (lower.x - lower.y) * s
	var x1 := (upper.x + upper.y) * s
	var top: Array[Vector2] = []
	for i in n + 1:
		var u := 0.5 - 0.5 * cos(PI * float(i) / float(n))
		var x := lerpf(x0, x1, u)
		var hw := 0.0
		for e: Vector3 in [lower, upper]:
			var d := (x / s - e.x) / e.y
			if absf(d) < 1.0:
				hw = maxf(hw, e.z * sqrt(1.0 - d * d) * s)
		top.append(Vector2(x, maxf(hw, 0.004 * s)))
	var pts := PackedVector2Array()
	for p in top:
		pts.append(p)
	for i in range(top.size() - 2, 0, -1):
		pts.append(Vector2(top[i].x, -top[i].y))
	return pts


static func _guitar(k: Kit, s: float, depth: float, top: Color, rim: Color, wood: Color) -> void:
	var outline := _body_outline(s, Vector3(-0.14, 0.16, 0.19), Vector3(0.085, 0.115, 0.145), 20)
	var hz := depth * 0.5
	k.slab(outline, -hz, hz, top, rim, wood, A_WOOD)
	# Binding round the top's edge (cream), the sound hole and its rosette, the bridge and saddle.
	k.outline_band(outline, hz, hz - 0.006, 0.004, Color(0.86, 0.82, 0.7), A_PAINT)
	k.disc(Vector3(0.062 * s, 0.0, hz + 0.0012), Vector3(0, 0, 1), 0.052 * s, Color(0.82, 0.76, 0.6), A_WOOD, 24)
	k.disc(Vector3(0.062 * s, 0.0, hz + 0.0018), Vector3(0, 0, 1), 0.043 * s, Color(0.02, 0.015, 0.01), A_HOLE, 24)
	k.box(Vector3(-0.155 * s, 0.0, hz + 0.005), Vector3(0.028 * s, 0.15 * s, 0.01), Color(0.1, 0.06, 0.04), A_WOOD)
	k.box(Vector3(-0.15 * s, 0.0, hz + 0.0115), Vector3(0.004, 0.075 * s, 0.004), Color(0.92, 0.9, 0.84), A_PAINT)
	# The pickguard (tortoiseshell), under the hole on the treble side.
	k.box(Vector3(0.02 * s, -0.07 * s, hz + 0.0008), Vector3(0.11 * s, 0.05 * s, 0.0012), Color(0.24, 0.1, 0.05), A_WOOD)
	# The neck, its fretboard, frets, the headstock tilted back, the pegs.
	var nx0 := 0.2 * s
	var nx1 := nx0 + 0.43 * s
	var nz := hz - 0.006
	k.box(Vector3((nx0 + nx1) * 0.5, 0.0, nz - 0.006), Vector3(nx1 - nx0, 0.05 * s, 0.022), wood, A_WOOD)
	k.box(Vector3((nx0 + nx1) * 0.5 - 0.03 * s, 0.0, nz + 0.008), Vector3(nx1 - nx0 + 0.06 * s, 0.052 * s, 0.006), Color(0.07, 0.04, 0.03), A_WOOD)
	for f in 14:
		var fx := nx1 - (nx1 - nx0 + 0.04 * s) * (1.0 - pow(0.944, f + 1)) / (1.0 - pow(0.944, 15))
		k.box(Vector3(fx, 0.0, nz + 0.0115), Vector3(0.0018, 0.051 * s, 0.0012), Color(0.55, 0.54, 0.5), A_STEEL)
	var head := Transform3D(Basis(Vector3(0, 1, 0), 0.22), Vector3(nx1 + 0.085 * s, 0.0, nz - 0.012))
	k.box_xf(head, Vector3(0.18 * s, 0.078 * s, 0.016), Color(0.08, 0.05, 0.03), A_WOOD)
	for i in 6:
		var px := nx1 + 0.035 * s + float(i % 3) * 0.045 * s
		var side := 1.0 if i < 3 else -1.0
		var peg := head * Vector3(px - nx1 - 0.085 * s, side * 0.045 * s, 0.0)
		k.cyl(peg, peg + head.basis.y * side * 0.03, 0.004, 0.004, Color(0.8, 0.8, 0.78), A_STEEL, 6)
		k.box(peg + head.basis.y * side * 0.034, Vector3(0.012, 0.006, 0.016), Color(0.85, 0.83, 0.75), A_PAINT)
	# The strings, bridge to nut.
	for i in 6:
		var y0 := (float(i) - 2.5) * 0.0105 * s
		var y1 := (float(i) - 2.5) * 0.0072 * s
		k.cyl(Vector3(-0.15 * s, y0, hz + 0.0135), Vector3(nx1, y1, nz + 0.0135), 0.0007 + 0.00025 * float(5 - i), 0.0007 + 0.00025 * float(5 - i), Color(0.82, 0.78, 0.66), A_STEEL, 3)


## A violin in the guitar's frame (neck along +X to the scroll, top +Z), body middle at the origin.
static func violin_mesh() -> ArrayMesh:
	return _cached("violin", func(k: Kit) -> void:
		var outline := _body_outline(1.0, Vector3(-0.06, 0.1, 0.103), Vector3(0.105, 0.075, 0.083), 18)
		k.slab(outline, -0.02, 0.02, Color(0.62, 0.22, 0.06), Color(0.3, 0.08, 0.02), Color(0.45, 0.16, 0.05), A_WOOD)
		# f-holes, bridge, tailpiece, fingerboard, scroll, chin rest.
		for side: float in [-1.0, 1.0]:
			k.box(Vector3(-0.03, side * 0.045, 0.0205), Vector3(0.07, 0.006, 0.001), Color(0.02, 0.01, 0.01), A_HOLE)
		k.box(Vector3(-0.03, 0.0, 0.032), Vector3(0.006, 0.042, 0.024), Color(0.85, 0.72, 0.5), A_WOOD)
		k.box(Vector3(-0.11, 0.0, 0.025), Vector3(0.11, 0.035, 0.008), Color(0.03, 0.03, 0.03), A_WOOD)
		k.box(Vector3(0.13, 0.0, 0.031), Vector3(0.27, 0.026, 0.008), Color(0.02, 0.02, 0.02), A_WOOD)
		k.box(Vector3(0.22, 0.0, 0.016), Vector3(0.12, 0.024, 0.02), Color(0.45, 0.16, 0.05), A_WOOD)
		k.cyl(Vector3(0.3, -0.016, 0.012), Vector3(0.3, 0.016, 0.012), 0.017, 0.017, Color(0.42, 0.15, 0.05), A_WOOD, 10)
		k.box(Vector3(-0.15, 0.04, 0.027), Vector3(0.05, 0.05, 0.012), Color(0.04, 0.03, 0.03), A_WOOD)
		for i in 4:
			var y := (float(i) - 1.5) * 0.0065
			k.cyl(Vector3(-0.1, y * 1.2, 0.035), Vector3(0.27, y * 0.8, 0.036), 0.0006, 0.0006, Color(0.8, 0.78, 0.7), A_STEEL, 3))


## A violin bow along +X from the frog at the origin (the hand), 0.74 m.
static func bow_mesh() -> ArrayMesh:
	return _cached("bow", func(k: Kit) -> void:
		k.cyl(Vector3(-0.02, 0.0, 0.0), Vector3(0.72, 0.0, 0.0), 0.0045, 0.0028, Color(0.3, 0.12, 0.05), A_WOOD, 6)
		k.box(Vector3(0.01, -0.012, 0.0), Vector3(0.045, 0.018, 0.012), Color(0.03, 0.03, 0.03), A_WOOD)
		k.box(Vector3(0.36, -0.016, 0.0), Vector3(0.7, 0.0015, 0.009), Color(0.92, 0.9, 0.82), A_PAINT)
		k.box(Vector3(0.715, -0.009, 0.0), Vector3(0.01, 0.016, 0.008), Color(0.88, 0.86, 0.8), A_PAINT))


## A trumpet along +X from the mouthpiece at the origin to the bell, valves up +Y.
static func trumpet_mesh() -> ArrayMesh:
	return _cached("trumpet", func(k: Kit) -> void:
		var brass := Color(0.86, 0.66, 0.3)
		k.cyl(Vector3(0.0, 0.0, 0.0), Vector3(0.03, 0.0, 0.0), 0.009, 0.004, Color(0.82, 0.82, 0.8), A_STEEL, 10)
		k.cyl(Vector3(0.03, 0.0, 0.0), Vector3(0.16, 0.0, 0.0), 0.0045, 0.0055, brass, A_BRASS, 10)
		# The lower tube back under the valves and the main slide's bow.
		k.cyl(Vector3(0.16, -0.045, 0.0), Vector3(0.03, -0.045, 0.0), 0.0058, 0.0058, brass, A_BRASS, 10)
		k.cyl(Vector3(0.03, -0.045, 0.0), Vector3(0.03, 0.0, 0.0), 0.0058, 0.0058, brass, A_BRASS, 8)
		# The bell tube from the valves out, flaring.
		k.cyl(Vector3(0.24, -0.045, 0.0), Vector3(0.3, -0.045, 0.0), 0.0062, 0.0075, brass, A_BRASS, 12)
		k.cyl(Vector3(0.3, -0.045, 0.0), Vector3(0.4, -0.045, 0.0), 0.0075, 0.018, brass, A_BRASS, 14)
		k.cyl(Vector3(0.4, -0.045, 0.0), Vector3(0.455, -0.045, 0.0), 0.018, 0.058, brass, A_BRASS, 18)
		k.disc(Vector3(0.452, -0.045, 0.0), Vector3(1, 0, 0), 0.052, Color(0.2, 0.15, 0.08), A_HOLE, 18)
		# Valves, their caps and pearl buttons.
		for i in 3:
			var x := 0.175 + float(i) * 0.024
			k.cyl(Vector3(x, -0.075, 0.0), Vector3(x, 0.03, 0.0), 0.0085, 0.0085, brass, A_BRASS, 12)
			k.cyl(Vector3(x, 0.03, 0.0), Vector3(x, 0.052, 0.0), 0.0025, 0.0025, brass, A_BRASS, 6)
			k.cyl(Vector3(x, 0.052, 0.0), Vector3(x, 0.058, 0.0), 0.007, 0.007, Color(0.94, 0.92, 0.86), A_PAINT, 10)
		k.cyl(Vector3(0.16, 0.0, 0.0), Vector3(0.235, 0.0, 0.0), 0.0055, 0.0055, brass, A_BRASS, 8)
		k.cyl(Vector3(0.235, 0.0, 0.0), Vector3(0.235, -0.045, 0.0), 0.006, 0.006, brass, A_BRASS, 8))


## A drumstick along +X from the butt at the origin, 0.41 m, the bead at the far end.
static func stick_mesh() -> ArrayMesh:
	return _cached("stick", func(k: Kit) -> void:
		k.cyl(Vector3(-0.08, 0.0, 0.0), Vector3(0.24, 0.0, 0.0), 0.0072, 0.0068, Color(0.86, 0.72, 0.5), A_WOOD, 8)
		k.cyl(Vector3(0.24, 0.0, 0.0), Vector3(0.32, 0.0, 0.0), 0.0068, 0.0035, Color(0.86, 0.72, 0.5), A_WOOD, 8)
		k.cyl(Vector3(0.32, 0.0, 0.0), Vector3(0.335, 0.0, 0.0), 0.0045, 0.002, Color(0.86, 0.72, 0.5), A_WOOD, 6))


## An open guitar case in its frame: long side along X, the lid up on the +Z side (toward the
## performer), the plush showing; coins and a few bills in it.
static func case_mesh() -> ArrayMesh:
	return _cached("case", func(k: Kit) -> void:
		var shell := Color(0.07, 0.065, 0.06)
		var plush := Color(0.42, 0.05, 0.08)
		var outline := _body_outline(1.08, Vector3(-0.14, 0.16, 0.2), Vector3(0.12, 0.2, 0.15), 14)
		var lifted := PackedVector2Array()
		for p in outline:
			lifted.append(p)
		# The base: a shell 11 cm deep laid flat (outline in X-Z), the plush well inside it.
		var flat := Transform3D(Basis(Vector3(1, 0, 0), -PI * 0.5), Vector3.ZERO)
		k.push(flat)
		k.slab(lifted, 0.0, 0.11, shell, shell, shell, A_RUBBER)
		var inner := PackedVector2Array()
		for p in outline:
			inner.append(p * 0.9)
		k.slab(inner, 0.05, 0.1125, plush, plush, plush, A_PLUSH)
		k.pop()
		# The lid, swung 100 degrees back about the hinge on the +Z edge (its plush toward the
		# street), the base's outline again.
		var hinge := Vector3(0.0, 0.11, 0.215)
		var open := Transform3D(Basis.IDENTITY, hinge) * Transform3D(Basis(Vector3(1, 0, 0), 1.75), Vector3.ZERO) \
			* Transform3D(Basis.IDENTITY, Vector3(0.0, 0.11, 0.0) - hinge) * flat
		k.push(open)
		k.slab(lifted, 0.0, 0.05, shell, shell, shell, A_RUBBER)
		k.slab(inner, -0.002, 0.01, plush, plush, plush, A_PLUSH)
		k.pop()
		# Latches.
		for x: float in [-0.25, 0.1]:
			k.box(Vector3(x, 0.06, -0.19), Vector3(0.04, 0.03, 0.012), Color(0.75, 0.75, 0.72), A_STEEL)
		# The tips: coins and a few bills on the plush.
		var r := RandomNumberGenerator.new()
		r.seed = 4417
		for i in 14:
			var p := Vector3(r.randf_range(-0.38, 0.32), 0.1135 + r.randf() * 0.002, r.randf_range(-0.09, 0.09))
			var cc := Color(0.8, 0.62, 0.3) if r.randf() < 0.4 else Color(0.78, 0.78, 0.76)
			k.disc(p, Vector3(0, 1, 0), r.randf_range(0.009, 0.013), cc, A_BRASS if cc.r > cc.b + 0.1 else A_STEEL, 10)
		for i in 4:
			var bxf := Transform3D(Basis(Vector3.UP, r.randf_range(-0.6, 0.6)), Vector3(r.randf_range(-0.3, 0.25), 0.1145 + float(i) * 0.0008, r.randf_range(-0.05, 0.05)))
			k.box_xf(bxf, Vector3(0.156, 0.0006, 0.066), Color(0.36, 0.42, 0.32), A_PAINT))


## A small practice amp, 36 x 33 x 20 cm, its grille facing -Z.
static func amp_mesh() -> ArrayMesh:
	return _cached("amp", func(k: Kit) -> void:
		k.box(Vector3(0.0, 0.165, 0.0), Vector3(0.36, 0.33, 0.2), Color(0.05, 0.05, 0.05), A_RUBBER)
		k.box(Vector3(0.0, 0.14, -0.1005), Vector3(0.32, 0.22, 0.002), Color(0.16, 0.15, 0.13), A_PLUSH)
		k.box(Vector3(0.0, 0.29, -0.1005), Vector3(0.32, 0.05, 0.002), Color(0.6, 0.58, 0.55), A_STEEL)
		for i in 5:
			k.cyl(Vector3(-0.12 + float(i) * 0.05, 0.29, -0.102), Vector3(-0.12 + float(i) * 0.05, 0.29, -0.112), 0.008, 0.007, Color(0.06, 0.06, 0.06), A_PLASTIC, 8)
		k.box(Vector3(0.0, 0.335, 0.0), Vector3(0.12, 0.012, 0.025), Color(0.05, 0.05, 0.05), A_RUBBER))


## A 5 gallon bucket (or a paint pail when `pail`): `up` true stands it open end up.
static func _bucket(k: Kit, at: Vector3, colour: Color, up: bool, pail: bool = false) -> void:
	var h := 0.19 if pail else 0.37
	var r_bot := 0.085 if pail else 0.145
	var r_top := 0.09 if pail else 0.162
	var kind := A_STEEL if pail else A_PLASTIC
	if up:
		k.cyl(at, at + Vector3(0, h, 0), r_bot, r_top, colour, kind, 22, true, false)
		k.cyl(at + Vector3(0, 0.01, 0), at + Vector3(0, h, 0), r_bot - 0.004, r_top - 0.004, colour.darkened(0.25), kind, 22, false, false, true)
		k.disc(at + Vector3(0, h * 0.25, 0), Vector3(0, 1, 0), lerpf(r_bot, r_top, 0.25) * 0.99, colour.darkened(0.5), kind, 22)
		k.ring(at + Vector3(0, h, 0), r_top, 0.012, colour, kind, 22)
	else:
		# Upturned: the open end down, the base up to be struck; the base's rim stands proud.
		k.cyl(at, at + Vector3(0, h, 0), r_top, r_bot, colour, kind, 22, false, true)
		k.ring(at + Vector3(0, 0.012, 0), r_top + 0.004, 0.014, colour, kind, 22)
		k.ring(at + Vector3(0, h - 0.004, 0), r_bot, 0.008, colour.darkened(0.08), kind, 22)
		if not pail:
			# Stiffening ribs round the top band.
			for i in 3:
				k.ring(at + Vector3(0, h * (0.72 + 0.06 * i), 0), lerpf(r_top, r_bot, 0.72 + 0.06 * i) + 0.003, 0.004, colour, kind, 22)


## A milk crate upturned (open side down), its top at 0.28 m.
static func _crate(k: Kit, at: Vector3, colour: Color) -> void:
	var s := 0.33
	var h := 0.28
	k.box(at + Vector3(0, h - 0.01, 0), Vector3(s, 0.02, s), colour, A_PLASTIC)
	for e in 4:
		var n := Vector3(1, 0, 0).rotated(Vector3.UP, PI * 0.5 * e)
		var t := n.cross(Vector3.UP)
		# Each side a frame with three slats (the lattice reads at a few metres).
		k.box(at + n * (s * 0.5 - 0.008) + Vector3(0, 0.02, 0), (t.abs() * s + n.abs() * 0.016 + Vector3(0, 0.04, 0)), colour, A_PLASTIC)
		for j in 3:
			k.box(at + n * (s * 0.5 - 0.008) + Vector3(0, 0.08 + 0.065 * j, 0), (t.abs() * s + n.abs() * 0.016 + Vector3(0, 0.022, 0)), colour, A_PLASTIC)
		k.box(at + n * (s * 0.5 - 0.008) + t * (s * 0.5 - 0.012) + Vector3(0, h * 0.5, 0), Vector3(0.024, h, 0.024), colour, A_PLASTIC)


## The drum kit, in the drummer's frame (feet at the origin, facing -Z, +X the right hand).
static func drums_mesh() -> ArrayMesh:
	return _cached("drums", func(k: Kit) -> void:
		var orange := Color(0.92, 0.42, 0.08)
		var white := Color(0.88, 0.88, 0.85)
		var blue := Color(0.12, 0.3, 0.62)
		# The seat: an upturned bucket with a folded towel on it.
		_bucket(k, Vector3(0.0, 0.0, SEAT_BACK), white, false)
		k.box(Vector3(0.0, 0.378, SEAT_BACK), Vector3(0.28, 0.018, 0.26), Color(0.2, 0.32, 0.36), A_PLUSH)
		# Bass bucket between the knees, the high bucket on a crate, the pail on a crate.
		var hits: Array = DRUM_HITS
		_bucket(k, Vector3((hits[0] as Vector3).x, 0.0, (hits[0] as Vector3).z), orange, false)
		_crate(k, Vector3((hits[1] as Vector3).x, 0.0, (hits[1] as Vector3).z), blue)
		_bucket(k, Vector3((hits[1] as Vector3).x, 0.28, (hits[1] as Vector3).z), white, false)
		_crate(k, Vector3((hits[2] as Vector3).x, 0.0, (hits[2] as Vector3).z), Color(0.1, 0.1, 0.1))
		_bucket(k, Vector3((hits[2] as Vector3).x, 0.28, (hits[2] as Vector3).z), Color(0.72, 0.72, 0.7), false, true)
		# The cymbal: a pot lid on a tripod stand.
		var cy: Vector3 = hits[3]
		k.cyl(Vector3(cy.x, 0.02, cy.z), Vector3(cy.x, cy.y - 0.01, cy.z), 0.008, 0.007, Color(0.6, 0.6, 0.6), A_STEEL, 8)
		for i in 3:
			var d := Vector3(0.0, 0.0, 0.22).rotated(Vector3.UP, TAU * float(i) / 3.0 + 0.3)
			k.cyl(Vector3(cy.x, 0.3, cy.z), Vector3(cy.x, 0.0, cy.z) + d, 0.006, 0.006, Color(0.55, 0.55, 0.55), A_STEEL, 6)
		k.cyl(Vector3(cy.x, cy.y - 0.012, cy.z), Vector3(cy.x, cy.y + 0.004, cy.z), 0.15, 0.04, Color(0.78, 0.74, 0.62), A_BRASS, 24, true, true)
		k.cyl(Vector3(cy.x, cy.y + 0.004, cy.z), Vector3(cy.x, cy.y + 0.03, cy.z), 0.012, 0.01, Color(0.1, 0.1, 0.1), A_RUBBER, 8)
		# The tips: a bucket upright in front with bills in it, and a spare pair of sticks.
		_bucket(k, Vector3(0.1, 0.0, -1.05), orange, true)
		for i in 3:
			k.box_xf(Transform3D(Basis(Vector3.UP, 0.7 * i), Vector3(0.1, 0.095 + 0.001 * i, -1.05)), Vector3(0.156, 0.0006, 0.066), Color(0.36, 0.42, 0.32), A_PAINT)
		for i in 2:
			k.cyl(Vector3(-0.55, 0.008, -0.15 + 0.02 * i), Vector3(-0.22, 0.008, -0.05 + 0.03 * i), 0.007, 0.005, Color(0.86, 0.72, 0.5), A_WOOD, 6))


## The breakdancer's floor: two flattened boxes taped together, a boombox to the side and an
## upturned cap for the tips, in the dancer's frame.
static func break_mesh() -> ArrayMesh:
	return _cached("break", func(k: Kit) -> void:
		var card := Color(0.66, 0.5, 0.32)
		k.box_xf(Transform3D(Basis(Vector3.UP, 0.04), Vector3(-0.55, 0.004, 0.0)), Vector3(1.25, 0.006, 2.1), card, A_CARD)
		k.box_xf(Transform3D(Basis(Vector3.UP, -0.03), Vector3(0.55, 0.0045, 0.05)), Vector3(1.2, 0.006, 2.05), card.darkened(0.06), A_CARD)
		for z: float in [-0.8, 0.0, 0.8]:
			k.box(Vector3(0.0, 0.0085, z), Vector3(0.09, 0.0015, 0.42), Color(0.55, 0.52, 0.45), A_PLASTIC)
		# Boombox: off the floor to the dancer's left, speakers to the floor's middle.
		var bb := Transform3D(Basis(Vector3.UP, PI * 0.5 + 0.3), Vector3(-1.75, 0.0, -0.4))
		k.push(bb)
		k.box(Vector3(0.0, 0.15, 0.0), Vector3(0.58, 0.28, 0.17), Color(0.1, 0.1, 0.11), A_RUBBER)
		for x: float in [-0.18, 0.18]:
			k.disc(Vector3(x, 0.14, -0.0865), Vector3(0, 0, -1), 0.095, Color(0.25, 0.25, 0.26), A_STEEL, 20)
			k.disc(Vector3(x, 0.14, -0.088), Vector3(0, 0, -1), 0.075, Color(0.04, 0.04, 0.04), A_RUBBER, 20)
			k.disc(Vector3(x, 0.14, -0.089), Vector3(0, 0, -1), 0.025, Color(0.6, 0.6, 0.6), A_STEEL, 12)
		k.box(Vector3(0.0, 0.2, -0.0865), Vector3(0.12, 0.04, 0.003), Color(0.1, 0.9, 0.35), A_LED)
		k.box(Vector3(0.0, 0.12, -0.0865), Vector3(0.1, 0.035, 0.003), Color(0.22, 0.22, 0.22), A_PLASTIC)
		k.cyl(Vector3(-0.22, 0.29, 0.0), Vector3(-0.2, 0.36, 0.0), 0.01, 0.01, Color(0.7, 0.7, 0.7), A_STEEL, 6)
		k.cyl(Vector3(0.22, 0.29, 0.0), Vector3(0.2, 0.36, 0.0), 0.01, 0.01, Color(0.7, 0.7, 0.7), A_STEEL, 6)
		k.cyl(Vector3(-0.2, 0.36, 0.0), Vector3(0.2, 0.36, 0.0), 0.012, 0.012, Color(0.7, 0.7, 0.7), A_STEEL, 8)
		k.pop()
		# The cap, crown down, in front.
		var cap := Vector3(1.55, 0.0, -0.85)
		k.cyl(cap + Vector3(0, 0.0, 0), cap + Vector3(0, 0.1, 0), 0.07, 0.095, Color(0.1, 0.1, 0.12), A_PLUSH, 16, true, false)
		k.box_xf(Transform3D(Basis(Vector3.UP, 0.4), cap + Vector3(0.1, 0.004, 0.06)), Vector3(0.12, 0.005, 0.08), Color(0.1, 0.1, 0.12), A_PLUSH)
		k.box_xf(Transform3D(Basis(Vector3.UP, 0.9), cap + Vector3(0.0, 0.07, 0.0)), Vector3(0.156, 0.0006, 0.066), Color(0.36, 0.42, 0.32), A_PAINT))


## The living statue's plinth: a painted box with a moulded top, a tin for the tips in front.
static func plinth_mesh() -> ArrayMesh:
	return _cached("plinth", func(k: Kit) -> void:
		var silver := Color(0.72, 0.72, 0.7)
		k.box(Vector3(0.0, PLINTH_H * 0.5 - 0.02, 0.0), Vector3(0.58, PLINTH_H - 0.04, 0.58), silver, A_SILVER)
		k.box(Vector3(0.0, PLINTH_H - 0.02, 0.0), Vector3(0.66, 0.04, 0.66), silver.lightened(0.05), A_SILVER)
		k.box(Vector3(0.0, 0.02, 0.0), Vector3(0.64, 0.04, 0.64), silver.darkened(0.15), A_SILVER)
		# The tin, open, a coin or two, and a chalk mark on the paving.
		k.cyl(Vector3(0.0, 0.0, -0.75), Vector3(0.0, 0.13, -0.75), 0.06, 0.06, Color(0.76, 0.76, 0.74), A_STEEL, 16, true, false)
		k.disc(Vector3(0.0, 0.03, -0.75), Vector3(0, 1, 0), 0.058, Color(0.25, 0.25, 0.25), A_STEEL, 16)
		k.ring(Vector3(0.0, 0.13, -0.75), 0.06, 0.004, Color(0.8, 0.8, 0.78), A_STEEL, 16)
		k.box(Vector3(0.0, 0.001, -0.5), Vector3(0.5, 0.001, 0.04), Color(0.9, 0.88, 0.82), A_PAINT))


## A mariachi's sombrero round a crowd rig's head (CrowdHat's head frame and measurements, as
## FireHelmet builds its helmet): a tall felt crown, a wide brim turned up at the edge, a silver
## embroidered band and edge. One mesh per rig.
static func sombrero_mesh(rig: String) -> ArrayMesh:
	return _cached("sombrero_" + rig.get_file(), func(k: Kit) -> void:
		var h := CrowdHat.head_for(rig)
		var felt := Color(0.05, 0.045, 0.045)
		var silver := Color(0.78, 0.78, 0.76)
		var cols := 32
		var band: Array[Vector3] = []
		for j in cols + 1:
			var th := TAU * float(j) / float(cols)
			var y := h.eye_y + 0.035
			var ph := h.phi_at_height(th, y)
			var d := CrowdHat.Head.dir(th, ph)
			band.append(h.c + d * (h.radius(th, ph) + 0.02))
		var top_y := maxf(h.top, h.eye_y + 0.1) + 0.12
		var peak := Vector3(h.c.x, top_y, h.c.z - 0.01)
		# The crown: from the band up, narrowing, dented in at the top.
		var rows := 6
		var prev := band
		for i in range(1, rows + 1):
			var f := float(i) / float(rows)
			var ring: Array[Vector3] = []
			for j in cols + 1:
				var p: Vector3 = band[j]
				var rel := p - Vector3(h.c.x, p.y, h.c.z)
				var shrink := lerpf(1.0, 0.55, f * f)
				var y := lerpf(p.y, top_y - 0.015 * (1.0 + cos(TAU * float(j) / float(cols) * 2.0)), f)
				ring.append(Vector3(h.c.x, y, h.c.z) + rel * shrink)
			for j in cols:
				var col := silver if i == 1 else felt
				k.quad_out(prev[j], prev[j + 1], ring[j + 1], ring[j], col, A_PAINT if i != 1 else A_SILVER, h.c)
			prev = ring
		for j in cols:
			k.tri_out(prev[j], prev[j + 1], peak, felt, A_PAINT, h.c - Vector3(0, 0.2, 0))
		# The brim: out to 0.32 m, dipping a little, then rolled up at the edge.
		var r_in: Array[Vector3] = band
		var mid: Array[Vector3] = []
		var rim: Array[Vector3] = []
		var lip: Array[Vector3] = []
		for j in cols + 1:
			var th := TAU * float(j) / float(cols)
			var o := Vector3(sin(th), 0.0, cos(th))
			var base := Vector3(h.c.x, (band[j] as Vector3).y, h.c.z)
			mid.append(base + o * 0.22 + Vector3(0, -0.012, 0))
			rim.append(base + o * 0.3 + Vector3(0, 0.0, 0))
			lip.append(base + o * 0.315 + Vector3(0, 0.055, 0))
		for j in cols:
			for pair: Array in [[r_in, mid, felt], [mid, rim, felt], [rim, lip, silver]]:
				var a: Array = pair[0]
				var b: Array = pair[1]
				k.quad_up(a[j], a[j + 1], b[j + 1], b[j], pair[2], A_PAINT if pair[2] == felt else A_SILVER, true)
				k.quad_up(a[j] + Vector3(0, -0.006, 0), a[j + 1] + Vector3(0, -0.006, 0), b[j + 1] + Vector3(0, -0.006, 0), b[j] + Vector3(0, -0.006, 0), felt.lightened(0.04), A_PAINT, false))


## Every mesh built once (the loading screen, the checks).
static func warm() -> void:
	guitar_mesh(false)
	guitar_mesh(true)
	violin_mesh()
	bow_mesh()
	trumpet_mesh()
	stick_mesh()
	case_mesh()
	amp_mesh()
	drums_mesh()
	break_mesh()
	plinth_mesh()


## The meshes on the ground, by batch key (the checks).
static func gear_meshes() -> Dictionary:
	return {K_CASE: case_mesh(), K_DRUMS: drums_mesh(), K_BREAK: break_mesh(), K_PLINTH: plinth_mesh(), K_AMP: amp_mesh()}


# --- Geometry --------------------------------------------------------------------------------

## A small mesh writer: triangles turned to face the way asked (Godot's front faces wind
## clockwise seen from the front), smooth or flat normals, colours as sRGB with the surface
## code in alpha, an optional stack of local frames.
class Kit:
	var st := SurfaceTool.new()
	var xf_stack: Array[Transform3D] = [Transform3D.IDENTITY]

	func _init() -> void:
		st.begin(Mesh.PRIMITIVE_TRIANGLES)

	func push(xf: Transform3D) -> void:
		xf_stack.append(xf_stack.back() * xf)

	func pop() -> void:
		xf_stack.pop_back()

	func commit(mat: Material) -> ArrayMesh:
		st.set_material(mat)
		return st.commit()

	func _v(p: Vector3, n: Vector3, col: Color, kind: float) -> void:
		var xf: Transform3D = xf_stack.back()
		st.set_color(Color(col.r, col.g, col.b, kind))
		st.set_normal((xf.basis * n).normalized())
		st.add_vertex(xf * p)

	## A triangle with per-corner normals, wound so its front faces along the normals' mean.
	func tri_n(a: Vector3, b: Vector3, c: Vector3, na: Vector3, nb: Vector3, nc: Vector3, col: Color, kind: float) -> void:
		var g := (b - a).cross(c - a)
		if g.length_squared() < 1e-16:
			return
		if g.dot(na + nb + nc) > 0.0:
			_v(a, na, col, kind)
			_v(c, nc, col, kind)
			_v(b, nb, col, kind)
		else:
			_v(a, na, col, kind)
			_v(b, nb, col, kind)
			_v(c, nc, col, kind)

	func tri(a: Vector3, b: Vector3, c: Vector3, n: Vector3, col: Color, kind: float) -> void:
		var g := (b - a).cross(c - a)
		if g.length_squared() < 1e-16:
			return
		var fn := g.normalized()
		if fn.dot(n) < 0.0:
			fn = -fn
		tri_n(a, b, c, fn, fn, fn, col, kind)

	func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, col: Color, kind: float) -> void:
		tri(a, b, c, n, col, kind)
		tri(a, c, d, n, col, kind)

	## A face pointing away from (or toward) `centre`.
	func tri_out(a: Vector3, b: Vector3, c: Vector3, col: Color, kind: float, centre: Vector3) -> void:
		tri(a, b, c, (a + b + c) / 3.0 - centre, col, kind)

	func quad_out(a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color, kind: float, centre: Vector3) -> void:
		var n := (a + b + c + d) * 0.25 - centre
		quad(a, b, c, d, n, col, kind)

	## A face pointing up (or down).
	func quad_up(a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color, kind: float, up: bool) -> void:
		quad(a, b, c, d, Vector3.UP if up else Vector3.DOWN, col, kind)

	func box(c: Vector3, s: Vector3, col: Color, kind: float) -> void:
		box_xf(Transform3D(Basis.IDENTITY, c), s, col, kind)

	func box_xf(xf: Transform3D, s: Vector3, col: Color, kind: float) -> void:
		var h := s * 0.5
		for axis in 3:
			for sgn: float in [-1.0, 1.0]:
				var n := Vector3.ZERO
				n[axis] = sgn
				var u := Vector3.ZERO
				u[(axis + 1) % 3] = 1.0
				var v := Vector3.ZERO
				v[(axis + 2) % 3] = 1.0
				var o := n * h[axis]
				var du := u * h[(axis + 1) % 3]
				var dv := v * h[(axis + 2) % 3]
				var q := [xf * (o - du - dv), xf * (o + du - dv), xf * (o + du + dv), xf * (o - du + dv)]
				quad(q[0], q[1], q[2], q[3], xf.basis * n, col, kind)

	## A tube (frustum) from `a` to `b`, smooth sides, capped as asked.
	func cyl(a: Vector3, b: Vector3, r0: float, r1: float, col: Color, kind: float, seg: int,
			cap_a: bool = true, cap_b: bool = true, inside: bool = false) -> void:
		var axis := b - a
		if axis.length_squared() < 1e-12:
			return
		var ax := axis.normalized()
		var u := ax.cross(Vector3.UP if absf(ax.y) < 0.9 else Vector3.RIGHT).normalized()
		var v := ax.cross(u)
		var slope := (r0 - r1) / axis.length()
		for i in seg:
			var a0 := TAU * float(i) / float(seg)
			var a1 := TAU * float(i + 1) / float(seg)
			var d0 := u * cos(a0) + v * sin(a0)
			var d1 := u * cos(a1) + v * sin(a1)
			var n0 := (d0 + ax * slope).normalized() * (-1.0 if inside else 1.0)
			var n1 := (d1 + ax * slope).normalized() * (-1.0 if inside else 1.0)
			var p0 := a + d0 * r0
			var p1 := a + d1 * r0
			var q0 := b + d0 * r1
			var q1 := b + d1 * r1
			tri_n(p0, q0, q1, n0, n0, n1, col, kind)
			tri_n(p0, q1, p1, n0, n1, n1, col, kind)
			if cap_a and r0 > 0.0:
				tri(a, p1, p0, -ax, col, kind)
			if cap_b and r1 > 0.0:
				tri(b, q0, q1, ax, col, kind)

	## A flat disc facing `n`.
	func disc(c: Vector3, n: Vector3, r: float, col: Color, kind: float, seg: int) -> void:
		var nn := n.normalized()
		var u := nn.cross(Vector3.UP if absf(nn.y) < 0.9 else Vector3.RIGHT).normalized()
		var v := nn.cross(u)
		for i in seg:
			var a0 := TAU * float(i) / float(seg)
			var a1 := TAU * float(i + 1) / float(seg)
			tri(c, c + (u * cos(a0) + v * sin(a0)) * r, c + (u * cos(a1) + v * sin(a1)) * r, nn, col, kind)

	## A rolled rim (a short fat tube round the vertical axis) at height `c`, radius `r`.
	func ring(c: Vector3, r: float, thick: float, col: Color, kind: float, seg: int) -> void:
		for i in seg:
			var a0 := TAU * float(i) / float(seg)
			var a1 := TAU * float(i + 1) / float(seg)
			var d0 := Vector3(cos(a0), 0.0, sin(a0))
			var d1 := Vector3(cos(a1), 0.0, sin(a1))
			var lo := Vector3(0, -thick * 0.5, 0)
			var hi := Vector3(0, thick * 0.5, 0)
			var o0 := c + d0 * (r + thick * 0.5)
			var o1 := c + d1 * (r + thick * 0.5)
			quad(o0 + lo, o1 + lo, o1 + hi, o0 + hi, (d0 + d1) * 0.5, col, kind)
			quad(c + d0 * r + hi, c + d1 * r + hi, o1 + hi, o0 + hi, Vector3.UP, col, kind)
			quad(c + d0 * r + lo, c + d1 * r + lo, o1 + lo, o0 + lo, Vector3.DOWN, col, kind)

	## An outline (in the XY plane, star-shaped from the origin) extruded from z0 to z1: the +Z
	## face shaded from `centre` to `edge` (a sunburst), the -Z face and the sides `side`.
	func slab(outline: PackedVector2Array, z0: float, z1: float, centre: Color, edge: Color, side: Color, kind: float) -> void:
		var n := outline.size()
		var mid := Vector2.ZERO
		for p in outline:
			mid += p
		mid /= float(n)
		for i in n:
			var p := outline[i]
			var q := outline[(i + 1) % n]
			var ep := edge.lerp(centre, 0.0)
			# Top: a fan with a ring at 60 % so the sunburst has room to fade.
			var p6 := mid.lerp(p, 0.6)
			var q6 := mid.lerp(q, 0.6)
			var c6 := centre.lerp(edge, 0.25)
			tri(Vector3(mid.x, mid.y, z1), Vector3(p6.x, p6.y, z1), Vector3(q6.x, q6.y, z1), Vector3.BACK, centre, kind)
			_quad_cols(Vector3(p6.x, p6.y, z1), Vector3(q6.x, q6.y, z1), Vector3(q.x, q.y, z1), Vector3(p.x, p.y, z1), Vector3.BACK, c6, c6, ep, ep, kind)
			tri(Vector3(mid.x, mid.y, z0), Vector3(p.x, p.y, z0), Vector3(q.x, q.y, z0), Vector3.FORWARD, side, kind)
			# Sides: normals from the outline's own direction, smooth.
			var tp := (outline[(i + 1) % n] - outline[(i - 1 + n) % n]).normalized()
			var tq := (outline[(i + 2) % n] - outline[i]).normalized()
			var np := Vector3(tp.y, -tp.x, 0.0)
			var nq := Vector3(tq.y, -tq.x, 0.0)
			if np.dot(Vector3(p.x - mid.x, p.y - mid.y, 0.0)) < 0.0:
				np = -np
				nq = -nq
			tri_n(Vector3(p.x, p.y, z0), Vector3(q.x, q.y, z0), Vector3(q.x, q.y, z1), np, nq, nq, side, kind)
			tri_n(Vector3(p.x, p.y, z0), Vector3(q.x, q.y, z1), Vector3(p.x, p.y, z1), np, nq, np, side, kind)

	func _quad_cols(a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, ca: Color, cb: Color, cc: Color, cd: Color, kind: float) -> void:
		for t: Array in [[a, b, c, ca, cb, cc], [a, c, d, ca, cc, cd]]:
			var g := ((t[1] as Vector3) - (t[0] as Vector3)).cross((t[2] as Vector3) - (t[0] as Vector3))
			if g.length_squared() < 1e-16:
				continue
			if g.dot(n) > 0.0:
				_v(t[0], n, t[3], kind)
				_v(t[2], n, t[5], kind)
				_v(t[1], n, t[4], kind)
			else:
				_v(t[0], n, t[3], kind)
				_v(t[1], n, t[4], kind)
				_v(t[2], n, t[5], kind)

	## A thin band along an outline at the top face (binding): from z_top down to z_bot, `w` wide.
	func outline_band(outline: PackedVector2Array, z_top: float, z_bot: float, w: float, col: Color, kind: float) -> void:
		var n := outline.size()
		for i in n:
			var p := outline[i]
			var q := outline[(i + 1) % n]
			var t := (q - p).normalized()
			var o := Vector2(t.y, -t.x)
			if o.dot(p) < 0.0:
				o = -o
			var p1 := p + o * 0.0006
			var q1 := q + o * 0.0006
			quad(Vector3(p1.x, p1.y, z_bot), Vector3(q1.x, q1.y, z_bot), Vector3(q1.x, q1.y, z_top), Vector3(p1.x, p1.y, z_top), Vector3(o.x, o.y, 0.0), col, kind)
			var pi := p - o * w
			var qi := q - o * w
			quad(Vector3(pi.x, pi.y, z_top + 0.0004), Vector3(qi.x, qi.y, z_top + 0.0004), Vector3(q1.x, q1.y, z_top + 0.0004), Vector3(p1.x, p1.y, z_top + 0.0004), Vector3.BACK, col, kind)
