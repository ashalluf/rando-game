class_name WorshipSunday
extends RefCounted
## The congregation (wave 8 refcam5 "church_sunday", docs/HANDOFF.md "The Mission church on a
## Sunday morning"): a place of worship's people on its day - Sunday for the churches and the
## temple, Saturday for the synagogue - before and after each service. The services are the ones
## its own name board lists (WorshipBuild._service_line()), so a board that says 10:30 Mass has a
## forecourt filling at 10:00. Who comes is an ordinary Pedestrian (Worshipper): shot, knocked and
## ragdolled like anyone, in the crowd cap; they walk up the pavement, in at the gate, up the path,
## stand and talk on the forecourt, and go in at the door; after a service they come out and go.
##
## How many is pure (`count()`: kind, seed, day, hour); where is the site's frame (`spots()`), so
## a FULL chunk builds them with the building (WorshipBuild.build() calls `people()` after the
## grounds). Hashes only: the block rng is never touched.
##
## WORSHIP_SUNDAY=0 in the environment: nobody (the A/B). WORSHIP_DAY=0..6 (0 Sunday) and
## WORSHIP_HOUR=h force the day and the hour the chunk is built for (stills, the refcam's
## `sunday` key).

static func _static_init() -> void: LoadPulse.compiled()  # a boot frame: docs/HANDOFF.md "The boot compile"

static var enabled: bool = OS.get_environment("WORSHIP_SUNDAY") != "0"
## Forced day / hour (-1: the calendar; tests). The environment's are read when asked, so a tool
## may set them after this class has compiled.
static var force_day: int = -1
static var force_hour: float = -1.0

## The most people a site holds at the peak, by kind (Worship.Kind order).
const PEAK := [26, 20, 9, 18, 12, 16]
## Hours before a service the arrivals start, and when the last one is in (after the start).
const ARRIVE_FROM := 0.75
const ARRIVE_TO := 0.08
## A service's length, and how long the people linger outside after it.
const SERVICE := 1.0
const LINGER := 0.5
## Never more than this many a chunk (a few blocks of crowd cap).
const MAX_CHUNK := 30
## The Sunday-best rigs (crowd_config.json: suits, blazers, dresses, button shirts, skirts,
## cardigans; no gym tanks, hi-vis or shorts).
const BEST := ["crowd_c", "crowd_f", "crowd_g", "crowd_h", "crowd_j", "crowd_m", "crowd_n", "crowd_r",
	"crowd_t", "crowd_u", "crowd_v", "crowd_w", "crowd_y", "crowd_aa", "crowd_ab", "crowd_ad"]


## The day this place keeps (0 Sunday .. 6 Saturday).
static func holy_day(kind: int) -> int:
	return 6 if kind == Worship.Kind.SYNAGOGUE else 0


## The start hours of its services that day (the name board's).
static func services(kind: int, sd: int) -> Array[float]:
	var hours := [9.0, 10.0, 10.5, 11.0, 8.5]
	var h: float = hours[sd % hours.size()]
	match kind:
		Worship.Kind.MISSION:
			return [h, 12.0]
		Worship.Kind.SYNAGOGUE:
			return [h]
		Worship.Kind.STOREFRONT:
			return [h]
	return [h]


## 0..1: how busy the outside is at `hour` on `day` (arrivals before each service, the crowd
## coming out after it).
static func busy(kind: int, sd: int, day: int, hour: float) -> float:
	if day != holy_day(kind):
		return 0.0
	var b := 0.0
	for s: float in services(kind, sd):
		# Arriving: up from ARRIVE_FROM before, full ten minutes before, gone once it starts.
		if hour > s - ARRIVE_FROM and hour < s + ARRIVE_TO:
			b = maxf(b, smoothstep(s - ARRIVE_FROM, s - 0.17, hour) * (1.0 - smoothstep(s - 0.02, s + ARRIVE_TO, hour)))
		# Coming out and talking on the steps.
		var e := s + SERVICE
		if hour > e - 0.05 and hour < e + LINGER:
			b = maxf(b, smoothstep(e - 0.05, e + 0.05, hour) * (1.0 - smoothstep(e + LINGER * 0.4, e + LINGER, hour)))
	return clampf(b, 0.0, 1.0)


## How many people stand about the site, and the share of them still arriving (the rest gather).
static func count(kind: int, sd: int, day: int, hour: float) -> int:
	return int(round(float(PEAK[kind]) * busy(kind, sd, day, hour)))


static func arriving(kind: int, sd: int, hour: float) -> bool:
	for s: float in services(kind, sd):
		if hour > s - ARRIVE_FROM and hour < s + ARRIVE_TO:
			return true
	return false


