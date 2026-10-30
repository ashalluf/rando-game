class_name SkaterPerson
extends RoughSleeper
## Somebody at THE PIT (SkatePark): a skater or a spectator, posed once and baked
## (SkateParkLife.figure()) the way the camps' and the beach's figures are, or - shot, knocked or
## near gunfire - the live person they turn into, who runs off like anyone (RoughSleeper's FLEE
## and RETURN), bleeds and ragdolls. Unlike a RoughSleeper they wear the crowd look as it is
## (street clothes, not worn down), and they stand on the park's concrete, not the sand.

## Poses in RoughSleeper.POSES' format (solved per rig from the idle, the body's front +Z in rig
## space), the board under the feet along the rig's x: riding, crouched (pumping, landing), in the
## air (knees tucked, arms out), grinding (low, arms wide); a spectator standing with folded arms,
## and one sitting on an edge with the legs hanging over it.
const POSES_SKATE := {
	"ride": {
		"hips_pitch": 8.0, "stand": true,
		"aim": {
			"Spine02": Vector3(0.0, 0.95, 0.3), "Spine01": Vector3(0.0, 0.97, 0.24),
			"Spine": Vector3(0.0, 0.98, 0.18), "neck": Vector3(0.22, 0.95, 0.2),
			"Head": Vector3(0.5, 0.82, 0.25),
			"LeftUpLeg": Vector3(0.32, -0.9, 0.28), "LeftLeg": Vector3(0.2, -0.96, -0.12),
			"RightUpLeg": Vector3(-0.32, -0.9, 0.28), "RightLeg": Vector3(-0.2, -0.96, -0.12),
			"LeftArm": Vector3(0.62, -0.72, 0.3), "LeftForeArm": Vector3(0.6, -0.62, 0.5),
			"RightArm": Vector3(-0.5, -0.8, 0.32), "RightForeArm": Vector3(-0.3, -0.72, 0.62),
		},
		"keep": ["LeftFoot", "RightFoot"],
	},
	"crouch": {
		"hips_pitch": 16.0, "stand": true,
		"aim": {
			"Spine02": Vector3(0.0, 0.84, 0.54), "Spine01": Vector3(0.0, 0.88, 0.47),
			"Spine": Vector3(0.0, 0.9, 0.42), "neck": Vector3(0.25, 0.9, 0.36),
			"Head": Vector3(0.55, 0.75, 0.38),
			"LeftUpLeg": Vector3(0.38, -0.62, 0.68), "LeftLeg": Vector3(0.22, -0.92, -0.32),
			"RightUpLeg": Vector3(-0.38, -0.62, 0.68), "RightLeg": Vector3(-0.22, -0.92, -0.32),
			"LeftArm": Vector3(0.8, -0.5, 0.33), "LeftForeArm": Vector3(0.72, -0.3, 0.62),
			"RightArm": Vector3(-0.72, -0.6, 0.35), "RightForeArm": Vector3(-0.45, -0.4, 0.8),
		},
		"keep": ["LeftFoot", "RightFoot"],
	},
	"air": {
		"hips_pitch": 12.0, "stand": true,
		"aim": {
			"Spine02": Vector3(0.0, 0.86, 0.5), "Spine01": Vector3(0.0, 0.9, 0.44),
			"Spine": Vector3(0.0, 0.92, 0.38), "neck": Vector3(0.3, 0.88, 0.3),
			"Head": Vector3(0.62, 0.7, 0.32),
			"LeftUpLeg": Vector3(0.3, -0.25, 0.92), "LeftLeg": Vector3(0.18, -0.95, -0.25),
			"RightUpLeg": Vector3(-0.3, -0.25, 0.92), "RightLeg": Vector3(-0.18, -0.95, -0.25),
			"LeftArm": Vector3(0.9, 0.12, 0.42), "LeftForeArm": Vector3(0.82, 0.38, 0.42),
			"RightArm": Vector3(-0.88, 0.2, 0.42), "RightForeArm": Vector3(-0.8, 0.45, 0.4),
		},
		"keep": ["LeftFoot", "RightFoot"],
	},
	"grind": {
		"hips_pitch": 14.0, "stand": true,
		"aim": {
			"Spine02": Vector3(0.0, 0.88, 0.47), "Spine01": Vector3(0.0, 0.9, 0.42),
			"Spine": Vector3(0.0, 0.92, 0.37), "neck": Vector3(0.35, 0.88, 0.3),
			"Head": Vector3(0.68, 0.66, 0.3),
			"LeftUpLeg": Vector3(0.36, -0.7, 0.6), "LeftLeg": Vector3(0.2, -0.94, -0.28),
			"RightUpLeg": Vector3(-0.36, -0.7, 0.6), "RightLeg": Vector3(-0.2, -0.94, -0.28),
			"LeftArm": Vector3(0.97, -0.1, 0.18), "LeftForeArm": Vector3(0.95, 0.12, 0.25),
			"RightArm": Vector3(-0.96, 0.02, 0.2), "RightForeArm": Vector3(-0.92, 0.25, 0.3),
		},
		"keep": ["LeftFoot", "RightFoot"],
	},
	"watch": {"aim": {}, "keep": []},
	"fold": {
		"aim": {
			"LeftArm": Vector3(0.2, -0.62, 0.55), "LeftForeArm": Vector3(-0.88, 0.12, 0.36),
			"RightArm": Vector3(-0.2, -0.6, 0.58), "RightForeArm": Vector3(0.88, 0.2, 0.32),
		},
		"keep": [],
	},
	# On a wall's edge (the figure's origin on the seat), thighs out over the drop, shins hanging,
	# hands on the edge beside the hips.
	"sit_edge": {
		"hips_y": 9.0,
		"aim": {
			"Spine02": Vector3(0.0, 0.97, 0.12), "Spine01": Vector3(0.0, 0.98, 0.1),
			"Spine": Vector3(0.0, 0.99, 0.06), "neck": Vector3(0.0, 0.97, 0.2), "Head": Vector3(0.0, 0.92, 0.38),
			"LeftUpLeg": Vector3(0.12, -0.05, 1.0), "LeftLeg": Vector3(0.04, -1.0, 0.12),
			"LeftFoot": Vector3(0.05, -0.2, 1.0),
			"LeftArm": Vector3(0.32, -0.92, -0.05), "LeftForeArm": Vector3(0.12, -0.95, 0.25),
		},
		"keep": [],
	},
}

