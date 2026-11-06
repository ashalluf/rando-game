class_name GroundContact
extends RefCounted
## Everything that stands on the ground meets it (docs/HANDOFF.md "Ground contact"). ContactShadows
## (the gi-review pass) put a soft occlusion quad under cars, loose props and a handful of furniture
## batches; a tree, a lamp post, a signal pole, a bollard or a person still stood on the pavement as
## if pasted on, and on the Compatibility renderer (the web, every opengl3 still), which has no SSAO
## at all, nothing at the foot of anything said it touched the ground.
##
## This table extends ContactShadows' two sets, on the same quads and the same shader
## (shaders/contact_shadow.gdshader), so nothing new is drawn:
##  - STATIC: a quad under every instance of the batches in FEET (MultiMeshBatch.build() ->
##    ContactShadows.batch_contacts(), one "BatchContact" MultiMesh a FULL chunk, as before): trunks
##    (street trees, palms, the LA trees), poles (every street lamp type, utility poles, sign and
##    shelter posts, pylons), bollards, bins, racks, planters, vendors' carts, scooters. A trunk or
##    a pole gets a ROUND footprint of its own diameter (the mesh box of a cobra lamp is its arm,
##    of a tree its crown) at the instance's origin, times its scale. Poles and hydrants also get
##    GRIME: the ragged dirty band dogs, mops and the rain leave round a street fixture's foot.
##  - DYNAMIC: a soft blob under each near person (group "pedestrian", "police", "responder" and the
##    player on foot), at most `people_budget` within `people_reach` of the camera, laid on the
##    ground a ray found at pick time (kept as the offset from the person's origin, so it follows
##    a walk up a slope), fading and spreading as the player leaves the ground.
## GROUND_CONTACT=0 is the A/B (ContactShadows' own set as it was).

static var enabled: bool = OS.get_environment("GROUND_CONTACT") != "0"

## A batch key (exact) -> [diameter (m, 0 = the mesh box's footprint), margin (m), strength, grime].
const FEET := {
	"bollard": [0.24, 0.24, 0.8, 0.5],
	"upole": [0.32, 0.3, 0.75, 0.75],
	"sg_post": [0.07, 0.16, 0.4, 0.45],
	"sign_post": [0.08, 0.16, 0.4, 0.45],
	"shelter_post": [0.1, 0.2, 0.45, 0.3],
	"pylon_pole": [0.4, 0.3, 0.5, 0.5],
	"street_sign": [0.08, 0.16, 0.4, 0.45],
	"vend_fruit": [0.0, 0.25, 0.7, 0.0],
	"vend_paleta": [0.0, 0.22, 0.7, 0.0],
	"vend_hotdog": [0.0, 0.25, 0.7, 0.0],
	"vend_elote": [0.0, 0.25, 0.7, 0.0],
	"mm_locked_road": [0.0, 0.14, 0.45, 0.0],
	"mm_locked_cruiser": [0.0, 0.14, 0.45, 0.0],
	"mm_rack": [0.0, 0.16, 0.45, 0.2],
	"sc2_cart": [0.0, 0.18, 0.6, 0.0],
	"sc2_bags_0": [0.0, 0.16, 0.6, 0.0],
	"sc2_bags_1": [0.0, 0.16, 0.6, 0.0],
	"sc2_bags_2": [0.0, 0.16, 0.6, 0.0],
	"valet_podium_0": [0.0, 0.2, 0.6, 0.0],
	"valet_podium_1": [0.0, 0.2, 0.6, 0.0],
	"pay_station": [0.0, 0.2, 0.7, 0.4],
	"sig_cabinet": [0.0, 0.22, 0.7, 0.6],
	"barrier": [0.0, 0.22, 0.6, 0.0],
	"barrier_tall": [0.0, 0.22, 0.6, 0.0],
	"sc_board": [0.0, 0.14, 0.5, 0.0],
	"sc_magrack": [0.0, 0.16, 0.65, 0.2],
	"busk_amp": [0.0, 0.14, 0.6, 0.0],
	"busk_case": [0.0, 0.12, 0.5, 0.0],
	"valet_base": [0.0, 0.2, 0.6, 0.0],
	"by_grill_gas": [0.0, 0.2, 0.6, 0.0],
	"by_grill_kettle": [0.0, 0.2, 0.6, 0.0],
	"by_doghouse": [0.0, 0.22, 0.75, 0.0],
	"by_loungers": [0.0, 0.2, 0.55, 0.0],
	"by_trampoline": [0.0, 0.5, 0.45, 0.0],
	"ad_bench": [0.0, 0.25, 0.75, 0.0],
}
## A batch key's prefix -> the same row. Trunks are measured at the instance's scale: a 0.5x
## street tree has a 0.5x trunk.
const FEET_PREFIX := {
	"lamp_": [0.34, 0.32, 0.8, 0.7],
	"tree_": [0.42, 0.6, 0.75, 0.0],
	"palm_": [0.44, 0.5, 0.75, 0.0],
	"la_": [0.5, 0.55, 0.7, 0.0],
	"sig_pole": [0.36, 0.32, 0.8, 0.7],
	"ss_": [0.08, 0.16, 0.4, 0.45],
}
## Never these, whatever their prefix: lit quads, decals and the grate a tree stands in.
const NOT := ["pool", "spill", "glow", "halo", "grate", "atmos", "shaft", "head", "arm", "far", "shadow"]
## Grime added to ContactShadows' own furniture keys (by key).
const GRIME := {"hydrant": 0.9, "hydrant_aged": 1.0, "meter": 0.5, "mailbox": 0.4, "sc_newsbox": 0.35}

