class_name YardFigure
extends BeachFigure
## A sunbather on a back-yard lounger (Backyards): a beach figure (BeachFigure, baked once and
## merged per chunk) whose live person stands on the yard, not on the sand - woken by a round, a
## knock or gunfire nearby, it hides its instance and a YardGoer in the same pose, suit and spot
## takes its place, gets up and runs about the yard.


func wake() -> RoughSleeper:
	if _awake or collision_layer == 0 or chunk == null or not is_instance_valid(chunk):
		return null
	_awake = true
	collision_layer = 0
	if figure_mesh and is_instance_valid(figure_mesh):
		figure_mesh.hide_figure(figure_index)
	if chunk.has_method("_take_crowd_room"):
		chunk._take_crowd_room()
	var ped := YardGoer.new()
	ped.setup_sleeper(ring, sidewalk, seed_value, pose, home, yaw)
	ped.beach_pose = beach_pose
	ped.suit = suit
	ped.lift = 0.0
	ped.yard_y = position.y - (chunk as CityChunk)._gy(home.x, home.y)
	ped.position = position
	chunk.add_child(ped)
	queue_free()
	return ped