## Which of POSES_SKATE they hold ("" the idle's own, for the live person).
var skate_pose: String = ""
## The park's origin in the parent's space, for the ground under them while they run.
var park_origin := Vector3.INF


func _init() -> void:
	# A bare head: the figures are baked without hats, and the live person must match.
	accessory_chance = 0.0


func _ready() -> void:
	super._ready()
	if _down:
		return
	# The crowd look as it is (RoughSleeper wears it down).
	for mi in _meshes:
		if not is_instance_valid(mi) or mi.mesh == null or Pedestrian.is_hair(mi):
			continue
		var src := mi.mesh.surface_get_material(0) as StandardMaterial3D
		if src and src.albedo_texture:
			mi.material_override = Pedestrian.character_material(src.albedo_texture, _look)
	Pedestrian.plain_hair(_visual)
	if skate_pose != "" and POSES_SKATE.has(skate_pose) and _skel != null and not _base_rot.is_empty():
		var p := _solve(POSES_SKATE[skate_pose])
		_posed_rot = p[0]
		_posed_hips = p[1]
		_apply(1.0)


## On the park's concrete inside its pad, the sand outside it.
func _ground_y(x: float, z: float, fallback: float) -> float:
	if park_origin != Vector3.INF:
		var lp := Vector2(x - park_origin.x, z - park_origin.z)
		if absf(lp.x) <= SkatePark.HALF_W and absf(lp.y) <= SkatePark.HALF_L:
			return park_origin.y + SkatePark.surface_y(lp)
	return BeachLife.ground_at(get_parent(), x, z, fallback)


func _pose_ground() -> float:
	return _ground_y(_home.x, _home.y, position.y) + lift


## Open ground: straight there, no ring corners.
func _ring_route(_from: Vector2, _to: Vector2) -> PackedVector2Array:
	return PackedVector2Array()


func _random_ring_point(_sidewalk: float) -> Vector2:
	return Vector2(_rng.randf_range(ring.position.x, ring.end.x), _rng.randf_range(ring.position.y, ring.end.y))


## Away from the threat, and inland (+x) rather than toward the sea.
func _flee_point() -> Vector2:
	var best := _random_ring_point(_sidewalk)
	for i in 6:
		var p := _random_ring_point(_sidewalk)
		if p.distance_squared_to(_threat) + p.x * 4.0 > best.distance_squared_to(_threat) + best.x * 4.0:
			best = p
	return best
