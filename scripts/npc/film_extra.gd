class_name FilmExtra
extends MarketShopper
## An extra at a film shoot (FilmShootBuild.spawn_extra()): an ordinary pedestrian waiting about in
## holding - the strip of road between the basecamp and the set - wandering a little, standing,
## talking, on the phone or with a coffee from catering. MarketShopper's aisle walk with
## FilmShoot.holding() as the aisle (the street frame is the same), out of the market's group.


func _roll_life(seed_value: int) -> void:
	super(seed_value)
	var r := _life.randf()
	if r < 0.4:
		_carry = CrowdLife.Carry.CUP
	elif r < 0.65:
		_carry = CrowdLife.Carry.TEXT
	elif r < 0.75:
		_carry = CrowdLife.Carry.CALL
	else:
		_carry = CrowdLife.Carry.NONE