## A person's blob: across, along (m), margin, strength.
const PERSON := Vector4(0.38, 0.26, 0.36, 0.9)
static var people_budget: int = 32
static var people_reach: float = 32.0
## Off the ground (m) at which the player's blob is gone; it spreads by this share a metre up.
const AIR_FADE := 3.0
const AIR_SPREAD := 0.35


## [diameter, margin, strength, grime] for a batch key, or [] for none. `base` is ContactShadows'
## own row for its keys (strength) or -1.
static func spec(key: String) -> Array:
	if not enabled:
		return []
	for n: String in NOT:
		if key.contains(n):
			return []
	if FEET.has(key):
		return FEET[key]
	for p: String in FEET_PREFIX:
		if key.begins_with(p):
			return FEET_PREFIX[p]
	return []


static func grime(key: String) -> float:
	return float(GRIME.get(key, 0.0)) if enabled else 0.0


## Is this node a person standing where a blob belongs? (On foot, drawn, not in a car.)
static func is_person(n: Node3D) -> bool:
	if n == null or not n.is_inside_tree() or not n.is_visible_in_tree():
		return false
	if n.is_in_group("player"):
		return n.get("vehicle") == null
	return true


## The people near `eye`, nearest first: [d2, node] pairs.
static func people_near(tree: SceneTree, eye: Vector3) -> Array:
	var out: Array = []
	if not enabled:
		return out
	var r2 := people_reach * people_reach
	var seen := {}
	for g: String in ["player", "pedestrian", "police", "responder"]:
		for c in tree.get_nodes_in_group(g):
			var p := c as Node3D
			if p == null or seen.has(p.get_instance_id()) or not is_person(p):
				continue
			seen[p.get_instance_id()] = true
			var d2 := eye.distance_squared_to(p.global_position)
			if d2 < r2:
				out.append([d2, p])
	out.sort_custom(func(a, b): return a[0] < b[0])
	if out.size() > people_budget:
		out.resize(people_budget)
	return out


## How far the ground lies under a person's origin (m, >= 0), NAN for none within 6 m: one
## world-layer ray, the person's own body excluded.
static func ground_drop(space: PhysicsDirectSpaceState3D, p: Node3D) -> float:
	var at := p.global_position
	var q := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 0.4, at + Vector3.DOWN * 6.0, 1)
	if p is CollisionObject3D:
		q.exclude = [(p as CollisionObject3D).get_rid()]
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return NAN
	return maxf(at.y - (hit.position as Vector3).y, 0.0)


## A bare dirt well was cut WELL_DIRT_DEPTH under the pavement round a street tree (Kerbs): the
## trunk standing at `c` (true world xz, within 25 cm) goes down onto the dirt with it, or it stood
## over the well on nothing. Moves the instance in the chunk's batch before it is built.
static func sink_trunk(data: Dictionary, c: Vector2, depth: float) -> void:
	if not enabled:
		return
	for key: String in data:
		if not (key.begins_with("tree_") or key.begins_with("palm_") or key.begins_with("la_")) or key == "tree_grate":
			continue
		var xfs: Array = data[key].xforms
		for i in xfs.size():
			var x: Transform3D = xfs[i]
			if Vector2(x.origin.x, x.origin.z).distance_squared_to(c) < 0.0625:
				x.origin.y -= depth
				xfs[i] = x
