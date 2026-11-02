class_name AlleyCook
extends StreetVendor
## A cook on a smoke break by a restaurant's back door in a service alley (Alleys, AlleyKit): stands
## off the wall with a cigarette, idling, now and then folding their arms. A crowd rig like anyone
## (StreetVendor's: shot, knocked, ragdolled, in the crowd cap and the "pedestrian" group); gunfire
## sends them running and they walk back to the door after.


func _roll_life(seed_value: int) -> void:
	super(seed_value)
	_carry = CrowdLife.Carry.SMOKE


func _do_act(delta: float) -> void:
	# The vendor's beat without the customers: idle mostly, arms folded now and then.
	if _stage != Stage.DOING or not _life_ok:
		super(delta)
		return
	_beat -= delta
	if _beat > 0.0:
		return
	_beat = _life.randf_range(4.0, 9.0)
	_life_look = Vector3.INF
	if _one_shot_left <= 0.0:
		_life_base = CrowdLife.IDLE if _life.randf() < 0.7 else CrowdLife.FOLD
		_life_clip = _life_base
