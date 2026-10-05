class_name BeachFigure
extends CampFigure
## One of the people lying, sitting or standing about on the sand (BeachLife), drawn the camps' way
## (CampFigure): each (person, pose, suit) is posed once on a real BeachGoer, its welded middle
## body skinned on the CPU into a plain mesh, and a chunk's figures are merged into one mesh
## (CampFigureMesh) - a crowded stretch of beach is a draw per crowd rig it uses, and one more for
## their shadows. This body is the figure's collision and what turns it back into a person: shot,
## knocked, or near gunfire (CampFigure.wake_near(), from Pedestrian.alarm(); BeachActivity wakes
## more of a beach than that) it hides its instance and a live BeachGoer in the same pose, suit and
## spot takes the round and gets up and runs.
##
## Also the bakes for the people in motion that never become a rig until something hits them:
## surfers and swimmers (still figures moved by BeachActivity) and riders on the bike path, whose
## pedalling is a flipbook of RIDE_FRAMES bakes - the legs solved onto the pedals by two-bone IK at
## each crank angle, the crank and the bike baked in with them (ride_meshes()).

## The extra pose (BeachGoer.BEACH_POSES) and the swimsuit (BeachGoer.SUITS).
var beach_pose: String = ""
var suit: int = 0

## Bakes by "seed|pose|beach_pose|suit" and ride flipbooks by "seed|suit" (null / [] where there is
## no mesh data), and the shadow body of each baked mesh.
static var _beach_baked: Dictionary = {}
static var _rides: Dictionary = {}
static var _bake_host: Node3D


func _ready() -> void:
	var fit := BeachGoer.beach_capsule(beach_pose, pose, 0.0)
	if fit.is_empty():
		var cap := CapsuleShape3D.new()
		cap.radius = 0.3
		cap.height = 1.7
		fit = {"shape": cap, "position": Vector3(0.0, 0.85, 0.0), "rotation": Vector3.ZERO}
	var cs := CollisionShape3D.new()
	cs.shape = fit.shape
	cs.position = fit.position
	cs.rotation = fit.rotation
	add_child(cs)


## The live BeachGoer in this figure's place (see CampFigure.wake()).
func wake() -> RoughSleeper:
	if _awake or collision_layer == 0 or chunk == null or not is_instance_valid(chunk):
		return null
	_awake = true
	collision_layer = 0
	if figure_mesh and is_instance_valid(figure_mesh):
		figure_mesh.hide_figure(figure_index)
	if chunk.has_method("_take_crowd_room"):
		chunk._take_crowd_room()
	var ped := BeachGoer.new()
	ped.setup_sleeper(ring, sidewalk, seed_value, pose, home, yaw)
	ped.beach_pose = beach_pose
	ped.suit = suit
	ped.lift = lift
	ped.position = Vector3(home.x, BeachLife.ground_at(chunk, home.x, home.y, position.y) + lift, home.y)
	chunk.add_child(ped)
	queue_free()
	return ped


## The host every bake poses its person under (far below the city, out of every view).
static func _bake_parent() -> Node3D:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	if _bake_host == null or not is_instance_valid(_bake_host):
		_bake_host = Node3D.new()
		_bake_host.name = "BeachFigureBake"
		_bake_host.position = Vector3(0.0, -5000.0, 0.0)
	if not _bake_host.is_inside_tree():
		# Under an autoload, for the reason CampFigure.mesh_for() gives.
		var parent: Node = tree.root.get_node_or_null("WorldState")
		if parent == null or not parent.is_inside_tree():
			parent = tree.root
		if _bake_host.get_parent() != null:
			_bake_host.get_parent().remove_child(_bake_host)
		parent.add_child(_bake_host)
		if not _bake_host.is_inside_tree():
			return null
	return _bake_host


