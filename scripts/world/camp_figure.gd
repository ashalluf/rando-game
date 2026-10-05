class_name CampFigure
extends StaticBody3D
## One of the people at a sidewalk encampment who is sitting, lying or slumped against the wall,
## drawn as a STATIC figure in the chunk's MultiMesh batch rather than as a live rig (owner,
## 2026-09-27: "downtown needs way more homeless people - multiply by 20"). A RoughSleeper in
## those poses never moves while nothing happens round them, yet each one was a skeleton, an
## AnimationPlayer, a script ticking every physics step and a spent place in the crowd cap: two
## hundred of them round skid row cost what two hundred walkers do. So each (model, pose) is
## posed ONCE on a real RoughSleeper, its welded middle body (Pedestrian.far_mesh(), the one a
## walker wears past 50 m) is skinned on the CPU into a plain mesh in the worn look, and a
## chunk's figures are merged into one mesh (CampFigureMesh): a skid-row block's eighteen people
## are a draw call per model it uses, their shadows one more from the far bodies.
##
## This body is only the figure's collision (the npc layer, like a walker's: bullets, blasts and
## car bumpers find it) and what turns it back into a person: shot, knocked, or near enough to
## gunfire (Pedestrian.alarm() -> wake_near()), the instance is hidden and a live RoughSleeper
## in the same pose, seed and spot takes its place - and takes the round, the blast or the fright
## - so a figure bleeds, ragdolls, gets up and flees exactly like a live one.
##
## Baking needs mesh data, which the headless dummy renderer does not keep (like the limb cut and
## the welded bodies): there bake() returns null, the chunk draws nothing, and the bodies and the
## waking still work, which is what the smoke test checks.

## Most figures one alarm wakes (the nearest first), and the farthest it reaches (m): each wakes
## into a full rig, so a burst of fire must not rebuild a whole block's people in one frame.
static var wake_on_alarm: int = 4
static var wake_reach: float = 26.0

## The chunk it belongs to, where it is drawn (its chunk's merged figures, and its index there),
## and the person it stands for.
var chunk: Node
var figure_mesh: CampFigureMesh
var figure_index: int = -1
var pose: int = RoughSleeper.Pose.SIT
var seed_value: int = 0
var home := Vector2.ZERO
var yaw: float = 0.0
var lift: float = 0.0
var ring := Rect2()
var sidewalk: float = 3.0
var _awake: bool = false

## Baked meshes by "seed|pose" (null where there is no mesh data), and the seed found for each
## "model|pose|variant".
static var _baked: Dictionary = {}
static var _seeds: Dictionary = {}
## Each baked figure's far body, the one its shadow is drawn from.
static var _shadows: Dictionary = {}
static var _host: Node3D
static var _acc_chance: float = -1.0


func _init() -> void:
	collision_layer = 8
	collision_mask = 0
	add_to_group("camp_figure")


func _ready() -> void:
	var fit := RoughSleeper.pose_capsule(pose, 0.0)
	if fit.is_empty():
		return
	var cs := CollisionShape3D.new()
	cs.shape = fit.shape
	cs.position = fit.position
	cs.rotation = fit.rotation
	add_child(cs)


## A round (WeaponFX.bullet_wound()): the person wakes and takes it.
func shot(at: Vector3, dir: Vector3, impulse: Vector3, strength: float = 1.0) -> void:
	var p := wake()
	if p:
		p.shot(at, dir, impulse, strength)


## A blast or a car (Explosion.blast(), a bumper).
func knock(impulse: Vector3, gibs: int = 0) -> void:
	var p := wake()
	if p:
		p.knock(impulse, gibs)


## Anything else that hits (a ray that asks for take_hit).
func take_hit(_shape_index: int, _damage: float, hit_dir: Vector3 = Vector3.UP) -> void:
	knock(hit_dir.normalized() * 4.0 + Vector3.UP)


## The live person in this figure's place (null if it already woke). Takes crowd room when there
## is some, but wakes whatever the cap says: a figure that is shot has to fall.
func wake() -> RoughSleeper:
	# A retired chunk (CityChunk.retire()) has dropped its collision: nobody wakes there.
	if _awake or collision_layer == 0 or chunk == null or not is_instance_valid(chunk):
		return null
	_awake = true
	collision_layer = 0
	if figure_mesh and is_instance_valid(figure_mesh):
		figure_mesh.hide_figure(figure_index)
	if chunk.has_method("_take_crowd_room"):
		chunk._take_crowd_room()
	var ped := RoughSleeper.new()
	ped.setup_sleeper(ring, sidewalk, seed_value, pose, home, yaw)
	ped.lift = lift
	var y: float = chunk.ground_y(home.x, home.y) if chunk.has_method("ground_y") else position.y
	ped.position = Vector3(home.x, y + lift, home.y)
	chunk.add_child(ped)
	queue_free()
	return ped


