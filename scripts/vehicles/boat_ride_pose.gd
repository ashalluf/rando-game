class_name BoatRidePose
extends SwimPose
## The hero at a boat's helm or astride a jet ski's saddle (Boat): his skeleton posed in code over
## the idle, like the swim strokes (SwimPose, whose aiming it borrows), added after every other
## modifier of his skeleton while he drives and freed when he gets off. The hips are put on the
## seat by Boat (the Avatar lowered by DROP, the hip height); this bends him into the seat: thighs
## forward, shins down to the footwell or the sole, the spine leaning to the grips, the arms out to
## the wheel or the bars, and a lean and a turn of the head with the steering (`steer`, -1..1).
## Skeleton space: the rig faces +Z, Y up, his LEFT is +X.

## How far under the standing hips the Avatar is lowered: the hips then sit at the seat point.
const DROP := [0.95, 0.95]

var kind: int = 0
## -1..1, the steering (Boat.steering over max_steer): positive turns left.
var steer: float = 0.0


static func attach(p: Player, boat: Boat) -> BoatRidePose:
	var sk := p.avatar.find_child("Skeleton3D", true, false) as Skeleton3D
	if sk == null:
		return null
	var r := BoatRidePose.new()
	r.name = "BoatRidePose"
	r.kind = boat.kind
	r.weight = 1.0
	sk.add_child(r)
	return r


func _process_modification_with_delta(_delta: float) -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	var want := ride_targets(kind, steer)
	for b: String in ORDER:
		if want.has(b):
			_aim(sk, b, want[b], 1.0)
	# The head looks where he steers.
	_turn(sk, _bone("Head"), Vector3.UP, steer * 0.35)


## The aim of every bone for a kind of boat and steering (pure: the checks ask it).
static func ride_targets(k: int, st: float) -> Dictionary:
	var out := {}
	var lean := st * (0.22 if k == BoatKit.Kind.JETSKI else 0.06)
	if k == BoatKit.Kind.JETSKI:
		out["Spine02"] = Vector3(lean, 0.9, 0.42)
		out["Spine01"] = Vector3(lean, 0.92, 0.38)
		out["Spine"] = Vector3(lean * 0.6, 0.95, 0.3)
		out["neck"] = Vector3(lean * 0.3, 0.9, 0.42)
	else:
		out["Spine02"] = Vector3(lean, 0.99, -0.04)
		out["Spine01"] = Vector3(lean, 0.99, 0.0)
		out["Spine"] = Vector3(lean, 0.99, 0.05)
		out["neck"] = Vector3(0.0, 0.97, 0.22)
	for s: Array in [[1.0, "Left"], [-1.0, "Right"]]:
		var side: float = s[0]
		var n: String = s[1]
		# The wheel turns under the hands: one hand rises, the other falls.
		var turn := st * side * 0.18
		if k == BoatKit.Kind.JETSKI:
			out[n + "UpLeg"] = Vector3(side * 0.42, -0.28, 0.86)
			out[n + "Leg"] = Vector3(side * 0.1, -0.96, -0.24)
			out[n + "Foot"] = Vector3(side * 0.05, -0.35, 0.94)
			out[n + "Arm"] = Vector3(side * 0.3, -0.42 + turn, 0.86)
			out[n + "ForeArm"] = Vector3(side * 0.02, -0.12 - turn * 0.5, 0.99)
			out[n + "Hand"] = Vector3(side * -0.05, -0.15, 1.0)
		else:
			out[n + "UpLeg"] = Vector3(side * 0.14, -0.1, 0.98)
			out[n + "Leg"] = Vector3(side * 0.04, -0.97, 0.22)
			out[n + "Foot"] = Vector3(side * 0.04, -0.3, 0.95)
			out[n + "Arm"] = Vector3(side * 0.1, -0.5 + turn, 0.86)
			out[n + "ForeArm"] = Vector3(side * -0.12, -0.05 - turn * 0.5, 0.99)
			out[n + "Hand"] = Vector3(side * -0.1, -0.1, 1.0)
	return out
