class_name FreewayMotorist
extends StreetVendor
## The driver of a car that broke down on the freeway (FreewayIncidents): out of the car, standing
## on the shoulder behind it by the barrier, on the phone, now and then folding their arms or
## looking down the road for the tow. A crowd rig like anyone (shot, knocked, ragdolled), placed
## on the deck rather than walked: the deck is no block's pavement ring. Gunfire makes them crouch
## where they stand (StreetVendor's truck cook), never run off the viaduct.

## The deck's top under them (true world y; their parent is in true world space).
var deck_y: float = 0.0


func setup_motorist(at: Vector2, yaw: float, deck: float, seed_value: int) -> void:
	deck_y = deck
	setup_vendor(Rect2(at - Vector2(3.0, 3.0), Vector2(6.0, 6.0)), seed_value, at, yaw, true, 0.0)


func _roll_life(seed_value: int) -> void:
	super(seed_value)
	_carry = CrowdLife.Carry.CALL


func _ground_y(_x: float, _z: float, _fallback: float) -> float:
	return deck_y


func _do_act(delta: float) -> void:
	super(delta)
	if _stage == Stage.DOING and _life_ok and _one_shot_left <= 0.0 and _life_base == CrowdLife.FOLD:
		# On the phone most of the time (the carried phone needs a free arm).
		_life_base = CrowdLife.IDLE
		_life_clip = _life_base