## A posed person ready to bake (in the host, bones and attachments brought up to the pose), or
## null. Free it with _drop().
static func _pose_person(seed: int, pose_kind: int, pose_key: String, suit_index: int) -> BeachGoer:
	var host := _bake_parent()
	if host == null:
		return null
	var ped := BeachGoer.new()
	ped.setup_sleeper(Rect2(0.0, 0.0, 10.0, 10.0), 2.0, seed, pose_kind, Vector2.ZERO, 0.0)
	ped.beach_pose = pose_key
	ped.suit = suit_index
	host.add_child(ped)
	# Baked at the rig's own size: the build variation would only stretch the flipbook's bike.
	if ped._visual:
		ped._visual.scale = Vector3.ONE
		ped._visual.position = Vector3.ZERO
	_refresh(ped)
	return ped


static func _refresh(ped: Node) -> void:
	for sk in ped.find_children("*", "Skeleton3D", true, false):
		(sk as Skeleton3D).force_update_all_bone_transforms()
	for ba in ped.find_children("*", "BoneAttachment3D", true, false):
		(ba as BoneAttachment3D).on_skeleton_update()


static func _drop(ped: Node) -> void:
	if ped and is_instance_valid(ped):
		ped.get_parent().remove_child(ped)
		ped.free()


## The figure mesh for person `seed` (crowd rig `model`) in `pose_kind` / `pose_key` wearing suit
## `suit_index` (feet at the origin, facing -Z); null without mesh data. The pose is baked once per
## person and pose, and each suit is that bake with the suit's look on its body surface (the
## geometry does not change with the colour).
static func beach_mesh(seed: int, pose_kind: int, pose_key: String, suit_index: int, model: int) -> Mesh:
	var key := "%d|%d|%s|%d" % [seed, pose_kind, pose_key, suit_index]
	if _beach_baked.has(key):
		return _beach_baked[key]
	var base_key := "%d|%d|%s" % [seed, pose_kind, pose_key]
	if not _beach_baked.has(base_key):
		_beach_baked[base_key] = null
		var ped := _pose_person(seed, pose_kind, pose_key, 0)
		if ped == null:
			_beach_baked.erase(base_key)
			return null
		var near := CampFigure._bake(ped, Pedestrian.mid_triangles)
		if near:
			var far := CampFigure._bake(ped, Pedestrian.far_triangles)
			if far:
				CampFigure._shadows[near] = far
		_drop(ped)
		_beach_baked[base_key] = near
	var base: Mesh = _beach_baked[base_key]
	var out: Mesh = base if base == null else _in_suit(base, suit_index, model)
	if out:
		var far_base: Mesh = CampFigure._shadows.get(base)
		var far: Mesh = _in_suit(far_base, suit_index, model) if far_base else null
		if far:
			CampFigure._shadows[out] = far
	_beach_baked[key] = out
	return out


## `mesh` with every swim-look surface put in suit `suit_index` (a new mesh sharing nothing but the
## numbers; the bike, the board and anything else keep their materials).
static func _in_suit(mesh: Mesh, suit_index: int, model: int) -> Mesh:
	var look := (model * 7 + 3) % Pedestrian.CHARACTER_LOOKS
	var out := ArrayMesh.new()
	for s in mesh.get_surface_count():
		var mat := mesh.surface_get_material(s)
		var sm := mat as ShaderMaterial
		if sm and sm.get_shader_parameter("albedo_tex") is Texture2D and sm.get_shader_parameter("region_mask") != null:
			var swim := BeachGoer.swim_material(sm.get_shader_parameter("albedo_tex"), suit_index, look)
			if swim:
				mat = swim
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, mesh.surface_get_arrays(s))
		out.surface_set_material(out.get_surface_count() - 1, mat)
	return out


