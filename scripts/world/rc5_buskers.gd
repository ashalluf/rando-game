class_name Rc5Buskers
extends RefCounted
## The buskers' plaza at eye level (wave 8 refcam `buskers_plaza`, docs/HANDOFF.md "The buskers'
## plaza at 15:30"): what Buskers' plazas lacked when stood among them.
##
## - A plaza holds THREE acts (`SLOTS`): the third pitch is on the fountain's cross axis, rolled
##   like the other two (PLAZA odds, its own hash id), so a big square is a busy square. Slots 0
##   and 1 are rolled exactly as before.
## - The acts' people are not turned away by a full crowd cap (`RESERVE`): a performer and the ring
##   that came with him are a dozen people at most, and an act on the ground with nobody playing
##   it (the cap was spent by the time the plaza's steps ran) was the plaza's whole failure.
## - The plaza's open ground has its own passers-by (`plaza_walkers()`): the walkers of a PLAZA
##   block with acts cross it point to point (PlazaCrowd's open ground) instead of filing round
##   its pavement ring, so the middle of the square is not an empty field of paving.
## Staging, for the refcam and stills: BUSK_HOUR=h builds every act for that hour (Buskers'
## force_hour), BUSK_PLAZA=break,mariachi,statue forces a plaza's slots 0, 1, 2 to those kinds
## whatever the rolls and hours.
##
## Every roll is a hash of seed + block + slot. RC5_BUSKERS=0 in the environment is the A/B (two
## slots, the cap as before, no open-ground walkers, the looks as before).

static func _static_init() -> void: LoadPulse.compiled()  # a boot frame: docs/HANDOFF.md "The boot compile"

static var enabled: bool = OS.get_environment("RC5_BUSKERS") != "0"

## Pitches on a plaza (Buskers' two, either side of the fountain on its long axis, and one on the
## cross axis).
const SLOTS := 3
## Extra walkers a PLAZA block with acts puts on its open ground (spawned through the crowd cap,
## after the block's own).
const PLAZA_WALKERS := 14
const KIND_NAMES := ["guitar", "drums", "break", "statue", "mariachi"]

## Staging: the hour every act is built for (-1: the chunk's own), the kinds a plaza's slots are
## forced to (empty: rolled).
static var stage_hour: float = float(OS.get_environment("BUSK_HOUR")) if OS.get_environment("BUSK_HOUR") != "" else -1.0
static var stage_plaza: Array = _kinds(OS.get_environment("BUSK_PLAZA"))


static func _kinds(text: String) -> Array:
	var out: Array = []
	var any := false
	for w in text.split(",", false):
		var k := KIND_NAMES.find(w.strip_edges().to_lower())
		out.append(k)
		any = any or k >= 0
	# "none" (or nothing a kind): not staged.
	return out if any else []


static func plaza_slots() -> int:
	return SLOTS if enabled or not stage_plaza.is_empty() else 2


## The forced kind of a plaza slot (-1: rolled).
static func forced_kind(slot: int) -> int:
	return int(stage_plaza[slot]) if slot < stage_plaza.size() else -1


## Whether a performer's own people take room the cap has left (true) or are refused like walkers.
static func reserve_room() -> bool:
	return enabled


## The direction of a plaza slot's pitch from the fountain: slots 0 / 1 along the long axis (+ / -),
## slot 2 across it, on a side picked by a hash of the block.
static func slot_dir(plan_seed: int, ix: int, iz: int, slot: int, long_x: bool) -> Vector2:
	var axis := Vector2(1.0, 0.0) if long_x else Vector2(0.0, 1.0)
	if slot < 2:
		return axis * (1.0 if slot == 0 else -1.0)
	var cross := Vector2(-axis.y, axis.x)
	var s := 1.0 if (absi(hash([plan_seed, ix, iz, "busk_cross"])) % 2) == 0 else -1.0
	return cross * s


## The open-ground passers-by of a PLAZA block whose acts were laid (Buskers.build_block): walkers
## of the block's own on a stream of their own, crossing the square point to point
## (PlazaCrowd's open ground, so the deal of rigs and looks and CrowdFlow's avoidance come with
## it), as many as the hour brings (PlazaCrowd.hour_factor). Spawned as build steps before the
## finish, through the crowd cap, after everything the block rolls.
static func plaza_walkers(chunk: CityChunk, block: Dictionary) -> void:
	if not enabled or not PlazaCrowd.enabled:
		return
	var inner: Rect2 = (block.rect as Rect2).grow(-5.0)
	var hour := Buskers.hour_now(chunk)
	var count := roundi(float(PLAZA_WALKERS) * PlazaCrowd.hour_factor(hour))
	if count <= 0:
		return
	PlazaCrowd.mark(chunk, inner)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([chunk.plan.seed, chunk.ix, chunk.iz, "busk_plaza_walkers"])
	for step in chunk._crowd_steps(inner, 3.0, count, rng):
		chunk._run_or_defer(step)
