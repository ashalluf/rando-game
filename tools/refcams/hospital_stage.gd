extends RefCounted
## The "hospital_er" reference camera's staging (tools/refcams/cameras_w7.json, `"stage":
## "hospital"`): an ambulance of the city's own Emergency service backing into a bay of the
## medical centre's ambulance court, reversing lamps and beacons on, held where it is for the
## shot (HospitalStage._stage_ambulance, the still_shot HOSPITAL=bay staging). Loaded at run time
## by refcams_shot.gd (after the autoloads), so it may name Emergency and HospitalStage.
##
## The row's `hospital` key (optional): {"t": 0..1 how far along its back-in path, default 0.82}.
## Env HOSPITAL_T overrides it for framing work.

## refcams_shot's _place() reads these (the stagers' contract): no hero in this shot.
static var hero_at := Vector3.INF
static var hero_yaw := 0.0
static var _car: Node = null
static var _em: Node = null
static var _was_enabled := true


static func stage(tree: SceneTree, scene: Node, _cam: Camera3D, _player: Node3D, place: Callable, row: Dictionary = {}) -> void:
	var spec: Dictionary = row.get("hospital", {}) if row.get("hospital", null) is Dictionary else {}
	var t := float(spec.get("t", 0.82))
	if OS.get_environment("HOSPITAL_T") != "":
		t = float(OS.get_environment("HOSPITAL_T"))
	var plan: CityPlan = scene.get("plan")
	var em := scene.get_node_or_null("Emergency") as Emergency
	var med := Hospital.medical_block(plan) if plan != null else Vector2i.MAX
	if em == null or med == Vector2i.MAX:
		push_warning("refcams hospital: no Emergency or no medical centre")
		return
	var lay := Hospital.layout(plan, med.x, med.y)
	_was_enabled = em.enabled
	var before := em.units.size()
	HospitalStage._stage_ambulance(tree, em, plan, lay, t)
	if em.units.size() > before:
		_car = em.units[em.units.size() - 1]
	# Nothing else answers a call while the shot is held.
	_em = em
	em.enabled = false
	for i in 6:
		await tree.process_frame
		place.call()
	if _car is Node3D:
		print("REFCAM hospital_er: ambulance at %s" % [WorldState.to_world((_car as Node3D).global_position)])


static func unstage() -> void:
	if is_instance_valid(_em):
		if is_instance_valid(_car):
			(_em.get("units") as Array).erase(_car)
		_em.set("enabled", _was_enabled)
	if is_instance_valid(_car):
		_car.queue_free()
	_car = null