## Wakes the nearest `wake_on_alarm` figures within `radius` (and wake_reach) of `at`, before the
## alarm's pass over the crowd, so they hear it like everyone else.
static func wake_near(tree: SceneTree, at: Vector3, radius: float) -> void:
	var r := minf(radius, wake_reach)
	var near: Array = []
	for n in tree.get_nodes_in_group("camp_figure"):
		var f := n as CampFigure
		if f == null or f._awake or f.collision_layer == 0 or not f.is_inside_tree():
			continue
		var d2 := f.global_position.distance_squared_to(at)
		if d2 <= r * r:
			near.append([d2, f])
	near.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for i in mini(wake_on_alarm, near.size()):
		(near[i][1] as CampFigure).wake()


## A seed that dresses a RoughSleeper as model `model` (index into Pedestrian.MODELS), in that
## model's one look, with the pose variant `variant` (RoughSleeper: the seed's parity), searched
## once and remembered: the figure and the person it wakes into are the same person.
static func seed_for(model: int, pose_kind: int, variant: int) -> int:
	var key := "%d|%d|%d" % [model, pose_kind, variant]
	if _seeds.has(key):
		return _seeds[key]
	var models := 0
	for path: String in Pedestrian.MODELS:
		if ResourceLoader.exists(path):
			models += 1
	var found := variant
	if models > 0:
		# One look per model (the character shader's clothing hue): every pose of a model then
		# shares one material, so a chunk's merged figures are a draw per model, not per figure.
		var look := (model * 7 + 3) % Pedestrian.CHARACTER_LOOKS
		var fallback := -1
		for k in 60000:
			var s := 7919 * (k + 1) + pose_kind * 131
			if absi(s) % 2 != variant:
				s += 1
			var style := RandomNumberGenerator.new()
			style.seed = hash([s, "style"])
			if style.randi() % models != model % models:
				continue
			if fallback < 0:
				fallback = s
			if style.randi() % Pedestrian.CHARACTER_LOOKS != look:
				continue
			# And bare-headed with no pack: an accessory is a material of its own. Pedestrian's
			# _add_model() draws five more (height, widths, lean, gait) before _add_accessory()
			# rolls; if that order ever changes this only costs a draw call, never a wrong person.
			for r in 5:
				style.randf()
			if style.randf() < _accessory_chance():
				continue
			found = s
			fallback = -1
			break
		if fallback >= 0:
			found = fallback
	_seeds[key] = found
	return found


## RoughSleeper's accessory_chance (an export, so read off an instance once).
static func _accessory_chance() -> float:
	if _acc_chance < 0.0:
		var p := RoughSleeper.new()
		_acc_chance = p.accessory_chance
		p.free()
	return _acc_chance


## The figure mesh for a person of `seed` in `pose_kind` (in their local space: feet at the
## origin, facing -Z), baked on first use (the loading screen bakes them all, warm()); null
## without mesh data.
static func mesh_for(seed: int, pose_kind: int) -> Mesh:
	var key := "%d|%d" % [seed, pose_kind]
	if _baked.has(key):
		return _baked[key]
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	if _host == null or not is_instance_valid(_host):
		_host = Node3D.new()
		_host.name = "CampFigureBake"
		# Far under the city, out of every view and query, for the frame a bake takes.
		_host.position = Vector3(0.0, -5000.0, 0.0)
	if not _host.is_inside_tree():
		# Under the WorldState autoload, not the root: while the city's own _ready() runs (a
		# --spawn builds its first ring there, and every tool adds the city from _initialize())
		# the root is busy setting up its children and add_child() fails, and a host left out of
		# the tree failed every later bake too - no posed figure for the whole session. The
		# autoloads are done with their children by then, and outlive a scene reload.
		var parent: Node = tree.root.get_node_or_null("WorldState")
		if parent == null or not parent.is_inside_tree():
			parent = tree.root
		if _host.get_parent() != null:
			_host.get_parent().remove_child(_host)
		parent.add_child(_host)
		if not _host.is_inside_tree():
			# Still refused: no figure this time, and nothing cached, so the next ask (the loading
			# screen's warm()) bakes it.
			return null
	_baked[key] = null
	var ped := RoughSleeper.new()
	ped.setup_sleeper(Rect2(0.0, 0.0, 10.0, 10.0), 2.0, seed, pose_kind, Vector2.ZERO, 0.0)
	_host.add_child(ped)
	# The pose was written this frame: bring the bones' globals and anything hung off a bone (a
	# cap, a pack) up to it now, not at the end of the frame.
	for sk in ped.find_children("*", "Skeleton3D", true, false):
		(sk as Skeleton3D).force_update_all_bone_transforms()
	for ba in ped.find_children("*", "BoneAttachment3D", true, false):
		(ba as BoneAttachment3D).on_skeleton_update()
	var near := _bake(ped, Pedestrian.mid_triangles)
	if near:
		var far := _bake(ped, Pedestrian.far_triangles)
		if far:
			_shadows[near] = far
	_host.remove_child(ped)
	ped.free()
	_baked[key] = near
	return near


