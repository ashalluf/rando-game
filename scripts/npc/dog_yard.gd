class_name DogYard
extends RefCounted
## Which yards have a dog (YardDog), from YardFill's lot plans: a hash share of the house lots in
## the suburbs and the beach town. A front garden behind a low wall or a picket fence, deep and wide
## enough, gets a dog the street can see (FRONT_ODDS); failing that a back yard without a pool gets
## one behind the lot-line fences (BACK_ODDS). FULL chunks only, at most MAX_PER_CHUNK. Every roll
## is a hash of the plan seed and the lot (never a chunk or block rng), so nothing else moves.

const FRONT_ODDS := 0.16
const BACK_ODDS := 0.07
const MAX_PER_CHUNK := 3
## The smallest patch a dog is given (metres along the fence, in from it).
const MIN_PATCH := Vector2(3.0, 1.8)
## Kept clear of the fence, the house and the drive (metres).
const INSET := 0.45

## Off: no yard dogs (DOG_YARDS=0 in the environment, the A/B).
static var enabled: bool = OS.get_environment("DOG_YARDS") != "0"


static func _h01(parts: Array) -> float:
	return float(absi(hash(parts)) % 100000) / 100000.0


## The patch a lot plan offers a dog: {"patch": Rect2 in the frame, "front": bool} or {}. Pure.
static func patch_for(plan: CityPlan, lp: Dictionary, edged: bool) -> Dictionary:
	var lot: Dictionary = lp.lot
	var key: int = lot.seed
	var f: Dictionary = lp.frame
	var U: float = f.U
	var V: float = f.V
	var fd: float = lp.front
	var bv1: float = lp.back
	if edged and _h01([plan.seed, key, "yard_dog"]) < FRONT_ODDS:
		# The front garden less the drive: the wider side of it.
		var u0 := INSET
		var u1 := U - INSET
		var drive: Rect2 = lp.drive
		if drive.size.x > 0.0:
			var dq := YardFill._to_frame(f, drive)
			var left := Vector2(INSET, dq.position.x - INSET)
			var right := Vector2(dq.end.x + INSET, U - INSET)
			if left.y - left.x >= right.y - right.x:
				u0 = left.x
				u1 = left.y
			else:
				u0 = right.x
				u1 = right.y
		var r := Rect2(u0, INSET, u1 - u0, fd - 2.0 * INSET - 0.4)
		if r.size.x >= MIN_PATCH.x and r.size.y >= MIN_PATCH.y:
			return {"patch": r, "front": true}
	if _h01([plan.seed, key, "yard_dog_back"]) < BACK_ODDS:
		for pc: Array in lp.pieces:
			if pc[3] == "pool":
				return {}
		var r := Rect2(INSET, bv1 + INSET, U - 2.0 * INSET, V - bv1 - 2.0 * INSET)
		if r.size.x >= MIN_PATCH.x and r.size.y >= MIN_PATCH.y:
			return {"patch": r, "front": false}
	return {}


## From YardFill._dress_beach_lot: maybe a dog in this lot's yard.
static func consider(ch: CityChunk, lp: Dictionary, edged: bool) -> void:
	if not enabled or not Dog.enabled or ch.level != CityChunk.Level.FULL or ch.capturing:
		return
	var n: int = ch.get_meta("yard_dogs", 0)
	if n >= MAX_PER_CHUNK:
		return
	var pf := patch_for(ch.plan, lp, edged)
	if pf.is_empty():
		return
	var f: Dictionary = lp.frame
	var dog := YardDog.new()
	dog.chunk = ch
	dog.frame_o = f.o
	dog.frame_u = f.u
	dog.frame_v = f.v
	dog.patch = pf.patch
	dog.fence_front = pf.front
	dog.roll(hash([ch.plan.seed, (lp.lot as Dictionary).seed, "yard_dog_breed"]))
	ch.add_child(dog)
	ch.set_meta("yard_dogs", n + 1)