static func day_now(node: Node) -> int:
	if force_day >= 0:
		return force_day
	if OS.get_environment("WORSHIP_DAY") != "":
		return int(OS.get_environment("WORSHIP_DAY"))
	return FarmersMarket.weekday(node)


static func hour_now(node: Node) -> float:
	if force_hour >= 0.0:
		return force_hour
	if OS.get_environment("WORSHIP_HOUR") != "":
		return float(OS.get_environment("WORSHIP_HOUR"))
	var dn := FarmersMarket._day_night(node)
	return float(dn.get("hour")) if dn != null else 12.0


## The walking points of the site in its frame (x along the street, +z out to it, y 0 the
## pavement): "street" the pavement in front (two ends), "gate" outside and inside the gap,
## "path" up to the door, "court" the forecourt's spots, "door" the door's step.
static func spots(p: Dictionary, ctx: Dictionary) -> Dictionary:
	var L: float = p.L
	var px: float = ctx.get("path_x", 0.0)
	var court: Array[Vector2] = []
	var door := Vector2(px, -float(p.get("fz", 6.0)) + 1.6)
	var front: float = -float(p.get("fz", 6.0))
	# The forecourt: the paved strip before the facade (the mission's) or the lawn's edge by the path.
	var x0 := px - 7.0
	var x1 := px + 7.0
	if int(p.kind) == Worship.Kind.MISSION:
		x0 = float(p.xc) - float(p.W) * 0.5 + 0.8
		x1 = float(p.xc) + float(p.W) * 0.5 + float(p.arcade) - 0.6
		door = Vector2(px, front + 0.9 + 0.8)
	for i in 14:
		var t := (float(i) + 0.5) / 14.0
		var x := lerpf(x0, x1, t)
		var z := front + 1.9 + 1.6 * fmod(float(i) * 0.618, 1.0)
		court.append(Vector2(x, z))
	return {"street": [Vector2(-L * 0.5 - 14.0, 2.0), Vector2(L * 0.5 + 14.0, 2.0)],
		"gate_out": Vector2(px, 1.6), "gate_in": Vector2(px, -1.6), "path": Vector2(px, (front + 2.0) * 0.5),
		"court": court, "door": door}


## The people of a site being built (WorshipBuild.build(), FULL chunks): `count()` of them for the
## day and hour the chunk is built at, a share still on their way in.
static func people(ctx: Dictionary) -> void:
	if not enabled:
		return
	var ch: CityChunk = ctx.ch
	var p: Dictionary = ctx.p
	var s: Dictionary = ctx.s
	var kind := int(p.kind)
	var sd := int(p.seed)
	var hour := hour_now(ch)
	var n := mini(count(kind, sd, day_now(ch), hour), MAX_CHUNK)
	if n <= 0:
		return
	var xf: Transform3D = ctx.xf
	var sp := spots(p, ctx)
	var to_chunk := func(q: Vector2) -> Vector2:
		var w := xf * Vector3(q.x, 0.0, q.y)
		return Vector2(w.x, w.z)
	var pts := {}
	for k: String in sp:
		var v: Variant = sp[k]
		if v is Vector2:
			pts[k] = to_chunk.call(v)
		else:
			var arr: Array[Vector2] = []
			for q: Vector2 in v:
				arr.append(to_chunk.call(q))
			pts[k] = arr
	var arriving_now := arriving(kind, sd, hour)
	var rect: Rect2 = ch.plan.block(ch.ix, ch.iz).rect
	var made := 0
	for i in n:
		if not ch._take_crowd_room():
			break
		var seed_i := hash([ch.plan.seed, sd, "ws_person", i])
		var ped: Node3D = load("res://scripts/npc/worshipper.gd").new()
		ped.name = "Worshipper_%d" % i
		# Arriving: two in three on their way (spread along the route), the rest already on the
		# forecourt; after a service: everybody out on the forecourt and drifting off.
		var roll := Worship.h01([sd, i, "ws_role"])
		var role := 0 if (arriving_now and roll < 0.62) else 1
		var start := Worship.h01([sd, i, "ws_at"])
		ped.set("kind", kind)
		ped.set("site_seed", sd)
		ped.call("setup_worship", rect, seed_i, pts, role, start, not arriving_now)
		var at: Vector2 = ped.call("start_point")
		ped.position = Vector3(at.x, ch.ground_y(at.x, at.y) + 0.12, at.y)
		ch.add_child(ped)
		made += 1
	ch.set_meta("worship_people", made)