## The posed person as one plain mesh: every skinned surface as its welded body with at most
## `triangles` triangles, taken through its bones' current poses and bind poses exactly as the
## GPU skins it (Ragdoll._cut_limbs() does the same at rest), and any rigid accessory (a cap, a
## pack) as it hangs; each keeps the person's own material.
static func _bake(ped: RoughSleeper, triangles: int) -> ArrayMesh:
	var inv := ped.global_transform.affine_inverse()
	var out := ArrayMesh.new()
	var skinned := false
	for node in ped.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		# A crowd rig's hair cards stay out of the figure: its body has the scalp painted in the
		# hair colour, and the cards would need a cut-out surface of their own in every chunk.
		if mi.mesh == null or not mi.visible or Pedestrian.is_hair(mi):
			continue
		var skel := mi.get_node_or_null(mi.skeleton) as Skeleton3D if mi.skin else null
		if mi.skin and skel:
			var body := Pedestrian.far_mesh(mi.mesh, triangles)
			var arrays := body.surface_get_arrays(0) if body and body.get_surface_count() > 0 else []
			if arrays.is_empty() or arrays[Mesh.ARRAY_BONES] == null or arrays[Mesh.ARRAY_WEIGHTS] == null:
				return null
			var to_local := inv * skel.global_transform
			var bind_xf: Array[Transform3D] = []
			for i in mi.skin.get_bind_count():
				var bone := mi.skin.get_bind_bone(i)
				if bone < 0:
					bone = skel.find_bone(mi.skin.get_bind_name(i))
				var g := skel.get_bone_global_pose(bone) if bone >= 0 else Transform3D.IDENTITY
				bind_xf.append(to_local * g * mi.skin.get_bind_pose(i))
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] if arrays[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
			var tangents: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT] if arrays[Mesh.ARRAY_TANGENT] != null else PackedFloat32Array()
			var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			var per := bones.size() / maxi(verts.size(), 1)
			var has_n := normals.size() == verts.size()
			var has_t := tangents.size() == verts.size() * 4
			for v in verts.size():
				var p := Vector3.ZERO
				var n := Vector3.ZERO
				var t := Vector3.ZERO
				var total := 0.0
				for k in per:
					var w := weights[v * per + k]
					var b := bones[v * per + k]
					if w <= 0.0 or b < 0 or b >= bind_xf.size():
						continue
					var xf := bind_xf[b]
					p += (xf * verts[v]) * w
					if has_n:
						n += (xf.basis * normals[v]) * w
					if has_t:
						t += (xf.basis * Vector3(tangents[v * 4], tangents[v * 4 + 1], tangents[v * 4 + 2])) * w
					total += w
				if total > 0.0:
					verts[v] = p / total
				if has_n:
					normals[v] = n.normalized()
				if has_t:
					t = t.normalized()
					tangents[v * 4] = t.x
					tangents[v * 4 + 1] = t.y
					tangents[v * 4 + 2] = t.z
			arrays[Mesh.ARRAY_VERTEX] = verts
			if has_n:
				arrays[Mesh.ARRAY_NORMAL] = normals
			if has_t:
				arrays[Mesh.ARRAY_TANGENT] = tangents
			arrays[Mesh.ARRAY_BONES] = null
			arrays[Mesh.ARRAY_WEIGHTS] = null
			out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			var mat := mi.material_override if mi.material_override else body.surface_get_material(0)
			out.surface_set_material(out.get_surface_count() - 1, mat)
			skinned = true
		elif not mi.skin:
			var xf := inv * mi.global_transform
			for s in mi.mesh.get_surface_count():
				var arrays := mi.mesh.surface_get_arrays(s)
				if arrays.is_empty():
					continue
				var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				for v in verts.size():
					verts[v] = xf * verts[v]
				arrays[Mesh.ARRAY_VERTEX] = verts
				if arrays[Mesh.ARRAY_NORMAL] != null:
					var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
					for v in normals.size():
						normals[v] = (xf.basis * normals[v]).normalized()
					arrays[Mesh.ARRAY_NORMAL] = normals
				arrays[Mesh.ARRAY_TANGENT] = null
				out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
				var mat := mi.material_override if mi.material_override else mi.get_active_material(s)
				out.surface_set_material(out.get_surface_count() - 1, mat)
	return out if skinned else null


## The kinds a chunk can draw: every model in every pose (and both ways of sitting).
static func kinds() -> Array:
	var out: Array = []
	for m in mini(Pedestrian.MODELS.size(), Encampment.FIGURE_POOL):
		for pk: int in [RoughSleeper.Pose.SIT, RoughSleeper.Pose.LIE, RoughSleeper.Pose.SLUMP, RoughSleeper.Pose.CHAIR]:
			for v in (2 if pk == RoughSleeper.Pose.SIT else 1):
				out.append([m, pk, v])
	return out


## The shadow body of a baked figure mesh (null if none).
static func shadow_for(mesh: Mesh) -> Mesh:
	return _shadows.get(mesh)


## Bakes every kind now (the loading screen), so no chunk stalls on its first figure.
static func warm() -> void:
	for k: Array in kinds():
		mesh_for(seed_for(k[0], k[1], k[2]), k[1])
