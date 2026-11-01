class_name CarInteriors
extends Node
## Decides which cars have their real cabin and hinged doors (CarInterior), runs the door splits
## (CarDoorSplit) inside a frame budget and ticks the rigs. One node under the tree root, made by
## the first Vehicle (ensure(), like CarLights). The rest of the city keeps the traced cabin
## (CarCabin): only these get geometry -
##   * the car the player drives (from the moment he gets in),
##   * up to `max_parked` empty parked cars within `near_range` of the player on foot,
##   * any car that has lost a door (its body has a hole now; kept until it is freed).
## The everyday bodies only (CarDoorSplit.DOORS): sedan, taxi, crossover, pickup, van, hatchback,
## SUV, minivan, beater. Hooks in Vehicle: the driver setter (driver_changed: the door on the side
## he came from swings open and shut), take_hit (on_hit: a hard crash or a blast tears a door off)
## and _apply_occupant (cabin_glass_override). `CAR_CABINS=0` in the environment turns it all off.

## Parked cars within this of the player on foot get theirs (m), dropped past it + `hysteresis`.
@export var near_range: float = 7.5
@export var hysteresis: float = 3.0
@export var max_parked: int = 1
## How often the set is chosen (s).
@export var pick_interval: float = 0.2
## Door splits per frame (us).
@export var split_budget_usec: int = 2500
## A crash this hard (m/s over Vehicle.crash_min_dv) or a blast this strong at the car tears off
## the door on the side it came from.
@export var detach_crash: float = 7.0
@export var detach_blast: float = 0.35

static var enabled: bool = OS.get_environment("CAR_CABINS") != "0"
static var _inst: CarInteriors = null

## Active rigs by car instance id.
var rigs: Dictionary = {}
var _pick_left: float = 0.0
## A car the player just left, waiting a tick for him to be put down outside (the door on that side).
var _exits: Array = []
## Cars whose door should swing the moment their rig is up (the player got in first), by id.
var _swing_later: Dictionary = {}
## Parked cars within near_range + this have their split and kit worked out ahead (m).
@export var prefetch: float = 12.0


static func ensure(from: Node) -> void:
	if not enabled:
		return
	if _inst != null and is_instance_valid(_inst):
		return
	var tree := from.get_tree()
	if tree == null:
		return
	_inst = CarInteriors.new()
	_inst.name = "CarInteriors"
	tree.root.add_child.call_deferred(_inst)


static func instance() -> CarInteriors:
	return _inst if _inst != null and is_instance_valid(_inst) and _inst.is_inside_tree() else null


static func supported(c: Vehicle) -> bool:
	return c != null and is_instance_valid(c) and c._has_model and CarDoorSplit.supported(c.body_type) \
			and not (c is Aircraft)


## The rig on `c`, or null.
static func rig_of(c: Vehicle) -> CarInterior:
	var inst := instance()
	if inst == null or c == null:
		return null
	var r: Variant = inst.rigs.get(c.get_instance_id())
	return r if r != null and is_instance_valid(r) else null


## Vehicle's driver setter: the player getting in (`who` him) or out (null).
static func driver_changed(c: Vehicle, who: Node3D) -> void:
	var inst := instance()
	if inst == null or not enabled or not supported(c) or not c.is_inside_tree():
		return
	if who != null:
		var rig := inst.activate(c)
		var side := inst._side_of(c, who.global_position)
		if rig != null:
			rig.swing(side)
		else:
			# Still being built (a worker thread): the door swings once it is.
			inst._swing_later[c.get_instance_id()] = side
	else:
		inst._exits.append(c)


## Vehicle.take_hit(): a hard enough crash or blast tears off the door on the side it came from.
static func on_hit(c: Vehicle, kind: int, damage: float, dir: Vector3, at: Vector3) -> void:
	var inst := instance()
	if inst == null or not enabled:
		return
	if OS.get_environment("CABIN_DEBUG") != "":
		print("CABIN hit %s kind %d damage %.2f v %s driver %s" % [c.name, kind, damage, c.linear_velocity, c.driver != null])
	var rig := rig_of(c)
	if rig == null:
		return
	var hard := (kind == Vehicle.HIT_CRASH and damage >= inst.detach_crash) or (kind == Vehicle.HIT_BLAST and damage >= inst.detach_blast)
	if not hard:
		return
	var side := inst._side_of(c, at)
	rig.detach(side, dir.normalized() * (3.0 + damage * 0.4))
	if kind == Vehicle.HIT_BLAST and damage >= inst.detach_blast * 2.0:
		rig.detach(-side, dir.normalized() * 3.0)


## Which door `world` is nearer: -1 the mesh's left, +1 its right.
func _side_of(c: Vehicle, world: Vector3) -> float:
	var lx := c.to_local(world).x
	return 1.0 if lx >= 0.0 else -1.0


