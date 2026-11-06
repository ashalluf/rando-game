class_name Sanctuary
extends RefCounted
## Places the guns will not fire at (owner, 2026-09-24, of the masjid: "make it impossible for
## the character to shoot anything at it completely, just deactivate the shooting at it").
##
## A sanctuary is a box - a Node3D in ZONE_GROUP carrying the box's half size in meta "extents",
## in the node's own frame, so it can be turned with the building - plus, where the building has
## collision, a StaticBody3D in BODY_GROUP. The check runs in Weapon.tick(), the one place every
## gun fires through, so there is nothing per weapon to forget:
##
##   - the crosshair is on the building (the aim ray's collider belongs to a sanctuary body);
##   - the shot would pass through the zone on its way to what the crosshair is on (the zone
##     covers the fenced grounds, so shooting across them at a car beyond is blocked too);
##   - an explosive would land close enough for its blast to reach the zone (`splash`);
##   - the player is standing inside the zone - on the grounds or in the building.
##
## The zone is added by the far build as well as the detailed one. The far copy has no collision,
## so without the zone a shot from across the city would pass straight through the building and
## hit whatever stood behind it. Rockets already in flight when the building gets in the way
## fizzle rather than explode (Rocket._physics_process), and nothing leaves a bullet hole or a
## scorch mark on it (WeaponFX.bullet_hole, Explosion.blast), which covers the police's guns too.

const ZONE_GROUP := "sanctuary_zone"
const BODY_GROUP := "sanctuary"


## Adds a zone under `parent`: a box of half size `extents` centred on `center`, turned `yaw`
## about Y. Returns the node, which carries the box and nothing else.
static func add_zone(parent: Node3D, center: Vector3, extents: Vector3, yaw: float = 0.0) -> Node3D:
	var zone := Node3D.new()
	zone.name = "SanctuaryZone"
	zone.position = center
	zone.rotation.y = yaw
	zone.set_meta("extents", extents)
	zone.add_to_group(ZONE_GROUP)
	parent.add_child(zone)
	return zone


## Whether `collider` is, or belongs to, a sanctuary's body.
static func is_sanctuary(collider: Object) -> bool:
	var node := collider as Node
	while node != null:
		if node.is_in_group(BODY_GROUP):
			return true
		node = node.get_parent()
	return false


## Whether the world point `p` is inside any zone grown by `margin` metres.
static func contains(tree: SceneTree, p: Vector3, margin: float = 0.0) -> bool:
	for zone in tree.get_nodes_in_group(ZONE_GROUP):
		var z := zone as Node3D
		if z == null or not z.is_inside_tree():
			continue
		var e: Vector3 = z.get_meta("extents", Vector3.ZERO) + Vector3.ONE * margin
		var q := z.global_transform.affine_inverse() * p
		if absf(q.x) <= e.x and absf(q.y) <= e.y and absf(q.z) <= e.z:
			return true
	return false


## Whether the segment a -> b passes through any zone grown by `margin` metres (the slab test in
## each zone's own frame).
static func segment_hits(tree: SceneTree, a: Vector3, b: Vector3, margin: float = 0.0) -> bool:
	for zone in tree.get_nodes_in_group(ZONE_GROUP):
		var z := zone as Node3D
		if z == null or not z.is_inside_tree():
			continue
		var e: Vector3 = z.get_meta("extents", Vector3.ZERO) + Vector3.ONE * margin
		var inv := z.global_transform.affine_inverse()
		var p := inv * a
		var d := inv * b - p
		var t0 := 0.0
		var t1 := 1.0
		var hit := true
		for i in 3:
			if absf(d[i]) < 1e-9:
				if absf(p[i]) > e[i]:
					hit = false
					break
				continue
			var ta := (-e[i] - p[i]) / d[i]
			var tb := (e[i] - p[i]) / d[i]
			t0 = maxf(t0, minf(ta, tb))
			t1 = minf(t1, maxf(ta, tb))
			if t0 > t1:
				hit = false
				break
		if hit:
			return true
	return false


## The whole rule, for Weapon.tick(): true means this shot must not be fired. `splash` is the
## weapon's blast radius (0 for bullets), so an explosive cannot be landed beside the building
## either.
static func blocks_fire(player: Node3D, aim: Dictionary, splash: float = 0.0) -> bool:
	var tree := player.get_tree()
	if tree.get_node_count_in_group(ZONE_GROUP) == 0 and not is_sanctuary(aim.get("collider")):
		return false
	if is_sanctuary(aim.get("collider")):
		return true
	if contains(tree, player.global_position):
		return true
	var origin: Vector3 = aim.get("origin", player.global_position)
	var point: Vector3 = aim.get("point", origin)
	# The path itself at the zone's own size, the blast only where the shot lands: growing the
	# whole path by the blast radius would refuse every rocket fired from the pavement outside,
	# whichever way it was aimed.
	return segment_hits(tree, origin, point) or (splash > 0.0 and contains(tree, point, splash))
