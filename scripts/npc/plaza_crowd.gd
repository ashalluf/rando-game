class_name PlazaCrowd
extends RefCounted
## A plaza's crowd at the hours people are there (rc2-crowd-plaza, refcam `crowd_plaza`).
##
## The landmarks' crowd rects (STARLIGHT PLAZA's 46 people, the arena's corner, the civic park,
## the convention centre's front) were spawned as ordinary pavement walkers: a fixed count at any
## hour, each walking round the RECT'S RING by its corners (Pedestrian._ring_route()), so the
## middle of a 56 x 70 m plaza at lunch was an empty field of paving with everybody filing along
## its edges, 40 m from the camera. Here a big enough rect (`MIN_SIDE`) is OPEN GROUND:
## - `count()`: its people by the hour the chunk is built at (`KEYS`, lunch and the evening the
##   busiest), never denser than one person a `AREA_PER_PERSON` m2. The extra walkers are spawned
##   after the rect's own on the same seeded stream, so the first `base` are the same people.
## - `walker()`: its walkers cross the plaza straight to a point anywhere in it (`point()`), stop
##   more often, and never plan a street crossing (the rect's corners are not a block's).
## Hooks: CityChunk._build_landmarks() (count, `mark()`), CityChunk._spawn_walker() (`walker()`),
## Pedestrian._random_ring_point() / _ring_route() (`open_ground`). Every roll is the walker's own
## stream. PLAZA_CROWD=0 in the environment is the A/B (the crowd exactly as before).

static var enabled: bool = OS.get_environment("PLAZA_CROWD") != "0"

## A crowd rect narrower than this either way is a strip (a forecourt, a station's walk): its
## people keep walking it end to end like a pavement.
const MIN_SIDE := 14.0
## At most one person to this many square metres of open ground (a busy plaza is 8-15).
const AREA_PER_PERSON := 14.0
## How many times the landmark's own count, hour by hour from midnight (25 keys, the last is 24).
## A city plaza: empty at night, filling from the morning, packed at lunch, quieter in the
## afternoon, busy again for the evening (the plaza's theatre and restaurants).
const KEYS := [0.35, 0.3, 0.25, 0.25, 0.25, 0.3, 0.45, 0.7, 1.0, 1.15, 1.35, 1.8,
	2.7, 2.8, 2.2, 1.6, 1.5, 1.7, 2.1, 2.3, 2.1, 1.6, 1.1, 0.7, 0.35]
## A plaza walker stops this often at the end of a walk (a pavement walker's default is lower):
## people stand to look at the screens, wait for someone, read their phone.
const PAUSE_CHANCE := 0.45
## And a crowd-life stop is likelier (Pedestrian.life_chance), so groups form in the open.
const LIFE_CHANCE := 0.55
## How far in from the rect's edge a target may be.
const INSET := 1.4


static func is_open(rect: Rect2) -> bool:
	return enabled and minf(rect.size.x, rect.size.y) >= MIN_SIDE


static func hour_factor(hour: float) -> float:
	var h := fposmod(hour, 24.0)
	var i := floori(h)
	return lerpf(float(KEYS[i]), float(KEYS[i + 1]), h - float(i))


## The people a crowd rect gets at `hour` (`base` is the landmark's own count).
static func count(rect: Rect2, base: int, hour: float) -> int:
	if not is_open(rect) or base <= 0:
		return base
	var want := roundi(float(base) * hour_factor(hour))
	var most := maxi(base, floori(rect.size.x * rect.size.y / AREA_PER_PERSON))
	return clampi(want, 1, most)


## The chunk's open-ground rects (chunk space), for walker() to recognise.
static func mark(chunk: Node, rect: Rect2) -> void:
	if not is_open(rect):
		return
	var rects: Array = chunk.get_meta("plaza_rects", [])
	rects.append(rect)
	chunk.set_meta("plaza_rects", rects)


## A walker just set up on `rect`: open ground if the chunk marked it.
static func walker(chunk: Node, ped: Pedestrian, rect: Rect2) -> void:
	if not enabled or not chunk.has_meta("plaza_rects"):
		return
	if not (rect in (chunk.get_meta("plaza_rects") as Array)):
		return
	ped.open_ground = true
	ped.cross_chance = 0.0
	ped.pause_chance = PAUSE_CHANCE
	ped.life_chance = maxf(ped.life_chance, LIFE_CHANCE)
	# Its first target was a ring point (setup() ran before this): anywhere on the plaza instead.
	ped._target = point(ped)


## A point anywhere on the walker's open ground, on its own walk stream.
static func point(ped: Pedestrian) -> Vector2:
	var r := ped.ring
	var ins := minf(INSET, minf(r.size.x, r.size.y) * 0.25)
	return Vector2(ped._rng.randf_range(r.position.x + ins, r.end.x - ins),
		ped._rng.randf_range(r.position.y + ins, r.end.y - ins))


## The rig and look of an open-ground walker, dealt rather than rolled: a plaza's walkers take the
## rigs in a seeded order, each round of them with fresh looks, so two people in one plaza share
## a rig only once every rig is out, and never a rig AND a look. [path, look], or [] to roll as
## before (not open ground, or the switch off). Pedestrian._add_model() still makes its own rolls,
## so nothing after them moves.
static func deal(ped: Pedestrian, available: Array) -> Array:
	if not enabled or not ped.open_ground or available.is_empty():
		return []
	var chunk := ped.get_parent()
	if chunk == null:
		return []
	var key := "plaza_deal_%d" % hash(ped.ring)
	var n: int = chunk.get_meta(key, 0)
	chunk.set_meta(key, n + 1)
	var m := available.size()
	var order := range(m)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([ped.ring, "deal"])
	for i in range(m - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t: int = order[i]
		order[i] = order[j]
		order[j] = t
	var model: int = order[n % m]
	var round_n := n / m
	# Each round of the rigs a look the rig has not worn here yet: the rounds step the look by a
	# number coprime to the 24 looks, from a start of the rig's own.
	var look := posmod(hash([ped.ring, model, "look"]) + round_n * 7, Pedestrian.CHARACTER_LOOKS)
	return [available[model], look]