## Puts `c`'s rig on now if its split is ready (null if not yet): the split is asked for either way.
func activate(c: Vehicle) -> CarInterior:
	var id := c.get_instance_id()
	var have: Variant = rigs.get(id)
	if have != null and is_instance_valid(have):
		return have
	var mesh := _near_mesh(c)
	if mesh == null:
		# The headless check keeps no mesh data: the cabin without the split.
		if not CarDoorSplit._done.has(c.body_type):
			CarDoorSplit._done[c.body_type] = {"real": false, "body": null, "doors": []}
	elif not CarDoorSplit.request(c.body_type, mesh):
		return null
	var split := CarDoorSplit.result(c.body_type)
	var kit := CarInteriorKit.request(c.body_type, CarCabin.for_car(c), CarInterior.doors_for(c, split))
	if kit.is_empty():
		return null
	var rig := CarInterior.make(c, split, kit)
	if rig != null:
		rigs[id] = rig
		var side: Variant = _swing_later.get(id)
		if side != null:
			_swing_later.erase(id)
			rig.swing(float(side))
	return rig


func deactivate(c: Vehicle) -> void:
	var id := c.get_instance_id()
	var rig: Variant = rigs.get(id)
	rigs.erase(id)
	if rig != null and is_instance_valid(rig):
		(rig as CarInterior).remove()


func _exit_tree() -> void:
	# Nothing of ours may still be running on a worker thread when the engine shuts down.
	CarDoorSplit.drain()
	CarInteriorKit.drain()


static func _near_mesh(c: Vehicle) -> Mesh:
	# The headless dummy renderer keeps no mesh data to split.
	if DisplayServer.get_name() == "headless":
		return null
	for m in c._body_meshes:
		if is_instance_valid(m) and m.mesh != null and not String(m.name).ends_with("_far"):
			return m.mesh
	return null


func _physics_process(delta: float) -> void:
	if not enabled:
		for id: int in rigs.keys():
			var r: Variant = rigs[id]
			if r != null and is_instance_valid(r):
				(r as CarInterior).remove()
		rigs.clear()
		return
	if CarDoorSplit.pending():
		CarDoorSplit.step(split_budget_usec)
	_pick_left -= delta
	if _pick_left <= 0.0:
		_pick_left = pick_interval
		_pick()
	# Untyped: a car freed since it was queued cannot be assigned to a typed variable.
	for c_any: Variant in _exits.duplicate():
		if not is_instance_valid(c_any):
			_exits.erase(c_any)
			continue
		var c := c_any as Vehicle
		var p := get_tree().get_first_node_in_group("player") as Node3D
		var rig := rig_of(c)
		if p != null and rig != null and c.driver == null:
			rig.swing(_side_of(c, p.global_position))
		_exits.erase(c)
	for id: int in rigs.keys():
		var rig: Variant = rigs[id]
		if rig == null or not is_instance_valid(rig) or not is_instance_valid((rig as CarInterior).car):
			rigs.erase(id)
			continue
		(rig as CarInterior).tick(delta)


func _pick() -> void:
	var p := get_tree().get_first_node_in_group("player") as Node3D
	if p == null:
		return
	var want := {}
	var driving: Vehicle = p.get("vehicle") if p.get("vehicle") is Vehicle else null
	if driving != null and is_instance_valid(driving) and supported(driving) and not driving.is_wreck():
		want[driving.get_instance_id()] = driving
	if driving == null:
		var near := []
		for n in get_tree().get_nodes_in_group("vehicle"):
			var c := n as Vehicle
			if c == null or not supported(c) or c.is_traffic() or c.driver != null or c.is_wreck() or c._abandoned():
				continue
			var dist := c.global_position.distance_to(p.global_position)
			var keep := rigs.has(c.get_instance_id())
			if dist < near_range + (hysteresis if keep else 0.0):
				near.append([dist, c])
			elif dist < near_range + prefetch:
				_prefetch(c)
		near.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
		for i in mini(near.size(), max_parked):
			var c: Vehicle = near[i][1]
			want[c.get_instance_id()] = c
	# Police cruisers whose crews stand behind their open doors (PoliceChase).
	for c: Vehicle in PoliceChase.open_door_cars():
		if supported(c):
			want[c.get_instance_id()] = c
	for id: int in rigs.keys():
		var rig: Variant = rigs[id]
		if rig == null or not is_instance_valid(rig):
			rigs.erase(id)
			continue
		var r := rig as CarInterior
		if want.has(id) or r.has_lost_door() or r.busy():
			continue
		if is_instance_valid(r.car):
			deactivate(r.car)
		else:
			rigs.erase(id)
	for id: int in want.keys():
		if not rigs.has(id):
			activate(want[id])
	for id: int in _swing_later.keys():
		if not want.has(id):
			_swing_later.erase(id)


## Starts the split and the kit for `c`'s body type before the player is close enough to need them.
func _prefetch(c: Vehicle) -> void:
	if CarDoorSplit.result(c.body_type).is_empty():
		var mesh := _near_mesh(c)
		if mesh != null:
			CarDoorSplit.request(c.body_type, mesh)
		return
	CarInteriorKit.request(c.body_type, CarCabin.for_car(c), CarInterior.doors_for(c, CarDoorSplit.result(c.body_type)))
