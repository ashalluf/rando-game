class_name LaneShopper
extends Pedestrian
## Somebody shopping down the marketplace lane (PuebloLaneLook): an ordinary pedestrian on the
## lane's ring - shot, knocked, bled and ragdolled like anyone, in the crowd cap - who is born at a
## stall's front and stops at stalls far more than a passer-by (the chunk's "vendor_queue" spots,
## which the life layer's _plan_queue() hands out), never crosses a street, and mostly carries a
## bag or a coffee. Nobody jogs or walks a dog down a market lane.

static func _static_init() -> void: LoadPulse.compiled()  # a boot frame: docs/HANDOFF.md "The boot compile"


func setup_lane(rect: Rect2, seed_value: int) -> void:
	setup(rect, 2.0, seed_value)
	cross_chance = 0.0
	pause_chance = 0.4
	pause_seconds = Vector2(2.0, 6.0)
	life_chance = 0.8
	life_spawn_chance = 0.9
	add_to_group("lane_shopper")


func _lives() -> bool:
	return true


func _roll_life(seed_value: int) -> void:
	super(seed_value)
	_jogger = false
	_dog_walker = false
	var r := _life.randf()
	if r < 0.45:
		_carry = CrowdLife.Carry.BAG
	elif r < 0.62:
		_carry = CrowdLife.Carry.CUP
	elif r < 0.72:
		_carry = CrowdLife.Carry.CALL
