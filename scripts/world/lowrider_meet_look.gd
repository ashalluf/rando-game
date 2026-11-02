class_name LowriderMeetLook
## The lowrider meet at eye level (wave 7 refcam `lowrider_meet`, docs/HANDOFF.md "The lowrider
## meet at eye level"). What the camera found reading fake, fixed here and in two hooks in
## LowriderMeet and Lowrider.Hydraulics:
## - the parked row stood identical, every car laid out with its lamps lit and a driver at the
##   wheel: now a parked car is EMPTY (its owner is out on the kerb: lamps off, no one in the
##   glass) and holds a display STANCE by hash - laid out, locked up on all four, standing on
##   three, or the nose up - the way cars sit at a real show;
## - a three-wheel lifted its wheel 0.2 m and barely read: now `Hydraulics.three_lift` (0.55 m);
## - the crowd stood one or two per car in an even line along the pavement: now most of them
##   gather round the cars that are putting on a show (closer to the kerb, in rings facing the
##   car), and the folding chairs have people in them (sitters, `sitter_spots()`).
## Every pick is a hash of the meet's seed (nothing rolls). RC4_LOWRIDER_MEET=0 is the A/B.

static var enabled: bool = OS.get_environment("RC4_LOWRIDER_MEET") != "0"

enum Stance { LAID, LOCKED, THREE, NOSE }
## Of the PARKED cars: the cumulative shares of LOCKED, THREE and NOSE (the rest lie laid out).
const STANCE_ODDS := [0.22, 0.38, 0.5]
## Of the crowd, how many gather round the show cars (when there are any).
const SHOW_SHARE := 0.6
## Of each pair of folding chairs, the odds each chair has somebody in it.
const SIT_ODDS := 0.75


static func _h01(parts: Array) -> float:
	return float(absi(hash(parts)) % 100003) / 100003.0


## The display stance of row car `spot` (LowriderMeet.layout()'s [p, yaw, type, look, show]) and
## its side for a three: [stance, side].
static func stance_for(spot: Array) -> Array:
	if not enabled or bool(spot[4]):
		return [Stance.LAID, 1.0]
	var r := _h01([int(spot[3]), "lrstance"])
	var st := Stance.LAID
	if r < STANCE_ODDS[0]:
		st = Stance.LOCKED
	elif r < STANCE_ODDS[1]:
		st = Stance.THREE
	elif r < STANCE_ODDS[2]:
		st = Stance.NOSE
	return [st, 1.0 if _h01([int(spot[3]), "lrside"]) < 0.5 else -1.0]


## Dresses a row car after it is parked (LowriderMeet._park): a parked car's owner is out on the
## kerb (nobody in it, lamps off) and it holds its stance; a show car keeps its driver at the
## switches.
static func dress_car(car: Vehicle, spot: Array) -> void:
	if not enabled:
		return
	var h := car.get_node_or_null("Hydraulics")
	# A car held mid-routine for a still (LOWRIDER_POSE) is being worked: its driver stays.
	var posed := h != null and bool(h.get("frozen"))
	if not bool(spot[4]) and not posed:
		car._npc_driver = false
		car._update_occupant(true)
	if h == null or posed:
		return
	var st := stance_for(spot)
	if int(st[0]) != Stance.LAID:
		h.call("set_stance", int(st[0]), float(st[1]))


## Where the crowd stands (replaces LowriderMeet.people_spots()'s even line, same format and
## count): SHOW_SHARE of them in a ring on the pavement round a show car's kerb side, facing it,
## the rest spread along the row by their car. [position (plan space), yaw, seed].
static func people_spots(m: Dictionary, spots: Array, want: int) -> Array:
	var out := []
	var axis := int(m.axis)
	var side := float(m.side)
	var kerb := float(m.centre) + side * float(m.width) * 0.5
	var shows := []
	for j in spots.size():
		if bool(spots[j][4]):
			shows.append(j)
	for i in want:
		var s := hash([int(m.seed), i, "person"])
		var gather := not shows.is_empty() and _h01([s, "gather"]) < SHOW_SHARE
		var j: int = shows[i % shows.size()] if gather else i % spots.size()
		var car_p: Vector2 = spots[j][0]
		var car_along := car_p.y if axis == CityPlan.AXIS_X else car_p.x
		var along: float
		var off: float
		if gather:
			# A ring on the pavement round the car's kerb side: the front rank by the kerb, the
			# back a step behind, spread the length of the car.
			along = car_along + (_h01([s, "a"]) - 0.5) * 6.4
			off = kerb + side * lerpf(0.45, 2.3, _h01([s, "o"]) * _h01([s, "o2"]))
		else:
			along = car_along + (_h01([s, "a"]) - 0.5) * LowriderMeet.PITCH * 0.9
			off = kerb + side * lerpf(0.9, 3.2, _h01([s, "o"]))
		var p := Vector2(off, along) if axis == CityPlan.AXIS_X else Vector2(along, off)
		var to := car_p - p
		var yaw := atan2(-to.x, -to.y) + (_h01([s, "y"]) - 0.5) * (0.5 if gather else 0.9)
		out.append([p, yaw, s])
	return out


## The people in the folding chairs: for each chair (two a LowriderMeet.chair_spots() pair) with
## somebody in it, [seat position (plan space), yaw facing the street, seed].
static func sitter_spots(m: Dictionary, chairs: Array) -> Array:
	var out := []
	if not enabled:
		return out
	for pl: Array in chairs:
		var p: Vector2 = pl[0]
		var yaw := float(pl[1])
		var right := Vector2(cos(yaw), -sin(yaw))
		for k in 2:
			var s := hash([int(pl[2]), k, "sitter"])
			if _h01([s, "sit"]) >= SIT_ODDS:
				continue
			out.append([p + right * (-0.55 + 1.1 * float(k)), yaw, s])
	return out
