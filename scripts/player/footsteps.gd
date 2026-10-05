class_name Footsteps
extends Node
## The hero's footsteps, by what he is standing on: concrete pavement, the asphalt of a road, the
## grass of a park or a yard, the beach's sand, a wooden pier or boardwalk, the metal of a car roof
## or a train. A child of the Player (one line in Player._ready()).
##
## A step is a foot coming down in the animation, not a timer: each foot's height in the skeleton
## is watched, and a step sounds when it drops into the bottom of its own range. So the steps keep
## time with the walk, the run and the boosted sprint whatever speed the clip plays at. Without a
## rig (the capsule fallback) they fall back to a stride length.
##
## The surface is a ray straight down (world + props) every `surface_interval`, read by
## surface_at(): what was hit first (a car, a train, the freeway deck, the river's concrete), then
## the map and the plan at that point (the zone, the road or the pavement ring of the block, a
## park or a yard, the pier over the water). Pure, so the smoke test asks it directly.

## Level of a step at a walk and at a full run, dB.
@export var walk_db: float = -13.0
@export var run_db: float = -7.0
## Speeds (m/s) the level runs from and to.
@export var walk_speed: float = 2.0
@export var run_speed: float = 12.0
## Random pitch spread of each step.
@export var pitch_spread: float = 0.07
## How often the ground under him is looked at, seconds.
@export var surface_interval: float = 0.2
## A foot counts as down in the lowest share of its own swing.
@export var contact_share: float = 0.22
## Without a rig: metres per step at a walk and at a run.
@export var stride: Vector2 = Vector2(0.8, 2.1)

const SURFACES := ["concrete", "asphalt", "grass", "sand", "wood", "metal"]
const FEET := ["LeftFoot", "RightFoot"]
const DOWN_MASK := 1 | 4 # world + props: a car roof is a surface too

## The surface under him (one of SURFACES) and the steps taken since load (for the HUD and tests).
var surface: String = "concrete"
var steps: int = 0

var _player: CharacterBody3D
var _skel: Skeleton3D
var _feet: Array[int] = []
var _lo: Array[float] = [0.0, 0.0]
var _hi: Array[float] = [0.0, 0.0]
var _prev: Array[float] = [0.0, 0.0]
var _armed: Array[bool] = [true, true]
var _last_ms: Array[int] = [0, 0]
var _walked: float = 0.0
var _surface_left: float = 0.0
var _ray := PhysicsRayQueryParameters3D.new()


func _ready() -> void:
	_player = get_parent() as CharacterBody3D
	_ray.collision_mask = DOWN_MASK
	if _player:
		_ray.exclude = [_player.get_rid()]


func _find_rig() -> void:
	var avatar: Node = _player.get("avatar") if _player else null
	if avatar == null:
		return
	var found := avatar.find_children("*", "Skeleton3D", true, false)
	if found.is_empty():
		return
	_skel = found[0] as Skeleton3D
	_feet.clear()
	for b: String in FEET:
		_feet.append(_skel.find_bone(b))
	if _feet.has(-1):
		_skel = null


func _process(delta: float) -> void:
	if _player == null or not _player.is_inside_tree():
		return
	if _player.get("vehicle") != null or not _player.is_on_floor():
		_walked = 0.0
		return
	var v := _player.velocity
	var speed := Vector2(v.x, v.z).length()
	_surface_left -= delta
	if _surface_left <= 0.0:
		_surface_left = surface_interval
		_read_surface()
	if _skel == null or not is_instance_valid(_skel):
		_find_rig()
	if _skel != null:
		_feet_down(speed)
	else:
		# No rig: a step every stride.
		_walked += speed * delta
		var step_len := lerpf(stride.x, stride.y, clampf(speed / run_speed, 0.0, 1.0))
		if speed > 0.5 and _walked >= step_len:
			_walked = 0.0
			_step(speed)


func _feet_down(speed: float) -> void:
	var now := Time.get_ticks_msec()
	for k in 2:
		# In metres above the player's origin, whatever units the rig is authored in.
		var y := (_skel.global_transform * _skel.get_bone_global_pose(_feet[k]).origin).y - _player.global_position.y
		# Each foot's own range, easing back in so a change of gait re-learns it.
		_lo[k] = minf(lerpf(_lo[k], y, 0.02), y)
		_hi[k] = maxf(lerpf(_hi[k], y, 0.02), y)
		var swing := _hi[k] - _lo[k]
		var low := _lo[k] + swing * contact_share
		if y > _lo[k] + swing * 0.5:
			_armed[k] = true
		var falling := y < _prev[k]
		_prev[k] = y
		# Moving at all, the foot swinging (3 cm or more), coming down.
		if speed > 0.6 and swing > 0.03 and _armed[k] and falling and y <= low and now - _last_ms[k] > 140:
			_armed[k] = false
			_last_ms[k] = now
			_step(speed)