## The pedalling flipbook of person `seed` (crowd rig `model`) in suit `suit_index` on a beach
## cruiser in `paint`: BeachGoer.RIDE_FRAMES meshes, frame k with the crank at k / RIDE_FRAMES of a
## turn, the rider's legs on its pedals. [] without mesh data.
static func ride_meshes(seed: int, suit_index: int, paint: int, model: int) -> Array:
	var key := "%d|%d|%d" % [seed, suit_index, paint]
	if _rides.has(key):
		return _rides[key]
	var base_key := "%d|%d" % [seed, paint]
	if not _rides.has(base_key):
		_rides[base_key] = []
		var ped := _pose_person(seed, RoughSleeper.Pose.CHAIR, "", 0)
		if ped == null:
			_rides.erase(base_key)
			return []
		var frames: Array = []
		for k in BeachGoer.RIDE_FRAMES:
			var fit := ped.ride_pose(TAU * float(k) / float(BeachGoer.RIDE_FRAMES))
			if fit.is_empty():
				break
			_refresh(ped)
			var body := CampFigure._bake(ped, Pedestrian.mid_triangles)
			if body == null:
				break
			var bike := BeachLife.bike_mesh(fit, paint)
			for s in bike.get_surface_count():
				body.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, bike.surface_get_arrays(s))
				body.surface_set_material(body.get_surface_count() - 1, bike.surface_get_material(s))
			frames.append(body)
		_drop(ped)
		_rides[base_key] = frames
	var out: Array = []
	for m: Mesh in _rides[base_key]:
		out.append(_in_suit(m, suit_index, model))
	_rides[key] = out
	return out


## A bike alone, for the one a rider leaves behind (thrown as debris): the flipbook's frame 0
## geometry of rider `seed` without the rider, or a stock-size cruiser.
static func lone_bike(paint: int) -> Mesh:
	var fit := {"bb": Vector3(0.0, 0.28, -0.3), "saddle": Vector3(0.0, 0.92, 0.0),
		"grip_l": Vector3(0.29, 1.06, -0.5), "grip_r": Vector3(-0.29, 1.06, -0.5),
		"pedal_l": Vector3(0.115, 0.11, -0.3), "pedal_r": Vector3(-0.115, 0.45, -0.3)}
	return BeachLife.bike_mesh(fit, paint)


## A skateboarder gliding (the "skate" pose, side-on) with the board under the feet, baked in.
static func skate_mesh(seed: int, suit_index: int, model: int) -> Mesh:
	var key := "skate|%d|%d" % [seed, suit_index]
	if _beach_baked.has(key):
		return _beach_baked[key]
	var base := beach_mesh(seed, RoughSleeper.Pose.STAND, "skate", suit_index, model)
	if base == null:
		return null
	var out := ArrayMesh.new()
	for s in base.get_surface_count():
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, base.surface_get_arrays(s))
		out.surface_set_material(out.get_surface_count() - 1, base.surface_get_material(s))
	var board := BeachLife.skateboard_mesh()
	# The figure stands on the board: lift it by the deck's height.
	var arrays := board.surface_get_arrays(0)
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	out.surface_set_material(out.get_surface_count() - 1, board.surface_get_material(0))
	_beach_baked[key] = out
	return out


## What the loading screen bakes: every beach rig in every pose a beach uses ([model, pose, key]),
## and every rider's flipbook ([model, "ride", paint]).
static func kinds() -> Array:
	var out: Array = []
	if not BeachLife.enabled:
		return out
	var poses: Array = []
	for r: Array in BeachLife.POSE_ODDS:
		poses.append([int(r[1]), String(r[2])])
	poses.append_array([[RoughSleeper.Pose.SIT, "surf_sit"], [RoughSleeper.Pose.LIE, "paddle"],
		[RoughSleeper.Pose.STAND, "surf_ride"], [RoughSleeper.Pose.STAND, "skate"]])
	for m: int in BeachGoer.BEACH_MODELS:
		for p: Array in poses:
			out.append([m, p[0], p[1]])
	for m: int in BeachGoer.RIDER_MODELS:
		for k in BeachGoer.RIDER_PAINTS:
			out.append([m, "ride", BeachGoer.rider_paint(m, k)])
	return out


static func warm_kind(k: Array) -> void:
	var model: int = k[0]
	var seed := BeachGoer.seed_for(model, 0)
	if k[1] is String:
		ride_meshes(seed, 0, int(k[2]), model)
	else:
		beach_mesh(seed, int(k[1]), String(k[2]), 0, model)
