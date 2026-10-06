class_name BeachWalker
extends Pedestrian
## Somebody walking on the sand in swimwear (BeachActivity): down to the water with a surfboard
## under the arm and back up to the towels, or strolling along the wet sand at the waterline. A
## Pedestrian in every other way (hears gunfire and runs, is shot, knocked, bleeds), dressed by
## BeachGoer.dress(), on the sand's height (BeachLife.ground_at()), and going straight across the
## open beach rather than round a block's corners.

var suit: int = 0
## Carries a board (BeachLife.BOARDS paint index), or -1.
var board: int = -1
## The world's plan, and the stretch of shore (world z) it keeps to.
var plan_ref: CityPlan
var z_lo: float = 0.0
var z_hi: float = 0.0
var _to_water: bool = true


func _init() -> void:
	accessory_chance = 0.0


func _ready() -> void:
	super._ready()
	if _visual:
		BeachGoer.dress(_visual, _model_path, suit)
		if board >= 0:
			_carry_board()
	# A beach pace: an amble.
	walk_speed = _rng.randf_range(0.9, 1.25)
	cross_chance = 0.0


func _lives() -> bool:
	return false


func _ring_route(_from: Vector2, _to: Vector2) -> PackedVector2Array:
	return PackedVector2Array()


## Board carriers go down to the waterline and back up the beach in turn; strollers keep to the wet
## sand, a few tens of metres at a time.
func _random_ring_point(_sidewalk: float) -> Vector2:
	if plan_ref == null or plan_ref.macro == null:
		return ring.get_center()
	var macro: MacroMap = plan_ref.macro
	var z := clampf((z_lo + z_hi) * 0.5 + _rng.randf_range(-1.0, 1.0) * (z_hi - z_lo) * 0.5, z_lo, z_hi)
	if is_inside_tree() and board < 0:
		z = clampf(position.z + _rng.randf_range(-35.0, 35.0), z_lo, z_hi)
	var cx := macro.coast_x(z)
	var w := macro.beach_width_at(z)
	if board >= 0:
		_to_water = not _to_water
		if _to_water:
			return Vector2(cx + _rng.randf_range(1.0, 3.0), z)
		return Vector2(cx + w * _rng.randf_range(0.25, 0.6), z)
	return Vector2(cx + _rng.randf_range(2.5, 9.0), z)


func _flee_point() -> Vector2:
	var best := ring.get_center()
	if plan_ref == null or plan_ref.macro == null:
		return best
	for i in 6:
		var z := _rng.randf_range(z_lo, z_hi)
		var p := Vector2(plan_ref.macro.coast_x(z) + plan_ref.macro.beach_width_at(z) * _rng.randf_range(0.3, 0.8), z)
		if p.distance_squared_to(_threat) > best.distance_squared_to(_threat):
			best = p
	return best


func _ground_y(x: float, z: float, fallback: float) -> float:
	return BeachLife.ground_at(get_parent(), x, z, fallback)


## The board under the right arm: on its rail along the body, the deck facing out, nose forward.
func _carry_board() -> void:
	var skel := _visual.find_child("Skeleton3D", true, false) as Skeleton3D
	if skel == null:
		return
	var idx := skel.find_bone("Hips")
	if idx < 0:
		return
	var unit := 1.0
	var node: Node3D = skel
	while node != null and node != _visual:
		unit *= node.transform.basis.get_scale().y
		node = node.get_parent() as Node3D
	unit = 1.0 / maxf(unit, 0.0001)
	var att := BoneAttachment3D.new()
	skel.add_child(att)
	att.bone_name = "Hips"
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = BeachLife.prop_mesh("surfboard")
	mm.instance_count = 1
	mm.set_instance_transform(0, Transform3D.IDENTITY)
	var paint: Color = BeachLife.BOARDS[posmod(board, BeachLife.BOARDS.size())]
	mm.set_instance_custom_data(0, Color(paint.r, paint.g, paint.b, 0.0))
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = 120.0
	var pose := skel.get_bone_global_pose(idx)
	# Skeleton space: +Z forward, +X the rig's left; the board's x to the front, its deck facing out
	# to the rig's right, held at the hip under the right arm.
	var b := Basis(Vector3(0.0, 0.0, 1.0), Vector3(-1.0, 0.0, 0.0), Vector3(0.0, -1.0, 0.0)).scaled(Vector3.ONE * unit)
	var want := Transform3D(b, pose.origin + Vector3(-0.27, 0.02, 0.1) * unit)
	mi.transform = pose.affine_inverse() * want
	att.add_child(mi)


func knock(impulse: Vector3, gibs: int = 0) -> void:
	if _down:
		return
	var parent := get_parent()
	var before := parent.get_child_count() if parent else 0
	super.knock(impulse, gibs)
	if parent == null:
		return
	for i in range(before, parent.get_child_count()):
		var doll := parent.get_child(i) as Ragdoll
		if doll and doll._rig:
			BeachGoer.dress(doll._rig, _model_path, suit)