func _step(speed: float) -> void:
	steps += 1
	var k := clampf((speed - walk_speed) / maxf(run_speed - walk_speed, 0.1), 0.0, 1.0)
	var db := lerpf(walk_db, run_db, k)
	if surface == "grass" or surface == "sand":
		db -= 2.0 # soft ground is quieter underfoot
	Sfx.play("footstep_" + surface, _player.global_position, db, randf_range(1.0 - pitch_spread, 1.0 + pitch_spread))


func _read_surface() -> void:
	var space := _player.get_world_3d().direct_space_state
	_ray.from = _player.global_position + Vector3.UP * 0.4
	_ray.to = _player.global_position + Vector3.DOWN * 1.6
	var hit := space.intersect_ray(_ray)
	var collider: Object = hit.get("collider") if not hit.is_empty() else null
	# The city's streamer is the player's nearest ancestor with a plan (none in the test room).
	var streamer: Node = _player.get_parent()
	while streamer != null and not ("plan" in streamer):
		streamer = streamer.get_parent()
	var plan: CityPlan = streamer.get("plan") as CityPlan if streamer else null
	var w := WorldState.to_world(_player.global_position)
	surface = surface_at(plan, Vector2(w.x, w.z), w.y, collider)


## What a foot at true world (`xz`, `y`) lands on, given the body the ray hit (or null). One of
## SURFACES.
static func surface_at(plan: CityPlan, xz: Vector2, y: float, collider: Object) -> String:
	if collider != null:
		if collider is VehicleBody3D or collider is RigidBody3D:
			return "metal"
		if collider is Node and ((collider as Node).is_in_group("rail_vehicle") or (collider as Node).is_in_group("vehicle")):
			return "metal"
		if collider is Node:
			var n := String((collider as Node).name)
			if n.begins_with("Freeway") or n.begins_with("River") or n.begins_with("Rail"):
				return "concrete"
	if plan == null or plan.macro == null:
		return "concrete"
	var macro := plan.macro
	var ground := macro.height_at(xz)
	var above := y - maxf(ground, 0.0)
	match macro.zone_at(xz):
		MacroMap.Zone.OCEAN:
			return "wood" # anything you stand on over the sea is a pier
		MacroMap.Zone.BEACH:
			return "wood" if above > 0.7 and _near_pier(xz) else "sand"
		MacroMap.Zone.HILLS:
			return "grass" if above < 1.0 else "concrete"
		MacroMap.Zone.AIRPORT, MacroMap.Zone.PORT:
			return "concrete"
	# Up on a roof, a balcony or a bridge: concrete.
	if above > 2.5:
		return "concrete"
	var bi := plan.block_index_at(xz)
	var b := plan.block(bi.x, bi.y)
	var rect: Rect2 = b.rect
	if not rect.has_point(xz):
		return "asphalt"
	if not rect.grow(-plan.sidewalk_width).has_point(xz):
		return "concrete"
	var grounds := String(b.get("grounds", ""))
	if grounds != "":
		for f: Dictionary in Parks.plan_for(plan, bi.x, bi.y).get("fac", []):
			if String(f.t) == "diamond" and xz.distance_to(f.c) < float(f.fence):
				return "grass"
			if f.has("r") and (f.r as Rect2).has_point(xz):
				match String(f.t):
					"soccer", "diamond", "lawn", "field":
						return "grass"
					"basketball", "tennis", "track", "parking", "dropoff", "games":
						return "asphalt"
					_:
						return "concrete"
		return "grass"
	match int(b.kind):
		CityPlan.BlockKind.PARK:
			return "grass"
		CityPlan.BlockKind.PLAZA, CityPlan.BlockKind.MALL, CityPlan.BlockKind.BIGBOX:
			return "concrete"
	var district := int(b.district)
	if district == CityPlan.District.SUBURBS or district == CityPlan.District.BEACHTOWN:
		return "grass" # front and back yards; the drives are a minority
	return "concrete"


static func _near_pier(xz: Vector2) -> bool:
	for lm: Dictionary in Landmarks.all():
		var id := String(lm.id)
		if (id.ends_with("pier") or id.ends_with("boardwalk")) and xz.distance_to(lm.anchor) < float(lm.radius):
			return true
	return false
