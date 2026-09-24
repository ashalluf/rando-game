class_name ReplicaWalker
extends Pedestrian
## A pedestrian on a replica area's own pavements (ReplicaAreas): it strolls along the ocean-side
## walkway or the inland pavement, a few tens of metres at a time, instead of round a block's
## ring - the Esplanade's pavements follow the route, not a rectangle. Everything else (the look,
## the gait, panic, being shot or knocked down) is Pedestrian's.

var rep: ReplicaAreas
## The stretch of path distance it keeps to (its chunk's), and which pavement: -1 the ocean-side
## walkway, +1 the inland pavement.
var s_lo: float = 0.0
var s_hi: float = 0.0
var side: float = -1.0

## How far along the pavement one stroll goes, at most.
const STROLL := 40.0


func _random_ring_point(_sidewalk: float) -> Vector2:
	var here := WorldState.to_world(global_position) if is_inside_tree() else Vector3.INF
	var hit := rep.nearest(Vector2(here.x, here.z), 60.0) if here != Vector3.INF else {}
	var s0: float = float(hit.s) if not hit.is_empty() else (s_lo + s_hi) * 0.5
	var s := clampf(s0 + _rng.randf_range(-STROLL, STROLL), s_lo, s_hi)
	var at := rep.at_s(s)
	var sd: Dictionary = at[3]
	var a: float = (float(sd.walk_w_edge) + 0.6) if side < 0.0 else (float(sd.kerb_e) + 0.9)
	var b: float = (float(sd.kerb_w) - 0.9) if side < 0.0 else (float(sd.walk_e_edge) - 0.6)
	var o := _rng.randf_range(minf(a, b), maxf(a, b))
	return (at[0] as Vector2) + ReplicaAreas.left_of(at[1]) * o
